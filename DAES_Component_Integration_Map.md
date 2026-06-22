# DAES Component Integration Map
**Author:** Derek Gordon

## Data and AI Enterprise System (DAES)

---

This document describes how the DAES components connect to each other. It covers
the real integration points verified against live code: the MCP routing layer, the
ARC constraint, the session store, the event path, and the audit/WORM chain.

Deployment topology and per-component environment variables are in
`EEOC_AI_Platform_Complete_Deployment_Guide.md`. Entra ID app-role wiring is in
`DAES_Entra_ID_Configuration_Guide.md`. This document focuses on runtime data flows.

---

## 1. Component Inventory

| Component | Repo | Protocol | Inbound auth |
|---|---|---|---|
| UDAP (AI Assistant + dashboard) | `eeoc-data-analytics-and-dashboard` | HTTP (Flask/Gunicorn) | Entra OIDC (browser), `Analytics.Read`/`Analytics.Write` bearer (MCP) |
| ADR Portal | `eeoc-ofs-adr` | HTTP (Flask/Gunicorn) | Entra OIDC (browser), `MCP.Read`/`MCP.Write` bearer (MCP) |
| Triage | `eeoc-ofs-triage` | HTTP (Flask/Gunicorn) | Entra OIDC (browser), `MCP.Read`/`MCP.Write` bearer (MCP) |
| OGC Trial Tool | `eeoc-ogc-trialtool` | HTTP (Flask/Gunicorn) | Entra OIDC (browser), `MCP.Read`/`MCP.Write` bearer (MCP) |
| OCHCO Benefits Validation | `eeoc-ochco-benefits-validation` | HTTP (Flask/Gunicorn) | `MCP.Read` bearer only (no browser users) |
| ARC Integration API | `eeoc-arc-integration-api` | HTTP (FastAPI/Uvicorn) | `ARC.Read`/`ARC.Write`/`Access.Read`/`Access.Admin` bearer |
| MCP Hub | `eeoc-mcp-hub-functions` | HTTP (Azure Functions) | `MCP.Read` bearer (from AI consumers) |
| Access Admin | `eeoc-access-admin` | HTTP (Flask) | Entra OIDC (browser only) |

---

