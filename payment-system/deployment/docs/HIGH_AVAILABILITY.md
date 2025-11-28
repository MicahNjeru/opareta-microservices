# High Availability Configuration

## Overview

The Payment System is configured for high availability with redundant components, automatic failover, and persistent data storage.

## Architecture Components

### Service Redundancy

```
┌─────────────────────────────────────────────────┐
│              Nginx Load Balancer                │
│            (Single Point - Port 443)            │
└─────────────────┬───────────────────────────────┘
                  │
         ┌────────┴────────┐
         │                 │
    ┌────▼────┐       ┌────▼────┐
    │Service A│       │Service B│
    │  Pool   │       │  Pool   │
    ├─────────┤       ├─────────┤
    │Instance1│       │Instance1│
    │Instance2│       │Instance2│
    └─────────┘       └─────────┘
```

### Redundant Components

| Component | Instances | Load Balancing | Auto-Restart |
|-----------|-----------|----------------|--------------|
| Service A (Auth) | 2 | Yes (Nginx) | Yes |
| Service B (Payment) | 2 | Yes (Nginx) | Yes |
| PostgreSQL A | 1 | N/A | Yes |
| PostgreSQL B | 1 | N/A | Yes |
| Redis | 1 | N/A | Yes |
| Nginx | 1 | N/A | Yes |

### Single Points of Failure

**Current SPOFs:**
1. **Nginx Load Balancer** - Single instance
2. **PostgreSQL Databases** - Single instances
3. **Redis Cache** - Single instance
4. **Physical Server** - Single server deployment

**Mitigation:**
- All containers have `restart: always` policy
- Health checks detect and isolate failed instances
- Redis has AOF persistence (no data loss on restart)
- PostgreSQL has automated backups
- Application layer handles database connection failures gracefully

**Future Improvements:**
- Nginx: HAProxy + Keepalived for LB redundancy
- PostgreSQL: Streaming replication with failover
- Redis: Sentinel or Cluster mode
- Multi-server deployment with shared storage

## Restart Policies

All services are configured with `restart: always`:

```yaml
restart: always
```

**Behavior:**
- Container restarts on failure
- Container restarts on system reboot
- Container restarts on Docker daemon restart
- Maximum restart attempts: Unlimited
- Backoff strategy: Exponential (1s, 2s, 4s, 8s, up to 1 minute)

## Health Checks

### Service A Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3001/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Health Check Endpoint Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "service": "auth-service",
  "database": "connected"
}
```

### Service B Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3002/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Health Check Endpoint Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-01T12:00:00.000Z",
  "service": "payment-service",
  "database": "connected",
  "redis": "connected"
}
```

### Database Health Checks

**PostgreSQL:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U auth_user -d auth_db"]
  interval: 10s
  timeout: 5s
  retries: 5
```

**Redis:**
```yaml
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### Nginx Load Balancer Health Checks

Nginx monitors backend health:

```nginx
upstream service_a_backend {
    least_conn;
    server service-a-1:3001 max_fails=3 fail_timeout=30s;
    server service-a-2:3003 max_fails=3 fail_timeout=30s;
}
```

**Parameters:**
- `max_fails=3`: Mark backend as down after 3 failed attempts
- `fail_timeout=30s`: Retry backend after 30 seconds
- Failed backends are automatically excluded from load balancing
- Recovered backends are automatically added back

## Failover Scenarios

### Scenario 1: Single Service Instance Failure

**What Happens:**
1. Service instance (e.g., service-a-1) crashes or becomes unhealthy
2. Docker health check detects failure after 3 retries (90 seconds)
3. Nginx stops sending traffic to failed instance
4. All requests routed to healthy instance (service-a-2)
5. Docker automatically restarts failed instance
6. Health check passes, Nginx adds instance back to pool

**Recovery Time:**
- Detection: 30-90 seconds
- Traffic reroute: Immediate (Nginx)
- Container restart: 10-40 seconds
- Total RTO: 1-2 minutes

**Impact:**
- ✅ No service interruption
- ✅ No data loss
- ⚠️ Reduced capacity (50% of instances)
- ⚠️ Increased load on remaining instance

**Test Command:**
```bash
# Stop one instance
docker stop service-a-1

# Verify traffic continues
for i in {1..20}; do curl -k https://localhost/auth/health; done

# Check logs
docker logs nginx | grep upstream

# Instance auto-restarts in background
docker ps | grep service-a
```

### Scenario 2: Database Connection Failure

**What Happens:**
1. PostgreSQL becomes unavailable
2. Application services detect connection failure
3. Health checks start failing
4. Nginx stops routing to unhealthy instances
5. Application returns 503 Service Unavailable
6. PostgreSQL container auto-restarts
7. Services reconnect to database
8. Health checks pass, traffic resumes

**Recovery Time:**
- Detection: 10-30 seconds
- Database restart: 5-10 seconds
- Connection re-establishment: 5-10 seconds
- Total RTO: 30-60 seconds

**Impact:**
- ❌ Service temporarily unavailable
- ✅ No data loss (WAL replay)
- ✅ Automatic recovery

