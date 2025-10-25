Here’s the **sanitized and publication-ready version** of your Quick Start README.
It keeps all technical detail but removes every identifier tied to your actual Azure environment.
You can safely post this on GitHub.

---

# Quick Start: Blob Storage Mode for DEPA Training

This guide explains how to use **Azure Blob Storage** instead of **CCF** for contract management during development or pilot deployments.

> ⚠️ **Security Note**
> All names and URLs in this document are placeholders.
> Replace every placeholder (for example, `<your-storage-account-name>`, `<your-tdp-username>`) with your actual values.
> Never publish real Azure subscription IDs, keys, or Key Vault URLs in public repositories.

---

## Prerequisites

```bash
# Ensure submodules are initialized
cd /home/user/<your-project-root>
git submodule update --init --recursive

# Install pyscitt CLI (one time)
cd external/contract-ledger/pyscitt
pip3 install -e .
```

---

## Workflow Comparison

### CCF Mode (Production)

```bash
cd external/contract-ledger/demo/contract
./2-create-did.sh          # Generate DID
./3-sign-contract.sh       # Sign contract
./4-register-contract.sh   # Submit to CCF ← Uses CCF service
```

### Blob Mode (Development or Pilots)

```bash
# Steps 1-3: same scripts as CCF mode
cd external/contract-ledger/demo/contract
./2-create-did.sh          # Generate DID
./3-sign-contract.sh       # Sign contract

# Step 4: upload to Blob from the deployment directory
cd ../../../../scenarios/<your-scenario>/deployment/azure
./4-upload-contract-to-blob.sh   # Upload to Azure Blob Storage
```

Only the last step changes; everything else is identical.

---

## Step-by-Step: Blob Mode

### 1  Set Environment Variables

```bash
# Required for Blob mode
export AZURE_STORAGE_ACCOUNT_NAME="<your-storage-account-name>"
export AZURE_STORAGE_ACCOUNT_KEY="<your-storage-key>"
export CONTRACT_VERSION="<contract-version>"

# Required for DID generation
export TDP_USERNAME="<your-tdp-username>"

# Optional
export CONTRACT_CONTAINER_NAME="<your-contract-container>"   # default if omitted
```

### 2  Navigate to the Contract Directory

```bash
cd external/contract-ledger/demo/contract
```

### 3  Run Existing Scripts

```bash
# Generate DID (creates tmp/<your-tdp-username>/did.json and key.pem)
./2-create-did.sh

# Sign contract (creates tmp/<your-tdp-username>/contract.cose)
./3-sign-contract.sh
```

### 4  Upload to Blob (Instead of CCF)

```bash
cd ../../../../scenarios/<your-scenario>/deployment/azure
./4-upload-contract-to-blob.sh
```

**Example Output (illustrative):**

```
✓ Uploaded: <contract-version>.cose
✓ Uploaded: trust_store/<your-tdp-username>-did.json
✓ Contract uploaded successfully!
  URL: https://<your-storage-account-name>.blob.core.windows.net/<your-contract-container>/<contract-version>.cose
```

### 5  Deploy Training with Blob Mode

```bash
cd scenarios/<your-scenario>/deployment/azure

# Enable Blob mode
export CONTRACT_STORAGE_MODE=blob

# Deploy (same command as CCF mode)
./deploy.sh -c <contract-version> -p ../../config/pipeline_config.json
```

---

## That’s It !

Blob mode simply replaces the CCF submission step with an upload to Azure Blob Storage.

---

## Multi-Party Signing (Optional)

If multiple participants must sign:

```bash
# TDP signs first (steps above)

# TDC signs second
export TDC_USERNAME="<your-tdc-username>"
./7-create-did.sh
./9-sign-contract.sh      # Adds TDC signature

# Upload contract with both signatures
cd ../../../../scenarios/<your-scenario>/deployment/azure
./4-upload-contract-to-blob.sh

# Additional participants repeat the same process
```

---

## Monitoring Deployment

```bash
# Check container status
az container show \
  --resource-group <your-resource-group> \
  --name <your-container-instance-name> \
  --query "containers[].{name:name, state:instanceView.currentState.state}" \
  -o table

# View sidecar logs
az container logs \
  --resource-group <your-resource-group> \
  --name <your-container-instance-name> \
  --container-name <your-sidecar-container>
```

**Illustrative Logs**

```
Contract storage mode: blob
Using Azure Blob Storage for contract retrieval
✓ Downloaded <contract-version>.cose
✓ Verified 1 signature(s)
✓ Contract saved to /tmp/contracts/2.<contract-version>.json
Policy checked, mounting encrypted storage...
```

---

## Switching Between Modes

### Use CCF Mode

```bash
export CONTRACT_STORAGE_MODE=ccf
export CONTRACT_SERVICE_URL="https://<your-ccf-service>:8000"
./4-register-contract.sh
./deploy.sh -c <contract-sequence-no> -p pipeline_config.json
```

### Use Blob Mode

```bash
cd external/contract-ledger/demo/contract
./2-create-did.sh
./3-sign-contract.sh

cd ../../../../scenarios/<your-scenario>/deployment/azure
export CONTRACT_STORAGE_MODE=blob
export AZURE_STORAGE_ACCOUNT_NAME="<your-storage-account-name>"
export AZURE_STORAGE_ACCOUNT_KEY="<your-storage-key>"
./4-upload-contract-to-blob.sh
./deploy.sh -c <contract-version> -p pipeline_config.json
```

---

## Troubleshooting

### Contract Not Found in Blob

```bash
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name <your-contract-container> \
  --output table
```

Re-upload if missing:

```bash
cd scenarios/<your-scenario>/deployment/azure
./4-upload-contract-to-blob.sh
```

### Signature Verification Fails

```bash
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name <your-contract-container> \
  --prefix trust_store/ \
  --output table
```

### Sidecar Exits Immediately

```bash
az container logs \
  --resource-group <your-resource-group> \
  --name <your-container-instance-name> \
  --container-name <your-sidecar-container>

# Verify credentials
echo $AZURE_STORAGE_ACCOUNT_NAME
echo $AZURE_STORAGE_ACCOUNT_KEY
```

---

## Files Created

```
external/contract-ledger/demo/contract/tmp/<your-tdp-username>/
├── did.json           # Public DID document
├── key.pem            # Private key (keep secure)
└── contract.cose      # Signed contract

Azure Blob Storage (<your-contract-container>):
├── <contract-version>.cose
└── trust_store/
    └── <your-tdp-username>-did.json
```

---

## Summary

Blob mode and CCF mode share identical workflows except for one step:

| Step                  | CCF Mode                            | Blob Mode                                   |
| --------------------- | ----------------------------------- | ------------------------------------------- |
| DID generation        | ✅ same script                       | ✅ same script                               |
| Contract signing      | ✅ same script                       | ✅ same script                               |
| Contract registration | `4-register-contract.sh` → CCF      | `4-upload-contract-to-blob.sh` → Azure Blob |
| Deployment            | identical command (`./deploy.sh …`) | identical command (`./deploy.sh …`)         |

**Minimal change, full compatibility.**

---

## References

* [CCF-vs-BLOB-MODES.md](../../scenarios/<your-scenario>/deployment/azure/CCF-vs-BLOB-MODES.md) – Detailed comparison
* [DID-SIGNING-WORKFLOW.md](../../scenarios/<your-scenario>/deployment/azure/DID-SIGNING-WORKFLOW.md) – Technical workflow
* [contract-ledger README](../../external/contract-ledger/README.md) – Full CCF documentation

---

This version is fully sanitized, parameterized, and safe for open publication while remaining technically complete for other developers.
