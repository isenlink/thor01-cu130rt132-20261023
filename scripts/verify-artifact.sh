#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ART=${1:-$ROOT/artifacts/llama-server-cu130rt132-sm110a}
EXPECTED_SHA=686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e

got=$(sha256sum "$ART" | awk '{print $1}')
[ "$got" = "$EXPECTED_SHA" ] || { echo "sha256 mismatch: $got" >&2; exit 2; }
echo "sha256 OK"

file "$ART" | grep -q 'ARM aarch64' || { echo "not an ARM aarch64 ELF" >&2; exit 3; }
echo "ELF OK"

readelf -d "$ART" | grep -q 'libcudart.so.13' || { echo "missing libcudart.so.13" >&2; exit 4; }
readelf -d "$ART" | grep -q 'libcublas.so.13' || { echo "missing libcublas.so.13" >&2; exit 5; }
readelf -d "$ART" | grep -q 'libcublasLt.so.13' || { echo "missing libcublasLt.so.13" >&2; exit 6; }
readelf -d "$ART" | grep -q 'libcuda.so.1' || { echo "missing libcuda.so.1" >&2; exit 7; }
echo "NEEDED OK"

if [ -z "${CUOBJDUMP:-}" ]; then
  count=
  for candidate in \
    "${CUDA_HOME:-}/bin/cuobjdump" \
    "${CUDA_PATH:-}/bin/cuobjdump" \
    "/usr/local/cuda-13.2/bin/cuobjdump" \
    "/usr/local/cuda-13.1/bin/cuobjdump" \
    "/usr/local/cuda-13.0/bin/cuobjdump" \
    "/opt/thor-cc/thor-u-repro/cuda-13.2.2-x86_64/toolkit/bin/cuobjdump" \
    "$(command -v cuobjdump 2>/dev/null || true)"; do
    if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
      continue
    fi
    candidate_count=$("$candidate" -lelf "$ART" 2>/dev/null | grep -c 'sm_110a' || true)
    if [ "${candidate_count:-0}" -gt 0 ]; then
      CUOBJDUMP=$candidate
      count=$candidate_count
      break
    fi
  done
fi

if [ -z "${CUOBJDUMP:-}" ] || [ ! -x "$CUOBJDUMP" ]; then
  echo "no cuobjdump can read sm_110a; set CUOBJDUMP=/path/to/cuobjdump" >&2
  exit 8
fi
if [ -z "${count:-}" ]; then
  count=$("$CUOBJDUMP" -lelf "$ART" | grep -c 'sm_110a' || true)
fi
[ "$count" = 144 ] || { echo "sm_110a cubin count=$count expected=144" >&2; exit 9; }
echo "sm_110a cubins=$count"
echo "artifact OK"
