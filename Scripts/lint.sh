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
            grep -E '(^|: )(error|warning):' "$compiler_log" | sort -u
            tail -n 20 "$compiler_log"
            return 1
        fi
        echo "--- WARN: SwiftPM build sandbox is unavailable in this host sandbox; retrying compiler log without SwiftPM subprocess sandbox" >> "$compiler_log"
        swift build \
            --cache-path "$package_root/.build/swiftpm-cache" \
            --config-path "$package_root/.build/swiftpm-config" \
            --security-path "$package_root/.build/swiftpm-security" \
            --disable-automatic-resolution \
            --disable-sandbox \
            -v >> "$compiler_log" 2>&1 || { grep -E '(^|: )(error|warning):' "$compiler_log" | sort -u; return 1; }
    fi

    # SwiftPM's verbose build passes `-v` to swiftc, and SwiftLint hands those
    # arguments to SourceKit, which then prints the toolchain banner twice per
    # file — thousands of lines hiding the findings. Drop the flag from the log
    # (a copy, not `sed -i`: BSD and GNU sed disagree on its syntax, and the
    # GitHub runner puts GNU tools first on PATH).
    sed -E 's/ -v( |$)/\1/' "$compiler_log" > "$compiler_log.tmp" && mv "$compiler_log.tmp" "$compiler_log"

    # The module list is what the analyzer will cover.
    echo "modules with a swiftc invocation in $compiler_log:"
    sed -n 's/.*swiftc .*-module-name \([^ ]*\).*/\1/p' "$compiler_log" | sort | uniq -c
}

run_swiftlint_analyze() {
    analyze_log="$package_root/.build/swiftlint-analyze.log"
    # The files, not their directories: with `included:` in .swiftlint.yml a
    # directory argument stands for the whole included set, and two arguments
    # analyzed every file twice.
    analyzed_files=$(find "$package_root/Sources" "$package_root/Tools" -name '*.swift')
    expected_count=$(printf '%s\n' "$analyzed_files" | wc -l | tr -d ' ')
    # One argument per line of `find`: split on newlines only, and no globbing,
    # so a path with a space or a glyph stays whole (this is POSIX sh, no arrays).
    saved_ifs=$IFS
    IFS='
'
    set -f
    swift_package_plugin swiftlint analyze \
        --strict \
        --force-exclude \
        --compiler-log-path "$package_root/.build/swiftlint-compiler.log" \
        $analyzed_files > "$analyze_log" 2>&1
    analyze_status=$?
    set +f
    IFS=$saved_ifs
    # Everything but the per-file progress and SourceKit's banner: the findings.
    grep -v -E '^(Analyzing |Apple Swift version|Target: )' "$analyze_log"
    [ "$analyze_status" -eq 0 ] || return "$analyze_status"

    # A file whose compiler arguments are missing from the log is skipped
    # without a word and without a violation, so a pass is a pass only when
    # SwiftLint's own count matches the files it was given.
    analyzed_count=$(grep -o 'Done analyzing!.* in [0-9]* files\{0,1\}\.' "$analyze_log" | sed 's/.* in \([0-9]*\) file.*/\1/' | tail -1)
    if [ "$analyzed_count" != "$expected_count" ]; then
        echo "--- swiftlint analyze read ${analyzed_count:-0} of $expected_count files; the rest had no compiler arguments in the log"
        return 1
    fi
    echo "SwiftLint analyze passed on $analyzed_count files; full log: $analyze_log"
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
