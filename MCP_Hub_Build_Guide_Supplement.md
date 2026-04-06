# MCP Hub Build Guide — Supplement for Hub Team

**Purpose:** This document fills the gaps between the existing MCP Hub Three-Application Integration document and what the hub team actually needs to build. The original document covers the three spoke apps well but does not address how the hub gets data from ARC, how OGC Trial Tool fits in, or several integration details that surfaced during the codebase review.

Read this alongside the existing integration document. Where they overlap, this one has more recent and more specific information.

**Audience:** The hub build team. Written as step-by-step instructions with enough context to understand why each piece matters.

---

## What the Hub Actually Does

The hub is a routing layer. It does not store case data, run AI models, or make business decisions. It does five things:

1. **Registers spokes** and learns what tools each one offers
2. **Routes tool calls** from AI consumers to the correct spoke
3. **Manages authentication** so each spoke gets the right token
4. **Forwards events** between spokes that need to know about each other's activity
5. **Logs everything** to an immutable audit trail for NARA 7-year retention

That is the entire scope. If you find yourself building business logic into the hub, stop and push it to a spoke instead.

**Important architectural context:** UDIP is the central internal data repository. It ingests a full replica of ARC's database in real-time via a WAL/CDC pipeline (PrEPA PostgreSQL → logical replication FOR ALL TABLES → Debezium → Azure Event Hub → UDIP replica schema → Data Middleware → analytics schema). All data passes through the UDIP Data Middleware, which provides YAML-driven column translation, value mapping, PII redaction, and schema validation. The IDR (nightly SQL Server snapshot) serves as a twice-weekly reconciliation source to verify CDC pipeline completeness. UDIP serves as the primary query target for analytics, cross-system lookups, and AI consumers. When an AI consumer asks a data question, the hub should route it to UDIP, not to ARC. The ARC Integration API spoke exists solely for **write-back** (pushing mediation outcomes and triage results back to ARC) and a small number of **targeted real-time lookups** (mediation eligibility, charge metadata at upload time, document metadata from ECM). It does not feed bulk data to UDIP — the CDC pipeline handles that independently.

---

## The Five Spokes You Are Connecting To

Your existing document covers three. There are five.

### Spoke 1: ADR Mediation Platform

- **MCP endpoint:** `POST /mcp` (JSON-RPC 2.0, protocol version 2025-03-26)
- **Feature gate:** `MCP_ENABLED=true` and `MCP_PROTOCOL_ENABLED=true` on ADR side
- **Auth:** Entra ID M2M bearer token. App roles: `MCP.Read` (read tools), `MCP.Write` (write tools)
- **Tools:** 10 total (4 read, 6 write)
- **Resources:** 5 (case listing, case detail, chat, documents, participants)
- **Prompts:** 2 (case summary, mediation status report)
- **Capability categories:** `case_management`, `document_storage`, `scheduling`
- **Events:** ADR pushes events to the hub via HTTPS webhook with HMAC-SHA256 signature
- **Event types:** case.created, case.started, case.closed, case.disposed, case.reassigned
- **Webhook validation:** X-MCP-Signature header, signed with a shared secret (32+ characters, stored in Key Vault on both sides)
- **Timeout:** 30 seconds recommended for tool calls
- **Pagination:** ADR case lists are bounded at 5,000 entities. Use filters (date range, office, status) for large result sets. There is no cursor pagination — results are capped, not paged.

**ADR write-back through ARC Integration API:** ADR does not write directly to ARC. Instead, ADR calls the hub, which routes write operations to the ARC Integration API spoke. The key write-back flows are:
- Mediation closure with outcome (success, impasse, withdrawal) and settlement data
- Action date logging (mediation started, session held, agreement signed)
- Document upload (signed settlement agreement, e-signed mediation agreement)
- Staff assignment updates

These write-backs use ARC Integration API tools (`arc_close_mediation_case`, `arc_log_case_events`, `arc_upload_case_document`), which map to PrEPA's existing write endpoints. The hub routes these calls the same way it routes reads -- it just requires the `ARC.Write` role on the caller's token.

