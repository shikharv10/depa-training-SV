# DID Contract Signing Workflow for DEPA Training

## Overview

This document describes how to sign contracts with DID (Decentralized Identifier) credentials for both CCF mode and Blob Storage mode.

## Key Insight

**Blob mode reuses existing contract-ledger scripts!** The only difference is the upload destination:

| Mode | Upload Script |
|------|---------------|
| CCF Mode | `4-register-contract.sh` (submits to CCF service) |
| Blob Mode | `4-upload-to-blob.sh` (uploads to blob storage) |

Everything else (DID generation, contract signing) is **identical**.

## Prerequisites

- Azure subscription with appropriate permissions
- Azure CLI installed and configured
- Python 3.8+ with pip
- pyscitt CLI installed
- Git with submodules initialized

## Workflow

### CCF Mode (Production)

```bash
cd external/contract-ledger/demo/contract

# Set environment
export TDP_USERNAME=your-username
export CONTRACT_SERVICE_URL=https://your-ccf-service.com:8000

# Generate DID and sign
./2-create-did.sh
./3-sign-contract.sh

# Submit to CCF
./4-register-contract.sh

# Deploy
cd ../../../../scenarios/covid/deployment/azure
export CONTRACT_STORAGE_MODE=ccf
./deploy.sh -c $CONTRACT_SEQ_NO -p ../../config/pipeline_config.json
```

### Blob Mode (Development/Pilots)

```bash
cd external/contract-ledger/demo/contract

# Set environment
export TDP_USERNAME=your-username
export AZURE_STORAGE_ACCOUNT_NAME=your_account
export AZURE_STORAGE_ACCOUNT_KEY=your_key
export CONTRACT_VERSION=15  # for contract 2.15

# Generate DID and sign (SAME as CCF mode)
./2-create-did.sh
./3-sign-contract.sh

# Upload to blob (DIFFERENT from CCF mode)
./4-upload-to-blob.sh

# Deploy
cd ../../../../scenarios/covid/deployment/azure
export CONTRACT_STORAGE_MODE=blob
./deploy.sh -c 15 -p ../../config/pipeline_config.json
```

## What Each Script Does

### 2-create-did.sh (Same for Both Modes)

Creates DID credentials:
- Generates EC (Elliptic Curve) private key
- Creates DID Web identity (e.g., `did:web:your-username.github.io`)
- Saves to `tmp/$TDP_USERNAME/` directory

**Output:**
```
tmp/$TDP_USERNAME/
├── key.pem          # Private key (KEEP SECURE!)
└── did.json         # DID document (public)
```

### 3-sign-contract.sh (Same for Both Modes)

Signs the contract:
- Loads contract from `tmp/contracts/contract.json`
- Signs with DID private key
- Creates COSE format signature
- Saves to `tmp/$TDP_USERNAME/contract.cose`

### 4-register-contract.sh (CCF Mode Only)

Submits to CCF:
- Connects to CCF service
- Submits signed contract
- Receives CCF receipt with Merkle proof
- Returns contract sequence number

### 4-upload-to-blob.sh (Blob Mode Only)

Uploads to blob storage:
- Connects to Azure Storage
- Uploads signed contract (COSE)
- Uploads DID document to trust store
- Returns blob URL

## Contract Structure (Same for Both Modes)

Deploy the DEPA Training clean room with contract verification:

```bash
# Set contract storage mode to blob
export CONTRACT_STORAGE_MODE=blob

# Set Azure resources
export AZURE_RESOURCE_GROUP=depa-pilots
export AZURE_LOCATION=eastus
export AZURE_KEYVAULT_ENDPOINT=https://depa-pilot-kv-1873.vault.azure.net
export CONTAINER_REGISTRY=depapilotacr.azurecr.io

# Set container names
export AZURE_ICMR_CONTAINER_NAME=icmrcontainer
export AZURE_COWIN_CONTAINER_NAME=cowincontainer
export AZURE_INDEX_CONTAINER_NAME=indexcontainer
export AZURE_MODEL_CONTAINER_NAME=modelcontainer
export AZURE_OUTPUT_CONTAINER_NAME=outputcontainer

# Deploy with contract version
./deploy.sh -c 15 -p ../../config/pipeline_config.json
```

**What this does:**
1. Checks contract storage mode (`blob` vs `ccf`)
2. Generates CCE (Confidential Container Environment) policy
3. Creates encrypted filesystem configuration
4. Injects storage credentials for contract retrieval
5. Deploys Azure Container Instance with:
   - Training container
   - Encrypted storage sidecar
6. Sidecar fetches and verifies signed contract from blob
7. Policy validates contract against configuration
8. Training executes if all checks pass

## How Blob Storage Mode Works

### 1. Contract Retrieval

When `CONTRACT_STORAGE_MODE=blob`, the sidecar:

```bash
# encfs.sh detects blob mode
if [ "$CONTRACT_STORAGE_MODE" = "blob" ]; then
    # Extract credentials from base64 config
    AZURE_STORAGE_ACCOUNT_NAME=...
    AZURE_STORAGE_ACCOUNT_KEY=...

    # Call Python fetch script
    /fetch_contract_from_blob.py
fi
```

### 2. Signature Verification

The fetch script (`fetch_contract_from_blob.py`):

```python
1. Download signed contract (COSE) from blob
2. Download trust store with DID documents
3. Load COSE message (multi-signature format)
4. Verify each signature:
   - Extract issuer DID from COSE headers
   - Resolve public key from DID document
   - Verify cryptographic signature
5. Extract contract JSON from verified COSE
6. Save to /tmp/contracts/2.{version}.json
```

### 3. Policy Validation

The OPA policy (`policy.rego`):

```rego
1. Check contract validity (dates, IDs)
2. Verify all datasets are properly configured
3. Validate encryption keys match contract
4. Enforce privacy constraints
5. Allow or deny training execution
```

## Contract Structure

### Unsigned Contract Template

```json
{
  "id": "uuid",
  "schemaVersion": "0.1",
  "startTime": "2023-03-14T00:00:00.000Z",
  "expiryTime": "2024-03-14T00:00:00.000Z",
  "tdc": "",              // Filled by script
  "tdps": [],             // Filled by script
  "ccrp": "",             // Filled by script
  "datasets": [
    {
      "id": "uuid",
      "name": "icmr",
      "url": "https://...",
      "provider": "",     // Filled with TDP DID
      "key": {
        "type": "azure",
        "properties": {
          "kid": "ICMRFilesystemEncryptionKey",
          "endpoint": "key-vault-url"
        }
      }
    }
  ],
  "purpose": "TRAINING",
  "constraints": [
    {
      "privacy": [
        {
          "dataset": "uuid",
          "epsilon_threshold": "1.5",
          "noise_multiplier": "2.0",
          "delta": "0.01",
          "epochs_per_report": "2"
        }
      ]
    }
  ],
  "terms": {
    "payment": {},
    "revocation": {}
  }
}
```

### Signed Contract (COSE Format)

```
COSE_Sign Message (CBOR):
├── Protected Headers
│   ├── Algorithm: ES256
│   ├── Content-Type: application/json
│   └── Issuer: did:web:participant.github.io
├── Payload: contract JSON (base64)
└── Signatures[]
    ├── Signature 1 (TDP)
    ├── Signature 2 (TDC)
    └── Signature 3 (CCRP)
```

## DID Format

### DID Web Identifier

```
did:web:depa-pilot-tdp.github.io
│   │   └── Domain name
│   └── Method: web
└── DID prefix
```

### DID Document

```json
{
  "@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/suites/jws-2020/v1"
  ],
  "id": "did:web:depa-pilot-tdp.github.io",
  "assertionMethod": [
    {
      "id": "did:web:depa-pilot-tdp.github.io#key-1",
      "type": "JsonWebKey2020",
      "controller": "did:web:depa-pilot-tdp.github.io",
      "publicKeyJwk": {
        "kty": "EC",
        "crv": "P-256",
        "x": "base64...",
        "y": "base64..."
      }
    }
  ]
}
```

## Environment Variables Reference

### Required for DID Generation

```bash
# Optional: customize DID usernames
export TDP_USERNAME=depa-pilot-tdp
export TDC_USERNAME=depa-pilot-tdc
export CCRP_USERNAME=depa-pilot-ccrp

# Optional: customize cryptography
export KEY_TYPE=ec              # ec, rsa, or ed25519
export KEY_ALG=ES256            # ES256, PS256, or EdDSA
```

### Required for Contract Signing

```bash
# Azure Storage (required)
export AZURE_STORAGE_ACCOUNT_NAME=depapilotstorage2336
export AZURE_STORAGE_ACCOUNT_KEY=your_key_here

# Optional: customize storage
export CONTRACT_CONTAINER_NAME=pilot-contracts
export CONTRACT_VERSION=2.15
export FEED_NAME=covid-training-pilot
```

### Required for Deployment

```bash
# Contract mode
export CONTRACT_STORAGE_MODE=blob

# Azure resources
export AZURE_RESOURCE_GROUP=depa-pilots
export AZURE_LOCATION=eastus
export AZURE_KEYVAULT_ENDPOINT=https://your-kv.vault.azure.net

# Container registry
export CONTAINER_REGISTRY=yourregistry.azurecr.io

# Storage containers
export AZURE_ICMR_CONTAINER_NAME=icmrcontainer
export AZURE_COWIN_CONTAINER_NAME=cowincontainer
export AZURE_INDEX_CONTAINER_NAME=indexcontainer
export AZURE_MODEL_CONTAINER_NAME=modelcontainer
export AZURE_OUTPUT_CONTAINER_NAME=outputcontainer
```

