# DAES Documentation Standardization Plan
**Author:** Derek Gordon

## Data and AI Enterprise System (DAES)

---

This plan brings every application repository up to a consistent documentation set,
using the ADR Portal (`eeoc-ofs-adr/docs/`) as the gold standard for naming, structure,
and style. It is a **planning document** — it specifies the target state, the per-repo
gaps, and the execution order. It does not author the documents themselves; that work is
handed off to follow-up sessions per the batches in Section 6.

Coverage is **applicability-driven**: a repo only carries a document type that genuinely
applies to it (Section 3). A repo without a user interface does not get a Section 508
statement; a repo that performs no AI generation does not get an AI governance card. Where
a document applies, it uses the **exact ADR filename** and the ADR header/section style.

---

## 1. Gold Standard — Canonical Document Set

The canonical set is the ADR Portal documentation (`eeoc-ofs-adr/docs/`, 37 documents).
For standardization purposes the set is grouped into **universal** documents (every repo),
**conditional** documents (gated on a repo capability), and **app-specific** documents
(unique to one application; not standardized across repos).

### 1.1 Universal — every application repo

| Canonical filename | Purpose |
|---|---|
| `{App}_Architecture_Diagram.md` | System boundary and component diagram |
| `{App}_Architecture_Visual.md` | Visual/executive architecture views |
| `API_Architecture_and_Integration_Guide.md` | Routes, contracts, inter-service integration |
| `{App}_Component_Compliance_Reference_Guide.md` | Component-by-component control mapping |
| `NIST_800-53_Compliance_Implementation_Analysis.md` | Rev 5 control implementation evidence |
| `FedRAMP_Authorization_Boundary_Diagram.md` | Authorization boundary |
| `Configuration_Management_Plan.md` | Config control process |
| `Data_Dictionary_and_Schema.md` | Tables, fields, schema reference |
| `Access_Control_Audit_and_Implementation_Plan.md` | AuthN/AuthZ model and audit |
| `CUI_Data_Flow_Lifecycle.md` | CUI handling end to end |
| `Data_Retention_Compliance_Plan.md` | NARA/retention schedule |
| `Azure_Tenant_Data_Lifecycle_Policy.md` | Tenant data lifecycle configuration |
| `SUPPLY_CHAIN_RISK.md` | SBOM, dependency, SCRM posture |
| `Incident_Response_Playbook.md` | IR procedures |
| `Disaster_Recovery_Runbook.md` | RTO/RPO, restore procedures |
| `Secret_Rotation_Runbook.md` | Key Vault rotation procedures |
| `Deployment_Guide.md` | Consolidated AKS deployment (manifests, image, secrets) |
| `Azure_Portal_Provisioning_Guide.md` | Portal click-path provisioning |
| `Entra_ID_App_Registration_Guide.md` | App registration, roles, audiences |
| `Environment_Variable_Dependencies.md` | Env var contract |

### 1.2 Conditional — gated on a capability (Section 3 decides)

| Canonical filename | Applies when |
|---|---|
| `Section_508_Accessibility_Conformance_Statement.md` | The repo serves a user interface (HTML templates) |
| `AI_Model_Governance_Card.md` | The repo performs AI generation |
| `AI_Bias_Fairness_and_Equitable_Treatment_Assessment.md` | The repo performs AI generation that informs a person-affecting decision |
| `ARC_Integration_Guide.md` | The repo calls ARC directly or consumes ARC data contracts |
| `Email_Notification_Configuration_Guide.md` | The repo sends notification email |
| `DNS_and_TLS_Setup.md` | The repo terminates its own public hostname/TLS |
| `Key_Vault_Secret_Generation.md` | The repo provisions its own Key Vault secrets (most do) |
| `First_Run_Setup_Guide.md` | The repo has a first-run/bootstrap procedure |

### 1.3 App-specific — not standardized

Documents unique to one application stay where they are and are not propagated:
ADR's `ADR_SameSite_Lax_Decision.md`, `ADR_Entra_ID_Graph_Permission_Review.md`,
`Agency_Domain_Onboarding_Guide.md`, `Multi_Level_Office_Structure_Plan.md`,
`Office_Feature_Administration_Guide.md`, `Dual_Authentication_Architecture_Visual.md`;
MCP Hub's `Spoke_Registration_Guide.md`; OCHCO's `Validation_Rules.md`; ARC Integration
API's `Charge_Identifier_Model.md` and `ARC_Role_Sync.md`; Access Admin's
`Configuration_Reference.md`. Keep these; they are not gaps.

---

