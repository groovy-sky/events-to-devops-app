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
        echo "Usage: $0 <resource-group-name> [location]"
        exit 1
    fi
    
    RESOURCE_GROUP=$1
    LOCATION=${2:-"eastus"}
    CURRENT_IP=$(get_current_ip)
    
    print_message "$YELLOW" "Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Current IP: ${CURRENT_IP:-Not detected}"
    
    # Create resource group if it doesn't exist
    if ! check_resource_group "$RESOURCE_GROUP"; then
        print_message "$YELLOW" "Creating resource group..."
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        print_message "$GREEN" "Resource group created successfully"
    else
        print_message "$YELLOW" "Resource group already exists"
    fi
    
    # Deploy Container App Environment
    print_message "$YELLOW" "Deploying Container App Environment..."
    ENVIRONMENT_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "templates/container-app-env-deploy.json" \
        --parameters location="$LOCATION" \
        --query properties.outputs \
        --output json)
    
    ENVIRONMENT_NAME=$(echo "$ENVIRONMENT_OUTPUT" | jq -r '.environmentName.value')
    ENVIRONMENT_ID=$(echo "$ENVIRONMENT_OUTPUT" | jq -r '.environmentId.value')
    OUTBOUND_IP=$(echo "$ENVIRONMENT_OUTPUT" | jq -r '.outboundIp.value')
    
    print_message "$GREEN" "Container App Environment deployed successfully"
    echo "  Environment Name: $ENVIRONMENT_NAME"
    echo "  Outbound IP: $OUTBOUND_IP"
    
    # Deploy Container App
    print_message "$YELLOW" "Deploying Container App..."
    APP_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "templates/container-app-deploy.json" \
        --parameters \
            location="$LOCATION" \
            environmentId="$ENVIRONMENT_ID" \
        --query properties.outputs \
        --output json)
    
    APP_NAME=$(echo "$APP_OUTPUT" | jq -r '.appName.value')
    APP_URL=$(echo "$APP_OUTPUT" | jq -r '.appUrl.value')
    IDENTITY_ID=$(echo "$APP_OUTPUT" | jq -r '.managedIdentityPrincipalId.value')
    
    print_message "$GREEN" "Container App deployed successfully"
    echo "  App Name: $APP_NAME"
    echo "  App URL: $APP_URL"
    
    # Deploy Storage Account
    print_message "$YELLOW" "Deploying Storage Account..."
    STORAGE_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "templates/storage-deploy.json" \
        --parameters \
            location="$LOCATION" \
            containerAppOutboundIp="$OUTBOUND_IP" \
            managedIdentityPrincipalId="$IDENTITY_ID" \
            currentUserIp="${CURRENT_IP}" \
        --query properties.outputs \
        --output json)
    
    STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_OUTPUT" | jq -r '.storageAccountName.value')
    FILE_SHARE_NAME=$(echo "$STORAGE_OUTPUT" | jq -r '.fileShareName.value')
    
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
    
    # Update Container App with storage mount
    print_message "$YELLOW" "Updating Container App with storage mount..."
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --set-env-vars \
            STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME" \
            FILE_SHARE_NAME="$FILE_SHARE_NAME" \
        --query properties.configuration.ingress.fqdn \
        --output tsv > /dev/null
    
    # Create storage mount
    az containerapp env storage set \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-name "appstorage" \
        --azure-file-account-name "$STORAGE_ACCOUNT_NAME" \
        --azure-file-account-key "$STORAGE_KEY" \
        --azure-file-share-name "$FILE_SHARE_NAME" \
        --access-mode ReadWrite || true
    
    print_message "$GREEN" "Storage mount configured successfully"
    
    # Deploy Azure DevOps Integration (if template exists)
    if [ -f "templates/devops-integration-deploy.json" ]; then
        print_message "$YELLOW" "Deploying Azure DevOps Integration..."
        az deployment group create \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "templates/devops-integration-deploy.json" \
            --parameters \
                location="$LOCATION" \
                containerAppName="$APP_NAME" \
                storageAccountName="$STORAGE_ACCOUNT_NAME"
        print_message "$GREEN" "Azure DevOps Integration deployed successfully"
    fi
    
    # Final summary
    print_message "$GREEN" "\n=== Deployment Complete ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Container App URL: https://$APP_URL"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "File Share: $FILE_SHARE_NAME"
    echo ""
    print_message "$YELLOW" "Next steps:"
    echo "1. Access your app at: https://$APP_URL"
    echo "2. Configure Azure DevOps webhooks to point to your app"
    echo "3. Monitor logs in the $FILE_SHARE_NAME file share"
}

# Run main function
main "$@"