**What the hub needs to provide to ADR before connecting:**
1. Hub's Entra ID app registration with `MCP.Read` and `MCP.Write` app roles defined
2. Hub's managed identity granted `MCP.Read` on ADR's app registration
3. Hub callback URL registered in ADR's Key Vault as `MCP_CALLBACK_URL`
4. Hub HMAC webhook secret (32+ chars) provided to ADR team for their Key Vault
5. Hub's `/api/v1/events` endpoint live and accepting events with the `MCPClient.EventPost` role
6. Hub's tool invocation proxy able to call `/api/v1/cases/*` and `/mcp` under bearer token
7. ARC Integration API write tools available through hub so ADR can push mediation outcomes back to ARC

### Spoke 2: OFS Triage System

- **MCP endpoint:** `POST /mcp` (JSON-RPC 2.0, protocol version 2025-03-26)
- **Feature gate:** `MCP_ENABLED=true` and `MCP_SERVER_EXPOSE=true` on Triage side
- **Auth:** Entra ID M2M bearer token. App roles: `MCP.Read`, `MCP.Write`
- **Tools:** 9 total (6 read, 3 write)
- **Resources:** 7 (cases, case detail, library, stats summary, drift, reliance, health)
- **Capability categories:** `case_management`, `analytics`, `document_storage`
- **Events:** Triage does not natively push events. Corrections are pull-based only.
- **Timeout:** 30 seconds for read tools, 60 seconds for `submit_batch` (up to 1,000 cases)

**Critical: Triage has two async tools.** `submit_case` and `submit_batch` do not complete synchronously. They enqueue work to an Azure processing queue and return immediately with a tracking ID. The actual classification happens in a background Azure Function and takes seconds to minutes.

The correct pattern:
1. Call `submit_case` → receive `{ "tracking_id": "abc123", "status": "queued" }`
2. Wait a reasonable interval (10-30 seconds)
3. Call `get_case` with the charge number → check if status has changed from `pending` to `classified`
4. If still pending, wait and poll again

**You have two options for handling this in the hub:**

**Option A (recommended):** Document the async pattern in the tool descriptions that get returned in `tools/list`. The AI model sees the description and understands it needs to poll. This is simpler and keeps the hub stateless.

**Option B:** Build a hub-level wrapper tool that calls `submit_case`, then polls `get_case` automatically, and only returns when classification is complete or a timeout expires. This is more complex and means the hub holds open connections for minutes.

Decide with the Triage team before connecting. The recommendation is Option A.

**What the hub needs to provide to Triage before connecting:**
1. Hub's managed identity granted `MCP.Read` (and `MCP.Write` if submitting cases) on Triage's app registration
2. Hub tool router configured to show Triage tools only in `case_management`, `analytics`, or `document_storage` contexts
3. Hub timeout set to 30+ seconds for read tools, 60+ seconds for batch operations

### Spoke 3: UDIP Analytics Platform

- **MCP endpoint:** `POST /mcp` (JSON-RPC 2.0, protocol version 2025-03-26)
- **Feature gate:** `MCP_ENABLED=true`, `MCP_PROTOCOL_ENABLED=true`, `MCP_SERVER_EXPOSE=true`
- **Auth:** Entra ID M2M bearer token. App roles: `Analytics.Read`, `Analytics.Write` (NOT MCP.Read/MCP.Write — this is intentional)
- **Tools:** 3 built-in (`search_narratives`, `get_metrics`, `get_dashboards`) plus N auto-generated `query_{dataset_name}` tools from dbt models. N changes whenever dbt runs.
- **Capability categories:** `analytics`, `narrative_search`, `reporting`
- **Events:** UDIP does not push events natively.

**Critical: The tool catalog is dynamic.** UDIP regenerates its tool list whenever dbt models are updated. A `query_fct_charges` tool that exists today might be renamed to `query_fct_charge_details` tomorrow if the dbt model name changes. New models create new tools automatically.

**What this means for the hub:**
- Your tool registry reconciliation loop (the 5-minute refresh) must call `tools/list` on UDIP every cycle, not just on initial connection
- You must handle tools appearing and disappearing between cycles without erroring
- When a tool disappears, remove it from the merged catalog. When a new one appears, add it
- Cap the number of UDIP tools shown in any single AI context to ~10. If UDIP has 30 dataset tools, showing all of them wastes context window and confuses the model

**Critical: Row-Level Security is a blocker until token delegation is resolved.**

UDIP enforces row-level security at the PostgreSQL layer. Every SQL query runs with session context set from the caller's Entra ID token:
- `app.current_regions` — comma-separated list of regions the caller can see
- `app.current_role` — the caller's role (Admin, Director, Analyst, etc.)
- `app.current_pii_tier` — what level of PII the caller can access (1, 2, or 3)

