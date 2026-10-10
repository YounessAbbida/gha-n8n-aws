# Runbook

Commands for deploying, operating and removing the stack. Region examples use
`eu-west-3`; replace placeholders in `<angle brackets>`.

Requirements on your machine: Terraform >= 1.10, AWS CLI v2, and the
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
for the AWS CLI. Use credentials with admin rights for the first apply.

## 1. Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set domain_name, acme_email, budget_email
cp backend.hcl.example backend.hcl             # your state bucket
terraform init -backend-config=backend.hcl
terraform apply
```

If you did not set `route53_zone_id`, create an `A` record for `domain_name`
pointing at the `elastic_ip` output. Caddy retries the certificate until DNS
resolves.

First boot takes 2 to 4 minutes. Follow it from a session (step 2):

```bash
sudo tail -f /var/log/n8n-bootstrap.log
```

Then open the `url` output and create the n8n owner account.

## 2. Shell access (no SSH)

```bash
aws ssm start-session --target "$(terraform -chdir=terraform output -raw instance_id)"
```

Useful once inside:

```bash
cd /opt/n8n
sudo docker compose ps
sudo docker compose logs --tail 100 n8n
systemctl list-timers n8n-backup.timer
```

## 3. Backups

Nightly at 02:30 UTC (with up to 15 minutes of random delay). Each run writes
`s3://<bucket>/backups/<id>/` with:

| File | Content |
|---|---|
| `n8n.dump` | `pg_dump --format=custom` of the n8n database |
| `n8n-data.tar.gz` | `/opt/n8n/data/n8n` (n8n settings, binary data) |
| `N8N_VERSION` | the n8n version that wrote the backup |
| `SHA256SUMS` | checksums, verified on restore |

`backups/LATEST` holds the newest id. Objects expire after
`backup_retention_days` (30 by default).

Run one by hand, and check the result:

```bash
sudo /opt/n8n/scripts/backup.sh
sudo journalctl -u n8n-backup.service --since today      # timer runs
aws s3 ls "s3://<bucket>/backups/" --region eu-west-3
```

The n8n encryption key is **not** in the backup. It lives in SSM Parameter
Store at `/<project_name>/n8n-encryption-key`. Without it, restored
credentials cannot be decrypted. Do not delete that parameter while you have
backups you may need.

## 4. Upgrade n8n

Read the n8n release notes for breaking changes first, then:

```bash
sudo /opt/n8n/scripts/upgrade.sh 2.43.0
```

What it does:

1. Pulls the new image (fails early if the tag does not exist).
2. Runs `backup.sh` and remembers the backup id.
3. Sets `N8N_VERSION` in `/opt/n8n/.env` and recreates the n8n container.
4. Waits up to 5 minutes for `http://127.0.0.1:5678/healthz`.
5. If the check fails, prints the last logs and runs `restore.sh <that id>`,
   which puts back the database, data directory and previous version.

Database migrations are not reversible, which is why rollback is a restore
rather than just starting the old image.

Postgres and Caddy are upgraded by editing their tags in
`docker-compose.yml`. Caddy can be upgraded in place. For a Postgres
**major** version, take a backup, stop the stack, remove the
`n8n_postgres_data` volume, start with the new image and run `restore.sh`.

## 5. Restore

```bash
sudo /opt/n8n/scripts/restore.sh latest          # newest backup
sudo /opt/n8n/scripts/restore.sh 20261010T023112Z   # a specific one
```

The script verifies checksums, stops n8n, recreates the database, restores the
dump, swaps in the archived data directory (the previous one is kept as
`data/n8n.pre-restore-<id>`), switches to the n8n version recorded in the
backup, starts n8n and waits for the health check.

Test this regularly: a backup that has never been restored is not a backup.

## 6. Rebuild from backup (lost or replaced instance)

The SSM parameters and the S3 bucket are independent of the instance, so:

```bash
terraform -chdir=terraform apply -replace=aws_instance.n8n
```

The new instance reads the existing secrets from SSM at first boot. Once it is
up, open a session and run `sudo /opt/n8n/scripts/restore.sh latest`.

The same command applies a newer AMI or edited stack files: Terraform ignores
those changes until you ask for a replacement.

## 7. Teardown

```bash
terraform -chdir=terraform destroy
```

`destroy` fails on the backup bucket while it still holds objects. Empty it
first if you do not need the backups (versioned bucket, so delete all
versions), or keep it and remove it from state.

The SSM parameters were created by the instance, not by Terraform, so they
remain. Delete them only when you no longer need any backup:

```bash
aws ssm delete-parameters --region eu-west-3 \
  --names /n8n/postgres-password /n8n/n8n-encryption-key
```
