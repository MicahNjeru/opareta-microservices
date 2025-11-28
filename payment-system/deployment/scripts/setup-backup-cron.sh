#!/bin/bash

# Setup Automated Backups with Cron
# Schedules daily backups at 2 AM

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Backup Cron Setup"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Configuration
BACKUP_SCRIPT="/opt/payment-system/deployment/scripts/backup-postgres.sh"
BACKUP_DIR="/opt/backups"
DEPLOYER_USER="deployer"

# Verify backup script exists
if [ ! -f "$BACKUP_SCRIPT" ]; then
    echo -e "${RED}Backup script not found: $BACKUP_SCRIPT${NC}"
    exit 1
fi

# Make script executable
chmod +x "$BACKUP_SCRIPT"
echo -e "${GREEN}✓ Backup script is executable${NC}"

# Create backup directory
mkdir -p "$BACKUP_DIR"
chown -R $DEPLOYER_USER:$DEPLOYER_USER "$BACKUP_DIR"
echo -e "${GREEN}✓ Backup directory created: $BACKUP_DIR${NC}"

# Create cron job
CRON_JOB="0 2 * * * BACKUP_DIR=$BACKUP_DIR $BACKUP_SCRIPT >> $BACKUP_DIR/backup.log 2>&1"

# Check if cron job already exists
if crontab -u $DEPLOYER_USER -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
    echo -e "${YELLOW}⚠ Cron job already exists, updating...${NC}"
    # Remove old cron job
    crontab -u $DEPLOYER_USER -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | crontab -u $DEPLOYER_USER -
fi

# Add new cron job
(crontab -u $DEPLOYER_USER -l 2>/dev/null; echo "$CRON_JOB") | crontab -u $DEPLOYER_USER -

echo -e "${GREEN}✓ Cron job added${NC}"

# Display current crontab
echo ""
echo "Current crontab for $DEPLOYER_USER:"
echo "----------------------------------------"
crontab -u $DEPLOYER_USER -l | grep "$BACKUP_SCRIPT"
echo "----------------------------------------"

# Verify cron service is running
if systemctl is-active --quiet cron || systemctl is-active --quiet crond; then
    echo -e "${GREEN}✓ Cron service is running${NC}"
else
    echo -e "${RED}✗ Cron service is not running${NC}"
    echo "Starting cron service..."
    systemctl start cron || systemctl start crond
fi

echo ""
echo "=========================================="
echo "Backup Schedule Configured"
echo "=========================================="
echo "Schedule: Daily at 2:00 AM"
echo "Script: $BACKUP_SCRIPT"
echo "Logs: $BACKUP_DIR/backup.log"
echo "Retention: 7 days"
echo ""
echo "To test backup now:"
echo "  sudo -u $DEPLOYER_USER $BACKUP_SCRIPT"
echo ""
echo "To view cron jobs:"
echo "  crontab -u $DEPLOYER_USER -l"
echo ""
echo "To view backup logs:"
echo "  tail -f $BACKUP_DIR/backup.log"
echo ""