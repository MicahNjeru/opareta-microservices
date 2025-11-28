#!/bin/bash

# Nginx Setup Script for Payment System
# This script installs and configures Nginx on the server

set -e

echo "================================================"
echo "Nginx Setup for Payment System"
echo "================================================"

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Update package list
echo "Updating package list..."
apt-get update

# Install Nginx
echo "Installing Nginx..."
apt-get install -y nginx

# Stop Nginx for configuration
systemctl stop nginx

# Backup default configuration
echo "Backing up default Nginx configuration..."
if [ -f /etc/nginx/nginx.conf ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
fi

# Create necessary directories
echo "Creating directories..."
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/ssl
mkdir -p /etc/nginx/conf.d
mkdir -p /usr/share/nginx/html

# Copy configuration files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Copying Nginx configuration files..."

# Copy main nginx.conf
if [ -f "$DEPLOYMENT_DIR/nginx/nginx.conf" ]; then
    cp "$DEPLOYMENT_DIR/nginx/nginx.conf" /etc/nginx/nginx.conf
    echo "✓ Copied nginx.conf"
else
    echo "✗ nginx.conf not found at $DEPLOYMENT_DIR/nginx/nginx.conf"
    exit 1
fi

# Copy site configuration
if [ -f "$DEPLOYMENT_DIR/nginx/sites-available/payment-system.conf" ]; then
    cp "$DEPLOYMENT_DIR/nginx/sites-available/payment-system.conf" /etc/nginx/sites-available/
    echo "✓ Copied payment-system.conf"
else
    echo "✗ payment-system.conf not found"
    exit 1
fi

# Create symbolic link to enable site
ln -sf /etc/nginx/sites-available/payment-system.conf /etc/nginx/sites-enabled/payment-system.conf
echo "✓ Enabled payment-system site"

# Remove default site if exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
    echo "✓ Removed default site"
fi

# Copy error pages
if [ -d "$DEPLOYMENT_DIR/nginx/html" ]; then
    cp -r "$DEPLOYMENT_DIR/nginx/html/"* /usr/share/nginx/html/
    echo "✓ Copied error pages"
fi

# Generate SSL certificates
echo ""
echo "Generating SSL certificates..."
if [ -f "$DEPLOYMENT_DIR/nginx/ssl/generate-certs.sh" ]; then
    bash "$DEPLOYMENT_DIR/nginx/ssl/generate-certs.sh" payment-system.local
else
    echo "Warning: SSL certificate generation script not found"
    echo "You'll need to manually generate certificates"
fi

# Test Nginx configuration
echo ""
echo "Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "✓ Nginx configuration is valid"
    
    # Enable and start Nginx
    echo "Starting Nginx..."
    systemctl enable nginx
    systemctl start nginx
    
    echo ""
    echo "================================================"
    echo "Nginx Setup Complete!"
    echo "================================================"
    echo "Status: $(systemctl is-active nginx)"
    echo ""
    echo "Access your application:"
    echo "  HTTP:  http://$(hostname -I | awk '{print $1}')"
    echo "  HTTPS: https://$(hostname -I | awk '{print $1}')"
    echo ""
    echo "Note: HTTPS will show a security warning (self-signed certificate)"
    echo ""
    echo "To check status: sudo systemctl status nginx"
    echo "To view logs:    sudo tail -f /var/log/nginx/error.log"
    echo "================================================"
else
    echo "✗ Nginx configuration test failed"
    echo "Please check the configuration and try again"
    exit 1
fi