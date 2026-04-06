# Azure Deployment Guide — Full Platform (Excluding MCP Hub)

**Purpose:** Step-by-step Azure Portal instructions to deploy every component of the EEOC AI Integration Platform except the MCP Hub (covered separately in `Azure_MCP_Hub_Setup_Guide.md`).

**Audience:** EEOC OCIO staff with Azure Government Portal access.

**Prerequisites:**
- Azure Government subscription with Contributor role
- Global Administrator for Entra ID app registrations
- Access to ARC DBA team for WAL/CDC provisioning (2 SQL commands)

**Deployment order matters.** Follow the sections in sequence — later sections depend on earlier ones.

---

## Section 1: Foundation Resources

### 1.1 Resource Group

1. Azure Portal → **Resource groups** → **Create**
2. Subscription: your Azure Gov subscription
3. Name: `rg-eeoc-ai-platform-prod`
4. Region: `USGov Virginia`
5. Tags:
   - `Environment`: `Production`
   - `Project`: `EEOC-AI-Platform`
   - `CostCenter`: `OCIO`
6. **Review + create** → **Create**

### 1.2 Virtual Network

1. **Create a resource** → search **Virtual Network** → **Create**
2. Resource group: `rg-eeoc-ai-platform-prod`
3. Name: `vnet-eeoc-ai-platform`
4. Region: `USGov Virginia`
5. **IP Addresses** tab:
   - Address space: `10.100.0.0/16`
   - Add subnets:

| Subnet name | Address range | Purpose |
|-------------|---------------|---------|
| `snet-apps` | `10.100.1.0/24` | Container Apps environment |
| `snet-postgres` | `10.100.2.0/24` | PostgreSQL private endpoint |
| `snet-redis` | `10.100.3.0/24` | Redis private endpoint |
| `snet-storage` | `10.100.4.0/24` | Storage account private endpoints |
| `snet-keyvault` | `10.100.5.0/24` | Key Vault private endpoint |
| `snet-eventhub` | `10.100.6.0/24` | Event Hub private endpoint |
| `snet-frontdoor` | `10.100.7.0/24` | Front Door backend (ADR) |

6. **Review + create** → **Create**

### 1.3 Key Vault

1. **Create** → search **Key Vault**
2. Name: `kv-eeoc-ai-prod`
3. Region: same
4. Pricing: `Standard`
5. **Networking** tab: Private endpoint in `snet-keyvault`
6. **Access configuration**: `Azure role-based access control`
7. **Review + create** → **Create**

**After creation — add secrets:**

Navigate to Key Vault → **Secrets** → **Generate/Import** for each:

| Secret Name | Purpose | How to Generate |
|-------------|---------|----------------|
| `HUB-AUDIT-HASH-SALT` | PII hashing in audit logs | 40+ random chars |
| `MCP-WEBHOOK-SECRET-ADR` | HMAC for ADR events | 32+ random chars |
| `MCP-WEBHOOK-SECRET-ARC` | HMAC for ARC events | 32+ random chars |
| `MCP-WEBHOOK-SECRET-TRIAGE` | HMAC for Triage events | 32+ random chars |
| `ARC-OAUTH-CLIENT-ID` | ARC Integration API auth | From ARC team |
| `ARC-OAUTH-CLIENT-SECRET` | ARC Integration API auth | From ARC team |
| `OPENAI-API-KEY` | Azure OpenAI (if not using managed identity) | From Azure OpenAI resource |
| `PG-ADMIN-PASSWORD` | PostgreSQL admin | Generated during DB creation |

Generate random secrets via Azure Cloud Shell:
```bash
openssl rand -base64 40
```

### 1.4 Storage Account (Audit + Blobs)

1. **Create** → search **Storage account**
2. Name: `steeocaiaudit` (globally unique)
3. Region: same
4. Performance: `Standard`
5. Redundancy: `GRS` (geo-redundant)
6. **Networking**: Private endpoint in `snet-storage`
7. **Review + create** → **Create**

**After creation:**

