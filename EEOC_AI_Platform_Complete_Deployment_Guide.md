# EEOC AI Integration Platform — Complete Deployment Guide

**Classification:** CUI // FOUO
**Version:** 1.0
**Last Updated:** 2026-04-06
**Owner:** OCIO Platform Team

---

## Table of Contents

- [Part 0: What You're Building](#part-0-what-youre-building)
- [Part 1: Prerequisites Checklist](#part-1-prerequisites-checklist)
- [Part 2: Azure Portal Steps](#part-2-azure-portal-steps)
  - [2.1 Resource Group](#21-resource-group)
  - [2.2 Virtual Network](#22-virtual-network)
  - [2.3 Key Vault](#23-key-vault)
  - [2.4 Storage Account](#24-storage-account)
  - [2.5 Azure Container Registry](#25-azure-container-registry)
  - [2.6 Azure Database for PostgreSQL](#26-azure-database-for-postgresql-flexible-server)
  - [2.7 PgBouncer](#27-pgbouncer-container-app)
  - [2.8 Azure Cache for Redis](#28-azure-cache-for-redis)
  - [2.9 Azure Event Hub Namespace](#29-azure-event-hub-namespace)
  - [2.10 Azure OpenAI](#210-azure-openai)
  - [2.11 Azure Cognitive Search](#211-azure-cognitive-search)
  - [2.12 Entra ID App Registrations](#212-entra-id-app-registrations)
  - [2.13 Container Apps Environment](#213-container-apps-environment)
  - [2.14 Deploy Container Apps](#214-deploy-container-apps)
  - [2.15 Azure Functions](#215-azure-functions)
  - [2.16 Azure API Management (MCP Hub)](#216-azure-api-management-mcp-hub)
  - [2.17 Azure Event Grid](#217-azure-event-grid)
  - [2.18 Azure Front Door + WAF](#218-azure-front-door--waf)
  - [2.19 Azure Sentinel (M-21-31 EL3)](#219-azure-sentinel-m-21-31-el3)
  - [2.20 Application Insights + Log Analytics](#220-application-insights--log-analytics)
  - [2.21 Azure Monitor Alert Rules](#221-azure-monitor-alert-rules)
- [Part 3: ARC DBA Coordination](#part-3-arc-dba-coordination)
- [Part 4: Post-Provisioning Configuration](#part-4-post-provisioning-configuration)
- [Part 5: First Data Flow Verification](#part-5-first-data-flow-verification)
- [Part 6: Going Live Checklist](#part-6-going-live-checklist)
- [Part 7: Troubleshooting](#part-7-troubleshooting)
- [Appendix A: All Resource Names](#appendix-a-all-resource-names)
- [Appendix B: All Environment Variables by Application](#appendix-b-all-environment-variables-by-application)
- [Appendix C: All Key Vault Secrets](#appendix-c-all-key-vault-secrets)
- [Appendix D: All Entra ID App Registrations and Roles](#appendix-d-all-entra-id-app-registrations-and-roles)
- [Appendix E: Network Diagram](#appendix-e-network-diagram)

---

## Part 0: What You're Building

### Architecture Overview

```
                          ┌──────────────────┐
                          │   Azure Front     │
                          │   Door + WAF      │  ← public internet (ADR only)
                          └────────┬─────────┘
                                   │
          ┌────────────────────────┼─────────────────────────┐
          │                  VNet 10.100.0.0/16               │
          │                                                   │
          │  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
          │  │ ADR      │  │ Triage   │  │ OGC Trial    │   │
          │  │ Mediation│  │ (OFS)    │  │ Tool         │   │
          │  │ :8000    │  │ :8000    │  │ App Service  │   │
          │  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
          │       │             │               │            │
          │       ├─────────────┼───────────────┤            │
          │       │             │               │            │
          │  ┌────▼─────────────▼───────────────▼────────┐   │
          │  │         Azure API Management               │   │
          │  │         (MCP Hub — tool routing)            │   │
          │  └────┬─────────────┬───────────────┬────────┘   │
          │       │             │               │            │
          │  ┌────▼─────┐ ┌────▼──────┐  ┌─────▼───────┐   │
          │  │ ARC      │ │ UDIP      │  │ Hub         │   │
          │  │ Integr.  │ │ Analytics │  │ Aggregator  │   │
          │  │ API      │ │ + AI Asst │  │ Function    │   │
          │  │ :8000    │ │ :5000     │  │             │   │
          │  └────┬─────┘ └────┬──────┘  └─────────────┘   │
          │       │            │                             │
          │       │       ┌────▼──────────────────┐         │
          │       │       │ PgBouncer :6432        │         │
          │       │       └────┬──────────────────┘         │
          │       │            │                             │
          │       │       ┌────▼──────────────────┐         │
          │       │       │ PostgreSQL Flex Server │         │
          │       │       │ 16 vCores / 128 GB    │         │
          │       │       │ + Read Replica         │         │
          │       │       └───────────────────────┘         │
          │       │                                          │
          │       │  ┌──────────┐  ┌─────────────────────┐  │
          │       │  │ Event Hub│  │ Debezium Connect    │  │
          │       └──│ (Kafka)  │◄─│ (WAL/CDC consumer)  │  │
          │          └──────────┘  └─────────────────────┘  │
          │                                                  │
          │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
          │  │ Key Vault│  │ Redis    │  │ Cog. Search  │  │
          │  └──────────┘  └──────────┘  └──────────────┘  │
          └──────────────────────────────────────────────────┘
                                   │
                          ┌────────▼─────────┐
                          │  ARC Backbone     │
                          │  (PrEPA + FEPA)   │
                          │  read-only access │
                          └──────────────────┘
```

### What Each Component Does

| Component | What It Does |
|-----------|-------------|
| **UDIP Analytics** | Central data store. Holds copied ARC data, analytics tables, and the AI Assistant that answers plain-language questions about EEOC case data and renders charts. |
| **ADR Mediation** | Public-facing mediation case management. Staff and external parties (via Login.gov) schedule mediations, track cases, record outcomes. Writes results back to ARC. |
| **OFS Triage** | Charge classification using GPT-4o. Staff upload charge documents, the model classifies them, results go back to ARC. Internal-only. |
| **OGC Trial Tool** | Litigation support for the Office of General Counsel. Case analysis, document indexing, trial preparation. Internal-only. |
| **ARC Integration API** | Bridge to ARC. Pushes case data to ADR/Triage, accepts write-backs (mediation outcomes, classifications), forwards Service Bus events. |
| **MCP Hub** | Azure API Management routes AI tool calls to the right spoke. A thin aggregator function merges tool catalogs from all 5 spokes. |
| **WAL/CDC Pipeline** | Streams every database change from PrEPA's PostgreSQL (ARC's system of record) into UDIP via Debezium and Event Hub. No impact on ARC — reads the existing transaction log. |
| **Data Middleware** | YAML-driven translation layer. Renames ARC's internal column labels to clear names, redacts PII per tier, validates data types. |

### Expected Outcome

When deployment is complete, an EEOC analyst can open UDIP, type "Show me the top 10 offices by mediation settlement rate this quarter" and get a chart back. ADR mediators can schedule sessions and record outcomes that flow back into ARC. Triage staff can upload charge documents and get AI-driven classifications. All of this runs on Azure Government under FedRAMP High controls, with 7-year NARA-compliant audit trails.

---

## Part 1: Prerequisites Checklist

Complete every item before touching Azure. Missing any of these will block you mid-deployment.

### Access and Permissions

| Prerequisite | Description | Status |
|-------------|-------------|--------|
| Azure Government subscription | Active subscription with Contributor role assigned to your account | [ ] |
| Global Administrator access | Entra ID Global Admin or Application Administrator — needed for app registrations (Section 2.12) | [ ] |
| GitHub access | Read access to all 6 repositories (eeoc-ofs-adr, eeoc-ofs-triage, eeoc-data-analytics-and-dashboard, eeoc-ogc-trialtool, eeoc-arc-integration-api, eeoc-mcp-hub-functions) | [ ] |

### External Dependencies

| Prerequisite | Description | Status |
|-------------|-------------|--------|
| ARC DBA contact info | Name and email of the PrEPA database administrator who will run 2 SQL commands | [ ] |
| ARC REST API credentials | OAuth2 client_id and client_secret for PrEPA Web Service and FEPA Gateway | [ ] |
| TLS certificate for ADR | PFX-format certificate for the ADR public domain (e.g., `adr.eeoc.gov`) | [ ] |
| DNS control for ADR domain | Ability to create a CNAME record pointing to Azure Front Door | [ ] |
| Login.gov integration (ADR) | Client ID and PKCS#8 private key for Login.gov OIDC integration | [ ] |

### Docker Images

| Prerequisite | Description | Status |
|-------------|-------------|--------|
| Docker images built | All 10 container images built from the 6 repositories | [ ] |
| Images pushed to ACR | Images tagged and pushed to Azure Container Registry (created in Section 2.5) | [ ] |

### Notification Contacts

| Prerequisite | Description | Status |
|-------------|-------------|--------|
| Alert email addresses | Email addresses for: platform team, security team, on-call rotation | [ ] |

### Fill-In-The-Blank Worksheet

Collect these values now. You will enter them repeatedly during deployment.

| Value | Where to Get It | Your Value |
|-------|----------------|------------|
| Subscription ID | Azure Portal > Subscriptions | __________________ |
| Tenant ID | Entra ID > Overview > Tenant ID | __________________ |
| ADR public domain | DNS team (e.g., `adr.eeoc.gov`) | __________________ |
| ARC OAuth2 client_id | ARC team | __________________ |
| ARC OAuth2 client_secret | ARC team | __________________ |
| ARC Gateway URL | ARC team (e.g., `https://fepa-gateway.eeoc.gov`) | __________________ |
| ARC PrEPA URL | ARC team (e.g., `https://prepa.eeoc.gov`) | __________________ |
| ARC Auth URL | ARC team (e.g., `https://auth.eeoc.gov/oauth2/token`) | __________________ |
| Login.gov Client ID | Login.gov dashboard | __________________ |
| Login.gov Private Key path | Login.gov dashboard (PKCS#8 PEM) | __________________ |
| Platform team email | Your team | __________________ |
| Security team email | ISSO/ISSM contact | __________________ |
| TLS certificate path (.pfx) | PKI team or CA | __________________ |
| Mediator AD Group ID | Entra ID group for ADR mediators | __________________ |
| Admin AD Group ID | Entra ID group for platform admins | __________________ |
| Analyst AD Group ID | Entra ID group for UDIP analysts | __________________ |
| Data Steward AD Group ID | Entra ID group for data stewards | __________________ |
| Legal Counsel AD Group ID | Entra ID group for OGC legal counsel | __________________ |

---

## Part 2: Azure Portal Steps

Every step below follows the same pattern: what to search for, what to click, what to type, and what to verify after creation.

> All resources are deployed to **Azure Government** region **US Gov Virginia** (`usgovvirginia`) unless otherwise noted.

### 2.1 Resource Group

**Portal Navigation:** Home > Resource groups > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Region | `US Gov Virginia` |

**Tags Tab:**

| Tag | Value |
|-----|-------|
| Environment | `Production` |
| Project | `EEOC-AI-Platform` |
| Compliance | `FedRAMP-High` |
| CostCenter | `OCIO` |
| Classification | `CUI` |

Click **Review + create**, then **Create**.

**Verify:** The resource group appears in your resource groups list.

---

### 2.2 Virtual Network

**Portal Navigation:** Home > Virtual networks > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Name | `vnet-eeoc-ai-prod` |
| Region | `US Gov Virginia` |

**IP Addresses Tab:**

| Setting | Value |
|---------|-------|
| Address space | `10.100.0.0/16` |

Create the following 7 subnets:

| Subnet Name | Address Range | Service Endpoints | Delegation | Notes |
|-------------|--------------|-------------------|------------|-------|
| `snet-apps` | `10.100.1.0/24` | Microsoft.KeyVault, Microsoft.Storage | Microsoft.App/environments | Container Apps |
| `snet-postgres` | `10.100.2.0/24` | — | Microsoft.DBforPostgreSQL/flexibleServers | Database |
| `snet-redis` | `10.100.3.0/24` | — | — | Redis private endpoint |
| `snet-storage` | `10.100.4.0/24` | — | — | Storage private endpoint |
| `snet-keyvault` | `10.100.5.0/24` | — | — | Key Vault private endpoint |
| `snet-eventhub` | `10.100.6.0/24` | — | — | Event Hub private endpoint |
| `snet-frontdoor` | `10.100.7.0/24` | — | — | Front Door backend |

To add each subnet: Click **+ Add a subnet**, fill in the name, address range, service endpoints, and delegation, then click **Add**.

**Security Tab:**

Leave BastionHost and DDoS Protection as defaults (disabled). DDoS is managed at the subscription level for Azure Government.

Click **Review + create**, then **Create**.

**Verify:** Navigate to the VNet. Under **Subnets**, all 7 subnets appear with the correct CIDR ranges.

#### Network Security Groups

Create one NSG per subnet that hosts application workloads.

**Portal Navigation:** Home > Network security groups > + Create

**NSG: `nsg-eeoc-apps-prod`** (for snet-apps):

| Setting | Value |
|---------|-------|
| Resource group | `rg-eeoc-ai-platform-prod` |
| Name | `nsg-eeoc-apps-prod` |
| Region | `US Gov Virginia` |

After creation, add these inbound rules:

| Priority | Name | Source | Destination | Port | Protocol | Action |
|----------|------|--------|-------------|------|----------|--------|
| 100 | AllowFrontDoor | Service Tag: AzureFrontDoor.Backend | Any | 443 | TCP | Allow |
| 110 | AllowVnetInternal | VirtualNetwork | VirtualNetwork | 443,8000,8088,5000 | TCP | Allow |
| 4096 | DenyAllInbound | Any | Any | * | Any | Deny |

> NSG is stateful — outbound connections from apps to Redis (6380) and PgBouncer (6432) automatically allow return traffic. No inbound rules needed for those flows on this NSG.

Associate `nsg-eeoc-apps-prod` with `snet-apps`: Go to NSG > Settings > Subnets > + Associate > select VNet and subnet.

**NSG: `nsg-eeoc-postgres-prod`** (for snet-postgres):

| Priority | Name | Source | Destination | Port | Protocol | Action |
|----------|------|--------|-------------|------|----------|--------|
| 100 | AllowAppsSubnet | `10.100.1.0/24` | Any | 5432 | TCP | Allow |
| 110 | AllowPgBouncer | `10.100.1.0/24` | Any | 6432 | TCP | Allow |
| 4096 | DenyAllInbound | Any | Any | * | Any | Deny |

Associate with `snet-postgres`.

---

### 2.3 Key Vault

**Portal Navigation:** Home > Key vaults > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Key vault name | `kv-eeoc-ai-prod` |
| Region | `US Gov Virginia` |
| Pricing tier | `Standard` |
| Days to retain deleted vaults | `90` |
| Purge protection | `Enable` |

**Access configuration Tab:**

| Setting | Value |
|---------|-------|
| Permission model | `Azure role-based access control` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Public access | `Disable` |
| Private endpoint | Create new |

Private endpoint settings:

| Setting | Value |
|---------|-------|
| Name | `pe-kv-eeoc-ai-prod` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-keyvault` |
| Integrate with private DNS zone | `Yes` |

Click **Review + create**, then **Create**.

**Verify:** Navigate to Key Vault > Networking. Public access should show "Disabled". Private endpoint should be listed.

#### Generate and Store Secrets

Navigate to Key Vault > Secrets > + Generate/Import for each secret below.

Run these commands from a machine with Azure CLI access to generate random values:

```bash
# HMAC keys for audit log integrity
openssl rand -base64 40   # → HUB-AUDIT-HMAC-KEY
openssl rand -base64 40   # → ARC-AUDIT-HMAC-KEY

# hash salts
openssl rand -base64 40   # → HUB-AUDIT-HASH-SALT

# webhook secrets (one per spoke)
openssl rand -base64 32   # → MCP-WEBHOOK-SECRET-ADR
openssl rand -base64 32   # → MCP-WEBHOOK-SECRET-TRIAGE
openssl rand -base64 32   # → MCP-WEBHOOK-SECRET-ARC-INTEGRATION
openssl rand -base64 32   # → MCP-WEBHOOK-SECRET-OGC
openssl rand -base64 32   # → MCP-WEBHOOK-SECRET-UDIP

# database admin password
openssl rand -base64 24   # → PG-ADMIN-PASSWORD

# Flask secret keys
openssl rand -hex 32      # → ADR-FLASK-SECRET
openssl rand -hex 32      # → TRIAGE-FLASK-SECRET
openssl rand -hex 32      # → OGC-FLASK-SECRET

# Superset secret key
openssl rand -hex 32      # → SUPERSET-SECRET-KEY
```

Store each generated value in Key Vault. Full secret list in [Appendix C](#appendix-c-all-key-vault-secrets).

> Record each generated value before storing — Key Vault will not show it again unless you have Get permission. Use the "Show Secret Value" button to verify immediately after creation.

---

### 2.4 Storage Account

**Portal Navigation:** Home > Storage accounts > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Storage account name | `steeocaiprod` |
| Region | `US Gov Virginia` |
| Performance | `Standard` |
| Redundancy | `Geo-redundant storage (GRS)` |

**Advanced Tab:**

| Setting | Value |
|---------|-------|
| Require secure transfer | `Enabled` |
| Allow Blob public access | `Disabled` |
| Minimum TLS version | `TLS 1.2` |
| Enable hierarchical namespace | `Disabled` |
| Enable blob versioning | `Enabled` |
| Enable blob soft delete | `Enabled` (7 days) |
| Enable container soft delete | `Enabled` (7 days) |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Public access | `Disabled` |
| Private endpoint | Create new |

Private endpoint:

| Setting | Value |
|---------|-------|
| Name | `pe-st-eeoc-ai-prod` |
| Target sub-resource | `blob` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-storage` |
| Integrate with private DNS zone | `Yes` |

Add a second private endpoint for `table` sub-resource using the same subnet and DNS zone settings.

Click **Review + create**, then **Create**.

#### Create Blob Containers

Navigate to Storage account > Containers > + Container for each:

| Container Name | Public access level | Immutability Policy |
|---------------|-------------------|-------------------|
| `hub-audit-archive` | Private | WORM: 2555 days (7 years), locked |
| `arc-integration-archive` | Private | WORM: 2555 days (7 years), locked |
| `adr-case-files` | Private | None |
| `adr-quarantine` | Private | None |
| `triage-processing` | Private | None |
| `triage-archival` | Private | None |
| `function-locks` | Private | None |
| `lifecycle-archives` | Private | None |
| `foia-exports` | Private | None |
| `ai-generation-archive` | Private | WORM: 2555 days (7 years), locked |
| `drift-snapshots` | Private | None |
| `stats-exports` | Private | None |

To set a WORM policy: click the container > Settings > Access policy > Add policy > select **Time-based retention** > set retention period to **2555 days** > **Lock** the policy.

> Once locked, a WORM policy cannot be shortened or removed. Verify the retention period is correct before locking.

#### Create Storage Tables

Navigate to Storage account > Tables > + Table for each:

| Table Name | Used By |
|-----------|---------|
| `hubauditlog` | MCP Hub — request audit log |
| `mcpspokes` | MCP Hub — spoke registry |
| `arcintegrationaudit` | ARC Integration API — audit log |

**Verify:** Navigate to Containers and Tables tabs. All entries listed with correct access levels.

---

### 2.5 Azure Container Registry

**Portal Navigation:** Home > Container registries > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Registry name | `acreeocaiprod` |
| Region | `US Gov Virginia` |
| SKU | `Premium` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Public access | `Disabled` |
| Private endpoint | Create new |

Private endpoint:

| Setting | Value |
|---------|-------|
| Name | `pe-acr-eeoc-ai-prod` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-apps` |

Click **Review + create**, then **Create**.

#### Push Docker Images

From your build machine with Docker access:

```bash
az acr login --name acreeocaiprod

# tag and push each image (repeat for all 10 images)
docker tag eeoc-udip-superset:latest acreeocaiprod.azurecr.us/udip/superset:v1.0.0
docker push acreeocaiprod.azurecr.us/udip/superset:v1.0.0

docker tag eeoc-udip-ai-assistant:latest acreeocaiprod.azurecr.us/udip/ai-assistant:v1.0.0
docker push acreeocaiprod.azurecr.us/udip/ai-assistant:v1.0.0

docker tag eeoc-udip-data-middleware:latest acreeocaiprod.azurecr.us/udip/data-middleware:v1.0.0
docker push acreeocaiprod.azurecr.us/udip/data-middleware:v1.0.0

docker tag eeoc-debezium-connect:latest acreeocaiprod.azurecr.us/udip/debezium-connect:v1.0.0
docker push acreeocaiprod.azurecr.us/udip/debezium-connect:v1.0.0

docker tag eeoc-udip-portal-nginx:latest acreeocaiprod.azurecr.us/udip/portal-nginx:v1.0.0
docker push acreeocaiprod.azurecr.us/udip/portal-nginx:v1.0.0

docker tag eeoc-adr-webapp:latest acreeocaiprod.azurecr.us/adr/webapp:v1.0.0
docker push acreeocaiprod.azurecr.us/adr/webapp:v1.0.0

docker tag eeoc-adr-functionapp:latest acreeocaiprod.azurecr.us/adr/functionapp:v1.0.0
docker push acreeocaiprod.azurecr.us/adr/functionapp:v1.0.0

docker tag eeoc-triage-webapp:latest acreeocaiprod.azurecr.us/triage/webapp:v1.0.0
docker push acreeocaiprod.azurecr.us/triage/webapp:v1.0.0

docker tag eeoc-triage-functionapp:latest acreeocaiprod.azurecr.us/triage/functionapp:v1.0.0
docker push acreeocaiprod.azurecr.us/triage/functionapp:v1.0.0

docker tag eeoc-arc-integration-api:latest acreeocaiprod.azurecr.us/arc/integration-api:v1.0.0
docker push acreeocaiprod.azurecr.us/arc/integration-api:v1.0.0
```

**Verify:** Navigate to ACR > Repositories. All 10 images appear with v1.0.0 tag.

---

### 2.6 Azure Database for PostgreSQL Flexible Server

**Portal Navigation:** Home > Azure Database for PostgreSQL flexible servers > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Server name | `pg-eeoc-udip-prod` |
| Region | `US Gov Virginia` |
| PostgreSQL version | `16` |
| Workload type | `Production (Small/Medium-size)` |
| Compute + storage | See below |
| Admin username | `udip_admin` |
| Password | Use value from Key Vault secret `PG-ADMIN-PASSWORD` |

**Compute + storage — Configure server:**

| Setting | Value |
|---------|-------|
| Compute tier | `Memory Optimized` |
| Compute size | `Standard_E16ds_v5` (16 vCores, 128 GB RAM) |
| Storage size | `2048 GiB` (2 TB) |
| Storage auto-grow | `Enabled` |
| Performance tier | `P30` |
| Backup retention | `35 days` |
| Geo-redundant backup | `Enabled` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Connectivity method | `Private access (VNet Integration)` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-postgres` |
| Private DNS zone | Create new: `privatelink.postgres.database.usgovcloudapi.net` |

**Server Parameters Tab (configure after creation):**

Navigate to Server > Settings > Server parameters. Set each value:

| Parameter | Value | Notes |
|-----------|-------|-------|
| `shared_buffers` | `4194304` | 32 GB (25% of RAM); unit is 8 KB pages |
| `effective_cache_size` | `12582912` | 96 GB (75% of RAM); unit is 8 KB pages |
| `work_mem` | `65536` | 64 MB; unit is kB |
| `maintenance_work_mem` | `2097152` | 2 GB; unit is kB |
| `max_connections` | `250` | PgBouncer pools; direct connections are rare |
| `max_parallel_workers` | `16` | match vCores |
| `max_parallel_workers_per_gather` | `4` | |
| `max_worker_processes` | `24` | workers + parallel + maintenance |
| `random_page_cost` | `1.1` | SSD storage |
| `effective_io_concurrency` | `200` | SSD |
| `checkpoint_completion_target` | `0.9` | spread I/O |
| `wal_buffers` | `8192` | 64 MB; unit is 8 KB pages |
| `wal_level` | `logical` | required for CDC/Debezium |
| `max_replication_slots` | `10` | CDC + replica |
| `max_wal_senders` | `10` | CDC + replica |
| `statement_timeout` | `60000` | 60 seconds |
| `idle_in_transaction_session_timeout` | `30000` | 30 seconds |
| `log_min_duration_statement` | `1000` | log queries > 1s |
| `shared_preload_libraries` | `pg_stat_statements` | |

Click **Save** after all parameters are set. The server will restart.

#### Enable Extensions

Connect to the database using `psql` and run:

```sql
CREATE EXTENSION IF NOT EXISTS vector;        -- pgvector for embeddings
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;       -- HMAC, encryption
CREATE EXTENSION IF NOT EXISTS pg_trgm;        -- trigram text search
CREATE EXTENSION IF NOT EXISTS unaccent;       -- accent-insensitive search
```

#### Run Schema Initialization Scripts

From the `eeoc-data-analytics-and-dashboard/analytics-db/postgres/` directory, run scripts in this exact order:

```bash
export PGHOST=pg-eeoc-udip-prod.postgres.database.usgovcloudapi.net
export PGUSER=udip_admin
export PGDATABASE=udip
export PGSSLMODE=require

psql -f 001-extensions.sql
psql -f 002-schemas.sql
psql -f 003-replica-schema.sql
psql -f 010-analytics-tables.sql
psql -f 011-lifecycle-columns.sql
psql -f 012-lifecycle-tables.sql
psql -f 013-lifecycle-views.sql
psql -f 014-adr-triage-tables.sql
psql -f 015-partitioning.sql
psql -f 016-cdc-target-tables.sql
psql -f 020-vector-tables.sql
psql -f 030-document-tables.sql
psql -f 040-rls-policies.sql
psql -f 050-search-functions.sql
psql -f 060-adr-operational-tables.sql
psql -f 061-triage-operational-tables.sql
psql -f 062-operations-rls.sql
psql -f 063-operations-views.sql
psql -f 065-litigation-holds.sql
```

**Verify:** Connect with psql and check:

```sql
\dn                         -- should show: analytics, replica, vectors, documents, search, middleware (operations created by 060-*)
\dt analytics.*             -- should list analytics tables
\dt replica.*               -- should list replica tables
SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pgcrypto', 'pg_trgm');
```

#### Create Read Replica

**Portal Navigation:** Home > pg-eeoc-udip-prod > Settings > Replication > + Create replica

| Setting | Value |
|---------|-------|
| Server name | `pg-eeoc-udip-prod-replica` |
| Region | `US Gov Virginia` (same-region replica) |
| Compute | Same as primary (`Standard_E16ds_v5`) |

The replica inherits server parameters from the primary. It takes 15-30 minutes to provision depending on data volume.

**Verify:** Under Replication, the replica shows "Replicating" status.

---

### 2.7 PgBouncer Container App

PgBouncer pools connections from all applications into a small number of PostgreSQL connections. Without it, the 250-connection limit would be exhausted quickly.

**Portal Navigation:** Home > Container Apps > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Container app name | `ca-pgbouncer-prod` |
| Region | `US Gov Virginia` |
| Container Apps Environment | (create in Section 2.13 first, then come back) |

**Container Tab:**

| Setting | Value |
|---------|-------|
| Image source | `Docker Hub` |
| Image | `bitnami/pgbouncer:latest` |
| CPU | `0.5` |
| Memory | `1 Gi` |

**Environment variables:**

| Name | Value |
|------|-------|
| `PGBOUNCER_DATABASE` | `udip` |
| `PGBOUNCER_PORT` | `6432` |
| `PGBOUNCER_POOL_MODE` | `transaction` |
| `PGBOUNCER_MAX_CLIENT_CONN` | `3000` |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `80` |
| `PGBOUNCER_MAX_DB_CONNECTIONS` | `200` |
| `PGBOUNCER_QUERY_TIMEOUT` | `60` |
| `PGBOUNCER_SERVER_TLS_SSLMODE` | `require` |
| `POSTGRESQL_HOST` | `pg-eeoc-udip-prod.postgres.database.usgovcloudapi.net` |
| `POSTGRESQL_PORT` | `5432` |
| `POSTGRESQL_USERNAME` | `udip_admin` |
| `POSTGRESQL_PASSWORD` | (Key Vault reference: `PG-ADMIN-PASSWORD`) |

**Ingress Tab:**

| Setting | Value |
|---------|-------|
| Ingress | `Enabled` |
| Ingress type | `Internal` (VNet only) |
| Target port | `6432` |
| Transport | `TCP` |

**Scale Tab:**

| Setting | Value |
|---------|-------|
| Min replicas | `2` |
| Max replicas | `4` |

**Verify:** From within the VNet, test connectivity:

```bash
psql "host=ca-pgbouncer-prod.internal.{env-suffix}.usgovcloudapi.net port=6432 dbname=udip user=udip_admin sslmode=require"
```

---

### 2.8 Azure Cache for Redis

**Portal Navigation:** Home > Azure Cache for Redis > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| DNS name | `redis-eeoc-ai-prod` |
| Region | `US Gov Virginia` |
| Cache SKU | `Premium` |
| Cache size | `P1` (6 GB) |

**Advanced Tab:**

| Setting | Value |
|---------|-------|
| Non-TLS port | `Disabled` |
| Minimum TLS version | `1.2` |
| Redis version | `6` |
| Clustering | `Disabled` (for 6 GB, clustering is not needed) |

**Networking Tab (Private Endpoint):**

| Setting | Value |
|---------|-------|
| Connectivity method | `Private endpoint` |

Create private endpoint:

| Setting | Value |
|---------|-------|
| Name | `pe-redis-eeoc-ai-prod` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-redis` |
| Integrate with private DNS zone | `Yes` |

Click **Review + create**, then **Create**.

After creation, navigate to Settings > Access keys. Copy the **Primary connection string** and store it in Key Vault as `REDIS-CONNECTION-STRING`.

**Verify:** Navigate to Redis > Overview. Status shows "Running". Connection test from VNet succeeds.

---

### 2.9 Azure Event Hub Namespace

**Portal Navigation:** Home > Event Hubs > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Namespace name | `evhns-eeoc-cdc-prod` |
| Region | `US Gov Virginia` |
| Pricing tier | `Standard` |
| Throughput units | `4` |
| Enable Auto-Inflate | `Yes` |
| Auto-Inflate Maximum | `10` |

**Advanced Tab:**

| Setting | Value |
|---------|-------|
| Enable Kafka | `Yes` |
| Minimum TLS version | `1.2` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Public access | `Disabled` |
| Private endpoint | Create new |

Private endpoint:

| Setting | Value |
|---------|-------|
| Name | `pe-evh-eeoc-cdc-prod` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-eventhub` |
| Integrate with private DNS zone | `Yes` |

Click **Review + create**, then **Create**.

#### Create Event Hub (Topic)

Navigate to the namespace > + Event Hub:

| Setting | Value |
|---------|-------|
| Name | `prepa-cdc-events` |
| Partition count | `8` |
| Message retention | `7 days` |

#### Create Consumer Group

Navigate to the event hub `prepa-cdc-events` > Consumer groups > + Consumer group:

| Setting | Value |
|---------|-------|
| Name | `udip-middleware` |

After creation, go to Shared access policies > + Add:

| Setting | Value |
|---------|-------|
| Policy name | `debezium-writer` |
| Claims | `Send` |

| Policy name | `udip-reader` |
| Claims | `Listen` |

Copy both connection strings and store in Key Vault:
- `debezium-writer` connection string → `CDC-EVENTHUB-SEND-CONNECTION`
- `udip-reader` connection string → `CDC-EVENTHUB-LISTEN-CONNECTION`

**Verify:** Navigate to Event Hub namespace. Status shows "Active". The event hub `prepa-cdc-events` appears with 8 partitions.

---

### 2.10 Azure OpenAI

**Portal Navigation:** Home > Azure OpenAI > + Create

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Region | `US Gov Virginia` |
| Name | `oai-eeoc-ai-prod` |
| Pricing tier | `Standard S0` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Public access | `Disabled` |
| Private endpoint | Create new |

Private endpoint:

| Setting | Value |
|---------|-------|
| Name | `pe-oai-eeoc-ai-prod` |
| Target sub-resource | `account` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Subnet | `snet-apps` |
| Integrate with private DNS zone | `Yes` |

After creation, deploy models:

Navigate to Azure OpenAI Studio > Deployments > + Create deployment:

| Model | Deployment Name | Version | TPM |
|-------|----------------|---------|-----|
| `gpt-4o` | `gpt-4o` | Latest GA | `30K` |
| `text-embedding-3-small` | `text-embedding-3-small` | Latest GA | `30K` |

#### Grant Managed Identity Access

Each Container App and Function App that calls OpenAI needs the `Cognitive Services OpenAI User` role:

Navigate to oai-eeoc-ai-prod > Access control (IAM) > + Add role assignment:

| Setting | Value |
|---------|-------|
| Role | `Cognitive Services OpenAI User` |
| Assign access to | `Managed identity` |
| Members | Select each Container App / Function App managed identity |

Repeat for: UDIP AI Assistant, ADR webapp, ADR functionapp, Triage webapp, Triage functionapp, OGC webapp.

**Verify:** Navigate to Deployments in OpenAI Studio. Both models show "Succeeded" status.

---

### 2.11 Azure Cognitive Search

Triage uses this for retrieval-augmented generation (RAG) — fetches reference documents during charge classification to ground the model's output.

**Portal Navigation:** Home > Azure AI Search > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Service name | `srch-eeoc-triage-prod` |
| Region | `US Gov Virginia` |
| Pricing tier | `Standard (S1)` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Public access | `Disabled` |
| Private endpoint | Create new — use `snet-apps` subnet |

After creation, navigate to Settings > Keys. Copy the **Primary admin key** and store in Key Vault as `SEARCH-ADMIN-KEY`.

**Verify:** Navigate to Search service. Status shows "Running".

---

### 2.12 Entra ID App Registrations

> This section requires **Global Administrator** or **Application Administrator** role.

You need 6 app registrations. Each app gets specific roles and API permissions.

**Portal Navigation:** Entra ID > App registrations > + New registration

#### Registration 1: EEOC-MCP-Hub

| Setting | Value |
|---------|-------|
| Name | `EEOC-MCP-Hub` |
| Supported account types | `Accounts in this organizational directory only` |
| Redirect URI | (leave blank) |

After creation:
1. Go to **Expose an API** > Set Application ID URI: `api://{client-id}`
2. **Add a scope**: `Hub.Read` (Admin consent required), `Hub.Write` (Admin consent required)
3. Go to **App roles** > Create:
   - `Hub.Read` — allowed member types: Applications — value: `Hub.Read`
   - `Hub.Write` — allowed member types: Applications — value: `Hub.Write`
4. Go to **Certificates & secrets** > + New client secret > description: `hub-m2m` > expires: 24 months
5. Store secret in Key Vault as `HUB-CLIENT-SECRET`

Record: Client ID → `{HUB_CLIENT_ID}`, Tenant ID → `{TENANT_ID}`

#### Registration 2: EEOC-ADR-Mediation

| Setting | Value |
|---------|-------|
| Name | `EEOC-ADR-Mediation` |
| Supported account types | `Accounts in this organizational directory only` |
| Redirect URI | Web: `https://{adr-domain}/auth/callback` |

After creation:
1. **App roles**: `MCP.Read`, `MCP.Write` (Applications)
2. **API permissions** > Add > EEOC-MCP-Hub > Application permissions > `Hub.Read`, `Hub.Write` > Grant admin consent
3. **Certificates & secrets** > New client secret > `adr-m2m` > 24 months
4. Store secret in Key Vault as `ADR-CLIENT-SECRET`

#### Registration 3: EEOC-OFS-Triage

| Setting | Value |
|---------|-------|
| Name | `EEOC-OFS-Triage` |
| Supported account types | `Accounts in this organizational directory only` |
| Redirect URI | Web: `https://triage.internal.eeoc.gov/auth/callback` |

After creation:
1. **App roles**: `MCP.Read`, `MCP.Write` (Applications)
2. **API permissions** > EEOC-MCP-Hub > `Hub.Read`, `Hub.Write` > Grant admin consent
3. **Certificates & secrets** > New client secret > `triage-m2m` > 24 months
4. Store secret in Key Vault as `TRIAGE-CLIENT-SECRET`

#### Registration 4: EEOC-UDIP-Analytics

| Setting | Value |
|---------|-------|
| Name | `EEOC-UDIP-Analytics` |
| Supported account types | `Accounts in this organizational directory only` |
| Redirect URI | Web: `https://udip.eeoc.gov/auth/callback` |

After creation:
1. **App roles**: `Analytics.Read`, `Analytics.Write` (Applications + Users)
2. **API permissions** > EEOC-MCP-Hub > `Hub.Read`, `Hub.Write` > Grant admin consent
3. **Expose an API** > Add scope: `user_impersonation` (for OBO flow)
4. **Certificates & secrets** > New client secret > `udip-m2m` > 24 months
5. Store secret in Key Vault as `UDIP-CLIENT-SECRET`

#### Registration 5: EEOC-OGC-TrialTool

| Setting | Value |
|---------|-------|
| Name | `EEOC-OGC-TrialTool` |
| Supported account types | `Accounts in this organizational directory only` |
| Redirect URI | Web: `https://ogc-trialtool.eeoc.gov/auth/callback` |

After creation:
1. **App roles**: `MCP.Read`, `MCP.Write` (Applications)
2. **API permissions** > EEOC-MCP-Hub > `Hub.Read`, `Hub.Write` > Grant admin consent
3. **Certificates & secrets** > New client secret > `ogc-m2m` > 24 months
4. Store secret in Key Vault as `OGC-CLIENT-SECRET`

#### Registration 6: EEOC-ARC-Integration

| Setting | Value |
|---------|-------|
| Name | `EEOC-ARC-Integration` |
| Supported account types | `Accounts in this organizational directory only` |
| Redirect URI | (leave blank — M2M only) |

After creation:
1. **App roles**: `ARC.Read`, `ARC.Write` (Applications)
2. **API permissions** > EEOC-MCP-Hub > `Hub.Read`, `Hub.Write` > Grant admin consent
3. **Certificates & secrets** > New client secret > `arc-m2m` > 24 months
4. Store secret in Key Vault as `ARC-INTEGRATION-CLIENT-SECRET`

**Verify:** Navigate to Entra ID > App registrations. All 6 apps appear. Each has the correct roles and API permissions with admin consent granted.

See [Appendix D](#appendix-d-all-entra-id-app-registrations-and-roles) for the complete role/permission matrix.

---

### 2.13 Container Apps Environment

**Portal Navigation:** Home > Container Apps Environments > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Environment name | `cae-eeoc-ai-prod` |
| Region | `US Gov Virginia` |
| Environment type | `Workload profiles` |
| Zone redundancy | `Enabled` |

**Monitoring Tab:**

| Setting | Value |
|---------|-------|
| Log destination | `Azure Log Analytics` |
| Log Analytics workspace | (create new: `log-eeoc-ai-prod`) |
| Retention | `365 days` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Use your own virtual network | `Yes` |
| Virtual network | `vnet-eeoc-ai-prod` |
| Infrastructure subnet | `snet-apps` |
| Internal | `Yes` (internal-only except ADR via Front Door) |

Click **Review + create**, then **Create**. This takes 5-10 minutes.

**Verify:** Navigate to Container Apps Environment. Status shows "Succeeded". The Log Analytics workspace is linked.

---

### 2.14 Deploy Container Apps

Deploy each application as a Container App within the `cae-eeoc-ai-prod` environment.

> Deploy PgBouncer first (Section 2.7), then these applications.

#### 2.14.1 UDIP AI Assistant

**Portal Navigation:** Container Apps > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Container app name | `ca-udip-ai-assistant-prod` |
| Container Apps Environment | `cae-eeoc-ai-prod` |

**Container Tab:**

| Setting | Value |
|---------|-------|
| Image source | `Azure Container Registry` |
| Registry | `acreeocaiprod` |
| Image | `udip/ai-assistant` |
| Tag | `v1.0.0` |
| CPU | `2` |
| Memory | `2 Gi` |

Environment variables — see [Appendix B](#appendix-b-all-environment-variables-by-application) for the full list. Key settings:

| Name | Source | Value |
|------|--------|-------|
| `FLASK_ENV` | Manual | `production` |
| `AI_ASSISTANT_PORT` | Manual | `5000` |
| `OPENAI_API_BASE` | Manual | `https://oai-eeoc-ai-prod.openai.azure.us/` |
| `OPENAI_API_VERSION` | Manual | `2024-02-01` |
| `OPENAI_DEPLOYMENT` | Manual | `gpt-4o` |
| `AI_MODEL_PROVIDER` | Manual | `azure_openai` |
| `PG_AI_HOST` | Manual | `ca-pgbouncer-prod` (PgBouncer internal FQDN) |
| `PG_AI_PORT` | Manual | `6432` |
| `PG_AI_DATABASE` | Manual | `udip` |
| `PG_AI_SSLMODE` | Manual | `require` |
| `REDIS_URL` | Secret ref | Key Vault: `REDIS-CONNECTION-STRING` |
| `OPENAI_API_KEY` | Secret ref | Key Vault: `OPENAI-API-KEY` |
| `FLASK_SECRET_KEY` | Secret ref | Key Vault: `UDIP-FLASK-SECRET` |

**Ingress Tab:**

| Setting | Value |
|---------|-------|
| Ingress | `Enabled` |
| Ingress type | `Internal` |
| Target port | `5000` |

**Scale Tab:**

| Setting | Value |
|---------|-------|
| Min replicas | `2` |
| Max replicas | `6` |
| Scale rule | CPU: 70% |

**Health Probes:**

| Probe | Path | Port | Period |
|-------|------|------|--------|
| Liveness | `/healthz` | `5000` | 30s |
| Readiness | `/healthz` | `5000` | 10s |
| Startup | `/healthz` | `5000` | 5s (failure threshold: 30) |

#### 2.14.2 UDIP Superset

| Setting | Value |
|---------|-------|
| Container app name | `ca-udip-superset-prod` |
| Image | `udip/superset:v1.0.0` |
| CPU | `2` |
| Memory | `4 Gi` |
| Target port | `8088` |
| Min/Max replicas | `2` / `4` |
| Scale rule | CPU: 70% |
| Liveness path | `/health` |

#### 2.14.3 Debezium Connect (CDC)

| Setting | Value |
|---------|-------|
| Container app name | `ca-debezium-connect-prod` |
| Image | `udip/debezium-connect:v1.0.0` |
| CPU | `2` |
| Memory | `4 Gi` |
| Target port | `8083` |
| Min/Max replicas | `1` / `2` |
| Liveness path | `/connectors` |
| Readiness path | `/connectors/prepa-postgresql-connector/status` |

Key environment variables:

| Name | Value |
|------|-------|
| `BOOTSTRAP_SERVERS` | `evhns-eeoc-cdc-prod.servicebus.usgovcloudapi.net:9093` |
| `GROUP_ID` | `debezium-connect` |
| `CONNECT_KEY_CONVERTER` | `org.apache.kafka.connect.json.JsonConverter` |
| `CONNECT_VALUE_CONVERTER` | `org.apache.kafka.connect.json.JsonConverter` |

Plus Kafka SASL/SSL configuration pointing to Event Hub.

#### 2.14.4 ARC Integration API

| Setting | Value |
|---------|-------|
| Container app name | `ca-arc-integration-prod` |
| Image | `arc/integration-api:v1.0.0` |
| CPU | `1` |
| Memory | `2 Gi` |
| Target port | `8000` |
| Min/Max replicas | `2` / `4` |
| Scale rule | CPU: 70% |
| Liveness path | `/healthz` |

Key environment variables:

| Name | Source | Value |
|------|--------|-------|
| `AZURE_TENANT_ID` | Manual | `{TENANT_ID}` |
| `AZURE_CLIENT_ID` | Manual | `{ARC_INTEGRATION_CLIENT_ID}` |
| `ARC_GATEWAY_URL` | Manual | `{from worksheet}` |
| `ARC_PREPA_URL` | Manual | `{from worksheet}` |
| `ARC_AUTH_URL` | Manual | `{from worksheet}` |
| `KEY_VAULT_URI` | Manual | `https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/` |
| `RATE_LIMIT_PER_MINUTE` | Manual | `120` |
| `ARC_CLIENT_SECRET` | Secret ref | Key Vault |
| `MCP_HUB_HMAC_SECRET` | Secret ref | Key Vault |
| `REDIS_URL` | Secret ref | Key Vault |

#### 2.14.5 ADR Web Application

| Setting | Value |
|---------|-------|
| Container app name | `ca-adr-webapp-prod` |
| Image | `adr/webapp:v1.0.0` |
| CPU | `2` |
| Memory | `4 Gi` |
| Target port | `8000` |
| Min/Max replicas | `3` / `12` |
| Scale rule | CPU: 65% |
| Liveness path | `/healthz` |

Key environment variables:

| Name | Value |
|------|-------|
| `FLASK_ENV` | `production` |
| `SESSION_TIMEOUT_MINUTES` | `30` |
| `MAX_CONTENT_LENGTH` | `52428800` |
| `MCP_ENABLED` | `true` |
| `GUNICORN_WORKERS` | `4` |
| `GUNICORN_WORKER_CLASS` | `gevent` |
| `AI_MODEL_PROVIDER` | `azure_openai` |

#### 2.14.6 ADR Function App

| Setting | Value |
|---------|-------|
| Container app name | `ca-adr-functionapp-prod` |
| Image | `adr/functionapp:v1.0.0` |
| CPU | `1` |
| Memory | `2 Gi` |
| Target port | `80` |
| Min/Max replicas | `2` / `6` |
| Scale rule | CPU: 70% |
| Liveness path | `/api/health` |

Key environment variables:

| Name | Value |
|------|-------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` |
| `ARC_SYNC_SCHEDULE` | `0 */15 * * * *` |
| `DISPOSITION_RETENTION_DAYS` | `2555` |

#### 2.14.7 Triage Web Application

| Setting | Value |
|---------|-------|
| Container app name | `ca-triage-webapp-prod` |
| Image | `triage/webapp:v1.0.0` |
| CPU | `1` |
| Memory | `2 Gi` |
| Target port | `8000` |
| Min/Max replicas | `2` / `6` |
| Scale rule | CPU: 70% |
| Liveness path | `/healthz` |

#### 2.14.8 Triage Function App

| Setting | Value |
|---------|-------|
| Container app name | `ca-triage-functionapp-prod` |
| Image | `triage/functionapp:v1.0.0` |
| CPU | `2` |
| Memory | `4 Gi` |
| Target port | `80` |
| Min/Max replicas | `2` / `8` |
| Scale rule | CPU: 60% |
| Liveness path | `/healthz` |

> Triage function app uses more resources than ADR because AI classification and ZIP extraction are CPU/memory-intensive.

#### 2.14.9 MCP Hub Aggregator Function

| Setting | Value |
|---------|-------|
| Container app name | `ca-mcp-hub-func-prod` |
| Image | `acreeocaiprod.azurecr.us/hub/aggregator-function:v1.0.0` |
| CPU | `0.5` |
| Memory | `1 Gi` |
| Target port | `80` |
| Min/Max replicas | `2` / `4` |
| Liveness path | `/api/tools` (GET) |

Environment variables:

| Name | Value |
|------|-------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` |
| `REDIS_URL` | Key Vault ref |
| `KEY_VAULT_URI` | `https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/` |
| `RECONCILIATION_INTERVAL_SECONDS` | `300` |
| `MAX_TOOLS_PER_CONTEXT` | `15` |
| `SPOKE_REQUEST_TIMEOUT_SECONDS` | `30` |

#### 2.14.10 Portal Nginx (UDIP)

| Setting | Value |
|---------|-------|
| Container app name | `ca-udip-portal-prod` |
| Image | `udip/portal-nginx:v1.0.0` |
| CPU | `0.25` |
| Memory | `512 Mi` |
| Target port | `8080` |
| Min/Max replicas | `2` / `4` |

This is a reverse proxy for UDIP services (Superset, AI Assistant, JupyterHub).

**Verify for all Container Apps:** Navigate to each app > Overview. Status shows "Running". Revision shows active. Check Logs for any startup errors.

---

### 2.15 Azure Functions

ADR and Triage function apps are deployed as Container Apps (Sections 2.14.6 and 2.14.8). OGC uses Azure App Service.

#### OGC Trial Tool (App Service)

OGC runs on Azure App Service in Azure Government, not Container Apps. It has its own provisioning script (`provision_ogc_trialtool.sh` in the OGC repo) that handles:
- App Service Plan (Premium V3 P1V3)
- Web App (Python 3.11)
- Function App for document indexing
- Application Gateway + WAF
- Redis, Key Vault, Storage (all within the OGC resource group)

Run the OGC provisioning script separately:

```bash
cd eeoc-ogc-trialtool/
./provision_ogc_trialtool.sh \
  --rg-name eeoc-ogc-prod-va \
  --suffix va001 \
  --location usgovvirginia \
  --tenant-id {TENANT_ID}
```

After provisioning, configure the OGC app settings to point to the shared MCP Hub and OpenAI endpoints.

---

### 2.16 Azure API Management (MCP Hub)

APIM acts as the MCP Hub router. It receives tool calls from the AI Assistant, identifies which spoke owns the requested tool, and routes the request.

> For full MCP Hub configuration, follow the detailed guide at `Azure_MCP_Hub_Setup_Guide.md`. This section covers the high-level steps.

**Portal Navigation:** Home > API Management services > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Region | `US Gov Virginia` |
| Resource name | `apim-eeoc-mcp-hub-prod` |
| Organization name | `EEOC OCIO` |
| Administrator email | `{platform team email}` |
| Pricing tier | `Standard v2` |

**Networking Tab:**

| Setting | Value |
|---------|-------|
| Connectivity type | `Virtual network — Internal` |
| Virtual network | `vnet-eeoc-ai-prod` |

After creation (takes 30-45 minutes):

1. **Configure backends** — one per spoke:

| Backend ID | URL | Description |
|-----------|-----|-------------|
| `adr-spoke` | `https://ca-adr-webapp-prod.internal.{env}/api/mcp` | ADR MCP endpoint |
| `triage-spoke` | `https://ca-triage-webapp-prod.internal.{env}/api/mcp` | Triage MCP endpoint |
| `udip-spoke` | `https://ca-udip-ai-assistant-prod.internal.{env}/api/mcp` | UDIP MCP endpoint |
| `arc-spoke` | `https://ca-arc-integration-prod.internal.{env}/api/mcp` | ARC Integration MCP endpoint |
| `ogc-spoke` | `https://app-ogctrialtool-web.azurewebsites.us/api/mcp` | OGC MCP endpoint |
| `hub-aggregator` | `https://ca-mcp-hub-func-prod.internal.{env}/api` | Hub aggregator function |

2. **Create API** — POST `/mcp` with tool-prefix routing policies
3. **Create API** — GET `/mcp/tools` routed to hub-aggregator
4. **Add inbound policies** — validate Entra ID JWT, set X-Request-ID header, route by tool prefix
5. **Add outbound policies** — log to Application Insights, write audit record

Tool routing prefixes:

| Prefix | Backend |
|--------|---------|
| `adr.*` | `adr-spoke` |
| `ofs-triage.*` | `triage-spoke` |
| `udip.*` | `udip-spoke` |
| `arc.*` | `arc-spoke` |
| `trial.*` | `ogc-spoke` |

**Verify:** Call `GET /mcp/tools` — should return the merged tool catalog from all registered spokes.

---

### 2.17 Azure Event Grid

Event Grid handles inter-spoke event notifications (e.g., ARC Integration API notifying ADR that a case status changed).

**Portal Navigation:** Home > Event Grid Topics > + Create

| Setting | Value |
|---------|-------|
| Resource group | `rg-eeoc-ai-platform-prod` |
| Name | `evgt-eeoc-ai-prod` |
| Region | `US Gov Virginia` |
| Event Schema | `Cloud Events Schema v1.0` |

After creation, add event subscriptions for each spoke that needs notifications:

| Subscription Name | Event Types | Endpoint |
|------------------|-------------|----------|
| `sub-adr-case-updates` | `case.status.changed`, `mediation.outcome.recorded` | ADR webhook URL |
| `sub-triage-case-updates` | `case.status.changed`, `charge.classified` | Triage webhook URL |

**Verify:** Navigate to Event Grid topic. Status shows "Active".

---

### 2.18 Azure Front Door + WAF

ADR is the only public-facing application. It needs Azure Front Door with WAF for external access via Login.gov.

**Portal Navigation:** Home > Front Door and CDN profiles > + Create

**Basics Tab:**

| Setting | Value |
|---------|-------|
| Subscription | `{your subscription}` |
| Resource group | `rg-eeoc-ai-platform-prod` |
| Name | `afd-eeoc-adr-prod` |
| Tier | `Standard` |

#### Create Endpoint

| Setting | Value |
|---------|-------|
| Endpoint name | `adr-eeoc` |
| Status | `Enabled` |

This gives you a domain: `adr-eeoc.azurefd.net`

#### Create Origin Group

| Setting | Value |
|---------|-------|
| Name | `og-adr-webapp` |
| Health probe path | `/healthz` |
| Health probe protocol | `HTTPS` |
| Health probe interval | `30 seconds` |
| Sample size | `4` |
| Required samples | `3` |

#### Add Origin

| Setting | Value |
|---------|-------|
| Name | `adr-container-app` |
| Origin type | `Custom` |
| Host name | `ca-adr-webapp-prod.internal.{env-suffix}` |
| HTTP port | `80` |
| HTTPS port | `443` |
| Priority | `1` |
| Weight | `1000` |

#### Create Route

| Setting | Value |
|---------|-------|
| Name | `route-adr-default` |
| Domains | `adr-eeoc.azurefd.net`, custom domain (added later) |
| Patterns to match | `/*` |
| Origin group | `og-adr-webapp` |
| Forwarding protocol | `HTTPS only` |
| Redirect | `HTTP to HTTPS` |

#### WAF Policy

**Portal Navigation:** Home > Web Application Firewall policies > + Create

| Setting | Value |
|---------|-------|
| Name | `waf-eeoc-adr-prod` |
| Policy for | `Azure Front Door` |
| Tier | `Standard` |
| Policy mode | `Prevention` |

**Managed rules:**

| Ruleset | Version |
|---------|---------|
| Microsoft Default Rule Set | `2.1` |
| Microsoft Bot Manager | `1.0` |

**Custom rules:**

| Rule name | Priority | Condition | Action |
|-----------|----------|-----------|--------|
| `RateLimit100PerMinute` | 1 | Rate limit: 100 requests per 1 minute per IP | Block |

Associate the WAF policy with the `adr-eeoc` endpoint.

#### Lock Down Backend to Your Front Door Instance

The `AzureFrontDoor.Backend` service tag allows traffic from any Front Door profile. To restrict to only your profile:

1. After Front Door creation, navigate to Overview and copy the **Front Door ID** (a GUID).
2. In the ADR Container App ingress settings, add a header-based access restriction:
   - Header name: `X-Azure-FDID`
   - Header value: `{your Front Door ID}`
   - Action: Allow (reject all other Front Door traffic)

This prevents another Azure tenant's Front Door from reaching your backend.

#### Custom Domain

1. Navigate to Front Door > Domains > + Add
2. Enter `adr.eeoc.gov` (or your ADR domain)
3. Create a CNAME record: `adr.eeoc.gov` → `adr-eeoc.azurefd.net`
4. Upload TLS certificate or use Front Door managed certificate
5. Associate domain with the route

**Verify:** Browse to `https://adr-eeoc.azurefd.net/healthz` — should return 200 OK.

---

### 2.19 Azure Sentinel (M-21-31 EL3)

M-21-31 Event Logging Tier 3 (Advanced) requires centralized SIEM with analytics, UEBA, and automated response.

**Portal Navigation:** Home > Microsoft Sentinel > + Create

| Setting | Value |
|---------|-------|
| Log Analytics workspace | `log-eeoc-ai-prod` (created in Section 2.13) |

After enabling Sentinel on the workspace:

#### Connect Data Sources

Navigate to Sentinel > Configuration > Data connectors:

1. **Azure Active Directory** — sign-in logs, audit logs, provisioning logs
2. **Azure Activity** — subscription-level operations
3. **Microsoft Defender for Cloud** — security alerts
4. **Azure Key Vault** — vault diagnostics
5. **Azure Storage Account** — blob read/write audit
6. **Azure PostgreSQL** — database diagnostics (configure in PostgreSQL > Diagnostic settings)
7. **Azure Container Apps** — application logs (already flowing via Log Analytics)

#### Enable UEBA (User and Entity Behavior Analytics)

Navigate to Sentinel > Configuration > Settings > UEBA:
1. Enable UEBA
2. Select data sources: Azure Active Directory
3. Entity types: Account, Host, IP

#### Analytics Rules

Navigate to Sentinel > Configuration > Analytics > + Create:

| Rule Name | Severity | Query Logic |
|-----------|----------|-------------|
| Failed login spike | High | More than 10 failed logins in 5 minutes from same IP |
| Key Vault unauthorized access | High | Key Vault access denied events |
| Database connection spike | Medium | PostgreSQL connections > 200 in 1 minute |
| Audit log tampering | Critical | Any modification to WORM blob containers |
| Unusual data export volume | High | FOIA export > 10 GB in single request |

#### SOAR Playbooks

Create Logic App playbooks for automated response:

| Playbook | Trigger | Action |
|----------|---------|--------|
| `playbook-block-ip` | Sentinel alert: brute force | Add IP to NSG deny rule |
| `playbook-notify-security` | Sentinel alert: High severity | Send email to security team |
| `playbook-isolate-container` | Sentinel alert: compromised identity | Scale Container App to 0 replicas |

**Verify:** Navigate to Sentinel > Overview. Data is flowing from connected sources. Analytics rules show "Enabled".

---

### 2.20 Application Insights + Log Analytics

The Log Analytics workspace `log-eeoc-ai-prod` was created with the Container Apps Environment (Section 2.13).

#### Application Insights

**Portal Navigation:** Home > Application Insights > + Create

| Setting | Value |
|---------|-------|
| Resource group | `rg-eeoc-ai-platform-prod` |
| Name | `appi-eeoc-ai-prod` |
| Region | `US Gov Virginia` |
| Log Analytics Workspace | `log-eeoc-ai-prod` |

After creation, copy the **Instrumentation Key** and **Connection String** and store in Key Vault as `APPINSIGHTS-CONNECTION-STRING`.

#### Diagnostic Settings

For each Azure resource, configure diagnostic settings to send logs to the Log Analytics workspace:

Navigate to each resource > Monitoring > Diagnostic settings > + Add diagnostic setting:

| Resource | Log Categories | Destination |
|----------|---------------|-------------|
| PostgreSQL Flex Server | PostgreSQL Logs, Query Store Runtime | `log-eeoc-ai-prod` |
| Redis | ConnectedClientList, AllMetrics | `log-eeoc-ai-prod` |
| Event Hub Namespace | OperationalLogs, AutoScaleLogs | `log-eeoc-ai-prod` |
| Key Vault | AuditEvent | `log-eeoc-ai-prod` |
| APIM | GatewayLogs, WebSocketConnectionLogs | `log-eeoc-ai-prod` |
| Front Door | FrontDoorAccessLog, FrontDoorHealthProbeLog, FrontDoorWebApplicationFirewallLog | `log-eeoc-ai-prod` |
| Storage Account | StorageRead, StorageWrite, StorageDelete | `log-eeoc-ai-prod` |

**Verify:** Navigate to Log Analytics workspace > Logs. Run a query: `Heartbeat | take 10` — should return results.

---

### 2.21 Azure Monitor Alert Rules

**Portal Navigation:** Home > Monitor > Alerts > + Create > Alert rule

First, create an **Action Group**:

Navigate to Monitor > Alerts > Action groups > + Create:

| Setting | Value |
|---------|-------|
| Resource group | `rg-eeoc-ai-platform-prod` |
| Action group name | `ag-eeoc-ai-platform-prod` |
| Display name | `EEOC-AI-Alerts` |

**Notifications:**
- Email: `{platform team email}`
- Email: `{security team email}`

Now create these alert rules:

| Alert Name | Resource | Metric | Condition | Threshold | Period | Severity |
|-----------|----------|--------|-----------|-----------|--------|----------|
| DB CPU High | PostgreSQL Server | CPU Percent | Greater than | 80% | 5 min | Sev 2 |
| DB Connections High | PostgreSQL Server | Active Connections | Greater than | 200 | 5 min | Sev 2 |
| DB Replica Lag | PostgreSQL Replica | Replica Lag (seconds) | Greater than | 30 | 5 min | Sev 1 |
| CDC Consumer Lag | Event Hub | Incoming vs Outgoing gap | Greater than | 1000 messages | 5 min | Sev 1 |
| ADR Error Rate | Front Door | 5xx Percentage | Greater than | 1% | 5 min | Sev 1 |
| Container Restarts | Container Apps | Restart Count | Greater than | 3 | 5 min | Sev 2 |
| Redis Memory High | Redis Cache | Used Memory Percentage | Greater than | 80% | 5 min | Sev 2 |
| Key Vault Throttled | Key Vault | ServiceApiHit (429) | Greater than | 10 | 5 min | Sev 3 |
| WORM Deletion Attempt | Storage | Delete operations on `hub-audit-archive` | Greater than | 0 | 1 min | Sev 0 (Critical) |

**Verify:** Navigate to Monitor > Alerts > Alert rules. All rules show "Enabled".

---

## Part 3: ARC DBA Coordination

The WAL/CDC pipeline requires 2 SQL commands on ARC's PrEPA PostgreSQL server. ARC runs these — we do not have write access to their database.

### Email Template

Send this to the ARC DBA contact:

> Subject: WAL/CDC Configuration Request — EEOC AI Integration Platform
>
> Hi {DBA name},
>
> We need two SQL commands run on the PrEPA production PostgreSQL server to enable Change Data Capture (CDC) for the EEOC AI Integration Platform. This lets us replicate data to UDIP with no load on PrEPA — it reads the existing write-ahead log.
>
> **What we need:**
>
> ```sql
> -- 1. Create a logical replication slot for Debezium
> SELECT pg_create_logical_replication_slot('udip_cdc', 'pgoutput');
>
> -- 2. Publish all tables for replication (UDIP filters tables on ingest via Debezium config)
> -- FOR ALL TABLES is used here because PrEPA's schema evolves and we need new tables
> -- as they appear. Row-level filtering happens in Debezium and the UDIP middleware.
> CREATE PUBLICATION udip_publication FOR ALL TABLES;
> ```
>
> **What we also need from you:**
> - Read-only database credentials (username/password) for the replication connection
> - The PostgreSQL server hostname and port
> - Confirmation of the PostgreSQL version (we expect 14+)
> - Confirmation that `wal_level` is set to `logical` (check with `SHOW wal_level;`)
>
> **Impact:** None. Logical replication reads the WAL that PostgreSQL already writes. No additional disk I/O, no table locks, no schema changes on your side.
>
> **Timeline:** We need this before we can start the CDC pipeline (Phase 1, Week 2 of deployment).
>
> Thanks,
> {your name}

### After the DBA Runs the Commands

1. Store the read-only credentials in Key Vault:
   - `PREPA-PG-HOST` → PrEPA server hostname
   - `PREPA-PG-USER` → replication username
   - `PREPA-PG-PASSWORD` → replication password
   - `PREPA-PG-DATABASE` → database name

2. Verify WAL/CDC is working:

```bash
# from a machine that can reach the PrEPA server (or via VPN)
psql "host={prepa-host} user={repl-user} dbname={prepa-db} sslmode=require" \
  -c "SELECT slot_name, plugin, active FROM pg_replication_slots WHERE slot_name = 'udip_cdc';"
```

Expected output:
```
 slot_name | plugin   | active
-----------+----------+--------
 udip_cdc  | pgoutput | t
```

3. Configure the Debezium connector:

```bash
curl -X POST http://ca-debezium-connect-prod:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prepa-postgresql-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "{prepa-host}",
      "database.port": "5432",
      "database.user": "{repl-user}",
      "database.password": "{repl-password}",
      "database.dbname": "{prepa-db}",
      "database.server.name": "prepa",
      "slot.name": "udip_cdc",
      "publication.name": "udip_publication",
      "plugin.name": "pgoutput",
      "topic.prefix": "prepa",
      "table.include.list": "public.*",
      "transforms": "route",
      "transforms.route.type": "io.debezium.transforms.ByLogicalTableRouter",
      "transforms.route.topic.regex": "prepa.public.(.*)",
      "transforms.route.topic.replacement": "prepa-cdc-events"
    }
  }'
```

4. Verify events are flowing:

```bash
# check connector status
curl http://ca-debezium-connect-prod:8083/connectors/prepa-postgresql-connector/status

# check Event Hub metrics in portal — Incoming Messages should be > 0
```

---

## Part 4: Post-Provisioning Configuration

### 4.1 Enable Feature Flags

Each application has feature flags that control integration points. Set these in each Container App's environment variables:

**ADR:**

| Env Var | Value | What It Does |
|---------|-------|-------------|
| `MCP_ENABLED` | `true` | Registers ADR tools with MCP Hub |
| `MCP_PROTOCOL_ENABLED` | `true` | Exposes MCP protocol endpoint |
| `ARC_SYNC_ENABLED` | `true` | Enables 15-minute case sync from ARC |
| `UDIP_PUSH_ENABLED` | `true` | Pushes operational analytics to UDIP |

**Triage:**

| Env Var | Value | What It Does |
|---------|-------|-------------|
| `MCP_ENABLED` | `false` | Triage MCP is disabled by default |
| `ARC_LOOKUP_ENABLED` | `true` | Enables charge metadata auto-population from ARC |
| `UDIP_PUSH_ENABLED` | `true` | Pushes classification results to UDIP |

**UDIP AI Assistant:**

| Env Var | Value | What It Does |
|---------|-------|-------------|
| `MCP_ENABLED` | `true` | Enables AI tool calls through MCP Hub |
| `ENABLE_AI_ASSISTANT` | `true` | Enables the AI chat interface |
| `ENABLE_AUDIT_LOG` | `true` | Logs all AI queries for FOIA compliance |

**ARC Integration API:**

| Env Var | Value | What It Does |
|---------|-------|-------------|
| `SERVICE_BUS_ENABLED` | `true` | Subscribes to PrEPA Service Bus events |
| `MCP_FORWARDING_ENABLED` | `true` | Forwards events to MCP Hub |

### 4.2 Register Spokes in MCP Hub

Register each spoke with the hub aggregator function:

```bash
HUB_URL="https://ca-mcp-hub-func-prod.internal.{env}"

# register ADR
curl -X POST "$HUB_URL/api/spokes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "adr",
    "display_name": "ADR Mediation",
    "endpoint": "https://ca-adr-webapp-prod.internal.{env}/api/mcp",
    "auth_type": "entra_id",
    "client_id": "{ADR_CLIENT_ID}",
    "tool_prefix": "adr",
    "health_endpoint": "https://ca-adr-webapp-prod.internal.{env}/healthz"
  }'

# register Triage
curl -X POST "$HUB_URL/api/spokes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "triage",
    "display_name": "OFS Triage",
    "endpoint": "https://ca-triage-webapp-prod.internal.{env}/api/mcp",
    "auth_type": "entra_id",
    "client_id": "{TRIAGE_CLIENT_ID}",
    "tool_prefix": "ofs-triage",
    "health_endpoint": "https://ca-triage-webapp-prod.internal.{env}/healthz"
  }'

# register UDIP
curl -X POST "$HUB_URL/api/spokes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "udip",
    "display_name": "UDIP Analytics",
    "endpoint": "https://ca-udip-ai-assistant-prod.internal.{env}/api/mcp",
    "auth_type": "entra_id_obo",
    "client_id": "{UDIP_CLIENT_ID}",
    "tool_prefix": "udip",
    "health_endpoint": "https://ca-udip-ai-assistant-prod.internal.{env}/healthz"
  }'

# register ARC Integration
curl -X POST "$HUB_URL/api/spokes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "arc",
    "display_name": "ARC Integration",
    "endpoint": "https://ca-arc-integration-prod.internal.{env}/api/mcp",
    "auth_type": "entra_id",
    "client_id": "{ARC_INTEGRATION_CLIENT_ID}",
    "tool_prefix": "arc",
    "health_endpoint": "https://ca-arc-integration-prod.internal.{env}/healthz"
  }'

# register OGC
curl -X POST "$HUB_URL/api/spokes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ogc",
    "display_name": "OGC Trial Tool",
    "endpoint": "https://app-ogctrialtool-web.azurewebsites.us/api/mcp",
    "auth_type": "entra_id",
    "client_id": "{OGC_CLIENT_ID}",
    "tool_prefix": "trial",
    "health_endpoint": "https://app-ogctrialtool-web.azurewebsites.us/health"
  }'
```

After registration, trigger a catalog refresh:

```bash
curl -X POST "$HUB_URL/api/tools/refresh"
```

### 4.3 Connection Sequence

Connect spokes in this order. Each phase has a gate — do not proceed until the gate passes.

**Phase 1: Hub Infrastructure**
- Gate: APIM healthy, VNet routing works, Key Vault accessible, token validation passes, WORM blob verified
- Test: `curl https://apim-eeoc-mcp-hub-prod.azure-api.net/mcp/tools` returns tool catalog

**Phase 2: ARC Integration API**
- Gate: 11 tools routable through APIM, write-back to PrEPA returns 200, event grid subscribed
- Test: `curl /arc/v1/mediation/eligible-cases` returns data (or empty array if no eligible cases yet)

**Phase 3: ADR**
- Gate: 10 tools callable through hub, ARCSyncImporter runs, event grid events flow
- Test: ADR health check passes, `/healthz/integrations` shows ARC connected

**Phase 4: Triage**
- Gate: Read tools return data, classification pipeline processes a test document
- Test: Upload a test charge document, verify classification completes

**Phase 5: UDIP + OBO**
- Gate: AI queries return regionally scoped data, dynamic tool catalog reconciled
- Test: Ask the AI "How many open cases are there?" — should return a number

**Phase 6: OGC Trial Tool**
- Gate: 3 tools callable, document indexing works
- Test: Upload a test litigation document, verify indexing completes

**Phase 7: Cross-Spoke Verification**
- Gate: Multi-spoke query returns combined results
- Test: AI query that requires data from both ADR and Triage spokes

---

## Part 5: First Data Flow Verification

Run these checks after all spokes are connected.

### 5.1 CDC Pipeline Verification

```bash
# 1. Check Debezium connector is running
curl http://ca-debezium-connect-prod:8083/connectors/prepa-postgresql-connector/status | jq .

# Expected: "state": "RUNNING" for both connector and all tasks

# 2. Check Event Hub is receiving messages
# Portal: Event Hub namespace > prepa-cdc-events > Metrics > Incoming Messages
# Should see a steady stream of messages

# 3. Check UDIP middleware is processing
# Portal: Container Apps > ca-udip-data-middleware > Logs
# Query: ContainerAppConsoleLogs | where ContainerAppName_s == "ca-udip-data-middleware" | take 20

# 4. Check analytics tables have data
psql "host=ca-pgbouncer-prod port=6432 dbname=udip user=udip_admin sslmode=require" \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables WHERE schemaname = 'analytics' ORDER BY n_live_tup DESC LIMIT 10;"
```

### 5.2 Middleware Translation Verification

```sql
-- check that YAML mappings translated ARC internal codes to readable labels
SELECT charge_number, status_label, office_name
FROM analytics.charges
LIMIT 5;

-- status_label should be human-readable (e.g., "Open - Formalized")
-- not ARC internal codes (e.g., "FORM")
```

### 5.3 Row-Level Security Verification

Test RLS with two users from different regions:

```sql
-- as a user in Region 1 (e.g., Charlotte district)
SET app.current_user_region = 'charlotte';
SELECT count(*) FROM analytics.charges;
-- should return only Charlotte-district cases

-- as a user in Region 2 (e.g., Chicago district)
SET app.current_user_region = 'chicago';
SELECT count(*) FROM analytics.charges;
-- should return only Chicago-district cases

-- as a data steward (full access)
SET app.current_user_role = 'data_steward';
SELECT count(*) FROM analytics.charges;
-- should return ALL cases
```

### 5.4 AI Assistant Verification

```bash
# send a test query to the AI Assistant
curl -X POST https://ca-udip-ai-assistant-prod.internal.{env}/api/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {token}" \
  -d '{"message": "How many cases were filed last month?"}'

# Expected: a JSON response with the AI's answer, including the SQL it generated
```

### 5.5 Chart Rendering Verification

```bash
# ask for a visualization
curl -X POST https://ca-udip-ai-assistant-prod.internal.{env}/api/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {token}" \
  -d '{"message": "Show me a bar chart of cases by statute for the last quarter"}'

# Expected: response includes chart data that renders in the UDIP portal
```

---

## Part 6: Going Live Checklist

| # | Check | Command / How to Verify | Status |
|---|-------|------------------------|--------|
| 1 | All health endpoints return 200 | `curl /healthz` on each app | [ ] |
| 2 | All spokes in hub tool catalog | `GET /mcp/tools` returns tools from all 5 spokes | [ ] |
| 3 | AI query returns data | Ask "How many open cases?" — get a number back | [ ] |
| 4 | ADR Login.gov works | External test party can sign in via Login.gov and see their cases | [ ] |
| 5 | Triage classification completes | Upload a test charge document, observe classification output | [ ] |
| 6 | Audit records in all audit tables | Query `hubauditlog`, `arcintegrationaudit` — rows exist | [ ] |
| 7 | WORM blob immutable | Try to delete a blob in `hub-audit-archive` — should fail with 403 | [ ] |
| 8 | Alerts fire on threshold breach | Temporarily lower a threshold (e.g., CPU > 1%) and verify email | [ ] |
| 9 | Backup/restore tested | Trigger a PostgreSQL point-in-time restore to a test server, verify data | [ ] |
| 10 | CDC lag under 30 seconds | Check Event Hub consumer lag metric — steady state should be < 5 seconds | [ ] |
| 11 | RLS enforced | Two users from different regions see different data | [ ] |
| 12 | PgBouncer connection pooling | `SHOW pools;` on PgBouncer shows active connections | [ ] |
| 13 | Redis caching active | `redis-cli INFO stats` shows `keyspace_hits` > 0 | [ ] |
| 14 | Sentinel receiving logs | Sentinel overview shows data volume > 0 | [ ] |
| 15 | WAF blocking attacks | Send a test SQLi payload to ADR — should return 403 | [ ] |
| 16 | TLS on all endpoints | `openssl s_client -connect {endpoint}:443` shows valid cert | [ ] |
| 17 | DR failover documented | DR runbook exists, failover steps tested in staging | [ ] |

---

## Part 7: Troubleshooting

### UDIP returns empty results

**Symptoms:** AI Assistant says "no data found" or returns empty tables.

**Check:**
1. Is the OBO token configured? The AI Assistant uses On-Behalf-Of flow to preserve the caller's regional identity for RLS. If OBO fails, the query runs with no region context and RLS blocks everything.
   - Verify `UDIP_CLIENT_SECRET` is set and the Entra app has `user_impersonation` scope exposed.
2. Is the user in a region group? Check Entra ID — the user must be in a group matching `UDIP-Data-Region-{region}`.
3. Does the analytics schema have data? Run `SELECT count(*) FROM analytics.charges;` — if 0, the CDC pipeline is not populating data.

### ADR login fails

**Symptoms:** Redirect loop, 401, or blank page after Login.gov authentication.

**Check:**
1. Is the redirect URI correct in Entra ID? It must match exactly: `https://{adr-domain}/auth/callback`
2. Is the Front Door forwarding the Host header? Check Front Door route — "Forwarding protocol" must preserve the original host.
3. Is Login.gov configured? Verify `LOGINGOV-CLIENT-ID` and `LOGINGOV-PRIVATE-KEY` secrets in Key Vault.

### CDC consumer not processing

**Symptoms:** Event Hub shows incoming messages but analytics tables are not updating.

**Check:**
1. Is the Debezium connector running? `curl /connectors/prepa-postgresql-connector/status` — look for `"state": "RUNNING"`.
2. Is the Event Hub connection string correct? Check `CDC-EVENTHUB-LISTEN-CONNECTION` in Key Vault.
3. Is the consumer group correct? Must be `udip-middleware`.
4. Is the replication slot active? On PrEPA: `SELECT * FROM pg_replication_slots WHERE slot_name = 'udip_cdc';` — `active` should be `t`.

### Tool not found in hub

**Symptoms:** AI query fails with "tool not found" or "no matching tool".

**Check:**
1. Is the spoke registered? `GET /api/spokes` — the spoke must appear in the list.
2. Is the spoke healthy? Hit the spoke's health endpoint directly.
3. Is APIM routing configured? Check the APIM policy for the tool prefix.
4. Is the catalog stale? `POST /api/tools/refresh` to force a refresh.

### 401 on all requests

**Symptoms:** Every API call returns 401 Unauthorized.

**Check:**
1. Is the JWT audience correct? The token's `aud` claim must match the app registration's Application ID URI.
2. Is the token expired? Decode the JWT at jwt.ms — check `exp` claim.
3. Is the tenant correct? The token's `tid` claim must match `AZURE_TENANT_ID`.
4. Are app roles assigned? The calling app must have the required role (e.g., `Hub.Read`) granted via admin consent.

### Container App crashes (restart loop)

**Symptoms:** Container App shows "Failed" or "CrashLoopBackOff" in logs.

**Check:**
1. Are resource limits too low? Check if the container is OOM-killed: Container App > Logs > `ContainerAppConsoleLogs | where Log_s contains "OOMKilled"`.
2. Are required environment variables set? Missing Key Vault references cause startup failures. Check all `Secret ref` values.
3. Is the database reachable? PgBouncer or PostgreSQL network issues cause health probes to fail.
4. Check container logs: Container App > Console logs for stack traces.

### Middleware translates data incorrectly

**Symptoms:** Analytics tables have wrong values, NULL where data should exist, or untranslated codes.

**Check:**
1. Are the YAML mapping files deployed? Check `data-middleware/mappings/*.yaml` in the data-middleware container.
2. Are lookup tables populated? The middleware uses `lookup_table` transforms that JOIN against replicated reference tables. If `replica.*` reference tables are empty, translations return NULL.
3. Is the CDC pipeline replicating reference tables? Some reference tables are small and change infrequently — verify they have data.

### Redis connection refused

**Symptoms:** Applications fall back to in-memory caching, session affinity breaks.

**Check:**
1. Is Redis accessible from the VNet? The private endpoint must be in `snet-redis` and DNS resolution must work.
2. Is TLS configured? Redis requires TLS 1.2 — connection strings must use `rediss://` (note double-s) not `redis://`.
3. Is the access key current? If Redis keys were regenerated, update Key Vault secret `REDIS-CONNECTION-STRING`.

---

## Appendix A: All Resource Names

| Resource Type | Name | SKU/Tier |
|--------------|------|----------|
| Resource Group | `rg-eeoc-ai-platform-prod` | — |
| Virtual Network | `vnet-eeoc-ai-prod` | — |
| NSG (Apps) | `nsg-eeoc-apps-prod` | — |
| NSG (Postgres) | `nsg-eeoc-postgres-prod` | — |
| Key Vault | `kv-eeoc-ai-prod` | Standard |
| Storage Account | `steeocaiprod` | Standard GRS |
| Container Registry | `acreeocaiprod` | Premium |
| PostgreSQL Server | `pg-eeoc-udip-prod` | Memory Optimized E16ds_v5 |
| PostgreSQL Replica | `pg-eeoc-udip-prod-replica` | Memory Optimized E16ds_v5 |
| Redis Cache | `redis-eeoc-ai-prod` | Premium P1 |
| Event Hub Namespace | `evhns-eeoc-cdc-prod` | Standard |
| Event Hub | `prepa-cdc-events` | 8 partitions |
| Azure OpenAI | `oai-eeoc-ai-prod` | Standard S0 |
| Cognitive Search | `srch-eeoc-triage-prod` | Standard S1 |
| Container Apps Env | `cae-eeoc-ai-prod` | Workload profiles |
| Log Analytics | `log-eeoc-ai-prod` | Per GB |
| Application Insights | `appi-eeoc-ai-prod` | — |
| API Management | `apim-eeoc-mcp-hub-prod` | Standard v2 |
| Front Door | `afd-eeoc-adr-prod` | Standard |
| WAF Policy | `waf-eeoc-adr-prod` | Standard |
| Event Grid Topic | `evgt-eeoc-ai-prod` | — |
| Action Group | `ag-eeoc-ai-platform-prod` | — |

### Container Apps

| App Name | Image | CPU | Memory | Min/Max Replicas |
|----------|-------|-----|--------|-----------------|
| `ca-udip-ai-assistant-prod` | `udip/ai-assistant:v1.0.0` | 2 | 2 Gi | 2/6 |
| `ca-udip-superset-prod` | `udip/superset:v1.0.0` | 2 | 4 Gi | 2/4 |
| `ca-udip-portal-prod` | `udip/portal-nginx:v1.0.0` | 0.25 | 512 Mi | 2/4 |
| `ca-debezium-connect-prod` | `udip/debezium-connect:v1.0.0` | 2 | 4 Gi | 1/2 |
| `ca-pgbouncer-prod` | `bitnami/pgbouncer:latest` | 0.5 | 1 Gi | 2/4 |
| `ca-adr-webapp-prod` | `adr/webapp:v1.0.0` | 2 | 4 Gi | 3/12 |
| `ca-adr-functionapp-prod` | `adr/functionapp:v1.0.0` | 1 | 2 Gi | 2/6 |
| `ca-triage-webapp-prod` | `triage/webapp:v1.0.0` | 1 | 2 Gi | 2/6 |
| `ca-triage-functionapp-prod` | `triage/functionapp:v1.0.0` | 2 | 4 Gi | 2/8 |
| `ca-mcp-hub-func-prod` | `hub/aggregator-function:v1.0.0` | 0.5 | 1 Gi | 2/4 |

---

## Appendix B: All Environment Variables by Application

### UDIP AI Assistant

| Variable | Value | Source |
|----------|-------|--------|
| `FLASK_ENV` | `production` | Manual |
| `AI_ASSISTANT_PORT` | `5000` | Manual |
| `OPENAI_API_BASE` | `https://oai-eeoc-ai-prod.openai.azure.us/` | Manual |
| `OPENAI_API_VERSION` | `2024-02-01` | Manual |
| `OPENAI_DEPLOYMENT` | `gpt-4o` | Manual |
| `AI_MODEL_PROVIDER` | `azure_openai` | Manual |
| `EMBEDDING_MODEL` | `text-embedding-3-small` | Manual |
| `EMBEDDING_DIMENSIONS` | `1536` | Manual |
| `PG_AI_HOST` | PgBouncer internal FQDN | Manual |
| `PG_AI_PORT` | `6432` | Manual |
| `PG_AI_DATABASE` | `udip` | Manual |
| `PG_AI_SSLMODE` | `require` | Manual |
| `MAX_TOKENS` | `2048` | Manual |
| `SQL_MAX_ROWS` | `500` | Manual |
| `RATE_LIMIT_PER_MINUTE` | `20` | Manual |
| `AUDIT_LOG_ENABLED` | `true` | Manual |
| `MCP_ENABLED` | `true` | Manual |
| `AI_FAILOVER_ENABLED` | `true` | Manual |
| `REDIS_URL` | Key Vault: `REDIS-CONNECTION-STRING` | Secret |
| `OPENAI_API_KEY` | Key Vault: `OPENAI-API-KEY` | Secret |
| `FLASK_SECRET_KEY` | Key Vault: `UDIP-FLASK-SECRET` | Secret |
| `DB_PASSWORD` | Key Vault: `PG-ADMIN-PASSWORD` | Secret |

### ADR Web Application

| Variable | Value | Source |
|----------|-------|--------|
| `FLASK_ENV` | `production` | Manual |
| `DEPLOYMENT_ENV` | `production` | Manual |
| `SESSION_TIMEOUT_MINUTES` | `30` | Manual |
| `MAX_CONTENT_LENGTH` | `52428800` | Manual |
| `ARC_INTEGRATION_API_URL` | ARC Integration API internal URL | Manual |
| `UDIP_INGEST_URL` | UDIP ingest internal URL | Manual |
| `MCP_HUB_URL` | APIM internal URL | Manual |
| `MCP_ENABLED` | `true` | Manual |
| `MCP_PROTOCOL_ENABLED` | `true` | Manual |
| `GRAPH_RATE_LIMIT_PER_SEC` | `15` | Manual |
| `GUNICORN_WORKERS` | `4` | Manual |
| `GUNICORN_WORKER_CLASS` | `gevent` | Manual |
| `GUNICORN_TIMEOUT` | `120` | Manual |
| `AI_MODEL_PROVIDER` | `azure_openai` | Manual |
| `AZURE_OPENAI_ENDPOINT` | `https://oai-eeoc-ai-prod.openai.azure.us/` | Manual |
| `AZURE_OPENAI_API_VERSION` | `2024-02-01` | Manual |
| `AZURE_OPENAI_DEPLOYMENT_CHAT` | `gpt-4o` | Manual |
| `KEY_VAULT_URI` | `https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/` | Manual |

### ADR Function App

| Variable | Value | Source |
|----------|-------|--------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` | Manual |
| `ARC_INTEGRATION_API_URL` | ARC Integration API internal URL | Manual |
| `UDIP_INGEST_URL` | UDIP ingest internal URL | Manual |
| `MCP_HUB_URL` | APIM internal URL | Manual |
| `ARC_SYNC_SCHEDULE` | `0 */15 * * * *` | Manual |
| `DISPOSITION_RETENTION_DAYS` | `2555` | Manual |
| `METRICS_ROLLUP_TIMEZONE` | `Eastern Standard Time` | Manual |

### Triage Web Application

| Variable | Value | Source |
|----------|-------|--------|
| `FLASK_ENV` | `production` | Manual |
| `DEPLOYMENT_ENV` | `production` | Manual |
| `SESSION_TIMEOUT_MINUTES` | `30` | Manual |
| `MAX_CONTENT_LENGTH` | `52428800` | Manual |
| `ARC_INTEGRATION_API_URL` | ARC Integration API internal URL | Manual |
| `UDIP_INGEST_URL` | UDIP ingest internal URL | Manual |
| `MCP_HUB_URL` | APIM internal URL | Manual |
| `MCP_ENABLED` | `false` | Manual |
| `ARC_LOOKUP_ENABLED` | `true` | Manual |
| `GUNICORN_WORKERS` | `2` | Manual |
| `GUNICORN_WORKER_CLASS` | `gevent` | Manual |
| `GUNICORN_TIMEOUT` | `120` | Manual |
| `AI_MODEL_PROVIDER` | `azure_openai` | Manual |
| `AZURE_OPENAI_ENDPOINT` | `https://oai-eeoc-ai-prod.openai.azure.us/` | Manual |
| `AZURE_OPENAI_API_VERSION` | `2024-02-01` | Manual |
| `AZURE_OPENAI_DEPLOYMENT_CHAT` | `gpt-4o` | Manual |

### Triage Function App

| Variable | Value | Source |
|----------|-------|--------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` | Manual |
| `ARC_INTEGRATION_API_URL` | ARC Integration API internal URL | Manual |
| `UDIP_INGEST_URL` | UDIP ingest internal URL | Manual |
| `MCP_HUB_URL` | APIM internal URL | Manual |
| `AZURE_OPENAI_API_VERSION` | `2024-02-01` | Manual |
| `DISPOSITION_RETENTION_DAYS` | `2555` | Manual |
| `METRICS_ROLLUP_TIMEZONE` | `Eastern Standard Time` | Manual |

### ARC Integration API

| Variable | Value | Source |
|----------|-------|--------|
| `AZURE_TENANT_ID` | `{TENANT_ID}` | Manual |
| `AZURE_CLIENT_ID` | `{ARC_INTEGRATION_CLIENT_ID}` | Manual |
| `ARC_GATEWAY_URL` | From worksheet | Manual |
| `ARC_PREPA_URL` | From worksheet | Manual |
| `ARC_AUTH_URL` | From worksheet | Manual |
| `KEY_VAULT_URI` | `https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/` | Manual |
| `RATE_LIMIT_PER_MINUTE` | `120` | Manual |
| `CACHE_TTL_REFERENCE` | `86400` | Manual |
| `CACHE_TTL_CASE_LIST` | `300` | Manual |
| `CACHE_TTL_CASE_DETAIL` | `120` | Manual |
| `CACHE_TTL_DOC_METADATA` | `600` | Manual |
| `SERVICE_BUS_DB_CHANGE_TOPIC` | `db-change-topic` | Manual |
| `SERVICE_BUS_DOCUMENT_TOPIC` | `document-activity-topic` | Manual |
| `SERVICE_BUS_SUBSCRIPTION` | `arc-integration-api` | Manual |
| `MCP_HUB_URL` | APIM internal URL | Manual |
| `LOG_LEVEL` | `INFO` | Manual |
| `ARC_AUDIT_TABLE` | `arcintegrationaudit` | Manual |
| `ARC_AUDIT_ARCHIVE_CONTAINER` | `arc-integration-archive` | Manual |
| `ARC_CLIENT_SECRET` | Key Vault | Secret |
| `SERVICE_BUS_CONNECTION_STRING` | Key Vault | Secret |
| `MCP_HUB_HMAC_SECRET` | Key Vault | Secret |
| `REDIS_URL` | Key Vault | Secret |
| `ARC_AUDIT_HMAC_KEY` | Key Vault | Secret |

### MCP Hub Aggregator Function

| Variable | Value | Source |
|----------|-------|--------|
| `FUNCTIONS_WORKER_RUNTIME` | `python` | Manual |
| `AZURE_STORAGE_CONNECTION_STRING` | Key Vault | Secret |
| `REDIS_URL` | Key Vault | Secret |
| `KEY_VAULT_URI` | `https://kv-eeoc-ai-prod.vault.usgovcloudapi.net/` | Manual |
| `RECONCILIATION_INTERVAL_SECONDS` | `300` | Manual |
| `MAX_TOOLS_PER_CONTEXT` | `15` | Manual |
| `SPOKE_REQUEST_TIMEOUT_SECONDS` | `30` | Manual |

---

## Appendix C: All Key Vault Secrets

| Secret Name | How to Generate | Used By |
|-------------|----------------|---------|
| `PG-ADMIN-PASSWORD` | `openssl rand -base64 24` | PostgreSQL, PgBouncer |
| `REDIS-CONNECTION-STRING` | Copy from Redis Access Keys after creation | All apps |
| `CDC-EVENTHUB-SEND-CONNECTION` | Event Hub > debezium-writer policy | Debezium |
| `CDC-EVENTHUB-LISTEN-CONNECTION` | Event Hub > udip-reader policy | UDIP middleware |
| `HUB-AUDIT-HMAC-KEY` | `openssl rand -base64 40` | MCP Hub |
| `HUB-AUDIT-HASH-SALT` | `openssl rand -base64 40` | MCP Hub |
| `ARC-AUDIT-HMAC-KEY` | `openssl rand -base64 40` | ARC Integration API |
| `MCP-WEBHOOK-SECRET-ADR` | `openssl rand -base64 32` | MCP Hub ↔ ADR |
| `MCP-WEBHOOK-SECRET-TRIAGE` | `openssl rand -base64 32` | MCP Hub ↔ Triage |
| `MCP-WEBHOOK-SECRET-ARC-INTEGRATION` | `openssl rand -base64 32` | MCP Hub ↔ ARC API |
| `MCP-WEBHOOK-SECRET-OGC` | `openssl rand -base64 32` | MCP Hub ↔ OGC |
| `MCP-WEBHOOK-SECRET-UDIP` | `openssl rand -base64 32` | MCP Hub ↔ UDIP |
| `HUB-CLIENT-SECRET` | Entra ID > EEOC-MCP-Hub > Client secret | MCP Hub |
| `ADR-CLIENT-SECRET` | Entra ID > EEOC-ADR-Mediation > Client secret | ADR |
| `TRIAGE-CLIENT-SECRET` | Entra ID > EEOC-OFS-Triage > Client secret | Triage |
| `UDIP-CLIENT-SECRET` | Entra ID > EEOC-UDIP-Analytics > Client secret | UDIP |
| `OGC-CLIENT-SECRET` | Entra ID > EEOC-OGC-TrialTool > Client secret | OGC |
| `ARC-INTEGRATION-CLIENT-SECRET` | Entra ID > EEOC-ARC-Integration > Client secret | ARC API |
| `ARC-OAUTH-CLIENT-ID` | From ARC team | ARC Integration API |
| `ARC-OAUTH-CLIENT-SECRET` | From ARC team | ARC Integration API |
| `OPENAI-API-KEY` | Azure OpenAI > Keys (or use managed identity instead) | AI apps |
| `SEARCH-ADMIN-KEY` | Cognitive Search > Keys | Triage |
| `ADR-FLASK-SECRET` | `openssl rand -hex 32` | ADR webapp |
| `TRIAGE-FLASK-SECRET` | `openssl rand -hex 32` | Triage webapp |
| `OGC-FLASK-SECRET` | `openssl rand -hex 32` | OGC webapp |
| `UDIP-FLASK-SECRET` | `openssl rand -hex 32` | UDIP AI Assistant |
| `SUPERSET-SECRET-KEY` | `openssl rand -hex 32` | UDIP Superset |
| `LOGINGOV-CLIENT-ID` | Login.gov dashboard | ADR |
| `LOGINGOV-PRIVATE-KEY` | Login.gov dashboard (PKCS#8 PEM) | ADR |
| `PREPA-PG-HOST` | From ARC DBA | Debezium |
| `PREPA-PG-USER` | From ARC DBA | Debezium |
| `PREPA-PG-PASSWORD` | From ARC DBA | Debezium |
| `PREPA-PG-DATABASE` | From ARC DBA | Debezium |
| `APPINSIGHTS-CONNECTION-STRING` | Application Insights > Connection String | All apps |
| `AZURE-STORAGE-CONNECTION-STRING` | Storage account > Access keys | MCP Hub, audit |

---

## Appendix D: All Entra ID App Registrations and Roles

| App Registration | Client ID Env Var | App Roles | API Permissions | Redirect URI |
|-----------------|-------------------|-----------|-----------------|-------------|
| `EEOC-MCP-Hub` | `HUB_CLIENT_ID` | Hub.Read, Hub.Write | — (exposes APIs) | None (M2M) |
| `EEOC-ADR-Mediation` | `ADR_CLIENT_ID` | MCP.Read, MCP.Write | EEOC-MCP-Hub: Hub.Read, Hub.Write | `https://{adr-domain}/auth/callback` |
| `EEOC-OFS-Triage` | `TRIAGE_CLIENT_ID` | MCP.Read, MCP.Write | EEOC-MCP-Hub: Hub.Read, Hub.Write | `https://triage.internal.eeoc.gov/auth/callback` |
| `EEOC-UDIP-Analytics` | `UDIP_CLIENT_ID` | Analytics.Read, Analytics.Write | EEOC-MCP-Hub: Hub.Read, Hub.Write | `https://udip.eeoc.gov/auth/callback` |
| `EEOC-OGC-TrialTool` | `OGC_CLIENT_ID` | MCP.Read, MCP.Write | EEOC-MCP-Hub: Hub.Read, Hub.Write | `https://ogc-trialtool.eeoc.gov/auth/callback` |
| `EEOC-ARC-Integration` | `ARC_CLIENT_ID` | ARC.Read, ARC.Write | EEOC-MCP-Hub: Hub.Read, Hub.Write | None (M2M) |

### Entra ID Security Groups

| Group Name | Purpose | Members |
|-----------|---------|---------|
| `EEOC-AI-Platform-Admins` | Full platform access | Platform team |
| `UDIP-Data-Analysts` | UDIP query access (PII Tier 1) | Analysts |
| `UDIP-Data-Stewards` | UDIP admin access (PII Tier 2) | Data stewards |
| `UDIP-Data-Region-{region}` | Regional RLS scoping | Users by district |
| `UDIP-PII-Tier2` | De-identified PII access | Authorized analysts |
| `UDIP-PII-Tier3` | Full PII access (restricted) | Legal, investigators |
| `UDIP-Legal-Counsel` | OGC litigation access | OGC attorneys |
| `ADR-Mediators` | ADR mediator role | Mediators |
| `ADR-Admins` | ADR admin role | ADR supervisors |

---

## Appendix E: Network Diagram

```
                    Internet
                       │
                       ▼
              ┌────────────────┐
              │  Front Door    │  adr-eeoc.azurefd.net
              │  + WAF Policy  │  OWASP 3.2, bot mgr, rate limit
              └───────┬────────┘
                      │ HTTPS (443)
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  VNet: vnet-eeoc-ai-prod  (10.100.0.0/16)                      │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  snet-apps (10.100.1.0/24)  [NSG: nsg-eeoc-apps-prod]  │    │
│  │                                                          │    │
│  │  ca-adr-webapp-prod         (2 CPU, 4Gi, 3-12 replicas)│    │
│  │  ca-adr-functionapp-prod    (1 CPU, 2Gi, 2-6 replicas) │    │
│  │  ca-triage-webapp-prod      (1 CPU, 2Gi, 2-6 replicas) │    │
│  │  ca-triage-functionapp-prod (2 CPU, 4Gi, 2-8 replicas) │    │
│  │  ca-udip-ai-assistant-prod  (2 CPU, 4Gi, 2-6 replicas) │    │
│  │  ca-udip-superset-prod      (2 CPU, 4Gi, 2-4 replicas) │    │
│  │  ca-udip-portal-prod        (0.25 CPU, 512Mi, 2-4 rep) │    │
│  │  ca-debezium-connect-prod   (2 CPU, 4Gi, 1-2 replicas) │    │
│  │  ca-pgbouncer-prod          (0.5 CPU, 1Gi, 2-4 rep)    │    │
│  │  ca-mcp-hub-func-prod       (0.5 CPU, 1Gi, 2-4 rep)    │    │
│  │  apim-eeoc-mcp-hub-prod     (APIM Standard v2)         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  snet-postgres (10.100.2.0/24)   │                           │
│  │  [NSG: nsg-eeoc-postgres-prod]   │                           │
│  │                                   │                           │
│  │  pg-eeoc-udip-prod               │  ← primary (R/W)         │
│  │  pg-eeoc-udip-prod-replica       │  ← replica (R/O)         │
│  └──────────────────────────────────┘                           │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  snet-redis (10.100.3.0/24)      │                           │
│  │  pe-redis-eeoc-ai-prod           │                           │
│  └──────────────────────────────────┘                           │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  snet-storage (10.100.4.0/24)    │                           │
│  │  pe-st-eeoc-ai-prod (blob)       │                           │
│  │  pe-st-eeoc-ai-prod (table)      │                           │
│  └──────────────────────────────────┘                           │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  snet-keyvault (10.100.5.0/24)   │                           │
│  │  pe-kv-eeoc-ai-prod              │                           │
│  └──────────────────────────────────┘                           │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  snet-eventhub (10.100.6.0/24)   │                           │
│  │  pe-evh-eeoc-cdc-prod            │                           │
│  └──────────────────────────────────┘                           │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  snet-frontdoor (10.100.7.0/24)  │                           │
│  │  (reserved for Front Door)        │                           │
│  └──────────────────────────────────┘                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

External Dependencies (outside VNet):
  ├── ARC PrEPA PostgreSQL  ← WAL/CDC via Debezium
  ├── ARC FEPA Gateway      ← REST API via ARC Integration API
  ├── Login.gov             ← OIDC auth for ADR external parties
  ├── Azure OpenAI          ← GPT-4o, text-embedding-3-small
  └── Azure Cognitive Search ← Triage RAG index
```

---

*Document version 1.0 — 2026-04-06*
