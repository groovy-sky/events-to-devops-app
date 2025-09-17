#!/bin/bash

# Script: deploy.sh
# Description: Deploy Azure resources for events-to-devops-app
# Author: groovy-sky

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if resource group exists
check_resource_group() {
    local rg_name=$1
    az group show --name "$rg_name" &>/dev/null
}

# Function to get current user's public IP
get_current_ip() {
    curl -s https://api.ipify.org || echo ""
}

# Main deployment
main() {
    print_message "$GREEN" "Starting Azure deployment for events-to-devops-app..."
    
    # Check for required parameters
    if [ -z "$1" ]; then
        print_message "$RED" "Error: Resource group name is required"
        echo "Usage: $0 <resource-group-name> [location] [environment-location]"
        exit 1
    fi
    
    RESOURCE_GROUP=$1
    LOCATION=${2:-"eastus"}
    ENVIRONMENT_LOCATION=${3:-$LOCATION}  # Allow separate environment location
    CURRENT_IP=$(get_current_ip)
    
    # Default values for Container App
    DOCKER_IMAGE="${DOCKER_IMAGE:-mcr.microsoft.com/azuredocs/containerapps-helloworld:latest}"
    
    print_message "$YELLOW" "Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Environment Location: $ENVIRONMENT_LOCATION"
    echo "  Docker Image: $DOCKER_IMAGE"
    echo "  Current IP: ${CURRENT_IP:-Not detected}"
    
    # Create resource group if it doesn't exist
    if ! check_resource_group "$RESOURCE_GROUP"; then
        print_message "$YELLOW" "Creating resource group..."
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        print_message "$GREEN" "Resource group created successfully"
    else
        print_message "$YELLOW" "Resource group already exists"
    fi
    
    # Deploy Container App (initial deployment without storage)
    print_message "$YELLOW" "Deploying Container App and Environment..."
    
    # First, run the deployment and capture the full output
    # The template only accepts: currentTime, dockerImage, location, resourceGroupName
    DEPLOYMENT_NAME="containerapp-$(date +%s)"
    CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    az deployment group create \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "templates/containerapp-deploy.json" \
        --parameters \
            location="$ENVIRONMENT_LOCATION" \
            resourceGroupName="$RESOURCE_GROUP" \
            dockerImage="$DOCKER_IMAGE" \
            currentTime="$CURRENT_TIME" \
        --output none
    
    # Then query the deployment outputs separately
    APP_OUTPUT=$(az deployment group show \
        --name "$DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs \
        --output json)
    
    # Parse the outputs
    APP_NAME=$(echo "$APP_OUTPUT" | jq -r '.appName.value // empty')
    APP_URL=$(echo "$APP_OUTPUT" | jq -r '.appUrl.value // empty')
    IDENTITY_ID=$(echo "$APP_OUTPUT" | jq -r '.managedIdentityPrincipalId.value // empty')
    ENVIRONMENT_NAME=$(echo "$APP_OUTPUT" | jq -r '.environmentName.value // empty')
    ENVIRONMENT_ID=$(echo "$APP_OUTPUT" | jq -r '.environmentId.value // empty')
    OUTBOUND_IP=$(echo "$APP_OUTPUT" | jq -r '.outboundIp.value // empty')
    
    # Validate required outputs
    if [ -z "$APP_NAME" ] || [ -z "$ENVIRONMENT_ID" ]; then
        print_message "$RED" "Error: Failed to get required outputs from Container App deployment"
        echo "Deployment outputs:"
        echo "$APP_OUTPUT"
        exit 1
    fi
    
    print_message "$GREEN" "Container App and Environment deployed successfully"
    echo "  App Name: $APP_NAME"
    echo "  App URL: $APP_URL"
    echo "  Environment Name: $ENVIRONMENT_NAME"
    echo "  Outbound IP: $OUTBOUND_IP"
    
    # Deploy Storage Account
    print_message "$YELLOW" "Deploying Storage Account..."
    
    # Generate unique storage account name (must be lowercase, no hyphens, max 24 chars)
    UNIQUE_SUFFIX=$(date +%s | tail -c 6)
    STORAGE_ACCOUNT_NAME="eventstorage${UNIQUE_SUFFIX}"
    
    # Run storage deployment
    STORAGE_DEPLOYMENT_NAME="storage-$(date +%s)"
    az deployment group create \
        --name "$STORAGE_DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "templates/storage-deploy.json" \
        --parameters \
            location="$ENVIRONMENT_LOCATION" \
            containerAppOutboundIp="$OUTBOUND_IP" \
            managedIdentityPrincipalId="$IDENTITY_ID" \
            currentUserIp="${CURRENT_IP}" \
            storageAccountName="$STORAGE_ACCOUNT_NAME" \
        --output none
    
    # Query storage deployment outputs
    STORAGE_OUTPUT=$(az deployment group show \
        --name "$STORAGE_DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs \
        --output json)
    
    STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_OUTPUT" | jq -r '.storageAccountName.value // empty')
    FILE_SHARE_NAME=$(echo "$STORAGE_OUTPUT" | jq -r '.fileShareName.value // empty')
    
    # Validate storage outputs
    if [ -z "$STORAGE_ACCOUNT_NAME" ] || [ -z "$FILE_SHARE_NAME" ]; then
        print_message "$RED" "Error: Failed to get required outputs from Storage deployment"
        echo "Storage outputs:"
        echo "$STORAGE_OUTPUT"
        exit 1
    fi
    
    print_message "$GREEN" "Storage Account deployed successfully"
    echo "  Storage Account Name: $STORAGE_ACCOUNT_NAME"
    echo "  File Share Name: $FILE_SHARE_NAME"
    
    # Get storage account key for mounting
    print_message "$YELLOW" "Retrieving storage account key..."
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query "[0].value" \
        --output tsv)
    
    if [ -z "$STORAGE_KEY" ]; then
        print_message "$RED" "Error: Failed to retrieve storage account key"
        exit 1
    fi
    
    # Update Container App with storage configuration using the containerapp-with-storage template
    print_message "$YELLOW" "Updating Container App with storage configuration..."
    
    UPDATE_DEPLOYMENT_NAME="update-$(date +%s)"
    az deployment group create \
        --name "$UPDATE_DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "templates/containerapp-with-storage.json" \
        --parameters \
            location="$ENVIRONMENT_LOCATION" \
            environmentId="$ENVIRONMENT_ID" \
            storageAccountName="$STORAGE_ACCOUNT_NAME" \
            storageAccountKey="$STORAGE_KEY" \
            fileShareName="$FILE_SHARE_NAME" \
            appName="$APP_NAME" \
            dockerImage="$DOCKER_IMAGE" \
        --output none
    
    # Query update deployment outputs
    UPDATE_OUTPUT=$(az deployment group show \
        --name "$UPDATE_DEPLOYMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.outputs \
        --output json 2>/dev/null || echo "{}")
    
    # Extract updated values if available
    if [ ! -z "$UPDATE_OUTPUT" ] && [ "$UPDATE_OUTPUT" != "{}" ]; then
        UPDATED_APP_URL=$(echo "$UPDATE_OUTPUT" | jq -r '.appUrl.value // empty')
        if [ -z "$UPDATED_APP_URL" ]; then
            UPDATED_APP_URL="$APP_URL"
        fi
    else
        UPDATED_APP_URL="$APP_URL"
    fi
    
    print_message "$GREEN" "Container App updated with storage mount successfully"
    
    # Set environment variables on the Container App
    print_message "$YELLOW" "Setting environment variables on Container App..."
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --set-env-vars \
            STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME" \
            FILE_SHARE_NAME="$FILE_SHARE_NAME" \
        --output none 2>/dev/null || {
            print_message "$YELLOW" "Warning: Could not set environment variables (may already be set)"
        }
    
    print_message "$GREEN" "Environment variables configured"
    
    # Deploy Azure DevOps Integration (if template exists)
    if [ -f "templates/devops-integration-deploy.json" ]; then
        print_message "$YELLOW" "Deploying Azure DevOps Integration..."
        az deployment group create \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "templates/devops-integration-deploy.json" \
            --parameters \
                location="$ENVIRONMENT_LOCATION" \
                containerAppName="$APP_NAME" \
                storageAccountName="$STORAGE_ACCOUNT_NAME" \
            --output none
        print_message "$GREEN" "Azure DevOps Integration deployed successfully"
    fi
    
    # Final summary
    print_message "$GREEN" "\n=== Deployment Complete ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Container App URL: https://$UPDATED_APP_URL"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "File Share: $FILE_SHARE_NAME"
    echo "Environment: $ENVIRONMENT_NAME"
    echo ""
    print_message "$YELLOW" "Next steps:"
    echo "1. Access your app at: https://$UPDATED_APP_URL"
    echo "2. Configure Azure DevOps webhooks to point to your app"
    echo "3. Monitor logs in the $FILE_SHARE_NAME file share"
    echo ""
    print_message "$YELLOW" "To view logs:"
    echo "az containerapp logs show --name $APP_NAME --resource-group $RESOURCE_GROUP --follow"
}

# Run main function
main "$@"
