# CCF vs Blob Storage: Understanding Contract Modes

## Overview

DEPA Training now supports **two modes** for contract management:

1. **CCF Mode** (Production) - Uses Confidential Consortium Framework with distributed ledger
2. **Blob Mode** (Development/Pilots) - Uses Azure Blob Storage with DID signatures

Both modes provide secure contract management, but with different trade-offs.

## CCF Mode (Standard Production Flow)

### What is CCF Mode?

CCF (Confidential Consortium Framework) mode uses a distributed, replicated ledger service running on confidential VMs. This is the **standard production approach** described in the COVID scenario README.

### Architecture

```
Contract Ledger Repository (CCF Service)
    ↓
https://depa-training-contract-service.centralindia.cloudapp.azure.com:8000
    ↓
Distributed Ledger (with receipts & non-repudiation)
    ↓
DEPA Training retrieves contracts via SCITT protocol
```

### Setup Process

1. **Deploy CCF Service** (one-time infrastructure setup)
   - Follow instructions at: https://github.com/kapilvgit/contract-ledger
   - Or use fork: https://github.com/shikharv10/contract-ledger-SV
   - Requires multiple confidential VMs for consensus
   - Provides distributed trust and Byzantine fault tolerance

2. **Sign and Submit Contract** (per training run)
   ```bash
   # Navigate to contract-ledger repo
   cd /path/to/contract-ledger/demo/contract

   # Generate DIDs
   ./2-create-did.sh

   # Sign contract
   ./3-sign-contract.sh

   # Submit to CCF service
   ./4-register-contract.sh

   # Get contract sequence number
   export CONTRACT_SEQ_NO=15  # e.g., 15 for contract 2.15
   ```

3. **Deploy Training** (with CCF)
   ```bash
   # Set contract service URL
   export CONTRACT_SERVICE_URL=https://depa-training-contract-service.centralindia.cloudapp.azure.com:8000

   # Use CCF mode (default)
   export CONTRACT_STORAGE_MODE=ccf  # or omit, as ccf is default

   # Deploy with contract sequence number
   ./deploy.sh -c $CONTRACT_SEQ_NO -p ../../config/pipeline_config.json
   ```

### What Happens During Deployment

```
1. deploy.sh obtains CCF service parameters
   └─> curl $CONTRACT_SERVICE_URL/parameters

2. Sidecar container starts
   └─> Detects CONTRACT_STORAGE_MODE=ccf (or default)
   └─> Calls: scitt retrieve-contracts
       --url $CONTRACT_SERVICE_URL
       --from $CONTRACT_SEQ_NO

3. CCF service returns:
   └─> Signed contract (COSE)
   └─> Receipt with Merkle proof
   └─> Ledger signature

4. Verification:
   └─> Verifies receipt against CCF certificate
   └─> Validates contract signatures
   └─> Confirms ledger inclusion

5. Policy validation and training proceeds
```

### CCF Mode Benefits

✅ **Production-grade security**
- Distributed consensus prevents single point of failure
- Byzantine fault tolerance
- Tamper-evident ledger with cryptographic proofs

✅ **Non-repudiation**
- CCF receipts provide irrefutable proof of contract registration
- Merkle proofs show contract inclusion in ledger
- Audit trail for compliance

✅ **Availability**
- Replicated across multiple nodes
- Survives individual node failures
- Geographic distribution possible

✅ **Governance**
- Multi-party control of contract ledger
- Transparent governance rules
- Member voting on policy changes

### CCF Mode Requirements

- **Infrastructure**: Multiple confidential VMs (3-5 nodes minimum)
- **Complexity**: Requires CCF deployment and management
- **Cost**: Higher due to distributed infrastructure
- **Expertise**: Requires CCF operational knowledge
- **Time**: Initial setup takes hours to days

## Blob Storage Mode (Development/Pilot Flow)

### What is Blob Mode?

Blob mode uses Azure Blob Storage with DID-based signatures. This is a **lightweight alternative** for development, testing, and pilot deployments.

### Architecture

```
DID Generation (local)
    ↓
Contract Signing (local with DIDs)
    ↓
Azure Blob Storage (pilot-contracts container)
    ↓
DEPA Training fetches and verifies signatures
```

### Setup Process

1. **Generate DIDs** (one-time per participant)
   ```bash
   cd scenarios/covid/deployment/azure
   ./1-generate-dids.sh
   ```

2. **Sign and Upload Contract** (per training run)
   ```bash
   export AZURE_STORAGE_ACCOUNT_NAME=your_account
   export AZURE_STORAGE_ACCOUNT_KEY=your_key
   ./2-create-and-sign-contract.sh
   ```

