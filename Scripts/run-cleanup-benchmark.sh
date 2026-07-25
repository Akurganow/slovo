#!/usr/bin/env bash
# Launches the full cleanup benchmark fully DETACHED (nohup): it survives the
# terminal, the IDE, and any agent session that started it. All state lives in
# one timestamped directory so progress and results are inspectable at any time:
#
#   .build/benchmark-runs/<stamp>/status         RUNNING -> DONE | FAILED(<code>)
#   .build/benchmark-runs/<stamp>/run.log        lifecycle + heartbeat every 60 s
#   .build/benchmark-runs/<stamp>/report.csv     aggregate report (written at the END of the run)
#   .build/benchmark-runs/<stamp>/benchmark.pid  worker PID (kill it to abort)
#
# Usage:
#   Scripts/run-cleanup-benchmark.sh                 # full shortlist, 10 repetitions
#   REPETITIONS=3 Scripts/run-cleanup-benchmark.sh   # cheaper run
#   PROVIDERS=passthrough Scripts/run-cleanup-benchmark.sh   # zero-network smoke
#
# The benchmark CLI prints its aggregate report only when the whole run
# completes, so an empty report.csv while status=RUNNING is normal — watch
# run.log for the heartbeat instead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$ROOT_DIR/.build/benchmark-runs/$STAMP"
mkdir -p "$RUN_DIR"

DEFAULT_PROVIDERS="openrouter:openai/gpt-5.6-luna,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-3.1-flash-lite,openrouter:qwen/qwen3.6-flash,openrouter:deepseek/deepseek-v4-flash,openrouter:mistralai/mistral-small-2603,openrouter:minimax/minimax-m3,passthrough"
PROVIDERS="${PROVIDERS:-$DEFAULT_PROVIDERS}"
REPETITIONS="${REPETITIONS:-10}"

# Build synchronously so a compile failure surfaces here, not inside nohup.
swift build --disable-automatic-resolution --product slovo-cleanup-benchmark >"$RUN_DIR/build.log" 2>&1

echo "RUNNING" > "$RUN_DIR/status"
{
  echo "[$(date '+%F %T')] start"
  echo "[$(date '+%F %T')] commit:      $(git -C "$ROOT_DIR" rev-parse --short HEAD)"
  echo "[$(date '+%F %T')] providers:   $PROVIDERS"
  echo "[$(date '+%F %T')] repetitions: $REPETITIONS"
  echo "[$(date '+%F %T')] report:      $RUN_DIR/report.csv"
} >> "$RUN_DIR/run.log"

nohup bash -c '
  RUN_DIR="$1"; PROVIDERS="$2"; REPETITIONS="$3"; ROOT_DIR="$4"
  cd "$ROOT_DIR"
  swift run --disable-automatic-resolution slovo-cleanup-benchmark \
    --env-file .env \
    --providers "$PROVIDERS" \
    --repetitions "$REPETITIONS" \
    --failure-breakdown \
    --category-breakdown > "$RUN_DIR/report.csv" 2>> "$RUN_DIR/run.log" &
  BENCH_PID=$!
  echo "$BENCH_PID" > "$RUN_DIR/benchmark.pid"
  START=$SECONDS
  while kill -0 "$BENCH_PID" 2>/dev/null; do
    sleep 60
    kill -0 "$BENCH_PID" 2>/dev/null || break
    echo "[$(date "+%F %T")] heartbeat: running, elapsed $(( (SECONDS - START) / 60 )) min" >> "$RUN_DIR/run.log"
  done
  wait "$BENCH_PID"; CODE=$?
  # The CLI exits 0 only when EVERY run passed quality; 2 means the run
  # completed and some quality checks failed — normal for any real model.
  if [ "$CODE" -eq 0 ] || [ "$CODE" -eq 2 ]; then
    echo "DONE" > "$RUN_DIR/status"
    echo "[$(date "+%F %T")] finished (exit $CODE) after $(( (SECONDS - START) / 60 )) min; report: $RUN_DIR/report.csv" >> "$RUN_DIR/run.log"
  else
    echo "FAILED($CODE)" > "$RUN_DIR/status"
    echo "[$(date "+%F %T")] FAILED with exit $CODE after $(( (SECONDS - START) / 60 )) min" >> "$RUN_DIR/run.log"
  fi
' bench-worker "$RUN_DIR" "$PROVIDERS" "$REPETITIONS" "$ROOT_DIR" >> "$RUN_DIR/run.log" 2>&1 &
disown

echo "benchmark launched, detached from this shell"
echo "  state dir: $RUN_DIR"
echo "  watch:     tail -f $RUN_DIR/run.log"
echo "  status:    cat $RUN_DIR/status"
