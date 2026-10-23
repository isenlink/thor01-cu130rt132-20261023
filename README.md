# Thor01：llama.cpp CUDA 13.0.88 编译 + CUDA 13.2 runtime

发布标识：`thor01-cu130rt132-20261023`  
验证日期：2026-10-23  
目标板：Thor01（`192.168.1.101`），aarch64，58 GiB UMA

## 获取预编译二进制

两个 `llama-server` 二进制（约 160 MB）不进 git 历史，从 [Releases](https://github.com/isenlink/thor01-cu130rt132-20261023/releases/tag/thor01-cu130rt132-20261023) 下载完整包：

| 文件 | 大小 | 说明 |
|---|---|---|
| `thor01-cu130rt132-20261023.tar.gz` | ~95 MB | 完整包：二进制 + 文档 + 补丁 + 脚本 + 证据 |
| `thor01-cu130rt132-20261023.tar.gz.sha256` | 65 B | 包 SHA256 |

```bash
sha256sum -c thor01-cu130rt132-20261023.tar.gz.sha256
tar xzf thor01-cu130rt132-20261023.tar.gz
cd thor01-cu130rt132-20261023
sha256sum -c SHA256SUMS          # 69 件全量校验
```

本仓库 git 历史里是文档、补丁、脚本与证据（`artifacts/` 下二进制被 `.gitignore` 排除，仅保留 `artifacts/SHA256SUMS` 供校验）。

## 1. 结论

本发布把 llama.cpp 的 **编译工具链改成 CUDA 13.0.88（nvcc 13.0，SBSA/aarch64）**，
生成 `sm_110a` cubin；进程运行时仍然使用 **CUDA 13.2 用户态 runtime + cuda-compat-orin**。
系统 `/usr/local/cuda` 和系统驱动不做替换。

已在 Thor01 完成实际部署和验收：

- 8080：RadixArk-F8attn-v2 + Qwen3.8-27B DFlash draft + mmproj，262144 ctx。
- 8082：Qwen3-VL-8B Q6_K + mmproj，20480 ctx。
- 最终质量门禁 **7/7 PASS**（两个 health、短问答、数字串转录、JSON、VL 短问答、红色图片识别）。
- 新二进制 SHA256：`686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e`。
  - 注：本发布件二进制为**脱敏重打包件**——仅在文本层把品牌路径→`/brand_data`、账号名脱敏，每个二进制只改 2 处字符串（共 10 字节），cubin 计算内容与文件总字节数与原构建件逐字节一致，仅 SHA256 因这 10 字节而不同。板上实测的**原构建件** SHA256：新件 `466f25d4d136035bb1c1b90f672c9fa7a9cdfad03b1c0690675a3d4b265084a7`、回滚件 `73bb5fc7540cc9b1547b6f5d8d9c3233081b389a758e75be2e09c295584fe1ee`（见 `evidence/` 快照）；**本发布件** SHA256：新件 `686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e`、回滚件 `8a0655ca61007d4ce57bab6a3e24a6d51768ad2ec46ad807f082dbd8dec919c8`，以 `SHA256SUMS` 为准。
- 50 GiB 大页池（25600 × 2 MiB）在服务起来后只剩个位数空闲页；部署参数没有权重流式。

**这不是提速版本。** 同一模型、同一参数、无前缀缓存的严格 A/B 中，新组合比既有
CUDA 13.2 原生件稳定慢约 **1.6% decode / 2.4% prefill**。部署理由是规避上游
`ggml-org/llama.cpp#27763` 记录的 CUDA 13.2 编译 SM110 风险，不是性能收益：
<https://github.com/ggml-org/llama.cpp/issues/27763>。

**T4 快路没有生效。** 13.2 compat 下设备上报 `cc=11.0`（代码 1100），而生产 T4
守卫要求 `10.1a`（代码 1010）。`T4_MMQ=1` 等环境变量虽然传入，但不会命中 T4-MMQ。
本包不声明任何“T4 加速”结果。

本轮没有做 100K/200K 长上下文的严格 A/B；严格性能数据只覆盖 128-token decode、
约 2K prefill 和约 8K prefill。不得把本包的数据外推成 100K/200K 结论。

## 2. 版本组合

| 角色 | 版本 |
|---|---|
| 编译工具链 | CUDA 13.0.1，`nvcc V13.0.88`，aarch64 SBSA |
| 编译期 cuBLAS | `13.0.2.14` |
| 目标架构 | `CMAKE_CUDA_ARCHITECTURES=110a` |
| 目标 cubin | 144 个 `sm_110a` |
| 进程 runtime | CUDA 13.2 用户态，`libcudart.so.13` = 13.2.86 |
| 进程 cuBLAS | `libcublas.so.13` / `libcublasLt.so.13` = 13.2.2.2 |
| 驱动兼容层 | `cuda-compat-orin-13-2_13.2.44290101-1_arm64.deb` |
| 运行 API | `cudaRuntimeGetVersion=13020`，`cuDriverGetVersion=13020` |

不是“CUDA 13.2 nvcc 编译”；也不是“12.8 二进制套 13.2 库”。复现时必须保持
`nvcc 13.0.88`，见 `BUILD.md` 和 `RUNTIME.md`。

## 3. 为什么做这个组合

上游 issue `ggml-org/llama.cpp#27763` 报告：在 Jetson Thor / SM110 上，CUDA 13.2
工具链编译的 qwen4exp 模型在 GPU 层数较多时出现确定性乱码；同一来源用 CUDA
13.0.88 工具链重建后输出正常。该 issue 的直接对象是 qwen4exp，并未证明本包的
Qwen3.8-27B dense/qwen35 模型一定受影响。

因此本部署的定位是：**在保持 13.2 runtime 不变的前提下，用 13.0.88 编译器降低
已知 SM110 编译风险**。这是风险规避，不是对缺陷已修复的证明，也不是性能优化。

## 4. 严格 A/B 结果

条件：同模型、同 prompt、同输出长度，`cache_prompt=false`，`temperature=0`，
`top_k=1`，`seed=42`；每个组合 3 次；2K 实际 `prompt_n=2067`，8K 实际
`prompt_n=8032`；128-token decode 使用 `ignore_eos=true`。

| 指标 | 13.0.88 编译 + 13.2 runtime | 既有 13.2 原生件 | 变化 |
|---|---:|---:|---:|
| 128-token decode | **27.403 t/s** | **27.849 t/s** | **-1.60%** |
| 2K prefill | **9314.6 ms** | **9099.1 ms** | **慢 2.37%** |
| 8K prefill | **35686.1 ms** | **34834.2 ms** | **慢 2.45%** |
| 2K 后 decode | **14.522 t/s** | **14.726 t/s** | **-1.39%** |
| 8K 后 decode | **36.931 t/s** | **37.258 t/s** | **-0.88%** |

原始 JSON 在 `evidence/bench-*.json`，汇总在 `evidence/bench-ab-summary.json`，
方法见 `BENCHMARKS.md`。

## 5. 包内有什么

```text
README.md                    本文件
SOURCE.md                    上游 commit、补丁、tree hash、模型身份
RUNTIME.md                   13.2 用户态 runtime 的来源和校验
BUILD.md                     13.0.88 交叉编译步骤
DEPLOY.md                    板端安装、切换、启动、冷启动要求
VERIFY.md                    静态、运行态、质量、性能的验收命令
ROLLBACK.md                  回滚到既有 13.2 原生件
BENCHMARKS.md                A/B 方法与完整结果
EVIDENCE.md                  证据索引和最终现场快照
PUBLISHING.md                交给发布者的检查清单和建议文案
LICENSE                      llama.cpp MIT 许可证
NOTICE.md                    第三方软件、模型和 runtime 边界
patches/                     相对上游基线的完整生产补丁
scripts/                     构建、CUDA 13.0 工具链/runtime 获取、预检、质量、bench、探针
board/                       生产 run/switch/rollback 脚本和 systemd unit
artifacts/                   新二进制 + 已验证的 13.2 原生回滚二进制
evidence/                    构建、质量、A/B、运行态和日志证据
```

模型权重和 NVIDIA 专有 runtime 库不随包分发。模型路径、大小和 SHA256 见
`SOURCE.md`；runtime 获取方式见 `RUNTIME.md`。

## 6. 最短使用路径

在发布包根目录：

```bash
sha256sum -c SHA256SUMS
./scripts/verify-artifact.sh
```

在 Thor01 上先安装文件但不切换：

前提：目标板已经有隔离的 `runtime/lib/`（CUDA 13.2）和 `compat/compat_orin/`。
如果还没有，先在宿主机执行 `./scripts/fetch-cu132-runtime.sh ./cu132-runtime`，
再按 `RUNTIME.md` 传到板上；安装脚本不会替你替换系统 CUDA。

```bash
BOARD_ADDR=192.168.1.101 BOARD_USER=nvidia ./scripts/install-board.sh
```

然后由有 sudo 权限的板端用户执行：

```bash
bash /brand_data/ai_workspace/thor01-cu132-20261022/preflight-board.sh --hash-models
sudo EXPECTED_SHA=686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e \
  bash /brand_data/ai_workspace/thor01-cu132-20261022/switch-to-cu130rt132.sh
```

最后在宿主机跑质量门禁：

```bash
python3 scripts/quality_gate.py --host 192.168.1.101 \
  --out evidence/quality-cu130rt132-final.json
```

详细前置条件和冷启动要求见 `DEPLOY.md`；每条验收判据见 `VERIFY.md`。

## 7. 已知边界

- 只在 Thor01 实机验收，不代表其他 Thor 板、其他 DriveOS 内核或其他模型同步通过。
- 13.2 compat 下 T4 守卫不命中；不要声称 T4-MMQ 生效。
- 没有 100K/200K 长上下文严格 A/B。
- 没有做长时间稳定性、并发压力或多用户 soak；质量门禁是短测。
- 发布包不包含模型权重、NVIDIA runtime 库、任何 token 或密码。
