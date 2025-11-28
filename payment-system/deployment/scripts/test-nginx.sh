#!/bin/bash

# Nginx Testing Script
# Tests Nginx configuration, load balancing, and endpoints

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HOST="${1:-localhost}"
HTTPS_PORT=443
HTTP_PORT=80

echo "=================================="
echo "Nginx Configuration Test"
echo "=================================="
echo "Host: $HOST"
echo ""

# Test 1: Nginx Configuration Syntax
echo -e "${YELLOW}Test 1: Nginx Configuration Syntax${NC}"
if sudo nginx -t 2>&1 | grep -q "successful"; then
    echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
else
    echo -e "${RED}✗ Nginx configuration has errors${NC}"
    sudo nginx -t
    exit 1
fi

# Test 2: Nginx is Running
echo -e "\n${YELLOW}Test 2: Nginx Service Status${NC}"
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✓ Nginx is running${NC}"
else
    echo -e "${RED}✗ Nginx is not running${NC}"
    exit 1
fi

# Test 3: HTTP to HTTPS Redirect
echo -e "\n${YELLOW}Test 3: HTTP to HTTPS Redirect${NC}"
REDIRECT_TEST=$(curl -s -o /dev/null -w "%{http_code}" -L http://$HOST/health 2>/dev/null || echo "000")
if [ "$REDIRECT_TEST" = "200" ]; then
    echo -e "${GREEN}✓ HTTP redirect working${NC}"
else
    echo -e "${RED}✗ HTTP redirect not working (Status: $REDIRECT_TEST)${NC}"
fi

# Test 4: HTTPS Endpoint
echo -e "\n${YELLOW}Test 4: HTTPS Health Check${NC}"
HTTPS_TEST=$(curl -sk https://$HOST/health | jq -r '.status' 2>/dev/null || echo "fail")
if [ "$HTTPS_TEST" = "healthy" ]; then
    echo -e "${GREEN}✓ HTTPS health check passed${NC}"
else
    echo -e "${RED}✗ HTTPS health check failed${NC}"
fi

# Test 5: Rate Limiting
echo -e "\n${YELLOW}Test 5: Rate Limiting (sending 10 rapid requests)${NC}"
RATE_LIMIT_HITS=0
for i in {1..10}; do
    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://$HOST/health 2>/dev/null)
    if [ "$STATUS" = "429" ]; then
        RATE_LIMIT_HITS=$((RATE_LIMIT_HITS + 1))
    fi
    sleep 0.1
done

if [ $RATE_LIMIT_HITS -gt 0 ]; then
    echo -e "${GREEN}✓ Rate limiting is active (got $RATE_LIMIT_HITS rate limit responses)${NC}"
else
    echo -e "${YELLOW}⚠ No rate limit hits detected (might need more requests)${NC}"
fi

# Test 6: Service A Health Check
echo -e "\n${YELLOW}Test 6: Service A Health Check${NC}"
SERVICE_A_TEST=$(curl -sk https://$HOST/auth/health | jq -r '.status' 2>/dev/null || echo "fail")
if [ "$SERVICE_A_TEST" = "ok" ]; then
    echo -e "${GREEN}✓ Service A is responding${NC}"
else
    echo -e "${RED}✗ Service A is not responding${NC}"
fi

# Test 7: Service B Health Check
echo -e "\n${YELLOW}Test 7: Service B Health Check${NC}"
SERVICE_B_TEST=$(curl -sk https://$HOST/payments/health/check 2>/dev/null | jq -r '.status' 2>/dev/null || echo "fail")
if [ "$SERVICE_B_TEST" = "ok" ]; then
    echo -e "${GREEN}✓ Service B is responding${NC}"
else
    echo -e "${RED}✗ Service B is not responding${NC}"
fi

# Test 8: Load Balancing - Multiple Requests
echo -e "\n${YELLOW}Test 8: Load Balancing Distribution${NC}"
echo "Sending 20 requests to check load distribution..."

# Create temporary file for response tracking
TEMP_FILE=$(mktemp)

for i in {1..20}; do
    curl -sk https://$HOST/auth/health 2>/dev/null >> $TEMP_FILE
    sleep 0.1
done

# Count unique container responses - if containers return unique IDs
UNIQUE_RESPONSES=$(sort $TEMP_FILE | uniq | wc -l)
rm $TEMP_FILE

if [ $UNIQUE_RESPONSES -gt 1 ]; then
    echo -e "${GREEN}✓ Load balancing appears to be working (detected variations)${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify load balancing distribution${NC}"
fi

# Test 9: SSL/TLS Configuration
echo -e "\n${YELLOW}Test 9: SSL/TLS Configuration${NC}"
SSL_TEST=$(echo | openssl s_client -connect $HOST:443 -servername $HOST 2>/dev/null | grep "Protocol" | awk '{print $3}')
if [[ $SSL_TEST == TLSv1.2 ]] || [[ $SSL_TEST == TLSv1.3 ]]; then
    echo -e "${GREEN}✓ SSL/TLS is properly configured ($SSL_TEST)${NC}"
else
    echo -e "${RED}✗ SSL/TLS configuration issue${NC}"
fi

# Test 10: Security Headers
echo -e "\n${YELLOW}Test 10: Security Headers${NC}"
HEADERS=$(curl -skI https://$HOST/health 2>/dev/null)

check_header() {
    local header=$1
    if echo "$HEADERS" | grep -qi "$header"; then
        echo -e "${GREEN}  ✓ $header present${NC}"
    else
        echo -e "${RED}  ✗ $header missing${NC}"
    fi
}

check_header "Strict-Transport-Security"
check_header "X-Content-Type-Options"
check_header "X-Frame-Options"
check_header "X-XSS-Protection"

# Test 11: Nginx Status - if accessible
echo -e "\n${YELLOW}Test 11: Nginx Status Endpoint${NC}"
STATUS_CHECK=$(curl -s http://127.0.0.1/nginx_status 2>/dev/null | grep -c "Active connections" || echo "0")
if [ "$STATUS_CHECK" -gt 0 ]; then
    echo -e "${GREEN}✓ Nginx status endpoint is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Nginx status endpoint not accessible (this is expected from external IPs)${NC}"
fi

# Summary
echo ""
echo "=================================="
echo -e "${GREEN}Testing Complete!${NC}"
echo "=================================="
echo ""
echo "View Nginx logs:"
echo "  Error log:  sudo tail -f /var/log/nginx/error.log"
echo "  Access log: sudo tail -f /var/log/nginx/access.log"
echo "  App log:    sudo tail -f /var/log/nginx/payment-system-access.log"
echo ""
echo "Nginx commands:"
echo "  Status:  sudo systemctl status nginx"
echo "  Restart: sudo systemctl restart nginx"
echo "  Reload:  sudo systemctl reload nginx"
echo "  Test:    sudo nginx -t"
echo "=================================="