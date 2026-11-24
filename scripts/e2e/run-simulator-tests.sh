#!/usr/bin/env bash
# Run the ReybainTests suites (see PLAN.md) on an iOS 18+ iPhone simulator.
# Works the same on a Mac and in CI (.github/workflows/e2e.yml).
#
#   scripts/e2e/run-simulator-tests.sh                   # every suite in ReybainTests (default)
#   SUITE=blueprint scripts/e2e/run-simulator-tests.sh   # only the Blueprint suites
#   TEST_RUNNER_REYBAIN_LIVE_GEMINI=1 scripts/e2e/run-simulator-tests.sh   # + real Gemini API
#   SIMULATOR_UDID=<udid> ...                            # pick the simulator yourself
#
# A new test file runs as soon as it is in the test target (scripts/pbxproj_files.py add ...);
# GeminiLiveSmokeTests skips itself unless TEST_RUNNER_REYBAIN_LIVE_GEMINI=1.
# With CI=true (GitHub Actions sets it) a skipped BlueprintPhotoLibraryE2ETests test fails the
# run, because the script grants Photos access and those tests must run (PLAN.md N1).
#
# The simulator cannot do Bluetooth (glasses) or the on-device MLX models; checklist tests that
# need the real Ray-Ban hardware are in PLAN.md section 7 (manual protocol).
set -euo pipefail
cd "$(dirname "$0")/../.."

SUITE="${SUITE:-all}"
case "$SUITE" in
  all|blueprint) ;;
  *) echo "error: SUITE must be 'all' (default) or 'blueprint', not '$SUITE'" >&2; exit 2 ;;
esac
DERIVED="${DERIVED_DATA:-DerivedData-sim}"
RESULT="${RESULT_BUNDLE:-build/E2E.xcresult}"

[ -f Config.xcconfig ] || cp Config.xcconfig.example Config.xcconfig
[ -f Reybain/Config/Config.swift ] || cp Reybain/Config/Config.swift.example Reybain/Config/Config.swift
BUNDLE_ID="$(awk -F= '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER/ { gsub(/[[:space:]]/, "", $2); print $2 }' Config.xcconfig)"
case "$BUNDLE_ID" in  # it goes into simctl arguments and an SQL statement below
  ""|*[!A-Za-z0-9.-]*) echo "error: unexpected PRODUCT_BUNDLE_IDENTIFIER '$BUNDLE_ID' in Config.xcconfig" >&2; exit 1 ;;
esac

# Newest iOS 18+ iPhone, preferring a Pro Max (the iPhone 15 Pro Max class this app targets).
UDID="${SIMULATOR_UDID:-}"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m or (int(m.group(1)), int(m.group(2))) < (18, 0):
        continue
    for d in devices:
        if d["name"].startswith("iPhone"):
            score = ((int(m.group(1)), int(m.group(2))), "Pro Max" in d["name"], "Pro" in d["name"])
            candidates.append((score, d["udid"], d["name"]))
candidates.sort()
print(candidates[-1][1] if candidates else "")
')"
fi
if [ -z "$UDID" ]; then
  echo "error: no iOS 18+ iPhone simulator available (xcrun simctl list devices)" >&2
  exit 1
fi
echo "Simulator: $(xcrun simctl list devices | grep "$UDID" | sed 's/^ *//')"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

pretty() { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify "$@"; else cat; fi; }
# Ad-hoc signing (CODE_SIGN_IDENTITY=-), NOT CODE_SIGNING_ALLOWED=NO: an unsigned simulator
# binary carries no entitlements, so every Keychain call fails with -34018 (errSecMissingEntitlement)
# and Wearables.configure() throws WearablesError.internalError. The test host app then traps at
# launch ("Call configure() before attempting to access Wearables!") before any test runs.
# Ad-hoc signing needs no certificate, account or provisioning profile on a simulator.
COMMON=(
  -project Reybain.xcodeproj
  -scheme Reybain
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED"
  -clonedSourcePackagesDirPath .spm
  -skipPackagePluginValidation
  -skipMacroValidation
  CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGNING_ALLOWED=YES
)