3. **Deploy Training** (with Blob Storage)
   ```bash
   # Enable blob mode
   export CONTRACT_STORAGE_MODE=blob

   # Storage credentials
   export AZURE_STORAGE_ACCOUNT_NAME=your_account
   export AZURE_STORAGE_ACCOUNT_KEY=your_key

   # Deploy with contract version
   ./deploy.sh -c 15 -p ../../config/pipeline_config.json
   ```

### What Happens During Deployment

```
1. deploy.sh detects blob mode
   └─> Skips CCF service check
   └─> Injects storage credentials into config

2. Sidecar container starts
   └─> Detects CONTRACT_STORAGE_MODE=blob
   └─> Calls: /fetch_contract_from_blob.py

3. Python script:
   └─> Downloads 2.15.cose from blob storage
   └─> Downloads trust store
   └─> Verifies signatures (TDP, TDC, CCRP)
   └─> Extracts contract JSON

4. Policy validation and training proceeds
```

### Blob Mode Benefits

✅ **Simple setup**
- No infrastructure deployment needed
- Uses existing Azure Storage account
- Ready in minutes

✅ **Low cost**
- Only blob storage costs
- No VM infrastructure required
- Pay-per-use pricing

✅ **Easy testing**
- Quick iteration during development
- Simple to update contracts
- Fast feedback loop

✅ **Flexible for pilots**
- Good for proof-of-concept deployments
- Suitable for single-organization testing
- Easy credential management

### Blob Mode Limitations

⚠️ **Single point of trust**
- Blob storage controlled by single account
- No distributed consensus
- Relies on Azure's security

⚠️ **No built-in receipts**
- No automatic non-repudiation proofs
- Must rely on blob versioning and logs
- Limited audit trail

⚠️ **Storage account security**
- Requires protecting storage keys
- Access control managed via Azure RBAC
- No Byzantine fault tolerance

⚠️ **Not for production governance**
- Single-party control of contract storage
- No multi-party governance
- Limited transparency

## When to Use Each Mode

### Use CCF Mode When:

- ✅ **Production deployments** with real data and commercial value
- ✅ **Multi-party governance** is required
- ✅ **Non-repudiation** and audit trails are mandatory
- ✅ **High availability** is critical
- ✅ **Regulatory compliance** requires distributed ledger
- ✅ **Long-term** contract storage (years)
- ✅ **Trust boundaries** between organizations

**Example**: Production COVID modeling with multiple government agencies providing sensitive health data.

### Use Blob Mode When:

- ✅ **Development and testing** of training pipelines
- ✅ **Pilot deployments** to demonstrate feasibility
- ✅ **Single organization** controlling all data
- ✅ **Quick prototyping** needed
- ✅ **Cost constraints** limit infrastructure
- ✅ **Short-term** experiments (days to weeks)
- ✅ **Learning** the DEPA Training system

**Example**: Initial pilot testing DEPA Training with synthetic data before production deployment.

## Migration Path: Blob → CCF

Blob mode is designed to be a stepping stone to CCF mode:

### Phase 1: Development (Blob Mode)
```bash
# Quick iteration with blob storage
export CONTRACT_STORAGE_MODE=blob
./1-generate-dids.sh
./2-create-and-sign-contract.sh
./deploy.sh -c 15 -p pipeline_config.json
```

### Phase 2: Pilot (Blob Mode)
```bash
# Same workflow, more realistic data
# Test with pilot partners
# Refine policies and configurations
```

### Phase 3: Production Prep (CCF Setup)
```bash
# Deploy CCF infrastructure
cd /path/to/contract-ledger
# Follow CCF deployment guide
# Set up governance members
# Configure network and certificates
```

### Phase 4: Production (CCF Mode)
```bash
# Switch to CCF mode
export CONTRACT_STORAGE_MODE=ccf
export CONTRACT_SERVICE_URL=https://your-ccf-service.com:8000
# Use CCF contract signing workflow
./deploy.sh -c $CONTRACT_SEQ_NO -p pipeline_config.json
```

## Technical Comparison

| Feature | CCF Mode | Blob Mode |
|---------|----------|-----------|
| **Infrastructure** | 3-5 confidential VMs | Azure Storage account |
| **Setup Time** | Hours to days | Minutes |
| **Monthly Cost** | $500-2000+ | $1-10 |
| **Signatures** | COSE with DID | COSE with DID |
| **Receipts** | CCF receipts with Merkle proofs | None (use blob versioning) |
| **Verification** | CCF certificate chain | DID trust store |
| **Consensus** | Raft/PBFT | N/A (single storage) |
| **Availability** | 99.9%+ (distributed) | 99.9% (Azure SLA) |
| **Governance** | Multi-party voting | Single account owner |
| **Audit Trail** | Immutable ledger | Blob logs & versioning |
| **Scalability** | High throughput | Very high throughput |
| **Byzantine Fault Tolerance** | Yes | No |
| **Suitable For** | Production | Development/Pilots |

