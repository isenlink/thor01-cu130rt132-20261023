# 部署指南（Thor01）

本文假设读者拿到的是完整发布包，目标板就是 Thor01 或同构 Thor 板，并且已有
可用的模型和隔离 CUDA 13.2 runtime。**不要把它当成通用 Thor 一键安装器。**

## 1. 目标板条件

实测 Thor01：

| 项目 | 值 |
|---|---|
| 架构 | aarch64 |
| OS | Ubuntu 24.04.1 LTS |
| kernel | `6.1.119-rt45-prod-rt-tegra` |
| 内存 | 61524140 kB ≈ 58 GiB UMA |
| 大页 | 25600 × 2 MiB = 50 GiB |
| 端口 | 8080 = Qwen3.8-27B；8082 = Qwen3-VL-8B |
| 服务用户 | `nvidia`，允许 `sudo -n` |

板端固定目录：

```text
/brand_data/ai_workspace/thor01-cu132-20261022/
  bin/llama-server-cu130rt132-sm110a       新二进制
  bin/llama-server-cu132-sm110a            已验证的 13.2 原生回滚二进制
  runtime/lib/                             CUDA 13.2 cudart/cublas/cublasLt
  compat/compat_orin/                      cuda-compat-orin
  run-8080-cu130rt132.sh
  run-8082-cu130rt132.sh
  switch-to-cu130rt132.sh
  rollback-to-cu132-native.sh
  systemd/                                 当前生效 unit 母本
  systemd-cu130rt132/                      新组合 unit
  systemd-cu132-native/                    13.2 原生 unit
  logs/
  evidence/
```

`/etc` 在 rw_overlay 上，冷启动会丢。因此所有 unit 必须同时写进
`/brand_data/.../systemd/` 母本；Thor01 的 `/brand_data/restore_overlay.sh` 第 ⑧ 段
会在恢复时把母本重装到 `/etc/systemd/system/` 并 enable/start。发布包中的
`switch-to-cu130rt132.sh` 和 `rollback-to-cu132-native.sh` 都会同步维护这个母本。

## 2. 大页池前置条件

先看板上实况：

```bash
grep -E 'HugePages_(Total|Free)|Hugepagesize' /proc/meminfo
sysctl vm.nr_hugepages
```

Thor01 当前：

```text
HugePages_Total: 25600
HugePages_Free:  9
Hugepagesize:    2048 kB
vm.nr_hugepages = 25600
```

服务未启动时，Free 应接近 Total；服务起来后 Free 只剩个位数是正常现象，因为
大部分池已被常驻分配占用。**这时不能再起第二套 27B**，也不要为了多开服务清空
大页池。

Thor01 的 boot 配置目前同时存在：

```text
/etc/sysctl.conf                    vm.nr_hugepages = 10240   (旧值，必须留意)
/etc/sysctl.d/99-hugepages.conf     vm.nr_hugepages = 25600
/etc/sysctl.d/99-zz-hugepages.conf  vm.nr_hugepages = 25600
```

当前生效值是 25600。为了冷启动可复现，建议在维护窗口把三个位置统一成 25600，
然后**断电/重启一次**让池干净建立。不要在线上反复用 `sysctl -w` 扩/缩池；那会
改变已运行进程的分配条件，不能作为发布验证的替代。重启需要现场授权。

本部署要求“放得下就全驻留”：**不要添加任何权重流式、CPU MoE offload 或按需
换页方案**。如果模型放不下，正确动作是停止部署、重新计算、扩大页池并重启，
而不是加流式后继续测速。

## 3. 模型前置条件

模型权重不随包分发。按以下路径放置，并核对 SHA256。Thor01 实测值：

| 角色 | 路径 | 大小 | SHA256 |
|---|---|---:|---|
| 主模型 | `/brand_data/ai_workspace/models/RadixArk-F8attn-v2.gguf` | 20G | `d15dac916823f590fa8e584ae18a37c62d61947ce33df943a658c83766d2e7e9` |
| DFlash draft | `/brand_data/ai_workspace/ai02/models/Qwen3.8-27B-DFlash2-BF16.gguf` | 3.6G | `26d47ca20ab07688327a63d912acad222d924eaaa92a980cc488de3c67e736bc` |
| 主模型 mmproj | `/brand_data/ai_workspace/models/mmproj-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-BF16.gguf` | 889M | `5681b690bcb8eb10cd28d62d078cb4e01521a3ea4880a3fc7d54de72de2dd142` |
| VL 模型 | `/brand_data/ai_workspace/models/qwen3vl8b/Qwen3-VL-8B-Instruct-Q6_K.gguf` | 6.3G | `f1a6f30ddae86e625cb5f494891b9a2a68169819f42527ef0c65fb46652366b5` |
| VL mmproj | `/brand_data/ai_workspace/models/qwen3vl8b/mmproj-Qwen3-VL-8B-Instruct-F16.gguf` | 1.1G | `30cc93c7375b529b2abe165d1597e12f6717bf87565655a546727c4bd2bb5ada` |

模型哈希检查：

```bash
bash /brand_data/ai_workspace/thor01-cu132-20261022/preflight-board.sh --hash-models
```

## 4. 宿主机安装文件（不切换）

从发布包根目录执行：

```bash
BOARD_ADDR=192.168.1.101 \
BOARD_USER=nvidia \
./scripts/install-board.sh
```

如果使用密码登录，可以在外层用 `sshpass`；不要把密码写进发布包或脚本。安装脚本做：

