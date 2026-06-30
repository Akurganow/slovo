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

if [[ -e "$APP_PATH" ]]; then
    echo "$APP_PATH already exists; move it aside before packaging to avoid stale signed artifacts" >&2
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
    ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
    run ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    run xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    run xcrun stapler staple "$APP_PATH"
fi

echo "$APP_PATH"
