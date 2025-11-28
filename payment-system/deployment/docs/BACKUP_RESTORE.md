# Database Backup and Restore Guide

## Overview

Automated backup system for PostgreSQL databases with:
- Daily automated backups
- 7-day retention policy
- Compressed backup files (gzip)
- Integrity verification
- Point-in-time recovery capability

## Backup Strategy

### What is Backed Up

1. **Authentication Database (postgres-a)**
   - Database: `auth_db`
   - Contains: User accounts, credentials
   - Location: `/opt/backups/postgres-a/`

2. **Payment Database (postgres-b)**
   - Database: `payment_db`
   - Contains: Payment transactions, webhooks
   - Location: `/opt/backups/postgres-b/`

### Backup Schedule

**Frequency:** Daily at 2:00 AM
**Method:** `pg_dump` with gzip compression
**Retention:** Last 7 days
**Format:** SQL dump (compressed)

### Backup File Naming

```
<database_name>_<timestamp>.sql.gz

Examples:
auth_db_20240115_020000.sql.gz
payment_db_20240115_020000.sql.gz
```

## Manual Backup

### Create Backup Manually

```bash
# Run backup script
sudo -u deployer /opt/payment-system/deployment/scripts/backup-postgres.sh

# Check backup files
ls -lh /opt/backups/postgres-a/
ls -lh /opt/backups/postgres-b/
```

### Backup Specific Database

```bash
# Auth database only
docker exec postgres-a pg_dump -U auth_user auth_db | \
  gzip > /opt/backups/postgres-a/auth_db_manual_$(date +%Y%m%d_%H%M%S).sql.gz

# Payment database only
docker exec postgres-b pg_dump -U payment_user payment_db | \
  gzip > /opt/backups/postgres-b/payment_db_manual_$(date +%Y%m%d_%H%M%S).sql.gz
```

## Automated Backups

### Option 1: Cron (Recommended for Simplicity)

**Setup:**
```bash
cd /opt/payment-system/deployment/scripts
sudo ./setup-backup-cron.sh
```

**Verify:**
```bash
# Check cron job exists
crontab -u deployer -l | grep backup

# View backup logs
tail -f /opt/backups/backup.log
```

**Manage:**
```bash
# Edit cron jobs
crontab -u deployer -e

# Remove cron job
crontab -u deployer -l | grep -v backup-postgres.sh | crontab -u deployer -
```

### Option 2: Systemd Timer 

**Setup:**
```bash
cd /opt/payment-system/deployment/scripts
sudo ./setup-backup-systemd.sh
```

**Verify:**
```bash
# Check timer status
systemctl status postgres-backup.timer

# View next scheduled run
systemctl list-timers postgres-backup.timer
```

**Manage:**
```bash
# Start timer
sudo systemctl start postgres-backup.timer

# Stop timer
sudo systemctl stop postgres-backup.timer

# Enable (start on boot)
sudo systemctl enable postgres-backup.timer

# Disable
sudo systemctl disable postgres-backup.timer

# Run backup immediately
sudo systemctl start postgres-backup.service

# View logs
journalctl -u postgres-backup.service -n 50
```

## Backup Verification

### Verify Backup Integrity

```bash
# Run verification script
/opt/payment-system/deployment/scripts/verify-backups.sh
```

### Manual Verification

```bash
# Check if backup file is valid gzip
gunzip -t /opt/backups/postgres-a/auth_db_20240115_020000.sql.gz

# Check backup file size (should be > 1KB)
ls -lh /opt/backups/postgres-a/

# Count SQL statements in backup
gunzip -c /opt/backups/postgres-a/auth_db_20240115_020000.sql.gz | grep -c "INSERT\|CREATE"
```

## Restore Procedures

### ⚠️ Pre-Restore Checklist

Before restoring:
1. ✅ Verify backup file integrity
2. ✅ Notify users of maintenance window
3. ✅ Stop application services
4. ✅ Create snapshot of current database (optional)
5. ✅ Confirm backup file timestamp

### Restore Using Script - Recommended

**Authentication Database:**
```bash
# List available backups
ls -lh /opt/backups/postgres-a/

# Restore (will prompt for confirmation)
sudo /opt/payment-system/deployment/scripts/restore-postgres.sh auth \
  /opt/backups/postgres-a/auth_db_20240115_020000.sql.gz
```

**Payment Database:**
```bash
# List available backups
ls -lh /opt/backups/postgres-b/

# Restore (will prompt for confirmation)
sudo /opt/payment-system/deployment/scripts/restore-postgres.sh payment \
  /opt/backups/postgres-b/payment_db_20240115_020000.sql.gz
```

### Manual Restore (Step-by-Step)

**Step 1: Stop Application Services**
```bash
# For auth database
docker stop service-a-1 service-a-2

# For payment database
docker stop service-b-1 service-b-2
```

