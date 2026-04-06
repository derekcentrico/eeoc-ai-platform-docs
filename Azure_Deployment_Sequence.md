# Azure Deployment Sequence

**Date:** 2026-04-03
**Purpose:** Step-by-step deployment order for standing up the full EEOC integration platform on Azure Government.
**Prerequisite:** All 26 implementation prompts completed. Code in repos. Prompt 27 (tests) can run in parallel.

---

## Phase 0: Azure Foundation (Week 1)

These are portal/CLI operations. No custom code deployed yet.

### 0.1 Resource Groups
```
az group create --name rg-eeoc-integration-prod --location usgovvirginia
az group create --name rg-eeoc-integration-dev --location usgovvirginia
```

### 0.2 Virtual Network
- VNet: `vnet-eeoc-integration` (10.100.0.0/16)
- Subnets: apim (10.100.1.0/24), apps (10.100.2.0/24), storage (10.100.3.0/24), keyvault (10.100.4.0/24), postgres (10.100.5.0/24)
- VNet peering to existing spoke VNets (ADR, Triage, UDIP, OGC if separate)

### 0.3 Key Vault
- `kv-eeoc-integration-prod`
- Private endpoint in keyvault subnet
- Secrets: HMAC keys, hash salts, ARC OAuth2 credentials, PrEPA DB credentials
- Access: RBAC-based, managed identities only

### 0.4 Storage Account (Audit)
- `steeocintegrationaudit`
- GRS redundancy
- Table: `hubauditlog`
- Container: `hub-audit-archive` with 2555-day WORM policy
- Private endpoint in storage subnet

### 0.5 Azure Cache for Redis
- `redis-eeoc-integration`
- Premium tier (for VNet integration)
- Used by: hub aggregator (tool catalog cache), ADR (sessions + feature flags), Triage (sessions + rate limiting), UDIP (rate limiting)

### 0.6 Entra ID App Registrations
Create per `Azure_MCP_Hub_Setup_Guide.md` Step 5:
- EEOC-MCP-Hub (Hub.Read, Hub.Write)
- EEOC-ARC-Integration (ARC.Read, ARC.Write)
- Verify existing registrations for ADR, Triage, UDIP, OGC
- Grant hub managed identity access to each spoke's app roles
- Configure OBO permissions for UDIP (delegated Analytics.Read)

---

## Phase 1: Database + CDC Pipeline (Weeks 1-3)

### 1.1 Azure Database for PostgreSQL Flexible Server

**Source data profile:** PrEPA has ~800 GB across ~350 tables with ~8,500 columns. The full CDC replica will mirror this entirely into the `replica` schema. The `analytics` schema adds transformed/indexed data on top. Plan for 2-3x source size (replica + analytics + vectors + indexes).

**Sizing:**

| Component | Estimate |
|-----------|----------|
| Replica schema (raw PrEPA mirror) | ~800 GB |
| Analytics schema (transformed, indexed) | ~400 GB (subset of columns, PII redacted) |
| Vector embeddings (pgvector) | ~100 GB (narrative embeddings, document embeddings) |
| Indexes (GIN, btree, vector HNSW) | ~200 GB |
| WAL + temp space headroom | ~200 GB |
| **Total required** | **~1.7 TB** |

**Instance configuration:**
- `pg-eeoc-udip-prod`
- PostgreSQL 16 (or highest available in Gov Cloud)
- **Memory Optimized tier, 16 vCores, 128 GB RAM, 2 TB storage**
  - Memory Optimized (not General Purpose) because RLS predicate evaluation, GIN index scans, and pgvector HNSW distance calculations are memory-intensive
  - 128 GB RAM gives ~80 GB effective shared_buffers (PostgreSQL default 25% of RAM), enough to cache the most active analytics tables + indexes in memory
  - 2 TB storage with auto-grow enabled (Azure Flexible Server supports up to 16 TB)
  - IOPS: ~5,000 baseline with Premium SSD v2 (burst to 20,000)
- Private endpoint in postgres subnet
- Enable extensions: pgvector, pg_stat_statements, pgcrypto, pg_trgm
- Entra ID admin authentication enabled

**Connection handling for thousands of concurrent connections:**

The application layer (AI Assistant, MCP tools, Superset, JupyterHub, dbt) could generate hundreds to low thousands of simultaneous connections. PostgreSQL Flexible Server defaults to max_connections = 500-800 depending on tier. Direct connections at this scale will exhaust the pool and degrade performance.

