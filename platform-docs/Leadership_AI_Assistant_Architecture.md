# Leadership AI Assistant — Functional Architecture

**Author:** Derek Gordon

## EEOC Unified Data Intelligence Portal (UDIP)

---

## 1. Overview

This document defines the functional architecture for the UDIP Leadership AI Assistant:
a conversational interface that allows authorized staff to ask complex questions across
all integrated data domains (case production, HR, financial, organizational), receive
answers as prose, charts, or data tables, and build persistent personal dashboards
from query results.

### 1.1 Design Constraints

| Constraint | Requirement |
|---|---|
| **User scale** | Up to 2,500 concurrent staff users |
| **Data domains** | Extensible — HR, Financial, Production, ADR, Triage, Hearings, future |
| **RBAC** | Row-level security per domain, enforced at query time |
| **508 compliance** | All generated UI meets WCAG 2.1 AA out of the box |
| **Dashboards** | Personal CRUD, sharing between colleagues, stable UX |
| **Audit** | Every AI query logged with HMAC signature, 7-year WORM retention |
| **Auth** | Entra ID OIDC, server-side Redis sessions |

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LEADERSHIP AI ASSISTANT                              │
│                                                                             │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────┐  │
│  │  Conversational  │    │  Dashboard        │    │  Data Domain         │  │
│  │  Query Engine    │    │  Manager          │    │  Registry            │  │
│  │  (NL → SQL)     │    │  (CRUD + Share)   │    │  (Schema Catalog)    │  │
│  └────────┬─────────┘    └────────┬──────────┘    └──────────┬───────────┘  │
│           │                       │                          │              │
│           └───────────────────────┼──────────────────────────┘              │
│                                   │                                         │
│                    ┌──────────────┴──────────────┐                          │
│                    │  Governed Query Executor     │                          │
│                    │  (RLS + Domain Predicates)   │                          │
│                    └──────────────┬──────────────┘                          │
│                                   │                                         │
└───────────────────────────────────┼─────────────────────────────────────────┘
                                    │
┌───────────────────────────────────┼─────────────────────────────────────────┐
│                        DATA PLATFORM LAYER                                   │
│                                   │                                          │
│  ┌────────────┐  ┌────────────┐  │  ┌────────────┐  ┌────────────────────┐ │
│  │ Production │  │ HR Domain  │  │  │ Financial  │  │ Future Domains     │ │
│  │ (Charges,  │  │ (Staff,    │  │  │ (Budget,   │  │ (OIG, Training,    │ │
│  │  ADR,      │  │  Ratings,  │  │  │  Spend,    │  │  FOIA stats, ...)  │ │
│  │  Triage)   │  │  Org Chart)│  │  │  Contracts)│  │                    │ │
│  └─────┬──────┘  └─────┬──────┘  │  └─────┬──────┘  └─────┬──────────────┘ │
│        │                │         │        │                │               │
│        └────────────────┴─────────┴────────┴────────────────┘               │
│                                   │                                          │
│                    ┌──────────────┴──────────────┐                          │
│                    │  PostgreSQL (analytics)      │                          │
│                    │  + SQL Server (IMS/legacy)   │                          │
│                    └──────────────┬──────────────┘                          │
│                                   │                                          │
│                    ┌──────────────┴──────────────┐                          │
│                    │  Data Middleware Pipeline    │                          │
│                    │  (YAML Mappings → dbt → RLS)│                          │
│                    └─────────────────────────────┘                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Conversational Query Engine

### 3.1 Multi-Domain Query Resolution

The current NL-to-SQL pipeline handles single-domain queries. Cross-domain questions
(e.g., "production trend for staff rated 3 or below in the southwest region") require
joining across domain schemas. The engine must:

1. **Classify the query domains** — Identify which schemas are referenced (HR, production,
   financial, etc.) from the natural language input.
2. **Load domain-specific schema context** — Each domain publishes a schema descriptor
   (tables, columns, relationships, join keys) via the dbt semantic layer manifest.
3. **Generate cross-domain SQL** — When multiple domains are referenced, the model
   receives join metadata (shared keys like `staff_id`, `office_code`, `region_code`)
   and generates the appropriate JOINs.
4. **Validate and bound** — The existing `sql_validator.py` (sqlglot AST) validates the
   generated SQL. Cross-domain queries are additionally bounded by:
   - Maximum 3 JOINs per query (configurable)
   - Row limit enforcement (10,000 default)
   - Query timeout (20s)
   - Cost estimation before execution

### 3.2 Domain Schema Registry

Each data domain registers itself in a catalog that the query engine consumes:

