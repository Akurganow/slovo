#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Slovo"
PROCESS_NAME="slovo"
BUNDLE_ID="com.slovo.app"
SUBSYSTEM="com.slovo.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CACHE_DIR="$ROOT_DIR/.build/swiftpm-cache"
BUILD_CONFIG_DIR="$ROOT_DIR/.build/swiftpm-config"
BUILD_SECURITY_DIR="$ROOT_DIR/.build/swiftpm-security"
RUN_DIR="$ROOT_DIR/.build/dev-run"
APP_BUNDLE="$RUN_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PROCESS_NAME"

build_app() {
  mkdir -p "$BUILD_CACHE_DIR" "$BUILD_CONFIG_DIR" "$BUILD_SECURITY_DIR"
  swift build \
    --cache-path "$BUILD_CACHE_DIR" \
    --config-path "$BUILD_CONFIG_DIR" \
    --security-path "$BUILD_SECURITY_DIR" \
    --disable-automatic-resolution \
    --product "$PROCESS_NAME"
}

# Locate the single Sparkle.framework SwiftPM unpacks under .build/artifacts.
# Mirrors the release script's discovery (Scripts/sign-and-notarize.sh) minus its
# DRY_RUN fallback — the dev launcher always stages for real — and uses the same
# count-and-fail idiom as resolve_signing_identity.
sparkle_framework_path() {
  local found count
  found="$(find "$ROOT_DIR/.build/artifacts" -type d -name "Sparkle.framework" 2>/dev/null || true)"
  count="$(printf '%s\n' "$found" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" != "1" ]]; then
    echo "expected exactly one Sparkle.framework under .build/artifacts, found $count (run swift build first / clear stale artifacts)" >&2
    exit 65
  fi
  printf '%s\n' "$found"
}

stage_bundle() {
  local build_binary
  build_binary="$(swift build \
    --cache-path "$BUILD_CACHE_DIR" \
    --config-path "$BUILD_CONFIG_DIR" \
    --security-path "$BUILD_SECURITY_DIR" \
    --disable-automatic-resolution \
    --show-bin-path)/$PROCESS_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"

  # Compile the macOS 26 app icon (theme-adaptive .icon -> Assets.car + legacy .icns).
  local icon_build="$RUN_DIR/icon"
  rm -rf "$icon_build"
  mkdir -p "$icon_build"
  xcrun actool "$ROOT_DIR/Resources/Slovo.icon" --app-icon "$APP_NAME" --compile "$icon_build" \
    --output-partial-info-plist "$icon_build/partial.plist" \
    --minimum-deployment-target 26.0 --platform macosx --target-device mac \
    --output-format human-readable-text >/dev/null
  cp "$icon_build/Assets.car" "$APP_CONTENTS/Resources/Assets.car"
  cp "$icon_build/$APP_NAME.icns" "$APP_CONTENTS/Resources/$APP_NAME.icns"

  # Ship the third-party license notices with the binary, matching the release
  # bundle shape. Staged here (before sign_bundle) so the signature seals it in.
  cp "$ROOT_DIR/THIRD-PARTY-NOTICES.md" "$APP_CONTENTS/Resources/THIRD-PARTY-NOTICES.md"

  # Embed Sparkle so the dev bundle matches the release bundle shape. ditto
  # preserves the framework's symlinks and exec bits (a flattening copy breaks
  # it); the unused XPC services are stripped just as the release script does.
  local sparkle_framework
  sparkle_framework="$(sparkle_framework_path)"
  ditto "$sparkle_framework" "$APP_CONTENTS/Frameworks/Sparkle.framework"
  rm -r "$APP_CONTENTS/Frameworks/Sparkle.framework/Versions/Current/XPCServices"
  rm "$APP_CONTENTS/Frameworks/Sparkle.framework/XPCServices"
}

available_signing_identities() {
  security find-identity -v -p codesigning | awk -F'"' '/[)] [A-F0-9]+ "/ { print $2 }'
}

resolve_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    printf '%s\n' "$SIGNING_IDENTITY"
    return
  fi

  local identities preferred count
  identities="$(available_signing_identities)"
  preferred="$(printf '%s\n' "$identities" | grep -Fx "Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)" || true)"
  if [[ -n "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return
  fi

  count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities"
    return
  fi

  if [[ "${ALLOW_AD_HOC_SIGNING:-0}" == "1" ]]; then
    printf '%s\n' "-"
    return
  fi

  echo "SIGNING_IDENTITY is required for TCC-stable development launches." >&2
  echo "Set SIGNING_IDENTITY or ALLOW_AD_HOC_SIGNING=1 for non-persistent permission tests." >&2
  exit 64
}

sign_bundle() {
  local identity
  identity="$(resolve_signing_identity)"
  # Inside-out: Sparkle's nested helpers, then the framework, before the app.
  # Never deep-sign — it mis-signs the Autoupdate helper (Sparkle #1641).
  # Sparkle code carries no entitlements; dev keeps the existing no-timestamp
  # signing.
  codesign --force --options runtime --sign "$identity" "$APP_CONTENTS/Frameworks/Sparkle.framework/Versions/Current/Autoupdate"
  codesign --force --options runtime --sign "$identity" "$APP_CONTENTS/Frameworks/Sparkle.framework/Versions/Current/Updater.app"
  codesign --force --options runtime --sign "$identity" "$APP_CONTENTS/Frameworks/Sparkle.framework"
  codesign \
    --force \
    --options runtime \
    --entitlements "$ROOT_DIR/slovo.entitlements" \
    --sign "$identity" \
    "$APP_BUNDLE"
}

stop_app() {
  pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  local attempts=20
  while (( attempts > 0 )); do
    if pgrep -x "$PROCESS_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.25
    attempts=$((attempts - 1))
  done
  echo "$APP_NAME did not stay running as process $PROCESS_NAME" >&2
  return 1
}

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_app
build_app
stage_bundle
sign_bundle

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$SUBSYSTEM\" || process == \"$PROCESS_NAME\""
    ;;
  --verify|verify)
    open_app
    verify_app
    echo "$APP_NAME is running from $APP_BUNDLE"
    ;;
  *)
    usage
    exit 2
    ;;
esac