**PgBouncer is mandatory.** Deploy as a sidecar or standalone service:

```
Clients (AI Assistant pods, Superset, JupyterHub, dbt, middleware)
    ↓ (thousands of logical connections)
PgBouncer (connection multiplexer)
    ↓ (50-100 actual PostgreSQL connections)
PostgreSQL Flexible Server
```

PgBouncer configuration for this workload:

| Setting | Value | Rationale |
|---------|-------|-----------|
| pool_mode | transaction | Release connection back to pool after each transaction (not session). Required for RLS with SET LOCAL. |
| max_client_conn | 3000 | Accept up to 3000 simultaneous client connections |
| default_pool_size | 80 | 80 actual PostgreSQL connections per database |
| reserve_pool_size | 20 | 20 extra connections for burst traffic |
| max_db_connections | 100 | Hard cap — never exceed 100 connections to PostgreSQL |
| server_idle_timeout | 300 | Close idle server connections after 5 minutes |
| query_timeout | 30 | Kill queries exceeding 30 seconds |
| client_idle_timeout | 600 | Disconnect idle clients after 10 minutes |

With this config: 3000 clients share 100 PostgreSQL connections. Each transaction takes a connection, runs the query (including SET LOCAL for RLS context), and returns the connection to the pool. Typical query duration: 50-200ms. At 100 connections × 5 queries/sec = 500 queries/sec throughput.

**Read replica for query offloading:**
- Enable Azure read replica (`pg-eeoc-udip-prod-replica`)
- Route all MCP read queries and Superset dashboards to the replica
- Route CDC writes, dbt rebuilds, and ingest to the primary
- This doubles effective read throughput and protects the primary from analyst query load

```
CDC Middleware → Primary (writes)
dbt rebuilds → Primary (writes)
Ingest API → Primary (writes)
    ↓ (async replication, <1 sec lag)
AI Assistant queries → Read Replica
Superset dashboards → Read Replica
JupyterHub notebooks → Read Replica
MCP tool queries → Read Replica
Reconciliation → Read Replica
```

**PostgreSQL tuning for this workload:**

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| shared_buffers | 32 GB | 25% of 128 GB RAM |
| effective_cache_size | 96 GB | 75% of RAM |
| work_mem | 64 MB | Per-sort/hash, generous for complex analytics queries |
| maintenance_work_mem | 2 GB | For VACUUM, CREATE INDEX, dbt rebuilds |
| max_worker_processes | 16 | Match vCore count |
| max_parallel_workers_per_gather | 4 | Parallelize large table scans |
| max_parallel_workers | 16 | Match vCore count |
| wal_buffers | 64 MB | High for CDC write throughput |
| checkpoint_completion_target | 0.9 | Spread checkpoint writes |
| random_page_cost | 1.1 | SSD storage, nearly sequential speed |
| effective_io_concurrency | 200 | SSD can handle concurrent I/O |
| max_connections | 250 | PgBouncer sends up to 200; leave 50 for admin, replication, monitoring |
| idle_in_transaction_session_timeout | 30s | Kill abandoned transactions |
| statement_timeout | 60s | Hard cap on query runtime |
| log_min_duration_statement | 1000 | Log queries exceeding 1 second |

**Table partitioning (from Prompt 9/15):**
- analytics.charges partitioned by fiscal_year (LIST partitioning)
- Each fiscal year: ~50-100K charges → manageable partition size
- Partition pruning means queries filtering by fiscal_year only scan relevant partition
- Dropping a fiscal year partition for lifecycle purge is instant (no vacuum)
- Auto-partition creation when CDC consumer encounters a new fiscal year

**Monitoring:**
- Azure Monitor: CPU, memory, connections, IOPS, storage, replication lag
- pg_stat_statements: top queries by total time, mean time, calls
- pg_stat_user_tables: per-partition scan counts (lifecycle access tracking)
- Alert thresholds: connections > 80%, CPU > 80%, replication lag > 30s, storage > 80%
- Run SQL scripts in order:
  ```
  001-extensions.sql
  002-schemas.sql
  003-replica-schema.sql
  010-analytics-tables.sql
  011-lifecycle-columns.sql
  012-lifecycle-tables.sql
  013-lifecycle-views.sql
  014-adr-triage-tables.sql  (from Prompt 16)
  020-vector-tables.sql
  030-document-tables.sql
  040-rls-policies.sql
  050-search-functions.sql
  ```

