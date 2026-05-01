# ARC Source Repository Gap Analysis
**Author:** Derek Gordon

## EEOC AI Platform — ARC Integration Coverage

---

## 1. Purpose

This document identifies gaps between the ARC source repositories in `eeoc-arc-payloads/`
and the current EEOC AI Platform implementation. The platform was built from 58
implementation prompts that assumed a specific set of ARC repos and endpoints. New ARC
repositories and endpoints have been added since then. This analysis maps every ARC
capability against the current integration surface, identifies what is missing, and
recommends specific changes.

## 2. Scope

| Dimension | Count |
|---|---|
| **ARC repos analyzed** | 34 (excluding `-clean` exports) |
| **PrEPA endpoints identified** | ~280 |
| **FepaGateway endpoints identified** | ~100 |
| **Other ARC service repos** | 26 (IntakeCollections, Federal, Portals, Content, etc.) |
| **Current PrepaClient methods** | 18 |
| **Current FepaClient methods** | 4 |
| **Current MCP tools** | 18 (10 read, 8 write) |
| **Current middleware YAML mappings** | 10 (7 PrEPA CDC, 2 SQL Server, 1 Angular) |

---

## 3. Current Integration Surface

### 3.1 PrepaClient — PrEPA Endpoints Currently Wired

| Method | PrEPA Path | Consumer |
|---|---|---|
| `get_case` | GET /cases/{id} | OGC TrialTool |
| `get_mediation_eligible` | GET /cases/mediation-eligible | ADR Portal |
| `get_case_mediation` | GET /cases/{id}/mediation | ADR Portal |
| `update_mediation` | PUT /cases/{id}/mediation | ADR Portal |
| `assign_mediation_staff` | POST /cases/{id}/mediation/staff | ADR Portal |
| `close_case` | POST /cases/{id}/close | ADR Portal |
| `post_benefits` | POST /cases/{id}/benefits | ADR Portal |
| `post_events` | POST /cases/{id}/events | ADR Portal, Triage |
| `post_document` | POST /cases/{id}/documents | ADR Portal |
| `post_signed_agreements` | POST /cases/{id}/signed-agreements | ADR Portal |
| `get_offices` | GET /reference/offices | Reference data |
| `get_lookup_data` | GET /reference/lookup | Reference data |
| `search_cases` | POST /cases/search | MCP Hub |
| `get_case_allegations` | GET /cases/{id}/allegations | MCP Hub |
| `get_case_staff` | GET /cases/{id}/staff | MCP Hub |
| `get_charge_metadata` | GET /charges/{num}/metadata | Triage |
| `patch_charge` | PATCH /charges/{num} | Triage |
| `trigger_nrts` | POST /charges/{num}/nrts | Triage |

### 3.2 FepaClient — FEPA Gateway Endpoints Currently Wired

| Method | Gateway Path | Consumer |
|---|---|---|
| `get_sbi_combinations` | GET /fepagateway/v1/sbi-combo | Reference data |
| `get_document_types` | GET /fepagateway/v1/documents/type | Reference data |
| `get_case_documents` | GET /fepagateway/v1/documents/{num} | ADR Portal, OGC |
| `get_document` | GET /fepagateway/v1/documents/download/{id} | ADR Portal, OGC |

### 3.3 Data Middleware — CDC/Source Mappings

| YAML File | Source Table | Target Table |
|---|---|---|
| `prepa_charges.yaml` | `charge_inquiry` | `analytics.charges` |
| `prepa_allegations.yaml` | `charge_allegation` | `analytics.allegations` |
| `prepa_charging_party.yaml` | `charging_party` | `analytics.charging_parties` |
| `prepa_event_log.yaml` | `charge_event_log` | `analytics.case_events` |
| `prepa_mediation.yaml` | `mediation_interview` | `analytics.mediation_sessions` |
| `prepa_respondent.yaml` | `respondent` | `analytics.respondents` |
| `prepa_staff_assignments.yaml` | `charge_assignment` | `analytics.staff_assignments` |
| `sqlserver_charges.yaml` | `dbo.CHG_TBL` | `analytics.charges` |
| `sqlserver_adr.yaml` | `dbo.ADR_OUT` | `analytics.adr_outcomes` |
| `angular_cases.yaml` | `tbl_cs_data` | `analytics.angular_cases` |

### 3.4 MCP Tools Currently Registered

**Read (10):** `arc_search_cases`, `arc_get_case`, `arc_get_case_allegations`,
`arc_get_case_staff`, `arc_get_case_documents`, `arc_get_mediation_eligible`,
`arc_get_charge_metadata`, `arc_get_litigation_case`, `arc_get_sbi_combinations`,
`arc_get_offices`

**Write (8):** `arc_update_mediation_status`, `arc_assign_mediation_staff`,
`arc_close_mediation_case`, `arc_upload_case_document`, `arc_log_case_events`,
`arc_generate_signed_agreements`, `arc_post_triage_classification`,
`arc_log_triage_events`

---

## 4. ARC Repository Inventory

### 4.1 PrEPAWebService-ims-aks-test (Primary — ~280 endpoints)

The main charge processing service. Our integration covers mediation, basic case CRUD,
allegations (read), events (write), documents, and a few reference endpoints. The
following endpoint groups exist in source but are not wired:

