# Quick Start: Blob Storage Mode for DEPA Training

This guide shows how to use Azure Blob Storage instead of CCF for contract management during development and pilot deployments.

## Prerequisites

```bash
# Ensure submodules are initialized
cd /home/user/depa-training-SV
git submodule update --init --recursive

# Install pyscitt CLI (one-time)
cd external/contract-ledger/pyscitt
pip3 install -e .
```

## Workflow Comparison

### CCF Mode (Production)
```bash
cd external/contract-ledger/demo/contract
./2-create-did.sh          # Generate DID
./3-sign-contract.sh       # Sign contract
./4-register-contract.sh   # Submit to CCF ← Uses CCF service
```

### Blob Mode (Development/Pilots)
```bash
# Steps 1-3: Use existing contract-ledger scripts
cd external/contract-ledger/demo/contract
./2-create-did.sh          # Generate DID (same)
./3-sign-contract.sh       # Sign contract (same)

# Step 4: Upload to blob from deployment directory
cd ../../../../scenarios/covid/deployment/azure
./4-upload-contract-to-blob.sh  # Upload to blob ← Uses blob storage
```

**Only the last step changes!** Everything else stays the same.

## Step-by-Step: Blob Mode

### 1. Set Environment Variables

```bash
# Required for blob mode
export AZURE_STORAGE_ACCOUNT_NAME=your_storage_account
export AZURE_STORAGE_ACCOUNT_KEY=your_storage_key
export CONTRACT_VERSION=15  # For contract 2.15

# Required for DID generation
export TDP_USERNAME=depa-pilot-tdp

# Optional
export CONTRACT_CONTAINER_NAME=pilot-contracts  # default
```

### 2. Navigate to Contract Directory

```bash
cd external/contract-ledger/demo/contract
```

### 3. Run Existing Scripts

```bash
# Generate DID (creates tmp/$TDP_USERNAME/did.json and key.pem)
./2-create-did.sh

# Sign contract (creates tmp/$TDP_USERNAME/contract.cose)
./3-sign-contract.sh
```

### 4. Upload to Blob (Instead of CCF)

```bash
# Upload to blob storage instead of submitting to CCF
cd ../../../../scenarios/covid/deployment/azure
./4-upload-contract-to-blob.sh
```

**Output:**
```
✓ Uploaded: 15.cose
✓ Uploaded: trust_store/depa-pilot-tdp-did.json
✓ Contract uploaded successfully!
  URL: https://your_account.blob.core.windows.net/pilot-contracts/15.cose
```

### 5. Deploy Training with Blob Mode

```bash
cd scenarios/covid/deployment/azure

# Enable blob mode
export CONTRACT_STORAGE_MODE=blob

# Deploy (same command as CCF mode!)
./deploy.sh -c 15 -p ../../config/pipeline_config.json
```

## That's It!

The **only difference** is using `4-upload-contract-to-blob.sh` (from deployment/azure) instead of `4-register-contract.sh`.

## Multi-Party Signing (Optional)

If you need multiple participants to sign:

```bash
# TDP signs first (steps above from contract-ledger directory)

# TDC signs second (still in contract-ledger directory)
export TDC_USERNAME=depa-pilot-tdc
./7-create-did.sh         # TDC's DID
./9-sign-contract.sh      # Add TDC signature

# Upload with both signatures (from deployment directory)
cd ../../../../scenarios/covid/deployment/azure
./4-upload-contract-to-blob.sh

# CCRP signs third (similar process)
```

## Monitoring Deployment

```bash
# Check container status
az container show \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid \
  --query "containers[].{name:name, state:instanceView.currentState.state}" \
  -o table

# Check sidecar logs
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid \
  --container-name encrypted-storage-sidecar
```

**Expected logs:**
```
Contract storage mode: blob
Using Azure Blob Storage for contract retrieval
✓ Downloaded 15.cose
✓ Verified 1 signature(s)
✓ Contract saved to /tmp/contracts/2.15.json
Policy checked, mounting encrypted storage...
```

## Switching Between Modes

### Use CCF Mode
```bash
export CONTRACT_STORAGE_MODE=ccf
export CONTRACT_SERVICE_URL=https://your-ccf-service:8000
./4-register-contract.sh   # Submit to CCF
./deploy.sh -c $CONTRACT_SEQ_NO -p pipeline_config.json
```

### Use Blob Mode
```bash
# From contract-ledger directory:
cd external/contract-ledger/demo/contract
./2-create-did.sh
./3-sign-contract.sh

# From deployment directory:
cd ../../../../scenarios/covid/deployment/azure
export CONTRACT_STORAGE_MODE=blob
export AZURE_STORAGE_ACCOUNT_NAME=your_account
export AZURE_STORAGE_ACCOUNT_KEY=your_key
./4-upload-contract-to-blob.sh      # Upload to blob
./deploy.sh -c 15 -p pipeline_config.json
```

## Troubleshooting

### Contract not found in blob
```bash
# List contracts
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --output table

# Re-upload if needed (from deployment directory)
cd scenarios/covid/deployment/azure
./4-upload-contract-to-blob.sh
```

### Signature verification fails
```bash
# Check DID was uploaded
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --prefix trust_store/ \
  --output table

# Verify locally
ls -la tmp/$TDP_USERNAME/
```

### Sidecar exits immediately
```bash
# Check sidecar logs
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid \
  --container-name encrypted-storage-sidecar

# Common cause: storage credentials not set
echo $AZURE_STORAGE_ACCOUNT_NAME
echo $AZURE_STORAGE_ACCOUNT_KEY
```

## Files Created

```
external/contract-ledger/demo/contract/tmp/$TDP_USERNAME/
├── did.json           # DID document (public)
├── key.pem            # Private key (keep secure!)
└── contract.cose      # Signed contract

Azure Blob Storage (pilot-contracts container):
├── 15.cose                          # Signed contract
└── trust_store/
    └── depa-pilot-tdp-did.json      # DID document
```

## Summary

**Blob mode is just CCF mode with a different final step:**
- Same DID generation (`2-create-did.sh` from contract-ledger)
- Same contract signing (`3-sign-contract.sh` from contract-ledger)
- Different upload destination (`4-upload-contract-to-blob.sh` vs `4-register-contract.sh`)
- Same deployment command (just set `CONTRACT_STORAGE_MODE=blob`)

**Minimal changes, maximum compatibility! Only one new script needed.**

## References

- [CCF-vs-BLOB-MODES.md](../../scenarios/covid/deployment/azure/CCF-vs-BLOB-MODES.md) - Detailed comparison
- [DID-SIGNING-WORKFLOW.md](../../scenarios/covid/deployment/azure/DID-SIGNING-WORKFLOW.md) - Technical details
- [contract-ledger README](../../external/contract-ledger/README.md) - Full CCF documentation
