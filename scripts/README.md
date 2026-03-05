# Scripts

## Setup Scripts

| Script | Purpose |
|--------|---------|
| `setup-local.sh` | One-command local dev setup (Docker MySQL + Rails) |
| `setup-aws.sh` | One-command AWS setup (Terraform + EKS) |
| `setup-aws-profiles.sh` | AWS profile helper (list, verify, add for multi-account) |
| `setup-aws-iam-user.sh` | Create IAM user with Terraform/EKS permissions (run as admin) |
| `setup-datadog.sh` | One-command Datadog setup (Agent + MySQL DBM on EKS) |
| `setup-github-actions.sh` | Configure GitHub Actions secrets (requires gh CLI) |

---

## MySQL Operation Scripts

Scripts for backup, upgrade, and monitoring of MySQL 5.6 master-replica on AWS EC2.

### Config Setup

1. Copy config example:
   ```bash
   cp config/mysql-ops.conf.example config/mysql-ops.conf
   ```

2. Edit `config/mysql-ops.conf` with your credentials and S3 bucket.

3. Make scripts executable:
   ```bash
   chmod +x scripts/*.sh
   ```

## Backup (`mysql-backup.sh`)

- **Full backup**: `./mysql-backup.sh full master`
- **Incremental**: `./mysql-backup.sh incremental master`
- Uploads to S3 if `S3_BUCKET` is set
- Prunes local backups older than `RETENTION_DAYS`

**Cron (daily full backup at 2am):**
```cron
0 2 * * * /opt/scripts/mysql-backup.sh full master >> /var/log/mysql-backup-cron.log 2>&1
```

## Upgrade (`mysql-upgrade.sh`)

1. `./mysql-upgrade.sh check`   - Check current version
2. `./mysql-upgrade.sh backup`  - Create pre-upgrade backup
3. `./mysql-upgrade.sh upgrade` - Run upgrade
4. `./mysql-upgrade.sh rollback` - Rollback (manual steps shown)

**Replication:** Upgrade replicas first, then master. Or use maintenance window.

## Monitor (`mysql-monitor.sh`)

- **Local**: `./mysql-monitor.sh local` - Connection, disk, connections
- **Replication**: `./mysql-monitor.sh replication` - Replication status
- **Full**: `./mysql-monitor.sh full` - All checks

**Remote check:**
```bash
MYSQL_HOST=10.0.1.50 ./mysql-monitor.sh full
```

**Cron (every 5 min):**
```cron
*/5 * * * * /opt/scripts/mysql-monitor.sh full >> /var/log/mysql-monitor.log 2>&1
```
