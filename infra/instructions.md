# Full provisioning and deployment instructions (copy-paste)

This file contains step-by-step Azure CLI commands and guidance to provision infrastructure, configure passwordless PostgreSQL access, deploy the Spring Boot 3.4 + Java 21 app to App Service, and verify.

**⚠️ CRITICAL:** Step 3 includes creating a **DNS Zone Group** for the private endpoint. This is mandatory for DNS resolution to work. Without it, your app will fail to connect to PostgreSQL.

Before you start:
- Install Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli
- Install psql (Postgres client) locally.
- Login: `az login`
- Set subscription if needed: `az account set --subscription "<YOUR_SUBSCRIPTION_ID>"`

Update these variables for your environment (choose region and names):

```bash
export RG="rg-pwless-sample"
export LOCATION="southeastasia"
export VNET="vnet-app"
export APP_SUBNET="snet-app"
export DNSZONE="privatelink.postgres.database.azure.com"
export PE_SUBNET="snet-privatelink"
export JU_SUBNET="ju-subnet"
export POSTGRES_SERVER="pg-flex-sample-$(date +%s)"
export POSTGRES_VERSION="14"
export POSTGRES_SKU="Standard_B1ms"
export DB_NAME="appdb"
export PG_ADMIN_UPN="Srinivas_Boini@epam.com"
export UAMI_NAME="myAppUami"
export APP_PLAN="asp-pwless"
export APP_NAME="pwless-sample-$(date +%s)"
```

---

1) Create resource group, VNet, and subnets

```bash
az group create -n $RG -l $LOCATION

az network vnet create -g $RG -n $VNET --address-prefix 10.1.0.0/16   --subnet-name $APP_SUBNET --subnet-prefix 10.1.0.0/24

az network vnet subnet create -g $RG --vnet-name $VNET -n $PE_SUBNET --address-prefix 10.1.1.0/24
```

2) Create private DNS zone and link to VNet

```bash
DNSZONE="privatelink.postgres.database.azure.com"
az network private-dns zone create -g $RG -n $DNSZONE
az network private-dns link vnet create -g $RG -n link-$VNET --zone-name $DNSZONE --virtual-network $VNET --registration-enabled false
```

3) Create PostgreSQL Flexible Server (public access disabled) and Private Endpoint

```bash
az postgres flexible-server create -g $RG -n $POSTGRES_SERVER   --admin-user $PG_ADMIN --admin-password $TEMP_ADMIN_PASS   --location $LOCATION --sku-name $POSTGRES_SKU --tier Burstable --version $POSTGRES_VERSION   --public-access none
```

Create Private Endpoint:

```bash
az network private-endpoint create -g $RG -n pe-$POSTGRES_SERVER   --vnet-name $VNET --subnet $PE_SUBNET   --private-connection-resource-id $(az postgres flexible-server show -g $RG -n $POSTGRES_SERVER --query id -o tsv)   --group-ids postgresqlServer   --connection-name pe-conn-$POSTGRES_SERVER
```

**IMPORTANT:** Create DNS Zone Group to automatically register A record in Private DNS Zone:

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az network private-endpoint dns-zone-group create \
  --endpoint-name pe-$POSTGRES_SERVER \
  --resource-group $RG \
  --name default \
  --private-dns-zone "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Network/privateDnsZones/$DNSZONE" \
  --zone-name privatelink-postgres-database-azure-com
```

This automatically creates the A record for `$POSTGRES_SERVER.postgres.database.azure.com` pointing to the private endpoint IP.

Verify DNS resolution (should return private IP in 10.1.1.x range):

```bash
nslookup $POSTGRES_SERVER.postgres.database.azure.com
```

4) Enable Microsoft Entra authentication and configure admin for PostgreSQL server

First, enable Entra authentication on the server:

```bash
az postgres flexible-server update -g $RG -n $POSTGRES_SERVER --microsoft-entra-auth Enabled
```

Then get object id for your Entra admin user and create the admin:

```bash
ADMIN_OBJECT_ID=$(az ad user show --id $PG_ADMIN_UPN --query id -o tsv)
az postgres flexible-server microsoft-entra-admin create -g $RG -s $POSTGRES_SERVER -u $PG_ADMIN_UPN -i $ADMIN_OBJECT_ID

az postgres flexible-server restart -g  $RG -n $POSTGRES_SERVER

