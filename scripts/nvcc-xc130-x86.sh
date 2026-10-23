#!/bin/bash
# CUDA 13.0.88 (SBSA/sbsa-linux) nvcc under qemu-aarch64 on the x86 host.
# The target device is aarch64 Thor (sm_110a); the compiler itself is the
# aarch64 SBSA toolkit, so it must run through the static qemu user emulator.
set -euo pipefail

XBUILD=${THOR_XBUILD:-/opt/thor-cc/thor-driveos/xbuild}
CUDA=${THOR_CUDA130:-$XBUILD/sbsa-linux-13}
SR=${THOR_SYSROOT:-$XBUILD/noble-sysroot/root}

export QEMU_LD_PREFIX="$SR"
exec qemu-aarch64-static -L "$SR" "$CUDA/bin/nvcc" \
  -target-dir sbsa-linux \
  -ccbin aarch64-linux-gnu-g++-14 \
  -allow-unsupported-compiler \
  -I"$CUDA/targets/sbsa-linux/include" \
  -Xcompiler "--sysroot=$SR" \
  -L"$CUDA/targets/sbsa-linux/lib" \
  "$@"