```yaml
# domain_registry/hr.yaml
name: hr
display_name: "Human Resources & Staffing"
description: >
  Staff roster, performance ratings, organizational structure, and
  position history.
schema_prefix: "hr"
access_group: "UDIP-Domain-HR"

scope_columns:
  - column: "office_code"
    maps_to: "user_offices"
  - column: "region_code"
    maps_to: "user_regions"
  - column: "program"
    maps_to: "user_programs"

models:
  - fct_staff_production
  - dim_staff
  - dim_org_hierarchy
  - stg_hr_staff
  - stg_hr_ratings
  - stg_hr_org

rls_function: null  # uses injected WHERE clauses

allowed_joins:
  - target_domain: "production"
    join_columns:
      - local: "dim_staff.staff_id"
        foreign: "staff_assignments.staff_id"
      - local: "dim_staff.office_code"
        foreign: "charges.office_code"

default_grants:
  - role: "Admin"
    scopes: ["*"]
  - role: "Director"
    scopes: ["own_region"]
```

### 3.3 Multi-Turn Conversation

The AI assistant maintains session state to support follow-up queries:

- "Show me production by region" → generates chart
- "Filter that to just the southwest" → modifies prior SQL with WHERE predicate
- "Add performance ratings below 3" → joins HR domain, adds filter
- "Save this as a dashboard panel" → persists the final chart spec

Session state is stored server-side in Redis (existing infrastructure). Each
conversation tracks:
- Prior SQL queries (for modification)
- Active domain context (which schemas are in scope)
- Chart specs generated (for dashboard persistence)
- User's RBAC context (cached from login, refreshed per request)

---

## 4. RBAC and Data Access Control

### 4.1 EEOC Organizational Structure

The access model must account for the full EEOC office taxonomy. Each office has
distinct data ownership and cross-office visibility needs:

| Office | Full Name | Primary Data Ownership |
|---|---|---|
| **OFP** | Office of Field Programs | Private sector charges, investigations, mediations, field office production. 53 field offices organized by district → region fall under OFP. |
| **OFS** | Office of Federal Operations | Federal sector (appellate) cases, hearings decisions |
| **OGC** | Office of General Counsel | Litigation, systemic investigations, amicus briefs |
| **OLC** | Office of Legal Counsel | Legal policy, ethics, FOIA legal review, regulatory drafting |
| **OCHCO** | Office of Chief Human Capital Officer | Staff records, performance ratings, benefits, org assignments |
| **OCFO** | Office of Chief Financial Officer | Budget, obligations, expenditures, contracts, travel |
| **OCLA** | Office of Communications and Legislative Affairs | Congressional inquiries, press, external communications |
| **OCH** | Office of the Chair | Agency-wide oversight, strategic priorities, all-office visibility |
| **OCIO** | Office of Chief Information Officer | IT systems, infrastructure, service metrics |
| **Commissioners** | Individual Commissioners + staff | Policy oversight, case review, all-office visibility (scoped) |
| **OIG** | Office of Inspector General | Audits, investigations (separate authority) |

### 4.2 Access Model — Three Dimensions

Access is controlled across three independent axes. A user's effective permissions
are the intersection of all three:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     EFFECTIVE ACCESS = A ∩ B ∩ C                     │
│                                                                     │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ A. ROLE         │  │ B. DATA DOMAINS  │  │ C. SCOPE          │  │
│  │ (what actions)  │  │ (which datasets) │  │ (which rows)      │  │
│  │                 │  │                  │  │                   │  │
│  │ Admin           │  │ Production       │  │ Agency-wide       │  │
│  │ Director        │  │ HR               │  │ Region(s)         │  │
│  │ Legal Counsel   │  │ Financial        │  │ District(s)       │  │
│  │ Analyst         │  │ Legislative      │  │ Office(s)         │  │
│  │ Viewer          │  │ IT Operations    │  │ Program(s)        │  │
│  │                 │  │ (future...)      │  │                   │  │
│  └─────────────────┘  └──────────────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

**A. Role** — Determines capabilities (can query, can export, can share, can admin).
**B. Data Domains** — Determines which schemas/tables are queryable.
**C. Scope** — Determines which rows are visible within those tables (region, office, program).

### 4.3 Cross-Office Query Eligibility

The original query example — "24-month production trend for staff rated 3 or below
in the southwest region of OFP" — requires access to both Production and HR domains.
Multiple offices legitimately need this cross-reference:

| Requester | Why | Domains Needed | Scope |
|---|---|---|---|
| OFP District Director | Managing their investigators | Production + HR | Their district only |
| OFP Regional Director | Regional performance oversight | Production + HR | Their region |
| OCHCO Director | Agency-wide workforce analytics | HR + Production | Agency-wide |
| OCH / Chair staff | Strategic oversight of all programs | All domains | Agency-wide |
| Commissioner staff | Policy review, hearing oversight | Production + HR + OFS | Agency-wide (read) |
| OCFO leadership | Cost-per-case analysis | Financial + Production | Agency-wide |

The system does not hardcode these combinations. Instead, an administrator assigns
domain access and scope independently. The query engine enforces the intersection.