# Wait 5 minutes
echo "Waiting 5 minutes..."
sleep 300

```

5) Create database

```bash
az postgres flexible-server db create -g $RG -s $POSTGRES_SERVER -d $DB_NAME


-- Create the managed identity user for your application
SELECT * FROM pgaadauth_create_principal('myAppUami', false, false);

-- Grant permissions on the appdb database
GRANT ALL PRIVILEGES ON DATABASE appdb TO "myAppUami";

-- If appdb doesn't exist yet, create it
CREATE DATABASE IF NOT EXISTS appdb;

-- Connect to appdb
\c appdb

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO "myAppUami";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "myAppUami";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "myAppUami";

-- For future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "myAppUami";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "myAppUami";
```

6) Create User Assigned Managed Identity (UAMI)

```bash
az identity create -g $RG -n $UAMI_NAME
UAMI_CLIENT_ID=$(az identity show -g $RG -n $UAMI_NAME --query clientId -o tsv)
UAMI_PRINCIPAL_ID=$(az identity show -g $RG -n $UAMI_NAME --query principalId -o tsv)
echo "UAMI client id: $UAMI_CLIENT_ID"
```

7) Create App Service Plan and Web App (Linux - Java 21)

```bash
az appservice plan create -g $RG -n $APP_PLAN --is-linux --sku P1v2 -l $LOCATION

az webapp create -g $RG -p $APP_PLAN -n $APP_NAME --runtime "JAVA|21-java21"
```

8) Assign UAMI to Web App (User-Assigned Identity)

```bash
UAMI_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$UAMI_NAME"

az webapp identity assign -g $RG -n $APP_NAME --identities $UAMI_RESOURCE_ID
```

9) Configure VNet integration for the Web App (outbound to Private Endpoint)

```bash
SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name $VNET -n $APP_SUBNET --query id -o tsv)
az webapp vnet-integration add -g $RG -n $APP_NAME --vnet $VNET --subnet $APP_SUBNET
```

10) Create Jump VM for PostgreSQL Administration

Since PostgreSQL is private (no public access), you need a VM inside the VNet to run psql commands.

Create jump subnet:

```bash
az network vnet subnet create -g $RG --vnet-name $VNET -n $JU_SUBNET --address-prefix 10.1.2.0/24
```

Create Ubuntu VM in the jump subnet:

```bash
az vm create \
  -g $RG \
  -n jumpbox \
  --image Ubuntu2204 \
  --vnet-name $VNET \
  --subnet $JU_SUBNET \
  --admin-username azureuser \
  --generate-ssh-keys \
  --size Standard_B1s \
  --public-ip-sku Standard
```

Get the public IP and SSH into the VM:

```bash
JUMPBOX_IP=$(az vm show -g $RG -n jumpbox -d --query publicIps -o tsv)
echo "SSH to jumpbox: ssh azureuser@$JUMPBOX_IP"
ssh azureuser@$JUMPBOX_IP
```

Once connected to the jumpbox, install required tools:

```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install PostgreSQL client
sudo apt update && sudo apt install postgresql-client -y
```

Login to Azure from the jumpbox:

```bash
az login
```

Verify DNS resolution (should return private IP 10.1.1.x):

```bash
nslookup $POSTGRES_SERVER.postgres.database.azure.com
# Expected output:
# Server:         168.63.129.16  (Azure DNS)
# Address:        168.63.129.16#53
# Name:    pg-flex-sample-XXXXX.postgres.database.azure.com
# Address: 10.1.1.4  (private IP)
```

**Note:** Keep this SSH session open - you'll use it in the next step.

11) Create AAD-mapped Postgres DB principal for the UAMI and grant DB rights

From the **jumpbox SSH session**, get access token for oss-rdbms:

```bash
# Set environment variables (same as your local machine)
export POSTGRES_SERVER="pg-flex-sample-XXXXXXXXX"  # Use your actual server name
export RG="rg-pwless-sample"
export DB_NAME="appdb"
export PG_ADMIN_UPN="Srinivas_Boini@epam.com"

