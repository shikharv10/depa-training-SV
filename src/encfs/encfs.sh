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

CONFIG_JSON=$(echo "$EncfsSideCarArgs" | base64 -d)
export AZURE_STORAGE_ACCOUNT_NAME=$(echo "$CONFIG_JSON" | jq -r '.storage_account_name // empty')
export AZURE_STORAGE_ACCOUNT_KEY=$(echo "$CONFIG_JSON" | jq -r '.storage_account_key // empty')

echo EncfsSideCarArgs = $EncfsSideCarArgs

echo "Saving contract service parameters"
TRUST_STORE=/tmp/trust_store
mkdir -p $TRUST_STORE
echo $ContractServiceParameters | base64 -d > $TRUST_STORE/scitt.json

echo "Retrieving contract..."

# COMMENTING OUT PREVIOUS COMMAND TO AVOID DEPENDENCY ON SCITT CLI
# scitt retrieve-contracts /tmp/contracts \
#    --url ${ContractService} \
#    --service-trust-store $TRUST_STORE \
#    --from $Contracts \
#    --development

# NEW: Check if using blob storage
if [[ "$ContractService" == blob://* ]]; then
    echo "Fetching contract from blob storage..."
    echo "DEBUG encfs.sh: AZURE_STORAGE_ACCOUNT_NAME = ${AZURE_STORAGE_ACCOUNT_NAME}"
    echo "DEBUG encfs.sh: AZURE_STORAGE_ACCOUNT_KEY = ${AZURE_STORAGE_ACCOUNT_KEY:0:20}..."
    echo "DEBUG encfs.sh: Exporting variables..."
    export AZURE_STORAGE_ACCOUNT_NAME
    export AZURE_STORAGE_ACCOUNT_KEY
    export CONTRACT_SEQ_NO=$Contracts
    echo "DEBUG encfs.sh: Calling Python..."
    python3 /fetch_contract_from_blob.py --id $Contracts --output /tmp/contracts
else
    echo "Fetching contract from CCF service..."
    scitt retrieve-contracts /tmp/contracts \
        --url ${ContractService} \
        --service-trust-store $TRUST_STORE \
        --from $Contracts \
        --development
fi

# PREVIOUS CODE CONTINUES BELOW

ContractPayload="/tmp/contracts/2.$Contracts.json"
if [ ! -f $ContractPayload ]; then 
  echo "Contract does not exist" 
  exit 1
fi 

# Construct input by combining encrypted file system parameters and model configuration
echo $EncfsSideCarArgs | base64 -d > ./encfs.json
echo $PipelineConfiguration | base64 -d > ./pipeline_config.json
jq -s '.[0] * .[1]' ./encfs.json ./pipeline_config.json > config.json

echo "Checking contract..."
cat $ContractPayload

echo "Configuration..."
cat ./config.json

echo "Policy..."
cat ./policy.rego

# Check configuration against contract
echo "Running OPA policy check..."
if ./opa eval --fail -i ./config.json -d $ContractPayload -d ./policy.rego 'data.policy.allowed'; then
    echo "OPA policy check PASSED"
else
    echo "ERROR: OPA policy check FAILED"
    ./opa eval -i ./config.json -d $ContractPayload -d ./policy.rego 'data.policy' || true
    exit 1
fi

echo "Policy checked, mounting encrypted storage..."

echo "DEBUG: About to run remotefs..."
echo "DEBUG: EncfsSideCarArgs length: ${#EncfsSideCarArgs}"

if [[ -z "${EncfsSideCarArgs}" ]]; then
  echo "DEBUG: Running remotefs WITHOUT base64 args"
  if /bin/remotefs -logfile /log.txt -loglevel trace; then
    echo "DEBUG: remotefs SUCCESS"
    echo "1" > result
  else
    REMOTEFS_EXIT=$?
    echo "DEBUG: remotefs FAILED with exit code $REMOTEFS_EXIT"
    echo "0" > result
  fi
else
  echo "DEBUG: Running remotefs WITH base64 args"
  if /bin/remotefs -logfile /log.txt -loglevel trace -base64 $EncfsSideCarArgs; then
    echo "DEBUG: remotefs SUCCESS"
    echo "1" > result
  else
    REMOTEFS_EXIT=$?
    echo "DEBUG: remotefs FAILED with exit code $REMOTEFS_EXIT"
    echo "DEBUG: Contents of /log.txt:"
    cat /log.txt || echo "No log file"
    echo "0" > result
  fi
fi

echo "DEBUG: Checking if /mnt/remote exists..."
ls -la /mnt/remote/ || echo "DEBUG: /mnt/remote does NOT exist"

echo "Writing training pipeline configuration..."

mkdir /mnt/remote/config
echo $PipelineConfiguration | base64 -d > /mnt/remote/config/pipeline_config.json

# Wait forever
while true; do sleep 1; done
