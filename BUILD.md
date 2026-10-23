# 构建指南

目标：在 x86_64 Ubuntu 宿主上，用 **CUDA 13.0.88（SBSA/aarch64）** 为
Thor（aarch64，SM110a）交叉编译 `llama-server`，产物在 Thor 上链接
**CUDA 13.2.2 runtime + cuda-compat-orin** 运行。

## 1. 宿主要求

实测宿主：

| 项目 | 值 |
|---|---|
| 架构 | x86_64 |
| CMake | 3.28.3 |
| 交叉编译器 | `aarch64-linux-gnu-gcc-14` / `g++-14` |
| 用户态模拟 | `qemu-aarch64-static` |
| sysroot | Ubuntu 24.04 aarch64 rootfs |
| CUDA 编译器 | `nvcc V13.0.88`（SBSA aarch64） |

安装依赖（Ubuntu 24.04 示例）：

```bash
sudo apt-get install -y cmake git rsync qemu-user-static \
  gcc-14-aarch64-linux-gnu g++-14-aarch64-linux-gnu
```

作者本机使用的 sysroot 路径：

```text
/opt/thor-cc/thor-driveos/xbuild/noble-sysroot/root
```

换路径时不需要改脚本。以下三个参数都可以在 CMake 命令行覆盖，并会传递给
`nvcc-xc130-x86.sh`：

```bash
-DTHOR_XBUILD=/path/to/xbuild
-DTHOR_CUDA130=/path/to/xbuild/sbsa-linux-13
-DTHOR_SYSROOT=/path/to/xbuild/noble-sysroot/root
```

如果只在 shell 环境里设置 `THOR_XBUILD` / `THOR_CUDA130` / `THOR_SYSROOT`，
wrapper 也会使用这些值；CMake 传参的优先级更直观，建议用它。发布包不再依赖
作者的 `/opt/thor-cc` 路径，只有未覆盖时才使用兼容默认值。

## 2. 获取 CUDA 13.0.88 SBSA 工具链

作者本机路径（仅作实测记录）：

```text
/opt/thor-cc/thor-driveos/xbuild/sbsa-linux-13
```

### 从固定镜像提取（推荐复现方式）

工具链不是按 x86 CUDA 安装包“猜”出来的。本包验证的 13.0.88 SBSA 编译器来自
NVIDIA Thor 官方镜像：

```text
ghcr.io/nvidia-ai-iot/llama_cpp@sha256:f7c67c102b08252e963f9e5f92c3a36554c8f69305eb7ea257c6cd12e24c3191
```

该 digest 的 `platform` 为 `linux/arm64`。在 x86 宿主机上，用 Docker 的 arm64
平台拉取并提取即可（不运行镜像）：

```bash
./scripts/fetch-cu130-toolchain.sh ./xbuild/sbsa-linux-13
```

脚本做三件事：`docker create --platform linux/arm64`、从容器复制
`/usr/local/cuda-13.0`、校验 `version.json` 和 `nvcc` SHA256。镜像约 23 GB
压缩层，提取后约 4.7 GB；这不是本发布包的大小。若组织内部已有同版本工具链，
也可以直接传 `-DTHOR_CUDA130=...`。

镜像 tag `latest-jetson-thor` 会漂移，因此这里固定 manifest digest，不要只写 tag。
如果上游删除了 digest，按 `SOURCE.md` 记录的文件哈希核验，不要静默换包。

验证（必须全部匹配）：

```bash
CUDA=/path/to/xbuild/sbsa-linux-13
SR=/path/to/xbuild/noble-sysroot/root
cat "$CUDA/version.json" | grep -A1 -E 'cuda_nvcc|cuda_cudart'
qemu-aarch64-static -L "$SR" \
  "$CUDA/bin/nvcc" --version
```

期望：

```text
cuda_nvcc   13.0.88
cuda_cudart 13.0.88
Cuda compilation tools, release 13.0, V13.0.88
```

工具链来源：NVIDIA 官方 aarch64/SBSA CUDA 13.0 运行环境（本机从
`ghcr.io/nvidia-ai-iot/llama_cpp:latest-jetson-thor` 的 `/usr/local/cuda-13.0`
提取）。不要用 x86_64 的 `/usr/local/cuda-13.x` 冒充；它的 `nvcc` 产生 x86
host 代码，无法链接 Thor。

`sbsa-linux-13` 的 `lib` 目录必须有顶层 `libcuda.so` 供 CMake try-compile 链接；
若只有 `stubs/libcuda.so`，执行：

```bash
ln -sf stubs/libcuda.so "$CUDA/targets/sbsa-linux/lib/libcuda.so"
```

### sysroot 说明

交叉编译需要一个 Ubuntu 24.04 aarch64 sysroot。作者实测 sysroot 的 ABI 组件包括
`libc6 2.39-0ubuntu8`、`libc6-dev 2.39-0ubuntu8`、`libstdc++-13-dev
13.2.0-23ubuntu4`、`libgcc-s1 14-20240412-0ubuntu1`、`linux-libc-dev
6.8.0-31.31`，并补入 14 系列交叉编译器的 `libgomp.so/.a`。

