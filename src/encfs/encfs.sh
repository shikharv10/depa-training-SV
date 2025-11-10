#!/bin/sh
set -e

if [[ -z "${Contracts}" ]]; then
  echo "Contract not specified"
  exit 1
fi

if [[ -z "${ContractServiceParameters}" ]]; then
  echo "Contract service parameters not specified"
  exit 1
fi

if [[ -z "${ContractService}" ]]; then
  echo "Contract service not specified"
  exit 1
fi

if [[ -z "${EncfsSideCarArgs}" ]]; then
  EncfsSideCarArgs=$1
fi

if [[ -z "${PipelineConfiguration}" ]]; then
  echo "Pipeline configuration not specified"
  exit 1
fi

echo EncfsSideCarArgs = $EncfsSideCarArgs

echo "Saving contract service parameters"
TRUST_STORE=/tmp/trust_store
mkdir -p $TRUST_STORE
echo $ContractServiceParameters | base64 -d > $TRUST_STORE/scitt.json

# NEW: Set blob storage backend if specified
if [[ ! -z "${PYSCITT_BACKEND}" ]] && [[ "${PYSCITT_BACKEND}" == "blob" ]]; then
  echo "Using blob storage backend"
  export PYSCITT_BACKEND=blob
  export PYSCITT_BLOB_ACCOUNT=${PYSCITT_BLOB_ACCOUNT}
  export PYSCITT_BLOB_KEY=${PYSCITT_BLOB_KEY}
  export PYSCITT_BLOB_CONTAINER=${PYSCITT_BLOB_CONTAINER:-contracts}
  echo "Blob account: ${PYSCITT_BLOB_ACCOUNT}"
  echo "Blob container: ${PYSCITT_BLOB_CONTAINER}"
fi

echo "Retrieving contract..."
scitt retrieve-contracts /tmp/contracts \
    --url ${ContractService} \
    --service-trust-store $TRUST_STORE \
    --from $Contracts \
    --development

ContractPayload="/tmp/contracts/2.$Contracts.json"

if [ ! -f $ContractPayload ]; then
  echo "Contract does not exist"
  exit 1
fi

# Construct input by combining encrypted file system parameters and model configuration
echo $EncfsSideCarArgs | base64 -d > ./encfs.json
jq '.contract_payload = env.ContractPayload' ./encfs.json > ./input.json

echo "Validating using OPA..."
result=$(./opa eval --fail-defined --format values --data policy.rego --input ./input.json data.scitt.validate)
if [ $? -ne 0 ]; then
  echo "OPA validation failed"
  exit 1
fi

# Decode configuration
echo $PipelineConfiguration | base64 -d > /mnt/remote/config/pipeline_config.json
