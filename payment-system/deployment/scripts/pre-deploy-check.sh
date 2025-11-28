#!/bin/bash

# Pre-Deployment Checklist Script
# Verifies system is ready for deployment

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "Pre-Deployment Checklist"
echo "========================================"
echo ""

WARNINGS=0
ERRORS=0

# Check 1: Docker daemon
echo -e "${YELLOW}Check 1: Docker Daemon${NC}"
if docker ps > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker is running${NC}"
else
    echo -e "${RED}✗ Docker is not running${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Disk space
echo ""
echo -e "${YELLOW}Check 2: Disk Space${NC}"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✓ Sufficient disk space (${DISK_USAGE}% used)${NC}"
elif [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "${YELLOW}⚠ Disk usage is ${DISK_USAGE}% - consider cleanup${NC}"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${RED}✗ Critical disk usage: ${DISK_USAGE}%${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: All services currently healthy
echo ""
echo -e "${YELLOW}Check 3: Current Service Health${NC}"
if curl -sf https://localhost/auth/health > /dev/null 2>&1 && \
   curl -sf https://localhost/payments/health/check > /dev/null 2>&1; then
    echo -e "${GREEN}✓ All services currently healthy${NC}"
else
    echo -e "${RED}✗ Some services are unhealthy${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Recent backups exist
echo ""
echo -e "${YELLOW}Check 4: Recent Database Backups${NC}"
RECENT_BACKUPS=$(find /opt/backups/postgres-a -name "*.sql.gz" -mtime -1 2>/dev/null | wc -l)

if [ "$RECENT_BACKUPS" -gt 0 ]; then
    echo -e "${GREEN}✓ Recent backups found (last 24 hours)${NC}"
else
    echo -e "${YELLOW}⚠ No recent backups found${NC}"
    echo "  Consider running: sudo -u deployer /opt/payment-system/deployment/scripts/backup-postgres.sh"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 5: Docker images built
echo ""
echo -e "${YELLOW}Check 5: Docker Images${NC}"
if docker images | grep -q payment-system-service-a && \
   docker images | grep -q payment-system-service-b; then
    echo -e "${GREEN}✓ Docker images exist${NC}"
else
    echo -e "${RED}✗ Docker images not found${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 6: No pending system updates
echo ""
echo -e "${YELLOW}Check 6: System Updates${NC}"
if [ -f /var/run/reboot-required ]; then
    echo -e "${YELLOW}⚠ System reboot required after updates${NC}"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${GREEN}✓ No pending reboot${NC}"
fi

# Check 7: Monitoring is active
echo ""
echo -e "${YELLOW}Check 7: Monitoring Stack${NC}"
if docker ps | grep -q prometheus && docker ps | grep -q grafana; then
    echo -e "${GREEN}✓ Monitoring stack is running${NC}"
else
    echo -e "${YELLOW}⚠ Monitoring stack is not running${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 8: Current load
echo ""
echo -e "${YELLOW}Check 8: System Load${NC}"
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CPU_COUNT=$(nproc)
LOAD_INT=$(echo "$LOAD" | awk '{print int($1)}')

if [ "$LOAD_INT" -lt "$CPU_COUNT" ]; then
    echo -e "${GREEN}✓ System load is normal ($LOAD)${NC}"
else
    echo -e "${YELLOW}⚠ High system load: $LOAD${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 9: Memory availability
echo ""
echo -e "${YELLOW}Check 9: Memory Availability${NC}"
MEM_AVAIL=$(free | grep Mem | awk '{print int($7/$2 * 100)}')

if [ "$MEM_AVAIL" -gt 20 ]; then
    echo -e "${GREEN}✓ Sufficient memory available (${MEM_AVAIL}%)${NC}"
else
    echo -e "${YELLOW}⚠ Low memory available: ${MEM_AVAIL}%${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 10: Git repository status - if in git
echo ""
echo -e "${YELLOW}Check 10: Git Status${NC}"
if [ -d .git ]; then
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "${GREEN}✓ No uncommitted changes${NC}"
    else
        echo -e "${YELLOW}⚠ Uncommitted changes exist${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "  Not a git repository (skipped)"
fi

# Summary
echo ""
echo "========================================"
echo "Pre-Deployment Checklist Summary"
echo "========================================"
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}✗ FAILED - Fix errors before deploying${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ PASSED WITH WARNINGS${NC}"
    echo "Review warnings before proceeding"
    echo ""
    read -p "Continue with deployment? (yes/no): " CONTINUE
    if [ "$CONTINUE" = "yes" ]; then
        exit 0
    else
        echo "Deployment cancelled"
        exit 1
    fi
else
    echo -e "${GREEN}✓ PASSED - System ready for deployment${NC}"
    exit 0
fi