The hub's managed identity has no region claim, no role beyond `Analytics.Read`, and no PII tier. If the hub calls UDIP with its own token:
- Queries return zero rows (not an error — just empty results)
- The connection appears to work
- The data is silently wrong
- This is harder to diagnose than a connection failure

**Token delegation options (decide before connecting UDIP):**

**Option 1: Explicit region parameter.** Add a `region` parameter to each `query_{dataset}` tool on the UDIP side. The hub passes the caller's region from the original request context. UDIP uses this parameter instead of the token claim to set session context.
- Pro: Simple to implement
- Con: Changes UDIP's security model. Callers can request any region. UDIP team may not approve this

**Option 2: OAuth 2.0 On-Behalf-Of (OBO) flow.** The hub acquires a token for UDIP on behalf of the original caller, preserving their identity, region claims, and PII tier.
- Pro: Most architecturally correct. UDIP's security model stays unchanged
- Con: Requires additional Entra ID configuration (OBO must be explicitly enabled on both app registrations). The hub must receive the original caller's token (not just a request from an AI consumer)

**Option 3: Hub-managed region mapping.** The hub maintains a table mapping caller identities to their regions. When calling UDIP, the hub injects the region as a tool parameter.
- Pro: No UDIP changes needed
- Con: Hub now owns region assignment data, which is a maintenance burden and a potential source of drift

**The recommendation is Option 2 (OBO).** It is more work upfront but avoids creating security model exceptions or data maintenance obligations.

**What the hub needs to provide to UDIP before connecting:**
1. Hub's managed identity granted `Analytics.Read` on UDIP's app registration
2. Token delegation approach agreed upon and implemented
3. Hub tool router configured to show UDIP tools only in `analytics`, `narrative_search`, or `reporting` contexts
4. Hub reconciler handling dynamic tool catalogs (tools appearing/disappearing between refreshes)
5. Verification that a regional caller token returns correct regional data, not empty results

### Spoke 4: OGC Trial Tool

- **MCP endpoint:** Will be built at `POST /mcp` (does not exist yet)
- **Feature gate:** `MCP_ENABLED=true`, `MCP_SERVER_EXPOSE=true` (will be added)
- **Auth:** Will use Entra ID M2M bearer token with `MCP.Read`, `MCP.Write` (currently uses demo session auth — must be replaced first)
- **Tools:** 3 planned (`trial_get_case_status`, `trial_analyze_case`, `trial_list_cases`)
- **Capability categories:** `litigation`, `document_storage`
- **Events:** None planned

**This spoke is not ready to connect today.** It needs two things first:
1. Production authentication (replace demo login with Entra ID Government OIDC)
2. An MCP server endpoint exposing its AI analysis tools

Both are being handled separately (see the implementation prompts document). The hub team does not need to build anything special for OGC Trial Tool — it registers and connects the same way as every other spoke. But do not attempt to connect it until the auth and MCP server work is done.

**What the hub needs to provide to OGC Trial Tool before connecting:**
1. Hub's managed identity granted `MCP.Read` and `MCP.Write` on Trial Tool's app registration
2. Standard spoke registration (same as any other spoke)

### Spoke 5: ARC Integration API

- **MCP endpoint:** `POST /mcp` (JSON-RPC 2.0, protocol version 2025-03-26)
- **Auth:** Entra ID M2M bearer token. App roles: `ARC.Read`, `ARC.Write`
- **Tools:** 18 (10 read, 8 write)
- **Capability categories:** `case_management`, `reference_data`, `document_storage`
- **Events:** Forwards PrEPA's Service Bus events to the hub as HTTPS/HMAC webhook calls

**This service does not exist yet.** It is being built as a separate workstream (see the ARC Integration API section of the architecture plan). The hub team does not build this, but you need to know what it provides. Note: this service does NOT feed bulk data to UDIP. UDIP gets its data via a WAL/CDC pipeline (PrEPA PostgreSQL → Debezium → Event Hub → UDIP Data Middleware) that operates independently of the hub. The ARC Integration API provides write-back tools and a small number of targeted read tools:

**Read tools (ARC.Read):**

