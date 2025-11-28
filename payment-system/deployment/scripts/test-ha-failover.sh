#!/bin/bash

# High Availability Failover Test Script
# Tests various failover scenarios

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOST="${1:-localhost}"

echo "========================================"
echo "High Availability Failover Tests"
echo "========================================"
echo "Target: $HOST"
echo ""

# Test 1: Single Instance Failover
echo -e "${YELLOW}Test 1: Single Service Instance Failover${NC}"
echo "Stopping service-a-1..."

# Record start time
START_TIME=$(date +%s)

# Stop instance
docker stop service-a-1 > /dev/null

# Test that service still works
ERRORS=0
for i in {1..10}; do
    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://$HOST/auth/health 2>/dev/null)
    if [ "$STATUS" != "200" ]; then
        ERRORS=$((ERRORS + 1))
    fi
    sleep 1
done

echo "Errors during failover: $ERRORS/10"

if [ $ERRORS -le 2 ]; then
    echo -e "${GREEN}✓ Failover successful (≤2 errors acceptable)${NC}"
else
    echo -e "${RED}✗ Too many errors during failover${NC}"
fi

# Wait for auto-restart
echo "Waiting for auto-restart..."
sleep 30

# Check if instance restarted
if docker ps | grep -q service-a-1; then
    RESTART_TIME=$(($(date +%s) - START_TIME))
    echo -e "${GREEN}✓ Instance auto-restarted in ${RESTART_TIME}s${NC}"
else
    echo -e "${RED}✗ Instance did not auto-restart${NC}"
fi

echo ""

# Test 2: Load Distribution
echo -e "${YELLOW}Test 2: Load Distribution Test${NC}"
echo "Sending 30 requests..."

# Create temp file for tracking
TEMP_FILE=$(mktemp)

for i in {1..30}; do
    curl -sk https://$HOST/auth/health 2>/dev/null >> $TEMP_FILE
    sleep 0.2
done

UNIQUE=$(sort $TEMP_FILE | uniq | wc -l)
rm $TEMP_FILE

if [ $UNIQUE -gt 1 ]; then
    echo -e "${GREEN}✓ Load distributed across multiple instances${NC}"
else
    echo -e "${YELLOW}⚠ All requests to single instance (check if both running)${NC}"
fi

echo ""

# Test 3: Redis Restart
echo -e "${YELLOW}Test 3: Redis Cache Failover${NC}"
echo "Restarting Redis..."

docker restart redis > /dev/null
sleep 5

# Test service still works
STATUS=$(curl -sk https://$HOST/payments/health/check 2>/dev/null | jq -r '.status')
if [ "$STATUS" = "ok" ]; then
    echo -e "${GREEN}✓ Service operational after Redis restart${NC}"
else
    echo -e "${RED}✗ Service not operational after Redis restart${NC}"
fi

# Wait for Redis to be fully ready
sleep 10

# Check Redis is healthy
REDIS_STATUS=$(docker inspect redis | jq -r '.[0].State.Health.Status')
if [ "$REDIS_STATUS" = "healthy" ]; then
    echo -e "${GREEN}✓ Redis recovered and healthy${NC}"
else
    echo -e "${YELLOW}⚠ Redis status: $REDIS_STATUS${NC}"
fi

echo ""

# Test 4: Database Restart
echo -e "${YELLOW}Test 4: Database Failover${NC}"
echo "Restarting postgres-a..."

docker restart postgres-a > /dev/null
sleep 10

# Test database connection
DB_STATUS=$(docker exec postgres-a pg_isready -U auth_user 2>/dev/null)
if echo "$DB_STATUS" | grep -q "accepting connections"; then
    echo -e "${GREEN}✓ Database accepting connections${NC}"
else
    echo -e "${RED}✗ Database not ready${NC}"
fi

# Wait for services to reconnect
sleep 20

# Test service recovered
AUTH_STATUS=$(curl -sk https://$HOST/auth/health 2>/dev/null | jq -r '.database')
if [ "$AUTH_STATUS" = "connected" ]; then
    echo -e "${GREEN}✓ Service reconnected to database${NC}"
else
    echo -e "${RED}✗ Service not connected to database${NC}"
fi

echo ""

# Test 5: Health Check Endpoints
echo -e "${YELLOW}Test 5: Health Check Validation${NC}"

# Overall health
OVERALL=$(curl -sk https://$HOST/health 2>/dev/null | jq -r '.status')
echo "Overall health: $OVERALL"

# Service A health
SERVICE_A=$(curl -sk https://$HOST/auth/health 2>/dev/null | jq -r '.status')
echo "Service A health: $SERVICE_A"

# Service B health
SERVICE_B=$(curl -sk https://$HOST/payments/health/check 2>/dev/null | jq -r '.status')
echo "Service B health: $SERVICE_B"

if [ "$OVERALL" = "healthy" ] && [ "$SERVICE_A" = "ok" ] && [ "$SERVICE_B" = "ok" ]; then
    echo -e "${GREEN}✓ All health checks passing${NC}"
else
    echo -e "${RED}✗ Some health checks failing${NC}"
fi

echo ""

# Summary
echo "========================================"
echo -e "${GREEN}Failover Testing Complete${NC}"
echo "========================================"
echo ""
echo "All containers status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(service|postgres|redis|nginx)"
echo ""
echo "Run 'docker logs <container>' for detailed logs"
echo "Run 'sudo tail -f /var/log/nginx/error.log' for Nginx upstream status"