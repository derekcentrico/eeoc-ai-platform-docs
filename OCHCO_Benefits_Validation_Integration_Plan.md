# OCHCO Benefits Coding Validation — Integration Plan

## Purpose

Build a Benefits Coding Validation and Overpayment Detection tool for EEOC's
Office of the Chief Human Capital Officer (OCHCO). The tool catches benefits
coding errors before they reach NFC payroll and identifies historical
overpayments for recovery.

This document defines how the new service integrates into the existing EEOC AI
platform. A new repository (`eeoc-ochco-benefits-validation` or similar) will
house the application code. This plan assumes questions from the OCHCO email
have been answered and data access is confirmed.

---

## Architecture Overview

```
                                 ┌─────────────────────────┐
                                 │    MCP Hub (APIM)        │
                                 │  eeoc-mcp-hub-functions  │
                                 │                          │
                                 │  Routes tool calls by    │
                                 │  prefix to spokes        │
                                 └──────────┬──────────────┘
                                            │
                    ┌───────────────────────┼───────────────────────┐
                    │                       │                       │
              ┌─────▼──────┐        ┌───────▼───────┐       ┌──────▼──────┐
              │ ADR Spoke   │        │ Benefits      │       │ Other       │
              │ Triage Spoke│        │ Validation    │       │ Spokes      │
              │ OGC Spoke   │        │ Spoke (NEW)   │       │             │
              └─────────────┘        └───────┬───────┘       └─────────────┘
                                             │
                                    ┌────────▼────────┐
                                    │ eeoc-ochco-      │
                                    │ benefits-        │
                                    │ validation       │
                                    │                  │
                                    │ Flask app with   │
                                    │ MCP endpoint     │
                                    └────────┬────────┘
                                             │
                              ┌──────────────┼──────────────┐
                              │              │              │
                       ┌──────▼───┐   ┌──────▼───┐  ┌──────▼───────┐
                       │ HR Data  │   │ Azure    │  │ Analytics    │
                       │ Source   │   │ OpenAI   │  │ Dashboard    │
                       │ (TBD)    │   │          │  │ Data Feed    │
                       └──────────┘   └──────────┘  └──────────────┘
```

---

## Components

### 1. Data Ingestion Layer

Plugs into the existing data-middleware pattern from
`eeoc-data-analytics-and-dashboard`.

**Source mapping file** — A new YAML mapping in `source_mappings/` defines:
- Source connection (SQL Server, file drop, or API — depends on OCHCO answers)
- Column-level transforms (OPM action codes to readable labels, PII redaction)
- Watermark column for incremental sync
- PII tier classification (employee names and SSNs never leave this layer unhashed)

**Example mapping structure:**

```yaml
source:
  name: nfc_benefits_extract
  type: sqlserver          # or file_drop or api
  connection_key_vault: kv-ochco-nfc-readonly
  watermark_column: last_modified_date

tables:
  - source_table: BENEFITS_ELECTIONS
    target_table: benefits_elections
    columns:
      - source: EMP_SSN
        target: employee_hash
        transform: sha256_with_salt
        pii_tier: 3
      - source: PLAN_CODE
        target: plan_code
        transform: value_map
        value_map_ref: opm_plan_codes
      - source: ACTION_CODE
        target: action_nature_code
        transform: value_map
        value_map_ref: gppa_action_codes
      - source: EFF_DATE
        target: effective_date
        transform: date_parse
        format: "%Y%m%d"
```

**Sync schedule** — Daily at 2 AM UTC via CronJob (offset from the 1 AM
analytics reconciliation run). Real-time CDC via Event Hub if the source
system supports it — but daily batch is the realistic starting point for
NFC data.

### 2. Validation Engine

The core logic. Two modes of operation:

#### Pre-submission validation (interactive)

HR specialist submits a proposed personnel action through the web UI. The
engine runs validation rules before the action is sent to NFC:

