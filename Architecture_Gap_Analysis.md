# Architecture Completeness Review

**Date:** 2026-03-30
**Purpose:** Identify every gap in the integration architecture before finalizing the plan and prompts.

---

## 1. Does UDIP Actually Become the Central Database?

Yes, with caveats. UDIP has the foundation: watermark-based sync engine, PostgreSQL with RLS, dbt semantic layer, an existing ingest API, and a production Data Middleware layer with YAML-based column mapping, value translation, PII redaction, and schema validation. But three data flows are missing today:

### What flows INTO UDIP now
- Charges from IDR SQL Server via Data Middleware (watermark sync, sqlserver_charges.yaml)
- ADR outcomes from IDR SQL Server via Data Middleware (watermark sync, sqlserver_adr.yaml)
- Angular case management data from PostgreSQL via Data Middleware (watermark sync, angular_cases.yaml)

All three flows pass through the UDIP Data Middleware, which applies YAML-driven column translation (e.g., IDR's `BAS_CD` → `basis: Race`), value maps (inline + CSV lookups for district offices, issue codes, region codes), PII redaction (tier 2/3 SSN/email/phone stripping), and computed columns. This middleware is the critical translation layer regardless of data source.

### What needs to flow INTO UDIP and does not today

| Source | Data | Value | Mechanism Needed |
|--------|------|-------|-----------------|
| ARC (PrEPA PostgreSQL) | Full database replica — all tables including charges, allegations, staff, closures, mediation, reference data | Replaces IDR/SQL Server as primary source. UDIP becomes the full read replica. | WAL/CDC: PrEPA PostgreSQL → logical replication (FOR ALL TABLES) → Debezium → Azure Event Hub → UDIP replica schema (raw) → Data Middleware (YAML translation, PII redaction) → analytics schema (clean, AI-ready) |
| ADR | Daily metrics rollup (case counts by status, resolution rates, mediator utilization, avg case duration) | Agency-wide mediation performance | ADR pushes to UDIP ingest API on schedule |
| ADR | AI reliance scores (per-mediator acceptance rates, feature diversity, fairness metrics) | AI governance and bias detection | ADR pushes to UDIP ingest API |
| ADR | Model drift signals (token distribution drift, response time drift, success rate drift) | Early warning for AI degradation | ADR pushes to UDIP ingest API |
| ADR | Scheduling analytics (booking success rates, provider distribution, session durations) | Operational efficiency | ADR pushes to UDIP ingest API |
| Triage | Classification results (rank, merit score, subscores, citation count, word count) | Case prioritization analytics across agency | Triage pushes to UDIP ingest API |
| Triage | Daily metrics (processing volume, AI acceptance rate, error rate, confidence distribution, latency percentiles) | AI pipeline health monitoring | Triage pushes to UDIP ingest API |
| Triage | Correction flow matrices (A→B, B→C counts — model drift indicators) | Model governance | Triage pushes to UDIP ingest API |
| Triage | Reliance scores (system acceptance rate, correction time, feedback adoption) | AI reliability tracking | Triage pushes to UDIP ingest API |

### What flows OUT OF UDIP to apps

| Consumer | What They Query | How |
|----------|----------------|-----|
| MCP Hub / AI consumers | Analytics, narrative search, metrics, cross-system queries | MCP tools (query_{dataset}, search_narratives, get_metrics) |
| ADR | Case background for mediation context, agency-wide settlement trends | UDIP MCP tools or direct REST API |
| Triage | Historical classification patterns, agency-wide case distributions | UDIP MCP tools or direct REST API |
| OGC Trial Tool | Case history, investigation timeline, litigation context | UDIP MCP tools or direct REST API |
| Superset dashboards | All analytics data | Direct PostgreSQL connection (existing) |
| JupyterHub notebooks | All analytics data | Direct PostgreSQL connection (existing) |

---

## 2. Can All Apps Push AND Pull?

After this architecture is complete, here is every app's read and write capability:

### ADR Mediation Platform

| Direction | What | Path |
|-----------|------|------|
| **Pull from ARC** | Mediation-eligible cases (charge number, mediator, party emails, dates) | ARC Integration API → ADR ARCSyncImporter (every 15 min) |
| **Pull from UDIP** | Agency-wide analytics, case context, settlement trends | UDIP MCP tools or REST API |
| **Push to ARC** | Mediation closure (reason, settlement amount, benefits), action dates, signed agreements, staff assignments | ADR → ARC Integration API write-back endpoints |
| **Push to UDIP** | Daily metrics, AI reliance scores, model drift, scheduling analytics | ADR → UDIP ingest API (daily push from ADR Azure Functions) |

### OFS Triage

| Direction | What | Path |
|-----------|------|------|
| **Pull from ARC** | Charge metadata at upload time (respondent, basis/issue codes, office) | ARC Integration API → Triage (on-demand lookup) |
| **Pull from UDIP** | Historical classification patterns, case distributions | UDIP MCP tools or REST API |
| **Push to ARC** | Classification results (rank, score, summary), correction events | Triage → ARC Integration API write-back endpoints |
| **Push to UDIP** | Daily metrics, correction flows, reliance scores, model drift | Triage → UDIP ingest API (daily push from Triage Azure Functions) |

### UDIP Analytics

| Direction | What | Path |
|-----------|------|------|
| **Pull from ARC** | Full charge lifecycle data (charges, allegations, staff, closures, mediation) | ARC Integration API feed endpoints → UDIP sync engine |
| **Pull from ADR** | Operational analytics (metrics, reliance, drift) | ADR pushes to UDIP ingest API |
| **Pull from Triage** | Classification analytics (metrics, corrections, drift) | Triage pushes to UDIP ingest API |
| **Serve to all** | Governed, RLS-enforced analytics views | UDIP MCP tools + REST API + direct PostgreSQL |

### OGC Trial Tool

| Direction | What | Path |
|-----------|------|------|
| **Pull from ARC** | Litigation case details (court, hearings, attorneys) | ARC Integration API → OGC (on-demand lookup) |
| **Pull from UDIP** | Case history, investigation timeline | UDIP MCP tools or REST API |
| **Push to ARC** | Minimal (litigation milestones if needed) | ARC Integration API event logging |

---

## 3. Future-Proofing: What Does a New App Need to Do?

When a sixth application joins the ecosystem, it should:

1. **Register as an MCP spoke** with the hub (name, URL, capability categories, auth)
2. **Query UDIP** for any case data, analytics, or cross-system context it needs
3. **Call ARC Integration API write-back tools** through the hub if it needs to push data to ARC
4. **Push its own operational analytics to UDIP** via the ingest API if it generates data worth centralizing
5. **Follow the established security pattern** (Entra ID M2M auth, HMAC event signatures, NARA 7-year audit logging)

No custom integration code needed for any of these steps. The infrastructure handles discovery, routing, and authentication.

---

## 4. What Is Missing from the Current Prompts

### Missing Prompt: UDIP Middleware Event Hub Consumer Driver
UDIP's sync engine only supports SQL sources (pyodbc, psycopg2). To consume WAL/CDC events from Azure Event Hub (Debezium format — JSON envelope with before/after row images), it needs an Event Hub consumer driver that yields row dicts in the same format as SQL cursor results. The middleware's YAML mapping engine then handles column translation, value maps, PII redaction, and computed columns — same as it does for SQL sources. The driver must track consumer group offsets (only commit after successful upsert) and support both batch and continuous sync modes.

### Missing Prompt: PrEPA WAL/CDC YAML Mapping Configs
New prepa_*.yaml mapping files for the middleware that translate PrEPA's PostgreSQL schema into analytics schema fields. PrEPA uses normalized FK integers (shared_basis_id, shared_issue_id, shared_statute_id) where the IDR uses denormalized inline codes (BAS_CD = 'R'). The value maps need to resolve FK integers to human-readable names. Tables: prepa_charges.yaml (charge_inquiry), prepa_allegations.yaml (charge_allegation), prepa_staff_assignments.yaml (charge_assignment), prepa_charging_party.yaml (charging_party, PII tier 3 → redact to tier 2), prepa_respondent.yaml (respondent).

### Missing Prompt: Debezium / CDC Infrastructure
Logical replication slot on PrEPA's PostgreSQL (pg_create_logical_replication_slot), publication for core tables (charge_inquiry, charging_party, respondent, charge_allegation, charge_assignment), Debezium connector deployment (Kubernetes or Container Apps), Azure Event Hub namespace provisioning (Kafka-enabled, 7-day retention, consumer group for UDIP middleware). Fallback documentation if ARC team cannot grant WAL access: Service Bus subscription + REST API feed endpoints.

### Missing Prompt: UDIP Middleware Reconciliation Engine
Twice-weekly comparison of UDIP analytics tables against IDR (SQL Server nightly snapshot) to detect missing or stale records. Row count comparison, sample checksum validation (SHA-256 on 1000 random rows by primary key), auto-backfill of missing records using existing sqlserver_*.yaml mappings. Alert if discrepancy exceeds 0.1% of total rows. New PostgreSQL table: middleware.reconciliation_log. Kubernetes CronJob: Tuesday + Friday at 03:00 UTC. The IDR stays alive as a safety net while the CDC pipeline proves itself.

### Missing Prompt: UDIP New Tables for ADR and Triage Data
UDIP needs new PostgreSQL tables and dbt models for ADR operational analytics and Triage classification data that is pushed via the ingest API.

### Missing Prompt: ADR → UDIP Analytics Push
ADR needs an Azure Function that pushes daily metrics, reliance scores, and drift data to UDIP's ingest API.

### Missing Prompt: Triage → UDIP Analytics Push
Same pattern: Triage pushes classification metrics, correction flows, and reliance data to UDIP.

### Missing Prompt: OGC Trial Tool CI/CD Pipeline
OGC Trial Tool has security scanning scripts in example_data but no GitHub Actions workflow. The new service needs one.

### Missing Prompt: CI/CD for New Services
Both new repositories (ARC Integration API and MCP Hub) need GitHub Actions workflows matching the established pattern: Bandit, Semgrep, CycloneDX SBOM, pip-audit, OWASP Dependency-Check, ZAP baseline, license compliance.

---

## 4.5 The UDIP Data Middleware Is a First-Class Component

The UDIP Data Middleware is the central translation layer between any data source and UDIP's analytics schema. It is already in production and must be treated as a first-class architectural component, not an implementation detail.

**What it does:**
- **YAML-based declarative column mapping** — each source table has a .yaml config defining source→target column mappings, data types, and transforms. No code changes needed for new columns or sources.
- **Value maps** — inline dictionaries for small code tables (BAS_CD "R" → "Race") and CSV lookup files for large ones (42 district offices, issue codes, region codes)
- **PII redaction** — regex-based stripping of SSN, email, phone, ZIP on tier 2/3 fields. PII tier classification enforced by MappingValidator.
- **Computed columns** — DATEDIFF, NULL coalescing, conditional expressions
- **MappingValidator** — validates all mappings at startup: checks source connections, column definitions, lookup files, PII tier consistency, computed expressions. Blocks sync on validation failure.
- **Watermark-based incremental sync** — only pulls rows changed since last sync

**Current source drivers:** pyodbc (SQL Server / IDR), psycopg2 (PostgreSQL / Angular)

**What needs to be added:**
- Event Hub consumer driver for WAL/CDC events (Debezium format)
- New prepa_*.yaml configs for PrEPA's normalized PostgreSQL schema (FK integers instead of inline codes)
- Reconciliation engine for twice-weekly IDR verification
- Continuous sync mode (Kubernetes Deployment, always-on) in addition to existing batch mode (CronJob, daily)

**Regardless of data source — WAL/CDC, REST API, IDR, Service Bus — all data flows through the middleware YAML layer before landing in analytics tables.** This is non-negotiable. The middleware handles label translation, PII governance, and data quality.

---

---

## 4.6 Security Audit Findings (2026-04-02)

Multi-pass security audit across UDIP, ADR, and Triage codebases. Findings organized by severity and mapped to NIST 800-53 controls. Each finding has a corresponding implementation prompt (Prompts 16-20).

### Critical (5 findings — must fix before production)

| # | Repo | Finding | NIST | Prompt |
|---|------|---------|------|--------|
| 1 | UDIP | 6 analytics tables referenced in YAML mappings do not exist in schema (allegations, charging_parties, respondents, staff_assignments, mediation_sessions, case_events) | N/A | 16 |
| 2 | UDIP | No RLS policies on new tables — PII exposed to all roles | AC-3 | 16 |
| 3 | Triage | SEARCH_KEY (Azure Cognitive Search admin key) read from env var, not Key Vault | IA-2, SC-2 | 18 |
| 4 | Triage | OData injection risk — sanitize_odata_value() not applied consistently to all partition/row keys | SI-10 | 18 |
| 5 | Triage | MCP_WEBHOOK_SECRET read from env var, not Key Vault | IA-2, SC-2 | 18 |

### High (16 findings — fix within sprint)

**UDIP (3):**
- 4 transform handlers not implemented in mapping engine (UUID_V5, lookup_table, lookup_then_redact, fiscal_year) → Prompt 17
- dbt model references analytics.vw_charges which does not exist → Prompt 16
- Lifecycle tables (lifecycle_audit_log, access_stats, etc.) have RLS enabled but no policies defined, blocking all reads → Prompt 16

**ADR (3):**
- CSP allows unsafe-inline styles (XSS surface) → Prompt 19
- MIME type validation allows application/octet-stream when extension is trusted → Prompt 19
- SameSite=Lax on session cookies (documented OIDC trade-off, needs ADR) → Prompt 19

**Triage (7):**
- Dependencies not pinned to specific versions (supply chain risk) → Prompt 18
- MSAL token cache serialized into client-side session cookie → Prompt 18
- AI responses stored without HTML escaping before render → Prompt 18
- Plaintext IP addresses in audit logs (not hashed) → Prompt 18
- OpenAI API key as string instead of managed identity token provider → Prompt 18
- Stats API key endpoints not rate limited → Prompt 20
- Batch file upload has no per-file size limits → Prompt 18

**Docs (3 inconsistencies):**
- Triage tool count: 8 in Leadership Briefing vs 9 in all other docs
- ARC Integration API: "3 read tools" in Architecture Plan vs "10 read tools" in Hub Build Guide (exposed vs implemented distinction unclear)
- Decision tables have different column structures across docs

### Medium (22 findings — plan for next iteration)

**UDIP (4):** PII redaction missing EIN (12-3456789) and DOB (MM/DD/YYYY) patterns. No charge number format validation. Replica schema tables undocumented. Computed expression parser does not support CASE WHEN, NOT(), or CONCAT aggregate. → Prompt 17

**ADR (7):** Email regex too permissive (allows a@b.c). Charge number not format-validated. No per-file size check on uploads. 30-min session timeout (consider 15 for federal). Test mode personas could leak to prod without startup guard. Webhook secret length not re-validated after Key Vault rotation. Token expiry verification not explicit in jwt.decode options. → Prompt 19

**Triage (9):** Prompt injection detection keyword-only. Malware scan post-upload not pre-processing gate. Model drift detection has no circuit breaker. CSRF not validated on JSON API endpoints. Error pages may expose stack traces in some configs. PII in direct log messages not fully hashed. Queue messages for learning not cryptographically signed. Timezone handling inconsistent (utcnow vs now(UTC)). LLM temperature/options hardcoded. → Prompts 18, 20

**Docs (2):** REST API feed fallback referenced but endpoints deprecated. OGC "9 AI analysis tools" phrasing confusing in decision table.

---

## 4.7 Scalability Audit Findings (2026-04-02)

Multi-pass scalability and distributed systems audit across ADR, Triage, and UDIP. Each application must support Azure horizontal scaling (multiple instances behind a load balancer). Findings mapped to remediation prompts.

### Scaling Blockers (10 — prevents horizontal scaling)

| # | Repo | Finding | Prompt |
|---|------|---------|--------|
| 1 | ADR | In-memory caches for rate limits, test mode, feature flags — each instance diverges | 21 |
| 2 | ADR | Stats API rate limiting falls back to in-memory dict when Redis unavailable | 21 |
| 3 | ADR | No distributed locking on Azure Function timer triggers — all instances fire simultaneously | 21 |
| 4 | Triage | Session state in cookie (MSAL token cache serialized client-side) — sticky sessions required | 22 |
| 5 | Triage | In-memory token validation cache, JWKS cache, rate limit fallback — per-instance | 22 |
| 6 | Triage | No distributed locking on timer functions (MetricsRollupDaily, ModelDriftDetector) | 22 |
| 7 | Triage | Azure Table Storage single partition "cases" — hot partition under load | 22 |
| 8 | Triage | No OpenAI retry/backoff — 429 errors cascade at 50+ cases/sec | 22 |
| 9 | UDIP | PostgreSQL connection pool at 15 per pod — 500 concurrent queries exhausts 5x over | 23 |
| 10 | UDIP | In-memory rate limiting not Redis-backed | 23 |

### Scaling Risks (12 — works but degrades at scale)

| # | Repo | Finding | Prompt |
|---|------|---------|--------|
| 1 | ADR | File uploads buffer entire 50MB file in memory before blob upload | 21 |
| 2 | ADR | Mediation table uses single "activecases" partition — hot partition | 21 |
| 3 | ADR | Event dispatcher HTTPS fallback uses blocking time.sleep() | 21 |
| 4 | ADR | Feature flag caches propagate with 60s delay across instances | 21 |
| 5 | ADR | Metrics table date-based partition — daily hot partition | 21 |
| 6 | Triage | ZIP extraction loads entire blob into memory (OOM on Consumption plan) | 22 |
| 7 | Triage | Queue messages have no idempotency keys — duplicates on retry | 22 |
| 8 | UDIP | dbt rebuilds hold exclusive table locks — concurrent queries block | 23 |
| 9 | UDIP | Embedding generation synchronous sequential batches — no parallelism | 23 |
| 10 | UDIP | MCP DatasetRegistry not thread-safe (shared dict, no locks) | 23 |
| 11 | UDIP | Query results fully buffered in memory (up to 10K rows) | 23 |
| 12 | UDIP | Reconciliation dual-DB reads under production load | 23 |

---

## 4.9 Production Deployment Gaps (2026-04-03)

ADR, Triage, and ARC Integration API have no production deployment manifests. UDIP is the only repo with Kubernetes configs, HPA, and PgBouncer. ADR is public-facing (Login.gov for external parties) and needs edge security. PgBouncer config was undersized for the actual data profile (800 GB source, 350 tables, thousands of concurrent connections).

### Deployment Infrastructure Status

| Repo | K8s Manifests | HPA | WAF/Edge | Resource Limits | Prompt |
|------|-------------|-----|---------|----------------|--------|
| UDIP | Yes | Yes (2-6 replicas) | N/A (internal) | Yes | PgBouncer updated |
| ADR | **MISSING** | **MISSING** | **MISSING** (public-facing!) | **MISSING** | 28 |
| Triage | **MISSING** | **MISSING** | N/A (internal) | **MISSING** | 29 |
| ARC Integration API | **MISSING** | **MISSING** | N/A (internal) | **MISSING** | 30 |
| MCP Hub | APIM (portal) | APIM built-in | APIM built-in | APIM tier | N/A |

### ADR Public-Facing Scaling Requirements

- 2000 new cases/month, 6000 active cases, ~18,000 registered users (parties)
- Sustained 500 concurrent users, burst to 2000
- Requires: Azure Front Door with WAF v2, OWASP 3.2, rate limiting, DDoS protection, bot filtering
- Table Storage: "activecases" hot partition must be repartitioned before 6000 cases
- Secondary index table for "list all active" queries after repartitioning

### PgBouncer Production Config (Updated 2026-04-03)

| Setting | Old | New |
|---------|-----|-----|
| MAX_CLIENT_CONN | 500 | 3,000 |
| DEFAULT_POOL_SIZE | 50 | 80 |
| RESERVE_POOL_SIZE | 5 | 20 |
| MAX_DB_CONNECTIONS | (unset) | 200 |
| CLIENT_IDLE_TIMEOUT | 0 (unlimited) | 600s |
| QUERY_TIMEOUT | 0 (unlimited) | 30s |

### Database Sizing for 800 GB Source

| Component | Size |
|-----------|------|
| Replica schema | ~800 GB |
| Analytics schema | ~400 GB |
| Vector embeddings | ~100 GB |
| Indexes | ~200 GB |
| WAL + headroom | ~200 GB |
| **Total** | **~1.7 TB** |

Instance: Memory Optimized, 16 vCores, 128 GB RAM, 2 TB storage with read replica.

---

### Scaling OK (17 items passed clean)

Sessions (ADR Redis-backed, UDIP Redis-backed), database connections (singleton + pooling), MCP servers (stateless request-scoped), blob storage (SAS tokens, no contention), Azure Table Storage writes (sequential, good partition design for non-case tables), Kubernetes HPA configured (UDIP 2-6 replicas), full-text search (GIN indexes acceptable), RLS overhead (negligible), concurrent request handling (gunicorn + Flask g context), no WebSocket dependencies, Azure Cognitive Search connection pooling, malware scanning (Event Grid scales), WORM blob writes (unique names).

---

---

## 4.8 AI Assistant Gaps (2026-04-02)

Audit of the UDIP AI Assistant against the requirement for a full conversational AI assistant capable of multi-turn conversations, complex database queries, and visualization generation.

### What exists and works well:
- Azure OpenAI GPT-4o integration with function/tool calling
- SQL generation with sqlglot AST-level validation (injection-proof)
- Row-level security enforced at database layer per user's region/office/PII tier
- Narrative full-text search + document RAG via Azure Cognitive Search
- MCP protocol server with auto-generated tools from dbt models
- 10+ metric definitions with canonical SQL expressions
- Comprehensive audit logging with HMAC integrity signatures
- Section 508 accessible chat UI

### Critical gaps (Prompts 24-26):

| Gap | Impact | Prompt |
|-----|--------|--------|
| **No persistent conversation history** | Each request is stateless. AI cannot see prior messages. Follow-up questions fail without manually repeating context. | 24 |
| **No multi-turn context** | "Break that down by region" produces garbage because the AI doesn't know what "that" refers to. | 24 |
| **No query refinement loop** | SQL errors terminate the conversation. No interactive "try again" flow. | 24 |
| **No visualization generation** | Suggests chart type as a string ("bar") but renders nothing. Users see raw tables only. | 25 |
| **No dashboard creation** | Links to Superset but cannot create dashboards dynamically. | 26 |
| **No reasoning explanation** | Cannot explain why it generated a particular query or chose specific tables. | 24 |

### Architecture for the AI Assistant (after Prompts 24-26):

```
User question
    ↓
Load conversation history (Azure Table Storage, last 20 messages)
    ↓
Build messages array: [system_prompt + schema + metrics, ...history, user_msg]
    ↓
Azure OpenAI GPT-4o (with tools: narrative_search, document_search,
    create_visualization, create_dashboard)
    ↓
Tool execution → SQL validation → RLS-enforced query → results
    ↓
Chart generation (Vega-Lite spec from result data)
    ↓
Response: {text, sql, data, chart_spec, reasoning}
    ↓
Store in conversation history → render chart client-side (Vega-Embed)
    ↓
User follow-up → AI sees full context → refines query/chart
```

---

### What Passed Clean

- **ADR**: Zero hardcoded secrets. OData sanitization consistent. CSRF on all state-changing ops. HMAC-SHA256 webhooks with timing-safe comparison. PII masked in audit logs. Dependencies fully pinned. Full security CI/CD pipeline.
- **UDIP**: Parameterized queries everywhere (no SQL injection). Zero hardcoded secrets. Strong Entra ID + RLS. Non-root containers.
- **Triage**: Government cloud endpoints. HTTPS enforced. AI audit dual-write with integrity hashes. Key Vault for most secrets.

---

### Missing from ALL Prompts: FedRAMP Compliance Requirements
Every prompt that produces code should specify:
- Bandit-clean Python (no B-series findings at medium+ severity)
- No hardcoded secrets (all from Key Vault or environment)
- Input validation on all external-facing parameters
- Structured logging with PII hashing
- HTTPS-only for all outbound calls
- TLS 1.2 minimum
- SBOM-compatible dependency management (pinned versions in requirements.txt)
- Non-root container execution
- Security headers (Talisman/CSP for web endpoints)

---

## 5. Compliance Requirements for All New Code

Every piece of code produced by the implementation prompts must pass:

| Check | Tool | Standard |
|-------|------|----------|
| Static analysis | Bandit | No medium+ findings (NIST SI-10) |
| Pattern-based SAST | Semgrep | No high findings |
| Dependency vulnerabilities | pip-audit | No known CVEs in dependencies |
| OWASP top 10 | OWASP Dependency-Check | No critical/high CVEs |
| License compliance | pip-licenses | No copyleft in production deps |
| SBOM generation | CycloneDX | SA-4 supplier transparency |
| Secret scanning | grep patterns + pre-commit | No secrets in source |
| Container security | Non-root user, minimal base image | AC-6 least privilege |
| DAST baseline | OWASP ZAP | No high findings on exposed endpoints |

These map to NIST 800-53 controls: SI-10 (input validation), SA-4 (supplier transparency), SA-11 (developer testing), AC-6 (least privilege), SC-8 (transmission confidentiality), AU-3 (audit content).
