#!/bin/sh
# AC-8 — non-masking diagnostic (diagnose-all -> fix-all).
#
# Runs the full gate WITHOUT fail-fast and aggregates the COMPLETE failure set.
# Build, test, and strict lint are captured independently so one failing stage
# never hides the others.
set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$package_root" || exit 1
mkdir -p .build/module-cache .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security
export CLANG_MODULE_CACHE_PATH="$package_root/.build/module-cache"

failures=""

run_stage() {
    # $1 = stable signature, rest = command
    signature="$1"
    shift
    echo "=== diagnose: $signature ==="
    if "$@"; then
        echo "--- PASS: $signature"
    else
        echo "--- FAIL: $signature"
        failures="$failures$signature
"
    fi
}

run_stage "swift-build" swift build \
    --cache-path "$package_root/.build/swiftpm-cache" \
    --config-path "$package_root/.build/swiftpm-config" \
    --security-path "$package_root/.build/swiftpm-security" \
    --disable-automatic-resolution
run_stage "swift-test" swift test \
    --cache-path "$package_root/.build/swiftpm-cache" \
    --config-path "$package_root/.build/swiftpm-config" \
    --security-path "$package_root/.build/swiftpm-security" \
    --disable-automatic-resolution
run_stage "cleanup-benchmark-cli" Scripts/check-cleanup-benchmark-cli.sh
run_stage "strict-lint" Scripts/lint.sh

if [ -n "$failures" ]; then
    echo ""
    echo "=== diagnose: COMPLETE failure set ==="
    printf '%s' "$failures"
    exit 1
fi

echo ""
echo "=== diagnose: all stages passed ==="
exit 0
