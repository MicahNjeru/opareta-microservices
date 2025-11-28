#!/bin/bash

# Rollback Script
# Reverts to previous deployment

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
DEPLOYMENT_LOG="/opt/backups/deployment.log"
BACKUP_DIR="/opt/backups/deployments"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOYMENT_LOG"
}

echo -e "${RED}=========================================="
echo "ROLLBACK PROCEDURE"
echo "==========================================${NC}"

# Warning
echo ""
echo -e "${YELLOW}WARNING: This will rollback to the previous deployment${NC}"
echo ""
read -p "Are you sure you want to rollback? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Rollback cancelled."
    exit 0
fi

log "Rollback initiated by user"

# Check if we have deployment records
if [ ! -d "$BACKUP_DIR" ]; then
    log "No deployment records found"
    echo -e "${RED}No previous deployments found${NC}"
    exit 1
fi

# List recent deployments
echo ""
echo "Recent deployments:"
ls -lt "$BACKUP_DIR" | head -6

# Try to get previous image tags
echo ""
echo -e "${YELLOW}Attempting to rollback...${NC}"

# Option 1: Use docker image history
log "Searching for previous image versions..."

# Get current image IDs
CURRENT_A=$(docker images payment-system-service-a --format "{{.ID}}" | head -1)
CURRENT_B=$(docker images payment-system-service-b --format "{{.ID}}" | head -1)

log "Current Service A image: $CURRENT_A"
log "Current Service B image: $CURRENT_B"

# Get previous images - if available
PREVIOUS_A=$(docker images payment-system-service-a --format "{{.ID}}" | sed -n '2p')
PREVIOUS_B=$(docker images payment-system-service-b --format "{{.ID}}" | sed -n '2p')

if [ -z "$PREVIOUS_A" ] || [ -z "$PREVIOUS_B" ]; then
    echo -e "${RED}No previous images found${NC}"
    echo "Rollback requires previous Docker images to be available."
    echo ""
    echo "To rollback manually:"
    echo "  1. Rebuild from previous git commit"
    echo "  2. Run deploy.sh with previous version"
    exit 1
fi

log "Previous Service A image: $PREVIOUS_A"
log "Previous Service B image: $PREVIOUS_B"

# Tag previous images as rollback
docker tag "$PREVIOUS_A" payment-system-service-a:rollback
docker tag "$PREVIOUS_B" payment-system-service-b:rollback

log "Tagged previous images for rollback"

# Update docker-compose to use rollback tags

echo ""
echo -e "${BLUE}Rolling back services...${NC}"

# Rollback Service A
echo ""
echo "Rolling back Service A..."
log "Stopping Service A instances"

docker-compose -f "$COMPOSE_FILE" stop service-a-1 service-a-2
docker-compose -f "$COMPOSE_FILE" rm -f service-a-1 service-a-2

# Use previous images
docker tag payment-system-service-a:rollback payment-system-service-a:latest

log "Starting Service A with previous image"
docker-compose -f "$COMPOSE_FILE" up -d service-a-1 service-a-2

echo "Waiting for Service A to be healthy..."
sleep 30

# Check health
if curl -sf https://localhost/auth/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Service A is healthy${NC}"
    log "Service A rollback successful"
else
    echo -e "${RED}✗ Service A health check failed${NC}"
    log "Service A rollback health check failed"
fi

# Rollback Service B
echo ""
echo "Rolling back Service B..."
log "Stopping Service B instances"

docker-compose -f "$COMPOSE_FILE" stop service-b-1 service-b-2
docker-compose -f "$COMPOSE_FILE" rm -f service-b-1 service-b-2

# Use previous images
docker tag payment-system-service-b:rollback payment-system-service-b:latest

log "Starting Service B with previous image"
docker-compose -f "$COMPOSE_FILE" up -d service-b-1 service-b-2

echo "Waiting for Service B to be healthy..."
sleep 30

# Check health
if curl -sf https://localhost/payments/health/check > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Service B is healthy${NC}"
    log "Service B rollback successful"
else
    echo -e "${RED}✗ Service B health check failed${NC}"
    log "Service B rollback health check failed"
fi

# Verification
echo ""
echo -e "${YELLOW}Verifying rollback...${NC}"

# Check all containers are running
RUNNING=$(docker-compose -f "$COMPOSE_FILE" ps --services | grep service- | wc -l)
echo "Running service containers: $RUNNING/4"

if [ "$RUNNING" -eq 4 ]; then
    echo -e "${GREEN}✓ All service containers are running${NC}"
else
    echo -e "${RED}✗ Not all service containers are running${NC}"
fi

# Test endpoints
echo ""
echo "Testing endpoints..."
if curl -sf https://localhost/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ System health endpoint OK${NC}"
else
    echo -e "${RED}✗ System health endpoint failed${NC}"
fi

# Create rollback record
ROLLBACK_RECORD="$BACKUP_DIR/rollback_$(date +%Y%m%d_%H%M%S).txt"
cat > "$ROLLBACK_RECORD" <<EOF
Rollback Record
===============
Date: $(date)
Rolled back to previous images

Service Status:
$(docker-compose -f "$COMPOSE_FILE" ps)

Image Status:
$(docker images | grep payment-system | head -6)
EOF

log "Rollback record saved: $ROLLBACK_RECORD"

echo ""
echo -e "${GREEN}=========================================="
echo "Rollback Complete"
echo "==========================================${NC}"
log "Rollback completed"
echo ""
echo "Services have been rolled back to previous version."
echo "Monitor logs and metrics to ensure stability."
echo ""
echo "View logs:"
echo "  docker-compose -f $COMPOSE_FILE logs -f"
echo ""
echo "Check metrics:"
echo "  http://$(hostname -I | awk '{print $1}'):3000"
echo ""