**Create audit table:**
1. Open storage account → **Tables** → **+ Table**
2. Name: `hubauditlog`

**Create WORM blob container:**
1. **Containers** → **+ Container**
2. Name: `hub-audit-archive`
3. Access level: `Private`
4. After creation → open container → **Access policy**
5. **Add policy**: Time-based retention, `2555` days
6. **Save**

**Create additional containers for each app:**

| Container | Purpose |
|-----------|---------|
| `adr-case-files` | ADR document storage |
| `adr-quarantine` | Malware-quarantined files |
| `triage-processing` | Triage case upload processing |
| `triage-archival` | Processed case archives |
| `function-locks` | Distributed lock blobs |
| `lifecycle-archives` | Data lifecycle partition archives |

---

## Section 2: Database

### 2.1 Azure Database for PostgreSQL Flexible Server

1. **Create** → search **Azure Database for PostgreSQL Flexible Server**
2. Resource group: `rg-eeoc-ai-platform-prod`
3. Server name: `pg-eeoc-udip-prod`
4. Region: `USGov Virginia`
5. PostgreSQL version: `16`
6. Workload type: `Production`
7. **Compute + storage**:
   - Tier: `Memory Optimized`
   - Size: `Standard_E16ds_v5` (16 vCores, 128 GB RAM)
   - Storage: `2048 GB` (2 TB)
   - Auto-grow: `Enabled`
   - IOPS: `5000` (Premium SSD v2)
8. **Authentication**: `PostgreSQL and Entra ID authentication`
9. Set admin username and password (store password in Key Vault as `PG-ADMIN-PASSWORD`)
10. **Networking**:
    - Connectivity: `Private access`
    - Virtual network: `vnet-eeoc-ai-platform`
    - Subnet: `snet-postgres`
11. **Review + create** → **Create** (takes 5-10 minutes)

**After creation — configure server parameters:**

1. Open the server → **Server parameters**
2. Search and set:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `shared_buffers` | `32GB` | 25% of RAM |
| `effective_cache_size` | `96GB` | 75% of RAM |
| `work_mem` | `64MB` | Per-sort memory |
| `maintenance_work_mem` | `2GB` | For VACUUM, index builds |
| `max_connections` | `250` | PgBouncer sends up to 200 |
| `max_parallel_workers_per_gather` | `4` | Parallel query execution |
| `max_parallel_workers` | `16` | Match vCores |
| `random_page_cost` | `1.1` | SSD-optimized |
| `effective_io_concurrency` | `200` | SSD concurrent I/O |
| `idle_in_transaction_session_timeout` | `30000` | 30s, kill stale transactions |
| `statement_timeout` | `60000` | 60s hard cap |
| `log_min_duration_statement` | `1000` | Log queries > 1s |
| `shared_preload_libraries` | `pg_stat_statements,pgcrypto` | Extensions |

3. Click **Save** (server restarts)

**Enable extensions:**

