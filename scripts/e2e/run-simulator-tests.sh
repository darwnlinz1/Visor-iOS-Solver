#!/usr/bin/env bash
# Run the Blueprint end-to-end suites (see PLAN.md) on an iOS 18+ iPhone simulator.
# Works the same on a Mac and in CI (.github/workflows/e2e.yml).
#
#   scripts/e2e/run-simulator-tests.sh                 # Blueprint suites (default)
#   SUITE=all scripts/e2e/run-simulator-tests.sh       # every test in OpenVisionTests
#   TEST_RUNNER_OPENVISION_LIVE_GEMINI=1 scripts/e2e/run-simulator-tests.sh   # + real Gemini API
#   SIMULATOR_UDID=<udid> ...                          # pick the simulator yourself
#
# The simulator cannot do Bluetooth (glasses) or the on-device MLX models; checklist tests that
# need the real Ray-Ban hardware are in PLAN.md section 7 (manual protocol).
set -euo pipefail
cd "$(dirname "$0")/../.."

SUITE="${SUITE:-blueprint}"
DERIVED="${DERIVED_DATA:-DerivedData-sim}"
RESULT="${RESULT_BUNDLE:-build/E2E.xcresult}"

[ -f Config.xcconfig ] || cp Config.xcconfig.example Config.xcconfig
[ -f OpenVision/Config/Config.swift ] || cp OpenVision/Config/Config.swift.example OpenVision/Config/Config.swift
BUNDLE_ID="$(awk -F= '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER/ { gsub(/[[:space:]]/, "", $2); print $2 }' Config.xcconfig)"

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
# META_APP_ID=0: the Meta SDK treats 0 / empty as "Developer Mode, no app ID" and skips
# attestation, which cannot run on a simulator. With the example placeholder (or a real ID) the
# test host app aborts at launch: Wearables.configure() fails, then GlassesManager.shared hits
# "Call configure() before attempting to access Wearables!". A command-line setting overrides
# Config.xcconfig, so a developer's real config is untouched.
COMMON=(
  -project OpenVision.xcodeproj
  -scheme OpenVision
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED"
  -clonedSourcePackagesDirPath .spm
  -skipPackagePluginValidation
  -skipMacroValidation
  CODE_SIGNING_ALLOWED=NO
  META_APP_ID=0
)

# When the test host dies at launch there is no test output at all; print what crashed.
dump_crash_reports() {
  echo "::group::OpenVision crash reports"
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
  done < <(find "$HOME/Library/Logs/DiagnosticReports" -name 'OpenVision*' -mmin -60 2>/dev/null | head -3)
  [ "$found" = 1 ] || echo "no OpenVision crash report found"
  echo "::endgroup::"
}

xcodebuild build-for-testing "${COMMON[@]}" | pretty ${XCBEAUTIFY_ARGS:-}

# Install once and grant Photos access, so the real-photo-library tests run instead of skipping.
APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -type d -path '*-iphonesimulator/OpenVision.app' | head -n 1)"
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID" || echo "warning: could not grant Photos access; library tests will skip"

ONLY=()
if [ "$SUITE" = "blueprint" ]; then
  for suite in BlueprintSolverTests BlueprintGeminiE2ETests BlueprintPhotoLibraryE2ETests GeminiLiveSmokeTests; do
    ONLY+=("-only-testing:OpenVisionTests/$suite")
  done
fi

rm -rf "$RESULT"
mkdir -p "$(dirname "$RESULT")"
if ! xcodebuild test-without-building "${COMMON[@]}" ${ONLY[@]+"${ONLY[@]}"} -resultBundlePath "$RESULT" | pretty ${XCBEAUTIFY_ARGS:-}; then
  dump_crash_reports
  exit 1
fi
