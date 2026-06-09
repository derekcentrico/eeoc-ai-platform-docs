# DAES Test Environment - Static-Import Proof Playbook

**Author:** Derek Gordon
**Platform:** Data and AI Enterprise System (DAES)
**Purpose:** Stand up the integrated stack and prove the end-to-end claim - **load static data
and query it through the MCP server and the central analytics warehouse, across the whole
platform (UDAP dashboard/AI assistant + MCP Hub + ARC Integration API + ADR Portal + OGC Trial
Tool)** - without live ARC ingest. Every application is reached through the MCP Hub, and AI
generation runs over that same governed, audited path.

This is a focused subset of the full
[EEOC AI Platform Complete Deployment Guide](EEOC_AI_Platform_Complete_Deployment_Guide.md).
Use that guide for the detailed Azure Portal click-paths, resource names (Appendix A), and
per-application environment variables (Appendix B). This playbook says **what to skip**,
**what to deploy**, **how to load the static file instead of live CDC**, and **how to prove
it works**.

---

## 1. What this proves (and what it does not)

**Proves:** static data loaded into the central analytics warehouse is visible in the UDAP
dashboard, and the UDAP AI assistant can answer questions that route through the MCP Hub to
every deployed spoke: the ARC Integration API tool surface (charge and reference data over the
warehouse), the ADR Portal (mediation `case_*`/`chat_*`/`doc_*`/`participant_*` tools over its
own store), and the OGC Trial Tool (`trial_*` tools over its own store). Each application is
registered as an MCP spoke and reached only through the Hub; AI generation runs over that same
governed, audited path. That is the
`static data -> central warehouse + spoke stores -> MCP Hub -> dashboard + AI` chain across the
whole platform.

**Does not exercise (intentionally deferred):** live ARC ingest (Debezium -> Event Hub ->
middleware), and the OFS Triage, OCHCO, and Access Admin apps. Those are out of scope for this
proof and are not deployed; each registers as an additional MCP spoke the same way once added.

---

## 2. Components to deploy

### Applications (5)

| Component | Repo | Role in the proof |
|---|---|---|
| **UDAP** - AI assistant, dashboard (Superset), portal | `eeoc-data-analytics-and-dashboard` | Central warehouse target, presentation, and the AI chat that drives the MCP path |
| **MCP Hub** - aggregator function | `eeoc-mcp-hub-functions` | Routes the AI assistant's tool calls to every spoke by tool-name prefix |
| **ARC Integration API** | `eeoc-arc-integration-api` | MCP spoke + data/reference endpoints. **Its live-ARC upstream stays unset** - the static import replaces it |
| **ADR Portal** | `eeoc-ofs-adr` | MCP spoke (`case_*`, `chat_*`, `doc_*`, `participant_*` tools) over its own Table Storage; mediation case data |
| **OGC Trial Tool** | `eeoc-ogc-trialtool` | MCP spoke (`trial_*` tools) over its own Table Storage; trial-prep data |

The compute target is **AKS** (see §6) - deploy from each repo's `deploy/k8s/` manifests. The
subset to deploy: UDAP's stack (`ai-assistant`, Superset, `portal-nginx`, `pgbouncer`; JupyterHub
is available for the data team but is not part of the smoke test), the **MCP Hub**, the **ARC
Integration API**, the **ADR Portal** (`adr-webapp`, `adr-functionapp`, `adr-redis`), and the
**OGC Trial Tool** (`ogc-webapp`, `ogc-functionapp`). **Do not deploy** the Debezium / Event Hub
CDC pipeline, or the OFS Triage / OCHCO / Access Admin apps.

### Supporting Azure resources (must exist)

| Resource | Complete Guide name | Why |
|---|---|---|
| PostgreSQL Flexible Server | `pg-eeoc-udap-*` | The analytics warehouse - the static import target |
| Azure OpenAI | `oai-eeoc-ai-*` | The AI assistant's model (`gpt-4o`) |
| Redis | `redis-eeoc-ai-*` | Sessions + cache for UDAP and the API |
| Key Vault | `kv-eeoc-ai-*` | HMAC keys, DB password, OpenAI key, Flask/secret keys |
| Storage account | `steeocai*` | WORM blob (AI audit archive) + Table Storage (audit/access) |
| Container Registry | `acreeocai*` | Holds the three components' images |
| AKS cluster | `aks-eeoc-…` | Compute host for all components (§6); deploy via each repo's `deploy/k8s/` |
| Log Analytics + App Insights | `log-…` / `appi-…` | Smoke-test log queries |
| Entra app registrations + managed identities | per component | Auth + the app-role wiring in §4 |

**Not needed for the proof:** Event Hub (`evhns-…`), Cognitive Search (`srch-…`), Front Door /
WAF (`afd-…`/`waf-…`), the read replica, API Management is only needed if you front the MCP
Hub with APIM (see §4).

