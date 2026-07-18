#!/usr/bin/env bash
set -euo pipefail

# Release packaging in two automated phases. The ONLY manual step is stapling the
# notarization ticket, which must run on a Mac that can reach Apple's notarization
# service; everything else here is scripted and re-runnable:
#
#   Scripts/sign-and-notarize.sh app        # build + sign + notarize $APP_NAME.app
#   xcrun stapler staple .build/dist/Slovo.app          # manual, on a networked Mac
#   Scripts/sign-and-notarize.sh dmg        # package the stapled app -> signed, notarized DMG
#   xcrun stapler staple .build/dist/Slovo.dmg          # manual, on a networked Mac
#
# SIGNING_IDENTITY is required. Notarization needs credentials from one of two
# sources: NOTARY_PROFILE (a notarytool keychain profile, used locally) OR an App
# Store Connect API key via NOTARY_KEY_P8 (path to the .p8), NOTARY_KEY_ID, and
# NOTARY_ISSUER_ID (used by CI, which has no keychain). Without either a phase
# stops after signing.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-Slovo}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DRY_RUN="${DRY_RUN:-0}"
DIST_DIR="$ROOT/.build/dist"
SWIFTPM_CACHE_DIR="$ROOT/.build/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$ROOT/.build/swiftpm-config"
SWIFTPM_SECURITY_DIR="$ROOT/.build/swiftpm-security"

PHASE="${1:-}"
case "$PHASE" in
    app|dmg) ;;
    *)
        echo "usage: $(basename "$0") <app|dmg>" >&2
        echo "  app   build, sign, and notarize \$APP_NAME.app (then staple it manually)" >&2
        echo "  dmg   package the stapled \$APP_NAME.app into a signed, notarized DMG (then staple it manually)" >&2
        exit 64
        ;;
esac

