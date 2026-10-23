# 验收指南

验收分四层：包完整性、静态产物、板端运行态、质量门禁。四层都通过才可称为
“本发布已在目标板验证”。性能 A/B 是解释性证据，不是部署推荐的门槛。

## 1. 包完整性

在解包目录执行：

```bash
sha256sum -c SHA256SUMS
cat MANIFEST.sha256
```

预期没有任何 `FAILED`。发布 tar 的 SHA256 单独放在同级 `*.tar.gz.sha256`。

## 2. 静态产物

```bash
./scripts/verify-artifact.sh
```

脚本会自动在 `CUDA_HOME`、`CUDA_PATH`、常见 CUDA 13.x 路径和 `PATH` 中寻找能读取
`sm_110a` 的 `cuobjdump`；也可以显式指定：

```bash
CUOBJDUMP=/path/to/cuobjdump ./scripts/verify-artifact.sh
```

必须输出：

```text
sha256 OK
ELF OK
NEEDED OK
sm_110a cubins=144
artifact OK
```

手工复核：

```bash
file artifacts/llama-server-cu130rt132-sm110a
readelf -d artifacts/llama-server-cu130rt132-sm110a | grep NEEDED
sha256sum artifacts/llama-server-cu130rt132-sm110a \
  artifacts/rollback/llama-server-cu132-sm110a
```

关键 SHA256：

| 文件 | SHA256 |
|---|---|
| 新件 | `686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e` |
| 13.2 原生回滚件 | `8a0655ca61007d4ce57bab6a3e24a6d51768ad2ec46ad807f082dbd8dec919c8` |

`NEEDED` 必须包含 `libcudart.so.13`、`libcublas.so.13`、
`libcublasLt.so.13`、`libcuda.so.1`。

## 3. 源码补丁可还原

在一台有 git 的宿主机上：

```bash
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
git checkout 72797e89198ab564fd0e6baa54ab196e8dd1d884
git apply /path/to/patches/production-sm110a-t4-dflash.patch
git add -A
git write-tree
```

最后一条必须为：

```text
5ff7bf075c7363e62e662d53bb9d235367eecf1d
```

补丁 SHA256 必须为：

```text
996e46dcd755576f800d5357516cb7128c72d5646757467467f4ee2a946b0a4d
```

2026-10-23 已在临时 worktree 上实际做过一次，结果一致。`git apply` 会报告若干
trailing-whitespace warning，这是生产补丁原有内容；只要 `write-tree` 一致即可。

## 4. 板端运行态

### 4.1 服务和端口

```bash
systemctl is-active thor01-qwen38-27b.service thor01-qwen3vl8b.service
systemctl is-enabled thor01-qwen38-27b.service thor01-qwen3vl8b.service
ss -ltnp | grep -E ':(8080|8082) '
pgrep -a llama-server
```

判据：

- 两服务都 `active`，都 `enabled`。
- 8080、8082 都在 `0.0.0.0` 监听。
- 两个进程的 argv[0] 都是 `bin/llama-server-cu130rt132-sm110a`。

Thor01 最终实测 PID：8080=`461997`，8082=`462129`（PID 会随重启变化，不能作为
长期判据）。

### 4.2 unit 母本一致

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
sha256sum /etc/systemd/system/thor01-qwen38-27b.service \
  /etc/systemd/system/thor01-qwen3vl8b.service \
  $BASE/systemd/thor01-qwen38-27b.service \
  $BASE/systemd/thor01-qwen3vl8b.service
