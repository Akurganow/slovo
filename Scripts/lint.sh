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
    swift build \
        --cache-path "$package_root/.build/swiftpm-cache" \
        --config-path "$package_root/.build/swiftpm-config" \
        --security-path "$package_root/.build/swiftpm-security" \
        --disable-automatic-resolution \
        "$@" > "$build_log" 2>&1
    build_status=$?
    cat "$build_log"
    [ "$build_status" -eq 0 ] && return 0
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
    return "$build_status"
}

swift_package_plugin() {
    plugin_log="$package_root/.build/swiftpm-plugin-sandbox.log"
    swift package \
        --cache-path "$package_root/.build/swiftpm-cache" \
        --config-path "$package_root/.build/swiftpm-config" \
        --security-path "$package_root/.build/swiftpm-security" \
        --disable-automatic-resolution \
        plugin \
        --allow-writing-to-package-directory \
        --allow-network-connections none \
        "$@" > "$plugin_log" 2>&1
    plugin_status=$?
    cat "$plugin_log"
    [ "$plugin_status" -eq 0 ] && return 0
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
    return "$plugin_status"
}

generate_swiftlint_compiler_log() {
    compiler_log="$package_root/.build/swiftlint-compiler.log"

    # `swiftlint analyze` takes a file's compiler arguments from the
    # `swiftc … -module-name …` line SwiftPM prints for that file's module, and
    # runs NO analyzer rule on a file whose line is missing — silently under
    # --quiet. SwiftPM prints a compile command only when it runs it, and after
    # the stages above every module is up to date, so a bare `swift build -v`
    # would log nothing and the analyze stage would pass empty. Touching the
    # package's own sources makes every one of its modules recompile (llbuild
    # invalidates on mtime); dependencies stay warm, since only these files are
    # analyzed. Tests/ is left out on purpose: SourceKit crashes (exit 11)
    # expanding the Swift Testing peer macros while type-checking a test file
    # for the analyzer, so the test targets are neither built here nor analyzed.
    find Sources Tools -name '*.swift' -exec touch {} +

    if ! swift build \
        --cache-path "$package_root/.build/swiftpm-cache" \
        --config-path "$package_root/.build/swiftpm-config" \
        --security-path "$package_root/.build/swiftpm-security" \
        --disable-automatic-resolution \
        -v > "$compiler_log" 2>&1; then
        if ! grep -q "sandbox_apply: Operation not permitted" "$compiler_log"; then
            cat "$compiler_log"
            return 1
        fi
        echo "--- WARN: SwiftPM build sandbox is unavailable in this host sandbox; retrying compiler log without SwiftPM subprocess sandbox" >> "$compiler_log"
        swift build \
            --cache-path "$package_root/.build/swiftpm-cache" \
            --config-path "$package_root/.build/swiftpm-config" \
            --security-path "$package_root/.build/swiftpm-security" \
            --disable-automatic-resolution \
            --disable-sandbox \
            -v >> "$compiler_log" 2>&1 || { cat "$compiler_log"; return 1; }
    fi

    # A log SwiftLint cannot read must fail HERE, not let the analyze stage pass
    # vacuously. The module list is what the analyzer will cover.
    echo "modules with a swiftc invocation in $compiler_log:"
    sed -n 's/.*swiftc .*-module-name \([^ ]*\).*/\1/p' "$compiler_log" | sort | uniq -c
    if ! grep -q 'swiftc .*-module-name ' "$compiler_log"; then
        echo "--- no swiftc invocation in $compiler_log; swiftlint analyze would skip every file"
        return 1
    fi
}

run_swiftlint_analyze() {
    analyze_log="$package_root/.build/swiftlint-analyze.log"
    if swift_package_plugin swiftlint analyze \
        --strict \
        --force-exclude \
        --compiler-log-path "$package_root/.build/swiftlint-compiler.log" \
        "$package_root/Sources" "$package_root/Tools" > "$analyze_log" 2>&1; then
        # Everything but the per-file progress: skipped files and issues.
        grep -v -E '^(Collecting|Linting) ' "$analyze_log"
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

run_stage "plist-lint" plutil -lint Resources/Info.plist slovo.entitlements

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