| Resource Group | Endpoints | Description |
|---|---|---|
| Enforcement | ~30 | Position statements, on-site investigations, communications, fact-finding, subpoenas, conferences, conciliation |
| Closure/NRTS Detail | ~25 | Closure reason lookup, allegation-level close, benefit-group management, NRTS document generation, FEPA closure, resend notifications |
| FEPA Credit | ~16 | Credit requests, responses, SWR (Statement of Work Release), beneficiary management, acknowledgments |
| Dual Filing/Deferral | ~12 | Deferral info, office notifications/acknowledgments, case cloning, receiving office management |
| Systemic Cases | ~18 | Systemic case CRUD, related charges, subscriptions, notes, search criteria |
| Case Notes | ~12 | Particular notes, mediation notes, general notes — CRUD plus amend |
| Case Review | ~6 | Review assignments, approvals, review types |
| Transfer | ~3 | Transfer requests, actions, transfer list |
| Suspension | ~7 | Create, update, remove, reasons lookup, case age |
| Timetap | ~3 | Staff scheduling, invite emails, deactivation |
| Interview | ~3 | Interview scheduling CRUD |
| RFI | ~3 | Request for Information content preview, list, document generation |
| Compliance | ~1 | Determination of compliance |
| Charging Party | ~4 | CRUD, portal account management |
| Respondent Detail | ~8 | CRUD, additional respondents, additional addresses, delink |
| Court Hearing | ~4 | CRUD on court hearing records |
| Case Folder | ~7 | Folder CRUD, assign/remove cases |
| Class Group | ~7 | Group CRUD, assign/remove cases |
| User | ~2 | User lookup by ID, user list |
| Office Detail | ~13 | District list, location lookup, zipcode, business ID, all offices |
| Reports | ~1 | PowerBI token endpoint |
| Document Generation | ~5 | COD, unsigned COD, NOC, investigative file, e-file notifications |
| Portal (Respondent) | ~3 | Respondent credentials, staff validation |
| FOIA | ~3 | FOIA request creation, deletion, list |
| Assessment | ~2 | Assessment areas, case assessment |

### 4.2 FepaGateway-ims-aks (~100 endpoints)

BFF (Backend-for-Frontend) gateway aggregating multiple ARC services. Our integration
covers only SBI combinations, document types, and document retrieval.

| Resource Group | Endpoints | Description |
|---|---|---|
| FEPA Case Management | ~15 | Case CRUD, validation, reopening, charging party, respondent, representatives, allegations, FEPA charge numbers |
| FEPA Reporting | ~5 | Office-level reports by receiving/deferral/accountability code, credit reports |
| FEPA Credit | ~8 | Credit request CRUD, revoke, beneficiary management |
| Attorney Portal | ~6 | Charge submission (multipart), data lookups (NAICS, employer, zipcode, SBI), email lookup, token exchange |
| Public Portal | ~40 | Charge submission (XML), supplemental filings, comments, office update, status tracking, COD generation/signing, amended COD, mediation response, representative management, scheduling, document upload/download/list, token management, CP info update |
| FOIA | ~5 | Office code lookup, charge detail, event CRUD |
| Document Service | ~5 | Upload, download (by ID, COD), delete, schema download |

### 4.3 Services with Zero Integration

| Repo | Purpose | Endpoint Count (est.) |
|---|---|---|
| `IntakeCollectionsService-main` | Online intake backend (Spring Boot 3.3, Java 21, SpiffWorkflow BPMN engine). REST API for session/task management. Login.gov OIDC auth | 5 REST + SpiffWorkflow gateway |
| `IntakeCollectionsUI-main` | Angular 19 intake frontend (USWDS design system) | N/A (UI) |
| `IntakeCollectionsWorkflow-main` | BPMN/DMN workflow definitions for FOI intake (demographics, screening, allegations, ICS). ~70 JSON schemas | N/A (workflow config) |
| `FederalHearings-ims-aks` | Federal sector hearings (Spring Boot 3.x). 26 controllers, 38 JPA entities in `fed_hearings` schema. Full case lifecycle: hearings, conferences, claims, ADR, assessments, transfers, stays | ~80+ |
| `FederalWebService-ims-aks` | Federal sector gateway bridging FederalHearings to legacy IMS. Hearing/appeal CRUD, agency lists, PDF reports | ~25 |
| `FedSep-ims-aks-test` | Legacy JSP/Servlet app (not REST). Federal separation processing | 0 (JSP only) |
| `FedSep-NG-ims-aks-test` | Angular 16 SPA frontend for FedSep appeals | N/A (UI) |
| `ContentGeneratorWebService-ims-aks` | Stateless document generation service. Template merge, format conversion (DOC/DOCX/PDF), PDF digital signing via BouncyCastle | 1 (multipart POST) |
| `ECMService-ims-aks-test` | Alfresco ECM wrapper. Document CRUD, folder ops, ZIP download. Schema `ecm` with event log | 14 |
| `EmailWebService-ims-aks-test` | SendGrid email delivery. Send with attachments, activity logging, webhook events, PDF export of email history | 13 |
| `TemplateMangementWebService-ims-aks-test` | Template CRUD and versioning. Schema `tmplmgmt`, ad-hoc attribute support, preview and document generation | 13 |
| `LitigationWebService-main` | Litigation case entities (17 JPA entities: LitigationCase, allegations, assignments, benefits, defendants). Controller stub exists but has zero active endpoints | 0 (entities only) |
| `EmployerWebService-ims-aks-test` | Employer data service with PostgreSQL + Elasticsearch dual store. NAICS lookup, employer search (fuzzy, wildcard, address), EEO-1 data, contact management | ~30 |
| `EEOCWebService-master` | Legacy JAX-WS SOAP service (pre-ARC). IMS entities. No REST endpoints | 0 (SOAP/legacy) |
| `ImsNXG-master` | Legacy/incomplete project; unclear purpose | 0 |
| `ImsNXG-NG-ims-aks-test` | Angular frontend application with service stubs for all ARC backends | N/A (UI) |
| `SearchDataWebService-ims-aks-test-es8` | Elasticsearch 8 indexer/search. Indices: casedetail, eventlog, hearing-case-detail, hearing-event-log, litigation-detail. Consumes `db-change-topic` and `federal-hearing-topic` from Service Bus | ~10 |
| `AuthorizationService-ims-aks` | OAuth2 Authorization Server (token endpoint). Azure AD Graph API integration. Clients: ecm, prepa, imsnxg-ng + 5 more | 1 (OAuth token) |
| `AzureAdService-main` | Azure AD user/group management via MS Graph API. User search, group assignment, guest invitations | 5 |
| `UserManagementWebService-master` | User lifecycle with Hibernate Envers audit. Users, roles, offices, domains, permissions. Publishes to `user-management-topic` Service Bus | ~20 |
| `AttorneyPortal-main` | React/Node.js frontend with Form.io integration | N/A (UI) |
| `RespondentPortal-ims-aks` | JSF/WildFly portal. Session-based auth with charge number + password. Integrates with PrEPA, Alfresco, EML | 0 (JSF, not REST) |
| `BIRTReports-master` | BIRT report definitions (EEOC-462, MD715, workforce analysis). XML report designs connecting to IMS/PostgreSQL | N/A (report config) |
| `Utilities-master` | Shared email DTOs (RequestVO, ResponseVO), ApplicationEventLog entity, Alfresco utilities, mass mail tools | N/A (library) |

