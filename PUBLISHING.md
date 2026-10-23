# 发布交接（给文强）

本文件是发布前检查清单和建议文案。代码/产物由本机准备，公开发布动作由文强执行。

## 1. 建议发布形态

建议作为一个**独立复现仓库 + GitHub Release asset**，不要直接把 160 MB 二进制提交进
普通 git 历史。

建议标签/目录名：

```text
thor01-cu130rt132-20261023
```

建议 release title：

```text
Thor01 llama.cpp: CUDA 13.0.88 SASS + CUDA 13.2 runtime (SM110a)
```

建议 asset：

```text
thor01-cu130rt132-20261023.tar.gz
thor01-cu130rt132-20261023.tar.gz.sha256
```

仓库里只放解包后的文档、补丁、脚本和证据；大二进制可以通过 release asset 或
Git LFS 单独处理。无论采用哪种方式，`SHA256SUMS` 必须保持一致。

## 2. 发布前必须确认

- [ ] `sha256sum -c SHA256SUMS` 全通过。
- [ ] `./scripts/verify-artifact.sh` 输出 `artifact OK`。
- [ ] 包内没有 `THOR_OP_PASS`、ai-post token、cc-connect secret、SSH 私钥。
- [ ] 包内没有 `*.bak`、`*.orig`、`__pycache__`、模型权重或 NVIDIA runtime 库。
- [ ] `README.md` 明确写着“不是提速版本”和“T4 未命中”。
- [ ] 没有把 100K/200K 或历史前缀缓存数字写成新结论。
- [ ] `ROLLBACK.md` 的 13.2 回滚件 SHA 与新件 SHA 都正确。
- [ ] 模型权重只在文档里给路径和 SHA，不随包分发。
- [ ] 新增脚本已通过 `bash -n` / `python3 -m py_compile`。

## 3. 建议对外结论

可以对外写：

- 在 Thor01（aarch64，58 GiB UMA，kernel 6.1.119 RT）上，把 llama.cpp 编译工具链固定为
  CUDA 13.0.88/SBSA，目标架构 `sm_110a`，运行时使用隔离的 CUDA 13.2 用户态库 +
  cuda-compat-orin。
- 新二进制在板上同时服务 Qwen3.8-27B + DFlash + mmproj（8080）和
  Qwen3-VL-8B（8082），质量门禁 7/7 PASS。
- 严格同条件 A/B：新组合比既有 13.2 原生件慢约 1.6% decode、2.4% prefill；
  部署目的是降低上游 #27763 的 SM110 工具链风险，不是提升速度。
- T4 守卫未命中：13.2 compat 报 `cc=11.0`，生产守卫要求 `10.1a`；本轮没有 T4 加速数据。

不要对外写：

- “CUDA 13.2 编译的二进制”。实际是 13.0.88 编译、13.2 runtime 运行。
- “13.2 比 12.8 快/慢”。本包没有做 12.8 严格 A/B。
- “T4-MMQ 已生效”或任何 T4 专属加速数字。
- “100K/200K 已验证”。本轮没有做。
- “完全修复了 #27763”。上游 issue 仍在，且直接对象是 qwen4exp；本包只是规避性组合。

## 4. 建议 commit / release 文案

```text
Thor01: llama.cpp built with CUDA 13.0.88, running on CUDA 13.2 runtime

This release documents and ships a reproducible Thor01 deployment that compiles
llama.cpp with nvcc 13.0.88 (SBSA/aarch64, sm_110a) while keeping an isolated
CUDA 13.2 user-space runtime and cuda-compat-orin.

Validated on Thor01:
- Qwen3.8-27B + DFlash + mmproj on :8080
- Qwen3-VL-8B on :8082
- 7/7 quality checks passed
- strict A/B versus the existing CUDA 13.2-native binary: about 1.6% slower
  decode and 2.4% slower prefill. This is a risk-mitigation build, not a speedup.

Known limits:
- T4 fast path is not active because CUDA 13.2 compat reports cc=11.0 while the
  production guard expects 10.1a.
- No strict 100K/200K A/B was performed in this release.
- Model weights and NVIDIA runtime libraries are not redistributed.
```

## 5. 文件审计建议

解包后先跑：

```bash
find . -type f | sort
grep -RIlE 'THOR_OP_PASS|MY_TOKEN|admin_token|BEGIN (OPENSSH|RSA) PRIVATE KEY' . \
  --exclude=PUBLISHING.md
find . -name '__pycache__' -o -name '*.bak*' -o -name '*.orig'
```

前两条应该没有输出；第三条也不应有发布物。`evidence/` 中有 SSH 的
`Warning: Permanently added ... known_hosts` 文本，这是连接提示，不是凭据；
如果发布者希望更干净，可以把这类提示从证据文件里删掉，但要保留原始 JSON 证据。
