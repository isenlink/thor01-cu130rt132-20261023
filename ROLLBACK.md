# 回滚

发布包支持回滚到 Thor01 上已经验证过的 **CUDA 13.2 原生件**。回滚二进制已放在
`artifacts/rollback/llama-server-cu132-sm110a`，SHA256：

```text
8a0655ca61007d4ce57bab6a3e24a6d51768ad2ec46ad807f082dbd8dec919c8
```

回滚只换二进制和 unit 母本，不改模型、不改 runtime、不改系统 CUDA、不动大页池。

## 1. 回滚前检查

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
sha256sum $BASE/bin/llama-server-cu132-sm110a
ls -l $BASE/systemd-cu132-native/thor01-qwen38-27b.service \
  $BASE/systemd-cu132-native/thor01-qwen3vl8b.service
```

二进制 SHA 必须等于上面的 `73bb…`。如果板上没有这个文件，用发布包安装：

```bash
scp artifacts/rollback/llama-server-cu132-sm110a \
  nvidia@192.168.1.101:/brand_data/ai_workspace/thor01-cu132-20261022/bin/
ssh nvidia@192.168.1.101 \
  'chmod +x /brand_data/ai_workspace/thor01-cu132-20261022/bin/llama-server-cu132-sm110a'
```

如果 `systemd-cu132-native/` 缺失，从发布包复制：

```bash
scp board/rollback-cu132-native/*.service board/rollback-cu132-native/*.sh \
  nvidia@192.168.1.101:/tmp/rollback-cu132/
# 再在板上分别放到 $BASE/ 和 $BASE/systemd-cu132-native/
```

正常通过 `install-board.sh` 安装时，这些文件已经就位。

## 2. 执行回滚

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
sudo EXPECTED_SHA=8a0655ca61007d4ce57bab6a3e24a6d51768ad2ec46ad807f082dbd8dec919c8 \
  bash $BASE/rollback-to-cu132-native.sh
```

脚本会：

1. 停止两个新服务。
2. 校验旧二进制 SHA256。
3. 从 `systemd-cu132-native/` 恢复两个 unit 到 `/etc/systemd/system/`。
4. 同步写回 `$BASE/systemd/` 母本（保证冷启动恢复的也是 13.2 原生）。
5. `daemon-reload`、enable、start。
6. 等两个 health，任一失败返回非零。

成功时最后一行是旧二进制 SHA。务必再独立检查：

```bash
systemctl is-active thor01-qwen38-27b.service thor01-qwen3vl8b.service
ss -ltnp | grep -E ':(8080|8082) '
grep -H '^ExecStart=' /etc/systemd/system/thor01-qwen38-27b.service \
  /etc/systemd/system/thor01-qwen3vl8b.service \
  $BASE/systemd/*.service
```

四条 `ExecStart` 应全部指向 `run-*-cu132.sh`，且两个进程 argv[0] 应为
`bin/llama-server-cu132-sm110a`。

质量门禁仍用同一脚本：

```bash
python3 scripts/quality_gate.py --host 192.168.1.101 \
  --out evidence/quality-cu132-native-rollback.json
```

2026-10-23 已实际演练过一次回滚，结果：

- 8080/8082 health 200。
- 质量门禁 7/7 PASS。
- 二进制 SHA 恢复为 `73bb5fc7…`。
- 回滚后证据在 `evidence/quality-cu132-native-rollback.json` 和
  `evidence/rollback-verified-state.txt`。

演练完成后已重新切回新组合；当前生产状态以 `EVIDENCE.md` 的最终快照为准。

## 3. 回滚失败

如果 health 不通过：

1. 不要反复重启服务；先看最新 `logs/radixark-cu132-*.log` 和
   `logs/qwen3vl8b-cu132-*.log`。
2. 检查端口是否被手工 nohup 进程占用。
3. 检查 `$BASE/systemd/` 是否真的被写回旧 unit。
4. 如果 `/etc` 已损坏，用 `/brand_data/restore_overlay.sh` 触发母本恢复；
   它会按 `$BASE/systemd/` 的当前内容重建并启动。
5. 仍不恢复时，现场需要重启/断电前先在主对话通知负责人，不要自行连续试。

## 4. 关于 12.8 回滚

Thor01 板上还保留了历史 `rollback-to-cu128.sh`，但它依赖更早的
`backup/units/`、12.8 部署目录和独立运行时。该链路不属于本次 13.2 发布包，
也没有在本轮重新演练。除非现场明确需要且这些前置件齐全，否则不要用 12.8
回滚来替代本包的 13.2 原生回滚。

## 5. 回滚后重新切回新组合

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
sudo EXPECTED_SHA=686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e \
  bash $BASE/switch-to-cu130rt132.sh
```

切换后必须重新跑 `VERIFY.md` 的质量门禁；不要沿用回滚前的 JSON。
