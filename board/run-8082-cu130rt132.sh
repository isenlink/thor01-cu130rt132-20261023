#!/bin/bash
set -euo pipefail

BASE=${THOR_LLM_BASE:-/brand_data/ai_workspace/thor01-cu132-20261022}
BIN=$BASE/bin/llama-server-cu130rt132-sm110a
DIR=${THOR_VL_DIR:-/brand_data/ai_workspace/models/qwen3vl8b}
LOGDIR=$BASE/logs

if ss -tln 2>/dev/null | grep -q ':8082 '; then
  echo "[cu130rt132-8082] SKIP: already listening"
  exit 0
fi
for f in "$BIN" "$DIR/Qwen3-VL-8B-Instruct-Q6_K.gguf" "$DIR/mmproj-Qwen3-VL-8B-Instruct-F16.gguf"; do
  [ -f "$f" ] || { echo "[cu130rt132-8082] MISSING $f" >&2; exit 2; }
done

for _ in $(seq 1 300); do
  ss -tln 2>/dev/null | grep -q ':8080 ' && break
  sleep 1
done
if ! ss -tln 2>/dev/null | grep -q ':8080 '; then
  echo "[cu130rt132-8082] 8080 not ready; refusing to start" >&2
  exit 3
fi

export LD_LIBRARY_PATH=$BASE/compat/compat_orin:$BASE/runtime/lib
export CUDA_CACHE_PATH=$BASE/cache

mkdir -p "$LOGDIR" "$CUDA_CACHE_PATH"
stamp=$(date +%Y%m%d-%H%M%S)
log=$LOGDIR/qwen3vl8b-cu130rt132-8082-$stamp.log

nohup "$BIN" \
  -m "$DIR/Qwen3-VL-8B-Instruct-Q6_K.gguf" \
  --mmproj "$DIR/mmproj-Qwen3-VL-8B-Instruct-F16.gguf" \
  --mmproj-offload \
  --alias qwen3-vl-8b \
  -ngl 99 \
  -c 20480 -np 1 \
  --host 0.0.0.0 --port 8082 \
  > "$log" 2>&1 &
pid=$!
echo "$pid" > "$LOGDIR/qwen3vl8b-cu130rt132-8082.pid"
sleep 2
echo 500 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
echo "[cu130rt132-8082] STARTED pid=$pid log=$log"

for i in $(seq 1 300); do
  if grep -q 'listening on http://0.0.0.0:8082' "$log" 2>/dev/null; then
    echo "[cu130rt132-8082] LISTENING after ${i}s"
    exit 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[cu130rt132-8082] START_FAILED" >&2
    tail -n 100 "$log" >&2 || true
    exit 4
  fi
  sleep 1
done
echo "[cu130rt132-8082] START_TIMEOUT log=$log" >&2
tail -n 100 "$log" >&2 || true
exit 5
