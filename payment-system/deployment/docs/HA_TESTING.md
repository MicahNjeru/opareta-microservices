# High Availability Testing Guide

## Overview

This guide provides procedures for testing failover scenarios and validating high availability configuration.

## Prerequisites

- All services running via docker-compose
- Access to server terminal
- `curl`, `jq`, and `docker` commands available

## Test 1: Single Service Instance Failover

### Objective
Verify that when one service instance fails, traffic continues via the healthy instance.

### Procedure

1. **Start continuous requests:**
```bash
# Terminal 1 - Run continuous requests
while true; do
  curl -sk https://localhost/auth/health | jq -r '.status'
  sleep 1
done
```

2. **Stop one instance:**
```bash
# Terminal 2
docker stop service-a-1
echo "Stopped service-a-1 at $(date)"
```

3. **Observe behavior:**
- ✅ Requests should continue succeeding
- ⚠️ May see brief errors during detection period (30-90s)
- ✅ All traffic routes to service-a-2

4. **Monitor Nginx logs:**
```bash
# Terminal 3
sudo tail -f /var/log/nginx/error.log | grep upstream
```

5. **Wait for auto-restart:**
```bash
# Check if instance restarted
watch docker ps | grep service-a
```

6. **Verify recovery:**
```bash
# Check instance is healthy
docker ps | grep service-a-1
docker inspect service-a-1 | jq '.[0].State.Health.Status'
```

### Expected Results

- **Detection time:** 30-90 seconds
- **Service interruption:** None or minimal (<5 seconds)
- **Auto-restart time:** 20-40 seconds
- **Full recovery time:** 1-2 minutes

### Success Criteria

- [ ] Less than 5% request failures
- [ ] Instance auto-restarts
- [ ] Instance becomes healthy
- [ ] Traffic distributes to both instances after recovery

---

## Test 2: Complete Service Pool Failure

### Objective
Verify system behavior when all instances of a service fail.

### Procedure

1. **Start continuous requests:**
```bash
while true; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost/auth/health)
  echo "$(date +%T) - Status: $STATUS"
  sleep 1
done
```

2. **Stop all instances:**
```bash
docker stop service-a-1 service-a-2
echo "Stopped all Service A instances at $(date)"
```

3. **Observe errors:**
- Should see 502 Bad Gateway responses
- Nginx error log shows "no live upstreams"

4. **Wait for auto-restart:**
```bash
watch "docker ps | grep service-a"
```

5. **Verify recovery:**
```bash
# Both instances should be running and healthy
docker ps | grep service-a
```

### Expected Results

- **Immediate:** 502 Bad Gateway errors
- **Recovery time:** 1-2 minutes
- **No data loss**

### Success Criteria

- [ ] 502 errors during outage
- [ ] Both instances auto-restart
- [ ] Service fully recovers
- [ ] No data corruption

---

## Test 3: Database Restart Failover

### Objective
Verify that services handle database restarts gracefully.

### Procedure

1. **Check current connections:**
```bash
docker exec postgres-a psql -U auth_user -d auth_db \
  -c "SELECT count(*) FROM pg_stat_activity WHERE usename='auth_user';"
```

2. **Start continuous requests:**
```bash
while true; do
  curl -sk https://localhost/auth/health | jq -r '.database'
  sleep 1
done
```

3. **Restart database:**
```bash
docker restart postgres-a
echo "Restarted postgres-a at $(date)"
```

4. **Observe behavior:**
- Services health checks fail
- Nginx stops routing to unhealthy instances
- Services show "database: disconnected"

5. **Wait for recovery:**
```bash
# Wait for database to be ready
docker exec postgres-a pg_isready -U auth_user -d auth_db

# Check service health
curl -sk https://localhost/auth/health | jq
```

### Expected Results

- **Database restart:** 5-10 seconds
- **Service detection:** 10-30 seconds
- **Full recovery:** 30-60 seconds
- **No data loss**

### Success Criteria

- [ ] Database restarts successfully
- [ ] Services reconnect automatically
- [ ] All data intact
- [ ] Services become healthy

---

## Test 4: Redis Cache Failure

### Objective
Verify that payment service continues operating when Redis fails.

### Procedure

1. **Set test data in Redis:**
```bash
docker exec redis redis-cli SET test-key "test-value"
docker exec redis redis-cli GET test-key
```

2. **Stop Redis:**
```bash
docker stop redis
echo "Stopped Redis at $(date)"
```

3. **Test service operations:**
```bash
# Should still work (slower, no cache)
curl -sk https://localhost/payments/health/check | jq

# Try webhook (idempotency check may fail)
curl -sk -X POST https://localhost/payments/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "payment_reference": "test-ref",
    "status": "SUCCESS",
    "provider_transaction_id": "TXN123",
    "timestamp": "2024-01-01T12:00:00Z"
  }'
```

4. **Wait for Redis restart:**
```bash
watch docker ps | grep redis
```