## Contract Format Compatibility

**Both modes use identical contract format:**

```json
{
  "id": "uuid",
  "schemaVersion": "0.1",
  "startTime": "2023-03-14T00:00:00.000Z",
  "expiryTime": "2024-03-14T00:00:00.000Z",
  "tdc": "did:web:tdc.github.io",
  "tdps": ["did:web:tdp.github.io"],
  "ccrp": "did:web:ccrp.github.io",
  "datasets": [...],
  "purpose": "TRAINING",
  "constraints": [...],
  "terms": {...}
}
```

**Both modes use identical signature format:**
- COSE (RFC 8152) with multiple signers
- DID Web identifiers
- CBOR serialization

**This ensures easy migration between modes!**

## Code Organization

### Shared Code (Both Modes)
- `external/contract-ledger/pyscitt/` - COSE and DID implementation
- `src/policy/policy.rego` - Policy validation
- `scenarios/covid/contract/contract.json` - Contract template

### CCF-Specific Code
- `src/encfs/encfs.sh` (CCF path) - Calls `scitt retrieve-contracts`
- CCF service at external repository

### Blob-Specific Code
- `scenarios/covid/deployment/azure/1-generate-dids.sh` - Local DID generation
- `scenarios/covid/deployment/azure/2-create-and-sign-contract.sh` - Local signing & upload
- `scenarios/covid/deployment/azure/fetch_contract_from_blob.py` - Blob fetch & verify
- `src/encfs/encfs.sh` (Blob path) - Calls fetch script

## Example: Complete Workflows

### CCF Mode Workflow
```bash
# One-time: Deploy CCF service
cd /path/to/contract-ledger
./deploy-ccf-service.sh

# Per training run:
export CONTRACT_SERVICE_URL=https://ccf-service.com:8000
export CONTRACT_STORAGE_MODE=ccf

# Sign contract via CCF
cd /path/to/contract-ledger/demo/contract
./2-create-did.sh
./3-sign-contract.sh
./4-register-contract.sh
export CONTRACT_SEQ_NO=15

# Deploy training
cd /path/to/depa-training/scenarios/covid/deployment/azure
./3-import-keys.sh
./4-encrypt-data.sh
./5-upload-encrypted-data.sh
./deploy.sh -c $CONTRACT_SEQ_NO -p ../../config/pipeline_config.json
```

### Blob Mode Workflow
```bash
# Per training run:
export CONTRACT_STORAGE_MODE=blob
export AZURE_STORAGE_ACCOUNT_NAME=pilotstorage
export AZURE_STORAGE_ACCOUNT_KEY=key123...

# Generate DIDs (first time only)
cd scenarios/covid/deployment/azure
./1-generate-dids.sh

# Sign and upload contract
./2-create-and-sign-contract.sh

# Deploy training
./3-import-keys.sh
./4-encrypt-data.sh
./5-upload-encrypted-data.sh
./deploy.sh -c 15 -p ../../config/pipeline_config.json
```

## Hybrid Approach

You can even use a **hybrid approach**:

1. **Development**: Use blob mode for fast iteration
2. **Staging**: Use private CCF instance for testing
3. **Production**: Use production CCF with governance

All use the same contract format and signatures, just different storage backends!

## Conclusion

### Choose CCF Mode if:
- You need production-grade security
- Multi-party governance is required
- You have infrastructure resources
- Compliance requires distributed ledger

### Choose Blob Mode if:
- You're developing or piloting
- You need quick iteration
- Cost is a constraint
- Single organization controls data

**Both modes are valid** and serve different purposes. Blob mode was added to lower the barrier to entry while maintaining the security properties of DID-based signatures. You can always migrate from blob to CCF mode when ready for production.

## References

- [CCF Documentation](https://microsoft.github.io/CCF/)
- [Contract Ledger Repository](https://github.com/kapilvgit/contract-ledger)
- [Contract Ledger Fork](https://github.com/shikharv10/contract-ledger-SV)
- [SCITT Architecture](https://datatracker.ietf.org/doc/draft-ietf-scitt-architecture/)
- [DID Web Specification](https://w3c-ccg.github.io/did-method-web/)
- [COSE (RFC 8152)](https://tools.ietf.org/html/rfc8152)