**Test Command:**
```bash
# Stop database
docker stop postgres-a

# Verify services become unhealthy
docker ps --filter "name=service-a"

# Database auto-restarts
# Services auto-reconnect
```

### Scenario 3: Redis Cache Failure

**What Happens:**
1. Redis becomes unavailable
2. Token validation falls back to direct Service A calls
3. Payment idempotency checks fail gracefully
4. Redis container auto-restarts
5. Cache is rebuilt on demand

**Recovery Time:**
- Detection: Immediate (next cache access)
- Redis restart: 5-10 seconds
- Cache rebuild: Progressive (on access)
- Total RTO: 10-20 seconds

**Impact:**
- ⚠️ Increased latency (no cache hits)
- ⚠️ Increased load on Service A
- ✅ Service remains functional
- ⚠️ Webhook idempotency may fail during restart

**Data Persistence:**
- AOF (Append Only File) enabled
- Fsync every second (appendfsync everysec)
- Max 1 second of data loss on crash
- RDB snapshots as backup

**Test Command:**
```bash
# Stop Redis
docker stop redis

# Test that services still work (slower)
curl -k https://localhost/auth/health

# Redis auto-restarts with data
docker logs redis
```

### Scenario 4: Nginx Load Balancer Failure

**What Happens:**
1. Nginx crashes or becomes unresponsive
2. All external traffic blocked (SPOF)
3. Nginx auto-restarts
4. Traffic resumes when Nginx is healthy

**Recovery Time:**
- Detection: Immediate (connection refused)
- Nginx restart: 5-10 seconds
- Total RTO: 10-20 seconds

**Impact:**
- ❌ Complete service outage
- ✅ Backend services remain running
- ✅ No data loss

**Mitigation:**
- Nginx is lightweight and rarely fails
- Configuration is tested before reload
- Consider HAProxy + Keepalived for redundancy

**Test Command:**
```bash
# Stop Nginx
docker stop nginx

# Verify no access
curl -k https://localhost/health

# Nginx auto-restarts
docker ps | grep nginx
```

### Scenario 5: Complete Service Pool Failure

**What Happens:**
1. Both instances of a service fail simultaneously
2. Nginx returns 502 Bad Gateway
3. Both instances auto-restart
4. Services become healthy
5. Traffic resumes

**Recovery Time:**
- Detection: 30-90 seconds
- Container restart: 20-40 seconds each
- Total RTO: 1-2 minutes

**Impact:**
- ❌ Service temporarily unavailable
- ✅ Other services continue working
- ✅ No data loss

**Test Command:**
```bash
# Stop all Service A instances
docker stop service-a-1 service-a-2

# Verify 502 response
curl -k https://localhost/auth/health

# Instances auto-restart
watch docker ps
```

### Scenario 6: Host Server Restart

**What Happens:**
1. Server reboots (planned or crash)
2. Docker daemon starts on boot
3. All containers auto-start
4. Services become healthy
5. System fully operational

**Recovery Time:**
- Server boot: 30-60 seconds
- Docker daemon start: 10-20 seconds
- Container startup: 40-60 seconds
- Total RTO: 2-3 minutes

**Impact:**
- ❌ Complete service outage during restart
- ✅ All data preserved (volumes)
- ✅ Full automatic recovery

**Prerequisites:**
- Docker daemon enabled: `systemctl enable docker`
- All containers have `restart: always`

## Resource Limits

Prevent resource exhaustion:

```yaml
deploy:
  resources:
    limits:
      cpus: '1'
      memory: 512M
```

**Current Limits:**

| Service | CPU | Memory |
|---------|-----|--------|
| Service A (each) | 1 core | 512 MB |
| Service B (each) | 1 core | 512 MB |
| PostgreSQL (each) | 1 core | 512 MB |
| Redis | 0.5 core | 256 MB |
| Nginx | 0.5 core | 256 MB |

**Total Resources Required:**
- CPU: 7 cores
- Memory: 3.5 GB

## Data Persistence

### PostgreSQL Persistence

**Storage:** Docker volumes
```yaml
volumes:
  - postgres-a-data:/var/lib/postgresql/data
```

**Durability:**
- Write-Ahead Logging (WAL)
- Fsync on commit
- No data loss on crash
- Data survives container restart

### Redis Persistence

**Dual Persistence Strategy:**

1. **AOF (Append Only File):**
   - Every write operation logged
   - Fsync every second
   - Max 1 second data loss
   - File: `/data/appendonly.aof`

2. **RDB Snapshots:**
   - Periodic full snapshots
   - Save every 15 min if ≥1 key changed
   - Save every 5 min if ≥10 keys changed
   - Save every 60 sec if ≥10000 keys changed
   - File: `/data/dump.rdb`

**Recovery Priority:**
1. Load AOF (more recent)
2. If AOF corrupted, load RDB
3. If both corrupted, start fresh

### Volume Backup

