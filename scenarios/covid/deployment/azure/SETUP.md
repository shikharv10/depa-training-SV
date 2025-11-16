# Deployment Setup

## Prerequisites

1. Copy the environment template:
```bash
   cp setup-environment.sh.template setup-environment.sh
```

2. Edit `setup-environment.sh` and fill in your secrets:
   - `AZURE_CONTAINER_REGISTRY_PASSWORD`: Get from Azure Portal → Container Registry → Access keys
   - `PYSCITT_BLOB_KEY`: Get from Azure Portal → Storage Account → Access keys

3. Load the environment:
```bash
   source setup-environment.sh
```

## Deploy
```bash
./deploy.sh -c $CONTRACT_SEQ_NO -p ../../config/pipeline_config.json
```
