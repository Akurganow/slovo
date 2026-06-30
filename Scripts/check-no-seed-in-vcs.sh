#!/bin/sh
# AC-6 — no-secrets / no-seed-in-VCS gate.
#
# Asserts loqui's .gitignore would keep every confidential seed/DB variant and
# key-material file out of version control. For each required glob, this creates
# a glob-matching probe file in an ISOLATED temp repo carrying loqui's real
# .gitignore, then requires `git check-ignore -q` to report it ignored. Exit 0
# only when EVERY probe is ignored; exit 1 naming the first probe that is not.
#
# Touches nothing in the real repo: all probes live in a throwaway temp tree.
set -eu

# Package root = the directory that contains this script's parent (Scripts/..).
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
real_gitignore="$package_root/.gitignore"

if [ ! -f "$real_gitignore" ]; then
    echo "FAIL: .gitignore not found at $real_gitignore" >&2
    exit 1
fi

# Probe names matching each required glob. Deliberately NOT the literal filenames
# the old exact list already covered — these are the variants the hardening adds.
probes="data/seed.dev.sql data/seed.2.sql data/loqui.db.x data/loqui.db-shm secrets/anthropic.key"

repo=$(mktemp -d "${TMPDIR:-/tmp}/loqui-noseed-XXXXXX")
trap 'rm -rf "$repo"' EXIT INT TERM

git -C "$repo" init -q
cp "$real_gitignore" "$repo/.gitignore"

status=0
for probe in $probes; do
    mkdir -p "$repo/$(dirname "$probe")"
    : > "$repo/$probe"
    if ! git -C "$repo" check-ignore -q "$probe"; then
        echo "FAIL: $probe matches a required glob but is NOT ignored by .gitignore" >&2
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "OK: every required seed/DB/key glob is ignored"
fi
exit "$status"
