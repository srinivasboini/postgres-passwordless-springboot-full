#!/bin/bash

#==============================================================================
# JKS KeyStore Creation Script for Technical User: FA0KBSB
#==============================================================================
# This script creates a JKS keystore with:
# - Your user certificate and private key
# - Issuing CA certificate (certificate chain)
# - Trusted CA certificates
#
# Prerequisites:
# 1. private_key.key - The private key used to generate the CSR
# 2. user_certificate.crt - Your signed certificate
# 3. issuing_ca.crt - The issuing CA certificate
# 4. trusted_ca_certs/ - Directory with trusted CA certificates
#==============================================================================

# Configuration
TECHNICAL_USER="techuser"
JKS_FILE="${TECHNICAL_USER}.jks"
KEYSTORE_PASSWORD="changeit"  # CHANGE THIS to your desired password!
KEY_ALIAS="${TECHNICAL_USER}"

# Certificate files (you'll need to create these)
USER_CERT="user_certificate.crt"
ISSUING_CA_CERT="issuing_ca.crt"
TRUSTED_CA_FILE="trusted_ca_certificates.crt"  # Single file with multiple BEGIN/END blocks
PRIVATE_KEY="private_key.key"  # Your original private key from CSR generation

# PKCS12 temporary file
P12_FILE="${TECHNICAL_USER}.p12"

echo "=========================================="
echo "Creating JKS KeyStore for ${TECHNICAL_USER}"
echo "=========================================="

# Step 1: Check if all required files exist
echo ""
echo "Step 1: Checking required files..."

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "ERROR: Private key file '$PRIVATE_KEY' not found!"
    echo "You need the private key that was used to generate the CSR."
    exit 1
fi

if [ ! -f "$USER_CERT" ]; then
    echo "ERROR: User certificate file '$USER_CERT' not found!"
    exit 1
fi

if [ ! -f "$ISSUING_CA_CERT" ]; then
    echo "ERROR: Issuing CA certificate file '$ISSUING_CA_CERT' not found!"
    exit 1
fi

echo "✓ All required files found"

# Step 2: Create certificate chain file
echo ""
echo "Step 2: Creating certificate chain..."
CERT_CHAIN="cert_chain.pem"
cat "$USER_CERT" "$ISSUING_CA_CERT" > "$CERT_CHAIN"
echo "✓ Certificate chain created: $CERT_CHAIN"

# Step 3: Convert to PKCS12 format (includes private key + cert chain)
echo ""
echo "Step 3: Creating PKCS12 keystore..."
openssl pkcs12 -export \
    -in "$CERT_CHAIN" \
    -inkey "$PRIVATE_KEY" \
    -out "$P12_FILE" \
    -name "$KEY_ALIAS" \
    -password pass:"$KEYSTORE_PASSWORD"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create PKCS12 file"
    exit 1
fi
echo "✓ PKCS12 keystore created: $P12_FILE"

# Step 4: Convert PKCS12 to JKS
echo ""
echo "Step 4: Converting PKCS12 to JKS..."
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
echo "✓ JKS keystore created: $JKS_FILE"

# Step 5: Import trusted CA certificates (single file with multiple certs)
echo ""
echo "Step 5: Importing trusted CA certificates..."

TRUSTED_CA_FILE="trusted_ca_certificates.crt"

if [ -f "$TRUSTED_CA_FILE" ]; then
    echo "  Importing trusted CA certificates bundle..."
    keytool -import \
        -trustcacerts \
        -alias "trusted_ca_bundle" \
        -file "$TRUSTED_CA_FILE" \
        -keystore "$JKS_FILE" \
        -storepass "$KEYSTORE_PASSWORD" \
        -noprompt
    
    if [ $? -eq 0 ]; then
        echo "✓ Trusted CA certificates imported"
    else
        echo "WARNING: Some trusted CA certificates may have failed to import"
        echo "This is often OK - they might already be in the chain"
    fi
else
    echo "WARNING: Trusted CA certificates file not found: $TRUSTED_CA_FILE"
    echo "Skipping trusted CA import. You can import them later if needed."
fi

# Step 6: Verify the keystore
echo ""
echo "Step 6: Verifying keystore contents..."
echo "=========================================="
keytool -list -v -keystore "$JKS_FILE" -storepass "$KEYSTORE_PASSWORD"

# Cleanup temporary files
echo ""
echo "Cleaning up temporary files..."
rm -f "$P12_FILE" "$CERT_CHAIN"

echo ""
echo "=========================================="
echo "✓ JKS KeyStore successfully created!"
echo "=========================================="
echo "File: $JKS_FILE"
echo "Password: $KEYSTORE_PASSWORD"
echo "Key Alias: $KEY_ALIAS"
echo ""
echo "IMPORTANT: Store the password securely!"
echo "=========================================="