---

## 3. Deployment order

1. **Foundational infra** - Resource Group, VNet/subnets/NSGs, Key Vault, Storage, ACR,
   Postgres, Redis, Azure OpenAI (Complete Guide Part 2).
2. **Secrets into Key Vault** - at minimum: DB admin password, `OPENAI-API-KEY`,
   `REDIS-CONNECTION-STRING`, the per-component audit HMAC keys
   (`AI-AUDIT-HMAC-KEY`, `ARC-AUDIT-HMAC-KEY`, `HUB-AUDIT-HMAC-KEY`), the Hub's
   `HUB-AUDIT-HASH-SALT` (a distinct PII salt, not the HMAC key), and Flask/app secret
   keys. The provisioning scripts in each repo create these; verify every name the
   SecretProviderClass/app settings reference actually exists, or the pod will not start.
3. **Entra registrations + app-roles** (§4) - before the apps start, since auth is wired at boot.
4. **Push images to ACR** - build and push the three components (Complete Guide Part 2 image step).
5. **Deploy ARC Integration API** - with its live-ARC upstream left unset (§5).
6. **Deploy ADR Portal** (`adr-webapp` + `adr-functionapp` + `adr-redis`) and **OGC Trial Tool**
   (`ogc-webapp` + `ogc-functionapp`) from their `deploy/k8s/` manifests, each with
   `MCP_ENABLED=true` so its `/mcp` endpoint is live.
7. **Deploy MCP Hub** - register the ARC Integration API, ADR, and OGC as spokes in the
   `mcpspokes` registry (§4) so the Hub aggregates all three tool catalogs.
8. **Deploy UDAP** (AI assistant, Superset, portal) - point it at Postgres, Redis, OpenAI, and
   the MCP Hub.
9. **Load the static data** into the warehouse and the ADR/OGC stores (§5).
10. **Smoke test** (§7).

---

## 4. Auth and wiring (the part that trips people)

Every component authenticates with managed identity for Azure-to-Azure calls and a bearer
token (Entra app-role) for service-to-service calls. The minimal app-role map for the proof:

| Caller -> callee | Role required |
|---|---|
| UDAP AI assistant -> MCP Hub | `MCP.Read` (and `MCP.Write` only if a write tool is exercised) |
| MCP Hub -> ARC Integration API (spoke) | `ARC.Read` |
| MCP Hub -> ADR Portal (spoke) | `MCP.Read`, `MCP.Write` (add `MCP.ReadConfidential` only to surface caucus channels) |
| MCP Hub -> OGC Trial Tool (spoke) | `MCP.Read`, `MCP.Write` |
| UDAP analytics surface | `Analytics.Read` (UDAP uses `Analytics.*`, **not** `MCP.*`) |

Key env vars that wire the components together (full list in Complete Guide Appendix B):

- **UDAP AI assistant:** `MCP_ENABLED=true`, `MCP_HUB_URL` (the MCP Hub / APIM internal URL),
  `PG_AI_DATABASE`, `OPENAI_API_BASE`/`OPENAI_DEPLOYMENT`, `REDIS_URL`, `OPENAI_API_KEY`.
- **ARC Integration API:** `MCP_HUB_URL`, `MCP_HUB_HMAC_SECRET`, `ARC_AUDIT_HMAC_KEY`,
  `REDIS_URL`. **Leave `ARC_GATEWAY_URL` / `ARC_PREPA_URL` / `ARC_AUTH_URL` unset** for the
  static proof so no live-ARC call is attempted.
- **MCP Hub:** `HUB_AUDIT_HMAC_KEY` and `HUB_AUDIT_HASH_SALT` (both required, at least 32 chars;
  the Hub fails closed on audit without the HMAC key), `ALLOWED_SPOKE_PRIVATE_CIDRS` set to the
  in-cluster spoke subnet CIDR, and the spoke registry pointing at the ARC Integration API, ADR,
  and OGC internal URLs. The Hub's SSRF validator rejects a private-IP spoke URL unless its range
  is listed in `ALLOWED_SPOKE_PRIVATE_CIDRS`; that value is substituted from the same
  `PRIVATE_ENDPOINTS_CIDR` token as the NetworkPolicy egress rule, so the allowlist and the
  network policy stay in sync. All three spokes run in-cluster on private IPs for this proof, so
  this must be set or the routed tool calls are blocked.
- **ADR Portal and OGC Trial Tool (spokes):** `MCP_ENABLED=true` and `MCP_PROTOCOL_ENABLED=true`
  so each exposes its `/mcp` endpoint, plus `ARC_INTEGRATION_API_URL` (both reach ARC only through
  the Integration API, never directly), each app's audit HMAC key, and its Table Storage
  connection. The Hub's managed identity must hold the spoke app-role each enforces on `/mcp`
  (the role map above), or the spoke returns 403 on `tools/list` and drops from the merged catalog.

