# Testing Blob Mode - Step by Step Guide

This guide walks you through testing the blob storage mode on your Linux VM.

## Prerequisites Check

SSH into your VM and run these checks:

```bash
# 1. Check you're in the right repo
cd ~/depa-training-SV
git branch
# Should show: claude/did-contract-signing-011CUSLx73gW18ZAAx7JMg9m

# 2. Check submodules are initialized
ls -la external/contract-ledger/pyscitt/
# Should show pyscitt directory with files

# 3. Check required tools
python3 --version  # Should be 3.8+
az --version       # Azure CLI
jq --version       # JSON processor
docker --version   # Docker

# 4. Check Azure login
az account show
# Should show your subscription
```

## Phase 1: Setup Environment

### Step 1: Set Azure Credentials

```bash
# Azure subscription and resources
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_RESOURCE_GROUP="<your-resource-group>"
export AZURE_LOCATION="<your-location>"

# Azure Storage (for contracts)
export AZURE_STORAGE_ACCOUNT_NAME="<your-storage-account-name>"
export AZURE_STORAGE_ACCOUNT_KEY="<your-storage-key>"

# Azure Key Vault (for encryption keys)
export AZURE_KEY_VAULT_NAME="<your-key-vault-name>"
export AZURE_KEYVAULT_ENDPOINT="https://<your-key-vault-name>.vault.azure.net"

# Container Registry
export CONTAINER_REGISTRY="<your-container-registry>.azurecr.io"
export AZURE_CONTAINER_REGISTRY_USERNAME="<your-registry-username>"
export AZURE_CONTAINER_REGISTRY_PASSWORD="<your-registry-password>"

# Storage container names
export AZURE_ICMR_CONTAINER_NAME="icmrcontainer"
export AZURE_COWIN_CONTAINER_NAME="cowincontainer"
export AZURE_INDEX_CONTAINER_NAME="indexcontainer"
export AZURE_MODEL_CONTAINER_NAME="modelcontainer"
export AZURE_OUTPUT_CONTAINER_NAME="outputcontainer"

# Blob mode specific
export CONTRACT_STORAGE_MODE="blob"
export CONTRACT_VERSION="<contract-version>"
export CONTRACT_CONTAINER_NAME="pilot-contracts"

# Optional: Save to file for reuse
cat > ~/depa-env.sh << 'EOF'
export AZURE_SUBSCRIPTION_ID="<your-subscription-id>"
export AZURE_RESOURCE_GROUP="<your-resource-group>"
export AZURE_LOCATION="<your-location>"
export AZURE_STORAGE_ACCOUNT_NAME="<your-storage-account-name>"
export AZURE_STORAGE_ACCOUNT_KEY="<your-storage-key>"
export AZURE_KEY_VAULT_NAME="<your-key-vault-name>"
export AZURE_KEYVAULT_ENDPOINT="https://<your-key-vault-name>.vault.azure.net"
export CONTAINER_REGISTRY="<your-container-registry>.azurecr.io"
export AZURE_CONTAINER_REGISTRY_USERNAME="<your-registry-username>"
export AZURE_CONTAINER_REGISTRY_PASSWORD="<your-registry-password>"
export AZURE_ICMR_CONTAINER_NAME="icmrcontainer"
export AZURE_COWIN_CONTAINER_NAME="cowincontainer"
export AZURE_INDEX_CONTAINER_NAME="indexcontainer"
export AZURE_MODEL_CONTAINER_NAME="modelcontainer"
export AZURE_OUTPUT_CONTAINER_NAME="outputcontainer"
export CONTRACT_STORAGE_MODE="blob"
export CONTRACT_VERSION="<contract-version>"
export CONTRACT_CONTAINER_NAME="pilot-contracts"
EOF

# Load it
source ~/depa-env.sh

```

### Step 2: Install pyscitt CLI

```bash
cd ~/depa-training-SV
cd external/contract-ledger/pyscitt
pip3 install -e .

# Verify
which scitt
scitt --help
```

## Phase 2: Generate DIDs and Sign Contract

### Step 3: Generate TDP DID

```bash
cd ~/depa-training-SV/external/contract-ledger/demo/contract

# Set TDP username
export TDP_USERNAME="<your-tdp-username>"

# Generate DID
./2-create-did.sh

# Verify DID was created
ls -la tmp/$TDP_USERNAME/
# Should show: did.json, key.pem

# Check DID content
cat tmp/$TDP_USERNAME/did.json | jq '.'
```

**Expected Output:**
```json
{
  "@context": [...],
  "id": "did:web:<your-tdp-username>.github.io",
  "assertionMethod": [...]
}
```

### Step 4: Prepare Contract

```bash
# Create contracts directory if it doesn't exist
mkdir -p tmp/contracts

# Copy the COVID contract template
cp ~/depa-training-SV/scenarios/covid/contract/contract.json tmp/contracts/contract.json

# Update contract with your environment variables
# (This step might be automated by update_contract.sh)
```

### Step 5: Sign Contract