# Launch the app alone for 15 s and print its console (stdout + stderr) into $2.
# $1: label; any further arguments are SIMCTL_CHILD_*=value assignments for the app's environment.
# Sets LAUNCH_ALIVE=1 when the app was still running after 15 s (`simctl launch --console`
# returns as soon as the app exits).
launch_console() {
  local label="$1" log="$2"
  shift 2
  echo "::group::App launch console: $label (15 s)"
  mkdir -p build
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  env ${1+"$@"} xcrun simctl launch --console --terminate-running-process "$UDID" "$BUNDLE_ID" > "$log" 2>&1 &
  local pid=$!
  sleep 15
  if kill -0 "$pid" 2>/dev/null; then LAUNCH_ALIVE=1; else LAUNCH_ALIVE=0; fi
  kill "$pid" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  cat "$log" || true
  echo "(still running after 15 s: $([ "$LAUNCH_ALIVE" = 1 ] && echo yes || echo no))"
  echo "::endgroup::"
}

# 1. Normal launch. Informational (never fails the job): it shows the app's own startup
#    messages, e.g. "[ReybainApp] Failed to configure Wearables SDK: ...", which xcodebuild
#    does not forward when the test host dies at launch.
# 2. Launch with the glasses SDK left unconfigured (Debug builds honour the variable): the app
#    must not trap and must say why the glasses are off (PLAN.md N2 / T2.5). This one fails the job.
launch_smoke() {
  launch_console "normal" build/launch-console.log
  local log=build/launch-console-no-dat.log
  launch_console "REYBAIN_SIMULATE_DAT_CONFIG_FAILURE=1" "$log" SIMCTL_CHILD_REYBAIN_SIMULATE_DAT_CONFIG_FAILURE=1
  if grep -q "Fatal error" "$log" || [ "$LAUNCH_ALIVE" != 1 ]; then
    echo "::error::the app did not survive a launch without a configured glasses SDK (console above)"
    return 1
  fi
  if ! grep -q "SDK kính chưa khởi tạo được" "$log"; then
    echo "::error::no \"SDK kính chưa khởi tạo được\" line when launched without the glasses SDK (console above)"
    return 1
  fi
  echo "Launch without the glasses SDK: no trap, and the app reports \"SDK kính chưa khởi tạo được\"."
}

# When the test host dies at launch there is no test output at all; print what crashed.
dump_crash_reports() {
  echo "::group::Reybain crash reports"
  sleep 10   # ReportCrash writes the file a few seconds after the process dies
  ls -t "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | head -5 || true
  xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "Reybain"' 2>/dev/null | tail -40 || true
  local found=0 report
  while IFS= read -r report; do
    [ -n "$report" ] || continue
    found=1
    echo "== $report"
    python3 - "$report" <<'PY' || true
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
body = raw.split("\n", 1)[1] if raw.startswith("{") and "\n" in raw else raw
try:
    d = json.loads(body)
    print("exception:", d.get("exception"))
    print("termination:", d.get("termination"))
    print("asi:", d.get("asi"))
    images = d.get("usedImages", [])
    thread = d["threads"][d.get("faultingThread", 0)]
    for frame in thread["frames"][:25]:
        idx = frame.get("imageIndex")
        image = images[idx]["name"] if idx is not None and idx < len(images) else "?"
        print("  ", image, frame.get("symbol", "?"))
except Exception as e:
    print("(could not parse: %s)" % e)
    print(raw[:4000])
PY
  done < <(find "$HOME/Library/Logs/DiagnosticReports" -name 'Reybain*' -mmin -30 2>/dev/null | head -3)
  [ "$found" = 1 ] || echo "no Reybain crash report found"
  echo "::endgroup::"
}

# Photos access for BlueprintPhotoLibraryE2ETests (PLAN.md N1). On the iOS 26 simulator runtimes
# `simctl privacy grant photos` writes a TCC row with auth_version 1, which PhotoKit ignores:
# authorizationStatus stays .notDetermined and the tests skipped on every CI run. The row is
# rewritten the way AppleSimulatorUtils writes Photos grants (auth_value 2 = full access,
# auth_version 2); like that tool, nothing is restarted afterwards.
SIM_HOME="$(xcrun simctl getenv "$UDID" HOME 2>/dev/null || true)"
TCC_DB="${SIM_HOME:-$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data}/Library/TCC/TCC.db"
tcc() { sqlite3 -cmd ".timeout 5000" "$@"; }
photos_tcc_rows() {
  tcc -header -column "$TCC_DB" "SELECT service, client, client_type, auth_value, auth_reason, auth_version, flags
    FROM access WHERE service LIKE 'kTCCServicePhotos%' AND client = '$BUNDLE_ID';" 2>&1 || true
}
grant_photos_access() {
  echo "::group::Photos access for $BUNDLE_ID"
  xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID" || echo "warning: simctl could not grant Photos access"
  if [ -f "$TCC_DB" ]; then
    echo "TCC row written by simctl ($TCC_DB):"
    photos_tcc_rows
    tcc "$TCC_DB" "UPDATE access SET auth_value = 2, auth_version = 2
        WHERE service = 'kTCCServicePhotos' AND client = '$BUNDLE_ID' AND client_type = 0;
      INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags)
        SELECT 'kTCCServicePhotos', '$BUNDLE_ID', 0, 2, 2, 2, 0 WHERE NOT EXISTS (SELECT 1 FROM access
          WHERE service = 'kTCCServicePhotos' AND client = '$BUNDLE_ID' AND client_type = 0);" \
      || echo "warning: could not rewrite the Photos TCC row; the photo library tests may skip"
    echo "TCC row the tests run with:"
    photos_tcc_rows
  else
    echo "warning: no TCC database at $TCC_DB; the photo library tests will skip"
  fi
  echo "::endgroup::"
}

