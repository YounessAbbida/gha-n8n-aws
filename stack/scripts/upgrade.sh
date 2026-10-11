#!/usr/bin/env bash
# One-command n8n upgrade with automatic rollback.
# Usage: sudo /opt/n8n/scripts/upgrade.sh <version>     e.g. 2.43.0
#
# 1. Takes a fresh backup.
# 2. Pulls and starts the new image (n8n runs its database migrations).
# 3. If n8n is not healthy within 5 minutes, restores the pre-upgrade backup,
#    which also puts the previous version back. Migrations are not reversible,
#    so restoring the backup is the only safe rollback.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"
load_env

new=${1:-}
if ! [[ $new =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <version>   (exact version, for example 2.43.0)" >&2
  exit 1
fi
if [[ $new == "$N8N_VERSION" ]]; then
  log "already on $new"
  exit 0
fi

log "pulling n8n $new before touching anything"
docker pull --quiet "docker.n8n.io/n8nio/n8n:$new" >/dev/null

log "pre-upgrade backup"
backup_id=$("$APP_DIR/scripts/backup.sh" | tail -n 1)

log "upgrading n8n $N8N_VERSION -> $new"
set_env_value N8N_VERSION "$new"
compose up -d n8n

if wait_healthy 300; then
  log "upgrade to $new complete (rollback point: $backup_id)"
  exit 0
fi

log "upgrade failed, restoring backup $backup_id"
compose logs --tail 50 n8n || true
"$APP_DIR/scripts/restore.sh" "$backup_id"
exit 1