可以用 Ubuntu 24.04 arm64 base rootfs + qemu-user 静态运行 `apt-get` 建立自己的
sysroot；也可以直接使用组织内已验证的 Ubuntu 24.04 aarch64 sysroot。无论来源，
必须检查下面的 ABI 文件和 `THOR_SYSROOT` 路径：

```bash
ls "$THOR_SYSROOT/usr/lib/aarch64-linux-gnu/libc.so.6" \
   "$THOR_SYSROOT/usr/include/aarch64-linux-gnu/bits/libc-header-start.h" \
   "$THOR_SYSROOT/usr/lib/gcc/aarch64-linux-gnu/14/libgcc.a" 2>/dev/null || true
```

如果构建时报 `libgomp` 缺失，从宿主交叉编译器目录补入：

```bash
cp /usr/lib/gcc-cross/aarch64-linux-gnu/14/libgomp.so "$THOR_SYSROOT/usr/lib/"
cp /usr/lib/gcc-cross/aarch64-linux-gnu/14/libgomp.a  "$THOR_SYSROOT/usr/lib/"
```

## 3. 准备源码

```bash
cd /path/to/llama.cpp
git checkout 72797e89198ab564fd0e6baa54ab196e8dd1d884
git apply /path/to/release/patches/production-sm110a-t4-dflash.patch
git add -A
test "$(git write-tree)" = "5ff7bf075c7363e62e662d53bb9d235367eecf1d"
```

最后一条必须通过。详见 `SOURCE.md`。

## 4. 配置

```bash
R=$PWD/build
S=/path/to/release

cmake \
  -DCMAKE_TOOLCHAIN_FILE="$S/scripts/toolchain-thor-cuda130-x86.cmake" \
  -B "$R/build/llama-cpp-cu130-sm110a" \
  -S /path/to/llama.cpp \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES=110a \
  -DTHOR_XBUILD=/path/to/xbuild \
  -DTHOR_CUDA130=/path/to/xbuild/sbsa-linux-13 \
  -DTHOR_SYSROOT=/path/to/xbuild/noble-sysroot/root \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_CUDA=ON -DGGML_CPU=ON -DGGML_CPU_AARCH64=ON
```

关键点：

| 参数 | 值 | 原因 |
|---|---|---|
| `CMAKE_CUDA_ARCHITECTURES` | `110a` | SM110 架构特定 cubin；不能用 `110` 或 `101a` |
| `BUILD_SHARED_LIBS` | `OFF` | 单文件可执行，便于板上替换/回滚 |
| `GGML_CUDA` | `ON` | CUDA backend |
| `GGML_CPU` / `GGML_CPU_AARCH64` | `ON` | ARM CPU fallback |
| `GGML_CUDA_NO_VMM` | 默认 `OFF` | 与 13.2 原生生产构建保持一致 |
| `GGML_NATIVE` | 默认 `OFF` | 交叉编译不能探测宿主 CPU |

配置日志中应出现：

```text
-- The CUDA compiler identification is NVIDIA 13.0.88
-- Using CMAKE_CUDA_ARCHITECTURES=110a
```

## 5. 编译

只构建服务端，节省时间：

```bash
cmake --build "$R/build/llama-cpp-cu130-sm110a" --target llama-server -j 24
```

本机实测：configure 于 `01:55:57` 完成，`build.pid` 为 `01:56:00`，产物写入
`02:15:12`，实际编译约 **19 分 12 秒**（qemu 下 aarch64 nvcc，96 核宿主，`-j 24`）。
完整的 make 输出在 `evidence/build/build-cu130.log`。
编译期间会出现大量 `warning #186-D` / narrowing 警告，来自 T4 模板实例；
只要没有 `error`，可继续。

产物：

```text
build/llama-cpp-cu130-sm110a/bin/llama-server
```

## 6. 静态验证

```bash
BIN="$R/build/llama-cpp-cu130-sm110a/bin/llama-server"
file "$BIN"
readelf -d "$BIN" | grep NEEDED
CUOBJDUMP=${CUOBJDUMP:-cuobjdump}
"$CUOBJDUMP" -lelf "$BIN" | grep -c 'sm_110a'
sha256sum "$BIN"
```

期望：

- `file`：`ELF 64-bit LSB pie executable, ARM aarch64`
- `NEEDED` 包含 `libcudart.so.13`、`libcublas.so.13`、`libcublasLt.so.13`、`libcuda.so.1`
- `sm_110a` cubin 数量为 **144**（与 13.2 原生生产件一致）
- SHA256 记录到 `artifacts/SHA256SUMS`

## 7. 可重复性说明

- 编译器、sysroot、CMake 版本、源码 tree hash、补丁 hash 全部记录。
- 构建目录不进入发布包；发布包只含产物和日志摘要。
- 二进制中不嵌入模型权重，也不链接 NVIDIA 专有库的静态副本。
- 由于 qemu/nvcc/链接器版本可能不同，逐字节可重复构建不保证；应以
  `sm_110a` 数量、动态依赖、SHA256 和行为门禁共同判定。