### 4.4 Infrastructure Repos (No API Endpoints)

| Repo | Contents |
|---|---|
| `azure-extmgmt-ansible-master` | Ansible playbooks for ARC infrastructure (Oracle IMS DB, Graylog, Nagios, bastion hosts) |
| `azure-extmgmt-design-master` | Architecture diagrams: 5 Azure subscriptions (network, ops, dev, test/UAT, production) |
| `azure-extmgmt-er-master` | ExpressRoute configuration for on-premises connectivity |
| `azure-extmgmt-helm-master` | Helm charts for 13 ARC services on AKS. Key deployment configs per service |
| `azure-extmgmt-prod-master` | Terraform IaC: PostgreSQL Flex, ConfigMaps, Service Bus, Key Vault |
| `AT_ARC_UI-ARC_UI_Automation` | Cucumber BDD UI automation (public portal scenarios) |
| `AT_ScenarioRunner-main` | Integration test scenario runner (TEST, UAT, LITTEST environments) |
| `alfresco-content-services-helm-master` | Alfresco Content Services Helm chart (v6.0+) |

### 4.5 ARC Internal Architecture (from Helm/Terraform)

**Internal Kubernetes Service URLs** (from `azure-extmgmt-helm-master` and `azure-extmgmt-prod-master`):

| Service | Internal URL | Port | Replicas (prod) |
|---|---|---|---|
| prepaws | `http://prepaws/prepa` | 9000 | ~5 |
| fepagateway | `http://fepagateway/gateway` | 8080 | ~10 |
| authsvc | `http://authsvc/oauth` | 9000 | ~5 |
| ecmsvc | `http://ecmsvc/ecm` | 9000 | ~7 |
| emailws | `http://emailws/ews/v2` | 9000 | — |
| searchdataws | `http://searchdataws/searchws` | 9000 | — |
| federalws | `http://federalws/federalws` | 9000 | ~5 |
| litigation | `http://litigation/litigation` | 9000 | ~3 |
| contentgen | `http://contentgen/content-generator` | 9000 | — |
| templatemgmtws | `http://templatemgmtws/tms/v1` | 9000 | — |
| usermgmtws | `http://usermgmtws/UserManagement` | 9000 | — |
| employerws | `http://employerws/empdb` | — | — |
| imsnxgng | `http://imsnxgng/` | 80 | ~3 |
| respondentportal | redirect to `/rsp` | 80 | — |

**Azure Service Bus Topics** (from `service_bus.tf`):

| Topic | Subscriptions | Purpose |
|---|---|---|
| `db-change-topic` | searchDataWS | PrEPA database change notifications for Elasticsearch reindexing |
| `document-activity-topic` | IMS Module, FederalHearings (filtered: `TARGET_DOMAIN='HEARING'`) | Document upload/change events from ECM |
| `user-management-topic` | prepa-subscriber, litigation-subscriber | User lifecycle events (create, update, disable) |

**Database** (PostgreSQL Flex Server): Host `eus1-prod-arcdb-*.postgres.database.azure.com`, database `ims`. Schema users: `s_admin`, `s_ecm`, `s_search`, `s_private`, `s_tmplmgmt`, `s_fed_hearings`. Legacy IMS Oracle DB also accessible via `federalws`.

---

## 5. Gap Findings

### 5.1 PrEPA Endpoint Gaps