## 2. Naming and Style Conventions

### 2.1 Style

All standardized documents follow the ADR house style (see `.../doc-style`):

- Header block: `# Title`, then `**Author:** Derek Gordon`, then `## <Application Name>`, then `---`.
- Numbered sections (`1.`, `1.1`, `2.`) — never skip levels.
- Attribute tables as `| **Bold Key** | Value |`; data tables as plain columns.
- Code references as backticked relative paths with line numbers.
- Diagrams as Mermaid `flowchart TB/LR` or box-drawing ASCII.
- Compliance documents end with an **Attestation** block and a **Document Control** table.
- Read the nearest existing ADR document of the same type before writing a new one.
- Naming: use the platform name **Data and AI Enterprise System (DAES)** and the component
  name (UDAP, ADR, Triage, OGC Trial Tool, OCHCO, Access Admin, MCP Hub, ARC Integration API)
  in titles. Do not invent new title forms.

### 2.2 Required renames (filename drift)

These existing files cover the right content under a non-canonical name. Rename in place
(preserve git history with `git mv`) and fix inbound links:

| Repo | Current filename | Canonical filename |
|---|---|---|
| `eeoc-mcp-hub-functions` | `Azure_MCP_Hub_Setup_Guide.md` | `Deployment_Guide.md` (and purge stale Container App references — see Section 5.2) |
| `eeoc-ochco-benefits-validation` | `Deployment.md` | `Deployment_Guide.md` |
| `eeoc-ochco-benefits-validation` | `Data_Dictionary.md` | `Data_Dictionary_and_Schema.md` |
| `eeoc-ogc-trialtool` | `Section_508_Accessibility_Conformance.md` | `Section_508_Accessibility_Conformance_Statement.md` |
| `eeoc-ogc-trialtool` | `Authentication_and_Access_Control.md` | `Access_Control_Audit_and_Implementation_Plan.md` (align to canonical access-control doc) |
| `eeoc-ochco-benefits-validation` | `Authentication_and_Access_Control.md` | `Access_Control_Audit_and_Implementation_Plan.md` |
| `eeoc-arc-integration-api` | `Architecture.md` | Keep as the architecture diagram doc; add `_Visual` only if a separate visual is warranted |
| `eeoc-mcp-hub-functions` | `Architecture.md` | Keep as the architecture diagram doc; same note |

> Lightweight backend repos (no UI) may keep a single `Architecture.md` rather than the
> `{App}_Architecture_Diagram.md` + `_Visual.md` split — the split exists for the UI apps
> where executive visuals matter. This is an allowed applicability exception, not a gap.

---

## 3. Applicability Determination

Capability scan performed 2026-06-05 (templates present → UI; Azure OpenAI/LLM client
present → AI generation; direct ARC client → ARC integration):

| Repo | UI (508) | AI generation | Calls/consumes ARC | Sends email |
|---|---|---|---|---|
| `eeoc-ofs-adr` (baseline) | Yes | Yes | Yes (via API) | Yes |
| `eeoc-ofs-triage` | Yes | Yes | Yes (via API) | No |
| `eeoc-ogc-trialtool` | Yes | Yes | Via API | No |
| `eeoc-data-analytics-and-dashboard` (UDAP) | Yes | Yes | Via MCP/API | Yes |
| `eeoc-ochco-benefits-validation` | Yes | Yes | No | TBD |
| `eeoc-access-admin` | Yes | No | Via API | No |
| `eeoc-arc-integration-api` | No | No | **Yes — the ARC caller** | No |
| `eeoc-mcp-hub-functions` | No | No | No (routes to spokes) | No |

Derived gates:

- **508 statement**: ADR, Triage, OGC, UDAP, OCHCO, Access Admin. **N/A** for ARC
  Integration API and MCP Hub (no UI).
- **AI governance card + bias assessment**: ADR, Triage, OGC, UDAP, OCHCO. **N/A** for
  Access Admin (no AI), ARC Integration API, MCP Hub.
- **ARC Integration Guide**: ARC Integration API (it *is* the caller — documents its own ARC
  surface), and any repo consuming ARC contracts. **N/A** for MCP Hub.

---

## 4. Per-Repo Target Matrix

Legend: **PRESENT** (correct name, exists) · **AUTHOR** (applicable, missing) ·
**RENAME** (exists under wrong name — Section 2.2) · **N/A** (not applicable, with reason).
Universal docs only are listed per repo; app-specific docs (Section 1.3) are kept as-is and
omitted here. Triage and UDAP are at or near parity and are not expanded below.