### 1.2 PgBouncer (from Prompt 23)
- Deploy as standalone Container App: `ca-pgbouncer`
- Configuration detailed in Section 1.1 above (3000 client connections → 100 PostgreSQL connections)
- Points to pg-eeoc-udip-prod (primary for writes) and pg-eeoc-udip-prod-replica (for reads)
- Health probe: PgBouncer SHOW STATS command via TCP check
- Deploy before any application connects to PostgreSQL

### 1.3 Azure Event Hub Namespace (for CDC)
- `evhns-eeoc-cdc`
- Kafka-enabled
- Standard tier, 4 throughput units
- Auto-inflate enabled (up to 8 TU)
- Topics auto-created by Debezium (prepa.public.*)
- Consumer group: udip-middleware
- 7-day message retention

### 1.4 Request WAL/CDC Access from ARC DBA
- Provide the two SQL commands:
  ```sql
  SELECT pg_create_logical_replication_slot('udip_cdc', 'pgoutput');
  CREATE PUBLICATION udip_publication FOR ALL TABLES;
  ```
- Request read-only PostgreSQL credentials for Debezium
- Request max_slot_wal_keep_size configuration

### 1.5 Deploy Debezium Connector
- Container App or Kubernetes Deployment
- Debezium PostgreSQL connector
- Connects to PrEPA PostgreSQL → streams to Event Hub
- Monitor: replication slot lag, connector health

### 1.6 Deploy UDIP Data Middleware (CDC Consumer)
- Container App: always-on Deployment (not CronJob)
- Consumes from Event Hub, applies YAML transforms, writes to UDIP PostgreSQL
- Verify: data flows from PrEPA → Event Hub → middleware → analytics tables

### 1.7 IDR Reconciliation CronJob
- Kubernetes CronJob: Tuesday + Friday at 03:00 UTC
- Compares UDIP analytics vs IDR SQL Server
- Verify: first reconciliation run completes, logs to middleware.reconciliation_log

---

## Phase 2: Application Deployments (Weeks 2-4, overlapping Phase 1)

### 2.1 ARC Integration API
- Container App: `ca-arc-integration`
- Internal ingress (VNet only)
- Environment: ARC_GATEWAY_URL, ARC_PREPA_URL, ARC_AUTH_URL, KEY_VAULT_URI
- Health probe: /healthz
- Verify: health returns 200, ARC OAuth2 token acquisition works

### 2.2 MCP Hub (Azure API Management)
- Follow `Azure_MCP_Hub_Setup_Guide.md` Steps 6-8
- APIM instance: `apim-mcp-hub`
- Internal VNet, Standard v2 tier
- Configure backends, routing policy, OBO for UDIP
- Deploy hub aggregator function: `func-mcp-hub-aggregator`
- Verify: /mcp endpoint returns merged tool catalog

### 2.3 Event Grid
- Follow `Azure_MCP_Hub_Setup_Guide.md` Step 9
- Topic: `evgt-mcp-hub-events`
- Subscriptions for ARC → ADR event routing

### 2.4 UDIP AI Assistant
- Container App: `ca-udip-ai-assistant`
- Environment: OPENAI_*, PG_*, REDIS_URL, KEY_VAULT_URI
- Health probe: /healthz
- Verify: /ai/query returns AI response, conversation history persists

---

## Phase 3: Spoke Connections (Weeks 3-5)

Follow the connection sequence from `Azure_MCP_Hub_Setup_Guide.md` Step 12.
Each spoke connection has gate criteria that must pass before moving to the next.

### 3.1 Connect ARC Integration API to Hub
- Register as spoke in hub aggregator
- Verify: write-back tools callable through APIM
- Verify: Service Bus events forwarding to Event Grid
- Gate: all 11 ARC tools in merged catalog, audit records written

### 3.2 Connect ADR to Hub
- Enable MCP_ENABLED + MCP_PROTOCOL_ENABLED on ADR
- Register as spoke
- Point ARCSyncImporter at ARC Integration API
- Verify: all 10 ADR tools callable, events round-trip
- Gate: X-Request-ID correlation in both hub and ADR audit logs

