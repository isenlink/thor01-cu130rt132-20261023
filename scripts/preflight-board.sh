#!/bin/bash
set -euo pipefail

BASE=${THOR_LLM_BASE:-/brand_data/ai_workspace/thor01-cu132-20261022}
HASH_MODELS=0
[ "${1:-}" = "--hash-models" ] && HASH_MODELS=1
fail=0

ok() { printf '[PASS] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*"; fail=1; }
note() { printf '[INFO] %s\n' "$*"; }

[ "$(uname -m)" = aarch64 ] && ok "aarch64" || bad "uname -m=$(uname -m)"
uname -r | grep -q tegra && ok "kernel=$(uname -r)" || bad "not a Tegra kernel: $(uname -r)"
command -v python3 >/dev/null && ok "python3" || bad "python3 missing"
command -v ss >/dev/null && ok "ss" || bad "ss missing"

check_file() {
  path=$1
  [ -f "$path" ] && ok "file $path" || bad "missing $path"
}

check_sha() {
  path=$1
  expected=$2
  [ -f "$path" ] || { bad "missing $path"; return; }
  got=$(sha256sum "$path" | awk '{print $1}')
  [ "$got" = "$expected" ] && ok "sha256 $path" || bad "sha256 mismatch $path got=$got"
}

check_file "$BASE/bin/llama-server-cu130rt132-sm110a"
check_sha "$BASE/bin/llama-server-cu130rt132-sm110a" 686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e
check_sha "$BASE/runtime/lib/libcudart.so.13" 17515a9dd5f56015baac7a7d94617e87ad802345ced2248fa37c4b5d1fd88235
check_sha "$BASE/runtime/lib/libcublas.so.13" f0993dea3451082be0e2c780f68600b27688dbea364c7031ae77e16ab3f9ed8c
check_sha "$BASE/runtime/lib/libcublasLt.so.13" 5af2ae59e652871dfc32fda727c0ede03fce740ca8c06b38b28a59644b35b247
check_sha "$BASE/compat/compat_orin/libcuda.so.1.1" e4c849be8e1bca055c13c8ee0866abfbc58a7041db32c9534ea07853da4f801d

MODELS=(
  "/brand_data/ai_workspace/models/RadixArk-F8attn-v2.gguf"
  "/brand_data/ai_workspace/ai02/models/Qwen3.8-27B-DFlash2-BF16.gguf"
  "/brand_data/ai_workspace/models/mmproj-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-BF16.gguf"
  "/brand_data/ai_workspace/models/qwen3vl8b/Qwen3-VL-8B-Instruct-Q6_K.gguf"
  "/brand_data/ai_workspace/models/qwen3vl8b/mmproj-Qwen3-VL-8B-Instruct-F16.gguf"
)
for path in "${MODELS[@]}"; do
  check_file "$path"
done

if [ "$HASH_MODELS" = 1 ]; then
  check_sha "/brand_data/ai_workspace/models/RadixArk-F8attn-v2.gguf" d15dac916823f590fa8e584ae18a37c62d61947ce33df943a658c83766d2e7e9
  check_sha "/brand_data/ai_workspace/ai02/models/Qwen3.8-27B-DFlash2-BF16.gguf" 26d47ca20ab07688327a63d912acad222d924eaaa92a980cc488de3c67e736bc
  check_sha "/brand_data/ai_workspace/models/mmproj-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-BF16.gguf" 5681b690bcb8eb10cd28d62d078cb4e01521a3ea4880a3fc7d54de72de2dd142
  check_sha "/brand_data/ai_workspace/models/qwen3vl8b/Qwen3-VL-8B-Instruct-Q6_K.gguf" f1a6f30ddae86e625cb5f494891b9a2a68169819f42527ef0c65fb46652366b5
  check_sha "/brand_data/ai_workspace/models/qwen3vl8b/mmproj-Qwen3-VL-8B-Instruct-F16.gguf" 30cc93c7375b529b2abe165d1597e12f6717bf87565655a546727c4bd2bb5ada
fi

total=$(awk '/HugePages_Total:/ {print $2}' /proc/meminfo)
free=$(awk '/HugePages_Free:/ {print $2}' /proc/meminfo)
size=$(awk '/Hugepagesize:/ {print $2}' /proc/meminfo)
note "hugepages total=$total free=$free size_kb=$size"
[ "${total:-0}" -ge 25600 ] && ok "hugepage pool >= 50 GiB" || bad "hugepage pool < 25600 pages"

if ss -tln | grep -Eq ':(8080|8082) '; then
  note "ports already active; stop services before switch (the switch script does this)"
  ss -ltnp | grep -E ':(8080|8082) ' || true
fi

if [ "$fail" -ne 0 ]; then
  echo "[preflight] FAILED" >&2
  exit 2
fi
echo "[preflight] OK"
