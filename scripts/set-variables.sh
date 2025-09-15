#!/bin/bash

# Script: set-variables.sh
# Description: Set and export deployment variables
# Author: groovy-sky
# Date: 2025-01-13

# Function to generate storage account name
generate_storage_name() {
    local rg_name=$1
    local storage_name="st${rg_name//[-_]/}$RANDOM"
    storage_name=$(echo "${storage_name:0:24}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    echo $storage_name
}

# Set default values if not provided
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-containerapp-storage}"
export CONTAINERAPP_LOCATION="${CONTAINERAPP_LOCATION:-eastus}"
export STORAGE_LOCATION="${STORAGE_LOCATION:-westus}"
export DOCKER_IMAGE="${DOCKER_IMAGE:-nginx:latest}"
export FILE_SHARE_NAME="${FILE_SHARE_NAME:-applogs}"

# Generate names from resource group
export CONTAINERAPP_ENV_NAME="cae-${RESOURCE_GROUP}"
export CONTAINERAPP_NAME="ca-${RESOURCE_GROUP}"
export STORAGE_ACCOUNT_NAME=$(generate_storage_name $RESOURCE_GROUP)

# Display configuration
echo "=========================================="
echo "Environment Variables Set:"
echo "RESOURCE_GROUP: $RESOURCE_GROUP"
echo "CONTAINERAPP_ENV_NAME: $CONTAINERAPP_ENV_NAME"
echo "CONTAINERAPP_NAME: $CONTAINERAPP_NAME"
echo "STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
echo "CONTAINERAPP_LOCATION: $CONTAINERAPP_LOCATION"
echo "STORAGE_LOCATION: $STORAGE_LOCATION"
echo "DOCKER_IMAGE: $DOCKER_IMAGE"
echo "FILE_SHARE_NAME: $FILE_SHARE_NAME"
echo "=========================================="

# Save to file for persistence
cat > .env << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
CONTAINERAPP_ENV_NAME=$CONTAINERAPP_ENV_NAME
CONTAINERAPP_NAME=$CONTAINERAPP_NAME
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
CONTAINERAPP_LOCATION=$CONTAINERAPP_LOCATION
STORAGE_LOCATION=$STORAGE_LOCATION
DOCKER_IMAGE=$DOCKER_IMAGE
FILE_SHARE_NAME=$FILE_SHARE_NAME
EOF

echo "Variables saved to .env file"