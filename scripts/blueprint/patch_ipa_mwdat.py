#!/usr/bin/env python3
"""Patch and validate MWDAT keys in Payload/OpenVision.app/Info.plist before IPA packaging.

Supports Meta Wearables Device Access Toolkit (DAT 1.0.1) in two explicit modes:
  - developer  (default): MetaAppID = "0", ClientToken = "", custom AppLinkURLScheme = "<scheme>://",
                          optional 10-char Apple Team ID (or empty/omitted via --omit-empty-team-id).
  - production:           Numeric MetaAppID (> 0), MWDAT_CLIENT_TOKEN = "AR|<MetaAppID>|<token>",
                          10-char Apple Team ID in MWDAT_TEAM_ID, and https:// Universal Link
                          (or custom scheme with warning).

Sensitive values (MWDAT_CLIENT_TOKEN, MWDAT_TEAM_ID) are read ONLY from environment variables and
are NEVER printed to stdout or stderr. Output plist is always written in binary format (FMT_BINARY).
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*$")
TEAM_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
DIGITS_RE = re.compile(r"^[0-9]+$")
BUNDLE_ID_RE = re.compile(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$")


def has_placeholder(value: str) -> bool:
    lower = value.lower()
    return (
        "your_" in lower
        or "$(" in value
        or "${" in value
        or "xxxxxxxxxx" in lower
    )


def has_whitespace(value: str) -> bool:
    return any(ch.isspace() for ch in value)


def parse_bool(raw: str) -> bool:
    normalized = raw.strip().lower()
    if normalized in ("1", "true", "yes", "on"):
        return True
    if normalized in ("0", "false", "no", "off", ""):
        return False
    raise argparse.ArgumentTypeError(f"Expected boolean (true/false), got: {raw!r}")


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def ensure_primary_url_type(plist: dict) -> dict:
    url_types = plist.get("CFBundleURLTypes")
    if not isinstance(url_types, list) or not url_types or not isinstance(url_types[0], dict):
        primary: dict = {
            "CFBundleTypeRole": "Editor",
            "CFBundleURLName": str(plist.get("CFBundleIdentifier", "")),
            "CFBundleURLSchemes": [],
        }
        plist["CFBundleURLTypes"] = [primary]
        return primary
    return url_types[0]


def validate_https_universal_link(url: str) -> bool:
    if has_placeholder(url) or has_whitespace(url):
        return False
    parsed = urlparse(url)
    return parsed.scheme == "https" and bool(parsed.netloc)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Patch and validate MWDAT keys in an OpenVision Info.plist before zipping an IPA."
    )
    parser.add_argument(
        "--plist",
        default="Payload/OpenVision.app/Info.plist",
        help="Path to Info.plist (XML or binary). Output is written as FMT_BINARY.",
    )
    parser.add_argument(
        "--mode",
        default="developer",
        choices=("developer", "production"),
        help="Target MWDAT mode: 'developer' (default) or 'production'.",
    )
    parser.add_argument(
        "--meta-app-id",
        default=None,
        help="Meta App ID (empty/'0' in developer mode; positive digits in production mode).",
    )
    parser.add_argument(
        "--bundle-id",
        default="",
        help="Optional CFBundleIdentifier override (also updates CFBundleURLTypes[0].CFBundleURLName).",
    )
    parser.add_argument(
        "--url-scheme",
        default="openvision",
        help="Custom URL scheme in developer mode (default: openvision), or https:// Universal Link in production.",
    )
    parser.add_argument(
        "--omit-empty-team-id",
        nargs="?",
        const="true",
        default="false",
        type=parse_bool,
        help="In developer mode, remove MWDAT.TeamID instead of writing '' when MWDAT_TEAM_ID is empty.",
    )
    args = parser.parse_args(argv)

    plist_path = Path(args.plist)
    if not plist_path.is_file():
        fail(f"Info.plist not found at: {plist_path}")

    try:
        plist = plistlib.loads(plist_path.read_bytes())
    except Exception as exc:
        fail(f"Failed to parse Info.plist at {plist_path}: {exc}")

    if not isinstance(plist, dict):
        fail("Info.plist root must be a dictionary")

    mode = args.mode
    raw_meta_app_id = args.meta_app_id
    if raw_meta_app_id is None:
        raw_meta_app_id = os.environ.get("MWDAT_META_APP_ID", "")
    raw_meta_app_id = raw_meta_app_id.strip()

    # 1. Validate MetaAppID
    if raw_meta_app_id and (has_placeholder(raw_meta_app_id) or has_whitespace(raw_meta_app_id)):
        fail(f"Invalid --meta-app-id: placeholder or whitespace is not allowed (got {raw_meta_app_id!r})")

    if mode == "developer":
        if raw_meta_app_id == "":
            meta_app_id = "0"
        elif raw_meta_app_id == "0":
            meta_app_id = "0"
        else:
            fail(
                "Developer mode requires --meta-app-id to be empty or '0' "
                f"(got {raw_meta_app_id!r}; use --mode production for a numeric Meta App ID)"
            )
    else:
        if not raw_meta_app_id or not DIGITS_RE.fullmatch(raw_meta_app_id) or int(raw_meta_app_id) == 0:
            fail(
                "Production mode requires --meta-app-id to be a non-zero ASCII integer "
                f"(got {raw_meta_app_id!r})"
            )
        meta_app_id = raw_meta_app_id

    # 2. Validate / override CFBundleIdentifier
    primary_url_type = ensure_primary_url_type(plist)
    bundle_id_override = args.bundle_id.strip()
    if bundle_id_override:
        if (
            has_placeholder(bundle_id_override)
            or has_whitespace(bundle_id_override)
            or not BUNDLE_ID_RE.fullmatch(bundle_id_override)
        ):
            fail(f"Invalid --bundle-id: {bundle_id_override!r}")
        plist["CFBundleIdentifier"] = bundle_id_override
        primary_url_type["CFBundleURLName"] = bundle_id_override
        final_bundle_id = bundle_id_override
    else:
        existing_bundle_id = str(plist.get("CFBundleIdentifier", "")).strip()
        if (
            not existing_bundle_id
            or has_placeholder(existing_bundle_id)
            or has_whitespace(existing_bundle_id)
        ):
            fail(f"Existing CFBundleIdentifier in Info.plist is missing or invalid: {existing_bundle_id!r}")
        final_bundle_id = existing_bundle_id
        existing_url_name = str(primary_url_type.get("CFBundleURLName", "")).strip()
        if not existing_url_name or has_placeholder(existing_url_name):
            primary_url_type["CFBundleURLName"] = final_bundle_id

    # 3. Validate URL scheme / AppLinkURLScheme
    raw_url_scheme = (args.url_scheme or "openvision").strip()
    if not raw_url_scheme or has_placeholder(raw_url_scheme) or has_whitespace(raw_url_scheme):
        fail(f"Invalid --url-scheme: {raw_url_scheme!r}")

    if mode == "developer":
        scheme = raw_url_scheme[:-3] if raw_url_scheme.endswith("://") else raw_url_scheme
        if not SCHEME_RE.fullmatch(scheme) or scheme.lower() in ("http", "https"):
            fail(
                "Developer mode requires a valid custom RFC 3986 URL scheme (e.g. 'openvision'), "
                f"got {raw_url_scheme!r}"
            )
        primary_url_type["CFBundleURLSchemes"] = [scheme]
        app_link_url_scheme = f"{scheme}://"
    else:
        if raw_url_scheme.lower().startswith("https://"):
            if not validate_https_universal_link(raw_url_scheme):
                fail(f"Invalid https:// Universal Link for --url-scheme: {raw_url_scheme!r}")
            app_link_url_scheme = raw_url_scheme
            existing_schemes = primary_url_type.get("CFBundleURLSchemes")
            valid_existing = (
                isinstance(existing_schemes, list)
                and len(existing_schemes) > 0
                and all(
                    isinstance(s, str)
                    and not has_placeholder(s)
                    and not has_whitespace(s)
                    and SCHEME_RE.fullmatch(s) is not None
                    for s in existing_schemes
                )
            )
            if not valid_existing:
                primary_url_type["CFBundleURLSchemes"] = ["openvision"]
        elif raw_url_scheme.lower().startswith("http://"):
            fail("Production mode forbids insecure http:// AppLinkURLScheme; use https:// Universal Link")
        else:
            scheme = raw_url_scheme[:-3] if raw_url_scheme.endswith("://") else raw_url_scheme
            if not SCHEME_RE.fullmatch(scheme):
                fail(
                    "Production mode --url-scheme must be an https:// Universal Link or valid custom scheme, "
                    f"got {raw_url_scheme!r}"
                )
            print(
                "::warning::Production mode normally requires an https:// Universal Link for "
                f"MWDAT.AppLinkURLScheme (using custom scheme '{scheme}://')",
                file=sys.stderr,
            )
            primary_url_type["CFBundleURLSchemes"] = [scheme]
            app_link_url_scheme = f"{scheme}://"

    # 4. Validate MWDAT_TEAM_ID from environment (NEVER print raw value)
    raw_team_id = os.environ.get("MWDAT_TEAM_ID", "").strip()
    team_id_status: str
    mwdat = plist.get("MWDAT")
    if not isinstance(mwdat, dict):
        mwdat = {}
        plist["MWDAT"] = mwdat

    if raw_team_id:
        if has_placeholder(raw_team_id) or not TEAM_ID_RE.fullmatch(raw_team_id):
            fail(
                "MWDAT_TEAM_ID must be a 10-character uppercase alphanumeric Apple Team ID "
                "(e.g. AB12CD34EF) with no placeholders"
            )
        mwdat["TeamID"] = raw_team_id
        team_id_status = "<set>"
    else:
        if mode == "production":
            fail("Production mode requires a valid 10-character Apple Team ID in MWDAT_TEAM_ID")
        if args.omit_empty_team_id:
            mwdat.pop("TeamID", None)
            team_id_status = "<omitted>"
        else:
            mwdat["TeamID"] = ""
            team_id_status = "<empty>"

    # 5. Validate MWDAT_CLIENT_TOKEN from environment (NEVER print raw value)
    raw_client_token = os.environ.get("MWDAT_CLIENT_TOKEN", "").strip()
    if mode == "developer":
        # Never leak a production ClientToken into a Developer Mode IPA.
        mwdat["ClientToken"] = ""
        client_token_status = "<empty>"
    else:
        if not raw_client_token:
            fail("Production mode requires MWDAT_CLIENT_TOKEN in format AR|<MetaAppID>|<token>")
        if has_placeholder(raw_client_token) or has_whitespace(raw_client_token):
            fail("MWDAT_CLIENT_TOKEN contains a placeholder or whitespace")
        token_pattern = re.compile(rf"^AR\|{re.escape(meta_app_id)}\|\S+$")
        if not token_pattern.fullmatch(raw_client_token):
            fail("MWDAT_CLIENT_TOKEN does not match required format AR|<MetaAppID>|<token>")
        mwdat["ClientToken"] = raw_client_token
        client_token_status = "<redacted>"

    mwdat["MetaAppID"] = meta_app_id
    mwdat["AppLinkURLScheme"] = app_link_url_scheme

    plist_path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_BINARY))

    schemes_out = primary_url_type.get("CFBundleURLSchemes", [])
    print(
        f"Patched {plist_path} (FMT_BINARY): "
        f"mode={mode}, MetaAppID={meta_app_id}, ClientToken={client_token_status}, "
        f"TeamID={team_id_status}, AppLinkURLScheme={app_link_url_scheme}, "
        f"CFBundleURLSchemes={schemes_out}, CFBundleIdentifier={final_bundle_id}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
