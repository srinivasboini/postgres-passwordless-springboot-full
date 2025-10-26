#!/bin/bash
# Usage: ./create_pg_ad_principal.sh <RG> <POSTGRES_SERVER> <PG_ADMIN_UPN> <PRINCIPAL_NAME>
RG=$1
POSTGRES_SERVER=$2
PG_ADMIN_UPN=$3
PRINCIPAL_NAME=$4

ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)

echo "Creating AD principal inside PostgreSQL: $PRINCIPAL_NAME"

psql "host=${POSTGRES_SERVER}.postgres.database.azure.com port=5432 dbname=postgres user=${PG_ADMIN_UPN}@${POSTGRES_SERVER} password=${ACCESS_TOKEN} sslmode=require" -c "SELECT * FROM pgaadauth_create_principal('${PRINCIPAL_NAME}', false, false);"
