#!/bin/bash

# Cleanup Script for Azure Passwordless PostgreSQL Sample
# This script deletes all Azure resources created for the application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables if available
if [ -f "$(dirname "$0")/00-set-env.sh" ]; then
    source "$(dirname "$0")/00-set-env.sh"
else
    # Default values if env file doesn't exist
    export RG="rg-pwless-sample"
fi

echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}  Azure Passwordless PostgreSQL - Cleanup${NC}"
echo -e "${YELLOW}================================================${NC}"
echo ""

# Function to list resources
list_resources() {
    echo -e "${GREEN}Listing resources in resource group: ${RG}${NC}"
    echo ""

    if az group exists --name "$RG" --output tsv | grep -q "true"; then
        echo "Web Apps:"
        az webapp list --resource-group "$RG" --query "[].{Name:name, State:state}" -o table
        echo ""

        echo "PostgreSQL Servers:"
        az postgres flexible-server list --resource-group "$RG" --query "[].{Name:name, State:state}" -o table
        echo ""

        echo "Managed Identities:"
        az identity list --resource-group "$RG" --query "[].{Name:name, PrincipalId:principalId}" -o table
        echo ""

        echo "App Service Plans:"
        az appservice plan list --resource-group "$RG" --query "[].{Name:name, Sku:sku.name}" -o table
        echo ""

        echo "All Resources:"
        az resource list --resource-group "$RG" --query "[].{Name:name, Type:type}" -o table
        echo ""
    else
        echo -e "${YELLOW}Resource group '${RG}' does not exist.${NC}"
        exit 0
    fi
}

# Function to delete resource group
delete_resource_group() {
    echo -e "${RED}WARNING: This will delete the entire resource group and ALL resources within it!${NC}"
    echo -e "${RED}Resource Group: ${RG}${NC}"
    echo ""

    read -p "Are you sure you want to proceed? (yes/no): " confirmation

    if [ "$confirmation" != "yes" ]; then
        echo -e "${YELLOW}Cleanup cancelled.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${GREEN}Deleting resource group: ${RG}...${NC}"
    echo "This may take several minutes..."

    if az group delete --name "$RG" --yes --no-wait; then
        echo -e "${GREEN}✓ Resource group deletion initiated successfully.${NC}"
        echo -e "${YELLOW}Note: Deletion is running in the background. It may take 5-10 minutes to complete.${NC}"
        echo ""
        echo "To check deletion status, run:"
        echo "  az group exists --name $RG"
    else
        echo -e "${RED}✗ Failed to delete resource group.${NC}"
        exit 1
    fi
}

# Function to delete specific resources (selective cleanup)
selective_cleanup() {
    echo -e "${YELLOW}Selective Cleanup Options:${NC}"
    echo "1. Delete Web App only"
    echo "2. Delete PostgreSQL Server only"
    echo "3. Delete Jump VM only (recommended to reduce costs)"
    echo "4. Delete Managed Identity only"
    echo "5. Delete everything (entire resource group)"
    echo "6. Cancel"
    echo ""
    read -p "Select option (1-6): " option

    case $option in
        1)
            APP_NAME=$(az webapp list --resource-group "$RG" --query "[0].name" -o tsv)
            if [ -n "$APP_NAME" ]; then
                echo -e "${GREEN}Deleting Web App: ${APP_NAME}...${NC}"
                az webapp delete --name "$APP_NAME" --resource-group "$RG"
                echo -e "${GREEN}✓ Web App deleted.${NC}"
            else
                echo -e "${YELLOW}No Web App found.${NC}"
            fi
            ;;
        2)
            PG_SERVER=$(az postgres flexible-server list --resource-group "$RG" --query "[0].name" -o tsv)
            if [ -n "$PG_SERVER" ]; then
                echo -e "${GREEN}Deleting PostgreSQL Server: ${PG_SERVER}...${NC}"
                az postgres flexible-server delete --name "$PG_SERVER" --resource-group "$RG" --yes
                echo -e "${GREEN}✓ PostgreSQL Server deleted.${NC}"
            else
                echo -e "${YELLOW}No PostgreSQL Server found.${NC}"
            fi
            ;;
        3)
            echo -e "${GREEN}Deleting Jump VM and associated resources...${NC}"

            # Delete VM
            VM_EXISTS=$(az vm list --resource-group "$RG" --query "[?name=='jumpbox'].name" -o tsv)
            if [ -n "$VM_EXISTS" ]; then
                echo "  Deleting VM: jumpbox..."
                az vm delete -g "$RG" -n jumpbox --yes --no-wait
            fi

            # Delete Public IP
            JUMPBOX_IP_NAME=$(az network public-ip list -g "$RG" --query "[?contains(name, 'jumpbox')].name" -o tsv)
            if [ -n "$JUMPBOX_IP_NAME" ]; then
                echo "  Deleting Public IP: $JUMPBOX_IP_NAME..."
                az network public-ip delete -g "$RG" -n "$JUMPBOX_IP_NAME" --no-wait
            fi

            # Delete NIC
            JUMPBOX_NIC_NAME=$(az network nic list -g "$RG" --query "[?contains(name, 'jumpbox')].name" -o tsv)
            if [ -n "$JUMPBOX_NIC_NAME" ]; then
                echo "  Deleting NIC: $JUMPBOX_NIC_NAME..."
                az network nic delete -g "$RG" -n "$JUMPBOX_NIC_NAME" --no-wait
            fi

            # Delete NSG if exists
            JUMPBOX_NSG=$(az network nsg list -g "$RG" --query "[?contains(name, 'jumpbox')].name" -o tsv)
            if [ -n "$JUMPBOX_NSG" ]; then
                echo "  Deleting NSG: $JUMPBOX_NSG..."
                az network nsg delete -g "$RG" -n "$JUMPBOX_NSG" --no-wait
            fi

            echo -e "${GREEN}✓ Jump VM deletion initiated (running in background).${NC}"
            echo -e "${YELLOW}Note: Resources are being deleted in the background.${NC}"
            ;;
        4)
            IDENTITY_NAME=$(az identity list --resource-group "$RG" --query "[0].name" -o tsv)
            if [ -n "$IDENTITY_NAME" ]; then
                echo -e "${GREEN}Deleting Managed Identity: ${IDENTITY_NAME}...${NC}"
                az identity delete --name "$IDENTITY_NAME" --resource-group "$RG"
                echo -e "${GREEN}✓ Managed Identity deleted.${NC}"
            else
                echo -e "${YELLOW}No Managed Identity found.${NC}"
            fi
            ;;
        5)
            delete_resource_group
            ;;
        6)
            echo -e "${YELLOW}Cleanup cancelled.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            exit 1
            ;;
    esac
}

# Main menu
echo "What would you like to do?"
echo "1. List all resources (view what will be deleted)"
echo "2. Delete everything (entire resource group)"
echo "3. Selective cleanup (delete specific resources)"
echo "4. Exit"
echo ""
read -p "Select option (1-4): " main_option

case $main_option in
    1)
        list_resources
        echo ""
        echo "Run this script again to perform cleanup."
        ;;
    2)
        list_resources
        echo ""
        delete_resource_group
        ;;
    3)
        list_resources
        echo ""
        selective_cleanup
        ;;
    4)
        echo -e "${YELLOW}Exiting without making changes.${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid option.${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Cleanup script completed.${NC}"
