#!/usr/bin/env bash
# Postgres dump + n8n data directory, uploaded to S3 under backups/<id>/.
# Runs nightly from n8n-backup.timer; safe to run by hand: sudo /opt/n8n/scripts/backup.sh
# Prints the backup id on the last line of output.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_env

id=$(date -u +%Y%m%dT%H%M%SZ)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

log "dumping database"
compose exec -T postgres pg_dump -U n8n -d n8n --format=custom >"$work/n8n.dump"

log "archiving n8n data directory"
tar -C "$APP_DIR/data" -czf "$work/n8n-data.tar.gz" n8n

printf '%s\n' "$N8N_VERSION" >"$work/N8N_VERSION"
(cd "$work" && sha256sum n8n.dump n8n-data.tar.gz N8N_VERSION >SHA256SUMS)

log "uploading to s3://$BACKUP_BUCKET/backups/$id/"
aws s3 cp --recursive --only-show-errors --region "$AWS_REGION" "$work" "s3://$BACKUP_BUCKET/backups/$id/"
printf '%s\n' "$id" | aws s3 cp --only-show-errors --region "$AWS_REGION" - "s3://$BACKUP_BUCKET/backups/LATEST"

log "backup complete"
echo "$id"
