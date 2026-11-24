#!/usr/bin/env python3
"""Local Python unittest suite for MWDAT IPA patching, IPA verification, and blueprint guard.

Exercises:
  - scripts/blueprint/patch_ipa_mwdat.py (XML & binary plist patching, Dev/Prod modes, redaction)
  - scripts/blueprint/verify_ipa_symbols.sh (synthetic .ipa zip archives with binary & XML plists)
  - scripts/blueprint/verify_blueprint.py (real repository guard check)
"""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PATCH_SCRIPT = REPO_ROOT / "scripts/blueprint/patch_ipa_mwdat.py"
VERIFY_IPA_SCRIPT = REPO_ROOT / "scripts/blueprint/verify_ipa_symbols.sh"
VERIFY_BLUEPRINT_SCRIPT = REPO_ROOT / "scripts/blueprint/verify_blueprint.py"

REQUIRED_SYMBOLS = (
    "RecentPhotoScanner",
    "cleanSpokenAudio",
    "conversationHistory",
    "PhotoPayload",
    "streamGenerateContent",
    "SolverIntent",
)


def base_plist() -> dict:
    return {
        "CFBundleDisplayName": "OpenVision",
        "CFBundleExecutable": "OpenVision",
        "CFBundleIdentifier": "com.yourcompany.openvision",
        "CFBundleShortVersionString": "2.14.0",
        "CFBundleVersion": "15",
        "CFBundleURLTypes": [
            {
                "CFBundleTypeRole": "Editor",
                "CFBundleURLName": "com.yourcompany.openvision",
                "CFBundleURLSchemes": ["openvision"],
            }
        ],
        "LSApplicationQueriesSchemes": ["fb-viewapp"],
        "UIBackgroundModes": ["audio", "bluetooth-central", "external-accessory"],
        "UISupportedExternalAccessoryProtocols": ["com.meta.ar.wearable"],
        "MWDAT": {
            "MetaAppID": "YOUR_META_APP_ID",
            "AppLinkURLScheme": "openvision://",
            "ClientToken": "AR|YOUR_META_APP_ID|YOUR_CLIENT_TOKEN",
            "TeamID": "",
        },
    }


