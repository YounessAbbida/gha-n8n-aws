#!/usr/bin/env bash
# Restores a backup from S3: database, n8n data directory and the n8n version
# that wrote it. Usage: sudo /opt/n8n/scripts/restore.sh [<backup-id>|latest]
#
# The n8n encryption key is not in the backup. It stays in SSM Parameter Store,
# so restored credentials decrypt as long as the parameter was not deleted.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_env

id=${1:-latest}
if [[ $id == latest ]]; then
  id=$(aws s3 cp --only-show-errors --region "$AWS_REGION" "s3://$BACKUP_BUCKET/backups/LATEST" -)
fi
if ! [[ $id =~ $BACKUP_ID_RE ]]; then
  echo "invalid backup id: $id (expected YYYYMMDDTHHMMSSZ)" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

log "downloading backup $id"
aws s3 cp --recursive --only-show-errors --region "$AWS_REGION" "s3://$BACKUP_BUCKET/backups/$id/" "$work"
(cd "$work" && sha256sum --check --quiet SHA256SUMS)
backup_version=$(<"$work/N8N_VERSION")

log "stopping n8n"
compose stop n8n

log "restoring database"
compose exec -T postgres dropdb -U n8n --if-exists --force n8n
compose exec -T postgres createdb -U n8n -O n8n n8n
compose exec -T postgres pg_restore -U n8n -d n8n --no-owner --exit-on-error <"$work/n8n.dump"

log "restoring n8n data directory (previous copy kept as data/n8n.pre-restore-$id)"
mv "$APP_DIR/data/n8n" "$APP_DIR/data/n8n.pre-restore-$id"
tar -C "$APP_DIR/data" -xzf "$work/n8n-data.tar.gz"
chown -R 1000:1000 "$APP_DIR/data/n8n"

# The schema in the dump matches the version that wrote it, so run that version.
if [[ $backup_version != "$N8N_VERSION" ]]; then
  log "switching n8n from $N8N_VERSION to $backup_version to match the backup"
  set_env_value N8N_VERSION "$backup_version"
fi

compose up -d n8n
wait_healthy
log "restore of $id complete"