| Rule category | Example checks |
|---|---|
| Plan eligibility | FEHB plan code valid for employee's appointment type and work schedule |
| Life event gating | Coverage change requires a qualifying life event within the QLE window |
| Duplicate detection | Same benefit change already processed in current pay period |
| Code consistency | Nature of action code matches the benefit change type (e.g., 292 for open season) |
| Effective date | Effective date falls within the correct pay period for the action type |
| Dependent eligibility | Dependent coverage changes match documented eligible dependents |

Rules are implemented as a pluggable rule engine — each rule is a Python
class with a `validate(action: PersonnelAction) -> list[Finding]` interface.
New rules can be added without modifying the engine.

#### Post-processing anomaly detection (batch)

Nightly batch job analyzes processed actions for patterns that correlate with
overpayments:

- Identify employees with benefit deductions that don't match their current
  elections (stale deductions after a qualifying event)
- Flag coverage levels that exceed what the action history supports
- Detect duplicate deductions across pay periods
- Compare coding patterns against historical error rates by action type

AI-assisted analysis (Azure OpenAI) is used for pattern recognition on
edge cases that don't match deterministic rules. Every AI call follows the
platform's audit logging pattern:

```python
audit_record = {
    "request_id": str(uuid4()),
    "tool_name": "benefits_anomaly_analysis",
    "user_id": user_hash,
    "input_hash": hmac_sha256(input_payload),
    "output_hash": hmac_sha256(ai_response),
    "model": "gpt-4o",
    "timestamp": utcnow().isoformat(),
    "retention_years": 7
}
```

### 3. Overpayment Case Tracker

When a coding error is confirmed (either caught pre-submission or found in
batch review), the system creates an overpayment record:

**Data model:**

```
OverpaymentCase
├── case_id (UUID)
├── employee_hash (SHA-256, no PII)
├── error_type (enum: plan_mismatch, duplicate_deduction, ...)
├── affected_pay_periods (list of PP identifiers)
├── calculated_overpayment_amount (decimal)
├── corrective_action_code (OPM correction NOA)
├── status (enum: detected, confirmed, corrective_submitted, resolved, waiver)
├── detected_by (enum: pre_validation, batch_review, manual)
├── detected_date
├── confirmed_by (user who reviewed)
├── confirmed_date
├── resolution_date
├── notes (encrypted at rest)
└── audit_trail (linked audit log entries)
```

**Storage:** Azure Table Storage (partitioned by fiscal year, row key is
case_id). Follows the same pattern as other platform entities.

### 4. MCP Spoke Registration and AI Assistant Integration

The application exposes an MCP endpoint so its tools are automatically
available through the MCP Hub. Once registered, the benefits tools appear
in the platform's AI Assistant — HR staff can query benefits data, validate
actions, and search overpayment cases using natural language, without leaving
the assistant interface they already use for other EEOC work.

**Tool prefix:** `benefits`

**Exposed tools:**

| Tool | Description |
|---|---|
| `benefits.validate_action` | Validate a proposed personnel action against coding rules |
| `benefits.get_case` | Retrieve an overpayment case by ID |
| `benefits.list_cases` | List overpayment cases with filters (status, date range, error type) |
| `benefits.get_error_summary` | Aggregate error statistics for dashboard consumption |
| `benefits.get_employee_history` | Retrieve benefits action history for a hashed employee |
| `benefits.search` | Natural-language search across benefits data (elections, actions, errors) |
| `benefits.explain_code` | Look up OPM action/benefit code and return plain-English explanation |

**Registration** — Add entry to the `mcpspokes` table in MCP Hub:

```json
{
  "PartitionKey": "spoke",
  "RowKey": "benefits-validation",
  "endpoint": "https://eeoc-benefits-validation.azurewebsites.net/mcp",
  "prefix": "benefits",
  "auth_type": "managed_identity",
  "health_check": "/health"
}
```

#### RBAC-scoped tool access

Every MCP tool call passes through the Hub's auth layer, which resolves
the caller's Entra ID identity and maps it to an application role. The
benefits spoke enforces access at the tool level:

| Role | Permitted tools |
|---|---|
| `benefits_specialist` | All tools — validate, search, case CRUD, code lookup |
| `benefits_manager` | All specialist tools + `get_error_summary` aggregate views |
| `benefits_readonly` | Read-only tools only — `get_case`, `list_cases`, `search`, `explain_code` |
| No benefits role | No benefits tools appear in the assistant's available tool list |

This means when an ADR mediator or OGC attorney uses the AI Assistant,
they do not see benefits tools at all — the Hub only surfaces tools the
user's roles permit. An HR specialist asking "show me overpayment cases
from Q2" gets results; a user without an OCHCO role gets nothing.

#### AI Assistant user experience

From the HR specialist's perspective, the assistant just gains new
capabilities once the spoke is registered. Example interactions:

- "What FEHB plan codes are valid for a part-time employee?"
  → `benefits.explain_code` returns OPM eligibility rules
- "Show me all detected overpayments this fiscal year over $500"
  → `benefits.list_cases` with filters, results in a table
- "Validate this action: 292, FEHB enrollment, plan code D5, effective 01/11/2027"
  → `benefits.validate_action` runs rules and returns findings
- "What's our error rate trend for FEGLI actions by quarter?"
  → `benefits.get_error_summary` returns data, assistant renders a summary

No new UI to learn for basic queries. The web UI (Section 5 below)
handles workflows that require forms, bulk uploads, and case management.

### 5. Web UI

Flask application with the standard platform patterns:

- **Entra ID authentication** for EEOC staff (HR specialists, managers)
- **Role-based access:**
  - `benefits_specialist` — validate actions, review flagged items, confirm overpayments
  - `benefits_manager` — all specialist permissions plus dashboard access and case resolution
  - `benefits_readonly` — view-only access for audit and oversight
- **Pages:**
  - Action validation form (paste or upload SF-52 data, get validation results)
  - Flagged items queue (batch review findings awaiting human confirmation)
  - Overpayment case list and detail views
  - Dashboard (error rates, trends, dollar impact)
- **508 compliance** — all WCAG 2.1 AA requirements per the platform 508 skill.
  Bootstrap 5.3.3 with EEOC contrast overrides. Charts require accessible
  data tables.

### 6. Analytics Dashboard Feed

Push summary data to `eeoc-data-analytics-and-dashboard` for leadership
reporting:

- Error rates by action type and processing office
- Overpayment dollar amounts by fiscal quarter
- Time-to-detection and time-to-resolution metrics
- Trend lines for coding accuracy improvement

Uses the same data-middleware ingestion pattern — the benefits app is a
source, the analytics dashboard is the consumer.

---

## Infrastructure

| Resource | Purpose |
|---|---|
| Azure App Service (Linux, Python 3.11) | Flask web application |
| Azure Table Storage | Overpayment cases, validation rule results, audit logs |
| Azure Blob Storage | Uploaded SF-52 files (encrypted at rest, 7-year retention) |
| Azure Key Vault | NFC connection credentials, HMAC signing key, encryption keys |
| Azure OpenAI (existing instance) | Anomaly detection on edge cases |
| Redis (existing instance) | Session management, MCP tool cache |
| Azure Event Hub (optional) | Real-time CDC if source system supports it |
| APIM (existing) | MCP Hub routing for the new spoke |

**Managed identity** for all Azure service-to-service auth. No stored
credentials in application code.

---

## Security and Compliance

| Requirement | Implementation |
|---|---|
| PII protection | Employee SSNs hashed with SHA-256 + Key Vault salt before storage. Names never stored — referenced by hash only. `_mask_pii()` applied to all log output. |
| AI audit trail | HMAC-SHA256 signed audit records on every AI call. 7-year WORM retention in immutable blob storage. |
| Data at rest | Azure Storage Service Encryption (SSE) with customer-managed keys in Key Vault |
| Data in transit | TLS 1.2+ on all connections. HTTPS only. |
| Access control | Entra ID RBAC. No shared accounts. |
| FedRAMP High | All infrastructure deployed within existing FedRAMP High boundary |
| NIST 800-53 | Inherits platform control implementations. AC-2, AU-2, AU-3, SC-8, SC-28 directly relevant. |
| Stop sequences | `["Legal Advice:", "Legal Conclusion:"]` on all AI calls (platform standard) |
| Human review | Every AI-flagged item requires human confirmation before corrective action |

