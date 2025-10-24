#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Generate DID credentials for Training Data Provider (TDP),
# Training Data Consumer (TDC), and Confidential Clean Room Provider (CCRP)
#
# This script creates DID Web identities with associated cryptographic keys.
# In production, these DIDs would be hosted on GitHub Pages or another web server.
# For pilot deployments, we store them locally and create a trust store.

set -e

# Configuration
: ${TDP_USERNAME:="depa-pilot-tdp"}
: ${TDC_USERNAME:="depa-pilot-tdc"}
: ${CCRP_USERNAME:="depa-pilot-ccrp"}
: ${DID_DIR:="./did-credentials"}
: ${KEY_TYPE:="ec"}  # ec, rsa, or ed25519
: ${KEY_ALG:="ES256"}  # ES256 for ec, PS256 for rsa, EdDSA for ed25519

echo "=================================================="
echo "Generating DID Credentials for DEPA Training"
echo "=================================================="
echo ""
echo "Configuration:"
echo "  TDP Username: $TDP_USERNAME"
echo "  TDC Username: $TDC_USERNAME"
echo "  CCRP Username: $CCRP_USERNAME"
echo "  Output Directory: $DID_DIR"
echo "  Key Type: $KEY_TYPE"
echo "  Algorithm: $KEY_ALG"
echo ""

# Clean and create output directory
rm -rf "$DID_DIR"
mkdir -p "$DID_DIR"

# Function to generate a DID for a participant
generate_did() {
    local username=$1
    local role=$2
    local output_dir="$DID_DIR/$role"

    echo "----------------------------------------"
    echo "Generating DID for $role ($username)"
    echo "----------------------------------------"

    mkdir -p "$output_dir"

    # Generate DID Web identity
    # Note: Using localhost for pilot. In production, use actual GitHub Pages URL
    scitt create-did-web \
        --url "https://$username.github.io" \
        --kty "$KEY_TYPE" \
        --alg "$KEY_ALG" \
        --out-dir "$output_dir"

    # Display generated DID
    local did=$(jq -r '.id' "$output_dir/did.json")
    echo "✓ Generated DID: $did"
    echo "✓ Private key: $output_dir/key.pem"
    echo "✓ DID document: $output_dir/did.json"
    echo ""

    # Store DID in environment variable format
    echo "export ${role}_DID=\"$did\"" >> "$DID_DIR/did_env.sh"
}

# Generate DIDs for all participants
generate_did "$TDP_USERNAME" "TDP"
generate_did "$TDC_USERNAME" "TDC"
generate_did "$CCRP_USERNAME" "CCRP"

# Create trust store with all DID documents
echo "----------------------------------------"
echo "Creating Trust Store"
echo "----------------------------------------"

TRUST_STORE_DIR="$DID_DIR/trust_store"
mkdir -p "$TRUST_STORE_DIR"

# Copy DID documents to trust store directory
cp "$DID_DIR/TDP/did.json" "$TRUST_STORE_DIR/tdp-did.json"
cp "$DID_DIR/TDC/did.json" "$TRUST_STORE_DIR/tdc-did.json"
cp "$DID_DIR/CCRP/did.json" "$TRUST_STORE_DIR/ccrp-did.json"

echo "✓ Trust store created at: $TRUST_STORE_DIR"
echo "  - tdp-did.json"
echo "  - tdc-did.json"
echo "  - ccrp-did.json"
echo ""

# Create summary JSON with all DIDs
jq -n \
    --arg tdp_did "$(jq -r '.id' $DID_DIR/TDP/did.json)" \
    --arg tdc_did "$(jq -r '.id' $DID_DIR/TDC/did.json)" \
    --arg ccrp_did "$(jq -r '.id' $DID_DIR/CCRP/did.json)" \
    '{
        "tdp": $tdp_did,
        "tdc": $tdc_did,
        "ccrp": $ccrp_did,
        "created": now | strftime("%Y-%m-%dT%H:%M:%SZ")
    }' > "$DID_DIR/did_summary.json"

echo "✓ DID summary saved to: $DID_DIR/did_summary.json"
echo ""

echo "=================================================="
echo "DID Generation Complete!"
echo "=================================================="
echo ""
echo "To use these DIDs, source the environment file:"
echo "  source $DID_DIR/did_env.sh"
echo ""
echo "Generated DIDs:"
jq '.' "$DID_DIR/did_summary.json"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "  1. Private keys are stored in $DID_DIR/*/key.pem"
echo "  2. Keep these keys secure and never commit to git"
echo "  3. In production, upload DID documents to GitHub Pages:"
echo "     scitt upload-did-web-github $DID_DIR/TDP/did.json"
echo "  4. For pilot deployments, we'll use local trust store"
echo ""