1. 校验新二进制和 13.2 回滚二进制的 SHA256。
2. 备份板上已有 `bin/llama-server-cu132-sm110a`、旧 run 脚本和旧 unit。
3. 复制新二进制、两个新 run 脚本、两个新 unit、switch/rollback 脚本。
4. 如果板上没有 13.2 原生件，则从 `artifacts/rollback/` 安装发布包内的已验证回滚件。
5. 只安装，不停止现有服务，不切换。

安装后先在板上跑预检（不启动服务）：

预检会校验板上的隔离 CUDA 13.2 runtime；如果 `runtime/lib` 或
`compat/compat_orin` 缺件，先按 `RUNTIME.md` 获取并放置，不能改系统 CUDA
或驱动来绕过。

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
bash $BASE/preflight-board.sh --hash-models
```

预期最后一行：

```text
[preflight] OK
```

## 5. 切换

切换会停止现有 8080/8082，替换 `/etc/systemd/system/` 和 `$BASE/systemd/`，
启动新组合并等待两个 health。命令：

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
sudo EXPECTED_SHA=686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e \
  bash $BASE/switch-to-cu130rt132.sh
```

成功时最后一行：

```text
[switch-cu130rt132] active; 8080/8082 health OK
```

切换脚本的失败路径会自动恢复旧 unit 并尝试拉起旧服务；不要因为脚本说“已回滚”
就假定两个端口一定健康，仍要按 `VERIFY.md` 做 health 检查。

## 6. 服务启动

systemd 单元：

```text
thor01-qwen38-27b.service  -> run-8080-cu130rt132.sh -> 0.0.0.0:8080
thor01-qwen3vl8b.service   -> run-8082-cu130rt132.sh -> 0.0.0.0:8082
```

8080 的关键参数：

```text
-m RadixArk-F8attn-v2.gguf
-md Qwen3.8-27B-DFlash2-BF16.gguf
--mmproj ... --mmproj-offload
-ngl 99 -c 262144 -fa on
--cache-type-k f16 --cache-type-v f16
--spec-type draft-dflash --spec-draft-n-max 7
```

8082 的关键参数：

```text
-m Qwen3-VL-8B-Instruct-Q6_K.gguf
--mmproj ... --mmproj-offload
-ngl 99 -c 20480 -np 1
```

两个服务都是 `Type=oneshot` + `RemainAfterExit=yes`；run 脚本本身在端口已监听时
直接 SKIP，所以重复 start 不会起第二份模型。

## 7. 冷启动

冷启动后只依赖持久层：

1. `/brand_data/restore_overlay.sh` 恢复 `/etc` 和网络。
2. 第 ⑤ 段把大页池恢复到 25600 页。
3. 第 ⑧ 段把 `$BASE/systemd/*.service` 重装到 `/etc/systemd/system/`。
4. 两个服务依次 start；8082 单元显式依赖 8080 单元。

切换后 `$BASE/systemd/` 里的两个 unit 必须使用 `run-*-cu130rt132.sh`；回滚后必须
使用 `run-*-cu132.sh`。检查命令：

```bash
grep -H '^ExecStart=' /etc/systemd/system/thor01-qwen38-27b.service \
  /etc/systemd/system/thor01-qwen3vl8b.service \
  /brand_data/ai_workspace/thor01-cu132-20261022/systemd/*.service
```

四条 `ExecStart` 应全部指向 `cu130rt132`。

## 8. 启动日志检查

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
ls -lt $BASE/logs/*cu130rt132*.log | head
grep -E 'speculative|n_max|listening|error|failed|out of memory' \
  $(ls -t $BASE/logs/radixark-cu130rt132-*.log | head -1) | tail -40
```

成功启动应看到：

```text
adding speculative implementation 'draft-dflash'
- n_max=7, n_min=0, p_min=0.00
listening on http://0.0.0.0:8080
```

8080 首次加载约 20 秒，8082 约 6 秒（Thor01 实测）；不要用固定 10 秒超时判断失败。
日志里 `dflash requires ctx_other to be set` 是启动阶段内存拟合的已知正常告警，
后续能完成加载并监听即可。

## 9. 故障处理

| 现象 | 先做什么 |
|---|---|
| `MISSING ...` | 按第 3 节核对模型路径和 runtime 文件 |
| 端口仍被占用 | 先看 `ss -ltnp`，确认是否有手工 nohup 进程；不要盲目 pkill |
| 8080 起不来 | 看最新日志尾部；确认 50 GiB 池、runtime SHA、模型 SHA |
| 只有 8082 失败 | 8082 会等 8080 监听；先修 8080 |
| `not found` 库 | 检查 `LD_LIBRARY_PATH` 是否指向本目录 compat/runtime |
| 大页不足 | 停止部署，计算所需页数；维护窗口统一 sysctl 后重启，不要流式降级 |
| 回滚 | 见 `ROLLBACK.md`，先验证 13.2 原生件 SHA 73bb… |

## 10. 不要做的事

- 不要修改 `/usr/local/cuda` 或系统 `libcuda`。
- 不要为了跑 T4 而改 `T4_MMQ_CC_THOR` 常量；本轮没有验证 T4 在 13.2 compat 下的正确性。
- 不要在 50 GiB 池已基本耗尽时并行起第二套 27B。
- 不要把 `T4_MMQ=1` 当作“T4 已生效”的证据；判据必须是设备 `cc` 和实际日志/探针。
- 不要把本包的 128-token/2K/8K 数据外推到 100K/200K。
