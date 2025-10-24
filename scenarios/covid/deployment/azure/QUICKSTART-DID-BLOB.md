# Quick Start: DID Contract Signing with Blob Storage

This is a quick start guide to get DEPA Training running with DID-signed contracts stored in Azure Blob Storage.

## Prerequisites Check

```bash
# Check Azure CLI
az --version

# Check Python
python3 --version

# Check you're logged into Azure
az account show

# Check git submodules are initialized
ls -la external/contract-ledger/pyscitt/
```

## Quick Setup (5 Steps)

### 1. Set Environment Variables

```bash
cd scenarios/covid/deployment/azure

# Azure Storage (REQUIRED)
export AZURE_STORAGE_ACCOUNT_NAME=your_storage_account
export AZURE_STORAGE_ACCOUNT_KEY=your_storage_key

# Azure Resources (REQUIRED)
export AZURE_RESOURCE_GROUP=depa-pilots
export AZURE_LOCATION=eastus
export AZURE_KEYVAULT_ENDPOINT=https://your-kv.vault.azure.net

# Container Registry (REQUIRED)
export CONTAINER_REGISTRY=yourregistry.azurecr.io

# Container Names (REQUIRED)
export AZURE_ICMR_CONTAINER_NAME=icmrcontainer
export AZURE_COWIN_CONTAINER_NAME=cowincontainer
export AZURE_INDEX_CONTAINER_NAME=indexcontainer
export AZURE_MODEL_CONTAINER_NAME=modelcontainer
export AZURE_OUTPUT_CONTAINER_NAME=outputcontainer

# Enable blob mode (REQUIRED)
export CONTRACT_STORAGE_MODE=blob
```

### 2. Generate DID Credentials

```bash
./1-generate-dids.sh
```

**Output:** DID credentials stored in `./did-credentials/`

**Important:** The private keys in `did-credentials/*/key.pem` are sensitive. Keep them secure!

### 3. Sign and Upload Contract

```bash
./2-create-and-sign-contract.sh
```

**Output:** Signed contract uploaded to Azure Blob Storage at:
- `pilot-contracts/2.15.cose` (signed contract)
- `pilot-contracts/2.15.json` (contract JSON)
- `pilot-contracts/trust_store/*` (DID documents)

### 4. Deploy Training Clean Room

```bash
./deploy.sh -c 15 -p ../../config/pipeline_config.json
```

**Output:** Azure Container Instance created with:
- Training container
- Encrypted storage sidecar
- Contract verification enabled

### 5. Monitor Deployment

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

# Check training logs
az container logs \
  --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid \
  --container-name depa-training
```

## Expected Flow

### Successful Deployment

```
1. Sidecar starts
   ├── Detects CONTRACT_STORAGE_MODE=blob
   ├── Extracts storage credentials from config
   └── Calls fetch_contract_from_blob.py

2. Contract Fetch
   ├── Downloads 2.15.cose from blob storage
   ├── Downloads trust store
   ├── Verifies signatures (TDP, TDC, CCRP)
   └── Extracts contract JSON

3. Policy Validation
   ├── Loads contract and filesystem config
   ├── Validates datasets match
   ├── Validates keys match
   └── Validates privacy constraints

4. Filesystem Mounting
   ├── Mounts encrypted ICMR data
   ├── Mounts encrypted COWIN data
   ├── Mounts encrypted Index data
   ├── Mounts encrypted Model data
   └── Mounts encrypted Output data

5. Training Starts
   ├── Training container starts
   ├── Reads pipeline config
   ├── Accesses encrypted data
   └── Executes training
```

### Expected Log Messages

```
Contract storage mode: blob
Using Azure Blob Storage for contract retrieval
Storage Account: depapilotstorage2336
Container: pilot-contracts
Contract Version: 15
Fetching signed contract from blob storage...
✓ Downloaded 2.15.cose
✓ Downloaded trust store
✓ Loaded COSE message with 3 signature(s)
Verifying signatures...
  Signature 1: did:web:depa-pilot-tdp.github.io
  Signature 2: did:web:depa-pilot-tdc.github.io
  Signature 3: did:web:depa-pilot-ccrp.github.io
