#!/bin/bash

# Setup Automated Backups with Systemd Timer
# Alternative to cron with better logging and management

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Backup Systemd Timer Setup"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="${DEPLOYMENT_DIR}/systemd"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup-postgres.sh"
BACKUP_DIR="/opt/backups"

# Verify files exist
if [ ! -f "${SYSTEMD_DIR}/postgres-backup.service" ]; then
    echo -e "${RED}Service file not found: ${SYSTEMD_DIR}/postgres-backup.service${NC}"
    exit 1
fi

if [ ! -f "${SYSTEMD_DIR}/postgres-backup.timer" ]; then
    echo -e "${RED}Timer file not found: ${SYSTEMD_DIR}/postgres-backup.timer${NC}"
    exit 1
fi

if [ ! -f "$BACKUP_SCRIPT" ]; then
    echo -e "${RED}Backup script not found: $BACKUP_SCRIPT${NC}"
    exit 1
fi

# Make backup script executable
chmod +x "$BACKUP_SCRIPT"
echo -e "${GREEN}✓ Backup script is executable${NC}"

# Create backup directory
mkdir -p "$BACKUP_DIR"
chown -R deployer:deployer "$BACKUP_DIR"
echo -e "${GREEN}✓ Backup directory created: $BACKUP_DIR${NC}"

# Copy systemd files
echo "Installing systemd files..."
cp "${SYSTEMD_DIR}/postgres-backup.service" /etc/systemd/system/
cp "${SYSTEMD_DIR}/postgres-backup.timer" /etc/systemd/system/
echo -e "${GREEN}✓ Systemd files copied${NC}"

# Reload systemd
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd reloaded${NC}"

# Enable and start timer
systemctl enable postgres-backup.timer
systemctl start postgres-backup.timer
echo -e "${GREEN}✓ Timer enabled and started${NC}"

# Display status
echo ""
echo "=========================================="
echo "Backup Timer Status"
echo "=========================================="
systemctl status postgres-backup.timer --no-pager

echo ""
echo "=========================================="
echo "Next Scheduled Backup"
echo "=========================================="
systemctl list-timers postgres-backup.timer --no-pager

echo ""
echo "=========================================="
echo "Setup Complete"
echo "=========================================="
echo "Schedule: Daily at 2:00 AM"
echo "Service: postgres-backup.service"
echo "Timer: postgres-backup.timer"
echo "Logs: $BACKUP_DIR/backup.log"
echo ""
echo "Useful commands:"
echo "  # Check timer status"
echo "  systemctl status postgres-backup.timer"
echo ""
echo "  # View next scheduled runs"
echo "  systemctl list-timers postgres-backup.timer"
echo ""
echo "  # Run backup manually"
echo "  sudo systemctl start postgres-backup.service"
echo ""
echo "  # View backup logs"
echo "  journalctl -u postgres-backup.service -n 50"
echo "  tail -f $BACKUP_DIR/backup.log"
echo ""
echo "  # Disable timer"
echo "  sudo systemctl disable postgres-backup.timer"
echo ""