### 4.4 Access Assignment (Application-Managed)

Access is managed through UDIP's admin interface, **not** through direct Entra group
manipulation. The admin UX writes access grants to a persistent store (Azure Table
Storage), and the auth layer reads them at session creation time.

**Why not pure Entra groups?**

| Approach | Pros | Cons |
|---|---|---|
| Entra groups only | Standard, IT-managed | Requires IT ticket for every change; 50+ groups needed; no audit of who-granted-what; group sprawl |
| Application-managed grants backed by Entra auth | Self-service admin UX; full audit trail; fine-grained scope; instant changes | Requires admin interface build; must sync with Entra for base auth |

**Hybrid model:** Entra ID handles *authentication* (who is this person?) and *base role*
(Admin/Director/Analyst/Viewer/LegalCounsel via 5 Entra groups). The UDIP admin UX
handles *data access grants* (which domains, which scope).

```
┌──────────────────────────────────────────────────────────────────┐
│  Entra ID (IT-managed, stable)                                   │
│  ─────────────────────────────                                   │
│  • Authentication (OIDC)                                         │
│  • Base role: UDIP-Admins, UDIP-Directors, UDIP-Analysts, etc.  │
│  • Office membership: user's home office (from HR feed)          │
└──────────────────────────────────┬───────────────────────────────┘
                                   │ login
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│  UDIP Access Store (app-managed, admin UX)                       │
│  ─────────────────────────────────────────                       │
│  • Domain grants: which data domains this user can query         │
│  • Scope grants: which regions/offices/programs are visible      │
│  • PII tier: what level of detail is exposed                     │
│  • Effective permissions: computed at session creation            │
│  • Full audit log: who granted what, when, why                   │
└──────────────────────────────────────────────────────────────────┘
```

### 4.5 Access Grant Data Model

```
┌─────────────────────────────────────────────────────────────────────┐
│  Azure Table Storage: udip_access_grants                            │
│─────────────────────────────────────────────────────────────────────│
│  PartitionKey: SHA-256(user_id)                                     │
│  RowKey: grant_id (UUID)                                            │
│  Fields:                                                            │
│    ├── grant_type: "domain" | "scope" | "pii_tier"                  │
│    ├── value: "hr" | "financial" | "production" | "region:SW" | ... │
│    ├── granted_by: SHA-256(admin_user_id)                           │
│    ├── granted_at: ISO datetime                                     │
│    ├── expires_at: ISO datetime (null = permanent)                  │
│    ├── justification: str (required, auditable)                     │
│    └── active: boolean                                              │
│                                                                     │
│  Secondary view: by-domain (for "who has HR access?" queries)       │
│  PartitionKey: domain_name                                          │
│  RowKey: SHA-256(user_id)                                           │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.6 Admin UX — Access Management

The admin interface provides a single screen for managing user access. Designed for
daily use by OCHCO administrators, office directors, or delegated access managers.

**4.6.1 User Access View**

Search or browse users → see their complete access profile at a glance:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  User: Jane Smith (OFP Regional Director, Southeast)                    │
│  Base Role: Director (from Entra)       Home Office: OFP (from Entra)   │
│─────────────────────────────────────────────────────────────────────────│
│                                                                         │
│  DATA DOMAINS                          SCOPE                            │
│  ──────────────                        ─────                            │
│  ☑ Production (charges, ADR, triage)   Regions: Southeast, Southwest    │
│  ☑ HR (staff, ratings, org)            Offices: All within regions      │
│  ☐ Financial                           Programs: OFP, ADR               │
│  ☐ Legislative                                                          │
│  ☐ IT Operations                       PII TIER                         │
│                                        ────────                         │
│  [+ Add Domain]                        ● Tier 2 (de-identified)         │
│                                        ○ Tier 3 (full PII)              │
│                                                                         │
│  RECENT CHANGES                                                         │
│  ──────────────                                                         │
│  2026-04-15  HR domain added by Admin T. Williams                       │
│             Justification: "Regional performance review prep"           │
│  2026-03-01  Southwest region added by Admin T. Williams                │
│             Justification: "Acting director for SW during vacancy"      │
│                                                                         │
│  [Save Changes]  [Revoke All Non-Base]  [Export Audit Log]              │
└─────────────────────────────────────────────────────────────────────────┘
```

**4.6.2 Domain Access View**

