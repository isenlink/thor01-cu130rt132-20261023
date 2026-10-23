#!/bin/bash
set -euo pipefail

BASE=${THOR_LLM_BASE:-/brand_data/ai_workspace/thor01-cu132-20261022}
NEW_UNITS=$BASE/systemd-cu130rt132
OLD_UNITS=$BASE/systemd-cu132-native
NEW_BIN=$BASE/bin/llama-server-cu130rt132-sm110a
OLD_BIN=$BASE/bin/llama-server-cu132-sm110a
EXPECTED_SHA=${EXPECTED_SHA:-}

log() { echo "[switch-cu130rt132] $*"; }
die() { echo "[switch-cu130rt132] ERROR: $*" >&2; exit 2; }

[ -x "$NEW_BIN" ] || die "missing $NEW_BIN"
[ -f "$NEW_UNITS/thor01-qwen38-27b.service" ] || die "missing new units"
[ -f "$OLD_UNITS/thor01-qwen38-27b.service" ] || die "missing archived old units"
if [ -n "$EXPECTED_SHA" ]; then
  got=$(sha256sum "$NEW_BIN" | awk '{print $1}')
  [ "$got" = "$EXPECTED_SHA" ] || die "sha256 mismatch: $got != $EXPECTED_SHA"
fi

stop_pair() {
  sudo -n systemctl stop thor01-qwen3vl8b.service 2>/dev/null || true
  sudo -n systemctl stop thor01-qwen38-27b.service 2>/dev/null || true
  for pf in "$BASE"/logs/qwen3vl8b-*.pid "$BASE"/logs/radixark-*.pid; do
    [ -f "$pf" ] || continue
    pid=$(cat "$pf" 2>/dev/null || true)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  for _ in $(seq 1 60); do
    if ! ss -tln 2>/dev/null | grep -Eq ':(8080|8082) '; then return 0; fi
    sleep 1
  done
  ss -ltnp | grep -E ':(8080|8082) ' >&2 || true
  die "ports still busy after stop"
}

wait_health() {
  port=$1
  for _ in $(seq 1 600); do
    if python3 - "$port" <<'PY'
import sys, urllib.request
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/health", timeout=2) as r:
        sys.exit(0 if r.status == 200 else 1)
except Exception:
    sys.exit(1)
PY
    then return 0; fi
    sleep 1
  done
  return 1
}

restore_old_units() {
  sudo -n cp -p "$OLD_UNITS"/*.service /etc/systemd/system/
  sudo -n cp -p "$OLD_UNITS"/*.service "$BASE/systemd/"
  sudo -n systemctl daemon-reload
}

mkdir -p "$BASE/evidence"
{
  date
  systemctl is-active thor01-qwen38-27b.service || true
  systemctl is-active thor01-qwen3vl8b.service || true
  sha256sum "$NEW_BIN" "$OLD_BIN"
  ss -ltnp | grep -E ':(8080|8082) ' || true
} > "$BASE/evidence/pre-switch-cu130rt132.txt" 2>&1

stop_pair
sudo -n cp -p "$NEW_UNITS"/*.service /etc/systemd/system/
sudo -n cp -p "$NEW_UNITS"/*.service "$BASE/systemd/"
sudo -n systemctl daemon-reload
sudo -n systemctl enable thor01-qwen38-27b.service thor01-qwen3vl8b.service

log "starting 8080"
if ! sudo -n systemctl start thor01-qwen38-27b.service || ! wait_health 8080; then
  echo "[switch-cu130rt132] 8080 failed; rolling back" >&2
  restore_old_units
  sudo -n systemctl start thor01-qwen38-27b.service || true
  sudo -n systemctl start thor01-qwen3vl8b.service || true
  wait_health 8080 || true
  wait_health 8082 || true
  exit 3
fi
log "starting 8082"
if ! sudo -n systemctl start thor01-qwen3vl8b.service || ! wait_health 8082; then
  echo "[switch-cu130rt132] 8082 failed; rolling back" >&2
  sudo -n systemctl stop thor01-qwen3vl8b.service 2>/dev/null || true
  restore_old_units
  sudo -n systemctl start thor01-qwen38-27b.service || true
  sudo -n systemctl start thor01-qwen3vl8b.service || true
  wait_health 8080 || true
  wait_health 8082 || true
  exit 4
fi

log "active; 8080/8082 health OK"