```bash
# Make sure you're in contract-ledger demo directory
cd ~/depa-training-SV/external/contract-ledger/demo/contract

# Sign the contract
./3-sign-contract.sh

# Verify signature was created
ls -la tmp/$TDP_USERNAME/
# Should show: contract.cose

# Check it's a COSE file
file tmp/$TDP_USERNAME/contract.cose
# Should indicate binary data
```

### Step 6: Upload to Blob Storage

```bash
# Navigate to deployment directory
cd ~/depa-training-SV/scenarios/covid/deployment/azure

# Upload signed contract to blob storage
./4-upload-contract-to-blob.sh
```

**Expected Output:**
```
Uploading signed contract to Azure Blob Storage...
  Storage Account: <your-storage-account-name>
  Container: pilot-contracts
  Version: 15
✓ Created container: pilot-contracts
✓ Uploaded: 15.cose
✓ Uploaded: trust_store/<your-tdp-username>-did.json
✓ Contract uploaded successfully!
  URL: https://<your-storage-account-name>.blob.core.windows.net/pilot-contracts/15.cose
```

### Step 7: Verify Upload

```bash
# List blobs in container
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --output table

# Should show:
# Name                            Blob Type    Length
# ------------------------------  -----------  --------
# 15.cose                         BlockBlob    <size>
# trust_store/<your-tdp-username>-did.json  BlockBlob    <size>
```

## Phase 3: Build and Push Containers

### Step 8: Build Containers with Blob Support

```bash
cd ~/depa-training-SV

# Build base containers
./ci/build.sh

# Build scenario-specific containers
cd scenarios/covid
./ci/build.sh
```

**Note:** This builds the containers with the updated `fetch_contract_from_blob.py` and modified `encfs.sh`.

### Step 9: Push to Container Registry

```bash
# Login to ACR
az acr login --name <your-container-registry-name>

# Or using docker
docker login <your-container-registry-name>.azurecr.io \
  -u $AZURE_CONTAINER_REGISTRY_USERNAME \
  -p $AZURE_CONTAINER_REGISTRY_PASSWORD

# Push containers
cd ~/depa-training-SV
./ci/push-containers.sh

cd scenarios/covid
./ci/push-containers.sh
```

**Expected Output:**
```
Pushing <your-container-registry-name>.azurecr.io/depa-training:latest
Pushing <your-container-registry-name>.azurecr.io/depa-training-encfs:latest
...
```

## Phase 4: Deploy and Test

### Step 10: Prepare Data and Keys

```bash
cd ~/depa-training-SV/scenarios/covid/deployment/azure

# Make sure environment is loaded
source ~/depa-env.sh

# Set additional variables for deployment
export TOOLS_HOME=~/depa-training-SV/external/confidential-sidecar-containers/tools
export SCENARIO=covid
export REPO_ROOT=~/depa-training-SV

# Create storage containers (if not exists)
./1-create-storage-containers.sh

# Import encryption keys to Key Vault
./3-import-keys.sh

# Encrypt data
./4-encrypt-data.sh

# Upload encrypted data
./5-upload-encrypted-data.sh
```

### Step 11: Deploy with Blob Mode

```bash
cd ~/depa-training-SV/scenarios/covid/deployment/azure

# Ensure blob mode is set
export CONTRACT_STORAGE_MODE=blob

# Deploy
./deploy.sh -c 15 -p ../../config/pipeline_config.json
```

**Expected Output:**
```
Obtaining contract service parameters...
Contract storage mode: blob
Using blob storage mode - skipping CCF service check
Computing CCE policy...
...
Deploying training clean room...
```

### Step 12: Monitor Deployment

```bash
# Check container status
az container show \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --query "containers[].{name:name, state:instanceView.currentState.state, exitCode:instanceView.currentState.exitCode}" \
  -o table

# Expected output:
# Name                        State        ExitCode
# --------------------------  -----------  ----------
# depa-training               Running      (null)
# encrypted-storage-sidecar   Running      (null)
```

### Step 13: Check Sidecar Logs (Critical!)

```bash
# View sidecar logs
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --container-name encrypted-storage-sidecar
```

**Expected Success Output:**
```
EncfsSideCarArgs = <base64-data>
Contract storage mode: blob
Using Azure Blob Storage for contract retrieval
Storage Account: <your-storage-account-name>
Container: pilot-contracts
Contract Version: 15
Fetching signed contract from blob storage...
INFO: Fetching Signed Contract from Azure Blob Storage
INFO: Storage Account: <your-storage-account-name>
INFO: Container: pilot-contracts
INFO: Contract Version: 15
INFO: Downloading 15.cose from container pilot-contracts...
INFO: ✓ Downloaded to /tmp/contract_fetch/15.cose
INFO: Downloading trust store...
INFO: ✓ Downloaded to /tmp/contract_fetch/trust_store/trust_store.json
INFO: Loading signed contract from /tmp/contract_fetch/15.cose...
INFO: ✓ Loaded COSE message with 1 signature(s)
INFO: Verifying signatures...
INFO:   Signature 1: did:web:<your-tdp-username>.github.io
INFO: ✓ Verified 1 signature(s)
INFO: Extracting contract JSON...
INFO: ✓ Contract saved to /tmp/contracts/2.15.json
Checking contract...
<contract JSON output>
Configuration...
<config JSON output>
Policy...
<policy output>
Policy checked, mounting encrypted storage...
```