Select a domain → see all users who have access, filter by office/role:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Domain: HR (Staff, Performance Ratings, Org Assignments)               │
│  Total users with access: 47                                            │
│─────────────────────────────────────────────────────────────────────────│
│                                                                         │
│  Filter: [All Offices ▼]  [All Roles ▼]  [Search name...]              │
│                                                                         │
│  Name              Office   Role      Scope         Granted By  Date    │
│  ─────────────────────────────────────────────────────────────────────  │
│  T. Williams       OCHCO    Admin     Agency-wide   System      —       │
│  J. Smith          OFP      Director  SE, SW        T. Williams 04/15   │
│  R. Chen           OCH      Director  Agency-wide   T. Williams 03/01   │
│  M. Johnson        OFP-ATL  Analyst   Atlanta only  J. Smith    04/20   │
│  ...                                                                    │
│                                                                         │
│  [+ Grant Access to User]  [Bulk Import from CSV]  [Export List]        │
└─────────────────────────────────────────────────────────────────────────┘
```

**4.6.3 Bulk Operations**

For onboarding new offices or reorganizations:
- **Grant domain to role** — "Give all Directors access to HR domain" (applies to
  existing and future users with that role)
- **Grant scope by office** — "All OFP staff can see Production data for their office"
- **Time-limited grants** — "Commissioner staff get Financial access through Sept 30
  for budget review" (auto-expires)
- **CSV import** — Upload a spreadsheet of user → domain → scope mappings

**4.6.4 Delegation**

Not all access management requires a system admin. Office directors can be delegated
authority to manage access within their scope:

| Delegated Role | Can Grant | Cannot Grant |
|---|---|---|
| Office Director (OFP) | Production domain, scoped to their region | HR, Financial, agency-wide scope |
| OCHCO Director | HR domain, any scope | Financial, Production |
| System Admin | Any domain, any scope | — |

Delegation rules are themselves stored as grants (grant_type: "delegation") and
are audited identically.

### 4.7 Effective Permissions Computation

At session creation (login), the system computes effective permissions by merging
Entra base role + application grants:

```python
def compute_effective_permissions(user: EntraUser) -> EffectiveAccess:
    base_role = resolve_role_from_entra_groups(user.groups)
    grants = load_grants(user.user_id)  # from udip_access_grants table

    return EffectiveAccess(
        role=base_role,
        domains=[g.value for g in grants if g.grant_type == "domain" and g.active],
        regions=[g.value for g in grants if g.grant_type == "scope" and g.value.startswith("region:")],
        offices=[g.value for g in grants if g.grant_type == "scope" and g.value.startswith("office:")],
        programs=[g.value for g in grants if g.grant_type == "scope" and g.value.startswith("program:")],
        pii_tier=max([g.value for g in grants if g.grant_type == "pii_tier"], default=1),
    )
```

Cached in Redis for the session duration (30 min). Changes by admins take effect
on the user's next login or session refresh.

### 4.8 RLS Predicate Injection

At query execution time, the engine injects WHERE clauses based on the user's
effective scope. Each domain registry declares which columns map to which scope
dimensions:

```python
def apply_rls(query: str, user: EffectiveAccess, domains: list[str]) -> str:
    for domain in domains:
        registry = load_domain_registry(domain)
        for table in registry.tables:
            for rls_col in table.rls_columns:
                if rls_col.maps_to == "user_regions" and user.regions:
                    # WHERE table.region_code IN ('SE', 'SW')
                    inject_predicate(query, table, rls_col.column, "IN", user.regions)
                elif rls_col.maps_to == "user_office" and user.offices:
                    inject_predicate(query, table, rls_col.column, "IN", user.offices)
                elif rls_col.maps_to == "user_programs" and user.programs:
                    inject_predicate(query, table, rls_col.column, "IN", user.programs)
            # Column masking for PII tier
            for col in table.columns:
                if col.pii_tier > user.pii_tier:
                    mask_column(query, table, col.name)
    return query
