#!/bin/bash

# Script: verify-deployment.sh
# Description: Verify Container App deployment and storage mount
# Author: groovy-sky
# Date: 2025-01-13

RESOURCE_GROUP="${1:-rg-containerapp-storage}"

# Load environment if exists
if [ -f ".env" ]; then
    source .env
fi

# Generate names from resource group if not loaded
CONTAINERAPP_NAME="${CONTAINERAPP_NAME:-ca-${RESOURCE_GROUP}}"
CONTAINERAPP_ENV_NAME="${CONTAINERAPP_ENV_NAME:-cae-${RESOURCE_GROUP}}"

echo "=========================================="
echo "Verifying Deployment for: $RESOURCE_GROUP"
echo "=========================================="

# Check if resource group exists
echo -n "Checking resource group... "
if az group show --name $RESOURCE_GROUP &>/dev/null; then
    echo "✓ Found"
else
    echo "✗ Not found"
    exit 1
fi

# Check Container App
echo -n "Checking Container App... "
STATUS=$(az containerapp show \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.runningStatus" -o tsv 2>/dev/null)

if [ "$STATUS" == "Running" ]; then
    echo "✓ Running"
else
    echo "✗ Status: $STATUS"
fi

# Get Container App URL
FQDN=$(az containerapp show \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null)

if [ ! -z "$FQDN" ]; then
    echo "Container App URL: https://$FQDN"
fi

# Check storage mount
echo -n "Checking storage mount... "
MOUNT_CHECK=$(az containerapp exec \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --command "df -h | grep storage" 2>/dev/null)

if [ ! -z "$MOUNT_CHECK" ]; then
    echo "✓ Mounted"
    echo "Mount details: $MOUNT_CHECK"
else
    echo "✗ Not mounted"
fi

# Check if mount status file exists
echo -n "Checking mount status file... "
STATUS_FILE=$(az containerapp exec \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --command "cat /mnt/storage/mount-status.txt" 2>/dev/null)

if [ ! -z "$STATUS_FILE" ]; then
    echo "✓ Found"
    echo "Content: $STATUS_FILE"
else
    echo "✗ Not found"
fi

# Write test file
echo ""
echo "Writing test file..."
TEST_MESSAGE="Test from verification script at $(date)"
az containerapp exec \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --command "echo '$TEST_MESSAGE' >> /mnt/storage/verify-test.log" 2>/dev/null

# Read test file
echo "Reading test file..."
TEST_CONTENT=$(az containerapp exec \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --command "cat /mnt/storage/verify-test.log | tail -1" 2>/dev/null)

if [ "$TEST_CONTENT" == "$TEST_MESSAGE" ]; then
    echo "✓ Read/Write verification successful"
else
    echo "✗ Read/Write verification failed"
fi

# List files in storage
echo ""
echo "Files in /mnt/storage:"
az containerapp exec \
    --name $CONTAINERAPP_NAME \
    --resource-group $RESOURCE_GROUP \
    --command "ls -la /mnt/storage/" 2>/dev/null

# Check storage account
echo ""
echo -n "Checking storage account... "
STORAGE_ACCOUNTS=$(az storage account list \
    --resource-group $RESOURCE_GROUP \
    --query "[].name" -o tsv 2>/dev/null)

if [ ! -z "$STORAGE_ACCOUNTS" ]; then
    echo "✓ Found"
    echo "Storage accounts: $STORAGE_ACCOUNTS"
else
    echo "✗ Not found"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="