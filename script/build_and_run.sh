#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Slovo"
PROCESS_NAME="slovo"
BUNDLE_ID="com.slovo.app"
SUBSYSTEM="com.slovo.app"

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

stage_bundle() {
  local build_binary
  build_binary="$(swift build \
    --cache-path "$BUILD_CACHE_DIR" \
    --config-path "$BUILD_CONFIG_DIR" \
    --security-path "$BUILD_SECURITY_DIR" \
    --disable-automatic-resolution \
    --show-bin-path)/$PROCESS_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
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
