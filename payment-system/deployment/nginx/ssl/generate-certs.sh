#!/bin/bash

# SSL Certificate Generation Script for Payment System
# Generates self-signed certificates for development/testing

set -e

# Configuration
DOMAIN="${1:-payment-system.local}"
COUNTRY="US"
STATE="State"
CITY="City"
ORGANIZATION="Payment System"
ORG_UNIT="IT"
EMAIL="admin@${DOMAIN}"
DAYS_VALID=365

# Output files
CERT_DIR="/etc/nginx/ssl"
KEY_FILE="${CERT_DIR}/${DOMAIN}.key"
CERT_FILE="${CERT_DIR}/${DOMAIN}.crt"
CSR_FILE="${CERT_DIR}/${DOMAIN}.csr"

echo "================================================"
echo "SSL Certificate Generation Script"
echo "================================================"
echo "Domain: ${DOMAIN}"
echo "Output Directory: ${CERT_DIR}"
echo "================================================"

# Create SSL directory if it doesn't exist
sudo mkdir -p ${CERT_DIR}

# Generate private key
echo "Generating private key..."
sudo openssl genrsa -out ${KEY_FILE} 4096

# Generate CSR (Certificate Signing Request)
echo "Generating Certificate Signing Request..."
sudo openssl req -new -key ${KEY_FILE} -out ${CSR_FILE} \
  -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORGANIZATION}/OU=${ORG_UNIT}/CN=${DOMAIN}/emailAddress=${EMAIL}"

# Generate self-signed certificate
echo "Generating self-signed certificate (valid for ${DAYS_VALID} days)..."
sudo openssl x509 -req -days ${DAYS_VALID} -in ${CSR_FILE} \
  -signkey ${KEY_FILE} -out ${CERT_FILE} \
  -extfile <(printf "subjectAltName=DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost,IP:127.0.0.1")

# Set proper permissions
echo "Setting file permissions..."
sudo chmod 600 ${KEY_FILE}
sudo chmod 644 ${CERT_FILE}
sudo chmod 644 ${CSR_FILE}

# Display certificate info
echo ""
echo "================================================"
echo "Certificate generated successfully!"
echo "================================================"
echo "Private Key: ${KEY_FILE}"
echo "Certificate: ${CERT_FILE}"
echo "CSR: ${CSR_FILE}"
echo ""
echo "Certificate Details:"
sudo openssl x509 -in ${CERT_FILE} -text -noout | grep -A 2 "Subject:"
echo ""
echo "Valid until:"
sudo openssl x509 -in ${CERT_FILE} -noout -enddate
echo ""
echo "================================================"
echo "IMPORTANT NOTES:"
echo "================================================"
echo "1. This is a SELF-SIGNED certificate for testing"
echo "2. Browsers will show a security warning"
echo "3. For production, use Let's Encrypt or commercial CA"
echo "4. To trust certificate locally:"
echo "   - Linux: sudo cp ${CERT_FILE} /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
echo "   - macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${CERT_FILE}"
echo "   - Windows: Import certificate to Trusted Root Certification Authorities"
echo "================================================"

# Optional: Generate DH parameters for enhanced security - takes time
DH_FILE="${CERT_DIR}/dhparam.pem"
if [ ! -f ${DH_FILE} ]; then
  echo ""
  read -p "Generate Diffie-Hellman parameters? (Recommended but takes 5-10 minutes) [y/N]: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Generating DH parameters (this will take several minutes)..."
    sudo openssl dhparam -out ${DH_FILE} 2048
    sudo chmod 644 ${DH_FILE}
    echo "DH parameters generated: ${DH_FILE}"
  fi
fi

echo ""
echo "Certificate generation complete!"
echo "You can now configure Nginx to use these certificates."