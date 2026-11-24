#!/usr/bin/env bash
# IPA symbol check: the shipped IPA must contain the code paths the
# workflow depends on. Looks in the Mach-O symbol table, Swift reflection metadata and string
# literals, so it works on an unstripped Release build.
#
# Usage: scripts/blueprint/verify_ipa_symbols.sh path/to/OpenVision.ipa
set -euo pipefail

IPA="${1:?usage: $0 path/to/OpenVision.ipa}"
REQUIRED=(
  RecentPhotoScanner      # lesson 6: temple-shutter photos from Camera Roll
  cleanSpokenAudio        # lesson 5: LaTeX-free speech
  conversationHistory     # lesson 7: follow-up context
  PhotoPayload            # full-resolution glasses photos
  streamGenerateContent   # streamed answers (no idle timeouts)
  SolverIntent            # free-form routing / stop words
)

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unzip -q "$IPA" -d "$work"
binary="$(find "$work/Payload" -maxdepth 2 -type f -name OpenVision | head -n 1)"
if [ -z "$binary" ]; then
  echo "::error::OpenVision binary not found inside $IPA"
  exit 1
fi

haystack="$work/haystack.txt"
{ nm -a "$binary" 2>/dev/null || true; strings -a "$binary"; } > "$haystack"

missing=0
for symbol in "${REQUIRED[@]}"; do
  if grep -q "$symbol" "$haystack"; then
    echo "✓ $symbol"
  else
    echo "::error::$symbol not found in the IPA binary"
    missing=1
  fi
done
size=$(wc -c < "$binary" | tr -d ' ')
echo "Binary: $(basename "$binary") ($((size / 1024 / 1024)) MB)"

plist_status=0
python3 - "$IPA" <<'PY' || plist_status=$?
import plistlib
import re
import sys
import zipfile
from urllib.parse import urlparse

ipa_path = sys.argv[1]
errors = []

SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*$")
TEAM_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
DIGITS_RE = re.compile(r"^[0-9]+$")


def has_placeholder(val: str) -> bool:
    low = val.lower()
    return "your_" in low or "$(" in val or "${" in val or "xxxxxxxxxx" in low