### 4.1 eeoc-arc-integration-api (currently 7 docs)

| Document | Status |
|---|---|
| `Architecture.md` | PRESENT (serves as architecture diagram) |
| `API_Reference.md` / `API_Architecture_and_Integration_Guide.md` | PRESENT (`API_Reference.md`); align name to `API_Architecture_and_Integration_Guide.md` |
| `Deployment_Guide.md` | PRESENT |
| `Access_Control_Audit_and_Implementation_Plan.md` | AUTHOR (has `Access_Control.md` — align name + expand to plan) |
| `ARC_Integration_Guide.md` | AUTHOR (documents its own ARC client surface; `ARC_Role_Sync.md` is a subset) |
| `Data_Dictionary_and_Schema.md` | AUTHOR (`Charge_Identifier_Model.md` is partial) |
| `NIST_800-53_Compliance_Implementation_Analysis.md` | AUTHOR |
| `FedRAMP_Authorization_Boundary_Diagram.md` | AUTHOR |
| `Configuration_Management_Plan.md` | AUTHOR |
| `Environment_Variable_Dependencies.md` | AUTHOR |
| `Entra_ID_App_Registration_Guide.md` | AUTHOR |
| `Incident_Response_Playbook.md` | AUTHOR |
| `Disaster_Recovery_Runbook.md` | AUTHOR |
| `Secret_Rotation_Runbook.md` | AUTHOR |
| `CUI_Data_Flow_Lifecycle.md` | AUTHOR |
| `Data_Retention_Compliance_Plan.md` | AUTHOR |
| `Azure_Tenant_Data_Lifecycle_Policy.md` | AUTHOR |
| `Azure_Portal_Provisioning_Guide.md` | AUTHOR |
| `SUPPLY_CHAIN_RISK.md` | PRESENT |
| Section 508 / AI governance / AI bias | N/A (no UI, no AI generation) |

### 4.2 eeoc-mcp-hub-functions (currently 4 docs)

| Document | Status |
|---|---|
| `Architecture.md` | PRESENT |
| `Deployment_Guide.md` | RENAME from `Azure_MCP_Hub_Setup_Guide.md` + de-stale (Section 5.2) |
| `Spoke_Registration_Guide.md` | PRESENT (app-specific, keep) |
| `API_Architecture_and_Integration_Guide.md` | AUTHOR (tools/call contract, prefix routing) |
| `Access_Control_Audit_and_Implementation_Plan.md` | AUTHOR (spoke app-roles, HMAC, SSRF allowlist) |
| `Data_Dictionary_and_Schema.md` | AUTHOR (Table Storage entities, audit blob) |
| `NIST_800-53_Compliance_Implementation_Analysis.md` | AUTHOR |
| `FedRAMP_Authorization_Boundary_Diagram.md` | AUTHOR |
| `Configuration_Management_Plan.md` | AUTHOR |
| `Environment_Variable_Dependencies.md` | AUTHOR |
| `Entra_ID_App_Registration_Guide.md` | AUTHOR |
| `Incident_Response_Playbook.md` | AUTHOR |
| `Disaster_Recovery_Runbook.md` | AUTHOR |
| `Secret_Rotation_Runbook.md` | AUTHOR |
| `Data_Retention_Compliance_Plan.md` | AUTHOR (WORM audit retention) |
| `Azure_Tenant_Data_Lifecycle_Policy.md` | AUTHOR |
| `SUPPLY_CHAIN_RISK.md` | PRESENT |
| Section 508 / AI governance / AI bias / ARC Integration | N/A (no UI, no AI generation, no direct ARC) |

### 4.3 eeoc-ochco-benefits-validation (currently 5 docs)