| # | Gap Type | ARC Resource | Endpoints | Affected Repos | Priority | Rationale |
|---|---|---|---|---|---|---|
| P-01 | New endpoint group | Enforcement — position statements, fact-finding, subpoenas | ~12 | arc-integration-api, ogc-trialtool, analytics | **High** | OGC TrialTool needs enforcement activity data for trial preparation; analytics needs investigation metrics |
| P-02 | New endpoint group | Enforcement — conciliation | ~4 | arc-integration-api, ofs-adr, analytics | **High** | Conciliation follows mediation; ADR and analytics need resolution outcome data |
| P-03 | New endpoint group | Enforcement — conferences | ~4 | arc-integration-api, ogc-trialtool, analytics | **Medium** | Conference scheduling supports investigation workflow |
| P-04 | New endpoint group | Closure — allegation-level close and benefit-groups | ~10 | arc-integration-api, ofs-adr, analytics | **High** | ADR posts high-level close but cannot close individual allegations or manage benefit groups per allegation |
| P-05 | New endpoint group | Closure — NRTS document generation | ~2 | arc-integration-api, ofs-triage | **High** | Triage triggers NRTS via `trigger_nrts` but cannot generate the actual NRTS document; ARC's `/closure/generation-of-nrts` does this |
| P-06 | New endpoint group | Closure — reason codes and admin reasons | ~4 | arc-integration-api, analytics | **Medium** | Reference data for closure types; enriches analytics closure breakdowns |
| P-07 | New endpoint group | FEPA credit request/response | ~16 | arc-integration-api, analytics | **Medium** | Cross-agency credit tracking not surfaced in platform; relevant for FEPA coordination analytics |
| P-08 | New endpoint group | Dual filing/deferral | ~12 | arc-integration-api, analytics | **Medium** | Dual-filing workflow between EEOC and FEPAs; needed for accurate charge counts and jurisdiction analytics |
| P-09 | New endpoint group | Systemic cases | ~18 | arc-integration-api, analytics, mcp-hub | **High** | Systemic investigations (multi-charge, multi-employer) are a core EEOC function; zero visibility in platform |
| P-10 | New endpoint group | Case notes (particular, mediation, general) | ~12 | arc-integration-api, ofs-adr, ogc-trialtool | **Medium** | ADR mediators and OGC attorneys need case notes from ARC; currently siloed |
| P-11 | New endpoint group | Case review/approval workflow | ~6 | arc-integration-api, analytics | **Medium** | Review assignments and approvals affect case disposition timing; relevant for performance analytics |
| P-12 | New endpoint group | Transfer management | ~3 | arc-integration-api, analytics | **Medium** | Case transfers between offices affect jurisdiction and workload analytics |
| P-13 | New endpoint group | Suspension management | ~7 | arc-integration-api, analytics | **Medium** | Suspended cases affect aging metrics; must exclude from active caseload calculations |
| P-14 | New endpoint group | Timetap scheduling | ~3 | arc-integration-api, ofs-adr | **Low** | Scheduling integration through Timetap; ADR has its own scheduling |
| P-15 | New endpoint group | RFI (Request for Information) | ~3 | arc-integration-api, ogc-trialtool | **Medium** | RFI documents are part of the investigative record; OGC needs access |
| P-16 | New endpoint group | Interview scheduling | ~3 | arc-integration-api | **Low** | Interview scheduling for investigations; not directly consumed by current apps |
| P-17 | New endpoint group | Compliance determination | ~1 | arc-integration-api, analytics | **Low** | Post-resolution compliance tracking |
| P-18 | New endpoint group | Court hearing management | ~4 | arc-integration-api, ogc-trialtool | **High** | OGC TrialTool has minimal integration; court hearing CRUD is essential for trial preparation |
| P-19 | New endpoint group | Office detail (district, location, zipcode) | ~13 | arc-integration-api, reference data | **Medium** | Current `/reference/offices` is basic; PrEPA exposes rich office data including location, zipcode lookup, district hierarchy |
| P-20 | New endpoint group | User lookup | ~2 | arc-integration-api | **Low** | Staff resolution for analytics; currently handled through CDC view workaround |
| P-21 | New endpoint group | Document generation (COD, NOC, investigative file) | ~5 | arc-integration-api, ofs-adr, ogc-trialtool | **Medium** | Charge of Discrimination, Notice of Charge, and investigative file downloads needed for case completeness |
| P-22 | New endpoint group | Respondent portal credentials | ~3 | arc-integration-api | **Low** | Internal portal management; not needed for AI platform |
| P-23 | New endpoint group | Case folder management | ~7 | arc-integration-api | **Low** | Internal organizational tool within ARC |
| P-24 | New endpoint group | Class group management | ~7 | arc-integration-api, analytics | **Low** | Class action grouping; niche use case |
| P-25 | New endpoint group | Assessment | ~2 | arc-integration-api | **Low** | Case quality assessment areas |
| P-26 | New endpoint group | FOIA requests | ~3 | arc-integration-api | **Low** | Freedom of Information Act request tracking; separate workflow |
| P-27 | Schema drift | Charging party detail | GET /v1/cases/{id}/chargingparty (GET, PUT) | arc-integration-api, analytics | **Medium** | We read charging party via CDC but never via REST; no portal account management |
| P-28 | Schema drift | Respondent detail | /v1/cases/{id}/respondent (GET, PUT), additional respondents, addresses | arc-integration-api, analytics | **Medium** | We read respondent via CDC but REST endpoints expose additional respondent data |
| P-29 | New endpoint | Event log detail operations | GET by eventCode, PUT, DELETE, download/{docExt} | arc-integration-api | **Low** | We POST events but cannot read by event code, update, or delete individual events |
| P-30 | New endpoint | Report/PowerBI | GET /v1/report/powerbi | analytics | **Low** | PowerBI token generation; analytics dashboard may benefit |
| P-31 | New endpoint | Case status update with reason | PUT /v1/cases/{id}/case-status-update-with-reason | arc-integration-api | **Medium** | More granular status transitions than current PATCH |

### 5.2 FEPA Gateway Gaps

| # | Gap Type | ARC Resource | Affected Repos | Priority | Rationale |
|---|---|---|---|---|---|
| G-01 | New endpoint group | FEPA case management (CRUD, validation, reopen, representatives) | arc-integration-api | **Medium** | Needed if platform handles FEPA-originated charges directly |
| G-02 | New endpoint group | FEPA reporting (office-level reports) | arc-integration-api, analytics | **Medium** | Office-level charge reports by receiving/deferral/accountability code |
| G-03 | New endpoint group | Attorney Portal data lookups (NAICS, employer, zipcode) | arc-integration-api, reference data | **Medium** | NAICS and employer lookups useful for respondent data enrichment |
| G-04 | New endpoint group | Public Portal charge submission and management | arc-integration-api | **Low** | Public-facing charge intake; IntakeCollections handles this |
| G-05 | New endpoint group | FOIA case operations | arc-integration-api | **Low** | FOIA tracking through gateway |
| G-06 | Unmapped endpoint | Document upload/delete | arc-integration-api | **Medium** | We can download but not upload/delete through gateway |

### 5.3 Unintegrated Service Gaps