> **Default-off integrations:** `MCP_ENABLED` and `MCP_PROTOCOL_ENABLED` default to `false`
> platform-wide. For this proof you intentionally set `MCP_ENABLED=true` on UDAP and the Hub.

> **ARC self-service auth:** ARC self-service authorization (a caller resolving its own roles or
> profile) matches the token's lowercased `email`/UPN claim, not `sub`. App-only tokens (managed
> identity / client credentials) carry no email, so any user-scoped ARC lookup needs the
> `Access.Admin` role. The data and reference tool calls the smoke test exercises do not hit
> these endpoints; if you add a user-context call, surface the optional `email`/`upn` claim on
> the caller's app registration.

---

## 5. Loading the static data (replaces live CDC)

The Complete Guide's Part 3 (ARC DBA coordination) and Part 5 (Debezium/Event Hub data flow)
are **skipped**. The static data lands in two places: the central warehouse (for analytics and
the AI's SQL path) and the ADR/OGC spoke stores (for their MCP tools).

**Central warehouse (UDAP Postgres):**

1. **Confirm the target schema.** The static file must load into the **warehouse** model that
   the dashboard and queries read - the Postgres `arc_analytics` analytics schema - **not** the
   source IMS SQL Server model. (The demo's "8 schemas / 331 tables" figures describe the
   *source* system, not the warehouse. Pin the warehouse target before anyone loads data.)
2. **Load.** Restore the static dump into the warehouse database
   (`psql`/`pg_restore` into `pg-eeoc-udap-*`), then apply the schema/RLS/grants the analytics
   layer expects. The `udap-demo` initialization (its `090`-series DB+RLS setup and the
   dashboard-seed scripts) is the proven mechanism - adapt those for the Azure Postgres target.
3. **Point the catalog at the warehouse.** Ensure the data catalog / dashboard datasource
   resolves to the loaded warehouse schema, not the demo placeholder figures.

**Spoke stores (ADR and OGC Table Storage):**

4. **Seed the spoke stores.** ADR and OGC serve their MCP tools from their own Azure Table
   Storage, not the warehouse, so the proof needs representative data in each. Load a static seed
   into ADR's case tables (mediation cases, participants, chat) and OGC's trial tables (`casedata`
   and related) using the table-import path each repo's seed fixtures use (`az storage entity`
   batch import against the test storage account). This is the same "static dump in place of live
   ingest" approach as the warehouse load, applied to the operational stores.

This whole static-data path is the **pre-WAL concept proof**. Once ARC WAL/CDC is approved, the
warehouse load (steps 1-3) is replaced by live ingest and the spoke stores fill from each app's
normal write path; the MCP wiring and the §7 smoke test do not change.

---

## 6. Compute target: AKS (decided)

The test environment runs on **AKS** - the same hosting model as production - so the test env
also rehearses the production deploy, and the data team's JupyterHub (which spawns Kubernetes
pods) runs natively. Deploy each component from its repo's `deploy/k8s/` manifests
(SecretProviderClass, workload identity, NetworkPolicy, HPA, PDB).

All deployed components ship complete `deploy/k8s/` manifests: UDAP, the ARC Integration API, the
MCP Hub (`deploy/k8s/mcp-hub/`), ADR (`adr-webapp`, `adr-functionapp`, `adr-redis`), and OGC
(`ogc-webapp`, `ogc-functionapp`). Follow each repo's `Deployment_Guide.md` for the apply steps;
the MCP Hub guide covers the image build, placeholder substitution, and the `PRIVATE_ENDPOINTS_CIDR`
token that wires the SSRF allowlist and the NetworkPolicy egress rule together. The interim
`func azure functionapp publish` path remains available for a quick catalog check before the
cluster namespace is ready.

The Complete Deployment Guide's Container Apps sections (`cae-…`, `ca-*`) are superseded for the
test env by these per-repo AKS manifests: use the Complete Guide for the supporting-resource
provisioning (compute-agnostic) and the per-repo manifests for compute.

---

## 7. Smoke test (proves the claim)

1. **Warehouse has data.** Query the analytics tables directly (Complete Guide Part 5, step 4
   pattern) and confirm row counts from the static file.
2. **Dashboard renders.** Open the UDAP portal/Superset; confirm a dashboard built on the
   loaded schema shows the imported data.
