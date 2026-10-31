# 源码身份与补丁

## 1. 上游基线

| 项目 | 值 |
|---|---|
| 仓库 | `ggml-org/llama.cpp` |
| 基线 commit | `72797e89198ab564fd0e6baa54ab196e8dd1d884` |
| commit 时间 | 2026-09-10 10:06:07 +0300 |
| commit 标题 | `vulkan : add command-buffer debug labels for GPU profilers (#28101)` |
| 应用补丁后的 git tree（可复现值） | `a652159a5b1c850289ed1b33f4bf28eb00adb004` |
| 生产补丁 | `patches/production-sm110a-t4-dflash.patch` |
| 补丁 SHA256 | `996e46dcd755576f800d5357516cb7128c72d5646757467467f4ee2a946b0a4d` |

生产源码树不是从 GitHub 直接 clone 的干净工作树。它是上述 commit 加一组
Thor01 生产补丁（T4-MMQ、NVFP4/FP8 路径、DFlash/MTP、qwen35/delta-net 修正、
server timing、GGUF converter 扩展等）。`patches/production-sm110a-t4-dflash.patch`
是相对基线 commit 的完整 diff，包含新增文件；`PRODUCTION_TREE.txt` 是应用补丁后
整棵树的 git tree hash。

复现方式：

```bash
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
git checkout 72797e89198ab564fd0e6baa54ab196e8dd1d884
git apply /path/to/patches/production-sm110a-t4-dflash.patch
git add -A
git write-tree          # 应为 a652159a5b1c850289ed1b33f4bf28eb00adb004
```

**适用环境（2026-10-31 独立重放确认）**：`git 2.47.3`、`core.autocrlf` 未设、
`core.fileMode` 默认（true/false 两种模式重放结果相同，均为 `a652159a…`）。
基线 commit 的 tree `4fe7b3d13209c8d5801994ea6b2ed733b861a793` 与上游官方一致，
确认 clone 忠实。两次干净重放结果一致（确定性）。

如果 `git write-tree` 与上述可复现值不同，先核对：①补丁 SHA256 是否为
`996e46dc…`（见上表）②基线 commit 是否正确 ③`git diff --stat` 是否为
36 文件 / 3019 增 / 70 删。内容 diff 一致即补丁完整，可继续构建；tree hash
差异若仅来自文件模式/换行环境，不影响构建产物。

> 历史对照：2026-10-23 首次发布时在临时 git worktree 上重放得到
> `5ff7bf075c7363e62e662d53bb9d235367eecf1d`，与本次干净 clone 重放值不同。
> 该 worktree 的 git 环境细节（fileMode/换行/索引状态）已不可完全还原；
> 内容一致性（diff stat + 补丁 SHA）已独立验证一致，故以可复现值
> `a652159a…` 为准。`git apply` 会报告补丁原有的 trailing-whitespace warning，
> 不影响 tree hash。

## 2. 补丁范围

补丁共 36 个文件、3019 行新增、70 行删除。主要类别：

| 类别 | 文件示例 | 用途 |
|---|---|---|
| T4-MMQ / tcgen05 | `ggml/src/ggml-cuda/t4_mmq.cu`、`t4_mmq.cuh`、`t4_mmq_pred.h`、`t4/*` | Thor T4 形状的 NVFP4 MMQ 快路；默认需 `T4_MMQ=1` 且 CC 守卫通过 |
| NVFP4/FP8 | `ggml/src/ggml-cuda/fp8-cublaslt.cu`、`fp8-mmq*.cu`、`mmvq.cu`、`mmq.cu` | NVFP4 权重与 FP8 KV 相关路径 |
| DFlash / MTP | `common/speculative.cpp`、`src/models/qwen35.cpp`、`src/models/delta-net-base.cpp` | draft-dflash 投机与 timing |
| Server | `tools/server/server-context.cpp` | 服务端上下文/缓存行为 |
| GGUF | `convert_hf_to_gguf.py`、`gguf-py/gguf/*` | 生产模型转换扩展 |

`*.bak`、`*.orig`、`__pycache__` 不属于补丁，也不参与构建；发布包不包含它们。

## 3. 编译器与 runtime