**Step 2: Terminate Database Connections**
```bash
# Auth database
docker exec postgres-a psql -U auth_user -d postgres -c \
  "SELECT pg_terminate_backend(pg_stat_activity.pid) 
   FROM pg_stat_activity 
   WHERE pg_stat_activity.datname = 'auth_db' 
   AND pid <> pg_backend_pid();"

# Payment database
docker exec postgres-b psql -U payment_user -d postgres -c \
  "SELECT pg_terminate_backend(pg_stat_activity.pid) 
   FROM pg_stat_activity 
   WHERE pg_stat_activity.datname = 'payment_db' 
   AND pid <> pg_backend_pid();"
```

**Step 3: Drop and Recreate Database**
```bash
# Auth database
docker exec postgres-a psql -U auth_user -d postgres -c "DROP DATABASE auth_db;"
docker exec postgres-a psql -U auth_user -d postgres -c "CREATE DATABASE auth_db OWNER auth_user;"

# Payment database
docker exec postgres-b psql -U payment_user -d postgres -c "DROP DATABASE payment_db;"
docker exec postgres-b psql -U payment_user -d postgres -c "CREATE DATABASE payment_db OWNER payment_user;"
```

**Step 4: Restore from Backup**
```bash
# Auth database
gunzip -c /opt/backups/postgres-a/auth_db_20240115_020000.sql.gz | \
  docker exec -i postgres-a psql -U auth_user -d auth_db

# Payment database
gunzip -c /opt/backups/postgres-b/payment_db_20240115_020000.sql.gz | \
  docker exec -i postgres-b psql -U payment_user -d payment_db
```

**Step 5: Verify Restoration**
```bash
# Check table count
docker exec postgres-a psql -U auth_user -d auth_db -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"

docker exec postgres-b psql -U payment_user -d payment_db -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"

# Check record counts
docker exec postgres-a psql -U auth_user -d auth_db -c "SELECT COUNT(*) FROM users;"
docker exec postgres-b psql -U payment_user -d payment_db -c "SELECT COUNT(*) FROM payments;"
```

**Step 6: Restart Application Services**
```bash
# Restart services
docker start service-a-1 service-a-2
docker start service-b-1 service-b-2

# Wait for health checks
sleep 30

# Verify services are healthy
curl -k https://localhost/auth/health
curl -k https://localhost/payments/health/check
```

## Testing Backup and Restore

### Test Backup Creation

```bash
# Run backup manually
sudo -u deployer /opt/payment-system/deployment/scripts/backup-postgres.sh

# Check backup was created
ls -lth /opt/backups/postgres-a/ | head -5
ls -lth /opt/backups/postgres-b/ | head -5

# Verify integrity
/opt/payment-system/deployment/scripts/verify-backups.sh
```

### Test Restore (Non-Production)

**⚠️ Only test on non-production environment**

```bash
# 1. Create test data
curl -k -X POST https://localhost/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+256700123456",
    "email": "test@example.com",
    "password": "Test@1234"
  }'

# 2. Create backup
sudo -u deployer /opt/payment-system/deployment/scripts/backup-postgres.sh

# 3. Create more test data
curl -k -X POST https://localhost/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+256700999999",
    "email": "test2@example.com",
    "password": "Test@1234"
  }'

# 4. Restore from backup (should only have first user)
sudo /opt/payment-system/deployment/scripts/restore-postgres.sh auth \
  /opt/backups/postgres-a/auth_db_LATEST.sql.gz

# 5. Verify first user exists, second doesn't
docker exec postgres-a psql -U auth_user -d auth_db -c \
  "SELECT phone_number FROM users;"
```

## Backup Retention

### Current Policy

- **Retention Period:** 7 days
- **Cleanup:** Automatic (during backup script)
- **Minimum Backups:** 7 (daily backups)
- **Maximum Backups:** Unlimited (within retention)

### Modify Retention Period

**Option 1: Environment Variable**
```bash
# Edit cron job
crontab -u deployer -e

# Change RETENTION_DAYS
0 2 * * * BACKUP_DIR=/opt/backups RETENTION_DAYS=14 /opt/payment-system/deployment/scripts/backup-postgres.sh
```

**Option 2: Systemd Service**
```bash
# Edit service file
sudo nano /etc/systemd/system/postgres-backup.service

# Change Environment line
Environment="RETENTION_DAYS=14"

# Reload
sudo systemctl daemon-reload
```

### Manual Cleanup

```bash
# Delete backups older than 30 days
find /opt/backups/postgres-a -name "*.sql.gz" -mtime +30 -delete
find /opt/backups/postgres-b -name "*.sql.gz" -mtime +30 -delete

# Delete backups older than specific date
find /opt/backups -name "*.sql.gz" -not -newermt "2024-01-01" -delete
```

