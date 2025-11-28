#!/bin/bash

# PostgreSQL Restore Script for Payment System
# Restores database from backup file

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <database> <backup_file>"
    echo ""
    echo "Examples:"
    echo "  $0 auth /opt/backups/postgres-a/auth_db_20240101_120000.sql.gz"
    echo "  $0 payment /opt/backups/postgres-b/payment_db_20240101_120000.sql.gz"
    echo ""
    echo "To list available backups:"
    echo "  ls -lh /opt/backups/postgres-a/"
    echo "  ls -lh /opt/backups/postgres-b/"
    exit 1
fi

DB_TYPE=$1
BACKUP_FILE=$2

# Configuration based on database type
if [ "$DB_TYPE" = "auth" ]; then
    CONTAINER="postgres-a"
    DB_USER="auth_user"
    DB_NAME="auth_db"
    SERVICE_A_1="service-a-1"
    SERVICE_A_2="service-a-2"
elif [ "$DB_TYPE" = "payment" ]; then
    CONTAINER="postgres-b"
    DB_USER="payment_user"
    DB_NAME="payment_db"
    SERVICE_B_1="service-b-1"
    SERVICE_B_2="service-b-2"
else
    echo -e "${RED}Invalid database type. Use 'auth' or 'payment'${NC}"
    exit 1
fi

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

# Verify backup file integrity
echo "Verifying backup file integrity..."
if ! gunzip -t "$BACKUP_FILE" 2>/dev/null; then
    echo -e "${RED}Backup file is corrupted or not a valid gzip file${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Backup file integrity verified${NC}"

# Warning prompt
echo ""
echo -e "${YELLOW}=========================================="
echo "WARNING: Database Restore"
echo "==========================================${NC}"
echo "Database: $DB_NAME"
echo "Backup file: $BACKUP_FILE"
echo ""
echo -e "${RED}This will:"
echo "1. Stop application services using this database"
echo "2. Drop and recreate the database"
echo "3. Restore data from backup"
echo "4. Restart application services${NC}"
echo ""
echo "All current data in $DB_NAME will be lost!"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

echo ""
echo "=========================================="
echo "Starting Restore Process"
echo "=========================================="

# Step 1: Stop affected services
echo ""
echo "Step 1: Stopping application services..."
if [ "$DB_TYPE" = "auth" ]; then
    docker stop $SERVICE_A_1 $SERVICE_A_2 || true
    echo -e "${GREEN}✓ Stopped Service A instances${NC}"
elif [ "$DB_TYPE" = "payment" ]; then
    docker stop $SERVICE_B_1 $SERVICE_B_2 || true
    echo -e "${GREEN}✓ Stopped Service B instances${NC}"
fi

# Step 2: Drop existing connections
echo ""
echo "Step 2: Terminating existing connections..."
docker exec $CONTAINER psql -U $DB_USER -d postgres -c \
    "SELECT pg_terminate_backend(pg_stat_activity.pid) 
     FROM pg_stat_activity 
     WHERE pg_stat_activity.datname = '$DB_NAME' 
     AND pid <> pg_backend_pid();" || true
echo -e "${GREEN}✓ Connections terminated${NC}"

# Step 3: Drop database
echo ""
echo "Step 3: Dropping existing database..."
docker exec $CONTAINER psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
echo -e "${GREEN}✓ Database dropped${NC}"

# Step 4: Create new database
echo ""
echo "Step 4: Creating new database..."
docker exec $CONTAINER psql -U $DB_USER -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
echo -e "${GREEN}✓ Database created${NC}"

# Step 5: Restore from backup
echo ""
echo "Step 5: Restoring data from backup..."
echo "This may take several minutes depending on backup size..."

if gunzip -c "$BACKUP_FILE" | docker exec -i $CONTAINER psql -U $DB_USER -d $DB_NAME > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Data restored successfully${NC}"
else
    echo -e "${RED}✗ Failed to restore data${NC}"
    echo "Attempting to recreate empty database..."
    docker exec $CONTAINER psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
    docker exec $CONTAINER psql -U $DB_USER -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    exit 1
fi

# Step 6: Verify restoration
echo ""
echo "Step 6: Verifying restoration..."

# Check if database exists and has tables
TABLE_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" | xargs)

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Database restored with $TABLE_COUNT table(s)${NC}"
else
    echo -e "${YELLOW}⚠ Warning: No tables found in restored database${NC}"
fi

# Step 7: Restart services
echo ""
echo "Step 7: Restarting application services..."
if [ "$DB_TYPE" = "auth" ]; then
    docker start $SERVICE_A_1 $SERVICE_A_2
    echo "Waiting for services to be healthy..."
    sleep 30
    echo -e "${GREEN}✓ Service A instances restarted${NC}"
elif [ "$DB_TYPE" = "payment" ]; then
    docker start $SERVICE_B_1 $SERVICE_B_2
    echo "Waiting for services to be healthy..."
    sleep 30
    echo -e "${GREEN}✓ Service B instances restarted${NC}"
fi

# Step 8: Final verification
echo ""
echo "Step 8: Final verification..."

# Test database connection
if docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Database connection failed${NC}"
    exit 1
fi

# Test service health (if applicable)
sleep 10
if [ "$DB_TYPE" = "auth" ]; then
    if curl -sk https://localhost/auth/health | grep -q "ok"; then
        echo -e "${GREEN}✓ Service A is healthy${NC}"
    else
        echo -e "${YELLOW}⚠ Service A health check failed - may need more time${NC}"
    fi
elif [ "$DB_TYPE" = "payment" ]; then
    if curl -sk https://localhost/payments/health/check | grep -q "ok"; then
        echo -e "${GREEN}✓ Service B is healthy${NC}"
    else
        echo -e "${YELLOW}⚠ Service B health check failed - may need more time${NC}"
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Restore Completed Successfully${NC}"
echo "=========================================="
echo ""
echo "Database: $DB_NAME"
echo "Restored from: $BACKUP_FILE"
echo "Tables restored: $TABLE_COUNT"
echo ""
echo "Next steps:"
echo "1. Verify application functionality"
echo "2. Check logs: docker logs $SERVICE_A_1 (or $SERVICE_B_1)"
echo "3. Test critical operations"
echo ""