| 角色 | 版本/路径 |
|---|---|
| 编译工具链 | CUDA 13.0.1 toolkit，`nvcc V13.0.88` |
| 编译工具链实际文件 | `/opt/thor-cc/thor-driveos/xbuild/sbsa-linux-13` |
| 工具链固定来源 | `ghcr.io/nvidia-ai-iot/llama_cpp@sha256:f7c67c102b08252e963f9e5f92c3a36554c8f69305eb7ea257c6cd12e24c3191` |
| `nvcc` SHA256 | `fbb111f057786ddd10ba723d993cc7dd43abf978b6baa32fedd3c9d806dc79e1` |
| `version.json` SHA256 | `3783fdadf263a0054f3ff9d90d69d48a3c2c39ce03743ed6f7ea607a83a95def` |
| 编译期 `libcudart.so.13.0.88` SHA256 | `7e14751ad519120a6d6f44dc51dfbad32b690edf64a919f54f4ed8ee568fe136` |
| 编译期 `libcublas.so.13.0.2.14` SHA256 | `2d389825cfad33aeb95b247d9aa0f9e8fc430adcec8ea25d31e9ee26e6444681` |
| 目标 runtime | CUDA 13.2.2 runtime（组件版本 13.2.86） |
| `libcudart.so.13` SHA256 | `17515a9dd5f56015baac7a7d94617e87ad802345ced2248fa37c4b5d1fd88235` |
| `libcublas.so.13` SHA256 | `f0993dea3451082be0e2c780f68600b27688dbea364c7031ae77e16ab3f9ed8c` |
| `libcublasLt.so.13` SHA256 | `5af2ae59e652871dfc32fda727c0ede03fce740ca8c06b38b28a59644b35b247` |
| 驱动兼容层 | `compat_orin/libcuda.so.1.1` SHA256 `e4c849be8e1bca055c13c8ee0866abfbc58a7041db32c9534ea07853da4f801d` |

编译工具链是 **aarch64 SBSA** 工具链，在 x86_64 宿主上通过
`qemu-aarch64-static` 运行。它不是 x86_64 CUDA toolkit，也不是 13.2 的 nvcc。

镜像 digest 固定的是 manifest，不是可变的 `latest-jetson-thor` tag。`scripts/fetch-cu130-toolchain.sh`
会从该 digest 提取 `/usr/local/cuda-13.0`，并用上面的 `nvcc` SHA256 校验；
工具链不随发布包分发。

`sbsa-linux-13` 的 `version.json` 明确记录：

```text
cuda        13.0.1
cuda_nvcc   13.0.88
cuda_cudart 13.0.88
cuda_crt    13.0.88
libcublas   13.0.2.14
```

`nvcc --version` 实测：

```text
Cuda compilation tools, release 13.0, V13.0.88
Build cuda_13.0.r13.0/compiler.36424714_0
```

## 4. 模型资产（不随包分发）

发布包不含模型权重。复现 Thor01 生产行为需要以下文件，放在记录的位置：

| 角色 | 路径 | 说明 |
|---|---|---|
| 主模型 | `/brand_data/ai_workspace/models/RadixArk-F8attn-v2.gguf` | 20G，SHA256 `d15dac916823f590fa8e584ae18a37c62d61947ce33df943a658c83766d2e7e9` |
| DFlash draft | `/brand_data/ai_workspace/ai02/models/Qwen3.8-27B-DFlash2-BF16.gguf` | 3.6G，SHA256 `26d47ca20ab07688327a63d912acad222d924eaaa92a980cc488de3c67e736bc` |
| 主模型 mmproj | `/brand_data/ai_workspace/models/mmproj-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-BF16.gguf` | 889M，SHA256 `5681b690bcb8eb10cd28d62d078cb4e01521a3ea4880a3fc7d54de72de2dd142` |
| VL 模型 | `/brand_data/ai_workspace/models/qwen3vl8b/Qwen3-VL-8B-Instruct-Q6_K.gguf` | 6.3G，SHA256 `f1a6f30ddae86e625cb5f494891b9a2a68169819f42527ef0c65fb46652366b5`。标准 llama.cpp K-quant 量化件，官方来源 `Qwen/Qwen3-VL-8B-Instruct-GGUF`（HuggingFace，Qwen 官方 GGUF 仓，`Q6_K` 档）；社区同款量化 `bartowski/Qwen_Qwen3-VL-8B-Instruct-GGUF`、`mradermacher/Qwen3-VL-8B-Instruct-GGUF` 文件名一致，可对照 SHA 取件 |
| VL mmproj | `/brand_data/ai_workspace/models/qwen3vl8b/mmproj-Qwen3-VL-8B-Instruct-F16.gguf` | 1.1G，SHA256 `30cc93c7375b529b2abe165d1597e12f6717bf87565655a546727c4bd2bb5ada`。多模态投影件，随上述官方 GGUF 仓分发（`mmproj-F16` 档） |

本包验证的是二进制/运行时组合和该模型上的输出质量；模型权重许可由模型提供方决定。