## Disaster Recovery

### Recovery Time Objective (RTO)

**Target:** < 15 minutes

**Typical Restore Time:**
- Small database (<100MB): 2-5 minutes
- Medium database (100MB-1GB): 5-10 minutes
- Large database (>1GB): 10-30 minutes

### Recovery Point Objective (RPO)

**Target:** < 24 hours (daily backups)

**Actual:** Maximum 24 hours of data loss

**Improvement Options:**
- Increase backup frequency (hourly, every 6 hours)
- Implement WAL archiving for point-in-time recovery
- Set up streaming replication

### Complete System Recovery

**Scenario:** Complete server failure

**Steps:**
1. Provision new server
2. Install Docker and dependencies (Ansible playbook)
3. Deploy application (docker-compose)
4. Restore databases from backup
5. Verify functionality
6. Update DNS/load balancer

**Estimated Time:** 30-60 minutes

## Monitoring and Alerts

### Check Last Backup Time

```bash
# Find most recent backup
ls -lt /opt/backups/postgres-a/ | head -2
ls -lt /opt/backups/postgres-b/ | head -2

# Check backup age
find /opt/backups -name "*.sql.gz" -mtime -1
```

### Monitor Backup Size

```bash
# Check backup sizes
du -sh /opt/backups/postgres-a/*
du -sh /opt/backups/postgres-b/*

# Check total backup disk usage
du -sh /opt/backups
```

### Alert on Backup Failure

Add to backup script or create monitoring:

```bash
# Check if backup completed today
if [ $(find /opt/backups/postgres-a -name "*.sql.gz" -mtime -1 | wc -l) -eq 0 ]; then
  echo "ALERT: No recent auth database backup"
  # Send notification
fi
```

## Offsite Backup (Optional)

### Copy to Remote Server

```bash
# Using rsync
rsync -avz --delete /opt/backups/ backup-server:/backups/payment-system/

# Using scp
scp /opt/backups/postgres-a/auth_db_*.sql.gz backup-server:/backups/
```

### Upload to S3 (Optional)

```bash
# Install AWS CLI
apt install awscli

# Configure credentials
aws configure

# Upload backup
aws s3 cp /opt/backups/postgres-a/ s3://my-backup-bucket/postgres-a/ --recursive

# Automate in cron
0 3 * * * aws s3 sync /opt/backups/ s3://my-backup-bucket/ --delete
```

## Troubleshooting

### Backup Script Fails

**Check logs:**
```bash
tail -100 /opt/backups/backup.log
```

**Common issues:**
- Docker not running: `systemctl status docker`
- Insufficient disk space: `df -h /opt/backups`
- Database not accessible: `docker ps | grep postgres`
- Permission issues: `ls -la /opt/backups`

### Restore Fails

**Issue:** Cannot drop database (connections exist)
```bash
# Force terminate all connections
docker exec postgres-a psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='auth_db';"
```

**Issue:** Backup file corrupted
```bash
# Verify integrity
gunzip -t backup_file.sql.gz

# Try alternate backup
ls -lt /opt/backups/postgres-a/ | head -5
```

**Issue:** Services won't reconnect
```bash
# Restart services
docker restart service-a-1 service-a-2

# Check logs
docker logs service-a-1
```

### Disk Space Issues

```bash
# Check disk usage
df -h /opt/backups

# Find large backups
find /opt/backups -type f -size +100M -exec ls -lh {} \;

# Manual cleanup
find /opt/backups -name "*.sql.gz" -mtime +7 -delete
```

## Best Practices

1. **Test Restores Regularly**
   - Monthly restore tests
   - Verify data integrity
   - Document restore time

2. **Monitor Backup Health**
   - Check daily for new backups
   - Verify backup sizes
   - Alert on failures

3. **Secure Backups**
   - Restrict file permissions (600)
   - Consider encryption for sensitive data
   - Offsite backup for disaster recovery

4. **Document Procedures**
   - Keep runbooks updated
   - Document custom configurations
   - Record restore times

5. **Version Control**
   - Track backup script changes
   - Document retention policy changes
   - Maintain audit log

## Quick Reference

```bash
# Manual backup
sudo -u deployer /opt/payment-system/deployment/scripts/backup-postgres.sh

# Verify backups
/opt/payment-system/deployment/scripts/verify-backups.sh

# Restore auth database
sudo /opt/payment-system/deployment/scripts/restore-postgres.sh auth BACKUP_FILE

# Restore payment database
sudo /opt/payment-system/deployment/scripts/restore-postgres.sh payment BACKUP_FILE

# Check cron status
crontab -u deployer -l

# Check systemd timer
systemctl status postgres-backup.timer

# View backup logs
tail -f /opt/backups/backup.log

# List backups
ls -lth /opt/backups/postgres-a/
ls -lth /opt/backups/postgres-b/
```