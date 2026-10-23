#!/bin/bash
set -euo pipefail

BASE=${THOR_LLM_BASE:-/brand_data/ai_workspace/thor01-cu132-20261022}
OLD_UNITS=$BASE/systemd-cu132-native
OLD_BIN=$BASE/bin/llama-server-cu132-sm110a
EXPECTED_SHA=${EXPECTED_SHA:-8a0655ca61007d4ce57bab6a3e24a6d51768ad2ec46ad807f082dbd8dec919c8}

[ -f "$OLD_UNITS/thor01-qwen38-27b.service" ] || { echo "missing archived units" >&2; exit 2; }
[ -x "$OLD_BIN" ] || { echo "missing rollback binary: $OLD_BIN" >&2; exit 2; }
got=$(sha256sum "$OLD_BIN" | awk '{print $1}')
[ "$got" = "$EXPECTED_SHA" ] || { echo "rollback binary sha256 mismatch: $got" >&2; exit 2; }

sudo -n systemctl stop thor01-qwen3vl8b.service 2>/dev/null || true
sudo -n systemctl stop thor01-qwen38-27b.service 2>/dev/null || true
for pf in "$BASE"/logs/qwen3vl8b-*.pid "$BASE"/logs/radixark-*.pid; do
  [ -f "$pf" ] || continue
  pid=$(cat "$pf" 2>/dev/null || true)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
done
for _ in $(seq 1 60); do
  ss -tln 2>/dev/null | grep -Eq ':(8080|8082) ' || break
  sleep 1
done

sudo -n cp -p "$OLD_UNITS"/*.service /etc/systemd/system/
sudo -n cp -p "$OLD_UNITS"/*.service "$BASE/systemd/"
sudo -n systemctl daemon-reload
sudo -n systemctl enable thor01-qwen38-27b.service thor01-qwen3vl8b.service
sudo -n systemctl start thor01-qwen38-27b.service
sudo -n systemctl start thor01-qwen3vl8b.service

failed=0
for port in 8080 8082; do
  healthy=0
  for _ in $(seq 1 300); do
    if python3 - "$port" <<'PY'
import sys, urllib.request
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/health", timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
PY
    then healthy=1; break; fi
    sleep 1
  done
  if [ "$healthy" -ne 1 ]; then
    echo "[rollback-cu132] port $port health check failed" >&2
    failed=1
  fi
done

[ "$failed" -eq 0 ] || exit 3

echo "[rollback-cu132] restored native CUDA 13.2 units"
sha256sum "$OLD_BIN"
