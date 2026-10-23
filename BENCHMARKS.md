# 严格 A/B 方法与本轮结果

## 1. 目标

回答一个问题：**在 runtime 不变的前提下，把编译工具链从既有 13.2 原生件换成
CUDA 13.0.88 编译，速度会怎样？**

这不是 T4 调优实验，也不是长上下文实验。T4 在本组合下没有命中，见 `RUNTIME.md`。

## 2. 固定条件

| 项目 | 值 |
|---|---|
| 模型 | `RadixArk-F8attn-v2.gguf` |
| draft | `Qwen3.8-27B-DFlash2-BF16.gguf` |
| mmproj | `mmproj-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-BF16.gguf` |
| 服务 | 8080，`--parallel 1`，`-c 262144`，DFlash `n_max=7` |
| KV | `f16` / `f16` |
| prompt cache | `cache_prompt=false` |
| 采样 | `temperature=0`，`top_k=1`，`seed=42` |
| decode | `n_predict=128`，`ignore_eos=true` |
| 2K | 同一长文本，实际 `prompt_n=2067` |
| 8K | 同一长文本，实际 `prompt_n=8032` |
| 次数 | 每个组合 3 次，取均值 |

请求和计时都来自 llama-server `/completion` 返回的 `timings`；脚本文本在
`scripts/bench_matrix.py`，prompt SHA256 记录在每个 JSON 内。

## 3. 使用哪些 run

新组合：

```text
evidence/bench-cu130rt132-8080.json        run 1
evidence/bench-cu130rt132-8080-run2.json   run 2
evidence/bench-cu130rt132-8080-run3.json   run 3
```

既有 13.2 原生：

```text
evidence/bench-cu132-native-8080-run1.json
evidence/bench-cu132-native-8080-run2.json
evidence/bench-cu132-native-8080-run3.json
```

早期的 `evidence/bench-cu132-native-8080.json`（01:59）是在正式 A/B 批次之前
的单次预跑，**不纳入 3 次均值**，但保留作为独立性参考。

## 4. 结果

### 新组合（3 次均值）

| 指标 | run1 | run2 | run3 | 均值 |
|---|---:|---:|---:|---:|
| decode128 t/s | 27.3188 | 27.4367 | 27.4542 | **27.4032** |
| 2K prefill ms | 9329.353 | 9311.410 | 9303.005 | **9314.589** |
| 8K prefill ms | 35670.911 | 35692.410 | 35694.908 | **35686.076** |
| 2K 后 decode t/s | 14.5201 | 14.5207 | 14.5247 | **14.5218** |
| 8K 后 decode t/s | 36.5068 | 37.1473 | 37.1383 | **36.9308** |

### 既有 13.2 原生（3 次均值）

| 指标 | run1 | run2 | run3 | 均值 |
|---|---:|---:|---:|---:|
| decode128 t/s | 27.8250 | 27.8656 | 27.8576 | **27.8494** |
| 2K prefill ms | 9117.256 | 9093.219 | 9086.784 | **9099.086** |
| 8K prefill ms | 34820.153 | 34842.439 | 34840.042 | **34834.211** |
| 2K 后 decode t/s | 14.7116 | 14.7286 | 14.7375 | **14.7259** |
| 8K 后 decode t/s | 37.0902 | 37.3595 | 37.3237 | **37.2578** |

### 变化

| 指标 | 变化 | 解释 |
|---|---:|---|
| decode128 | **-1.60%** | 新组合更慢 |
| 2K prefill | **+2.37% 耗时** | 新组合更慢 |
| 8K prefill | **+2.45% 耗时** | 新组合更慢 |
| 2K 后 decode | **-1.39%** | 新组合更慢 |
| 8K 后 decode | **-0.88%** | 新组合更慢 |

计算：`(new / old - 1) × 100%`；对 prefill，正数表示耗时增加（更慢）。

## 5. 解释

差异的方向一致：**13.0.88 编译版在 decode 和 prefill 上都略慢**。差异不大，
但五项指标同向，足以说明它不是“换编译器后更快”。

由于 T4 守卫没有命中，两个二进制都在通用 CUDA 路径上运行；本轮差异可以归因于
编译工具链生成代码的差别，而不是 T4 快路开关。仍然不能把它当成严格的因果分解：
两个二进制不是同一份源码在同一天用两套完整工具链重新构建的受控实验，且运行顺序
没有随机化。这里的结论只适用于“这两个已存在二进制在本板上的实测”。

## 6. 不能从本报告得到什么

- 不能得到 100K/200K 的 prefill/decode 结论；本轮没有跑。
- 不能得到并发/多用户吞吐；本轮是单 slot 顺序请求。
- 不能得到长时间热稳定或 24h soak；本轮是短测。
- 不能得到 T4 快路性能；T4 没有命中。
- 不能因为质量门禁 7/7 就推断所有模型、所有 prompt 都不会出现数值问题；它只是
  生产烟测，不是完整评测集。
