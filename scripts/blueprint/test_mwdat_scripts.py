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
            env.pop("MWDAT_TEAM_ID", None)
            env.pop("MWDAT_CLIENT_TOKEN", None)
            env.pop("MWDAT_META_APP_ID", None)
            if env_extra:
                env.update(env_extra)

            proc = subprocess.run(
                [sys.executable, str(PATCH_SCRIPT), "--plist", str(plist_path), *args],
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
            return subprocess.run(
                ["bash", str(VERIFY_IPA_SCRIPT), str(ipa)],
                capture_output=True,
                text=True,
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
            env["MWDAT_TEAM_ID"] = ""
            env["MWDAT_CLIENT_TOKEN"] = ""
            p1 = subprocess.run(
                [sys.executable, str(PATCH_SCRIPT), "--plist", str(dev_plist_path), "--mode", "developer"],
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
            v1 = subprocess.run(["bash", str(VERIFY_IPA_SCRIPT), str(dev_ipa)], capture_output=True, text=True)
            self.assertEqual(v1.returncode, 0, v1.stdout + v1.stderr)

            # Production mode with custom scheme (emits warning, passes strict verify)
            prod_plist_path = tmp_path / "ProdInfo.plist"
            prod_plist_path.write_bytes(plistlib.dumps(base_plist(), fmt=plistlib.FMT_XML))
            env["MWDAT_TEAM_ID"] = "AB12CD34EF"
            env["MWDAT_CLIENT_TOKEN"] = "AR|555666777|E2E_SECRET_TOKEN_1"
            p2 = subprocess.run(
                [
                    sys.executable,
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
            v2 = subprocess.run(["bash", str(VERIFY_IPA_SCRIPT), str(prod_ipa)], capture_output=True, text=True)
            self.assertEqual(v2.returncode, 0, v2.stdout + v2.stderr)
            self.assertNotIn("E2E_SECRET_TOKEN_1", v2.stdout + v2.stderr)
            self.assertNotIn("AB12CD34EF", v2.stdout + v2.stderr)


class VerifyBlueprintTests(unittest.TestCase):
    def test_verify_blueprint_passes_on_repository(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(VERIFY_BLUEPRINT_SCRIPT)],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("0 failed", proc.stdout)


if __name__ == "__main__":
    unittest.main()