def make_synthetic_ipa(
    target_path: Path,
    plist_data: dict,
    *,
    plist_fmt: plistlib.PlistFormat = plistlib.FMT_BINARY,
    symbols: tuple[str, ...] = REQUIRED_SYMBOLS,
) -> Path:
    binary_payload = b"\x00\x01FAKE_MACHO_HEADER\x00" + b"\x00".join(s.encode("utf-8") for s in symbols) + b"\x00"
    plist_bytes = plistlib.dumps(plist_data, fmt=plist_fmt)
    with zipfile.ZipFile(target_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("Payload/OpenVision.app/OpenVision", binary_payload)
        zf.writestr("Payload/OpenVision.app/Info.plist", plist_bytes)
    return target_path


class PatchIpaMwdatTests(unittest.TestCase):
    def _run_patch(
        self,
        plist_data: dict,
        args: list[str],
        *,
        env_extra: dict[str, str] | None = None,
        input_fmt: plistlib.PlistFormat = plistlib.FMT_XML,
    ) -> tuple[subprocess.CompletedProcess[str], bytes, dict | None]:
        with tempfile.TemporaryDirectory() as tmp:
            plist_path = Path(tmp) / "Info.plist"
            plist_path.write_bytes(plistlib.dumps(plist_data, fmt=input_fmt))

            env = os.environ.copy()
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            env.pop("MWDAT_TEAM_ID", None)
            env.pop("MWDAT_CLIENT_TOKEN", None)
            env.pop("MWDAT_META_APP_ID", None)
            if env_extra:
                env.update(env_extra)

            proc = subprocess.run(
                [sys.executable, "-B", str(PATCH_SCRIPT), "--plist", str(plist_path), *args],
                capture_output=True,
                text=True,
                env=env,
            )
            raw = plist_path.read_bytes()
            parsed = plistlib.loads(raw) if proc.returncode == 0 else None
            return proc, raw, parsed

    def test_developer_mode_default_writes_binary_plist(self) -> None:
        proc, raw, plist = self._run_patch(base_plist(), ["--mode", "developer"], input_fmt=plistlib.FMT_XML)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(raw.startswith(b"bplist00"), "output plist must be FMT_BINARY")
        assert plist is not None
        self.assertEqual(plist["MWDAT"]["MetaAppID"], "0")
        self.assertEqual(plist["MWDAT"]["ClientToken"], "")
        self.assertEqual(plist["MWDAT"]["TeamID"], "")
        self.assertEqual(plist["MWDAT"]["AppLinkURLScheme"], "openvision://")
        self.assertEqual(plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["openvision"])

    def test_developer_mode_from_binary_plist_strips_leaked_token_and_redacts_team_id(self) -> None:
        team_id = "AB12CD34EF"
        leaked_token = "AR|999999|SUPER_SECRET_LEAKED_TOKEN"
        proc, raw, plist = self._run_patch(
            base_plist(),
            ["--mode", "developer", "--bundle-id", "com.example.solver", "--url-scheme", "myvision://"],
            env_extra={"MWDAT_TEAM_ID": team_id, "MWDAT_CLIENT_TOKEN": leaked_token},
            input_fmt=plistlib.FMT_BINARY,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(raw.startswith(b"bplist00"))
        assert plist is not None
        self.assertEqual(plist["MWDAT"]["MetaAppID"], "0")
        self.assertEqual(plist["MWDAT"]["ClientToken"], "")
        self.assertEqual(plist["MWDAT"]["TeamID"], team_id)
        self.assertEqual(plist["MWDAT"]["AppLinkURLScheme"], "myvision://")
        self.assertEqual(plist["CFBundleIdentifier"], "com.example.solver")
        self.assertEqual(plist["CFBundleURLTypes"][0]["CFBundleURLName"], "com.example.solver")
        self.assertEqual(plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["myvision"])

        combined = proc.stdout + proc.stderr
        self.assertNotIn(team_id, combined)
        self.assertNotIn(leaked_token, combined)
        self.assertNotIn("SUPER_SECRET_LEAKED_TOKEN", combined)

    def test_developer_mode_omit_empty_team_id_removes_key(self) -> None:
        proc, _, plist = self._run_patch(
            base_plist(),
            ["--mode", "developer", "--omit-empty-team-id", "true"],
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        assert plist is not None
        self.assertNotIn("TeamID", plist["MWDAT"])
        self.assertIn("TeamID=<omitted>", proc.stdout)

    def test_developer_mode_rejects_nonzero_or_placeholder_meta_app_id(self) -> None:
        for bad_id in ("123456789", "YOUR_META_APP_ID", "$(META_APP_ID)"):
            proc, _, _ = self._run_patch(base_plist(), ["--mode", "developer", "--meta-app-id", bad_id])
            self.assertNotEqual(proc.returncode, 0, f"expected failure for --meta-app-id={bad_id}")

    def test_production_mode_valid_universal_link_and_redaction(self) -> None:
        secret_tok = "AR|123456789|VERY_SECRET_PROD_TOKEN_987"
        team_id = "ZX98CV76BN"
        proc, raw, plist = self._run_patch(
            base_plist(),
            [
                "--mode",
                "production",
                "--meta-app-id",
                "123456789",
                "--url-scheme",
                "https://openvision.example.com/dat",
            ],
            env_extra={"MWDAT_CLIENT_TOKEN": secret_tok, "MWDAT_TEAM_ID": team_id},
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(raw.startswith(b"bplist00"))
        assert plist is not None
        self.assertEqual(plist["MWDAT"]["MetaAppID"], "123456789")
        self.assertEqual(plist["MWDAT"]["ClientToken"], secret_tok)
        self.assertEqual(plist["MWDAT"]["TeamID"], team_id)
        self.assertEqual(plist["MWDAT"]["AppLinkURLScheme"], "https://openvision.example.com/dat")
        self.assertEqual(plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["openvision"])

        combined = proc.stdout + proc.stderr
        self.assertNotIn(secret_tok, combined)
        self.assertNotIn("VERY_SECRET_PROD_TOKEN_987", combined)
        self.assertNotIn(team_id, combined)

    def test_production_mode_fails_on_missing_or_bad_credentials_without_leaking(self) -> None:
        # Missing token
        proc, _, _ = self._run_patch(
            base_plist(),
            ["--mode", "production", "--meta-app-id", "123456789", "--url-scheme", "https://example.com/app"],
            env_extra={"MWDAT_TEAM_ID": "AB12CD34EF"},
        )
        self.assertNotEqual(proc.returncode, 0)

        # Mismatched app id in token (must NOT leak token)
        bad_token = "AR|999999999|LEAK_CHECK_BAD_TOKEN"
        proc, _, _ = self._run_patch(
            base_plist(),
            ["--mode", "production", "--meta-app-id", "123456789", "--url-scheme", "https://example.com/app"],
            env_extra={"MWDAT_TEAM_ID": "AB12CD34EF", "MWDAT_CLIENT_TOKEN": bad_token},
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn("LEAK_CHECK_BAD_TOKEN", proc.stdout + proc.stderr)

        # Missing TeamID
        proc, _, _ = self._run_patch(
            base_plist(),
            ["--mode", "production", "--meta-app-id", "123456789", "--url-scheme", "https://example.com/app"],
            env_extra={"MWDAT_CLIENT_TOKEN": "AR|123456789|validtok"},
        )
        self.assertNotEqual(proc.returncode, 0)

        # Invalid TeamID (must NOT leak)
        bad_team = "bad_team_secret"
        proc, _, _ = self._run_patch(
            base_plist(),
            ["--mode", "production", "--meta-app-id", "123456789", "--url-scheme", "https://example.com/app"],
            env_extra={"MWDAT_CLIENT_TOKEN": "AR|123456789|validtok", "MWDAT_TEAM_ID": bad_team},
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn(bad_team, proc.stdout + proc.stderr)

        # Zero MetaAppID in production
        proc, _, _ = self._run_patch(
            base_plist(),
            ["--mode", "production", "--meta-app-id", "0", "--url-scheme", "https://example.com/app"],
            env_extra={"MWDAT_CLIENT_TOKEN": "AR|0|tok", "MWDAT_TEAM_ID": "AB12CD34EF"},
        )
        self.assertNotEqual(proc.returncode, 0)

    def test_placeholder_bundle_id_and_url_scheme_rejected(self) -> None:
        proc, _, _ = self._run_patch(base_plist(), ["--bundle-id", "YOUR_BUNDLE_ID"])
        self.assertNotEqual(proc.returncode, 0)

        proc, _, _ = self._run_patch(base_plist(), ["--url-scheme", "$(APP_LINK_URL_SCHEME)"])
        self.assertNotEqual(proc.returncode, 0)

    def test_rejects_http_and_https_as_custom_url_schemes_in_dev_and_prod(self) -> None:
        prod_env = {"MWDAT_TEAM_ID": "Q9W8E7R6T5", "MWDAT_CLIENT_TOKEN": "AR|123456789|prod_tok"}
        for bad_scheme in ("http", "https", "HTTP", "HTTPS", "http://", "https://", "HTTP://", "HTTPS://"):
            proc_dev, _, _ = self._run_patch(base_plist(), ["--mode=developer", f"--url-scheme={bad_scheme}"])
            self.assertEqual(proc_dev.returncode, 1, f"dev should reject {bad_scheme!r}")

            proc_prod, _, _ = self._run_patch(
                base_plist(),
                ["--mode=production", "--meta-app-id=123456789", f"--url-scheme={bad_scheme}"],
                env_extra=prod_env,
            )
            self.assertEqual(proc_prod.returncode, 1, f"prod should reject {bad_scheme!r}")

        # Pre-existing CFBundleURLSchemes=["http"] or ["https"] must be sanitized to ["openvision"]
        for existing_bad in (["http"], ["https"], ["HTTP"]):
            data = base_plist()
            data["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = existing_bad
            proc, _, plist = self._run_patch(
                data,
                ["--mode=production", "--meta-app-id=123456789", "--url-scheme=https://example.com/dat"],
                env_extra=prod_env,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            assert plist is not None
            self.assertEqual(plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["openvision"])

    def test_production_rejects_malformed_https_universal_links_without_traceback(self) -> None:
        prod_env = {"MWDAT_TEAM_ID": "Q9W8E7R6T5", "MWDAT_CLIENT_TOKEN": "AR|123456789|prod_tok"}
        bad_urls = (
            "https://:443/dat",
            "https://user@/dat",
            "https://user:pass@example.com/dat",
            "https://example.com:0/dat",
            "https://example.com:99999/dat",
            "https://example.com:abc/dat",
            "https://example.com:/dat",
            "https://;rm",
            "https://foo|bar",
            'https://foo"bar',
            "https://foo'bar",
            "https://`id`",
            "https://[::1/dat",
            "https://example.com/path;rm",
        )
        for bad_url in bad_urls:
            proc, _, _ = self._run_patch(
                base_plist(),
                ["--mode=production", "--meta-app-id=123456789", f"--url-scheme={bad_url}"],
                env_extra=prod_env,
            )
            combined = proc.stdout + proc.stderr
            self.assertEqual(proc.returncode, 1, f"expected rc=1 for {bad_url!r}, got {proc.returncode}: {combined}")
            self.assertIn("::error::", combined, f"expected ::error:: for {bad_url!r}")
            self.assertNotIn("Traceback", combined, f"unexpected traceback for {bad_url!r}: {combined}")

        # Valid port & IPv6 Universal Links should succeed cleanly
        for good_url in ("https://example.com:8443/dat?v=1", "https://[::1]/dat"):
            proc, _, plist = self._run_patch(
                base_plist(),
                ["--mode=production", "--meta-app-id=123456789", f"--url-scheme={good_url}"],
                env_extra=prod_env,
            )
            self.assertEqual(proc.returncode, 0, f"expected rc=0 for {good_url!r}: {proc.stderr}")
            assert plist is not None
            self.assertEqual(plist["MWDAT"]["AppLinkURLScheme"], good_url)

    def test_rejects_corrupted_or_whitespace_existing_bundle_id(self) -> None:
        for bad_bid in (12345, " com.example.app ", "notadomain", ""):
            data = base_plist()
            data["CFBundleIdentifier"] = bad_bid
            proc, _, _ = self._run_patch(data, ["--mode=developer"])
            self.assertEqual(proc.returncode, 1, f"expected rc=1 for CFBundleIdentifier={bad_bid!r}")
            self.assertIn("::error::", proc.stderr)

    def test_omit_empty_team_id_cli_flag_safety_and_contradictions(self) -> None:
        # --omit-empty-team-id -h must fail non-zero instead of printing help and exiting 0
        proc_help, raw_help, _ = self._run_patch(base_plist(), ["--mode", "developer", "--omit-empty-team-id", "-h"])
        self.assertEqual(proc_help.returncode, 2, proc_help.stdout + proc_help.stderr)
        self.assertEqual(plistlib.loads(raw_help)["MWDAT"]["MetaAppID"], "YOUR_META_APP_ID")

        # Contradictory MWDAT_TEAM_ID + --omit-empty-team-id=true must fail without leaking Team ID
        secret_team = "Q9W8E7R6T5"
        proc_both, _, _ = self._run_patch(
            base_plist(),
            ["--mode=developer", "--omit-empty-team-id=true"],
            env_extra={"MWDAT_TEAM_ID": secret_team},
        )
        self.assertEqual(proc_both.returncode, 1)
        self.assertIn("::error::", proc_both.stderr)
        self.assertNotIn(secret_team, proc_both.stdout + proc_both.stderr)

        # Contradictory --mode=production + --omit-empty-team-id=true must fail
        proc_prod, _, _ = self._run_patch(
            base_plist(),
            ["--mode=production", "--meta-app-id=123456789", "--url-scheme=https://example.com/dat", "--omit-empty-team-id=true"],
            env_extra={"MWDAT_CLIENT_TOKEN": "AR|123456789|tok"},
        )
        self.assertEqual(proc_prod.returncode, 1)
        self.assertIn("::error::", proc_prod.stderr)


class VerifyIpaSymbolsTests(unittest.TestCase):
    def _run_verify(
        self,
        plist_data: dict,
        *,
        plist_fmt: plistlib.PlistFormat = plistlib.FMT_BINARY,
        symbols: tuple[str, ...] = REQUIRED_SYMBOLS,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as tmp:
            ipa = make_synthetic_ipa(Path(tmp) / "OpenVision.ipa", plist_data, plist_fmt=plist_fmt, symbols=symbols)
            env = os.environ.copy()
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            return subprocess.run(
                ["bash", str(VERIFY_IPA_SCRIPT), str(ipa)],
                capture_output=True,
                text=True,
                env=env,
            )

    def _valid_dev_plist(self) -> dict:
        data = base_plist()
        data["MWDAT"] = {
            "MetaAppID": "0",
            "AppLinkURLScheme": "openvision://",
            "ClientToken": "",
            "TeamID": "",
        }
        return data

    def test_valid_developer_mode_binary_and_xml_plists_pass(self) -> None:
        proc_bin = self._run_verify(self._valid_dev_plist(), plist_fmt=plistlib.FMT_BINARY)
        self.assertEqual(proc_bin.returncode, 0, proc_bin.stdout + proc_bin.stderr)

        xml_plist = self._valid_dev_plist()
        xml_plist["MWDAT"].pop("TeamID")
        proc_xml = self._run_verify(xml_plist, plist_fmt=plistlib.FMT_XML)
        self.assertEqual(proc_xml.returncode, 0, proc_xml.stdout + proc_xml.stderr)

    def test_valid_production_mode_passes_and_redacts_secrets(self) -> None:
        secret_tok = "AR|123456789|TOP_SECRET_IPA_VERIFY_TOKEN"
        team_id = "AB12CD34EF"
        data = self._valid_dev_plist()
        data["MWDAT"] = {
            "MetaAppID": "123456789",
            "AppLinkURLScheme": "https://example.com/dat",
            "ClientToken": secret_tok,
            "TeamID": team_id,
        }
        proc = self._run_verify(data, plist_fmt=plistlib.FMT_BINARY)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        combined = proc.stdout + proc.stderr
        self.assertNotIn(secret_tok, combined)
        self.assertNotIn("TOP_SECRET_IPA_VERIFY_TOKEN", combined)
        self.assertNotIn(team_id, combined)

    def test_placeholders_in_mwdat_fail(self) -> None:
        # Original broken CI IPA with YOUR_META_APP_ID / YOUR_CLIENT_TOKEN
        proc = self._run_verify(base_plist())
        self.assertNotEqual(proc.returncode, 0)

        # YOUR_TEAM_ID placeholder
        team_ph = self._valid_dev_plist()
        team_ph["MWDAT"]["TeamID"] = "YOUR_TEAM_ID"
        self.assertNotEqual(self._run_verify(team_ph).returncode, 0)

        # Unexpanded build setting variable $(META_APP_ID)
        var_ph = self._valid_dev_plist()
        var_ph["MWDAT"]["MetaAppID"] = "$(META_APP_ID)"
        self.assertNotEqual(self._run_verify(var_ph).returncode, 0)

    def test_dev_mode_nonempty_client_token_fails_without_leaking(self) -> None:
        data = self._valid_dev_plist()
        secret = "AR|0|SHOULD_NOT_BE_IN_DEV_MODE"
        data["MWDAT"]["ClientToken"] = secret
        proc = self._run_verify(data)
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn(secret, proc.stdout + proc.stderr)

    def test_mismatched_or_malformed_url_scheme_fails(self) -> None:
        mismatch = self._valid_dev_plist()
        mismatch["MWDAT"]["AppLinkURLScheme"] = "other://"
        self.assertNotEqual(self._run_verify(mismatch).returncode, 0)

        no_suffix = self._valid_dev_plist()
        no_suffix["MWDAT"]["AppLinkURLScheme"] = "openvision"
        self.assertNotEqual(self._run_verify(no_suffix).returncode, 0)

    def test_rejects_http_and_https_custom_url_schemes_in_dev_and_prod(self) -> None:
        for web_scheme in ("http", "https", "HTTP", "HTTPS"):
            dev_bad = self._valid_dev_plist()
            dev_bad["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = [web_scheme]
            dev_bad["MWDAT"]["AppLinkURLScheme"] = f"{web_scheme}://"
            self.assertNotEqual(self._run_verify(dev_bad).returncode, 0, f"dev should reject {web_scheme}")

            prod_bad = self._valid_dev_plist()
            prod_bad["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = [web_scheme]
            prod_bad["MWDAT"] = {
                "MetaAppID": "123456789",
                "AppLinkURLScheme": f"{web_scheme}://",
                "ClientToken": "AR|123456789|valid_tok",
                "TeamID": "Q9W8E7R6T5",
            }
            self.assertNotEqual(self._run_verify(prod_bad).returncode, 0, f"prod should reject {web_scheme}://")

            prod_bad_existing = self._valid_dev_plist()
            prod_bad_existing["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = [web_scheme]
            prod_bad_existing["MWDAT"] = {
                "MetaAppID": "123456789",
                "AppLinkURLScheme": "https://example.com/dat",
                "ClientToken": "AR|123456789|valid_tok",
                "TeamID": "Q9W8E7R6T5",
            }
            self.assertNotEqual(
                self._run_verify(prod_bad_existing).returncode,
                0,
                f"prod should reject CFBundleURLSchemes=[{web_scheme!r}]",
            )

    def test_rejects_malformed_https_universal_links_without_traceback(self) -> None:
        bad_urls = (
            "https://:443/dat",
            "https://user@/dat",
            "https://example.com:0/dat",
            "https://example.com:99999/dat",
            "https://example.com:abc/dat",
            "https://example.com:/dat",
            "https://;rm",
            "https://foo|bar",
            "https://[::1/dat",
        )
        for bad_url in bad_urls:
            data = self._valid_dev_plist()
            data["MWDAT"] = {
                "MetaAppID": "123456789",
                "AppLinkURLScheme": bad_url,
                "ClientToken": "AR|123456789|valid_tok",
                "TeamID": "Q9W8E7R6T5",
            }
            proc = self._run_verify(data)
            combined = proc.stdout + proc.stderr
            self.assertEqual(proc.returncode, 1, f"expected rc=1 for {bad_url!r}: {combined}")
            self.assertIn("::error::", combined)
            self.assertNotIn("Traceback", combined, f"unexpected traceback for {bad_url!r}: {combined}")

        for good_url in ("https://example.com:8443/dat", "https://[::1]/dat"):
            data = self._valid_dev_plist()
            data["MWDAT"] = {
                "MetaAppID": "123456789",
                "AppLinkURLScheme": good_url,
                "ClientToken": "AR|123456789|valid_tok",
                "TeamID": "Q9W8E7R6T5",
            }
            proc = self._run_verify(data)
            self.assertEqual(proc.returncode, 0, f"expected rc=0 for {good_url!r}: {proc.stdout + proc.stderr}")

    def test_rejects_leading_trailing_whitespace_before_stripping(self) -> None:
        # 1. MetaAppID with surrounding whitespace / whitespace-only
        for bad_id in (" 0\n", "   "):
            data = self._valid_dev_plist()
            data["MWDAT"]["MetaAppID"] = bad_id
            self.assertEqual(self._run_verify(data).returncode, 1, f"should reject MetaAppID={bad_id!r}")

        # 2. AppLinkURLScheme with surrounding whitespace
        data = self._valid_dev_plist()
        data["MWDAT"]["AppLinkURLScheme"] = " openvision://\n"
        self.assertEqual(self._run_verify(data).returncode, 1)

        # 3. CFBundleURLSchemes with surrounding whitespace or leading empty string
        for bad_schemes in ([" openvision\n"], ["", "openvision"]):
            data = self._valid_dev_plist()
            data["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = bad_schemes
            self.assertEqual(self._run_verify(data).returncode, 1, f"should reject schemes={bad_schemes!r}")

        # 4. TeamID with surrounding whitespace (must NOT leak value)
        data = self._valid_dev_plist()
        data["MWDAT"]["TeamID"] = " Q9W8E7R6T5\n"
        proc_team = self._run_verify(data)
        self.assertEqual(proc_team.returncode, 1)
        self.assertNotIn("Q9W8E7R6T5", proc_team.stdout + proc_team.stderr)

        # 5. ClientToken whitespace-only in Dev Mode
        data = self._valid_dev_plist()
        data["MWDAT"]["ClientToken"] = "   "
        self.assertEqual(self._run_verify(data).returncode, 1)

        # 6. ClientToken with surrounding whitespace in Prod Mode (must NOT leak value)
        data = self._valid_dev_plist()
        data["MWDAT"] = {
            "MetaAppID": "123456789",
            "AppLinkURLScheme": "https://example.com/dat",
            "ClientToken": " AR|123456789|SECRET_WS_TOKEN_99\n",
            "TeamID": "Q9W8E7R6T5",
        }
        proc_tok = self._run_verify(data)
        self.assertEqual(proc_tok.returncode, 1)
        self.assertNotIn("SECRET_WS_TOKEN_99", proc_tok.stdout + proc_tok.stderr)

    def test_missing_meta_ai_or_bluetooth_classic_keys_fail(self) -> None:
        no_fb = self._valid_dev_plist()
        no_fb["LSApplicationQueriesSchemes"] = []
        self.assertNotEqual(self._run_verify(no_fb).returncode, 0)

        no_ea = self._valid_dev_plist()
        no_ea["UISupportedExternalAccessoryProtocols"] = []
        self.assertNotEqual(self._run_verify(no_ea).returncode, 0)

        no_bg = self._valid_dev_plist()
        no_bg["UIBackgroundModes"] = ["audio", "bluetooth-central"]
        self.assertNotEqual(self._run_verify(no_bg).returncode, 0)

    def test_missing_required_macho_symbol_fails(self) -> None:
        proc = self._run_verify(self._valid_dev_plist(), symbols=REQUIRED_SYMBOLS[:-1])
        self.assertNotEqual(proc.returncode, 0)

    def test_production_mode_missing_team_id_or_mismatched_token_fails(self) -> None:
        no_team = self._valid_dev_plist()
        no_team["MWDAT"] = {
            "MetaAppID": "123456789",
            "AppLinkURLScheme": "https://example.com/dat",
            "ClientToken": "AR|123456789|valid_secret",
            "TeamID": "",
        }
        proc = self._run_verify(no_team)
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn("valid_secret", proc.stdout + proc.stderr)

        bad_tok = self._valid_dev_plist()
        bad_tok["MWDAT"] = {
            "MetaAppID": "123456789",
            "AppLinkURLScheme": "https://example.com/dat",
            "ClientToken": "AR|999999999|wrong_app_secret",
            "TeamID": "AB12CD34EF",
        }
        proc2 = self._run_verify(bad_tok)
        self.assertNotEqual(proc2.returncode, 0)
        self.assertNotIn("wrong_app_secret", proc2.stdout + proc2.stderr)

    def test_patch_then_verify_ipa_end_to_end_dev_and_prod(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)

            # Developer mode end-to-end: start from broken placeholders, patch, zip, verify
            dev_plist_path = tmp_path / "DevInfo.plist"
            dev_plist_path.write_bytes(plistlib.dumps(base_plist(), fmt=plistlib.FMT_BINARY))
            env = os.environ.copy()
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            env["MWDAT_TEAM_ID"] = ""
            env["MWDAT_CLIENT_TOKEN"] = ""
            p1 = subprocess.run(
                [sys.executable, "-B", str(PATCH_SCRIPT), "--plist", str(dev_plist_path), "--mode", "developer"],
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(p1.returncode, 0, p1.stderr)
            dev_ipa = make_synthetic_ipa(
                tmp_path / "OpenVision-dev.ipa",
                plistlib.loads(dev_plist_path.read_bytes()),
                plist_fmt=plistlib.FMT_BINARY,
            )
            v1 = subprocess.run(["bash", str(VERIFY_IPA_SCRIPT), str(dev_ipa)], capture_output=True, text=True, env=env)
            self.assertEqual(v1.returncode, 0, v1.stdout + v1.stderr)

            # Production mode with custom scheme (emits warning, passes strict verify)
            prod_plist_path = tmp_path / "ProdInfo.plist"
            prod_plist_path.write_bytes(plistlib.dumps(base_plist(), fmt=plistlib.FMT_XML))
            env["MWDAT_TEAM_ID"] = "AB12CD34EF"
            env["MWDAT_CLIENT_TOKEN"] = "AR|555666777|E2E_SECRET_TOKEN_1"
            p2 = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(PATCH_SCRIPT),
                    "--plist",
                    str(prod_plist_path),
                    "--mode",
                    "production",
                    "--meta-app-id",
                    "555666777",
                    "--url-scheme",
                    "openvision",
                ],
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(p2.returncode, 0, p2.stderr)
            self.assertIn("::warning::", p2.stderr)
            self.assertNotIn("E2E_SECRET_TOKEN_1", p2.stdout + p2.stderr)
            self.assertNotIn("AB12CD34EF", p2.stdout + p2.stderr)
            prod_ipa = make_synthetic_ipa(
                tmp_path / "OpenVision-prod.ipa",
                plistlib.loads(prod_plist_path.read_bytes()),
                plist_fmt=plistlib.FMT_BINARY,
            )
            v2 = subprocess.run(["bash", str(VERIFY_IPA_SCRIPT), str(prod_ipa)], capture_output=True, text=True, env=env)
            self.assertEqual(v2.returncode, 0, v2.stdout + v2.stderr)
            self.assertNotIn("E2E_SECRET_TOKEN_1", v2.stdout + v2.stderr)
            self.assertNotIn("AB12CD34EF", v2.stdout + v2.stderr)


class WorkflowAndMakefileTests(unittest.TestCase):
    @staticmethod
    def _extract_patch_step_script() -> str:
        wf_lines = (REPO_ROOT / ".github/workflows/build-ipa.yml").read_text(encoding="utf-8").splitlines()
        in_step = False
        in_run = False
        run_indent: int | None = None
        script_lines: list[str] = []
        for line in wf_lines:
            if not in_step:
                if "name: Patch MWDAT configuration and package IPA" in line:
                    in_step = True
                continue
            if not in_run:
                if line.strip() == "run: |":
                    in_run = True
                continue
            if line.strip() == "":
                script_lines.append("")
                continue
            indent = len(line) - len(line.lstrip(" "))
            if run_indent is None:
                run_indent = indent
            if indent < run_indent:
                break
            script_lines.append(line[run_indent:])
        assert script_lines, "Failed to extract Patch MWDAT step script from build-ipa.yml"
        return "\n".join(script_lines) + "\n"

    def _run_build_ipa_step(
        self,
        env_overrides: dict[str, str],
        *,
        product_dirs: tuple[str, ...] = ("Release-iphoneos",),
    ) -> tuple[subprocess.CompletedProcess[str], Path | None, dict | None, bool]:
        script = self._extract_patch_step_script()
        binary_payload = b"\x00FAKE_MACHO\x00" + b"\x00".join(s.encode("utf-8") for s in REQUIRED_SYMBOLS) + b"\x00"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scripts").symlink_to(REPO_ROOT / "scripts")
            for pdir in product_dirs:
                app_dir = root / "DerivedData/Build/Products" / pdir / "OpenVision.app"
                fw_dir = app_dir / "Frameworks/Dummy.framework/Versions/A"
                fw_dir.mkdir(parents=True, exist_ok=True)
                (fw_dir / "Dummy").write_bytes(b"fw")
                (app_dir / "Frameworks/Dummy.framework/Versions/Current").symlink_to("A")
                (app_dir / "OpenVision").write_bytes(binary_payload)
                (app_dir / "Info.plist").write_bytes(plistlib.dumps(base_plist(), fmt=plistlib.FMT_BINARY))

            env = os.environ.copy()
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            for key in (
                "INPUT_MWDAT_MODE",
                "INPUT_META_APP_ID",
                "VAR_META_APP_ID",
                "SECRET_META_APP_ID",
                "INPUT_APPLE_TEAM_ID",
                "SECRET_APPLE_TEAM_ID",
                "INPUT_OMIT_EMPTY_TEAM_ID",
                "INPUT_BUNDLE_ID",
                "VAR_BUNDLE_ID",
                "INPUT_URL_SCHEME",
                "SECRET_META_CLIENT_TOKEN",
            ):
                env[key] = ""
            env.update(env_overrides)

            proc = subprocess.run(["bash", "-c", script], cwd=str(root), capture_output=True, text=True, env=env)
            ipa_path = root / "OpenVision.ipa"
            if proc.returncode != 0 or not ipa_path.is_file():
                return proc, None, None, False

            symlink_preserved = (root / "Payload/OpenVision.app/Frameworks/Dummy.framework/Versions/Current").is_symlink()
            with zipfile.ZipFile(ipa_path, "r") as zf:
                patched_plist = plistlib.loads(zf.read("Payload/OpenVision.app/Info.plist"))

            verify_proc = subprocess.run(
                ["bash", str(VERIFY_IPA_SCRIPT), str(ipa_path)],
                cwd=str(root),
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(verify_proc.returncode, 0, verify_proc.stdout + verify_proc.stderr)
            return proc, ipa_path, patched_plist, symlink_preserved

    def test_build_ipa_workflow_dev_mode_isolates_secret_team_id_and_honors_omit_empty_team_id(self) -> None:
        secret_team = "Q9W8E7R6T5"
        secret_tok = "AR|123456789|WF_SECRET_TOKEN_XYZ"

        # 1. Dev Mode + omit_empty_team_id=true with SECRET_APPLE_TEAM_ID set -> MUST omit TeamID & never leak secret
        proc, _, plist, symlink_ok = self._run_build_ipa_step(
            {
                "INPUT_MWDAT_MODE": "developer",
                "INPUT_OMIT_EMPTY_TEAM_ID": "true",
                "SECRET_APPLE_TEAM_ID": secret_team,
                "SECRET_META_CLIENT_TOKEN": secret_tok,
            }
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        assert plist is not None
        self.assertNotIn("TeamID", plist["MWDAT"])
        self.assertEqual(plist["MWDAT"]["MetaAppID"], "0")
        self.assertEqual(plist["MWDAT"]["ClientToken"], "")
        self.assertTrue(symlink_ok, "cp -Rp must preserve framework symlinks")
        self.assertNotIn(secret_team, proc.stdout + proc.stderr)
        self.assertNotIn(secret_tok, proc.stdout + proc.stderr)

        # 2. Dev Mode default (omit_empty_team_id=false) with SECRET_APPLE_TEAM_ID set -> MUST stay empty ""
        proc2, _, plist2, _ = self._run_build_ipa_step(
            {
                "INPUT_MWDAT_MODE": "developer",
                "INPUT_OMIT_EMPTY_TEAM_ID": "false",
                "SECRET_APPLE_TEAM_ID": secret_team,
            }
        )
        self.assertEqual(proc2.returncode, 0, proc2.stdout + proc2.stderr)
        assert plist2 is not None
        self.assertEqual(plist2["MWDAT"]["TeamID"], "")
        self.assertNotIn(secret_team, proc2.stdout + proc2.stderr)

        # 3. Prod Mode + omit_empty_team_id=true -> MUST fail fast
        proc3, _, _, _ = self._run_build_ipa_step(
            {
                "INPUT_MWDAT_MODE": "production",
                "INPUT_META_APP_ID": "123456789",
                "INPUT_URL_SCHEME": "https://example.com/dat",
                "INPUT_OMIT_EMPTY_TEAM_ID": "true",
                "SECRET_APPLE_TEAM_ID": secret_team,
                "SECRET_META_CLIENT_TOKEN": secret_tok,
            }
        )
        self.assertNotEqual(proc3.returncode, 0)

        # 4. Prod Mode fallback to SECRET_APPLE_TEAM_ID & SECRET_META_CLIENT_TOKEN -> succeeds without leaks
        proc4, _, plist4, _ = self._run_build_ipa_step(
            {
                "INPUT_MWDAT_MODE": "production",
                "INPUT_META_APP_ID": "123456789",
                "INPUT_URL_SCHEME": "https://example.com/dat",
                "SECRET_APPLE_TEAM_ID": secret_team,
                "SECRET_META_CLIENT_TOKEN": secret_tok,
            }
        )
        self.assertEqual(proc4.returncode, 0, proc4.stdout + proc4.stderr)
        assert plist4 is not None
        self.assertEqual(plist4["MWDAT"]["TeamID"], secret_team)
        self.assertEqual(plist4["MWDAT"]["ClientToken"], secret_tok)
        self.assertNotIn(secret_team, proc4.stdout + proc4.stderr)
        self.assertNotIn(secret_tok, proc4.stdout + proc4.stderr)

        # 5. Fallback APP_PATH find with multiple OpenVision.app dirs must not SIGPIPE under pipefail
        proc5, _, _, _ = self._run_build_ipa_step(
            {"INPUT_MWDAT_MODE": "developer"},
            product_dirs=("Alt1-iphoneos", "Alt2-iphoneos"),
        )
        self.assertEqual(proc5.returncode, 0, proc5.stdout + proc5.stderr)

    def test_makefile_check_config_handles_case_comments_and_conditionals(self) -> None:
        makefile = REPO_ROOT / "Makefile"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)

            # Should reject lowercase placeholder
            (tmp_path / "Config.xcconfig").write_text("META_APP_ID = your_meta_app_id\n", encoding="utf-8")
            r_lower = subprocess.run(["make", "-f", str(makefile), "check-config"], cwd=tmp, capture_output=True, text=True)
            self.assertNotEqual(r_lower.returncode, 0)

            # Should reject conditional xcconfig placeholder
            (tmp_path / "Config.xcconfig").write_text(
                "DEVELOPMENT_TEAM[sdk=iphoneos*] = YOUR_TEAM_ID\n", encoding="utf-8"
            )
            r_cond = subprocess.run(["make", "-f", str(makefile), "check-config"], cwd=tmp, capture_output=True, text=True)
            self.assertNotEqual(r_cond.returncode, 0)

            # Should pass inline // comment containing placeholder word
            (tmp_path / "Config.xcconfig").write_text(
                "META_APP_ID = 0 // replaced YOUR_META_APP_ID\n", encoding="utf-8"
            )
            r_comment = subprocess.run(["make", "-f", str(makefile), "check-config"], cwd=tmp, capture_output=True, text=True)
            self.assertEqual(r_comment.returncode, 0, r_comment.stdout + r_comment.stderr)

            # Should pass real Config.xcconfig.example
            (tmp_path / "Config.xcconfig").write_text(
                (REPO_ROOT / "Config.xcconfig.example").read_text(encoding="utf-8"), encoding="utf-8"
            )
            r_example = subprocess.run(["make", "-f", str(makefile), "check-config"], cwd=tmp, capture_output=True, text=True)
            self.assertEqual(r_example.returncode, 0, r_example.stdout + r_example.stderr)


class VerifyBlueprintTests(unittest.TestCase):
    def test_verify_blueprint_passes_on_repository(self) -> None:
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        proc = subprocess.run(
            [sys.executable, "-B", str(VERIFY_BLUEPRINT_SCRIPT)],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("0 failed", proc.stdout)


if __name__ == "__main__":
    unittest.main()