| Document | Status |
|---|---|
| `Architecture.md` | PRESENT |
| `Deployment_Guide.md` | RENAME from `Deployment.md` |
| `Data_Dictionary_and_Schema.md` | RENAME from `Data_Dictionary.md` |
| `Validation_Rules.md` | PRESENT (app-specific, keep) |
| `Access_Control_Audit_and_Implementation_Plan.md` | RENAME from `Authentication_and_Access_Control.md` + expand |
| `Section_508_Accessibility_Conformance_Statement.md` | AUTHOR (has UI) |
| `AI_Model_Governance_Card.md` | AUTHOR (performs AI generation) |
| `AI_Bias_Fairness_and_Equitable_Treatment_Assessment.md` | AUTHOR (overpayment detection is person-affecting) |
| `API_Architecture_and_Integration_Guide.md` | AUTHOR |
| `NIST_800-53_Compliance_Implementation_Analysis.md` | AUTHOR |
| `FedRAMP_Authorization_Boundary_Diagram.md` | AUTHOR |
| `Configuration_Management_Plan.md` | AUTHOR |
| `Environment_Variable_Dependencies.md` | AUTHOR |
| `Entra_ID_App_Registration_Guide.md` | AUTHOR |
| `Incident_Response_Playbook.md` | AUTHOR |
| `Disaster_Recovery_Runbook.md` | AUTHOR |
| `Secret_Rotation_Runbook.md` | AUTHOR |
| `CUI_Data_Flow_Lifecycle.md` | AUTHOR |
| `Data_Retention_Compliance_Plan.md` | AUTHOR |
| `Azure_Tenant_Data_Lifecycle_Policy.md` | AUTHOR |
| `Azure_Portal_Provisioning_Guide.md` | AUTHOR |
| `SUPPLY_CHAIN_RISK.md` | AUTHOR (missing) |

### 4.4 eeoc-access-admin (currently 3 docs)

| Document | Status |
|---|---|
| `Access_Admin_Architecture.md` | PRESENT (architecture) |
| `Configuration_Reference.md` | PRESENT (app-specific, keep) |
| `Deployment_Guide.md` | PRESENT |
| `Access_Control_Audit_and_Implementation_Plan.md` | AUTHOR (this app *is* access control — highest priority) |
| `Section_508_Accessibility_Conformance_Statement.md` | AUTHOR (has UI) |
| `API_Architecture_and_Integration_Guide.md` | AUTHOR |
| `Data_Dictionary_and_Schema.md` | AUTHOR |
| `NIST_800-53_Compliance_Implementation_Analysis.md` | AUTHOR |
| `FedRAMP_Authorization_Boundary_Diagram.md` | AUTHOR |
| `Configuration_Management_Plan.md` | AUTHOR |
| `Environment_Variable_Dependencies.md` | AUTHOR |
| `Entra_ID_App_Registration_Guide.md` | AUTHOR |
| `Incident_Response_Playbook.md` | AUTHOR |
| `Disaster_Recovery_Runbook.md` | AUTHOR |
| `Secret_Rotation_Runbook.md` | AUTHOR |
| `CUI_Data_Flow_Lifecycle.md` | AUTHOR |
| `Data_Retention_Compliance_Plan.md` | AUTHOR |
| `Azure_Tenant_Data_Lifecycle_Policy.md` | AUTHOR |
| `Azure_Portal_Provisioning_Guide.md` | AUTHOR |
| `SUPPLY_CHAIN_RISK.md` | AUTHOR (missing) |
| AI governance / AI bias | N/A (no AI generation) |

### 4.5 eeoc-ogc-trialtool (currently 13 docs)

| Document | Status |
|---|---|
| `OGC_Trial_Tool_Architecture_Diagram.md` | PRESENT |
| `{App}_Architecture_Visual.md` | AUTHOR |
| `API_Architecture_and_Integration_Guide.md` | PRESENT |
| `Component_Compliance_Reference_Guide.md` | AUTHOR |
| `Access_Control_Audit_and_Implementation_Plan.md` | RENAME/merge from `Authentication_and_Access_Control.md` + `Access_Control_Audit_and_Implementation_Plan.md` (both present) |
| `Section_508_Accessibility_Conformance_Statement.md` | RENAME from `Section_508_Accessibility_Conformance.md` |
| `AI_Model_Governance_Card.md` | PRESENT |
| `AI_Bias_Fairness_and_Equitable_Treatment_Assessment.md` | AUTHOR |
| `Data_Dictionary_and_Schema.md` | PRESENT |
| `NIST_800-53_Compliance_Implementation_Analysis.md` | PRESENT |
| `FedRAMP_Authorization_Boundary_Diagram.md` | PRESENT |
| `Configuration_Management_Plan.md` | AUTHOR |
| `Environment_Variable_Dependencies.md` | AUTHOR |
| `Entra_ID_App_Registration_Guide.md` | AUTHOR |
| `Incident_Response_Playbook.md` | AUTHOR |
| `Disaster_Recovery_Runbook.md` | AUTHOR |
| `Secret_Rotation_Runbook.md` | AUTHOR |
| `CUI_Data_Flow_Lifecycle.md` | AUTHOR |
| `Data_Retention_Compliance_Plan.md` | PRESENT (`NARA_Data_Retention_Implementation_Plan.md` — align name) |
| `Azure_Tenant_Data_Lifecycle_Policy.md` | PRESENT |
| `Deployment_Guide.md` | AUTHOR (k8s manifests exist in `deploy/k8s/`; no consolidated guide) |
| `Azure_Portal_Provisioning_Guide.md` | PRESENT (`Azure_Portal_OGC_Trial_Tool_Guide.md` — align name) |
| `SUPPLY_CHAIN_RISK.md` | PRESENT |

