# Nginx Reverse Proxy & Load Balancing Configuration

This directory contains Nginx configuration for the Payment System with reverse proxy and load balancing capabilities.

## Overview

The Nginx setup provides:
- **Reverse Proxy**: Routes requests to backend services
- **Load Balancing**: Distributes traffic across 2 instances of each service
- **SSL/TLS**: HTTPS encryption (self-signed certificates for development)
- **Rate Limiting**: 100 requests/minute per IP with burst allowance
- **Health Checks**: Monitors backend service availability
- **Security Headers**: HSTS, X-Frame-Options, etc.
- **Custom Error Pages**: User-friendly error messages

## Architecture

```
Client (HTTPS) → Nginx (443) → Load Balancer → Service Instances
                               ├─→ Service A Instance 1 (3001)
                               ├─→ Service A Instance 2 (3003)
                               ├─→ Service B Instance 1 (3002)
                               └─→ Service B Instance 2 (3004)
```

## Quick Start

### 1. Generate SSL Certificates

```bash
cd deployment/nginx/ssl
chmod +x generate-certs.sh
./generate-certs.sh payment-system.local
```

### 2. Setup Nginx (on server)

```bash
cd deployment/scripts
chmod +x setup-nginx.sh
sudo ./setup-nginx.sh
```

### 3. Start All Services

```bash
cd deployment
docker-compose -f docker-compose.prod.yml up -d --build
```

### 4. Verify Setup

```bash
cd deployment/scripts
chmod +x test-nginx.sh
./test-nginx.sh
```

## Configuration Files

### Main Configuration (`nginx.conf`)

Global Nginx settings:
- Worker processes and connections
- Logging format
- Gzip compression
- SSL/TLS protocols
- Rate limiting zones
- Proxy settings

### Site Configuration (`sites-available/payment-system.conf`)

Application-specific settings:
- Upstream definitions (load balancer pools)
- HTTP to HTTPS redirect
- HTTPS server configuration
- Location blocks for services
- Health check endpoints
- Error page configuration

## Load Balancing

### Strategy

Using **least_conn** algorithm:
- Routes requests to server with fewest active connections
- Better than round-robin for long-lived connections
- Handles varying request processing times

### Upstream Configuration

```nginx
upstream service_a_backend {
    least_conn;
    server service-a-1:3001 max_fails=3 fail_timeout=30s;
    server service-a-2:3003 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
```

### Health Checks

Nginx monitors backend health:
- **max_fails**: 3 failed attempts before marking as down
- **fail_timeout**: 30 seconds before retry
- Automatic removal of unhealthy instances
- Automatic recovery when instance becomes healthy

## Rate Limiting

### Configuration

- **Limit**: 100 requests per minute per IP
- **Burst**: 20 additional requests allowed
- **Status Code**: 429 (Too Many Requests)
- **Scope**: Applied to `/auth` and `/payments` endpoints

### Testing Rate Limits

```bash
# Send 150 rapid requests
for i in {1..150}; do
  curl -sk https://localhost/health
  sleep 0.1
done

# Should see some 429 responses
```

## SSL/TLS Configuration

### Current Setup (Development)

- **Type**: Self-signed certificates
- **Protocols**: TLSv1.2, TLSv1.3
- **Ciphers**: Strong ciphers only
- **HSTS**: Enabled (1 year)
- **Key Size**: 4096-bit RSA

### Production Setup

For production, replace with Let's Encrypt:

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d yourdomain.com

# Auto-renewal is configured by certbot
```

Update `payment-system.conf`:
```nginx
ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
```

## Endpoints

### Public Endpoints

- `GET /` - API information
- `GET /health` - Overall system health
- `POST /auth/register` - User registration
- `POST /auth/login` - User login
- `POST /auth/validate` - Token validation
- `POST /payments/initiate` - Create payment
- `GET /payments/:reference` - Get payment
- `PATCH /payments/:reference/status` - Update payment
- `POST /payments/webhook` - Process webhook

### Health Check Endpoints

- `GET /health` - Nginx health
- `GET /auth/health` - Service A health
- `GET /payments/health` - Service B health

### Monitoring Endpoints (localhost only)

- `GET /nginx_status` - Nginx statistics

### Documentation

- `/api/docs/auth` - Service A Swagger docs
- `/api/docs/payments` - Service B Swagger docs

## Logging

### Log Files

```bash
# Access logs (all requests)
/var/log/nginx/access.log

# Error logs (errors only)
/var/log/nginx/error.log