```

Users with agency-wide scope (OCH, Commissioners with full access) have no
region/office predicates injected — they see all rows within their granted domains.

### 4.9 PII Tier per Domain

Each domain declares PII classification at the column level:

| PII Tier | Visibility | Example |
|---|---|---|
| 1 (public) | Aggregate counts, region-level stats | "150 charges filed in SW region" |
| 2 (internal) | De-identified records, staff IDs without names | "Staff ID 4872 closed 23 cases" |
| 3 (restricted) | Full PII — names, SSN fragments, party details | "Jane Doe, SSN ***-**-1234" |

### 4.10 Access Audit Trail

Every grant, revocation, and delegation is logged immutably:

| Field | Value |
|---|---|
| `action` | grant, revoke, modify, delegate |
| `target_user_hash` | SHA-256 of affected user |
| `admin_user_hash` | SHA-256 of administrator |
| `grant_type` | domain, scope, pii_tier, delegation |
| `value` | What was granted/revoked |
| `justification` | Required free-text reason |
| `timestamp` | ISO 8601 UTC |
| `hmac_signature` | HMAC-SHA256 of record (tamper detection) |

Retention: 7 years (NARA). Queryable by OIG for compliance reviews.

---

## 5. Dashboard Architecture

### 5.1 Requirements

| Requirement | Implementation |
|---|---|
| Create personal dashboards | Existing — `POST /ai/dashboards` |
| Add/remove panels | Existing — `POST /ai/dashboards/<id>/panels`, `DELETE` |
| Edit panel arrangement | **New** — drag-and-drop reorder, resize within 12-col grid |
| Rename/describe dashboards | Existing — `PUT /ai/dashboards/<id>` |
| Delete dashboards | Existing — `DELETE /ai/dashboards/<id>` |
| Share with colleagues | **New** — share link with viewer/editor permission |
| 508 compliance | Existing charts use Vega-Lite `description` field; grid layout uses semantic HTML |
| Stable UX | Pre-built widget library, not arbitrary AI-generated HTML |

### 5.2 Dashboard Data Model

```
┌─────────────────────────────────────────────────────────────────┐
│  Azure Table Storage: aidashboards                              │
│─────────────────────────────────────────────────────────────────│
│  PartitionKey: SHA-256(owner_user_id)                           │
│  RowKey: dashboard_id (UUID)                                    │
│  content (JSON):                                                │
│    ├── title: str                                               │
│    ├── description: str                                         │
│    ├── panels[]:                                                │
│    │     ├── panel_id: UUID                                     │
│    │     ├── title: str                                         │
│    │     ├── chart_type: enum                                   │
│    │     ├── chart_spec: Vega-Lite JSON                         │
│    │     ├── source_query: str (SQL, for refresh)               │
│    │     ├── source_domains: list[str]                          │
│    │     ├── position: {row, col, width, height}                │
│    │     └── refresh_interval: int (minutes, 0=manual)          │
│    ├── layout: {columns: 12, row_height: int}                   │
│    ├── visibility: "private" | "shared" | "team"                │
│    ├── shared_with[]: list of user_id hashes                    │
│    ├── share_permission: "view" | "edit"                        │
│    ├── created_at: ISO datetime                                 │
│    └── updated_at: ISO datetime                                 │
│                                                                 │
│  Secondary index: shared_dashboards (for lookup by recipient)   │
│  PartitionKey: SHA-256(shared_with_user_id)                     │
│  RowKey: dashboard_id                                           │
│  content: {owner_hash, title, permission}                       │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Sharing Model

Dashboard sharing uses a secondary index table (`aidashboards_shared`) to enable
efficient lookup of dashboards shared with a given user without scanning all
partitions:

1. **Owner shares** → Creates entry in `aidashboards_shared` with recipient's
   hashed user_id as PartitionKey and the dashboard_id as RowKey.
2. **Recipient lists shared dashboards** → Queries `aidashboards_shared` by their
   own PartitionKey, then fetches full dashboard from `aidashboards` by ID.
3. **Permissions** → `view` (read-only render) or `edit` (can add/remove/reorder panels).
4. **Revocation** → Owner deletes the share entry. Immediate effect.
5. **RBAC enforcement** — When a shared dashboard refreshes, the *viewer's* RBAC
   context is applied to the query. If the viewer lacks access to a domain, that
   panel shows "Insufficient permissions" rather than data.

### 5.4 Panel Editing and Layout

The frontend uses a 12-column CSS Grid with drag handles for repositioning:

- **Resize**: grab corner handle, snap to grid columns (minimum 4-col width)
- **Reorder**: drag panel header, drop between other panels
- **Edit title**: inline click-to-edit on panel header
- **Remove**: confirmation modal, then DELETE panel from dashboard
- **Add from conversation**: "Pin to dashboard" action on any AI-generated chart

All layout changes persist immediately via `PUT /ai/dashboards/<id>` with the
updated positions array. No save button — changes auto-persist on drop/resize end.

### 5.5 508 Compliance — Dashboard Rendering

| Element | Accessibility Pattern |
|---|---|
| Grid layout | CSS Grid with `role="region"` per panel, `aria-label` = panel title |
| Charts | Vega-Lite `description` field populated with summary text; `<details>` data table below each chart |
| Drag-and-drop | Keyboard-accessible reorder via arrow keys when panel is focused; `aria-grabbed` / `aria-dropeffect` |
| Share modal | Focus trap, escape to close, `aria-labelledby` linked to heading |
| Status messages | `aria-live="polite"` region for "Dashboard saved", "Panel removed" confirmations |
| Color | All chart palettes meet 4.5:1 contrast; no information conveyed by color alone |

---

## 6. Data Domain Onboarding Contract

Every new data domain (HR, Financial, OIG, Training, etc.) follows this pipeline:

### 6.1 Onboarding Steps