| # | Gap Type | ARC Service | Affected Repos | Priority | Rationale |
|---|---|---|---|---|---|
| S-01 | Missing service | FederalWebService — federal sector case handling | arc-integration-api, ofs-triage, analytics | **High** | Federal sector charges (~40% of EEOC caseload) use different workflows; Triage classifies both sectors but lacks federal data paths |
| S-02 | Missing service | FederalHearings — hearing scheduling and management | arc-integration-api, analytics | **High** | Federal hearings are a distinct EEOC function; zero visibility in analytics |
| S-03 | Missing service | FedSep-NG — federal sector separation process | arc-integration-api | **Medium** | Federal employee separation proceedings; active development |
| S-04 | Missing service | IntakeCollectionsService — online intake workflows | arc-integration-api, ofs-triage | **Medium** | Intake events could feed Triage earlier in the lifecycle |
| S-05 | Missing service | ContentGeneratorWebService — document generation | arc-integration-api, ofs-adr | **Medium** | Centralized document generation; ADR could request agreement documents |
| S-06 | Missing service | EmployerWebService — employer data (EEO-1, matching) | arc-integration-api, analytics | **Medium** | EEO-1 employer data, NAICS resolution, employer matching scores |
| S-07 | Missing service | SearchDataWebService — Elasticsearch search | arc-integration-api, mcp-hub | **Medium** | Full-text search across ARC data; could power MCP search tool |
| S-08 | Missing service | EmailWebService — email delivery | arc-integration-api | **Low** | Transactional email; apps have their own email via Azure |
| S-09 | Missing service | TemplateMangementWebService — templates | arc-integration-api | **Low** | Template CRUD; internal ARC concern |
| S-10 | Missing service | ECMService — Alfresco ECM | arc-integration-api | **Low** | Direct ECM access; we proxy through PrEPA/Gateway |
| S-11 | Missing service | AuthorizationService — RBAC | arc-integration-api | **Low** | ARC's internal RBAC; we use Entra ID roles |
| S-12 | Missing service | ImsNXG-NG — next-gen case management | arc-integration-api | **Low** | Appears to be ARC's replacement UI; overlaps with PrEPA data |
| S-13 | Missing service | EEOCWebService — core service | arc-integration-api | **Low** | Legacy service layer; functionality available through PrEPA |
| S-14 | Missing service | LitigationWebService — 17 JPA entities (LitigationCase, LitigationAllegation, LitigationAssignment, LitigationBenefit, LitigationDefendantAssc, LitigationChargeAssc, etc.) but controller has zero active endpoints. Entities define schema for `litigation_case`, `litigation_allegation`, `litigation_assignment`, `litigation_benefit`, `litigation_benefit_detail` tables | arc-integration-api, ogc-trialtool | **Medium** | Rich data model exists but no REST surface yet; OGC reads from PrEPA generic case endpoint. When ARC activates these endpoints, we need a LitigationClient |

### 5.4 Data Middleware Gaps

| # | Gap Type | Source Entity | Target Table (proposed) | Priority | Rationale |
|---|---|---|---|---|---|
| D-01 | Unmapped entity | `charging_party_race` | `analytics.charging_party_races` | **Medium** | Multi-valued race data; required for demographic analytics per EEO reporting |
| D-02 | Unmapped entity | `conciliation` (enforcement) | `analytics.conciliations` | **High** | Post-cause conciliation outcomes; feeds ADR and analytics |
| D-03 | Unmapped entity | `benefit_group` / `beneficiary` | `analytics.benefits` | **High** | Detailed remedy/benefit data by allegation; essential for outcome analytics |
| D-04 | Unmapped entity | `suspension` | `analytics.suspensions` | **Medium** | Suspension periods must be excluded from aging calculations |
| D-05 | Unmapped entity | `systemic_case` + related | `analytics.systemic_cases` | **Medium** | Systemic investigation tracking; high-profile enforcement actions |
| D-06 | Unmapped entity | `case_note` (mediation, particular, general) | `analytics.case_notes` | **Low** | Notes contain investigation context; PII-heavy, AI use case only |
| D-07 | Unmapped entity | `case_review` | `analytics.case_reviews` | **Low** | Review/approval data; niche analytics use case |
| D-08 | Unmapped entity | `rfi` (Request for Information) | `analytics.rfis` | **Low** | RFI tracking; investigation process metric |
| D-09 | Unmapped entity | `enforcement_conference` | `analytics.enforcement_conferences` | **Medium** | Conference scheduling tied to enforcement outcomes |
| D-10 | Unmapped entity | `court_hearing` | `analytics.court_hearings` | **Medium** | Hearing dates and outcomes for litigation cases |
| D-11 | Unmapped entity | `transfer_request` | `analytics.transfers` | **Medium** | Case transfers affect office workload metrics |
| D-12 | Unmapped entity | `interview` (mediation_interview extended) | Extend `analytics.mediation_sessions` | **Low** | Interview scheduling beyond what mediation_interview covers |

### 5.5 MCP Hub Gaps

| # | Gap Type | Proposed Tool | Priority | Rationale |
|---|---|---|---|---|
| M-01 | Missing tool | `arc_get_enforcement_status` — read enforcement activity | **High** | OGC and Triage need enforcement context |
| M-02 | Missing tool | `arc_get_systemic_cases` — search/read systemic investigations | **Medium** | Cross-charge pattern detection |
| M-03 | Missing tool | `arc_get_case_notes` — read case notes | **Medium** | AI summarization of case notes |
| M-04 | Missing tool | `arc_get_closure_reasons` — reference data | **Medium** | Enriches AI classification context |
| M-05 | Missing tool | `arc_get_suspension_status` — check if case suspended | **Medium** | Prevents acting on suspended cases |
| M-06 | Missing tool | `arc_search_elasticsearch` — full-text search | **Medium** | More powerful search than current PrEPA search |
| M-07 | Missing tool | `arc_get_court_hearings` — litigation schedule | **Medium** | OGC trial preparation |
| M-08 | Missing tool | `arc_get_federal_hearing` — federal hearing data | **High** | Federal sector case handling |

