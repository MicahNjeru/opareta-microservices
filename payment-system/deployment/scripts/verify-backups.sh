#!/bin/bash

# Backup Verification Script
# Checks backup files for integrity and completeness

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/opt/backups}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Backup Verification Report"
echo "=========================================="
echo "Backup Directory: $BACKUP_DIR"
echo "Timestamp: $(date)"
echo ""

# Function to verify a backup directory
verify_backup_dir() {
    local DIR=$1
    local DB_NAME=$2
    
    echo "----------------------------------------"
    echo "Checking: $DB_NAME"
    echo "----------------------------------------"
    
    if [ ! -d "$DIR" ]; then
        echo -e "${RED}✗ Backup directory does not exist: $DIR${NC}"
        return 1
    fi
    
    # Count backup files
    BACKUP_COUNT=$(find "$DIR" -name "*.sql.gz" -type f | wc -l)
    echo "Total backups: $BACKUP_COUNT"
    
    if [ $BACKUP_COUNT -eq 0 ]; then
        echo -e "${RED}✗ No backup files found${NC}"
        return 1
    fi
    
    # Check each backup file
    VALID_COUNT=0
    INVALID_COUNT=0
    TOTAL_SIZE=0
    
    while IFS= read -r FILE; do
        FILENAME=$(basename "$FILE")
        FILESIZE=$(du -h "$FILE" | cut -f1)
        FILESIZE_BYTES=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null)
        TOTAL_SIZE=$((TOTAL_SIZE + FILESIZE_BYTES))
        
        # Check if file is not empty
        if [ $FILESIZE_BYTES -lt 100 ]; then
            echo -e "${RED}✗ $FILENAME - Too small ($FILESIZE)${NC}"
            INVALID_COUNT=$((INVALID_COUNT + 1))
            continue
        fi
        
        # Check gzip integrity
        if gunzip -t "$FILE" 2>/dev/null; then
            echo -e "${GREEN}✓ $FILENAME - Valid ($FILESIZE)${NC}"
            VALID_COUNT=$((VALID_COUNT + 1))
        else
            echo -e "${RED}✗ $FILENAME - Corrupted${NC}"
            INVALID_COUNT=$((INVALID_COUNT + 1))
        fi
        
    done < <(find "$DIR" -name "*.sql.gz" -type f | sort)
    
    # Summary
    echo ""
    echo "Summary for $DB_NAME:"
    echo "  Valid backups: $VALID_COUNT"
    echo "  Invalid backups: $INVALID_COUNT"
    echo "  Total size: $(numfmt --to=iec-i --suffix=B $TOTAL_SIZE)"
    
    # List oldest and newest backups
    OLDEST=$(find "$DIR" -name "*.sql.gz" -type f -printf '%T+ %p\n' | sort | head -1 | cut -d' ' -f2)
    NEWEST=$(find "$DIR" -name "*.sql.gz" -type f -printf '%T+ %p\n' | sort | tail -1 | cut -d' ' -f2)
    
    if [ -n "$OLDEST" ]; then
        OLDEST_DATE=$(stat -f%Sm -t "%Y-%m-%d %H:%M" "$OLDEST" 2>/dev/null || stat -c%y "$OLDEST" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  Oldest backup: $(basename "$OLDEST") ($OLDEST_DATE)"
    fi
    
    if [ -n "$NEWEST" ]; then
        NEWEST_DATE=$(stat -f%Sm -t "%Y-%m-%d %H:%M" "$NEWEST" 2>/dev/null || stat -c%y "$NEWEST" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  Newest backup: $(basename "$NEWEST") ($NEWEST_DATE)"
    fi
    
    echo ""
}

# Verify Auth Database backups
verify_backup_dir "${BACKUP_DIR}/postgres-a" "Authentication Database"

# Verify Payment Database backups
verify_backup_dir "${BACKUP_DIR}/postgres-b" "Payment Database"

# Overall status
echo "=========================================="
echo "Overall Backup Status"
echo "=========================================="

# Check if backups are recent (within last 25 hours)
RECENT_AUTH=$(find "${BACKUP_DIR}/postgres-a" -name "*.sql.gz" -type f -mtime -1 | wc -l)
RECENT_PAYMENT=$(find "${BACKUP_DIR}/postgres-b" -name "*.sql.gz" -type f -mtime -1 | wc -l)

if [ $RECENT_AUTH -gt 0 ] && [ $RECENT_PAYMENT -gt 0 ]; then
    echo -e "${GREEN}✓ Recent backups exist for both databases${NC}"
else
    echo -e "${YELLOW}⚠ No recent backups found (within last 24 hours)${NC}"
    echo "  Auth DB recent backups: $RECENT_AUTH"
    echo "  Payment DB recent backups: $RECENT_PAYMENT"
fi

# Check disk space
DISK_USAGE=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4}')

echo ""
echo "Disk Space:"
echo "  Usage: ${DISK_USAGE}%"
echo "  Available: $DISK_AVAIL"

if [ $DISK_USAGE -gt 80 ]; then
    echo -e "${RED}✗ Warning: Disk usage above 80%${NC}"
elif [ $DISK_USAGE -gt 70 ]; then
    echo -e "${YELLOW}⚠ Warning: Disk usage above 70%${NC}"
else
    echo -e "${GREEN}✓ Disk space is adequate${NC}"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="