## 2. Integration Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DAES - Runtime Integration Map                             │
│                    Azure Commercial · AKS / Container Apps                   │
└──────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────┐
  │   EEOC Staff (@eeoc.gov)│
  │   Entra ID → OIDC       │
  └───────────┬─────────────┘
              │  browser HTTPS
              ▼
  ┌─────────────────────────┐     ┌────────────────────────────┐
  │  ADR Portal             │     │  External Parties          │
  │  Triage                 │     │  Login.gov (OIDC+PKCE)     │
  │  OGC Trial Tool         │     └────────────┬───────────────┘
  │  UDAP (portal/dashboard)│                  │
  │  Access Admin           │◄─────────────────┘
  └────────┬──────────────┬─┘      browser HTTPS
           │              │
           │ Redis         │ inter-service HTTPS
           │ sessions      │ Bearer token (Entra M2M)
           ▼              ▼
  ┌─────────────┐  ┌──────────────────────────────────────────────┐
  │  Redis      │  │              MCP Hub                          │
  │  (sessions  │  │  eeoc-mcp-hub-functions                       │
  │  + cache)   │  │  · Routes by tool-name prefix                 │
  └─────────────┘  │  · Reconciles spoke catalog every 5 min       │
                   │  · Logs every call to hubauditlog + WORM blob │
                   │  · Uses DefaultAzureCredential (MI) to call   │
                   │    spokes - no client secret                   │
                   └─────────────────┬────────────────────────────┘
                                     │
              ┌──────────────────────┼───────────────────────────────┐
              │  HTTPS + Bearer      │  ARC.Read / MCP.*/Analytics.* │
     ┌────────▼──────┐  ┌───────────▼──────┐  ┌──────────▼─────────┐
     │  ADR Portal   │  │  Triage          │  │  UDAP AI Assistant  │
     │  POST /mcp    │  │  POST /mcp       │  │  POST /mcp          │
     │  MCP.Read     │  │  MCP.Read        │  │  Analytics.Read     │
     │  MCP.Write    │  │  MCP.Write       │  │  Analytics.Write    │
     │  MCP.ReadConf │  │  (tool prefix:   │  │  (tool prefix:      │
     │  MCP.WriteConf│  │   triage_*)      │  │   query_* / search_ │
     │  (tool prefix:│  └──────────────────┘  │   / ingest_*)       │
     │   case_*      │                         └─────────────────────┘
     │   chat_*      │  ┌───────────▼──────┐  ┌──────────▼─────────┐
     │   doc_*       │  │  OGC Trial Tool  │  │  OCHCO Benefits     │
     └───────────────┘  │  POST /mcp       │  │  POST /mcp          │
                        │  MCP.Read        │  │  MCP.Read           │
                        │  MCP.Write       │  │  (tool prefix:      │
                        │  (tool prefix:   │  │   benefits_*)       │
                        │   trial_*)       │  └─────────────────────┘
                        └──────────────────┘
                                     │
              ┌──────────────────────┘
              │  ARC.Read / ARC.Write
              ▼
  ┌──────────────────────────────────────────────────────┐
  │  ARC Integration API                                  │
  │  eeoc-arc-integration-api                             │
  │  · ONLY service that calls ARC backbone directly      │
  │  · Exposes ARC data as MCP tools (18 tools)           │
  │  · Access subsystem: Access.Read + Access.Admin       │
  └───────────────────────────────┬──────────────────────┘
                                  │
                    ┌─────────────┴────────────┐
                    │                          │
                    ▼                          ▼
          ┌──────────────────┐      ┌─────────────────────┐
          │  ARC backbone    │      │  Access Admin UI     │
          │  PrEPA / FEPA    │      │  eeoc-access-admin   │
          │  Gateway (AKS)   │      │  Calls ARC Int. API  │
          │  Service Bus     │      │  Access.Read + Admin │
          └──────────────────┘      └─────────────────────┘
```

---

## 3. Integration Points in Detail

### 3.1 AI consumer → MCP Hub

AI consumers (the UDAP AI assistant, and future MCP-compatible clients) call the Hub
at a single endpoint. The Hub holds an inbound bearer token requirement; callers must
present an Entra ID token with a Hub-level role or a spoke-level role (depending on
whether APIM or the Functions host validates it).

- Protocol: JSON-RPC 2.0 over HTTPS, MCP protocol version 2025-03-26
- Env var on callers: `MCP_HUB_URL`, `MCP_ENABLED=true`, `MCP_PROTOCOL_ENABLED=true`
- Both flags default to `false` platform-wide. Every component starts and passes its
  health check with them off.

Source: `eeoc-ofs-adr/deploy/k8s/adr-webapp/configmap.yaml`;
`eeoc-ofs-triage/deploy/k8s/triage-webapp/configmap.yaml`.

### 3.2 MCP Hub → spokes (tool routing by prefix)

The Hub routes a tool call to the correct spoke by matching the tool name prefix.
Each spoke registers its tools in the Hub's `mcpspokes` Azure Table Storage table.
The Hub reconciles the spoke catalog on a 5-minute interval
(`RECONCILIATION_INTERVAL_SECONDS=300`).

| Tool prefix | Spoke | Role the Hub MI holds |
|---|---|---|
| `case_*`, `chat_*`, `doc_*`, `participant_*` | ADR Portal | `MCP.Read`, `MCP.Write` |
| `triage_*` | OFS Triage | `MCP.Read`, `MCP.Write` |
| `trial_*` | OGC Trial Tool | `MCP.Read`, `MCP.Write` |
| `benefits_*` | OCHCO Benefits Validation | `MCP.Read` |
| `query_*`, `search_*`, `ingest_*`, `get_*` | UDAP AI Assistant | `Analytics.Read`, `Analytics.Write` |
| `arc_*` | ARC Integration API | `ARC.Read`, `ARC.Write` |

The Hub uses `DefaultAzureCredential` (managed identity) to acquire spoke tokens at
call time. Scope: `api://<spoke-client-id>/.default`.

Source: `eeoc-mcp-hub-functions/hub_functions/auth.py`;
`eeoc-mcp-hub-functions/hub_functions/config.py:25`.

### 3.3 ARC constraint - only ARC Integration API calls ARC directly

No component other than `eeoc-arc-integration-api` may call ARC backbone services
(PrEPA, FEPA Gateway, Service Bus). All write-back and targeted lookup operations
from ADR, Triage, and the Hub go through the ARC Integration API MCP tools.

The ARC Integration API is the only service that holds ARC backbone credentials
(`arc_client_id`, `arc_client_secret`, `arc_gateway_url`, `arc_prepa_url`,
`arc_auth_url`).

Source: `eeoc-arc-integration-api/app/config/__init__.py:16-20`.

### 3.4 UDAP data path - CDC pipeline, not the MCP Hub

UDAP receives ARC data via a separate WAL/CDC pipeline that does not go through the
Hub:

```
ARC PrEPA (PostgreSQL)
  └─ logical replication slot
       └─ Debezium connector (deploy/cdc-pipeline/k8s/)
            └─ Azure Event Hub (evhns-eeoc-ai-*)
                 └─ Data Middleware (data-middleware/)
                      └─ UDAP PostgreSQL (arc_analytics schema)
                           └─ dbt transform cronjob
                                └─ analytics schema → Superset dashboards
```

The IDR (SQL Server nightly snapshot) is used as a reconciliation source twice weekly,
not as the primary ingest path.

The MCP Hub routes **queries** to UDAP; it does not feed data into UDAP. The Hub's
`arc_*` tools route to the ARC Integration API for write-back and targeted real-time
lookups (mediation eligibility, charge metadata). Data queries go to UDAP.

Source: `eeoc-mcp-hub-functions/hub_functions/` (Hub is stateless on data);
`MCP_Hub_Build_Guide_Supplement.md:23` (CDC pipeline description, archive).

### 3.5 Redis sessions

All user-facing applications use Redis for server-side session storage. No session
data is serialized to browser cookies.

| Component | Redis usage |
|---|---|
| ADR Portal | Flask-session (REDIS-HOST + REDIS-PASSWORD from Key Vault) |
| Triage | Flask-session |
| OGC Trial Tool | Flask-session |
| UDAP AI Assistant | Flask-session (REDIS-URL from Key Vault) |
| Access Admin | Flask-session (REDIS_URL env var) |
| ARC Integration API | Response caching (REDIS_URL env var) |
| MCP Hub | Tool catalog caching (REDIS_URL env var, `mcp:tool_catalog` key) |

### 3.6 ADR → ARC Integration API write-back

ADR does not call ARC directly. Mediation outcomes, document uploads, and action-date
logs are routed through the Hub to ARC Integration API tools:

- `arc_close_mediation_case` (requires `ARC.Write`)
- `arc_log_case_events` (requires `ARC.Write`)
- `arc_upload_case_document` (requires `ARC.Write`)

ADR also calls the ARC Integration API directly (bypassing the Hub) for pre-case
operations:
- `ARC_INTEGRATION_API_URL` (env var, ConfigMap) - charge lookup and mediation
  eligibility checks via `ARC.Read`-gated endpoints.

Source: `eeoc-ofs-adr/deploy/k8s/adr-webapp/configmap.yaml:14`;
`MCP_Hub_Build_Guide_Supplement.md:46-52`.

### 3.7 Access Admin → ARC Integration API

The Access Admin UI has no local database. All grant CRUD operations call the ARC
Integration API's access subsystem:

- Reads grants: `Access.Read` role
- Creates/revokes grants: `Access.Admin` role

Access Admin authenticates to the ARC Integration API using a confidential M2M
credential (`ARC_API_CLIENT_ID`, `ARC_API_CLIENT_SECRET`/`ARC_API_SCOPE`).

Source: `eeoc-access-admin/access_admin/config.py:30-33`.

### 3.8 ARC backbone events → Hub

The ARC Integration API forwards selected ARC Service Bus events to the Hub as
HTTPS/HMAC-SHA256 webhook calls. The Hub receives them at `/api/v1/events`. The Hub
then routes relevant events to downstream spokes (ADR, Triage) that subscribe to case
lifecycle changes.

Service Bus topics in the ARC Integration API:
- `db-change-topic` (database change notifications)
- `document-activity-topic` (document events)

Source: `eeoc-arc-integration-api/app/config/__init__.py:25-29`.

ADR pushes its own internal events to the Hub via HMAC-signed webhook
(`MCP_CALLBACK_URL`, `adr_webapp/mcp_event_dispatcher.py`). Event types:
`case.created`, `case.started`, `case.closed`, `case.disposed`, `case.reassigned`.

---

## 4. Audit and WORM Path

Every AI generation across all components produces an HMAC-SHA256 signed audit record
per NARA 7-year retention (M-21-31, AU-10, AU-11).

```
AI generation call
  └─ Component audit logger
       ├─ Azure Table Storage (queryable; partition key = date)
       │    ├─ ADR: aigenerationaudit
       │    ├─ ARC Integration API: arcintegrationaudit
       │    └─ MCP Hub: hubauditlog
       └─ WORM blob container (immutable; 2555-day retention policy)
            ├─ ADR: (blob container per constants.py)
            ├─ ARC Integration API: arc-integration-archive
            └─ MCP Hub: hub-audit-archive
```

HMAC keys by component:

| Component | Key Vault secret | Env var |
|---|---|---|
| ADR Portal | (loaded from Key Vault at startup) | `AI_AUDIT_HMAC_KEY` |
| ARC Integration API | loaded via `pydantic_settings` | `ARC_AUDIT_HMAC_KEY` |
| MCP Hub | `HUB_AUDIT_HMAC_KEY` | `HUB_AUDIT_HMAC_KEY` |
| UDAP AI Assistant | `AI-AUDIT-HMAC-KEY` (Key Vault) | `ai-audit-hmac-key` |
| OCHCO Benefits Validation | `benefits-ai-hmac-key` (Key Vault) | `AI_AUDIT_HMAC_KEY` |

The Hub audit logger fails hard in production if `HUB_AUDIT_HMAC_KEY` is empty or
shorter than 32 characters.

Source: `eeoc-mcp-hub-functions/hub_functions/audit_logger.py:43-58`.

---

## 5. Feature-Flag Defaults

Every integration point is gated behind a feature flag that defaults to `false`.
Components start and pass health checks with all integrations disabled.

| Flag | Default | Controls |
|---|---|---|
| `MCP_ENABLED` | `false` | MCP tool dispatch and event sending |
| `MCP_PROTOCOL_ENABLED` | `false` | MCP server endpoint exposure |
| `MCP_SERVER_EXPOSE` | `false` | Spoke registration with Hub |
| `ARC_LOOKUP_ENABLED` | `false` | ARC charge lookups in Triage |
| `ARC_SYNC_ENABLED` | `true` | ADR sync importer (set `false` to disable) |
| `LOGINGOV_ENABLED` | not set | Login.gov login button on ADR/Triage |
| `UNIFIED_ACCESS_ENABLED` | not set | Unified access control across user-facing apps |
| `MEDIATOR_AI_MULTITURN` | `true` | ADR mediator advisor sends its private channel as role-tagged turns (vs. legacy single prompt) |
| `MEDIATOR_AI_VERIFY` | `true` | ADR mediator advisor verifies cited quotes against case sources |
| `MEDIATOR_AI_VECTOR_RETRIEVAL` | `false` | ADR mediator advisor semantic retrieval; requires `PG_MIGRATION_MODE` past `off` |

### 5.1 ADR mediator advisor — conversation data and DB-swap fit

The ADR mediator AI advisor is multi-turn: the mediator's private `mediator_ai`
channel is sent to the model as alternating user/assistant turns, while the rest
of the case (other channels, documents, notes) is passed as a separate system
context message marked as untrusted data.

Two properties matter at the platform level:

- **Case isolation.** Conversation content is read only through
  `get_all_conversations(case_id)`, which filters on `PartitionKey == case_id`.
  The thread and context can therefore contain a single case's records only;
  no cross-case or cross-mediator content can enter the prompt, and the reply
  posts back only to that case's private channel. The post-migration pgvector
  retrieval path must apply the same mandatory `case_id` filter.
- **DB-swap migration fit.** The advisor does not keep a separate conversation
  store. It reads the existing `chatlogs` records through that one read path,
  which migrates to PostgreSQL (`operations.adr_chat_messages`) under the
  platform `PG_MIGRATION_MODE` swap (`off` → `dual_write` → `pg_primary` →
  `pg_only`). Because the read goes through a single chokepoint, the advisor
  follows the swap with no feature-specific change.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial release - expands §4 of DAES_Test_Environment_Static_Import_Playbook.md |
| 1.1 | June 2026 | Derek Gordon / OIT | Add §5.1 mediator advisor conversation data, case isolation, and DB-swap migration fit; add mediator AI feature flags |
