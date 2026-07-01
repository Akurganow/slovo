#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$package_root"

sample_file=$(mktemp "${TMPDIR:-/tmp}/slovo-cleanup-smoke.XXXXXX.json")
output_file=$(mktemp "${TMPDIR:-/tmp}/slovo-cleanup-smoke.XXXXXX.out")
error_file=$(mktemp "${TMPDIR:-/tmp}/slovo-cleanup-smoke.XXXXXX.err")
trap 'rm -f "$sample_file" "$output_file" "$error_file"' EXIT

cat > "$sample_file" <<'JSON'
[
  {
    "id": "smoke",
    "raw": "Hello.",
    "expectation": {
      "requiredSubstrings": ["Hello"],
      "minimumSentenceTerminators": 1
    }
  }
]
JSON

if ! swift run --disable-automatic-resolution slovo-cleanup-benchmark \
    --providers passthrough \
    --samples "$sample_file" \
    --repetitions 1 \
    >"$output_file" 2>"$error_file"; then
    cat "$output_file"
    cat "$error_file" >&2
    exit 1
fi

grep -q "candidate,runs,passed,errors,p50_ms,p95_ms" "$output_file"
grep -q "passthrough:none,1,1,0," "$output_file"
