#!/bin/bash
set -e

# Script: deploy.sh
# Description: Main deployment script for Container App with Storage Account
# Author: groovy-sky
# Date: 2025-01-13

# Configuration
RESOURCE_GROUP="${1:-rg-containerapp-storage}"
CONTAINERAPP_LOCATION="${2:-eastus}"
STORAGE_LOCATION="${3:-westus}"
DOCKER_IMAGE="mcr.microsoft.com/azurelinux/base/nginx:1.25"
FILE_SHARE_NAME="applogs"
DEPLOYMENT_NAME="deployment-$(date +%s)"

# Generate names from resource group
CONTAINERAPP_ENV_NAME="cae-${RESOURCE_GROUP}"
CONTAINERAPP_NAME="ca-${RESOURCE_GROUP}"
STORAGE_ACCOUNT_NAME="st${RESOURCE_GROUP//[-_]/}$RANDOM"
STORAGE_ACCOUNT_NAME=$(echo "${STORAGE_ACCOUNT_NAME:0:24}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')

echo "=========================================="
echo "Deployment Configuration:"
echo "Resource Group: $RESOURCE_GROUP"
echo "Container App Location: $CONTAINERAPP_LOCATION"
echo "Storage Location: $STORAGE_LOCATION"
echo "Docker Image: $DOCKER_IMAGE"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "=========================================="

# Step 1: Create Resource Group
echo "[1/5] Creating resource group..."
az group create --name $RESOURCE_GROUP --location $CONTAINERAPP_LOCATION --output none

# Step 2: Deploy Container App
echo "[2/5] Deploying Container App with managed identity..."
az deployment group create \
  --name "${DEPLOYMENT_NAME}-containerapp" \
  --resource-group $RESOURCE_GROUP \
  --template-file templates/containerapp-deploy.json \
  --parameters \
    resourceGroupName=$RESOURCE_GROUP \
    location=$CONTAINERAPP_LOCATION \
    dockerImage=$DOCKER_IMAGE \
  --output none

# Get outputs
MANAGED_IDENTITY_PRINCIPAL_ID=$(az deployment group show \
  --name "${DEPLOYMENT_NAME}-containerapp" \
  --resource-group $RESOURCE_GROUP \
  --query properties.outputs.managedIdentityPrincipalId.value -o tsv)

CONTAINER_APP_OUTBOUND_IP=$(az deployment group show \
  --name "${DEPLOYMENT_NAME}-containerapp" \
  --resource-group $RESOURCE_GROUP \
  --query properties.outputs.containerAppOutboundIp.value -o tsv)

CONTAINER_APP_ENV_NAME=$(az deployment group show \
  --name "${DEPLOYMENT_NAME}-containerapp" \
  --resource-group $RESOURCE_GROUP \
  --query properties.outputs.containerAppEnvName.value -o tsv)

echo "  ✓ Container App deployed"
echo "  ✓ Outbound IP: $CONTAINER_APP_OUTBOUND_IP"
echo "  ✓ Managed Identity ID: $MANAGED_IDENTITY_PRINCIPAL_ID"

# Step 3: Deploy Storage Account
echo "[3/5] Deploying Storage Account with IP whitelist..."
MY_IP=$(curl -s ifconfig.me)

az deployment group create \
  --name "${DEPLOYMENT_NAME}-storage" \
  --resource-group $RESOURCE_GROUP \
  --template-file templates/storage-deploy.json \
  --parameters \
    storageAccountName=$STORAGE_ACCOUNT_NAME \
    location=$STORAGE_LOCATION \
    fileShareName=$FILE_SHARE_NAME \
    containerAppOutboundIp=$CONTAINER_APP_OUTBOUND_IP \
    managedIdentityPrincipalId=$MANAGED_IDENTITY_PRINCIPAL_ID \
    currentUserIp=$MY_IP \
  --output none

STORAGE_KEY=$(az deployment group show \
  --name "${DEPLOYMENT_NAME}-storage" \
  --resource-group $RESOURCE_GROUP \
  --query properties.outputs.storageAccountKey.value -o tsv)

echo "  ✓ Storage Account deployed"
echo "  ✓ File share created"
echo "  ✓ IPs whitelisted: $CONTAINER_APP_OUTBOUND_IP, $MY_IP"

# Step 4: Configure Environment Storage
echo "[4/5] Configuring storage in Container Apps environment..."
az containerapp env storage set \
  --name $CONTAINER_APP_ENV_NAME \
  --resource-group $RESOURCE_GROUP \
  --storage-name appstorage \
  --azure-file-account-name $STORAGE_ACCOUNT_NAME \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name $FILE_SHARE_NAME \
  --access-mode ReadWrite \
  --output none

echo "  ✓ Storage configured"

# Step 5: Redeploy Container App with Storage
echo "[5/5] Redeploying Container App with mounted storage..."
az deployment group create \
  --name "${DEPLOYMENT_NAME}-final" \
  --resource-group $RESOURCE_GROUP \
  --template-file templates/containerapp-with-storage.json \
  --parameters \
    resourceGroupName=$RESOURCE_GROUP \
    location=$CONTAINERAPP_LOCATION \
    dockerImage=$DOCKER_IMAGE \
    storageAccountName=$STORAGE_ACCOUNT_NAME \
    fileShareName=$FILE_SHARE_NAME \
  --output none

FINAL_URL=$(az deployment group show \
  --name "${DEPLOYMENT_NAME}-final" \
  --resource-group $RESOURCE_GROUP \
  --query properties.outputs.containerAppUrl.value -o tsv)

echo "  ✓ Container App redeployed with storage"

# Save deployment info
echo "$RESOURCE_GROUP" > .last-deployment
echo "$CONTAINER_APP_NAME" >> .last-deployment
echo "$STORAGE_ACCOUNT_NAME" >> .last-deployment

# Verification
echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo "Container App URL: $FINAL_URL"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "File Share: $FILE_SHARE_NAME"
echo "Mount Path: /mnt/storage"
echo ""
echo "To verify the deployment:"
echo "  ./scripts/verify-deployment.sh $RESOURCE_GROUP"
echo ""
echo "To cleanup resources:"
echo "  ./scripts/cleanup.sh $RESOURCE_GROUP"
