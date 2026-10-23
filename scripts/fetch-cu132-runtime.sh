#!/bin/bash
set -euo pipefail

DEST=${1:-$PWD/cu132-runtime}
CACHE=${CU132_CACHE:-}
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

RUNTIME_WHEEL=nvidia_cuda_runtime-13.2.86-py3-none-manylinux2014_aarch64.manylinux_2_17_aarch64.whl
RUNTIME_URL=https://files.pythonhosted.org/packages/89/d4/fa981071e3d9f29158ca16c69ee617831cd6df4dd47024149c16eec717f8/$RUNTIME_WHEEL
RUNTIME_SHA=37844957894bfdecf90243568d21a2cb251b66106915b71459a23c8e6ef2da69

CUBLAS_WHEEL=nvidia_cublas-13.2.2.2-py3-none-manylinux_2_27_aarch64.whl
CUBLAS_URL=https://files.pythonhosted.org/packages/3e/03/a5159a114b62d738d385233be6ea345bb43e1f6392fabaebca61c96ed283/$CUBLAS_WHEEL
CUBLAS_SHA=178c9d61959c1184603951703c947b2007989cf7fea6b216cf1a31c104fbdeac

COMPAT_DEB=cuda-compat-orin-13-2_13.2.44290101-1_arm64.deb
COMPAT_URL=https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/sbsa/$COMPAT_DEB
COMPAT_SHA=3331f3ac94eecc0e3c0d1976c8fa306c2bf33dd6f771e0d61bb583cab3590037

command -v curl >/dev/null
command -v dpkg-deb >/dev/null

mkdir -p "$DEST/runtime/lib" "$DEST/compat/compat_orin" "$WORK/downloads"

fetch() {
  url=$1
  file=$2
  sha=$3
  if [ ! -f "$WORK/downloads/$file" ]; then
    if [ -n "$CACHE" ] && [ -f "$CACHE/$file" ]; then
      echo "[fetch] $file (cache)"
      cp "$CACHE/$file" "$WORK/downloads/$file"
    else
      echo "[fetch] $file"
      curl -fL --retry 3 --output "$WORK/downloads/$file" "$url"
    fi
  fi
  printf '%s  %s\n' "$sha" "$WORK/downloads/$file" | sha256sum -c -
}

fetch "$RUNTIME_URL" "$RUNTIME_WHEEL" "$RUNTIME_SHA"
fetch "$CUBLAS_URL" "$CUBLAS_WHEEL" "$CUBLAS_SHA"
fetch "$COMPAT_URL" "$COMPAT_DEB" "$COMPAT_SHA"

python3 - "$WORK/downloads/$RUNTIME_WHEEL" "$WORK/runtime-wheel" "$DEST/runtime/lib" <<'PY'
import os, shutil, sys, zipfile
wheel, out, dest = sys.argv[1:]
with zipfile.ZipFile(wheel) as zf:
    zf.extractall(out)
for name in ("libcudart.so.13",):
    src = os.path.join(out, "nvidia/cu13/lib", name)
    shutil.copy2(src, os.path.join(dest, name))
PY

python3 - "$WORK/downloads/$CUBLAS_WHEEL" "$WORK/cublas-wheel" "$DEST/runtime/lib" <<'PY'
import os, shutil, sys, zipfile
wheel, out, dest = sys.argv[1:]
with zipfile.ZipFile(wheel) as zf:
    zf.extractall(out)
for name in ("libcublas.so.13", "libcublasLt.so.13"):
    src = os.path.join(out, "nvidia/cu13/lib", name)
    shutil.copy2(src, os.path.join(dest, name))
PY

dpkg-deb -x "$WORK/downloads/$COMPAT_DEB" "$WORK/compat-root"
cp -a "$WORK/compat-root/usr/local/cuda-13.2/compat_orin/." "$DEST/compat/compat_orin/"

ln -sfn libcudart.so.13 "$DEST/runtime/lib/libcudart.so"
ln -sfn libcublas.so.13 "$DEST/runtime/lib/libcublas.so"
ln -sfn libcublasLt.so.13 "$DEST/runtime/lib/libcublasLt.so"
ln -sfn libcuda.so.1.1 "$DEST/compat/compat_orin/libcuda.so.1"
ln -sfn libcuda.so.1 "$DEST/compat/compat_orin/libcuda.so"

sha256sum \
  "$DEST/runtime/lib/libcudart.so.13" \
  "$DEST/runtime/lib/libcublas.so.13" \
  "$DEST/runtime/lib/libcublasLt.so.13" \
  "$DEST/compat/compat_orin/libcuda.so.1.1"

echo "[fetch] runtime ready at $DEST"
