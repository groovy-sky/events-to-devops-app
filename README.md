# Container App with Storage Account Deployment

This solution deploys an Azure Container App with managed identity in one region and a storage account with file share in another region, with IP-restricted access.

## Prerequisites

- Azure CLI version 2.53.0 or later
- An active Azure subscription
- Bash shell (Linux/Mac/WSL)

## Quick Start

```bash
# Make scripts executable
chmod +x deploy.sh scripts/*.sh

# Run deployment with defaults
./deploy.sh

# Or with custom parameters
./deploy.sh "my-rg" "eastus" "westus" "nginx:alpine"
```

## Architecture

1. **Container App** - Deployed in primary region with managed identity
2. **Storage Account** - Deployed in secondary region with IP restrictions
3. **File Share** - Mounted to Container App at `/mnt/storage`

## Files Description

- `deploy.sh` - Main deployment script
- `templates/containerapp-deploy.json` - ARM template for initial Container App
- `templates/storage-deploy.json` - ARM template for Storage Account with IP whitelist
- `templates/containerapp-with-storage.json` - ARM template for Container App with mounted storage
- `scripts/set-variables.sh` - Variable configuration script
- `scripts/verify-deployment.sh` - Deployment verification script
- `scripts/cleanup.sh` - Resource cleanup script

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Resource Group | rg-containerapp-storage | Resource group name |
| Container App Location | eastus | Primary region for Container App |
| Storage Location | westus | Secondary region for Storage Account |
| Docker Image | nginx:latest | Docker image to deploy |

## Verification

After deployment, verify the setup:

```bash
./scripts/verify-deployment.sh <resource-group-name>
```

## Cleanup

To remove all resources:

```bash
./scripts/cleanup.sh <resource-group-name>
```

## Author

Created by groovy-sky