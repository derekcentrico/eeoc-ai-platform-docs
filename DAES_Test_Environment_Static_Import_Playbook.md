# DAES Test Environment — Static-Import Proof Playbook

**Author:** Derek Gordon
**Platform:** Data and AI Enterprise System (DAES)
**Purpose:** Stand up the smallest set of components that proves the end-to-end claim —
**import a static database file and query it through the integrated stack (MCP Hub +
ARC Integration API + UDAP dashboard/AI assistant)** — without live ARC ingest.

This is a focused subset of the full
[EEOC AI Platform Complete Deployment Guide](EEOC_AI_Platform_Complete_Deployment_Guide.md).
Use that guide for the detailed Azure Portal click-paths, resource names (Appendix A), and
per-application environment variables (Appendix B). This playbook says **what to skip**,
**what to deploy**, **how to load the static file instead of live CDC**, and **how to prove
it works**.

---

## 1. What this proves (and what it does not)

**Proves:** a static export loaded into the analytics warehouse is visible in the UDAP
dashboard, and the UDAP AI assistant can answer a question about that data by calling the
MCP Hub, which routes to the ARC Integration API tool surface. That is the
`import → warehouse → MCP/API → dashboard + AI` chain.

**Does not exercise (intentionally deferred):** live ARC ingest (Debezium → Event Hub →
middleware), and the case-management applications (ADR, Triage, OGC Trial Tool, OCHCO,
Access Admin). Those are out of scope for the proof and are not deployed.

---

## 2. Components to deploy

### Applications (3)

| Component | Repo | Role in the proof |
|---|---|---|
| **UDAP** — AI assistant, dashboard (Superset), portal | `eeoc-data-analytics-and-dashboard` | Import target, presentation, and the AI chat over the data |
| **MCP Hub** — aggregator function | `eeoc-mcp-hub-functions` | Routes the AI assistant's tool calls to the spoke(s) |
| **ARC Integration API** | `eeoc-arc-integration-api` | MCP spoke + data/reference endpoints. **Its live-ARC upstream stays unset** — the static import replaces it |

The compute target is **AKS** (see §6) — deploy from each repo's `deploy/k8s/` manifests. The
subset to deploy: UDAP's stack (`ai-assistant`, Superset, `portal-nginx`, `pgbouncer`; JupyterHub
is available for the data team but is not part of the smoke test), the **MCP Hub**, and the
**ARC Integration API**. **Do not deploy** the Debezium / Event Hub CDC pipeline, the
ADR/Triage/OGC/OCHCO apps, or the Access Admin app.

### Supporting Azure resources (must exist)

| Resource | Complete Guide name | Why |
|---|---|---|
| PostgreSQL Flexible Server | `pg-eeoc-udap-*` | The analytics warehouse — the static import target |
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

1. **Foundational infra** — Resource Group, VNet/subnets/NSGs, Key Vault, Storage, ACR,
   Postgres, Redis, Azure OpenAI (Complete Guide Part 2).
2. **Secrets into Key Vault** — at minimum: DB admin password, `OPENAI-API-KEY`,
   `REDIS-CONNECTION-STRING`, the per-component audit HMAC keys
   (`AI-AUDIT-HMAC-KEY`, `ARC-AUDIT-HMAC-KEY`, `HUB-AUDIT-HMAC-KEY`), and Flask/app secret
   keys. The provisioning scripts in each repo create these; verify every name the
   SecretProviderClass/app settings reference actually exists, or the pod will not start.
3. **Entra registrations + app-roles** (§4) — before the apps start, since auth is wired at boot.
4. **Push images to ACR** — build and push the three components (Complete Guide Part 2 image step).
5. **Deploy ARC Integration API** — with its live-ARC upstream left unset (§5).
6. **Deploy MCP Hub** — point its spoke registry at the ARC Integration API.
7. **Deploy UDAP** (API assistant, Superset, portal) — point it at Postgres, Redis, OpenAI,
   and the MCP Hub.
8. **Load the static file** (§5).
9. **Smoke test** (§7).

---

## 4. Auth and wiring (the part that trips people)

Every component authenticates with managed identity for Azure-to-Azure calls and a bearer
token (Entra app-role) for service-to-service calls. The minimal app-role map for the proof:

| Caller → callee | Role required |
|---|---|
| UDAP AI assistant → MCP Hub | `MCP.Read` (and `MCP.Write` only if a write tool is exercised) |
| MCP Hub → ARC Integration API (spoke) | `ARC.Read` |
| UDAP analytics surface | `Analytics.Read` (UDAP uses `Analytics.*`, **not** `MCP.*`) |

Key env vars that wire the components together (full list in Complete Guide Appendix B):

