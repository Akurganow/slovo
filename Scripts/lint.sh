#!/bin/sh
set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$package_root" || exit 1
mkdir -p .build/module-cache
mkdir -p .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security
export CLANG_MODULE_CACHE_PATH="$package_root/.build/module-cache"

failures=""

run_stage() {
    signature="$1"
    shift
    echo "=== lint: $signature ==="
    if "$@"; then
        echo "--- PASS: $signature"
    else
        echo "--- FAIL: $signature"
        failures="$failures$signature
"
    fi
}

swift_build_resolved() {
    build_log="$package_root/.build/swift-build-sandbox.log"
    if swift build \
        --cache-path "$package_root/.build/swiftpm-cache" \
        --config-path "$package_root/.build/swiftpm-config" \
        --security-path "$package_root/.build/swiftpm-security" \
        --disable-automatic-resolution \
        "$@" > "$build_log" 2>&1; then
        cat "$build_log"
        return 0
    fi

    build_status=$?
    cat "$build_log"
    if grep -q "sandbox_apply: Operation not permitted" "$build_log"; then
        echo "--- WARN: SwiftPM build sandbox is unavailable in this host sandbox; retrying without SwiftPM subprocess sandbox"
        swift build \
            --cache-path "$package_root/.build/swiftpm-cache" \
            --config-path "$package_root/.build/swiftpm-config" \
            --security-path "$package_root/.build/swiftpm-security" \
            --disable-automatic-resolution \
            --disable-sandbox \
            "$@"
        return $?
    fi
    return $build_status
}

swift_package_plugin() {
    plugin_log="$package_root/.build/swiftpm-plugin-sandbox.log"
    if swift package \
        --cache-path "$package_root/.build/swiftpm-cache" \
        --config-path "$package_root/.build/swiftpm-config" \
        --security-path "$package_root/.build/swiftpm-security" \
        --disable-automatic-resolution \
        plugin \
        --allow-writing-to-package-directory \
        --allow-network-connections none \
        "$@" > "$plugin_log" 2>&1; then
        cat "$plugin_log"
        return 0
    fi

    plugin_status=$?
    cat "$plugin_log"
    if grep -q "sandbox_apply: Operation not permitted" "$plugin_log"; then
        echo "--- WARN: SwiftPM plugin sandbox is unavailable in this host sandbox; retrying without SwiftPM subprocess sandbox"
        swift package \
            --cache-path "$package_root/.build/swiftpm-cache" \
            --config-path "$package_root/.build/swiftpm-config" \
            --security-path "$package_root/.build/swiftpm-security" \
            --disable-automatic-resolution \
            --disable-sandbox \
            plugin \
            --allow-writing-to-package-directory \
            --allow-network-connections none \
            "$@"
        return $?
    fi
    return $plugin_status
}

generate_swiftlint_compiler_log() {
    if swift build \
        --cache-path "$package_root/.build/swiftpm-cache" \
        --config-path "$package_root/.build/swiftpm-config" \
        --security-path "$package_root/.build/swiftpm-security" \
        --disable-automatic-resolution \
        -v > "$package_root/.build/swiftlint-compiler.log" 2>&1; then
        return 0
    fi

    if grep -q "sandbox_apply: Operation not permitted" "$package_root/.build/swiftlint-compiler.log"; then
        echo "--- WARN: SwiftPM build sandbox is unavailable in this host sandbox; retrying compiler log without SwiftPM subprocess sandbox" >> "$package_root/.build/swiftlint-compiler.log"
        swift build \
            --cache-path "$package_root/.build/swiftpm-cache" \
            --config-path "$package_root/.build/swiftpm-config" \
            --security-path "$package_root/.build/swiftpm-security" \
            --disable-automatic-resolution \
            --disable-sandbox \
            -v >> "$package_root/.build/swiftlint-compiler.log" 2>&1
        return $?
    fi
    return 1
}

run_swiftlint_analyze() {
    analyze_log="$package_root/.build/swiftlint-analyze.log"
    if swift_package_plugin swiftlint analyze \
        --quiet \
        --strict \
        --force-exclude \
        --compiler-log-path "$package_root/.build/swiftlint-compiler.log" > "$analyze_log" 2>&1; then
        echo "SwiftLint analyze passed; full log: $analyze_log"
        return 0
    fi

    cat "$analyze_log"
    return 1
}

run_stage "explicit-target-imports" swift_build_resolved \
    --explicit-target-dependency-import-check error

for script in Scripts/*.sh; do
    run_stage "bash-syntax:$script" bash -n "$script"
done

run_stage "plist-lint" plutil -lint Resources/Info.plist loqui.entitlements

run_stage "swiftlint-strict" swift_package_plugin swiftlint
run_stage "swiftlint-compiler-log" generate_swiftlint_compiler_log
run_stage "swiftlint-analyze" run_swiftlint_analyze

if [ -n "$failures" ]; then
    echo ""
    echo "=== lint: COMPLETE failure set ==="
    printf '%s' "$failures"
    exit 1
fi

echo ""
echo "=== lint: all required stages passed ==="