---

## 5. Priority Deliverables (do first in the hand-off)

These three serve the immediate test-deployment goal — letting the team deploy UDAP + ARC
(plus the rest) consistently from each repo's `deploy/k8s/` — and are the most bounded.

### 5.1 ADR consolidated `Deployment_Guide.md`

ADR has `deploy/k8s/adr-webapp/`, `deploy/k8s/adr-functionapp/`, `deploy/k8s/adr-redis/`
and `provision_adr_system.sh`, but no single deployment guide. Author one modeled on
`eeoc-access-admin/docs/Deployment_Guide.md` and `eeoc-arc-integration-api/docs/Deployment_Guide.md`:
prerequisites, image build + digest pin, manifest substitution (`sed`, not `envsubst`),
apply order, Key Vault CSI secrets, post-deploy verification. Event-driven function app
probes are `tcpSocket` (no HTTP health route).

### 5.2 MCP Hub guide rename + de-stale

Rename `Azure_MCP_Hub_Setup_Guide.md` → `Deployment_Guide.md`. The guide's Section 6 is
already an AKS deployment, but stale **Container App** references remain in the table of
contents (the `Compute — Container App` ToC entry) and Section 9 (`Set these on the
container app`). Replace those with the AKS equivalents (deployment env / ConfigMap), so the
document is internally consistent.

### 5.3 Static-import playbook freshness pass

`DAES_Test_Environment_Static_Import_Playbook.md` already specifies the bare-minimum
UDAP + MCP Hub + ARC Integration API deployment with a manual `psql`/`pg_restore` import and
acceptance criteria. Re-verify it against the current manifests and the recent security
changes (the MCP Hub `ALLOWED_SPOKE_PRIVATE_CIDRS` wiring, ARC self-service email-claim
behavior) before the team follows it.

---

## 6. Execution Batches (hand-off)

Author in this order so deployment-critical and highest-risk-of-audit documents land first.
Each batch is one self-verifying session; one PR per repo.

| Batch | Scope | Repos |
|---|---|---|
| **B0** | Section 5 priority deliverables (ADR deploy guide; MCP Hub rename/de-stale; playbook freshness) | ADR, MCP Hub, platform-docs |
| **B1** | Renames only (low-risk `git mv` + link fixes) | OCHCO, OGC, ARC, MCP Hub |
| **B2** | Deployment + provisioning + env docs (`Deployment_Guide`, `Azure_Portal_Provisioning_Guide`, `Environment_Variable_Dependencies`, `Entra_ID_App_Registration_Guide`) | ARC, MCP Hub, OCHCO, Access Admin, OGC |
| **B3** | Access control + 508 (highest audit value; Access Admin first) | Access Admin, OCHCO, OGC, ARC, MCP Hub |
| **B4** | Compliance core (`NIST_800-53`, `FedRAMP_Authorization_Boundary`, `Configuration_Management_Plan`, `Component_Compliance_Reference_Guide`) | all thin repos |
| **B5** | Data + retention + lifecycle (`Data_Dictionary_and_Schema`, `CUI_Data_Flow_Lifecycle`, `Data_Retention_Compliance_Plan`, `Azure_Tenant_Data_Lifecycle_Policy`) | all thin repos |
| **B6** | Operations runbooks (`Incident_Response_Playbook`, `Disaster_Recovery_Runbook`, `Secret_Rotation_Runbook`) | all thin repos |
| **B7** | AI governance (`AI_Model_Governance_Card`, `AI_Bias_Fairness...`) | OCHCO, OGC |
| **B8** | Supply chain (`SUPPLY_CHAIN_RISK.md`) | OCHCO, Access Admin |

Estimated net new documents: ~45 (excludes renames). Each must read the nearest ADR
equivalent first and match its structure exactly. No document is marked complete until it
is accurate against the live code in its repo, not merely structurally present.

---

## 7. Out of Scope

- ADR-specific and app-specific documents (Section 1.3) are not propagated.
- No filename changes to ADR, Triage, or UDAP (already canonical / near-parity).
- This plan does not move per-application docs into `eeoc-ai-platform-docs/`; per-app docs
  stay in each repo's `docs/`. Only cross-cutting platform docs belong in the docs repo.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial standardization plan and per-repo target matrix |