**If you see errors:**
```bash
# Common error: Storage credentials not found
ERROR: Storage credentials not found in EncfsSideCarArgs

# Fix: Check deploy.sh injected credentials
# Look at /tmp/encrypted-filesystem-config.json on your VM
cat /tmp/encrypted-filesystem-config.json | base64 -d | jq '.'
# Should contain: storage_account_name, storage_account_key
```

### Step 14: Check Training Logs

```bash
# View training container logs
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --container-name depa-training

# Follow logs in real-time
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --container-name depa-training \
  --follow
```

**Expected Training Output:**
```
Waiting for /mnt/remote/config/pipeline_config.json...
Found pipeline config
Generating aggregated data in /tmp/covid_joined.csv
Training samples: 1483
Validation samples: 424
Test samples: 212
Dataset constructed from config
Model loaded from ONNX file
...
Epoch 1/5 completed | Training Loss: 0.6092 | Epsilon: 0.3496
...
CCR Training complete!
```

### Step 15: Verify Success

```bash
# Check final container state
az container show \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --query "containers[].{name:name, state:instanceView.currentState.state, exitCode:instanceView.currentState.exitCode, finishTime:instanceView.currentState.finishTime}" \
  -o table

# Both containers should show Terminated with exitCode 0
```

## Phase 5: Compare with CCF Mode (Optional)

To verify blob mode works equivalently to CCF mode:

### Step 16: Test CCF Mode

```bash
# Switch to CCF mode
export CONTRACT_STORAGE_MODE=ccf
export CONTRACT_SERVICE_URL=https://<your-contract-service-url>

# You would need to:
# 1. Run contract-ledger scripts with CCF submission (4-register-contract.sh)
# 2. Deploy with CCF mode
# 3. Compare results
```

## Troubleshooting

### Issue: Sidecar exits immediately

```bash
# Check exit code
az container show \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --query "containers[?name=='encrypted-storage-sidecar'].instanceView.currentState" \
  -o json

# Check logs for error
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --container-name encrypted-storage-sidecar | tail -50
```

**Common causes:**
1. Storage credentials not set → Check deploy.sh injected them
2. Contract not uploaded → Re-run step 6
3. Trust store missing → Check blob upload included trust store

### Issue: Contract fetch fails

```bash
# Verify contract exists in blob
az storage blob exists \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --name 15.cose \
  --output table

# Download and inspect locally
az storage blob download \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --name 15.cose \
  --file /tmp/test-contract.cose

file /tmp/test-contract.cose
```

### Issue: Policy validation fails

```bash
# Check contract matches environment
# Download contract JSON
az storage blob download \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --name 15.json \
  --file /tmp/contract-debug.json

# Check dataset URLs match
cat /tmp/contract-debug.json | jq '.datasets[].url'

# Should match:
echo "https://$AZURE_STORAGE_ACCOUNT_NAME.blob.core.windows.net/$AZURE_ICMR_CONTAINER_NAME/data.img"
```

### Issue: Container build fails

```bash
# Check if contract-ledger submodule has pyscitt wheel
ls -la external/contract-ledger/pyscitt/dist/

# If missing, build it
cd external/contract-ledger/pyscitt
python3 setup.py sdist bdist_wheel
```

## Cleanup

```bash
# Delete container instance
az container delete \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --yes

# Keep storage and containers for next test

# To clean everything:
# az group delete --name $AZURE_RESOURCE_GROUP --yes
```

## Success Criteria

✅ **Blob mode working if:**
1. Contract uploaded to blob storage (step 7 ✓)
2. Containers built and pushed (step 9 ✓)
3. Sidecar fetches contract from blob (step 13 ✓)
4. Sidecar verifies signatures (step 13 ✓)
5. Policy validation passes (step 13 ✓)
6. Training completes successfully (step 14 ✓)
7. Exit code 0 for both containers (step 15 ✓)

## Quick Test Script

Save this for quick testing:

```bash
#!/bin/bash
# quick-test-blob.sh

set -e

echo "=== Quick Blob Mode Test ==="

# Load environment
source ~/depa-env.sh

# Check contract in blob
echo "1. Checking contract in blob..."
az storage blob exists \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --name 15.cose \
  --output table

# Deploy
echo "2. Deploying..."
cd ~/depa-training-SV/scenarios/covid/deployment/azure
./deploy.sh -c 15 -p ../../config/pipeline_config.json

# Wait a bit
echo "3. Waiting 30 seconds..."
sleep 30

# Check status
echo "4. Checking status..."
az container show \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --query "containers[].{name:name, state:instanceView.currentState.state}" \
  -o table

# Show sidecar logs
echo "5. Sidecar logs:"
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name <your-container-instance-name> \
  --container-name encrypted-storage-sidecar | tail -50

echo "=== Test Complete ==="
```

## Next Steps After Success

Once blob mode is working:
1. Test multi-party signing (TDC adds signature)
2. Test contract updates (new version)
3. Document any deployment-specific issues
4. Create production deployment guide