| Tool | What It Does |
|------|-------------|
| `arc_search_cases` | Search ARC cases by status, office, date range |
| `arc_get_case` | Full case detail by charge number |
| `arc_get_case_allegations` | Allegations with statute/basis/issue detail |
| `arc_get_case_staff` | Staff assignments for a case |
| `arc_get_case_documents` | Document metadata list |
| `arc_get_mediation_eligible` | Cases eligible for mediation (used by ADR) |
| `arc_get_charge_metadata` | Charge metadata for triage auto-population |
| `arc_get_litigation_case` | Litigation case detail (used by OGC Trial Tool) |
| `arc_get_sbi_combinations` | Statute/Basis/Issue reference data tree |
| `arc_get_offices` | EEOC office codes and hierarchy |

**Write tools (ARC.Write) -- these push results back to ARC:**

| Tool | What It Does | Primary Consumer |
|------|-------------|-----------------|
| `arc_update_mediation_status` | Update mediation status, party replies, eligibility reasons | ADR |
| `arc_assign_mediation_staff` | Assign or update mediation staff on a case | ADR |
| `arc_close_mediation_case` | Close case with full mediation outcome: closure reason, settlement amounts, monetary and non-monetary benefits, beneficiary counts | ADR |
| `arc_upload_case_document` | Upload a document to the case in ARC's ECM -- e.g., signed settlement agreement, e-signed mediation agreement | ADR |
| `arc_log_case_events` | Log action dates and milestones to ARC's event log -- mediation started, session held, agreement signed, settlement finalized | ADR |
| `arc_generate_signed_agreements` | Trigger generation of signed Agreement to Mediate and Confidentiality Agreement documents in ARC | ADR |
| `arc_post_triage_classification` | Write triage classification results (rank, merit score, summary) to ARC's event log so investigators see them | Triage |
| `arc_log_triage_events` | Log triage corrections and re-classifications as case events | Triage |

The write tools are critical. Without them, ADR and Triage are islands -- they consume ARC data but ARC never learns what happened. Mediation outcomes, settlement amounts, action dates, and classification results all need to flow back to the system of record.

**Write-back data flows:**

```
ADR closes mediation successfully:
  1. arc_close_mediation_case  -> PrEPA closes the charge with ADR resolution code
                                  + records beneficiaries and settlement amounts
  2. arc_upload_case_document  -> PrEPA/ECM stores the signed settlement agreement
  3. arc_log_case_events       -> PrEPA event log records: mediation complete date,
                                  agreement signed date, settlement finalized date

ADR mediation fails (impasse):
  1. arc_update_mediation_status -> PrEPA records ineligibility reason
  2. arc_close_mediation_case    -> PrEPA closes with impasse code (no benefits)
  3. arc_log_case_events         -> PrEPA event log records impasse date

Triage classifies a charge:
  1. arc_post_triage_classification -> PrEPA event log records rank (A/B/C),
                                       merit score, and one-line summary
  2. Investigator opens case in IMS -> sees triage result in event log
```

The ARC Integration API also forwards case lifecycle events from PrEPA's Azure Service Bus. When a case is created, updated, closed, or reassigned in ARC, the integration API receives the Service Bus message, transforms it into the hub's event format, signs it with HMAC-SHA256, and POSTs it to the hub's `/api/v1/events` endpoint.

**What the hub needs to provide to the ARC Integration API:**
1. Hub's managed identity granted `ARC.Read` and `ARC.Write` on the integration API's app registration
2. Hub's event ingestion endpoint (`/api/v1/events`) live and accepting HMAC-signed events
3. Hub callback URL and HMAC secret provided to the integration API team

---

## What You Need to Build

### 1. Spoke Registration System

Spokes register themselves with the hub at startup. You need a registration endpoint and a persistence layer for registrations.

**Registration payload:**
```json
{
  "name": "adr",
  "display_name": "ADR Mediation Platform",
  "url": "https://adr-app.azurewebsites.net/mcp",
  "capability_categories": ["case_management", "document_storage", "scheduling"],
  "auth_method": "azure_managed_identity",
  "auth_scope": "api://adr-client-id/.default",
  "app_roles_required": {
    "read": "MCP.Read",
    "write": "MCP.Write"
  },
  "protocol_version": "2025-03-26",
  "health_endpoint": "/healthz",
  "timeout_seconds": 30
}
```

Store registrations in Azure Table Storage. The hub should survive restarts without requiring all spokes to re-register.

**Endpoints:**
- `POST /api/v1/spokes/register` — register or update a spoke
- `GET /api/v1/spokes` — list all registered spokes with health status
- `DELETE /api/v1/spokes/{name}` — deregister a spoke