### 5.6 Event Subscription Gaps

The ARC Service Bus has three topics that the AI Platform does not subscribe to:

| # | Topic | Current Subscribers | Platform Gap | Priority |
|---|---|---|---|---|
| E-01 | `db-change-topic` | searchDataWS only | Platform could subscribe for real-time CDC notifications instead of polling. Would eliminate sync latency for analytics dashboard. | **High** |
| E-02 | `document-activity-topic` | IMS Module, FederalHearings | Platform has no document event subscription. ADR and Triage could react to document uploads in real time (e.g., position statement filed → notify mediator). | **Medium** |
| E-03 | `user-management-topic` | prepa-subscriber, litigation-subscriber | Platform has no staff change subscription. Analytics staff_assignments table goes stale until next CDC sync. | **Medium** |

### 5.7 Feature Flag Gaps

| # | Flag Needed | Default | Affected Repos | Priority |
|---|---|---|---|---|
| F-01 | `ENFORCEMENT_SYNC_ENABLED` | `false` | arc-integration-api, analytics | **High** |
| F-02 | `FEDERAL_SECTOR_ENABLED` | `false` | arc-integration-api, ofs-triage | **High** |
| F-03 | `SYSTEMIC_CASES_ENABLED` | `false` | arc-integration-api | **Medium** |
| F-04 | `FEPA_CREDIT_ENABLED` | `false` | arc-integration-api | **Medium** |
| F-05 | `DUAL_FILING_ENABLED` | `false` | arc-integration-api | **Medium** |
| F-06 | `EMPLOYER_SERVICE_ENABLED` | `false` | arc-integration-api | **Medium** |
| F-07 | `SEARCH_ELASTICSEARCH_ENABLED` | `false` | arc-integration-api | **Medium** |

---

## 6. Recommended Changes

### 6.1 High Priority — Blocks Data Flow or Compliance

#### 6.1.1 Enforcement Data Integration (P-01, P-02, D-02, D-03, M-01, F-01)

**arc-integration-api — new service client methods:**

```
# PrepaClient additions
async def get_enforcement_position_statements(case_id: str) -> list[dict]
    # GET /v1/cases/enforcement/position-statement/{caseId}
async def get_enforcement_fact_finding(case_id: str) -> list[dict]
    # GET /v1/cases/enforcement/fact-finding/{caseId}
async def get_enforcement_subpoenas(case_id: str) -> list[dict]
    # GET /v1/cases/enforcement/subpoena/{caseId}
async def get_enforcement_communications(case_id: str) -> list[dict]
    # GET /v1/cases/enforcement/communication/{caseId}
async def get_conciliation(case_id: str) -> dict
    # GET /v1/cases/{caseId}/enforcement/conciliation
```

**New router:** `app/routers/enforcement.py` — exposes enforcement data to OGC TrialTool and analytics.

**data-middleware — new YAML mappings:**
- `source_mappings/prepa_conciliation.yaml` — conciliation outcomes to `analytics.conciliations`
- `source_mappings/prepa_benefits.yaml` — benefit/remedy detail to `analytics.benefits`

**MCP Hub — new tool:** `arc_get_enforcement_status`

#### 6.1.2 Federal Sector Integration (S-01, S-02, M-08, F-02)

FederalHearings has 26 REST controllers and 38 JPA entities (schema `fed_hearings`). Key entities: `hearing_case`, `hearing_complainant`, `hearing_agency`, `hearing_claims`, `hearing_conference`, `hearing_action`, `hearing_note`, `hearing_assessment`, `hearing_assignment`, `hearing_allegation`, `hearing_stay`, `hearing_transfer`, `hearing_event_log`. Roles include `HEARING_ADMIN_JUDGE`, `HEARING_COMPLAINANT`, `ADR_COORDINATOR`, etc.

FederalWebService bridges to legacy IMS with hearing/appeal CRUD and PDF report generation.

**arc-integration-api — new service clients:**

```
# New: FederalHearingsClient (services/federal_hearings_client.py)
# Base URL: http://federalws/federalws (gateway) or direct to FederalHearings
class FederalHearingsClient:
    async def get_hearing_cases(agency_code: str, status: str) -> list[dict]
        # GET /v1/hearings/cases/agencies/{agency-code}/status/{status}
    async def get_hearing_case(case_id: str) -> dict
        # GET /v1/hearings/{id}
    async def get_hearing_actions(case_id: str) -> list[dict]
        # GET /v1/hearings/{id}/actions
    async def get_hearing_conferences(case_id: str) -> list[dict]
        # GET /v1/hearings/{id}/conferences
    async def get_hearing_claims(case_id: str) -> list[dict]
        # GET /v1/hearings/{id}/claims
    async def get_hearing_assessment(case_id: str) -> dict
        # GET /v1/hearings/{id}/assessment
    async def get_hearing_domain_lookup(domain: str) -> list[dict]
        # GET /v1/common/lookup/domain/{domainName}
```

**New router:** `app/routers/federal.py` — federal sector data for Triage and analytics.

**Config:** New `ARC_FEDERAL_HEARINGS_URL` setting (targets `http://federalws/federalws`). Feature flag `FEDERAL_SECTOR_ENABLED=false`.

**Triage impact:** `ofs-triage` classifies federal charges but has no read-back path for federal-specific data. New `arc_lookup.py` methods needed for federal charge metadata.

#### 6.1.3 Systemic Cases (P-09, M-02, F-03)

**arc-integration-api — new service client methods:**

