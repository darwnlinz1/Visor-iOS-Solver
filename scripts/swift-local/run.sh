#!/usr/bin/env bash
# Run the pure-Swift logic tests on Linux with SwiftPM, without Xcode (see PLAN.md §0 and §11).
#
#   scripts/swift-local/run.sh                  # every pure suite
#   scripts/swift-local/run.sh VietMathSpeech   # only test files whose name contains this text
#
# Sources: every *.swift in OpenVision/Services/Speech (that folder must stay pure: Foundation only).
# Tests:   OpenVisionTests/<Prefix>*Tests.swift for the prefixes below. Test files keep
#          `@testable import OpenVision`, so the same files also run in the iOS target on CI.
# The package lives OUTSIDE the repo (one per checkout/worktree) and keeps .build for fast reruns.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
WORK="${SWIFT_LOCAL_DIR:-$ROOT/../.swift-local/$(basename "$ROOT")}"
FILTER="${1:-}"
SRC_DIR="$ROOT/OpenVision/Services/Speech"
PREFIXES=(VietMath AnswerFormat ReplyAssembler PromptV2 ReadingEngine ReadingCommand ReadingModel MathPretty)

command -v swift >/dev/null || { echo "error: swift toolchain not found" >&2; exit 1; }
shopt -s nullglob
sources=("$SRC_DIR"/*.swift)
[ ${#sources[@]} -gt 0 ] || { echo "error: no Swift files in $SRC_DIR" >&2; exit 1; }

rm -rf "$WORK/Sources" "$WORK/Tests"
mkdir -p "$WORK/Sources/OpenVision" "$WORK/Tests/OpenVisionTests"
for f in "${sources[@]}"; do ln -s "$f" "$WORK/Sources/OpenVision/"; done

tests=0
for prefix in "${PREFIXES[@]}"; do
  for f in "$ROOT"/OpenVisionTests/"$prefix"*Tests.swift; do
    name="$(basename "$f")"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
    ln -s "$f" "$WORK/Tests/OpenVisionTests/$name"
    tests=$((tests + 1))
  done
done

cat > "$WORK/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "OpenVisionLocal",
    targets: [
        .target(name: "OpenVision"),
        .testTarget(name: "OpenVisionTests", dependencies: ["OpenVision"]),
    ]
)
EOF

cd "$WORK"
echo "swift-local: ${#sources[@]} source file(s), $tests test file(s) in $WORK"
if [ "$tests" -eq 0 ]; then
  swift build
else
  swift test
fi