validate_app_name() {
    local name="$1"
    case "$name" in
        ""|"."|".."|*/*|*..*)
            echo "APP_NAME must be a simple bundle basename" >&2
            exit 64
            ;;
    esac
}

validate_app_name "$APP_NAME"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "SIGNING_IDENTITY is required; use a stable dev or Developer ID identity" >&2
    exit 64
fi

if [[ "$SIGNING_IDENTITY" == "-" && "${ALLOW_AD_HOC_SIGNING:-0}" != "1" ]]; then
    echo "Ad-hoc signing requires ALLOW_AD_HOC_SIGNING=1 and cannot prove TCC persistence" >&2
    exit 64
fi

# Notarization credential source, resolved once for both phases. The keychain
# profile takes precedence so local runs behave exactly as before; otherwise any
# App Store Connect API-key variable selects the API-key path. A partial API-key
# set is rejected rather than silently skipping notarization, so a misconfigured
# run never ships an unnotarized artifact. An empty array means "sign only".
notary_submit_args=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_submit_args=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_P8:-}" || -n "${NOTARY_KEY_ID:-}" || -n "${NOTARY_ISSUER_ID:-}" ]]; then
    if [[ -z "${NOTARY_KEY_P8:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
        echo "App Store Connect API-key notarization needs NOTARY_KEY_P8, NOTARY_KEY_ID, and NOTARY_ISSUER_ID together" >&2
        exit 64
    fi
    notary_submit_args=(--key "$NOTARY_KEY_P8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'DRY-RUN'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

APP_PATH="$DIST_DIR/$APP_NAME.app"
CONTENTS_PATH="$APP_PATH/Contents"
BINARY_PATH="$ROOT/.build/$CONFIGURATION/slovo"
APP_ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_STAGING="$DIST_DIR/$APP_NAME-dmg-staging"

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
        echo "Expected exactly one Sparkle.framework under $ROOT/.build/artifacts, found $count" >&2
        exit 65
    fi
}

build_app() {
    if [[ -e "$APP_PATH" ]]; then
        echo "$APP_PATH already exists; move it aside before packaging to avoid stale signed artifacts" >&2
        exit 65
    fi
    if [[ -e "$APP_ZIP_PATH" ]]; then
        echo "$APP_ZIP_PATH already exists; move it aside before packaging to avoid stale signed artifacts" >&2
        exit 65
    fi

    run install -d "$SWIFTPM_CACHE_DIR" "$SWIFTPM_CONFIG_DIR" "$SWIFTPM_SECURITY_DIR"
    run swift build \
        --cache-path "$SWIFTPM_CACHE_DIR" \
        --config-path "$SWIFTPM_CONFIG_DIR" \
        --security-path "$SWIFTPM_SECURITY_DIR" \
        --disable-automatic-resolution \
        -c "$CONFIGURATION"

    run install -d "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
    run install "$BINARY_PATH" "$CONTENTS_PATH/MacOS/slovo"
    run install -m 0644 "$ROOT/Resources/Info.plist" "$CONTENTS_PATH/Info.plist"

    # Compile the macOS 26 app icon (theme-adaptive .icon -> Assets.car + legacy .icns).
    local icon_build="$DIST_DIR/icon"
    run install -d "$icon_build"
    run xcrun actool "$ROOT/Resources/$APP_NAME.icon" --app-icon "$APP_NAME" --compile "$icon_build" \
        --output-partial-info-plist "$icon_build/partial.plist" \
        --minimum-deployment-target 26.0 --platform macosx --target-device mac \
        --output-format human-readable-text
    run install -m 0644 "$icon_build/Assets.car" "$CONTENTS_PATH/Resources/Assets.car"
    run install -m 0644 "$icon_build/$APP_NAME.icns" "$CONTENTS_PATH/Resources/$APP_NAME.icns"

    # Embed Sparkle for auto-update. ditto preserves the framework's internal
    # symlinks and executable bits — a flattening copy breaks the bundle.
    local sparkle_framework
    sparkle_framework="$(sparkle_framework_path)"
    run ditto "$sparkle_framework" "$CONTENTS_PATH/Frameworks/Sparkle.framework"

    # Not sandboxed → Sparkle's XPC services are unused; strip them from the
    # staged copy to shrink the signing/notarization surface. Drop the versioned
    # dir and the now-dangling framework-root symlink so codesign --strict sees
    # no broken link.
    run rm -r "$CONTENTS_PATH/Frameworks/Sparkle.framework/Versions/Current/XPCServices"
    run rm "$CONTENTS_PATH/Frameworks/Sparkle.framework/XPCServices"

    # Inside-out signing: Sparkle's nested helpers, then the framework, before
    # the app below. Deep signing mis-signs the Autoupdate helper and fails only
    # at notarization (Sparkle #1641), so each piece is signed explicitly;
    # Sparkle code carries no entitlements.
    local sparkle_codesign_args=(--force --options runtime)
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        sparkle_codesign_args+=(--timestamp)
    fi
    run codesign "${sparkle_codesign_args[@]}" --sign "$SIGNING_IDENTITY" "$CONTENTS_PATH/Frameworks/Sparkle.framework/Versions/Current/Autoupdate"
    run codesign "${sparkle_codesign_args[@]}" --sign "$SIGNING_IDENTITY" "$CONTENTS_PATH/Frameworks/Sparkle.framework/Versions/Current/Updater.app"
    run codesign "${sparkle_codesign_args[@]}" --sign "$SIGNING_IDENTITY" "$CONTENTS_PATH/Frameworks/Sparkle.framework"

    local codesign_args=(--force --options runtime --entitlements "$ROOT/slovo.entitlements")
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        codesign_args+=(--timestamp)
    fi
    run codesign "${codesign_args[@]}" --sign "$SIGNING_IDENTITY" "$APP_PATH"

    if [[ ${#notary_submit_args[@]} -gt 0 ]]; then
        run ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"
        run xcrun notarytool submit "$APP_ZIP_PATH" "${notary_submit_args[@]}" --wait
    fi

    echo "Next: staple the app on a Mac that can reach Apple notarization, then run '$0 dmg':" >&2
    echo "  xcrun stapler staple \"$APP_PATH\"" >&2
    echo "$APP_PATH"
}

build_dmg() {
    if [[ ! -d "$APP_PATH" ]]; then
        echo "$APP_PATH not found; run '$0 app' and staple it first" >&2
        exit 65
    fi
    if [[ -e "$DMG_STAGING" || -e "$DMG_PATH" ]]; then
        echo "$DMG_STAGING or $DMG_PATH already exists; move it aside before packaging to avoid stale artifacts" >&2
        exit 65
    fi

    run install -d "$DMG_STAGING"
    run ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
    run ln -s /Applications "$DMG_STAGING/Applications"
    run hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -format UDZO "$DMG_PATH"

    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        run codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    fi

    if [[ ${#notary_submit_args[@]} -gt 0 ]]; then
        run xcrun notarytool submit "$DMG_PATH" "${notary_submit_args[@]}" --wait
    fi

    echo "Next: staple the DMG on a Mac that can reach Apple notarization, then publish it:" >&2
    echo "  xcrun stapler staple \"$DMG_PATH\"" >&2
    echo "$DMG_PATH"
}

case "$PHASE" in
    app) build_app ;;
    dmg) build_dmg ;;
esac
