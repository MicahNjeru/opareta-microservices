# Quick Start Guide - Server Provisioning

## Prerequisites Checklist

- [ ] Fresh Ubuntu 20.04/22.04 server
- [ ] Server root or sudo access
- [ ] Ansible installed on local machine
- [ ] SSH key generated (`~/.ssh/id_rsa`)
- [ ] SSH access to server configured

## Step-by-Step Provisioning

### Step 1: Install Ansible (if not installed)

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y ansible

# macOS
brew install ansible

# Verify
ansible --version
```

### Step 2: Configure Server Access

```bash
# Generate SSH key if needed
ssh-keygen -t rsa -b 4096

# Copy SSH key to server (replace with your server IP)
ssh-copy-id ubuntu@YOUR_SERVER_IP

# Test SSH connection
ssh ubuntu@YOUR_SERVER_IP
```

### Step 3: Update Inventory

Edit `inventory/hosts.ini`:

```ini
[production]
prod-server-1 ansible_host=YOUR_SERVER_IP ansible_user=ubuntu ansible_port=22
```

### Step 4: Test Connectivity

```bash
cd deployment/ansible

# Test connection
ansible all -m ping
```

Expected output:
```
prod-server-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### Step 5: Review Configuration 

Check `group_vars/all.yml` to customize:
- Application directory
- User names
- Firewall ports
- Other settings

### Step 6: Run Provisioning

```bash
# Full provisioning for first run
ansible-playbook provision.yml

# With system upgrade
ansible-playbook provision.yml --extra-vars "perform_system_upgrade=true"

# Dry run - to see what would change
ansible-playbook provision.yml --check
```

### Step 7: Verify Installation

```bash
# SSH as deployment user
ssh deployer@YOUR_SERVER_IP

# Check Docker
docker --version
docker ps

# Check firewall
sudo ufw status

# Check Node Exporter
curl http://localhost:9100/metrics
```

## What Was Installed

**System User**: `deployer` with sudo access
**Docker**: Latest Docker CE and Docker Compose
**Firewall**: UFW configured (22, 80, 443 open)
**SSH**: Hardened (no root, no password auth)
**Monitoring**: Node Exporter on port 9100
**Security**: fail2ban for SSH protection

## Common Commands

```bash
# Re-run provisioning
ansible-playbook provision.yml

# Update only firewall
ansible-playbook provision.yml --tags firewall

# Update only Docker
ansible-playbook provision.yml --tags docker

# Verbose output
ansible-playbook provision.yml -vv
```

## Next Steps

1. Server provisioned - DONE
2. Deploy application with Docker Compose
3. Configure Nginx reverse proxy
4. Set up SSL certificates
5. Configure Prometheus & Grafana monitoring

## Troubleshooting

**Can't connect?**
```bash
# Use password authentication initially
ansible-playbook provision.yml --ask-pass
```

**Docker permission denied?**
```bash
# Logout and login again
ssh deployer@YOUR_SERVER_IP
```

**Locked out after firewall setup?**
- Access via cloud provider console
- Run: `sudo ufw allow 22/tcp && sudo ufw enable`

## Getting Help

- Check `README.md` for detailed documentation
- View logs: `ansible-playbook provision.yml -vvv`
- Test specific role: `ansible-playbook provision.yml --tags role_name --check`