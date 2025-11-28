#!/bin/bash

# Zero-Downtime Deployment Script
# Performs rolling updates with health checks

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
HEALTH_CHECK_TIMEOUT=60
HEALTH_CHECK_INTERVAL=5
DEPLOYMENT_LOG="/opt/backups/deployment.log"

# Services to deploy
SERVICES=("service-a" "service-b")

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOYMENT_LOG"
}

# Error handling
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$DEPLOYMENT_LOG"
    exit 1
}

# Check if running from correct directory
if [ ! -f "$COMPOSE_FILE" ]; then
    error_exit "Must run from deployment directory containing $COMPOSE_FILE"
fi

# Parse arguments
VERSION="${1:-latest}"
SERVICE_TO_DEPLOY="${2:-all}"

echo -e "${BLUE}=========================================="
echo "Zero-Downtime Deployment"
echo "==========================================${NC}"
log "Starting deployment"
log "Version: $VERSION"
log "Service: $SERVICE_TO_DEPLOY"

# Pre-deployment checks
echo ""
echo -e "${YELLOW}Pre-Deployment Checks${NC}"
echo "----------------------------------------"

# Check Docker
if ! docker ps > /dev/null 2>&1; then
    error_exit "Cannot connect to Docker daemon"
fi
log "✓ Docker is running"

# Check compose file
if ! docker-compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
    error_exit "Invalid docker-compose file"
fi
log "✓ Docker Compose configuration is valid"

# Check all services are healthy
check_service_health() {
    local SERVICE=$1
    local INSTANCE=$2
    local MAX_ATTEMPTS=$((HEALTH_CHECK_TIMEOUT / HEALTH_CHECK_INTERVAL))
    local ATTEMPT=0
    
    log "Checking health of $INSTANCE..."
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if docker inspect "$INSTANCE" | jq -e '.[0].State.Health.Status == "healthy"' > /dev/null 2>&1; then
            log "✓ $INSTANCE is healthy"
            return 0
        fi
        
        # Also check if container is running without health check
        if docker inspect "$INSTANCE" | jq -e '.[0].State.Running == true' > /dev/null 2>&1; then
            # Try to curl health endpoint
            local PORT=""
            if [[ "$INSTANCE" == *"service-a-1"* ]]; then
                PORT="3001"
            elif [[ "$INSTANCE" == *"service-a-2"* ]]; then
                PORT="3003"
            elif [[ "$INSTANCE" == *"service-b-1"* ]]; then
                PORT="3002"
            elif [[ "$INSTANCE" == *"service-b-2"* ]]; then
                PORT="3004"
            fi
            
            if [ -n "$PORT" ]; then
                if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
                    log "✓ $INSTANCE is responding"
                    return 0
                fi
            fi
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log "✗ $INSTANCE health check failed"
    return 1
}

# Pull/build new images
echo ""
echo -e "${YELLOW}Pulling/Building New Images${NC}"
echo "----------------------------------------"

if [ "$VERSION" != "latest" ]; then
    log "Using version tag: $VERSION"
    # If using version tags, pull from registry
    # docker-compose -f "$COMPOSE_FILE" pull
fi

log "Building images..."
if docker-compose -f "$COMPOSE_FILE" build --pull > /dev/null 2>&1; then
    log "✓ Images built successfully"
else
    error_exit "Failed to build images"
fi

# Function to deploy a service instance
deploy_instance() {
    local SERVICE=$1
    local INSTANCE=$2
    
    echo ""
    echo -e "${BLUE}Deploying $INSTANCE${NC}"
    echo "----------------------------------------"
    
    # Record current state
    log "Starting deployment of $INSTANCE"
    
    # Stop instance
    log "Stopping $INSTANCE..."
    if docker-compose -f "$COMPOSE_FILE" stop "$INSTANCE" > /dev/null 2>&1; then
        log "✓ $INSTANCE stopped"
    else
        log "⚠ Failed to stop $INSTANCE gracefully, forcing..."
        docker stop "$INSTANCE" || true
    fi
    
    # Remove old container
    log "Removing old container..."
    docker-compose -f "$COMPOSE_FILE" rm -f "$INSTANCE" > /dev/null 2>&1
    
    # Start new container
    log "Starting new $INSTANCE..."
    if docker-compose -f "$COMPOSE_FILE" up -d "$INSTANCE" > /dev/null 2>&1; then
        log "✓ $INSTANCE started"
    else
        error_exit "Failed to start $INSTANCE"
    fi
    
    # Wait for health check
    log "Waiting for $INSTANCE to become healthy..."
    if check_service_health "$SERVICE" "$INSTANCE"; then
        log "✓ $INSTANCE is healthy and ready"
    else
        error_exit "$INSTANCE failed health check"
    fi
    
    # Additional verification - check if receiving traffic
    log "Verifying $INSTANCE is receiving traffic..."
    sleep 5
    
    # Check Nginx logs for requests to this instance
    local LOG_CHECK=$(docker logs nginx 2>&1 | tail -20 | grep -c "$INSTANCE" || echo "0")
    if [ "$LOG_CHECK" -gt 0 ]; then
        log "✓ $INSTANCE is receiving traffic"
    else
        log "⚠ No traffic detected yet (may need more time)"
    fi
}

