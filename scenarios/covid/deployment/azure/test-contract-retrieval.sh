#!/bin/bash
set -e

export CONTRACT_SERVICE_URL=http://localhost:7071/api
export CONTRACT_SEQ_NO=5
export PYSCITT_BACKEND=blob
export PYSCITT_BLOB_ACCOUNT=depapilotstorage2337
export PYSCITT_BLOB_KEY="<your-key>"

echo "Testing contract retrieval for CCR deployment..."

# Activate venv
cd ~/contract-ledger-SV/pyscitt
source venv/bin/activate

# Test retrieval
echo "Retrieving contract 2.${CONTRACT_SEQ_NO}..."
scitt retrieve-contracts /tmp/ccr-deploy-test \
    --from ${CONTRACT_SEQ_NO} \
    --to ${CONTRACT_SEQ_NO}

if [ -f "/tmp/ccr-deploy-test/2.${CONTRACT_SEQ_NO}.cose" ]; then
    echo "✅ Contract retrieved successfully"
    echo "Contract details:"
    cat /tmp/ccr-deploy-test/2.${CONTRACT_SEQ_NO}.json | jq '{tdc, tdps, datasets: .datasets | length}'
else
    echo "❌ Contract retrieval failed"
    exit 1
fi

# Test service parameters
echo ""
echo "Testing service parameters..."
curl -f ${CONTRACT_SERVICE_URL}/parameters > /tmp/params.json
if [ $? -eq 0 ]; then
    echo "✅ Service parameters retrieved"
    cat /tmp/params.json | jq '{serviceId, treeAlgorithm}'
else
    echo "❌ Service parameters failed"
    exit 1
fi

echo ""
echo "✅ All CCR contract retrieval tests passed!"