```
Step 1: Source System Agreement
    ├── Identify source database/API/extract
    ├── Define refresh frequency (real-time CDC vs. batch)
    ├── Identify data steward (EEOC staff owner)
    └── Confirm Key Vault credentials provisioned

Step 2: Schema Mapping
    ├── Write YAML mapping file(s) in source_mappings/
    ├── Classify every column: pii_tier (1/2/3)
    ├── Define RLS columns (region, office, program, etc.)
    ├── Identify join keys to existing domains
    └── Validate with mapping_validator.py

Step 3: Target Schema
    ├── Create PostgreSQL migration (analytics.<domain>_*)
    ├── Define dbt staging model (rename, type-cast)
    ├── Define dbt mart model (business logic, JOINs)
    └── Register metrics in metric_definitions.yml

Step 4: Domain Registry
    ├── Write domain_registry/<domain>.yaml
    ├── Declare tables, join keys, RLS columns
    ├── Declare domain access group (UDIP-Domain-<Name>)
    └── Update dbt schema.yml with descriptions

Step 5: RBAC Configuration
    ├── Create Entra group: UDIP-Domain-<Name>
    ├── Define which roles get auto-membership
    ├── Configure RLS predicates in domain registry
    └── Test: user without group cannot query domain

Step 6: Validation
    ├── Run sync_engine.py against source (dry-run)
    ├── Run mapping_validator.py
    ├── Run dbt build --select <domain>
    ├── Test NL-to-SQL against domain questions
    └── Verify RLS blocks unauthorized access
```

### 6.2 Source Mapping YAML Template

```yaml
# source_mappings/<system>_<entity>.yaml
# Data Steward: [Name, Office]
# Source System: [System name and version]
# Refresh: [batch-daily | batch-hourly | cdc-realtime]
# Last Reviewed: [Date]

source:
  driver: "pyodbc"              # pyodbc | eventhub | rest_api | csv_extract
  connection_env: "SOURCE_CONNECTION_STRING"
  table: "schema.table_name"
  watermark_column: "modified_date"
  primary_key: "record_id"
  # For batch: poll interval defined in sync schedule
  # For CDC: topic and consumer group defined here

target:
  schema: "analytics"           # or "hr", "financial", etc.
  table: "target_table"
  primary_key: "target_pk"

columns:
  - source: "source_column"
    target: "target_column"
    type: "varchar(100)"
    pii_tier: 1                 # 1=public, 2=internal, 3=restricted
    rls_domain: null            # "user_regions" | "user_office" | null
    transform: null             # null | value_map | lookup_table | computed | parse_date | redact_pii
    nullable: false
```

### 6.3 Domain Registry YAML Template

```yaml
# domain_registry/<domain>.yaml
domain: "<domain_name>"
schema: "<postgresql_schema>"
description: "<one-line description>"
access_group: "UDIP-Domain-<Name>"
data_steward: "<name, office>"
refresh_frequency: "<cdc-realtime | batch-daily | batch-hourly>"

tables:
  - name: "<table_name>"
    description: "<table purpose>"
    primary_key: "<column>"
    join_keys:
      - column: "<local_column>"
        foreign_domain: "<other_domain>"
        foreign_table: "<other_table>"
        foreign_column: "<other_column>"
    rls_columns:
      - column: "<column>"
        maps_to: "<user_regions | user_office | pii_tier>"
    columns:
      - name: "<column>"
        type: "<sql_type>"
        pii_tier: 1
        description: "<for NL-to-SQL context>"
```

---

## 7. Cross-Domain Query Execution Flow

```
┌──────────┐     ┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  User    │     │  Query      │     │  Domain      │     │  Governed    │
│  Input   │────▶│  Classifier │────▶│  Schema      │────▶│  Executor    │
│          │     │             │     │  Loader      │     │              │
└──────────┘     └─────────────┘     └──────────────┘     └──────┬───────┘
                                                                  │
                 ┌─────────────┐     ┌──────────────┐            │
                 │  Response   │◀────│  Chart       │◀───────────┘
                 │  (prose +   │     │  Generator   │
                 │   chart +   │     │  (Vega-Lite) │
                 │   table)    │     │              │
                 └─────────────┘     └──────────────┘
```

### 7.1 Execution Steps

1. **Input** — User submits natural language query via chat interface.
2. **Domain classification** — GPT-4o classifies which domains are referenced.
   Model receives the domain registry catalog (names + descriptions only, not
   full schemas) to make this determination.
3. **Access check** — Verify user has the required `UDIP-Domain-*` group for
   each referenced domain. Reject with explanation if not.
4. **Schema loading** — Load full schema context (tables, columns, types,
   descriptions, join keys) for the classified domains only. This bounds the
   token cost — loading all domains for every query would exceed context limits
   as domains grow.
5. **SQL generation** — GPT-4o generates SQL with explicit JOINs using the
   declared join keys from the domain registry.
6. **Validation** — sqlglot AST validation (existing). Additional checks:
   - All referenced tables belong to the classified domains
   - JOIN keys match the declared relationships
   - No cross-domain JOINs on undeclared keys
7. **RLS injection** — Domain-specific predicates injected per the user's
   regions, office, and PII tier.