grep -H '^ExecStart=' /etc/systemd/system/thor01-qwen38-27b.service \
  /etc/systemd/system/thor01-qwen3vl8b.service \
  $BASE/systemd/*.service
```

Thor01 实测 unit SHA256：

```text
452657d7ba48725d5b67946d45be372122122a46fad98f5420982a60e095d256  thor01-qwen38-27b.service
4629d129dfa1d51b1ca7006df7cd84ddb8038107bb7b64957152f61ae60071a0  thor01-qwen3vl8b.service
```

四条 `ExecStart` 必须都指向 `run-8080-cu130rt132.sh` / `run-8082-cu130rt132.sh`。

### 4.3 库映射

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
LD_LIBRARY_PATH=$BASE/compat/compat_orin:$BASE/runtime/lib \
  ldd $BASE/bin/llama-server-cu130rt132-sm110a | grep -E 'cuda|cublas|not found'
```

必须映射到本目录的 `runtime/lib` 和 `compat/compat_orin`，不能有 `not found`。

### 4.4 大页和内存

```bash
grep -E 'HugePages_(Total|Free)|Hugepagesize' /proc/meminfo
head -5 /proc/meminfo
```

Thor01 最终快照：

```text
HugePages_Total:   25600
HugePages_Free:        9
Hugepagesize:       2048 kB
MemTotal:        61524140 kB
MemFree:           615564 kB
MemAvailable:      2127868 kB
```

服务已驻留时 `HugePages_Free` 很小是预期结果，不是要求“空闲越多越健康”。
如果 Total 小于 25600，说明冷启动页池没有建立正确，不要继续做性能测试。

### 4.5 T4 守卫

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
python3 $BASE/device_probe.py
```

Thor01 实测：

```text
devices=1 name=Thor cc=11.0 cc_code=1100 runtime=13020 driver=13020
T4_GUARD=NOT_MATCHED expected_cc_code=1010
```

这是**预期结果**，不是部署失败。T4 快路没有生效；本轮不声称 T4 性能。

### 4.6 内核事件

```bash
sudo dmesg | grep -Ei 'Xid|out of memory|oom-kill|timeout|nvgpu:.*(fault|error)' | tail -40
```

最终快照中 7576 行 dmesg 无匹配。若出现 Xid、OOM 或 nvgpu fault，停止服务并
保留日志；不要继续性能测试。

## 5. 质量门禁

从宿主机：

```bash
python3 scripts/quality_gate.py --host 192.168.1.101 \
  --out evidence/quality-cu130rt132-final.json
```

必须 7/7 PASS：

| 项 | 判据 | Thor01 结果 |
|---|---|---|
| `health_8080` | HTTP 200 + `{"status":"ok"}` | PASS |
| `health_8082` | HTTP 200 + `{"status":"ok"}` | PASS |
| `8080_short` | `1+1` 只回答 `2` | PASS |
| `8080_digit_copy` | 精确复制 32 位数字串 | PASS |
| `8080_json` | 输出 JSON 恰好等于 `{"answer":2,"unit":"ok"}` | PASS |
| `8082_short` | `1+1` 只回答 `2` | PASS |
| `8082_red_image` | 64×64 红图回答“红色” | PASS |

最终证据：`evidence/quality-cu130rt132-final.json`，`failures=[]`。

## 6. 性能复核（可选）

```bash
python3 scripts/bench_matrix.py --base-url http://192.168.1.101:8080 \
  --tag local-run1 --out evidence/bench-local-run1.json
```

每次请求都会设置 `cache_prompt=false`、`temperature=0`、`top_k=1`、`seed=42`。
最好连续跑 3 次，和 `evidence/bench-ab-summary.json` 对照。注意：

- 不要打乱 trial 名或混用历史带前缀缓存的数据。
- 不要把 2K/8K prefill 的数字当作 100K/200K。
- 不要把 decode128 和 prefill 后的 decode 混为一个“t/s”。

## 7. 验收通过条件

以下全部满足才可收尾：

1. `SHA256SUMS` 全通过。
2. `verify-artifact.sh` 输出 `artifact OK`。
3. 两个 unit active + enabled，四个 `ExecStart` 指向新脚本。
4. 两个 8080/8082 health 200。
5. 质量门禁 7/7 PASS。
6. `device_probe` 明确显示 T4 未命中。
7. dmesg 无 Xid/OOM/timeout/nvgpu fault。
8. `$BASE/systemd/` 母本已是新 unit，冷启动不会回旧组合。
