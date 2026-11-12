#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Slovo"
PROCESS_NAME="slovo"
SUBSYSTEM="com.slovo.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

# Physical path: the process check below compares it with what ps reports.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
BUILD_CACHE_DIR="$ROOT/.build/swiftpm-cache"
BUILD_CONFIG_DIR="$ROOT/.build/swiftpm-config"
BUILD_SECURITY_DIR="$ROOT/.build/swiftpm-security"
RUN_DIR="$ROOT/.build/dev-run"
APP_BUNDLE="$RUN_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PROCESS_NAME"

# The staging and framework-signing steps the release script runs too.
DRY_RUN=0
run() { "$@"; }
source "$ROOT/Scripts/app-bundle.sh"

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
  local bin_path build_binary
  bin_path="$(swift build \
    --cache-path "$BUILD_CACHE_DIR" \
    --config-path "$BUILD_CONFIG_DIR" \
    --security-path "$BUILD_SECURITY_DIR" \
    --disable-automatic-resolution \
    --show-bin-path)"
  build_binary="$bin_path/$PROCESS_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT/Resources/Info.plist" "$APP_CONTENTS/Info.plist"

  # Mark the staged copy — never the committed plist — as a dev build; the About
  # header version line renders this as the Dobro suffix. Release packaging
  # installs the committed plist untouched, so the marker cannot reach a shipped
  # artifact.
  /usr/libexec/PlistBuddy -c "Add :SlovoDevBuild bool true" "$APP_CONTENTS/Info.plist"

  rm -rf "$RUN_DIR/icon"
  stage_bundle_contents "$bin_path" "$APP_CONTENTS" "$RUN_DIR/icon"
}

available_signing_identities() {
  security find-identity -v -p codesigning | awk -F'"' '/[)] [A-F0-9]+ "/ { print $2 }'
}

resolve_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    printf '%s\n' "$SIGNING_IDENTITY"
    return
  fi

  local identities count
  identities="$(available_signing_identities)"
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
  # Dev signing carries no timestamp.
  sign_bundle_frameworks "$APP_CONTENTS" --force --options runtime --sign "$identity"
  codesign \
    --force \
    --options runtime \
    --entitlements "$ROOT/slovo.entitlements" \
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
  local core_resources
  core_resources="$(bundle_resource_dir "$APP_CONTENTS/Resources/slovo_SlovoCore.bundle")"
  # A missing resource bundle degrades every prompt to example-free at runtime
  # (PromptExampleCatalog logs but keeps working), so staging is asserted here.
  if [[ ! -f "$core_resources/PromptExamples.xml" ]]; then
    echo "prompt examples resource bundle is not staged in $APP_CONTENTS/Resources" >&2
    return 1
  fi
  local cue_resource
  for cue_resource in \
    "$core_resources/AudioCues/start.wav" \
    "$core_resources/AudioCues/end.wav" \
    "$core_resources/AudioCues/error.wav"
  do
    if [[ ! -f "$cue_resource" ]]; then
      echo "dictation sound cue is not staged: $cue_resource" >&2
      return 1
    fi
  done
  # A missing embedded framework surfaces as a dyld launch failure with no
  # useful message, so name it here instead.
  if [[ ! -d "$APP_CONTENTS/Frameworks/SQLCipher.framework" ]]; then
    echo "SQLCipher.framework is not staged in $APP_CONTENTS/Frameworks" >&2
    return 1
  fi
  local attempts=20
  local pid
  while (( attempts > 0 )); do
    for pid in $(pgrep -x "$PROCESS_NAME" || true); do
      if [[ "$(ps -o comm= -p "$pid")" == "$APP_BINARY" ]]; then
        return 0
      fi
    done
    sleep 0.25
    attempts=$((attempts - 1))
  done
  pgrep -x "$PROCESS_NAME" >/dev/null && echo "a $PROCESS_NAME process runs, but not from $APP_BINARY" >&2
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
