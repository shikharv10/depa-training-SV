#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Upload signed contract to Azure Blob Storage with sequence numbering
# This mimics CCF's immutable ledger behavior where each submission gets a new sequence number
#
# CCF-like Workflow:
#   TDP: sign → upload → get sequence 15
#   TDC: retrieve seq 15 → sign → upload → get sequence 16
#
# Usage:
#   # TDP workflow:
#   cd external/contract-ledger/demo/contract
#   export TDP_USERNAME=my-tdp
#   ./2-create-did.sh
#   ./3-sign-contract.sh
#   cd ../../../../scenarios/covid/deployment/azure
#   ./4-upload-contract-to-blob.sh
#   # Returns: "Submitted as transaction 2.15"
#
#   # TDC workflow:
#   cd external/contract-ledger/demo/contract
#   export TDC_USERNAME=my-tdc
#   ./7-create-did.sh
#   cd ../../../../scenarios/covid/deployment/azure
#   ./5-retrieve-contract-from-blob.sh 15  # Get TDP's version
#   cd ../../../../external/contract-ledger/demo/contract
#   ./9-sign-contract.sh 15
#   cd ../../../../scenarios/covid/deployment/azure
#   ./4-upload-contract-to-blob.sh
#   # Returns: "Submitted as transaction 2.16"

set -e

: ${AZURE_STORAGE_ACCOUNT_NAME:?"AZURE_STORAGE_ACCOUNT_NAME not set"}
: ${AZURE_STORAGE_ACCOUNT_KEY:?"AZURE_STORAGE_ACCOUNT_KEY not set"}
: ${CONTRACT_CONTAINER_NAME:="pilot-contracts"}

# Determine signer (TDP or TDC or other)
if [ -n "$TDP_USERNAME" ]; then
    SIGNER_USERNAME="$TDP_USERNAME"
elif [ -n "$TDC_USERNAME" ]; then
    SIGNER_USERNAME="$TDC_USERNAME"
else
    echo "ERROR: Neither TDP_USERNAME nor TDC_USERNAME is set"
    echo "Please set one of them to identify the signer"
    exit 1
fi

# Path to contract-ledger tmp directory
CONTRACT_LEDGER_DIR="${REPO_ROOT:-../../../..}/external/contract-ledger/demo/contract"
SIGNER_DIR="$CONTRACT_LEDGER_DIR/tmp/$SIGNER_USERNAME"

if [ ! -f "$SIGNER_DIR/contract.cose" ]; then
    echo "ERROR: $SIGNER_DIR/contract.cose not found"
    echo "Please run the appropriate sign-contract.sh script first"
    exit 1
fi

echo "Uploading signed contract to Azure Blob Storage..."
echo "  Storage Account: $AZURE_STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTRACT_CONTAINER_NAME"
echo "  Signer: $SIGNER_USERNAME"

# Upload using Python and get sequence number
SEQUENCE=$(python3 << 'EOF'
from azure.storage.blob import BlobServiceClient
import sys
import os
import re

try:
    connection_string = f"DefaultEndpointsProtocol=https;AccountName={os.environ['AZURE_STORAGE_ACCOUNT_NAME']};AccountKey={os.environ['AZURE_STORAGE_ACCOUNT_KEY']};EndpointSuffix=core.windows.net"
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)

    # Get container client
    container_name = os.environ['CONTRACT_CONTAINER_NAME']
    container_client = blob_service_client.get_container_client(container_name)
    try:
        container_client.create_container()
        print(f"✓ Created container: {container_name}", file=sys.stderr)
    except Exception as e:
        if "ContainerAlreadyExists" not in str(e):
            raise

    # Find next sequence number by listing existing contracts
    existing_sequences = []
    blob_list = container_client.list_blobs()
    for blob in blob_list:
        # Match pattern: <number>.cose
        match = re.match(r'^(\d+)\.cose$', blob.name)
        if match:
            existing_sequences.append(int(match.group(1)))

    # Get next sequence number
    if existing_sequences:
        next_sequence = max(existing_sequences) + 1
    else:
        next_sequence = 15  # Start at 15 to match contract version 2.15

    print(f"✓ Next sequence number: {next_sequence}", file=sys.stderr)

    # Upload signed contract (COSE format) with sequence number
    signer_dir = os.environ['SIGNER_DIR']
    with open(f"{signer_dir}/contract.cose", "rb") as data:
        blob_client = container_client.get_blob_client(f"{next_sequence}.cose")
        blob_client.upload_blob(data, overwrite=False)  # Don't overwrite - immutable!
        print(f"✓ Uploaded: {next_sequence}.cose", file=sys.stderr)

    # Upload all DID documents from tmp/ to trust store
    tmp_base_dir = os.path.dirname(signer_dir)
    if os.path.exists(tmp_base_dir):
        for user_dir in os.listdir(tmp_base_dir):
            did_path = os.path.join(tmp_base_dir, user_dir, "did.json")
            if os.path.exists(did_path):
                with open(did_path, "rb") as data:
                    blob_name = f"trust_store/{user_dir}-did.json"
                    blob_client = container_client.get_blob_client(blob_name)
                    blob_client.upload_blob(data, overwrite=True)
                    print(f"✓ Uploaded: {blob_name}", file=sys.stderr)

    blob_url = f"https://{os.environ['AZURE_STORAGE_ACCOUNT_NAME']}.blob.core.windows.net/{container_name}/{next_sequence}.cose"
    print(f"\n✓ Contract uploaded successfully!", file=sys.stderr)
    print(f"  URL: {blob_url}", file=sys.stderr)

    # Output sequence number to stdout (for capture)
    print(next_sequence)

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
)

if [ $? -eq 0 ]; then
    echo ""
    echo "Submitted tmp/$SIGNER_USERNAME/contract.cose as transaction 2.$SEQUENCE"
    echo ""
    echo "Next steps:"
    echo "  - Other participants can retrieve and sign:"
    echo "      ./5-retrieve-contract-from-blob.sh $SEQUENCE"
    echo "  - Deploy training with:"
    echo "      CONTRACT_STORAGE_MODE=blob ./deploy.sh -c $SEQUENCE -p pipeline_config.json"

    # Save sequence number for easy reference
    echo "$SEQUENCE" > /tmp/last-contract-sequence.txt
else
    exit 1
fi