**Manual Backup:**
```bash
# Backup PostgreSQL volumes
docker run --rm -v postgres-a-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/postgres-a-backup.tar.gz /data

# Backup Redis volume
docker run --rm -v redis-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/redis-backup.tar.gz /data
```

**Restore:**
```bash
# Restore PostgreSQL
docker run --rm -v postgres-a-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/postgres-a-backup.tar.gz -C /

# Restore Redis
docker run --rm -v redis-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/redis-backup.tar.gz -C /
```

## Monitoring Health Status

### Check All Container Health

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Check Specific Service Health

```bash
# Service A
docker inspect service-a-1 | jq '.[0].State.Health'

# Service B
docker inspect service-b-1 | jq '.[0].State.Health'
```

### Check Database Connections

```bash
# PostgreSQL
docker exec postgres-a psql -U auth_user -d auth_db -c "SELECT count(*) FROM pg_stat_activity;"

# Redis
docker exec redis redis-cli info clients
```

### Check Nginx Upstream Status

```bash
# View Nginx logs for upstream status
sudo tail -f /var/log/nginx/error.log | grep upstream

# Check which backends are active
sudo tail -f /var/log/nginx/payment-system-access.log | grep upstream_addr
```

## Performance During Degraded State

### Single Instance Operation

When running on 50% capacity (one instance down):

**Capacity:**
- Throughput: ~50% of normal
- Latency: May increase 10-20%
- Connection limit: Reduced by half

**Acceptable Duration:**
- Short term (<5 minutes): No issues
- Medium term (5-30 minutes): Monitor closely
- Long term (>30 minutes): Investigate and resolve

### Recovery After Restart

**Cold Start Times:**

| Service | Cold Start | Warm Start |
|---------|-----------|-----------|
| PostgreSQL | 5-8 seconds | 2-3 seconds |
| Redis | 2-5 seconds | 1-2 seconds |
| Service A | 15-30 seconds | 10-15 seconds |
| Service B | 15-30 seconds | 10-15 seconds |
| Nginx | 2-5 seconds | 1-2 seconds |

## Capacity Planning

### Current Capacity

**Per Instance Limits:**
- Service A: ~100 requests/sec
- Service B: ~80 requests/sec
- Database: ~500 connections
- Redis: ~10,000 ops/sec

**Total System Capacity:**
- With 2 instances: ~180 req/sec
- With rate limit: 100 req/min per IP
- Max concurrent users: ~1,000

### Scaling Considerations

**Horizontal Scaling:**
```bash
# Scale Service A to 3 instances
docker-compose -f docker-compose.prod.yml up -d --scale service-a=3

# Update Nginx upstream config to include new instances
```

**Vertical Scaling:**
- Increase container resource limits
- Upgrade server specifications

## SLA and RTO/RPO

### Service Level Objectives

| Metric | Target | Current |
|--------|--------|---------|
| Availability | 99.5% | ~99.8% |
| RTO (Recovery Time) | <5 minutes | 1-3 minutes |
| RPO (Data Loss) | <1 second | <1 second |
| Response Time (p95) | <200ms | ~150ms |
| Error Rate | <1% | <0.5% |

### Downtime Budget

**Monthly (99.5% availability):**
- Allowed downtime: 3.6 hours
- Current downtime: ~1 hour (typical)

## Testing HA Configuration

See [HA_TESTING.md](./HA_TESTING.md) for detailed testing procedures.

**Quick Tests:**
```bash
# Test instance failure
cd deployment/scripts
./test-ha-failover.sh

# Test database restart
./test-db-failover.sh

# Test load balancing
./test-load-distribution.sh
```

## Troubleshooting

### Container Won't Restart

```bash
# Check container status
docker ps -a | grep service-a-1

# Check logs
docker logs service-a-1 --tail 100

# Force restart
docker restart service-a-1

# If still failing, check resource limits
docker stats
```

### Health Check Failing

```bash
# Test health endpoint directly
docker exec service-a-1 curl http://localhost:3001/health

# Check application logs
docker logs service-a-1 | grep -i error

# Verify dependencies
docker exec service-a-1 ping postgres-a
```

### Nginx Not Detecting Recovery

```bash
# Check Nginx upstream status
docker exec nginx nginx -T | grep upstream

# Manually reload Nginx
docker exec nginx nginx -s reload

# Check fail_timeout expired
docker logs nginx | grep "upstream"
```

## Future Enhancements

1. **Database Replication:**
   - PostgreSQL streaming replication
   - Automatic failover with Patroni/Stolon
   - Read replicas for scaling

2. **Redis Cluster:**
   - Redis Sentinel for auto-failover
   - Or Redis Cluster for sharding
   - Multi-master replication

3. **Multi-Server Deployment:**
   - Docker Swarm or Kubernetes
   - Shared persistent storage
   - Cross-datacenter replication

4. **Advanced Load Balancing:**
   - HAProxy + Keepalived
   - VRRP for LB redundancy
   - Geographic load balancing

5. **Circuit Breakers:**
   - Implement in application layer
   - Automatic degradation
   - Faster failure detection