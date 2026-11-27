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
    "references": ["Hello."]
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

grep -q "candidate,runs,failed_runs,p50_ms,p95_ms,max_ms,fuzzy,embedding,jev,cost_usd" "$output_file"
grep -Eq '^passthrough:none,1,0,[0-9]+\.[0-9],[0-9]+\.[0-9],[0-9]+\.[0-9],1\.000,,,0\.000000$' "$output_file"
grep -q '^progress: cleanup finished: calls made 1, failed 0, retried after a rate limit 0, gave up after rate limits 0$' "$error_file"
