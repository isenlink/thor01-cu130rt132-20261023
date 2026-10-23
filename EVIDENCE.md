# 证据索引与最终现场快照

所有时间以证据文件内的时间戳为准。宿主和 Thor01 的时钟可能有秒级到分钟级偏差；
质量门禁 JSON 使用宿主时间，板端状态文件使用板端时间。

## 1. 最终结论证据

| 事实 | 证据文件 |
|---|---|
| 最终质量门禁 7/7 | `evidence/quality-cu130rt132-final.json`、`.txt` |
| 最终服务状态、PID、端口、库映射 | `evidence/final-runtime-state.txt` |
| 8080 进程实际映射 compat/runtime 库 | `evidence/final-process-maps.txt` |
| 板端预检通过 | `evidence/preflight-final.txt` |
| T4 守卫未命中 | `evidence/t4-probe-final.txt` |
| 源码补丁 tree 可还原 | `evidence/source-tree-repro.txt` |
| 编译耗时和工具链 | `evidence/build-timeline.txt`、`evidence/toolchain-versions.txt` |
| 静态产物校验 | `scripts/verify-artifact.sh` 输出、`evidence/build/CMakeCache.key.txt` |
| runtime 文件 hash | `evidence/runtime-sha256.txt` |
| 模型文件 hash | `evidence/model-sha256.txt` |
| 严格 A/B 汇总 | `evidence/bench-ab-summary.json`、`BENCHMARKS.md` |

## 2. 最终板端快照

来自 `evidence/final-runtime-state.txt`（板端 `2026-10-23T02:20:01+08:00`）：

```text
host=tegra-ubuntu
Linux 6.1.119-rt45-prod-rt-tegra aarch64
Ubuntu 24.04.1 LTS

thor01-qwen38-27b.service  active / enabled
thor01-qwen3vl8b.service   active / enabled

PID 461997  bin/llama-server-cu130rt132-sm110a ... --port 8080
PID 462129  bin/llama-server-cu130rt132-sm110a ... --port 8082

8080 LISTEN 0.0.0.0:8080
8082 LISTEN 0.0.0.0:8082

new binary SHA256 466f25d4d136035bb1c1b90f672c9fa7a9cdfad03b1c0690675a3d4b265084a7
rollback SHA256   73bb5fc7540cc9b1547b6f5d8d9c3233081b389a758e75be2e09c295584fe1ee

HugePages_Total 25600
HugePages_Free      9
Hugepagesize     2048 kB
vm.nr_hugepages 25600
vm.nr_overcommit_hugepages 0

dmesg_lines 7582
DMESG=NO_MATCHES
```

发布前复检（板端时钟 `2026-10-23T02:27:21+08:00`，宿主时钟约快 12 分钟，
`NTPSynchronized=no`）见 `evidence/final-runtime-state-20261023-0239.txt`：
两服务仍 active+enabled，两个端口仍在监听，新/旧二进制 SHA 仍分别为
`466f25d4…` / `73bb5fc7…`，大页池仍为 25600 页、Free=9，dmesg 无匹配。
时间戳相关性以事件顺序和文件内容为准，不能只靠板端墙钟比较先后。

`/etc/systemd/system/` 和 `$BASE/systemd/` 的 unit 哈希两两相同：

```text
452657d7ba48725d5b67946d45be372122122a46fad98f5420982a60e095d256  thor01-qwen38-27b.service
4629d129dfa1d51b1ca7006df7cd84ddb8038107bb7b64957152f61ae60071a0  thor01-qwen3vl8b.service
```

四条 `ExecStart` 全部指向 `run-8080-cu130rt132.sh` / `run-8082-cu130rt132.sh`。

## 3. 启动日志证据

8080：

```text
loading draft model 'Qwen3.8-27B-DFlash2-BF16.gguf'
adding speculative implementation 'draft-dflash'
- n_max=7, n_min=0, p_min=0.00
- block_size=8, mask_token_id=248070, n_extract=5, sample_from_anchor=true
listening on http://0.0.0.0:8080
```

8082：

```text
listening on http://0.0.0.0:8082
```

完整日志：`evidence/board-logs/radixark-cu130rt132-8080.log` 和
`evidence/board-logs/qwen3vl8b-cu130rt132-8082.log`。启动日志里
`dflash requires ctx_other to be set` 是内存拟合阶段已知告警，不是最终失败；
后面正常出现 DFlash 配置和监听行。

早期 `evidence/post-switch-state.txt` 里有一行 `cudaMalloc failed: out of memory`。
那是当时用一个临时探针在服务已占满大页池后尝试 `cudaMalloc` 的结果，不是 llama-server
发生 OOM；最终 `dmesg` 无 OOM/Xid，两个服务也一直 active。后续最终探针只读设备属性，
不分配 GPU 内存，输出见 `evidence/t4-probe-final.txt`。

## 4. 质量证据

最终门禁 JSON 时间为 `2026-10-23T02:32:25+0800`；早先切换后的门禁和最终重跑
两次均为：

```text
health_8080 PASS
health_8082 PASS
8080_short PASS
8080_digit_copy PASS
8080_json PASS
8082_short PASS
8082_red_image PASS
```

发布前又从宿主机独立重跑一次，JSON 时间为 `2026-10-23T02:39:41+0800`，
`failures=[]`，同样 7/7；证据为
`evidence/quality-cu130rt132-current-20261023.json`。

`8080_digit_copy` 返回原文：

```text
82947103655829174063829517402938
```

`8080_json` 返回：

```json
{"answer": 2, "unit": "ok"}
```

`8082_red_image` 返回：

```text
红色
```

## 5. A/B 证据

使用：

```text
bench-cu130rt132-8080.json
bench-cu130rt132-8080-run2.json
bench-cu130rt132-8080-run3.json
bench-cu132-native-8080-run1.json
bench-cu132-native-8080-run2.json
bench-cu132-native-8080-run3.json
```

排除：

```text
bench-cu132-native-8080.json   # 正式 A/B 前的单次预跑，仅保留参考
```

汇总文件给出 3 次均值：

```text
new decode128 27.4032 t/s   old 27.8494 t/s   -1.6021%
new prefill2k 9314.5893 ms  old 9099.0863 ms  +2.3684% 耗时
new prefill8k 35686.0763 ms old 34834.2113 ms +2.4455% 耗时
new post2k    14.5218 t/s   old 14.7259 t/s   -1.3857%
new post8k    36.9308 t/s   old 37.2578 t/s   -0.8777%
```

新组合更慢。部署理由是降低 #27763 的 SM110 工具链风险，不是速度。

## 6. 回滚演练证据

`evidence/rollback-verified-state.txt` 记录：

- 回滚后 8080/8082 都 active；
- PID 为旧二进制；
- 旧二进制 SHA 恢复为 `73bb5fc7…`；
- 回滚质量门禁 7/7，见 `evidence/quality-cu132-native-rollback.json`。

演练完成后已重新切回新组合，本文件第 2 节是最终状态。回滚脚本本轮又补了
`systemctl enable` 和 health 失败返回非零；包内脚本已在回滚演练后做过语法检查，
但“带 enable 的最终脚本”没有再次执行第二次回滚，因为当前生产已切回新组合。

## 7. 没有的证据

- 没有 100K/200K 严格 A/B。
- 没有并发吞吐/多用户 soak。
- 没有 T4 快路性能；探针明确显示未命中。
- 没有 12.8 的严格 A/B；12.8 不是本次部署目标。
