#!/bin/bash

# Redeploy script with the fixed encfs image
# This script assumes:
# - Azure CLI is installed and you're logged in (az login)
# - Environment variables are sourced from ~/depa-env.sh

set -e

echo "=== Setting up environment ==="
cd ~/depa-training-SV/scenarios/covid/deployment/azure

# Source environment variables
source ~/depa-env.sh

# Set storage credentials for blob mode
# NOTE: These should be set in ~/depa-env.sh or your environment
export AZURE_STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT_NAME:-depapilotstorage2336}"
if [[ -z "${AZURE_STORAGE_ACCOUNT_KEY}" ]]; then
  echo "ERROR: AZURE_STORAGE_ACCOUNT_KEY must be set in your environment"
  echo "Please set it before running this script"
  exit 1
fi

echo ""
echo "=== Deleting old container group (using broken image) ==="
az container delete --resource-group depa-pilots --name depa-training-covid --yes

echo ""
echo "=== Waiting for deletion to complete ==="
sleep 10

echo ""
echo "=== Deploying with fixed encfs image ==="
echo "Image digest: sha256:6ed68e5dfbd83b8767eba48e8592f48dade67cbd1cf13c9be5865d3c640756fe"
CONTRACT_STORAGE_MODE=blob ./deploy.sh -c 15 -p ../../config/pipeline_config.json

echo ""
echo "=== Deployment complete! ==="
echo ""
echo "=== Waiting 15 seconds for container to start ==="
sleep 15

echo ""
echo "=== Checking sidecar logs ==="
az container logs --resource-group depa-pilots --name depa-training-covid --container-name encrypted-storage-sidecar

echo ""
echo "=== Expected behavior ==="
echo "You should see:"
echo "  - Contract storage mode: blob"
echo "  - Fetching signed contract from blob storage..."
echo "  - Contract sequence 15 downloaded"
echo "  - Signature validation from TDP and TDC DIDs"
echo "  - Filesystem mounting operations"
echo ""
echo "NO MORE 'exec /encfs.sh: no such file or directory' errors!"
