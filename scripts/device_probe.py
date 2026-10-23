#!/usr/bin/env python3
"""Read Thor CUDA device identity without allocating GPU memory."""

import argparse
import ctypes
import os
import sys


DEFAULT_BASE = "/brand_data/ai_workspace/thor01-cu132-20261022"


def load(path: str) -> ctypes.CDLL:
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    return ctypes.CDLL(path, mode=ctypes.RTLD_GLOBAL)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=os.environ.get("THOR_LLM_BASE", DEFAULT_BASE))
    args = parser.parse_args()

    library_path = ":".join(
        (os.path.join(args.base, "compat/compat_orin"), os.path.join(args.base, "runtime/lib"))
    )
    if os.environ.get("THOR_PROBE_REEXEC") != "1":
        os.environ["LD_LIBRARY_PATH"] = library_path + ":" + os.environ.get("LD_LIBRARY_PATH", "")
        os.environ["THOR_PROBE_REEXEC"] = "1"
        os.execv(sys.executable, [sys.executable] + sys.argv)

    libcuda = load(os.path.join(args.base, "compat/compat_orin/libcuda.so.1"))
    libcudart = load(os.path.join(args.base, "runtime/lib/libcudart.so.13"))

    rc = libcuda.cuInit(0)
    if rc != 0:
        print(f"cuInit failed: {rc}", file=sys.stderr)
        return 2

    count = ctypes.c_int()
    if libcuda.cuDeviceGetCount(ctypes.byref(count)) != 0 or count.value < 1:
        print("no CUDA device", file=sys.stderr)
        return 3

    device = ctypes.c_int(0)
    name = ctypes.create_string_buffer(256)
    major = ctypes.c_int()
    minor = ctypes.c_int()
    runtime_version = ctypes.c_int()
    driver_version = ctypes.c_int()

    if libcuda.cuDeviceGetName(name, len(name), device) != 0:
        print("cuDeviceGetName failed", file=sys.stderr)
        return 4
    if libcuda.cuDeviceComputeCapability(ctypes.byref(major), ctypes.byref(minor), device) != 0:
        print("cuDeviceComputeCapability failed", file=sys.stderr)
        return 5
    if libcudart.cudaRuntimeGetVersion(ctypes.byref(runtime_version)) != 0:
        print("cudaRuntimeGetVersion failed", file=sys.stderr)
        return 6
    if libcuda.cuDriverGetVersion(ctypes.byref(driver_version)) != 0:
        print("cuDriverGetVersion failed", file=sys.stderr)
        return 7

    cc_code = major.value * 100 + minor.value
    print(
        f"devices={count.value} name={name.value.decode(errors='replace')} "
        f"cc={major.value}.{minor.value} cc_code={cc_code} "
        f"runtime={runtime_version.value} driver={driver_version.value}"
    )
    if cc_code != 1010:
        print("T4_GUARD=NOT_MATCHED expected_cc_code=1010")
    else:
        print("T4_GUARD=MATCHED expected_cc_code=1010")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