8. **Execution** — Query runs against PostgreSQL with 20s timeout.
9. **Response generation** — Results formatted as:
   - Prose summary (natural language answer)
   - Chart (Vega-Lite spec if data is visual)
   - Data table (if user requests raw data)
10. **Audit** — Query, result row count, domains accessed, and user context
    logged with HMAC signature to WORM storage.

### 7.2 Performance at Scale (2,500 Users)

| Concern | Mitigation |
|---|---|
| Concurrent AI queries | Azure OpenAI rate limiting + queue (existing) |
| RLS predicate cost | SQL Server RLS is index-aware; region/office columns indexed |
| Schema registry loading | Cached in Redis (5-min TTL), invalidated on domain deploy |
| Dashboard refresh storms | Staggered refresh intervals, no sub-5-minute refresh |
| Session storage | Redis cluster, 30-min TTL, ~2KB per session |

---

## 8. Planned Data Domains

### 8.1 HR Domain (OCHCO)

| Attribute | Value |
|---|---|
| **Source system** | TBD — NFC extract, USA Performance, or eOPF |
| **Key entities** | Staff roster, performance ratings, org assignments, position history |
| **Join keys** | `staff_id` → `production.staff_assignments.staff_id`, `office_code` → all domains |
| **RLS columns** | `region_code`, `office_code`, `supervisory_chain` |
| **PII classification** | Names (tier 2), SSN (tier 3), ratings (tier 2), salary (tier 3) |
| **Refresh** | Batch daily (NFC extracts are overnight) |
| **Data steward** | OCHCO designee |
| **Access group** | `UDIP-Domain-HR` |

**Enables queries like:**
- "24-month production trend for staff rated 3 or below in southwest OFP"
- "Average case closure time by investigator performance tier"
- "Attrition rate by region correlated with caseload per capita"

### 8.2 Financial Domain (CFO)

| Attribute | Value |
|---|---|
| **Source system** | TBD — Oracle Federal Financials, Pegasys, or manual extract |
| **Key entities** | Budget allocations, obligations, expenditures, contracts, travel |
| **Join keys** | `office_code`, `program_code`, `fiscal_year` |
| **RLS columns** | `region_code`, `office_code` |
| **PII classification** | Aggregate budget (tier 1), contract details (tier 2), vendor PII (tier 3) |
| **Refresh** | Batch daily |
| **Data steward** | CFO designee |
| **Access group** | `UDIP-Domain-Financial` |

**Enables queries like:**
- "Compare travel spend vs. case closures by district this fiscal year"
- "Which offices are over-budget on personnel costs relative to output"
- "Contract obligations remaining by quarter for IT services"

### 8.3 Future Domains

| Domain | Source | Timeline |
|---|---|---|
| Training / CLEs | EEOC Learning Center | After HR onboarding |
| FOIA statistics | FOIAXpress | When available |
| OIG findings | Manual extract | When available |
| Congressional inquiries | Tracking system TBD | When available |

---

## 9. Implementation Phases

### Phase 1 — Access Management + Dashboard Enhancement

**1A. Admin Access UX**
- Access grant store (`udip_access_grants` Azure Table Storage table)
- Admin blueprint with user search, grant/revoke, domain/scope assignment
- Delegation model (office directors can manage within their scope)
- Audit logging for all access changes (HMAC-signed)
- Effective permissions computation at session creation
- Bulk grant operations (role-based defaults, CSV import)

**1B. Dashboard Enhancement**
- Panel drag-and-drop reorder and resize (frontend, keyboard-accessible)
- Dashboard sharing (secondary index table, permission model)
- "Pin to dashboard" action from AI chat responses
- Increase max panels from 8 → 12

**Infrastructure:** Uses existing Azure Table Storage, existing Flask routes,
existing Redis sessions. Adds one new blueprint (`admin_bp`) and one new table.

### Phase 2 — Multi-Domain Query Engine

- Implement domain registry (`domain_registry/` YAML files)
- Add domain classifier to chat pipeline (pre-SQL-generation step)
- Extend SQL validation for cross-domain JOIN verification
- Replace Entra group domain gating with application-managed grant checks
- Extend RLS injection for per-domain predicate columns + scope dimensions
- Multi-turn conversation state (prior query modification)

**Infrastructure:** No new services. Extends existing `chat.py` pipeline and
`data_access.py` executor.

### Phase 3 — HR Domain Onboarding

- Confirm source system with OCHCO (NFC, USA Performance, or eOPF)
- Write YAML mapping(s) for staff roster, performance ratings, org structure
- Create PostgreSQL schema (`hr.*` tables)
- Write dbt staging + mart models
- Register domain in `domain_registry/hr.yaml`
- Configure default grants: OCHCO staff get HR domain at login; OFP/OFS directors
  get HR scoped to their region; OCH gets agency-wide
- Validate end-to-end: NL query → domain classify → SQL → RLS → result

### Phase 4 — Financial Domain Onboarding

