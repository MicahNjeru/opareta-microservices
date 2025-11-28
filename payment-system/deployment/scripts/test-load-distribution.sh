#!/bin/bash

# Load Distribution Test Script
# Verifies requests are properly distributed across instances

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOST="${1:-localhost}"
REQUEST_COUNT="${2:-50}"

echo "========================================"
echo "Load Distribution Test"
echo "========================================"
echo "Target: $HOST"
echo "Requests: $REQUEST_COUNT"
echo ""

# Check both instances are running
echo "Checking instance status..."
SERVICE_A_1=$(docker ps --filter "name=service-a-1" --format "{{.Status}}" | grep -c "Up")
SERVICE_A_2=$(docker ps --filter "name=service-a-2" --format "{{.Status}}" | grep -c "Up")
SERVICE_B_1=$(docker ps --filter "name=service-b-1" --format "{{.Status}}" | grep -c "Up")
SERVICE_B_2=$(docker ps --filter "name=service-b-2" --format "{{.Status}}" | grep -c "Up")

if [ $SERVICE_A_1 -eq 0 ] || [ $SERVICE_A_2 -eq 0 ]; then
    echo -e "${RED}✗ Not all Service A instances running${NC}"
    docker ps | grep service-a
    exit 1
fi

if [ $SERVICE_B_1 -eq 0 ] || [ $SERVICE_B_2 -eq 0 ]; then
    echo -e "${RED}✗ Not all Service B instances running${NC}"
    docker ps | grep service-b
    exit 1
fi

echo -e "${GREEN}✓ All service instances running${NC}"
echo ""

# Test Service A distribution
echo -e "${YELLOW}Testing Service A Load Distribution${NC}"
echo "Sending $REQUEST_COUNT requests to /auth/health..."

SUCCESS_COUNT=0
ERROR_COUNT=0

for i in $(seq 1 $REQUEST_COUNT); do
    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://$HOST/auth/health 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    sleep 0.1
done

echo "Results: $SUCCESS_COUNT successful, $ERROR_COUNT errors"

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All requests successful${NC}"
else
    echo -e "${YELLOW}⚠ Some requests failed${NC}"
fi

# Analyze Nginx logs for distribution
echo ""
echo "Analyzing request distribution from Nginx logs..."

# Get last N entries from access log
LOG_ENTRIES=$(sudo tail -n $REQUEST_COUNT /var/log/nginx/payment-system-access.log 2>/dev/null | \
    grep "/auth/health" | wc -l)

if [ $LOG_ENTRIES -gt 0 ]; then
    echo "Found $LOG_ENTRIES log entries"
    
    # Count requests to each upstream
    INSTANCE_1=$(sudo tail -n $REQUEST_COUNT /var/log/nginx/payment-system-access.log 2>/dev/null | \
        grep -c "service-a-1:3001" || echo 0)
    INSTANCE_2=$(sudo tail -n $REQUEST_COUNT /var/log/nginx/payment-system-access.log 2>/dev/null | \
        grep -c "service-a-2:3003" || echo 0)
    
    TOTAL=$((INSTANCE_1 + INSTANCE_2))
    
    if [ $TOTAL -gt 0 ]; then
        PERCENT_1=$(awk "BEGIN {printf \"%.1f\", ($INSTANCE_1/$TOTAL)*100}")
        PERCENT_2=$(awk "BEGIN {printf \"%.1f\", ($INSTANCE_2/$TOTAL)*100}")
        
        echo ""
        echo "Distribution:"
        echo "  service-a-1: $INSTANCE_1 requests ($PERCENT_1%)"
        echo "  service-a-2: $INSTANCE_2 requests ($PERCENT_2%)"
        
        # Check if distribution is reasonable (40-60%)
        if (( $(echo "$PERCENT_1 >= 40 && $PERCENT_1 <= 60" | bc -l) )); then
            echo -e "${GREEN}✓ Load is well distributed${NC}"
        else
            echo -e "${YELLOW}⚠ Load distribution is uneven${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Could not analyze Nginx logs${NC}"
fi

echo ""

# Test Service B distribution
echo -e "${YELLOW}Testing Service B Load Distribution${NC}"
echo "Sending $REQUEST_COUNT requests to /payments/health/check..."

SUCCESS_COUNT=0
ERROR_COUNT=0

for i in $(seq 1 $REQUEST_COUNT); do
    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://$HOST/payments/health/check 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    sleep 0.1
done

echo "Results: $SUCCESS_COUNT successful, $ERROR_COUNT errors"

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All requests successful${NC}"
else
    echo -e "${YELLOW}⚠ Some requests failed${NC}"
fi

# Analyze Service B distribution
echo ""
echo "Analyzing Service B distribution..."

INSTANCE_1=$(sudo tail -n $REQUEST_COUNT /var/log/nginx/payment-system-access.log 2>/dev/null | \
    grep -c "service-b-1:3002" || echo 0)
INSTANCE_2=$(sudo tail -n $REQUEST_COUNT /var/log/nginx/payment-system-access.log 2>/dev/null | \
    grep -c "service-b-2:3004" || echo 0)

TOTAL=$((INSTANCE_1 + INSTANCE_2))

if [ $TOTAL -gt 0 ]; then
    PERCENT_1=$(awk "BEGIN {printf \"%.1f\", ($INSTANCE_1/$TOTAL)*100}")
    PERCENT_2=$(awk "BEGIN {printf \"%.1f\", ($INSTANCE_2/$TOTAL)*100}")
    
    echo ""
    echo "Distribution:"
    echo "  service-b-1: $INSTANCE_1 requests ($PERCENT_1%)"
    echo "  service-b-2: $INSTANCE_2 requests ($PERCENT_2%)"
    
    if (( $(echo "$PERCENT_1 >= 40 && $PERCENT_1 <= 60" | bc -l) )); then
        echo -e "${GREEN}✓ Load is well distributed${NC}"
    else
        echo -e "${YELLOW}⚠ Load distribution is uneven${NC}"
    fi
fi

echo ""

# Test with concurrent connections
echo -e "${YELLOW}Testing Concurrent Connection Distribution${NC}"
echo "Simulating 5 concurrent users..."

# Run 5 parallel request streams
for i in {1..5}; do
    {
        for j in {1..10}; do
            curl -sk https://$HOST/auth/health > /dev/null 2>&1
            sleep 0.1
        done
    } &
done

# Wait for all background jobs
wait

echo -e "${GREEN}✓ Concurrent load test complete${NC}"

echo ""
echo "========================================"
echo "Load Distribution Test Complete"
echo "========================================"
echo ""
echo "Key Findings:"
echo "1. Check that both instances received requests"
echo "2. Distribution should be roughly 40-60% to 60-40%"
echo "3. No instance should be overwhelmed"
echo ""
echo "View detailed logs:"
echo "  sudo tail -100 /var/log/nginx/payment-system-access.log | grep upstream"