# Get access token
ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
```

Run psql to create the database principal for UAMI:

```bash
psql "host=${POSTGRES_SERVER}.postgres.database.azure.com port=5432 dbname=postgres user=${PG_ADMIN_UPN} password=${ACCESS_TOKEN} sslmode=require"   -c "SELECT * FROM pgaadauth_create_principal('myAppUami', false, false);"
```

Grant privileges on the application database:

```bash
psql "host=${POSTGRES_SERVER}.postgres.database.azure.com port=5432 dbname=${DB_NAME} user=${PG_ADMIN_UPN}@${POSTGRES_SERVER} password=${ACCESS_TOKEN} sslmode=require" \
  -c "GRANT CONNECT ON DATABASE ${DB_NAME} TO \"myAppUami\";
      GRANT USAGE ON SCHEMA public TO \"myAppUami\";
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"myAppUami\";
      GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"myAppUami\";
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"myAppUami\";
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"myAppUami\";"
```

**Success!** You should see output confirming the grants were applied. You can now exit the jumpbox or leave the session open for troubleshooting.

12) Configure App Settings (Environment Variables) on Web App

Set app settings so the app uses the UAMI and the DB:

```bash
az webapp config appsettings set \
  --resource-group $RG \
  --name $APP_NAME \
  --settings \
    AZURE_CLIENT_ID="$UAMI_CLIENT_ID" \
    SPRING_PROFILES_ACTIVE="prod" \
    SPRING_DATASOURCE_URL="jdbc:postgresql://${POSTGRES_SERVER}.postgres.database.azure.com:5432/${DB_NAME}?sslmode=require" \
    SPRING_DATASOURCE_USERNAME="myAppUami" \
    SPRING_CLOUD_AZURE_PROFILE_TENANT_ID="$(az account show --query tenantId -o tsv)" \
    SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED="true"
```

13) Initialize schema (create tables)

The application is configured with `spring.sql.init.mode=always`, which automatically runs `schema.sql` on startup. However, you can also initialize the schema manually from the jumpbox:

```bash
# From the jumpbox SSH session
ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)

psql "host=${POSTGRES_SERVER}.postgres.database.azure.com port=5432 dbname=${DB_NAME} user=${PG_ADMIN_UPN}@${POSTGRES_SERVER} password=${ACCESS_TOKEN} sslmode=require" \
  -c "CREATE TABLE IF NOT EXISTS users (
        id serial PRIMARY KEY,
        name varchar(100) NOT NULL,
        email varchar(200) UNIQUE NOT NULL
      );"
```

14) Build and Deploy the App

Build jar:

```bash
mvn -DskipTests package
```

Deploy to App Service (jar):

```bash
az webapp deploy --resource-group $RG --name $APP_NAME --type jar --src-path target/postgres-passwordless-sample-0.0.1-SNAPSHOT.jar
```

15) Validate

Test the application endpoints:

```bash
# Health check
curl https://$APP_NAME.azurewebsites.net/actuator/health

# List users (should return empty array initially)
curl https://$APP_NAME.azurewebsites.net/users

# Create a user
curl -X POST https://$APP_NAME.azurewebsites.net/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'

# List users again (should show the created user)
curl https://$APP_NAME.azurewebsites.net/users
```

Verify passwordless authentication in logs:

```bash
# Download logs
az webapp log download --name $APP_NAME --resource-group $RG --log-file app-logs.zip
unzip app-logs.zip

