#!/bin/bash
set -e  # Exit on error

ENVIRONMENT=$1
echo "Starting deployment for environment: $ENVIRONMENT"

# --- Install dependencies ---
apt-get update && apt-get install -y gnupg git python3-pip jq
pip install --upgrade pip
pip install snowflake-connector-python cryptography pyyaml

# --- Prepare GPG home ---
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
echo "use-agent" > ~/.gnupg/gpg.conf
echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf

# --- Import and decrypt private key ---
base64 --decode private_key.asc.b64 | gpg --batch --yes --import
gpg --batch --yes --passphrase "$GPG_PASSPHRASE" \
    --output /tmp/snowflake_private_key.p8 \
    --decrypt serv_source_dev_rsa_key_encr.p8.secret

# --- Prepare metadata directory ---
mkdir -p metadata

# --- Capture deployment metadata ---
DEPLOY_FILE="metadata/deployment_history_${ENVIRONMENT,,}.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_ID=$(git rev-parse HEAD)
DEPLOYED_FILES=$(ls deploy_sql_files | tr '\n' ',' | sed 's/,$//')

echo "Capturing metadata for $ENVIRONMENT deployment..."

# Create file if missing
if [ ! -f "$DEPLOY_FILE" ]; then
  echo "[]" > $DEPLOY_FILE
fi

# Append new record
jq --arg env "$ENVIRONMENT" \
   --arg branch "$BRANCH_NAME" \
   --arg commit "$COMMIT_ID" \
   --arg time "$TIMESTAMP" \
   --arg files "$DEPLOYED_FILES" \
   '. += [{"environment":$env,"branch":$branch,"commit_id":$commit,"timestamp":$time,"deployed_files":($files | split(","))}]' \
   $DEPLOY_FILE > metadata/tmp.json && mv metadata/tmp.json $DEPLOY_FILE

# --- Commit metadata to repo ---
git config user.email "pipeline@bitbucket.org"
git config user.name "Bitbucket Pipeline"
git add $DEPLOY_FILE
git commit -m "Add deployment metadata for $BRANCH_NAME ($ENVIRONMENT)" || echo "No new metadata changes"
git push origin HEAD || echo "Skipping push (manual run)"

# --- Execute deployment ---
echo "Running deployment for $ENVIRONMENT..."
python execute_sql.py "$ENVIRONMENT"

echo "✅ Deployment completed successfully for $ENVIRONMENT"
