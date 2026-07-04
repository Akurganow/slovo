#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-Slovo}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DRY_RUN="${DRY_RUN:-0}"
DIST_DIR="$ROOT/.build/dist"
SWIFTPM_CACHE_DIR="$ROOT/.build/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$ROOT/.build/swiftpm-config"
SWIFTPM_SECURITY_DIR="$ROOT/.build/swiftpm-security"

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
ICON_BUILD="$DIST_DIR/icon"
run install -d "$ICON_BUILD"
run xcrun actool "$ROOT/Resources/$APP_NAME.icon" --app-icon "$APP_NAME" --compile "$ICON_BUILD" \
    --output-partial-info-plist "$ICON_BUILD/partial.plist" \
    --minimum-deployment-target 26.0 --platform macosx --target-device mac \
    --output-format human-readable-text
run install -m 0644 "$ICON_BUILD/Assets.car" "$CONTENTS_PATH/Resources/Assets.car"
run install -m 0644 "$ICON_BUILD/$APP_NAME.icns" "$CONTENTS_PATH/Resources/$APP_NAME.icns"

CODESIGN_ARGS=(
    --force
    --options runtime
    --entitlements "$ROOT/slovo.entitlements"
)

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    CODESIGN_ARGS+=(--timestamp)
fi

run codesign "${CODESIGN_ARGS[@]}" --sign "$SIGNING_IDENTITY" "$APP_PATH"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    run ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"
    run xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    run xcrun stapler staple "$APP_PATH"
fi

# Package into a distributable DMG (app plus a drag-to-Applications shortcut).
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_STAGING="$DIST_DIR/$APP_NAME-dmg-staging"
if [[ -e "$DMG_STAGING" || -e "$DMG_PATH" ]]; then
    echo "$DMG_STAGING or $DMG_PATH already exists; move it aside before packaging to avoid stale artifacts" >&2
    exit 65
fi
run install -d "$DMG_STAGING"
run cp -R "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
run ln -s /Applications "$DMG_STAGING/Applications"
run hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -format UDZO "$DMG_PATH"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    run codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    run xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    # Stapling reaches Apple CloudKit, whose cert pinning a TLS-inspecting proxy
    # (e.g. company Zscaler) breaks. Notarization already succeeded, so stapling is
    # best-effort: a notarized-but-un-stapled build still passes Gatekeeper online.
    run xcrun stapler staple "$DMG_PATH" \
        || echo "WARNING: stapling failed (likely a TLS-inspecting proxy); the DMG is notarized and passes Gatekeeper with network." >&2
fi

echo "$DMG_PATH"
