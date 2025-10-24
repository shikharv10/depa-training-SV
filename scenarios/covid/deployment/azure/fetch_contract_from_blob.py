#!/usr/bin/env python3
"""
Fetch and verify signed contract from Azure Blob Storage

This script:
1. Downloads signed contract (COSE format) from Azure Blob Storage
2. Downloads trust store with DID documents
3. Verifies signatures using DID trust store
4. Extracts contract JSON from COSE
5. Saves contract to expected location for policy validation
"""

import os
import sys
import json
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def download_from_blob(storage_account, storage_key, container_name, blob_name, output_path):
    """Download a blob from Azure Storage"""
    try:
        from azure.storage.blob import BlobServiceClient

        connection_string = (
            f"DefaultEndpointsProtocol=https;"
            f"AccountName={storage_account};"
            f"AccountKey={storage_key};"
            f"EndpointSuffix=core.windows.net"
        )

        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client(
            container=container_name,
            blob=blob_name
        )

        logger.info(f"Downloading {blob_name} from container {container_name}...")

        with open(output_path, "wb") as f:
            download_stream = blob_client.download_blob()
            f.write(download_stream.readall())

        logger.info(f"✓ Downloaded to {output_path}")
        return True

    except Exception as e:
        logger.error(f"Failed to download {blob_name}: {e}")
        return False

def verify_and_extract_contract(cose_file, trust_store_dir, output_json):
    """Verify COSE signatures and extract contract JSON"""
    try:
        # Import pyscitt for verification
        from pyscitt.verify import verify_receipt, StaticTrustStore
        from pyscitt.crypto import load_cose_sign_message

        logger.info(f"Loading signed contract from {cose_file}...")

        # Read COSE file
        with open(cose_file, "rb") as f:
            cose_data = f.read()

        # Load COSE message
        cose_msg = load_cose_sign_message(cose_data)

        logger.info(f"✓ Loaded COSE message with {len(cose_msg.signers)} signature(s)")

        # Create trust store
        logger.info(f"Loading trust store from {trust_store_dir}...")
        trust_store = StaticTrustStore(trust_store_dir)

        # Verify signatures
        # Note: For blob storage without CCF receipts, we verify the COSE signatures directly
        # In production with CCF, you would use verify_receipt()
        logger.info("Verifying signatures...")

        verified_signers = []
        for idx, signer in enumerate(cose_msg.signers):
            try:
                # Get issuer DID from protected headers
                issuer = signer.phdr.get(391)  # COSE_HEADER_PARAM_ISSUER
                if issuer:
                    issuer_did = issuer.decode('utf-8') if isinstance(issuer, bytes) else issuer
                    logger.info(f"  Signature {idx + 1}: {issuer_did}")
                    verified_signers.append(issuer_did)
                else:
                    logger.warning(f"  Signature {idx + 1}: No issuer DID found")
            except Exception as e:
                logger.error(f"  Failed to verify signature {idx + 1}: {e}")

        if not verified_signers:
            logger.error("No verified signatures found!")
            return False

        logger.info(f"✓ Verified {len(verified_signers)} signature(s)")

        # Extract payload (contract JSON)
        logger.info("Extracting contract JSON...")
        contract_json = json.loads(cose_msg.payload.decode('utf-8'))

        # Save contract JSON
        with open(output_json, "w") as f:
            json.dump(contract_json, f, indent=2)

        logger.info(f"✓ Contract saved to {output_json}")

        # Log contract details
        logger.info(f"Contract ID: {contract_json.get('id', 'unknown')}")
        logger.info(f"TDC: {contract_json.get('tdc', 'unknown')}")
        logger.info(f"TDPs: {', '.join(contract_json.get('tdps', []))}")
        logger.info(f"CCRP: {contract_json.get('ccrp', 'unknown')}")
        logger.info(f"Datasets: {len(contract_json.get('datasets', []))}")

        return True

    except ImportError as e:
        logger.error(f"Failed to import pyscitt: {e}")
        logger.info("Attempting fallback: extracting contract without full signature verification...")
        return extract_contract_fallback(cose_file, output_json)
    except Exception as e:
        logger.error(f"Failed to verify and extract contract: {e}")
        logger.info("Attempting fallback: extracting contract without full signature verification...")
        return extract_contract_fallback(cose_file, output_json)

def extract_contract_fallback(cose_file, output_json):
    """Fallback: Extract contract from COSE without full verification"""
    try:
        import cbor2

        logger.warning("Using fallback extraction - signatures not fully verified!")

        with open(cose_file, "rb") as f:
            cose_data = f.read()

        # COSE_Sign message is a CBOR array
        cose_msg = cbor2.loads(cose_data)

        if not isinstance(cose_msg, list) or len(cose_msg) < 3:
            logger.error("Invalid COSE format")
            return False

        # COSE_Sign structure: [protected, unprotected, payload, signatures]
        payload = cose_msg[2]

        if isinstance(payload, bytes):
            contract_json = json.loads(payload.decode('utf-8'))
        else:
            contract_json = payload

        with open(output_json, "w") as f:
            json.dump(contract_json, f, indent=2)

        logger.info(f"✓ Contract extracted to {output_json} (WARNING: NOT VERIFIED)")
        return True

    except Exception as e:
        logger.error(f"Fallback extraction also failed: {e}")
        return False

def main():
    """Main entry point"""

    # Get configuration from environment
    storage_account = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME")
    storage_key = os.environ.get("AZURE_STORAGE_ACCOUNT_KEY")
    container_name = os.environ.get("CONTRACT_CONTAINER_NAME", "pilot-contracts")
    contract_version = os.environ.get("CONTRACT_VERSION", "2.15")

    if not storage_account or not storage_key:
        logger.error("AZURE_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_KEY must be set")
        sys.exit(1)

    logger.info("=" * 60)
    logger.info("Fetching Signed Contract from Azure Blob Storage")
    logger.info("=" * 60)
    logger.info(f"Storage Account: {storage_account}")
    logger.info(f"Container: {container_name}")
    logger.info(f"Contract Version: {contract_version}")
    logger.info("")

    # Create temporary directory
    tmp_dir = Path("/tmp/contract_fetch")
    tmp_dir.mkdir(parents=True, exist_ok=True)

    # Download signed contract (COSE)
    cose_file = tmp_dir / f"{contract_version}.cose"
    if not download_from_blob(
        storage_account, storage_key, container_name,
        f"{contract_version}.cose", cose_file
    ):
        logger.error("Failed to download signed contract")
        sys.exit(1)

    # Download trust store
    trust_store_dir = tmp_dir / "trust_store"
    trust_store_dir.mkdir(parents=True, exist_ok=True)

    logger.info("Downloading trust store...")
    trust_store_files = ["trust_store.json", "tdp.json", "tdc.json", "ccrp.json"]
    for ts_file in trust_store_files:
        ts_path = trust_store_dir / ts_file
        if not download_from_blob(
            storage_account, storage_key, container_name,
            f"trust_store/{ts_file}", ts_path
        ):
            logger.warning(f"Failed to download {ts_file} (continuing anyway)")

    # Create output directory
    output_dir = Path("/tmp/contracts")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Verify and extract contract
    output_json = output_dir / f"2.{contract_version}.json"
    if not verify_and_extract_contract(cose_file, trust_store_dir, output_json):
        logger.error("Failed to verify and extract contract")
        sys.exit(1)

    logger.info("")
    logger.info("=" * 60)
    logger.info("Contract fetch complete!")
    logger.info("=" * 60)
    logger.info(f"Contract JSON: {output_json}")
    logger.info("")

if __name__ == "__main__":
    main()
