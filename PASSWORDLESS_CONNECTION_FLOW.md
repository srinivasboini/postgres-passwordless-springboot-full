# Passwordless PostgreSQL Connection Flow

Complete technical documentation of how Azure Managed Identity passwordless authentication works with Spring Boot, PostgreSQL, and HikariCP.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Components](#architecture-components)
3. [Complete Flow Diagram](#complete-flow-diagram)
4. [Phase-by-Phase Breakdown](#phase-by-phase-breakdown)
5. [Key Mechanisms](#key-mechanisms)
6. [Token Lifecycle](#token-lifecycle)
7. [Connection Lifecycle](#connection-lifecycle)
8. [Timing and Refresh Behavior](#timing-and-refresh-behavior)
9. [Sources and References](#sources-and-references)

---

## Overview

This application uses **Azure Managed Identity** to authenticate to **Azure Database for PostgreSQL Flexible Server** without storing passwords. The authentication flow uses **OAuth 2.0 tokens** as database passwords.

**Key Concept**: The PostgreSQL JDBC driver uses an Azure AD access token as the password field when connecting to the database.

---

## Architecture Components

### 1. Application Layer
- **Spring Boot 3.4.2** with Java 21
- **Spring Cloud Azure JDBC PostgreSQL** (`spring-cloud-azure-starter-jdbc-postgresql`)
- **Spring Data JDBC** / **JdbcTemplate**

### 2. Connection Pool Layer
- **HikariCP** (default Spring Boot connection pool)
- Configuration:
  - `maximumPoolSize: 10`
  - `minimumIdle: 10`
  - `maxLifetime: 30 minutes` (connections refresh every 30 min)
  - `idleTimeout: 10 minutes`

### 3. Authentication Layer
- **Azure Identity SDK** (`com.azure:azure-identity`)
- **MSAL4J** (Microsoft Authentication Library for Java)
- **Azure PostgreSQL JDBC Authentication Plugin**
- **ManagedIdentityCredential** (user-assigned)

### 4. Infrastructure Layer
- **Azure App Service** (hosts Spring Boot app)
- **User-Assigned Managed Identity** (UAMI)
- **Azure Database for PostgreSQL Flexible Server**
- **Azure AD** (issues OAuth tokens)
- **Azure IMDS** (Instance Metadata Service - provides tokens)

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Application Startup                          │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  1. Spring Boot reads application.yml                               │
│     - SPRING_DATASOURCE_URL                                         │
│     - SPRING_DATASOURCE_USERNAME: myAppUami                         │
│     - spring.datasource.azure.passwordless-enabled: true            │
│     - AZURE_CLIENT_ID: d8db0245-bcb2-4cd0-9ddc-8169d952fa7a        │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  2. Spring Cloud Azure JDBC Autoconfiguration                       │
│     - Detects passwordless mode                                    │
│     - JdbcConnectionStringEnhancer modifies JDBC URL                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  3. Enhanced JDBC URL includes:                                     │
│     &authenticationPluginClassName=                                 │
│       com.azure.identity.extensions.jdbc.postgresql.                │
│         AzurePostgresqlAuthenticationPlugin                         │
│     &azure.clientId=d8db0245-bcb2-4cd0-9ddc-8169d952fa7a          │
│     &azure.managedIdentityEnabled=true                             │
│     &azure.scopes=https://ossrdbms-aad.database.windows.net/.default│
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  4. HikariCP initializes connection pool                            │
│     - Creates 10 connections                                        │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  5. First Connection - Token Acquisition                            │
│                                                                     │
│  PostgreSQL JDBC Driver                                             │
│         │                                                           │
│         ▼                                                           │
│  Load AzurePostgresqlAuthenticationPlugin                          │
│         │                                                           │
│         ▼                                                           │
│  Plugin creates ManagedIdentityCredential                          │
│         │                                                           │
│         ▼                                                           │
│  credential.getToken(scopes)                                       │
│         │                                                           │
│         ▼                                                           │
│  ManagedIdentityCredential detects environment:                    │
│    - MSI_ENDPOINT (Azure IMDS endpoint)                            │
│    - MSI_SECRET (App Service identity secret)                      │
│    - AZURE_CLIENT_ID (User-assigned identity)                      │
│         │                                                           │
│         ▼                                                           │
│  HTTP GET to Azure IMDS:                                           │
│    http://169.254.169.254/metadata/identity/oauth2/token           │
│    Headers:                                                         │
│      - Metadata: true                                              │
│      - X-IDENTITY-HEADER: [MSI_SECRET]                             │
│    Params:                                                          │
│      - resource=https://ossrdbms-aad.database.windows.net          │
│      - client_id=d8db0245-bcb2-4cd0-9ddc-8169d952fa7a            │
│         │                                                           │
│         ▼                                                           │
│  Azure IMDS Response:                                              │
│    {                                                                │
│      "access_token": "eyJ0eXAiOiJKV1Qi...",                       │
│      "expires_on": "1730034427",  // 60 min from now               │
│      "resource": "https://ossrdbms-aad.database.windows.net"       │
│    }                                                                │
│         │                                                           │
│         ▼                                                           │
│  MSAL4J caches token (60-minute lifetime)                          │
│         │                                                           │
│         ▼                                                           │
│  Plugin returns token to PostgreSQL driver                         │
│         │                                                           │
│         ▼                                                           │
│  PostgreSQL driver connects:                                       │
│    - Host: pg-flex-sample.postgres.database.azure.com             │
│    - Port: 5432                                                    │
│    - Database: appdb                                               │
│    - Username: myAppUami                                           │
│    - Password: eyJ0eXAiOiJKV1Qi... (JWT token as password!)       │
│         │                                                           │
│         ▼                                                           │
│  PostgreSQL Server validates token:                                │
│    - Checks signature with Azure AD public keys                    │
│    - Validates expiry                                              │
│    - Verifies audience                                             │
│    - Matches username to database principal                        │
│         │                                                           │
│         ▼                                                           │
│  Connection established ✓                                          │
│  org.postgresql.jdbc.PgConnection@401ec794                         │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  6. Remaining Connections (#2-10)                                   │
│                                                                     │
│  For each subsequent connection:                                   │
│    1. Plugin calls credential.getToken()                           │
│    2. MSAL checks cache:                                           │
│       if (cachedToken.expiresAt > now + 5 min) {                   │
│         return cachedToken;  ← CACHE HIT                           │
│       }                                                             │
│    3. Log: "Returning token from cache"                            │
│    4. NO HTTP request to Azure                                     │
│    5. Same token used for all 10 connections                       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  7. Application Runtime                                             │
│                                                                     │
│  HikariCP Housekeeper (every 30 seconds):                          │
│    - Checks pool stats                                             │
│    - Validates connections                                         │
│    - Logs: "Pool stats (total=10, active=0, idle=10, waiting=0)"  │
│                                                                     │
│  Query Execution:                                                  │
│    1. @Repository method called                                    │
│    2. JdbcTemplate requests connection                             │
│    3. HikariCP provides idle connection                            │
│    4. Query executes                                               │
│    5. Connection returned to pool                                  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  8. Connection Refresh (Every 30 minutes)                           │
│                                                                     │
│  HikariCP maxLifetime = 30 minutes                                 │
│                                                                     │
│  After 30 minutes:                                                 │
│    1. Connection Closer: "Closing connection (maxLifetime)"        │
│    2. Connection closed                                            │
│    3. Connection Adder: Creates new connection                     │
│    4. Plugin requests token → MSAL returns CACHED token            │
│    5. New connection established with SAME token                   │
│                                                                     │
│  This happens for all 10 connections over 30 minutes               │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  9. Token Refresh (After ~55 minutes)                               │
│                                                                     │
│  Token acquired: 02:47:07                                          │
│  Token expires: 03:47:07 (60 min later)                            │
│  Current time: 03:42:07 (55 min later)                             │
│                                                                     │
│  MSAL Proactive Refresh:                                           │
│    if (expiresAt - now < 5 minutes) {                              │
│      fetchNewToken();  ← REFRESH TRIGGERED                         │
│    }                                                                │
│                                                                     │
│  1. Next connection creation triggers getToken()                   │
│  2. MSAL detects: "Token expires in 4 minutes"                     │
│  3. HTTP Request to Azure IMDS (fetches new token)                 │
│  4. New token cached (expires 60 min from now)                     │
│  5. Old connections gradually replaced over 30 min                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Phase-by-Phase Breakdown

### Phase 1: Application Startup

**What happens:**
- Spring Boot loads `application.yml` configuration
- Spring Cloud Azure JDBC autoconfiguration detects `passwordless-enabled: true`
- `JdbcConnectionStringEnhancer` modifies the JDBC URL to include authentication plugin parameters

**Configuration loaded:**
```yaml
spring:
  datasource:
    url: jdbc:postgresql://pg-flex-sample.postgres.database.azure.com:5432/appdb?sslmode=require
    username: myAppUami
    azure:
      passwordless-enabled: true  # CRITICAL

  cloud:
    azure:
      credential:
        managed-identity-enabled: true
        client-id: ${AZURE_CLIENT_ID}
```

**Enhanced JDBC URL:**
```
jdbc:postgresql://pg-flex-sample.postgres.database.azure.com:5432/appdb
  ?sslmode=require
  &ApplicationName=az-sp-psql/5.23.0
  &assumeMinServerVersion=9.0.0
  &authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin
  &azure.authorityHost=https://login.microsoftonline.com/
  &azure.clientId=d8db0245-bcb2-4cd0-9ddc-8169d952fa7a
  &azure.managedIdentityEnabled=true
  &azure.scopes=https://ossrdbms-aad.database.windows.net/.default
  &azure.tenantId=b41b72d0-4e9f-4c26-8a69-f949f367c91d
```

**Log evidence:**
```
2025-10-26T02:47:04.163Z DEBUG a.s.c.a.i.j.JdbcConnectionStringEnhancer : Trying to construct enhanced jdbc url for POSTGRESQL
```

---

### Phase 2: HikariCP Initialization

**What happens:**
- HikariCP DataSource bean created
- Configuration loaded from properties
- Pool attempts to create `minimumIdle` (10) connections

**HikariCP Configuration:**
```
maximumPoolSize: 10
minimumIdle: 10
maxLifetime: 1800000 ms (30 minutes)
idleTimeout: 600000 ms (10 minutes)
connectionTimeout: 30000 ms (30 seconds)
```

**Log evidence:**
```
2025-10-26T02:47:04.304Z DEBUG com.zaxxer.hikari.HikariConfig : maxLifetime.....................1800000
2025-10-26T02:47:04.304Z DEBUG com.zaxxer.hikari.HikariConfig : maximumPoolSize.................10
2025-10-26T02:47:04.317Z  INFO com.zaxxer.hikari.HikariDataSource : HikariPool-1 - Starting...
```

---

### Phase 3: First Connection - Token Acquisition

**Step-by-step flow:**

1. **PostgreSQL JDBC Driver loads authentication plugin**
   ```java
   // Driver reads URL parameter
   String pluginClass = "com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin";
   AuthenticationPlugin plugin = Class.forName(pluginClass).newInstance();
   ```

2. **Plugin reads Azure parameters from URL**
   ```java
   String clientId = connectionProps.get("azure.clientId");
   String scopes = connectionProps.get("azure.scopes");
   String tenantId = connectionProps.get("azure.tenantId");
   boolean managedIdentityEnabled = connectionProps.get("azure.managedIdentityEnabled");
   ```

3. **Plugin creates ManagedIdentityCredential**
   ```java
   ManagedIdentityCredential credential = new ManagedIdentityCredentialBuilder()
       .clientId("d8db0245-bcb2-4cd0-9ddc-8169d952fa7a")
       .build();
   ```

4. **Credential detects environment variables**
   - `MSI_ENDPOINT` - Azure IMDS endpoint
   - `MSI_SECRET` - App Service managed identity secret
   - `AZURE_CLIENT_ID` - User-assigned identity client ID

   **Log evidence:**
   ```
   2025-10-26T02:47:05.224Z DEBUG c.a.identity.ManagedIdentityCredential : Found the following environment variables: MSI_ENDPOINT, MSI_SECRET, AZURE_CLIENT_ID
   2025-10-26T02:47:05.291Z  INFO c.a.identity.ManagedIdentityCredential : User-assigned Managed Identity ID: d8db0245-bcb2-4cd0-9ddc-8169d952fa7a
   ```

5. **HTTP Request to Azure IMDS**
   ```http
   GET http://169.254.169.254/metadata/identity/oauth2/token
   Headers:
     Metadata: true
     X-IDENTITY-HEADER: [value from MSI_SECRET]
   Query Parameters:
     api-version=2019-08-01
     resource=https://ossrdbms-aad.database.windows.net
     client_id=d8db0245-bcb2-4cd0-9ddc-8169d952fa7a
   ```

   **Log evidence:**
   ```
   2025-10-26T02:47:05.818Z  INFO c.m.a.m.AppServiceManagedIdentitySource : [Managed Identity] Environment variables validation passed
   2025-10-26T02:47:07.878Z  INFO com.microsoft.aad.msal4j.HttpHelper : Sent (null) Correlation Id is not same as received (null)
   2025-10-26T02:47:07.878Z  INFO c.m.a.m.AbstractManagedIdentitySource : [Managed Identity] Successful response received
   ```

6. **Azure IMDS responds with token**
   ```json
   {
     "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6...",
     "expires_on": "1730034427",
     "resource": "https://ossrdbms-aad.database.windows.net",
     "token_type": "Bearer",
     "client_id": "d8db0245-bcb2-4cd0-9ddc-8169d952fa7a"
   }
   ```

7. **MSAL4J caches the token**
   ```java
   // Internal MSAL cache
   CacheKey key = new CacheKey(
       scope: "https://ossrdbms-aad.database.windows.net/.default",
       clientId: "d8db0245-bcb2-4cd0-9ddc-8169d952fa7a"
   );

   CachedToken cached = new CachedToken(
       token: "eyJ0eXAiOiJKV1Qi...",
       expiresAt: OffsetDateTime.parse("2025-10-26T03:47:07Z")  // 60 minutes
   );

   tokenCache.put(key, cached);
   ```

   **Log evidence:**
   ```
   2025-10-26T02:47:07.892Z DEBUG c.m.a.msal4j.ManagedIdentityApplication : [Correlation ID: 91710457-df97-45d2-a850-a57b00d47c86] Access Token was returned
   2025-10-26T02:47:07.892Z  INFO c.a.identity.ManagedIdentityCredential : Azure Identity => Managed Identity environment: Managed Identity
   ```

8. **Plugin returns token to PostgreSQL driver**
   ```java
   // Plugin implementation
   public String getPassword() {
       AccessToken token = credential.getToken(new TokenRequestContext()
           .addScopes("https://ossrdbms-aad.database.windows.net/.default"));
       return token.getToken();  // JWT string
   }
   ```

9. **PostgreSQL driver connects with token as password**
   ```java
   Connection conn = DriverManager.getConnection(
       "jdbc:postgresql://pg-flex-sample.postgres.database.azure.com:5432/appdb?sslmode=require",
       "myAppUami",  // username
       "eyJ0eXAiOiJKV1Qi..."  // JWT token as password
   );
   ```

10. **PostgreSQL server validates token**
    - Extracts token from password field
    - Validates JWT signature using Azure AD public keys (from JWKS endpoint)
    - Checks token expiry
    - Verifies audience claim: `https://ossrdbms-aad.database.windows.net`
    - Matches `oid` claim to database principal (created via `pgaadauth_create_principal`)
    - Grants access if all checks pass

11. **Connection established**
    **Log evidence:**
    ```
    2025-10-26T02:47:07.996Z  INFO com.zaxxer.hikari.pool.HikariPool : HikariPool-1 - Added connection org.postgresql.jdbc.PgConnection@401ec794
    2025-10-26T02:47:08.000Z  INFO com.zaxxer.hikari.HikariDataSource : HikariPool-1 - Start completed
    ```

---

### Phase 4: Remaining Connections (2-10)

**What happens:**
- HikariCP needs 10 connections (configured `minimumIdle`)
- For connections #2-10, token is already cached
- MSAL returns cached token without HTTP request

**MSAL Cache Logic:**
```java
public AccessToken getToken(TokenRequestContext request) {
    CacheKey key = createKey(request);
    CachedToken cached = tokenCache.get(key);

    if (cached != null && cached.expiresAt.isAfter(now().plus(5, MINUTES))) {
        log.debug("Returning token from cache");
        return cached.token;  // ← This branch executes for connections 2-10
    }

    // Fetch new token (NOT executed)
    return fetchNewToken(request);
}
```

**Log evidence (repeated 9 times):**
```
2025-10-26T02:47:08.210Z DEBUG .m.AcquireTokenByManagedIdentitySupplier : ForceRefresh set to false. Attempting cache lookup
2025-10-26T02:47:08.211Z DEBUG c.m.a.msal4j.AcquireTokenSilentSupplier : Returning token from cache
2025-10-26T02:47:08.211Z DEBUG .m.AcquireTokenByManagedIdentitySupplier : Returning token from cache
2025-10-26T02:47:08.215Z DEBUG c.m.a.msal4j.ManagedIdentityApplication : [Correlation ID: ...] Access Token was returned
```

**Result:**
- 10 connections created
- 1 HTTP request to Azure IMDS
- 9 cache hits
- All connections use the same token

---

### Phase 5: Application Runtime (Normal Operation)

**HikariCP Housekeeper Thread:**
- Runs every 30 seconds
- Checks pool health
- Logs pool statistics
- Validates idle connections
- Closes connections exceeding `idleTimeout`

**Log evidence:**
```
2025-10-26T02:47:38.104Z DEBUG com.zaxxer.hikari.pool.HikariPool : HikariPool-1 - Pool stats (total=10, active=0, idle=10, waiting=0)
2025-10-26T02:47:38.105Z DEBUG com.zaxxer.hikari.pool.HikariPool : HikariPool-1 - Fill pool skipped, pool has sufficient level
```

**Query Execution Flow:**
```java
// Application code
@Repository
class UserRepository {
    private final JdbcTemplate jdbc;

    List<User> findAll() {
        return jdbc.query("SELECT * FROM users", userRowMapper);
    }
}

// Internal flow:
// 1. JdbcTemplate.query() called
// 2. DataSource.getConnection() requested
// 3. HikariCP provides idle connection from pool
// 4. Query executes on existing connection
// 5. Connection.close() returns connection to pool
```

**No token activity during this phase** - connections reuse cached token.

---

### Phase 6: Connection Refresh (Every 30 Minutes)

**Why connections are refreshed:**
- HikariCP `maxLifetime = 1800000 ms` (30 minutes)
- Prevents stale connections
- Forces connection validation
- Ensures connection-level resources are cleaned up

**Flow:**
1. HikariCP Connection Closer Thread detects connection age > 30 minutes
2. Closes the PostgreSQL connection
3. HikariCP Connection Adder Thread creates replacement
4. Plugin requests token from MSAL
5. MSAL returns **cached token** (still valid for 30+ more minutes)
6. New connection established with same token

**Log evidence:**
```
2025-10-26T03:16:34.013Z DEBUG com.zaxxer.hikari.pool.PoolBase : HikariPool-1 - Closing connection org.postgresql.jdbc.PgConnection@67c20712: (connection has passed maxLifetime)

2025-10-26T03:16:34.062Z DEBUG .m.AcquireTokenByManagedIdentitySupplier : ForceRefresh set to false. Attempting cache lookup
2025-10-26T03:16:34.064Z DEBUG c.m.a.msal4j.AcquireTokenSilentSupplier : Returning token from cache

2025-10-26T03:16:34.111Z DEBUG com.zaxxer.hikari.pool.HikariPool : HikariPool-1 - Added connection org.postgresql.jdbc.PgConnection@27ff2132
```

**Timeline example:**
```
02:47:07 - Token acquired (expires 03:47:07)
02:47:08 - 10 connections created
03:17:08 - Connections start refreshing (30 min later)
03:17:08 - MSAL cache hit (token still valid for 30 min)
03:17:08 - New connections use SAME token
```

---

### Phase 7: Token Refresh (After ~55 Minutes)

**MSAL Proactive Refresh:**
- MSAL refreshes tokens **5 minutes before expiry**
- Prevents authentication failures
- Ensures smooth token rotation

**Trigger condition:**
```java
if (cachedToken.expiresAt.minus(5, MINUTES).isBefore(now())) {
    // Token expires in < 5 minutes
    fetchNewTokenFromAzure();
}
```

**Timeline:**
```
02:47:07 - Token acquired (expires 03:47:07)
03:42:07 - MSAL detects: "Token expires in 5 minutes"
03:42:07 - HTTP request to Azure IMDS
03:42:07 - New token cached (expires 04:42:07)
03:42:07 - Next connection uses NEW token
03:47:07 - Old token expires (no longer used)
```

**Log evidence (expected around 03:42:07):**
```
DEBUG .m.AcquireTokenByManagedIdentitySupplier : ForceRefresh set to false. Attempting cache lookup
DEBUG .m.AcquireTokenByManagedIdentitySupplier : Token not found in the cache
INFO  c.m.a.m.AppServiceManagedIdentitySource : [Managed Identity] Environment variables validation passed
INFO  c.m.a.m.AbstractManagedIdentitySource : [Managed Identity] Successful response received
DEBUG c.m.a.msal4j.ManagedIdentityApplication : Access Token was returned
```

**Gradual rotation:**
- Old connections (with old token) still work until `maxLifetime`
- New connections (created in next 30 min) use new token
- Over 30 minutes, all connections rotate to new token

---

## Key Mechanisms

### 1. Token Caching (MSAL4J)

**Purpose:** Reduce HTTP requests to Azure IMDS

**Implementation:**
```java
class TokenCache {
    private final Map<CacheKey, CachedToken> cache = new ConcurrentHashMap<>();

    public AccessToken getToken(TokenRequestContext request) {
        CacheKey key = new CacheKey(request.getScopes(), clientId);
        CachedToken cached = cache.get(key);

        // Return cached token if it's still valid for > 5 minutes
        if (cached != null && cached.expiresAt.isAfter(Instant.now().plus(5, MINUTES))) {
            logger.debug("Returning token from cache");
            return cached.token;
        }

        // Fetch new token if cache miss or expiring soon
        AccessToken newToken = fetchFromAzure(request);
        cache.put(key, new CachedToken(newToken, newToken.getExpiresAt()));
        return newToken;
    }
}
```

**Behavior:**
- **Cache hit:** Token returned in microseconds
- **Cache miss:** HTTP request to Azure (~100-500ms)
- **Proactive refresh:** 5 minutes before expiry
- **Thread-safe:** ConcurrentHashMap

---

### 2. HikariCP Connection Pool

**Purpose:** Reuse database connections for performance

**Configuration:**
```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10        # Max connections
      minimum-idle: 10              # Min idle connections
      max-lifetime: 1800000         # 30 min (connections refresh)
      idle-timeout: 600000          # 10 min (unused connections closed)
      connection-timeout: 30000     # 30 sec (wait for available connection)
```

**Lifecycle:**
```
Connection Created
      ↓
  Added to pool
      ↓
  Used for queries
      ↓
  Idle in pool
      ↓
After maxLifetime (30 min)
      ↓
  Closed and replaced
      ↓
  New connection created
```

**Threads:**
1. **Housekeeper Thread:** Runs every 30s, checks pool health
2. **Connection Closer Thread:** Closes connections exceeding `maxLifetime`
3. **Connection Adder Thread:** Creates replacement connections

---

### 3. PostgreSQL AAD Authentication

**Server-side validation:**

1. **Token extraction:**
   ```sql
   -- PostgreSQL receives password field containing JWT
   -- Passes to pgaadauth extension
   ```

2. **Signature validation:**
   ```
   - Fetch Azure AD public keys (JWKS)
   - Verify JWT signature with RS256 algorithm
   ```

3. **Claims validation:**
   ```json
   {
     "aud": "https://ossrdbms-aad.database.windows.net",  // Must match
     "iss": "https://sts.windows.net/<tenant-id>/",       // Must match tenant
     "oid": "5ad5bef1-d8e8-4739-bc84-42941c97ab0e",       // User object ID
     "exp": 1730034427,                                    // Must be future
     "nbf": 1730030827,                                    // Must be past
     "iat": 1730030827,                                    // Issued at
     "sub": "5ad5bef1-d8e8-4739-bc84-42941c97ab0e"
   }
   ```

4. **Database principal matching:**
   ```sql
   -- PostgreSQL maps token 'oid' claim to database user
   -- User created via: pgaadauth_create_principal('myAppUami', false, false)
   -- User must have required permissions (CONNECT, SELECT, INSERT, etc.)
   ```

---

## Token Lifecycle

### Token Phases

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: Acquisition (First request)                        │
├─────────────────────────────────────────────────────────────┤
│ Time: 02:47:07                                              │
│ Action: HTTP request to Azure IMDS                          │
│ Result: Token cached (expires 03:47:07)                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Phase 2: Cached Usage (0-55 minutes)                        │
├─────────────────────────────────────────────────────────────┤
│ Time: 02:47:07 - 03:42:07 (55 minutes)                      │
│ Action: All token requests return cached token              │
│ HTTP Requests: 0                                            │
│ Log: "Returning token from cache"                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Phase 3: Proactive Refresh (55-60 minutes)                  │
├─────────────────────────────────────────────────────────────┤
│ Time: 03:42:07 (5 min before expiry)                        │
│ Trigger: expiresAt - now < 5 minutes                        │
│ Action: Fetch new token from Azure                          │
│ Result: New token cached (expires 04:42:07)                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Phase 4: Token Rotation (60-90 minutes)                     │
├─────────────────────────────────────────────────────────────┤
│ Time: 03:47:07 - 04:17:07                                   │
│ Old token: Expired, no longer used                          │
│ New connections: Use new token                              │
│ Old connections: Gradually replaced (maxLifetime)           │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    (Cycle repeats)
```

### Token Properties

```json
{
  "token_type": "Bearer",
  "expires_in": 3599,
  "ext_expires_in": 3599,
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6...",
  "expires_on": "1730034427",
  "not_before": "1730030827",
  "resource": "https://ossrdbms-aad.database.windows.net"
}
```

**Key fields:**
- `access_token`: JWT to use as database password
- `expires_on`: Unix timestamp (60 minutes from issuance)
- `resource`: Audience claim (PostgreSQL service)

---

## Connection Lifecycle

### Individual Connection Timeline

```
┌─────────────────────────────────────────────────────────────┐
│ T+0:00 - Connection Created                                 │
├─────────────────────────────────────────────────────────────┤
│ - Plugin requests token (cache hit after first connection)  │
│ - PostgreSQL driver connects with token                     │
│ - Connection added to HikariCP pool                         │
│ - State: IDLE                                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ T+0:01 - T+30:00 - Connection in Use                        │
├─────────────────────────────────────────────────────────────┤
│ - Borrowed from pool for queries                            │
│ - Returned to pool after use                                │
│ - Validated by HikariCP housekeeper every 30s               │
│ - State: ACTIVE ↔ IDLE                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ T+30:00 - Connection Aged Out (maxLifetime)                 │
├─────────────────────────────────────────────────────────────┤
│ - HikariCP detects: age > 30 minutes                        │
│ - Connection closed gracefully                              │
│ - State: CLOSED                                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ T+30:01 - Replacement Connection Created                    │
├─────────────────────────────────────────────────────────────┤
│ - HikariCP creates new connection                           │
│ - Plugin requests token (cache hit if token still valid)    │
│ - New connection added to pool                              │
│ - Cycle restarts                                            │
└─────────────────────────────────────────────────────────────┘
```

### Pool-Level Timeline

```
02:47:07 - Initial pool creation (10 connections)
02:47:08 - All connections IDLE
03:17:07 - First connection refresh (30 min)
03:17:37 - Second connection refresh
...        (Staggered over ~5 minutes)
03:22:00 - All connections refreshed once
03:47:07 - Token expires, new token in cache
03:52:07 - Next connection refresh uses new token
04:22:00 - All connections using new token
```

---

## Timing and Refresh Behavior

### Why "Returning token from cache" is normal

**Scenario:** App started at 02:47:07, current time 03:16:50 (29 minutes later)

**Analysis:**
```
Token acquired:     02:47:07
Token expires:      03:47:07 (60 min later)
Current time:       03:16:50 (29 min elapsed)
Time until expiry:  31 minutes remaining
MSAL refresh threshold: 5 minutes before expiry

Cache decision:
if (31 minutes > 5 minutes) {
    return cachedToken;  ← This branch executes
}
```

**Expected behavior:**
- **0-55 minutes:** All requests use cached token
- **55-60 minutes:** New token acquired
- **60+ minutes:** All requests use new cached token

**This is efficient and correct** - no need to fetch a new token when the current one is still valid for 31 minutes!

---

## Sources and References

### Official Documentation

1. **Azure Managed Identity:**
   - [What are managed identities for Azure resources?](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
   - [How to use managed identities for App Service](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity)

2. **Azure Database for PostgreSQL:**
   - [Use Microsoft Entra ID for authentication](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/how-to-configure-sign-in-azure-ad-authentication)
   - [Microsoft Entra authentication concepts](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-azure-ad-authentication)

3. **Spring Cloud Azure:**
   - [Spring Cloud Azure JDBC support](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/configure-spring-data-jdbc-with-azure-postgresql)
   - [Passwordless connections](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/configure-spring-boot-starter-java-app-with-azure-active-directory)

4. **MSAL4J (Microsoft Authentication Library):**
   - [MSAL4J Wiki](https://github.com/AzureAD/microsoft-authentication-library-for-java/wiki)
   - [Token caching](https://github.com/AzureAD/microsoft-authentication-library-for-java/wiki/Token-Cache-Serialization)

5. **HikariCP:**
   - [HikariCP Configuration](https://github.com/brettwooldridge/HikariCP#configuration-knobs-baby)
   - [Connection lifecycle](https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing)

### Observed Behavior from Logs

The following details were **directly observed** from application logs:

1. **Token acquisition flow:** Logs show IMDS HTTP requests and successful responses
2. **Cache hits:** Repeated "Returning token from cache" logs confirm caching behavior
3. **Connection refresh timing:** Logs show connections closed at exactly 30-minute intervals
4. **JDBC URL enhancement:** Debug logs show the enhanced connection string
5. **Managed Identity detection:** Logs confirm MSI_ENDPOINT and MSI_SECRET environment variables

**Log file:** Azure App Service application logs (downloaded via `az webapp log download`)

### Inferred Technical Details

The following are **reasonable inferences** based on:
- Azure SDK source code (publicly available on GitHub)
- MSAL4J library implementation
- PostgreSQL JDBC driver behavior
- Standard OAuth 2.0 / JWT practices

**Specifically inferred:**
1. **IMDS request format:** Based on Azure IMDS API documentation and SDK implementation
2. **MSAL cache logic:** Based on MSAL4J source code and observed log patterns
3. **PostgreSQL token validation:** Based on Azure PostgreSQL Entra ID documentation
4. **HikariCP internal threads:** Based on HikariCP source code and configuration

### Validation Methods

All claims in this document can be validated by:

1. **Enabling debug logging:**
   ```yaml
   logging.level:
     com.azure.identity: TRACE
     com.microsoft.aad.msal4j: DEBUG
     com.zaxxer.hikari: DEBUG
   ```

2. **Downloading application logs:**
   ```bash
   az webapp log download --name <app-name> --resource-group <rg>
   ```

3. **Reading source code:**
   - [Azure Identity Java SDK](https://github.com/Azure/azure-sdk-for-java/tree/main/sdk/identity/azure-identity)
   - [MSAL4J](https://github.com/AzureAD/microsoft-authentication-library-for-java)
   - [Spring Cloud Azure](https://github.com/Azure/azure-sdk-for-java/tree/main/sdk/spring)
   - [HikariCP](https://github.com/brettwooldridge/HikariCP)

---

## Conclusion

This passwordless connection flow demonstrates:

1. **Zero secrets stored** - No passwords in configuration
2. **Automatic token management** - MSAL handles caching and refresh
3. **Efficient caching** - Minimal HTTP requests to Azure
4. **Connection pooling** - HikariCP reuses connections
5. **Seamless rotation** - Tokens refresh without downtime

**Key takeaway:** The high frequency of "Returning token from cache" logs is **expected and optimal** - it indicates the system is working efficiently without unnecessary HTTP requests.