Connect via Azure Cloud Shell or psql:
```sql
CREATE EXTENSION IF NOT EXISTS pgvector;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

**Run schema scripts:**

Execute in order from the UDIP repo `analytics-db/postgres/` directory:
```
001-extensions.sql
002-schemas.sql
003-replica-schema.sql
010-analytics-tables.sql
011-lifecycle-columns.sql
012-lifecycle-tables.sql
013-lifecycle-views.sql
014-adr-triage-tables.sql
016-cdc-target-tables.sql
020-vector-tables.sql
030-document-tables.sql
040-rls-policies.sql
050-search-functions.sql
```

### 2.2 Read Replica

1. Open `pg-eeoc-udip-prod` → **Replication**
2. Click **+ Add replica**
3. Name: `pg-eeoc-udip-prod-replica`
4. Region: same (`USGov Virginia`)
5. Same compute tier (Memory Optimized E16ds_v5)
6. **Review + create** → **Create**

The replica is read-only and replicates asynchronously (typically < 1 second lag).

### 2.3 Azure Cache for Redis

1. **Create** → search **Azure Cache for Redis**
2. Name: `redis-eeoc-ai-prod`
3. Resource group: same
4. Region: same
5. Cache type: `Premium P1` (6 GB, VNet support)
6. **Networking**: Private endpoint in `snet-redis`
7. **Advanced**:
   - Redis version: `7.x`
   - Enable non-TLS port: `No`
   - Persistence: `RDB` (every 60 minutes)
8. **Review + create** → **Create** (takes 15-20 minutes)

Copy the **Access keys** → **Primary connection string** → store in Key Vault as `REDIS-CONNECTION-STRING`.

---

## Section 3: Event Hub (CDC Pipeline)

### 3.1 Event Hub Namespace

1. **Create** → search **Event Hubs**
2. Name: `evhns-eeoc-cdc-prod`
3. Resource group: same
4. Region: same
5. Pricing tier: `Standard`
6. Throughput units: `4` (auto-inflate to `8`)
7. Enable Kafka: `Yes`
8. **Networking**: Private endpoint in `snet-eventhub`
9. **Review + create** → **Create**

**After creation:**

Event Hub topics are auto-created by Debezium when it connects. You don't need to create them manually. But verify after Debezium starts that you see topics like:
- `prepa.public.charge_inquiry`
- `prepa.public.charging_party`
- `prepa.public.respondent`
- `prepa.public.charge_allegation`
- etc.

**Create consumer group:**
1. Open any Event Hub topic → **Consumer groups** → **+ Consumer group**
2. Name: `udip-middleware`

Copy the **Shared access policies** → **RootManageSharedAccessKey** connection string → store in Key Vault as `EVENTHUB-CONNECTION-STRING`.

### 3.2 Request WAL/CDC Access from ARC DBA

Provide the ARC DBA team with:

1. **Two SQL commands to run on PrEPA's PostgreSQL:**
```sql
SELECT pg_create_logical_replication_slot('udip_cdc', 'pgoutput');
CREATE PUBLICATION udip_publication FOR ALL TABLES;
```

2. **What we need from them:**
   - Read-only PostgreSQL credentials (username + password) for Debezium
   - Hostname and port of PrEPA's PostgreSQL server
   - Confirmation that `max_slot_wal_keep_size` is set (prevents disk exhaustion)

3. **Store the credentials in Key Vault:**
   - `ARC-PG-HOST`: PrEPA server hostname
   - `ARC-PG-PORT`: typically 5432
   - `ARC-PG-USER`: read-only Debezium user
   - `ARC-PG-PASSWORD`: password

---

## Section 4: Container Apps Environment

### 4.1 Create Container Apps Environment

1. **Create** → search **Container Apps Environment**
2. Name: `cae-eeoc-ai-prod`
3. Resource group: same
4. Region: same
5. **Networking**:
   - Use your own VNet: `Yes`
   - Virtual network: `vnet-eeoc-ai-platform`
   - Subnet: `snet-apps`
   - Internal only: `Yes` (no public access except via Front Door)
6. **Monitoring**: Create or select Log Analytics workspace
7. **Review + create** → **Create**

### 4.2 Deploy Container Apps

For each application, the process is:

1. **Container Apps** → **+ Create**
2. Select environment: `cae-eeoc-ai-prod`
3. Name: (see table below)
4. **Container** tab:
   - Image source: Azure Container Registry (push images first)
   - CPU / Memory: (see table below)
5. **Scale** tab:
   - Min replicas / Max replicas: (see table below)
   - Scale rule: CPU-based (threshold in table)
6. **Ingress**: Internal (except ADR which also needs external via Front Door)

| App | Container Name | Image | CPU | Memory | Min | Max | CPU Threshold |
|-----|---------------|-------|-----|--------|-----|-----|--------------|
| **UDIP AI Assistant** | `ca-udip-ai` | `eeoc-udip-ai-assistant:latest` | 2 | 4Gi | 2 | 6 | 70% |
| **UDIP CDC Consumer** | `ca-udip-cdc` | `eeoc-udip-data-middleware:latest` | 2 | 4Gi | 1 | 2 | 80% |
| **ADR Web App** | `ca-adr-webapp` | `eeoc-adr-webapp:latest` | 2 | 4Gi | 3 | 12 | 65% |
| **Triage Web App** | `ca-triage-webapp` | `eeoc-triage-webapp:latest` | 1 | 2Gi | 2 | 6 | 70% |
| **ARC Integration API** | `ca-arc-integration` | `eeoc-arc-integration:latest` | 1 | 2Gi | 2 | 4 | 70% |
| **OGC Trial Tool** | `ca-ogc-trialtool` | `eeoc-ogc-trialtool:latest` | 1 | 2Gi | 2 | 4 | 70% |
| **PgBouncer** | `ca-pgbouncer` | `edoburu/pgbouncer:latest` | 0.5 | 256Mi | 2 | 4 | 80% |
| **Debezium Connect** | `ca-debezium` | `eeoc-debezium-connect:latest` | 2 | 4Gi | 1 | 1 | N/A |
| **MCP Hub Aggregator** | `ca-mcp-aggregator` | `eeoc-mcp-hub-functions:latest` | 0.5 | 512Mi | 1 | 2 | 70% |
| **Superset Web** | `ca-superset-web` | `eeoc-superset:latest` | 2 | 4Gi | 2 | 4 | 70% |

**ADR is public-facing** — it requires both internal ingress (for hub/spoke communication) and external ingress (for parties via Front Door). Set ingress to `Accepting traffic from anywhere` and configure Front Door in Section 5.

**Environment variables for each app:**

Set via Container App → **Settings** → **Environment variables**. Reference Key Vault secrets using managed identity:

Common variables (all apps):
```
KEY_VAULT_URI=https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/
REDIS_URL=rediss://redis-eeoc-ai-prod.redis.cache.usgovcloudapi.net:6380
AZURE_TENANT_ID=(your tenant ID)
```

Per-app variables are documented in each repo's `deploy/k8s/*/configmap.yaml`.

### 4.3 Azure Functions (ADR + Triage)

ADR and Triage each have Azure Function Apps for background processing (timers, queue triggers, blob triggers).

For each function app:

1. **Create** → search **Function App**
2. Resource group: same
3. Name: `func-eeoc-adr-prod` / `func-eeoc-triage-prod`
4. Runtime: `Python 3.12`
5. Plan: `Premium (EP1)` (required for VNet integration and always-ready instances)
6. **Networking**: VNet integration with `snet-apps`
7. **Monitoring**: Application Insights (same workspace)

**After creation:**

1. Open function app → **Configuration** → **Application settings**
2. Add all environment variables from the function app's config
3. Add Key Vault references for secrets: `@Microsoft.KeyVault(SecretUri=https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/secrets/SECRET-NAME/)`

---

## Section 5: Azure Front Door (ADR Public Access)

ADR is the only public-facing application. Azure Front Door provides edge security.

### 5.1 Create Front Door Profile

1. **Create** → search **Front Door and CDN profiles**
2. Name: `fd-eeoc-adr-prod`
3. Tier: `Standard`
4. **Endpoint**: `adr-eeoc` (becomes `adr-eeoc.azurefd.net`)
5. **Origin group**:
   - Name: `adr-origin`
   - Origin: `ca-adr-webapp` internal FQDN
   - Protocol: HTTPS
   - Priority: 1
   - Health probe: `/healthz` every 30 seconds
6. **Route**:
   - Patterns: `/*`
   - HTTPS only: Yes
   - Caching: Enable for static assets (`/static/*`)
7. **Review + create** → **Create**

### 5.2 WAF Policy

1. **Create** → search **Web Application Firewall policies**
2. Policy for: `Azure Front Door`
3. Name: `waf-eeoc-adr-prod`
4. Mode: `Prevention`
5. **Managed rules**:
   - Add `Microsoft_DefaultRuleSet_2.1` (OWASP 3.2)
   - Add `Microsoft_BotManagerRuleSet_1.0`
6. **Custom rules**:
   - Rate limit: 100 requests per minute per IP
   - Geo-filter: Allow US only (if applicable)
7. Associate with Front Door endpoint
8. **Save**

### 5.3 Custom Domain

1. Open Front Door → **Domains** → **+ Add**
2. Domain: `adr.eeoc.gov` (or your domain)
3. Certificate: `AFD managed` (auto-renews)
4. DNS: Add CNAME record pointing `adr.eeoc.gov` to `adr-eeoc.azurefd.net`
5. Validate and associate with route

---

## Section 6: Azure OpenAI

### 6.1 Create Azure OpenAI Resource

1. **Create** → search **Azure OpenAI**
2. Name: `oai-eeoc-ai-prod`
3. Resource group: same
4. Region: `USGov Virginia` (or wherever GPT-4o is available in Gov)
5. Pricing: Standard (S0)
6. **Review + create** → **Create**

### 6.2 Deploy Models

1. Open resource → **Model deployments** → **+ Create**
2. Deploy:

| Model | Deployment Name | TPM (Tokens Per Minute) |
|-------|----------------|------------------------|
| `gpt-4o` | `gpt-4o` | 80,000 |
| `text-embedding-3-small` | `text-embedding-3-small` | 350,000 |

3. Store the endpoint and key in Key Vault:
   - `OPENAI-ENDPOINT`: e.g., `https://oai-eeoc-ai-prod.openai.azure.us/`
   - `OPENAI-API-KEY`: (or use managed identity — preferred)

### 6.3 Managed Identity Access (Preferred over API Key)

1. Open Azure OpenAI resource → **Access control (IAM)** → **+ Add role assignment**
2. Role: `Cognitive Services OpenAI User`
3. Assign to: each Container App's managed identity (UDIP AI Assistant, Triage CaseFileProcessor)
4. **Save**

This allows the apps to use `DefaultAzureCredential` instead of an API key.

---

## Section 7: Azure Cognitive Search (Triage RAG)

1. **Create** → search **Azure AI Search**
2. Name: `search-eeoc-triage-prod`
3. Resource group: same
4. Region: same
5. Pricing: `Standard` (S1)
6. **Networking**: Private endpoint in `snet-storage`
7. **Review + create** → **Create**

Store the admin key in Key Vault as `SearchServiceAdminKey`.

---

## Section 8: Entra ID App Registrations

Create one app registration per service. For each:

1. **Microsoft Entra ID** → **App registrations** → **New registration**
2. Name and roles:

| App Name | App Roles |
|----------|-----------|
| `EEOC-MCP-Hub` | `Hub.Read`, `Hub.Write` |
| `EEOC-ADR-Mediation` | `MCP.Read`, `MCP.Write` |
| `EEOC-OFS-Triage` | `MCP.Read`, `MCP.Write` |
| `EEOC-UDIP-Analytics` | `Analytics.Read`, `Analytics.Write` |
| `EEOC-OGC-TrialTool` | `MCP.Read`, `MCP.Write` |
| `EEOC-ARC-Integration` | `ARC.Read`, `ARC.Write` |

3. For each: **App roles** → **Create app role** → set Display name, Value, Allowed member types: Applications
4. **Certificates & secrets** → **New client secret** → store in Key Vault

**Grant managed identity access:**

For each Container App:
1. Open Container App → **Identity** → **System assigned** → `On`
2. Copy the Object ID
3. Open the target app registration → **API permissions** → **+ Add permission** → **My APIs**
4. Select the target app → **Application permissions** → check the required role
5. **Grant admin consent**

---

## Section 9: Monitoring and Alerting

### 9.1 Application Insights

Each Container App and Function App should use the same Application Insights instance:

1. **Create** → search **Application Insights**
2. Name: `appi-eeoc-ai-prod`
3. Resource group: same
4. Log Analytics workspace: same as Container Apps environment

### 9.2 Alert Rules

1. **Monitor** → **Alerts** → **Create alert rule**
2. Create alerts for:

| Alert | Resource | Condition | Action |
|-------|----------|-----------|--------|
| Database CPU high | PostgreSQL | CPU > 80% for 5 min | Email OCIO team |
| Database connections high | PostgreSQL | Active connections > 200 | Email |
| Replication lag | Read replica | Lag > 30 seconds | Email |
| CDC consumer lag | Event Hub | Consumer lag > 5 min | Email |
| ADR error rate | Front Door | 5xx > 1% | Email + Teams |
| Container App restart | Container Apps | Restart count > 3 in 5 min | Email |
| Redis memory | Redis | Memory > 80% | Email |
| Storage WORM breach attempt | Storage | Delete on WORM container | Email (critical) |

---

## Section 10: Verification Checklist

After deployment, verify each component:

### Foundation
- [ ] VNet subnets have correct address ranges
- [ ] Key Vault accessible via private endpoint
- [ ] Storage account tables and containers created
- [ ] WORM policy prevents blob deletion (test: try to delete → should fail)

### Database
- [ ] PostgreSQL server accepts connections from PgBouncer
- [ ] Extensions enabled (pgvector, pg_stat_statements)
- [ ] Schema scripts executed successfully (all tables, views, RLS policies)
- [ ] Read replica replicating (check lag in Azure Portal)
- [ ] PgBouncer connects and pools correctly

### CDC Pipeline
- [ ] ARC DBA has run the 2 SQL commands
- [ ] Debezium connector starts and creates Event Hub topics
- [ ] CDC consumer processes events and writes to replica schema
- [ ] Middleware transforms data into analytics schema
- [ ] Reconciliation CronJob runs successfully (first manual trigger)

### Applications
- [ ] Each Container App responds on /healthz
- [ ] ADR: Login.gov OIDC flow works for external parties
- [ ] ADR: Entra ID login works for staff
- [ ] Triage: Entra ID login, file upload, AI classification
- [ ] UDIP: AI Assistant responds to queries, charts render
- [ ] OGC: Entra ID login (no demo), case analysis works
- [ ] ARC Integration API: health check, ARC OAuth2 token acquisition

### MCP Hub (see separate guide)
- [ ] APIM deployed and routing
- [ ] Aggregator function returning merged tool catalog
- [ ] Tool calls routing to correct spokes

### Security
- [ ] All endpoints require authentication (test unauthenticated request → 401)
- [ ] RLS: regional user sees only their region's data
- [ ] PII: tier 1 user cannot see tier 3 columns
- [ ] Audit: tool invocations appear in hubauditlog table
- [ ] WORM: audit blobs cannot be deleted

---

## Quick Reference: All Resource Names

| Resource | Name | Type |
|----------|------|------|
| Resource Group | `rg-eeoc-ai-platform-prod` | Resource Group |
| VNet | `vnet-eeoc-ai-platform` | Virtual Network |
| Key Vault | `kv-eeoc-ai-prod` | Key Vault |
| Storage | `steeocaiaudit` | Storage Account |
| PostgreSQL Primary | `pg-eeoc-udip-prod` | Flexible Server |
| PostgreSQL Replica | `pg-eeoc-udip-prod-replica` | Read Replica |
| Redis | `redis-eeoc-ai-prod` | Cache for Redis |
| Event Hub | `evhns-eeoc-cdc-prod` | Event Hubs Namespace |
| Container Apps Env | `cae-eeoc-ai-prod` | Container Apps Environment |
| Front Door | `fd-eeoc-adr-prod` | Front Door Profile |
| WAF | `waf-eeoc-adr-prod` | WAF Policy |
| Azure OpenAI | `oai-eeoc-ai-prod` | OpenAI Service |
| Search | `search-eeoc-triage-prod` | AI Search |
| App Insights | `appi-eeoc-ai-prod` | Application Insights |
| ADR Functions | `func-eeoc-adr-prod` | Function App |
| Triage Functions | `func-eeoc-triage-prod` | Function App |
