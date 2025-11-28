#!/bin/bash

# PostgreSQL Backup Script for Payment System
# Backs up both auth_db and payment_db with rotation

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/opt/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${BACKUP_DIR}/backup.log"

# Database configurations
AUTH_CONTAINER="postgres-a"
AUTH_USER="auth_user"
AUTH_DB="auth_db"

PAYMENT_CONTAINER="postgres-b"
PAYMENT_USER="payment_user"
PAYMENT_DB="payment_db"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Check if running as root or with docker permissions
if ! docker ps > /dev/null 2>&1; then
    error_exit "Cannot connect to Docker. Please run with appropriate permissions."
fi

# Create backup directories
mkdir -p "${BACKUP_DIR}/postgres-a"
mkdir -p "${BACKUP_DIR}/postgres-b"

log "=========================================="
log "Starting PostgreSQL Backup"
log "=========================================="
log "Backup Directory: ${BACKUP_DIR}"
log "Retention: ${RETENTION_DAYS} days"

# Function to backup a database
backup_database() {
    local CONTAINER=$1
    local USER=$2
    local DATABASE=$3
    local BACKUP_SUBDIR=$4
    
    log "Backing up ${DATABASE} from ${CONTAINER}..."
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        error_exit "Container ${CONTAINER} is not running"
    fi
    
    # Define backup file path
    local BACKUP_FILE="${BACKUP_DIR}/${BACKUP_SUBDIR}/${DATABASE}_${TIMESTAMP}.sql.gz"
    
    # Perform backup
    if docker exec ${CONTAINER} pg_dump -U ${USER} ${DATABASE} | gzip > "${BACKUP_FILE}"; then
        # Get file size
        local SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        log "✓ Backup completed: ${BACKUP_FILE} (${SIZE})"
        
        # Verify backup file
        if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
            # Test backup integrity
            if gunzip -t "${BACKUP_FILE}" 2>/dev/null; then
                log "✓ Backup integrity verified"
            else
                error_exit "Backup file ${BACKUP_FILE} is corrupted"
            fi
        else
            error_exit "Backup file ${BACKUP_FILE} is empty or missing"
        fi
        
        return 0
    else
        error_exit "Failed to backup ${DATABASE}"
    fi
}

# Backup Auth Database
log "----------------------------------------"
log "Backing up Authentication Database"
log "----------------------------------------"
backup_database "${AUTH_CONTAINER}" "${AUTH_USER}" "${AUTH_DB}" "postgres-a"

# Backup Payment Database
log "----------------------------------------"
log "Backing up Payment Database"
log "----------------------------------------"
backup_database "${PAYMENT_CONTAINER}" "${PAYMENT_USER}" "${PAYMENT_DB}" "postgres-b"

# Apply retention policy
log "----------------------------------------"
log "Applying Retention Policy"
log "----------------------------------------"

cleanup_old_backups() {
    local BACKUP_SUBDIR=$1
    local DB_NAME=$2
    
    log "Cleaning up ${DB_NAME} backups older than ${RETENTION_DAYS} days..."
    
    # Find and delete old backups
    DELETED_COUNT=$(find "${BACKUP_DIR}/${BACKUP_SUBDIR}" \
        -name "${DB_NAME}_*.sql.gz" \
        -type f \
        -mtime +${RETENTION_DAYS} \
        -delete -print | wc -l)
    
    if [ ${DELETED_COUNT} -gt 0 ]; then
        log "✓ Deleted ${DELETED_COUNT} old backup(s)"
    else
        log "No old backups to delete"
    fi
    
    # Count remaining backups
    REMAINING_COUNT=$(find "${BACKUP_DIR}/${BACKUP_SUBDIR}" \
        -name "${DB_NAME}_*.sql.gz" \
        -type f | wc -l)
    
    log "Remaining backups: ${REMAINING_COUNT}"
}

cleanup_old_backups "postgres-a" "${AUTH_DB}"
cleanup_old_backups "postgres-b" "${PAYMENT_DB}"

# Backup summary
log "----------------------------------------"
log "Backup Summary"
log "----------------------------------------"

# List current backups
log "Auth Database Backups:"
ls -lh "${BACKUP_DIR}/postgres-a/" | tail -n +2 | awk '{print "  " $9 " - " $5}' | tee -a "$LOG_FILE"

log "Payment Database Backups:"
ls -lh "${BACKUP_DIR}/postgres-b/" | tail -n +2 | awk '{print "  " $9 " - " $5}' | tee -a "$LOG_FILE"

# Calculate total backup size
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
log "Total backup size: ${TOTAL_SIZE}"

log "=========================================="
log "Backup Completed Successfully"
log "=========================================="

# Optional: Send notification (uncomment and configure)
# curl -X POST "YOUR_WEBHOOK_URL" \
#   -H "Content-Type: application/json" \
#   -d "{\"text\":\"PostgreSQL backup completed successfully\"}"

exit 0