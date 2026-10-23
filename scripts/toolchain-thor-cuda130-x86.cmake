# Thor (aarch64, SM110a) cross toolchain.
# Compiler/SDK: CUDA 13.0.88 (SBSA), run through qemu-aarch64 on x86_64.
# Target runtime: CUDA 13.2 (provided separately on the board).
set(THOR_XBUILD "/opt/thor-cc/thor-driveos/xbuild" CACHE PATH "xbuild root")
set(THOR_CUDA130 "${THOR_XBUILD}/sbsa-linux-13" CACHE PATH "CUDA 13.0.88 SBSA toolkit")
set(THOR_SYSROOT "${THOR_XBUILD}/noble-sysroot/root" CACHE PATH "Ubuntu 24.04 aarch64 sysroot")

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(SR ${THOR_SYSROOT})
set(SBSA ${THOR_CUDA130}/targets/sbsa-linux)

# CMake invokes the nvcc wrapper as a child process. Export the resolved paths so
# an out-of-tree copy of the toolkit does not fall back to the author's /opt/thor-cc.
set(ENV{THOR_XBUILD} "${THOR_XBUILD}")
set(ENV{THOR_CUDA130} "${THOR_CUDA130}")
set(ENV{THOR_SYSROOT} "${THOR_SYSROOT}")

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc-14)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++-14)
set(CMAKE_CUDA_COMPILER ${CMAKE_CURRENT_LIST_DIR}/nvcc-xc130-x86.sh)
set(CMAKE_CUDA_HOST_COMPILER aarch64-linux-gnu-g++-14)

set(CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES ${SBSA}/include)
set(CMAKE_CUDA_LIBRARIES ${SBSA}/lib/libcudart.so)
set(CUDA_CUDART_ROOT ${SBSA})
set(CUDA_CUDART_INCLUDE_DIR ${SBSA}/include)
set(CUDA_CUDART_LIBRARY ${SBSA}/lib/libcudart.so)
set(CUDA_TOOLKIT_ROOT_DIR ${THOR_CUDA130})
set(CUDAToolkit_ROOT ${THOR_CUDA130})
set(CUDAToolkit_VERSION 13.0.88)
set(CMAKE_IGNORE_PATH /usr/local/cuda /usr/local/cuda-12 /usr/local/cuda-12.8 /usr/local/cuda-13 /usr/local/cuda-13.0 /usr/local/cuda-13.1)
set(CMAKE_PREFIX_PATH ${THOR_CUDA130})

set(CMAKE_SYSROOT ${SR})
set(CMAKE_FIND_ROOT_PATH ${SR} ${SBSA} ${THOR_CUDA130})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_LIBRARY_PATH ${SBSA}/lib)
set(CMAKE_INCLUDE_PATH ${SBSA}/include)

set(CMAKE_C_FLAGS_INIT "--sysroot=${SR} -isystem ${SR}/usr/include -isystem ${SR}/usr/include/aarch64-linux-gnu")
set(CMAKE_CXX_FLAGS_INIT "--sysroot=${SR} -isystem ${SR}/usr/include -isystem ${SR}/usr/include/aarch64-linux-gnu")
set(CMAKE_CUDA_FLAGS_INIT "")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L${SBSA}/lib -Wl,--allow-shlib-undefined -lcudart -lcublas -lcublasLt -lcuda")
