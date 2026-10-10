#!/usr/bin/env bash
# Shared helpers for backup.sh, restore.sh and upgrade.sh. Sourced, not run.

APP_DIR=/opt/n8n
BACKUP_ID_RE='^[0-9]{8}T[0-9]{6}Z$'

load_env() {
  cd "$APP_DIR"
  set -a
  # shellcheck source=/dev/null
  . "$APP_DIR/.env"
  set +a
}

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

compose() {
  docker compose --project-directory "$APP_DIR" "$@"
}

set_env_value() {
  local key=$1 value=$2
  sed -i "s|^${key}=.*|${key}=${value}|" "$APP_DIR/.env"
}

# Waits until n8n answers its health endpoint on the loopback port.
wait_healthy() {
  local timeout=${1:-180} waited=0
  until curl --silent --fail --max-time 5 http://127.0.0.1:5678/healthz >/dev/null; do
    if (( waited >= timeout )); then
      log "n8n not healthy after ${timeout}s"
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
  log "n8n healthy"
}
