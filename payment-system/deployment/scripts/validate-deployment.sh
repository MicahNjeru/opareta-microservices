#!/bin/bash

# Deployment Validation Script
# Validates that deployment was successful

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOST="${1:-localhost}"

echo "========================================"
echo "Deployment Validation"
echo "========================================"
echo "Target: $HOST"
echo ""

FAILED_CHECKS=0

# Check 1: All containers running
echo -e "${YELLOW}Check 1: Container Status${NC}"
EXPECTED_CONTAINERS=8
RUNNING_CONTAINERS=$(docker ps | grep -E "(service-a|service-b|postgres|redis|nginx)" | wc -l)

if [ "$RUNNING_CONTAINERS" -eq "$EXPECTED_CONTAINERS" ]; then
    echo -e "${GREEN}✓ All $EXPECTED_CONTAINERS containers running${NC}"
else
    echo -e "${RED}✗ Expected $EXPECTED_CONTAINERS containers, found $RUNNING_CONTAINERS${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 2: Service A health
echo ""
echo -e "${YELLOW}Check 2: Service A Health${NC}"
SERVICE_A_STATUS=$(curl -sk https://$HOST/auth/health | jq -r '.status' 2>/dev/null || echo "fail")

if [ "$SERVICE_A_STATUS" = "ok" ]; then
    echo -e "${GREEN}✓ Service A is healthy${NC}"
else
    echo -e "${RED}✗ Service A is not healthy${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 3: Service B health
echo ""
echo -e "${YELLOW}Check 3: Service B Health${NC}"
SERVICE_B_STATUS=$(curl -sk https://$HOST/payments/health/check | jq -r '.status' 2>/dev/null || echo "fail")

if [ "$SERVICE_B_STATUS" = "ok" ]; then
    echo -e "${GREEN}✓ Service B is healthy${NC}"
else
    echo -e "${RED}✗ Service B is not healthy${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 4: Database connectivity
echo ""
echo -e "${YELLOW}Check 4: Database Connectivity${NC}"
AUTH_DB=$(curl -sk https://$HOST/auth/health | jq -r '.database' 2>/dev/null || echo "fail")
PAYMENT_DB=$(curl -sk https://$HOST/payments/health/check | jq -r '.database' 2>/dev/null || echo "fail")

if [ "$AUTH_DB" = "connected" ] && [ "$PAYMENT_DB" = "connected" ]; then
    echo -e "${GREEN}✓ Both databases connected${NC}"
else
    echo -e "${RED}✗ Database connectivity issue${NC}"
    echo "  Auth DB: $AUTH_DB"
    echo "  Payment DB: $PAYMENT_DB"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 5: Redis connectivity
echo ""
echo -e "${YELLOW}Check 5: Redis Connectivity${NC}"
REDIS_STATUS=$(curl -sk https://$HOST/payments/health/check | jq -r '.redis' 2>/dev/null || echo "fail")

if [ "$REDIS_STATUS" = "connected" ]; then
    echo -e "${GREEN}✓ Redis connected${NC}"
else
    echo -e "${RED}✗ Redis connectivity issue${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 6: Nginx routing
echo ""
echo -e "${YELLOW}Check 6: Nginx Routing${NC}"
NGINX_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://$HOST/health)

if [ "$NGINX_STATUS" = "200" ]; then
    echo -e "${GREEN}✓ Nginx is routing correctly${NC}"
else
    echo -e "${RED}✗ Nginx routing issue (status: $NGINX_STATUS)${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 7: Load balancing
echo ""
echo -e "${YELLOW}Check 7: Load Balancing${NC}"
echo "Sending 20 requests to check distribution..."

# Send multiple requests and check if both instances respond
for i in {1..20}; do
    curl -sk https://$HOST/auth/health > /dev/null 2>&1
    sleep 0.1
done

# Check Nginx logs for both instances
INSTANCE1_COUNT=$(docker logs nginx 2>&1 | tail -50 | grep -c "service-a-1" || echo "0")
INSTANCE2_COUNT=$(docker logs nginx 2>&1 | tail -50 | grep -c "service-a-2" || echo "0")

if [ "$INSTANCE1_COUNT" -gt 0 ] && [ "$INSTANCE2_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Load balancing is working${NC}"
    echo "  Instance 1: $INSTANCE1_COUNT requests"
    echo "  Instance 2: $INSTANCE2_COUNT requests"
else
    echo -e "${RED}✗ Load balancing issue${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 8: SSL/TLS
echo ""
echo -e "${YELLOW}Check 8: SSL/TLS${NC}"
SSL_STATUS=$(curl -skI https://$HOST/health | grep -c "HTTP" || echo "0")

if [ "$SSL_STATUS" -gt 0 ]; then
    echo -e "${GREEN}✓ SSL/TLS is working${NC}"
else
    echo -e "${RED}✗ SSL/TLS issue${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 9: Recent errors in logs
echo ""
echo -e "${YELLOW}Check 9: Recent Error Rate${NC}"
ERROR_COUNT=$(docker-compose logs --tail=100 2>&1 | grep -i "error" | grep -v "error_log" | wc -l)

if [ "$ERROR_COUNT" -lt 5 ]; then
    echo -e "${GREEN}✓ Low error rate ($ERROR_COUNT errors in last 100 log lines)${NC}"
else
    echo -e "${YELLOW}⚠ Warning: $ERROR_COUNT errors in last 100 log lines${NC}"
fi

# Check 10: Container health checks
echo ""
echo -e "${YELLOW}Check 10: Container Health Status${NC}"
HEALTHY_COUNT=$(docker ps --format "{{.Status}}" | grep -c "healthy" || echo "0")

echo "Healthy containers: $HEALTHY_COUNT"
if [ "$HEALTHY_COUNT" -ge 4 ]; then
    echo -e "${GREEN}✓ Service containers are healthy${NC}"
else
    echo -e "${YELLOW}⚠ Some containers may not have health checks configured${NC}"
fi

# Summary
echo ""
echo "========================================"
if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}Validation: PASSED${NC}"
    echo "========================================"
    echo "All checks passed successfully!"
    exit 0
else
    echo -e "${RED}Validation: FAILED${NC}"
    echo "========================================"
    echo "$FAILED_CHECKS check(s) failed"
    echo ""
    echo "Review the failures above and:"
    echo "  1. Check service logs: docker-compose logs"
    echo "  2. Check container status: docker ps"
    echo "  3. Check health endpoints manually"
    echo "  4. Consider rollback if issues persist"
    exit 1
fi