- Same pattern as Phase 3 with CFO source system
- Cross-domain queries now span Production + HR + Financial
- Default grants: OCFO staff get Financial domain; directors get Financial scoped
  to their region; OCH gets agency-wide

### Phase 5 — Remaining Domains (as source systems are confirmed)

| Domain | Likely Owner | Blocked On |
|---|---|---|
| IT Operations | OCIO | Service metrics data source TBD |
| Legislative | OCLA | Congressional inquiry tracking system TBD |
| Training/CLEs | OCHCO | Learning Center integration TBD |
| OIG | OIG | Separate authority — may require isolated instance |

---

## 10. Security Controls

| Control | Implementation |
|---|---|
| **Query injection** | sqlglot AST validation, parameterized execution |
| **Domain isolation** | Entra group gating before query, schema-level access |
| **Row-level security** | Predicate injection per user context, per domain |
| **PII protection** | Column masking by tier, SHA-256 hashing in logs |
| **Audit trail** | HMAC-signed log of every query + result metadata (7-year WORM) |
| **Session security** | Server-side Redis, 30-min TTL, secure/httponly cookies |
| **Dashboard isolation** | User-hashed partition keys, share entries explicitly granted |
| **Rate limiting** | Flask-Limiter per user, prevents query flooding |
| **Timeout** | 20s query timeout, prevents resource exhaustion |

---

## 11. Data Flow — End to End

```
┌────────────────┐
│ Source Systems  │
│ (NFC, PrEPA,   │
│  Oracle, etc.) │
└───────┬────────┘
        │  Batch extract / CDC / Event Hub
        ▼
┌────────────────┐
│ Data Middleware │  ← YAML mapping, PII classification, transform
│ (sync_engine)  │
└───────┬────────┘
        │  Upsert to target schema
        ▼
┌────────────────┐
│ PostgreSQL     │  ← analytics.*, hr.*, financial.* schemas
│ (UDIP Store)   │
└───────┬────────┘
        │  dbt build (staging → marts → metrics)
        ▼
┌────────────────┐
│ dbt Semantic   │  ← Business logic, canonical metrics, descriptions
│ Layer          │
└───────┬────────┘
        │  Schema manifest (JSON) cached in Redis
        ▼
┌────────────────┐
│ Domain Registry│  ← Join keys, RLS columns, access groups
│ (YAML catalog) │
└───────┬────────┘
        │  Loaded by query engine
        ▼
┌────────────────┐
│ AI Assistant   │  ← NL → classify → generate SQL → validate → RLS → execute
│ (Chat + Dash)  │
└───────┬────────┘
        │  Prose + Chart + Table
        ▼
┌────────────────┐
│ Leadership     │  ← Personal dashboards, shared views, conversational queries
│ (2,500 users)  │
└────────────────┘
```

---

## 12. Open Decisions

| # | Decision | Options | Recommendation |
|---|---|---|---|
| 1 | HR source system | NFC extract, USA Performance, eOPF, Core HCM | Requires OCHCO confirmation |
| 2 | Financial source system | Oracle Federal Financials, Pegasys, manual | Requires CFO confirmation |
| 3 | Dashboard refresh model | Manual only, scheduled (>5min), webhook on data sync | Scheduled (15-min minimum) for stability |
| 4 | Cross-domain JOIN limit | 2, 3, or unlimited with timeout | 3 JOINs max (prevents runaway queries) |
| 5 | Share scope | Individual users only, or teams/groups | Both — individual + Entra group sharing |
| 6 | Dashboard panel limit | 8 (current), 12, 16 | 12 (accommodates leadership KPI views) |
| 7 | Admin delegation depth | 1 level (directors only) or multi-level | 1 level initially, expand if needed |
| 8 | Grant expiration default | No default, 90 days, fiscal year end | No default (permanent until revoked) with optional expiry |
| 9 | Access change propagation | Next login only, or force session refresh | Next login (30-min max delay, simple and predictable) |
| 10 | Commissioner scope | Full agency-wide, or per-commissioner limitation | Agency-wide read + domain-specific grants per commissioner |

---

## 13. Attestation

- [x] Architecture supports 2,500 concurrent users without per-user materialization
- [x] RBAC enforced at query time via RLS predicates, not application-level filtering
- [x] Three-axis access model (role × domain × scope) covers all EEOC office structures
- [x] Admin UX provides self-service access management without IT tickets or Azure Portal
- [x] All access grants are HMAC-signed and retained 7 years for OIG audit
- [x] All new domains onboard through the data middleware pipeline with PII classification
- [x] Dashboard UI meets WCAG 2.1 AA via pre-built 508-compliant widget patterns
- [x] Every AI query is audit-logged with HMAC signature and 7-year WORM retention
- [x] No PII stored in dashboard or access grant metadata (user IDs hashed throughout)

**Authorized Official:** ________________________________
**Date:** ________________________________
