#!/usr/bin/env python3
import os
import sys

# DEBUG: Print all environment variables
print("DEBUG: All environment variables:")
for key, value in os.environ.items():
    if 'AZURE' in key or 'STORAGE' in key:
        print(f"  {key} = {value[:20]}..." if len(value) > 20 else f"  {key} = {value}")

# Original code
from azure.storage.blob import BlobServiceClient

storage_account = os.environ.get('AZURE_STORAGE_ACCOUNT_NAME')
storage_key = os.environ.get('AZURE_STORAGE_ACCOUNT_KEY')

if not storage_account or not storage_key:
    print(f"Error: AZURE_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_KEY must be set")
    print(f"DEBUG: storage_account = {storage_account}")
    print(f"DEBUG: storage_key = {storage_key}")
    sys.exit(1)

# Rest of the script...
container_name = "pilot-contracts"
contract_seq = os.environ.get('CONTRACT_SEQ_NO', '15')
blob_name = f"2.{contract_seq}.json"

try:
    blob_service_client = BlobServiceClient(
        account_url=f"https://{storage_account}.blob.core.windows.net",
        credential=storage_key
    )
    
    blob_client = blob_service_client.get_blob_client(
        container=container_name,
        blob=blob_name
    )
    
    output_path = f"/tmp/contracts/{blob_name}"
    os.makedirs("/tmp/contracts", exist_ok=True)
    
    with open(output_path, "wb") as download_file:
        download_file.write(blob_client.download_blob().readall())
    
    print(f"Contract {blob_name} downloaded to {output_path}")
    
except Exception as e:
    print(f"Error downloading contract: {e}")
    sys.exit(1)
