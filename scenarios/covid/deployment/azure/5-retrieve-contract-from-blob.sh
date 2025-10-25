#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Retrieve a signed contract from Azure Blob Storage by sequence number
# This is equivalent to external/contract-ledger/demo/contract/8-retrieve-contract.sh
#
# Usage:
#   cd scenarios/covid/deployment/azure
#   ./5-retrieve-contract-from-blob.sh <sequence_number>
#
# Example:
#   ./5-retrieve-contract-from-blob.sh 15
#   # Downloads 15.cose and places it in contract-ledger/tmp/contracts/2.15.cose

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <sequence_number>"
    echo ""
    echo "Example: $0 15"
    echo "  This retrieves contract 2.15 from blob storage"
    exit 1
fi

SEQUENCE=$1

: ${AZURE_STORAGE_ACCOUNT_NAME:?"AZURE_STORAGE_ACCOUNT_NAME not set"}
: ${AZURE_STORAGE_ACCOUNT_KEY:?"AZURE_STORAGE_ACCOUNT_KEY not set"}
: ${CONTRACT_CONTAINER_NAME:="pilot-contracts"}

# Path to contract-ledger tmp directory
CONTRACT_LEDGER_DIR="${REPO_ROOT:-../../../..}/external/contract-ledger/demo/contract"
CONTRACTS_DIR="$CONTRACT_LEDGER_DIR/tmp/contracts"

# Create contracts directory if it doesn't exist
mkdir -p "$CONTRACTS_DIR"

echo "Retrieving contract from Azure Blob Storage..."
echo "  Storage Account: $AZURE_STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTRACT_CONTAINER_NAME"
echo "  Sequence: $SEQUENCE"

# Download using Python
python3 << EOF
from azure.storage.blob import BlobServiceClient
import sys
import os

try:
    connection_string = f"DefaultEndpointsProtocol=https;AccountName=${AZURE_STORAGE_ACCOUNT_NAME};AccountKey=${AZURE_STORAGE_ACCOUNT_KEY};EndpointSuffix=core.windows.net"
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)

    # Get container client
    container_client = blob_service_client.get_container_client("${CONTRACT_CONTAINER_NAME}")

    # Download signed contract
    blob_name = f"${SEQUENCE}.cose"
    blob_client = container_client.get_blob_client(blob_name)

    output_path = "${CONTRACTS_DIR}/2.${SEQUENCE}.cose"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "wb") as f:
        download_stream = blob_client.download_blob()
        f.write(download_stream.readall())

    print(f"✓ Downloaded: {blob_name}")
    print(f"✓ Saved to: {output_path}")

    # Also download trust store DIDs for verification
    trust_store_dir = "${CONTRACTS_DIR}/trust_store"
    os.makedirs(trust_store_dir, exist_ok=True)

    blob_list = container_client.list_blobs(name_starts_with="trust_store/")
    for blob in blob_list:
        if blob.name.endswith("-did.json"):
            blob_client = container_client.get_blob_client(blob.name)
            local_filename = os.path.basename(blob.name)
            local_path = os.path.join(trust_store_dir, local_filename)
            with open(local_path, "wb") as f:
                download_stream = blob_client.download_blob()
                f.write(download_stream.readall())
            print(f"✓ Downloaded: {blob.name}")

    print(f"\n✓ Contract 2.${SEQUENCE} retrieved successfully!")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "Next steps:"
    echo "  1. Sign the contract (from contract-ledger directory):"
    echo "       cd external/contract-ledger/demo/contract"
    echo "       ./9-sign-contract.sh $SEQUENCE"
    echo "  2. Upload the newly signed contract (from deployment directory):"
    echo "       cd ../../../../scenarios/covid/deployment/azure"
    echo "       ./4-upload-contract-to-blob.sh"
else
    exit 1
fi