### 3.3 Connect Triage to Hub
- Enable MCP_ENABLED + MCP_SERVER_EXPOSE on Triage
- Register as spoke
- Enable ARC_LOOKUP_ENABLED for charge metadata auto-population
- Verify: read tools return data, async submit_case pattern works
- Gate: classification results write back to ARC via hub

### 3.4 Connect UDIP to Hub
- Verify OBO token delegation working (test with real user with region groups)
- Register as spoke
- Verify: AI query through hub returns regionally scoped data (NOT empty)
- Verify: dynamic tool catalog reconciles on dbt schedule
- Gate: regional user gets correct data, not empty results

### 3.5 Connect OGC Trial Tool to Hub
- Verify Entra ID auth replacement is live (no demo login)
- Register as spoke
- Verify: 3 tools callable through hub
- Gate: litigation data flows from ARC spoke through hub

### 3.6 Cross-Spoke Verification
- AI query touching 2+ spokes returns correct combined result
- Example: "Settlement rates by region this quarter" → UDIP
- Example: "Close mediation case 370-2026-00123" → ARC Integration API → PrEPA → WAL/CDC → UDIP
- Verify request_id correlates across all audit logs

---

## Phase 4: Lifecycle + Monitoring (Week 5-6)

### 4.1 Data Lifecycle Automation
- Deploy lifecycle CronJobs (daily state transitions, weekly access stats)
- Verify: lifecycle_state transitions work, access_stats populated
- Test: set a FOIA hold, verify purge blocked

### 4.2 UDIP Analytics Push
- Enable ADR → UDIP daily push (UDIPAnalyticsPush Azure Function)
- Enable Triage → UDIP daily push
- Verify: analytics tables populated after push runs

### 4.3 Monitoring and Alerting
- Azure Monitor alerts on: APIM error rates, spoke health, CDC lag, PostgreSQL connections
- Application Insights for each Container App
- Log Analytics workspace for centralized querying
- Dashboard: spoke health, tool invocation rates, audit volume, CDC lag

---

## Phase 5: AI Assistant Go-Live (Week 6-7)

### 5.1 AI Assistant Validation
- Conversation memory: verify multi-turn context works
- Visualization: verify charts render in browser
- Dashboard creation: verify Superset export works (if enabled)
- RLS: verify different regional users see different data
- Audit: verify all AI queries logged with correlation IDs

### 5.2 User Acceptance Testing
- Invite pilot group (5-10 analysts)
- Test: complex multi-turn queries, chart generation, follow-ups
- Collect feedback on query accuracy, response time, visualization quality

### 5.3 Production Cutover
- Remove IDR as primary data source (now reconciliation-only)
- Enable all feature flags in production
- Monitor for 1 week with heightened alerting thresholds

---

## Parallel Track: Tests (Prompt 27)

Run Prompt 27 per repo while deployment progresses:

| Session | Repo | Modules to Test |
|---------|------|----------------|
| T1 | eeoc-data-analytics-and-dashboard | conversation_store, chart_generator, dashboard_builder, eventhub_source, reconciliation |
| T2 | eeoc-ofs-adr | distributed_lock, UDIPAnalyticsPush, ARCSyncImporter |
| T3 | eeoc-ofs-triage | arc_lookup, UDIPAnalyticsPush, OpenAI retry |
| T4 | eeoc-ogc-trialtool | mcp_server, auth flow |

Tests don't block deployment. Run them in parallel and fix any failures as they surface.

---

## Quick Reference: What Depends on What

```
Phase 0 (Azure foundation)
    ↓
Phase 1.1-1.3 (PostgreSQL + Event Hub + PgBouncer)
    ↓
Phase 1.4-1.5 (ARC DBA grants WAL access → Debezium deployed)
    ↓
Phase 1.6 (CDC consumer running, data flowing to UDIP)
    ↓
Phase 2.1-2.4 (ARC API + Hub + Event Grid + AI Assistant deployed)
    ↓
Phase 3.1-3.6 (Spokes connected in sequence, each gated)
    ↓
Phase 4 (Lifecycle, analytics push, monitoring)
    ↓
Phase 5 (AI Assistant go-live, UAT, production cutover)
```

The critical path is: **Azure foundation → PostgreSQL → ARC DBA grants WAL → Debezium → CDC consumer → data flowing → spokes connect → AI go-live.**

The ARC DBA request (Phase 1.4) is the only external dependency. Everything else is on us.
