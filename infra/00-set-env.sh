#!/bin/bash

# Azure Infrastructure Setup Variables
# This script sets up environment variables for deploying the Spring Boot application

echo "Setting up environment variables..."

export RG="rg-pwless-sample"
export LOCATION="southeastasia"
export VNET="vnet-app"
export APP_SUBNET="snet-app"
export PE_SUBNET="snet-privatelink"
export JU_SUBNET="ju-subnet"
export DNSZONE="privatelink.postgres.database.azure.com"
export POSTGRES_SERVER="pg-flex-sample-$(date +%s)"
export POSTGRES_VERSION="16"
export POSTGRES_SKU="Standard_B1ms"
export DB_TIER="Burstable"
export DB_NAME="appdb"
export PG_ADMIN_UPN="Srinivas_Boini@epam.com"
export PG_ADMIN="pgadmin"
export TEMP_ADMIN_PASS="TempP@ssw0rd123!"
export UAMI_NAME="myAppUami"
export APP_PLAN="asp-pwless"
export APP_NAME="pwless-sample-$(date +%s)"