#!/bin/bash

# Monitoring Setup Script
# Sets up Prometheus and Grafana

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Monitoring Stack Setup"
echo "=========================================="

# Check if running from deployment directory
if [ ! -f "docker-compose.prod.yml" ]; then
    echo -e "${RED}Error: Must run from deployment directory${NC}"
    exit 1
fi

# Create monitoring directories
echo "Creating monitoring directories..."
mkdir -p monitoring/prometheus
mkdir -p monitoring/grafana/provisioning/datasources
mkdir -p monitoring/grafana/provisioning/dashboards
mkdir -p monitoring/grafana/dashboards

echo -e "${GREEN}✓ Directories created${NC}"

# Check if configuration files exist
echo ""
echo "Checking configuration files..."

FILES=(
    "monitoring/prometheus/prometheus.yml"
    "monitoring/prometheus/alerts.yml"
    "monitoring/grafana/provisioning/datasources/prometheus.yml"
    "monitoring/grafana/provisioning/dashboards/dashboard.yml"
    "monitoring/grafana/dashboards/payment-system-dashboard.json"
)

MISSING_FILES=0
for FILE in "${FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
        echo -e "${RED}✗ Missing: $FILE${NC}"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        echo -e "${GREEN}✓ Found: $FILE${NC}"
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo ""
    echo -e "${RED}Error: $MISSING_FILES configuration file(s) missing${NC}"
    echo "Please ensure all monitoring configuration files are in place."
    exit 1
fi

echo ""
echo "Starting monitoring stack..."

# Start Prometheus and Grafana
docker-compose -f docker-compose.prod.yml up -d prometheus grafana node-exporter

echo ""
echo "Waiting for services to start..."
sleep 10

# Check if services are running
echo ""
echo "Checking service status..."

if docker ps | grep -q prometheus; then
    echo -e "${GREEN}✓ Prometheus is running${NC}"
else
    echo -e "${RED}✗ Prometheus is not running${NC}"
    docker logs prometheus --tail 20
fi

if docker ps | grep -q grafana; then
    echo -e "${GREEN}✓ Grafana is running${NC}"
else
    echo -e "${RED}✗ Grafana is not running${NC}"
    docker logs grafana --tail 20
fi

if docker ps | grep -q node-exporter; then
    echo -e "${GREEN}✓ Node Exporter is running${NC}"
else
    echo -e "${RED}✗ Node Exporter is not running${NC}"
fi

# Test endpoints
echo ""
echo "Testing endpoints..."

# Prometheus
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    echo -e "${GREEN}✓ Prometheus is healthy${NC}"
else
    echo -e "${RED}✗ Prometheus is not responding${NC}"
fi

# Grafana
if curl -s http://localhost:3000/api/health > /dev/null; then
    echo -e "${GREEN}✓ Grafana is healthy${NC}"
else
    echo -e "${YELLOW}⚠ Grafana is starting up...${NC}"
fi

# Node Exporter
if curl -s http://localhost:9100/metrics > /dev/null; then
    echo -e "${GREEN}✓ Node Exporter is healthy${NC}"
else
    echo -e "${RED}✗ Node Exporter is not responding${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Monitoring Stack Setup Complete${NC}"
echo "=========================================="
echo ""
echo "Access URLs:"
echo "  Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "  Grafana:    http://$(hostname -I | awk '{print $1}'):3000"
echo "  Node Exp:   http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo ""
echo "Grafana Default Credentials:"
echo "  Username: admin"
echo "  Password: admin (change on first login)"
echo ""
echo "Next Steps:"
echo "1. Access Grafana and change admin password"
echo "2. Verify Prometheus targets: http://localhost:9090/targets"
echo "3. View dashboard in Grafana"
echo "4. Configure alert notifications (optional)"
echo "5. Add application metrics to services"
echo ""
echo "To view logs:"
echo "  docker logs prometheus"
echo "  docker logs grafana"
echo ""