---

## Dependencies and Open Questions

These must be resolved before development begins:

### Blocking questions (from email)

1. **What is the source system?** NFC direct feed, EEOC intermediary database,
   or file export? This determines the entire ingestion layer design.
2. **What data format?** Column names, data types, code tables. We need a
   sample extract or data dictionary.
3. **What are the top 5-10 error types?** Drives the initial rule set for the
   validation engine.
4. **Where are OPM coding rules documented?** GPPA chapters, EEOC-specific
   SOPs, or institutional knowledge that needs to be formalized.
5. **Who are the users?** Number of HR specialists, their current workflow,
   and whether managers also need access.
6. **Integration timeline constraints?** Any systems being sunsetted under
   Core HCM that we should avoid depending on.

### Technical assumptions to confirm

7. Existing Azure OpenAI quota has capacity for additional workload (estimate:
   low volume — hundreds of actions per month, not thousands).
8. Network path exists from Azure App Service to NFC data source (may require
   VPN or private endpoint configuration).
9. OCHCO is willing to define and maintain validation rules with OCIO — this
   is not a "set and forget" tool.

---

## Repo Structure (Proposed)

```
eeoc-ochco-benefits-validation/
├── .claude/
│   └── CLAUDE.md                  # Repo-specific instructions
├── app/
│   ├── __init__.py                # Flask app factory
│   ├── auth.py                    # Entra ID authentication
│   ├── config.py                  # Configuration from env/Key Vault
│   ├── models/
│   │   ├── overpayment_case.py    # Table Storage entity
│   │   ├── personnel_action.py    # Input data model
│   │   └── validation_result.py   # Rule engine output
│   ├── rules/
│   │   ├── base.py                # Rule interface
│   │   ├── plan_eligibility.py
│   │   ├── life_event_gating.py
│   │   ├── duplicate_detection.py
│   │   ├── code_consistency.py
│   │   └── effective_date.py
│   ├── services/
│   │   ├── validation_service.py  # Orchestrates rule execution
│   │   ├── anomaly_service.py     # Batch anomaly detection
│   │   ├── case_service.py        # Overpayment case CRUD
│   │   └── ai_analysis.py         # Azure OpenAI integration
│   ├── routes/
│   │   ├── validation.py          # Action validation endpoints
│   │   ├── cases.py               # Case management endpoints
│   │   ├── dashboard.py           # Dashboard data endpoints
│   │   └── mcp.py                 # MCP spoke endpoint
│   ├── templates/                 # Jinja2 templates (508 compliant)
│   └── static/
├── data_ingestion/
│   ├── source_mappings/
│   │   └── nfc_benefits.yaml      # Source-to-target mapping
│   └── sync_job.py                # Ingestion CronJob
├── tests/
├── scripts/
│   └── run_tests_two_loops.sh
├── requirements.txt
├── Dockerfile
└── docs/
    ├── Architecture.md
    ├── Validation_Rules.md
    └── Data_Dictionary.md
```

---

## Implementation Sequence

1. **Repo setup and scaffolding** — Flask app factory, auth, config, health
   endpoint, MCP spoke skeleton. Register in MCP Hub.
2. **Data ingestion** — Source mapping, sync job, sample data validation.
   Requires answers to questions 1-2.
3. **Validation engine** — Rule interface, initial rule set (top 5 error
   types). Requires answers to questions 3-4.
4. **Overpayment case tracker** — Table Storage entities, CRUD routes, case
   list and detail UI.
5. **AI anomaly detection** — Batch job for historical analysis, audit logging
   integration.
6. **Dashboard and reporting** — Analytics feed, leadership dashboard views.
7. **508 audit and security review** — Full accessibility audit, pre-pen-test
   hardening, post-impl verification.

Each phase produces a working increment that can be demonstrated to OCHCO
for feedback.
