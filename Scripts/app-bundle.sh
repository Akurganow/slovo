# Sourced by Scripts/build_and_run.sh and Scripts/sign-and-notarize.sh, so the
# dev bundle and the release bundle are staged and signed by the same lines.
# The caller sets ROOT, APP_NAME and DRY_RUN and defines run().

# Locate the single Sparkle.framework SwiftPM unpacks under .build/artifacts.
# Real staging demands exactly one (zero/multiple is a setup error worth
# stopping for); a DRY_RUN plan falls back to the canonical artifact path so the
# printed plan stays stable on machines that have not fetched the artifact.
sparkle_framework_path() {
    local canonical found count
    canonical="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    found="$(find "$ROOT/.build/artifacts" -type d -name "Sparkle.framework" 2>/dev/null || true)"
    count="$(printf '%s\n' "$found" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$count" == "1" ]]; then
        printf '%s\n' "$found"
    elif [[ "$DRY_RUN" == "1" ]]; then
        printf '%s\n' "$canonical"
    else
        echo "Expected exactly one Sparkle.framework under $ROOT/.build/artifacts, found $count (run swift build first / clear stale artifacts)" >&2
        exit 65
    fi
}

# Locate the macOS slice of SQLCipher.xcframework, with the same
# one-or-stop/DRY_RUN contract as the Sparkle twin above. Every platform slice
# carries a SQLCipher.framework, so the path filter picks the macOS one — the
# maccatalyst slice has no "macos-" path component and is excluded by it.
sqlcipher_framework_path() {
    local canonical found count
    canonical="$ROOT/.build/artifacts/sqlcipher.swift/SQLCipher/SQLCipher.xcframework/macos-arm64_x86_64/SQLCipher.framework"
    found="$(find "$ROOT/.build/artifacts" -type d -path "*/macos-*/*" -name "SQLCipher.framework" 2>/dev/null || true)"
    count="$(printf '%s\n' "$found" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$count" == "1" ]]; then
        printf '%s\n' "$found"
    elif [[ "$DRY_RUN" == "1" ]]; then
        printf '%s\n' "$canonical"
    else
        echo "Expected exactly one macOS SQLCipher.framework under $ROOT/.build/artifacts, found $count (run swift build first / clear stale artifacts)" >&2
        exit 65
    fi
}

# SwiftPM's resource bundle is flat under the native build system and a macOS
# bundle with Contents/Resources under Swift Build, its default from
# swift-6.4.0-RELEASE (swift-package-manager, Sources/CoreCommands/Options.swift).
bundle_resource_dir() {
    if [[ -d "$1/Contents/Resources" ]]; then
        printf '%s\n' "$1/Contents/Resources"
    else
        printf '%s\n' "$1"
    fi
}

# Everything in Contents except the binary and Info.plist, staged before
# signing so the seal covers it.
# $1 = SwiftPM bin directory, $2 = Contents directory, $3 = icon scratch directory.
stage_bundle_contents() {
    local bin_dir="$1" contents="$2" icon_build="$3"
    local core_resources cue_resource sparkle_framework sqlcipher_framework

    # PromptExampleCatalog resolves the SlovoCore resource bundle from
    # Contents/Resources; a missing bundle degrades every prompt to example-free.
    run ditto "$bin_dir/slovo_SlovoCore.bundle" "$contents/Resources/slovo_SlovoCore.bundle"
    core_resources="$(bundle_resource_dir "$contents/Resources/slovo_SlovoCore.bundle")"
    for cue_resource in start.wav end.wav error.wav; do
        run test -f "$core_resources/AudioCues/$cue_resource"
    done

    # Compile the theme-adaptive app icon (.icon -> Assets.car + legacy .icns).
    run install -d "$icon_build"
    run xcrun actool "$ROOT/Resources/$APP_NAME.icon" --app-icon "$APP_NAME" --compile "$icon_build" \
        --output-partial-info-plist "$icon_build/partial.plist" \
        --minimum-deployment-target 15.0 --platform macosx --target-device mac \
        --output-format human-readable-text
    run install -m 0644 "$icon_build/Assets.car" "$contents/Resources/Assets.car"
    run install -m 0644 "$icon_build/$APP_NAME.icns" "$contents/Resources/$APP_NAME.icns"

    run install -m 0644 "$ROOT/THIRD-PARTY-NOTICES.md" "$contents/Resources/THIRD-PARTY-NOTICES.md"

    # ditto preserves the framework's internal symlinks and executable bits — a
    # flattening copy breaks the bundle. Not sandboxed → Sparkle's XPC services
    # are unused; strip the versioned dir and the now-dangling root symlink so
    # codesign --strict sees no broken link.
    sparkle_framework="$(sparkle_framework_path)"
    run ditto "$sparkle_framework" "$contents/Frameworks/Sparkle.framework"
    run rm -r "$contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices"
    run rm "$contents/Frameworks/Sparkle.framework/XPCServices"

    # The binary loads SQLCipher through @executable_path/../Frameworks.
    sqlcipher_framework="$(sqlcipher_framework_path)"
    run ditto "$sqlcipher_framework" "$contents/Frameworks/SQLCipher.framework"
}

# Inside-out signing: Sparkle's nested helpers, then the frameworks; the caller
# signs the app last. Deep signing mis-signs the Autoupdate helper and fails
# only at notarization (Sparkle #1641). Framework code carries no entitlements.
# $1 = Contents directory, the rest = codesign arguments ending in --sign <identity>.
sign_bundle_frameworks() {
    local contents="$1"
    shift
    run codesign "$@" "$contents/Frameworks/Sparkle.framework/Versions/Current/Autoupdate"
    run codesign "$@" "$contents/Frameworks/Sparkle.framework/Versions/Current/Updater.app"
    run codesign "$@" "$contents/Frameworks/Sparkle.framework"
    run codesign "$@" "$contents/Frameworks/SQLCipher.framework"
}