```
# PrepaClient additions
async def get_systemic_cases(params: dict) -> dict
    # GET /v1/cases/systemic-cases
async def get_systemic_case(id: str) -> dict
    # GET /v1/cases/systemic-case/{id}
async def get_systemic_case_charges(id: str) -> list[dict]
    # GET /v1/cases/{chargeId}/systemic-case
```

**New router:** `app/routers/systemic.py`

**MCP Hub — new tool:** `arc_get_systemic_cases`

#### 6.1.4 Court Hearing Data for OGC (P-18)

**arc-integration-api — new service client methods:**

```
# PrepaClient additions
async def get_court_hearings(case_id: str) -> list[dict]
    # GET /v1/cases/{caseId}/court-hearing
async def create_court_hearing(case_id: str, data: dict) -> dict
    # POST /v1/cases/{caseId}/court-hearing
async def update_court_hearing(case_id: str, data: dict) -> dict
    # PUT /v1/cases/{caseId}/court-hearing
```

**OGC TrialTool impact:** `ogc-trialtool` currently reads only `LitigationCase` from a generic PrEPA case endpoint. Court hearing CRUD is essential for trial scheduling.

#### 6.1.5 Allegation-Level Closure and Benefits (P-04, P-05)

**arc-integration-api — PrepaClient additions:**

```
async def close_allegation(case_id: str, allegation_id: str, data: dict) -> dict
    # POST /v1/cases/{caseId}/allegations/{allegationId}/close
async def get_benefit_groups(case_id: str) -> list[dict]
    # GET /v1/cases/{caseId}/allegations/benefit-groups
async def assign_benefits(case_id: str, data: dict) -> dict
    # POST /v1/cases/{caseId}/allegations/assignment-of-benefits
async def generate_nrts(case_id: str) -> dict
    # POST /v1/cases/{caseId}/closure/generation-of-nrts
```

**ADR Portal impact:** `ofs-adr` posts high-level closure but cannot manage allegation-level closures or structured benefit assignments. These endpoints complete the ADR closure workflow.

### 6.2 Medium Priority — Enriches Existing Features

#### 6.2.1 FEPA Credit and Dual Filing (P-07, P-08, F-04, F-05)

**arc-integration-api — PrepaClient additions:**

```
async def get_credit_requests(case_id: str) -> list[dict]
    # GET /v1/credit-request/{caseId}
async def get_deferral_info(case_id: str) -> dict
    # GET /v1/cases/{caseId}/deferralinfo
```

**Middleware YAML:** No immediate CDC mapping needed; accessible via REST for analytics dashboards.

#### 6.2.2 Case Notes Access (P-10, M-03)

**arc-integration-api — PrepaClient additions:**

```
async def get_case_notes(case_id: str) -> list[dict]
    # GET /v1/cases/{caseId}/notes
async def get_mediation_notes(case_id: str) -> list[dict]
    # GET /v1/cases/{caseId}/notes/mediation
```

**MCP Hub — new tool:** `arc_get_case_notes` — enables AI summarization of case history.

**PII:** Notes contain PII. Must apply `_mask_pii()` before any AI processing or analytics storage.

#### 6.2.3 Suspension Status (P-13, M-05, D-04)

**arc-integration-api — PrepaClient additions:**

```
async def get_suspension(case_id: str) -> dict
    # GET /v1/cases/{chargeInquiryId}/suspendnoc
async def get_suspension_reasons() -> list[dict]
    # GET /v1/cases/suspension/reasons
```

**data-middleware:** New `prepa_suspensions.yaml` mapping `suspension` entity to `analytics.suspensions`. Suspension periods must adjust `days_to_resolution` in analytics.

#### 6.2.4 Rich Office Reference Data (P-19)

**arc-integration-api — PrepaClient additions:**

```
async def get_district_offices() -> list[dict]
    # GET /v1/offices/district
async def get_office_by_zipcode(zip_code: str) -> dict
    # GET /v1/offices/zipcode/{zipCode}
async def get_all_office_details() -> list[dict]
    # GET /v1/all/offices/details
async def get_office_locations() -> list[dict]
    # GET /v1/all/offices/location/details
```

**Impact:** Replaces the static `lookups/district_offices.csv` and `lookups/region_codes.csv` with live ARC data. Resolves the NEEDS_DATA gap in `prepa_charges.yaml` for office-to-region mapping.

#### 6.2.5 Employer Data Enrichment (S-06, G-03, F-06)

EmployerWebService has ~30 endpoints with PostgreSQL + Elasticsearch dual store. Key endpoints: NAICS code lookup (`/empdb/census/v1/naics/{code}`), employer search by name/zip/address (`/empdb/es/v2/employer/search`), fuzzy search (`/empdb/es/v1/employer/fuzzy/search`), EEO-1 data (`/empdb/es/v1/eeo/search`), and employer CRUD. Entity model includes `Employer` (with EIN, DUNS, CAGE, NAICS, employee count, franchise flag) and `EmployerContact`.

**arc-integration-api — new client:**

```
# New: EmployerClient (services/employer_client.py)
# Base URL: http://employerws/empdb
class EmployerClient:
    async def get_naics_code(code: str) -> dict
        # GET /empdb/census/v1/naics/{code}
    async def search_naics(description: str) -> list[dict]
        # GET /empdb/census/v2/naics?description={description}
    async def search_employer(name: str, zip_code: str) -> list[dict]
        # GET /empdb/es/v2/employer/search?name={name}&zipCode={zip}
    async def get_employer(employer_id: str) -> dict
        # GET /empdb/es/v1/employer/id/{employerId}
    async def search_eeo1(survey_ids: list[str]) -> list[dict]
        # GET /empdb/es/v1/employer/eeo1/id?eeoSurveyIds={ids}
```

**data-middleware:** Add `lookups/naics_codes.csv` from EmployerWebService bulk export (resolves NEEDS_DATA in `prepa_respondent.yaml`). Alternatively, call `/empdb/census/v2/naics/all` at sync time.