# Application-specific logs (detailed)
/var/log/nginx/payment-system-access.log
/var/log/nginx/payment-system-error.log
```

### Log Format

Detailed format includes:
- Request details
- Response status
- Bytes sent/received
- Request time
- Upstream response time
- User agent

### View Logs

```bash
# Tail all requests
sudo tail -f /var/log/nginx/payment-system-access.log

# Tail errors only
sudo tail -f /var/log/nginx/payment-system-error.log

# View last 100 lines
sudo tail -100 /var/log/nginx/access.log

# Search for specific IP
sudo grep "192.168.1.100" /var/log/nginx/access.log

# View 429 (rate limit) responses
sudo grep " 429 " /var/log/nginx/access.log
```

## Testing

### Manual Testing

```bash
# Test HTTPS
curl -k https://localhost/health

# Test HTTP redirect
curl -I http://localhost/health

# Test Service A
curl -k https://localhost/auth/health

# Test Service B
curl -k https://localhost/payments/health/check

# Test rate limiting (rapid requests)
for i in {1..150}; do curl -sk https://localhost/health; done
```

### Automated Testing

```bash
cd deployment/scripts
chmod +x test-nginx.sh
./test-nginx.sh localhost
```

## Troubleshooting

### Issue: Configuration Test Fails

```bash
# Test configuration
sudo nginx -t

# View specific error
sudo nginx -t 2>&1 | grep error

# Common issues:
# - Missing SSL certificates
# - Syntax errors in config
# - Conflicting server blocks
```

### Issue: Services Not Responding

```bash
# Check if containers are running
docker ps

# Check container logs
docker logs service-a-1
docker logs service-b-1

# Check Nginx error log
sudo tail -f /var/log/nginx/error.log

# Test upstream directly
curl http://localhost:3001/health
```

### Issue: SSL Certificate Errors

```bash
# Regenerate certificates
cd deployment/nginx/ssl
./generate-certs.sh payment-system.local

# Verify certificate
sudo openssl x509 -in /etc/nginx/ssl/payment-system.local.crt -text -noout

# Check certificate permissions
ls -l /etc/nginx/ssl/
```

### Issue: Rate Limiting Too Strict

Edit `nginx.conf`:
```nginx
# Increase rate limit to 200 requests/minute
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=200r/m;
```

Then reload:
```bash
sudo nginx -s reload
```

### Issue: 502 Bad Gateway

Causes:
1. Backend services not running
2. Backend not healthy
3. Port mismatch

Debug:
```bash
# Check backend health
curl http://localhost:3001/health
curl http://localhost:3002/health

# Check Docker network
docker network inspect deployment_frontend

# View Nginx upstream status
sudo tail -f /var/log/nginx/error.log | grep upstream
```

## Maintenance

### Reload Configuration

```bash
# Test first
sudo nginx -t

# Reload without downtime
sudo nginx -s reload

# Or using systemctl
sudo systemctl reload nginx
```

### Restart Nginx

```bash
sudo systemctl restart nginx
```

### Update SSL Certificates

```bash
# Regenerate
cd deployment/nginx/ssl
./generate-certs.sh yourdomain.com

# Reload Nginx
sudo nginx -s reload
```

### Log Rotation

Nginx logs are automatically rotated by logrotate:
```bash
# View logrotate config
cat /etc/logrotate.d/nginx

# Manual rotation
sudo logrotate -f /etc/logrotate.d/nginx
```

## Security Considerations

### Current Security Features

**SSL/TLS encryption**
**Strong cipher suites**
**HSTS enabled**
**Security headers**
**Rate limiting**
**Hiding server version**
**Restricted monitoring endpoints**

### Additional Recommendations

1. **Use real SSL certificates** in production (Let's Encrypt)
2. **Enable ModSecurity** WAF for additional protection
3. **Implement fail2ban** for brute force protection
4. **Set up log monitoring** and alerts
5. **Regular security updates** for Nginx
6. **IP whitelisting** for admin endpoints

## Performance Tuning

### Current Settings

- Worker processes: auto
- Worker connections: 2048
- Keepalive timeout: 65s
- Client max body size: 10MB
- Gzip compression: enabled

### For High Traffic

Edit `nginx.conf`:
```nginx
worker_processes 4;  # Match CPU cores
worker_connections 4096;
keepalive_requests 1000;
```

## Next Steps

After Nginx is configured:

1. Nginx configured and running
2. Configure monitoring (Prometheus/Grafana)
3. Set up automated backups
4. Implement zero-downtime deployment
5. Configure alerts and notifications

## Resources

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Load Balancing Guide](https://nginx.org/en/docs/http/load_balancing.html)
- [SSL Configuration](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [Rate Limiting](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html)