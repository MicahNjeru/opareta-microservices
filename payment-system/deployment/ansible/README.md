# Ansible Provisioning for Payment System

This directory contains Ansible playbooks and roles for automated server provisioning.

## Prerequisites

### On Your Local Machine (Control Node)

1. **Install Ansible**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ansible

# macOS
brew install ansible

# Verify installation
ansible --version
```

2. **Install required Python packages**
```bash
pip3 install docker docker-compose
```

3. **Generate SSH key (if not already present)**
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

4. **Copy SSH key to target server**
```bash
ssh-copy-id ubuntu@your_server_ip
# Or manually copy ~/.ssh/id_rsa.pub to server's ~/.ssh/authorized_keys
```

### On Target Server (Managed Node)

- Fresh Ubuntu 20.04 or 22.04 LTS installation
- Root or sudo access
- SSH access enabled
- Python 3 installed 

## Configuration

### 1. Update Inventory File

Edit `inventory/hosts.ini` and replace `your_server_ip_here` with your actual server IP:

```ini
[production]
prod-server-1 ansible_host=YOUR_ACTUAL_SERVER_IP ansible_user=ubuntu ansible_port=22
```

### 2. Review Group Variables

Check `group_vars/all.yml` and adjust variables as needed:

- `app_user`: Deployment user name (default: deployer)
- `app_dir`: Application directory (default: /opt/payment-system)
- `ssh_port`: SSH port (default: 22)
- `node_exporter_version`: Prometheus Node Exporter version
- `system_timezone`: Server timezone (default: UTC)

### 3. Test Connectivity

```bash
# Ping all hosts
ansible all -m ping

# Should return:
# prod-server-1 | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

## Running the Playbook

### Full Provisioning

```bash
# Run complete provisioning
ansible-playbook provision.yml

# Run with verbose output
ansible-playbook provision.yml -v
ansible-playbook provision.yml -vv   # More verbose
ansible-playbook provision.yml -vvv  # Very verbose (debug)

# Perform system upgrade during provisioning
ansible-playbook provision.yml --extra-vars "perform_system_upgrade=true"
```

### Run Specific Roles (Using Tags)

```bash
# Only setup users
ansible-playbook provision.yml --tags users

# Only configure firewall
ansible-playbook provision.yml --tags firewall

# Only install Docker
ansible-playbook provision.yml --tags docker

# Only setup monitoring
ansible-playbook provision.yml --tags monitoring

# Only apply security configurations
ansible-playbook provision.yml --tags security

# Multiple tags
ansible-playbook provision.yml --tags "users,docker"
```

### Dry Run (Check Mode)

```bash
# See what changes would be made without actually applying them
ansible-playbook provision.yml --check

# With diff to see actual changes
ansible-playbook provision.yml --check --diff
```

### Run on Specific Hosts

```bash
# Only run on specific host
ansible-playbook provision.yml --limit prod-server-1

# Run on staging environment
ansible-playbook provision.yml --limit staging
```

## What Gets Installed/Configured

### 1. System Users Role
- Creates deployment user (`deployer` by default)
- Sets up SSH keys for deployment user
- Configures passwordless sudo for specific commands
- Creates application directories
- Sets up user environment

### 2. Firewall Role
- Installs and configures UFW (Uncomplicated Firewall)
- Allows SSH (22), HTTP (80), HTTPS (443)
- Denies external access to PostgreSQL (5432, 5433)
- Denies external access to Redis (6379)
- Denies external access to monitoring ports (9090, 9100)
- Installs fail2ban for SSH brute force protection

### 3. SSH Hardening Role
- Disables root login
- Disables password authentication
- Enables public key authentication only
- Disables X11 forwarding
- Sets connection timeouts
- Creates SSH login banner
- Configures secure SSH settings

### 4. Docker Role
- Installs Docker CE
- Installs Docker Compose
- Adds deployment user to docker group
- Configures Docker daemon
- Sets up Docker logging
- Creates Docker network for application

### 5. Monitoring Role
- Installs Prometheus Node Exporter
- Configures Node Exporter as systemd service
- Sets up log rotation for application logs
- Exposes system metrics on port 9100

## Verification

After provisioning completes, verify the setup:

### 1. Check SSH Access

```bash
# Login as deployment user
ssh deployer@your_server_ip

# Should not be able to login as root with password
ssh root@your_server_ip  # Should fail
```

### 2. Check Firewall Status

```bash
ssh deployer@your_server_ip
sudo ufw status verbose
```

Expected output:
```
Status: active
To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
```

### 3. Check Docker Installation

```bash
ssh deployer@your_server_ip
docker --version
docker-compose --version
docker ps  # Should work without sudo
```

### 4. Check Node Exporter

```bash
# From local machine
curl http://your_server_ip:9100/metrics

# Should return Prometheus metrics
```

### 5. Check Fail2ban

```bash
ssh deployer@your_server_ip
sudo fail2ban-client status sshd
```

## Troubleshooting

### Issue: "Permission denied (publickey)"

**Solution:**
```bash
# Ensure SSH key is added to ssh-agent
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

# Or use password initially and copy key
ansible-playbook provision.yml --ask-pass
```

### Issue: "Unable to connect to Docker daemon"

**Solution:**
```bash
# Logout and login again to apply group changes
ssh deployer@your_server_ip

# Or manually add user to docker group
sudo usermod -aG docker deployer
```

### Issue: Playbook fails on certain tasks

**Solution:**
```bash
# Run with verbose output to see exact error
ansible-playbook provision.yml -vvv

# Skip specific roles
ansible-playbook provision.yml --skip-tags "role_name"
```

### Issue: UFW blocks SSH after enabling

**Prevention:** The playbook always allows SSH before enabling UFW. If you get locked out:

**Solution:**
```bash
# Access via cloud provider console or rescue mode
sudo ufw disable
sudo ufw allow 22/tcp
sudo ufw enable
```

## Re-running the Playbook

Ansible is idempotent so the playbook can be safely re-run multiple times and will only make changes if needed.

```bash
# Re-run to apply any configuration changes
ansible-playbook provision.yml

# Re-run specific role
ansible-playbook provision.yml --tags docker
```

## Updating Configurations

To update configurations after initial provisioning:

1. Edit the relevant files in `group_vars/all.yml`
2. Re-run the playbook or specific role:
   ```bash
   ansible-playbook provision.yml --tags firewall
   ```

## Security Considerations

- **SSH Keys**: Keep private keys secure, never commit to version control
- **Inventory File**: Don't commit with real IP addresses (use .gitignore)
- **Secrets**: Use Ansible Vault for sensitive data
- **Firewall**: Test thoroughly before blocking access
- **Backups**: Always backup before making system changes

## Next Steps

After successful provisioning:

1. Deploy application using docker-compose
2. Configure Nginx reverse proxy 
3. Set up SSL/TLS certificates 
4. Configure monitoring dashboards 
5. Set up database backups 

## Additional Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Docker Documentation](https://docs.docker.com/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW)
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)