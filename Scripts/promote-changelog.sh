#!/usr/bin/env bash
set -euo pipefail

# Cut a Keep a Changelog release section during the publish job. Renames the top
# `## [Unreleased]` heading to `## [<version>] - <date>` and inserts a fresh, empty
# `## [Unreleased]` above it. Any notes contributors curated under Unreleased become
# the released version's notes; the authoritative per-release notes are the
# GitHub Release body (generated separately). This preserves the existing
# Keep a Changelog style instead of pasting a differently-formatted conventional
# changelog into the file.
#
# Usage: promote-changelog.sh <version> <date> [changelog-path]
#   version          e.g. 0.10.0
#   date             ISO date, e.g. 2026-07-17
#   changelog-path   defaults to CHANGELOG.md

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $(basename "$0") <version> <date> [changelog-path]" >&2
    exit 64
fi

version="$1"
date="$2"
file="${3:-CHANGELOG.md}"

if [[ -z "$version" || -z "$date" ]]; then
    echo "version and date must not be empty" >&2
    exit 64
fi
if [[ ! -f "$file" ]]; then
    echo "changelog not found: $file" >&2
    exit 65
fi
if ! grep -qE '^## \[Unreleased\]' "$file"; then
    echo "no '## [Unreleased]' section found in $file" >&2
    exit 65
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v ver="$version" -v date="$date" '
    !promoted && /^## \[Unreleased\]/ {
        print "## [Unreleased]"
        print ""
        print "## [" ver "] - " date
        promoted = 1
        next
    }
    { print }
' "$file" > "$tmp"
mv "$tmp" "$file"
trap - EXIT
