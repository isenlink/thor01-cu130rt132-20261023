#!/bin/bash
set -euo pipefail

BASE=/brand_data/ai_workspace/thor01-cu132-20261022
BIN=$BASE/bin/llama-server-cu132-sm110a
MODEL=/brand_data/ai_workspace/models/RadixArk-F8attn-v2.gguf
DRAFT=/brand_data/ai_workspace/ai02/models/Qwen3.8-27B-DFlash2-BF16.gguf
MMPROJ=/brand_data/ai_workspace/models/mmproj-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-BF16.gguf
LOGDIR=$BASE/logs

if ss -tln 2>/dev/null | grep -q ':8080 '; then
  echo "[cu132-8080] SKIP: already listening"
  exit 0
fi
for f in "$BIN" "$MODEL" "$DRAFT" "$MMPROJ"; do
  [ -f "$f" ] || { echo "[cu132-8080] MISSING $f" >&2; exit 2; }
done

export LD_LIBRARY_PATH=$BASE/compat/compat_orin:$BASE/runtime/lib
export CUDA_CACHE_PATH=$BASE/cache
export GGML_CUDA_GRAPH_OPT=1
export GGML_MMVQ_MAX=2
export GGML_NVFP4_WIDE_MAX=0
export LLAMA_SPEC_TIMING=1
export T4_MMQ=1
export T4_CPS=7
export T4_STAGES=2
export T4_ARES=1

mkdir -p "$LOGDIR" "$CUDA_CACHE_PATH"
stamp=$(date +%Y%m%d-%H%M%S)
log=$LOGDIR/radixark-cu132-262k-8080-$stamp.log

nohup "$BIN" \
  -m "$MODEL" \
  -md "$DRAFT" \
  --mmproj "$MMPROJ" --mmproj-offload \
  --alias qwen3.8-27b --reasoning-effort medium --temp 0.3 \
  -ngl 99 -c 262144 -fa on \
  --cache-type-k f16 --cache-type-v f16 \
  --parallel 1 --port 8080 --host 0.0.0.0 \
  --spec-type draft-dflash --spec-draft-n-max 7 \
  --cache-ram 2048 \
  > "$log" 2>&1 &
pid=$!
echo "$pid" > "$LOGDIR/radixark-cu132-8080.pid"
echo "[cu132-8080] STARTED pid=$pid log=$log"

for i in $(seq 1 600); do
  if grep -q 'listening on http://0.0.0.0:8080' "$log" 2>/dev/null; then
    echo "[cu132-8080] LISTENING after ${i}s"
    exit 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[cu132-8080] START_FAILED" >&2
    tail -n 100 "$log" >&2 || true
    exit 3
  fi
  sleep 1
done
echo "[cu132-8080] START_TIMEOUT log=$log" >&2
tail -n 100 "$log" >&2 || true
exit 4
