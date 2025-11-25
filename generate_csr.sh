#!/bin/bash

#==============================================================================
# Generate Private Key and CSR for Certificate Request
#==============================================================================
# This script generates:
# 1. Private Key (KEEP THIS SAFE!)
# 2. Certificate Signing Request (CSR) - submit this to your CA
#==============================================================================

echo "=========================================="
echo "Generate Private Key and CSR"
echo "=========================================="
echo ""

# Get technical user name
read -p "Enter Technical User Name (e.g., test): " TECHNICAL_USER

if [ -z "$TECHNICAL_USER" ]; then
    echo "ERROR: Technical user name cannot be empty"
    exit 1
fi

PRIVATE_KEY="${TECHNICAL_USER}_private.key"
CSR_FILE="${TECHNICAL_USER}.csr"

echo ""
echo "Technical User: ${TECHNICAL_USER}"
echo ""

# Step 1: Generate Private Key
echo "Step 1: Generating private key..."
openssl genrsa -out "$PRIVATE_KEY" 2048

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate private key"
    exit 1
fi

echo "✓ Private key generated: $PRIVATE_KEY"
echo ""
echo "⚠️  IMPORTANT: SAVE THIS FILE SECURELY!"
echo "⚠️  You will need this file later to create the JKS!"
echo ""

# Step 2: Get user input for CSR details
echo "Step 2: Enter details for Certificate Signing Request"
echo "------------------------------------------------------"
echo ""

read -p "Country Code (e.g., SG, US, UK): " COUNTRY
read -p "State/Province: " STATE
read -p "City: " CITY
read -p "Organization/Company Name: " ORG
read -p "Department/Unit: " DEPT
read -p "Email Address: " EMAIL

# Use technical user as Common Name
COMMON_NAME="$TECHNICAL_USER"

echo ""
echo "Review your details:"
echo "  Country: $COUNTRY"
echo "  State: $STATE"
echo "  City: $CITY"
echo "  Organization: $ORG"
echo "  Department: $DEPT"
echo "  Common Name: $COMMON_NAME"
echo "  Email: $EMAIL"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Step 3: Create CSR config
CSR_CONFIG="csr_config_${TECHNICAL_USER}.txt"
cat > "$CSR_CONFIG" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=${COUNTRY}
ST=${STATE}
L=${CITY}
O=${ORG}
OU=${DEPT}
CN=${COMMON_NAME}
emailAddress=${EMAIL}

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

echo "✓ CSR configuration created: $CSR_CONFIG"

# Step 4: Generate CSR
echo ""
echo "Step 3: Generating Certificate Signing Request (CSR)..."
openssl req -new \
    -key "$PRIVATE_KEY" \
    -out "$CSR_FILE" \
    -config "$CSR_CONFIG"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate CSR"
    exit 1
fi

echo "✓ CSR generated: $CSR_FILE"
echo ""

# Step 5: Display CSR
echo "=========================================="
echo "Your Certificate Signing Request (CSR):"
echo "=========================================="
echo ""
cat "$CSR_FILE"
echo ""
echo "=========================================="
echo ""

echo "✓ SUCCESS!"
echo ""
echo "Files created:"
echo "  1. $PRIVATE_KEY  ← KEEP THIS SAFE!"
echo "  2. $CSR_FILE     ← Submit this to your CA"
echo "  3. $CSR_CONFIG   ← Configuration file (can delete later)"
echo ""
echo "=========================================="
echo "NEXT STEPS:"
echo "=========================================="
echo "1. Copy the CSR content above"
echo "2. Submit it to your Certificate Authority (CA)"
echo "3. Wait for CA to send you certificates via email"
echo "4. Save certificates from email as:"
echo "   - user_certificate.crt"
echo "   - issuing_ca.crt"
echo "5. Run the JKS creation script with these files"
echo ""
echo "⚠️  DO NOT LOSE: $PRIVATE_KEY"
echo "   You MUST use this same file when creating JKS!"
echo "=========================================="
