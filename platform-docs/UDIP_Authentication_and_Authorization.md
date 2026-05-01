# EEOC UDIP — Authentication and Authorization

**Author:** Derek Gordon

## Authentication Flow

UDIP uses a **consolidated gateway authentication** pattern. A single OIDC login occurs at the portal-nginx level via the AI Assistant's Entra ID integration. All downstream services (Superset, JupyterHub) receive pre-authenticated identity through `X-UDIP-*` HTTP headers — they do not perform their own OAuth flows.

**Code Reference:** `ai-assistant/app/auth.py`, `deploy/k8s/portal-nginx/nginx.conf`

### Gateway Authentication Pattern

Portal-nginx uses the `auth_request` directive to call the AI Assistant's `/auth/verify` endpoint on every inbound request. If the user has a valid session, `/auth/verify` returns HTTP 200 and sets response headers (`X-UDIP-User`, `X-UDIP-Role`, `X-UDIP-Regions`, `X-UDIP-Office`, `X-UDIP-PII-Tier`, `X-UDIP-Permitted-Schemas`). Nginx forwards these headers to the upstream service. If the user is not authenticated, `/auth/verify` returns HTTP 401 and nginx redirects to `/auth/login`.

Only **one Entra ID app registration** is required (the AI Assistant's `AZURE_CLIENT_ID`). Superset and JupyterHub no longer need their own client IDs or secrets.

**Security:** Nginx strips any client-supplied `X-UDIP-*` headers before invoking `auth_request`. The headers are only set from the `/auth/verify` response, preventing spoofing.

### Step-by-Step Flow

1. **User visits UDIP** → portal-nginx invokes `auth_request` to `/auth/verify`
2. `/auth/verify` checks for a valid Flask session in Redis
3. If no valid session → nginx redirects to `/auth/login`
4. `/auth/login` builds MSAL `ConfidentialClientApplication` with tenant ID, client ID, and client secret from Key Vault (`auth.py` — MSAL `ConfidentialClientApplication` setup)
5. MSAL generates authorization URL with `openid`, `profile`, `email`, `offline_access` scopes and a random `state` parameter for CSRF protection (`auth.py` — authorization URL generation)
6. **User authenticates** at `login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize`
7. **Entra ID callback** → `/auth/callback` with authorization code
8. UDIP validates `state` parameter to prevent CSRF (`auth.py` — `state` parameter CSRF validation)
9. Exchanges authorization code for tokens via `acquire_token_by_authorization_code` (`auth.py` — `acquire_token_by_authorization_code`)
10. Extracts user claims from ID token: `preferred_username`, `name`, `email`, `groups` (`auth.py` — ID token claim extraction)
11. Resolves user attributes from group memberships:
    - Role via `_resolve_role()` — priority chain lookup
    - Regions via `_resolve_regions()` — UDIP-Data-Region-* prefix matching
    - Office via `_resolve_office()` — UDIP-Office-* prefix matching (EEOC office assignment)
    - PII tier via `_resolve_pii_tier()` — tier group membership
    - Permitted schemas via `_resolve_permitted_schemas()` — governed view catalog
12. Creates `UDIPUser` object and stores in Redis server-side session (`auth.py` — `UDIPUser` object creation)
13. Redirects to requested page or chat index
14. **Subsequent requests:** `/auth/verify` returns `X-UDIP-*` headers from the session, and nginx forwards them to the target service

### Downstream Service Authentication

| Service | Auth Method | How It Receives Identity |
|---------|-----------|--------------------------|
| AI Assistant | Direct session (Flask-Login) | Reads `UDIPUser` from Redis session |
| Superset | `AUTH_REMOTE_USER` | Reads `X-UDIP-User`, `X-UDIP-Role` headers set by nginx from `/auth/verify` |
| JupyterHub | `UDIPHeaderAuthenticator` | Reads `X-UDIP-User`, `X-UDIP-Role`, `X-UDIP-Regions` headers set by nginx from `/auth/verify` |

### Logout

`/auth/logout` clears the Redis session, calls Flask-Login `logout_user()`, and redirects to Entra ID's federated logout endpoint (`auth.py` — logout flow).

---

## Role Mapping

UDIP defines five roles with a strict priority chain. Users receive the highest-privilege role from their Entra ID group memberships.

**Code Reference:** `ai-assistant/app/auth.py` — `_resolve_role()`

### Priority Chain

```
Admin > Director > LegalCounsel > Analyst > Viewer
```

### Role Configuration

| Role | Config Variable | Entra ID Group |
|------|----------------|---------------|
| Admin | `ENTRA_GROUP_ADMINS` | UDIP-Admins |
| Director | `ENTRA_GROUP_DIRECTORS` | UDIP-Directors |
| LegalCounsel | `ENTRA_GROUP_LEGAL_COUNSEL` | UDIP-LegalCounsel |
| Analyst | `ENTRA_GROUP_ANALYSTS` | UDIP-Analysts |
| Viewer | `ENTRA_GROUP_VIEWERS` | UDIP-Viewers |

The `_resolve_role()` function iterates the priority list and returns the first match. If no group matches and `ENTRA_GROUP_VIEWERS` is not configured, the user is denied access (HTTP 403).

### Entra Group Overage Handling (NIST 800-53 AC-3)

When a user belongs to more than 200 Entra ID groups, the ID token omits inline `groups` claims and instead emits overage indicators:

- `_claim_names: { "groups": "src1" }` — standard overage pattern
- `hasgroups: true` — alternative boolean indicator

**Code Reference:** `ai-assistant/app/auth.py` — `_fetch_groups_from_graph()`

When overage is detected, the AI Assistant auth callback falls back to the Microsoft Graph API (`/v1.0/me/memberOf/microsoft.graph.group`) to retrieve the full group membership list. This keeps authorization decisions accurate regardless of group count.

| Component | Overage Handling |
|-----------|-----------------|
| AI Assistant | Graph API fallback via `_fetch_groups_from_graph()` with SSRF validation |
| Superset | Receives pre-resolved role via `X-UDIP-Role` header (overage handled at gateway) |
| JupyterHub | Receives pre-resolved attributes via `X-UDIP-*` headers (overage handled at gateway) |

GCC-High environments use `graph.microsoft.us` instead of `graph.microsoft.com` (configured via `AZURE_CLOUD` environment variable).

### Role Permissions

| Capability | Admin | Director | LegalCounsel | Analyst | Viewer |
|-----------|-------|----------|-------------|---------|--------|
| AI chat queries | Yes | Yes | Yes | Yes | No |
| Narrative search | Yes | Yes | Yes | Yes | No |
| View dashboards | Yes | Yes | Yes | Yes | Yes |
| Export data | Yes | Yes | Yes | No | No |
| Admin functions | Yes | No | No | No | No |

---

## Region Mapping

UDIP restricts data access by EEOC region via Entra ID group membership.

**Code Reference:** `ai-assistant/app/auth.py` — `_resolve_regions()`

### Group Naming Convention

Groups use the `UDIP-Data-Region-` prefix (configurable via `ENTRA_REGION_GROUP_PREFIX`):

| Entra ID Group | Region |
|----------------|--------|
| `UDIP-Data-Region-Southeast` | Southeast |
| `UDIP-Data-Region-Northeast` | Northeast |
| `UDIP-Data-Region-Midwest` | Midwest |
| `UDIP-Data-Region-Southwest` | Southwest |
| `UDIP-Data-Region-West` | West |
| `UDIP-Data-Region-National` | National (all regions) |

The `_resolve_regions()` function extracts region names by stripping the prefix from matching group display names. Regions are sorted alphabetically and stored in the session as `user_regions`.

### Region Enforcement

Regions are passed to `SESSION_CONTEXT` as a comma-separated list and enforced by RLS predicate functions at the database layer.

---

## PII Tier Mapping

UDIP implements three PII access tiers.

**Code Reference:** `ai-assistant/app/auth.py` — `_resolve_pii_tier()`

| Tier | Access Level | Entra ID Group | Views Available |
|------|-------------|---------------|-----------------|
| Tier 1 (default) | Aggregates only | No group required | Summary/aggregate views only |
| Tier 2 | De-identified records | `ENTRA_GROUP_PII_TIER2` | De-identified detail views |
| Tier 3 | Full PII | `ENTRA_GROUP_PII_TIER3` | All views including PII columns |

The `_resolve_pii_tier()` function checks Tier 3 first, then Tier 2. If neither group matches, the user defaults to Tier 1.

---

## SESSION_CONTEXT Enforcement

Every database connection sets SQL Server `SESSION_CONTEXT` with the authenticated user's attributes.

**Code Reference:** `ai-assistant/app/data_access.py` — `set_session_context()`

### Context Keys

| Key | Value Source | Read-Only |
|-----|------------|-----------|
| `user_id` | `current_user.username` | Yes (`@read_only = 1`) |
| `user_role` | `current_user.user_role` | Yes |
| `pii_tier` | `current_user.pii_tier` (as string) | Yes |
| `user_regions` | Comma-separated `current_user.user_regions` | Yes |
| `user_office` | `current_user.user_office` | Yes |

All values are set with `@read_only = 1` to prevent modification by application-layer SQL. This is enforced on every connection checkout via SQLAlchemy's `checkout` event listener (`data_access.py` — SQLAlchemy `checkout` event listener).

PostgreSQL equivalent session variables are also set via `set_config()` with `is_local=true`:

| GUC Variable | Value Source |
|-------------|------------|
| `app.current_user_id` | `current_user.username` |
| `app.current_role` | `current_user.user_role` |
| `app.current_regions` | Comma-separated `current_user.user_regions` |
| `app.current_office` | `current_user.user_office` |
| `app.current_pii_tier` | `current_user.pii_tier` (as string) |

### How RLS Uses SESSION_CONTEXT

RLS predicate functions in `analytics-db/rls/predicate-functions.sql` read `SESSION_CONTEXT` to filter rows:

- **Region filter:** Only return rows where the record's region matches one of the user's permitted regions
- **Office filter:** Only return rows where the record's `office_code` matches the user's assigned EEOC office (Admin/Director/LegalCounsel bypass)
- **PII tier filter:** Only expose PII columns when the user's tier meets the column's classification level
- **Role filter:** Restrict certain views to specific roles

---

## RLS Policy Descriptions

**Code Reference:** `analytics-db/rls/security-policies.sql`

| Policy | Target View | Filter Logic |
|--------|------------|-------------|
| Region filter | All charge/case views | `region IN (user_regions)` or user has National region |
| PII tier filter | Views with PII columns | Tier 1: aggregates only. Tier 2: de-identified. Tier 3: full PII. |
| Small cell suppression | Aggregate views | Suppress counts < 10 for Tier 1 users to prevent re-identification |

---

## Authorization Decorators

**Code Reference:** `ai-assistant/app/auth.py` — `@require_role`, `@require_min_tier`, `@require_analyst` decorators

### @require_role

Restricts route access to users with one of the specified roles.

```python
@require_role(['Admin', 'Analyst'])
def my_view():
    ...
```

Behavior: unauthenticated users are redirected to login. Authenticated users without a matching role receive HTTP 403. All denials are audit-logged with `AUDIT|AUTH|ROLE_DENIED`.

### @require_min_tier

Restricts route access to users with at least the specified PII tier.

```python
@require_min_tier(2)
def pii_route():
    ...
```

Behavior: users below the required tier receive HTTP 403. Logged as `AUDIT|AUTH|TIER_DENIED`.

### @require_analyst

Legacy decorator that requires any authenticated user with a valid role. Equivalent to `@require_role(ALL_ROLES)`.

---

## Session Management

**Code Reference:** `ai-assistant/app/config.py:25-37`, `ai-assistant/app/auth.py` — session cookie configuration

| Setting | Value | Code Reference |
|---------|-------|---------------|
| Session type | Redis (server-side) | `config.py:32` |
| Redis connection | TLS on port 6380 (`rediss://`) | `config.py:37` |
| Session lifetime | 30 minutes | `config.py:34` — `PERMANENT_SESSION_LIFETIME = 1800` |
| Session permanent | True (enables lifetime enforcement) | `config.py:33` |
| Key prefix | `udip:session:` | `config.py:35` |
| Signed cookies | Yes | `config.py:36` — `SESSION_USE_SIGNER = True` |
| Cookie secure | True (HTTPS only) | `config.py:26` |
| Cookie HttpOnly | True (no JavaScript access) | `config.py:27` |
| Cookie SameSite | Lax | `config.py:29` |

The 30-minute session lifetime aligns with NIST 800-53 AC-12 (Session Termination) requirements.

---

## Rate Limiting (NIST 800-53 SC-5)

UDIP enforces rate limiting at two layers:

### Edge Layer (NGINX)

**Code Reference:** `deploy/k8s/portal-nginx/nginx.conf`

| Zone | Rate | Burst |
|------|------|-------|
| Portal (`/`, `/dashboards/`, `/notebooks/`) | 30 requests/min per IP | 10-20 |
| AI Assistant (`/ai/`) | 20 requests/min per IP | 5 |

### Application Layer (Flask-Limiter)

**Code Reference:** `ai-assistant/app/__init__.py`

Flask-Limiter is initialized in the app factory with per-user keys:

| Setting | Value | Source |
|---------|-------|--------|
| Default limit | 20 requests/min | `RATE_LIMIT_PER_MINUTE` config |
| Key function | Authenticated user ID, fallback to IP | `_rate_limit_key()` |
| Storage backend | Redis (configurable) | `RATELIMIT_STORAGE_URI` config |
| Strategy | Fixed window | `strategy="fixed-window"` |

---

## Superset Account Provisioning (NIST 800-53 AC-2)

**Code Reference:** `deploy/docker/superset/superset_config.py`, `deploy/docker/superset/custom_security.py`

Superset uses `AUTH_REMOTE_USER` mode with auto-registration. Authentication is handled at the portal gateway — Superset receives the authenticated user's identity via `X-UDIP-*` headers forwarded by nginx from the AI Assistant's `/auth/verify` endpoint.

| Setting | Value | Purpose |
|---------|-------|---------|
| `AUTH_TYPE` | `AUTH_REMOTE_USER` | Trust pre-authenticated identity from gateway headers |
| `AUTH_USER_REGISTRATION` | `True` | Allows first-login provisioning |
| `AUTH_USER_REGISTRATION_ROLE` | `Public` | No-access default role |
| `AUTH_ROLES_SYNC_AT_LOGIN` | `True` | Updates roles from `X-UDIP-Role` header on every request |

Superset reads `X-UDIP-User` for the username and `X-UDIP-Role` for role mapping. Users whose role does not map to a Superset role receive the `Public` role, which has no dashboard or dataset access. Superset no longer requires its own `AZURE_CLIENT_ID` or `AZURE_CLIENT_SECRET`. This satisfies AC-2 account management requirements without requiring manual provisioning.

---

## Document Control

| Attribute | Value |
|-----------|-------|
| **Version** | 2.0 |
| **Created** | March 2026 |
| **Author** | EEOC OCIO |
| **Classification** | CUI // SP-UDIP |
| **Review Cycle** | Quarterly |
| **Next Review** | June 2026 |

---

## Unified Access Control (Cross-Application)

### Overview

UDIP serves as the centralized access management hub for all EEOC user-facing
applications. The admin interface at `/admin` → Applications tab allows
authorized administrators to assign app-level roles without requiring Entra ID
group modifications or IT tickets.

**Code Reference:** `ai-assistant/app/access_api.py`, `ai-assistant/app/access_store.py`

### Architecture

```
┌──────────────┐     ┌──────────────────────┐     ┌──────────────┐
│  ADR Portal  │     │  UDIP Access Store    │     │  Admin UX    │
│  Triage      │────▶│  /api/v1/access/check │◀────│  /admin      │
│  Trial Tool  │     │  (M2M bearer auth)    │     │  (browser)   │
│  Benefits    │     └──────────────────────┘     └──────────────┘
└──────────────┘
      ↑ login time, 2s timeout, fallback to Entra-only
```

### Grant Model

App grants use the `app` grant type with value format `app:<app_name>:<role>`:

| Example Grant Value | Meaning |
|---|---|
| `app:adr:supervisor` | User has Supervisor role in ADR Portal |
| `app:triage:admin` | User has Admin role in Triage |
| `app:trialtool:attorney` | User has Attorney role in Trial Tool |
| `app:benefits:benefits_manager` | User has Manager role in Benefits Validation |

### Access Check API

**Endpoint:** `GET /api/v1/access/check`

| Parameter | Required | Description |
|---|---|---|
| `user_email` | Yes | User's email address |
| `app` | Yes | Application identifier (adr, triage, trialtool, benefits) |

**Auth:** M2M bearer token with `Access.Read` app role.

**Response:**
```json
{"user_email_hash": "sha256...", "app": "adr", "roles": ["supervisor", "mediator"], "granted": true}
```

### Feature Flag

All consuming apps use `UNIFIED_ACCESS_ENABLED=false` by default. When enabled:

1. App resolves roles from Entra ID groups (existing behavior)
2. App calls UDIP `/api/v1/access/check` with user email and app name
3. Response roles are merged with Entra-derived roles (dual-authority)
4. If API call fails (timeout, 5xx, network): Entra-only, warning logged

### Migration Phases

| Phase | State | Admin Workflow |
|---|---|---|
| 1. Import | Flag off | Run `scripts/import_entra_grants.py` to seed UDIP with Entra data |
| 2. Dual-authority | Flag on | Both Entra groups and UDIP grants active (union) |
| 3. Cutover | Flag on, Entra frozen | UDIP is source of truth; Entra simplified to auth-only |

### Available App Roles

| Application | Roles |
|---|---|
| ADR Portal | admin, supervisor, attorney, coordinator, mediator, intake_coordinator |
| Triage | admin, user |
| Trial Tool | admin, attorney |
| Benefits | benefits_specialist, benefits_manager, benefits_readonly |

### Env Vars (Consuming Apps)

| Variable | Default | Description |
|---|---|---|
| `UNIFIED_ACCESS_ENABLED` | `false` | Enable/disable unified access check |
| `UNIFIED_ACCESS_URL` | (empty) | UDIP access check endpoint URL |
| `UNIFIED_ACCESS_CLIENT_ID` | (empty) | M2M client ID for token acquisition |
| `UNIFIED_ACCESS_CLIENT_SECRET` | (empty) | M2M client secret (Key Vault) |
| `UNIFIED_ACCESS_TIMEOUT` | `2.0` | Timeout in seconds for API call |

---

**END OF DOCUMENT**
