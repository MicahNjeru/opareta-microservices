# Zero-Downtime Deployment Guide

## Overview

This guide explains how to deploy updates to the Payment System with zero downtime using rolling updates.

## Deployment Strategy

### Rolling Update

The deployment script performs rolling updates:
1. Updates instances one at a time
2. Waits for health checks before continuing
3. Verifies traffic is being received
4. Maintains service availability throughout

### Timeline

**Total deployment time:** ~5-10 minutes
- Pre-deployment checks: 1 minute
- Service A deployment: 2-4 minutes
- Service B deployment: 2-4 minutes
- Post-deployment validation: 1-2 minutes

## Prerequisites

- SSH access to server
- Sudo/docker permissions
- Recent backup completed
- All services currently healthy

## Deployment Process

### Step 1: Pre-Deployment Preparation

**1.1 Backup Database (Recommended)**
```bash
ssh deployer@YOUR_SERVER_IP
cd /opt/payment-system/deployment
sudo -u deployer ./scripts/backup-postgres.sh
```

**1.2 Review Changes**
```bash
# If using git
git log --oneline -10
git diff HEAD~1

# Review what will be deployed
```

**1.3 Run Pre-Deployment Checklist**
```bash
./scripts/pre-deploy-check.sh
```

This checks:
- Docker is running
- Sufficient disk space
- Services are healthy
- Recent backups exist
- System load is normal

### Step 2: Build New Images

**Option A: Build on Server**
```bash
cd /opt/payment-system/deployment
docker-compose -f docker-compose.prod.yml build
```

**Option B: Build Locally and Push**
```bash
# On local machine
docker-compose -f docker-compose.prod.yml build
docker tag payment-system-service-a:latest registry.example.com/service-a:v1.2.3
docker push registry.example.com/service-a:v1.2.3

# On server
docker pull registry.example.com/service-a:v1.2.3
```

### Step 3: Execute Deployment

**Deploy All Services (Default)**
```bash
cd /opt/payment-system/deployment
./scripts/deploy.sh
```

**Deploy Specific Service Only**
```bash
# Deploy only Service A
./scripts/deploy.sh latest service-a

# Deploy only Service B
./scripts/deploy.sh latest service-b
```

**Deploy with Version Tag**
```bash
./scripts/deploy.sh v1.2.3
```

### Step 4: Deployment Process (Automatic)

The script will:

1. **Pre-Deployment Checks**
   - Verify Docker is running
   - Validate docker-compose configuration
   - Check current service health

2. **Pull/Build Images**
   - Build new Docker images
   - Verify build success

3. **Deploy Service A**
   - Stop service-a-2
   - Start new service-a-2
   - Wait for health check (up to 60s)
   - Verify traffic routing
   - Pause 10 seconds
   - Stop service-a-1
   - Start new service-a-1
   - Wait for health check
   - Verify traffic routing

4. **Deploy Service B**
   - Same process as Service A
   - Updates service-b-2 first
   - Then service-b-1

5. **Post-Deployment Verification**
   - Verify all services healthy
   - Test critical endpoints
   - Check for errors in logs
   - Create deployment record

### Step 5: Validation

**Run Validation Script**
```bash
./scripts/validate-deployment.sh
```

This validates:
- All containers running
- Service health checks passing
- Database connectivity
- Redis connectivity
- Nginx routing
- Load balancing
- SSL/TLS
- Recent error rate

**Manual Verification**
```bash
# Check service health
curl -k https://localhost/auth/health
curl -k https://localhost/payments/health/check

# Check container status
docker ps

# Check logs for errors
docker-compose -f docker-compose.prod.yml logs --tail=50 | grep -i error

# Check Grafana metrics
# Open: http://YOUR_SERVER_IP:3000
```

### Step 6: Monitor Post-Deployment

**Monitor for 15-30 minutes:**

```bash
# Watch logs
docker-compose -f docker-compose.prod.yml logs -f

# Watch metrics
# Grafana: http://YOUR_SERVER_IP:3000
# Prometheus: http://YOUR_SERVER_IP:9090

# Check error rate
watch "docker-compose logs --tail=100 | grep -c ERROR"
```

## Rollback Procedure

If issues are detected after deployment:

### Quick Rollback

```bash
cd /opt/payment-system/deployment
./scripts/rollback.sh
```

The rollback script will:
1. Stop current instances
2. Revert to previous Docker images
3. Start instances with old images
4. Verify health checks
5. Create rollback record

### Manual Rollback

If rollback script fails:

```bash
# Stop current services
docker-compose -f docker-compose.prod.yml stop service-a-1 service-a-2 service-b-1 service-b-2

# Remove containers
docker-compose -f docker-compose.prod.yml rm -f service-a-1 service-a-2 service-b-1 service-b-2

# Find previous image IDs
docker images | grep payment-system

# Tag previous images
docker tag <PREVIOUS_IMAGE_ID> payment-system-service-a:latest
docker tag <PREVIOUS_IMAGE_ID> payment-system-service-b:latest

# Restart services
docker-compose -f docker-compose.prod.yml up -d service-a-1 service-a-2 service-b-1 service-b-2

# Verify
./scripts/validate-deployment.sh
```