5. **Verify data persistence:**
```bash
# Check if AOF restored data
docker exec redis redis-cli GET test-key
```

### Expected Results

- **Service continues:** ✅ (with degraded performance)
- **Redis restarts:** 5-10 seconds
- **Data persisted:** ✅ (max 1 second loss)

### Success Criteria

- [ ] Service B remains functional
- [ ] Redis auto-restarts
- [ ] AOF data recovered
- [ ] Cache rebuilds on access

---

## Test 5: Nginx Load Balancer Failure

### Objective
Verify Nginx auto-restart behavior.

### Procedure

1. **Start continuous requests:**
```bash
while true; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost/health 2>&1)
  echo "$(date +%T) - Status: $STATUS"
  sleep 1
done
```

2. **Stop Nginx:**
```bash
docker stop nginx
echo "Stopped Nginx at $(date)"
```

3. **Observe outage:**
- All requests fail with "Connection refused"

4. **Wait for auto-restart:**
```bash
watch docker ps | grep nginx
```

5. **Verify recovery:**
```bash
curl -k https://localhost/health
```

### Expected Results

- **Complete outage:** During restart
- **Recovery time:** 10-20 seconds
- **Backend services:** Continue running

### Success Criteria

- [ ] Nginx auto-restarts
- [ ] All routes functional after restart
- [ ] No backend service disruption

---

## Test 6: Load Distribution

### Objective
Verify requests are distributed across multiple instances.

### Procedure

1. **Send multiple requests:**
```bash
#!/bin/bash
# Save as test-load-distribution.sh

COUNT=50
OUTPUT_FILE="load-test-$(date +%s).txt"

echo "Sending $COUNT requests..."

for i in $(seq 1 $COUNT); do
  RESPONSE=$(curl -sk https://localhost/auth/health)
  echo "$RESPONSE" >> $OUTPUT_FILE
  sleep 0.2
done

echo "Analyzing distribution..."
echo "Unique responses: $(sort $OUTPUT_FILE | uniq | wc -l)"
```

2. **Check Nginx logs:**
```bash
# See which upstream handled requests
sudo tail -50 /var/log/nginx/payment-system-access.log | \
  grep -oP 'upstream: "\K[^"]+' | sort | uniq -c
```

### Expected Results

- Requests distributed between both instances
- Roughly 50/50 distribution (with least_conn algorithm)

### Success Criteria

- [ ] Both instances receive requests
- [ ] Distribution is balanced (40/60 to 60/40 range)
- [ ] No single instance overwhelmed

---

## Test 7: Concurrent Load with Instance Failure

### Objective
Verify system handles load during failover.

### Procedure

1. **Generate load:**
```bash
#!/bin/bash
# Save as load-test.sh

# Run 5 concurrent request streams
for i in {1..5}; do
  {
    while true; do
      curl -sk https://localhost/auth/health > /dev/null
      sleep 0.5
    done
  } &
done

echo "Load test started with PIDs: $(jobs -p)"
```

2. **Stop instance during load:**
```bash
sleep 10
docker stop service-a-1
echo "Stopped instance during load at $(date)"
```

3. **Monitor error rate:**
```bash
# Count successes vs failures
sudo tail -f /var/log/nginx/payment-system-access.log | \
  awk '{print $9}' | sort | uniq -c
```

4. **Stop load test:**
```bash
# Kill background jobs
jobs -p | xargs kill
```

### Expected Results

- Minimal errors during failover
- Recovery within 1-2 minutes
- No complete service outage

### Success Criteria

- [ ] Error rate <5% during failover
- [ ] Service continues operating
- [ ] Load distributes to healthy instance

---

## Test 8: Data Persistence After Crash

### Objective
Verify no data loss after unclean shutdown.

### Procedure

1. **Create test data:**
```bash
# Register a user
curl -sk -X POST https://localhost/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+256700999999",
    "email": "test-persistence@example.com",
    "password": "Test@1234"
  }'

# Create a payment (need token first)
TOKEN=$(curl -sk -X POST https://localhost/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+256700999999",
    "password": "Test@1234"
  }' | jq -r '.access_token')

curl -sk -X POST https://localhost/payments/initiate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 5000,
    "currency": "UGX",
    "payment_method": "MOBILE_MONEY",
    "customer_phone": "+256700999999",
    "customer_email": "test@example.com"
  }'
```

2. **Force stop containers (simulating crash):**
```bash
docker kill postgres-a postgres-b redis
```

3. **Wait for auto-restart:**
```bash
watch docker ps
```

4. **Verify data still exists:**
```bash
# Try to login (should work if data persisted)
curl -sk -X POST https://localhost/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+256700999999",
    "password": "Test@1234"
  }'

# Check database directly
docker exec postgres-a psql -U auth_user -d auth_db \
  -c "SELECT email FROM users WHERE phone_number='+256700999999';"
```

### Expected Results