**Health checking:** Every 60 seconds, call each spoke's health endpoint. Track status (healthy, degraded, unreachable). Do not remove unreachable spokes automatically — just mark them and exclude their tools from the catalog until they recover.

### 2. Tool Registry and Reconciliation

The hub maintains a merged tool catalog from all spokes. This is the most important piece of the hub — it is what AI consumers interact with.

**How it works:**

1. When a spoke registers (or every 5 minutes on a timer), call `tools/list` on the spoke's MCP endpoint
2. Parse the response and store each tool with metadata: tool name, input schema, description, required role, spoke name, capability categories
3. Merge all spoke tools into one catalog
4. When an AI consumer calls `tools/list` on the hub, return the merged catalog

**Filtering:** The `tools/list` response should accept an optional `categories` parameter. If provided, only return tools whose capability categories overlap with the requested categories. This prevents AI consumers from seeing 35+ tools when they only need 5-10 for their task.

Example filtering:
- `categories=["case_management"]` → ADR case tools + Triage case tools + ARC case tools (~12 tools)
- `categories=["analytics", "reporting"]` → Triage analytics + UDIP query tools (~6-10 tools)
- `categories=["litigation"]` → OGC Trial Tool + ARC litigation tools (~5 tools)
- No categories parameter → all tools (use sparingly)

**Handling dynamic catalogs (UDIP):** The reconciliation loop must handle tools that appear or disappear between cycles. When a tool was in the catalog last cycle but is not in this cycle's `tools/list` response, remove it. When a new tool appears, add it. Do not cache tool catalogs across hub restarts — always reconcile from spokes on startup.

**Naming collisions:** If two spokes register tools with the same name, prefix with the spoke name. For example, both ADR and Triage have a tool called `list_cases`. In the merged catalog, these become `adr.list_cases` and `ofs-triage.list_cases`. Apply this prefixing to all tools to avoid ambiguity.

### 3. Tool Call Routing

When an AI consumer calls `tools/call` on the hub, the hub must:

1. Look up which spoke owns the tool (from the merged catalog)
2. Acquire an M2M token for that spoke (managed identity + spoke's auth scope)
3. Generate a request ID (UUIDv4) and set it as the `X-Request-ID` header
4. Forward the `tools/call` JSON-RPC request to the spoke's MCP endpoint
5. Wait for the response (respect the spoke's timeout setting)
6. Log the invocation to the audit table (request_id, tool_name, spoke_name, caller, response hash)
7. Return the spoke's response to the AI consumer

**Token acquisition:** Use `DefaultAzureCredential` with the spoke's auth scope. Each spoke has a different scope (e.g., `api://adr-client-id/.default`, `api://triage-client-id/.default`). Cache tokens with a 60-second pre-expiry buffer.

**OBO for UDIP:** When routing to UDIP, the hub must use OBO to preserve the original caller's identity. This means the hub needs the original caller's token (not just a client credentials token). The hub's inbound auth must preserve the caller's access token so it can be exchanged via OBO for UDIP calls.

**Error handling:**
- Spoke unreachable → return JSON-RPC error with code -32603 (internal error) and message "Spoke {name} is not available"
- Spoke returns error → forward the spoke's error response as-is to the caller
- Timeout → return JSON-RPC error with code -32603 and message "Spoke {name} timed out after {n} seconds"
- Auth failure → return JSON-RPC error with code -32603 and message "Unable to acquire token for spoke {name}"

### 4. Event Ingestion and Forwarding

The hub accepts events from spokes and the ARC Integration API, validates them, and optionally forwards them to interested subscribers. These events are for inter-spoke notifications (e.g., ADR needs to know when a case status changes in ARC). This is separate from the WAL/CDC pipeline that feeds UDIP — UDIP gets its data independently via PostgreSQL logical replication through the Data Middleware, not through the hub's event system.

**Ingestion endpoint:** `POST /api/v1/events`

**Validation:**
1. Extract the `X-MCP-Signature` header
2. Compute HMAC-SHA256 of the request body using the spoke's webhook secret (from Key Vault, keyed by spoke name)
3. Compare. Reject if mismatch (401 response)
4. Parse the event payload
5. Log to audit table
6. Check subscriber list for interested spokes
7. Forward event to each subscriber (with the hub's own HMAC signature)

**Event payload format (standardized across all spokes):**
```json
{
  "event_type": "case.status_changed",
  "source_system": "arc-integration-api",
  "timestamp": "2026-03-30T14:30:00Z",
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "data": {
    "charge_number": "370-2026-00123",
    "old_status": "FORMALIZED",
    "new_status": "IN_MEDIATION",
    "office_code": "37A"
  }
}
```

**Subscriber configuration:** Store in Azure Table Storage alongside spoke registrations. Each spoke can declare which event types it wants to receive. For the initial build:

| Source | Event Type | Subscribers |
|--------|-----------|------------|
| ARC Integration API | `case.status_changed` | ADR |
| ARC Integration API | `case.created` | ADR |
| ARC Integration API | `case.closed` | ADR |
| ARC Integration API | `case.staff_assigned` | ADR |
| ADR | `case.closed` | (log only — no subscribers initially) |
| ADR | `case.reassigned` | (log only) |

UDIP does not subscribe to real-time events. It uses watermark-based batch sync on its own schedule.

### 5. Audit Logging

Every tool invocation and every event must be logged to an immutable audit trail.

**Storage:** Two targets (dual-write, same pattern as ADR and Triage):
1. Azure Table Storage (`hubauditlog` table) — structured fields, truncated to 32 KB per property
2. Azure Blob Storage (`hub-audit-archive` container) — full JSON, WORM policy with 2555-day retention

**Fields per audit record:**

| Field | Type | Source |
|-------|------|--------|
| PartitionKey | string | Date (YYYY-MM-DD) |
| RowKey | string | `{request_id}_{timestamp_microseconds}` |
| RequestID | string (UUID) | Hub-generated |
| CallerOID | string | SHA-256 hash of caller's Entra ID object ID + salt |
| ToolName | string | The tool that was invoked |
| SpokeSystem | string | Which spoke handled the request |
| RequestPayload | string (max 32 KB) | Input parameters (truncated if needed) |
| ResponsePayload | string (max 32 KB) | Tool response (truncated if needed) |
| ResponseHash | string | SHA-256 of full response content |
| LatencyMs | int | Time from hub receiving request to returning response |
| StatusCode | int | HTTP status of spoke response |
| RetentionPolicy | string | Always `FOIA_7_YEAR` |
| DataClassification | string | Always `AI_AUDIT` |
| Timestamp | datetime | UTC |
| BlobArchivePath | string | Path in hub-audit-archive (when content exceeds 32 KB) |
| ContentTruncated | bool | True if table fields were truncated |

**The hash salt** for CallerOID must come from Key Vault (`HUB-AUDIT-HASH-SALT`). Do not hardcode it.

**The WORM policy** on `hub-audit-archive` must be set during provisioning (2555 days = 7 years + 1 day buffer). The hub application must never have delete permissions on this container.

### 6. Authentication

**Inbound (AI consumers calling the hub):**
- Validate Entra ID M2M bearer tokens
- JWKS discovery from `https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys`
- Check audience claim matches hub's client ID
- Check issuer claim matches `https://login.microsoftonline.com/{tenant_id}/v2.0`
- Extract `roles` claim and verify `Hub.Read` or `Hub.Write` (depending on whether the tool being called requires read or write)
- Extract caller's object ID (`oid` claim) for audit logging

**Outbound (hub calling spokes):**
- For each spoke, acquire a token using `DefaultAzureCredential` with the spoke's auth scope
- Cache tokens with 60-second pre-expiry buffer
- Different spokes may require different scopes (ADR uses `api://adr-client-id/.default`, UDIP uses `api://udip-client-id/.default`)

**OBO flow (hub calling UDIP on behalf of the original caller):**
- The hub must receive the caller's access token in the inbound request
- Use MSAL's `acquire_token_on_behalf_of()` with the caller's token and UDIP's scope
- The resulting OBO token carries the original caller's claims (including region groups)
- Only needed for UDIP. All other spokes work fine with client credentials

### 7. Health and Readiness

Three health endpoints:

- `GET /healthz` — liveness probe. Returns 200 if the process is running. No dependency checks.
- `GET /readyz` — readiness probe. Returns 200 if the hub can reach its dependencies (Table Storage, Key Vault). Returns 503 if not.
- `GET /api/v1/health` — detailed health for operators. Returns per-spoke health status, tool counts, last reconciliation time, event ingestion status.

---

## Connection Sequence

Do not connect all five spokes at once. Follow this sequence:

| Step | What Connects | Gate Criteria |
|------|--------------|---------------|
| 1 | Hub infrastructure only | Health, auth, events, and VNet are all working. All Build Guide acceptance tests pass |
| 2 | ARC Integration API (as first spoke) | Write-back tools and targeted read tools return correct data. Event forwarding from Service Bus works. Audit records are being written. Note: UDIP data currency is handled by the WAL/CDC pipeline, not this spoke |
| 3 | ADR | All 10 tools callable. Events round-trip (ADR -> hub -> audit). Audit correlation (request_id) verified in both hub and ADR audit tables |
| 4 | OFS Triage | Read tools return live data. Async submit_case pattern is documented or wrapped. Charge metadata auto-population working through ARC spoke |
| 5 | UDIP (after token delegation is resolved) | OBO token returns correct regional data. Dynamic tool catalog reconciles cleanly. Empty results confirmed to be a scoping issue, not a bug. Verify UDIP's WAL/CDC pipeline is populating data independently — the hub routes queries TO UDIP but does not feed data INTO UDIP |
| 6 | OGC Trial Tool (after auth replacement is done) | Entra ID auth is live. MCP server responds. Litigation data flows from ARC spoke through hub to trial tool |
| 7 | Cross-spoke verification | An AI query that touches two or more spokes returns a correct combined result |

**Do not skip the gate criteria.** Each step depends on the previous one being solid. A spoke that "mostly works" will create debugging headaches later.

---

## Network Connectivity

All spoke connections are HTTPS on port 443. No exceptions.

| Connection | From | To | Auth |
|-----------|------|------|------|
| Hub -> ADR | Hub Container App | `adr-app.azurewebsites.net/mcp` | Hub managed identity -> ADR scope |
| Hub -> Triage | Hub Container App | `ofs-triage.azurewebsites.net/mcp` | Hub managed identity -> Triage scope |
| Hub -> UDIP | Hub Container App | `udip.azurewebsites.net/mcp` | OBO token (carries caller identity) |
| Hub -> OGC Trial Tool | Hub Container App | `ogc-trialtool.azurewebsites.net/mcp` | Hub managed identity -> Trial Tool scope |
| Hub -> ARC Integration API | Hub Container App | `arc-integration.azurewebsites.net/mcp` | Hub managed identity -> ARC scope |
| ADR -> Hub (events) | ADR App Service | Hub Container App internal FQDN | HMAC signature + service principal token |
| ARC Integration -> Hub (events) | ARC Container App | Hub Container App internal FQDN | HMAC signature + managed identity token |
| All -> Entra ID | Hub + all spokes | `login.microsoftonline.com` | OAuth2 |
| All -> Key Vault | Hub + all spokes | `*.vault.azure.net` | Managed identity |

The hub Container App should use internal-only ingress. Spokes reach it via VNet peering or private endpoint. The hub's MCP endpoint (`/mcp`) should be reachable from AI consumers on the internal network but not from the public internet.

All spoke URLs are `.azurewebsites.net` and pass the S-20 domain allowlist already configured in the spoke codebases.

---

## Configuration Reference

Environment variables the hub needs:

| Variable | What It Is | Example |
|----------|-----------|---------|
| `AZURE_TENANT_ID` | Entra ID tenant | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `AZURE_CLIENT_ID` | Hub's app registration client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `KEY_VAULT_URI` | Key Vault for secrets | `https://kv-mcp-hub.vault.azure.net/` |
| `AZURE_STORAGE_CONNECTION_STRING` | For Table Storage and Blob Storage | (connection string from Key Vault) |
| `REDIS_URL` | For tool catalog cache | `rediss://mcp-hub-redis.redis.cache.windows.net:6380` |
| `RECONCILIATION_INTERVAL_SECONDS` | How often to refresh tool catalogs | `300` (5 minutes) |
| `HEALTH_CHECK_INTERVAL_SECONDS` | How often to check spoke health | `60` |
| `HUB_AUDIT_HASH_SALT` | Salt for hashing caller OIDs in audit logs | (from Key Vault, 32+ characters) |
| `MAX_TOOLS_PER_CONTEXT` | Cap on tools returned when no category filter is applied | `15` |

Per-spoke secrets in Key Vault:

| Secret Name | What It Is |
|------------|-----------|
| `MCP-WEBHOOK-SECRET-ADR` | HMAC key for ADR event validation |
| `MCP-WEBHOOK-SECRET-ARC-INTEGRATION` | HMAC key for ARC Integration API events |
| `MCP-WEBHOOK-SECRET-TRIAGE` | HMAC key for Triage events (reserved, not used initially) |

---

## Testing Checklist

Before declaring each phase complete, verify these:

### Hub Infrastructure (Phase 2)
- [ ] `/healthz` returns 200
- [ ] `/readyz` returns 200 (and 503 when Key Vault is unreachable)
- [ ] Spoke registration persists across hub restart
- [ ] HMAC validation rejects events with wrong signature
- [ ] HMAC validation accepts events with correct signature
- [ ] Audit records appear in both Table Storage and Blob archive
- [ ] Blob archive container has WORM policy enforced (try to delete a blob — it should fail)

### ARC Integration API Connection (Phase 2-3)
- [ ] `tools/list` returns 11 ARC tools
- [ ] `arc_get_case` returns correct case detail for a known charge number
- [ ] `arc_get_sbi_combinations` returns the SBI tree (and result is cached)
- [ ] `arc_get_mediation_eligible` returns cases matching the filter criteria
- [ ] Events from ARC Integration API are received, validated, and logged

### ADR Connection (Phase 3)
- [ ] `tools/list` includes all 10 ADR tools alongside ARC tools
- [ ] `adr.list_cases` returns case data
- [ ] `adr.create_case` creates a case (MCP.Write role required)
- [ ] ADR event webhook fires and hub receives it
- [ ] Request ID from hub appears in ADR's audit log (CorrelationID field)

### Triage Connection (Phase 4)
- [ ] `tools/list` includes all 9 Triage tools
- [ ] `ofs-triage.list_cases` returns triage data
- [ ] `ofs-triage.submit_case` returns a tracking ID (not a completed result)
- [ ] Subsequent `ofs-triage.get_case` shows the case status progressing

### UDIP Connection (Phase 5)
- [ ] OBO token delegation is working (test with a user who has region groups)
- [ ] `tools/list` includes UDIP built-in tools plus dynamic query tools
- [ ] `udip.get_metrics` returns the dbt metrics catalog
- [ ] `udip.query_fct_charges` returns data scoped to the caller's region (not empty, not all regions)
- [ ] After a dbt run that adds a new model, the new `query_{model}` tool appears in the next reconciliation cycle

### OGC Trial Tool Connection (Phase 6)
- [ ] Demo auth is gone. Entra ID login works.
- [ ] `tools/list` includes 3 Trial Tool tools
- [ ] `trial.trial_get_case_status` returns case processing status
- [ ] `trial.trial_analyze_case` triggers an AI analysis and returns results with citations

### Cross-Spoke Verification (Phase 7)
- [ ] An AI consumer can call tools from two different spokes in one session
- [ ] Request IDs correlate across hub + spoke audit logs
- [ ] A query like "find charge 370-2026-00123 in both ARC and ADR" returns results from both spokes

---

## Common Mistakes to Avoid

1. **Do not build business logic into the hub.** If you find yourself writing code that understands what a "charge" is or how mediation eligibility works, that logic belongs in a spoke (probably the ARC Integration API).

2. **Do not assume tool catalogs are stable.** UDIP's catalog changes. Test with tools appearing and disappearing.

3. **Do not hardcode spoke URLs.** They come from the registration payload.

4. **Do not use the hub's own managed identity token when calling UDIP.** You will get empty results and think something is broken. Use OBO.

5. **Do not forward Service Bus events without transforming them.** PrEPA's event format is internal to ARC. Transform to the standardized event payload format before forwarding to spokes.

6. **Do not delete anything from the audit archive.** The WORM policy should prevent it, but also do not write code that tries. The application should have no delete permissions on that container.

7. **Do not connect spokes out of sequence.** ARC Integration API first, then ADR, then Triage, then UDIP, then OGC Trial Tool. Each step validates assumptions that the next step depends on.

8. **Do not ignore the UDIP RLS problem.** A connection that returns 200 OK with empty data is worse than a connection that fails. Test with a real user who has region groups. Verify the data is correct, not just present.

9. **Do not confuse UDIP's data ingestion with the hub's event routing.** UDIP gets its data from PrEPA via WAL/CDC (PostgreSQL logical replication → Debezium → Event Hub → UDIP Data Middleware). The hub routes queries TO UDIP and forwards event notifications between spokes. These are separate paths. The hub does not feed data into UDIP.