# xcbeautify prints a skipped test without its reason: show the reasons from the raw output,
# with the Photos TCC row as the tests left it (does test-without-building reinstall reset it?).
# With CI=true, returns 1 after the report when a BlueprintPhotoLibraryE2ETests test skipped
# (PLAN.md N1); skips in other suites never fail. xcodebuild prints two raw lines per skip:
#   .../BlueprintPhotoLibraryE2ETests.swift:20: -[ReybainTests.BlueprintPhotoLibraryE2ETests testX] : Test skipped - ...
#   Test Case '-[ReybainTests.BlueprintPhotoLibraryE2ETests testX]' skipped (0.062 seconds).
report_skips() {
  echo "::group::Skipped tests and why"
  grep -h -E "Test skipped|\[BlueprintPhotoLibraryE2ETests\]" build/test-output.log 2>/dev/null || echo "no skipped tests"
  echo "Photos TCC row after the run:"
  photos_tcc_rows
  echo "::endgroup::"
  [ "${CI:-}" = "true" ] || return 0
  local name list="" count=0
  while IFS= read -r name; do
    list="${list:+$list, }$name"
    count=$((count + 1))
  done < <(LC_ALL=C sed -n -E \
    -e "s/.*-\[([[:alnum:]_]+\.)?BlueprintPhotoLibraryE2ETests ([[:alnum:]_]+)] : Test skipped.*/\2/p" \
    -e "s/^Test Case '-\[([[:alnum:]_]+\.)?BlueprintPhotoLibraryE2ETests ([[:alnum:]_]+)]' skipped .*/\2/p" \
    build/test-output.log 2>/dev/null | LC_ALL=C sort -u)
  if [ "$count" -gt 0 ]; then
    echo "::error::BlueprintPhotoLibraryE2ETests skipped $count test(s) on CI: $list." \
      "These tests must run (PLAN.md N1); the reason and the Photos TCC row are in the" \
      "\"Skipped tests and why\" group above."
    return 1
  fi
  echo "CI skip check: no BlueprintPhotoLibraryE2ETests test was skipped."
}

xcodebuild build-for-testing "${COMMON[@]}" | pretty ${XCBEAUTIFY_ARGS:-}

# Install once and grant Photos access, so the real-photo-library tests run instead of skipping.
APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -type d -path '*-iphonesimulator/Reybain.app' | head -n 1)"
xcrun simctl install "$UDID" "$APP"
grant_photos_access
launch_smoke

# SUITE=all runs the whole ReybainTests target (no -only-testing list to keep in step).
ONLY=()
if [ "$SUITE" = "blueprint" ]; then
  for suite in BlueprintSolverTests BlueprintGeminiE2ETests BlueprintPhotoLibraryE2ETests GeminiLiveSmokeTests; do
    ONLY+=("-only-testing:ReybainTests/$suite")
  done
fi
echo "Test suites: $SUITE"

rm -rf "$RESULT"
mkdir -p "$(dirname "$RESULT")"
status=0
xcodebuild test-without-building "${COMMON[@]}" ${ONLY[@]+"${ONLY[@]}"} -resultBundlePath "$RESULT" \
  | tee build/test-output.log | pretty ${XCBEAUTIFY_ARGS:-} || status=$?
# Report first; a failed run still ends through dump_crash_reports, then the skip check fails it.
skip_status=0
report_skips || skip_status=$?
if [ "$status" -ne 0 ]; then
  dump_crash_reports
  exit 1
fi
if [ "$skip_status" -ne 0 ]; then
  exit 1
fi
