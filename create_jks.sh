#!/bin/bash

#==============================================================================
# Simplified JKS KeyStore Creation Script
#==============================================================================
# This script:
# 1. Imports user certificate + private key into keystore
# 2. Imports issuing CA certificate into truststore.
#==============================================================================

# Configuration
TECHNICAL_USER="test"
JKS_FILE="${TECHNICAL_USER}.jks"
KEYSTORE_PASSWORD="changeit"  # CHANGE THIS!
KEY_ALIAS="${TECHNICAL_USER}"

# Required files
USER_CERT="user_certificate.crt"
ISSUING_CA_CERT="issuing_ca.crt"
PRIVATE_KEY="private_key.key"

# Temporary PKCS12 file
P12_FILE="${TECHNICAL_USER}.p12"

echo "=========================================="
echo "Creating JKS KeyStore for ${TECHNICAL_USER}"
echo "=========================================="

# Check required files
echo ""
echo "Checking required files..."

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "ERROR: Private key not found: $PRIVATE_KEY"
    exit 1
fi

if [ ! -f "$USER_CERT" ]; then
    echo "ERROR: User certificate not found: $USER_CERT"
    exit 1
fi

if [ ! -f "$ISSUING_CA_CERT" ]; then
    echo "ERROR: Issuing CA certificate not found: $ISSUING_CA_CERT"
    exit 1
fi

echo "✓ All required files found"

# Step 1: Create PKCS12 with user cert and private key
echo ""
echo "Step 1: Creating PKCS12 keystore with user certificate..."
openssl pkcs12 -export \
    -in "$USER_CERT" \
    -inkey "$PRIVATE_KEY" \
    -out "$P12_FILE" \
    -name "$KEY_ALIAS" \
    -password pass:"$KEYSTORE_PASSWORD"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create PKCS12 file"
    exit 1
fi
echo "✓ PKCS12 keystore created"

# Step 2: Convert PKCS12 to JKS
echo ""
echo "Step 2: Converting PKCS12 to JKS..."
keytool -importkeystore \
    -srckeystore "$P12_FILE" \
    -srcstoretype PKCS12 \
    -srcstorepass "$KEYSTORE_PASSWORD" \
    -destkeystore "$JKS_FILE" \
    -deststoretype JKS \
    -deststorepass "$KEYSTORE_PASSWORD" \
    -destkeypass "$KEYSTORE_PASSWORD" \
    -noprompt

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to convert to JKS"
    exit 1
fi
echo "✓ JKS keystore created"

# Step 3: Import issuing CA certificate into truststore
echo ""
echo "Step 3: Importing issuing CA certificate into truststore..."
keytool -import \
    -trustcacerts \
    -alias "issuing_ca" \
    -file "$ISSUING_CA_CERT" \
    -keystore "$JKS_FILE" \
    -storepass "$KEYSTORE_PASSWORD" \
    -noprompt

if [ $? -ne 0 ]; then
    echo "WARNING: Failed to import issuing CA (may already exist in chain)"
else
    echo "✓ Issuing CA certificate imported"
fi

# Step 4: Verify the keystore
echo ""
echo "Step 4: Verifying keystore contents..."
echo "=========================================="
keytool -list -keystore "$JKS_FILE" -storepass "$KEYSTORE_PASSWORD"

# Cleanup
echo ""
echo "Cleaning up temporary files..."
rm -f "$P12_FILE"

echo ""
echo "=========================================="
echo "✓ JKS KeyStore created successfully!"
echo "=========================================="
echo "File: $JKS_FILE"
echo "Password: $KEYSTORE_PASSWORD"
echo "Key Alias: $KEY_ALIAS"
echo ""
echo "Contents:"
echo "  - User certificate with private key (alias: $KEY_ALIAS)"
echo "  - Issuing CA certificate (alias: issuing_ca)"
echo "=========================================="