- **UDAP AI assistant:** `MCP_ENABLED=true`, `MCP_HUB_URL` (the MCP Hub / APIM internal URL),
  `PG_AI_DATABASE`, `OPENAI_API_BASE`/`OPENAI_DEPLOYMENT`, `REDIS_URL`, `OPENAI_API_KEY`.
- **ARC Integration API:** `MCP_HUB_URL`, `MCP_HUB_HMAC_SECRET`, `ARC_AUDIT_HMAC_KEY`,
  `REDIS_URL`. **Leave `ARC_GATEWAY_URL` / `ARC_PREPA_URL` / `ARC_AUTH_URL` unset** for the
  static proof so no live-ARC call is attempted.
- **MCP Hub:** `HUB_AUDIT_HMAC_KEY` (must be set — the Hub fails closed on audit without it),
  spoke registry pointing at the ARC Integration API internal URL.

> **Default-off integrations:** `MCP_ENABLED` and `MCP_PROTOCOL_ENABLED` default to `false`
> platform-wide. For this proof you intentionally set `MCP_ENABLED=true` on UDAP and the Hub.

---

## 5. Loading the static file (replaces live CDC)

The Complete Guide's Part 3 (ARC DBA coordination) and Part 5 (Debezium/Event Hub data flow)
are **skipped**. Instead:

1. **Confirm the target schema.** The static file must load into the **warehouse** model that
   the dashboard and queries read — the Postgres `arc_analytics` analytics schema — **not** the
   source IMS SQL Server model. (The demo's "8 schemas / 331 tables" figures describe the
   *source* system, not the warehouse. Pin the warehouse target before anyone loads data.)
2. **Load.** Restore the static dump into the warehouse database
   (`psql`/`pg_restore` into `pg-eeoc-udap-*`), then apply the schema/RLS/grants the analytics
   layer expects. The `udap-demo` initialization (its `090`-series DB+RLS setup and the
   dashboard-seed scripts) is the proven mechanism — adapt those for the Azure Postgres target.
3. **Point the catalog at the warehouse.** Ensure the data catalog / dashboard datasource
   resolves to the loaded warehouse schema, not the demo placeholder figures.

---

## 6. Compute target: AKS (decided)

The test environment runs on **AKS** — the same hosting model as production — so the test env
also rehearses the production deploy, and the data team's JupyterHub (which spawns Kubernetes
pods) runs natively. Deploy each component from its repo's `deploy/k8s/` manifests
(SecretProviderClass, workload identity, NetworkPolicy, HPA, PDB).

UDAP and the ARC Integration API ship complete `deploy/k8s/` manifests. **The MCP Hub does not
have AKS manifests yet** — it has only a Dockerfile (itself being corrected to the Azure Functions
base image). Its Deployment / Service / SecretProviderClass / ServiceAccount / NetworkPolicy set
must be authored, modeled on the ARC manifests, before the MCP Hub can be deployed to AKS. Until
then, the MCP Hub can run via `func azure functionapp publish` for an interim catalog check.

The Complete Deployment Guide's Container Apps sections (`cae-…`, `ca-*`) are superseded for the
test env by these per-repo AKS manifests: use the Complete Guide for the supporting-resource
provisioning (compute-agnostic) and the per-repo manifests for compute.

---

## 7. Smoke test (proves the claim)

1. **Warehouse has data.** Query the analytics tables directly (Complete Guide Part 5, step 4
   pattern) and confirm row counts from the static file.
2. **Dashboard renders.** Open the UDAP portal/Superset; confirm a dashboard built on the
   loaded schema shows the imported data.
3. **AI assistant answers via MCP.** Send a question to the UDAP AI assistant (Complete Guide
   Part 5, steps 5–6 pattern). Confirm the response includes the generated SQL and a result,
   and that the MCP Hub logs show a tool call routed to the ARC Integration API spoke
   (App Insights / Log Analytics on `ca-mcp-hub-func`).
4. **Audit trail.** Confirm an AI-generation audit record was written (Table Storage
   `arcintegrationaudit` / the UDAP audit table) with an HMAC signature — this is the
   NARA/AU-10 requirement and proves the governed path, not a bypass.

If all four pass, the static-import proof is complete.

---

## 8. Known accuracy caveats in the referenced guide

- The Complete Guide has been updated to Azure Commercial endpoints throughout (`*.openai.azure.com`,
  `*.vault.azure.net`, `*.postgres.database.azure.com`, `*.servicebus.windows.net`,
  `login.microsoftonline.com`, `graph.microsoft.com`, region `eastus`). The application code,
  provisioning scripts, and the guide now all target Azure Commercial.
- Verify Key Vault secret **names** in each repo's SecretProviderClass against what the
  provisioning script actually creates before first pod start.
