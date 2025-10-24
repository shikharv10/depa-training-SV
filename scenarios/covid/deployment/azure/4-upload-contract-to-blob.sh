#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Upload signed contract to Azure Blob Storage
# This is an alternative to external/contract-ledger/demo/contract/4-register-contract.sh
#
# Usage:
#   # First, run DID and signing scripts from contract-ledger:
#   cd external/contract-ledger/demo/contract
#   ./2-create-did.sh
#   ./3-sign-contract.sh
#
#   # Then upload from deployment directory:
#   cd scenarios/covid/deployment/azure
#   export AZURE_STORAGE_ACCOUNT_NAME=your_account
#   export AZURE_STORAGE_ACCOUNT_KEY=your_key
#   export CONTRACT_VERSION=15
#   ./4-upload-contract-to-blob.sh

set -e

: ${TDP_USERNAME:?"TDP_USERNAME not set"}
: ${AZURE_STORAGE_ACCOUNT_NAME:?"AZURE_STORAGE_ACCOUNT_NAME not set"}
: ${AZURE_STORAGE_ACCOUNT_KEY:?"AZURE_STORAGE_ACCOUNT_KEY not set"}
: ${CONTRACT_CONTAINER_NAME:="pilot-contracts"}
: ${CONTRACT_VERSION:?"CONTRACT_VERSION not set (e.g., 15 for contract 2.15)"}

# Path to contract-ledger tmp directory
CONTRACT_LEDGER_DIR="${REPO_ROOT:-../../../..}/external/contract-ledger/demo/contract"
TMP_DIR="$CONTRACT_LEDGER_DIR/tmp/$TDP_USERNAME"

if [ ! -f "$TMP_DIR/contract.cose" ]; then
    echo "ERROR: $TMP_DIR/contract.cose not found"
    echo "Please run 3-sign-contract.sh first"
    exit 1
fi

echo "Uploading signed contract to Azure Blob Storage..."
echo "  Storage Account: $AZURE_STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTRACT_CONTAINER_NAME"
echo "  Version: $CONTRACT_VERSION"

# Upload using Python
python3 << EOF
from azure.storage.blob import BlobServiceClient
import sys
import os

try:
    connection_string = f"DefaultEndpointsProtocol=https;AccountName=${AZURE_STORAGE_ACCOUNT_NAME};AccountKey=${AZURE_STORAGE_ACCOUNT_KEY};EndpointSuffix=core.windows.net"
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)

    # Get container client
    container_client = blob_service_client.get_container_client("${CONTRACT_CONTAINER_NAME}")
    try:
        container_client.create_container()
        print(f"✓ Created container: ${CONTRACT_CONTAINER_NAME}")
    except Exception as e:
        if "ContainerAlreadyExists" not in str(e):
            raise

    # Upload signed contract (COSE format)
    with open("${TMP_DIR}/contract.cose", "rb") as data:
        blob_client = container_client.get_blob_client("${CONTRACT_VERSION}.cose")
        blob_client.upload_blob(data, overwrite=True)
        print(f"✓ Uploaded: ${CONTRACT_VERSION}.cose")

    # Upload DID documents to trust store
    for did_file in ["did.json"]:
        if os.path.exists("${TMP_DIR}/" + did_file):
            with open("${TMP_DIR}/" + did_file, "rb") as data:
                blob_client = container_client.get_blob_client(f"trust_store/${TDP_USERNAME}-" + did_file)
                blob_client.upload_blob(data, overwrite=True)
                print(f"✓ Uploaded: trust_store/${TDP_USERNAME}-{did_file}")

    print(f"\n✓ Contract uploaded successfully!")
    print(f"  URL: https://${AZURE_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${CONTRACT_CONTAINER_NAME}/${CONTRACT_VERSION}.cose")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "Next steps:"
    echo "  1. Other participants can sign the contract (steps 7-10)"
    echo "  2. Deploy training with: CONTRACT_STORAGE_MODE=blob ./deploy.sh -c $CONTRACT_VERSION -p pipeline_config.json"
fi
