# Implementation Prompts

Each prompt below is designed to be given to an engineer (or an AI coding assistant) working in a specific repository. The prompts produce working code plus documentation explaining the changes. Each prompt also asks for a diff-friendly output so the developer who owns the repository can review what changed and why.

---

## Prompt 1: ARC Integration API (New Repository)

**Repository:** NEW -- create `eeoc-arc-integration-api/`
**Owner:** Hub team
**Phase:** 1 (Weeks 1-6)

### Prompt

```
Create a new FastAPI service called "ARC Integration API" that serves as the
bidirectional integration layer between the EEOC ARC backbone (FEPA Gateway and
PrEPA Web Service) and the downstream application ecosystem.

This service has two jobs:
1. PUSH CASE DATA to specific apps: Targeted endpoints for ADR (mediation-eligible
   cases) and Triage (charge metadata at upload time). These are the only read
   endpoints apps call directly. Forward Service Bus event notifications through
   the MCP Hub for inter-app routing.
2. WRITE BACK to ARC: Accept mediation outcomes, triage classifications, documents,
   and action dates from downstream apps and translate them into PrEPA's internal
   API calls.

NOTE: This service does NOT feed bulk data to UDIP. UDIP gets its data via a
WAL/CDC pipeline (PrEPA PostgreSQL → Debezium → Event Hub → UDIP Data Middleware).
See Prompt 9 for the CDC pipeline and Prompt 14 for the Debezium infrastructure.

CONTEXT:
- FEPA Gateway runs at a configurable base URL (env: ARC_GATEWAY_URL) and handles
  document operations and external auth. It uses OAuth2 JWT tokens.
- PrEPA Web Service runs at a configurable base URL (env: ARC_PREPA_URL) and is the
  system of record for discrimination charges. It uses OAuth2 JWT tokens obtained
  from an auth service (env: ARC_AUTH_URL) with client credentials
  (env: ARC_CLIENT_ID, ARC_CLIENT_SECRET).
- This service validates inbound requests with Entra ID M2M bearer tokens
  (env: AZURE_TENANT_ID, AZURE_CLIENT_ID). App roles: ARC.Read and ARC.Write.
- All secrets come from Azure Key Vault (env: KEY_VAULT_URI).

BUILD THE FOLLOWING:

1. Project structure:
   - FastAPI app with Pydantic models, dependency injection, proper error handling
   - Docker container targeting Azure Container Apps
   - Health endpoint at /healthz
   - OpenAPI docs at /docs

2. Authentication module:
   - Inbound: Validate Entra ID M2M JWT tokens. Check for ARC.Read or ARC.Write
     app roles. Use JWKS discovery from login.microsoftonline.com.
   - Outbound: ARC OAuth2 client that acquires tokens from ARC_AUTH_URL using
     client credentials grant. Cache tokens with 60-second pre-expiry buffer.

3. Service Bus event forwarding:
   - Subscribe to PrEPA's Azure Service Bus topics (db-change-topic,
     document-activity-topic)
   - Transform Service Bus messages into MCP Hub's standardized event format
   - Forward to MCP Hub's /api/v1/events endpoint with HMAC-SHA256 signature
   - Use for inter-app notifications (e.g., ADR notified of case status changes)
   - NOT for UDIP data feed (WAL/CDC handles that independently)

4. Case push endpoints (targeted reads for specific apps):
   - GET /arc/v1/mediation/eligible-cases -- mediation-eligible cases for ADR's
     ARCSyncImporter (see below for full payload spec)
   - GET /arc/v1/mediation/cases/{charge_number} -- single case detail for ADR
   - GET /arc/v1/charges/{charge_number}/metadata -- charge metadata for Triage
     auto-population at upload time
   - GET /arc/v1/charges/batch -- up to 100 charge numbers for Triage batch uploads
   - GET /arc/v1/cases/{charge_number}/documents -- document metadata from ECM
   - GET /arc/v1/cases/{charge_number}/documents/{doc_id} -- binary download
   - GET /arc/v1/litigation/cases/{charge_number} -- litigation detail for OGC
   These are the only read endpoints apps call directly. Everything else goes
   through UDIP.

5. Mediation write-back endpoints (ADR pushing results to ARC):
   - GET /arc/v1/mediation/eligible-cases -- query PrEPA for cases that are formalized,
     less than 9 months old, not in enforcement, with assigned ADR staff. Support
     watermark-based filtering (since parameter) and pagination. Return payload matching
     what ADR's ARCSyncImporter expects: arc_case_number, charge_number, case_name,
     mediator_email, mediator_name, office_id, office_name, statutes,
     mediation_eligible_date, staff_assignment_date, sector, participants array.
   - GET /arc/v1/mediation/cases/{charge_number} -- mediation-specific case detail
   - POST /arc/v1/mediation/cases/{charge_number}/status -- update mediation status,
     party replies, ineligibility reasons in PrEPA. Maps to PrEPA PUT
     /v1/cases/{caseId}/mediation (MediationVO). Requires ARC.Write role.
   - PUT /arc/v1/mediation/cases/{charge_number}/staff -- assign or update mediation
     staff. Maps to PrEPA POST /v1/cases/{caseId}/mediation-assignment.
     Body: array of { staff_id, is_adr, assignment_reason }. Requires ARC.Write.
   - POST /arc/v1/mediation/cases/{charge_number}/close -- close a case through
     mediation with full outcome data. This is the most important write-back endpoint.
     Body: { closure_reason (e.g., ADR_SETTLEMENT, ADR_IMPASSE), closure_date,
     is_adr_resolution: true, beneficiaries: [{ type, persons_benefitted,
     benefits: [{ type (monetary or non-monetary code), dollar_amount,
     training_types, compliance_outcome, compliance_date }] }] }.
     Maps to: PrEPA PUT /v1/cases/{caseId}/charge/close/no-review (ClosureVO)
     followed by POST /v1/cases/{caseId}/allegations/benefits (BenefitGroupVO).
     Requires ARC.Write role.
   - POST /arc/v1/mediation/cases/{charge_number}/documents -- upload a document
     to the case in ARC's ECM (e.g., signed settlement agreement, e-signed
     mediation agreement). Multipart form: file + { document_type, file_name }.
     Maps to: PrEPA POST /v1/documents (multipart, ImsDocumentRequest).
     Requires ARC.Write role.
   - POST /arc/v1/mediation/cases/{charge_number}/events -- log action dates
     and milestones back to ARC's case event log. Body: array of
     { event_code, event_date (yyyy-MM-dd), comments, attributes: [{name, value}] }.
     Maps to: PrEPA POST /v1/cases/{caseId}/events (List<EventVO>).
     Use for: mediation started, session held, agreement signed, settlement finalized.
     Requires ARC.Write role.
   - POST /arc/v1/mediation/cases/{charge_number}/signed-agreements -- trigger
     generation of signed Agreement to Mediate and Confidentiality Agreement
     documents in ARC. Body: { person_type, sequence_id }.
     Maps to: PrEPA POST /v1/cases/{caseId}/mediation/signed/agreements.
     Requires ARC.Write role.

6. Triage write-back endpoints (Triage pushing results to ARC):
   - GET /arc/v1/charges/{charge_number}/metadata -- return charge_number,
     respondent_name, basis_codes[], issue_codes[], statute_codes[], office_code,
     filing_date, status
   - GET /arc/v1/charges/batch -- accept up to 100 charge numbers, return array
     of metadata objects (parallelize PrEPA calls)
   - POST /arc/v1/charges/{charge_number}/classification -- write triage
     classification results back to ARC's event log so investigators can see
     them. Body: { rank (A/B/C), merit_score, summary, classified_date }.
     Maps to: PrEPA POST /v1/cases/{caseId}/events with a triage-specific
     event code and attributes for rank, score, and summary.
     Requires ARC.Write role.
   - POST /arc/v1/charges/{charge_number}/events -- log triage actions
     (correction, re-classification) as case events.
     Body: array of { event_code, event_date, comments, attributes }.
     Maps to: PrEPA POST /v1/cases/{caseId}/events. Requires ARC.Write.

7. Reference data endpoints (cached 24h, also ingested by UDIP feed):
   - GET /arc/v1/reference/sbi-combinations -- from FEPA Gateway /fepagateway/v1/sbi-combo
   - GET /arc/v1/reference/offices -- from PrEPA /v1/offices
   - GET /arc/v1/reference/document-types -- from FEPA Gateway /fepagateway/v1/documents/type
   - GET /arc/v1/reference/statuses -- from PrEPA /v1/lookup-data

8. MCP spoke registration:
   - POST /mcp endpoint implementing JSON-RPC 2.0 (protocol version 2025-03-26)
   - Expose all endpoints above as MCP tools with proper input schemas
   - Read tools: arc_search_cases, arc_get_case, arc_get_case_allegations,
     arc_get_case_staff, arc_get_case_documents, arc_get_mediation_eligible,
     arc_get_charge_metadata, arc_get_litigation_case,
     arc_get_sbi_combinations, arc_get_offices
   - Write tools: arc_update_mediation_status, arc_assign_mediation_staff,
     arc_close_mediation_case, arc_upload_case_document, arc_log_case_events,
     arc_generate_signed_agreements, arc_post_triage_classification,
     arc_log_triage_events

10. Caching:
    - Redis-based cache (env: REDIS_URL)
    - Reference data: 24h TTL
    - Case list queries: 5min TTL
    - Individual case detail: 2min TTL
    - Document metadata: 10min TTL

11. Input validation:
    - Charge numbers: regex ^[A-Z0-9\-]{3,25}$
    - SSRF prevention: block private/loopback IPs on outbound calls
    - Rate limiting: per-client, per-minute

12. Logging:
    - Structured JSON logging
    - Hash user identifiers (never log PII)
    - Correlation ID propagation (X-Request-ID header)

13. Tests:
    - Unit tests for auth, caching, and data mapping
    - Integration test stubs with httpx mock for PrEPA/Gateway calls

14. Documentation:
    - README explaining what the service does, how to configure it, and how it maps
      to ARC internals. Written as a developer would write it -- no preamble, no filler,
      just what someone needs to know to run and maintain the service.

15. Provide a complete file listing with contents so the developer can review every file.
```

---

## Prompt 2: ADR Audit Correlation Update

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 3 (Weeks 5-7)

### Prompt

```
In the ADR Mediation Platform codebase, make these changes to support MCP hub
audit correlation:

1. In shared_code/mcp_protocol/ and adr_webapp/mcp_server.py:
   - Accept an X-Request-ID header on all /mcp and /api/v1/* requests
   - If present, use it as the correlation ID instead of generating a new one
   - Echo it back in responses as X-Request-ID
   - Pass it through to AIAuditLogger as the CorrelationID field

2. In shared_code/ai_audit_logger.py:
   - Accept an optional request_id parameter
   - If provided, store it as both CorrelationID (existing field) and RequestID (new field)
   - This maintains backward compatibility while adding hub correlation

3. In adr_webapp/mcp_event_dispatcher.py:
   - Include request_id in outbound event payloads when available

4. Verify the retention tag is already FOIA_7_YEAR (it should be based on existing code).

Write a short document (CHANGES.md) explaining what changed and why, written
for the developer who maintains this repo. Include a unified diff of all changes
so they can review exactly what was modified.

Do not change any other behavior. Do not refactor surrounding code. Do not add
comments to unchanged lines.
```

---

## Prompt 3: OFS Triage Audit Correlation Update

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 4 (Weeks 7-8)

### Prompt

```
In the OFS Triage System codebase, make these changes to support MCP hub
audit correlation and standardize audit fields:

1. In mcp_server.py and blueprints/api_mcp.py:
   - Accept X-Request-ID header on all /mcp and /api/v1/* requests
   - Echo it back in responses
   - Pass it through to all tool handler functions

2. In mcp_tools.py:
   - Accept request_id as an optional parameter in each tool handler
   - Pass it to the audit logger when logging tool invocations

3. In the AI audit logger (find the audit logging module):
   - Add a RequestID field to aigenerationaudit table writes
   - Add a CallerOIDHash field: SHA-256 hash of the caller's object ID from
     the bearer token, using the existing STATS-HASH-SALT from Key Vault
   - Change RetentionPolicy from "NARA_7_YEAR" to "FOIA_7_YEAR" for consistency
     with the hub and ADR

4. In the blob archive writes (ai-generation-archive container):
   - Include request_id and caller_oid_hash in the JSON payload

Write a CHANGES.md explaining the modifications for the repository owner.
Include a unified diff. Do not touch anything outside the audit correlation path.
```

---

## Prompt 4: UDIP Audit Correlation and OBO Preparation

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 5 (Weeks 8-10)

### Prompt

```
In the UDIP Analytics Platform codebase, make these changes:

PART 1: Audit correlation (required for hub integration)

1. In ai-assistant/app/mcp_server.py and ai-assistant/app/mcp_api.py:
   - Accept X-Request-ID header on /mcp and /api/v1/mcp/* requests
   - Echo it back in responses
   - Pass through to query execution and audit logging

2. In the audit logger (ai-assistant/app/audit.py or shared_code/ai_audit_logger.py):
   - Add RequestID field to audit table writes
   - Align RetentionPolicy to "FOIA_7_YEAR"
   - Include request_id in blob archive JSON

PART 2: OBO token delegation support (required for RLS to work through the hub)

3. In ai-assistant/app/mcp_api.py (the M2M bearer token validation):
   - Add support for extracting region claims from OBO tokens
   - When the bearer token contains a "regions" or region-related claim
     (from the original caller's token via OBO flow), extract it and use it
     for RLS session context instead of requiring the caller to be in a
     UDIP-Data-Region-* group
   - Preserve the existing group-based region resolution as a fallback
     when region claims are not present in the token

4. In ai-assistant/app/data_access.py:
   - When setting PostgreSQL session context (set_pg_session_context),
     accept region values from either the OBO token claims or the
     existing group membership lookup
   - Log which source was used (obo_token vs group_membership) for debugging

5. Add a configuration flag: OBO_REGION_CLAIMS_ENABLED (default: false)
   When false, the existing behavior is unchanged. When true, OBO token
   region claims take precedence over group membership lookup.

Write a CHANGES.md explaining both parts. Include a unified diff.
Keep the existing auth flow working as-is when OBO is not enabled.
```

---

## Prompt 5: OGC Trial Tool Production Auth and MCP Server

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 6 (Weeks 10-12)

### Prompt

```
The OGC Trial Tool currently uses demo session-based authentication
(GET /demo_login?role=attorney). This must be replaced with Entra ID
Government OIDC before the tool can integrate with the MCP hub.

Additionally, the trial tool needs an MCP server endpoint so it can
register as a spoke with the hub.

PART 1: Replace demo auth with Entra ID Government

1. In trial_tool_webapp/trial_tool_app.py:
   - Remove the /demo_login route entirely
   - Add MSAL Confidential Client authentication using Azure AD Government
     (login.microsoftonline.us)
   - Configuration via environment variables:
     AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET
   - OIDC callback at /auth/callback
   - Session stored in Flask server-side session (Redis if REDIS_URL is set,
     filesystem fallback for local dev)
   - Role determination from Entra ID group membership:
     ATTORNEY_GROUP_ID -> attorney role
     ADMIN_GROUP_ID -> admin role
   - Keep all existing @login_required decorators working
   - Keep CSRF protection (Flask-WTF) working

2. Add /auth/login, /auth/callback, /auth/logout routes

3. Update templates/login.html to redirect to /auth/login instead of
   showing demo login buttons

PART 2: MCP server endpoint

4. Create a new file trial_tool_webapp/mcp_server.py:
   - POST /mcp endpoint implementing JSON-RPC 2.0 (protocol version 2025-03-26)
   - Validate Entra ID M2M bearer tokens with app roles: MCP.Read, MCP.Write
   - Feature-gated: MCP_ENABLED and MCP_SERVER_EXPOSE env vars (both default false)

5. Expose three MCP tools:
   - trial_get_case_status (MCP.Read): returns case processing status from
     the casedata table. Input: case_name. Output: status, details, witnesses,
     assigned attorney, document count.
   - trial_analyze_case (MCP.Write): triggers AI analysis on an indexed case.
     Input: case_name, feature_name (one of: q_and_a, timeline, summary,
     outline_builder, impeachment_kit, comparator_analyzer, issue_matrix,
     damages_snapshot, mil_helper), prompt, options. Output: analysis result
     with citations. Calls the existing full_context_llm module.
   - trial_list_cases (MCP.Read): returns all cases from the casedata table
     with their status.

6. Add audit correlation:
   - Accept X-Request-ID header, echo in responses
   - Add RequestID field to aigenerationaudit writes
   - Hash user email with SHA-256 before logging (CallerOIDHash field)
   - Set RetentionPolicy to FOIA_7_YEAR

PART 3: Documentation

7. Write a CHANGES.md explaining:
   - What was removed (demo auth)
   - What was added (Entra ID OIDC, MCP server)
   - How to configure it (environment variables)
   - What the developer needs to set up in Azure portal (app registration,
     group assignments, app roles)

8. Include a unified diff of all changes.

IMPORTANT: The existing AI analysis pipeline (full_context_llm.py),
document indexer (DocumentIndexer function), and audit logger
(shared_code/ai_audit_logger.py) must not be modified beyond adding
the request_id and caller_oid_hash fields. Do not refactor, reorganize,
or "improve" existing working code.
```

---

## Prompt 6: MCP Hub — Azure Infrastructure Setup + Tool Aggregator Function

**Repository:** NEW -- create `eeoc-mcp-hub-functions/` (small repo, not a full service)
**Owner:** Hub team
**Phase:** 2 (Weeks 3-6)
**Guide:** See `Azure_MCP_Hub_Setup_Guide.md` for portal-based configuration steps

### Overview

The MCP Hub is NOT a custom-built service. It is assembled from Azure managed
services configured through the Azure Portal:

- **Azure API Management** — MCP routing, auth validation, tool call proxying
- **Azure Event Grid** — inter-spoke event routing
- **Azure Key Vault** — secrets (HMAC keys, hash salt, credentials)
- **Azure Table Storage + Blob (WORM)** — audit logging
- **Entra ID** — app registrations, M2M auth, OBO for UDIP

The only custom code is a lightweight Azure Function for tool catalog
aggregation (UDIP's dynamic catalog requires periodic reconciliation).

See `Azure_MCP_Hub_Setup_Guide.md` for complete portal-based setup
instructions covering Steps 1-12 (resource group, VNet, Key Vault, storage,
Entra app registrations, APIM configuration, OBO for UDIP, Event Grid,
health monitoring, audit logging, and connection sequence).

### Prompt (for the aggregator function only)

```
Create a lightweight Azure Function app that aggregates MCP tool catalogs
from all registered spokes and returns a merged catalog. This is the only
custom code needed for the MCP Hub — everything else is configured in
Azure Portal (see Azure_MCP_Hub_Setup_Guide.md).

CONTEXT:
- Azure API Management handles routing, auth, and proxying
- Each spoke has a POST /mcp endpoint with tools/list capability
- UDIP's tool catalog changes whenever dbt runs (dynamic)
- APIM routes tools/call by prefix (adr.*, ofs-triage.*, udip.*, etc.)
- APIM needs a backend to handle tools/list aggregation

BUILD THE FOLLOWING:

1. Project structure:
   - Azure Function App (Python, v2 programming model)
   - Timer trigger: refresh catalog every 5 minutes
   - HTTP trigger: return merged catalog on request
   - Dockerfile for Azure Container Apps deployment

2. Timer trigger — CatalogRefresher (every 5 minutes):
   - Read spoke registry from Azure Table Storage (table: "mcpspokes")
   - For each registered spoke:
     a. Acquire Entra M2M token for spoke's auth scope
     b. Call POST /mcp with {"jsonrpc":"2.0","method":"tools/list","id":1}
     c. Parse tool list from response
     d. Prefix each tool name with spoke name (adr.list_cases, etc.)
     e. Tag each tool with spoke's capability categories
   - Merge all tool lists into single catalog
   - Cache merged catalog in Redis (key: "mcp:tool_catalog", TTL: 10 min)
   - Handle spokes that are unreachable (skip, log warning, use stale cache)
   - Handle UDIP tools appearing/disappearing between refreshes

3. HTTP trigger — GetToolCatalog:
   - GET /api/tools — return merged catalog from Redis cache
   - Accept optional query parameter: categories (comma-separated)
   - Filter tools by capability category if specified
   - Cap returned tools at MAX_TOOLS_PER_CONTEXT (default: 15)
   - Called by APIM backend "hub-aggregator" when routing tools/list

4. Spoke registry table schema (Azure Table Storage: "mcpspokes"):
   PartitionKey: "spoke"
   RowKey: spoke name (adr, ofs-triage, udip, ogc-trial-tool, arc-integration)
   Fields: url, capability_categories (comma-separated), auth_scope,
     protocol_version, health_endpoint, timeout_seconds, last_healthy_at,
     last_catalog_refresh_at, tool_count, is_healthy

5. Health checking:
   - During catalog refresh, also call each spoke's health endpoint
   - Update is_healthy and last_healthy_at in registry
   - Exclude unhealthy spokes from the merged catalog
   - Log health transitions (healthy→unhealthy, unhealthy→healthy)

6. Configuration:
   - AZURE_STORAGE_CONNECTION_STRING (spoke registry + audit)
   - REDIS_URL (tool catalog cache)
   - KEY_VAULT_URI (spoke auth credentials)
   - RECONCILIATION_INTERVAL_SECONDS (default: 300)
   - MAX_TOOLS_PER_CONTEXT (default: 15)

7. Audit logging:
   - Log every catalog refresh: spokes contacted, tools found, errors
   - Log to Azure Table Storage "hubauditlog" table
   - Include: refresh_id, spokes_healthy, spokes_unhealthy, total_tools,
     duration_seconds, timestamp

8. Populate the spoke registry:
   - Provide a CLI script or Azure Function HTTP endpoint to register spokes:
     POST /api/spokes with body: {name, url, categories, auth_scope, ...}
   - Also: GET /api/spokes (list all), DELETE /api/spokes/{name}
   - These are called once per spoke during initial setup

Write a CHANGES.md and include all files with complete listing.
```

---

## Prompt 7: ADR ARCSyncImporter Migration

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 3 (Week 7)

### Prompt

```
In the ADR Mediation Platform, update the ARCSyncImporter Azure Function to
point at the new ARC Integration API instead of the current ARC_API_BASE_URL.

CHANGES NEEDED:

1. In adr_functionapp/ARCSyncImporter/__init__.py:
   - The function currently calls ARC_API_BASE_URL + "/api/mediation/cases"
     with a "since" watermark parameter
   - Change it to call ARC_INTEGRATION_API_URL + "/arc/v1/mediation/eligible-cases"
     with the same "since" watermark parameter and pagination support
   - The response payload format should be the same (the ARC Integration API
     was designed to return the payload ARCSyncImporter expects)
   - Add support for paginated responses: follow next_page links until exhausted

2. In adr_functionapp/shared/arc_client.py (or adr_webapp/arc_client.py):
   - Add a new auth method: "managed_identity" that uses DefaultAzureCredential
     to acquire an Entra ID token for the ARC Integration API's app registration
     (scope from env: ARC_INTEGRATION_API_SCOPE)
   - Keep existing auth methods (api_key, bearer, basic) working for backward
     compatibility

3. Configuration changes:
   - New env var: ARC_INTEGRATION_API_URL (the base URL of the integration API)
   - New env var: ARC_INTEGRATION_API_SCOPE (the Entra ID scope, e.g.,
     api://<client-id>/.default)
   - New env var: ARC_AUTH_METHOD should accept "managed_identity" as a value
   - Old ARC_API_BASE_URL remains functional if ARC_INTEGRATION_API_URL is not set
     (graceful fallback)

4. In adr_webapp/routes/mediator.py (the arc_lookup route):
   - Update the manual ARC lookup to also use the integration API when configured
   - Same fallback behavior: use old endpoint if new one is not configured

Write a CHANGES.md and include a unified diff. Do not change anything else
in the function app or webapp.
```

---

## Prompt 8: OFS Triage Charge Metadata Auto-Population

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 4 (Week 8)

### Prompt

```
Add optional charge metadata auto-population from the ARC Integration API
to the OFS Triage System.

Currently, when analysts upload a case for triage, they manually enter
the charge number, respondent name, basis codes, and issue codes. With
this change, the system can optionally look up this metadata from ARC
when a charge number is provided.

CHANGES:

1. Create a new module triage_webapp/arc_lookup.py:
   - Function: lookup_charge_metadata(charge_number) -> dict or None
   - Calls ARC_INTEGRATION_API_URL + "/arc/v1/charges/{charge_number}/metadata"
   - Auth: Entra ID managed identity token (DefaultAzureCredential)
   - Scope: ARC_INTEGRATION_API_SCOPE env var
   - Returns: { charge_number, respondent_name, basis_codes[], issue_codes[],
     statute_codes[], office_code, filing_date, status } or None on failure
   - Timeout: 10 seconds. Failure is non-fatal (return None, log warning)

2. In blueprints/cases.py (upload_case route):
   - After the charge number is extracted from the upload form, if
     ARC_LOOKUP_ENABLED is true, call lookup_charge_metadata()
   - If metadata is returned, use it to populate the casetriage table
     fields (respondent, basis_codes, issue_codes) instead of requiring
     manual entry
   - If lookup fails or returns None, fall through to existing behavior
     (manual entry fields used)

3. In blueprints/api_mcp.py (submit_case and submit_batch endpoints):
   - Same logic: if ARC_LOOKUP_ENABLED and a charge_number is provided,
     attempt auto-population before queueing for processing
   - Non-fatal: if lookup fails, proceed with whatever metadata was
     provided in the request body

4. Configuration:
   - ARC_LOOKUP_ENABLED (default: false)
   - ARC_INTEGRATION_API_URL
   - ARC_INTEGRATION_API_SCOPE

5. In mcp_tools.py:
   - Update the submit_case tool description to note that when ARC lookup
     is enabled, basis_codes and issue_codes are auto-populated from ARC
     if a valid charge number is provided

Write a CHANGES.md and include a unified diff. This is additive functionality
behind a feature flag; existing behavior must be preserved when the flag is off.
```

---

## Summary: Which Prompt Goes Where

| Prompt | Repository | Creates/Modifies | Phase |
|--------|-----------|-----------------|-------|
| 1 | NEW: `eeoc-arc-integration-api/` | Creates service (write-back + targeted reads, no UDIP feed) | Phase 1 | DONE 2026-04-03 |
| 2 | `eeoc-ofs-adr/` | Modifies audit correlation (3-4 files) | Phase 4 | DONE 2026-04-03 |
| 3 | `eeoc-ofs-triage/` | Modifies audit correlation (4-5 files) | Phase 5 | DONE 2026-04-03 |
| 4 | `eeoc-data-analytics-and-dashboard/` | Modifies audit + adds OBO support (4-5 files) | Phase 3 | DONE 2026-04-03 |
| 5 | `eeoc-ogc-trialtool/` | Replaces auth, adds MCP server (3-4 files) | Phase 6 | DONE 2026-04-03 |
| 6 | NEW: `eeoc-mcp-hub-functions/` | Tool catalog aggregator function (hub is Azure APIM + portal config, see Azure_MCP_Hub_Setup_Guide.md) | Phase 2 | DONE 2026-04-03 |
| 7 | `eeoc-ofs-adr/` | Modifies ARCSyncImporter + arc_client (3-4 files) | Phase 4 | DONE 2026-04-03 |
| 8 | `eeoc-ofs-triage/` | Adds ARC lookup module + wires into upload (3-4 files) | Phase 5 | DONE 2026-04-03 |
| 9 | `eeoc-data-analytics-and-dashboard/` | UDIP WAL/CDC driver + reconciliation engine + data lifecycle schema + new ADR/Triage tables | Phase 1 | DONE 2026-04-03 |
| 10 | `eeoc-ofs-adr/` | ADR → UDIP analytics push (new Azure Function) | Phase 4 | DONE 2026-04-03 |
| 11 | `eeoc-ofs-triage/` | Triage → UDIP analytics push (new Azure Function) | Phase 5 | DONE 2026-04-03 |
| 12 | `eeoc-ogc-trialtool/` | CI/CD pipeline (GitHub Actions) | Phase 6 | DONE 2026-04-03 |
| 13 | NEW repos | CI/CD pipelines for ARC Integration API + MCP Hub aggregator function | Phase 1-2 | DONE 2026-04-03 |
| 14 | `eeoc-data-analytics-and-dashboard/` | Debezium CDC pipeline from PrEPA to Event Hub (ran with UDIP) | Phase 1 | DONE 2026-04-03 |
| 15 | `eeoc-data-analytics-and-dashboard/` | Data lifecycle automation (state machine, access tracking, purge, FOIA holds) | Phase 1-2 | DONE 2026-04-03 |
| 16 | `eeoc-data-analytics-and-dashboard/` | Schema completion: 6 missing tables, RLS policies, vw_charges, dbt models | Phase 1 | DONE 2026-04-03 |
| 17 | `eeoc-data-analytics-and-dashboard/` | Middleware engine extensions: lookup_table, UUID_V5, fiscal_year, PII patterns | Phase 1 | DONE 2026-04-03 |
| 18 | `eeoc-ofs-triage/` | Security hardening: Key Vault, OData, deps, OpenAI managed identity, session store | Phase 2 | DONE 2026-04-03 |
| 19 | `eeoc-ofs-adr/` | Security hardening: CSP, MIME validation, input validation, session config | Phase 2 | DONE 2026-04-03 |
| 20 | `eeoc-ofs-triage/` | AI/LLM hardening: prompt injection, drift circuit breaker, scan gate, rate limits | Phase 3 | DONE 2026-04-03 |
| 21 | `eeoc-ofs-adr/` | Horizontal scaling: Redis caches, distributed locking, streaming uploads, repartitioning | Phase 2 | DONE 2026-04-03 |
| 22 | `eeoc-ofs-triage/` | Horizontal scaling: Redis sessions, distributed locking, OpenAI retry, repartitioning, ZIP streaming | Phase 2 | DONE 2026-04-03 |
| 23 | `eeoc-data-analytics-and-dashboard/` | Horizontal scaling: PgBouncer, connection pool, thread safety, async embeddings, streaming queries | Phase 1-2 | DONE 2026-04-03 |
| 24 | `eeoc-data-analytics-and-dashboard/` | AI Assistant: persistent conversation history, multi-turn context, query refinement loop | Phase 2 | DONE 2026-04-03 |
| 25 | `eeoc-data-analytics-and-dashboard/` | AI Assistant: interactive visualization generation (charts, tables, exports) | Phase 2 | DONE 2026-04-03 |
| 26 | `eeoc-data-analytics-and-dashboard/` | AI Assistant: dynamic dashboard creation and Superset integration | Phase 3 | DONE 2026-04-03 |
| 27 | ALL repos | Unit tests for 14 uncovered new modules (run per repo) | Parallel | DONE 2026-04-05 |
| 28 | `eeoc-ofs-adr/` | Production deployment: K8s manifests, HPA, Front Door WAF, Table Storage partitioning, public-facing scaling | Phase 2 | DONE 2026-04-05 |
| 29 | `eeoc-ofs-triage/` | Production deployment: K8s manifests, HPA, function app scaling | Phase 2 | DONE 2026-04-05 |
| 30 | `eeoc-arc-integration-api/` | Production deployment: K8s manifests, HPA, configmaps | Phase 1 | DONE 2026-04-05 |
| 31 | `eeoc-ofs-triage/` | Scaling fix-up: wire OpenAI retry, repartition tables, stream ZIP, gate rate limit fallback | Phase 2 | DONE 2026-04-05 |
| 32 | `eeoc-ofs-adr/` | Graceful degradation: standalone operation with all integrations optional, feature flags, health reporting | Phase 2 | DONE 2026-04-05 |
| 33 | `eeoc-data-analytics-and-dashboard/` | Read replica routing: primary for writes, replica for reads, PgBouncer dual-backend | Phase 2 | DONE 2026-04-05 |
| 34 | `eeoc-data-analytics-and-dashboard/` | AI Assistant fix-up: get_messages→get_history, tiktoken context window, error refinement loop | Phase 2 | DONE 2026-04-05 |
| 35 | `eeoc-ofs-triage/` | Move MSAL token cache from session cookie to Redis-keyed storage | Phase 2 | DONE 2026-04-05 |
| 36 | `eeoc-data-analytics-and-dashboard/` | Schema design: ADR + Triage operational tables in UDIP PostgreSQL (long-term data consolidation) | Phase 3 | DONE 2026-04-05 |
| 37 | `eeoc-ofs-adr/` | Data layer migration: Azure Table Storage → PostgreSQL via SQLAlchemy (phased, behind feature flag) | Phase 4 | DONE 2026-04-05 |
| 38 | `eeoc-ofs-triage/` | Data layer migration: Azure Table Storage → PostgreSQL via SQLAlchemy (phased, behind feature flag) | Phase 4 | DONE 2026-04-05 |
| 39 | `eeoc-data-analytics-and-dashboard/` | FOIA/NARA: conversation history 7-year retention, litigation hold, case lifecycle linking | Phase 2 | PENDING |
| 40 | ALL repos | FOIA export API: /api/foia-export endpoint with ZIP + chain-of-custody audit | Phase 2 | PENDING |
| 41 | ALL repos | Litigation hold mechanism: centralized hold table, FinalizeDisposal integration | Phase 2 | PENDING |
| 42 | `eeoc-arc-integration-api/` | M-21-31/FedRAMP: HMAC audit logging, retention policy, audit table, structured compliance logging | Phase 1 | PENDING |
| 43 | `eeoc-mcp-hub-functions/` | M-21-31/FedRAMP: HMAC audit logging, PII hashing, correlation IDs, retention policy | Phase 2 | PENDING |
| 44 | `eeoc-ogc-trialtool/` | M-21-31/FedRAMP: Structured JSON logging, HMAC audit, correlation IDs, PII hashing, retention | Phase 2 | PENDING |
| 45 | Infrastructure | M-21-31 EL3: Azure Sentinel, NSG flow logs, DNS Analytics, Network Watcher, UBA, SOAR playbooks | Phase 3 | PENDING |
| 46 | `eeoc-ogc-trialtool/` | License + dependency remediation: remove poppler/GPL, replace python-jose, pin all deps, document Ollama model licenses | Phase 2 | PENDING |
| 47 | ALL repos | Supply chain hardening: container image scanning (Trivy), Dependabot/Renovate, system dep SBOM, code signing | Phase 2 | PENDING |
| 48 | `eeoc-ogc-trialtool/` | Replace Ollama with FoundryModelProvider (default: Azure OpenAI GA, Foundry optional), remove all Ollama references | Phase 2 | PENDING |
| 49 | `eeoc-ofs-triage/` | Adopt FoundryModelProvider pattern (default: Azure OpenAI GA, Foundry optional for future), managed identity, endpoint validation | Phase 2 | PENDING |
| 50 | Workspace root | Complete platform deployment guide (zero-assumption, newbie-friendly, portal step-by-step) | Phase 1 | PENDING |
| 51 | Workspace root | Azure provisioning script (provision_eeoc_ai_platform.sh) with pre/post checklists | Phase 1 | PENDING |
| 52 | `eeoc-data-analytics-and-dashboard/` | Auto-schema detection: new tables auto-created, labeled, documented, dbt models generated, AI-discoverable | Phase 3 | PENDING |
| 53 | `eeoc-ofs-triage/` | Triage multi-tenancy: OFS/OFP sector field, office hierarchy, district scoping, 3-layer access control, 508 compliance | Phase 3 | PENDING |
| 54 | `eeoc-ofs-triage/` | OFP intake pipeline: CDC case detection, configurable delay, OFP system prompt, separate scoring, document refresh notification | Phase 3 | PENDING |
| 55 | `eeoc-ofs-triage/` + `eeoc-arc-integration-api/` | ARC write-back: classification routing, NRTS trigger, configurable field mapping, approval workflow | Phase 3 | PENDING |
| 56 | `eeoc-ofs-triage/` | OFS Rank C decision letter: AI-assisted generation, DOCX template, attorney review workflow (disabled by default) | Phase 3 | PENDING |
| 57 | `eeoc-ofs-triage/` | RAG library expansion: SEP, Compliance Manual, Commission Guidance categories, sector filtering for OFS/OFP | Phase 3 | PENDING |
| 58 | `eeoc-ofs-triage/` | OFS submission window: configurable timer, extension handling, CDC monitoring, manual early review override | Phase 3 | PENDING |
| 59 | `eeoc-mcp-hub-functions/` | REMEDIATION: Full M-21-31 compliance logging (P43 was not implemented) + protocol version fix (P6) | Phase 2 | PENDING |
| 60 | `eeoc-ogc-trialtool/` | REMEDIATION: Remove pdf2image/poppler, replace python-jose→PyJWT, pin deps, MODEL_LICENSES.md, build-and-test.yml | Phase 2 | PENDING |
| 61 | `eeoc-ofs-triage/` | REMEDIATION: Reconstruct OFPCaseMonitor/__init__.py (P54 source file missing) | Phase 3 | PENDING |
| 62 | Workspace root | REMEDIATION: Create Azure_M2131_EL3_Infrastructure_Guide.md (P45 was not implemented) | Phase 3 | PENDING |
| 63 | Multiple repos | REMEDIATION: HMAC-SHA256 upgrade for Triage+UDIP audit loggers, OGC 508 CSS, retention string standardization, ADR MCP protocol version | Phase 2 | PENDING |
| 64 | UDIP + Triage | WIRING FIX: Connect conversation lifecycle to case closure/holds (UDIP), wire session population into login flow (Triage), fix ScheduledDisposal (Triage) | Phase 2 | PENDING |
| 65 | ALL repos | FINAL HARDENING: 7 missing test suites, UDIP PDBs, HMAC key out of ConfigMaps, SQL roles, search function ordering, startup probes, doc cross-references | Phase 2 | PENDING |
| 66 | `eeoc-data-analytics-and-dashboard/` | Debezium schema expansion: `schema.include.list` → `"public,fed_hearings"` + PII column exclusions + runbook | Phase 4a | PENDING |
| 67 | `eeoc-data-analytics-and-dashboard/` | Replica schema DDL: 24 new tables (13 fed_hearings + 11 public gaps) | Phase 4a | PENDING |
| 68 | `eeoc-data-analytics-and-dashboard/` | Analytics target tables: 17 new analytics schema tables + lifecycle triggers + indexes | Phase 4a | PENDING |
| 69 | `eeoc-data-analytics-and-dashboard/` | YAML mappings for 13 federal hearings CDC entities (fedhearings_*.yaml) | Phase 4a | PENDING |
| 70 | `eeoc-data-analytics-and-dashboard/` | YAML mappings for 12 public schema gap entities (prepa_conciliation, benefits, race, etc.) | Phase 4a | PENDING |
| 71 | `eeoc-arc-integration-api/` | Service Bus subscriptions: `user-management-topic` + `federal-hearing-topic` + handlers | Phase 4a | PENDING |
| 72 | `eeoc-arc-integration-api/` | FederalHearingsClient: 9 methods, Pydantic models, feature flag | Phase 4b | PENDING |
| 73 | `eeoc-arc-integration-api/` | EmployerClient (5 methods) + PrepaClient enforcement/conciliation/systemic additions (17 methods) | Phase 4b | PENDING |
| 74 | `eeoc-arc-integration-api/` | New routers: federal.py, enforcement.py, systemic.py, employer.py | Phase 4b | PENDING |
| 75 | `eeoc-arc-integration-api/` | MCP tools: 11 new tools (9 read + 2 write), dispatch handlers | Phase 4b | PENDING |
| 76 | `eeoc-arc-integration-api/` | Feature flags consolidation: 7 flags, 2 URLs, 4 TTLs, helper module | Phase 4b | PENDING |
| 77 | `eeoc-arc-integration-api/` | Unit tests for all Phase 4b additions (9 test files) | Phase 4b | PENDING |
| 78 | `eeoc-ogc-trialtool/` | Enforcement + court hearing data display, CRUD routes, MCP tools | Phase 5 | PENDING |
| 79 | `eeoc-ofs-triage/` | Federal sector data path: hearing metadata lookup, enriched classification context | Phase 5 | PENDING |
| 80 | `eeoc-ofs-adr/` | Conciliation status display + case notes access (read-only additions) | Phase 5 | PENDING |
| 81 | `eeoc-data-analytics-and-dashboard/` | Analytics views + AI assistant tools for federal hearings and enforcement | Phase 5 | PENDING |
| 82 | `eeoc-ofs-adr/` + `eeoc-ofs-triage/` | Unified staff portal: blueprint extraction, namespaced routes, shared navigation | Phase 6 | PENDING |
| 83 | `eeoc-ofs-adr/` | Unified staff portal: shared auth, role resolver, session manager, decorators | Phase 6 | PENDING |
| 84 | `eeoc-ofs-adr/` | Unified staff portal: Dockerfile, K8s manifests, HPA, CI/CD pipeline | Phase 6 | PENDING |
| 85 | `eeoc-ogc-trialtool/` | OGC case registry: dual case ID (internal + ARC), RBAC, organizational hierarchy, case dashboard | Phase 7 | PENDING |
| 86 | `eeoc-ogc-trialtool/` | Transcript parser: page:line preservation from PDF, Document Intelligence OCR, case document ingestion + categorization | Phase 7 | PENDING |
| 87 | `eeoc-ogc-trialtool/` | Case-scoped AI Assistant: per-case conversation store, dual-corpus RAG, Bluebook citation engine, case chat UI | Phase 7 | PENDING |
| 88 | `eeoc-ogc-trialtool/` | Case lifecycle: closure → retention → disposal, FOIA export, ARC status pull (read-only), litigation hold integration | Phase 7 | PENDING |
| 89 | `eeoc-ogc-trialtool/` | Word Add-in: secure API layer + SSO + manifest + security docs (foundation — full UI is future phase) | Phase 8 | PENDING |
| 90 | ADR + Triage + Trial Tool + UDIP | PWA support: manifest.json, service worker, generated icons, taskbar/desktop install | Phase 7 | PENDING |
| 91 | `eeoc-ofs-adr/` | Production deployment docs: Entra ID app registration guide, Login.gov prod setup, Key Vault secret generation, DNS/TLS, env var dependencies, health check script, first-run setup guide | Phase 9 | PENDING |
| 92 | `eeoc-ofs-adr/` | Audit log viewer (search/filter/export), per-case activity timeline, bulk security audit export for compliance reviews | Phase 9 | PENDING |
| 93 | All repos | Python 3.13 upgrade: psycopg2-binary bump, Dockerfile base image, CI python-version, config files | Phase 9 | PENDING |

### For the developer reviewing diffs:

- **Prompts 2, 3, 4, 7, 8, 9, 10, 11, 15** are modifications to existing repos. Each asks for a unified diff and a CHANGES.md so the repository owner can see exactly what changed, why, and what configuration is needed.
- **Prompts 1, 6, 12, 13, 14** create new repositories, infrastructure, or CI/CD pipelines. Each asks for a complete file listing so all code can be reviewed before merging.
- **Prompt 5** is the largest single-repo change (auth replacement + MCP server), but it is isolated to the trial tool and does not affect any shared infrastructure.
- **Prompt 9** is the largest UDIP change: CDC driver, reconciliation engine, data lifecycle schema (partitioning, metadata columns, lifecycle state machine, access tracking, FOIA/NARA holds, monitoring views), and new ADR/Triage analytics tables.
- **Prompt 15** builds the automation that operates on Prompt 9's lifecycle schema: state transitions, access stats snapshots, purge candidate identification, archive/purge execution, FOIA hold management, and Data Steward CLI.
- **Prompts 16-17** complete UDIP schema and middleware gaps identified in the security audit. Must run before first CDC data sync.
- **Prompts 18-20** harden Triage and ADR codebases based on security audit findings. Must run before hub connection and production deployment.

### Execution order:

**Phase 1 (parallel start):**
Prompts 1, 6, 9, 14 can start in parallel (new services + CDC infrastructure + UDIP middleware).
Prompt 14 is the first dependency for Prompt 9 (Event Hub must exist before CDC driver testing).
Prompt 13 runs alongside 1 and 6 (CI/CD for the new repos).
Prompts 16, 17 run immediately after Prompt 9 schema is deployed (complete missing tables, engine extensions). Must finish before first CDC sync.
Prompt 15 depends on Prompt 9 (lifecycle schema must exist before automation).

**Phase 2 (after Phase 1 deployed):**
Prompt 4 depends on OBO decision being finalized.
Prompts 2, 7, 10 run together (ADR audit correlation + ARCSyncImporter + UDIP push).
Prompts 3, 8, 11 run together (Triage audit correlation + ARC lookup + UDIP push).
Prompt 18 runs in Phase 2 (Triage security hardening — critical fixes before hub connection).
Prompt 19 runs in Phase 2 (ADR security hardening — before hub connection).

**Phase 2 (scaling hardening, before hub connection):**
Prompts 21, 22 run in Phase 2 (ADR + Triage horizontal scaling — distributed locking, Redis caches, repartitioning). Must complete before connecting to hub (hub will send concurrent requests to spokes).
Prompt 23 runs in Phase 1-2 (UDIP scaling — PgBouncer, connection pool, thread safety). Must complete before MCP queries go live.

**Phase 2 (AI Assistant — after UDIP data pipeline is live):**
Prompt 24 runs after data is flowing (conversation memory + multi-turn context). This is the highest-impact AI feature — leadership wants conversational interaction.
Prompt 25 runs after Prompt 24 (visualization generation depends on conversation context for follow-up chart modifications). Can start in parallel if visualization is independent of history.

**Phase 3 (before production):**
Prompt 20 runs before production (Triage AI/LLM hardening).
Prompt 26 runs in Phase 3 (dashboard creation + Superset integration — requires Prompts 24+25).
Prompts 5 and 12 are independent (OGC Trial Tool, can start anytime).

---

## Compliance Mandate for All Prompts

**Every prompt that produces code must include this compliance block.** Append it to
the end of each prompt when executing:

```
COMPLIANCE REQUIREMENTS (apply to all code produced):

All code must pass the established FedRAMP NIST 800-53 security toolchain:

1. SAST: Code must pass Bandit with zero medium+ findings and Semgrep with
   zero high findings. No eval(), no subprocess with shell=True on user input,
   no hardcoded credentials, no insecure deserialization.

2. SCA: All dependencies pinned to exact versions in requirements.txt.
   No known CVEs per pip-audit. No copyleft licenses in production dependencies
   per pip-licenses check.

3. SBOM: Include a CycloneDX-compatible requirements.txt so generate-sbom.sh
   can produce a valid SBOM (NIST SA-4 supplier transparency).

4. Secrets: Zero hardcoded secrets, tokens, keys, or passwords in source code.
   All secrets from Azure Key Vault via environment variables or
   DefaultAzureCredential. Connection strings, API keys, HMAC salts — all
   from Key Vault.

5. Input validation: All external-facing parameters validated. Charge numbers:
   regex ^[A-Z0-9\-]{3,25}$. Email addresses: validated format. Date strings:
   ISO 8601 parsed with error handling. No raw string concatenation in SQL
   queries (parameterized only). No OData injection in Azure Table queries
   (sanitize partition/row keys).

6. Logging: Structured JSON logging. Hash all user identifiers with SHA-256
   before logging (PII protection). Never log tokens, passwords, or PII.
   Include correlation IDs (X-Request-ID) in all log entries.

7. Transport: HTTPS only for all outbound calls. TLS 1.2 minimum.
   SSRF prevention: block private/loopback/reserved IP ranges on outbound.

8. Containers: Non-root user in Dockerfile. Minimal base image
   (python:3.12-slim-bookworm). No unnecessary packages. Multi-stage build
   to exclude build tools from runtime image.

9. Auth: All endpoints authenticated (no anonymous access except /healthz).
   Bearer tokens validated via JWKS discovery. Role-based access control
   enforced at the decorator level.

10. Audit: All state-changing operations logged to immutable audit trail.
    RetentionPolicy: FOIA_7_YEAR. DataClassification: AI_AUDIT for AI
    operations, OPERATIONAL for non-AI operations. HMAC-SHA256 integrity
    hashes on audit records.

11. Security headers: Flask-Talisman for CSP, HSTS (31536000s), X-Frame-Options,
    X-Content-Type-Options. CSRF protection via Flask-WTF on all form endpoints.

12. Error handling: Never expose stack traces, internal paths, or system details
    in error responses. Return structured error JSON with correlation ID only.
```

---

## Prompt 9: UDIP WAL/CDC Pipeline + Reconciliation Engine + New Analytics Tables

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 1 (Weeks 2-6)

### Prompt

```
The UDIP Analytics Platform needs three changes to become the central data store:

1. An Event Hub consumer driver for the sync engine so it can ingest WAL/CDC
   change events from PrEPA's PostgreSQL (via Debezium and Azure Event Hub)
2. A reconciliation engine that compares UDIP analytics tables against IDR
   (the nightly SQL Server snapshot) twice weekly to catch any missed records
3. New PostgreSQL tables and dbt models for ADR and Triage operational analytics
   pushed via the existing ingest API

PART 1: Event Hub Consumer Driver for Sync Engine

In data-middleware/sync_engine.py, the current sync engine only supports SQL
sources (pyodbc for SQL Server, psycopg2 for PostgreSQL). Add an Azure Event Hub
(Kafka protocol) consumer driver so UDIP can consume WAL/CDC change events from
PrEPA's PostgreSQL database via Debezium.

1. Create data-middleware/eventhub_source.py:
   - Class EventHubSourceDriver that implements the same interface as SQL sources
   - Accepts configuration: connection_string (from env), consumer_group,
     topic_prefix (Debezium topic naming: {prefix}.{schema}.{table}),
     starting_position (earliest, latest, or offset)
   - Auth: EVENTHUB_CONNECTION_STRING from Key Vault, or managed identity
   - Consumes Debezium CDC events (JSON envelope: before/after row images,
     operation type: c=create, u=update, d=delete, r=read/snapshot)
   - Yields rows as list of dicts matching the "after" image for creates/updates
   - Handles deletes by yielding a tombstone record (soft-delete marker)
   - Tracks consumer group offsets -- only commits offset after successful upsert
   - Returns rows in the same format as SQL cursor fetchall mapping
   - Timeout: 60 seconds per poll cycle
   - Dead letter: events that fail transformation logged to middleware.sync_dead_letter

2. Two-schema data flow:
   CDC events land first in the replica schema (raw, original PrEPA column
   names, untransformed) and then the middleware reads from replica and
   writes translated data to the analytics schema (clean labels, PII
   redacted, AI-ready). The publication is FOR ALL TABLES -- every PrEPA
   table replicates, including reference tables (shared_basis, shared_issue,
   shared_statute, offices). Reference tables replicate to replica schema
   and are used as JOIN targets for FK resolution in the YAML mappings
   (replacing static CSV lookup files).

   Create source mapping YAML files for PrEPA WAL/CDC:
   - data-middleware/source_mappings/prepa_charges.yaml
     Source: replica.charge_inquiry (populated by CDC from Event Hub)
     Target: analytics.charges
     Column mappings from PrEPA's PostgreSQL schema to analytics schema
     FK resolution: JOIN replica.shared_basis ON shared_basis_id to get
     human-readable basis name (replaces inline value_map)
     PII redaction on narrative fields
   - data-middleware/source_mappings/prepa_allegations.yaml
     Source: replica.charge_allegation
   - data-middleware/source_mappings/prepa_staff_assignments.yaml
     Source: replica.charge_assignment
   - data-middleware/source_mappings/prepa_charging_party.yaml
     Source: replica.charging_party (PII tier 3 → redact to tier 2)
   - data-middleware/source_mappings/prepa_respondent.yaml
     Source: replica.respondent
   - Reference tables (replica.shared_basis, replica.shared_issue,
     replica.shared_statute, replica.offices, etc.) do not need YAML
     mappings -- they replicate as-is and serve as lookup targets

3. In data-middleware/sync_engine.py:
   - Add Event Hub source type to the driver factory
   - When source_mappings specify connection_type: "eventhub", use EventHubSourceDriver
   - Keep existing SQL drivers for IDR reconciliation and Angular cases
   - Add a "continuous" sync mode (in addition to existing batch mode) that
     keeps the Event Hub consumer running and processes events as they arrive
   - The continuous mode should be deployable as a Kubernetes Deployment
     (always-on) rather than the existing CronJob (periodic batch)

4. Configuration:
   - EVENTHUB_CONNECTION_STRING (Event Hub namespace connection)
   - EVENTHUB_CONSUMER_GROUP (default: "udip-middleware")
   - CDC_TOPIC_PREFIX (default: "prepa", maps to Debezium server.name)

PART 2A: Reconciliation Engine

5. Create data-middleware/reconciliation.py:
   - Class ReconciliationEngine that compares UDIP analytics tables against
     IDR SQL Server snapshot to detect missing or stale records
   - reconcile_table(config) method:
     a. Count rows in IDR where modified > last_reconciliation_timestamp
     b. Count matching rows in analytics
     c. Compare SHA-256 checksums on a sample (1000 random rows by primary key)
     d. If discrepancy found, identify specific missing charge_ids
     e. Auto-backfill missing records using existing sqlserver_*.yaml mappings
     f. Alert if discrepancy > 0.1% of total rows
   - Log reconciliation results to middleware.reconciliation_log table

6. Create reconciliation config YAMLs:
   - data-middleware/reconciliation_configs/charges_reconciliation.yaml
     Source: IDR dbo.CHG_TBL (existing sqlserver connection)
     Target: analytics.charges
     Schedule: tuesday,friday at 03:00 UTC
     Threshold: 0.1%
     Backfill mapping: sqlserver_charges.yaml (reuses existing YAML transform)
   - data-middleware/reconciliation_configs/adr_reconciliation.yaml
     Same pattern for adr_outcomes

7. Create new PostgreSQL tables:
   - middleware.reconciliation_log: reconciliation_id, table_name,
     reconciliation_date, idr_row_count, analytics_row_count,
     sample_size, mismatches_found, records_backfilled,
     discrepancy_percent, status, error_message, duration_seconds
   - middleware.sync_dead_letter: id, source_topic, event_key,
     event_payload (JSON), error_message, received_at, retry_count

8. Kubernetes CronJob for reconciliation:
   - Schedule: "0 3 * * 2,5" (Tuesday + Friday 03:00 UTC)
   - Separate from the main sync job
   - Uses existing IDR SQL Server connection (SOURCE_SQLSERVER_CONNECTION)

9. Kubernetes Deployment for continuous CDC consumer:
   - Always-on deployment (not a CronJob)
   - Runs sync_engine.py in continuous mode consuming from Event Hub
   - Health probe: consumer lag check (alert if lag > 5 minutes)
   - Resource limits appropriate for sustained Event Hub consumption

PART 2B: Data Lifecycle Management Schema

The analytics database currently has no partitioning, no access tracking, no
retention enforcement, and no automated purge capability. ARC data arrives
with no creation or last-accessed timestamps. Add a complete data lifecycle
management layer that supports FOIA/NARA compliance, space reclamation, and
usage-based pruning decisions.

10. Partition analytics.charges by fiscal year (Oct 1 - Sep 30):
    - Add a computed column: fiscal_year INT GENERATED ALWAYS AS (
        CASE WHEN EXTRACT(MONTH FROM filing_date) >= 10
            THEN EXTRACT(YEAR FROM filing_date) + 1
            ELSE EXTRACT(YEAR FROM filing_date)
        END) STORED
    - Convert analytics.charges to a partitioned table using PARTITION BY LIST (fiscal_year)
    - Create partitions for each fiscal year with data (FY2020 through FY2027).
      Use a default partition to catch records outside the defined range.
    - Create a partition creation function that auto-creates next year's
      partition when a record arrives for an undefined fiscal year
    - Migrate existing data into partitions (pg_dump old table, create
      partitioned table, restore into partitions, swap names)
    - Verify all existing RLS policies apply correctly to partitioned tables
      (PostgreSQL applies parent table policies to all partitions automatically)
    - Verify all existing indexes are recreated per-partition
    - Verify CASCADE foreign keys from adr_outcomes, investigations,
      angular_cases still work (they reference charge_id, not fiscal_year)

11. Partition analytics.adr_outcomes, analytics.investigations, and
    analytics.angular_cases by fiscal_year using the same pattern.
    Each references a charge — derive fiscal_year from the parent charge's
    filing_date via a join at sync time, or add a fiscal_year column
    populated by the middleware during sync.

12. Add lifecycle metadata columns to ALL analytics tables
    (charges, adr_outcomes, investigations, angular_cases, and the new
    ADR/Triage tables defined in PART 3):

    - first_synced_at (TIMESTAMPTZ DEFAULT NOW())
      When the record first entered UDIP. Set on INSERT only, never
      overwritten on UPDATE. Use INSERT ... ON CONFLICT DO UPDATE with
      a check: SET first_synced_at = COALESCE(EXCLUDED.first_synced_at,
      analytics.charges.first_synced_at) to preserve the original value.

    - case_closed_at (TIMESTAMPTZ, nullable)
      Populated from ARC closure data (via CDC or middleware sync).
      NULL while the case is open. Starts the NARA 7-year retention clock.

    - retention_expires_at (TIMESTAMPTZ GENERATED ALWAYS AS
      (case_closed_at + INTERVAL '7 years') STORED)
      Computed. When NARA 7-year retention ends. NULL while case is open
      (open cases never expire). For non-charge tables (adr_daily_metrics,
      triage_daily_metrics), use metric_date + INTERVAL '7 years' instead.

    - retention_hold (BOOLEAN DEFAULT FALSE)
      FOIA or litigation hold flag. When TRUE, prevents purging regardless
      of retention_expires_at. Can only be set by users with the
      data_steward role.

    - hold_reason (VARCHAR(200), nullable)
      FOIA request number, litigation case ID, or other justification.
      Required when retention_hold is set to TRUE (enforced by CHECK
      constraint: hold_reason IS NOT NULL WHEN retention_hold = TRUE).

    - hold_set_by (VARCHAR(128), nullable)
      Hashed OID of the user who set the hold (PII protection, same
      SHA-256 pattern as audit logger).

    - hold_set_at (TIMESTAMPTZ, nullable)
      When the hold was applied.

    - lifecycle_state (VARCHAR(20) DEFAULT 'active' CHECK (lifecycle_state
      IN ('active', 'closed', 'eligible', 'held', 'archived', 'purged')))
      State machine:
        active    → case is open in ARC
        closed    → case_closed_at is populated, retention clock running
        eligible  → retention_expires_at < NOW() and retention_hold = FALSE
        held      → eligible but retention_hold = TRUE (FOIA/litigation)
        archived  → data moved to cold storage, partition detached
        purged    → data deleted, only audit record remains

13. Create middleware.lifecycle_audit_log table:
    - audit_id (UUID DEFAULT gen_random_uuid())
    - table_name (VARCHAR(128))
    - partition_name (VARCHAR(128))
    - fiscal_year (INT)
    - action (VARCHAR(20): 'state_transition', 'hold_set', 'hold_released',
      'archive', 'purge', 'partition_created', 'partition_dropped')
    - old_state (VARCHAR(20), nullable)
    - new_state (VARCHAR(20), nullable)
    - records_affected (INT)
    - performed_by (VARCHAR(128)) -- hashed OID
    - performed_at (TIMESTAMPTZ DEFAULT NOW())
    - reason (TEXT)
    - approved_by (VARCHAR(128), nullable) -- hashed OID of Data Steward
    - approval_date (TIMESTAMPTZ, nullable)
    Grant INSERT only to application roles. No UPDATE or DELETE permissions.
    This table is the immutable audit trail for all lifecycle operations.

14. Create middleware.access_stats table for partition-level usage tracking:
    - table_name (VARCHAR(128))
    - partition_name (VARCHAR(128))
    - fiscal_year (INT)
    - snapshot_date (DATE)
    - seq_scan_count (BIGINT) -- from pg_stat_user_tables
    - idx_scan_count (BIGINT) -- from pg_stat_user_tables
    - seq_scan_delta (BIGINT) -- change since last snapshot
    - idx_scan_delta (BIGINT) -- change since last snapshot
    - mcp_query_count (INT) -- from MCP audit log aggregation
    - superset_query_count (INT) -- from query log aggregation
    - total_rows (BIGINT) -- pg_class.reltuples
    - total_bytes (BIGINT) -- pg_total_relation_size
    - days_since_last_scan (INT, computed) -- for pruning decisions
    Primary key: (table_name, partition_name, snapshot_date)
    Populated daily by the lifecycle automation job (see Prompt 15).

15. Enable pg_stat_statements on the Azure PostgreSQL Flexible Server:
    - Document the Azure parameter change: shared_preload_libraries = 'pg_stat_statements'
    - Set pg_stat_statements.max = 5000 (default is 5000, confirm)
    - Set pg_stat_statements.track = 'all' (track all statements including nested)
    - This provides query-level access patterns: which query templates run,
      how often, mean execution time, rows returned. Zero per-row overhead.

16. Create data lifecycle views for operational monitoring:
    - middleware.vw_partition_usage: joins pg_stat_user_tables with
      access_stats to show each partition's scan activity, size, row count,
      and days since last access. Ordered by days_since_last_scan DESC
      to surface cold partitions.
    - middleware.vw_retention_status: per-fiscal-year summary showing
      total records, records with case_closed_at populated, records past
      retention, records on hold, and records eligible for purge.
    - middleware.vw_purge_candidates: records where lifecycle_state = 'eligible'
      AND retention_hold = FALSE AND retention_expires_at < NOW(),
      grouped by fiscal year with row counts and total size estimates.
    - middleware.vw_hold_inventory: all records with retention_hold = TRUE,
      showing hold_reason, hold_set_by, hold_set_at, and the underlying
      charge details. For FOIA compliance reporting.

PART 3: New Tables for ADR and Triage Analytics

These tables receive data pushed by ADR and Triage via the existing
POST /api/v1/mcp/ingest endpoint (Analytics.Write role).

17. Create new PostgreSQL tables (add to analytics-db/postgres/):
   - analytics.adr_daily_metrics
     Columns: metric_date (DATE, PK), cases_open, cases_closed,
     agreements_finalized, impasses, withdrawals, avg_case_duration_days,
     total_mediators, active_mediators, utilization_rate,
     ai_tokens_used, malware_files_detected, synced_at
   - analytics.adr_reliance_scores
     Columns: score_date (DATE), feature_name, user_id_hash,
     total_generations, accepted_without_edit, accepted_with_minor_edit,
     accepted_with_major_edit, rejected, reliance_score, diversity_score,
     synced_at
   - analytics.adr_model_drift
     Columns: analysis_date, model_deployment, feature_name,
     drift_percentage, drift_detected (BOOL), severity, sample_size,
     synced_at
   - analytics.triage_daily_metrics
     Columns: metric_date (DATE, PK), total_cases, rank_a, rank_b, rank_c,
     corrections, avg_confidence, ai_acceptance_rate, error_rate,
     p50_processing_seconds, p95_processing_seconds, scan_clean,
     scan_malicious, synced_at
   - analytics.triage_correction_flows
     Columns: analysis_hour (TIMESTAMP), a_to_b, a_to_c, b_to_a, b_to_c,
     c_to_a, c_to_b, total_corrections, b_to_c_threshold_breach (BOOL),
     synced_at
   - analytics.triage_reliance_scores
     Columns: score_date (DATE), system_acceptance_rate,
     avg_correction_time_hours, total_corrections, total_cases,
     feedback_adoption_rate, synced_at

18. Apply RLS policies to new tables:
    - Same pattern as existing analytics tables
    - Privileged roles see all; others scoped by region

19. Add lifecycle metadata columns (from PART 2, item 12) to all new tables.
    For daily metrics tables that have no case_closed_at concept, use:
    - retention_expires_at = metric_date + INTERVAL '7 years'
    - lifecycle_state defaults to 'closed' (metrics are immutable once written)

20. Create dbt models for new tables:
    - stg_adr_daily_metrics, stg_triage_daily_metrics (staging)
    - fct_adr_performance (joins daily metrics + reliance + drift)
    - fct_triage_performance (joins daily metrics + corrections + reliance)

21. Register new tables in the MCP dataset registry so they appear as
    query_{table_name} tools and ingest_{table_name} tools automatically.

22. Create dbt models for lifecycle monitoring:
    - rpt_data_lifecycle_summary: fiscal year rollup of lifecycle states,
      retention status, hold counts, and partition sizes
    - rpt_partition_usage: daily partition access patterns for pruning decisions

Write a CHANGES.md explaining all three parts. Include a unified diff.
```

---

## Prompt 10: ADR → UDIP Analytics Push

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 4 (Week 9)

### Prompt

```
Add an Azure Function to the ADR Mediation Platform that pushes operational
analytics to UDIP's centralized data store on a daily schedule.

UDIP has an ingest API at POST /api/v1/mcp/ingest that accepts JSON records
with an Analytics.Write bearer token. ADR needs to push its daily metrics,
AI reliance scores, and model drift data to UDIP so the agency has a unified
analytics picture.

1. Create adr_functionapp/UDIPAnalyticsPush/__init__.py:
   - Timer trigger: runs daily at 04:00 UTC (after MetricsRollupDaily at 02:00)
   - ShedLock: lock name "udip-analytics-push", lock for PT15M
   - Reads from ADR's Azure Table Storage:
     a. metricsrollupdaily — last 2 days of daily metrics
     b. reliancescores — last 2 days of reliance data
     c. modeldrift — last 2 days of drift data
   - Transforms each into the UDIP target schema:
     a. metricsrollupdaily → analytics.adr_daily_metrics
     b. reliancescores → analytics.adr_reliance_scores
     c. modeldrift → analytics.adr_model_drift
   - Calls UDIP's ingest API:
     POST {UDIP_INGEST_URL}/api/v1/mcp/ingest
     Authorization: Bearer {managed identity token for UDIP scope}
     Body: { "dataset": "adr_daily_metrics", "records": [...] }
   - Repeats for each dataset
   - Logs success/failure per dataset to application insights

2. Create adr_functionapp/UDIPAnalyticsPush/function.json:
   - Timer trigger with schedule "0 0 4 * * *"

3. Auth: Use DefaultAzureCredential to acquire token for UDIP's app
   registration scope (env: UDIP_API_SCOPE)

4. Configuration:
   - UDIP_INGEST_URL (base URL of UDIP analytics platform)
   - UDIP_API_SCOPE (Entra ID scope, e.g., api://<udip-client-id>/.default)
   - UDIP_PUSH_ENABLED (feature flag, default: false)

5. Error handling:
   - If UDIP is unreachable, log warning and retry next cycle (not fatal)
   - If a dataset push fails, continue with remaining datasets
   - Track last successful push timestamp in systemsettings table

6. PII: All user identifiers are already hashed (SHA-256) in the source
   tables. No additional PII handling needed.

Write a CHANGES.md and unified diff. This is additive — existing functions
must not be modified.
```

---

## Prompt 11: Triage → UDIP Analytics Push

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 5 (Week 10)

### Prompt

```
Add an Azure Function to the OFS Triage System that pushes operational
analytics to UDIP's centralized data store on a daily schedule.

Same pattern as the ADR analytics push. UDIP has an ingest API at
POST /api/v1/mcp/ingest that accepts JSON records with Analytics.Write.

1. Create case-processor-function/UDIPAnalyticsPush/__init__.py:
   - Timer trigger: runs daily at 04:30 UTC (after MetricsRollupDaily)
   - Reads from Triage's Azure Table Storage:
     a. metricsdaily — last 2 days of daily metrics
     b. modeldrift — last 2 days of correction flow data
     c. reliancescores — last 2 days of reliance data
   - Transforms to UDIP target schema:
     a. metricsdaily → analytics.triage_daily_metrics
     b. modeldrift → analytics.triage_correction_flows
     c. reliancescores → analytics.triage_reliance_scores
   - Calls UDIP ingest API for each dataset
   - Logs success/failure

2. Create case-processor-function/UDIPAnalyticsPush/function.json

3. Auth: DefaultAzureCredential for UDIP scope

4. Configuration:
   - UDIP_INGEST_URL, UDIP_API_SCOPE, UDIP_PUSH_ENABLED (default: false)

5. Error handling: same resilience pattern as ADR (non-fatal, retry next cycle)

Write a CHANGES.md and unified diff.
```

---

## Prompt 12: OGC Trial Tool CI/CD Pipeline

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 6

### Prompt

```
The OGC Trial Tool has security scanning scripts in example_data/scripts/
but no GitHub Actions workflow. Create a CI/CD pipeline matching the pattern
established in the ADR and Triage repositories.

1. Create .github/workflows/security-audit-evidence.yml:
   - Trigger: push to main, pull_request to main, manual dispatch
   - Jobs:
     a. sbom-generation: Run scripts/generate-sbom.sh using cyclonedx-bom
     b. sast-scan: Run Bandit on trial_tool_webapp/ and shared_code/,
        Semgrep via container, pip-audit on requirements.txt, secret scanning
     c. dependency-check: OWASP Dependency-Check with NVD API key
     d. license-scan: pip-licenses compliance check
     e. dast-baseline: Manual trigger only, OWASP ZAP against staging URL
   - Artifact retention: 90 days
   - Reference NIST controls in job comments: SA-4, SA-11, CA-8

2. Create scripts/ directory (copy pattern from example_data/scripts/):
   - scripts/generate-sbom.sh
   - scripts/sast-scan.sh
   - scripts/owasp-depcheck.sh
   - scripts/license-scan.sh
   - scripts/dast-baseline.sh

3. Ensure all scripts reference the correct paths for the trial tool
   (trial_tool_webapp/, trial_tool_functionapp/, shared_code/)

Write a CHANGES.md. Include all files with complete contents.
```

---

## Prompt 13: CI/CD Pipelines for New Services

**Repository:** NEW repos: `eeoc-arc-integration-api/` and `eeoc-mcp-hub/`
**Owner:** Hub team
**Phase:** 1-2

### Prompt

```
Create GitHub Actions CI/CD pipelines for both new services: the ARC Integration
API and the MCP Hub. Follow the established EEOC security scanning pattern.

For EACH repository, create:

1. .github/workflows/security-audit-evidence.yml:
   - Trigger: push to main, pull_request to main, weekly schedule, manual
   - Jobs matching the ADR/Triage/UDIP pattern:
     a. sbom-generation (CycloneDX)
     b. sast-scan (Bandit + Semgrep + pip-audit + secrets)
     c. dependency-check (OWASP with NVD API key)
     d. license-scan (pip-licenses)
     e. dast-baseline (manual trigger, ZAP)
   - Artifact retention: 90 days
   - NIST control references: SA-4, SA-11, CA-8, SI-10

2. .github/workflows/build-and-test.yml:
   - Trigger: push, pull_request
   - Jobs:
     a. lint: ruff or flake8
     b. test: pytest with coverage (minimum 80% line coverage)
     c. type-check: mypy (if type hints are used throughout)
     d. build-container: Build Docker image, verify it starts

3. scripts/ directory:
   - generate-sbom.sh
   - sast-scan.sh
   - owasp-depcheck.sh
   - license-scan.sh
   - dast-baseline.sh

4. Dockerfile best practices:
   - Multi-stage build (builder + runtime)
   - Base: python:3.12-slim-bookworm
   - Non-root user (appuser, UID 1001)
   - HEALTHCHECK instruction
   - No unnecessary packages in runtime stage
   - Pin base image digest for reproducibility

5. .dockerignore and .gitignore matching EEOC standards

Provide complete file listings for both repositories.
```

---

## Prompt 14: Debezium CDC Infrastructure

**Repository:** Infrastructure / DevOps (new deployment configs)
**Owner:** Platform team
**Phase:** 1 (Weeks 1-2)

### Prompt

```
Set up the CDC pipeline from PrEPA's PostgreSQL to Azure Event Hub using
Debezium.

CONTEXT:
- PrEPA runs PostgreSQL 9.x on Azure (jdbc:postgresql, HikariCP pool max 25)
- PrEPA's core tables: charge_inquiry, charging_party, respondent,
  charge_allegation, charge_assignment, plus reference tables (shared_basis,
  shared_issue, shared_statute)
- Target: Azure Event Hub namespace (Kafka protocol compatible)
- Debezium runs as a standalone connector or Kafka Connect cluster

BUILD THE FOLLOWING:

1. PostgreSQL logical replication setup:
   - SQL script to create a logical replication slot on PrEPA's PostgreSQL:
     SELECT pg_create_logical_replication_slot('udip_cdc', 'pgoutput');
   - SQL script to create a publication for ALL tables:
     CREATE PUBLICATION udip_publication FOR ALL TABLES;
     This streams every table in PrEPA's database -- charges, allegations,
     staff, reference tables (shared_basis, shared_issue, shared_statute,
     offices), mediation, closures, events, everything. When PrEPA adds
     new tables, they appear in the stream automatically.
   - Document the exact permissions needed (REPLICATION role, SELECT on tables)
   - Document WAL retention settings (max_slot_wal_keep_size to prevent
     disk exhaustion if consumer falls behind)

2. Debezium connector configuration:
   - Connector class: io.debezium.connector.postgresql.PostgresConnector
   - Connection to PrEPA PostgreSQL (credentials from Key Vault)
   - Plugin: pgoutput (native, no extension needed on 10+) or
     decoderbufs (for 9.x if pgoutput not available)
   - Topic naming: prepa.public.{table_name}
   - Snapshot mode: initial (full snapshot on first start, then streaming)
   - Heartbeat interval: 30 seconds
   - Slot name: udip_cdc
   - Publication name: udip_publication
   - Tombstone on delete: true
   - Column filtering: exclude PII columns that UDIP does not need
     (e.g., charging_party.ssn — never transmitted, redacted at source)

3. Azure Event Hub namespace:
   - Kafka-enabled Event Hub namespace
   - One Event Hub (topic) per PrEPA table
   - Retention: 7 days (enough buffer for UDIP outages)
   - Consumer group: udip-middleware
   - Partition count: 4 (sufficient for current volume)

4. Monitoring:
   - Debezium connector health check endpoint
   - Lag monitoring: consumer group offset lag
   - Alert if replication slot WAL retention exceeds threshold
   - Alert if connector is not running

5. Deployment:
   - Kubernetes Deployment for Debezium Connect (or Azure Container Apps)
   - Dockerfile with Debezium PostgreSQL connector
   - Helm chart or deployment YAML
   - Health and readiness probes

6. Fallback documentation:
   - If ARC team cannot grant logical replication access, document the
     fallback path: Service Bus subscription on db-change-topic +
     REST API feed endpoints from ARC Integration API
   - The middleware YAML configs work with either path (just different
     source driver in the YAML)
```

---

## Prompt 15: UDIP Data Lifecycle Automation

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 1-2 (after Prompt 9 schema is deployed)

### Prompt

```
Add automated data lifecycle management to the UDIP Analytics Platform.
Prompt 9 defines the schema (partitioning, lifecycle metadata columns,
lifecycle_audit_log, access_stats tables, monitoring views). This prompt
builds the automation that operates on that schema.

CONTEXT:
- Analytics tables are partitioned by fiscal year (Prompt 9, items 10-11)
- Every analytics record has lifecycle_state, case_closed_at,
  retention_expires_at, retention_hold, hold_reason columns (Prompt 9, item 12)
- middleware.lifecycle_audit_log records every lifecycle action immutably
- middleware.access_stats tracks partition-level scan activity daily
- pg_stat_statements is enabled for query pattern analysis
- NARA requires 7-year retention from case closure (not creation)
- FOIA holds block purging regardless of retention expiration
- All purge operations require Data Steward approval

BUILD THE FOLLOWING:

1. Create data-middleware/lifecycle_manager.py:

   Class LifecycleManager with the following operations:

   a. transition_states():
      - Move records from 'active' to 'closed' where case_closed_at IS NOT NULL
        AND lifecycle_state = 'active'
      - Move records from 'closed' to 'eligible' where retention_expires_at < NOW()
        AND retention_hold = FALSE AND lifecycle_state = 'closed'
      - Move records from 'eligible' to 'held' where retention_hold = TRUE
        AND lifecycle_state = 'eligible'
      - Move records from 'held' to 'eligible' where retention_hold = FALSE
        AND lifecycle_state = 'held' (hold was released)
      - Log every transition batch to middleware.lifecycle_audit_log
      - Return summary: { transitions: { active_to_closed: N, closed_to_eligible: N, ... } }

   b. snapshot_access_stats():
      - Query pg_stat_user_tables for all analytics partitions
        (filter by schemaname = 'analytics' and relname matching partition pattern)
      - Record seq_scan, idx_scan counts per partition
      - Compute delta from previous snapshot
      - Query MCP audit logs (aigenerationaudit table) for tool invocations
        that reference analytics datasets, aggregate by fiscal year
      - Insert snapshot row into middleware.access_stats
      - Return summary: { partitions_tracked: N, coldest_partition: { name, days_since_scan } }

   c. identify_purge_candidates():
      - Query middleware.vw_purge_candidates (records where eligible, no hold,
        past retention)
      - Group by fiscal year
      - For each fiscal year, check partition access_stats: if the partition
        has had zero scans in the last 180 days, flag as "cold + eligible"
      - Return list of candidate fiscal years with record counts, total size,
        last access date, and hold count (should be 0)
      - Do NOT execute any purge. This is reporting only.

   d. execute_purge(fiscal_year, approved_by, approval_reason):
      - Validate: ALL records in the partition have lifecycle_state = 'eligible'
        AND retention_hold = FALSE AND retention_expires_at < NOW()
      - If any records fail validation, abort and return the failing charge_ids
      - Before dropping: pg_dump the partition to Azure Blob Storage (cool tier)
        as a safety archive. Record the blob path in lifecycle_audit_log.
      - Update lifecycle_state to 'purged' for all records (this persists
        in the audit log even after the partition is dropped)
      - Log the purge to middleware.lifecycle_audit_log with approved_by,
        approval_reason, records_affected, archive_blob_path
      - DROP the partition (CASCADE handles dependent records in adr_outcomes,
        investigations, angular_cases, embeddings)
      - Return summary: { fiscal_year, records_purged, bytes_freed, archive_path }

   e. archive_partition(fiscal_year):
      - For cold partitions that are not yet eligible for purge but consume
        space: pg_dump to Azure Blob (cool tier), then DETACH the partition
        from the parent table. The data is preserved in blob storage and can
        be re-attached if needed.
      - Set lifecycle_state to 'archived' for affected records
      - Log to lifecycle_audit_log

   f. set_hold(charge_ids, hold_reason, set_by):
      - Set retention_hold = TRUE, hold_reason, hold_set_by (hashed),
        hold_set_at = NOW() for the specified charge_ids
      - If any charge_ids are in lifecycle_state = 'eligible', move them to 'held'
      - Log to lifecycle_audit_log
      - Return: { charges_held: N, charges_already_held: N }

   g. release_hold(charge_ids, release_reason, released_by):
      - Set retention_hold = FALSE, clear hold_reason, hold_set_by, hold_set_at
      - If retention_expires_at < NOW(), move lifecycle_state to 'eligible'
      - If retention_expires_at >= NOW(), move lifecycle_state back to 'closed'
      - Log to lifecycle_audit_log
      - Return: { charges_released: N, now_eligible: N, still_retained: N }

   h. auto_create_partition(fiscal_year):
      - Check if partition exists for the given fiscal year
      - If not, CREATE TABLE analytics.charges_fy{year} PARTITION OF
        analytics.charges FOR VALUES IN ({year})
      - Repeat for adr_outcomes, investigations, angular_cases
      - Log to lifecycle_audit_log with action = 'partition_created'
      - Called automatically by the CDC consumer when a record arrives
        for an undefined fiscal year

2. Create data-middleware/lifecycle_cli.py:
   Command-line interface for Data Stewards to manage lifecycle operations.

   Commands:
   - lifecycle status: print middleware.vw_retention_status
   - lifecycle usage: print middleware.vw_partition_usage (sorted by coldest)
   - lifecycle candidates: print purge candidates with sizes
   - lifecycle holds: print middleware.vw_hold_inventory
   - lifecycle set-hold --charges 370-2026-00123,370-2026-00124 --reason "FOIA-2026-0456"
   - lifecycle release-hold --charges 370-2026-00123 --reason "FOIA request closed"
   - lifecycle archive --fiscal-year 2020 --reason "Cold data, pre-retention"
   - lifecycle purge --fiscal-year 2019 --approved-by {oid} --reason "Past 7-year retention"
     (requires --confirm flag to actually execute)

   Auth: requires data_steward role. Validate via Entra ID token or
   local role check depending on execution context.

3. Kubernetes CronJob for daily lifecycle automation:
   - Schedule: "0 5 * * *" (daily at 05:00 UTC, after CDC sync and
     reconciliation are done)
   - Runs: transition_states() then snapshot_access_stats()
   - Does NOT run purge or archive automatically — those require
     Data Steward approval via the CLI
   - Logs summary to Application Insights

4. Kubernetes CronJob for weekly purge candidate reporting:
   - Schedule: "0 6 * * 1" (Monday at 06:00 UTC)
   - Runs: identify_purge_candidates()
   - Sends summary to a configured notification endpoint (email, Teams
     webhook, or Azure Monitor alert) if eligible partitions exist
   - Does NOT purge — notification only

5. Configuration:
   - LIFECYCLE_ENABLED (feature flag, default: false)
   - LIFECYCLE_ARCHIVE_CONTAINER (Azure Blob container for partition archives)
   - LIFECYCLE_ARCHIVE_CONNECTION_STRING (from Key Vault)
   - LIFECYCLE_NOTIFICATION_WEBHOOK (Teams or email endpoint for weekly report)
   - LIFECYCLE_COLD_THRESHOLD_DAYS (default: 180 — days with zero scans
     before a partition is considered cold)
   - LIFECYCLE_MIN_RETENTION_YEARS (default: 7 — NARA minimum, cannot be
     reduced below 7)

6. Tests:
   - Unit tests for state transitions (all valid transitions, rejection of
     invalid transitions like active → purged)
   - Unit test for hold/release logic (hold blocks purge, release re-enables)
   - Integration test: create test partition, populate, run lifecycle through
     all states, verify audit log completeness
   - Test that purge aborts if any record has retention_hold = TRUE
   - Test that purge aborts if any record has retention_expires_at in the future
   - Test archive and re-attach workflow

7. Documentation:
   - LIFECYCLE_GUIDE.md explaining the state machine, FOIA/NARA compliance
     rules, how to set/release holds, how to approve purges, and how to
     interpret the access stats and purge candidate reports
   - Written for Data Stewards, not developers

Write a CHANGES.md and unified diff. This is additive — existing sync engine,
middleware, and application code must not be modified beyond wiring in the
auto_create_partition call when the CDC consumer encounters an unknown
fiscal year.
```

---

## Prompt 16: UDIP Schema Completion (Missing Tables, RLS, dbt)

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 1 (before first CDC sync)

### Prompt

```
The security audit identified critical gaps: 6 analytics tables referenced
in YAML mappings do not exist, RLS policies are missing for new tables, and
dbt models reference a non-existent view. Fix all of these.

1. Create missing analytics tables in analytics-db/postgres/010-analytics-tables.sql
   (or a new 014-cdc-target-tables.sql file):

   - analytics.allegations
     Columns: allegation_id (UUID PK), charge_id (UUID FK -> charges),
     allegation_number (INT), statute (VARCHAR(100)), statute_code (VARCHAR(10)),
     basis (VARCHAR(100)), basis_code (VARCHAR(10)), issue (VARCHAR(200)),
     issue_code (VARCHAR(10)), first_alleged_date (DATE), last_alleged_date (DATE),
     allegation_description (TEXT, pii_tier 3),
     allegation_description_redacted (TEXT, pii_tier 2),
     allegation_status (VARCHAR(20)), cause_finding (VARCHAR(50)),
     cause_approval_status (VARCHAR(30)), is_continuing_action (BOOLEAN),
     is_recommended_for_litigation (BOOLEAN), closure_reason (VARCHAR(100)),
     closed_date (TIMESTAMPTZ), original_basis (VARCHAR(100)),
     original_issue (VARCHAR(200)),
     source_modified_at (TIMESTAMPTZ), synced_at (TIMESTAMPTZ DEFAULT NOW()),
     first_synced_at (TIMESTAMPTZ DEFAULT NOW()),
     case_closed_at (TIMESTAMPTZ), retention_expires_at (TIMESTAMPTZ),
     retention_hold (BOOLEAN DEFAULT FALSE), hold_reason (VARCHAR(200)),
     hold_set_by (VARCHAR(128)), hold_set_at (TIMESTAMPTZ),
     lifecycle_state middleware.lifecycle_state_t DEFAULT 'active'

   - analytics.charging_parties
     Columns: party_id (UUID PK), full_name (VARCHAR(200) pii_tier 3),
     name_initials (VARCHAR(10) pii_tier 1), email (VARCHAR(200) pii_tier 3),
     phone_home (VARCHAR(20) pii_tier 3), phone_cell (VARCHAR(20) pii_tier 3),
     phone_work (VARCHAR(20) pii_tier 3), city (VARCHAR(100) pii_tier 2),
     state (VARCHAR(50) pii_tier 1), zip_code (VARCHAR(10) pii_tier 3),
     zip_prefix (VARCHAR(3) pii_tier 1), sex (VARCHAR(20) pii_tier 1),
     is_hispanic (BOOLEAN pii_tier 1), has_disability (BOOLEAN pii_tier 1),
     date_of_birth (DATE pii_tier 3), language (VARCHAR(50)),
     national_origin_group (VARCHAR(100) pii_tier 2),
     mediation_reply (VARCHAR(50)),
     source_modified_at, synced_at, first_synced_at,
     lifecycle metadata columns (same pattern as charges)

   - analytics.respondents
     Columns: respondent_id (UUID PK), company_name (VARCHAR(200) pii_tier 2),
     doing_business_as (VARCHAR(200)), employer_id_number (VARCHAR(20) pii_tier 3),
     duns_number (VARCHAR(20)), cage_code (VARCHAR(10)), naics_code (VARCHAR(10)),
     employee_count_range (VARCHAR(50)), institution_type (VARCHAR(50)),
     city (VARCHAR(100)), state (VARCHAR(50)), zip_code (VARCHAR(10)),
     zip_prefix (VARCHAR(3)), contact_email (VARCHAR(200) pii_tier 3),
     contact_phone (VARCHAR(20) pii_tier 3), mediation_consent (VARCHAR(50)),
     mediation_agreement_signed (BOOLEAN), is_franchise (BOOLEAN),
     eeo1_headquarters_number (VARCHAR(20)), eeo1_headquarters_name (VARCHAR(200)),
     source_modified_at, synced_at, first_synced_at,
     lifecycle metadata columns

   - analytics.staff_assignments
     Columns: assignment_id (UUID PK), charge_id (UUID FK -> charges),
     staff_id (VARCHAR(50) pii_tier 2), staff_name (VARCHAR(200) pii_tier 2),
     is_mediator (BOOLEAN), is_primary_investigator (BOOLEAN),
     is_advisory_attorney (BOOLEAN), is_scheduler (BOOLEAN),
     assignment_reason (VARCHAR(100)), reporting_office (VARCHAR(100)),
     assignment_ended_at (TIMESTAMPTZ), is_active (BOOLEAN),
     assigned_at (TIMESTAMPTZ),
     source_modified_at, synced_at, first_synced_at,
     lifecycle metadata columns

   - analytics.mediation_sessions
     Columns: session_id (UUID PK), charge_id (UUID FK -> charges),
     scheduled_date (TIMESTAMPTZ), held_date (TIMESTAMPTZ),
     timezone (VARCHAR(50)), mediation_type (VARCHAR(50)),
     interpreter_needed (BOOLEAN), session_held (BOOLEAN),
     created_at (TIMESTAMPTZ),
     source_modified_at, synced_at, first_synced_at,
     lifecycle metadata columns

   - analytics.case_events
     Columns: event_id (UUID PK), charge_id (UUID FK -> charges),
     event_type (VARCHAR(100)), event_code (VARCHAR(20)),
     event_group (VARCHAR(50)), event_display_text (TEXT pii_tier 2),
     event_display_text_redacted (TEXT pii_tier 1),
     event_detail (JSONB pii_tier 2), legacy_event_detail (JSONB),
     is_mediation_event (BOOLEAN), reporting_office (VARCHAR(100)),
     document_type (VARCHAR(100)), is_mediation_related (BOOLEAN),
     is_public (BOOLEAN), is_fepa_event (BOOLEAN),
     event_date (TIMESTAMPTZ),
     source_modified_at, synced_at, first_synced_at,
     lifecycle metadata columns

   Add appropriate indexes on each table (charge_id FK, date columns,
   status columns).

2. Add RLS policies for ALL new tables in 040-rls-policies.sql:
   - ENABLE ROW LEVEL SECURITY and FORCE ROW LEVEL SECURITY on each
   - Region policy: inherit from parent charge via EXISTS subquery
     (same pattern as adr_outcomes, investigations, angular_cases)
   - PII policy on charging_parties: block tier 3 columns unless
     current_pii_tier >= 3
   - Writer policy: FOR ALL TO udip_writer USING (TRUE)
   - Add RLS policies for lifecycle tables (lifecycle_audit_log,
     access_stats, sync_dead_letter, reconciliation_log) — writer-only

3. Create analytics.vw_charges view:
   - SELECT * FROM analytics.charges
   - Or a filtered/transformed view if the dbt staging model expects
     specific column transformations
   - Verify stg_charges.sql works against this view

4. Create dbt staging and fact models for new tables:
   - stg_allegations, stg_charging_parties, stg_respondents,
     stg_staff_assignments, stg_mediation_sessions, stg_case_events
   - fct_allegations (joined with charge context)
   - fct_case_timeline (case_events ordered by event_date per charge)
   - dim_respondents, dim_charging_parties (dimension tables)
   - Add schema.yml entries with tests (uniqueness, not-null, accepted-values)
   - Add metric definitions in metric_definitions.yml

5. Add retention triggers on all new tables:
   - Same compute_retention_expires trigger as existing tables
   - lifecycle_state domain type already exists from 011-lifecycle-columns.sql

Write a CHANGES.md and unified diff.
```

---

## Prompt 17: UDIP Middleware Engine Extensions

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 1 (before first CDC sync)

### Prompt

```
The security audit identified that the YAML mapping configs reference
transform handlers not yet implemented in mapping_engine.py. Additionally,
PII redaction patterns are incomplete and input validation is missing.

PART 1: New Transform Handlers

In data-middleware/mapping_engine.py, add these transform handlers to
the RowTransformer class:

1. lookup_table transform:
   - Accepts lookup_config with: join_table, join_key, value_column
   - At sync startup, loads the lookup table into an in-memory dict
     (SELECT join_key, value_column FROM lookup_table WHERE obsolete != true)
   - During row transformation, resolves FK integer to value via dict lookup
   - If FK not found in dict, log warning and return NULL (not crash)
   - For multi-step joins (join_path + then_join), resolve sequentially
   - Support aggregate modes: "first" (default), "concat_with_separator"
   - Cache lookup dicts for the duration of the sync run, refresh on next run
   - The lookup tables are in the replica schema (populated by CDC)

2. lookup_then_redact transform:
   - Combines lookup_table resolution with redact_pii in one step
   - First resolves the FK to text via lookup, then applies PII redaction
   - Used for narrative fields that are stored as FKs to detail tables

3. fiscal_year transform:
   - Accepts fiscal_year_start_month (default: 10 for EEOC Oct 1 start)
   - Takes a date column, returns the fiscal year integer
   - Logic: if month >= start_month, year + 1, else year
   - Handle NULL dates (return NULL, not crash)

4. UUID_V5 computed expression:
   - In _evaluate_computed(), recognize UUID_V5(namespace, value) pattern
   - Generate deterministic UUID v5 from namespace string + source value
   - Use uuid.uuid5(uuid.NAMESPACE_DNS, f"{namespace}.{value}")
   - This converts PrEPA integer PKs to stable UUIDs for the analytics schema

5. Extended computed expressions:
   - CASE WHEN condition THEN value ELSE value END
   - NOT(condition) — invert a boolean expression
   - CONCAT(col1, separator, col2) — string concatenation
   - LEFT(column, n) — substring from left

PART 2: PII Redaction Enhancements

6. In the PII redaction regex patterns (RowTransformer.__init__), add:
   - EIN format: \b\d{2}-\d{7}\b (Employer Identification Number)
   - DOB format: \b(?:0[1-9]|1[0-2])[-/](?:0[1-9]|[12]\d|3[01])[-/](?:19|20)\d{2}\b
   - Require contextual keywords for DOB to avoid false positives on
     other date formats (keywords: "born", "DOB", "birth", "age")

PART 3: Input Validation

7. Add charge number format validation in MappingValidator:
   - If target column name is "charge_number", validate source values
     match ^[A-Z0-9\-]{3,25}$ (or stricter EEOC format if known)
   - Log warning on invalid format, do not block sync (data quality issue)

8. Document replica schema tables in 003-replica-schema.sql:
   - Add CREATE TABLE statements (or comments) for all tables referenced
     in YAML lookup_config: shared_basis, shared_issue, shared_statute,
     shared_code, charge_event_code, shared_document_type, charge_detail,
     charging_party, respondent, charge_allegation, charge_assignment,
     mediation_interview, charge_event_log
   - These tables are populated by CDC (Debezium), not by the middleware.
     The CREATE TABLE statements serve as documentation and schema
     validation targets.

9. Add unit tests for all new transforms:
   - lookup_table with valid FK, missing FK, NULL FK
   - fiscal_year with dates in Oct-Dec (next FY) and Jan-Sep (current FY)
   - UUID_V5 determinism (same input always same UUID)
   - CASE WHEN with true/false/null conditions
   - PII redaction for EIN and DOB patterns
   - Charge number validation

Write a CHANGES.md and unified diff.
```

---

## Prompt 18: Triage Security Hardening

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 2 (before hub connection)

### Prompt

```
Security audit identified 3 critical, 5 high, and 4 medium findings
in the Triage codebase. Fix all of them.

CRITICAL FIXES:

1. Move SEARCH_KEY to Key Vault retrieval:
   In case-processor-function/CaseFileProcessor/__init__.py (line 50-51):
   - Replace: SEARCH_KEY = os.environ["SEARCH_KEY"]
   - With: Key Vault retrieval using SecretClient, same pattern as
     other secrets in the file (AzureOpenAIKey retrieval at line 265)
   - Fail startup if secret not available in production

2. Move MCP_WEBHOOK_SECRET to Key Vault retrieval:
   In triage_webapp/triage_app.py (line 211-213):
   - Replace: mcp_webhook_secret = os.environ.get("MCP_WEBHOOK_SECRET", "")
   - With: Key Vault retrieval. Fail startup in production if empty.
   - Validate minimum length (32 chars) same as ADR pattern

3. Audit and fix OData sanitization consistency:
   In shared/utils/ai_audit_logger.py (line 318):
   - Apply sanitize_odata_value() to partition_key before building
     OData filter string
   - Audit ALL Azure Table Storage query construction across the codebase
   - Ensure sanitize_odata_value() is called on every user-influenced
     value used in OData filters
   - Add unit tests for OData injection scenarios (single quotes,
     logical operators, null bytes)

HIGH FIXES:

4. Pin all dependencies in requirements.txt files:
   - triage_webapp/requirements.txt: pin every package to exact version
   - case-processor-function/requirements.txt: pin every package
   - Run pip freeze to get current versions, lock them
   - Add pip-audit to CI pipeline (if not already present)

5. Switch OpenAI to managed identity token provider:
   In case-processor-function/CaseFileProcessor/__init__.py (line 265-270):
   - Replace api_key=openai_api_key with azure_ad_token_provider
   - Use DefaultAzureCredential to acquire token for
     cognitiveservices.azure.us scope
   - Same pattern as foundry_model_provider.py line 231

6. Move MSAL token cache to server-side session store:
   In triage_webapp/auth.py (line 39-50):
   - Replace session["token_cache"] with Redis-backed session storage
   - Use Flask-Session with Redis backend (REDIS_URL env var)
   - Session cookie contains only session ID, not serialized token cache
   - Fallback to filesystem sessions for local dev

7. Hash IP addresses in audit logs:
   In triage_webapp/audit.py (line 77):
   - Replace: "ClientIP": request.remote_addr
   - With: "ClientIP": hash_value(request.remote_addr, salt)
   - Use same STATS_HASH_SALT as StructuredLogger

8. HTML-escape AI responses before storage:
   In shared/utils/ai_audit_logger.py (line 142-231):
   - Apply html.escape() to ai_response content before writing to
     Table Storage and Blob
   - Document that consumers must still escape before rendering

9. Add per-file size limits on batch uploads:
   In triage_webapp/blueprints/cases.py (line 60-124):
   - Check individual file size before adding to processing ZIP
   - Reject files over 10MB individually
   - Stream ZIP extraction instead of loading into memory
   - Add total upload rate limiting (e.g., 10 uploads per minute per user)

MEDIUM FIXES:

10. Fix timezone inconsistency:
    - Search for all datetime.utcnow() calls, replace with
      datetime.now(timezone.utc)
    - Add pre-commit check to flag utcnow() usage

11. Add generic error handlers:
    In triage_webapp/triage_app.py:
    - Add @app.errorhandler(500) that returns generic JSON error
    - Add @app.errorhandler(404) and @app.errorhandler(403)
    - Never expose stack traces regardless of config

12. Hash PII in direct log messages:
    Search all blueprints for logger.error/warning/info calls that
    include user_name, email, or IP without hashing. Apply hash_value()
    to all user identifiers in log messages.

13. Sign learning queue messages:
    In triage_webapp/blueprints/api_mcp.py (line 197-207):
    - Compute HMAC-SHA256 of message JSON using Key Vault secret
    - Include signature as a field in the message
    - Verify signature in learning processor before applying corrections

Write a CHANGES.md and unified diff.
```

---

## Prompt 19: ADR Security Hardening

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 2 (before hub connection)

### Prompt

```
Security audit found 0 critical but 3 high and 7 medium findings in ADR.
The codebase is the strongest of the four repos. These are hardening fixes.

HIGH FIXES:

1. Remove unsafe-inline from CSP style-src:
   In adr_webapp/mediation_app.py (line 455-484):
   - Remove "'unsafe-inline'" from style-src directive
   - Extract any inline styles to external CSS files
   - If framework requires inline styles, use nonce-based CSP:
     generate a nonce per request, add to CSP header, apply to
     style tags
   - Test all pages to verify no style regressions

2. Validate MIME type matches file extension:
   In adr_webapp/mediation_app.py (line 4349-4351):
   - When mime_type == 'application/octet-stream', do NOT allow upload
     based on extension alone
   - Require that detected MIME type matches the claimed extension
   - Build a MIME-to-extension mapping and reject mismatches
   - Allow override only for known safe edge cases (e.g., .docx sometimes
     detected as application/octet-stream), documented in code

3. Document SameSite=Lax as accepted risk:
   In adr_webapp/mediation_app.py (line 501-506):
   - Add an Architectural Decision Record (ADR) in docs/ explaining:
     why SameSite=Lax is used (OIDC form_post compatibility),
     what the CSRF mitigation is (Flask-WTF tokens on all state-changing ops),
     when to revisit (if OIDC flow changes to code+PKCE)

MEDIUM FIXES:

4. Tighten email validation:
   In adr_webapp/routes/api_mcp.py (line 530):
   - Replace regex with email-validator library, or use stricter regex:
     r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
   - Reject emails shorter than 5 characters total

5. Add charge number format validation:
   In adr_webapp/routes/api_mcp.py (line 324):
   - After sanitization, validate charge_number matches EEOC format
   - Regex: ^[A-Z0-9\-]{3,25}$
   - Return 400 Bad Request on invalid format

6. Add per-file size validation on uploads:
   In adr_webapp/mediation_app.py (line 495):
   - Before uploading to blob, check individual file size
   - Reject files over 10MB
   - Return user-friendly error message

7. Make session timeout configurable:
   In adr_webapp/mediation_app.py (line 545):
   - Read from env: SESSION_TIMEOUT_MINUTES (default: 30)
   - app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(minutes=int(timeout))

8. Add test mode production guard:
   In adr_webapp/mediation_app.py startup:
   - If TEST_MODE_ENABLED and environment is production, log CRITICAL
     warning and refuse to start
   - Detect production via FLASK_ENV, WEBSITE_SITE_NAME, or similar
   - Allow override with explicit TEST_MODE_FORCE=true for staging

9. Re-validate webhook secret on each use:
   In adr_webapp/mcp_event_dispatcher.py:
   - In _get_webhook_secret(), check length >= 32 before returning
   - If length < 32, log error and skip event dispatch (don't crash)

10. Explicit token expiry verification:
    In adr_webapp/mediation_app.py (jwt.decode call):
    - Explicitly pass options={'verify_exp': True} to jwt.decode()
    - Add comment documenting that this is intentional defense-in-depth

Write a CHANGES.md and unified diff. Do not touch any code outside the
files listed above.
```

---

## Prompt 20: Triage AI/LLM and Operational Hardening

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (before production)

### Prompt

```
Additional security hardening for Triage's AI pipeline and operational
infrastructure. These are medium-severity findings from the security audit.

1. Enhance prompt injection detection:
   In case-processor-function/CaseFileProcessor/__init__.py (line 289-300):
   - Expand PROMPT_INJECTION_RE to include additional patterns:
     "system prompt", "you are", "act as", "pretend", "roleplay",
     "new instructions", "override", "bypass"
   - Add entropy-based detection: if a text chunk has unusually high
     instruction-like density (> 5 imperative verbs per 100 words),
     flag for review
   - Apply detection to RAG context from Azure Search, not just input text
   - Log all detections to AI audit with category "prompt_injection_attempt"

2. Add model drift circuit breaker:
   In case-processor-function/ModelDriftDetector/__init__.py:
   - If drift_detected = True AND severity = "high" for 3 consecutive
     detection cycles, set a circuit breaker flag in systemsettings table
   - CaseFileProcessor checks circuit breaker before processing:
     if open, queue cases for manual review instead of AI classification
   - Alert via configured notification endpoint (Teams webhook or email)
   - Auto-reset circuit breaker after manual acknowledgment
   - Log circuit breaker state changes to AI audit

3. Add malware scan pre-processing gate:
   In case-processor-function/CaseFileProcessor/__init__.py:
   - Before processing a case, check ScanStatus in the blob metadata
   - If ScanStatus != "Passed", re-queue the message with a delay
     (exponential backoff: 30s, 60s, 120s, max 3 retries)
   - If scan not completed after 3 retries (15+ minutes), mark case as
     "scan_timeout" and alert for manual review
   - Never process a file that hasn't passed malware scanning

4. Make LLM options configurable:
   In case-processor-function/CaseFileProcessor/__init__.py (line 69):
   - Move LLM_OPTIONS to environment variables or Key Vault:
     LLM_TEMPERATURE (default: 0.1)
     LLM_TOP_P (default: 1.0)
     LLM_SEED (default: 42)
     LLM_STOP_SEQUENCES (default: "---,===")
   - Log active LLM options at startup for audit trail
   - Document rationale for each default in code comments

5. Add rate limiting on Stats API:
   In triage_webapp/stats/api.py:
   - Add per-API-key rate limiting: 60 requests per minute
   - Use the same rate limiting pattern as MCP endpoints
   - Return 429 Too Many Requests with Retry-After header

6. Add CSP nonce for CDN scripts:
   In triage_webapp/triage_app.py (line 73-82):
   - Add Subresource Integrity (SRI) hashes for CDN script tags
   - If feasible, serve scripts locally instead of from CDN
   - Remove unsafe-inline from style-src if possible (match ADR fix)

Write a CHANGES.md and unified diff.
```

---

## Prompt 21: ADR Horizontal Scaling Remediation

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 2 (before hub connection)

### Prompt

```
Scalability audit identified 3 blockers and 5 risks that prevent ADR from
running more than ~3 instances safely. Fix all blockers and high-risk items.

SCALING BLOCKERS:

1. Move all in-memory caches to Redis:
   In adr_webapp/mediation_app.py:
   - _ai_rate_limit_cache (lines 74-101): Move to Redis hash with 60s TTL.
     Key: "adr:ai_rate_limit". Read/write via Redis GET/SET.
   - _test_mode_cache (lines 6124-6157): Move to Redis key "adr:test_mode"
     with 60s TTL. All instances read from same Redis key.
   - _ai_chat_delay_cache (lines 6164-6229): Move to Redis key
     "adr:chat_delay" with 60s TTL.
   - _agreement_tab_cache (lines 6236-6272): Move to Redis key
     "adr:agreement_tab" with 60s TTL.
   - Pattern: Each cache becomes a Redis GET with TTL check. If expired
     or missing, query Table Storage, write to Redis with TTL, return value.
   - JWKS cache (_entra_jwks_cache at line 3451) can stay in-memory
     (read-only, identical across instances, acceptable).

2. Remove in-memory rate limiting fallback:
   In adr_webapp/common/auth_stats.py (lines 37-57):
   - Remove the in-memory dict fallback entirely
   - If Redis is unavailable, deny the request with 503 (fail-closed)
   - Log Redis connection failure as CRITICAL
   - Do NOT silently fall back to per-instance counting

3. Add distributed locking to Azure Function timer triggers:
   Create adr_functionapp/shared/distributed_lock.py:
   - Implement blob lease-based distributed locking
   - acquire_lock(lock_name, duration_seconds=60) -> lease_id or None
   - release_lock(lock_name, lease_id)
   - Uses Azure Blob Storage container "function-locks"
   - Each blob = one lock. Acquire via BlobLeaseClient.acquire_lease()
   - If lease already held, return None (another instance is running)

   Apply to ALL timer triggers:
   - MetricsRollupDaily: lock "metrics-rollup-daily"
   - MetricsRollupHourly: lock "metrics-rollup-hourly"
   - PollAutoFinalizer: lock "poll-auto-finalizer"
   - ScheduledCleanup: lock "scheduled-cleanup"
   - SendDigestEmail: lock "send-digest-email"
   - SendNotificationEmail: lock per batch
   - PollConflictChecker: lock "poll-conflict-checker"
   Pattern: acquire lock at top of main(). If None, log and return.
   Release in finally block.

SCALING RISKS:

4. Stream file uploads instead of buffering:
   In adr_webapp/mediation_app.py (line 4528):
   - Replace: blob_client.upload_blob(file.read(), overwrite=True)
   - With: blob_client.upload_blob(file.stream, overwrite=True)

5. Repartition mediation table:
   In adr_webapp/mediation_app.py (line 363):
   - Replace: PartitionKey = "activecases"
   - With: PartitionKey = case_id[:8]
   - Update all queries filtering on PartitionKey eq 'activecases'
   - Migration script to rewrite existing entities with new partition keys

6. Make event dispatcher non-blocking:
   In adr_webapp/mcp_event_dispatcher.py:
   - Remove time.sleep() from HTTPS fallback path
   - Use queue-based dispatch exclusively, remove HTTPS fallback
     or move it to a background thread

Write a CHANGES.md and unified diff.
```

---

## Prompt 22: Triage Horizontal Scaling Remediation

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 2 (before hub connection)

### Prompt

```
Scalability audit identified 5 blockers and 2 risks preventing Triage from
scaling beyond ~2 instances. Fix all blockers and high-risk items.

SCALING BLOCKERS:

1. Implement Redis-backed sessions:
   In triage_webapp/triage_app.py:
   - Add Flask-Session with Redis backend:
     app.config['SESSION_TYPE'] = 'redis'
     app.config['SESSION_REDIS'] = redis.from_url(os.environ.get('REDIS_URL'))
   - In triage_webapp/auth.py (lines 39-50): store MSAL token cache in
     Redis keyed by session ID, not serialized into cookie
   - Session cookie should contain only session ID (< 50 bytes)
   - Fallback: filesystem sessions if REDIS_URL not set (local dev only)
   - Add flask-session to requirements.txt (pinned)

2. Move in-memory caches to Redis:
   - TokenValidationCache (aad_role_validator.py line 157): Redis hash
     "triage:token:{token_hash}" with matching TTL
   - Rate limit fallback (common/auth_stats.py): remove in-memory fallback,
     require Redis, return 503 if unavailable
   - JWKS client can stay in-memory (read-only, acceptable)

3. Add distributed locking to timer functions:
   Create case-processor-function/shared/distributed_lock.py:
   - Blob lease pattern (same as ADR Prompt 21)
   - Apply to: MetricsRollupDaily, MetricsRollupHourly, ModelDriftDetector,
     RelianceScorer
   - Pattern: acquire at start, skip if held, release in finally

4. Repartition Azure Table Storage:
   - casetriage table: Replace PartitionKey = "cases" with
     PartitionKey = case_number[:8]
   - metricshourly: PartitionKey = YYYY-MM-DD-HH
   - metricsdaily: PartitionKey = YYYY-MM-DD
   - modeldrift: PartitionKey = YYYY-MM-DD
   - reliancescores: PartitionKey = YYYY-MM-DD
   - Update all queries in triage_webapp/blueprints/ and case-processor-function/
   - Migration script for existing data

5. Add OpenAI retry with exponential backoff:
   In case-processor-function/CaseFileProcessor/__init__.py:
   - Create call_openai_with_retry(messages, model, **kwargs):
     Max 3 attempts, backoff = 2^attempt + random(0,1)
     Catch openai.RateLimitError specifically
   - Add concurrency semaphore: max 5 concurrent OpenAI calls per instance
   - Apply to both Pass 1 and Pass 2 classification calls

SCALING RISKS:

6. Stream ZIP extraction:
   In triage_webapp/blueprints/cases.py (lines 75-118):
   - Replace io.BytesIO() with tempfile.NamedTemporaryFile()
   In case-processor-function/CaseFileProcessor/__init__.py (line 918):
   - Replace myblob.read() with chunked download to temp file
   - Set per-file limit: 10MB, file count limit: 100
   In triage_webapp/blueprints/library.py (lines 81-99):
   - Same streaming pattern

7. Add queue message idempotency:
   In triage_webapp/blueprints/api_mcp.py (lines 197-207):
   - Add idempotency_key: f"{case_id}:{rank}:{minute_bucket}"
   - Check before applying correction in learning processor

Write a CHANGES.md and unified diff.
```

---

## Prompt 23: UDIP Horizontal Scaling Remediation

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 1-2 (before production queries)

### Prompt

```
Scalability audit identified 2 blockers and 5 risks in UDIP. Fix all to
support 500+ concurrent MCP queries and continuous CDC ingestion.

SCALING BLOCKERS:

1. Increase PostgreSQL connection pool and deploy PgBouncer:
   In ai-assistant/app/data_access.py (lines 177-210):
   - Increase pool_size from 5 to 20, max_overflow from 10 to 30
   - With 6 pods: 300 total connections for 500 concurrent queries
   - Add PgBouncer Kubernetes deployment (deploy/k8s/pgbouncer/):
     pool_mode = transaction, max_client_conn = 500, default_pool_size = 50
   - Update set_pg_session_context() to use SET LOCAL instead of SET
     (transaction-scoped, compatible with PgBouncer transaction mode)
   - Point AI Assistant at PgBouncer, not direct PostgreSQL

2. Move rate limiting to Redis:
   In ai-assistant/app/mcp_api.py (lines 98-134):
   - Replace _api_key_request_counts dict with Redis INCR + EXPIRE
   - In ai-assistant/app/__init__.py: change RATELIMIT_STORAGE_URI default
     from "memory://" to Redis URL from REDIS_URL env var
   - Require Redis for multi-instance deployments

SCALING RISKS:

3. Add thread safety to MCP DatasetRegistry:
   In ai-assistant/app/mcp_registry.py (lines 157-195):
   - Add threading.RLock to DatasetRegistry
   - Wrap register(), unregister(), get(), list_datasets() with lock
   - Read-heavy, write-rare pattern (writes only on dbt refresh)

4. Optimize dbt refresh strategy:
   In scripts/dbt-run.sh:
   - Use incremental materialization instead of full table rebuild
   - Add --defer flag to skip unchanged models
   - Export run duration to Application Insights
   - Alert if > 20 minutes
   Consider triggering dbt on CDC batch completion instead of fixed schedule

5. Implement async embedding generation:
   In data-middleware/sync_engine.py (lines 543-604):
   - Use concurrent.futures.ThreadPoolExecutor(max_workers=4)
   - Add exponential backoff on RateLimitError (3 attempts)
   - Increase EMBEDDING_BATCH_SIZE from 16 to 64
   - Track: embeddings_generated, embeddings_failed, duration_seconds

6. Implement query result streaming:
   In ai-assistant/app/data_access.py (lines 330-340):
   - Replace list buffering with generator:
     yield dict(row._mapping) instead of rows.append()
   - Convert to list only at response serialization boundary
   - Log estimated response size in bytes

7. Deploy PostgreSQL read replica:
   - Enable read replica via Azure Database for PostgreSQL Flexible Server
   - Point reconciliation engine at replica (PG_RECONCILIATION_CONNECTION)
   - Optionally point MCP read queries at replica to reduce primary load
   - Primary: CDC writes. Replica: MCP reads + reconciliation.

Write a CHANGES.md and unified diff.
```

---

## Prompt 24: AI Assistant — Conversation Memory and Multi-Turn Context

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 2

### Prompt

```
The UDIP AI Assistant is currently a stateless single-turn query service.
Each request is independent — the AI does not see prior messages or results.
Users cannot ask follow-up questions like "break that down by region" because
the AI has no context from the previous exchange.

Transform it into a multi-turn conversational AI assistant with persistent
memory, context carryover, and an interactive query refinement loop.

CONTEXT:
- chat.py currently accepts conversation_id but never persists or loads history
- Client-side chat.js stores messages in a JavaScript array (lost on refresh)
- Azure OpenAI GPT-4o supports multi-message conversations via the messages array
- Redis sessions already configured (Flask-Session)
- Azure Table Storage already used for audit logging
- Max tokens: 2048 (configurable via OPENAI_MAX_TOKENS)

BUILD THE FOLLOWING:

1. Conversation history storage:
   Create ai-assistant/app/conversation_store.py:
   - Class ConversationStore backed by Azure Table Storage
   - Table: "aiconversations"
   - PartitionKey: user_id_hash (SHA-256 of user OID)
   - RowKey: "{conversation_id}_{message_sequence}"
   - Fields: role (system/user/assistant/tool), content (text),
     sql_generated (if any), result_summary (row count, columns),
     chart_type (if suggested), timestamp, token_count
   - Methods:
     a. create_conversation(user_id) -> conversation_id (UUID)
     b. add_message(conversation_id, role, content, metadata) -> sequence
     c. get_history(conversation_id, max_messages=20) -> List[Message]
     d. list_conversations(user_id, limit=50) -> List[ConversationSummary]
     e. delete_conversation(conversation_id, user_id)
   - PII: hash user_id before storage. Do NOT store raw SQL results —
     store only result_summary (row count, column names, chart type).
   - Retention: 90-day TTL on conversation entities (configurable).
     Conversations older than 90 days auto-purge. Audit records in
     aiassistantaudit are separate and follow NARA 7-year retention.
   - Max messages per conversation: 100 (configurable). Oldest messages
     trimmed when limit reached.

2. Context window management:
   In ai-assistant/app/chat.py:
   - Before calling Azure OpenAI, load conversation history via
     ConversationStore.get_history()
   - Build the messages array:
     [system_prompt, ...prior_messages_summary, current_user_message]
   - Implement context window fitting:
     a. Count tokens in system_prompt + current_message using tiktoken
     b. Available context = model_max_tokens - max_response_tokens - system_tokens
        (GPT-4o supports 128K context; use 100K as working limit)
     c. Fill remaining context with prior messages, newest first
     d. If prior messages exceed available context, summarize older
        messages into a single "conversation summary" message
   - The summary should include: prior questions asked, SQL generated,
     key results (row counts, notable values), chart types suggested
   - Use a lightweight summarization call (GPT-4o-mini or same model
     with low max_tokens) to compress older history

3. Follow-up question handling:
   In ai-assistant/app/chat.py:
   - When loading conversation history, the AI naturally understands
     follow-ups because it sees prior messages in the messages array
   - Add explicit handling for anaphora resolution:
     If user message contains "that", "it", "those", "the same",
     "break down", "drill into", "more detail" without a subject,
     AND prior message exists with SQL results:
     → Inject a context hint: "The user is referring to the previous
       query result which returned {summary}. The SQL was: {prior_sql}"
   - This helps the AI generate follow-up SQL that builds on prior queries
     (e.g., adding GROUP BY region to the previous SELECT)

4. Query refinement loop:
   In ai-assistant/app/chat.py:
   - When SQL validation fails or query execution errors:
     a. Store the error as an assistant message in conversation history
     b. Return a structured response indicating error + suggestion:
        {"error": true, "message": "...", "suggestion": "Try asking..."}
     c. On the next user message, the AI sees the prior error in context
        and can generate a corrected query
   - When results are empty:
     a. Return suggestion: "No results found. Try broadening the date range
        or removing the region filter."
     b. The AI sees this in the next turn and adjusts accordingly
   - When cost estimation exceeds threshold:
     a. Return: "This query is too expensive. Would you like me to add a
        date range filter to narrow it down?"
     b. Store as assistant message; user's next message is a refinement

5. Conversation management API:
   Add endpoints to ai-assistant/app/chat.py (or new file conversation_api.py):
   - GET /ai/conversations — list user's conversations (last 50)
   - GET /ai/conversations/{id} — load full conversation history
   - DELETE /ai/conversations/{id} — delete a conversation
   - POST /ai/conversations — create new conversation (returns ID)
   - These endpoints use the same auth as /ai/query

6. Update chat UI:
   In ai-assistant/app/templates/chat.html and static/js/chat.js:
   - Add conversation sidebar: list prior conversations, click to load
   - "New conversation" button that creates a fresh conversation_id
   - On page load, restore last active conversation from API
   - Show conversation title (auto-generated from first user message)
   - Messages persist across page refreshes (loaded from API, not memory)

7. Reasoning and explanation:
   - Add a "explain" tool that the AI can invoke:
     When user asks "why did you write that query?" or "explain",
     the AI returns its reasoning: which metric definition it used,
     which tables it joined, why it filtered on those columns
   - Implement as a system prompt instruction: "When asked to explain,
     describe your reasoning step by step, referencing the metric
     definitions and schema you used."

8. Token usage tracking:
   - Track tokens per message (prompt + completion) via tiktoken
   - Store in conversation metadata
   - Track cumulative tokens per conversation
   - Track daily token usage per user (for cost monitoring)
   - Store in Azure Table Storage: "aitokenusage" table
   - Surface in /ai/conversations response: total_tokens per conversation

Write a CHANGES.md and unified diff.
```

---

## Prompt 25: AI Assistant — Interactive Visualization Generation

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 2

### Prompt

```
The AI Assistant currently suggests a chart type as a string ("bar", "line",
"pie") but does not generate actual visualizations. Users see raw tabular
data and must open Superset separately for charts. Add interactive
visualization generation directly in the chat response.

CONTEXT:
- chat.py has _suggest_chart_type() that analyzes column types and returns a string
- Client-side chat.js renders result tables with CSV export
- No visualization libraries are installed (no plotly, altair, etc.)
- The AI returns structured JSON with columns, rows, and suggested chart_type
- Azure OpenAI can generate chart specifications if asked

APPROACH: Generate chart specifications server-side (Vega-Lite JSON), render
client-side with Vega-Embed. This avoids server-side image generation, works
in Section 508 accessible browsers, and produces interactive charts.

BUILD THE FOLLOWING:

1. Add Vega-Lite chart specification generation:
   Create ai-assistant/app/chart_generator.py:
   - Function: generate_chart_spec(columns, rows, chart_type, title) -> dict
   - Accepts the query result data and suggested chart type
   - Generates a Vega-Lite JSON specification:
     a. "bar" → horizontal or vertical bar chart
        - X axis: first categorical column
        - Y axis: first numeric column
        - Color: second categorical column (if present)
     b. "line" → time series line chart
        - X axis: date/year column (sorted)
        - Y axis: numeric column(s)
        - Multiple lines if GROUP BY produces series
     c. "pie" → donut chart
        - Theta: numeric column
        - Color: categorical column
     d. "table" → no chart, just formatted table
     e. "scatter" → scatter plot (two numeric columns)
     f. "heatmap" → for cross-tabulations (basis × region, etc.)
     g. "stacked_bar" → for multi-category breakdowns
   - Auto-detect best chart type if none suggested:
     - 1 categorical + 1 numeric → bar
     - date/year + numeric → line
     - 2 numeric → scatter
     - 1 categorical + 1 numeric (< 8 categories) → pie
     - 2 categorical + 1 numeric → heatmap or stacked bar
   - Apply EEOC branding: color palette matching existing Superset themes
   - Section 508 compliance: include alt text description of the chart
     in the spec (description field in Vega-Lite)
   - Max data points: 1000 (aggregate if more)

2. Add AI-driven chart customization:
   In ai-assistant/app/chat.py:
   - Add a new tool for the AI: "create_visualization"
     Input: { chart_type, title, x_column, y_column, color_column,
              filter, aggregation, sort_order }
     Output: Vega-Lite JSON spec
   - The AI can invoke this tool when the user asks:
     "Show me a chart of...", "Graph the...", "Visualize...",
     "Create a bar chart of...", "Plot..."
   - The AI decides the chart parameters based on the question and data
   - Include the Vega-Lite spec in the response JSON:
     {"text": "...", "sql": "...", "data": [...], "chart": {vega_lite_spec}}

3. Client-side chart rendering:
   In ai-assistant/app/templates/chat.html:
   - Add Vega-Embed library (CDN or local): vega, vega-lite, vega-embed
   - In static/js/chat.js:
     When response contains "chart" field:
     a. Create a chart container div in the message area
     b. Call vegaEmbed(container, spec, {actions: true})
     c. Actions: export PNG, export SVG, view source data
     d. Chart is interactive: hover tooltips, click to filter
   - Add chart/table toggle button: users can switch between chart and
     raw table view for the same data
   - Responsive: charts resize with the chat panel width

4. Data export enhancements:
   In static/js/chat.js:
   - Existing CSV export: keep as-is
   - Add Excel export: generate .xlsx using SheetJS (client-side library)
   - Add PNG chart export: via Vega-Embed's built-in export action
   - Add "Copy to clipboard" for both table data and chart image
   - Add "Share chart" that generates a shareable URL with the chart spec
     encoded (optional, requires backend endpoint to store specs)

5. Chart history in conversation:
   - When a chart is generated, store the Vega-Lite spec in conversation
     history (ConversationStore from Prompt 24)
   - On conversation reload, re-render charts from stored specs
   - Users can ask follow-ups about charts: "Add a trend line to that",
     "Change it to a pie chart", "Remove the Southeast region"
   - The AI modifies the prior spec based on the follow-up instruction

6. Summary statistics:
   In ai-assistant/app/chart_generator.py:
   - Function: generate_summary_stats(columns, rows) -> dict
   - For each numeric column: count, mean, median, min, max, std dev
   - For each categorical column: unique count, top 5 values by frequency
   - For date columns: range (earliest to latest), density
   - Return as structured JSON for display above/below the chart
   - The AI can reference these stats when explaining results

7. Dependencies:
   - No new Python server-side dependencies (Vega-Lite specs are JSON dicts)
   - Client-side: add to templates/chat.html:
     vega@5 (CDN), vega-lite@5 (CDN), vega-embed@6 (CDN)
     Optional: sheetjs (xlsx export)
   - Add SRI hashes for all CDN scripts

Write a CHANGES.md and unified diff.
```

---

## Prompt 26: AI Assistant — Dynamic Dashboard Creation and Superset Integration

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 3

### Prompt

```
The AI Assistant can generate individual charts (Prompt 25). Now add the
ability to create and manage multi-chart dashboards, and integrate with
Apache Superset for persistent dashboard sharing.

CONTEXT:
- Superset is deployed separately (deploy/k8s/superset/)
- Superset has a REST API for programmatic dashboard creation
- chat.py already has _execute_get_dashboards() returning a static catalog
- Vega-Lite charts are generated per Prompt 25
- Conversation history persists per Prompt 24

BUILD THE FOLLOWING:

1. In-chat dashboard composition:
   Create ai-assistant/app/dashboard_builder.py:
   - Class DashboardBuilder:
     a. create_dashboard(title, description) -> dashboard_id
     b. add_panel(dashboard_id, chart_spec, position, size) -> panel_id
     c. update_layout(dashboard_id, layout) -> updated layout
     d. get_dashboard(dashboard_id) -> full dashboard with all panels
     e. list_dashboards(user_id) -> user's dashboards
     f. delete_dashboard(dashboard_id)
   - Storage: Azure Table Storage "aidashboards" table
     PartitionKey: user_id_hash, RowKey: dashboard_id
     Content: JSON with title, panels[], layout, created_at, updated_at
   - Panel layout: CSS Grid-based (row, column, width, height)
   - Default layouts:
     - 1 chart → full width
     - 2 charts → side by side
     - 3 charts → 2 top + 1 bottom
     - 4 charts → 2×2 grid

2. AI tool for dashboard creation:
   In ai-assistant/app/chat.py:
   - Add tools the AI can invoke:
     a. "create_dashboard" → creates a new dashboard from conversation
     b. "add_to_dashboard" → adds the current chart to an existing dashboard
     c. "show_dashboard" → renders a dashboard in the chat
   - Conversation flow:
     User: "Create a dashboard with settlement rates and case volume by region"
     AI: Generates 2 queries, 2 charts, assembles into dashboard
     User: "Add a trend line for the last 5 years"
     AI: Generates 3rd chart, adds to dashboard
     User: "Save this dashboard"
     AI: Persists to DashboardBuilder storage

3. Dashboard rendering UI:
   Create ai-assistant/app/templates/dashboard_view.html:
   - CSS Grid layout for multiple Vega-Lite charts
   - Each panel: chart + title + data table toggle
   - Dashboard title and description
   - Print-friendly CSS (@media print)
   - Section 508: ARIA landmarks, chart descriptions, keyboard navigation
   Add route: GET /ai/dashboards/{id} → renders dashboard_view.html

4. Superset integration (export to Superset):
   Create ai-assistant/app/superset_client.py:
   - Class SupersetClient:
     a. Connect to Superset REST API (SUPERSET_API_URL env var)
     b. Auth: Superset service account credentials from Key Vault
     c. create_chart(sql_query, chart_type, title) -> chart_id
        Maps Vega-Lite spec to Superset chart config (viz_type, params)
     d. create_dashboard(title, chart_ids, layout) -> dashboard_url
     e. share_dashboard(dashboard_id, users) -> share link
   - Feature-gated: SUPERSET_INTEGRATION_ENABLED (default: false)
   - When enabled, "export to Superset" button appears on dashboards
   - The export creates a persistent Superset dashboard that auto-refreshes
     (Superset queries the database directly, not the AI)

5. Scheduled dashboard refresh:
   - Dashboards created via the AI use saved SQL queries
   - Add a "refresh" button that re-executes all queries and updates charts
   - Optional: schedule auto-refresh (daily, weekly) via Azure Function
     timer trigger with dashboard_id and query list
   - Refresh respects RLS: queries run with the dashboard owner's permissions

6. Dashboard sharing:
   - Each dashboard gets a shareable URL: /ai/dashboards/{id}
   - Access control: only the creator and explicitly shared users can view
   - Share via: add user email → lookup Entra ID → grant viewer access
   - Shared dashboards render with the VIEWER's RLS context (not creator's)
   - Audit: log all dashboard views and shares

7. Configuration:
   - DASHBOARD_STORAGE_TABLE: "aidashboards" (default)
   - DASHBOARD_MAX_PANELS: 8 (default)
   - DASHBOARD_RETENTION_DAYS: 365 (default)
   - SUPERSET_API_URL: Superset REST API base URL
   - SUPERSET_INTEGRATION_ENABLED: false (default)

Write a CHANGES.md and unified diff.
```

---

## Prompt 27: Test Coverage for All New Modules (All Repos)

**Repositories:** All — run per repo in separate sessions
**Owner:** All teams
**Phase:** Parallel with deployment

### Prompt (UDIP — run in eeoc-data-analytics-and-dashboard/)

```
The cross-ecosystem audit found 5 new modules in UDIP with zero test
coverage. Write comprehensive unit tests for each. Follow the existing
test patterns in ai-assistant/tests/ and data-middleware/tests/.

Use the existing conftest.py fixtures (ai-assistant/tests/conftest.py)
which set up environment variables and mock Azure credentials.

1. ai-assistant/tests/test_conversation_store.py:
   Test ConversationStore class against mocked Azure Table Storage.
   - test_create_conversation: returns UUID, stores system message
   - test_add_message: increments sequence, stores role + content
   - test_get_history: returns messages in order, respects max_messages
   - test_get_history_empty: returns empty list for unknown conversation_id
   - test_list_conversations: returns summaries sorted by recency
   - test_delete_conversation: removes all messages for conversation_id
   - test_max_messages_trim: oldest messages removed when limit exceeded
   - test_pii_hashing: user_id is hashed before storage, never plaintext
   - test_90_day_ttl: entities created with appropriate TTL metadata
   Mock: azure.data.tables.TableClient (upsert_entity, query_entities, delete_entity)

2. ai-assistant/tests/test_chart_generator.py:
   Test chart spec generation with various data shapes.
   - test_bar_chart: 1 categorical + 1 numeric → valid Vega-Lite bar spec
   - test_line_chart: date column + numeric → time series spec
   - test_pie_chart: < 8 categories + numeric → donut spec
   - test_scatter: 2 numeric columns → scatter spec
   - test_heatmap: 2 categorical + 1 numeric → heatmap spec
   - test_auto_detect_bar: auto-detection picks bar for categorical + numeric
   - test_auto_detect_line: auto-detection picks line for date + numeric
   - test_empty_data: returns None or empty spec, does not crash
   - test_max_data_points: data exceeding 1000 rows is aggregated
   - test_section_508_alt_text: spec includes description field
   - test_summary_stats: numeric columns get count, mean, median, min, max

3. ai-assistant/tests/test_dashboard_builder.py:
   Test dashboard CRUD and layout logic.
   - test_create_dashboard: returns dashboard_id, stores metadata
   - test_add_panel: adds chart spec to dashboard, assigns position
   - test_get_dashboard: returns all panels with layout
   - test_default_layouts: 1 panel → full width, 2 → side by side, 4 → grid
   - test_max_panels: rejects panel when DASHBOARD_MAX_PANELS exceeded
   - test_delete_dashboard: removes dashboard and all panels
   - test_list_dashboards: returns user's dashboards only (not other users')
   Mock: azure.data.tables.TableClient

4. data-middleware/tests/test_eventhub_source.py:
   Test EventHubSourceDriver against mocked Event Hub consumer.
   - test_consume_create_event: Debezium create (op=c) yields row dict
   - test_consume_update_event: Debezium update (op=u) yields after image
   - test_consume_delete_event: Debezium delete (op=d) yields tombstone
   - test_consume_snapshot: Debezium snapshot (op=r) yields row dict
   - test_offset_commit_on_success: offset committed after successful upsert
   - test_offset_not_committed_on_failure: offset NOT committed if upsert fails
   - test_dead_letter_on_transform_error: malformed event logged to dead letter
   - test_connection_retry: reconnects after transient Event Hub failure
   - test_empty_poll: returns empty list when no new events
   Mock: azure.eventhub.EventHubConsumerClient

5. data-middleware/tests/test_reconciliation.py:
   Test ReconciliationEngine against mocked SQL Server + PostgreSQL.
   - test_reconcile_matching: IDR and analytics have same row count → no backfill
   - test_reconcile_missing_records: IDR has rows analytics doesn't → backfill triggered
   - test_reconcile_threshold: discrepancy < 0.1% → no alert; > 0.1% → alert
   - test_checksum_mismatch: sample checksums differ → records flagged
   - test_backfill_uses_yaml: backfill applies existing sqlserver_*.yaml transform
   - test_reconciliation_log: results written to middleware.reconciliation_log
   - test_idr_unreachable: logs error, does not crash, skips reconciliation
   Mock: pyodbc.connect (IDR), psycopg2.connect (analytics)

Write tests only. Do not modify any source code.
```

### Prompt (ADR — run in eeoc-ofs-adr/)

```
Write unit tests for 3 uncovered new modules in ADR.

1. adr_functionapp/tests/test_distributed_lock.py:
   Test blob lease-based distributed locking.
   - test_acquire_lock_success: returns lease_id when blob available
   - test_acquire_lock_already_held: returns None when another instance holds lease
   - test_release_lock: releases lease, blob becomes available
   - test_lock_expires: after duration_seconds, lock auto-releases
   - test_lock_blob_creation: creates lock blob if it doesn't exist
   - test_concurrent_acquire: only one of two concurrent acquire calls succeeds
   Mock: azure.storage.blob.BlobLeaseClient, BlobClient

2. adr_functionapp/tests/test_udip_analytics_push.py:
   Test the UDIPAnalyticsPush Azure Function.
   - test_push_daily_metrics: reads from metricsrollupdaily, transforms, posts to UDIP
   - test_push_reliance_scores: reads from reliancescores, transforms, posts
   - test_push_model_drift: reads from modeldrift, transforms, posts
   - test_udip_unreachable: logs warning, does not crash, continues with next dataset
   - test_dataset_push_failure: one dataset fails, others still pushed
   - test_empty_records: no records in source → skip push, log info
   - test_auth_token_acquisition: managed identity token acquired for UDIP scope
   Mock: requests.post (UDIP ingest), azure.data.tables.TableClient (source tables)

3. adr_functionapp/tests/test_arc_sync_importer.py:
   Test ARCSyncImporter with new ARC Integration API endpoint.
   - test_sync_new_endpoint: calls /arc/v1/mediation/eligible-cases when configured
   - test_sync_legacy_fallback: calls old endpoint when new URL not configured
   - test_pagination: follows next_page links until exhausted
   - test_watermark_update: updates watermark after successful sync
   - test_managed_identity_auth: uses DefaultAzureCredential for new endpoint
   - test_empty_response: no new cases → watermark unchanged, no errors
   Mock: requests.get (ARC API), azure.data.tables.TableClient (case storage)

Write tests only. Do not modify any source code.
```

### Prompt (Triage — run in eeoc-ofs-triage/)

```
Write unit tests for 3 uncovered new modules in Triage.

1. triage_webapp/tests/test_arc_lookup.py:
   Test ARC Integration API charge metadata lookup.
   - test_lookup_success: valid charge number → returns metadata dict
   - test_lookup_not_found: unknown charge → returns None
   - test_lookup_timeout: API timeout after 10s → returns None, logs warning
   - test_lookup_disabled: ARC_LOOKUP_ENABLED=false → returns None without API call
   - test_charge_number_validation: invalid format → returns None, logs warning
   - test_auth_token: managed identity token acquired for ARC scope
   - test_response_fields: response contains charge_number, respondent_name,
     basis_codes, issue_codes, statute_codes, office_code, filing_date, status
   Mock: requests.get (ARC API), azure.identity.DefaultAzureCredential

2. case-processor-function/tests/test_udip_analytics_push.py:
   Test Triage's UDIPAnalyticsPush Azure Function.
   - test_push_daily_metrics: reads metricsdaily, transforms, posts with "dataset" key
   - test_push_correction_flows: reads modeldrift, transforms, posts
   - test_push_reliance_scores: reads reliancescores, transforms, posts
   - test_payload_key_is_dataset: verify payload uses "dataset" not "target_table"
   - test_udip_unreachable: logs warning, continues with next dataset
   - test_empty_records: skip push for empty source tables
   Mock: requests.post (UDIP ingest), azure.data.tables.TableClient

3. case-processor-function/tests/test_openai_retry.py:
   Test OpenAI exponential backoff retry logic.
   - test_success_first_attempt: returns response immediately, no retry
   - test_retry_on_rate_limit: 429 → backoff → retry → success on 2nd attempt
   - test_max_retries_exceeded: 3 consecutive 429s → raises RateLimitError
   - test_backoff_timing: verify exponential backoff (2^attempt + jitter)
   - test_non_rate_limit_error: other exceptions propagate immediately, no retry
   - test_semaphore_limits_concurrency: max 5 concurrent calls enforced
   Mock: openai.AzureOpenAI.chat.completions.create

Write tests only. Do not modify any source code.
```

### Prompt (OGC Trial Tool — run in eeoc-ogc-trialtool/)

```
Write unit tests for 2 uncovered new modules in OGC Trial Tool.

1. tests/test_mcp_server.py:
   Test the MCP JSON-RPC server endpoint.
   - test_initialize: returns server info with protocol version 2025-03-26
   - test_tools_list: returns 3 tools (trial_get_case_status, trial_analyze_case, trial_list_cases)
   - test_tools_call_get_status: invokes trial_get_case_status, returns case data
   - test_tools_call_analyze: invokes trial_analyze_case, returns analysis with citations
   - test_tools_call_list: invokes trial_list_cases, returns case list
   - test_auth_required: request without bearer token → 401
   - test_invalid_role: token with wrong role → 403
   - test_request_id_echo: X-Request-ID header echoed in response
   - test_feature_gate: MCP_ENABLED=false → 404 on /mcp
   - test_invalid_jsonrpc: malformed request → JSON-RPC error response
   Mock: Flask test client, JWT token generation

2. tests/test_auth_flow.py:
   Test Entra ID Government OIDC auth replacement.
   - test_login_redirect: /auth/login redirects to Entra ID authorize endpoint
   - test_callback_success: valid code → session created with user info
   - test_callback_invalid_code: bad code → redirect to login with error
   - test_logout: clears session, redirects to Entra ID logout
   - test_role_from_groups: ATTORNEY_GROUP_ID → attorney role
   - test_admin_role: ADMIN_GROUP_ID → admin role
   - test_login_required_decorator: unauthenticated request → redirect to login
   - test_session_timeout: expired session → redirect to login
   Mock: msal.ConfidentialClientApplication, Flask test client

Write tests only. Do not modify any source code.
```

---

## Prompt 28: ADR Production Deployment Manifests and Public-Facing Scaling

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 2

### Prompt

```
ADR Mediation Platform currently has no production deployment manifests.
It runs on Azure App Service with default scaling. ADR is PUBLIC-FACING:
external parties (charging parties, respondents, attorneys) access it via
Login.gov OIDC. Expected load: 2000 new cases/month, ~6000 active cases
at any time, with unpredictable daily usage by external parties.

This means potentially 18,000+ registered users (3 parties per case ×
6000 cases) with unknown concurrency patterns. Design for sustained 500
concurrent users with burst to 2000.

CREATE THE FOLLOWING:

1. deploy/k8s/adr-webapp/deployment.yaml:
   - Container: adr-webapp (gunicorn + Flask)
   - Initial replicas: 3
   - CPU request: 500m, limit: 2 cores
   - Memory request: 1Gi, limit: 4Gi
   - Gunicorn: 4 workers, gevent worker class, 120s timeout
   - Liveness probe: /healthz, 30s interval
   - Readiness probe: /healthz, 10s interval
   - Environment from: ConfigMap (adr-config) + Secret (adr-secrets)
   - Volume mount: /etc/adr/config (ConfigMap)

2. deploy/k8s/adr-webapp/hpa.yaml:
   - Min replicas: 3 (high availability for public-facing)
   - Max replicas: 12
   - CPU threshold: 65% (lower than internal apps — headroom for burst)
   - Memory threshold: 75%
   - Scale-up: max 4 pods per 60 seconds (handle sudden traffic)
   - Scale-down: max 1 pod per 300 seconds (conservative scale-down)

3. deploy/k8s/adr-webapp/service.yaml:
   - Internal ClusterIP service
   - Port 8000 → target 8000

4. deploy/k8s/adr-webapp/ingress.yaml:
   - Azure Application Gateway Ingress Controller (AGIC)
   - TLS termination at gateway
   - WAF v2 policy: OWASP 3.2 ruleset enabled
   - Rate limiting at edge: 100 requests/minute per IP
   - Bot protection enabled
   - DDoS protection standard enabled

5. deploy/k8s/adr-functionapp/deployment.yaml:
   - Container: adr-functionapp (Azure Functions custom handler)
   - Initial replicas: 2
   - CPU request: 250m, limit: 1 core
   - Memory request: 512Mi, limit: 2Gi
   - Env: all function configuration from ConfigMap

6. deploy/k8s/adr-functionapp/hpa.yaml:
   - Min replicas: 2
   - Max replicas: 6
   - CPU threshold: 70%

7. deploy/k8s/adr-redis/deployment.yaml (or reference Azure Cache for Redis):
   - If self-managed: Redis 7.x with persistence (AOF + RDB)
   - Memory: 2Gi (sessions for 18,000 users × ~1KB per session = 18MB
     + rate limit buckets + feature flag cache)
   - Recommended: Azure Cache for Redis Premium (P1) for VNet integration
     and data persistence. Document as an Azure resource, not K8s deployment.

8. deploy/k8s/adr-webapp/configmap.yaml:
   - SESSION_TIMEOUT_MINUTES: 30
   - MAX_CONTENT_LENGTH: 52428800 (50MB)
   - REDIS_URL: (from secret)
   - KEY_VAULT_URI: (from secret)
   - ARC_INTEGRATION_API_URL: (internal service URL)
   - UDIP_INGEST_URL: (internal service URL)
   - MCP_ENABLED: "true"
   - MCP_PROTOCOL_ENABLED: "true"

9. deploy/azure/front-door-profile.bicep (or ARM template):
   Azure Front Door configuration for public-facing ADR:
   - Origin group: ADR Application Gateway
   - Custom domain: adr.eeoc.gov (or similar)
   - TLS: managed certificate
   - WAF policy: OWASP 3.2, rate limiting, bot protection, geo-filtering
   - Caching: static assets (CSS, JS, images) cached at edge, 1 hour TTL
   - Health probe: /healthz every 30 seconds
   - Session affinity: disabled (Redis sessions handle this)
   - Compression: enabled for text/html, text/css, application/javascript

10. deploy/azure/table-storage-partitioning.md:
    Document the partition key migration strategy for 6000 active cases:
    - mediationcases: PartitionKey changes from "activecases" to case_id[:8]
      (already defined in Prompt 21, document the migration procedure here)
    - At 6000 active cases with PartitionKey = case_id[:8]:
      ~6000 / 16^8 = effectively unique per case. No hot partition.
    - Query patterns:
      a. Single case lookup: PartitionKey eq '{id[:8]}' AND RowKey eq '{id}' — fast
      b. List all active cases: cross-partition query with status filter — slower
         but acceptable at 6000 entities
      c. List by mediator: cross-partition with mediator_id filter
    - For the "list all" pattern, maintain a secondary index table:
      mediationcases_index with PartitionKey = "active", RowKey = case_id
      Updated on case create/close. Queries hit the index first, then
      look up full case data by case_id.

Write a CHANGES.md. Include all deployment files with complete contents.
```

---

## Prompt 29: Triage Production Deployment Manifests

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 2

### Prompt

```
OFS Triage has no production deployment manifests. Create Kubernetes
deployment configs with autoscaling for the web app and function app.
Triage is internal-facing (staff only, no public access).

Expected load: analysts uploading 50-100 cases per day, batch uploads of
up to 1000 cases. AI classification takes 30-60 seconds per case.

1. deploy/k8s/triage-webapp/deployment.yaml:
   - Container: triage-webapp (gunicorn + Flask)
   - Initial replicas: 2
   - CPU request: 250m, limit: 1 core
   - Memory request: 512Mi, limit: 2Gi
   - Gunicorn: 2 workers, gevent, 120s timeout
   - Liveness/readiness probes: /healthz

2. deploy/k8s/triage-webapp/hpa.yaml:
   - Min replicas: 2, max: 6
   - CPU threshold: 70%, memory: 80%

3. deploy/k8s/triage-functionapp/deployment.yaml:
   - Container: triage-functionapp
   - Initial replicas: 2
   - CPU request: 500m, limit: 2 cores (AI classification is CPU-intensive)
   - Memory request: 1Gi, limit: 4Gi (ZIP extraction memory)

4. deploy/k8s/triage-functionapp/hpa.yaml:
   - Min replicas: 2, max: 8
   - CPU threshold: 60% (lower threshold — AI workload spikes fast)
   - Scale-up: 2 pods per 30 seconds (batch upload bursts)

5. deploy/k8s/triage-webapp/configmap.yaml:
   - All application configuration
   - MCP_ENABLED, MCP_SERVER_EXPOSE, ARC_LOOKUP_ENABLED flags

6. deploy/k8s/triage-webapp/ingress.yaml:
   - Internal ingress (no public access)
   - TLS within cluster

Write a CHANGES.md. Include all files.
```

---

## Prompt 30: ARC Integration API Production Deployment Manifests

**Repository:** `eeoc-arc-integration-api/`
**Owner:** Hub team
**Phase:** 1

### Prompt

```
ARC Integration API has a Dockerfile but no orchestration config.
Create Kubernetes deployment manifests. This service handles write-back
to ARC and targeted case pushes. Internal-facing only.

Expected load: ADR polls eligible-cases every 15 minutes. Triage looks up
charge metadata on upload (50-100/day). Write-backs: 2000 closures/month
plus document uploads and event logging.

1. deploy/k8s/arc-integration/deployment.yaml:
   - Container: arc-integration-api (uvicorn + FastAPI)
   - Initial replicas: 2
   - CPU request: 250m, limit: 1 core
   - Memory request: 512Mi, limit: 2Gi
   - Uvicorn: 4 workers (already in Dockerfile CMD)
   - Liveness: /healthz
   - Readiness: /healthz

2. deploy/k8s/arc-integration/hpa.yaml:
   - Min replicas: 2, max: 4
   - CPU threshold: 70%

3. deploy/k8s/arc-integration/configmap.yaml:
   - ARC_GATEWAY_URL, ARC_PREPA_URL, ARC_AUTH_URL
   - KEY_VAULT_URI, REDIS_URL
   - RATE_LIMIT_PER_MINUTE: 120
   - Cache TTL values

4. deploy/k8s/arc-integration/service.yaml:
   - ClusterIP, port 8000

Write a CHANGES.md. Include all files.
```

---

## Prompt 31: Triage Scaling Fix-Up (Incomplete Items from Prompt 22)

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 2 (before hub connection)

### Prompt

```
Post-implementation verification found 5 items from the scaling remediation
(Prompt 22) that were incomplete or not wired up. Fix all of them.

1. Wire up OpenAI retry wrapper:
   In case-processor-function/CaseFileProcessor/__init__.py:
   - The call_openai_with_retry() function exists (lines 89-125) but is
     NEVER CALLED. The actual OpenAI calls still use
     openai_client.chat.completions.create() directly.
   - Replace ALL direct OpenAI calls with call_openai_with_retry():
     a. Pass 1 classification call (~line 874)
     b. Pass 2 retry call (~line 916)
     c. Any other chat.completions.create() calls in the file
   - Verify the retry wrapper catches openai.RateLimitError and
     openai.APIError with exponential backoff

2. Repartition cases table:
   In case-processor-function/CaseFileProcessor/__init__.py (~line 998):
   - Replace: "PartitionKey": "cases"
   - With: "PartitionKey": case_number[:8].lower() if case_number else "unknown"
   - Update ALL queries in the codebase that filter on
     PartitionKey eq 'cases' for the casetriage table:
     a. triage_webapp/blueprints/cases.py — list queries
     b. triage_webapp/blueprints/api_mcp.py — MCP tool queries
     c. Any other files querying casetriage table
   - For single-case lookups: use PartitionKey eq '{case_number[:8]}'
   - For list-all queries: remove PartitionKey filter (cross-partition scan)
     or maintain a secondary index (same pattern as ADR Prompt 28 item 10)

3. Repartition metrics tables:
   In case-processor-function/MetricsRollupHourly/__init__.py (~line 232):
   - Replace: "PartitionKey": "hourly"
   - With: "PartitionKey": datetime.now(timezone.utc).strftime('%Y-%m-%d')
   In case-processor-function/MetricsRollupDaily/__init__.py (~line 270):
   - Replace: "PartitionKey": "metrics"
   - With: "PartitionKey": target_date.strftime('%Y-%m-%d')
   Update corresponding queries in stats blueprints to use date-range
   PartitionKey filters instead of PartitionKey eq 'hourly'.

4. Stream ZIP extraction in CaseFileProcessor:
   In case-processor-function/CaseFileProcessor/__init__.py (~line 1096):
   - Replace: with io.BytesIO(myblob.read()) as in_memory_zip:
   - With: download to tempfile, extract from disk:
     import tempfile
     tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
     tmp.write(myblob.read())  # still reads blob, but writes to disk
     tmp.close()
     with zipfile.ZipFile(tmp.name, 'r') as z:
         ...
     os.unlink(tmp.name)
   - This moves the ZIP from memory to disk. The blob read is unavoidable
     (Azure Functions InputStream), but the ZIP extraction works from disk
     instead of a BytesIO buffer, reducing peak memory.

5. Remove or gate the rate limit in-memory fallback:
   In triage_webapp/common/auth_stats.py:
   - The in-memory fallback was intentionally kept as a resilience pattern.
   - Change it to: if in production (detect via env), return 503 instead
     of falling back to in-memory. In dev/local, allow in-memory fallback.
   - Pattern:
     if not _redis:
         if os.environ.get("WEBSITE_SITE_NAME"):  # Azure App Service
             return False  # deny request (fail-closed in production)
         # local dev: allow in-memory fallback
         store = getattr(_rate_consume, "_buckets", {})
         ...

Write a CHANGES.md and unified diff.
```

---

## Prompt 32: ADR Graceful Degradation (Standalone Operation)

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 2 (critical — must run before any hub connections)

### Prompt

```
ADR must continue operating independently while the integration ecosystem
is brought online over the next two months. Every external dependency
(ARC Integration API, MCP Hub, UDIP ingest, Event Grid) must be optional.
If a dependency is unreachable or not yet deployed, ADR continues working
with zero impact on core mediation functionality.

Audit every integration point and ensure graceful degradation:

1. ARCSyncImporter graceful fallback:
   In adr_functionapp/ARCSyncImporter/__init__.py:
   - If ARC_INTEGRATION_API_URL is empty or not set:
     a. If ARC_API_BASE_URL (legacy) is set, use legacy endpoint
     b. If neither is set, log warning and skip sync entirely
     c. Do NOT crash the function app
   - If ARC Integration API returns error (5xx, timeout, connection refused):
     a. Log error with structured logging
     b. Skip this sync cycle
     c. Retry on next timer trigger (15 minutes)
     d. Do NOT mark cases as failed or modify any local data
   - Add: ARC_SYNC_ENABLED feature flag (default: true). When false,
     ARCSyncImporter logs info and returns immediately.

2. MCP event dispatcher graceful fallback:
   In adr_webapp/mcp_event_dispatcher.py:
   - If MCP_CALLBACK_URL is empty or not set:
     a. Log info "MCP event dispatch disabled — no callback URL configured"
     b. Events are still logged to local audit table
     c. Queue-based dispatch silently skipped
     d. Do NOT raise or crash
   - If hub is unreachable (connection refused, timeout, 5xx):
     a. Log warning with event_type and error
     b. Events accumulate in local audit only
     c. No retry queue (events are not critical path for ADR operations)
   - Add: MCP_EVENTS_ENABLED feature flag (default: false). Events only
     dispatch when explicitly enabled AND callback URL is configured.

3. UDIP analytics push graceful fallback:
   In adr_functionapp/UDIPAnalyticsPush/__init__.py:
   - If UDIP_PUSH_ENABLED is false (default): skip entirely, log info
   - If UDIP_INGEST_URL is empty: skip, log warning
   - If UDIP is unreachable: log error, skip, retry next cycle
   - Track last successful push timestamp in systemsettings table
   - If push hasn't succeeded in 48 hours: log CRITICAL for alerting
   - Do NOT affect any ADR operation if UDIP is down

4. MCP server endpoint graceful behavior:
   In adr_webapp/mcp_server.py:
   - If MCP_ENABLED is false (default): /mcp returns 404
   - If MCP_PROTOCOL_ENABLED is false: /mcp returns 404
   - When enabled, /mcp works independently of hub (direct tool calls work)
   - No dependency on hub being reachable for MCP server to function

5. ARC write-back tools graceful behavior:
   In adr_webapp/routes/api_mcp.py (or wherever write-back tools are):
   - If ARC Integration API is not configured: write-back tools return
     structured error: {"error": "ARC Integration not configured"}
   - ADR stores mediation outcomes locally regardless of ARC write-back
   - ARC write-back is fire-and-forget with retry — local data is always
     the source of truth for ADR operations

6. Feature flag defaults for standalone operation:
   Document and enforce these defaults in adr_webapp/mediation_app.py startup:

   | Flag | Default | Standalone Behavior |
   |------|---------|-------------------|
   | MCP_ENABLED | false | /mcp returns 404 |
   | MCP_PROTOCOL_ENABLED | false | MCP protocol disabled |
   | MCP_EVENTS_ENABLED | false | No event dispatch |
   | ARC_SYNC_ENABLED | true | Sync runs if URL configured |
   | UDIP_PUSH_ENABLED | false | No UDIP push |
   | ARC_LOOKUP_ENABLED | false | No ARC charge lookup |
   | ARC_WRITEBACK_ENABLED | false | No ARC write-back |

   With ALL flags at defaults, ADR operates exactly as it does today:
   staff create cases, manage mediation, close cases, upload documents.
   Zero external dependencies. Zero new failure modes.

   Each flag is independently enabled as the corresponding service comes
   online. If a service goes down, disable its flag — ADR keeps working.

7. Startup validation:
   In adr_webapp/mediation_app.py startup sequence:
   - Log the state of every integration flag at INFO level:
     "INTEGRATION_STATUS|MCP_ENABLED=false|ARC_SYNC_ENABLED=true|..."
   - If a flag is enabled but its URL is missing, log WARNING:
     "ARC_SYNC_ENABLED=true but ARC_INTEGRATION_API_URL is empty — sync will be skipped"
   - Never fail startup due to missing integration URLs

8. Health endpoint integration status:
   In the /healthz endpoint (or a new /healthz/integrations):
   - Return the status of each integration dependency:
     {"arc_sync": "disabled", "mcp_hub": "disabled", "udip_push": "disabled"}
   - When enabled: check connectivity and report "healthy" or "unreachable"
   - /healthz itself always returns 200 (ADR is healthy regardless of integrations)

Write a CHANGES.md and unified diff. This is the most important prompt
for operational stability — ADR must never go down because an integration
dependency is unavailable.
```

---

## Prompt 33: UDIP Read Replica Configuration

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 2 (before production query load)

### Prompt

```
The scaling verification found that PostgreSQL read replica support is
documented but not implemented in the application code. Add configuration
to route read queries to a replica and write operations to the primary.

1. In ai-assistant/app/data_access.py:
   - Add configuration for a read replica connection:
     PG_REPLICA_HOST (or PG_REPLICA_CONNECTION as full DSN)
     Default: empty (when empty, all queries go to primary)
   - When PG_REPLICA_HOST is set:
     a. Create a second SQLAlchemy engine: _pg_replica_engine
     b. Same pool settings as primary (pool_size=20, max_overflow=30)
     c. Same RLS session context (set_pg_session_context on checkout)
     d. Route all SELECT queries to replica engine
     e. Route all INSERT/UPDATE/DELETE to primary engine
   - In execute_governed_query(): use replica engine for reads
   - In the MCP ingest endpoint: use primary engine for writes
   - Log which engine is used: "QUERY|engine=replica" or "QUERY|engine=primary"

2. In deploy/k8s/ai-assistant/configmap.yaml:
   - Add PG_REPLICA_HOST and PG_REPLICA_PORT environment variables
   - Default: empty (primary-only mode)
   - Document: "Set these when Azure read replica is provisioned"

3. In data-middleware/sync_engine.py:
   - CDC writes always go to primary (no change needed — already does)
   - Reconciliation reads: add option to read from replica via
     PG_RECONCILIATION_CONNECTION env var
   - Default: uses primary connection (backward compatible)

4. In deploy/k8s/pgbouncer/configmap.yaml:
   - Add a second database section for the replica:
     DB_REPLICA_HOST, DB_REPLICA_PORT
   - PgBouncer can route to different backends per database name:
     "udip_analytics" → primary, "udip_analytics_ro" → replica
   - Application connects to "udip_analytics_ro" for reads

Write a CHANGES.md and unified diff.
```

---

## Prompt 34: AI Assistant Fix-Up (Method Mismatch, Context Window, Error Refinement)

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 2 (critical — conversation feature is broken without this)

### Prompt

```
Post-implementation verification found 3 issues in the AI Assistant that
prevent conversation memory from working correctly. Fix all of them.

1. Fix method name mismatch (CRITICAL — runtime crash):
   In ai-assistant/app/chat.py (~line 359):
   - Code calls store.get_messages(conversation_id, max_messages=20)
   - But ConversationStore (conversation_store.py) defines get_history(),
     NOT get_messages()
   - Fix: change get_messages() to get_history() in chat.py
   - Also check conversation_api.py (~line 75) for the same mismatch
   - Search the entire ai-assistant/app/ directory for any other calls
     to get_messages() and fix them all

2. Add tiktoken context window management (HIGH):
   In ai-assistant/app/chat.py, before the Azure OpenAI call:
   - import tiktoken
   - enc = tiktoken.encoding_for_model("gpt-4o")
   - Count tokens in system_prompt + current user message
   - Available context = 100000 - max_response_tokens - system_tokens
     (GPT-4o supports 128K; use 100K as working limit with buffer)
   - Load conversation history via get_history()
   - Fill remaining context with prior messages, newest first
   - Count tokens for each message being added
   - When adding the next message would exceed available context, stop
   - If history is truncated, prepend a summary message constructed from
     message metadata (sql_generated, result_summary fields), not by
     calling the LLM again
   - tiktoken is already in requirements.txt — verify version is current

3. Store errors in conversation history for refinement (MEDIUM):
   In ai-assistant/app/chat.py, when SQL validation fails or query errors:
   - Call store.add_message(conversation_id, role="assistant",
     content=f"Error: {error_message}. Suggestion: {suggestion}",
     metadata={"error": True, "sql_attempted": sql_text})
   - When results are empty, store a message noting 0 rows returned
   - When cost estimation exceeds threshold, store a message suggesting
     filters to narrow scope
   - On next user message, the AI sees these in context and self-corrects

Write a CHANGES.md and unified diff.
```

---

## Prompt 35: Triage MSAL Token Cache Migration to Redis

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 2 (before horizontal scaling)

### Prompt

```
The MSAL token cache is still serialized into the Flask session cookie
(triage_webapp/auth.py lines 49-60). Move it to Redis-keyed storage.

1. In triage_webapp/auth.py:
   - Replace _load_cache() and _save_cache():
     Store in Redis keyed by session ID:
       redis_client.setex(f"triage:msal_cache:{session.sid}", 1800, cache.serialize())
     Load: redis_client.get(f"triage:msal_cache:{session.sid}")
   - Remove session["token_cache"] entirely
   - Fallback: if Redis unavailable, use session-based storage (local dev)
   - Guard: use session.get("_id", str(uuid.uuid4())) if session.sid unavailable

2. Add cleanup on logout:
   - Delete redis key when user logs out
   - TTL handles expiration for abandoned sessions

Write a CHANGES.md and unified diff.
```

---

## Prompt 36: UDIP Schema for ADR + Triage Operational Data

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 3 (after integration platform is stable)

### Prompt

```
Design and create PostgreSQL tables in UDIP to hold ADR and Triage
operational data. This is the long-term data consolidation: moving from
37 Azure Table Storage tables across 2 apps into UDIP's central PostgreSQL
database. All AI tools, dashboards, and queries will draw from one source.

CONTEXT:
- ADR has 25 Azure Table Storage tables (mediationcases, chatlogs,
  caseparticipants, casedocuments, schedulingpolls, agreementversions, etc.)
- Triage has 12 tables (casetriage, AIClassificationLog, tasktracker, etc.)
- AI audit tables (aigenerationaudit, reliancescores, modeldrift) stay in
  Table Storage + WORM blob (immutable FOIA requirement). PostgreSQL gets
  a read-only copy for query purposes.
- Documents stay in Blob Storage. PostgreSQL stores references (URLs),
  not binary content.

CREATE THE FOLLOWING in analytics-db/postgres/:

1. Create 060-adr-operational-tables.sql:

   operations.adr_cases (replaces mediationcases):
   - case_id UUID PRIMARY KEY
   - case_name VARCHAR(200)
   - charge_number VARCHAR(25)
   - assigned_mediator_id VARCHAR(50)
   - assigned_mediator_name VARCHAR(200)
   - office_id VARCHAR(20)
   - office_name VARCHAR(100)
   - sector VARCHAR(20)
   - status VARCHAR(50)
   - priority VARCHAR(20)
   - mediation_type VARCHAR(50)
   - created_at TIMESTAMPTZ
   - closed_at TIMESTAMPTZ
   - closure_reason VARCHAR(100)
   - settlement_amount DECIMAL(12,2)
   - notes TEXT (pii_tier 3)
   - arc_case_number VARCHAR(25)
   - arc_sync_status VARCHAR(20)
   - All lifecycle metadata columns (first_synced_at, case_closed_at,
     retention_expires_at, retention_hold, lifecycle_state)

   operations.adr_chat_messages (replaces chatlogs):
   - message_id UUID PRIMARY KEY
   - case_id UUID FK -> adr_cases
   - channel VARCHAR(30) CHECK (main, complainant_caucus, agency_caucus)
   - author_id VARCHAR(128) (hashed)
   - author_role VARCHAR(30)
   - author_display_name VARCHAR(200) (pii_tier 2)
   - message_text TEXT (pii_tier 2)
   - is_ai_generated BOOLEAN
   - ai_model VARCHAR(50)
   - created_at TIMESTAMPTZ
   - INDEX (case_id, channel, created_at)

   operations.adr_participants (replaces caseparticipants):
   - participant_id UUID PRIMARY KEY
   - case_id UUID FK -> adr_cases
   - email VARCHAR(200) (pii_tier 3)
   - email_hash VARCHAR(128)
   - display_name VARCHAR(200) (pii_tier 2)
   - role VARCHAR(30)
   - auth_provider VARCHAR(20) (entra_id, login_gov)
   - joined_at TIMESTAMPTZ
   - left_at TIMESTAMPTZ

   operations.adr_documents (replaces casedocuments):
   - document_id UUID PRIMARY KEY
   - case_id UUID FK -> adr_cases
   - filename VARCHAR(255)
   - document_type VARCHAR(50)
   - blob_url TEXT
   - blob_container VARCHAR(100)
   - file_size_bytes BIGINT
   - mime_type VARCHAR(100)
   - scan_status VARCHAR(20)
   - uploaded_by VARCHAR(128) (hashed)
   - uploaded_at TIMESTAMPTZ

   operations.adr_scheduling_polls (replaces schedulingpolls):
   - poll_id UUID PRIMARY KEY
   - case_id UUID FK -> adr_cases
   - status VARCHAR(20)
   - proposed_times JSONB
   - created_by VARCHAR(128)
   - created_at TIMESTAMPTZ
   - expires_at TIMESTAMPTZ

   operations.adr_scheduling_responses (replaces schedulingresponses):
   - response_id UUID PRIMARY KEY
   - poll_id UUID FK -> adr_scheduling_polls
   - respondent_email_hash VARCHAR(128)
   - selected_time TIMESTAMPTZ
   - responded_at TIMESTAMPTZ

   operations.adr_agreement_versions (replaces agreementversions):
   - version_id UUID PRIMARY KEY
   - case_id UUID FK -> adr_cases
   - version_number INT
   - content_blob_url TEXT
   - created_by VARCHAR(128)
   - created_at TIMESTAMPTZ
   - status VARCHAR(20)

   operations.adr_signature_tracking (replaces signaturetracking):
   - signature_id UUID PRIMARY KEY
   - case_id UUID FK -> adr_cases
   - document_id UUID FK -> adr_documents
   - signer_email_hash VARCHAR(128)
   - signed_at TIMESTAMPTZ
   - signature_type VARCHAR(20)

2. Create 061-triage-operational-tables.sql:

   operations.triage_cases (replaces casetriage):
   - case_id UUID PRIMARY KEY
   - charge_number VARCHAR(25)
   - respondent_name VARCHAR(200)
   - basis_codes VARCHAR(200)
   - issue_codes VARCHAR(200)
   - statute_codes VARCHAR(200)
   - office_code VARCHAR(20)
   - filing_date DATE
   - status VARCHAR(20)
   - rank VARCHAR(1) CHECK (A, B, C)
   - merit_score DECIMAL(5,2)
   - ai_summary TEXT
   - ai_analysis JSONB
   - classified_at TIMESTAMPTZ
   - corrected_rank VARCHAR(1)
   - corrected_by VARCHAR(128)
   - corrected_at TIMESTAMPTZ
   - correction_notes TEXT
   - scan_status VARCHAR(20)
   - processing_status VARCHAR(20)
   - created_at TIMESTAMPTZ
   - All lifecycle metadata columns

   operations.triage_classification_log (replaces AIClassificationLog):
   - log_id UUID PRIMARY KEY
   - case_id UUID FK -> triage_cases
   - action VARCHAR(30) (classify, correct, re_classify)
   - old_rank VARCHAR(1)
   - new_rank VARCHAR(1)
   - actor_id_hash VARCHAR(128)
   - reason TEXT
   - created_at TIMESTAMPTZ

3. Create 062-operations-rls.sql:
   - Enable RLS on all operations.* tables
   - Region policy: join to analytics.charges via charge_number for region scoping
   - PII policy: tier-based visibility on participant emails, names, chat content
   - Writer policy for application service accounts

4. Create 063-operations-views.sql:
   - operations.vw_case_timeline: UNION of adr_chat_messages + analytics.case_events
     ordered by timestamp — complete case history in one query
   - operations.vw_active_mediations: adr_cases WHERE status = 'active'
     joined with participant count, document count, last chat activity
   - operations.vw_triage_pipeline: triage_cases with processing status,
     time since upload, correction rate

5. Create new dbt models:
   - stg_adr_cases, stg_adr_chat_messages, stg_triage_cases
   - fct_mediation_lifecycle (case creation → closure timeline)
   - fct_chat_activity (messages per case per day, AI vs human ratio)
   - fct_triage_pipeline_health (processing time, correction rate, rank distribution)

Write a CHANGES.md and unified diff.
```

---

## Prompt 37: ADR Data Layer Migration (Table Storage → PostgreSQL)

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 4 (after Prompt 36 schema deployed and tested)

### Prompt

```
Add a PostgreSQL data layer to ADR alongside the existing Azure Table Storage
layer. The migration is PHASED and FEATURE-FLAGGED — both storage backends
work simultaneously during transition. No data loss, no downtime.

APPROACH: Dual-write during transition. When enabled, every Table Storage
write also writes to PostgreSQL. Reads gradually shift from Table Storage
to PostgreSQL as confidence grows.

1. Create adr_webapp/data/pg_client.py:
   - PostgreSQL client using SQLAlchemy (same engine pattern as UDIP)
   - Connection via PgBouncer (UDIP's PgBouncer, shared)
   - RLS session context set per connection (same pattern as UDIP)
   - Methods mirror existing Table Storage patterns:
     a. get_case(case_id) -> dict
     b. list_cases(filters) -> list[dict]
     c. upsert_case(entity) -> None
     d. delete_case(case_id) -> None
     e. Same for: chat_messages, participants, documents, polls, agreements
   - Each method maps Azure Table Storage entity format to PostgreSQL row

2. Create adr_webapp/data/dual_writer.py:
   - Wraps both TableServiceClient and pg_client
   - On write: writes to Table Storage first (primary), then PostgreSQL
   - If PostgreSQL write fails: log error, do NOT fail the request
     (Table Storage is still the source of truth during transition)
   - On read: reads from Table Storage by default (PG_READ_ENABLED flag
     switches to PostgreSQL when ready)
   - Feature flags:
     PG_WRITE_ENABLED=false (dual-write to PostgreSQL)
     PG_READ_ENABLED=false (read from PostgreSQL instead of Table Storage)
     PG_MIGRATION_MODE=off (off, dual_write, pg_primary, pg_only)

3. Migration sequence:
   Phase A: PG_MIGRATION_MODE=dual_write
     - All writes go to both backends
     - All reads still from Table Storage
     - Run comparison queries to verify data parity
   Phase B: PG_MIGRATION_MODE=pg_primary
     - Reads shift to PostgreSQL
     - Writes still dual-write (Table Storage as backup)
     - Monitor for any discrepancies
   Phase C: PG_MIGRATION_MODE=pg_only
     - All reads and writes from PostgreSQL only
     - Table Storage writes stopped
     - Table Storage data retained for rollback (30 days)
   Phase D: Decommission Table Storage tables

4. Create adr_functionapp/DataMigration/__init__.py:
   - One-time Azure Function to bulk-migrate existing Table Storage data
     to PostgreSQL
   - Reads all entities from each table, transforms to PostgreSQL schema,
     bulk inserts via COPY
   - Progress tracking: logs rows migrated per table
   - Idempotent: can be re-run safely (upserts on PK)

5. Update FinalizeDisposal:
   - When PG_MIGRATION_MODE >= dual_write: dispose from both backends
   - Archive-before-delete uses PostgreSQL transaction (BEGIN → archive AI
     rows → delete case rows → COMMIT) for atomicity
   - Table Storage disposal remains as fallback

Write a CHANGES.md and unified diff. This is a large change — include a
MIGRATION_GUIDE.md documenting the phase transition procedure.
```

---

## Prompt 38: Triage Data Layer Migration (Table Storage → PostgreSQL)

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 4 (after Prompt 36 schema deployed and tested)

### Prompt

```
Same pattern as ADR (Prompt 37). Add PostgreSQL data layer to Triage with
dual-write, phased migration, and feature flags.

1. Create triage_webapp/data/pg_client.py:
   - PostgreSQL client via SQLAlchemy + PgBouncer
   - Methods: get_case, list_cases, upsert_case, log_classification,
     log_correction

2. Create triage_webapp/data/dual_writer.py:
   - Same dual-write pattern as ADR
   - PG_MIGRATION_MODE: off, dual_write, pg_primary, pg_only

3. Create case-processor-function/DataMigration/__init__.py:
   - Bulk migration from Table Storage to PostgreSQL
   - Handles: casetriage, AIClassificationLog, tasktracker

4. Update CaseFileProcessor to write classification results to both
   backends when PG_MIGRATION_MODE >= dual_write

5. Update FinalizeDisposal for dual-backend disposal

Write a CHANGES.md and MIGRATION_GUIDE.md.
```

---

## Prompt 39: UDIP Conversation History — FOIA/NARA 7-Year Retention

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 2 (critical — before AI Assistant goes live)

### Prompt

```
The AI Assistant conversation store has a 90-day TTL on conversation history.
Individual AI queries are logged to aigenerationaudit (7-year WORM), but the
conversation thread connecting those queries disappears after 90 days. This
violates FOIA requirements: the full decision-making context must be
reconstructable for 7 years from case closure.

Fix the conversation retention model to align with NARA 7-year requirements.

1. Link conversations to cases:
   In ai-assistant/app/conversation_store.py:
   - Add optional charge_number field to conversation metadata
   - When a user's query references a charge number (detected from SQL
     generated or explicit mention), link the conversation to that charge
   - Store in conversation entity: ChargeNumber, LinkedCaseId
   - A single conversation can link to multiple charges (analyst comparing cases)

2. Replace 90-day TTL with case-lifecycle retention:
   In conversation_store.py:
   - Remove the 90-day TTL (_RETENTION_DAYS = 90)
   - Conversations linked to a charge: retained until charge's
     retention_expires_at (case_closed_at + 7 years)
   - Conversations NOT linked to any charge: retain 1 year (analyst
     exploratory queries not tied to a specific case)
   - Add retention_expires_at field to conversation entity
   - Add lifecycle_state field (active, retained, held, archived)

3. Litigation hold on conversations:
   In conversation_store.py:
   - Add hold_conversation(conversation_id, hold_reason, set_by) method
   - Add release_hold(conversation_id, released_by) method
   - When a charge gets a litigation hold (via lifecycle_manager.set_hold()),
     automatically hold ALL conversations linked to that charge
   - Held conversations cannot be deleted regardless of retention_expires_at
   - Log hold/release events to middleware.lifecycle_audit_log

4. Archive conversations to WORM blob on case closure:
   When a linked case is closed:
   - Export the full conversation thread (all messages, in order) as JSON
   - Write to ai-generation-archive blob container (WORM, 2555 days)
   - Include: conversation_id, all messages with role/content/timestamp,
     all SQL generated, all result summaries, charge_numbers linked
   - HMAC-SHA256 signature on the archived blob
   - The conversation remains in Table Storage for continued access
     until retention expires

5. Conversation audit trail:
   Every conversation message is ALREADY logged to aigenerationaudit
   individually. Add a conversation-level audit record:
   - When conversation is created: log to aigenerationaudit with
     task_type="CONVERSATION_START"
   - When conversation is archived: task_type="CONVERSATION_ARCHIVED"
   - When conversation hold is set: task_type="CONVERSATION_HOLD"
   - These records have 7-year WORM retention (same as all aigenerationaudit)

6. Configuration:
   - CONVERSATION_UNLINKED_RETENTION_DAYS: 365 (default, for conversations
     not tied to any charge)
   - CONVERSATION_ARCHIVE_ON_CLOSE: true (default, archive to blob on
     case closure)
   - CONVERSATION_AUTO_HOLD_WITH_CASE: true (default, hold conversations
     when linked case gets held)

Write a CHANGES.md and unified diff.
```

---

## Prompt 40: FOIA Export API (All Repos)

**Repositories:** All 4 app repos (run per repo)
**Owner:** All teams
**Phase:** 2 (before production)

### Prompt (UDIP — run in eeoc-data-analytics-and-dashboard/)

```
Add a FOIA export endpoint to the UDIP AI Assistant. Triage already has
ExportTriageRecord as a template. FOIA requests require exporting all AI
interaction records for a specific case or date range.

1. Create ai-assistant/app/foia_export.py:
   - POST /api/foia-export
   - Auth: requires Admin or LegalCounsel role
   - Input: { case_id or charge_number, date_range_start, date_range_end }
   - Process:
     a. Query aigenerationaudit by case_id and/or date range
     b. For each record with ContentArchived=true, download full content
        from ai-generation-archive blob
     c. Query aiconversations for linked conversations (if Prompt 39 done)
     d. Package into ZIP:
        - ai_audit_records.json (all audit entries)
        - conversations/ directory with one JSON per conversation thread
        - metadata.json (export timestamp, requester hash, record count,
          SHA-256 hash of ZIP contents)
     e. Log export to audit table:
        task_type="FOIA_EXPORT", case_id, requester_hash, record_count,
        export_blob_url, zip_hash
     f. Upload ZIP to foia-exports blob container
     g. Return: { export_id, download_url (SAS, 24hr expiry), record_count }

2. Chain of custody:
   - Every FOIA export gets a unique export_id (UUID)
   - ZIP hash (SHA-256) logged to audit table
   - Download URL is SAS-tokenized (24-hour expiry, single use)
   - Re-export generates new export with new hash (no caching)

3. Rate limiting: 5 exports per hour per user (FOIA exports are expensive)

Write a CHANGES.md and unified diff.
```

### Prompt (ADR — run in eeoc-ofs-adr/)

```
Add FOIA export to ADR. Same pattern as UDIP (Prompt 40 above).

1. Create adr_webapp/routes/foia_export.py:
   - POST /api/v1/foia-export
   - Auth: admin or legal_counsel role required
   - Queries aigenerationaudit + chatlogs (archived) by case_id
   - Packages into ZIP with chain-of-custody metadata
   - Logs export to apiauditlog table

Write a CHANGES.md and unified diff.
```

### Prompt (OGC — run in eeoc-ogc-trialtool/)

```
Add FOIA export to OGC Trial Tool. Same pattern.

1. Create trial_tool_webapp/routes/foia_export.py:
   - POST /api/v1/foia-export
   - Auth: admin role required
   - Queries aigenerationaudit by case_name or date range
   - Packages into ZIP with chain-of-custody metadata

Write a CHANGES.md and unified diff.
```

---

## Prompt 41: Centralized Litigation Hold Mechanism

**Repositories:** All 4 app repos + UDIP for central hold table
**Owner:** All teams
**Phase:** 2 (before production)

### Prompt (UDIP — central hold table, run in eeoc-data-analytics-and-dashboard/)

```
Create a centralized litigation hold mechanism that prevents deletion of
case data and AI records across all applications when a FOIA request or
litigation hold is issued.

1. Create analytics-db/postgres/065-litigation-holds.sql:

   operations.litigation_holds:
   - hold_id UUID PRIMARY KEY
   - charge_number VARCHAR(25) NOT NULL
   - hold_type VARCHAR(30) CHECK ('foia', 'litigation', 'congressional', 'inspector_general')
   - hold_reason TEXT NOT NULL
   - reference_number VARCHAR(100) (FOIA request number, case docket, etc.)
   - issued_by VARCHAR(128) (hashed OID)
   - issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
   - released_by VARCHAR(128)
   - released_at TIMESTAMPTZ
   - is_active BOOLEAN DEFAULT TRUE
   - affects_systems TEXT[] DEFAULT ARRAY['adr','triage','udip','ogc']
   - INDEX (charge_number, is_active)

   operations.hold_audit_log:
   - audit_id UUID PRIMARY KEY
   - hold_id UUID FK -> litigation_holds
   - action VARCHAR(20) ('issued', 'released', 'extended', 'check_passed', 'check_blocked')
   - performed_by VARCHAR(128)
   - performed_at TIMESTAMPTZ DEFAULT NOW()
   - details TEXT

2. Create ai-assistant/app/hold_service.py:
   - HoldService class with methods:
     a. issue_hold(charge_number, hold_type, reason, reference, issued_by)
     b. release_hold(hold_id, released_by)
     c. check_hold(charge_number) -> bool (is any active hold present?)
     d. list_holds(active_only=True) -> list
     e. get_holds_for_charge(charge_number) -> list
   - Exposed via API:
     POST /api/holds (issue)
     DELETE /api/holds/{id} (release)
     GET /api/holds (list)
     GET /api/holds/check/{charge_number} (check)
   - Auth: LegalCounsel or Admin role required

3. Integration with lifecycle_manager.py:
   - Before any purge operation, check_hold() for all affected charge_numbers
   - If hold exists, abort purge and log to hold_audit_log with action='check_blocked'
   - When hold is issued, automatically set retention_hold=TRUE on:
     a. analytics.charges where charge_number matches
     b. All linked conversations in aiconversations
     c. Log to lifecycle_audit_log

4. MCP tool for hold checking:
   - Add hold_check_tool to UDIP's MCP server:
     Input: charge_number
     Output: { has_hold: bool, holds: [...] }
   - Other apps can call this through the MCP Hub before disposal

Write a CHANGES.md and unified diff.
```

### Prompt (ADR + Triage + OGC — run in each repo)

```
Integrate with UDIP's centralized litigation hold service.

1. In FinalizeDisposal function:
   - Before processing disposal, call UDIP's hold check API:
     GET {UDIP_API_URL}/api/holds/check/{charge_number}
   - If hold exists: abort disposal, log reason, return without deleting
   - If UDIP is unreachable: abort disposal (fail-closed), log error
   - Feature flag: LITIGATION_HOLD_CHECK_ENABLED (default: true)

2. In application startup:
   - Log: "Litigation hold checking: enabled/disabled"
   - If enabled but UDIP URL not configured: log warning, operate without hold checks

Write a CHANGES.md and unified diff.
```

---

## Prompt 42: ARC Integration API — M-21-31 / FedRAMP Compliance Logging

**Repository:** `eeoc-arc-integration-api/`
**Owner:** Hub team
**Phase:** 1 (before production)

### Prompt

```
The compliance audit found the ARC Integration API is missing HMAC audit
signing (AU-9, AU-10), persistent audit storage (AU-4), and explicit
retention policies (AU-11). It uses structlog for structured JSON which
is good, but lacks the tamper protection and immutability that ADR, Triage,
and UDIP already implement.

Bring the ARC Integration API to parity with ADR/Triage/UDIP audit logging.
Use the shared_code/ai_audit_logger.py pattern from ADR as the template.

1. Create app/audit_logger.py:
   - Dual-write: Azure Table Storage (primary) + WORM blob (archive)
   - Table: "arcintegrationaudit"
   - Blob container: "arc-integration-archive" (WORM 2555-day policy)
   - HMAC-SHA256 signatures on every record:
     Compute from: PartitionKey + RowKey + event_type + caller_hash
     Key: from Key Vault ("ARC-AUDIT-HMAC-KEY", minimum 32 chars)
   - Fields per record:
     PartitionKey (YYYY-MM-DD), RowKey (request_id + timestamp_microseconds),
     RequestID (X-Request-ID), CallerOIDHash (SHA-256 of caller OID),
     EventType (tool_invocation, write_back, feed_sync, event_forward),
     ToolName, TargetSystem (prepa, gateway, ecm),
     RequestPayload (truncated 32KB), ResponsePayload (truncated 32KB),
     ResponseHash (SHA-256 of full response),
     StatusCode, LatencyMs,
     RetentionPolicy ("FOIA_7_YEAR"), DataClassification ("OPERATIONAL"),
     InputHash (HMAC-SHA256), OutputHash (HMAC-SHA256),
     ContentTruncated (bool), BlobArchivePath (when content > 32KB)
   - When content exceeds 32KB: write full JSON to blob archive, store
     path in BlobArchivePath field
   - PII hashing: all user identifiers hashed with SHA-256 before logging

2. Integrate with existing structlog:
   In app/logging.py:
   - Add a structlog processor that writes to the audit logger for
     specific event types (tool invocations, write-backs, errors)
   - Keep structlog stdout output for operational logs
   - Audit logger fires in addition to structlog (not instead of)

3. Add to all routers:
   - mediation.py: log every write-back call (close, status update, document upload)
   - charges.py: log every charge metadata lookup
   - feed.py: log every feed sync request (if feed endpoints are used as fallback)
   - mcp.py: log every MCP tool invocation
   - Pattern: call audit_logger.log_event() in the router handler,
     after the response is generated, before returning

4. Failure handling (AU-5):
   - If audit write fails: retry 3 times with exponential backoff
   - If all retries fail: log error to structlog (stdout), continue serving
     (do NOT block the API response for audit failures)
   - Track failed audit writes: counter metric to Application Insights

5. Retention policy enforcement:
   - Add "RetentionPolicy": "FOIA_7_YEAR" to every audit entity
   - Document in README: arcintegrationaudit table must have Azure
     lifecycle management configured for 7-year retention
   - Document: arc-integration-archive blob container must have
     2555-day WORM immutability policy

6. Configuration:
   - ARC_AUDIT_HMAC_KEY: from Key Vault (32+ chars)
   - AZURE_STORAGE_CONNECTION_STRING: for Table + Blob access
   - ARC_AUDIT_TABLE: "arcintegrationaudit" (default)
   - ARC_AUDIT_ARCHIVE_CONTAINER: "arc-integration-archive" (default)

Write a CHANGES.md and unified diff.
```

---

## Prompt 43: MCP Hub Functions — M-21-31 / FedRAMP Compliance Logging

**Repository:** `eeoc-mcp-hub-functions/`
**Owner:** Hub team
**Phase:** 2 (before spokes connect)

### Prompt

```
The MCP Hub aggregator function has minimal logging — just Azure Functions
default Application Insights. It's missing HMAC signing, PII hashing,
correlation ID propagation, and persistent audit storage. Fix all.

1. Create hub_functions/audit_logger.py:
   - Same dual-write pattern as ARC Integration API (Prompt 42):
     Table: "hubauditlog" + Blob: "hub-audit-archive" (WORM 2555 days)
   - HMAC-SHA256 on every record using HUB-AUDIT-HASH-SALT from Key Vault
   - Fields: RequestID, CallerOIDHash, EventType (catalog_refresh,
     spoke_health_check, tool_call_routed, spoke_registered),
     SpokeName, ToolCount, Duration, Status, RetentionPolicy

2. Add PII hashing:
   - Create hub_functions/security.py:
     hash_pii(value, salt) → SHA-256 hex digest
   - Apply to all caller identifiers before logging
   - Salt from Key Vault (HUB-AUDIT-HASH-SALT)

3. Add correlation ID propagation:
   - In catalog_service.py: when calling spoke's tools/list,
     generate and propagate X-Request-ID header
   - In spoke_registry.py: log spoke registration with request_id
   - In function_app.py: extract X-Request-ID from HTTP trigger requests

4. Structured JSON logging:
   - Replace logging.getLogger() with structlog configured for JSON output
   - Add structlog to requirements.txt
   - All log entries include: timestamp (UTC ISO), request_id, event_type,
     spoke_name (if applicable), level

5. Add audit logging to all operations:
   - Catalog refresh: log spokes contacted, tools found per spoke,
     total tools in merged catalog, duration, errors
   - Spoke health check: log spoke name, health status, response time
   - Spoke registration: log spoke name, URL, categories, registered_by
   - Tool catalog request: log requester, categories requested, tools returned

Write a CHANGES.md and unified diff.
```

---

## Prompt 44: OGC Trial Tool — M-21-31 / FedRAMP Compliance Logging

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 2 (before hub connection)

### Prompt

```
The OGC Trial Tool has the weakest logging compliance: plain text format,
no HMAC signing, no correlation IDs, no PII hashing, no structured JSON,
and no explicit retention policy. Bring it to parity with ADR/Triage/UDIP.

The Trial Tool already has shared_code/ai_audit_logger.py (same as ADR).
The issue is that the main application logging (trial_tool_app.py) does
not use it for HTTP request/response logging — only for AI generation events.

1. Add structured JSON logging for all HTTP requests:
   In trial_tool_webapp/trial_tool_app.py:
   - Replace the plain text Flask formatter with a JSON formatter:
     import json, logging
     class JSONFormatter(logging.Formatter):
         def format(self, record):
             return json.dumps({
                 "timestamp": datetime.now(timezone.utc).isoformat(),
                 "level": record.levelname,
                 "module": record.module,
                 "message": record.getMessage(),
                 "request_id": getattr(record, 'request_id', ''),
             })
   - Add @app.before_request to capture X-Request-ID and start time
   - Add @app.after_request to log: method, path, status, duration_ms,
     request_id, user_hash

2. Add correlation ID propagation:
   - Accept X-Request-ID header on all requests
   - Generate UUID if not provided
   - Echo in response headers
   - Include in all log entries and AI audit records
   - Pass to MCP server tool handlers

3. Add PII hashing:
   - Hash user email with SHA-256 before any logging
   - Hash IP addresses in access logs
   - Use the same hash pattern as shared_code/ai_audit_logger.py

4. Verify and enforce retention:
   - Confirm shared_code/ai_audit_logger.py sets RetentionPolicy = "FOIA_7_YEAR"
   - Confirm aigenerationaudit table has 7-year lifecycle policy
   - Confirm aigenerationarchive blob has 2555-day WORM policy
   - If any are missing, add them

5. Add Application Insights integration:
   - Add APPLICATIONINSIGHTS_CONNECTION_STRING to app config
   - Configure OpenTelemetry or azure-monitor-opentelemetry for Flask:
     pip install azure-monitor-opentelemetry
     configure_azure_monitor(connection_string=...)
   - This sends structured logs + distributed traces to Log Analytics

6. AU-5 failure handling:
   - Wrap all ai_audit_logger calls in try/except with retry
   - If audit fails: log to stderr, continue serving
   - Never block case analysis because audit logging failed

Write a CHANGES.md and unified diff.
```

---

## Prompt 45: M-21-31 EL3 Infrastructure — Azure Sentinel, Flow Logs, DNS, UBA

**Repository:** Infrastructure documentation (not a code repo)
**Owner:** OCIO Platform team
**Phase:** 3 (after applications deployed)

### Prompt

```
This is a DOCUMENTATION prompt, not a code prompt. Create an infrastructure
deployment guide for M-21-31 EL3 requirements that are handled at the Azure
infrastructure level, not the application level.

Create a file: Azure_M2131_EL3_Infrastructure_Guide.md

Document step-by-step Azure Portal instructions for:

1. Azure Sentinel (SOAR + UBA):
   - Enable Microsoft Sentinel on the Log Analytics workspace
   - Connect data sources: Azure AD sign-in logs, Azure Activity logs,
     Application Insights (all 6 apps), NSG flow logs
   - Enable User and Entity Behavior Analytics (UEBA)
   - Create analytics rules for:
     a. Failed authentication > 10 per hour per user
     b. AI audit write failures > 5 per hour
     c. Unusual query patterns (> 100 AI queries per hour per user)
     d. After-hours access to PII tier 3 data
     e. FOIA export activity (any export triggers alert)
   - Create automation playbooks (Logic Apps):
     a. On high-severity alert: email security team + create ServiceNow ticket
     b. On AI circuit breaker: notify ADR/Triage team leads
     c. On WORM deletion attempt: email Records Management Officer

2. NSG Flow Logs:
   - Enable on all NSGs in vnet-eeoc-ai-platform
   - Version 2 (includes bytes transferred)
   - Retention: 365 days
   - Send to Log Analytics workspace
   - Enable Traffic Analytics

3. Azure DNS Analytics:
   - Enable DNS Analytics solution in Log Analytics
   - Configure diagnostic settings on Azure DNS zones
   - Alert on: DNS queries to known malicious domains, unusual query volume

4. Azure Network Watcher:
   - Enable in USGov Virginia region
   - Configure packet capture capability (on-demand, not always-on)
   - Document procedure for initiating packet capture during incident response
   - Retention: 30 days for captured packets

5. Log Analytics Workspace Configuration:
   - Interactive retention: 12 months (M-21-31 requirement)
   - Archive tier: 18 months beyond interactive (total 30 months)
   - Tables: configure per-table retention where needed
   - Data Export Rules: export to cold storage blob containers
   - Configure workspace-level RBAC (who can query what)

6. Azure AD Identity Protection:
   - Enable risk-based conditional access policies
   - Alert on: impossible travel, anonymous IP, malware-linked IP
   - Feed risk detections into Sentinel for correlation

7. TLS Inspection (if required):
   - Azure Firewall Premium with TLS inspection
   - Or Application Gateway with end-to-end TLS + certificate management
   - Document: which traffic is inspected, which is pass-through

8. Compliance Dashboard:
   - Create Azure Monitor workbook that shows:
     a. M-21-31 maturity level per application (EL1/EL2/EL3)
     b. AU control compliance status
     c. Log volume per application per day
     d. Audit record integrity (HMAC validation results)
     e. Retention policy adherence
     f. Open litigation holds

Write a complete guide with Azure Portal click-by-click instructions.
```

---

## Prompt 46: OGC Trial Tool — License Remediation and Dependency Hardening

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 2 (before any compliance scan)

### Prompt

```
SCA/license analysis found 3 issues in OGC Trial Tool that BlackDuck or
any compliance scanner would flag. Fix all of them. Additionally, all
dependencies are unpinned — a supply chain risk that fails SI-2.

1. Remove poppler-utils GPL dependency (HIGH — copyleft risk):
   In trial_tool_functionapp/requirements.txt:
   - pdf2image depends on poppler-utils (GPL-2.0) as a system dependency
   - GPL-2.0 in a Docker container may trigger copyleft obligations
   - REPLACE: pdf2image + poppler-utils with pypdf or pdfplumber
     (both already in the project, both MIT/BSD licensed)
   - In DocumentIndexer function, replace pdf2image.convert_from_bytes()
     with pdfplumber page rendering or pypdf page extraction
   - Remove poppler-utils from Dockerfile apt-get install list
   - Remove pdf2image from requirements.txt
   - Test: verify PDF processing still works with the replacement library

2. Replace deprecated python-jose (HIGH — unmaintained, CVE risk):
   In trial_tool_webapp/requirements.txt:
   - python-jose has not been maintained since 2021
   - Known CVEs in the cryptographic backend
   - REPLACE with PyJWT[crypto] (actively maintained, used by all other repos)
   - In trial_tool_webapp/ code, replace:
     from jose import jwt → from jwt import PyJWT (or import jwt)
   - Update any jwt.decode() calls to match PyJWT API
   - PyJWT is already proven in ADR, Triage, UDIP, ARC API

3. Document Ollama model licenses (MEDIUM):
   Create trial_tool_webapp/MODEL_LICENSES.md documenting:
   - Which LLM models the Trial Tool uses (list from config)
   - The license for each model:
     a. Llama 2/3: Meta Community License (commercial use allowed,
        must accept Meta's terms, not fully open source)
     b. Mistral: Apache 2.0 (fully permissive)
     c. Any other models used
   - Government use implications for each license
   - Recommendation: prefer Apache-2.0 licensed models (Mistral, Phi)
     for government use to avoid Meta Community License ambiguity

4. Pin ALL dependencies to exact versions:
   In trial_tool_webapp/requirements.txt AND trial_tool_functionapp/requirements.txt:
   - Run pip freeze in the current working environment
   - Pin every package to exact version (== not >= or ~=)
   - Include transitive dependencies
   - This prevents supply chain attacks via malicious version bumps
   - Add pip-audit to the CI pipeline (Prompt 12 should have added it —
     verify it's checking these requirements files)

5. Remove pytesseract system dependency if possible:
   - pytesseract requires Tesseract OCR as a system package
   - Tesseract is Apache-2.0 (safe) but adds container bloat
   - If Azure Document Intelligence (AI) is available (it is — used by Triage),
     consider replacing pytesseract with Document Intelligence for OCR
   - This eliminates a system dependency and uses a managed service
   - If pytesseract is kept: document Tesseract as Apache-2.0 in SBOM

Write a CHANGES.md and unified diff.
```

---

## Prompt 47: Supply Chain Hardening (All Repos) — FedRAMP Rev5 SR + SI-2 + CM-8

**Repositories:** All repos (run guidance per repo)
**Owner:** All teams
**Phase:** 2 (before FedRAMP assessment)

### Prompt

```
FedRAMP Rev5 introduced the Supply Chain Risk Management (SR) control family.
Additionally, SI-2 (Flaw Remediation) requires timely patching, and CM-8
(Information System Component Inventory) requires a complete SBOM. Implement
the following across ALL repositories.

This is a DOCUMENTATION + CONFIGURATION prompt, not heavy code changes.

1. Container image scanning (RA-5, SI-2):
   Add to EVERY repo's .github/workflows/build-and-test.yml:
   - Job: container-scan
   - Build the Docker image
   - Run Trivy scan: trivy image --severity CRITICAL,HIGH --exit-code 1 <image>
   - Fail the build if CRITICAL or HIGH vulnerabilities found
   - Upload scan results as artifact

   Example job:
   ```yaml
   container-scan:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: Build image
         run: docker build -t ${{ github.repository }}:scan .
       - name: Trivy scan
         uses: aquasecurity/trivy-action@master
         with:
           image-ref: ${{ github.repository }}:scan
           severity: CRITICAL,HIGH
           exit-code: 1
           format: sarif
           output: trivy-results.sarif
       - name: Upload results
         uses: github/codeql-action/upload-sarif@v3
         with:
           sarif_file: trivy-results.sarif
   ```

2. Automated dependency updates (SI-2):
   Add to EVERY repo: .github/dependabot.yml
   ```yaml
   version: 2
   updates:
     - package-ecosystem: pip
       directory: "/"
       schedule:
         interval: weekly
       open-pull-requests-limit: 5
       reviewers:
         - "derekcentrico"
   ```
   This creates weekly PRs for outdated dependencies. Review and merge.

3. System dependency SBOM (CM-8):
   The CycloneDX SBOM from pip only covers Python packages. System
   dependencies installed via apt-get in Dockerfiles are not captured.
   Add to each generate-sbom.sh:
   - After pip CycloneDX SBOM, scan the Docker image:
     syft <image> -o cyclonedx-json > system-sbom.json
   - This captures OS packages (libpq, msodbcsql, poppler, tesseract, etc.)
   - Upload both SBOMs as CI artifacts
   - Alternatively: add dpkg --list output as a text artifact

4. Supply chain risk documentation (SR-1, SR-2, SR-3):
   Create in EACH repo: docs/SUPPLY_CHAIN_RISK.md documenting:
   - Third-party dependencies and their licenses
   - Vendor assessment status (Azure services are FedRAMP High authorized)
   - Dependency update policy (weekly Dependabot + manual review)
   - Container base image update policy (monthly rebuild with latest slim-bookworm)
   - How to respond to a supply chain incident (compromised package):
     a. Pin to last known-good version
     b. Run pip-audit to identify affected versions
     c. Create incident ticket
     d. Replace package if maintainer is compromised

5. Container image signing (SI-7 if required):
   - Document: whether container image signing (cosign/Notation) is required
     for the agency's FedRAMP authorization boundary
   - If required: add cosign sign step to build-and-test.yml after image push
   - If not required: document as an accepted risk with compensating controls
     (image digest pinning in K8s manifests, private container registry with
     access controls)

6. Secret scanning (SA-11, IA-5(7)):
   The existing sast-scan.sh Phase 4 "Hardcoded Secrets Scan" uses regex
   grep patterns only — no dedicated tool, no git history scanning, no
   pre-commit hook. This is insufficient for FedRAMP.

   a. Add gitleaks to EVERY repo's CI pipeline:
      Add to .github/workflows/build-and-test.yml (or security-audit-evidence.yml):
      ```yaml
      secret-scan:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
            with:
              fetch-depth: 0  # full history for git log scanning
          - name: Gitleaks scan
            uses: gitleaks/gitleaks-action@v2
            env:
              GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      ```
      This scans the FULL git history, not just current files. Catches
      secrets that were committed and later removed.

   b. Add .gitleaks.toml to EVERY repo root:
      Configure allowlists for known false positives (test fixtures,
      placeholder values, documentation examples):
      ```toml
      [allowlist]
        description = "Known false positives"
        paths = [
          '''example_data/''',
          '''tests/fixtures/''',
          '''docs/'''
        ]
        regexTarget = "match"
      ```
      Customize per repo based on what sast-scan.sh's .secrets-allowlist.json
      already suppresses — migrate those suppressions to gitleaks format.

   c. Add pre-commit hook for local development:
      Create .pre-commit-config.yaml in EVERY repo:
      ```yaml
      repos:
        - repo: https://github.com/gitleaks/gitleaks
          rev: v8.18.0
          hooks:
            - id: gitleaks
      ```
      Document in CONTRIBUTING.md or README: developers must run
      `pre-commit install` after cloning the repo.

   d. One-time full history scan:
      Run gitleaks detect --source . --report-format sarif across ALL repos.
      If any real secrets are found in git history:
        - Rotate the compromised credential immediately
        - Document the incident
        - Do NOT rewrite git history (breaks audit trail) — rotation is
          sufficient per NIST SP 800-53 IA-5(7)
      Upload scan results as CI artifacts alongside other security evidence.

   e. Enable GitHub push protection (if available):
      - Go to each repo → Settings → Code security and analysis
      - Enable "Secret scanning" and "Push protection"
      - This blocks pushes containing known secret patterns (API keys,
        tokens, connection strings) before they enter the repository
      - Document as a compensating control in the SSP

   f. Update sast-scan.sh in all repos:
      - Keep the existing grep-based Phase 4 as a fast local check
      - Add a note: "For comprehensive scanning including git history,
        see the gitleaks CI job in .github/workflows/"
      - The grep scan remains useful for quick local validation but
        gitleaks in CI is the authoritative gate

Write guidance docs and CI configuration files. No application code changes.
```

---

## Prompt 48: OGC Trial Tool — Replace Ollama with FoundryModelProvider

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 2 (critical — Ollama is not production-grade for federal systems)

### Prompt

```
The OGC Trial Tool currently uses Ollama for local LLM inference. This must
be replaced with Azure OpenAI / Azure AI Foundry using the same provider-
agnostic pattern that ADR uses (FoundryModelProvider from shared_code).

Ollama is not acceptable for production because:
- No FedRAMP authorization
- Local model inference on application server = uncontrolled compute
- Model provenance and licensing not managed
- No centralized audit of AI token usage
- No managed identity authentication
- Not on any approved Azure endpoint allowlist

ADR's FoundryModelProvider supports: Azure OpenAI, Azure AI Foundry, and MCP
backends with automatic HTTPS validation, domain allowlisting, managed identity
token acquisition, and provider-agnostic API.

CHANGES:

1. Copy ADR's shared_code/foundry_model_provider.py into OGC's shared_code/:
   - FoundryModelProvider class
   - create_foundry_model_provider() factory
   - ProviderConfig, ModelProvider enum
   - _AI_ENDPOINT_DOMAIN_ALLOWLIST
   - HTTPS enforcement + domain validation
   - Managed identity token provider (DefaultAzureCredential)
   - All three backends: AZURE_OPENAI, AZURE_AI_FOUNDRY, MCP

2. Replace all Ollama calls in trial_tool_webapp/full_context_llm.py:
   - Remove: import ollama, from ollama import ...
   - Remove: ollama.chat(), ollama.Client()
   - Replace with: FoundryModelProvider.chat_completion()
   - The full_context_llm module has 9 AI analysis functions:
     q_and_a, timeline, summary, outline_builder, impeachment_kit,
     comparator_analyzer, issue_matrix, damages_snapshot, mil_helper
   - Each calls Ollama — replace every call with the provider
   - Preserve the system prompts and function-calling patterns
   - The FoundryModelProvider returns the same chat completion response
     format as Azure OpenAI (messages + tool_calls)

3. Replace Ollama in trial_tool_functionapp/DocumentIndexer/:
   - DocumentIndexer uses Ollama for text cleanup and summarization
   - Replace with FoundryModelProvider calls
   - If DocumentIndexer also uses Ollama for embeddings: replace with
     Azure OpenAI text-embedding-3-small (same as UDIP and Triage)

4. Remove ollama from requirements.txt:
   - trial_tool_webapp/requirements.txt: remove ollama
   - trial_tool_functionapp/requirements.txt: remove ollama
   - Add: openai (Azure OpenAI SDK) if not present
   - Add: azure-identity (for managed identity)

5. Configuration (environment variables):
   DEFAULT: Azure OpenAI (GA packages, passes all SCA/license audits).
   OPTIONAL: AI Foundry (beta packages — do NOT enable in production until
   azure-ai-inference reaches GA and clears audit).
   Provider auto-detection (same as ADR):
   - If AZURE_OPENAI_ENDPOINT set: use Azure OpenAI (default, recommended)
   - If AZURE_AI_FOUNDRY_ENDPOINT set: use AI Foundry (future option)
   - If neither: fail startup with clear error message
   - If BOTH set: prefer Azure OpenAI (log warning about dual config)
   Environment variables (Azure OpenAI — primary):
   - AZURE_OPENAI_ENDPOINT (e.g., https://oai-eeoc-ai-prod.openai.azure.us/)
   - AZURE_OPENAI_CHAT_DEPLOYMENT (e.g., gpt-4o)
   - AZURE_OPENAI_API_VERSION (e.g., 2024-02-01)
   Environment variables (AI Foundry — reserved for future):
   - AZURE_AI_FOUNDRY_ENDPOINT (leave unset for now)
   - AZURE_AI_FOUNDRY_DEPLOYMENT
   Auth: managed identity only (DefaultAzureCredential), no API keys

6. Remove Ollama from Docker:
   - Remove any Ollama server installation from Dockerfile
   - Remove any Ollama model download steps
   - Remove OLLAMA_HOST, OLLAMA_MODELS environment variables
   - The container no longer needs GPU or large model files

7. Update all references across the codebase:
   - Search for "ollama" (case-insensitive) across ALL files
   - Update docs, README, config examples, test mocks
   - 22 files currently reference Ollama — update or remove all references

8. Update tests:
   - Replace Ollama mock fixtures with Azure OpenAI mock fixtures
   - Test the FoundryModelProvider initialization and fallback logic
   - Verify all 9 AI analysis functions work with the new provider

Write a CHANGES.md and unified diff.
```

---

## Prompt 49: Triage — Adopt FoundryModelProvider Pattern

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 2

### Prompt

```
Triage currently uses direct AzureOpenAI client instantiation with
managed identity token provider (Prompt 18 migrated from API key).
This works but is not provider-agnostic. Adopt ADR's FoundryModelProvider
pattern so all three AI apps (ADR, Triage, OGC) use the same abstraction.

Benefits: switchable between Azure OpenAI and AI Foundry via config,
centralized endpoint validation, domain allowlisting, consistent error
handling, identical audit patterns.

CHANGES:

1. Copy ADR's shared_code/foundry_model_provider.py into Triage's shared/:
   - Full FoundryModelProvider class with all three backends
   - HTTPS validation + domain allowlist
   - Managed identity token acquisition
   - Provider auto-detection from environment variables

2. Refactor CaseFileProcessor to use FoundryModelProvider:
   In case-processor-function/CaseFileProcessor/__init__.py:
   - Replace direct AzureOpenAI client initialization (lines 331-338)
     with create_foundry_model_provider()
   - Replace openai_client.chat.completions.create() calls with
     provider.chat_completion()
   - The call_openai_with_retry() wrapper (Prompt 22/31) should wrap
     the provider call, not the raw SDK call
   - Keep the same system prompts, temperature, and stop sequences

3. Refactor PriorityDocIndexer to use FoundryModelProvider:
   In case-processor-function/PriorityDocIndexer/__init__.py:
   - Replace direct AzureOpenAI client for embeddings
   - Use provider.embeddings() if FoundryModelProvider supports it
   - If not: keep direct Azure OpenAI for embeddings (embedding models
     are not typically available on AI Foundry)

4. Configuration alignment:
   DEFAULT: Azure OpenAI (GA, audit-clean, production-ready).
   OPTIONAL: AI Foundry support wired but NOT enabled until GA.
   - Same env var names as ADR and OGC:
     AZURE_OPENAI_ENDPOINT (primary, required)
     AZURE_OPENAI_CHAT_DEPLOYMENT (e.g., gpt-4o)
     AZURE_OPENAI_API_VERSION (e.g., 2024-02-01)
   - AZURE_AI_FOUNDRY_ENDPOINT (reserved for future, leave unset)
   - If both set: prefer Azure OpenAI, log warning
   - No API keys — managed identity only (already done via Prompt 18)
   - Document: "AI Foundry support exists in FoundryModelProvider but
     should not be enabled until azure-ai-inference package reaches GA
     and passes SCA/license audit. Azure OpenAI packages (openai SDK)
     are GA and clear all compliance checks."

5. Remove hardcoded model deployment names:
   - COMPLETION_DEPLOYMENT should come from config, not hardcoded
   - EMBEDDING_DEPLOYMENT should come from config
   - Document all AI-related env vars in a single config block

Write a CHANGES.md and unified diff.
```

---

## Prompt 50: Complete Platform Deployment Guide (Zero Assumptions)

**Output:** `./EEOC_AI_Platform_Complete_Deployment_Guide.md` in workspace root
**Owner:** OCIO Platform team
**Phase:** 1 (create before any deployment begins)

### Prompt

```
Create a complete, newbie-friendly, zero-assumption deployment guide for the
entire EEOC AI Integration Platform. This guide covers EVERYTHING — from
"I have an empty Azure subscription" to "the AI Assistant is answering
questions and all 5 spokes are connected."

AUDIENCE: An IT administrator who has Azure Portal access but has never
deployed this system before. Assume they know what Azure is but nothing
about our architecture. Explain every click, every field, every value.

MODEL AFTER: The ADR project's Azure_Portal_Provisioning_Guide.md (in
eeoc-ofs-adr/docs/). Match the format: table of contents, prerequisites
checklist with checkboxes, phase-by-phase sections, post-deployment
verification, appendix with naming conventions.

THE GUIDE MUST COVER (in order):

PART 0: WHAT YOU'RE BUILDING (1 page)
- Architecture diagram (text-based, same as EEOC_AI_Platform_Azure_Overview.md)
- What each component does in plain English
- Expected outcome: "When you're done, analysts can ask the AI questions
  about EEOC case data and get charts back"

PART 1: PREREQUISITES CHECKLIST (before touching Azure)
- [ ] Azure Government subscription with Contributor role
- [ ] Global Administrator access for Entra ID
- [ ] List of all Entra ID security groups needed (with exact names)
- [ ] TLS certificate for ADR public domain (PFX format)
- [ ] ARC DBA contact info (for the 2 SQL commands)
- [ ] ARC REST API credentials (OAuth2 client_id/secret)
- [ ] DNS control for ADR public domain (CNAME record)
- [ ] GitHub access to all 6 repos
- [ ] Docker images built and pushed to Azure Container Registry
- [ ] Complete list of all email addresses for alert notifications
- Fill-in-the-blank worksheet for all values needed during deployment:
  tenant ID, subscription ID, domain name, group IDs, etc.

PART 2: AZURE PORTAL STEPS (click-by-click)
For EVERY resource, document:
  a. What to search for in the portal
  b. What to click
  c. What to type in EVERY field (exact values or "{placeholder}")
  d. What tab to go to next
  e. Screenshot-equivalent text descriptions ("You should now see...")
  f. What to verify after creation

Section order:
  2.1 Resource Group
  2.2 Virtual Network (7 subnets, exact CIDRs)
  2.3 Key Vault (every secret listed with generation method)
  2.4 Storage Account (tables, containers, WORM policy)
  2.5 Azure Container Registry (push all 10 images)
  2.6 Azure Database for PostgreSQL Flexible Server
      - Server parameters (exact values table)
      - Extensions to enable
      - Schema scripts to run (exact order, exact filenames)
      - Read replica creation
  2.7 PgBouncer (Container App, configmap values)
  2.8 Azure Cache for Redis
  2.9 Azure Event Hub Namespace
  2.10 Azure OpenAI (model deployments, managed identity access)
  2.11 Azure Cognitive Search (Triage RAG)
  2.12 Entra ID App Registrations (6 apps, every role, every permission grant)
  2.13 Container Apps Environment
  2.14 Deploy Container Apps (10 apps, exact CPU/memory/scaling/env vars each)
  2.15 Azure Functions (ADR + Triage function apps)
  2.16 Azure API Management (MCP Hub — reference Azure_MCP_Hub_Setup_Guide.md)
  2.17 Azure Event Grid (inter-spoke events)
  2.18 Azure Front Door + WAF (ADR public access)
  2.19 Azure Sentinel (M-21-31 EL3 — reference Prompt 45 guide)
  2.20 Application Insights + Log Analytics
  2.21 Azure Monitor Alert Rules (every alert with exact thresholds)

PART 3: ARC DBA COORDINATION
- Exact email template to send to ARC DBA
- The 2 SQL commands they need to run
- What credentials to ask for
- How to verify WAL/CDC is working after they run the commands

PART 4: POST-PROVISIONING CONFIGURATION
- Enable feature flags per application (exact env var names and values)
- Spoke registration in MCP Hub (exact API calls or portal steps)
- Connection sequence (Phase 3.1-3.6 from Azure_Deployment_Sequence.md)
- How to verify each spoke is connected and healthy

PART 5: FIRST DATA FLOW VERIFICATION
- How to verify CDC is streaming data from PrEPA to UDIP
- How to verify the middleware is translating data correctly
- How to verify RLS is working (test with 2 different regional users)
- How to verify the AI Assistant responds to a query
- How to verify charts render in the browser

PART 6: GOING LIVE CHECKLIST
- [ ] All health endpoints return 200
- [ ] All spokes appear in hub tool catalog
- [ ] AI query returns data (not empty)
- [ ] ADR Login.gov works for external test party
- [ ] Triage classification completes for a test case
- [ ] Audit records appear in all audit tables
- [ ] WORM blob cannot be deleted (verify)
- [ ] Alerts fire when thresholds are simulated
- [ ] Backup/restore tested on PostgreSQL
- [ ] DR failover documented (if applicable)

PART 7: TROUBLESHOOTING
Common problems and solutions:
- UDIP returns empty results → OBO not configured, check caller region
- ADR login fails → Entra ID redirect URI misconfigured
- CDC consumer not processing → Event Hub connection string, consumer group
- Tool not found in hub → spoke not registered, check APIM routing
- 401 on all requests → token validation, check audience claim
- Container App crashes → check resource limits, review logs

APPENDIX A: All Resource Names (single table)
APPENDIX B: All Environment Variables by Application
APPENDIX C: All Key Vault Secrets
APPENDIX D: All Entra ID App Registrations and Roles
APPENDIX E: Network Diagram (text-based, subnet-to-resource mapping)

Write the complete guide. Target length: 1500-2000 lines. This is the
definitive document — someone should be able to follow it from scratch
with zero tribal knowledge.
```

---

## Prompt 51: Azure Provisioning Script (provision_eeoc_ai_platform.sh)

**Output:** `./provision_eeoc_ai_platform.sh` in workspace root
**Owner:** OCIO Platform team
**Phase:** 1

### Prompt

```
Create an automated Azure provisioning script for the EEOC AI Integration
Platform. Model after the ADR project's provision_adr_system.sh — same
structure, same safety patterns, same documentation density.

The script provisions EVERYTHING except:
- Entra ID app registrations (portal-only, requires Global Admin)
- ARC DBA actions (2 SQL commands, external team)
- Docker image builds (separate CI/CD)
- DNS records (external DNS provider)
- TLS certificates (uploaded separately)

SCRIPT STRUCTURE:

SECTION 0: Header and documentation
- Purpose, author, version
- Architecture overview in comments
- Security compliance notes (FedRAMP High, NIST 800-53)
- What the script does and does NOT do (explicit exclusions)

SECTION 1: Pre-deployment prerequisites (manual steps)
- Checklist of what must exist BEFORE running the script
- How to obtain each prerequisite
- Validation commands to verify readiness

SECTION 2: Configuration variables
- ALL configurable values at the top of the script
- Naming convention: EEOC_* prefix
- Environment-specific overrides (dev/staging/prod)
- Region configuration (primary: usgovvirginia)
- Resource naming convention (documented inline)
  Example:
  EEOC_ENV="prod"
  EEOC_REGION="usgovvirginia"
  EEOC_RG="rg-eeoc-ai-platform-${EEOC_ENV}"
  EEOC_VNET="vnet-eeoc-ai-${EEOC_ENV}"
  EEOC_KV="kv-eeoc-ai-${EEOC_ENV}"
  EEOC_PG_SERVER="pg-eeoc-udip-${EEOC_ENV}"
  ... etc for ALL resources

SECTION 3: Safety checks
- Verify Azure CLI logged in (az account show)
- Verify correct subscription selected
- Verify Azure Government cloud (az cloud show)
- Prompt user to confirm before proceeding
- Check for existing resources (don't overwrite without --force flag)

SECTION 4: Resource Group + Tags

SECTION 5: Virtual Network + 7 Subnets + NSGs

SECTION 6: Key Vault + Private Endpoint
- Generate and store ALL secrets:
  HMAC keys (openssl rand -base64 40)
  Audit hash salts
  Webhook secrets per spoke
- Output generated secrets to console (one-time display)

SECTION 7: Storage Account + Private Endpoint
- Tables: hubauditlog
- Containers: hub-audit-archive (WORM 2555 days),
  adr-case-files, adr-quarantine, triage-processing,
  triage-archival, function-locks, lifecycle-archives,
  foia-exports
- Immutability policy on audit containers

SECTION 8: Azure Database for PostgreSQL Flexible Server
- Memory Optimized E16ds_v5 (16 vCores, 128 GB, 2 TB)
- Private endpoint
- Extensions: pgvector, pg_stat_statements, pgcrypto, pg_trgm
- Server parameters (all values from deployment guide)
- Run ALL schema scripts in order (psql -f ...)
- Create read replica

SECTION 9: PgBouncer Container App
- Deploy from pgbouncer image
- ConfigMap values (3000/80/200)
- Health probe

SECTION 10: Azure Cache for Redis
- Premium P1, VNet integration
- Store connection string in Key Vault

SECTION 11: Azure Event Hub Namespace
- Kafka-enabled, Standard tier
- Consumer group: udip-middleware
- Store connection string in Key Vault

SECTION 12: Azure OpenAI
- Deploy gpt-4o and text-embedding-3-small
- Grant managed identity access (Cognitive Services OpenAI User)

SECTION 13: Azure Cognitive Search
- Standard S1
- Store admin key in Key Vault

SECTION 14: Container Apps Environment
- Internal-only ingress
- Log Analytics workspace

SECTION 15: Deploy All Container Apps (10 apps)
- For each: create app, set env vars, configure scaling, health probes
- All env vars reference Key Vault secrets where applicable

SECTION 16: Azure Functions (ADR + Triage)
- Premium EP1 plan
- VNet integration
- Application settings from Key Vault references

SECTION 17: Azure Front Door + WAF (ADR)
- Standard tier
- OWASP 3.2 managed ruleset
- Bot manager ruleset
- Rate limiting custom rule (100/min/IP)
- Health probe to ADR /healthz

SECTION 18: Application Insights
- Connect to Log Analytics workspace
- Configure diagnostic settings on all resources

SECTION 19: Azure Monitor Alert Rules
- All alerts from deployment guide (CPU, connections, lag, errors, WORM)

SECTION 20: Azure Sentinel (M-21-31)
- Enable on Log Analytics workspace
- Connect data sources
- Enable UEBA
- Create analytics rules

SECTION 21: Post-provisioning output
- Print all resource URLs
- Print all Key Vault secret names (not values)
- Print next steps (manual Entra ID setup, ARC DBA coordination, DNS)
- Save deployment summary to deploy_summary_{timestamp}.txt

SCRIPT REQUIREMENTS:
- Uses az CLI exclusively (no ARM templates, no Terraform)
- Every command has error checking: || { echo "FAILED: ..."; exit 1; }
- Every resource creation checks if it already exists first (idempotent)
- set -euo pipefail at the top
- Color-coded output: green for success, red for failure, yellow for skip
- Estimated time per section printed before each section starts
- Total estimated time: ~45-60 minutes
- Progress counter: "Step 14 of 21: Deploying Container Apps Environment..."
- Log all output to provision_log_{timestamp}.txt

PRE-SCRIPT CHECKLIST (printed before execution):
  "Before running this script, ensure you have:
   [ ] Azure CLI installed and logged in to Azure Government
   [ ] Contributor role on the target subscription
   [ ] The following values ready:
       - Subscription ID
       - TLS certificate path (.pfx)
       - ARC OAuth2 client_id and client_secret
       - ADR public domain name
       - Notification email addresses
   Press Enter to continue or Ctrl+C to abort..."

POST-SCRIPT CHECKLIST (printed after execution):
  "Provisioning complete. Manual steps remaining:
   1. Create Entra ID app registrations (see guide Section 2.12)
   2. Send WAL/CDC request to ARC DBA (email template in guide Part 3)
   3. Build and push Docker images to ACR
   4. Create DNS CNAME for ADR domain → Front Door endpoint
   5. Upload TLS certificate to Key Vault
   6. Enable feature flags per application
   7. Register spokes in MCP Hub
   8. Run connection sequence (Phase 3.1-3.6)
   9. Verify first data flow (guide Part 5)"

Write the complete script. Target: 800-1200 lines. Match the quality and
documentation density of provision_adr_system.sh.
```

---

## Prompt 52: Auto-Schema Detection, Labeling, and AI Discovery

**Repository:** `eeoc-data-analytics-and-dashboard/`
**Owner:** UDIP team
**Phase:** 3 (after CDC pipeline is stable)

### Prompt

```
Build an automated system that detects new data arriving from any connected
application (ARC via CDC, ADR via ingest, Triage via ingest), auto-creates
properly labeled analytics tables, generates dbt models, and makes the data
immediately discoverable by the AI Assistant, JupyterHub notebooks, and
Superset dashboards — all with minimal human intervention.

The critical requirement: every auto-created table must have HUMAN-READABLE
column names, descriptions, and metric definitions. The AI Assistant should
be able to answer questions about the new data without anyone writing custom
SQL or dbt models. Analysts should be able to build Superset dashboards
against the new table immediately.

BUILD THE FOLLOWING:

1. Create data-middleware/schema_detector.py:

   Class SchemaDetector:

   a. detect_new_replica_tables():
      - Compare tables in replica.* schema against registered analytics tables
      - Return list of replica tables with no corresponding analytics table
      - Run daily via Kubernetes CronJob (after CDC consumer has run)

   b. detect_new_ingest_datasets(payload):
      - Called by the ingest API when a dataset name is unknown
      - Infers schema from the first batch of records:
        column names, data types (string, int, float, bool, date, timestamp)
      - Returns inferred schema

   c. auto_label_columns(source_table, columns):
      THE MOST IMPORTANT FUNCTION. Takes raw column names and produces
      human-readable labels, descriptions, and metadata.

      Labeling strategy (in priority order):

      i.  KNOWN COLUMN REGISTRY: Check a maintained registry of known
          EEOC column name → label mappings. This registry is a YAML file
          (data-middleware/column_registry.yaml) that maps:
          ```yaml
          columns:
            charge_inquiry_id:
              label: "Charge ID"
              description: "Unique identifier for a discrimination charge"
              category: "identifier"
              pii_tier: 1
            shared_basis_id:
              label: "Discrimination Basis"
              description: "Protected class (Race, Sex, Age, etc.)"
              category: "classification"
              pii_tier: 1
              resolve_via: "replica.shared_basis.description"
            first_name:
              label: "First Name"
              description: "Person's first/given name"
              category: "pii"
              pii_tier: 3
            closure_date:
              label: "Case Closure Date"
              description: "Date the case was formally closed"
              category: "date"
              pii_tier: 1
            # ... hundreds of entries covering all known EEOC columns
          ```
          Pre-populate this registry from the PrEPA JPA entity analysis
          we already have (see data-middleware/source_mappings/NEEDS_DATA.md).
          Every column from every PrEPA entity should have an entry.

      ii. PATTERN-BASED INFERENCE: For columns NOT in the registry,
          apply naming pattern rules:
          - *_id → "ID" suffix, category: identifier
          - *_date, *_on, *_at → category: date
          - is_*, has_* → category: boolean flag
          - *_name → category: name (check PII)
          - *_code → category: code (look for matching *_description column)
          - *_amount, *_count, *_total → category: numeric measure
          - *_email, *_phone, *_address, *_ssn, *_dob → category: pii, tier 3
          - Convert snake_case to Title Case for label:
            "mediation_reply_due_date" → "Mediation Reply Due Date"

      iii. FK RESOLUTION: For columns ending in _id that reference
           replica.shared_code or other reference tables:
           - Auto-generate a lookup_table transform in the YAML
           - Create a paired human-readable column:
             shared_basis_id (integer FK) → basis_name (resolved description)
           - The resolved column is what the AI and dashboards use

      iv. AI-ASSISTED LABELING (optional, feature-flagged):
          If AUTO_LABEL_AI_ENABLED=true:
          - Send column names + sample values to Azure OpenAI
          - Prompt: "Given these database columns and sample values from
            an EEOC discrimination charge system, provide a human-readable
            label and one-sentence description for each column."
          - Use the AI response to fill in labels for unknown columns
          - Store results in column_registry.yaml for future reuse
          - Flag AI-generated labels for human review

   d. auto_detect_pii(column_name, sample_values):
      - Pattern-based PII detection:
        Name patterns → tier 3
        Email/phone/SSN/DOB patterns → tier 3
        Address patterns → tier 2 (city), tier 3 (street/zip)
        Code/ID patterns → tier 1
      - Scan sample values with PII regex (same patterns as redact_pii)
      - If values match SSN/email/phone patterns → tier 3 regardless of name
      - Return recommended pii_tier

2. Create data-middleware/auto_schema_builder.py:

   Class AutoSchemaBuilder:

   a. create_analytics_table(table_name, labeled_columns):
      - Generate CREATE TABLE SQL for analytics.{table_name}
      - Include all standard columns:
        source_modified_at, synced_at, first_synced_at,
        lifecycle metadata (case_closed_at, retention_expires_at, etc.)
      - Apply PII tiers from auto_detect_pii
      - Execute against PostgreSQL
      - Log creation to middleware.lifecycle_audit_log

   b. create_rls_policy(table_name, labeled_columns):
      - If table has a charge_id or charge_number column:
        create region policy inherited from analytics.charges
      - If table has PII columns (tier 2/3):
        create PII tier policy
      - Always create writer policy for udip_writer role
      - Execute against PostgreSQL

   c. generate_yaml_mapping(source_schema, table_name, labeled_columns):
      - Create a new YAML mapping file in source_mappings/auto/{table_name}.yaml
      - Include all labeled columns with transforms:
        FK integers → lookup_table transforms (auto-resolved)
        PII columns → redact_pii transforms
        Date columns → parse_date transforms
        Everything else → null transform
      - Mark as auto-generated: "# AUTO-GENERATED by SchemaDetector on {date}"
      - Include [REVIEW_NEEDED] tags on uncertain mappings

   d. generate_dbt_model(table_name, labeled_columns):
      - Create staging model: dbt-semantic-layer/models/staging/stg_{table_name}.sql
        SELECT * FROM analytics.{table_name}
      - Create schema.yml entry with:
        - model name, description (auto-generated from table purpose)
        - column descriptions (from labeled_columns)
        - tests: unique on PK, not_null on required fields
      - Create metric definitions if numeric columns detected:
        {table_name}_count → COUNT(*)
        {table_name}_{numeric_col}_avg → AVG({col})
        {table_name}_{numeric_col}_sum → SUM({col})

   e. generate_dataset_metadata(table_name, labeled_columns):
      - Create a metadata JSON file that the AI Assistant, Superset,
        and JupyterHub can all consume:
        ```json
        {
          "table": "analytics.new_table_name",
          "display_name": "New Table Human Name",
          "description": "Auto-generated description of what this table contains",
          "source": "arc_cdc" or "adr_ingest" or "triage_ingest",
          "created_at": "2026-04-04T...",
          "auto_generated": true,
          "review_status": "pending_review",
          "columns": [
            {
              "name": "column_name",
              "label": "Human Readable Label",
              "description": "What this column means",
              "type": "varchar(100)",
              "pii_tier": 1,
              "category": "classification",
              "is_metric": false,
              "is_dimension": true,
              "sample_values": ["Race", "Sex", "Age"]
            }
          ],
          "metrics": [
            {
              "name": "record_count",
              "label": "Total Records",
              "sql": "COUNT(*)",
              "description": "Total number of records in this dataset"
            }
          ],
          "suggested_dashboards": [
            "Bar chart: {dimension_col} by {metric_col}",
            "Time series: {date_col} trend of {metric_col}"
          ]
        }
        ```
      - Save to: data-middleware/dataset_metadata/{table_name}.json
      - The AI Assistant loads this metadata to understand the new dataset
      - Superset can use the metadata to auto-suggest chart types
      - JupyterHub can display the metadata as a data dictionary

3. Integration with existing systems:

   a. AI Assistant discovery:
      - In ai-assistant/app/mcp_registry.py:
        On startup and every 5 minutes, scan dataset_metadata/ for new files
        Auto-register new datasets as MCP query_{table_name} tools
        Include column labels and descriptions in the tool schema
        The AI sees: "query_new_table — New Table Human Name: What this
        table contains. Columns: Human Readable Label (description)..."

   b. Superset auto-discovery:
      - Create a Superset sync script (scripts/superset_dataset_sync.py):
        Reads dataset_metadata/ JSON files
        Creates Superset datasets via Superset REST API
        Sets column labels and descriptions from metadata
        Creates default charts (bar, line, pie based on column types)
        Adds to a "Auto-Discovered Datasets" dashboard

   c. JupyterHub data dictionary:
      - Create a Jupyter notebook template (notebooks/data_dictionary.ipynb):
        Reads all dataset_metadata/ JSON files
        Renders a browsable data dictionary with:
          table name, description, column list with labels and types
          sample queries for each table
          metric definitions
        Auto-refreshes when new datasets are added

   d. Ingest API auto-creation:
      - In ai-assistant/app/mcp_api.py (ingest endpoint):
        When dataset name is unknown:
        1. Call SchemaDetector.detect_new_ingest_datasets(payload)
        2. Call auto_label_columns() on inferred schema
        3. Call AutoSchemaBuilder.create_analytics_table()
        4. Call create_rls_policy()
        5. Call generate_yaml_mapping()
        6. Call generate_dbt_model()
        7. Call generate_dataset_metadata()
        8. Accept the ingest payload into the new table
        9. Log: "Auto-created table analytics.{name} with {n} columns"
        10. Flag for human review

4. Create data-middleware/column_registry.yaml:
   Pre-populate with ALL known EEOC column names from:
   - PrEPA JPA entities (charge_inquiry, charging_party, respondent,
     charge_allegation, charge_assignment, mediation_interview,
     charge_event_log, shared_code, shared_basis, shared_issue, etc.)
   - ADR Table Storage columns (mediationcases, chatlogs, participants, etc.)
   - Triage Table Storage columns (casetriage, AIClassificationLog, etc.)
   - Existing analytics schema columns

   Target: 500+ column entries covering the full EEOC data vocabulary.
   Each entry: column_name, label, description, category, pii_tier,
   and optionally resolve_via (for FK lookups).

   This registry is the SINGLE SOURCE OF TRUTH for column labeling
   across the entire platform. When the AI Assistant, Superset, or
   JupyterHub need to display a column label, they use this registry.

5. Human review workflow:
   - Auto-generated tables get review_status = "pending_review"
   - Create a CLI command: lifecycle review-schema {table_name}
     Displays: table name, all columns with auto-generated labels,
     PII tier assignments, FK resolutions, suggested metrics
   - Reviewer can: approve, modify labels, change PII tiers, add/remove columns
   - After review: review_status → "approved", dataset_metadata updated
   - Unapproved tables are still queryable but marked in AI responses:
     "Note: This dataset was auto-generated and is pending review.
      Column labels may not be fully accurate."

6. Daily CronJob (data-middleware/auto_schema_cronjob.py):
   - Schedule: 06:00 UTC daily (after CDC sync + reconciliation + dbt)
   - Runs SchemaDetector.detect_new_replica_tables()
   - For each new table: auto-label, auto-create, auto-model, auto-metadata
   - Sends notification (Teams webhook or email) listing new datasets:
     "3 new datasets auto-discovered: analytics.charge_transfer (12 columns),
      analytics.enforcement_conference (8 columns), analytics.case_folder (6 columns).
      Review pending at: lifecycle review-schema {table_name}"

7. Configuration:
   - AUTO_SCHEMA_ENABLED (default: true)
   - AUTO_LABEL_AI_ENABLED (default: false — use registry + patterns first)
   - AUTO_SCHEMA_NOTIFY_WEBHOOK (Teams/email for new dataset notifications)
   - COLUMN_REGISTRY_PATH (default: data-middleware/column_registry.yaml)
   - DATASET_METADATA_PATH (default: data-middleware/dataset_metadata/)
   - AUTO_SCHEMA_DEFAULT_PII_TIER (default: 2 — conservative, assume internal)

Write a CHANGES.md and unified diff.
```

---

## Prompt 53: Triage Multi-Tenancy — Office Hierarchy, District Scoping, 508 Compliance

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (foundation for OFP intake — must complete before Prompts 54-58)

### Prompt

```
The Triage system currently operates as a single national instance for OFS
(Office of Federal Operations). OFP (Office of Field Programs) intake
requires district-level scoping where each district office team of intake
coordinators only sees their own cases. OFS remains national (single team,
no district scoping needed).

Add multi-tenancy, office hierarchy, and 508 compliance to Triage. Model
after ADR's implementation in eeoc-ofs-adr/ (see mediation_app.py lines
6638-6990, helpers/office_hierarchy.py, data/pg_client.py, static/css/app.css).

1. Add Sector field to case entities:
   In case-processor-function/CaseFileProcessor/__init__.py:
   - Add Sector field ("OFS" or "OFP") to all case entities written to
     casetriage table and PostgreSQL operations.triage_cases
   - Default to "OFS" for backward compatibility
   - Sector determined by: explicit upload parameter, ARC office code mapping,
     or configuration default

   In triage_webapp/ templates and blueprints:
   - Display sector badge on each case in dashboard
   - Sector-aware terminology:
     OFS: "Complainant" / "Agency"
     OFP: "Charging Party" / "Respondent"
   - Rank meaning labels per sector:
     OFS: A="Priority/Merit", B="Further Investigation", C="Decision Letter Queue"
     OFP: A="Refer to Legal", B="Refer to ADR", C="Issue NRTS"

2. Office hierarchy (copy ADR pattern):
   Create triage_webapp/helpers/office_hierarchy.py:
   - officestructure table (Azure Table Storage):
     PartitionKey = sector ("OFS" or "OFP")
     RowKey = office_id
     Fields: Name, OfficeType, ParentOfficeId, SortOrder, TimeZone, Active
   - _get_office_tree() builds parent-child tree in memory
   - _get_subtree_office_ids(office_id, tree) recursively collects children
   - Cycle detection via visited set
   - OFS has one entry (HQ national team). OFP has district hierarchy:
     OFP Director → Regional Director(s) → District Director/Manager →
     Supervisor(s) → Intake Coordinator(s)

   Create staffassignments and supervisorsubordinates tables:
   - staffassignments: PartitionKey=user_oid, stores role, office_id, sector
   - supervisorsubordinates: PartitionKey=manager_oid, RowKey=subordinate_oid
   - Roles: intake_coordinator, supervisor, director, admin

3. Three-layer access control (match ADR):
   Layer 1 — Session scoping (triage_app.py):
   - On login, populate session with:
     staff_role, office_id, sector, subordinate_coordinator_ids
   - Admin: sees everything
   - Director/Supervisor: sees cases for all subordinate coordinators + own office subtree
   - Intake Coordinator: sees only own assigned cases
   - OFS users: see all OFS cases (national, no district filter)

   Layer 2 — Query filtering (blueprints/cases.py):
   - OData/SQL queries filtered by sector + office subtree
   - OFS queries: PartitionKey filter only (no office scoping)
   - OFP queries: sector='OFP' AND (assigned_coordinator IN [subordinates]
     OR office_id IN [subtree])
   - Batch optimization: split large coordinator lists into ≤15 OR conditions

   Layer 3 — PostgreSQL RLS (when PG_MIGRATION_MODE active):
   - SET LOCAL app.current_role, app.current_sector, app.current_office
   - RLS policy filters operations.triage_cases by sector + office

4. Dashboard scoping:
   In triage_webapp/blueprints/cases.py:
   - Add sector filter dropdown (OFS / OFP / All — admin only for All)
   - Add district/office filter dropdown (OFP only, populated from hierarchy)
   - Case counts per district in sidebar (OFP directors/supervisors)
   - Hide district filter for OFS users (irrelevant — one national team)

5. Statistics rollup per office:
   Copy ADR's MetricsRollupHourly/Daily pattern:
   - Create case-processor-function/MetricsRollupHourly/__init__.py:
     Timer trigger, counts new cases per hour per office per sector
     Tracks rank distribution (A/B/C counts), AI accept/correction rates
   - Create case-processor-function/MetricsRollupDaily/__init__.py:
     Aggregates hourly metrics, calculates daily KPIs per office
   - Stats API endpoints (triage_webapp/stats/api.py):
     Extend existing stats endpoints with office_id and sector filters
     Add: /api/stats/by-office (breakdown per district)

6. 508 compliance:
   Copy ADR's accessibility patterns:
   - Create/update triage_webapp/static/css/accessibility.css:
     Override Bootstrap defaults for 4.5:1+ contrast ratios:
       .text-muted: #5a6472 (6.0:1)
       .text-info: #087990 (7.1:1)
       .text-warning: #997404 (5.7:1)
       .text-danger: #b02a37 (6.5:1)
       --bs-border-color: #737373 (4.7:1)
     Force dark text on light badges (bg-info, bg-warning)
     Minimal color palette — avoid decorative colors
   - Add axe-core accessibility tests:
     Create triage_webapp/tests/test_508_accessibility.py
     Playwright + axe.min.js injection
     WCAG 2.1 AA audit on: login page, dashboard, case detail, admin page
     Tags: wcag2a, wcag2aa, wcag21aa
   - Ensure all images have alt text, forms have labels, headings are sequential
   - Add <html lang="en"> if missing

7. Admin UI for office management:
   In triage_webapp/blueprints/admin.py:
   - Add /admin/offices route: view and manage office hierarchy
   - Add /admin/staff route: assign users to offices and roles
   - Import from CSV/JSON for bulk setup
   - Audit log: who changed office assignments and when

8. Configuration:
   - TRIAGE_DEFAULT_SECTOR: "OFS" (default)
   - OFP_MULTI_TENANCY_ENABLED: true (default, disable to run OFP as national)
   - OFFICE_HIERARCHY_CACHE_TTL_SECONDS: 300 (5 minute cache)

Write a CHANGES.md and unified diff.
```

---

## Prompt 54: Triage OFP Intake Pipeline — Case Pull and AI Classification

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (depends on Prompt 53 for multi-tenancy + Prompt 57 for OFP RAG library)

### Prompt

```
Build the OFP intake pipeline for Triage. OFP (Office of Field Programs)
processes private-sector discrimination charges. Unlike OFS, OFP intake:
- Reviews charging party information only (employer does not know about the
  case at this stage — no respondent documents)
- Case data arrives when the charge is filed in ARC
- Classification delay is configurable (default 5 days) to allow additional
  documents from the charging party before AI review
- Each district office has its own team of intake coordinators

The existing CaseFileProcessor handles OFS. OFP uses the same AI pipeline
but with different scoring configuration, system prompts, and training data.

PREREQUISITE: Prompt 53 (multi-tenancy) must be complete. Prompt 57
(RAG library expansion) should be complete for full OFP legal framework.

1. OFP case detection from CDC pipeline:
   Create case-processor-function/OFPCaseMonitor/__init__.py:
   - Timer trigger: runs every 15 minutes
   - Queries UDIP analytics tables (via UDIP API or direct PostgreSQL read replica)
     for new charges matching OFP criteria:
     a. accountabilityOfficeCode maps to an OFP district office
     b. Status = CHARGE_FILED (or configurable status list)
     c. Not already in casetriage table
   - For each new case:
     a. Check classification delay: if charge_filed_date + OFP_REVIEW_DELAY_DAYS
        > now(), skip (not ready yet). If delay = 0, process immediately.
     b. Pull case metadata from ARC via Integration API
        (GET /arc/v1/charges/{charge_number}/metadata)
     c. Pull available case files/documents from ARC document store
        (charging party uploads only — filter by isUploadableByChargingParty)
     d. Create entry in casetriage table with Sector="OFP",
        office_id from accountabilityOfficeCode mapping,
        status="PENDING_REVIEW"
     e. Queue for CaseFileProcessor if documents are available
     f. If no documents yet: mark status="AWAITING_DOCUMENTS"
   - Configuration:
     OFP_CASE_MONITOR_ENABLED: true (default)
     OFP_REVIEW_DELAY_DAYS: 5 (default, 0 = immediate)
     OFP_TRIGGER_STATUS: "CHARGE_FILED" (configurable, comma-separated list)
     OFP_CASE_MONITOR_INTERVAL_MINUTES: 15

   Fallback timer logic:
   - If ARC has a "ready for review" flag (future): use that as trigger
   - Until then: charge_filed_date + OFP_REVIEW_DELAY_DAYS
   - If delay is 0: classify immediately on detection
   - Timer is per-case, not global (each case has its own delay window)

2. OFP-specific classification in CaseFileProcessor:
   In CaseFileProcessor/__init__.py:
   - Add sector-aware processing branch:
     if case.sector == "OFP":
       use OFP system prompt, OFP thresholds, OFP RAG filter
     else:
       use existing OFS logic (unchanged)

   - OFP system prompt (new):
     "You are an experienced EEOC private-sector intake analyst reviewing
      a Title VII/ADA/ADEA/EPA/GINA discrimination charge. The charging
      party has filed a charge against a private employer. At this stage,
      only the charging party's information is available — the respondent
      (employer) has not been notified and has not submitted a position
      statement. Evaluate based solely on the charging party's allegations
      and supporting documents."
     Include private sector legal references:
     - Title VII procedural requirements (29 CFR Parts 1601-1610)
     - McDonnell Douglas burden-shifting framework
     - NRTS issuance criteria
     - Reference EEOC Compliance Manual sections (if in RAG)
     - Reference Strategic Enforcement Plan priorities (if in RAG)

   - OFP scoring thresholds (separate from OFS):
     OFP_THRESH_A: 78 (default, same as OFS initially)
     OFP_THRESH_B: 59 (default, same as OFS initially)
     These are independently configurable for future calibration

   - OFP rank output labels:
     Rank A: "REFER_TO_LEGAL" (not "Priority/Merit")
     Rank B: "REFER_TO_ADR" (not "Further Investigation")
     Rank C: "ISSUE_NRTS" (not "Low Merit/Closure")

   - OFP scoring weights (initially same as OFS, separately configurable):
     OFP_WEIGHT_PRIMA_FACIE: 0.28
     OFP_WEIGHT_EVIDENCE: 0.22
     OFP_WEIGHT_PRETEXT: 0.22
     OFP_WEIGHT_PROCEDURE: 0.18
     OFP_WEIGHT_AGENCY_REASON: 0.10
     Note: agency_reason factor may not be meaningful for OFP since
     there is no employer response at intake stage. Keep for now but
     document that this weight should be redistributed once OFP has
     its own calibration dataset.

   - OFP RAG query filter:
     When querying Azure AI Search for OFP cases, add filter:
     "sector_relevance eq 'OFP' or sector_relevance eq 'BOTH'"
     This ensures OFS-specific federal sector documents are not retrieved
     (requires Prompt 57 to add sector_relevance field to index)

   - OFP calibration data:
     OFP will have its own calibration dataset (separate from the OFS
     412-case OIG audit set). Until available:
     a. Use OFS weights as starting point
     b. Track OFP correction rates separately in model drift detection
     c. Flag in UI: "OFP scoring model is in calibration phase"

3. New document arrival notification:
   In case-processor-function/OFPCaseMonitor/__init__.py:
   - When monitoring detects a new document uploaded to an already-classified
     case (CDC streams document events from ARC):
     a. Update case status: add "NEW_DOCUMENT_AVAILABLE" flag
     b. Do NOT auto-reclassify (coordinator or attorney decides)
     c. Dashboard shows indicator: document icon badge on the case row
   - In triage_webapp/blueprints/cases.py:
     a. Display "New documents available" badge on cases with the flag
     b. Add "Re-analyze" button: coordinator clicks → clears flag →
        re-queues case for CaseFileProcessor with updated documents
     c. Re-analysis creates new classification record (preserves history)
     d. Audit log: who triggered re-analysis and when

4. OFP dashboard view:
   In triage_webapp/blueprints/cases.py and templates/dashboard.html:
   - OFP-specific columns:
     District Office, Intake Coordinator (assigned), Days Since Filing,
     Classification Status, Rank, New Documents indicator
   - OFP-specific filters:
     District office dropdown, coordinator dropdown, date range,
     rank filter, status filter (Pending/Classified/Re-analysis Needed)
   - OFP rank color coding:
     A (red): Refer to Legal — high priority
     B (yellow): Refer to ADR — standard processing
     C (gray): Issue NRTS — administrative closure
   - Case detail view shows:
     Charging party information only (no respondent section for OFP)
     AI analysis with OFP-specific rank meaning
     Document list with upload timestamps
     Classification history (if re-analyzed)

5. OFP training/learning pipeline:
   Extend TrainingBatchProcessor for OFP:
   - Separate PromptExamples partition for OFP: PartitionKey="ofp_examples"
   - OFP corrections stored separately from OFS corrections
   - OFP model drift tracked independently (ModelDriftDetector)
   - OFP reliance scores tracked independently (RelianceScorer)

6. Configuration summary:
   - OFP_CASE_MONITOR_ENABLED: true
   - OFP_REVIEW_DELAY_DAYS: 5 (0 = immediate)
   - OFP_TRIGGER_STATUS: "CHARGE_FILED"
   - OFP_THRESH_A: 78
   - OFP_THRESH_B: 59
   - OFP_WEIGHT_*: same as OFS initially (6 weights)
   - OFP_RAG_SECTOR_FILTER: true (requires Prompt 57)
   - OFP_CALIBRATION_PHASE: true (show calibration warning in UI)

Write a CHANGES.md and unified diff.
```

---

## Prompt 55: Triage ARC Write-Back — Classification Routing

**Repository:** `eeoc-ofs-triage/` and `eeoc-arc-integration-api/`
**Owner:** Triage team + Hub team
**Phase:** 3 (depends on Prompt 53 for multi-tenancy)

### Prompt (ARC Integration API — run in eeoc-arc-integration-api/)

```
Add triage classification write-back endpoints to the ARC Integration API.
When Triage classifies a case, the result must be pushed back to ARC so
ARC's own workflow can route the case to the appropriate queue (attorney,
ADR, NRTS issuance, etc.).

The write-back sets a flag/field on the ARC charge record. The exact ARC
field will be determined with the ARC team — design the endpoint so the
field mapping is easily adjustable via configuration.

1. Create app/routers/triage.py:

   POST /arc/v1/charges/{charge_number}/triage-classification
   Auth: managed identity (Triage function app identity)
   Request body:
   {
     "charge_number": "string",
     "sector": "OFS" | "OFP",
     "rank": "A" | "B" | "C",
     "rank_label": "REFER_TO_LEGAL" | "REFER_TO_ADR" | "ISSUE_NRTS" |
                   "PRIORITY_MERIT" | "FURTHER_INVESTIGATION" | "DECISION_LETTER_QUEUE",
     "merit_score": 0-100,
     "classification_id": "UUID (Triage internal reference)",
     "classified_by": "hashed OID of coordinator who approved",
     "classified_at": "ISO 8601 timestamp",
     "summary": "one-sentence AI classification summary",
     "recommended_action": "string (human-readable next step)"
   }

   Processing:
   a. Validate charge_number exists in ARC (GET charge metadata)
   b. Map rank_label to ARC field value:
      TRIAGE_FIELD_MAPPING config (YAML or JSON):
      {
        "target_field": "triage_classification_status",  # ARC field name
        "value_mapping": {
          "REFER_TO_LEGAL": "TRIAGE_A_LEGAL",
          "REFER_TO_ADR": "TRIAGE_B_ADR",
          "ISSUE_NRTS": "TRIAGE_C_NRTS",
          "PRIORITY_MERIT": "TRIAGE_A_MERIT",
          "FURTHER_INVESTIGATION": "TRIAGE_B_INVESTIGATE",
          "DECISION_LETTER_QUEUE": "TRIAGE_C_DECISION_LETTER"
        }
      }
   c. Write to ARC: PATCH /prepa/charges/{charge_number}
      with { [target_field]: mapped_value }
   d. If ARC write succeeds: return 200 with { "status": "written",
      "arc_field": target_field, "arc_value": mapped_value }
   e. If ARC write fails: return 502 with error, log to audit

   The field mapping is the ONLY thing that needs to change when the
   ARC team confirms the exact field name. No code changes required.

2. POST /arc/v1/charges/{charge_number}/triage-nrts-request
   Auth: managed identity
   Request body:
   {
     "charge_number": "string",
     "closure_reason": "string (from ARC ClosureReason enum)",
     "classification_id": "UUID",
     "requested_by": "hashed OID"
   }

   Processing:
   a. Validate charge exists and is in a state that allows NRTS
   b. Write to ARC: trigger NRTS issuance via PrEPA endpoint
      (ARC already has NoticeOfRightToSueService — this just triggers it)
   c. Log to audit trail
   d. Return: { "status": "nrts_requested", "charge_number": "..." }

   Note: This does NOT generate the letter. ARC's existing
   NoticeOfRightToSueService handles letter generation. Triage
   only triggers the process.

3. Audit logging:
   - Every write-back logged to arcintegrationaudit table (Prompt 42):
     EventType="triage_classification" or "triage_nrts_request"
     Full request/response payloads, HMAC-signed
   - Failed writes logged with retry status

4. Configuration:
   - TRIAGE_FIELD_MAPPING_PATH: path to field mapping config file
     (default: app/config/triage_field_mapping.yaml)
   - TRIAGE_WRITEBACK_ENABLED: true (default, feature flag)
   - Create app/config/triage_field_mapping.yaml with the default mapping

Write a CHANGES.md and unified diff.
```

### Prompt (Triage — run in eeoc-ofs-triage/)

```
Integrate ARC write-back into Triage for classification routing. When an
intake coordinator approves a classification, push the result to ARC via
the Integration API so ARC's workflow routes the case.

1. Create triage_webapp/arc_writeback.py:
   - write_classification(charge_number, sector, rank, rank_label,
     merit_score, classification_id, classified_by, summary):
     POST to {ARC_INTEGRATION_API_URL}/arc/v1/charges/{charge_number}/triage-classification
     Auth: managed identity token for ARC Integration API scope
     Retry: 3 attempts with exponential backoff
     On failure: log error, mark case as "WRITEBACK_FAILED" in dashboard
     Non-blocking: classification stands even if write-back fails

   - request_nrts(charge_number, closure_reason, classification_id, requested_by):
     POST to {ARC_INTEGRATION_API_URL}/arc/v1/charges/{charge_number}/triage-nrts-request
     Same auth/retry/failure pattern

2. Human approval workflow:
   In triage_webapp/blueprints/cases.py:
   - Add "Approve & Route" button on classified cases (replaces simple "Mark Reviewed")
   - Button click:
     a. Logs coordinator approval to audit trail
     b. Calls arc_writeback.write_classification()
     c. For OFP Rank C: also calls arc_writeback.request_nrts()
     d. Updates case status: "ROUTED_TO_ARC"
     e. Shows confirmation: "Classification sent to ARC — Rank {X}: {action}"
   - Add "Route Failed" indicator for cases where write-back failed
   - Add "Retry Route" button for failed write-backs

   Role requirement: only supervisor+ can approve routing (coordinators
   classify, supervisors approve the routing to ARC). Configurable:
   TRIAGE_ROUTING_APPROVAL_ROLE: "supervisor" (default)

3. OFS Rank C special handling:
   - OFS Rank C cases are NOT routed to ARC for NRTS
   - Instead, OFS Rank C cases enter a "Decision Letter Queue" (see Prompt 56)
   - If Prompt 56 (decision letter) is not enabled: OFS Rank C cases
     write a standard classification to ARC and the OFS team handles
     closure through their normal ARC workflow
   - Feature flag: OFS_DECISION_LETTER_ENABLED (default: false)

4. Dashboard status tracking:
   Add routing status column to dashboard:
   - PENDING_CLASSIFICATION: AI processing in progress
   - CLASSIFIED: AI complete, awaiting coordinator review
   - APPROVED: Coordinator reviewed, awaiting supervisor approval
   - ROUTED_TO_ARC: Write-back succeeded
   - WRITEBACK_FAILED: Write-back failed (retry available)
   - NRTS_REQUESTED: OFP Rank C, NRTS triggered in ARC
   - DECISION_LETTER_QUEUE: OFS Rank C (Prompt 56 flow)

5. Configuration:
   - ARC_WRITEBACK_ENABLED: false (default — enable when ARC field confirmed)
   - ARC_INTEGRATION_API_URL: (required when enabled)
   - ARC_INTEGRATION_API_SCOPE: (Entra ID scope for managed identity)
   - TRIAGE_ROUTING_APPROVAL_ROLE: "supervisor" (who can approve routing)
   - OFS_DECISION_LETTER_ENABLED: false (default — see Prompt 56)

Write a CHANGES.md and unified diff.
```

---

## Prompt 56: OFS Rank C Decision Letter — AI-Assisted Generation

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (depends on Prompt 55 for routing workflow)

### Prompt

```
OPTIONAL FEATURE — disabled by default.

OFS Rank C cases (low merit/closure) enter a decision letter queue where
an attorney reviews an AI-generated letter before it goes through ARC's
closure workflow. This is a convenience feature — without it, OFS attorneys
write these letters manually.

Model letter generation after ADR's settlement agreement pattern
(see eeoc-ofs-adr/adr_functionapp/MediationProcessor/__init__.py lines
89-1100 for the dual template approach).

1. Decision letter template:
   Create a DOCX template: OFS_Decision_Letter_Template.docx
   Upload to priority-docs blob container (same as ADR templates)
   Configurable blob name: OFS_DECISION_LETTER_TEMPLATE_BLOB

   Placeholder variables:
   [COMPLAINANT_NAME]           — from ARC charge metadata
   [AGENCY_NAME]                — from ARC charge metadata
   [EEOC_CASE_NUMBER]           — charge_number
   [FILING_DATE]                — from ARC
   [BASIS_LIST]                 — discrimination bases (Race, Sex, Age, etc.)
   [ISSUE_LIST]                 — charge issues (Termination, Harassment, etc.)
   [DECISION_SUMMARY]           — AI-generated summary of why case lacks merit
   [APPLICABLE_STATUTES]        — statutes cited in AI analysis
   [CLOSURE_DATE]               — date of letter
   [REVIEWING_ATTORNEY_NAME]    — from session (attorney who approves)
   [OFFICE_DIRECTOR_NAME]       — configurable

2. System prompt text fallback:
   Create triage_webapp/templates/decision_letter_text.py:
   - Plain-text template with the same placeholders
   - Used when DOCX template is not available in blob storage
   - Includes standard boilerplate:
     a. Header: U.S. Equal Employment Opportunity Commission letterhead format
     b. Opening: "Dear [COMPLAINANT_NAME],"
     c. Body paragraph 1: case identification and basis summary
     d. Body paragraph 2: AI-generated decision summary explaining why
        the case does not meet the threshold for further processing
     e. Body paragraph 3: right to request reconsideration (standard language)
     f. Body paragraph 4: right to file in federal court (standard language)
     g. Closing: reviewing attorney name and title, OFS Director name

3. AI decision summary generation:
   In case-processor-function/CaseFileProcessor/__init__.py or new module:
   - When an OFS Rank C case enters the decision letter queue:
     a. Take the existing AI detailed_analysis from classification
     b. Generate a letter-appropriate summary using a separate LLM call:
        System prompt: "You are drafting a formal EEOC decision letter
        paragraph explaining why a federal-sector EEO complaint does not
        meet the threshold for further processing. Write in formal,
        neutral government prose. Do not editorialize. Cite specific
        deficiencies in the complaint (procedural, evidentiary, or
        prima facie). Keep to 2-3 sentences."
     c. Store generated summary in case entity: decision_letter_summary
     d. Log to AI audit trail

4. Letter review workflow:
   In triage_webapp/blueprints/cases.py:
   - New route: GET /cases/{case_id}/decision-letter
     Displays the generated letter in a review interface
     Attorney can:
     a. View the complete letter with all placeholders filled
     b. Edit any section (rich text editor, same Quill.js as ADR if available)
     c. Approve: triggers ARC closure write-back + letter storage
     d. Reject: sends case back for re-classification or manual handling
     e. Regenerate: request new AI summary with different prompt parameters

   - POST /cases/{case_id}/decision-letter/approve
     a. Generates final DOCX from template + filled placeholders
     b. Stores letter in WORM blob (ai-generation-archive, 7-year retention)
     c. Logs approval to audit trail: who approved, when, letter hash
     d. Writes closure to ARC via Integration API:
        POST /arc/v1/charges/{charge_number}/triage-classification
        with rank_label="DECISION_LETTER_QUEUE" and closure metadata
     e. Updates case status: "LETTER_APPROVED"
     f. Optionally triggers ARC closure workflow
        (feature flag: AUTO_ARC_CLOSURE_ON_LETTER_APPROVAL, default: false)

5. DOCX generation:
   - If DOCX template exists in blob: download, replace placeholders,
     save to WORM blob, return download link
   - If no template: use python-docx to build from text template
     (same pattern as ADR's _build_generic_settlement_docx)
   - Font: Times New Roman 12pt (legal standard)
   - 508 compliance: proper heading structure, readable formatting
   - Include HTML-to-DOCX conversion for edited content
     (copy ADR's html_to_docx.py if Quill.js editor is used)

6. Dashboard integration:
   - Decision Letter Queue view: filtered list of OFS Rank C cases
     awaiting letter review
   - Status indicators:
     LETTER_GENERATING: AI summary in progress
     LETTER_READY: letter generated, awaiting attorney review
     LETTER_APPROVED: attorney approved, sent to ARC
     LETTER_REJECTED: attorney rejected, needs manual handling
   - Queue depth metric in stats dashboard

7. Configuration:
   - OFS_DECISION_LETTER_ENABLED: false (default — entire feature opt-in)
   - OFS_DECISION_LETTER_TEMPLATE_BLOB: "OFS_Decision_Letter_Template.docx"
   - OFS_DECISION_LETTER_CONTAINER: "priority-docs"
   - OFS_OFFICE_DIRECTOR_NAME: (configurable, appears on letter)
   - AUTO_ARC_CLOSURE_ON_LETTER_APPROVAL: false (default)
   - DECISION_LETTER_LLM_TEMPERATURE: 0.2 (slightly higher than classification
     for natural prose, but still controlled)

Write a CHANGES.md and unified diff.
```

---

## Prompt 57: Triage RAG Library Expansion — New Categories and Sector Filtering

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (should complete before Prompt 54 for full OFP legal framework)

### Prompt

```
Expand the Triage RAG library to support OFP-specific legal documents and
improve document categorization. Currently the library has 7 categories
(Statute, CFR, Primary Case, Secondary Case, Admin Policy, ADR Guidance,
ADR Mediation Material). The last 2 are filtered out of RAG queries.

Add new categories for EEOC-specific document types and add sector
filtering so OFS and OFP cases retrieve the most relevant legal context.

1. Expand CATEGORY_MAP in triage_webapp/blueprints/library.py:
   Add new categories:
   {
     "statutes": "Statute",
     "cfr": "CFR",
     "primary cases": "Primary Case",
     "secondary cases": "Secondary Case",
     "admin policy": "Admin Policy",
     "adr guidance": "ADR Guidance",              # filtered out of RAG
     "adr mediation material": "ADR Mediation Material",  # filtered out
     "sep": "Strategic Enforcement Plan",          # NEW
     "compliance_manual": "Compliance Manual",     # NEW
     "commission_guidance": "Commission Guidance",  # NEW
     "nrts_guidance": "NRTS Guidance"              # NEW (OFP-relevant)
   }

   New category descriptions:
   - Strategic Enforcement Plan: EEOC Commission SEP priority areas and
     enforcement focus areas. Updated every few years. Critical for
     understanding agency priorities when scoring cases.
   - Compliance Manual: EEOC Compliance Manual sections covering
     discrimination theories, evidence standards, remedies, procedures.
     Core reference for both OFS and OFP analysis.
   - Commission Guidance: EEOC Commission policy guidance documents,
     enforcement guidance, technical assistance documents.
   - NRTS Guidance: Procedures and criteria for Notice of Right to Sue
     issuance. Primarily relevant to OFP Rank C processing.

2. Add sector_relevance field to Azure AI Search index:
   In provision_azure.sh or the index creation script:
   - Add field: sector_relevance (Edm.String, Filterable)
   - Values: "OFS", "OFP", or "BOTH"
   - Default: "BOTH" (most legal documents apply to both sectors)

   Category-to-sector defaults:
   - Statute → BOTH (Title VII applies to both sectors)
   - CFR → sector-specific:
     29 CFR Part 1614 → OFS (federal sector EEO process)
     29 CFR Parts 1601-1610 → OFP (private sector charge process)
   - Primary/Secondary Case → BOTH (unless tagged otherwise)
   - Admin Policy → BOTH
   - Strategic Enforcement Plan → BOTH
   - Compliance Manual → BOTH
   - Commission Guidance → BOTH
   - NRTS Guidance → OFP
   - ADR Guidance → filtered out (no sector relevant)

   In PriorityDocIndexer/__init__.py:
   - Read sector_relevance from blob metadata (default: "BOTH")
   - Write to search index as filterable field
   - Reindex existing documents with sector_relevance="BOTH" (safe default)

3. Sector-aware RAG retrieval:
   In CaseFileProcessor/__init__.py (RAG query section):
   - When building the Azure AI Search query for case analysis:
     OFS cases: filter = "category ne 'ADR Guidance' and category ne
       'ADR Mediation Material' and (sector_relevance eq 'OFS' or
       sector_relevance eq 'BOTH')"
     OFP cases: filter = "category ne 'ADR Guidance' and category ne
       'ADR Mediation Material' and (sector_relevance eq 'OFP' or
       sector_relevance eq 'BOTH')"
   - If OFP_RAG_SECTOR_FILTER is false: use existing filter (backward compat)
   - Top K remains 5 per query (configurable)

4. OFP system prompt legal references:
   Add to the OFP system prompt (Prompt 54 creates the prompt, this adds
   the legal annex section):

   "When relevant, name at least one authority (not invented):
   - Title VII of the Civil Rights Act of 1964, 42 U.S.C. § 2000e et seq.
   - Americans with Disabilities Act (ADA), 42 U.S.C. § 12101 et seq.
   - Age Discrimination in Employment Act (ADEA), 29 U.S.C. § 621 et seq.
   - Equal Pay Act (EPA), 29 U.S.C. § 206(d)
   - Genetic Information Nondiscrimination Act (GINA), 42 U.S.C. § 2000ff
   - 29 CFR Parts 1601-1610 (charge filing and processing procedures)
   - McDonnell Douglas Corp. v. Green, 411 U.S. 792 (1973) (burden shifting)
   - Texas Dept. of Community Affairs v. Burdine, 450 U.S. 248 (1981)
   - Reeves v. Sanderson Plumbing Products, 530 U.S. 133 (2000)
   - Burlington Northern & Santa Fe Ry. Co. v. White, 548 U.S. 53 (2006)"

5. Library management UI updates:
   In triage_webapp/blueprints/library.py and templates/manage_library.html:
   - Add sector_relevance dropdown on document upload: OFS / OFP / Both
   - Default to "Both" for new uploads
   - Display sector tag on library document list
   - Filter library view by sector
   - Bulk update sector_relevance for existing documents

6. Configuration:
   - OFP_RAG_SECTOR_FILTER: true (default, filter RAG by sector)
   - RAG_TOP_K: 5 (default, number of nearest neighbors per query)

Write a CHANGES.md and unified diff.
```

---

## Prompt 58: OFS Intake Timer and Case File Submission Window

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (depends on Prompt 53 for multi-tenancy)

### Prompt

```
OFS intake has a submission window where parties can submit case files,
motions, and request extensions before the case is reviewed. Unlike OFP
(where cases are reviewed shortly after filing), OFS cases must wait for
this window to close.

Build the OFS submission window tracking and auto-queue system.

1. Submission window tracking:
   In case-processor-function/OFSSubmissionMonitor/__init__.py:
   - Timer trigger: runs every 30 minutes
   - For each OFS case in casetriage with status="AWAITING_SUBMISSION_WINDOW":
     a. Calculate window close date:
        - If ARC has a filing deadline (filingDeadlineDte): use that
        - Fallback: charge_created_date + OFS_SUBMISSION_WINDOW_DAYS
     b. Check for extensions:
        - Query CDC events for extension grants on this charge
        - If extension found: recalculate window close date
        - Store: original_deadline, current_deadline, extension_count
     c. If current_deadline <= now():
        - Window closed → change status to "READY_FOR_REVIEW"
        - Queue for CaseFileProcessor
        - Pull latest case files from ARC
     d. If current_deadline > now():
        - Calculate days remaining
        - Update case entity with days_remaining for dashboard display

   Configuration:
   - OFS_SUBMISSION_WINDOW_DAYS: configurable (default TBD — coordinate
     with OFS team for the standard submission period)
   - OFS_SUBMISSION_MONITOR_ENABLED: true
   - OFS_SUBMISSION_MONITOR_INTERVAL_MINUTES: 30

2. CDC event monitoring for new filings during window:
   - Monitor CDC stream for document upload events on tracked OFS cases
   - When new document detected during submission window:
     a. Update case entity: increment document_count, update last_document_date
     b. Log: "New document received for {charge_number} during submission window"
     c. Do NOT trigger AI analysis yet (window still open)
   - When motion/extension event detected:
     a. Check if it's an extension grant
     b. If yes: update current_deadline, log extension
     c. Display in dashboard: "Extension granted — new deadline: {date}"

3. Manual override — early review:
   In triage_webapp/blueprints/cases.py:
   - Add "All Files Received — Review Now" button on cases in submission window
   - Button visible to supervisor+ role only
   - Click: closes submission window early, queues for AI classification
   - Audit log: who closed window early, original deadline, reason
   - Case status: "AWAITING_SUBMISSION_WINDOW" → "READY_FOR_REVIEW"

4. Dashboard indicators:
   In triage_webapp/templates/dashboard.html:
   - OFS Submission Window column:
     - Green: "X days remaining" (window open, on track)
     - Yellow: "2 days remaining" (approaching deadline)
     - Red: "Overdue" (past deadline, not yet queued — investigate)
     - Gray: "Window closed" (ready for or completed review)
     - Blue: "Extension granted — new deadline: {date}"
   - Document count badge: shows how many documents received during window
   - Last document date: when the most recent file was uploaded
   - All colors must meet 508 4.5:1 contrast requirements

5. OFS case flow summary:
   The complete OFS case lifecycle in Triage:
   a. Case detected via CDC (new OFS charge in ARC)
   b. Entry created: status="AWAITING_SUBMISSION_WINDOW"
   c. Submission window tracked (timer + CDC document events)
   d. Window closes (deadline reached or manual override)
   e. Status → "READY_FOR_REVIEW", queued for CaseFileProcessor
   f. AI classification runs → Rank A/B/C
   g. Coordinator reviews classification
   h. Supervisor approves routing
   i. Write-back to ARC (Prompt 55)
   j. If Rank C + OFS_DECISION_LETTER_ENABLED: enter letter queue (Prompt 56)

6. Configuration:
   - OFS_SUBMISSION_WINDOW_DAYS: (default TBD, coordinate with OFS team)
   - OFS_SUBMISSION_MONITOR_ENABLED: true
   - OFS_SUBMISSION_MONITOR_INTERVAL_MINUTES: 30
   - OFS_EXTENSION_DETECTION_ENABLED: true (monitors CDC for extensions)
   - OFS_OVERDUE_ALERT_DAYS: 3 (alert if window closed X days ago and
     case not yet queued for review)

Write a CHANGES.md and unified diff.
```

---

## Prompt 59: MCP Hub — Compliance Logging Remediation + Protocol Version Fix

**Repository:** `eeoc-mcp-hub-functions/`
**Owner:** Hub team
**Phase:** 2 (CRITICAL — blocks M-21-31 compliance for the hub)

### Prompt

```
POST-AUDIT REMEDIATION: The implementation audit found two issues in the
MCP Hub Functions repository:

1. Prompt 43 (M-21-31 compliance logging) was NOT implemented. The entire
   audit logging layer is missing — no audit_logger.py, no security.py,
   no HMAC signatures, no PII hashing, no structlog, no WORM blob archive.
   Only a basic AuditRecord model and Table Storage write for catalog
   refresh events exist.

2. Prompt 6 MCP protocol version is still 2024-11-05 in three files
   instead of 2025-03-26.

FIX ALL OF THE FOLLOWING:

PART A — Protocol Version Fix (3 files):

1. In hub_functions/models.py: change the default protocol version from
   "2024-11-05" to "2025-03-26"
2. In function_app.py: change any hardcoded "2024-11-05" to "2025-03-26"
3. In tests/conftest.py: update test fixtures to use "2025-03-26"
   Search for "2024-11-05" across the entire repo and fix every occurrence.

PART B — Full M-21-31 Compliance Logging (Prompt 43 implementation):

1. Create hub_functions/audit_logger.py:
   Use eeoc-arc-integration-api/app/audit_logger.py as the reference
   implementation — it already passes audit. Implement the same pattern:

   - Dual-write: Azure Table Storage ("hubauditlog") + WORM blob
     ("hub-audit-archive", 2555-day immutability policy)
   - HMAC-SHA256 on every record:
     Key from Key Vault: HUB_AUDIT_HMAC_KEY (minimum 32 chars)
     Signature covers: partition_key + row_key + event_type + caller_hash
     Stored as RecordHMAC field
   - Fields per record:
     PartitionKey (YYYY-MM-DD), RowKey (request_id + timestamp_micros),
     RequestID, CallerOIDHash (SHA-256 of caller OID, truncated 16 hex),
     EventType (catalog_refresh, spoke_health_check, tool_call_routed,
     spoke_registered, spoke_deregistered),
     SpokeName, ToolCount, Duration, StatusCode, LatencyMs,
     RetentionPolicy ("FOIA_7_YEAR"), DataClassification ("OPERATIONAL"),
     RecordHMAC, Timestamp_UTC
   - Content truncation at 32KB with blob overflow (BlobArchivePath)
   - Lazy initialization with double-checked locking
   - Immutability policy verification at startup

2. Create hub_functions/security.py:
   - hash_pii(value: str) → str:
     HMAC-SHA256 with salt from Key Vault (HUB_AUDIT_HASH_SALT)
     Truncate to 16 hex characters
     Apply to ALL caller identifiers before logging
   - validate_request_id(request_id: str) → str:
     Sanitize and validate X-Request-ID header

3. Add correlation ID propagation:
   - In function_app.py: extract X-Request-ID from HTTP trigger requests,
     generate UUID if not provided, echo in response headers
   - In catalog_service.py: propagate X-Request-ID when calling spokes
   - Include request_id in ALL log entries and audit records

4. Replace logging with structlog:
   - Add structlog to requirements.txt
   - Configure structlog with JSON output, UTC timestamps, log level,
     request_id context variable
   - Replace all logging.getLogger() calls with structlog.get_logger()

5. Add audit logging to ALL operations:
   - Catalog refresh: log spokes contacted, tools per spoke, total tools,
     duration, errors
   - Spoke health check: log spoke name, status, response time
   - Spoke registration/deregistration: log spoke name, URL, registered_by
   - Tool catalog request: log requester, categories, tools returned
   - Every HTTP trigger: log request_id, method, path, status, latency

6. AU-5 failure handling:
   - Retry audit writes 3 times with exponential backoff (0.5s, 1s, 2s)
   - On all retries exhausted: log to stderr, continue serving
   - Never block hub operations for audit failures

7. Update existing AuditRecord model in models.py:
   - Add missing fields: RequestID, CallerOIDHash, EventType, SpokeName,
     RetentionPolicy, RecordHMAC, StatusCode, LatencyMs, DataClassification
   - Keep existing fields (refresh_id, spokes_healthy, etc.) as additional
     context fields

8. Update tests:
   - Add tests/test_audit_logger.py: test HMAC computation, PII hashing,
     dual-write, retry logic, blob overflow
   - Update test_function_app.py: verify audit logging is called on
     every HTTP trigger

Write a CHANGES.md and unified diff.
```

---

## Prompt 60: OGC Trial Tool — License Remediation Completion + CI Pipeline Fix

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 2 (HIGH — license/SCA blockers + CI gap)

### Prompt

```
POST-AUDIT REMEDIATION: The implementation audit found two incomplete
prompts in the OGC Trial Tool:

1. Prompt 46 (license remediation) was PARTIALLY implemented:
   - pdf2image is STILL in trial_tool_functionapp/requirements.txt and
     imported in DocumentIndexer/__init__.py (line 96: from pdf2image
     import convert_from_bytes). poppler-utils (GPL-2.0) remains a
     runtime dependency.
   - python-jose is STILL in trial_tool_webapp/requirements.txt and used
     in mcp_server.py (line 86: from jose import jwt). Was supposed to
     be replaced with PyJWT.
   - MODEL_LICENSES.md was never created.
   - openai and azure-identity use >= instead of == in both requirements
     files.

2. Prompt 12 (CI/CD) is missing a build-and-test.yml workflow. Only
   security-audit-evidence.yml exists. Tests are never run in CI.

FIX ALL OF THE FOLLOWING:

PART A — Complete pdf2image removal:

1. In trial_tool_functionapp/requirements.txt:
   - Remove pdf2image entirely

2. In trial_tool_functionapp/DocumentIndexer/__init__.py:
   - Remove: from pdf2image import convert_from_bytes
   - Replace PDF-to-image conversion with pdfplumber (already in the
     project) or pypdf (also available):
     - If convert_from_bytes was used for page rendering/OCR:
       replace with pdfplumber.open(io.BytesIO(pdf_bytes)) and iterate
       pages with page.extract_text()
     - If it was used for image extraction: use pdfplumber page images
       or pypdf page extraction
   - Test that PDF processing still works after the replacement

PART B — Replace python-jose with PyJWT:

1. In trial_tool_webapp/requirements.txt:
   - Remove: python-jose[cryptography]
   - Add: PyJWT[crypto]==2.9.0 (or latest stable, pinned)
   - Add: cryptography (if not already present, needed by PyJWT[crypto])

2. In trial_tool_webapp/mcp_server.py:
   - Replace: from jose import jwt, JWTError, jwk
   - With: import jwt from jwt.exceptions import PyJWTError
   - Update jwt.decode() calls to match PyJWT API:
     python-jose: jwt.decode(token, key, algorithms=["RS256"], audience=...)
     PyJWT: jwt.decode(token, key, algorithms=["RS256"], audience=...)
     (API is similar but error classes differ)
   - Replace JWTError catches with PyJWTError (or jwt.exceptions.*)
   - JWKS key handling: python-jose uses jwk.construct(key_data),
     PyJWT uses jwt.algorithms.RSAAlgorithm.from_jwk(key_data)
   - Test: verify MCP server JWT validation still works after the swap

PART C — Pin all dependencies:

1. In trial_tool_webapp/requirements.txt:
   - Change openai>=1.14.0 to openai==1.14.0 (or current installed version)
   - Change azure-identity>=1.15.0 to azure-identity==1.15.0 (or current)
   - Verify ALL other entries use == pinning

2. In trial_tool_functionapp/requirements.txt:
   - Same: pin openai and azure-identity to exact versions
   - Verify all entries use == pinning

PART D — Create MODEL_LICENSES.md:

1. Create trial_tool_webapp/MODEL_LICENSES.md documenting:
   - The Trial Tool now uses Azure OpenAI (via FoundryModelProvider)
   - Model: GPT-4o — licensed through Azure OpenAI Service agreement
   - Azure OpenAI is a Microsoft managed service, FedRAMP High authorized
   - No local model files, no Ollama, no direct model licensing concerns
   - If embeddings are used: text-embedding-3-small via Azure OpenAI
   - Previous Ollama models (Llama, Mistral) have been removed
   - Government use: Azure OpenAI Service terms govern usage, not
     individual model community licenses

PART E — Create build-and-test.yml:

1. Create .github/workflows/build-and-test.yml:
   Model after eeoc-arc-integration-api/.github/workflows/build-and-test.yml
   (which already passes audit). Include:

   Jobs:
   - lint: ruff check + format validation
   - test: pytest with coverage (target 80%)
     - Install both webapp and functionapp requirements
     - Run tests from tests/ directory
   - build-container: Docker build (if Dockerfile exists, otherwise skip)
   - container-scan: Trivy (if container built)
   - secret-scan: gitleaks with full history

   Triggers: push to main/feature/*/fix/*/refactor/*, PRs to main

Write a CHANGES.md and unified diff.
```

---

## Prompt 61: Triage OFP Case Monitor Recovery

**Repository:** `eeoc-ofs-triage/`
**Owner:** Triage team
**Phase:** 3 (HIGH — OFP intake pipeline non-functional)

### Prompt

```
POST-AUDIT REMEDIATION: The implementation audit found that
case-processor-function/OFPCaseMonitor/__init__.py source file is MISSING.
The directory exists and compiled .pyc files are present, but the actual
Python source was not committed or was lost.

The OFPCaseMonitor is the timer-triggered Azure Function that detects new
OFP cases from the CDC pipeline and queues them for AI classification.
Without it, the OFP intake pipeline (Prompt 54) does not function.

Reconstruct OFPCaseMonitor/__init__.py based on the Prompt 54 specification
and the patterns established in the repository. Use OFSSubmissionMonitor/
__init__.py (which exists and works, 401 lines) as the structural template.

1. Create case-processor-function/OFPCaseMonitor/__init__.py:

   Timer trigger: runs every 15 minutes (configure in function.json)

   Main function flow:
   a. Acquire distributed lock (same pattern as OFSSubmissionMonitor)
   b. Query UDIP analytics tables (via read replica or UDIP API) for new
      charges matching OFP criteria:
      - accountabilityOfficeCode maps to an OFP district office
        (use office hierarchy lookup from triage_webapp/helpers/office_hierarchy.py)
      - Status = CHARGE_FILED (configurable via OFP_TRIGGER_STATUS env var)
      - Not already in casetriage table (check by charge_number)
   c. For each new case:
      - Check classification delay: if charge_filed_date + OFP_REVIEW_DELAY_DAYS
        > now(), skip (not ready). If delay = 0, process immediately.
      - Pull case metadata from ARC via Integration API
        (GET {ARC_INTEGRATION_API_URL}/arc/v1/charges/{charge_number}/metadata)
        Auth: managed identity token (same pattern as arc_lookup.py)
      - Pull available case files from ARC document store
        (charging party uploads only)
      - Create entry in casetriage table:
        Sector="OFP", office_id from accountabilityOfficeCode mapping,
        status="PENDING_REVIEW" (if documents available)
        status="AWAITING_DOCUMENTS" (if no documents yet)
      - Queue for CaseFileProcessor if documents available
        (upload to processing-container blob to trigger blob trigger)
   d. Check for new documents on already-classified OFP cases:
      - Monitor CDC events for document uploads on tracked cases
      - If new document found: set NEW_DOCUMENT_AVAILABLE flag on case entity
      - Do NOT auto-reclassify
   e. Log all activity to structured logger
   f. Release distributed lock

   Configuration (from environment):
   - OFP_CASE_MONITOR_ENABLED: true (default)
   - OFP_REVIEW_DELAY_DAYS: 5 (default, 0 = immediate)
   - OFP_TRIGGER_STATUS: "CHARGE_FILED" (comma-separated list)
   - OFP_CASE_MONITOR_INTERVAL_MINUTES: 15
   - ARC_INTEGRATION_API_URL: (required)
   - ARC_INTEGRATION_API_SCOPE: (Entra ID scope)
   - UDIP_API_URL or PG_READ_REPLICA_CONNECTION_STRING: for querying new cases
   - OFP_CALIBRATION_PHASE: true (log calibration warnings)

2. Create or verify case-processor-function/OFPCaseMonitor/function.json:
   Timer trigger with schedule matching the interval config.
   Ensure the function is registered in the function app.

3. Add tests:
   Create or update tests to cover:
   - New case detection logic
   - Delay calculation (5-day default, 0 immediate, configurable)
   - Duplicate detection (case already in casetriage)
   - New document detection on classified cases
   - Lock acquisition and release
   - ARC API failure handling (non-blocking)

Write a CHANGES.md and unified diff.
```

---

## Prompt 62: M-21-31 EL3 Infrastructure Guide

**Repository:** Workspace root
**Owner:** OCIO Platform team
**Phase:** 3 (HIGH — compliance documentation gap)

### Prompt

```
POST-AUDIT REMEDIATION: The implementation audit found that Prompt 45 was
not implemented. The file Azure_M2131_EL3_Infrastructure_Guide.md does
not exist. While some Sentinel configuration is covered in the deployment
guide (Section 2.19), the standalone M-21-31 EL3 infrastructure guide
was never created.

Create Azure_M2131_EL3_Infrastructure_Guide.md in the workspace root.

This is a DOCUMENTATION prompt. Create a complete infrastructure guide for
M-21-31 EL3 requirements handled at the Azure infrastructure level.

Document step-by-step Azure Portal instructions for:

1. Azure Sentinel (SOAR + UBA):
   - Enable Microsoft Sentinel on the Log Analytics workspace
   - Connect data sources: Azure AD sign-in logs, Azure Activity logs,
     Application Insights (all 6 apps), NSG flow logs
   - Enable User and Entity Behavior Analytics (UEBA)
   - Create analytics rules for:
     a. Failed authentication > 10 per hour per user
     b. AI audit write failures > 5 per hour
     c. Unusual query patterns (> 100 AI queries per hour per user)
     d. After-hours access to PII tier 3 data
     e. FOIA export activity (any export triggers alert)
   - Create automation playbooks (Logic Apps):
     a. On high-severity alert: email security team + create ticket
     b. On AI circuit breaker: notify ADR/Triage team leads
     c. On WORM deletion attempt: email Records Management Officer

2. NSG Flow Logs:
   - Enable on all NSGs in vnet-eeoc-ai-platform
   - Version 2 (includes bytes transferred)
   - Retention: 365 days
   - Send to Log Analytics workspace
   - Enable Traffic Analytics

3. Azure DNS Analytics:
   - Enable DNS Analytics solution in Log Analytics
   - Configure diagnostic settings on Azure DNS zones
   - Alert on: DNS queries to known malicious domains, unusual volume

4. Azure Network Watcher:
   - Enable in USGov Virginia region
   - Configure on-demand packet capture capability
   - Document incident response procedure for initiating capture
   - Retention: 30 days for captured packets

5. Log Analytics Workspace Configuration:
   - Interactive retention: 12 months (M-21-31 requirement)
   - Archive tier: 18 months beyond interactive (30 months total)
   - Per-table retention where needed
   - Data Export Rules to cold storage blob containers
   - Workspace-level RBAC (who can query what)

6. Azure AD Identity Protection:
   - Enable risk-based conditional access policies
   - Alert on: impossible travel, anonymous IP, malware-linked IP
   - Feed risk detections into Sentinel for correlation

7. TLS Inspection:
   - Azure Firewall Premium with TLS inspection
   - Or Application Gateway with end-to-end TLS
   - Document which traffic is inspected vs pass-through

8. Compliance Dashboard (Azure Monitor Workbook):
   - M-21-31 maturity level per application (EL1/EL2/EL3)
   - AU control compliance status
   - Log volume per application per day
   - Audit record integrity (HMAC validation results)
   - Retention policy adherence
   - Open litigation holds

Write click-by-click Azure Portal instructions for each section.
Reference the existing EEOC_AI_Platform_Complete_Deployment_Guide.md
Section 2.19 where applicable, but this document must be STANDALONE and
COMPLETE — someone should be able to follow it without the deployment guide.

Target length: 600-800 lines.
```

---

## Prompt 63: Cross-Cutting Compliance Remediation — HMAC, 508, Retention String, Protocol Version

**Repositories:** `eeoc-ofs-triage/`, `eeoc-data-analytics-and-dashboard/`, `eeoc-ogc-trialtool/`, `eeoc-ofs-adr/` (run per repo)
**Owner:** All teams
**Phase:** 2 (compliance — blocks FedRAMP assessment)

### Prompt (Triage — run in eeoc-ofs-triage/)

```
POST-AUDIT REMEDIATION: The compliance audit found that the Triage audit
logger uses SHA-256 hashing but NOT HMAC-SHA256 keyed signatures. Per
NIST 800-53 AU-10 (non-repudiation), audit records must use keyed HMAC
to prevent tampering by anyone with write access to Table Storage.

ADR (eeoc-ofs-adr/shared_code/ai_audit_logger.py) and ARC Integration API
(eeoc-arc-integration-api/app/audit_logger.py) already implement HMAC-SHA256
correctly. Bring Triage to parity.

1. Upgrade shared/utils/ai_audit_logger.py to use HMAC-SHA256:
   - Add HMAC key configuration:
     AI_AUDIT_HMAC_KEY from environment (sourced from Key Vault)
     Minimum 32 characters, fail startup in production if missing
     Allow empty key in development (log warning, use SHA-256 fallback)
   - Replace hashlib.sha256() calls with hmac.new(key, msg, hashlib.sha256):
     InputPromptHash → HMAC-SHA256 of system prompt + user prompt
     OutputResponseHash → HMAC-SHA256 of AI response
   - Add RecordHMAC field: HMAC-SHA256 covering
     PartitionKey + RowKey + event fields (same pattern as ARC API)
   - Keep SHA-256 as fallback ONLY when HMAC key is not configured
     (development mode)

2. Standardize retention policy string:
   - Change RETENTION_POLICY from "NARA_7_YEAR" to "FOIA_7_YEAR"
   - This aligns with ADR and ARC Integration API
   - Both strings mean the same thing (7-year retention per NARA/FOIA)
     but consistency matters for automated compliance queries
   - Update in: ai_audit_logger.py, foia_export.py (if present),
     any other file referencing the retention string

3. Add AI_AUDIT_HMAC_KEY to configuration documentation and K8s configmaps.

Write a CHANGES.md and unified diff.
```

### Prompt (UDIP — run in eeoc-data-analytics-and-dashboard/)

```
POST-AUDIT REMEDIATION: Same HMAC-SHA256 and retention string issue as
Triage. The UDIP analytics dashboard audit logger uses SHA-256 only.

1. Upgrade shared_code/ai_audit_logger.py to use HMAC-SHA256:
   - Same changes as Triage prompt above:
     HMAC key from Key Vault (AI_AUDIT_HMAC_KEY, 32+ chars)
     Replace hashlib.sha256 with hmac.new for all hash fields
     Add RecordHMAC integrity field
     Fail in production without key, allow SHA-256 fallback in dev

2. Standardize retention policy string:
   - Change RETENTION_POLICY from "NARA_7_YEAR" to "FOIA_7_YEAR"
   - Update in ai_audit_logger.py and any other files referencing it

Write a CHANGES.md and unified diff.
```

### Prompt (OGC — run in eeoc-ogc-trialtool/)

```
POST-AUDIT REMEDIATION: The OGC Trial Tool has no accessibility CSS
overrides for 508 compliance. ADR and Triage both have dedicated
stylesheets overriding Bootstrap defaults to meet WCAG 2.1 AA 4.5:1
contrast requirements.

1. Create trial_tool_webapp/static/css/accessibility.css:
   Copy the proven pattern from eeoc-ofs-triage/triage_webapp/static/css/accessibility.css:
   - Override Bootstrap color defaults for 4.5:1+ contrast:
     .text-muted: #5a6472 (6.0:1 on white)
     .text-info: #087990 (7.1:1)
     .text-warning: #997404 (5.7:1)
     .text-danger: #b02a37 (6.5:1)
     --bs-border-color: #737373 (4.7:1)
   - Force dark text on light badges (bg-info, bg-warning)
   - Focus indicators: 2px solid #0a58ca with offset (WCAG 2.4.7)
   - Minimal color palette — avoid decorative colors

2. Include the stylesheet in the base template:
   Add <link rel="stylesheet" href="/static/css/accessibility.css">
   after Bootstrap CSS in the base HTML template

3. Standardize retention policy string:
   In shared_code/ai_audit_logger.py:
   - Change RETENTION_POLICY from "NARA_7_YEAR" to "FOIA_7_YEAR"
   - Update in any other files referencing the string (foia_export.py, etc.)

Write a CHANGES.md and unified diff.
```

### Prompt (ADR — run in eeoc-ofs-adr/)

```
POST-AUDIT REMEDIATION: Two minor fixes found in the cross-repo audit.

1. Add MCP protocol version to ADR's MCP server:
   In adr_webapp/routes/api_mcp.py (or adr_webapp/mcp_server.py):
   - Add: _PROTOCOL_VERSION = "2025-03-26"
   - Include in the server_info response and any protocol handshake
   - Triage and ARC Integration API already declare this version;
     ADR is the only spoke that omits it

2. No other changes needed — ADR already has HMAC-SHA256, 508 compliance,
   and uses "FOIA_7_YEAR" retention string.

Write a CHANGES.md and unified diff.
```

---

## Prompt 64: Final Wiring Fixes — UDIP Conversation Lifecycle + Triage Session Population + ScheduledDisposal

**Repositories:** `eeoc-data-analytics-and-dashboard/` and `eeoc-ofs-triage/`
**Owner:** UDIP team + Triage team
**Phase:** 2 (CRITICAL — dead code paths that break compliance and multi-tenancy)

### Prompt (UDIP — run in eeoc-data-analytics-and-dashboard/)

```
POST-AUDIT WIRING FIX: The full wiring audit found two methods in
conversation_store.py that are implemented correctly but NEVER CALLED
from any production code path. This means:
- Case closures do NOT archive conversations to WORM blob
- Case closures do NOT set retention_expires_at on conversations
- Litigation holds do NOT freeze linked conversations

Both methods exist and are tested, but the integration points are missing.

FIX 1 — Wire case closure to conversation archival:

The method ConversationStore.set_retention_on_case_closure() at
ai-assistant/app/conversation_store.py:809 must be called when a
charge's lifecycle_state transitions to "closed" in the system.

Option A (preferred): Wire into HoldService/lifecycle events.
In ai-assistant/app/hold_service.py, the issue_hold() method at line 45
already propagates holds to 9 analytics tables. Add a call after the
analytics propagation:

   # After _set_analytics_hold() succeeds:
   from .conversation_store import ConversationStore
   store = ConversationStore(table_service_client)
   store.hold_conversations_for_charge(charge_number)

Option B: Wire into lifecycle_manager.py case closure path.
In data-middleware/lifecycle_manager.py, when execute_purge() or any
lifecycle transition sets a charge to "closed":
   - Import ConversationStore
   - Call store.set_retention_on_case_closure(charge_number, case_closed_at)
   - This archives all linked conversations and sets 7-year retention

Implement BOTH options:
1. In hold_service.py issue_hold(): after _set_analytics_hold(), call
   ConversationStore.hold_conversations_for_charge(charge_number)
   — this freezes conversations when a hold is issued

2. In hold_service.py release_hold(): after _release_analytics_hold(),
   call ConversationStore.release_hold_for_charge(charge_number)
   — this unfreezes conversations when a hold is released
   (create this method if it doesn't exist — iterate linked conversations
   and call release_hold() on each)

3. Create a new API endpoint or hook for case closure events:
   POST /api/lifecycle/case-closed
   Input: { charge_number, case_closed_at }
   Auth: managed identity (lifecycle_manager or CDC consumer identity)
   Action: calls ConversationStore.set_retention_on_case_closure()
   This is called by the lifecycle_manager when it detects a case has
   been closed (either via CDC status change or manual closure).

   Alternatively, if lifecycle_manager.py already has a case closure
   detection path, add the ConversationStore call directly there.

4. Wire into the data middleware CDC consumer if possible:
   When the CDC consumer processes a charge status change to CLOSED
   (via the lifecycle state machine), trigger the conversation archival.
   This ensures conversations are archived in near-real-time after
   case closure, not just during batch lifecycle runs.

5. Add integration test:
   Test that when a charge gets a litigation hold:
   - All linked conversations have lifecycle_state="held"
   Test that when a case is closed:
   - All linked conversations are archived to WORM blob
   - retention_expires_at is set to case_closed_at + 7 years

Write a CHANGES.md and unified diff.
```

### Prompt (Triage — run in eeoc-ofs-triage/)

```
POST-AUDIT WIRING FIX: The full wiring audit found two issues:

1. office_hierarchy.py is loaded and the office tree works, but the
   login flow does NOT populate session fields needed for multi-tenancy.
   Dashboard queries that filter by sector + office subtree will not
   work because session['staff_role'], session['office_id'], and
   session['sector'] are never set.

2. ScheduledDisposal/ directory has a function.json timer trigger
   (daily 3 AM) but no __init__.py source file. This will cause
   runtime errors in Azure Functions.

FIX 1 — Wire session population into login flow:

In triage_webapp/auth.py (or wherever the MSAL login callback is):
After successful authentication (where session['user'] and session['sid']
are set), add hierarchy lookup:

   from helpers.office_hierarchy import (
       load_staff_assignment,
       load_staff_hierarchy,
   )

   # After session['user'] is set:
   user_oid = session['user']['oid']  # or however the OID is extracted

   # Look up staff assignment
   assignment = load_staff_assignment(table_service, user_oid)
   if assignment:
       session['staff_role'] = assignment.get('Role', 'intake_coordinator')
       session['office_id'] = assignment.get('OfficeId', '')
       session['sector'] = assignment.get('Sector', 'OFS')
       # Load subordinate IDs for supervisors/directors
       if session['staff_role'] in ('supervisor', 'director', 'admin'):
           session['subordinate_coordinator_ids'] = (
               load_staff_hierarchy(table_service, user_oid)
           )
       else:
           session['subordinate_coordinator_ids'] = []
   else:
       # Default for users not in staffassignments table
       session['staff_role'] = 'intake_coordinator'
       session['office_id'] = ''
       session['sector'] = os.environ.get('TRIAGE_DEFAULT_SECTOR', 'OFS')
       session['subordinate_coordinator_ids'] = []

   session['hierarchy_loaded'] = True

This must happen BEFORE the user is redirected to the dashboard.

Verify that office_hierarchy.py has the functions load_staff_assignment()
and load_staff_hierarchy() that return the expected data. If they have
different names, use the actual function names — the key point is that
the session must be populated with role, office, and sector after login.

Also verify that blueprints/cases.py (dashboard queries) actually READ
these session fields when filtering. If the query filtering code
references session['office_id'] or session['sector'], this fix will
make it functional. If the filtering code doesn't exist yet, add it:
- OFS users: no office filter (national view)
- OFP users with role=intake_coordinator: filter to own cases only
- OFP users with role=supervisor/director: filter to subordinate cases
  + own office subtree

FIX 2 — ScheduledDisposal source file:

Either create case-processor-function/ScheduledDisposal/__init__.py or
remove the directory entirely. Check whether any other function or
documentation references ScheduledDisposal:
- If it's supposed to be a timer that triggers FinalizeDisposal for
  expired retention records: create the source file that queries cases
  past retention_expires_at and queues them for FinalizeDisposal
- If FinalizeDisposal is already triggered by other means (HTTP, queue):
  remove the ScheduledDisposal directory and its function.json to
  prevent Azure Functions runtime errors

The safest approach: create a minimal __init__.py that:
1. Queries casetriage for cases where retention_expires_at < now()
   AND lifecycle_state = "retained" (not held)
2. For each: sends a message to the disposal queue that triggers
   FinalizeDisposal
3. Respects LITIGATION_HOLD_CHECK — never queues held cases
4. Uses distributed lock to prevent concurrent runs
5. Logs activity to structured logger

Write a CHANGES.md and unified diff.
```

---

## Prompt 65: Final Hardening — Tests, K8s, SQL Roles, Config Hygiene (All Repos)

**Repositories:** All repos as specified per section
**Owner:** All teams
**Phase:** 2 (FINAL — run before production deployment)

### Prompt (Triage — run in eeoc-ofs-triage/)

```
FINAL HARDENING: The comprehensive audit identified the following issues
in the Triage repo. Fix ALL of them.

PART A — Missing unit tests (7 gaps):

1. Create triage_webapp/tests/test_office_hierarchy.py:
   Test office_hierarchy.py (Prompt 53 multi-tenancy):
   - test_get_office_tree_builds_correct_hierarchy: mock officestructure
     table, verify parent-child relationships
   - test_get_subtree_office_ids_returns_all_descendants: verify recursive
     traversal collects all children
   - test_cycle_detection_prevents_infinite_loop: create circular
     parent references, verify no hang
   - test_load_staff_assignment_returns_role_office_sector: mock
     staffassignments table, verify correct fields returned
   - test_load_staff_hierarchy_for_supervisor: verify subordinate IDs
     loaded for supervisor role
   - test_cache_expires_after_ttl: verify office tree reloads after
     OFFICE_HIERARCHY_CACHE_TTL_SECONDS
   - test_missing_staff_assignment_returns_none: verify graceful
     handling when user not in staffassignments

2. Create case-processor-function/tests/test_ofs_submission_monitor.py:
   Test OFSSubmissionMonitor (Prompt 58):
   - test_window_closed_transitions_to_ready_for_review: verify state
     transition when deadline passes
   - test_window_open_calculates_days_remaining: verify countdown
   - test_extension_detected_updates_deadline: mock CDC extension event,
     verify new deadline calculated
   - test_manual_override_closes_window_early: verify "Review Now"
     triggers immediate transition
   - test_distributed_lock_prevents_concurrent_runs: verify only one
     instance runs
   - test_arc_deadline_preferred_over_fallback: when filingDeadlineDte
     exists, use it instead of created_date + window_days
   - test_no_cases_in_window_is_noop: verify clean exit when no
     AWAITING_SUBMISSION_WINDOW cases

3. Create triage_webapp/tests/test_session_population.py:
   Test the login → session population flow (Prompt 64):
   - test_successful_login_populates_all_session_fields: verify
     staff_role, office_id, sector, subordinate_coordinator_ids set
   - test_unknown_user_gets_restrictive_defaults: verify
     intake_coordinator role, empty office/sector
   - test_supervisor_gets_subordinate_ids: verify hierarchy loaded
   - test_ofs_user_gets_national_view: verify no office filtering

PART B — K8s ConfigMap hygiene:

4. In deploy/k8s/triage-functionapp/configmap.yaml:
   - Remove AI_AUDIT_HMAC_KEY from the ConfigMap entirely
   - It is a secret and must come from triage-secrets (Kubernetes Secret)
   - Add a comment: "# AI_AUDIT_HMAC_KEY: sourced from triage-secrets"

5. In deploy/k8s/triage-webapp/configmap.yaml:
   - Same: remove AI_AUDIT_HMAC_KEY, reference triage-secrets

6. In deploy/k8s/triage-functionapp/deployment.yaml and
   deploy/k8s/triage-webapp/deployment.yaml:
   - If AI_AUDIT_HMAC_KEY is in the env section from configMapRef,
     add it via secretKeyRef instead:
     - name: AI_AUDIT_HMAC_KEY
       valueFrom:
         secretKeyRef:
           name: triage-secrets
           key: ai-audit-hmac-key

Write a CHANGES.md and unified diff.
```

### Prompt (UDIP — run in eeoc-data-analytics-and-dashboard/)

```
FINAL HARDENING: The comprehensive audit identified the following issues
in the UDIP repo. Fix ALL of them.

PART A — Missing unit tests (4 gaps):

1. Create ai-assistant/tests/test_hold_service.py:
   Test hold_service.py API endpoints (Prompt 41):
   - test_issue_hold_creates_record_and_returns_hold_id: POST /api/holds
   - test_release_hold_updates_record: DELETE /api/holds/{id}
   - test_check_hold_returns_true_when_active: GET /api/holds/check/{charge}
   - test_check_hold_returns_false_when_none: verify no false positives
   - test_list_holds_filters_active_only: GET /api/holds
   - test_issue_hold_propagates_to_conversations: verify
     hold_conversations_for_charge() called
   - test_case_closed_endpoint_archives_conversations: POST
     /api/lifecycle/case-closed triggers archival
   - test_unauthorized_user_rejected: verify role check (Admin/LegalCounsel)
   - Mock PostgreSQL and ConversationStore, test HTTP responses

2. Create ai-assistant/tests/test_foia_export.py:
   Test foia_export.py (Prompt 40):
   - test_export_creates_zip_with_correct_structure: verify ZIP contains
     ai_audit_records.json, conversations/, metadata.json
   - test_metadata_includes_chain_of_custody: verify export_id,
     requester_hash, zip_hash, timestamp
   - test_rate_limit_enforced: verify 5 per hour limit
   - test_admin_role_required: verify 403 for non-admin
   - test_sas_url_generated_with_24hr_expiry: verify download URL
   - Mock Table Storage, Blob Storage, test full export flow

3. Create data-middleware/tests/test_schema_detector.py:
   Test schema_detector.py (Prompt 52):
   - test_detect_new_replica_tables_finds_unregistered: mock replica
     schema, verify new tables identified
   - test_detect_new_ingest_datasets_infers_schema: pass sample records,
     verify column types inferred correctly
   - test_auto_label_columns_from_registry: verify known columns get
     labels from column_registry.yaml
   - test_auto_label_columns_pattern_based: verify *_id → identifier,
     *_date → date, is_* → boolean patterns
   - test_auto_detect_pii_flags_sensitive_columns: verify SSN/email/name
     patterns detected as tier 3
   - test_column_registry_loads_from_yaml: verify YAML parsing of
     column_registry.yaml

4. Create data-middleware/tests/test_auto_schema_builder.py:
   Test auto_schema_builder.py (Prompt 52):
   - test_create_analytics_table_generates_valid_sql: verify CREATE TABLE
     with lifecycle columns
   - test_create_rls_policy_for_charge_linked_table: verify region-based
     RLS when charge_id present
   - test_generate_yaml_mapping_creates_valid_yaml: verify YAML output
     with transforms
   - test_generate_dbt_model_creates_staging_sql: verify SQL + schema.yml
   - test_generate_dataset_metadata_creates_json: verify metadata JSON
     with columns, metrics, suggested_dashboards
   - Mock PostgreSQL connection

PART B — K8s PodDisruptionBudgets:

5. Create deploy/k8s/ai-assistant/pdb.yaml:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: ai-assistant-pdb
     namespace: udip
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: ai-assistant
   ```

6. Create deploy/k8s/superset/pdb.yaml:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: superset-web-pdb
     namespace: udip
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: superset-web
   ---
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: superset-worker-pdb
     namespace: udip
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: superset-worker
   ```

7. Create deploy/k8s/pgbouncer/pdb.yaml:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: pgbouncer-pdb
     namespace: udip
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: pgbouncer
   ```

8. Create deploy/k8s/portal-nginx/pdb.yaml:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: portal-nginx-pdb
     namespace: udip
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: portal-nginx
   ```

PART C — SQL role creation:

9. In analytics-db/postgres/040-rls-policies.sql (or a new file
   039-application-roles.sql that runs before 040):
   Add creation of application roles used by 065-litigation-holds.sql:
   ```sql
   DO $$
   BEGIN
     IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'adr_app') THEN
       CREATE ROLE adr_app NOLOGIN;
     END IF;
     IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'triage_app') THEN
       CREATE ROLE triage_app NOLOGIN;
     END IF;
     IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ogc_app') THEN
       CREATE ROLE ogc_app NOLOGIN;
     END IF;
   END $$;
   ```
   Also add these roles to the provision script Section 8 if not present.

PART D — Search function ordering fix:

10. Rename 050-search-functions.sql to 017-search-functions.sql so it
    runs AFTER 016-cdc-target-tables.sql (which creates tables that the
    search function references). Update the provision script
    SCHEMA_FILES array to match the new filename.

    Alternatively: if renaming would break existing deployments, add a
    comment to 050-search-functions.sql documenting the lazy evaluation
    dependency and add a verification step to the provision script that
    checks the referenced tables exist after all files are run.

Write a CHANGES.md and unified diff.
```

### Prompt (ADR — run in eeoc-ofs-adr/)

```
FINAL HARDENING: Two minor K8s issues found.

1. In deploy/k8s/adr-functionapp/deployment.yaml:
   Add a startupProbe if missing. The function app may have cold starts
   >30s. Match the pattern from triage-functionapp:
   ```yaml
   startupProbe:
     httpGet:
       path: /api/health/startup
       port: 80
     initialDelaySeconds: 10
     periodSeconds: 5
     failureThreshold: 24
   ```
   This gives up to 2 minutes for cold start before the pod is killed.

2. Verify AI_AUDIT_HMAC_KEY is NOT in any ConfigMap. It should only be
   in adr-secrets (Kubernetes Secret). If it appears in any configmap.yaml,
   remove it and add a secretKeyRef in the deployment env section instead.

Write a CHANGES.md and unified diff.
```

### Prompt (OGC — run in eeoc-ogc-trialtool/)

```
FINAL HARDENING: No critical issues found — OGC passed all audits.
One documentation cross-reference:

1. In trial_tool_webapp/MODEL_LICENSES.md:
   If not already present, add a section noting that the accessibility
   overrides (accessibility.css) follow WCAG 2.1 AA with 4.5:1+ contrast
   ratios, matching the ADR and Triage implementations. Reference the
   CSS file path.

2. Verify all tests pass: run pytest tests/ -v and fix any failures.

Write a CHANGES.md and unified diff.
```

### Prompt (ARC Integration API — run in eeoc-arc-integration-api/)

```
FINAL HARDENING: No critical issues found — ARC Integration API passed
all audits with 100% on every check. One minor item:

1. Verify TRIAGE_FIELD_MAPPING_PATH is configurable via environment
   variable (not hardcoded). In app/routers/triage.py, the YAML mapping
   file path should come from settings or an env var so it can be
   overridden without code changes. If it's already configurable, no
   action needed. If hardcoded, add:
   - TRIAGE_FIELD_MAPPING_PATH env var (default: app/config/triage_field_mapping.yaml)
   - Read in config.py or directly in triage.py's load_field_mapping()

2. Verify all tests pass: run pytest tests/ -v and fix any failures.

Write a CHANGES.md and unified diff.
```

### Prompt (MCP Hub — run in eeoc-mcp-hub-functions/)

```
FINAL HARDENING: No critical issues found — MCP Hub passed all audits
after Prompt 59 remediation. One item:

1. Verify all tests pass: run pytest tests/ -v and fix any failures.

2. If any test references the old protocol version "2024-11-05" that
   was missed in the grep, update it to "2025-03-26".

Write a CHANGES.md and unified diff.
```

### Prompt (Workspace docs — run in workspace root)

```
FINAL HARDENING: Cross-reference and consistency fixes.

1. In EEOC_AI_Platform_Complete_Deployment_Guide.md, Section 2.19
   (Azure Sentinel), add at the beginning of the section:

   > For complete step-by-step implementation with KQL queries, retention
   > configurations, SOAR playbook definitions, and M-21-31 control
   > mappings, refer to Azure_M2131_EL3_Infrastructure_Guide.md. This
   > section provides a summary; the infrastructure guide is the
   > authoritative reference.

2. In provision_eeoc_ai_platform.sh, Section 20 (Sentinel) comments,
   add a reference:

   # Detailed portal instructions: Azure_M2131_EL3_Infrastructure_Guide.md

3. In provision_eeoc_ai_platform.sh, Section 8 (PostgreSQL), verify
   the SCHEMA_FILES array includes all 19 SQL files in correct order.
   If 050-search-functions.sql was renamed to 017-search-functions.sql
   (per UDIP prompt above), update the array accordingly.

4. In provision_eeoc_ai_platform.sh, Section 8, add application role
   creation BEFORE running schema files (if not already present):

   log_info "Creating application roles..."
   psql -h "$PG_HOST" -U "$PG_ADMIN_USER" -d udip -c "
     DO \$\$ BEGIN
       IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'adr_app') THEN
         CREATE ROLE adr_app NOLOGIN;
       END IF;
       IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'triage_app') THEN
         CREATE ROLE triage_app NOLOGIN;
       END IF;
       IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ogc_app') THEN
         CREATE ROLE ogc_app NOLOGIN;
       END IF;
     END \$\$;
   " || log_warn "Role creation had issues (may already exist)"

5. Update SESSION_HANDOFF.md prompt status: mark prompts 39-64 as DONE
   and add the execution note for Prompt 65.

Write a CHANGES.md for the documentation updates.
```

---

## Prompt 66: Debezium Schema Expansion for Federal Hearings

**Repository:** eeoc-data-analytics-and-dashboard/
**Owner:** UDIP team
**Phase:** 4a

### Prompt

```
Expand the Debezium CDC pipeline to capture the fed_hearings schema.

1. In deploy/cdc-pipeline/debezium/connector-config.json, line 17,
   change:
     "schema.include.list": "public"
   to:
     "schema.include.list": "public,fed_hearings"

2. Apply the same change to the embedded connector config in
   deploy/cdc-pipeline/k8s/configmap.yaml.

3. Add PII column exclusions for the fed_hearings schema. In both
   connector-config.json and the configmap embedded config, add or
   extend the "column.exclude.list" property:
     "column.exclude.list": "fed_hearings.hearing_complainant.ssn,fed_hearings.hearing_complainant.social_security_number"
   If other schemas already have column exclusions, append these
   entries to the existing comma-separated list.

4. Add a feature flag CDC_FED_HEARINGS_ENABLED to the configmap.
   The connector registration script (if one exists) should check
   this flag before registering the fed_hearings connector. If no
   script exists, document the flag in the configmap with a comment.

5. Note: 002-publication.sql already uses FOR ALL TABLES so no SQL
   publication change is needed.

6. Create deploy/cdc-pipeline/docs/fed-hearings-cdc.md as an
   operations runbook covering:
   - Purpose: what data flows from fed_hearings to analytics
   - Connector configuration fields and their values
   - PII exclusions and why each column is excluded
   - How to enable: set CDC_FED_HEARINGS_ENABLED=true and register
     the connector via the Kafka Connect REST API
   - How to verify: Kafka topic naming convention for fed_hearings
     tables, how to check consumer lag
   - How to pause and resume without data loss
   - Rollback procedure

Write CHANGES.md summarizing all files modified and created.
```

---

## Prompt 67: Replica Schema DDL for New Entities

**Repository:** eeoc-data-analytics-and-dashboard/
**Owner:** UDIP team
**Phase:** 4a

### Prompt

```
Create replica schema DDL files for Federal Hearings entities and
public schema gap entities. Follow the exact pattern established in
analytics-db/postgres/003-replica-schema.sql: integer PKs, no FK
constraints, updated_on TIMESTAMPTZ NOT NULL DEFAULT now(), GRANT
SELECT/INSERT/UPDATE/DELETE ON all tables TO udip_writer.

FILE 1: analytics-db/postgres/004-replica-fed-hearings.sql

Create 13 replica tables in the fed_hearings schema (CREATE SCHEMA IF
NOT EXISTS fed_hearings first) matching the FederalHearings JPA entities
in eeoc-arc-payloads/FederalHearings-ims-aks/:

  hearing_case           — case header, agency_code, aj_id, stage,
                           filed_date, closed_date, disposition_code
  hearing_complainant    — complainant demographics (no ssn/ssn_last4),
                           case_id FK reference (no constraint)
  hearing_agency         — respondent agency name, bureau, org_code
  hearing_claims         — basis_code, issue_code, statute_code, case_id
  hearing_allegation     — allegation text, ruling, case_id
  hearing_assignment     — aj_id, assigned_date, reassigned_date, case_id
  hearing_conference     — conference_type, scheduled_date, held_flag,
                           outcome_code, case_id
  hearing_action         — action_code, action_date, performed_by, case_id
  hearing_event_log      — event_type, event_timestamp, user_id, payload
                           JSONB, case_id
  hearing_note           — note_text, note_type, authored_by,
                           authored_date, case_id
  hearing_assessment     — merit_assessment, monetary_request,
                           recommended_remedy, case_id
  hearing_stay           — stay_reason, stay_date, lifted_date, case_id
  hearing_case_transfer  — from_office, to_office, transfer_date,
                           reason_code, case_id

Also create shared reference/lookup tables in fed_hearings schema:
  hearing_shared_code     — domain, code, description, active_flag
  hearing_shared_doc_type — doc_type_code, description
  hearing_shared_office_info — office_code, office_name, region
  hearing_event_code      — event_code, category, description
  fed_shared_basis        — basis_code, basis_description
  fed_shared_issue        — issue_code, issue_description
  fed_shared_statute      — statute_code, statute_name, citation

FILE 2: analytics-db/postgres/005-replica-public-extensions.sql

Create 11 additional replica tables in the public schema to cover
gaps identified from PrEPA JPA entities:

  conciliation_proposal_response — charge_number, proposal_date,
    response_date, outcome_code, monetary_amount NUMERIC(12,2),
    updated_on TIMESTAMPTZ
  benefit_group              — group_code, group_name, category,
    active_flag, updated_on TIMESTAMPTZ
  beneficiary                — charge_number, beneficiary_name,
    benefit_type, amount NUMERIC(12,2), updated_on TIMESTAMPTZ
  charging_party_race        — charge_number, race_code,
    national_origin_code, updated_on TIMESTAMPTZ
  charge_suspension          — charge_number, suspension_reason_code,
    suspension_date, lift_date, updated_on TIMESTAMPTZ
  charge_transfer            — charge_number, from_office_id,
    to_office_id, transfer_date, reason_code, updated_on TIMESTAMPTZ
  systemic_case              — systemic_case_id INTEGER PK,
    case_name, office_id, status_code, opened_date, closed_date,
    updated_on TIMESTAMPTZ
  systemic_case_charge       — systemic_case_id, charge_number,
    link_date, updated_on TIMESTAMPTZ
  enforcement_conference     — charge_number, conference_type,
    scheduled_date, held_flag, outcome_code, updated_on TIMESTAMPTZ
  charge_review_assignment   — charge_number, reviewer_id,
    assigned_date, review_type, completed_date, updated_on TIMESTAMPTZ

Grant all tables to udip_writer. Add COMMENT ON TABLE for each table
briefly describing its source system.

Write CHANGES.md listing both files and the table count in each.
```

---

## Prompt 68: Analytics Target Tables for New Entities

**Repository:** eeoc-data-analytics-and-dashboard/
**Owner:** UDIP team
**Phase:** 4a

### Prompt

```
Create analytics target table DDL for Federal Hearings and Enforcement
entities. Follow the lifecycle pattern from
analytics-db/postgres/016-cdc-target-tables.sql exactly: UUID PKs
(DEFAULT gen_random_uuid()), lifecycle columns, retention trigger,
hold-reason CHECK constraint, GRANT to udip_writer and udip_reader.

FILE 1: analytics-db/postgres/017-fed-hearings-analytics-tables.sql

Create 6 analytics tables in the analytics schema:

  hearing_cases
    Columns: id UUID PK, source_hearing_case_id INTEGER NOT NULL,
    agency_code VARCHAR(10), aj_employee_id VARCHAR(20),
    stage_code VARCHAR(20), filed_date DATE, closed_date DATE,
    disposition_code VARCHAR(20), fiscal_year INTEGER GENERATED ALWAYS
    AS (EXTRACT(YEAR FROM filed_date + INTERVAL '3 months')::INTEGER)
    STORED, lifecycle_state VARCHAR(20) NOT NULL DEFAULT 'active',
    first_synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    case_closed_at TIMESTAMPTZ, retention_expires_at TIMESTAMPTZ,
    retention_hold BOOLEAN NOT NULL DEFAULT FALSE,
    hold_reason VARCHAR(100), hold_set_by VARCHAR(100),
    hold_set_at TIMESTAMPTZ, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()

  hearing_claims
    source_hearing_claim_id, source_hearing_case_id, basis_code,
    issue_code, statute_code, plus lifecycle columns

  hearing_assignments
    source_assignment_id, source_hearing_case_id, aj_employee_id,
    assigned_date, reassigned_date, plus lifecycle columns

  hearing_conferences
    source_conference_id, source_hearing_case_id, conference_type,
    scheduled_date, held_flag, outcome_code, plus lifecycle columns

  hearing_actions
    source_action_id, source_hearing_case_id, action_code,
    action_date, performed_by, plus lifecycle columns

  hearing_events
    source_event_id, source_hearing_case_id, event_type,
    event_timestamp, user_id, event_payload JSONB,
    plus lifecycle columns

For each table:
- Add CHECK (hold_reason IS NOT NULL OR retention_hold = FALSE)
- Add CHECK (lifecycle_state IN ('active','closed','purged','held'))
- Create trigger set_updated_at BEFORE UPDATE using the shared
  trigger function from 016-cdc-target-tables.sql
- GRANT SELECT ON table TO udip_reader
- GRANT SELECT, INSERT, UPDATE ON table TO udip_writer
- CREATE INDEX ON hearing_cases (agency_code, fiscal_year)
- CREATE INDEX ON hearing_cases (lifecycle_state)

FILE 2: analytics-db/postgres/018-enforcement-analytics-tables.sql

Create 11 analytics tables in the analytics schema:

  conciliations — source fields from conciliation_proposal_response,
    plus outcome_category, fiscal_year derived, lifecycle columns

  benefits — source fields from benefit_group + beneficiary,
    benefit_amount NUMERIC(12,2), lifecycle columns

  charging_party_races — charge_number, race_code,
    national_origin_code, lifecycle columns

  suspensions — charge_number, suspension_reason_code,
    suspension_date, lift_date, is_active BOOLEAN GENERATED ALWAYS
    AS (lift_date IS NULL) STORED, lifecycle columns

  systemic_cases — systemic_case_id (from source), case_name,
    office_id, status_code, opened_date, closed_date,
    fiscal_year derived, lifecycle columns

  systemic_case_charges — systemic_case_id, charge_number,
    link_date, lifecycle columns

  enforcement_conferences — charge_number, conference_type,
    scheduled_date, held_flag, outcome_code, lifecycle columns

  transfers — charge_number, from_office_id, to_office_id,
    transfer_date, reason_code, lifecycle columns

  court_hearings — charge_number, hearing_date, court_name,
    judge_name, outcome_code, appeal_flag, lifecycle columns

  review_assignments — charge_number, reviewer_id, assigned_date,
    review_type, completed_date, lifecycle columns

  employer_enrichment — charge_number, employer_id, naics_code,
    employer_size_code, state_code, lifecycle columns

Apply same index, grant, trigger, and constraint patterns as File 1.

Write CHANGES.md listing both files, table counts, and noting that
these depend on 016-cdc-target-tables.sql for the shared trigger
function.
```

---

## Prompt 69: YAML Mappings for Federal Hearings CDC Entities

**Repository:** eeoc-data-analytics-and-dashboard/
**Owner:** UDIP team
**Phase:** 4a

### Prompt

```
The 13 fedhearings_*.yaml mapping files have already been created in
data-middleware/source_mappings/. This prompt validates and finalizes
them.

1. Read each of the 13 fedhearings_*.yaml files:
   fedhearings_hearing_case.yaml
   fedhearings_hearing_complainant.yaml
   fedhearings_hearing_agency.yaml
   fedhearings_hearing_claims.yaml
   fedhearings_hearing_allegation.yaml
   fedhearings_hearing_assignment.yaml
   fedhearings_hearing_conference.yaml
   fedhearings_hearing_action.yaml
   fedhearings_hearing_event_log.yaml
   fedhearings_hearing_note.yaml
   fedhearings_hearing_assessment.yaml
   fedhearings_hearing_stay.yaml
   fedhearings_hearing_case_transfer.yaml

2. For each file, verify:
   a. source_schema is "fed_hearings" (not "public")
   b. Column names in source_columns match JPA entity field names from
      eeoc-arc-payloads/FederalHearings-ims-aks/ entity classes. Read
      the entity source if needed. Fix any mismatches.
   c. uuid_v5_namespace uses the prefix "fed_hearings." (e.g.,
      "fed_hearings.hearing_case") — not "prepa." or "public."
   d. Any lookup_table references use the correct fed_hearings lookup
      table names: hearing_shared_code, hearing_event_code,
      fed_shared_basis, fed_shared_issue, fed_shared_statute — not
      the public schema's shared_code table.
   e. destination_table references match tables created in
      017-fed-hearings-analytics-tables.sql.
   f. No SSN or social_security_number columns appear in any mapping
      (these are excluded at the Debezium layer per Prompt 66).

3. If the mapping_validator script exists in data-middleware/,
   run it against each file and fix all validation errors.

4. Update data-middleware/source_mappings/README.md:
   - Add a "Federal Hearings" section listing all 13 files with a
     one-line description of each entity
   - Document the fed_hearings schema context: these tables originate
     from the FederalHearings ARC service, captured via the expanded
     Debezium connector (Prompt 66)
   - Note that fed_hearings lookup tables differ from public schema
     lookup tables even where names are similar

Write CHANGES.md listing each yaml file reviewed, what was corrected
(if anything), and confirming validation status.
```

---

## Prompt 70: YAML Mappings for Public Schema Gap Entities

**Repository:** eeoc-data-analytics-and-dashboard/
**Owner:** UDIP team
**Phase:** 4a

### Prompt

```
The 12 prepa_*.yaml gap mapping files have already been created in
data-middleware/source_mappings/. This prompt validates and finalizes
them.

1. Read each of the 12 gap files:
   prepa_conciliation_proposal_response.yaml
   prepa_benefit_group.yaml
   prepa_beneficiary.yaml
   prepa_charging_party_race.yaml
   prepa_charge_suspension.yaml
   prepa_charge_transfer.yaml
   prepa_systemic_case.yaml
   prepa_systemic_case_charge.yaml
   prepa_enforcement_conference.yaml
   prepa_charge_review_assignment.yaml
   prepa_court_hearing.yaml
   prepa_employer_enrichment.yaml

2. For each file verify:
   a. source_schema is "public"
   b. source_table matches the exact JPA entity table name from
      eeoc-arc-payloads/PrEPAWebService-ims-aks-test/ entity classes.
      Read entity source if needed. Fix any mismatches.
   c. uuid_v5_namespace uses "prepa." prefix
   d. lookup_table references use replica.shared_code (public schema
      lookup) not fed_hearings lookup tables
   e. destination_table references match tables in
      018-enforcement-analytics-tables.sql

3. Special attention to three files:
   prepa_court_hearing.yaml — if this is modeled as a filtered event
   log (i.e., source is hearing_event_log filtered by event_type),
   verify the filter_expression field is supported by the mapping
   engine. Read data-middleware/engine/ to confirm. If not supported,
   change source_table to a direct court_hearing table if one exists,
   or add a comment explaining the workaround needed.

   prepa_employer_enrichment.yaml — this uses a REST driver to enrich
   charge data from the Employer service. Verify the driver config
   block (driver: rest, base_url, auth_type) is documented. If the
   REST driver is not yet implemented in data-middleware/engine/,
   add a comment block: "# REST driver — requires engine v2 support"
   and a JIRA/backlog reference format: "# Backlog: UDIP-XXX".

   prepa_benefits.yaml — this denormalizes benefit_group into
   beneficiary rows. Verify the join_key and denormalization transform
   are correctly expressed. If the engine does not support in-mapping
   joins, note the limitation and propose a replica-layer view instead.

4. Run mapping_validator if available. Fix all errors.

5. Update data-middleware/source_mappings/README.md:
   - Add a "Public Schema Gap Entities" section listing all 12 files
   - Note which files have engine limitations (REST driver, filtered
     event log, denormalization)

Write CHANGES.md summarizing validation results and any issues found.
```

---

## Prompt 71: Service Bus Topic Subscriptions

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4a

### Prompt

```
Add conditional Service Bus subscriptions for two new topics:
user-management-topic and federal-hearing-topic.

1. Modify app/config.py Settings class:
   Add fields:
     service_bus_user_mgmt_topic: str = ""
     service_bus_federal_hearing_topic: str = ""
     service_bus_user_mgmt_enabled: bool = False
     service_bus_federal_hearing_enabled: bool = False
   Follow the naming and default patterns of existing Service Bus
   config fields.

2. Modify app/services/service_bus.py:
   In the subscription setup function (wherever db-change-topic and
   document-activity-topic are registered), add two conditional blocks:

     if settings.service_bus_user_mgmt_enabled and
        settings.service_bus_user_mgmt_topic:
         subscribe to service_bus_user_mgmt_topic
         on message: call handle_user_management(payload)

     if settings.service_bus_federal_hearing_enabled and
        settings.service_bus_federal_hearing_topic:
         subscribe to service_bus_federal_hearing_topic
         on message: call handle_federal_hearing(payload)

   Existing db-change-topic and document-activity-topic subscriptions
   are unchanged.

3. Create app/services/service_bus_handlers.py:

   def handle_user_management(payload: dict) -> None:
     Transform the raw Service Bus message into the MCP event envelope
     format used by existing handlers. Extract event_type, entity_id,
     timestamp. Forward to MCP Hub via the internal HTTP client
     (follow the pattern of existing topic handlers). Log with
     request_id propagation. Never log PII fields. On error: log and
     do not re-raise (dead-letter the message).

   def handle_federal_hearing(payload: dict) -> None:
     Same pattern. Extract hearing_case_id, event_type, stage_code,
     agency_code from payload. Forward to MCP Hub endpoint
     /internal/events/federal-hearing. Never log case content beyond
     IDs. On error: log and do not re-raise.

   Both functions must have full type hints and docstrings explaining
   the expected payload schema.

4. Wire into app/main.py startup: import and call the subscription
   setup so new topics are registered on application start, same as
   existing topics.

5. Add SERVICE_BUS_USER_MGMT_TOPIC, SERVICE_BUS_USER_MGMT_ENABLED,
   SERVICE_BUS_FEDERAL_HEARING_TOPIC, and
   SERVICE_BUS_FEDERAL_HEARING_ENABLED to README env var table.

Write CHANGES.md with a unified diff of each modified file.
```

---

## Prompt 72: FederalHearingsClient Service

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4b

### Prompt

```
Create the FederalHearingsClient service following the exact pattern
of app/services/prepa_client.py. Read prepa_client.py first to match
constructor signature, auth provider injection, error handling, retry
logic, and logging patterns.

1. Create app/models/federal.py with Pydantic v2 models:
   HearingCase — hearing_id, agency_code, aj_employee_id, stage_code,
     filed_date, closed_date, disposition_code, created_at, updated_at
   HearingClaim — claim_id, hearing_id, basis_code, issue_code,
     statute_code
   HearingConference — conference_id, hearing_id, conference_type,
     scheduled_date, held_flag, outcome_code
   HearingAction — action_id, hearing_id, action_code, action_date,
     performed_by
   HearingAssessment — assessment_id, hearing_id, merit_assessment,
     monetary_request, recommended_remedy
   HearingNote — note_id, hearing_id, note_type, authored_date
     (no note_text — PII risk; text fetched only on explicit request)
   HearingCasesResponse — cases: list[HearingCase], total: int,
     page: int, page_size: int

   All models: use Optional for nullable fields, Field(alias=...) if
   ARC uses camelCase, model_config = ConfigDict(populate_by_name=True)

2. Create app/services/federal_hearings_client.py:
   Class FederalHearingsClient:
     __init__(self, auth_provider, settings): build httpx.AsyncClient
       with base_url=settings.arc_federal_hearings_url, timeout=30s,
       inject auth token from auth_provider on each request
     async get_hearing_cases(agency_code: str, status: str | None)
       -> HearingCasesResponse
     async get_hearing_case(case_id: int) -> HearingCase
     async get_hearing_actions(case_id: int) -> list[HearingAction]
     async get_hearing_conferences(case_id: int)
       -> list[HearingConference]
     async get_hearing_claims(case_id: int) -> list[HearingClaim]
     async get_hearing_assessment(case_id: int) -> HearingAssessment
     async get_hearing_notes(case_id: int) -> list[HearingNote]
     async get_hearing_domain_lookup(domain: str) -> list[dict]
     async search_hearing_cases(query: dict) -> HearingCasesResponse

   All methods: raise FeatureDisabledError (from
   app/config/feature_flags.py — see Prompt 76) when
   settings.federal_sector_enabled is False. On HTTP error: raise
   with status code and upstream message. Propagate X-Request-ID
   from context var. Log at DEBUG before each request, INFO on
   success, ERROR on failure — never log response body.

3. Modify app/config.py Settings:
   Add arc_federal_hearings_url: str = ""
   Add federal_sector_enabled: bool = False

4. Add arc_federal_hearings_url and FEDERAL_SECTOR_ENABLED to README
   env var table with descriptions and default values.

Write CHANGES.md with unified diff of each new and modified file.
```

---

## Prompt 73: EmployerClient and Enforcement Method Additions

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4b

### Prompt

```
Add an EmployerClient service, Employer and Enforcement Pydantic models,
and 17 new methods on the existing PrepaClient. Read the existing
PrepaClient and models before writing.

1. Create app/models/employer.py:
   NaicsCode — naics_code, title, sector_code, subsector_code
   EmployerSearchResult — employer_id, employer_name, naics_code,
     state_code, employee_count_range, eeo1_filer_flag
   EmployerDetail — all EmployerSearchResult fields plus address,
     parent_employer_id, subsidiaries: list[str]

2. Create app/models/enforcement.py:
   EnforcementActivity — charge_number, activity_type, activity_date,
     status_code, assigned_to
   ConciliationStatus — charge_number, proposal_date, response_date,
     outcome_code, monetary_amount: Decimal | None
   CourtHearing — hearing_id: int | None, charge_number, hearing_date,
     court_name, judge_name, outcome_code, appeal_flag: bool
   SystemicCase — systemic_case_id, case_name, office_id, status_code,
     opened_date, closed_date
   SuspensionStatus — charge_number, suspension_reason_code,
     suspension_date, lift_date, is_active: bool
   TransferRecord — charge_number, from_office_id, to_office_id,
     transfer_date, reason_code
   ClosureReasonCode — code, description, category
   CaseNote — note_id, charge_number, note_type, authored_by,
     authored_date (no note_text field)

3. Create app/services/employer_client.py:
   Class EmployerClient following FederalHearingsClient pattern:
     base_url = settings.arc_employer_url
     async get_naics_code(naics_code: str) -> NaicsCode
     async search_naics(query: str) -> list[NaicsCode]
     async search_employer(name: str, state: str | None,
       naics: str | None) -> list[EmployerSearchResult]
     async get_employer(employer_id: str) -> EmployerDetail
     async search_eeo1(employer_id: str, year: int | None)
       -> list[dict]
   All methods raise FeatureDisabledError when
   settings.employer_service_enabled is False.

4. Add 17 methods to app/services/prepa_client.py:
   Enforcement data:
     async get_enforcement_position_statements(charge_number: str)
     async get_enforcement_fact_finding(charge_number: str)
     async get_enforcement_subpoenas(charge_number: str)
     async get_enforcement_communications(charge_number: str)
     async get_conciliation(charge_number: str) -> ConciliationStatus
     async get_court_hearings(charge_number: str) -> list[CourtHearing]
     async create_court_hearing(charge_number: str,
       data: CourtHearing) -> CourtHearing
     async update_court_hearing(charge_number: str, hearing_id: int,
       data: CourtHearing) -> CourtHearing
   Systemic cases:
     async get_systemic_cases(office_id: str | None,
       status: str | None) -> list[SystemicCase]
     async get_systemic_case(systemic_case_id: int) -> SystemicCase
     async get_systemic_case_charges(systemic_case_id: int)
       -> list[dict]
   Other:
     async get_suspension(charge_number: str) -> SuspensionStatus
     async get_transfers(charge_number: str) -> list[TransferRecord]
     async close_allegation(charge_number: str, allegation_id: int,
       reason_code: str) -> dict
     async get_benefit_groups() -> list[dict]
     async get_closure_reason_codes() -> list[ClosureReasonCode]
     async get_case_notes(charge_number: str) -> list[CaseNote]

   Methods gated by feature flags:
     get_court_hearings, create_court_hearing, update_court_hearing —
       require settings.court_hearings_enabled
     get_systemic_cases, get_systemic_case, get_systemic_case_charges
       — require settings.systemic_cases_enabled
     All others — require settings.enforcement_sync_enabled

5. Modify app/config.py:
   Add enforcement_sync_enabled: bool = False
   Add systemic_cases_enabled: bool = False
   Add employer_service_enabled: bool = False
   Add court_hearings_enabled: bool = False
   Add arc_employer_url: str = ""

Write CHANGES.md with unified diff of each new and modified file.
```

---

## Prompt 74: Federal Sector and Enforcement Routers

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4b

### Prompt

```
Create four new FastAPI routers covering federal hearings, enforcement
activities, systemic cases, and employer lookups. Read an existing
router (e.g., app/routers/charges.py or app/routers/triage.py) before
writing to match auth dependency patterns, Redis caching, audit
logging, and error response format exactly.

1. Create app/routers/federal.py (prefix /arc/v1/federal):
   GET  /cases                     list hearing cases, params: agency_code, status
   GET  /cases/{hearing_id}        single case detail
   GET  /cases/{hearing_id}/claims list claims for case
   GET  /cases/{hearing_id}/conferences
   GET  /cases/{hearing_id}/actions
   GET  /cases/{hearing_id}/assessment
   GET  /cases/{hearing_id}/notes
   POST /cases/search              body: HearingSearchRequest (agency_code,
                                   status, filed_after, filed_before, aj_id)
   All endpoints: read_dep auth dependency, cache GET responses in
   Redis (TTL 300s for lists, 120s for detail), emit audit log entry
   with endpoint + hearing_id (no PII), propagate X-Request-ID.
   Return HTTP 404 (not 403) when federal_sector_enabled is False.

2. Create app/routers/enforcement.py (prefix /arc/v1/enforcement):
   GET  /cases/{charge_number}/position-statements
   GET  /cases/{charge_number}/fact-finding
   GET  /cases/{charge_number}/subpoenas
   GET  /cases/{charge_number}/communications
   GET  /cases/{charge_number}/conciliation
   GET  /cases/{charge_number}/court-hearings
   POST /cases/{charge_number}/court-hearings    write_dep auth
   PUT  /cases/{charge_number}/court-hearings/{hearing_id}  write_dep
   GET  /cases/{charge_number}/suspension
   GET  /cases/{charge_number}/transfers
   GET  /cases/{charge_number}/benefit-groups
   GET  /cases/{charge_number}/notes
   GET  /closure-reason-codes                    (static, TTL 3600s)
   POST /cases/{charge_number}/allegations/{allegation_id}/close  write_dep
   All read endpoints: read_dep, Redis cache TTL 300s.
   Return HTTP 404 when enforcement_sync_enabled is False.

3. Create app/routers/systemic.py (prefix /arc/v1/systemic):
   GET /cases                      params: office_id, status
   GET /cases/{systemic_case_id}
   GET /cases/{systemic_case_id}/charges
   All: read_dep, Redis cache TTL 300s.
   Return HTTP 404 when systemic_cases_enabled is False.

4. Create app/routers/employer.py (prefix /arc/v1/employer):
   GET /search                     params: name, state, naics
   GET /{employer_id}
   GET /naics/{naics_code}
   GET /naics/search               params: query
   GET /{employer_id}/eeo1         params: year
   All: read_dep, Redis cache TTL 3600s (employer data changes rarely).
   Return HTTP 404 when employer_service_enabled is False.

5. Register all four routers in app/main.py with the same include
   pattern as existing routers.

6. All four routers use RFC 7807 Problem Details for errors (match
   existing router error format).

Write CHANGES.md with a list of every new endpoint, its method,
path, auth level, cache TTL, and feature flag dependency.
```

---

## Prompt 75: New MCP Tools for Gap Entities

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4b

### Prompt

```
Extend the MCP tool registry in app/routers/mcp.py with 11 new tools
covering the gap entities from Prompts 72-74. Read the full mcp.py
file first to understand _READ_TOOLS, _WRITE_TOOLS, and _dispatch_tool
structure before making changes.

1. Add 9 entries to _READ_TOOLS list:

   arc_get_enforcement_status
     description: "Get enforcement activity status for a charge,
       including conciliation, suspension, and transfer history."
     inputSchema: {"charge_number": {"type": "string"}}

   arc_get_court_hearings
     description: "List court hearings scheduled or completed for
       a charge number."
     inputSchema: {"charge_number": {"type": "string"}}

   arc_get_systemic_cases
     description: "List systemic investigation cases, optionally
       filtered by office and status."
     inputSchema: {"office_id": {"type": "string", "required": false},
       "status": {"type": "string", "required": false}}

   arc_get_case_notes
     description: "Retrieve case note metadata (type, date, author)
       for a charge. Note text is not returned — view in ARC directly."
     inputSchema: {"charge_number": {"type": "string"}}

   arc_get_suspension_status
     description: "Get the current suspension status for a charge,
       including reason and lift date if applicable."
     inputSchema: {"charge_number": {"type": "string"}}

   arc_get_federal_hearing
     description: "Get federal sector hearing case detail including
       stage, assigned AJ, and agency."
     inputSchema: {"hearing_id": {"type": "integer"}}

   arc_get_federal_hearing_claims
     description: "List claims (basis, issue, statute) for a federal
       sector hearing case."
     inputSchema: {"hearing_id": {"type": "integer"}}

   arc_get_closure_reasons
     description: "List all valid charge closure reason codes and
       their descriptions."
     inputSchema: {}

   arc_search_employer
     description: "Search for employer records by name, state, or
       NAICS code."
     inputSchema: {"name": {"type": "string", "required": false},
       "state": {"type": "string", "required": false},
       "naics": {"type": "string", "required": false}}

2. Add 2 entries to _WRITE_TOOLS list:

   arc_create_court_hearing
     description: "Schedule a new court hearing for a charge number.
       Requires ARC.Write role."
     inputSchema: {"charge_number": {"type": "string"},
       "hearing_date": {"type": "string", "format": "date"},
       "court_name": {"type": "string"},
       "judge_name": {"type": "string", "required": false}}

   arc_close_allegation
     description: "Close an allegation with a disposition code.
       Requires ARC.Write role. Irreversible — confirm before calling."
     inputSchema: {"charge_number": {"type": "string"},
       "allegation_id": {"type": "integer"},
       "reason_code": {"type": "string"}}

3. Add matching cases to _dispatch_tool() for all 11 tools, routing
   each to the appropriate router method or client call. Write tools
   require the ARC.Write role check — follow existing write tool
   pattern.

4. Feature-flag-gated tools: when the corresponding feature flag is
   False, return a MCP error response:
   {"error": {"code": -32004, "message": "Feature not enabled"}}
   Do not raise an exception — return the error dict.

5. Update the tool count comment in mcp.py to reflect the new total
   (18 existing + 11 new = 29 tools).

Write CHANGES.md listing all 11 new tools, their type (read/write),
feature flag dependency, and the dispatch target.
```

---

## Prompt 76: Feature Flags and Configuration Consolidation

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4b

### Prompt

```
Consolidate all new feature flags and configuration values added by
Prompts 71-75 into a clean, documented configuration layer.

1. Update app/config.py Settings class.
   Verify these fields exist (add if missing from prior prompts):
     federal_sector_enabled: bool = False
     enforcement_sync_enabled: bool = False
     systemic_cases_enabled: bool = False
     employer_service_enabled: bool = False
     court_hearings_enabled: bool = False
     arc_federal_hearings_url: str = ""
     arc_employer_url: str = ""
     service_bus_user_mgmt_topic: str = ""
     service_bus_federal_hearing_topic: str = ""
     service_bus_user_mgmt_enabled: bool = False
     service_bus_federal_hearing_enabled: bool = False
     cache_ttl_hearing_list: int = 300
     cache_ttl_hearing_detail: int = 120
     cache_ttl_enforcement: int = 300
     cache_ttl_employer: int = 3600

   Group these under a comment block:
   # Phase 4b — Federal Sector, Enforcement, Employer feature flags

2. Create app/config/feature_flags.py:

   class FeatureDisabledError(Exception):
     """Raised when a disabled feature is accessed."""
     def __init__(self, feature_name: str) -> None:
       super().__init__(f"Feature '{feature_name}' is not enabled")
       self.feature_name = feature_name

   def is_enabled(flag_name: str, settings=None) -> bool:
     """Return True if the named feature flag is enabled.
     Resolves settings from dependency injection or import fallback.
     Logs a structured WARNING when a disabled feature is accessed,
     including flag_name and caller module — never logs PII."""
     ...

   The is_enabled function should accept an optional settings object
   for testability. If settings is None, import from app/config.py.
   Log at WARNING level using structlog or the project's existing
   logger when a flag is False and a caller attempts access, so that
   operations can identify misconfigured deployments.

3. Verify all routers added in Prompt 74 reference cache TTL constants
   from settings (cache_ttl_hearing_list etc.) rather than hardcoded
   integers. If any router hardcodes a TTL, update it to read from
   settings.

4. Update README.md env var table with all 15 new variables. Each
   entry: variable name, type, default, description. Group under
   heading "Phase 4b Configuration".

Write CHANGES.md listing every setting added or verified, and confirming
the feature_flags.py module was created.
```

---

## Prompt 77: Unit Tests for Phase 4b

**Repository:** eeoc-arc-integration-api/
**Owner:** Hub team
**Phase:** 4b

### Prompt

```
Write comprehensive unit tests for all Phase 4b code. Read existing
test files in tests/ first to match the fixture patterns, mock
strategy, and assertion style before writing.

Create the following test files:

tests/test_federal_hearings_client.py
  - test_get_hearing_cases_success: httpx mock returns 200, verify
    HearingCasesResponse deserialized correctly
  - test_get_hearing_cases_filters_by_status: verify query params sent
  - test_get_hearing_case_success: single case, verify fields
  - test_get_hearing_claims_success: list response
  - test_get_hearing_client_raises_when_disabled: settings.federal_sector_enabled=False,
    verify FeatureDisabledError raised
  - test_get_hearing_client_http_error: httpx mock returns 503,
    verify exception with status code

tests/test_employer_client.py
  - test_search_employer_success
  - test_get_employer_success
  - test_get_naics_success
  - test_employer_client_raises_when_disabled
  - test_employer_http_error

tests/test_enforcement_methods.py
  - test_get_conciliation_success
  - test_get_court_hearings_success
  - test_create_court_hearing_success
  - test_get_systemic_cases_success
  - test_get_suspension_success
  - test_get_case_notes_success: verify note_text NOT in returned model
  - test_enforcement_raises_when_disabled
  - test_court_hearings_raises_when_court_hearings_disabled

tests/test_router_federal.py
  - Use TestClient, mock FederalHearingsClient
  - test_list_hearing_cases_200
  - test_get_hearing_case_200
  - test_search_hearing_cases_200
  - test_hearing_routes_return_404_when_flag_off: set
    federal_sector_enabled=False, verify all endpoints return 404
  - test_hearing_routes_require_auth: remove auth header, verify 401

tests/test_router_enforcement.py
  - test_get_conciliation_200
  - test_post_court_hearing_201
  - test_put_court_hearing_200
  - test_close_allegation_200
  - test_enforcement_routes_return_404_when_flag_off

tests/test_router_systemic.py
  - test_list_systemic_cases_200
  - test_get_systemic_case_200
  - test_systemic_routes_return_404_when_flag_off

tests/test_router_employer.py
  - test_search_employer_200
  - test_get_employer_200
  - test_employer_routes_return_404_when_flag_off

tests/test_mcp_new_tools.py
  - test_all_11_new_tools_in_tool_list: verify each tool name appears
    in the tools list response
  - test_arc_get_enforcement_status_dispatch: call tool, verify routed
    to enforcement client
  - test_arc_create_court_hearing_requires_write_role: mock read-only
    token, verify error returned
  - test_arc_close_allegation_dispatches: verify allegation_id and
    reason_code forwarded
  - test_gated_tool_returns_error_when_disabled: set flag off, call
    tool, verify error code -32004

tests/test_feature_flags.py
  - test_is_enabled_returns_true_when_flag_set
  - test_is_enabled_returns_false_when_flag_unset
  - test_is_enabled_logs_warning_when_false: capture log output,
    verify WARNING emitted with flag_name
  - test_feature_disabled_error_message_contains_flag_name
  - test_gating_behavior_in_client: end-to-end — Settings flag=False,
    call client method, verify FeatureDisabledError propagates

Run pytest tests/ -v after writing. All tests must pass with zero
failures. If any existing test breaks due to Phase 4b changes, fix it.

Write CHANGES.md listing each new test file and the count of test
functions in each.
```

---

## Prompt 78: OGC TrialTool — Enforcement and Court Hearing Data

**Repository:** eeoc-ogc-trialtool/
**Owner:** OGC team
**Phase:** 5

### Prompt

```
Add enforcement timeline and court hearing views to the OGC Trial Tool.
Read arc_lookup.py (in eeoc-ofs-triage/ — study as the reference
pattern for calling the ARC Integration API), and read the existing
OGC Trial Tool's structure and templates before writing.

1. Create trial_tool_webapp/arc_enforcement_client.py:
   A thin async wrapper calling the ARC Integration API endpoints
   added in Prompt 74. Follow arc_lookup.py's pattern: managed
   identity token acquisition, httpx.AsyncClient, X-Request-ID
   propagation, structured logging, non-fatal error handling (return
   None on failure, log warning).

   Functions:
     async def get_enforcement_status(charge_number: str) -> dict | None
       Calls GET /arc/v1/enforcement/cases/{charge_number}/conciliation
       and GET .../suspension, returns combined dict.
     async def get_court_hearings(charge_number: str) -> list[dict]
       Calls GET /arc/v1/enforcement/cases/{charge_number}/court-hearings
     async def create_court_hearing(charge_number: str,
       data: dict) -> dict | None
       Calls POST /arc/v1/enforcement/cases/{charge_number}/court-hearings
     async def update_court_hearing(charge_number: str,
       hearing_id: int, data: dict) -> dict | None
       Calls PUT .../court-hearings/{hearing_id}

   Gate each function: return None/[] immediately when
   ENFORCEMENT_DATA_ENABLED env var is not "true".

2. Add two routes to the existing case detail Blueprint:
   GET  /cases/<case_name>/enforcement
     Fetch enforcement status via arc_enforcement_client.
     Render enforcement_detail.html.
     Gate with ENFORCEMENT_DATA_ENABLED.
   GET  /cases/<case_name>/court-hearings
     Fetch court hearings list.
     Render court_hearings.html.
     Gate with COURT_HEARING_ENABLED.
   POST /cases/<case_name>/court-hearings
     Create new court hearing via arc_enforcement_client.
     Redirect to GET on success.
     Gate with COURT_HEARING_ENABLED.
   PUT  /cases/<case_name>/court-hearings/<hearing_id>
     Update court hearing.

3. Create templates/enforcement_detail.html:
   Extend base.html. Show enforcement timeline: conciliation status,
   suspension status, transfer history. Read-only view.
   508 compliance: table with headers, no color-only indicators,
   status uses text + icon with aria-label.

4. Create templates/court_hearings.html:
   Extend base.html. List upcoming and past hearings in a sortable
   table. Include "Schedule Hearing" form (hearing_date, court_name,
   judge_name fields) when COURT_HEARING_ENABLED is true. Edit inline
   or via modal. 508 compliant: form labels, aria-required, error
   announcements via aria-live.

5. Add two MCP tools to mcp_server.py (follow existing OGC tool
   pattern):
   ogc_get_enforcement_timeline — calls arc_enforcement_client
   ogc_get_court_hearings — calls arc_enforcement_client
   Both gated by feature flags.

6. Add "Enforcement" and "Court Hearings" tabs to the case detail
   navigation (wherever existing tabs like "Documents", "Timeline" are
   defined). Show tabs only when respective flags are enabled.

7. Add ENFORCEMENT_DATA_ENABLED and COURT_HEARING_ENABLED to
   .env.example and the config/README if one exists.

Write CHANGES.md listing all new files and modified files.
```

---

## Prompt 79: Triage Federal Sector Data Path

**Repository:** eeoc-ofs-triage/
**Owner:** Triage team
**Phase:** 5

### Prompt

```
Add a federal sector data path to the Triage application. When a charge
is identified as federal sector, fetch hearing metadata from the ARC
Integration API to enrich the AI classification pipeline.

Read arc_lookup.py and blueprints/cases.py before writing to match
existing patterns for ARC calls, error handling, and AI pipeline
context injection.

1. Create triage_webapp/federal_lookup.py:

   async def lookup_federal_hearing_metadata(
     charge_number: str
   ) -> dict | None:
     """Fetch federal hearing metadata for a charge number.

     Returns a dict with keys: agency_name, claims (list of
     basis/issue pairs), stage, assigned_aj_id — or None if the
     charge has no federal hearing, the API is unavailable, or
     FEDERAL_SECTOR_ENABLED is not 'true'.

     Non-fatal: all exceptions are caught and logged at WARNING.
     Never logs charge content beyond charge_number.
     """
     if not os.environ.get("FEDERAL_SECTOR_ENABLED") == "true":
         return None
     Call GET /arc/v1/federal/cases/search with charge_number param
     (or the appropriate search endpoint from Prompt 74).
     Extract and return the relevant fields. On 404: return None.
     On any other error: log and return None.

   Follow arc_lookup.py's auth pattern (managed identity token,
   httpx, X-Request-ID propagation).

2. Modify arc_lookup.py:
   In the function that fetches charge detail (read the file to find
   the correct function), add a detection step after the ARC response
   is received:

     is_federal = (
       charge_data.get("institution_type") == "FEDERAL" or
       charge_data.get("sector") == "FEDERAL"
     )

   If is_federal is True and FEDERAL_SECTOR_ENABLED is "true":
     Call lookup_federal_hearing_metadata(charge_number) and attach
     the result to the charge_data dict under the key
     "federal_hearing_metadata".
   This is additive — no existing fields are changed or removed.

3. Modify blueprints/cases.py:
   In the AI classification pipeline context-building step, when
   "federal_hearing_metadata" is present in charge_data, add it to
   the AI context dict under key "federal_hearing_context". Include:
   agency_name, claims summary (basis/issue codes only — no free
   text), stage.
   This gives the AI model federal-specific context for better
   classification of federal sector charges.

4. Modify the case review template (read the file to find it):
   When charge_data contains "federal_hearing_metadata", add a
   "Federal Hearing Detail" card below existing charge detail cards.
   Show: Agency, Stage, Claims (table of basis/issue), Assigned AJ ID.
   Read-only. 508 compliant (table headers, card region landmark).
   Show the card only when federal_hearing_metadata is not None.

5. Add FEDERAL_SECTOR_ENABLED to .env.example (default "false") and
   to the configuration table in the Triage README.

Write CHANGES.md listing all files modified and describing each change.
```

---

## Prompt 80: ADR Conciliation and Case Notes Wiring

**Repository:** eeoc-ofs-adr/
**Owner:** ADR team
**Phase:** 5

### Prompt

```
Wire conciliation status and case notes from the ARC Integration API
into the ADR mediator interface. Read adr_webapp/arc_client.py,
adr_functionapp/shared/arc_client.py, and the mediator case detail
template before writing.

1. Add two methods to adr_webapp/arc_client.py:

   async def get_conciliation_status(
     self, charge_number: str
   ) -> dict | None:
     """Fetch conciliation proposal/response status from ARC.
     Returns dict with keys: proposal_date, response_date,
     outcome_code, monetary_amount — or None on 404 or error.
     Non-fatal. Never logs monetary_amount (treat as PII-adjacent)."""
     Calls GET /arc/v1/enforcement/cases/{charge_number}/conciliation
     Gate: return None when CONCILIATION_ENABLED is not "true".

   async def get_case_notes(
     self, charge_number: str
   ) -> list[dict]:
     """Fetch case note metadata list from ARC.
     Returns list of {note_id, note_type, authored_date, authored_by}.
     No note_text field — text is not fetched to avoid PII exposure.
     Non-fatal: returns [] on error."""
     Calls GET /arc/v1/enforcement/cases/{charge_number}/notes
     Gate: return [] when CASE_NOTES_ENABLED is not "true".

2. Add the same two methods to adr_functionapp/shared/arc_client.py,
   matching the existing sync or async pattern in that module (read
   the file first — function app client may be sync).

3. Modify the mediator case detail template (read the file to find it):
   a. Add a "Post-Mediation Status" card when CONCILIATION_ENABLED
      is true and conciliation_status is not None:
      - Proposal Date, Response Date, Outcome (text label from
        outcome_code), Monetary Amount redacted as "$***" (do not
        display actual amount in UI — compliance requirement)
      - Read-only. ARIA region with label "Post-Mediation Status".
      - 508: no color-only status indicators.
   b. Add a "Case Notes" tab to the case detail tab set when
      CASE_NOTES_ENABLED is true:
      - Table: Note Type, Author, Date — reverse chronological order
      - No note text displayed
      - 508: table with thead, th scope="col", caption

4. Modify the mediator case detail view function (in routes or
   blueprints — read to find it) to:
   a. Call get_conciliation_status when CONCILIATION_ENABLED is "true"
   b. Call get_case_notes when CASE_NOTES_ENABLED is "true"
   c. Pass results to template context as conciliation_status and
      case_notes respectively

5. Add CONCILIATION_ENABLED and CASE_NOTES_ENABLED to:
   - adr_webapp/.env.example (default "false")
   - deploy/k8s/adr-webapp/configmap.yaml (value "false")
   - ADR README configuration table

Write CHANGES.md listing all files modified.
```

---

## Prompt 81: Analytics Dashboard — Federal Hearing and Enforcement Views

**Repository:** eeoc-data-analytics-and-dashboard/
**Owner:** UDIP team
**Phase:** 5

### Prompt

```
Add SQL views and MCP tools for federal hearing and enforcement
analytics. Read analytics-db/views/ for existing view patterns and
ai-assistant/app/mcp_server.py for tool registration patterns before
writing.

1. Create analytics-db/views/vw_hearing_cases.sql:
   SELECT from analytics.hearing_cases. Include:
   - hearing_case_id (source_hearing_case_id), agency_code, stage_code,
     filed_date, closed_date, disposition_code, fiscal_year,
     lifecycle_state
   - Derived: is_resolved (lifecycle_state IN ('closed','purged'))
   - Filter: WHERE lifecycle_state != 'purged' (default view)
   Follow the exact CREATE OR REPLACE VIEW pattern from existing views.
   Add COMMENT ON VIEW.

2. Create analytics-db/views/vw_hearing_claims_summary.sql:
   Aggregate hearing_claims joined to hearing_cases:
   SELECT fiscal_year, agency_code, basis_code, issue_code,
     COUNT(*) AS claim_count
   FROM analytics.hearing_claims hc
   JOIN analytics.hearing_cases hcase
     ON hc.source_hearing_case_id = hcase.source_hearing_case_id
   WHERE hcase.lifecycle_state != 'purged'
   GROUP BY fiscal_year, agency_code, basis_code, issue_code
   Add COMMENT ON VIEW.

3. Create analytics-db/views/vw_enforcement_summary.sql:
   Aggregate conciliations joined to charges (use source charge_number
   as join key if charges table exists, otherwise standalone):
   SELECT fiscal_year, outcome_code,
     COUNT(*) AS case_count,
     SUM(CASE WHEN outcome_code = 'SUCCESS' THEN 1 ELSE 0 END)
       AS successful_conciliations
   FROM analytics.conciliations
   WHERE lifecycle_state != 'purged'
   GROUP BY fiscal_year, outcome_code
   Add COMMENT ON VIEW.

4. Create analytics-db/views/vw_conciliation_outcomes.sql:
   Extend vw_enforcement_summary with office dimension (join to a
   charges or office table if available, else use a placeholder
   office_id = 'UNKNOWN' with a comment noting the join dependency):
   Include: fiscal_year, office_id, outcome_code, case_count,
   success_rate NUMERIC(5,2) computed as
   (successful / NULLIF(case_count, 0)) * 100
   Add COMMENT ON VIEW.

5. Create analytics-db/views/vw_court_hearings.sql:
   SELECT from analytics.court_hearings:
   - hearing_date, court_name, outcome_code, appeal_flag,
     fiscal_year derived from hearing_date,
     is_upcoming (hearing_date > CURRENT_DATE),
     lifecycle_state
   WHERE lifecycle_state != 'purged'
   Add COMMENT ON VIEW.

6. Create ai-assistant/app/tools/federal_hearing_tools.py:
   Follow the pattern of existing tool files in that directory.
   Four async tool functions:

   async def udip_get_hearing_caseload(
     agency_code: str | None = None,
     fiscal_year: int | None = None
   ) -> dict:
     Query vw_hearing_cases. Return aggregated counts by stage_code.
     If no filters: return current fiscal year. Never return individual
     case records — aggregate only.

   async def udip_get_enforcement_metrics(
     fiscal_year: int | None = None
   ) -> dict:
     Query vw_enforcement_summary. Return case counts and success
     rate by outcome_code.

   async def udip_get_conciliation_rates(
     office_id: str | None = None,
     fiscal_year: int | None = None
   ) -> dict:
     Query vw_conciliation_outcomes. Return success_rate by office
     and fiscal year.

   async def udip_get_court_hearing_schedule(
     upcoming_only: bool = True
   ) -> dict:
     Query vw_court_hearings. Return count of upcoming hearings by
     court_name if upcoming_only, else return outcome summary.

   All functions: read-only database access, 30-second timeout,
   return structured dicts not raw rows, aggregate only — no charge
   numbers or individual identifiers in return values.

7. Register all four tools in ai-assistant/app/mcp_server.py following
   the existing tool registration pattern (import function, add to
   tools list/dict with name and description).

Write CHANGES.md listing all new SQL files, the new tools file, and
the mcp_server.py registration.
```

---

## Prompt 82: Unified Staff Portal — Blueprint Extraction and Shared Navigation

**Repository:** eeoc-ofs-adr/ and eeoc-ofs-triage/
**Owner:** ADR + Triage teams
**Phase:** 6

### Prompt

```
Create the foundation of the Unified Staff Portal within eeoc-ofs-adr/.
This portal combines ADR and Triage under a single navigation surface
without merging their databases or cases.

Read adr_webapp/__init__.py, adr_webapp/routes/__init__.py,
and triage_webapp/__init__.py before writing to understand existing
app factory and blueprint registration patterns.

1. Create staff_portal/__init__.py:
   App factory create_app(config_override: dict | None = None)
     -> Flask:
   - Create Flask app
   - Load config from environment (follow existing config pattern)
   - Register extensions: Redis session, login manager
   - Import and register ADR blueprints under url_prefix="/adr"
     (read adr_webapp/routes/__init__.py to find all blueprints)
   - Import and register Triage blueprints under url_prefix="/triage"
     (read triage_webapp to find entry blueprints)
   - Register the context processor from staff_portal/shared/nav.py
   - Register /healthz route returning {"status": "ok"}
   - Return app

   Both standalone apps must still start independently — do not
   modify their own create_app() functions. The portal create_app()
   imports from them; it does not replace them.

2. Create staff_portal/shared/nav.py:
   Context processor inject_nav_context() -> dict:
   Returns {"nav_sections": [...]} where each section is:
   {"label": str, "url": str, "visible": bool, "active": bool}
   Sections: "Mediation" (url /adr/), "Triage" (url /triage/)
   visible is determined by user roles in session:
   - Mediation visible when session role includes "mediator" or
     "coordinator" or "supervisor"
   - Triage visible when session role includes "coordinator" or
     "supervisor" or "intake_coordinator"
   active is True when request.path starts with the section url.
   Returns empty nav_sections list when no session (unauthenticated).

3. Create staff_portal/shared/templates/base_portal.html:
   Extends nothing (is the root base). Imports from shared static.
   Navigation bar: horizontal list of nav_sections, showing only
   visible sections, marking active with aria-current="page".
   Skip-navigation link at top: <a href="#main-content">Skip to main
   content</a> (508 requirement).
   Main content area: <main id="main-content" role="main">.
   Footer: EEOC branding, no PII.
   4.5:1 contrast minimum for all text. No color-only indicators.
   All interactive elements reachable by keyboard.

4. Create Azure Table unified_case_index schema definition in
   staff_portal/shared/unified_case_index.py:
   Class UnifiedCaseIndex with PartitionKey = app_source ("adr" or
   "triage"), RowKey = case_identifier, fields: case_number,
   display_name, status, app_url (relative URL within the portal).
   Methods:
     upsert_case(entity: dict) -> None
     lookup_case(case_number: str) -> dict | None
     search_cases(query: str, app_source: str | None) -> list[dict]
   Use Azure Table Storage SDK. Connection string from env var
   UNIFIED_CASE_INDEX_CONNECTION_STRING. Non-fatal: log and return
   None/[] on error.

5. Modify adr_webapp/routes/__init__.py:
   Wrap each blueprint.register call so blueprints can be imported
   with or without a url_prefix. If blueprints are registered directly
   (not via a register function), refactor to a register_blueprints(app,
   prefix="") function that the portal can call with prefix="/adr" and
   the standalone app can call with prefix="".

6. Add UNIFIED_CASE_INDEX_CONNECTION_STRING to eeoc-ofs-adr/.env.example.

Write CHANGES.md listing all new files and the modification to
adr_webapp/routes/__init__.py.
```

---

## Prompt 83: Unified Staff Portal — Shared Auth and Role Resolution

**Repository:** eeoc-ofs-adr/
**Owner:** ADR + Triage teams
**Phase:** 6

### Prompt

```
Build the shared authentication and role resolution layer for the
Unified Staff Portal. Read staff_portal/__init__.py (Prompt 82),
adr_webapp/auth.py (or wherever MSAL login is implemented in ADR),
and any existing role/permission code before writing.

1. Create staff_portal/shared/role_resolver.py:

   ROLE_GROUP_MAP: dict[str, str] = {
     # Map Entra ID group object IDs or display names to portal roles.
     # Values read from env vars at startup — not hardcoded.
     # Pattern: GROUP_MEDIATOR_ID, GROUP_COORDINATOR_ID, etc.
   }

   def resolve_roles(group_ids: list[str], settings=None) -> list[str]:
     """Map a user's Entra ID group memberships to portal role names.
     Returns a list of role strings: e.g. ['mediator', 'coordinator'].
     Unknown groups are silently ignored.
     Group-to-role mapping is loaded from env vars:
       PORTAL_GROUP_MEDIATOR, PORTAL_GROUP_COORDINATOR,
       PORTAL_GROUP_SUPERVISOR, PORTAL_GROUP_ATTORNEY,
       PORTAL_GROUP_ADMIN
     Each env var contains the Entra ID group object ID (UUID) for
     that role. A user can have multiple roles."""

   def get_highest_role(roles: list[str]) -> str:
     """Return the highest-privilege role from a list.
     Order: admin > supervisor > attorney > coordinator > mediator >
     intake_coordinator. Returns 'guest' if list is empty."""

2. Create staff_portal/shared/session_manager.py:

   def populate_portal_session(
     user_info: dict,
     group_ids: list[str],
     session: dict
   ) -> None:
     """Populate Flask session with portal role context.
     Sets: session['portal_roles'], session['primary_role'],
     session['display_name'], session['user_oid'].
     Replaces any prior portal session fields.
     Never logs user_info contents."""

   def get_portal_roles(session: dict) -> list[str]:
     """Return portal roles from session, or [] if not set."""

   def clear_portal_session(session: dict) -> None:
     """Remove all portal-specific keys from session on logout."""

3. Create staff_portal/shared/decorators.py:

   def portal_login_required(f):
     """Redirect to /auth/login if session has no portal_roles."""

   def require_role(role: str):
     """Return 403 if user does not have the specified role.
     Use as @require_role('mediator')."""

   def require_any_role(roles: list[str]):
     """Return 403 if user has none of the specified roles.
     Use as @require_any_role(['mediator', 'coordinator'])."""

   All decorators preserve function name via @functools.wraps.
   403 responses use RFC 7807 Problem Details format.

4. Create staff_portal/shared/auth.py:
   Single MSAL login flow for the portal. Read adr_webapp/auth.py
   to understand the existing MSAL client setup and token flow, then
   adapt it:
   - On callback: extract groups claim from ID token (or call Graph
     API /me/memberOf if groups not in token due to size limit)
   - Call role_resolver.resolve_roles(group_ids)
   - Call session_manager.populate_portal_session(user_info, groups,
     session)
   - Redirect to originally requested URL or /adr/ as default
   - Logout route: call session_manager.clear_portal_session, then
     MSAL logout with post_logout_redirect_uri

   The existing standalone ADR auth (adr_webapp/auth.py) is preserved
   unchanged. The portal auth module is separate and additive.

5. Add env vars to eeoc-ofs-adr/.env.example:
   PORTAL_GROUP_MEDIATOR=
   PORTAL_GROUP_COORDINATOR=
   PORTAL_GROUP_SUPERVISOR=
   PORTAL_GROUP_ATTORNEY=
   PORTAL_GROUP_ADMIN=

Write CHANGES.md listing all new files and confirming adr_webapp/auth.py
was not modified.
```

---

## Prompt 84: Unified Staff Portal — Deployment

**Repository:** eeoc-ofs-adr/
**Owner:** Hub team
**Phase:** 6

### Prompt

```
Create the deployment artifacts for the Unified Staff Portal. Read
existing Dockerfiles and K8s manifests in eeoc-ofs-adr/deploy/ and
eeoc-ofs-triage/deploy/ before writing to match conventions.

1. Create staff_portal/Dockerfile:
   Multi-stage build:
   Stage 1 (builder): python:3.12-slim-bookworm, install build deps,
     pip install --no-cache-dir -r staff_portal/requirements.txt into
     /install
   Stage 2 (runtime): python:3.12-slim-bookworm, non-root user
     (useradd -r -u 1001 portal), copy /install from builder, copy:
       adr_webapp/
       adr_functionapp/shared/
       triage_webapp/
       staff_portal/
     WORKDIR /app, USER portal
   CMD: gunicorn --worker-class gevent --workers 4 --bind 0.0.0.0:8080
     --timeout 60 --access-logfile - --error-logfile -
     "staff_portal:create_app()"
   EXPOSE 8080
   No secrets or credentials in the image. No pip install at runtime.

2. Create staff_portal/requirements.txt:
   Merge requirements from adr_webapp/requirements.txt and
   triage_webapp/requirements.txt. Deduplicate. Pin all versions.
   Add gunicorn[gevent] if not already present.
   Add azure-data-tables for UnifiedCaseIndex.
   Retain any ADR or Triage version pins — do not upgrade packages.
   If there are version conflicts between ADR and Triage dependencies,
   flag each conflict in a comment and resolve to the higher version
   unless that would break a known constraint.

3. Create staff_portal/deploy/k8s/portal-deployment.yaml:
   Deployment in namespace udip (or match existing app namespace).
   Image: pulled from ACR, tag from CI (use image: PORTAL_IMAGE
   placeholder with a comment). Replicas: 2.
   Resources: requests cpu=250m memory=512Mi, limits cpu=1000m
   memory=1Gi. Non-root security context (runAsUser: 1001,
   runAsNonRoot: true, readOnlyRootFilesystem: true).
   Liveness probe: GET /healthz, initialDelaySeconds 15, period 20.
   Readiness probe: GET /healthz, initialDelaySeconds 10, period 10.
   envFrom: configMapRef portal-configmap, secretRef portal-secrets.
   Volumes: emptyDir for /tmp (required for readOnlyRootFilesystem).

4. Create staff_portal/deploy/k8s/portal-service.yaml:
   Service type ClusterIP, port 80 → targetPort 8080. Add annotation
   for Azure internal load balancer if other services use it.

5. Create staff_portal/deploy/k8s/portal-configmap.yaml:
   Non-secret configuration: FLASK_ENV, LOG_LEVEL, REDIS_URL (no
   password), UNIFIED_CASE_INDEX_CONNECTION_STRING placeholder comment,
   PORTAL_GROUP_* vars as empty strings (values from secrets at deploy).
   Comment at top: "# Secrets (MSAL keys, Redis password, HMAC key)
   must come from portal-secrets — never put them here."

6. Create staff_portal/deploy/k8s/portal-hpa.yaml:
   HorizontalPodAutoscaler: min 2, max 6 replicas, CPU utilization
   target 70%. Match API version used in other HPA files in the repo.

7. Create .github/workflows/portal-build-and-test.yml:
   Trigger: push to main or PR targeting main, path filter
   staff_portal/** or adr_webapp/** or triage_webapp/**.
   Jobs:
   lint-and-test:
     - Checkout
     - Setup Python 3.12
     - pip install -r staff_portal/requirements.txt
     - ruff check staff_portal/ adr_webapp/ triage_webapp/
     - mypy --strict staff_portal/
     - pytest tests/ triage_webapp/tests/ -v --tb=short
   build-and-push (depends on lint-and-test, runs on main only):
     - Docker buildx build --file staff_portal/Dockerfile
     - Tag: acr.azurecr.io/eeoc-staff-portal:${{ github.sha }}
     - Push to ACR (use OIDC workload identity — no stored passwords)
   deploy-staging (depends on build-and-push, runs on main only):
     - kubectl set image deployment/portal portal=<new image>
     - kubectl rollout status deployment/portal --timeout=120s

   This CI/CD pipeline does NOT replace individual app pipelines for
   eeoc-ofs-adr or eeoc-ofs-triage. It is an additional pipeline.
   No hardcoded credentials. Use GitHub Actions OIDC for ACR auth.

Write CHANGES.md listing all new files and noting that individual ADR
and Triage deployments are unaffected.
```

---

## Prompt 66: Advanced Security Scanning — ScanCode, OSV, Grype, PII Rules, Checkov, Fuzzing, SLSA, Authenticated DAST

**Repositories:** All 7 EEOC repos (run per repo where applicable)
**Owner:** All teams
**Phase:** 2 (before FedRAMP assessment — closes remaining gaps vs. commercial SCA/IAST)

### Prompt (All repos — scanning infrastructure, run once per repo)

```
ADVANCED SECURITY HARDENING: Add 7 new security scanning capabilities to
close gaps identified against Black Duck SCA and Synopsys Seeker IAST.

After this prompt, the platform will query 6 vulnerability advisory
databases (vs Black Duck's 2), perform snippet-level license detection
(matching Black Duck), detect PII leakage statically (partially matching
Seeker), scan infrastructure-as-code (neither commercial tool does this),
fuzz critical input functions, and generate supply chain provenance.

The only remaining gap vs. commercial tooling will be true IAST runtime
instrumentation, which requires a commercial product.

Implement ALL of the following in this repository.

=== PART 1: Snippet-Level License Detection (ScanCode) ===

ScanCode Toolkit detects licenses, copyrights, and code snippets matching
known open-source projects — including copy-pasted code without imports.
This is the capability that previously only Black Duck provided.

1. Add ScanCode to the security-audit-evidence.yml workflow:

   license-deep-scan:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: Install ScanCode
         run: pip install scancode-toolkit
       - name: Run ScanCode license + copyright scan
         run: |
           scancode \
             --license --copyright --package --classify \
             --json-pp scancode-results.json \
             --processes 4 \
             --timeout 120 \
             --ignore "*.pyc" --ignore "__pycache__" \
             --ignore "node_modules" --ignore ".git" \
             --ignore ".venv" --ignore "venv" \
             --ignore "example_data" \
             .
       - name: Check for copyleft licenses
         run: |
           python3 -c "
           import json, sys
           data = json.load(open('scancode-results.json'))
           copyleft = []
           for f in data.get('files', []):
               for lic in f.get('licenses', []):
                   cat = lic.get('category', '')
                   if 'copyleft' in cat.lower() and 'weak' not in cat.lower():
                       copyleft.append({
                           'file': f['path'],
                           'license': lic.get('spdx_license_key', 'unknown'),
                           'category': cat
                       })
           if copyleft:
               print('COPYLEFT LICENSES FOUND:')
               for c in copyleft:
                   print(f'  {c[\"file\"]}: {c[\"license\"]} ({c[\"category\"]})')
               sys.exit(1)
           print('No copyleft license issues found.')
           "
       - name: Upload ScanCode results
         if: always()
         uses: actions/upload-artifact@v4
         with:
           name: scancode-license-evidence
           path: scancode-results.json
           retention-days: 90

=== PART 2: Multi-Source Vulnerability Scanning (OSV + Grype) ===

Add two additional vulnerability scanners that query databases beyond NVD.
Combined with existing Trivy + pip-audit + OWASP Dependency-Check +
Dependabot, this gives us 6 advisory sources.

2. Add Google OSV Scanner to build-and-test.yml:

   osv-scan:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: OSV Scanner
         uses: google/osv-scanner-action/osv-scanner-action@v2
         with:
           scan-args: |-
             --recursive
             --format sarif
             --output osv-results.sarif
             .
       - name: Upload OSV results
         if: always()
         uses: github/codeql-action/upload-sarif@v3
         with:
           sarif_file: osv-results.sarif
         continue-on-error: true
       - name: Upload artifact
         if: always()
         uses: actions/upload-artifact@v4
         with:
           name: osv-scan-evidence
           path: osv-results.sarif
           retention-days: 90

3. Add Anchore Grype to build-and-test.yml:

   grype-scan:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: Grype vulnerability scan
         uses: anchore/scan-action@v4
         with:
           path: "."
           severity-cutoff: high
           fail-build: true
           output-format: sarif
       - name: Upload Grype results
         if: always()
         uses: github/codeql-action/upload-sarif@v3
         with:
           sarif_file: results.sarif
         continue-on-error: true

=== PART 3: PII Leakage Detection (Custom Semgrep Rules) ===

Static detection of PII flowing into logs, API responses, and exception
messages without hashing. Partially replicates Seeker IAST's data-flow
tracking capability.

4. Create .semgrep/pii-leak-detection.yml in the repo root:

   rules:
     - id: pii-in-log-statement
       patterns:
         - pattern-either:
             - pattern: logging.$METHOD(..., $VAR, ...)
             - pattern: logger.$METHOD(..., $VAR, ...)
             - pattern: app.logger.$METHOD(..., $VAR, ...)
             - pattern: structlog.get_logger().$METHOD(..., $VAR, ...)
         - metavariable-regex:
             metavariable: $VAR
             regex: ".*(email|ssn|social_security|phone|first_name|last_name|street_address|date_of_birth|dob|password|secret|token|api_key).*"
         - pattern-not: logging.$METHOD(..., _hash_pii($VAR), ...)
         - pattern-not: logging.$METHOD(..., hash_pii($VAR), ...)
         - pattern-not: logging.$METHOD(..., _mask_pii($VAR), ...)
       message: >
         PII field '$VAR' passed to log statement without hashing.
         Use _hash_pii() or _mask_pii() before logging.
       severity: ERROR
       languages: [python]
       metadata:
         category: security
         cwe: "CWE-532: Insertion of Sensitive Information into Log File"
         owasp: "A09:2021 Security Logging and Monitoring Failures"

     - id: pii-in-jsonify-response
       patterns:
         - pattern-either:
             - pattern: jsonify({..., "$KEY": $VAR, ...})
             - pattern: json.dumps({..., "$KEY": $VAR, ...})
         - metavariable-regex:
             metavariable: $KEY
             regex: "(email|ssn|social_security|phone|first_name|last_name|street_address|date_of_birth|dob|home_address)"
       message: >
         PII field '$KEY' included in API response. Verify the endpoint
         requires this field and that the caller is authorized for PII access.
       severity: WARNING
       languages: [python]
       metadata:
         category: security
         cwe: "CWE-359: Exposure of Private Personal Information"

     - id: pii-in-exception
       patterns:
         - pattern-either:
             - pattern: raise $EXC(f"...$VAR...")
             - pattern: raise $EXC(..., $VAR, ...)
         - metavariable-regex:
             metavariable: $VAR
             regex: ".*(email|ssn|phone|password|secret|token|api_key|connection_string).*"
       message: >
         Potential PII or secret in exception message. Exception text may
         appear in logs, error responses, or monitoring dashboards.
       severity: WARNING
       languages: [python]
       metadata:
         category: security
         cwe: "CWE-209: Generation of Error Message Containing Sensitive Info"

     - id: unhashed-oid-in-audit
       patterns:
         - pattern: |
             $DICT["$KEY"] = $VAR
         - metavariable-regex:
             metavariable: $KEY
             regex: "(CallerOID|UserID|UserId|user_id|caller_id|assigned_to|mediator_id)"
         - metavariable-regex:
             metavariable: $VAR
             regex: "^(?!.*hash)(?!.*Hash)(?!.*HASH).*$"
       message: >
         User identifier '$KEY' stored without hashing. Use SHA-256 or
         _hash_pii() before storing in audit records.
       severity: ERROR
       languages: [python]
       metadata:
         category: security
         cwe: "CWE-312: Cleartext Storage of Sensitive Information"

5. Add PII rules to the existing Semgrep scan step in CI:
   In the Semgrep scan command, add: --config .semgrep/
   This picks up the custom rules alongside the default rulesets.
   If the repo already passes --config p/python or similar, APPEND
   --config .semgrep/ as an additional config source.

=== PART 4: Infrastructure as Code Scanning (Checkov) ===

Scans K8s manifests, Dockerfiles, and Helm charts for security
misconfigurations. Neither Black Duck nor Seeker covers this.

6. Add Checkov to security-audit-evidence.yml (repos WITH deploy/k8s/):

   iac-scan:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - name: Checkov IaC security scan
         uses: bridgecrewio/checkov-action@v12
         with:
           directory: deploy/
           framework: kubernetes,dockerfile
           output_format: sarif
           output_file_path: checkov-results.sarif
           soft_fail: false
           skip_check: CKV_K8S_43  # skip image digest pin (we use Always pull)
       - name: Upload Checkov results
         if: always()
         uses: github/codeql-action/upload-sarif@v3
         with:
           sarif_file: checkov-results.sarif
         continue-on-error: true

   For repos WITHOUT K8s manifests (eeoc-ogc-trialtool, eeoc-mcp-hub-functions):
   - Only scan Dockerfile if one exists
   - Skip the job entirely if neither deploy/ nor Dockerfile exists

=== PART 5: Property-Based Fuzzing (Hypothesis) ===

Fuzz critical input-handling functions with random inputs to find
edge cases that unit tests miss. Focus on security-sensitive functions.

7. Add hypothesis to dev dependencies (requirements-dev.txt or equivalent).

8. Create tests/test_fuzz_security.py with fuzz tests for the repo's
   critical input functions. Choose from the following based on what
   exists in this repo:

   For repos with OData sanitization (ADR, Triage):
   ```python
   from hypothesis import given, strategies as st
   from hypothesis import settings as hyp_settings

   @given(st.text(min_size=0, max_size=2000, alphabet=st.characters()))
   @hyp_settings(max_examples=500)
   def test_sanitize_odata_rejects_injection(raw):
       """No input can produce unescaped single quotes in output."""
       result = sanitize_odata_value(raw)
       # After sanitization, any remaining ' must be doubled ''
       stripped = result.replace("''", "")
       assert "'" not in stripped
       assert "\x00" not in result
   ```

   For repos with PII hashing:
   ```python
   @given(st.text(min_size=1, max_size=500))
   @hyp_settings(max_examples=500)
   def test_hash_pii_never_returns_original(raw):
       """Hash output must never equal the input."""
       hashed = _hash_pii(raw)
       assert hashed != raw
       assert len(hashed) > 0

   @given(st.text(min_size=1, max_size=500))
   def test_hash_pii_is_deterministic(raw):
       """Same input always produces same hash."""
       assert _hash_pii(raw) == _hash_pii(raw)
   ```

   For repos with charge number validation:
   ```python
   @given(st.text(min_size=0, max_size=100, alphabet=st.characters()))
   @hyp_settings(max_examples=1000)
   def test_charge_number_validation_rejects_path_traversal(raw):
       """No input can bypass charge number regex to inject paths."""
       import re
       pattern = re.compile(r'^[A-Z0-9\-]{3,25}$')
       if not pattern.match(raw):
           # The validation function should reject this
           # (test the actual validation function used in the repo)
           pass
       else:
           assert '/' not in raw
           assert '..' not in raw
           assert '\x00' not in raw
   ```

   For repos with HMAC computation:
   ```python
   @given(st.binary(min_size=32, max_size=64), st.text(min_size=1, max_size=10000))
   def test_hmac_different_keys_different_output(key, data):
       """Different keys must produce different HMACs for same data."""
       import hmac, hashlib
       h1 = hmac.new(key, data.encode(), hashlib.sha256).hexdigest()
       h2 = hmac.new(key + b'\x00', data.encode(), hashlib.sha256).hexdigest()
       assert h1 != h2
   ```

   Include 3-5 fuzz tests per repo targeting the most security-critical
   functions. Run with: pytest tests/test_fuzz_security.py -v

=== PART 6: Supply Chain Provenance (SLSA + Cosign) ===

Generate build provenance and sign container images. FedRAMP Rev5 SR
family encourages (not yet requires) this. Neither Black Duck nor Seeker
provides it.

9. For repos that build container images (those with Dockerfile or
   container-build job in build-and-test.yml), add after the image build:

   - name: Install Cosign
     uses: sigstore/cosign-installer@v3

   - name: Sign container image
     if: github.ref == 'refs/heads/main'
     run: |
       cosign sign --yes \
         ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
     env:
       COSIGN_EXPERIMENTAL: "true"

   - name: Generate SLSA provenance attestation
     if: github.ref == 'refs/heads/main'
     run: |
       cosign attest --yes --predicate <(
         cat <<'PROVENANCE'
       {
         "buildType": "https://github.com/actions/runner",
         "builder": { "id": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" },
         "invocation": {
           "configSource": {
             "uri": "${{ github.server_url }}/${{ github.repository }}",
             "digest": { "sha1": "${{ github.sha }}" },
             "entryPoint": "${{ github.workflow }}"
           }
         },
         "metadata": {
           "buildStartedOn": "${{ github.event.head_commit.timestamp }}",
           "completeness": { "parameters": true, "environment": true, "materials": true }
         },
         "materials": [
           { "uri": "${{ github.server_url }}/${{ github.repository }}", "digest": { "sha1": "${{ github.sha }}" } }
         ]
       }
       PROVENANCE
       ) ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}

   For repos WITHOUT container images (pure Azure Functions or docs):
   skip this section entirely.

=== PART 7: Authenticated DAST Upgrade (ZAP Active Scan) ===

10. In security-audit-evidence.yml, if a DAST section already exists
    with ZAP baseline scan, upgrade it to an authenticated active scan:

    dast-authenticated:
      runs-on: ubuntu-latest
      if: inputs.staging_url != ''
      steps:
        - uses: actions/checkout@v4
        - name: ZAP authenticated full scan
          uses: zaproxy/action-full-scan@v0.12.0
          with:
            target: ${{ inputs.staging_url }}
            rules_file_name: ".zap/rules.tsv"
            allow_issue_writing: false
            artifact_name: "dast-authenticated-evidence"
            cmd_options: >
              -config replacer.full_list(0).description=AuthHeader
              -config replacer.full_list(0).enabled=true
              -config replacer.full_list(0).matchtype=REQ_HEADER
              -config replacer.full_list(0).matchstr=Authorization
              -config replacer.full_list(0).replacement="Bearer ${{ secrets.ZAP_AUTH_TOKEN }}"

    If no staging URL workflow_dispatch input exists, add one:
    on:
      workflow_dispatch:
        inputs:
          staging_url:
            description: 'Staging URL for authenticated DAST scan'
            required: false
            type: string

    Create .zap/rules.tsv if it does not exist:
    - Suppress known false positives (e.g., CSP report-uri informational)
    - Set threshold to MEDIUM for all other rules

    Note: The ZAP_AUTH_TOKEN secret must be configured in GitHub repo
    settings. Document this in README or CONTRIBUTING.md.

=== SUMMARY OF FILES TO CREATE/MODIFY ===

New files:
- .semgrep/pii-leak-detection.yml (PII static detection rules)
- tests/test_fuzz_security.py (property-based fuzz tests)
- .zap/rules.tsv (ZAP scan configuration)

Modified files:
- .github/workflows/security-audit-evidence.yml (add: ScanCode, Checkov, DAST upgrade)
- .github/workflows/build-and-test.yml (add: OSV, Grype, Cosign/SLSA)
- requirements-dev.txt or equivalent (add: hypothesis, scancode-toolkit)

Do NOT modify application code. This prompt adds scanning and testing
infrastructure only.

Write a CHANGES.md and unified diff.
```

---

## Prompt 85: OGC Trial Tool — Case Registry, RBAC, and Organizational Hierarchy

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 7 (OGC AI Assistant foundation — must complete before Prompts 86-89)

### Prompt

```
Build a case registry for the OGC Trial Tool that supports two types of
cases: OFP litigation cases (linked to ARC charges) and OGC-internal cases
(opened by OGC attorneys, not in ARC). Add organizational hierarchy and
case-level RBAC so attorneys only see their assigned cases.

CONTEXT: The Trial Tool currently has 9 AI analysis functions but no
persistent case registry, no per-case document management, and no
organizational scoping. This prompt builds the foundation for a
case-scoped AI Assistant (Prompt 87).

OGC handles litigation for the entire agency. Cases may come from OFP
(a charge was filed and OFP elected to prosecute) or be opened directly
by OGC (Commissioner charges, directed investigations, systemic cases).
OFP attorneys also litigate cases. Both offices need access, scoped to
their assigned cases.

1. Case registry data model:

   Create trial_tool_webapp/models/case_registry.py:

   class TrialCase:
     case_id: UUID (primary key, auto-generated)
     case_name: str (human-readable, e.g., "EEOC v. Acme Corp")
     case_number: str (OGC internal number, unique)
     charge_number: Optional[str] (ARC charge number if OFP-originated)
     case_type: str ("ofp_litigation", "commissioner_charge",
       "directed_investigation", "systemic", "amicus", "other")
     status: str ("open", "discovery", "trial_prep", "trial",
       "post_trial", "appeal", "settled", "closed")
     court_name: Optional[str] (e.g., "N.D. Ill.", "5th Cir.")
     court_case_number: Optional[str] (docket number)
     assigned_attorney_id: str (Entra ID OID, hashed for storage)
     assigned_paralegal_ids: list[str] (Entra ID OIDs)
     office: str ("OGC", "OFP")
     region: Optional[str] (for OFP district mapping)
     created_at: datetime
     updated_at: datetime
     closed_at: Optional[datetime]
     lifecycle_state: str ("active", "retained", "held", "archived")
     retention_expires_at: Optional[datetime]

   Storage: Azure Table Storage (primary) with PostgreSQL dual-write
   (same PG_MIGRATION_MODE pattern as ADR/Triage).
   PartitionKey: office (OGC or OFP)
   RowKey: case_id

2. Case CRUD API:

   Create trial_tool_webapp/routes/cases.py:
   - GET /cases — list cases (filtered by RBAC)
   - GET /cases/<case_id> — case detail
   - POST /cases — create new case
   - PUT /cases/<case_id> — update case metadata
   - POST /cases/<case_id>/close — close case, trigger retention
   - Auth: Entra ID, role-based (attorney, paralegal, supervisor,
     director, admin)

3. Organizational hierarchy (copy ADR pattern):

   Create trial_tool_webapp/helpers/office_hierarchy.py:
   - OGC hierarchy: OGC Director → Deputy → Supervisory Attorneys →
     Trial Attorneys + Paralegals
   - OFP litigation: uses existing OFP hierarchy from ADR
     (Regional Director → District → Supervisor → Attorney)
   - officestructure table: PartitionKey=office (OGC/OFP), RowKey=office_id
   - staffassignments table: user-to-office-to-role mapping
   - Session population on login: staff_role, office_id, office,
     subordinate_attorney_ids

4. Case-level RBAC:

   Three-layer access control (same as ADR):

   Layer 1 — Session scoping:
   - On login, populate session with role, office, assigned cases
   - Attorney: sees only own assigned cases
   - Supervisor: sees subordinate attorneys' cases
   - Director: sees all cases in their office
   - Admin/OCH: sees everything

   Layer 2 — Query filtering:
   - Case list queries filtered by assigned_attorney_id or office subtree
   - No cross-case data access unless authorized

   Layer 3 — PostgreSQL RLS (when PG_MIGRATION_MODE active):
   - SET LOCAL app.current_attorney, app.current_office
   - RLS policies filter by assignment

5. ARC charge linkage (optional, for OFP cases):

   When creating a case with a charge_number:
   - Pull charge metadata from ARC via Integration API
   - Auto-populate respondent name, basis codes, filing date
   - Display ARC charge status (read-only, pulled periodically)
   - Feature flag: ARC_CASE_LINK_ENABLED (default: false)

6. Case dashboard:

   Update trial_tool_webapp/templates/ with:
   - Case list view: filterable by status, office, attorney, case type
   - Case detail view: metadata, assigned staff, documents (Prompt 86),
     AI conversations (Prompt 87)
   - Status badges with 508-compliant colors
   - Office filter (OGC / OFP / All for admin)

7. Configuration:
   - OGC_CASE_REGISTRY_ENABLED: true (default)
   - ARC_CASE_LINK_ENABLED: false (default)
   - OGC_DEFAULT_RETENTION_YEARS: 7
   - PG_MIGRATION_MODE: "off" (default, same as ADR/Triage)

Write a CHANGES.md and unified diff.
```

---

## Prompt 86: OGC Trial Tool — Transcript Parser and Case Document Ingestion

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 7 (depends on Prompt 85 for case registry)

### Prompt

```
Build a document ingestion system for the OGC Trial Tool that handles
depositions, trial transcripts, exhibits, pleadings, and other litigation
documents. The critical capability: preserve page and line number structure
from transcripts so the AI can produce accurate page:line citations.

Transcripts are uploaded as PDFs — either machine-generated (text-selectable)
or clean scans (OCR required). Standard court reporter format: 25 lines per
page, line numbers 1-25 on the left margin.

PREREQUISITE: Prompt 85 (case registry) must be complete.

1. Document categories:

   Define document types in trial_tool_webapp/models/document_types.py:
   - DEPOSITION_TRANSCRIPT: deposition testimony
   - TRIAL_TRANSCRIPT: trial testimony
   - HEARING_TRANSCRIPT: hearing testimony (admin proceedings)
   - EXHIBIT: trial exhibit (photos, documents, contracts, emails)
   - PLEADING: complaint, answer, motion, brief, order
   - CORRESPONDENCE: letters between counsel
   - DISCOVERY: interrogatories, requests for production, responses
   - EXPERT_REPORT: expert witness reports
   - DECLARATION: sworn declarations, affidavits
   - OTHER: uncategorized

2. Transcript parser:

   Create trial_tool_functionapp/TranscriptParser/__init__.py:
   Azure Function, blob trigger on case document uploads.

   For TRANSCRIPT types (deposition, trial, hearing):

   a. Text extraction:
      - Machine-generated PDF: extract text directly with pypdf,
        preserving page boundaries
      - Scanned PDF: use Azure Document Intelligence (Layout model)
        for OCR with spatial analysis
      - Detect which type automatically (check if text layer exists)

   b. Page:line structure preservation:
      THE MOST CRITICAL FUNCTION.

      parse_transcript_lines(pdf_bytes) -> TranscriptDocument:

      TranscriptDocument:
        witness_name: str (extracted from header/caption)
        date: str (deposition/hearing date)
        pages: list[TranscriptPage]

      TranscriptPage:
        page_number: int
        lines: list[TranscriptLine]

      TranscriptLine:
        line_number: int (1-25 typically)
        text: str
        speaker: Optional[str] (Q/A/THE WITNESS/THE COURT/etc.)

      Parsing strategy:
      i.   Split PDF by page boundaries
      ii.  For each page, detect line number column on left margin:
           - Regex: look for sequential integers 1-25 at start of lines
           - Spatial: use Document Intelligence word positions to identify
             the line number column (leftmost numeric column)
      iii. Associate each line of text with its line number
      iv.  Detect Q/A speaker changes:
           - "Q." or "Q " at start = attorney question
           - "A." or "A " at start = witness answer
           - "THE COURT:" = judge
           - "MR./MS. [NAME]:" = identified speaker
      v.   Handle continuation lines (text that wraps without new line number)
      vi.  Handle page headers/footers (reporter certification, page numbers)
           — exclude from line content but preserve page number

   c. Store structured transcript:
      - Full structured JSON → blob storage (case-documents container)
      - Searchable text → Azure AI Search index (per-case, with page:line metadata)
      - Each indexed chunk includes: case_id, document_id, page_number,
        start_line, end_line, speaker, text

   d. Chunking strategy for RAG:
      - Chunk by Q&A exchange (question + answer = one chunk), not by
        fixed character count
      - Each chunk tagged with: page_number, start_line, end_line
      - This enables precise page:line citations in AI responses

3. Non-transcript document handling:

   For EXHIBIT, PLEADING, DISCOVERY, etc.:
   - Extract text with Document Intelligence or pypdf
   - If document has page numbers: preserve page references
   - If document has paragraph numbers (common in pleadings): preserve
   - Chunk by paragraph or section (not fixed character count)
   - Index with: case_id, document_id, page_number, document_type

4. Case document management API:

   In trial_tool_webapp/routes/case_documents.py:
   - POST /cases/<case_id>/documents — upload document(s)
     Accepts: single file, multiple files, or ZIP
     Requires: document_type parameter
     Auto-detects transcript format if type is *_TRANSCRIPT
   - GET /cases/<case_id>/documents — list documents for case
   - GET /cases/<case_id>/documents/<doc_id> — document detail + metadata
   - DELETE /cases/<case_id>/documents/<doc_id> — soft delete (lifecycle)
   - GET /cases/<case_id>/documents/<doc_id>/transcript — structured
     transcript JSON (for transcript types only)
   - Auth: case-level RBAC (only assigned attorneys/paralegals)

5. Blob storage layout:
   Container: ogc-case-documents
   Path: {case_id}/{document_type}/{document_id}/{original_filename}
   Structured data: {case_id}/{document_type}/{document_id}/parsed.json
   Quarantine: ogc-quarantine (for malware-flagged files)

6. Malware scanning:
   Same pattern as ADR/Triage: Microsoft Defender scan on blob upload,
   Event Grid trigger to MalwareScanner function, quarantine on detection.

7. Document audit trail:
   Every upload, download, and deletion logged to aigenerationaudit
   with: case_id, document_id, action, user_hash, timestamp, HMAC signature.

8. Configuration:
   - OGC_CASE_DOCUMENTS_CONTAINER: "ogc-case-documents"
   - OGC_QUARANTINE_CONTAINER: "ogc-quarantine"
   - TRANSCRIPT_PARSER_ENABLED: true
   - TRANSCRIPT_OCR_FALLBACK: true (use Document Intelligence if no text layer)
   - MAX_DOCUMENT_SIZE_MB: 100 (transcripts can be large)

Write a CHANGES.md and unified diff.
```

---

## Prompt 87: OGC Trial Tool — Case-Scoped AI Assistant with Bluebook Citations

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 7 (depends on Prompts 85 + 86 for case registry + documents)

### Prompt

```
Build a case-scoped AI Assistant for the OGC Trial Tool. Unlike UDIP's
cross-system analytics assistant, this one operates WITHIN a single case
and NEVER mixes data between cases. It answers questions about case
documents, generates citations in Bluebook format, and helps attorneys
prepare briefs, motions, and trial materials.

The assistant combines two knowledge sources:
1. CASE DOCUMENTS (per-case): depositions, transcripts, exhibits, pleadings
   uploaded via Prompt 86 — scoped to the current case only
2. LAW LIBRARY (shared): statutes, CFR, case law, compliance manual —
   same as Triage's priority-docs index but accessible to OGC

Data isolation is absolute: an attorney working on Case A cannot retrieve
documents from Case B through the AI, even accidentally. The RAG query
filters by case_id before any retrieval.

PREREQUISITE: Prompts 85 (case registry) and 86 (document ingestion).

1. Case-scoped conversation store:

   Create trial_tool_webapp/conversation_store.py:
   Copy the pattern from UDIP's conversation_store.py but with case_id
   as the mandatory scoping field.

   - Every conversation belongs to exactly one case
   - Conversations stored in Azure Table Storage:
     PartitionKey: case_id
     RowKey: conversation_id
   - Fields: case_id, conversation_id, user_hash, messages (JSON),
     created_at, updated_at, lifecycle_state, retention_expires_at,
     charge_number (optional, if OFP-linked)
   - HMAC-SHA256 on every audit record
   - WORM archival on case closure (same as UDIP)
   - Litigation hold support (same as UDIP)

   Retention:
   - Active case: conversations retained indefinitely
   - Closed case: retention_expires_at = closed_at + 7 years
   - Held case: frozen, no expiration

2. Dual-corpus RAG:

   Create trial_tool_webapp/case_rag.py:

   a. Case document retrieval (per-case):
      Query Azure AI Search with MANDATORY filter: case_id eq '{case_id}'
      Returns: transcript excerpts with page:line metadata, exhibit text,
      pleading sections
      This index is populated by Prompt 86's TranscriptParser

   b. Law library retrieval (shared):
      Query the shared priority-docs-index (same as Triage)
      Filter: category ne 'ADR Guidance' and category ne 'ADR Mediation Material'
      Returns: statutes, CFR, case law, compliance manual

   c. Combined context assembly:
      Merge case documents + law library results
      Label each source clearly:
      "--- CASE DOCUMENT: Smith Depo., p. 47, ll. 12-15 ---"
      "--- LAW LIBRARY: Title VII, 42 U.S.C. § 2000e-2(a)(1) ---"
      The LLM sees both but knows which is which

3. Bluebook citation engine:

   Create trial_tool_webapp/citation_formatter.py:

   The AI must produce citations that attorneys can paste directly into
   briefs. Encode these Bluebook formatting rules:

   a. Deposition citations:
      {Witness Last Name} Dep. {page}:{line}-{line}
      Example: "Smith Dep. 47:12-15"
      If spanning pages: "Smith Dep. 47:22-48:3"

   b. Trial transcript citations:
      Trial Tr. {page}:{line}-{line} ({Witness Last Name})
      Example: "Trial Tr. 142:8-14 (Jones)"

   c. Case law citations:
      {Case Name}, {Volume} {Reporter} {Page}, {Pinpoint} ({Court} {Year})
      Example: "McDonnell Douglas Corp. v. Green, 411 U.S. 792, 802 (1973)"

   d. Statute citations:
      {Title} U.S.C. § {Section} ({Year})
      Example: "42 U.S.C. § 2000e-2(a)(1) (2018)"

   e. Regulation citations:
      {Title} C.F.R. § {Section} ({Year})
      Example: "29 C.F.R. § 1614.105(a)(1) (2024)"

   f. Exhibit citations:
      {Party} Ex. {Number} at {Page}
      Example: "Pl. Ex. 12 at 3"

   The system prompt instructs the LLM to use these formats. The
   citation_formatter.py post-processes AI output to validate and
   normalize citation format — flagging citations that don't match
   any known pattern.

4. AI Assistant system prompt:

   "You are a litigation support assistant for EEOC attorneys preparing
   federal employment discrimination cases. You have access to two
   knowledge sources: (1) case documents for the current case only
   (depositions, transcripts, exhibits, pleadings), and (2) a law
   library of statutes, regulations, and case law.

   Rules:
   - NEVER reference documents from other cases
   - EVERY factual statement must cite a source document with page:line
     or exhibit number
   - Use Bluebook citation format for all legal authorities
   - Use deposition/transcript citation format: Witness Dep. page:line
   - When citing transcript testimony, quote the exact text
   - Do not provide legal conclusions — present facts and let the
     attorney draw conclusions
   - Stop sequences: 'Legal Conclusion:', 'Legal Advice:'
   - If asked about something not in the case documents or law library,
     say so explicitly — do not fabricate"

5. Chat UI:

   Create trial_tool_webapp/templates/case_chat.html:
   - Embedded within the case detail view (not a separate page)
   - Chat panel on right side of case view
   - Markdown rendering for AI responses (preserving citation formatting)
   - "Copy citation" button on each cited source
   - Document reference links: clicking a citation opens the source
     document at the referenced page
   - Conversation history in sidebar (per-case, per-user)
   - "New conversation" button (starts fresh within same case)
   - 508 compliant: keyboard navigable, screen reader labels, 4.5:1 contrast

6. API endpoints:

   In trial_tool_webapp/routes/case_chat.py:
   - POST /cases/<case_id>/chat — send message, get AI response
     Input: { message, conversation_id (optional) }
     Output: { response, citations: [...], conversation_id }
     Auth: case-level RBAC (must be assigned to case)
   - GET /cases/<case_id>/conversations — list conversations for case
   - GET /cases/<case_id>/conversations/<conv_id> — conversation history
   - DELETE /cases/<case_id>/conversations/<conv_id> — soft delete

7. Audit logging:
   Every AI interaction logged to aigenerationaudit:
   - task_type: "CASE_CHAT"
   - case_id, conversation_id, user_hash
   - Full prompt + response + citations + token count
   - HMAC-SHA256 signature
   - WORM blob archival for responses > 32KB
   - RetentionPolicy: "FOIA_7_YEAR"

8. Configuration:
   - OGC_AI_ASSISTANT_ENABLED: true (default)
   - OGC_AI_CHAT_TEMPERATURE: 0.15 (low for factual accuracy)
   - OGC_AI_CHAT_MAX_TOKENS: 4000
   - OGC_AI_CITATION_VALIDATION: true (post-process citations)
   - OGC_LAW_LIBRARY_INDEX: "priority-docs-index" (shared with Triage)
   - OGC_CASE_DOCS_INDEX: "ogc-case-docs-index" (per-case document index)

Write a CHANGES.md and unified diff.
```

---

## Prompt 88: OGC Trial Tool — Case Lifecycle, FOIA Export, and ARC Status Integration

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 7 (depends on Prompts 85-87)

### Prompt

```
Add case lifecycle management, FOIA export, and optional ARC status
integration to the OGC Trial Tool. Cases stay active until litigation
concludes, then enter 7-year NARA retention.

PREREQUISITE: Prompts 85 (case registry), 86 (documents), 87 (AI assistant).

1. Case lifecycle state machine:

   In trial_tool_webapp/models/case_registry.py:

   States: open → discovery → trial_prep → trial → post_trial → appeal →
           settled | closed
   Plus: any state can transition to "held" (litigation hold from UDIP)

   On case closure (settled or closed):
   a. Set closed_at = now()
   b. Set retention_expires_at = closed_at + 7 years (2555 days)
   c. Set lifecycle_state = "retained"
   d. Archive all AI conversations to WORM blob (same as UDIP pattern)
   e. Archive case documents metadata to WORM blob
   f. Documents themselves remain in blob storage until retention expires
   g. Log to audit trail: CASE_CLOSED event with HMAC signature

   On retention expiry:
   a. Queue for ScheduledDisposal (same pattern as Triage/ADR)
   b. Check litigation holds before disposal (fail-closed)
   c. Purge case documents, conversations, audit records from Table Storage
   d. WORM blobs are immutable — retained by Azure lifecycle policy

2. ARC status pull (for OFP-originated cases):

   Feature flag: ARC_STATUS_PULL_ENABLED (default: false)

   When enabled and case has a charge_number:
   - Timer function (hourly): query ARC Integration API for charge status
   - GET /arc/v1/charges/{charge_number}/metadata
   - Update case display with current ARC status (read-only display)
   - If ARC status = CLOSED and case still open: show warning banner
     "ARC charge is closed — verify litigation status"
   - Do NOT auto-close the OGC case based on ARC status (litigation
     may continue after charge closure)
   - Do NOT write back to ARC from OGC (OGC manages its own lifecycle)

3. FOIA export:

   Extend trial_tool_webapp/routes/foia_export.py:
   - Add case-scoped export: POST /api/v1/foia-export with case_id
   - Packages:
     a. All AI audit records for the case
     b. All conversation threads (full text)
     c. Case metadata (registry entry)
     d. Document list with metadata (not the documents themselves —
        those are exported separately by OGC records management)
     e. Chain-of-custody metadata (export_id, requester_hash, zip_hash)
   - Auth: admin or legal_counsel role
   - Rate limit: 5 per hour per user

4. Litigation hold integration:

   Same pattern as ADR/Triage:
   - Before any disposal: check UDIP hold API
     GET {UDIP_API_URL}/api/holds/check/{charge_number_or_case_id}
   - Fail-closed: if UDIP unreachable, block disposal
   - When hold is issued on a linked charge: freeze case and all
     conversations (set lifecycle_state="held")
   - Feature flag: LITIGATION_HOLD_CHECK_ENABLED (default: true)

5. Case closure UI:

   In trial_tool_webapp/routes/cases.py:
   - "Close Case" button with confirmation dialog
   - Closure reason selection: settled, judgment, appeal_exhausted,
     dismissed, voluntary_dismissal, other
   - Closure summary text (attorney writes brief summary)
   - On submit: triggers lifecycle closure flow (step 1 above)
   - Shows progress: "Archiving conversations... Archiving documents...
     Setting retention... Done."

6. Disposal queue:

   Create trial_tool_functionapp/ScheduledDisposal/__init__.py:
   (If it doesn't already exist from Prompt 41 — extend it)
   - Timer trigger: daily at 03:00 UTC
   - Query cases where retention_expires_at < now() and lifecycle_state = "retained"
   - For each: check litigation hold, then queue for disposal
   - Distributed lock to prevent concurrent runs

7. Configuration:
   - ARC_STATUS_PULL_ENABLED: false (default)
   - ARC_STATUS_PULL_INTERVAL_MINUTES: 60
   - LITIGATION_HOLD_CHECK_ENABLED: true (default)
   - OGC_DEFAULT_RETENTION_YEARS: 7
   - OGC_DISPOSAL_SCHEDULE: "0 0 3 * * *"

Write a CHANGES.md and unified diff.
```

---

## Prompt 89: OGC Trial Tool — Secure Word Add-in Architecture (Planning + Foundation)

**Repository:** `eeoc-ogc-trialtool/`
**Owner:** OGC team
**Phase:** 8 (FUTURE — build after Prompts 85-88 are stable)

### Prompt

```
ARCHITECTURE + FOUNDATION ONLY. Build the API layer and documentation
for a Microsoft Word Office Add-in that connects to the OGC Trial Tool's
case-scoped AI Assistant. The Add-in itself (JavaScript/HTML taskpane)
can be built in a later phase — this prompt creates the secure backend
endpoints and deployment documentation.

WHY NOT COPILOT: Microsoft 365 Copilot routes queries through Microsoft's
orchestration layer. Even with a custom plugin pointing to our Azure OpenAI,
the Copilot orchestrator sees the content in transit. For active litigation
material (depositions, case strategy, witness prep), this is unacceptable.

APPROACH: A Word Office Add-in is a web panel hosted on OUR infrastructure
that runs inside Word. The Add-in calls our API directly. Microsoft Word
is the container, but Microsoft's cloud services are NOT in the data path.
All AI processing stays within our Azure Government tenant and our Azure
OpenAI deployment.

DATA FLOW:
  Attorney opens Word → Add-in taskpane loads from our server →
  Attorney selects text → Add-in POSTs to our API with case_id + text →
  Our API queries case documents via RAG → Our Azure OpenAI generates
  response → Response returned to Add-in → Displayed in Word taskpane

Microsoft Word sees the Add-in's HTML/JS but NEVER sees the API calls,
case data, or AI responses. The Add-in uses fetch() directly to our
endpoint with Entra ID authentication.

1. Word Add-in API endpoints:

   Create trial_tool_webapp/routes/word_addin_api.py:

   POST /api/v1/addin/analyze
   Auth: Entra ID bearer token (SSO from Word → Entra ID → our API)
   Input: {
     case_id: str,
     selected_text: str,
     action: "analyze" | "cite" | "summarize" | "find_testimony" |
             "draft_argument" | "check_facts",
     context: Optional[str] (surrounding text for better context)
   }
   Output: {
     response: str (markdown formatted),
     citations: [{ source, page, line_start, line_end, text }],
     action: str,
     model: str,
     tokens_used: int
   }

   POST /api/v1/addin/search
   Auth: Entra ID bearer token
   Input: {
     case_id: str,
     query: str,
     document_types: Optional[list] (filter by deposition, exhibit, etc.),
     witness: Optional[str] (filter by deponent name)
   }
   Output: {
     results: [{
       document_name: str,
       document_type: str,
       page: int,
       line_start: int,
       line_end: int,
       text: str,
       relevance_score: float,
       citation: str (pre-formatted Bluebook)
     }]
   }

   POST /api/v1/addin/format-citation
   Auth: Entra ID bearer token
   Input: {
     citation_type: "deposition" | "trial_transcript" | "case_law" |
                    "statute" | "regulation" | "exhibit",
     raw_data: { witness_name, page, line_start, line_end, ... }
   }
   Output: {
     formatted: str (Bluebook format, paste-ready),
     short_form: str (id. / supra form for subsequent references)
   }

   GET /api/v1/addin/cases
   Auth: Entra ID bearer token
   Output: list of cases the authenticated user is assigned to
   (used by Add-in to populate case selector dropdown)

2. SSO authentication flow:

   The Word Add-in uses Office.js SSO to get an Entra ID token:
   - Add-in calls Office.auth.getAccessToken()
   - Word brokers SSO with Entra ID (user already signed in)
   - Token sent to our API in Authorization header
   - Our API validates token against same Entra ID tenant
   - No additional login required — seamless for the attorney

   Document the Entra ID app registration requirements:
   - Register a new app: "EEOC OGC Word Add-in"
   - API permissions: access_as_user (delegated)
   - Expose an API: api://{client_id} with scope access_as_user
   - Authorized client IDs: add Office desktop client IDs
     (Office client IDs are well-known Microsoft GUIDs)
   - Token validation: verify aud, iss, tid claims

3. Add-in manifest (XML):

   Create trial_tool_webapp/word_addin/manifest.xml:
   - Define the Add-in metadata (name, description, icon)
   - Taskpane URL: https://{OGC_TRIALTOOL_URL}/addin/taskpane
   - SSO resource URI: api://{OGC_TRIALTOOL_URL}/{ADDIN_CLIENT_ID}
   - Required permissions: ReadWriteDocument (read selected text,
     insert formatted citations)
   - Ribbon buttons:
     a. "EEOC AI" tab in ribbon
     b. "Analyze Selection" button
     c. "Search Case" button
     d. "Insert Citation" button

4. Taskpane route (serves the Add-in UI):

   In trial_tool_webapp/routes/word_addin_api.py:
   - GET /addin/taskpane — serves the Add-in HTML page
   - The page loads Office.js and our custom JavaScript
   - For this prompt: create a minimal placeholder page that:
     a. Initializes Office.js
     b. Gets SSO token
     c. Lists user's cases (from /api/v1/addin/cases)
     d. Shows "Add-in connected" status
   - The full interactive UI is a future phase

5. Security documentation:

   Create trial_tool_webapp/docs/WORD_ADDIN_SECURITY.md:
   Document:
   - Data flow diagram showing Word → Add-in → Our API → Azure OpenAI
   - Explicit statement: Microsoft does NOT see case data, AI prompts,
     or AI responses. Only the Add-in HTML/JS is served from our URL.
   - Comparison with Copilot: why Copilot is not suitable for
     litigation material and how the Add-in avoids the same risks
   - Azure OpenAI data policy: prompts and completions are not used for
     training, not available to other customers or OpenAI
   - Entra ID SSO: no credentials stored in the Add-in
   - All API calls over HTTPS with managed identity validation
   - Audit logging: every Add-in interaction logged with HMAC signature
   - FOIA implications: Add-in interactions are case-scoped AI queries,
     subject to same 7-year retention as case chat

6. Deployment documentation:

   Create trial_tool_webapp/docs/WORD_ADDIN_DEPLOYMENT.md:
   Document:
   - Entra ID app registration steps (portal walk-through)
   - Microsoft 365 admin center: how to deploy the Add-in centrally
   - Testing: how to sideload for development
   - Configuration: environment variables for Add-in client ID, scope
   - Verification: how to confirm data stays within Azure Gov tenant

7. Configuration:
   - OGC_WORD_ADDIN_ENABLED: false (default — enable when ready)
   - OGC_ADDIN_CLIENT_ID: (Entra ID app registration client ID)
   - OGC_ADDIN_SCOPE: "api://{host}/{client_id}/access_as_user"

Write a CHANGES.md and unified diff.
```

---

## Prompt 90: Progressive Web App (PWA) Installation for ADR, Triage, Trial Tool, UDIP

**Repositories:** `eeoc-ofs-adr/`, `eeoc-ofs-triage/`, `eeoc-ogc-trialtool/`, `eeoc-data-analytics-and-dashboard/`
**Owner:** All teams
**Phase:** 7 (run per repo, all 4 in parallel)

### Prompt

```
Add Progressive Web App (PWA) support so EEOC staff can install the
application to their desktop and taskbar as a standalone app window.
No offline support — these apps require live Azure connections. This is
purely a "looks and launches like a desktop app" install.

When staff visit the app in Edge or Chrome, the browser shows an install
prompt. After installing, the app opens in its own window (no browser
chrome — no address bar, no tabs), with the app icon on the taskbar and
desktop. It behaves like a native app but is still the web application.

Implement ALL of the following in this repository.

1. Generate app icon:

   Create a Python script that generates simple, clean PWA icons with
   the app abbreviation text on a solid background. Run the script
   during build to produce the required icon sizes.

   Create scripts/generate_pwa_icons.py:
   ```python
   """Generate PWA icons with app abbreviation text."""
   from PIL import Image, ImageDraw, ImageFont
   import os

   # Configure per app:
   #   ADR repo:     APP_NAME="ADR",    BG_COLOR="#1a5276", TEXT_COLOR="#ffffff"
   #   Triage repo:  APP_NAME="Triage", BG_COLOR="#1a5276", TEXT_COLOR="#ffffff"
   #   Trial Tool:   APP_NAME="Trial",  BG_COLOR="#1a5276", TEXT_COLOR="#ffffff"
   #   UDIP repo:    APP_NAME="UDIP",   BG_COLOR="#1a5276", TEXT_COLOR="#ffffff"
   APP_NAME = "ADR"  # CHANGE PER REPO
   BG_COLOR = "#1a5276"  # EEOC navy
   TEXT_COLOR = "#ffffff"
   SIZES = [72, 96, 128, 144, 152, 192, 384, 512]

   output_dir = os.path.join(os.path.dirname(__file__), "..", 
       # ADR: "adr_webapp/static/icons"
       # Triage: "triage_webapp/static/icons"
       # Trial Tool: "trial_tool_webapp/static/icons"
       # UDIP: "ai-assistant/app/static/icons"
       "REPLACE_WITH_CORRECT_PATH/static/icons")
   os.makedirs(output_dir, exist_ok=True)

   for size in SIZES:
       img = Image.new("RGB", (size, size), BG_COLOR)
       draw = ImageDraw.Draw(img)
       # Use a clean font; fall back to default if not available
       font_size = size // 3 if len(APP_NAME) <= 4 else size // 4
       try:
           font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
       except OSError:
           font = ImageFont.load_default()
       bbox = draw.textbbox((0, 0), APP_NAME, font=font)
       tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
       x = (size - tw) // 2
       y = (size - th) // 2
       draw.text((x, y), APP_NAME, fill=TEXT_COLOR, font=font)
       img.save(os.path.join(output_dir, f"icon-{size}x{size}.png"))

   print(f"Generated {len(SIZES)} icons for {APP_NAME} in {output_dir}")
   ```

   Set APP_NAME and the output_dir path for this specific repo:
   - eeoc-ofs-adr: APP_NAME="ADR", path="adr_webapp/static/icons"
   - eeoc-ofs-triage: APP_NAME="Triage", path="triage_webapp/static/icons"
   - eeoc-ogc-trialtool: APP_NAME="Trial", path="trial_tool_webapp/static/icons"
   - eeoc-data-analytics-and-dashboard: APP_NAME="UDIP", path="ai-assistant/app/static/icons"

   Run the script: python3 scripts/generate_pwa_icons.py
   Commit the generated PNG files.

   Add Pillow to requirements-dev.txt (or equivalent) if not present.

2. Create manifest.json:

   Place in the app's static directory (same level as css/, js/):

   For ADR (adr_webapp/static/manifest.json):
   {
     "name": "EEOC ADR Mediation Portal",
     "short_name": "ADR",
     "description": "AI-powered mediation case management for EEOC",
     "start_url": "/",
     "display": "standalone",
     "background_color": "#1a5276",
     "theme_color": "#1a5276",
     "orientation": "any",
     "scope": "/",
     "icons": [
       { "src": "/static/icons/icon-72x72.png", "sizes": "72x72", "type": "image/png" },
       { "src": "/static/icons/icon-96x96.png", "sizes": "96x96", "type": "image/png" },
       { "src": "/static/icons/icon-128x128.png", "sizes": "128x128", "type": "image/png" },
       { "src": "/static/icons/icon-144x144.png", "sizes": "144x144", "type": "image/png" },
       { "src": "/static/icons/icon-152x152.png", "sizes": "152x152", "type": "image/png" },
       { "src": "/static/icons/icon-192x192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable" },
       { "src": "/static/icons/icon-384x384.png", "sizes": "384x384", "type": "image/png" },
       { "src": "/static/icons/icon-512x512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
     ]
   }

   For Triage: name="EEOC Triage", short_name="Triage"
   For Trial Tool: name="EEOC Trial Tool", short_name="Trial"
   For UDIP: name="EEOC Analytics & AI", short_name="UDIP"

3. Create service worker (minimal, no offline caching):

   Place in the app's static directory:
   static/sw.js:
   ```javascript
   // Minimal service worker required for PWA install prompt.
   // No offline caching — app requires live connection.
   self.addEventListener("install", function(event) {
     self.skipWaiting();
   });

   self.addEventListener("activate", function(event) {
     event.waitUntil(clients.claim());
   });

   self.addEventListener("fetch", function(event) {
     // Pass through all requests to the network.
     // No caching, no offline support.
     event.respondWith(fetch(event.request));
   });
   ```

4. Update the base HTML template:

   In the <head> of the base/layout template (layout.html, base.html,
   or equivalent), add:

   <!-- PWA manifest -->
   <link rel="manifest" href="{{ url_for('static', filename='manifest.json') }}">
   <meta name="theme-color" content="#1a5276">
   <meta name="apple-mobile-web-app-capable" content="yes">
   <meta name="apple-mobile-web-app-status-bar-style" content="default">
   <meta name="apple-mobile-web-app-title" content="SHORT_NAME_HERE">
   <link rel="apple-touch-icon" href="{{ url_for('static', filename='icons/icon-152x152.png') }}">

   At the bottom of <body> (before closing </body> tag), add the
   service worker registration:

   <script>
     if ("serviceWorker" in navigator) {
       navigator.serviceWorker.register("{{ url_for('static', filename='sw.js') }}")
         .catch(function(err) { console.log("SW registration failed:", err); });
     }
   </script>

5. Flask route for manifest (if needed):

   Some Flask setups require serving manifest.json from the root URL.
   If the browser doesn't pick up /static/manifest.json, add a route:

   @app.route("/manifest.json")
   def manifest():
       return send_from_directory(app.static_folder, "manifest.json",
           mimetype="application/manifest+json")

   Test: visit /manifest.json in the browser — it should return the JSON.

6. Verify install works:

   After implementation:
   a. Open the app in Edge or Chrome
   b. Look for the install icon in the address bar (or three-dot menu →
      "Install EEOC ADR Mediation Portal")
   c. Click install — app should open in a standalone window
   d. Check taskbar — app icon should appear
   e. Close and reopen from taskbar — should launch standalone
   f. Verify: no address bar, no browser tabs, just the app

7. 508 compliance note:
   PWA install is progressive enhancement — the app works identically
   in a regular browser tab. The install feature is optional for users.
   No accessibility impact. Ensure the service worker doesn't break
   keyboard navigation or screen readers (it won't with pass-through fetch).

8. CSP update (if applicable):
   If the app uses Content-Security-Policy headers, ensure the service
   worker is allowed:
   - worker-src 'self'
   Add this to the Talisman CSP configuration or equivalent.

Write a CHANGES.md and unified diff.
```

---

## Prompt 91: ADR Production Deployment — Zero-Assumption Documentation Completion

**Repository:** `eeoc-ofs-adr/`
**Owner:** OCIO Platform team
**Phase:** 9 (CRITICAL — before production rollout)

### Prompt

```
The deployment documentation audit found 8 critical gaps that would block
a zero-assumption operator from completing a production deployment. Fill
ALL of them. The existing docs are good for Azure resource provisioning
but incomplete for Entra ID setup, secret generation, DNS/TLS, initial
data, and post-deployment validation.

Do NOT rewrite existing docs. ADD the missing sections where they belong
or create new targeted guides. Reference existing docs where appropriate.

=== PART 1: Entra ID App Registration Guide (CRITICAL) ===

Create docs/Entra_ID_App_Registration_Guide.md:

This guide must cover creation of TWO app registrations from scratch.

1. ADR Web Application Registration:

   Step-by-step Azure Portal instructions:
   a. Go to portal.azure.com → Entra ID → App registrations → New registration
   b. Name: "EEOC-ADR-Mediation-Portal"
   c. Supported account types: "Accounts in this organizational directory only"
      (Single tenant — EEOC tenant only)
   d. Redirect URI:
      - Platform: Web
      - URI: https://{ADR_DOMAIN}/signin-oidc
      - Add second: https://{ADR_DOMAIN}/signin-oidc-logingov (if Login.gov enabled)
   e. Click Register
   f. Record: Application (client) ID → this becomes AAD-CLIENT-ID
   g. Record: Directory (tenant) ID → this becomes TENANT_ID
   h. Go to Certificates & secrets → Client secrets → New client secret
      - Description: "ADR production secret"
      - Expiry: 24 months (set rotation reminder)
      - Copy the secret VALUE (not the ID) → this becomes AAD-CLIENT-SECRET
   i. Go to API permissions → Add a permission:
      - Microsoft Graph → Delegated permissions:
        - User.Read (Sign in and read user profile)
        - GroupMember.Read.All (Read group memberships)
      - Click "Grant admin consent for EEOC"
   j. Go to Token configuration → Add groups claim:
      - Select: Security groups
      - ID token: Group ID
      (This ensures group memberships appear in the ID token)

2. Graph Daemon Registration (for email/calendar background jobs):

   a. New registration → Name: "EEOC-ADR-Graph-Daemon"
   b. Supported account types: Single tenant
   c. No redirect URI needed (daemon/background app)
   d. Click Register
   e. Record: Application (client) ID → GRAPH-CLIENT-ID
   f. Go to Certificates & secrets → New client secret
      - Copy VALUE → GRAPH-CLIENT-SECRET
   g. Go to API permissions → Add a permission:
      - Microsoft Graph → Application permissions (NOT delegated):
        - Mail.Send
        - Calendars.ReadWrite
        - User.Read.All
        - GroupMember.Read.All
      - Click "Grant admin consent for EEOC"
   h. Go to Overview → copy Application (client) ID

3. Application Access Policy (restricts daemon to mediator mailboxes):

   This requires Exchange Online PowerShell. Document step-by-step:

   a. Prerequisites:
      - Install Exchange Online PowerShell module:
        Install-Module ExchangeOnlineManagement -Scope CurrentUser
      - You need Exchange administrator role in Entra ID
   b. Connect:
      Connect-ExchangeOnline -Organization eeoc.onmicrosoft.com
   c. Create the policy:
      New-ApplicationAccessPolicy `
        -AppId "{GRAPH-CLIENT-ID}" `
        -PolicyScopeGroupId "{MEDIATOR-SECURITY-GROUP-EMAIL}" `
        -AccessRight RestrictAccess `
        -Description "Restrict ADR Graph daemon to mediator mailboxes"
   d. Verify:
      Test-ApplicationAccessPolicy `
        -AppId "{GRAPH-CLIENT-ID}" `
        -Identity "mediator@eeoc.gov"
      Expected: AccessCheckResult = Granted
      Test-ApplicationAccessPolicy `
        -AppId "{GRAPH-CLIENT-ID}" `
        -Identity "non-mediator@eeoc.gov"
      Expected: AccessCheckResult = Denied
   e. Note: Policy propagation takes 30-60 minutes

4. Security Groups:

   Create these Entra ID security groups (if not existing):
   a. EEOC-ADR-Mediators — members get mediator role
      Record Object ID → MEDIATOR-GROUP-ID (Key Vault)
   b. EEOC-ADR-Admins — members get admin role
      Record Object ID → ADMIN-GROUP-ID (Key Vault)
   c. EEOC-ADR-Stats-Viewers — members get stats API access
      Record Object ID → STATS-ADMIN-GROUP-ID (Key Vault)
   d. EEOC-OFS-Staff (for bulk sync) — all OFS staff members
   e. EEOC-OFP-Staff (for bulk sync) — all OFP staff members

   For each: Entra ID → Groups → New group → Security → name → create
   Add members: Groups → select group → Members → Add members

=== PART 2: Login.gov Production Registration ===

Add to docs/Entra_ID_App_Registration_Guide.md (or create separate
docs/Login_Gov_Production_Setup.md):

1. Generate production RSA key pair:
   openssl genrsa -out logingov-private.pem 4096
   openssl rsa -in logingov-private.pem -pubout -out logingov-public.pem
   openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt \
     -in logingov-private.pem -out logingov-private-pkcs8.pem

2. Register at Login.gov Partner Dashboard:
   a. Go to https://dashboard.login.gov (production)
   b. Create a new app:
      - App name: "EEOC ADR Mediation Portal"
      - Issuer: urn:gov:gsa:openidconnect.profiles:sp:sso:eeoc:adr
      - Redirect URIs: https://{ADR_DOMAIN}/signin-oidc-logingov
      - Authentication method: private_key_jwt
      - Level of service: IAL1
      - Upload public key: paste contents of logingov-public.pem
   c. Record the Issuer URI → LOGINGOV_CLIENT_ID
   d. Store private key in Key Vault:
      az keyvault secret set --vault-name {KV_NAME} \
        --name LOGINGOV-PRIVATE-KEY \
        --file logingov-private-pkcs8.pem
   e. Delete the local private key file:
      shred -u logingov-private.pem logingov-private-pkcs8.pem

3. Environment variables to set:
   LOGINGOV_ENABLED=true
   LOGINGOV_CLIENT_ID=urn:gov:gsa:openidconnect.profiles:sp:sso:eeoc:adr
   LOGINGOV_AUTHORITY=https://secure.login.gov
   LOGINGOV_REDIRECT_URI=https://{ADR_DOMAIN}/signin-oidc-logingov

=== PART 3: Key Vault Secret Generation Commands ===

Add to docs/Azure_Portal_Provisioning_Guide.md Section 5.2 (or create
docs/Key_Vault_Secret_Generation.md):

For EVERY secret, provide the exact generation command:

| Secret Name | Generation Command | Format | Notes |
|---|---|---|---|
| FLASK-SECRET-KEY | openssl rand -base64 48 | Base64 string (64 chars) | Changing invalidates all sessions |
| AAD-CLIENT-ID | From Entra ID app registration | UUID | See Part 1 above |
| AAD-CLIENT-SECRET | From Entra ID app registration | String (40+ chars) | Rotate every 24 months |
| STATS-HASH-SALT | openssl rand -hex 32 | 64 hex characters | Used by StructuredLogger |
| Stats-API-Key | openssl rand -base64 32 | Base64 string | Stats API authentication |
| AI-AUDIT-HMAC-KEY | openssl rand -hex 32 | 64 hex characters | HMAC-SHA256 on audit records |
| GRAPH-CLIENT-ID | From Graph Daemon app registration | UUID | See Part 1 above |
| GRAPH-CLIENT-SECRET | From Graph Daemon app registration | String (40+ chars) | Rotate every 24 months |
| GRAPH-TENANT-ID | From Entra ID tenant | UUID | Same as TENANT_ID |
| REDIS-HOST | From Azure Redis creation | Hostname | {name}.redis.cache.windows.net |
| REDIS-PASSWORD | From Azure Redis access keys | String | Primary access key |
| FUNCTION-APP-URL | From Azure Function App creation | HTTPS URL | https://{funcapp}.azurewebsites.net |
| ExportFunctionKey | From Function App → App keys → default | String | Function-level auth key |
| FinalizeDisposalFunctionKey | Same as above | String | Function-level auth key |
| MEDIATOR-GROUP-ID | From Entra ID security group | UUID | Object ID of mediator group |
| ADMIN-GROUP-ID | From Entra ID security group | UUID | Object ID of admin group |
| STATS-ADMIN-GROUP-ID | From Entra ID security group | UUID | Object ID of stats group |
| LOGINGOV-PRIVATE-KEY | openssl genrsa + pkcs8 conversion | PEM private key | See Part 2 |

az keyvault secret set example:
  az keyvault secret set \
    --vault-name kv-eeoc-adr-prod \
    --name FLASK-SECRET-KEY \
    --value "$(openssl rand -base64 48)"

=== PART 4: DNS and TLS Certificate Setup ===

Create docs/DNS_and_TLS_Setup.md:

1. Obtain TLS certificate:
   - Request from EEOC's certificate authority (or Let's Encrypt for dev)
   - Certificate must cover: adr.eeoc.gov (or your production domain)
   - Export as PFX format with private key:
     openssl pkcs12 -export \
       -in cert.pem -inkey key.pem -certfile chain.pem \
       -out adr-cert.pfx -passout pass:{PFX_PASSWORD}

2. Upload to Key Vault:
   az keyvault certificate import \
     --vault-name kv-eeoc-adr-prod \
     --name adr-tls-cert \
     --file adr-cert.pfx \
     --password {PFX_PASSWORD}

3. Create DNS record:
   After Application Gateway is created:
   a. Get the Application Gateway's public IP:
      az network public-ip show \
        --resource-group rg-eeoc-adr-prod \
        --name pip-eeoc-adr-appgw \
        --query ipAddress -o tsv
   b. Create DNS record with your DNS provider:
      Type: A record
      Name: adr (or adr.eeoc.gov)
      Value: {PUBLIC_IP from above}
      TTL: 300

4. Certificate renewal:
   - Set calendar reminder for 30 days before expiry
   - Generate new PFX, import to Key Vault (same name)
   - Application Gateway auto-detects new certificate version
     (if using unversioned secret ID — verify in listener config)
   - No downtime required for renewal

=== PART 5: Environment Variable Dependency Table ===

Create docs/Environment_Variable_Dependencies.md:

Document every conditional dependency:

| If This Is Set | Then These Are REQUIRED | What Breaks Without Them |
|---|---|---|
| LOGINGOV_ENABLED=true | LOGINGOV_CLIENT_ID, LOGINGOV_REDIRECT_URI, LOGINGOV-PRIVATE-KEY (KV) | Login.gov auth fails, external parties cannot log in |
| ESIGNATURE-ENABLED=true (KV) | ESIGNATURE-PROVIDER, DOCUSIGN-API-KEY or ADOBE-SIGN-API-KEY (KV) | E-signature feature crashes |
| PG_MIGRATION_MODE != "off" | PG_CONNECTION_STRING | App crashes on any database write |
| MCP_ENABLED=true | MCP_CALLBACK_URL, MCP_WEBHOOK_SECRET | MCP event dispatch fails silently |
| UDIP_PUSH_ENABLED=true | UDIP_INGEST_URL, UDIP_API_SCOPE | Analytics push crashes |
| ARC_SYNC_ENABLED=true | ARC_INTEGRATION_API_URL or ARC_API_BASE_URL | ARC sync logs warning, skips |
| TEAMS_ENABLED=true (KV) | GRAPH-CLIENT-ID, GRAPH-CLIENT-SECRET (KV) | Calendar/scheduling features fail |
| TABLE_PARTITION_BY_OFFICE=true | Office structure must be configured | Queries may return empty results |

Also document: which variables have safe defaults (most integration flags
default to false/disabled), which have NO default and MUST be set
(KEY_VAULT_URI, AZURE_STORAGE_ACCOUNT_NAME), and validation rules
(TENANT_ID must be UUID format, GRAPH_RATE_LIMIT_PER_SEC must be 1-100).

=== PART 6: Post-Deployment Health Check Script ===

Create scripts/post_deploy_health_check.sh:

#!/usr/bin/env bash
# Verify all ADR components are connected and healthy after deployment.
set -euo pipefail

WEBAPP_URL="${1:?Usage: $0 <webapp-url> [funcapp-url]}"
FUNCAPP_URL="${2:-}"
PASS=0
FAIL=0

check() {
    local name="$1" url="$2" expected="$3"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
    if [ "$status" = "$expected" ]; then
        echo "  PASS: $name ($status)"
        ((PASS++))
    else
        echo "  FAIL: $name (got $status, expected $expected)"
        ((FAIL++))
    fi
}

echo "ADR Post-Deployment Health Check"
echo "================================"
echo ""
echo "Web App: $WEBAPP_URL"

# Basic health
check "Health endpoint" "$WEBAPP_URL/health" "200"
check "Integration health" "$WEBAPP_URL/healthz/integrations" "200"

# Auth (should redirect to login)
check "Login page loads" "$WEBAPP_URL/" "302"

# Static assets
check "CSS loads" "$WEBAPP_URL/static/css/app.css" "200"
check "Accessibility CSS" "$WEBAPP_URL/static/css/accessibility.css" "200"

# PWA manifest
check "PWA manifest" "$WEBAPP_URL/manifest.json" "200"

# API endpoints (should return 401 without auth)
check "Stats API (auth required)" "$WEBAPP_URL/api/stats/health" "200"
check "MCP endpoint (if enabled)" "$WEBAPP_URL/mcp" "404"

if [ -n "$FUNCAPP_URL" ]; then
    echo ""
    echo "Function App: $FUNCAPP_URL"
    check "Function health" "$FUNCAPP_URL/api/healthz" "200"
fi

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED" || echo "FAILURES DETECTED"
exit $FAIL

Also add to the script: a Key Vault connectivity test (curl the
webapp health endpoint and check if it reports Key Vault as "connected"
in the JSON response from /healthz/integrations).

=== PART 7: First-Run Setup Guide ===

Create docs/First_Run_Setup_Guide.md:

After deployment, before the first user logs in:

1. Create the first admin user:
   a. Ensure your @eeoc.gov account is in the EEOC-ADR-Admins
      security group in Entra ID
   b. Navigate to https://{ADR_DOMAIN}/
   c. Log in with your Entra ID credentials
   d. You should see the admin dashboard (if not, verify group membership)

2. Set up the office structure:
   a. Navigate to /admin/offices
   b. Create the root organization:
      - Name: "EEOC"
      - Type: organization
   c. Create sectors:
      - Name: "Office of Federal Operations" / Type: sector / Parent: EEOC
      - Name: "Office of Field Programs" / Type: sector / Parent: EEOC
   d. Create regions/districts under each sector as needed
   e. Set timezone for each office

3. Add the first mediator:
   a. Navigate to /admin/staff
   b. Click "Add Staff Member"
   c. Enter a mediator's @eeoc.gov email
   d. Select office, role=mediator, assign supervisor (yourself if needed)
   e. Click Submit
   f. Mediator can now log in and will see their empty case dashboard

4. Configure feature flags (optional):
   The app stores feature flags in the systemsettings Azure Table.
   Most features default to disabled. To enable:
   a. Open Azure Storage Explorer or Azure Portal → Storage Account →
      Tables → systemsettings
   b. Add entities:
      PartitionKey: "settings", RowKey: "LOGINGOV_ENABLED", Value: "true"
      PartitionKey: "settings", RowKey: "MCP_ENABLED", Value: "true"
      (Add each feature flag you want to enable)

5. Upload settlement template (optional):
   a. Upload ADR_Settlement_Boilerplate.docx to the settlement-drafts
      blob container
   b. This enables AI-assisted settlement agreement generation

6. Verify everything works:
   a. Run: bash scripts/post_deploy_health_check.sh https://{ADR_DOMAIN}
   b. Create a test case: navigate to case dashboard, create a new case
   c. Assign the test case to the mediator you created
   d. Log in as the mediator → verify they see the case
   e. Open the case → verify AI chat works (if Azure OpenAI configured)
   f. Delete the test case when satisfied

=== PART 8: Cross-Reference Updates ===

1. In docs/Azure_Portal_Provisioning_Guide.md:
   - At the beginning of Section 5.2 (Key Vault secrets), add:
     "For step-by-step generation of each secret, see
     docs/Key_Vault_Secret_Generation.md (Part 3 above)."
   - At the beginning of Section 5.3 (App settings), add:
     "For conditional dependencies between environment variables, see
     docs/Environment_Variable_Dependencies.md."

2. In docs/Azure_Portal_Provisioning_Guide.md Section 5.2:
   - Add: "Before configuring secrets, you must create two Entra ID
     app registrations. See docs/Entra_ID_App_Registration_Guide.md
     for complete step-by-step instructions."

3. In docs/Configuration_Management_Plan.md:
   - Add a "Dependencies" column to the env var table
   - Add a "Required/Optional" column with clear YES/NO

4. In provision_adr_system.sh:
   - After the script completes, add a section that prints:
     "Post-deployment steps:
      1. Run: bash scripts/post_deploy_health_check.sh {WEBAPP_URL}
      2. Follow: docs/First_Run_Setup_Guide.md
      3. Review: docs/Entra_ID_App_Registration_Guide.md (if not done)"

Write a CHANGES.md listing all new files created and existing files
modified.
```

---

## Prompt 92: ADR Audit Log Viewer, Per-Case Activity Timeline, and Security Audit Export

**Repository:** `eeoc-ofs-adr/`
**Owner:** ADR team
**Phase:** 9 (production readiness)

### Prompt

```
The admin audit log is currently a read-only feed of the latest 50
records with no search, no filtering, and no export. There is no way
to see all actions for a specific case, no way to search by user or
date range, and no way to export multiple cases for a security audit.

Build three features:
1. A searchable audit log viewer for system admins
2. A per-case activity timeline showing every action on a case
3. A bulk security audit export for compliance reviews

Read adr_webapp/routes/admin.py (audit log display), routes/foia_export.py
(FOIA export pattern), shared_code/ai_audit_logger.py (AI audit queries),
and templates/admin_dashboard.html (current audit feed) before writing.

=== PART 1: Searchable Audit Log Viewer ===

Create a dedicated audit log viewer page accessible to system admins.

1. Create route in adr_webapp/routes/admin.py:
   GET /admin/audit-logs
   Auth: admin role required

   Query parameters (all optional, combinable):
   - case_id: filter to a specific case
   - user: filter by user email or OID hash
   - action: filter by action type (case_access, status_change,
     document_upload, ai_generation, foia_export, staff_change, etc.)
   - date_from: ISO date (start of range)
   - date_to: ISO date (end of range)
   - source: which audit table to query (all, ai_audit, api_audit,
     office_audit) — default: all
   - page: pagination (50 records per page)

2. Query logic:
   - Queries across THREE audit tables:
     a. aigenerationaudit — AI interactions (filter by CaseID)
     b. apiauditlog — API actions (filter by Details containing case_id)
     c. officeauditlog — staff/office changes (filter by action type)
   - Merges results into a unified timeline sorted by timestamp
   - Each record shows: timestamp, action type, user (hashed), case ID
     (if applicable), source table, summary of action
   - Pagination via continuation tokens or offset

3. Create template admin_audit_logs.html:
   - Search/filter bar at top:
     - Case ID text input
     - User email/OID text input
     - Action type dropdown (populated from distinct PartitionKeys)
     - Date range picker (from/to)
     - Source selector (All / AI Audit / API Audit / Office Audit)
     - Search button + Clear filters button
   - Results table:
     - Timestamp | Action | User | Case ID | Source | Details
     - Details column: expandable row showing full JSON
     - Sortable by timestamp (default: newest first)
   - Pagination controls (Previous / Next / Page N of M)
   - Export button: "Export filtered results as CSV"
   - Export button: "Export filtered results as JSON"
   - 508 compliant: all interactive elements keyboard-navigable,
     table headers with scope, aria-labels on buttons

4. CSV/JSON export from the viewer:
   - Exports whatever the current filter returns (not just current page)
   - CSV: one row per audit record, flattened
   - JSON: array of full audit records
   - Rate limit: 5 exports per hour per user (same as FOIA)

=== PART 2: Per-Case Activity Timeline ===

Add a comprehensive activity timeline to the case detail view.

5. Create route in adr_webapp/routes/admin.py (or mediator.py):
   GET /cases/<case_id>/activity
   Auth: user must have access to the case (RBAC check)

   Queries ALL audit sources for the case and merges into a timeline:
   a. aigenerationaudit: all AI interactions (CaseID eq case_id)
   b. apiauditlog: all API actions mentioning this case
   c. chatlogs: all messages (PartitionKey eq case_id) — count + date range
   d. Case entity itself: created_at, status changes, assigned mediator,
      closure date, settlement info

   Returns unified timeline:
   [
     { timestamp, event_type, actor, summary, details, source },
     ...
   ]

   Event types include:
   - CASE_CREATED: case opened
   - CASE_STATUS_CHANGE: status updated (with from/to)
   - MEDIATOR_ASSIGNED: mediator assigned or changed
   - DOCUMENT_UPLOADED: document added to case
   - AI_GENERATION: AI analysis or draft generated (with task type)
   - AI_CHAT_MESSAGE: message in AI-assisted chat
   - MEETING_SCHEDULED: calendar event created
   - SETTLEMENT_DRAFTED: settlement agreement generated
   - CASE_CLOSED: case closed (with reason)
   - FOIA_EXPORT: case was included in a FOIA export
   - HOLD_ISSUED: litigation hold placed
   - HOLD_RELEASED: litigation hold released

6. Add activity tab to case detail view:
   In the case detail template, add a "Case Activity" tab (or section)
   that renders the timeline as:
   - Vertical timeline (most recent at top)
   - Each event: icon + timestamp + actor + summary
   - Expandable details on click
   - Color-coded by event type (508 compliant — use icons, not just color)
   - Filter checkboxes: show/hide event types
   - "Export case activity" button → downloads JSON or CSV of the timeline

=== PART 3: Security Audit Bulk Export ===

Add a bulk export for system admins conducting compliance reviews.

7. Create route in adr_webapp/routes/admin.py:
   POST /admin/security-audit-export
   Auth: admin role ONLY (not legal_counsel — this is system-level)

   Input:
   {
     "case_ids": ["case-1", "case-2", ...],  // optional, omit for all
     "date_from": "2025-01-01",              // optional
     "date_to": "2026-04-13",               // optional
     "include_ai_audit": true,               // default true
     "include_api_audit": true,              // default true
     "include_office_audit": true,           // default true
     "include_chat_logs": true,              // default true
     "format": "zip"                         // zip or json
   }

   Processing:
   a. If case_ids provided: export only those cases
   b. If case_ids omitted: export ALL cases in date range (dangerous —
      warn user, require confirmation checkbox)
   c. For each case:
      - Pull AI audit records
      - Pull API audit records
      - Pull chat message counts and date ranges
      - Pull case metadata (status, mediator, office)
   d. Package into ZIP:
      security-audit-export-{export_id}/
        manifest.json (export metadata, requester hash, date range,
          case count, record count per table, export timestamp)
        cases/
          {case_id_1}/
            ai_audit.json
            api_audit.json
            chat_summary.json (count + date range, not full messages)
            case_metadata.json
          {case_id_2}/
            ...
        global/
          office_audit.json (all office/staff changes in date range)
          system_summary.json (total records, date range, case count)
   e. Compute SHA-256 of ZIP for integrity
   f. Upload to foia-exports blob container
   g. Generate 24-hour SAS download URL
   h. Log to apiauditlog: SECURITY_AUDIT_EXPORT event with
      export_id, requester_hash, case_count, record_count, zip_hash

   Rate limit: 2 per hour (these are expensive queries)

8. Add UI for security audit export:
   Add a "Security Audit Export" card to /admin/tools (admin_tools.html):
   - Date range picker
   - Case ID list input (textarea, one per line, or "all cases" checkbox)
   - Checkboxes: include AI audit, API audit, office audit, chat logs
   - Warning text: "This export may take several minutes for large
     date ranges. The download link will be available for 24 hours."
   - Submit button → shows progress indicator → shows download link
   - Confirmation dialog if "all cases" selected: "This will export
     audit data for ALL cases. Are you sure?"

9. Audit the export itself:
   Every security audit export is logged with:
   - Who requested it (hashed OID)
   - What was included (case count, table flags, date range)
   - ZIP hash (SHA-256)
   - When it was created
   - This ensures that the export mechanism itself has an audit trail

=== PART 4: Wire Existing Audit Logs into Case Context ===

10. In the existing FOIA export (foia_export.py):
    - Add the per-case activity timeline to the FOIA export ZIP:
      Include activity_timeline.json alongside the existing files
    - This means FOIA responses now include a complete case timeline
      without additional work

11. In the admin dashboard (admin_dashboard.html):
    - Replace the static "50 latest audit logs" feed with a link to
      the new /admin/audit-logs viewer: "View full audit log →"
    - Keep a compact "5 latest" feed on the dashboard for quick glance
    - Add a link from each audit record to the case it references
      (if CaseID is present)

12. In the case detail view:
    - Add a badge showing audit record count for the case
    - Clicking the badge opens the audit log viewer pre-filtered to
      that case: /admin/audit-logs?case_id={case_id}

Write a CHANGES.md listing all new files and modifications.
```

---

## Prompt 93: Python 3.13 Upgrade (All Repos)

**Repositories:** All 7 EEOC repos (run per repo, all in parallel)
**Owner:** All teams
**Phase:** 9 (production readiness)

### Prompt

```
Upgrade this repository from Python 3.12 to Python 3.13. Python 3.13
extends EOL from October 2028 to October 2029. No application code
changes are needed — our codebase has zero deprecated 3.13 patterns.

The only dependency blocker is psycopg2-binary, which needs a version
bump for 3.13 wheel availability. All other dependencies already have
3.13 wheels on PyPI.

Implement ALL of the following.

=== PART 1: Dependency Version Bump ===

1. If this repo has psycopg2-binary in ANY requirements file:
   Change: psycopg2-binary==2.9.11 → psycopg2-binary==2.10.1
   
   Files to check:
   - requirements.txt (root level)
   - */requirements.txt (subdirectories like adr_webapp/, triage_webapp/,
     case-processor-function/, learning-processor-function/,
     trial_tool_webapp/, trial_tool_functionapp/, data-middleware/,
     ai-assistant/, staff_portal/)
   
   psycopg2-binary 2.10.1 is API-compatible with 2.9.x — same
   connection interface, same cursor behavior, same parameterized
   query syntax. No code changes required.
   
   If psycopg2-binary is not in this repo's requirements, skip this step.

2. Verify all other pinned dependencies have 3.13 wheels:
   Run: pip install --dry-run --python-version 3.13 -r requirements.txt
   (or equivalent check)
   
   If any dependency fails to resolve for 3.13, check PyPI for the
   latest version that supports 3.13 and bump to that version.
   
   Known-good versions for Python 3.13:
   - Flask>=3.0.0 (3.1.x preferred)
   - gunicorn>=22.0.0
   - gevent>=24.11.1 (has 3.13 wheels)
   - cryptography>=42.0.0 (46.x preferred)
   - lxml>=5.2.0 (5.4.x preferred)
   - SQLAlchemy>=2.0.30
   - openai>=1.14.0
   - PyJWT>=2.8.0
   - All azure-* SDKs (current versions support 3.13)
   - redis>=5.0.0
   - structlog>=24.0.0
   - Pillow>=10.4.0
   - pypdf>=4.0.0
   - pdfplumber>=0.11.0
   - hypothesis>=6.100.0

=== PART 2: Dockerfile Update ===

3. Find every Dockerfile in the repo. For each one:
   Change: FROM python:3.12-slim-bookworm
   To:     FROM python:3.13-slim-bookworm

   If the Dockerfile uses a different base image pattern (e.g.,
   python:3.12-bookworm without slim), match the same pattern:
   FROM python:3.13-bookworm

   If the Dockerfile uses a multi-stage build, update ALL stages
   that reference python:3.12.

   Do NOT change any other Dockerfile instructions (apt-get packages,
   COPY commands, CMD, etc.).

=== PART 3: CI/CD Workflow Update ===

4. Find every GitHub Actions workflow file in .github/workflows/.
   For each one that specifies python-version:

   Change: python-version: "3.12"
   To:     python-version: "3.13"

   If the workflow uses a matrix strategy with multiple Python versions,
   replace 3.12 with 3.13 (do not add 3.13 alongside 3.12 — we are
   migrating, not supporting both).

   Common files to check:
   - .github/workflows/build-and-test.yml
   - .github/workflows/security-audit-evidence.yml
   - .github/workflows/portal-build-and-test.yml (if exists)

=== PART 4: Configuration Files ===

5. If pyproject.toml exists with a python_requires or requires-python:
   Change: requires-python = ">=3.12"
   To:     requires-python = ">=3.13"

6. If setup.cfg or setup.py exists with python_requires:
   Same change.

7. If .python-version file exists:
   Change contents to: 3.13

8. Search the ENTIRE repo for any reference to Python 3.12 and update:

   Run: grep -rn "3\.12" --include="*.md" --include="*.sh" --include="*.yaml" --include="*.yml" --include="*.toml" --include="*.cfg" --include="*.txt" --include="*.json" .

   Specific files known to reference Python 3.12:

   a. docs/SUPPLY_CHAIN_RISK.md:
      - Update "Azure App Service (Python 3.12 runtime)" → 3.13
      - Update "Python 3.12 runtime" references → 3.13

   b. Provisioning scripts (provision_adr_system.sh or equivalent):
      - Update --runtime "PYTHON:3.12" → --runtime "PYTHON:3.13"
      - Update --runtime-version 3.12 → --runtime-version 3.13
      - Update any log messages mentioning "Python 3.12" → "Python 3.13"

   c. scripts/generate-sbom.sh (if exists):
      - Update "runtime": "Python 3.12" → "Python 3.13" in SBOM metadata
      - Update any comments referencing Python 3.12

   d. shared_code/pyproject.toml or any pyproject.toml:
      - Update requires-python = ">=3.12" → ">=3.13"

   e. Azure deployment guides in docs/:
      - docs/Azure_Portal_Provisioning_Guide.md
      - docs/Azure_Portal_Development_Provisioning_Guide.md
      - docs/Azure_Portal_Development_to_Production_Provisioning_Guide.md
      - docs/Azure_Portal_ZIP_Deployment_Guide.md
      - Any reference to "Runtime: Python 3.12" → "Runtime: Python 3.13"

   f. requirements.txt comment headers mentioning Python 3.12

   g. CLAUDE.md (workspace level — if it mentions Python 3.12)

   Do NOT update:
   - debug/ directory (historical logs, leave as-is)
   - Implementation_Prompts.md (historical prompts, leave as-is)
   - archive/ directory (superseded docs, leave as-is)
   - Section numbers like "3.12" in documentation (e.g., "Section 3.12
     FOIA Export Route" — this is a section number, not a Python version)

   For each file modified, verify the change makes sense in context.
   "3.12" in a section heading or a date is NOT a Python version reference.

=== PART 5: Runtime Version File and Azure Provisioning ===

9. For Azure App Service deployments: if a runtime.txt file exists:
   Change: python-3.12
   To:     python-3.13

   Azure App Service supports Python 3.13 as of early 2025.

10. For the workspace-level provisioning script
    (provision_eeoc_ai_platform.sh in the workspace root, if accessible):
    - Update --runtime-version 3.12 → --runtime-version 3.13
    - Update any log messages: "Python 3.12" → "Python 3.13"
    - This script provisions Azure Function Apps with the Python runtime
      and the version must match what the containers/app service runs

=== PART 6: Verify ===

11. Run the full test suite:
    python -m pytest tests/ -v --tb=short
    (adjust path based on repo structure)

    If tests fail due to the Python version change:
    - Check if the failure is a genuine incompatibility (fix it)
    - Check if the failure is a test environment issue (install missing deps)
    - Do NOT skip failing tests

12. Verify Python version in any health check or version endpoint:
    If the app reports its Python version (e.g., in /healthz or logs),
    confirm it now shows 3.13.

=== SUMMARY OF CHANGES PER REPO ===

| Repo | psycopg2 bump? | Dockerfile? | CI? | Other? |
|------|---------------|-------------|-----|--------|
| eeoc-ofs-adr | YES (multiple req files) | YES | YES | staff_portal Dockerfile too |
| eeoc-ofs-triage | YES | Check | YES | |
| eeoc-data-analytics-and-dashboard | YES (data-middleware) | YES | YES | |
| eeoc-arc-integration-api | NO (no psycopg2) | YES | YES | |
| eeoc-mcp-hub-functions | NO | YES | YES | |
| eeoc-ogc-trialtool | NO | Check | YES | |
| eeoc-ofs-adr-clean | SKIP (sync copy) | | | |

Do NOT modify application code, route logic, templates, or business
logic. This prompt changes ONLY: dependency versions, base images,
and CI configuration.

Write a CHANGES.md listing every file modified and the specific
version changes made.
```