## Troubleshooting

### Sidecar Container Crashes

**Symptom:** Sidecar exits with code 1, no logs

**Check:**
1. Storage credentials in environment variables
2. Contract exists in blob storage
3. Trust store is properly uploaded
4. Container has network access to blob storage

**Debug:**
```bash
# Check sidecar logs
az container logs \
  --resource-group depa-pilots \
  --name depa-training-covid \
  --container-name encrypted-storage-sidecar

# Check container status
az container show \
  --resource-group depa-pilots \
  --name depa-training-covid \
  --query "containers[].{name:name, state:instanceView.currentState}" \
  -o table
```

### Signature Verification Fails

**Symptom:** "Failed to verify signatures" error

**Check:**
1. Trust store uploaded to blob storage
2. DID documents match the signing keys
3. Contract was signed with correct keys
4. COSE format is valid

**Debug:**
```bash
# Manually verify contract locally
source did-credentials/did_env.sh

# Download and inspect contract
az storage blob download \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name pilot-contracts \
  --name 2.15.cose \
  --file /tmp/contract.cose

# Use pyscitt to validate
scitt validate-contract \
  /tmp/contract.cose \
  --trust-store ./did-credentials/trust_store
```

### Policy Validation Fails

**Symptom:** "Policy checked" fails in sidecar logs

**Check:**
1. Contract datasets match filesystem configuration
2. Key vault endpoints match
3. Encryption key IDs match
4. Privacy constraints are satisfied

**Debug:**
```bash
# Extract and check policy evaluation
cat /tmp/encrypted-filesystem-config.json | base64 -d > /tmp/config.json
cat /tmp/contracts/2.15.json > /tmp/contract.json

# Test policy locally with OPA
opa eval \
  --fail \
  -i /tmp/config.json \
  -d /tmp/contract.json \
  -d src/policy/policy.rego \
  'data.policy.allowed'
```

## Production Considerations

### DID Hosting

For production deployments:

1. **Host DID documents on GitHub Pages:**
   ```bash
   scitt upload-did-web-github ./did-credentials/TDP/did.json
   ```

2. **Or use a web server:**
   ```
   https://your-domain.com/.well-known/did.json
   ```

3. **Update DIDs in contract before signing**

### Key Management

1. **Store private keys securely:**
   - Use Azure Key Vault
   - Use Hardware Security Modules (HSM)
   - Never commit to version control

2. **Rotate keys periodically:**
   - Generate new DID with new key
   - Update trust store
   - Re-sign active contracts

3. **Backup keys safely:**
   - Encrypted backups
   - Multi-party recovery
   - Document key recovery procedures

### Contract Versioning

1. **Use semantic versioning:**
   ```bash
   export CONTRACT_VERSION=2.15.0
   ```

2. **Maintain contract history:**
   - Keep old contracts in blob storage
   - Track which version is active
   - Document contract changes

3. **Coordinate updates:**
   - All participants must agree
   - Update and re-sign together
   - Test before production deployment

### Monitoring

1. **Monitor blob storage access:**
   - Enable Azure Storage Analytics
   - Track contract downloads
   - Alert on unauthorized access

2. **Monitor signature verification:**
   - Log all verification attempts
   - Alert on failed verifications
   - Track which DIDs are used

3. **Monitor policy enforcement:**
   - Log policy evaluations
   - Alert on policy violations
   - Track privacy budget consumption

## Security Best Practices

1. **Private Key Security:**
   - Generate keys on secure hardware
   - Never transmit private keys over network
   - Use strong passphrases for key encryption
   - Implement key rotation policies

2. **Contract Integrity:**
   - Always verify signatures before using contracts
   - Validate contract expiry dates
   - Check for contract revocation
   - Maintain audit logs

3. **Trust Store Management:**
   - Verify DID documents are authentic
   - Use HTTPS for DID resolution
   - Implement DID document revocation
   - Monitor for unauthorized changes

4. **Blob Storage Security:**
   - Use private containers
   - Enable SAS token restrictions
   - Implement IP allowlisting
   - Enable soft delete for recovery

## References

- [W3C DID Core Specification](https://www.w3.org/TR/did-core/)
- [DID Web Method Specification](https://w3c-ccg.github.io/did-method-web/)
- [COSE (RFC 8152)](https://tools.ietf.org/html/rfc8152)
- [CBOR (RFC 7049)](https://tools.ietf.org/html/rfc7049)
- [SCITT Architecture](https://datatracker.ietf.org/doc/draft-ietf-scitt-architecture/)

## Support

For issues or questions:
- GitHub Issues: https://github.com/iSPIRT/depa-training/issues
- Documentation: https://github.com/iSPIRT/depa-training/tree/main/docs
