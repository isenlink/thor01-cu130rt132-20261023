#!/bin/bash
set -euo pipefail

# Extract CUDA 13.0.88 (SBSA/aarch64) from the pinned NVIDIA Thor image.
# The image is large (~23 GB compressed), but its digest fixes the compiler bits.
IMAGE=${CU130_IMAGE:-ghcr.io/nvidia-ai-iot/llama_cpp@sha256:f7c67c102b08252e963f9e5f92c3a36554c8f69305eb7ea257c6cd12e24c3191}
DEST=${1:-$PWD/cu130-toolchain}
CID=

cleanup() {
  if [ -n "$CID" ]; then
    docker rm -f "$CID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

command -v docker >/dev/null || { echo "docker is required" >&2; exit 2; }
mkdir -p "$DEST"

echo "[cu130] creating container from $IMAGE"
CID=$(docker create --platform linux/arm64 "$IMAGE")

echo "[cu130] extracting /usr/local/cuda-13.0 to $DEST"
docker cp "$CID:/usr/local/cuda-13.0/." "$DEST/"

if [ ! -e "$DEST/targets/sbsa-linux/lib/libcuda.so" ] && \
   [ -e "$DEST/targets/sbsa-linux/lib/stubs/libcuda.so" ]; then
  ln -s stubs/libcuda.so "$DEST/targets/sbsa-linux/lib/libcuda.so"
fi

python3 - "$DEST/version.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    versions = json.load(fh)
expected = {"cuda": "13.0.1", "cuda_nvcc": "13.0.88", "cuda_cudart": "13.0.88"}
for key, want in expected.items():
    got = versions.get(key, {}).get("version")
    if got != want:
        raise SystemExit(f"{key}: got {got}, expected {want}")
print("[cu130] version.json OK:", ", ".join(f"{k}={v}" for k, v in expected.items()))
PY

expected_nvcc=fbb111f057786ddd10ba723d993cc7dd43abf978b6baa32fedd3c9d806dc79e1
got_nvcc=$(sha256sum "$DEST/bin/nvcc" | awk '{print $1}')
[ "$got_nvcc" = "$expected_nvcc" ] || {
  echo "nvcc sha256 mismatch: got $got_nvcc expected $expected_nvcc" >&2
  exit 3
}
echo "[cu130] nvcc sha256 OK"
echo "[cu130] ready at $DEST"