def scan_placeholders(obj, path: str) -> None:
    if isinstance(obj, str):
        if has_placeholder(obj):
            errors.append(f"Placeholder detected in {path}")
    elif isinstance(obj, dict):
        for k, v in obj.items():
            scan_placeholders(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for idx, item in enumerate(obj):
            scan_placeholders(item, f"{path}[{idx}]")


try:
    with zipfile.ZipFile(ipa_path, "r") as zf:
        raw_plist = zf.read("Payload/OpenVision.app/Info.plist")
except KeyError:
    print("::error::Payload/OpenVision.app/Info.plist not found inside IPA")
    sys.exit(1)
except Exception as exc:
    print(f"::error::Unable to read IPA archive {ipa_path}: {exc}")
    sys.exit(1)

try:
    plist = plistlib.loads(raw_plist)
except Exception as exc:
    print(f"::error::Payload/OpenVision.app/Info.plist is malformed: {exc}")
    sys.exit(1)

if not isinstance(plist, dict):
    print("::error::Info.plist root is not a dictionary")
    sys.exit(1)

# 1. Reject any placeholder anywhere in CFBundleIdentifier, CFBundleURLTypes, or MWDAT
for top_key in ("CFBundleIdentifier", "CFBundleURLTypes", "MWDAT"):
    if top_key in plist:
        scan_placeholders(plist[top_key], top_key)

# 2. CFBundleIdentifier
bundle_id = plist.get("CFBundleIdentifier")
if not isinstance(bundle_id, str) or not bundle_id.strip() or any(c.isspace() for c in bundle_id):
    errors.append("CFBundleIdentifier is missing or invalid")
else:
    bundle_id = bundle_id.strip()

# 3. MWDAT dictionary
mwdat = plist.get("MWDAT")
if not isinstance(mwdat, dict):
    errors.append("MWDAT dictionary is missing from Info.plist")
    mwdat = {}

meta_app_id_raw = mwdat.get("MetaAppID")
is_dev_mode = False
is_prod_mode = False
if not isinstance(meta_app_id_raw, str):
    errors.append("MWDAT.MetaAppID must be a string")
    meta_app_id = ""
else:
    meta_app_id = meta_app_id_raw.strip()
    if meta_app_id in ("", "0"):
        is_dev_mode = True
    elif DIGITS_RE.fullmatch(meta_app_id) and int(meta_app_id) > 0:
        is_prod_mode = True
    else:
        errors.append(
            "MWDAT.MetaAppID must be '' / '0' (Developer Mode) or positive ASCII digits (Production Mode)"
        )

# 4. MWDAT.ClientToken (NEVER print raw token value!)
client_token_raw = mwdat.get("ClientToken", "")
if not isinstance(client_token_raw, str):
    errors.append("MWDAT.ClientToken must be a string when present")
    client_token = ""
else:
    client_token = client_token_raw.strip()

if is_dev_mode:
    if client_token != "":
        errors.append("MWDAT.ClientToken must be empty or absent in Developer Mode")
    client_token_state = "<empty>" if "ClientToken" in mwdat else "<omitted>"
elif is_prod_mode:
    token_re = re.compile(rf"^AR\|{re.escape(meta_app_id)}\|\S+$")
    if not client_token or not token_re.fullmatch(client_token):
        errors.append("MWDAT.ClientToken must match AR|<MetaAppID>|<token> in Production Mode")
    client_token_state = "<redacted>" if client_token else "<empty>"
else:
    client_token_state = "<redacted>" if client_token else "<empty>"

# 5. CFBundleURLTypes & MWDAT.AppLinkURLScheme
url_types = plist.get("CFBundleURLTypes")
primary_scheme = ""
if (
    not isinstance(url_types, list)
    or not url_types
    or not isinstance(url_types[0], dict)
    or not isinstance(url_types[0].get("CFBundleURLSchemes"), list)
    or not url_types[0]["CFBundleURLSchemes"]
    or not isinstance(url_types[0]["CFBundleURLSchemes"][0], str)
):
    errors.append("CFBundleURLTypes[0].CFBundleURLSchemes[0] is missing")
else:
    primary_scheme = url_types[0]["CFBundleURLSchemes"][0].strip()
    if not SCHEME_RE.fullmatch(primary_scheme):
        errors.append(f"CFBundleURLTypes[0].CFBundleURLSchemes[0] is not a valid scheme: {primary_scheme!r}")

app_link_raw = mwdat.get("AppLinkURLScheme")
app_link = app_link_raw.strip() if isinstance(app_link_raw, str) else ""
if not app_link or any(c.isspace() for c in app_link):
    errors.append("MWDAT.AppLinkURLScheme is missing or contains whitespace")
elif primary_scheme:
    expected_custom = f"{primary_scheme}://"
    if is_dev_mode:
        if app_link.lower() != expected_custom.lower():
            errors.append(
                f"Developer Mode requires MWDAT.AppLinkURLScheme ({app_link!r}) to equal {expected_custom!r}"
            )
    elif is_prod_mode:
        parsed = urlparse(app_link)
        is_valid_https = parsed.scheme == "https" and bool(parsed.netloc)
        if not is_valid_https and app_link.lower() != expected_custom.lower():
            errors.append(
                "Production Mode requires MWDAT.AppLinkURLScheme to be an https:// Universal Link "
                f"or equal {expected_custom!r}"
            )

# 6. MWDAT.TeamID (NEVER print raw TeamID value!)
if "TeamID" not in mwdat:
    team_id_state = "<omitted>"
    if is_prod_mode:
        errors.append("Production Mode requires a non-empty 10-character MWDAT.TeamID")
else:
    team_id_raw = mwdat.get("TeamID")
    if not isinstance(team_id_raw, str):
        errors.append("MWDAT.TeamID must be a string when present")
        team_id_state = "<invalid>"
    else:
        team_id = team_id_raw.strip()
        if not team_id:
            team_id_state = "<empty>"
            if is_prod_mode:
                errors.append("Production Mode requires a non-empty 10-character MWDAT.TeamID")
        elif not TEAM_ID_RE.fullmatch(team_id):
            errors.append("MWDAT.TeamID must be 10 uppercase ASCII alphanumeric characters when non-empty")
            team_id_state = "<invalid>"
        else:
            team_id_state = "<set>"

# 7. LSApplicationQueriesSchemes (Meta AI app)
query_schemes = plist.get("LSApplicationQueriesSchemes")
if not isinstance(query_schemes, list) or "fb-viewapp" not in query_schemes:
    errors.append("LSApplicationQueriesSchemes must include 'fb-viewapp'")

# 8. Bluetooth Classic (PLAN.md D2)
bg_modes = plist.get("UIBackgroundModes")
if not isinstance(bg_modes, list) or "bluetooth-central" not in bg_modes or "external-accessory" not in bg_modes:
    errors.append("UIBackgroundModes must include 'bluetooth-central' and 'external-accessory'")

ea_protocols = plist.get("UISupportedExternalAccessoryProtocols")
if not isinstance(ea_protocols, list) or "com.meta.ar.wearable" not in ea_protocols:
    errors.append("UISupportedExternalAccessoryProtocols must include 'com.meta.ar.wearable'")

if errors:
    for err in errors:
        print(f"::error::{err}")
    sys.exit(1)

mode_label = "developer" if is_dev_mode else "production"
print(
    f"✓ Info.plist MWDAT valid (mode={mode_label}, MetaAppID={meta_app_id or '<empty>'}, "
    f"ClientToken={client_token_state}, TeamID={team_id_state}, "
    f"AppLinkURLScheme={app_link}, CFBundleURLSchemes[0]={primary_scheme}, "
    f"CFBundleIdentifier={bundle_id})"
)
print("✓ Info.plist Meta AI query scheme (fb-viewapp) & Bluetooth Classic (bluetooth-central, external-accessory, com.meta.ar.wearable)")
PY

if [ "$missing" -ne 0 ] || [ "$plist_status" -ne 0 ]; then
  exit 1
fi
exit 0
