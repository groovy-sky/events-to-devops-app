#!/bin/bash

# Script: cleanup.sh
# Description: Clean up deployed resources
# Author: groovy-sky
# Date: 2025-01-13

RESOURCE_GROUP="${1}"

if [ -z "$RESOURCE_GROUP" ]; then
    if [ -f ".last-deployment" ]; then
        RESOURCE_GROUP=$(head -n 1 .last-deployment)
        echo "Using resource group from last deployment: $RESOURCE_GROUP"
    else
        echo "Error: Resource group name required"
        echo "Usage: $0 <resource-group-name>"
        exit 1
    fi
fi

echo "=========================================="
echo "Resource Cleanup"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo ""
echo "This will DELETE all resources in the resource group."
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."

# Delete resource group
echo "Deleting resource group: $RESOURCE_GROUP"
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait

echo ""
echo "Cleanup initiated. Resources are being deleted in the background."
echo "This may take several minutes to complete."
echo ""
echo "To check deletion status:"
echo "  az group show --name $RESOURCE_GROUP"

# Clean up local files
if [ -f ".last-deployment" ]; then
    rm .last-deployment
    echo "Removed .last-deployment file"
fi

if [ -f ".env" ]; then
    rm .env
    echo "Removed .env file"
fi

echo ""
echo "Local cleanup complete."