# Check for Managed Identity authentication
grep -i "Managed Identity" LogFiles/Application/*.log
# Should see: "User-assigned Managed Identity ID: <client-id>"
# Should see: "Azure Identity => Managed Identity environment: Managed Identity"
```

Optional: Verify DNS resolution from App Service Kudu console:
1. Go to `https://$APP_NAME.scm.azurewebsites.net`
2. Debug Console → CMD
3. Run: `nslookup $POSTGRES_SERVER.postgres.database.azure.com`
4. Should return private IP (10.1.1.x)

16) Cleanup (when done)

**Option 1: Delete everything** (recommended for demo/test environments):

```bash
# This deletes the entire resource group including:
# - PostgreSQL server and private endpoint
# - Web App and App Service Plan
# - Jump VM
# - VNet, subnets, and DNS zones
# - Managed Identity
az group delete -n $RG --yes --no-wait
```

**Option 2: Keep infrastructure, delete only the jump VM** (if you want to keep the app running):

```bash
# Delete only the jump VM to save costs
az vm delete -g $RG -n jumpbox --yes --no-wait

# Delete the jump VM's public IP
JUMPBOX_IP_NAME=$(az network public-ip list -g $RG --query "[?contains(name, 'jumpbox')].name" -o tsv)
az network public-ip delete -g $RG -n $JUMPBOX_IP_NAME

# Delete the jump VM's NIC
JUMPBOX_NIC_NAME=$(az network nic list -g $RG --query "[?contains(name, 'jumpbox')].name" -o tsv)
az network nic delete -g $RG -n $JUMPBOX_NIC_NAME
```

**Option 3: Use the cleanup script**:

```bash
cd infra
./cleanup.sh
# Select option 2 to delete everything, or option 3 for selective cleanup
```

---

## Troubleshooting

### Issue: App can't connect to PostgreSQL (Connection timeout or refused)

**Symptoms:**
- App logs show connection errors
- `nslookup` from Kudu console shows public IP instead of private IP (10.1.1.x)

**Solution:**
The DNS Zone Group was not created. Run step 3 again:

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az network private-endpoint dns-zone-group create \
  --endpoint-name pe-$POSTGRES_SERVER \
  --resource-group $RG \
  --name default \
  --private-dns-zone "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Network/privateDnsZones/$DNSZONE" \
  --zone-name privatelink-postgres-database-azure-com
```

Verify DNS from Kudu console (`https://$APP_NAME.scm.azurewebsites.net` → Debug Console):
```bash
nslookup pg-flex-sample-XXXXXXXXXX.postgres.database.azure.com
# Should return: 10.1.1.x (private IP)
```

### Issue: Password authentication required (not using Managed Identity)

**Symptoms:**
- Logs show: "The server requested password-based authentication, but no password was provided"

**Solution:**
1. Check `application.yml` has: `spring.datasource.azure.passwordless-enabled: true`
2. Verify app settings in Azure:
   ```bash
   az webapp config appsettings list -g $RG -n $APP_NAME \
     --query "[?name=='AZURE_CLIENT_ID' || name=='SPRING_DATASOURCE_AZURE_PASSWORDLESS_ENABLED'].{Name:name, Value:value}" -o table
   ```
3. Ensure `spring-cloud-azure-starter-jdbc-postgresql` dependency is in pom.xml

### Issue: Database user doesn't exist

**Symptoms:**
- Authentication fails with "role does not exist"

**Solution:**
Re-run step 10 to create the database principal:
```bash
ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)

psql "host=${POSTGRES_SERVER}.postgres.database.azure.com port=5432 dbname=postgres user=${PG_ADMIN_UPN}@${POSTGRES_SERVER} password=${ACCESS_TOKEN} sslmode=require" \
  -c "SELECT * FROM pgaadauth_create_principal('myAppUami', false, false);"
```


```bash
# Set variables
export RG="rg-pwless-sample"
export POSTGRES_SERVER="pg-flex-sample-1761438910"
export PG_ADMIN_UPN="Srinivas_Boini@epam.com"

# 1. Remove Entra admin
az postgres flexible-server microsoft-entra-admin delete \
  --resource-group $RG \
  --name $POSTGRES_SERVER \
  --yes

# 2. Connect as SQL admin and drop the role if it exists
# (Replace with your SQL admin password)
export PGPASSWORD='<your-sql-admin-password>'
psql "host=${POSTGRES_SERVER}.postgres.database.azure.com \
      port=5432 \
      dbname=postgres \
      user=pgadmin \
      sslmode=require" \
      -c "DROP ROLE IF EXISTS \"Srinivas_Boini@epam.com\";"

# 3. Re-add Entra admin
az postgres flexible-server microsoft-entra-admin create \
  --resource-group $RG \
  --name $POSTGRES_SERVER \
  --object-id "10f5e77c-b805-4702-874c-85cdacc4ceea" \
  --display-name "Srinivas Boini"

# 4. Restart the server (CRITICAL STEP)
az postgres flexible-server restart \
  --resource-group $RG \
  --name $POSTGRES_SERVER

# 5. Wait for restart and synchronization
echo "Waiting 5 minutes for server restart and AD sync..."
sleep 300

# 6. Try connecting
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
psql "host=${POSTGRES_SERVER}.postgres.database.azure.com \
      port=5432 \
      dbname=postgres \
      user=Srinivas_Boini@epam.com \
      sslmode=require"
```
If you want an ARM/Bicep template or a GitHub Actions workflow, ask and I'll add it.