# Deploy Service A
if [ "$SERVICE_TO_DEPLOY" = "all" ] || [ "$SERVICE_TO_DEPLOY" = "service-a" ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "Deploying Service A (Authentication)"
    echo "==========================================${NC}"
    
    # Deploy instance 2 first - less traffic during odd hours
    deploy_instance "service-a" "service-a-2"
    
    # Pause between instances
    log "Pausing 10 seconds before next instance..."
    sleep 10
    
    # Deploy instance 1
    deploy_instance "service-a" "service-a-1"
    
    log "✓ Service A deployment complete"
fi

# Deploy Service B
if [ "$SERVICE_TO_DEPLOY" = "all" ] || [ "$SERVICE_TO_DEPLOY" = "service-b" ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "Deploying Service B (Payment)"
    echo "==========================================${NC}"
    
    # Deploy instance 2 first
    deploy_instance "service-b" "service-b-2"
    
    # Pause between instances
    log "Pausing 10 seconds before next instance..."
    sleep 10
    
    # Deploy instance 1
    deploy_instance "service-b" "service-b-1"
    
    log "✓ Service B deployment complete"
fi

# Post-deployment verification
echo ""
echo -e "${YELLOW}Post-Deployment Verification${NC}"
echo "----------------------------------------"

# Check all services are healthy
log "Verifying all services are healthy..."

UNHEALTHY=0
for SERVICE in service-a-1 service-a-2 service-b-1 service-b-2; do
    if ! check_service_health "" "$SERVICE"; then
        log "✗ $SERVICE is not healthy"
        UNHEALTHY=$((UNHEALTHY + 1))
    fi
done

if [ $UNHEALTHY -gt 0 ]; then
    error_exit "$UNHEALTHY service(s) are not healthy after deployment"
fi

log "✓ All services are healthy"

# Test critical endpoints
log "Testing critical endpoints..."

# Test Service A
if curl -sf https://localhost/auth/health > /dev/null 2>&1; then
    log "✓ Service A is responding"
else
    log "✗ Service A health check failed"
fi

# Test Service B
if curl -sf https://localhost/payments/health/check > /dev/null 2>&1; then
    log "✓ Service B is responding"
else
    log "✗ Service B health check failed"
fi

# Check for errors in logs
log "Checking for errors in recent logs..."
ERROR_COUNT=$(docker-compose -f "$COMPOSE_FILE" logs --tail=50 | grep -i "error" | wc -l)
if [ "$ERROR_COUNT" -gt 5 ]; then
    log "⚠ Warning: $ERROR_COUNT errors found in recent logs"
else
    log "✓ No significant errors in logs"
fi

# Create deployment record
DEPLOYMENT_RECORD="/opt/backups/deployments/deployment_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p /opt/backups/deployments
cat > "$DEPLOYMENT_RECORD" <<EOF
Deployment Record
=================
Date: $(date)
Version: $VERSION
Service: $SERVICE_TO_DEPLOY
Status: SUCCESS

Services Deployed:
$(docker-compose -f "$COMPOSE_FILE" ps --services | grep service-)

Image Tags:
$(docker images | grep payment-system | head -5)

Health Status:
$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep service-)
EOF

log "Deployment record saved: $DEPLOYMENT_RECORD"

# Summary
echo ""
echo -e "${GREEN}=========================================="
echo "Deployment Successful!"
echo "==========================================${NC}"
log "Deployment completed successfully"
echo ""
echo "Deployment Summary:"
echo "  Version: $VERSION"
echo "  Service: $SERVICE_TO_DEPLOY"
echo "  Time: $(date)"
echo ""
echo "Deployed Services:"
docker-compose -f "$COMPOSE_FILE" ps --services | grep service- | while read svc; do
    echo "  ✓ $svc"
done
echo ""
echo "Next Steps:"
echo "  1. Monitor application logs: docker-compose -f $COMPOSE_FILE logs -f"
echo "  2. Check metrics in Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "  3. Verify functionality with test requests"
echo ""
echo "To rollback if needed:"
echo "  ./scripts/rollback.sh"
echo ""