## Deployment Scenarios

### Scenario 1: Hotfix Deployment

For critical bug fixes:

```bash
# 1. Apply fix to code
# 2. Build and test locally
# 3. Create backup
sudo -u deployer ./scripts/backup-postgres.sh

# 4. Deploy
./scripts/deploy.sh hotfix

# 5. Validate immediately
./scripts/validate-deployment.sh

# 6. Monitor closely for 30 minutes
```

### Scenario 2: Major Version Deployment

For significant changes:

```bash
# 1. Deploy to staging first (if available)
# 2. Schedule maintenance window
# 3. Notify users of deployment
# 4. Create backup
sudo -u deployer ./scripts/backup-postgres.sh

# 5. Run pre-deployment checks
./scripts/pre-deploy-check.sh

# 6. Deploy
./scripts/deploy.sh v2.0.0

# 7. Extended validation
./scripts/validate-deployment.sh

# 8. Functional testing
# Test critical user flows

# 9. Monitor for extended period (2-4 hours)
```

### Scenario 3: Database Migration

For deployments with database changes:

```bash
# 1. Create backup
sudo -u deployer ./scripts/backup-postgres.sh

# 2. Test migration on backup copy (recommended)
# 3. Deploy application with migration
./scripts/deploy.sh

# 4. Monitor for migration completion
docker logs service-a-1 | grep -i migration
docker logs service-b-1 | grep -i migration

# 5. Verify data integrity
# 6. Test application functionality
```

## Troubleshooting

### Deployment Hangs on Health Check

**Issue:** Health check times out

**Solutions:**
```bash
# Check service logs
docker logs service-a-1 --tail=50

# Check if service is actually running
docker ps | grep service-a-1

# Try accessing health endpoint directly
curl http://localhost:3001/health

# If database issue:
docker logs postgres-a
docker exec postgres-a pg_isready -U auth_user
```

### Service Fails to Start

**Issue:** Container starts but immediately exits

**Solutions:**
```bash
# Check logs
docker logs service-a-1

# Common issues:
# - Database connection failed
# - Environment variable missing
# - Port already in use

# Verify environment variables
docker inspect service-a-1 | jq '.[0].Config.Env'

# Check port conflicts
netstat -tlnp | grep 3001
```

### Health Check Passes but Service Unresponsive

**Issue:** Health endpoint works but other endpoints fail

**Solutions:**
```bash
# Test endpoints manually
curl -v https://localhost/auth/register

# Check Nginx routing
docker logs nginx | tail -50

# Check for application errors
docker logs service-a-1 | grep -i error

# Verify database connectivity
docker exec service-a-1 curl http://postgres-a:5432
```

### Rollback Fails

**Issue:** Rollback script encounters errors

**Solutions:**
```bash
# Stop all service containers
docker-compose -f docker-compose.prod.yml stop service-a-1 service-a-2 service-b-1 service-b-2

# Manually restore from backup
./scripts/restore-postgres.sh auth BACKUP_FILE
./scripts/restore-postgres.sh payment BACKUP_FILE

# Start services with previous images
docker-compose -f docker-compose.prod.yml up -d

# If complete failure:
# Redeploy from known good state
git checkout PREVIOUS_COMMIT
docker-compose -f docker-compose.prod.yml build
docker-compose -f docker-compose.prod.yml up -d
```

## Deployment Checklist

### Pre-Deployment
- [ ] Recent backup completed
- [ ] Pre-deployment checks passed
- [ ] Team notified
- [ ] Rollback plan ready
- [ ] Monitoring dashboards open
- [ ] Off-peak time chosen

### During Deployment
- [ ] Build successful
- [ ] Deployment script completed
- [ ] All health checks passed
- [ ] No errors in logs
- [ ] Load balancing verified

### Post-Deployment
- [ ] Validation script passed
- [ ] Critical endpoints tested
- [ ] Monitored for 30 minutes
- [ ] No elevated error rates
- [ ] Deployment documented
- [ ] Team notified of completion

## Deployment Logs

All deployments are logged to:
- `/opt/backups/deployment.log` - Detailed deployment log
- `/opt/backups/deployments/` - Per-deployment records

Review logs:
```bash
# View recent deployments
ls -lt /opt/backups/deployments/ | head -10

# View deployment log
tail -100 /opt/backups/deployment.log

# Search for specific deployment
grep "2024-01-15" /opt/backups/deployment.log
```

## Version Management

### Tagging Releases

```bash
# Tag release in git
git tag -a v1.2.3 -m "Release version 1.2.3"
git push origin v1.2.3

# Build with version tag
docker build -t payment-system-service-a:v1.2.3 service-a/
docker build -t payment-system-service-b:v1.2.3 service-b/

# Deploy specific version
./scripts/deploy.sh v1.2.3
```

### Version History

Maintain version history:
```bash
# List deployed versions
ls -lt /opt/backups/deployments/

# Each deployment record includes:
# - Timestamp
# - Version deployed
# - Services updated
# - Image tags used
```