- All data persisted
- Services recover automatically
- No data corruption

### Success Criteria

- [ ] User data intact
- [ ] Payment data intact
- [ ] Redis cache rebuilt
- [ ] No database corruption

---

## Test 9: System Resource Exhaustion

### Objective
Verify resource limits prevent system-wide failure.

### Procedure

1. **Monitor resources:**
```bash
watch "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"
```

2. **Generate high load:**
```bash
# Install Apache Bench
sudo apt install apache2-utils

# Generate load
ab -n 10000 -c 100 https://localhost/auth/health
```

3. **Observe behavior:**
- Containers stay within resource limits
- Rate limiting kicks in (429 responses)
- No container crashes

### Expected Results

- Containers respect CPU/memory limits
- System remains stable
- Rate limiting protects backend

### Success Criteria

- [ ] No container exceeds resource limits
- [ ] No out-of-memory kills
- [ ] Rate limiting active
- [ ] System responsive

---

## Test 10: Full System Restart

### Objective
Verify complete system recovery after host reboot.

### Procedure

1. **Record system state:**
```bash
docker ps > /tmp/pre-reboot-state.txt
```

2. **Reboot server:**
```bash
sudo reboot
```

3. **After reboot, check Docker status:**
```bash
# Wait for system to boot
ssh deployer@YOUR_SERVER_IP

# Check Docker daemon
systemctl status docker

# Check containers
docker ps
```

4. **Verify all services:**
```bash
# Check all containers running
docker ps | wc -l  # Should be 8

# Check health
curl -k https://localhost/health
curl -k https://localhost/auth/health
curl -k https://localhost/payments/health/check
```

### Expected Results

- All containers auto-start
- All services healthy
- Complete recovery in 2-3 minutes

### Success Criteria

- [ ] Docker daemon starts on boot
- [ ] All 8 containers running
- [ ] All health checks pass
- [ ] API endpoints accessible

---

## Automated Test Script

Create comprehensive automated test:

```bash
#!/bin/bash
# save as deployment/scripts/test-ha-complete.sh

echo "=== High Availability Test Suite ==="
echo "Starting comprehensive HA tests..."

# Test 1: Instance Failover
echo "Test 1: Instance Failover"
docker stop service-a-1
sleep 60
if docker ps | grep -q service-a-1; then
  echo "✓ Instance auto-restarted"
else
  echo "✗ Instance did not restart"
fi

# Test 2: Load Distribution
echo "Test 2: Load Distribution"
for i in {1..20}; do
  curl -sk https://localhost/auth/health > /dev/null
done
echo "✓ Load distributed across instances"

# Test 3: Redis Failover
echo "Test 3: Redis Failover"
docker restart redis
sleep 20
if curl -sk https://localhost/payments/health/check | grep -q "ok"; then
  echo "✓ Service operational after Redis restart"
else
  echo "✗ Service not operational"
fi

# Test 4: Database Failover
echo "Test 4: Database Failover"
docker restart postgres-a
sleep 30
if curl -sk https://localhost/auth/health | grep -q "connected"; then
  echo "✓ Database reconnected"
else
  echo "✗ Database not reconnected"
fi

echo "=== Test Suite Complete ==="
```

---

## Monitoring During Tests

### Key Metrics to Watch

1. **Response Times:**
```bash
while true; do
  curl -sk -w "\nTime: %{time_total}s\n" https://localhost/health | jq
  sleep 2
done
```

2. **Error Rates:**
```bash
sudo tail -f /var/log/nginx/access.log | \
  awk '{print $9}' | \
  awk '{total++; if($1>=500) errors++} 
       END {printf "Error Rate: %.2f%%\n", (errors/total)*100}'
```

3. **Container Health:**
```bash
watch "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(health|service)'"
```

## Troubleshooting Test Failures

### Instance Won't Restart

**Check logs:**
```bash
docker logs service-a-1 --tail 100
```

**Check resource limits:**
```bash
docker stats --no-stream
```

**Manual restart:**
```bash
docker restart service-a-1
```

### Services Don't Reconnect to Database

**Check database is ready:**
```bash
docker exec postgres-a pg_isready -U auth_user
```

**Check network connectivity:**
```bash
docker exec service-a-1 ping postgres-a
```

**Restart application:**
```bash
docker restart service-a-1 service-a-2
```

### Nginx Not Detecting Recovery

**Reload Nginx:**
```bash
docker exec nginx nginx -s reload
```

**Check fail_timeout:**
```bash
# Wait 30 seconds for fail_timeout to expire
sleep 30
```

## Reporting Test Results

Document test results in this format:

```
Test: [Test Name]
Date: [Date/Time]
Duration: [Duration]
Result: [PASS/FAIL]

Metrics:
- Detection Time: [seconds]
- Recovery Time: [seconds]
- Error Rate: [percentage]
- Data Loss: [yes/no]

Observations:
[Any notable behavior]

Issues Found:
[Any problems discovered]
```