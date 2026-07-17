#!/usr/bin/env bash
set -euo pipefail

# Stamp the app version into Info.plist at build time on the CI runner. The
# packaging job and the publish job both call this with identical, deterministic
# arguments so the signed artifact and the committed plist carry the same version.
#
# Usage: stamp-app-version.sh <short-version> <bundle-version> [plist-path]
#   short-version   CFBundleShortVersionString (marketing version, e.g. 0.10.0)
#   bundle-version   CFBundleVersion (monotonic build number; a positive integer)
#   plist-path       defaults to Resources/Info.plist
#
# The committed Resources/Info.plist is never a release source of truth for the
# build number: CI computes a deterministic, monotonic CFBundleVersion from git
# history and injects it here. Keeping this in one script guarantees the two jobs
# cannot drift.

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $(basename "$0") <short-version> <bundle-version> [plist-path]" >&2
    exit 64
fi

short_version="$1"
bundle_version="$2"
plist="${3:-Resources/Info.plist}"

# Accepts a release marketing version (0.10.0) and the marked dev form
# (0.9.0-ci.777); rejects empty, whitespace, and shell metacharacters.
if [[ ! "$short_version" =~ ^[A-Za-z0-9][A-Za-z0-9.+-]*$ ]]; then
    echo "short-version has an unexpected shape: $short_version" >&2
    exit 64
fi
if [[ ! "$bundle_version" =~ ^[0-9]+$ ]]; then
    echo "bundle-version must be a positive integer, got: $bundle_version" >&2
    exit 64
fi
if [[ ! -f "$plist" ]]; then
    echo "plist not found: $plist" >&2
    exit 65
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $short_version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $bundle_version" "$plist"

# Fail loudly if the edit produced an invalid plist rather than shipping it.
plutil -lint "$plist"
