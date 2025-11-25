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
TECHNICAL_USER="FA0KBSB"
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

# Step 2: Clean and validate certificates
echo ""
echo "Step 2: Cleaning and validating certificates..."

# Function to clean certificate files (remove any extra text/whitespace)
clean_cert() {
    local input_file=$1
    local output_file=$2
    
    # Extract only the certificate part (from BEGIN to END)
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$input_file" > "$output_file.tmp"
    
    # Verify it's a valid certificate
    if openssl x509 -in "$output_file.tmp" -noout 2>/dev/null; then
        mv "$output_file.tmp" "$output_file"
        return 0
    else
        echo "ERROR: Invalid certificate in $input_file"
        rm -f "$output_file.tmp"
        return 1
    fi
}

# Clean user certificate
echo "  Cleaning user certificate..."
clean_cert "$USER_CERT" "user_cert_clean.pem"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clean user certificate"
    exit 1
fi

# Clean issuing CA certificate
echo "  Cleaning issuing CA certificate..."
clean_cert "$ISSUING_CA_CERT" "issuing_ca_clean.pem"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clean issuing CA certificate"
    exit 1
fi

echo "✓ Certificates cleaned and validated"

# Step 3: Create certificate chain file
echo ""
echo "Step 3: Creating certificate chain..."
CERT_CHAIN="cert_chain.pem"
cat "user_cert_clean.pem" "issuing_ca_clean.pem" > "$CERT_CHAIN"

# Verify the chain file
echo "  Verifying certificate chain..."
cert_count=$(grep -c "BEGIN CERTIFICATE" "$CERT_CHAIN")
echo "  Found $cert_count certificate(s) in chain"

if [ $cert_count -lt 2 ]; then
    echo "ERROR: Certificate chain should contain at least 2 certificates"
    exit 1
fi

echo "✓ Certificate chain created: $CERT_CHAIN"

# Step 3: Check and convert private key format if needed
echo ""
echo "Step 4: Checking private key format..."

# Check if private key is encrypted
if grep -q "ENCRYPTED" "$PRIVATE_KEY"; then
    echo "WARNING: Private key is encrypted (password protected)"
    echo "You'll need to enter the password to decrypt it..."
    CONVERTED_KEY="private_key_decrypted.pem"
    openssl rsa -in "$PRIVATE_KEY" -out "$CONVERTED_KEY"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to decrypt private key"
        exit 1
    fi
    PRIVATE_KEY="$CONVERTED_KEY"
    echo "✓ Private key decrypted"
elif grep -q "BEGIN RSA PRIVATE KEY" "$PRIVATE_KEY"; then
    echo "✓ Private key format: RSA (traditional format)"
elif grep -q "BEGIN PRIVATE KEY" "$PRIVATE_KEY"; then
    echo "✓ Private key format: PKCS#8"
elif grep -q "BEGIN EC PRIVATE KEY" "$PRIVATE_KEY"; then
    echo "✓ Private key format: EC (Elliptic Curve)"
else
    echo "WARNING: Unknown private key format. Attempting to proceed..."
fi

# Step 4: Convert to PKCS12 format (includes private key + cert chain)
echo ""
echo "Step 5: Creating PKCS12 keystore..."
openssl pkcs12 -export \
    -in "$CERT_CHAIN" \
    -inkey "$PRIVATE_KEY" \
    -out "$P12_FILE" \
    -name "$KEY_ALIAS" \
    -password pass:"$KEYSTORE_PASSWORD"

if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Failed to create PKCS12 file"
    echo ""
    echo "Common causes:"
    echo "1. Private key format issue - try converting it:"
    echo "   openssl rsa -in private_key.key -out private_key_converted.pem"
    echo ""
    echo "2. Private key doesn't match the certificate"
    echo "   Verify with: openssl x509 -noout -modulus -in user_certificate.crt | openssl md5"
    echo "   And compare: openssl rsa -noout -modulus -in private_key.key | openssl md5"
    echo ""
    echo "3. Private key is password protected - you'll be prompted for password"
    echo ""
    exit 1
fi
echo "✓ PKCS12 keystore created: $P12_FILE"

# Step 5: Convert PKCS12 to JKS
echo ""
echo "Step 6: Converting PKCS12 to JKS..."
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

# Step 6: Import trusted CA certificates (single file with multiple certs)
echo ""
echo "Step 7: Importing trusted CA certificates..."

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

# Step 7: Verify the keystore
echo ""
echo "Step 8: Verifying keystore contents..."
echo "=========================================="
keytool -list -v -keystore "$JKS_FILE" -storepass "$KEYSTORE_PASSWORD"

# Cleanup temporary files
echo ""
echo "Cleaning up temporary files..."
rm -f "$P12_FILE" "$CERT_CHAIN" "user_cert_clean.pem" "issuing_ca_clean.pem" "private_key_decrypted.pem"

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
