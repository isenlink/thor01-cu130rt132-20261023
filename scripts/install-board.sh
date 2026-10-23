#!/bin/bash
set -euo pipefail

BOARD_ADDR=${BOARD_ADDR:?set BOARD_ADDR}
BOARD_USER=${BOARD_USER:-nvidia}
BASE=${THOR_LLM_BASE:-/brand_data/ai_workspace/thor01-cu132-20261022}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ART=$ROOT/artifacts/llama-server-cu130rt132-sm110a
ART_ROLLBACK=$ROOT/artifacts/rollback/llama-server-cu132-sm110a
SSH_OPTS=${SSH_OPTS:--o StrictHostKeyChecking=accept-new}
SSH_CMD=${SSH_CMD:-ssh}
SCP_CMD=${SCP_CMD:-scp}
EXPECTED_NEW=686b251fa6e43b5eb762177f66a6cfaa3624153fd7a05dd274c055653e63ed7e
EXPECTED_ROLLBACK=8a0655ca61007d4ce57bab6a3e24a6d51768ad2ec46ad807f082dbd8dec919c8

[ -x "$ART" ] || { echo "missing $ART" >&2; exit 2; }
[ -x "$ART_ROLLBACK" ] || { echo "missing $ART_ROLLBACK" >&2; exit 2; }
[ "$(sha256sum "$ART" | awk '{print $1}')" = "$EXPECTED_NEW" ] || { echo "new artifact sha256 mismatch" >&2; exit 2; }
[ "$(sha256sum "$ART_ROLLBACK" | awk '{print $1}')" = "$EXPECTED_ROLLBACK" ] || { echo "rollback artifact sha256 mismatch" >&2; exit 2; }
sha256sum "$ART" "$ART_ROLLBACK"

$SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "mkdir -p '$BASE/bin' '$BASE/backup/pre-cu130-20261023' '$BASE/systemd-cu130rt132' '$BASE/systemd-cu132-native' '$BASE/evidence'"

$SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" \
  "cd '$BASE' && cp -a bin/llama-server-cu132-sm110a backup/pre-cu130-20261023/ 2>/dev/null || true; cp -a run-8080-cu132.sh run-8082-cu132.sh backup/pre-cu130-20261023/ 2>/dev/null || true; cp -a systemd/*.service backup/pre-cu130-20261023/ 2>/dev/null || true"

if $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "test -f '$BASE/bin/llama-server-cu132-sm110a'"; then
  $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" \
    "test \"\$(sha256sum '$BASE/bin/llama-server-cu132-sm110a' | awk '{print \$1}')\" = '$EXPECTED_ROLLBACK' || echo 'WARN: existing CUDA 13.2 binary differs from release fallback; it was left untouched' >&2"
else
  tmp_rollback="$BASE/bin/.llama-server-cu132-sm110a.new.$$"
  $SCP_CMD $SSH_OPTS "$ART_ROLLBACK" "$BOARD_USER@$BOARD_ADDR:$tmp_rollback"
  $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "mv -f '$tmp_rollback' '$BASE/bin/llama-server-cu132-sm110a'"
fi

if ! $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "test -f '$BASE/run-8080-cu132.sh'"; then
  $SCP_CMD $SSH_OPTS "$ROOT/board/rollback-cu132-native/run-8080-cu132.sh" "$BOARD_USER@$BOARD_ADDR:$BASE/"
fi
if ! $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "test -f '$BASE/run-8082-cu132.sh'"; then
  $SCP_CMD $SSH_OPTS "$ROOT/board/rollback-cu132-native/run-8082-cu132.sh" "$BOARD_USER@$BOARD_ADDR:$BASE/"
fi
if ! $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "test -f '$BASE/systemd-cu132-native/thor01-qwen38-27b.service'"; then
  $SCP_CMD $SSH_OPTS "$ROOT/board/rollback-cu132-native/thor01-qwen38-27b.service" "$BOARD_USER@$BOARD_ADDR:$BASE/systemd-cu132-native/"
fi
if ! $SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "test -f '$BASE/systemd-cu132-native/thor01-qwen3vl8b.service'"; then
  $SCP_CMD $SSH_OPTS "$ROOT/board/rollback-cu132-native/thor01-qwen3vl8b.service" "$BOARD_USER@$BOARD_ADDR:$BASE/systemd-cu132-native/"
fi

tmp_new="$BASE/bin/.llama-server-cu130rt132-sm110a.new.$$"
$SCP_CMD $SSH_OPTS "$ART" "$BOARD_USER@$BOARD_ADDR:$tmp_new"
$SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "mv -f '$tmp_new' '$BASE/bin/llama-server-cu130rt132-sm110a'"
$SCP_CMD $SSH_OPTS "$ROOT/board/run-8080-cu130rt132.sh" "$ROOT/board/run-8082-cu130rt132.sh" "$BOARD_USER@$BOARD_ADDR:$BASE/"
$SCP_CMD $SSH_OPTS "$ROOT/board/thor01-qwen38-27b.service" "$ROOT/board/thor01-qwen3vl8b.service" "$BOARD_USER@$BOARD_ADDR:$BASE/systemd-cu130rt132/"
$SCP_CMD $SSH_OPTS "$ROOT/board/switch-to-cu130rt132.sh" "$ROOT/board/rollback-to-cu132-native.sh" "$BOARD_USER@$BOARD_ADDR:$BASE/"
$SCP_CMD $SSH_OPTS "$ROOT/scripts/preflight-board.sh" "$ROOT/scripts/device_probe.py" "$BOARD_USER@$BOARD_ADDR:$BASE/"

$SSH_CMD $SSH_OPTS "$BOARD_USER@$BOARD_ADDR" "chmod +x '$BASE'/run-8080-cu130rt132.sh '$BASE'/run-8082-cu130rt132.sh '$BASE'/run-8080-cu132.sh '$BASE'/run-8082-cu132.sh '$BASE'/switch-to-cu130rt132.sh '$BASE'/rollback-to-cu132-native.sh '$BASE'/preflight-board.sh '$BASE'/device_probe.py '$BASE'/bin/llama-server-cu130rt132-sm110a '$BASE'/bin/llama-server-cu132-sm110a"

echo "installed; not switched. Run on board: sudo $BASE/switch-to-cu130rt132.sh"
