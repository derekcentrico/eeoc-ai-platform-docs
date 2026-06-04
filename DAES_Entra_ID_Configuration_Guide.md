# DAES Entra ID Configuration Guide
**Author:** Derek Gordon

## Data and AI Enterprise System (DAES)

---

This guide is the authoritative reference for Entra ID configuration across all DAES
components. It covers app registrations, app roles, managed-identity grants, access
restrictions, and Key Vault secret wiring per component.

Cross-references:
- Handshake code and OIDC callback detail: `Entra_ID_Handshake_Code_Reference.md`
- Dual-IdP routing and Login.gov pattern: `Authentication_Integration_Reference.md`
- Per-component environment variables: `EEOC_AI_Platform_Complete_Deployment_Guide.md` Appendix B

---

## Table of Contents

1. [App Registrations — one per component](#1-app-registrations--one-per-component)
2. [App-Role Catalog](#2-app-role-catalog)
3. [MCP Hub managed-identity grants](#3-mcp-hub-managed-identity-grants)
4. [Tenant, domain, and security-group restriction layers](#4-tenant-domain-and-security-group-restriction-layers)
5. [Per-component Key Vault secrets and workload identity](#5-per-component-key-vault-secrets-and-workload-identity)

---

## 1. App Registrations — one per component

Each DAES component has exactly one Entra ID app registration. Registrations are
**single-tenant** (the EEOC tenant). Machine-to-machine (M2M) registrations have no
redirect URI.

| Component | Entra app name | Client-ID env var | Auth model |
|---|---|---|---|
| ADR Portal | `EEOC-ADR-Mediation` | `AZURE_CLIENT_ID` (Key Vault: `AAD-CLIENT-ID`) | Interactive OIDC (EEOC staff) + M2M bearer (MCP callers) |
| Triage | `EEOC-OFS-Triage` | `AZURE_CLIENT_ID` (Key Vault: `AAD-CLIENT-ID`) | Interactive OIDC + M2M bearer |
| OGC Trial Tool | `EEOC-OGC-TrialTool` | `AZURE_CLIENT_ID` | Interactive OIDC + M2M bearer |
| OCHCO Benefits Validation | `EEOC-OCHCO-Benefits` | `AZURE_CLIENT_ID` | M2M bearer only (spoke) |
| UDAP (AI assistant) | `EEOC-UDAP-Analytics` | `AZURE_CLIENT_ID` | Interactive OIDC + M2M bearer |
| ARC Integration API | `EEOC-ARC-Integration` | `AZURE_CLIENT_ID` | M2M bearer only |
| MCP Hub | `EEOC-MCP-Hub` | Managed identity (no client secret for spoke calls) | Managed identity + M2M bearer (inbound) |
| Access Admin | `EEOC-Access-Admin` | `AZURE_CLIENT_ID` | Interactive OIDC only |

**Authority URL** for all registrations: `https://login.microsoftonline.com/<EEOC-tenant-id>/v2.0`

The EEOC tenant ID is injected at deploy time via the `AZURE_TENANT_ID` environment
variable. It must never be hardcoded. The `.gov` GCC-High authority
(`login.microsoftonline.us`) must not appear in any DAES configuration — the platform
runs on Azure Commercial.

---

## 2. App-Role Catalog

### 2.1 Role definitions per registration

Each spoke exposes app roles on its own registration. A consumer gains access by
receiving an admin-consent assignment of the spoke's role on the spoke's registration.

#### ADR Portal (`EEOC-ADR-Mediation`)

| Role value | Type | Purpose |
|---|---|---|
| `MCP.Read` | Application | Read tools, resources, and prompts via MCP |
| `MCP.Write` | Application | Invoke write tools via MCP |
| `MCP.ReadConfidential` | Application | Read caucus-channel content (requires separate grant) |
| `MCP.WriteConfidential` | Application | Write caucus-channel content (requires separate grant) |

Source: `eeoc-ofs-adr/adr_webapp/routes/api_mcp.py:249,990` and
`eeoc-ofs-adr/adr_webapp/mcp_server.py:885`.

#### OFS Triage (`EEOC-OFS-Triage`)

| Role value | Type | Purpose |
|---|---|---|
| `MCP.Read` | Application | Read tools and case data via MCP |
| `MCP.Write` | Application | Submit and update cases via MCP |

Source: `eeoc-ofs-triage/triage_webapp/mcp_server.py` (validated by
`test_mcp_server.py:324`).

#### OGC Trial Tool (`EEOC-OGC-TrialTool`)

| Role value | Type | Purpose |
|---|---|---|
| `MCP.Read` | Application | Read case status and list tools |
| `MCP.Write` | Application | Invoke analysis tools |

Source: `eeoc-ogc-trialtool/tests/test_mcp_server.py:182,324`.

#### OCHCO Benefits Validation (`EEOC-OCHCO-Benefits`)

| Role value | Type | Purpose |
|---|---|---|
| `MCP.Read` | Application | Read validation tools (all current tools are read-only) |

Source: `eeoc-ochco-benefits-validation/app/routes/mcp.py:121`.

#### UDAP — AI Assistant (`EEOC-UDAP-Analytics`)

| Role value | Type | Purpose |
|---|---|---|
| `Analytics.Read` | Application | Read analytics tools, resources, and prompts |
| `Analytics.Write` | Application | Invoke ingest tools (tools whose names start with `ingest_`) |

UDAP uses `Analytics.*` roles, **not** `MCP.*`. This is intentional and must not be
changed without updating the UDAP MCP server.

Source: `eeoc-data-analytics-and-dashboard/ai-assistant/app/mcp_api.py:294` and
`mcp_server.py:782,885`.

#### ARC Integration API (`EEOC-ARC-Integration`)

| Role value | Type | Purpose |
|---|---|---|
| `ARC.Read` | Application | Read ARC data (cases, charges, reference data, documents) |
| `ARC.Write` | Application | Write back to ARC (mediation outcomes, triage results, documents) |
| `Access.Read` | Application | Read platform access grants |
| `Access.Admin` | Application | Create, update, and revoke platform access grants |

Source: `eeoc-arc-integration-api/app/auth/__init__.py:9-12`.

### 2.2 Exposer-vs-consumer summary

| Role | Exposed by | Consumed by |
|---|---|---|
| `MCP.Read` | ADR, Triage, OGC Trial Tool, OCHCO | MCP Hub managed identity |
| `MCP.Write` | ADR, Triage, OGC Trial Tool | MCP Hub managed identity |
| `MCP.ReadConfidential` | ADR only | MCP Hub managed identity (separate grant) |
| `MCP.WriteConfidential` | ADR only | MCP Hub managed identity (separate grant) |
| `Analytics.Read` | UDAP | MCP Hub managed identity |
| `Analytics.Write` | UDAP | MCP Hub managed identity (only if ingest tools are exercised) |
| `ARC.Read` | ARC Integration API | MCP Hub managed identity; ADR; Triage |
| `ARC.Write` | ARC Integration API | MCP Hub managed identity; ADR (write-back path) |
| `Access.Read` | ARC Integration API | Access Admin |
| `Access.Admin` | ARC Integration API | Access Admin |

---

## 3. MCP Hub Managed-Identity Grants

The MCP Hub uses `DefaultAzureCredential` (managed identity) to acquire spoke tokens.
It acquires a token scoped to `api://<spoke-client-id>/.default` and presents it as a
bearer token in the `Authorization` header.

For the Hub to call a spoke, the Hub's managed identity must hold the spoke's app role
on the spoke's app registration. This is an admin-consent application permission, not
a delegated permission.

**Steps (Azure Portal):**

1. Open the spoke's app registration.
2. **Expose an API** — confirm the `api://<spoke-client-id>` scope URI is set.
3. **App roles** — confirm the relevant roles are defined and enabled.
4. Navigate to **Enterprise Applications** → find the Hub's managed identity
   (`EEOC-MCP-Hub` managed identity or the identity backing `ca-mcp-hub-func`).
5. **Permissions** → **Add a permission** → **My APIs** → select the spoke →
   **Application permissions** → check the required role → **Add**.
6. **Grant admin consent**.

Required grants for the Hub managed identity:

| Spoke registration | Roles to grant |
|---|---|
| `EEOC-ADR-Mediation` | `MCP.Read`, `MCP.Write` |
| `EEOC-OFS-Triage` | `MCP.Read`, `MCP.Write` |
| `EEOC-OGC-TrialTool` | `MCP.Read`, `MCP.Write` |
| `EEOC-OCHCO-Benefits` | `MCP.Read` |
| `EEOC-UDAP-Analytics` | `Analytics.Read`, `Analytics.Write` |
| `EEOC-ARC-Integration` | `ARC.Read`, `ARC.Write` |

> `MCP.ReadConfidential` and `MCP.WriteConfidential` (ADR caucus channels) are not
> granted to the Hub by default. Grant them only after an explicit policy review —
> caucus content is attorney-client-privileged.

The Hub's `get_m2m_token(scope)` function in
`eeoc-mcp-hub-functions/hub_functions/auth.py` calls
`DefaultAzureCredential().get_token(scope)` at spoke-call time. The managed identity
must be attached to the Hub compute resource (Container App or AKS workload identity).

**Spoke scope pattern:** `api://<spoke-app-client-id>/.default`

The scope is stored per-spoke in the Hub's spoke registry table (`mcpspokes` in Azure
Table Storage), not as a static env var. Update the registry row when a spoke
registration is re-created.

---

## 4. Tenant, Domain, and Security-Group Restriction Layers

Entra ID access is enforced at three sequential layers for every component that serves
interactive (browser) users.

### Layer 1 — Tenant

The MSAL `authority` URL is bound to the EEOC tenant ID:

```
https://login.microsoftonline.com/<EEOC-tenant-id>
```

Users from any other Entra tenant cannot authenticate against this authority. The
tenant ID is injected via `AAD_AUTHORITY` (ADR, Triage) or `AZURE_TENANT_ID`
(Access Admin, ARC Integration API).

### Layer 2 — Domain routing

Components that serve both EEOC staff and external parties (ADR, Triage) route only
`@eeoc.gov` email addresses to Entra ID. All other domains route to Login.gov.

```python
# adr_webapp/auth/provider_router.py
ENTRA_DOMAINS = frozenset(["eeoc.gov"])
```

This is a code-level constant, not a runtime flag. Adding a new agency domain requires
a code change and redeployment (intentional review gate).

Components that serve only EEOC staff (Access Admin, OGC Trial Tool) do not implement
Login.gov and skip this layer.

### Layer 3 — Security group membership

After token exchange, the application calls the Graph API `checkMemberGroups` endpoint
to confirm the user belongs to an authorized security group. Users who authenticate
successfully but are in neither group receive the lowest-privilege role or are denied.

| Component | Groups checked | Source (Key Vault secret name) |
|---|---|---|
| ADR Portal | Admin group, Mediator group | `ADMIN-GROUP-ID`, `MEDIATOR-GROUP-ID` |
| Triage | Admin group, Triage users group | `ADMIN-USERS-GROUP-ID`, `TRIAGE-USERS-GROUP-ID` |
| Access Admin | Access Admin group(s) | `ACCESS_ADMIN_GROUP_IDS` (env var, comma-separated OIDs) |

Graph endpoint: `https://graph.microsoft.com/v1.0` (Azure Commercial — never `.us`).

### Dual-IdP split

| User population | Identity provider | Protocol |
|---|---|---|
| `@eeoc.gov` employees | Entra ID | OIDC authorization code, MSAL confidential client |
| External parties (complainants, attorneys, agency reps) | Login.gov | OIDC + PKCE + `private_key_jwt` |

Components that are MCP spokes only (OCHCO, ARC Integration API) serve no browser
users. They accept only Entra ID M2M bearer tokens — no interactive OIDC flow is
implemented.

---

## 5. Per-Component Key Vault Secrets and Workload Identity

All secrets are stored in Azure Key Vault. No secrets appear in code, ConfigMaps, or
container images. The CSI Secrets Store driver mounts secrets into pods and syncs them
to Kubernetes Secrets consumed via `envFrom`.

Key Vault name (common to all components unless overridden): `eeoc-platform-kv`
UDAP uses a separate vault: `kv-udap-prod` (see UDAP section below).

### 5.1 ADR Portal

**SecretProviderClass:** not present in `eeoc-ofs-adr/deploy/` (secrets loaded at
runtime by `mediation_app.py` via `SecretClient`).

| Key Vault secret name | Loaded as | Purpose |
|---|---|---|
| `FLASK-SECRET-KEY` | `SECRET_KEY` | Flask session signing |
| `AAD-CLIENT-ID` | `CLIENT_ID` | Entra app registration client ID |
| `AAD-CLIENT-SECRET` | `CLIENT_SECRET` | Entra app registration client secret |
| `MEDIATOR-GROUP-ID` | `MEDIATOR_GROUP_ID` | Entra security group for mediator role |
| `ADMIN-GROUP-ID` | `ADMIN_GROUP_ID` | Entra security group for admin role |
| `STATS-ADMIN-GROUP-ID` | `STATS_ADMIN_GROUP_ID` | Entra security group for stats admin role |
| `REDIS-HOST` | `redis_host` | Redis hostname |
| `REDIS-PASSWORD` | `redis_password` | Redis auth password |
| `Stats-API-Key` | `STATS_API_KEY` | Statistics API key |
| `STATS-HASH-SALT` | `STATS_HASH_SALT` | Salt for PII hashing |

Source: `eeoc-ofs-adr/adr_webapp/mediation_app.py:679-733`.

Env vars set in ConfigMap (not secrets): `ARC_INTEGRATION_API_URL`,
`ARC_INTEGRATION_API_SCOPE`, `MCP_ENABLED`, `MCP_PROTOCOL_ENABLED`.

Source: `eeoc-ofs-adr/deploy/k8s/adr-webapp/configmap.yaml`.

### 5.2 OFS Triage

**SecretProviderClass:** not present in `eeoc-ofs-triage/deploy/` (runtime `SecretClient` load).

| Key Vault secret name | Purpose |
|---|---|
| `FLASK-SECRET-KEY` | Flask session signing |
| `AAD-CLIENT-ID` | Entra app registration client ID |
| `AAD-CLIENT-SECRET` | Entra app registration client secret |
| `TRIAGE-USERS-GROUP-ID` | Entra security group for triage users |
| `ADMIN-USERS-GROUP-ID` | Entra security group for admin users |
| `STATS-ADMIN-GROUP-ID` | Entra security group for stats admins |
| `Stats-API-Key` | Statistics API key |
| `STATS-HASH-SALT` | Salt for PII hashing |

Source: `eeoc-ofs-triage/triage_webapp/triage_app.py:132-164`.

MCP webhook secret (loaded only when `MCP_ENABLED=true`): loaded from Key Vault at
`triage_webapp/triage_app.py:246`.

### 5.3 UDAP — AI Assistant

**SecretProviderClass:** `eeoc-data-analytics-and-dashboard/deploy/k8s/ai-assistant/secret-provider.yaml`
**SecretProviderClass name:** `ai-assistant-secrets-provider` (namespace: `udap`)
**Key Vault name:** `kv-udap-prod`
**Workload identity:** `useVMManagedIdentity: "true"` with
`userAssignedIdentityID: REPLACE_WITH_MANAGED_IDENTITY_CLIENT_ID`

| Key Vault secret (objectName) | Kubernetes secret key | Purpose |
|---|---|---|
| `OPENAI-API-KEY` | `openai-api-key` | Azure OpenAI API key |
| `FLASK-SECRET-KEY` | `flask-secret-key` | Flask session signing |
| `DB-PASSWORD` | `db-password` | PostgreSQL database password |
| `AI-AUDIT-HMAC-KEY` | `ai-audit-hmac-key` | HMAC key for AI audit record signing (NARA AU-10) |
| `PII-HASH-SALT` | `pii-hash-salt` | Salt for PII hashing before logging |
| `UDAP-PG-AI-CONNECTION` | `pg-ai-connection` | PostgreSQL connection string for AI schema |
| `UDAP-PG-ENTERPRISE-CONNECTION` | `pg-enterprise-connection` | PostgreSQL connection string for enterprise schema |
| `REDIS-URL` | `redis-url` | Redis connection string |

Source: `eeoc-data-analytics-and-dashboard/deploy/k8s/ai-assistant/secret-provider.yaml`.

### 5.4 ARC Integration API

**SecretProviderClass:** not present in `eeoc-arc-integration-api/deploy/` (env-based
via `pydantic_settings.BaseSettings` in `app/config/__init__.py`).

| Config field | Env var | Purpose |
|---|---|---|
| `azure_tenant_id` | `AZURE_TENANT_ID` | Entra tenant ID for JWKS validation |
| `azure_client_id` | `AZURE_CLIENT_ID` | App registration audience claim |
| `arc_client_secret` | `ARC_CLIENT_SECRET` | ARC backbone client secret (Key Vault in prod) |
| `arc_audit_hmac_key` | `ARC_AUDIT_HMAC_KEY` | HMAC key for audit record signing |
| `azure_storage_connection_string` | `AZURE_STORAGE_CONNECTION_STRING` | Audit table storage |
| `redis_url` | `REDIS_URL` | Redis connection string |
| `mcp_hub_hmac_secret` | `MCP_HUB_HMAC_SECRET` | HMAC key for MCP Hub webhook validation |

Source: `eeoc-arc-integration-api/app/config/__init__.py`.

Audit table: `arcintegrationaudit`. Archive container: `arc-integration-archive`.
Both are set in `eeoc-arc-integration-api/deploy/k8s/arc-integration/configmap.yaml`.

### 5.5 OCHCO Benefits Validation

**SecretProviderClass:** `eeoc-ochco-benefits-validation/deploy/k8s/ochco/secretproviderclass.yaml`
**SecretProviderClass name:** `ochco-benefits-keyvault-secrets` (namespace: `eeoc-ochco`)
**Key Vault name:** `eeoc-platform-kv`
**Cloud:** `AzurePublicCloud` (Azure Commercial)
**Workload identity:** `clientID: OCHCO_MANAGED_IDENTITY_CLIENT_ID`

| Key Vault secret (objectName) | Kubernetes secret key | Purpose |
|---|---|---|
| `benefits-secret-key` | `SECRET_KEY` | Flask session signing |
| `benefits-azure-client-secret` | `AZURE_CLIENT_SECRET` | Entra app registration client secret |
| `benefits-ai-hmac-key` | `AI_AUDIT_HMAC_KEY` | HMAC key for AI audit record signing |
| `benefits-storage-connection` | `AZURE_STORAGE_CONNECTION` | Audit table storage connection |

Additional secrets loaded at runtime via `Config.load_key_vault_secrets()`:
`benefits-nfc-connection`, `benefits-ai-hmac-key` (override). These are not duplicated
in the CSI mount.

Source: `eeoc-ochco-benefits-validation/deploy/k8s/ochco/secretproviderclass.yaml`.

### 5.6 Access Admin

**SecretProviderClass:** `eeoc-access-admin/deploy/k8s/access-admin/secretproviderclass.yaml`
**SecretProviderClass name:** `access-admin-keyvault-secrets` (namespace: `eeoc-access-admin`)
**Key Vault name:** `eeoc-platform-kv`
**Cloud:** `AzurePublicCloud` (Azure Commercial)
**Workload identity:** `clientID: ACCESS_ADMIN_MANAGED_IDENTITY_CLIENT_ID`

| Key Vault secret (objectName) | Kubernetes secret key | Purpose |
|---|---|---|
| `access-admin-secret-key` | `SECRET_KEY` | Flask session signing |
| `access-admin-azure-client-secret` | `AZURE_CLIENT_SECRET` | Entra app registration client secret |
| `access-admin-arc-api-client-secret` | `ARC_API_CLIENT_SECRET` | M2M secret for calling ARC Integration API |

Additional env vars (not in CSI, set in deployment or ConfigMap):
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `ARC_API_BASE_URL`, `ARC_API_CLIENT_ID`,
`ARC_API_SCOPE`, `REDIS_URL`, `ACCESS_ADMIN_GROUP_IDS`.

Source: `eeoc-access-admin/deploy/k8s/access-admin/secretproviderclass.yaml` and
`eeoc-access-admin/access_admin/config.py`.

### 5.7 MCP Hub

**SecretProviderClass:** none found in `eeoc-mcp-hub-functions/` (env-var based).

| Env var | Purpose |
|---|---|
| `HUB_AUDIT_HMAC_KEY` | HMAC key for audit record signing — Hub fails closed without this |
| `AZURE_STORAGE_CONNECTION_STRING` | Audit table storage |
| `REDIS_URL` | Redis for tool catalog caching |
| `KEY_VAULT_URI` | Key Vault URI for runtime secret access |

Source: `eeoc-mcp-hub-functions/hub_functions/config.py`.

The Hub does not hold a client secret for spoke calls. It uses `DefaultAzureCredential`
(managed identity) — see Section 3.

---

## 6. Attestation

- [x] All endpoints use `https://login.microsoftonline.com` (Azure Commercial). No `.us` or GCC-High authority appears.
- [x] All Graph calls use `https://graph.microsoft.com/v1.0` (Azure Commercial).
- [x] No client secret, tenant ID, or group OID is hardcoded. All come from Key Vault or env vars at deploy time.
- [x] UDAP uses `Analytics.*` roles, not `MCP.*`. This distinction is enforced in code.
- [x] `MCP_ENABLED` and `MCP_PROTOCOL_ENABLED` default to `false` platform-wide.
- [x] ADR caucus roles (`MCP.ReadConfidential`, `MCP.WriteConfidential`) require a separate admin-consent grant.

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial release — consolidates Entra config from three prior docs |
| 1.1 | June 2026 | Derek Gordon / OIT | Add `Analytics.Write` to UDAP Hub grant (ingest tools require it per `mcp_api.py:385`); remove Access Admin from `ARC.Read` consumers (calls only `/arc/v1/access/` endpoints); correct Client-ID env var column for OCHCO and Access Admin (both use `AZURE_CLIENT_ID`, not a KV secret name) |