✓ Verified 3 signature(s)
✓ Contract saved to /tmp/contracts/2.15.json
Policy checked, mounting encrypted storage...
```

## Troubleshooting

### Problem: Sidecar exits immediately

```bash
# Check logs for errors
az container logs --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid --container-name encrypted-storage-sidecar

# Common causes:
# 1. AZURE_STORAGE_ACCOUNT_KEY not set
# 2. Contract not uploaded to blob
# 3. Trust store missing
```

**Fix:**
```bash
# Verify contract exists
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --output table

# Re-upload if needed
./2-create-and-sign-contract.sh
```

### Problem: Signature verification fails

```bash
# Check trust store
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --prefix trust_store/ \
  --output table

# Verify locally
source did-credentials/did_env.sh
echo "TDP_DID: $TDP_DID"
echo "TDC_DID: $TDC_DID"
echo "CCRP_DID: $CCRP_DID"
```

**Fix:**
```bash
# Re-generate DIDs and re-sign contract
./1-generate-dids.sh
./2-create-and-sign-contract.sh
```

### Problem: Policy validation fails

```bash
# Check policy logs in sidecar
az container logs --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid --container-name encrypted-storage-sidecar | grep -A 10 "Policy"

# Common causes:
# 1. Dataset URLs don't match
# 2. Key IDs don't match
# 3. Key vault endpoint mismatch
```

**Fix:**
```bash
# Check contract matches environment
cat did-credentials/contract-output/contract.json | jq '.datasets[].url'
echo "Expected: https://$AZURE_STORAGE_ACCOUNT_NAME.blob.core.windows.net/..."

# Verify key vault
cat did-credentials/contract-output/contract.json | jq '.datasets[].key.properties.endpoint'
echo "Expected: $AZURE_KEYVAULT_ENDPOINT"
```

## Comparison: CCF vs Blob Mode

### CCF Mode (Original)

```bash
# Requires running CCF service
export CONTRACT_STORAGE_MODE=ccf
export CONTRACT_SERVICE_URL=https://your-ccf-service:8000

# Contracts stored in distributed ledger
# Receipts provide non-repudiation
# Requires CCF infrastructure
```

### Blob Mode (New)

```bash
# Uses Azure Blob Storage
export CONTRACT_STORAGE_MODE=blob
export AZURE_STORAGE_ACCOUNT_NAME=your_storage
export AZURE_STORAGE_ACCOUNT_KEY=your_key

# Contracts stored in blob storage
# Signatures verified locally
# No additional infrastructure needed
```

## Next Steps

1. **Production Setup:**
   - Host DID documents on GitHub Pages
   - Store private keys in Azure Key Vault
   - Use private blob containers
   - Enable storage analytics

2. **Key Management:**
   - Implement key rotation
   - Backup keys securely
   - Document recovery procedures

3. **Monitoring:**
   - Set up alerts for failed verifications
   - Monitor blob storage access
   - Track policy violations

4. **Testing:**
   - Test contract updates
   - Test key rotation
   - Test failure scenarios

## Full Documentation

For complete documentation, see:
- [DID-SIGNING-WORKFLOW.md](./DID-SIGNING-WORKFLOW.md) - Complete workflow documentation
- [../../contract/contract.json](../../contract/contract.json) - Contract template
- [../../../docs/](../../../docs/) - General DEPA Training documentation

## Common Commands

```bash
# Re-deploy after changes
az container delete --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid --yes
./deploy.sh -c 15 -p ../../config/pipeline_config.json

# View all logs
az container logs --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid --follow

# Download model output
az storage blob download \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name $AZURE_OUTPUT_CONTAINER_NAME \
  --name model.pkl \
  --file ./output/model.pkl

# List contracts in blob
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --output table

# Delete deployment
az container delete --resource-group $AZURE_RESOURCE_GROUP \
  --name depa-training-covid --yes
```

## Support

If you encounter issues:
1. Check the logs (sidecar and training)
2. Verify environment variables are set
3. Confirm contract and trust store are uploaded
4. Review [DID-SIGNING-WORKFLOW.md](./DID-SIGNING-WORKFLOW.md) for detailed troubleshooting