#### 6.2.6 Closure Reason Reference Data (P-06, M-04)

**arc-integration-api — PrepaClient additions:**

```
async def get_closure_reason_codes() -> list[dict]
    # GET /v1/cases/closure/reasoncodes
async def get_closure_admin_reasons() -> list[dict]
    # GET /v1/cases/closure/adminreasons
async def get_adr_benefit_codes() -> list[dict]
    # GET /v1/cases/benefit/adrcodes
```

**Impact:** Reference data that enriches analytics closure breakdowns and AI classification context.

#### 6.2.7 Transfer Tracking (P-12, D-11)

**arc-integration-api — PrepaClient additions:**

```
async def get_transfers() -> list[dict]
    # GET /v1/cases/transfers
```

**data-middleware:** New `prepa_transfers.yaml` mapping to `analytics.transfers`.

#### 6.2.8 Charging Party Race (D-01)

**data-middleware — new YAML:**
- `source_mappings/prepa_charging_party_race.yaml`

```yaml
source:
  driver: "eventhub"
  topic: "prepa.public.charging_party_race"
  primary_key: "charging_party_race_id"
target:
  schema: "analytics"
  table: "charging_party_races"
  primary_key: "race_entry_id"
columns:
  - source: "charging_party_id"
    target: "party_id"
    type: "uuid"
    transform: "computed"
    expression: "UUID_V5('prepa.charging_party', source.charging_party_id)"
  - source: "race_id"
    target: "race"
    type: "varchar(50)"
    transform: "lookup_table"
    lookup_config:
      join_table: "replica.shared_code"
      join_key: "shared_code_id"
      value_column: "description"
```

#### 6.2.9 SearchDataWebService Integration (S-07, M-06, F-07)

**arc-integration-api — new client:**

```
# New: SearchClient (services/search_client.py)
class SearchClient:
    async def search(query: str, filters: dict, limit: int) -> dict
```

**Config:** New `ARC_SEARCH_URL` setting. Feature flag `SEARCH_ELASTICSEARCH_ENABLED=false`.

**MCP Hub — new tool:** `arc_search_elasticsearch` — enables more powerful full-text search than current PrEPA `/cases/search`.

#### 6.2.10 Litigation Service (S-14)

**arc-integration-api:** Investigate `LitigationWebService-main` for litigation-specific data. Current `get_litigation_case` in `routers/litigation.py` calls the generic `prepa.get_case()`. If LitigationWebService exposes distinct endpoints, wire a `LitigationClient`. If empty (appears to be a placeholder), document and defer.

---

## 7. Implementation Phasing

### Phase 1 — High Priority (Q3 2026)

| Work Item | Gap IDs | Effort (est.) |
|---|---|---|
| Enforcement data integration | P-01, P-02, D-02, D-03, M-01, F-01 | 2 weeks |
| Federal sector client and router | S-01, S-02, M-08, F-02 | 2 weeks |
| Court hearing CRUD for OGC | P-18 | 3 days |
| Allegation-level closure and benefits | P-04, P-05 | 1 week |
| Systemic cases | P-09, M-02, F-03 | 1 week |

### Phase 2 — Medium Priority (Q4 2026)

| Work Item | Gap IDs | Effort (est.) |
|---|---|---|
| FEPA credit and dual filing | P-07, P-08, F-04, F-05 | 1 week |
| Case notes access | P-10, M-03 | 3 days |
| Suspension tracking | P-13, M-05, D-04 | 3 days |
| Rich office reference data | P-19 | 2 days |
| Employer/NAICS enrichment | S-06, G-03, F-06 | 3 days |
| Closure reason reference data | P-06, M-04 | 2 days |
| Transfer tracking | P-12, D-11 | 2 days |
| Charging party race mapping | D-01 | 1 day |
| Elasticsearch search | S-07, M-06, F-07 | 3 days |

### Phase 3 — Low Priority (2027+)

| Work Item | Gap IDs |
|---|---|
| Case review/approval | P-11, D-07 |
| Case notes CDC mapping | D-06 |
| RFI access | P-15, D-08 |
| Interview scheduling | P-16, D-12 |
| Compliance determination | P-17 |
| Timetap scheduling | P-14 |
| Portal services (Attorney, Respondent) | G-04, P-22 |
| FOIA integration | P-26, G-05 |
| Case folder/class group | P-23, P-24 |
| Assessment | P-25 |
| Document generation direct | P-21 |
| Event log detail operations | P-29 |
| PowerBI reporting token | P-30 |

---

## 8. Coverage Summary

| Layer | Current | After Phase 1 | After Phase 2 |
|---|---|---|---|
| PrEPA endpoints wired | 18 (~7%) | ~45 (~16%) | ~70 (~25%) |
| FepaGateway endpoints wired | 4 (~4%) | 4 (~4%) | ~10 (~10%) |
| ARC services integrated | 2 of 26 | 5 of 26 | 8 of 26 |
| CDC entity mappings | 7 PrEPA | 10 PrEPA | 14 PrEPA |
| MCP tools | 18 | 24 | 32 |
| Feature flags | 4 existing | 6 | 11 |

**Note:** Not all ARC endpoints need wiring. Many are internal ARC UI operations (case
folder management, portal credential management, Angular error logging) that have no
consumer in the AI platform. The percentages above reflect API coverage, not
functional coverage. Functional coverage is substantially higher because the wired
endpoints serve the primary data flows.

---

## 9. Attestation

- [x] All 34 ARC repos analyzed (excluding `-clean` exports)
- [x] All current integration code reviewed (`arc-integration-api`, `data-middleware`, downstream apps)
- [x] Gaps categorized by type, priority, and affected repos
- [x] Recommendations include specific method signatures and YAML structures
- [x] No code changes made; document only

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | April 2026 | Derek Gordon / OIT | Initial gap analysis across 34 ARC repos |