3. **Merged catalog spans all spokes.** Hit the Hub's `GET /api/tools` (or `POST
   /api/tools/refresh`) and confirm the catalog includes tools from every spoke, prefixed: ARC
   tools, ADR `case_*`/`chat_*`/`doc_*`/`participant_*`, and OGC `trial_*`. A spoke missing from
   the catalog means a missing app-role grant (§4), not a token problem.
4. **AI assistant answers via MCP, across spokes.** Send the UDAP AI assistant a warehouse
   question (ARC analytics), then one that needs a mediation case (routes to ADR), then one that
   needs trial data (routes to OGC). Confirm each response includes a result and that the MCP Hub
   logs show the call routed to the matching spoke (App Insights / Log Analytics for the `mcp-hub`
   pods in `eeoc-mcp`). This proves every application is reached through the MCP server.
5. **Audit trail.** Confirm an AI-generation audit record was written with an HMAC signature for
   the AI path, and that each spoke wrote its own MCP tool-call audit (the UDAP audit table,
   `arcintegrationaudit`, and ADR's/OGC's audit tables). This is the NARA/AU-10 requirement and
   proves the governed path, not a bypass.

If all five pass, the integrated static-data proof is complete: static data loaded, every app
reached through the MCP server and the central warehouse, and AI answering over that governed path.

---

## 8. Known accuracy caveats in the referenced guide

- The Complete Guide has been updated to Azure Commercial endpoints throughout (`*.openai.azure.com`,
  `*.vault.azure.net`, `*.postgres.database.azure.com`, `*.servicebus.windows.net`,
  `login.microsoftonline.com`, `graph.microsoft.com`, region `eastus`). The application code,
  provisioning scripts, and the guide now all target Azure Commercial.
- Verify Key Vault secret **names** in each repo's SecretProviderClass against what the
  provisioning script actually creates before first pod start.
- The storage account needs the **`security-audit-archive`** WORM container (2555-day
  immutability) in addition to the AI/hub/ARC audit archives: ARC, MCP Hub, ADR, and OGC write
  their security-event audit rows there. The Complete Guide's blob-container table
  lists it. When provisioning the policy by CLI, `az storage container immutability-policy
  create` is a management-plane (ARM) call and does not take `--auth-mode`.

---

## 9. Provisioning ADR and OGC in the shared resource group

ADR and OGC are spokes in this proof (§2), provisioned into the same test resource group and
sharing its supporting resources (Key Vault, Redis, Storage, Azure OpenAI, AKS, Log Analytics).
This section covers their provisioning specifics; the deploy order and MCP wiring are in §3 and §4.

### ADR Portal

**No name collisions.** `provision_adr_system.sh` derives its resource names from a `--suffix`
and prefixes them `eeoc-adr-*`, which does not overlap the UDAP/`udap-*`/`eeoc-ai-*` names. Pass
the shared resource group with `--rg-name`:

```bash
./provision_adr_system.sh \
  --rg-name rg-daes-test \
  --suffix test \
  --location eastus \
  --custom-dns adr-test.eeoc.gov \
  --tenant-id <tenant-id> \
  --mediator-group-id <guid> --admin-group-id <guid> --stats-admin-group-id <guid> \
  --ir-email security@eeoc.gov \
  --triage-rg rg-daes-test --triage-storage <triage-or-shared-storage> \
  --gateway-cidrs "<your-test-source-cidrs>"   # lock the gateway for a test env
```

**ADR-specific storage.** ADR adds its own Table Storage audit tables and these blob containers:
`adr-case-files`, `adr-quarantine`, the `ai-generation-archive` WORM container (AI generation
records), and the `security-audit-archive` WORM container (security-event rows). The provisioning
script creates both WORM containers with the 2555-day time-based immutability policy and a
matching lifecycle cleanup rule; it never creates them at app runtime.

**Manual steps before first run** (the script validates the second one and exits if missing):

1. Import the TLS certificate into Key Vault under the name `provision_adr_system.sh` expects
   (`az keyvault certificate import ... --name eeoc-adr-cert`). The all-in-one
   `provision_eeoc_ai_platform.sh` path names the same cert `adr-tls-cert`; use the name matching
   the script you run.
2. Upload the settlement boilerplate document to the Triage/shared storage `priority-docs`
   container (`ADR_Settlement_Boilerplate.docx`).
3. Register the ADR Entra app (web OIDC) and grant admin consent; provision Azure Communication
   Services for email if you exercise notifications.

For the proof, ADR runs with `MCP_ENABLED=true` so its `/mcp` spoke is live (§4). Confirm health
at its `/health` endpoint and sign in through Entra ID; the merged-catalog and routing checks are
in §7.

### OGC Trial Tool

OGC provisions into the same resource group via `provision_ogc_trialtool.sh` and adds its own
Table Storage (`casedata` and related trial tables) plus its AI-audit and security-audit WORM
containers. Deploy `ogc-webapp` and `ogc-functionapp` from `deploy/k8s/`, set `MCP_ENABLED=true`
and `ARC_INTEGRATION_API_URL`, and grant the Hub's managed identity OGC's `MCP.Read`/`MCP.Write`
app-roles so its `trial_*` tools appear in the merged catalog. Seed its trial tables with the
static data per §5 step 4.
