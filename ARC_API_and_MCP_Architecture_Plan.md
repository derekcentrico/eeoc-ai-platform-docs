# ARC API & MCP Server Architecture Plan

**Date:** 2026-03-30
**Scope:** REST API layer over ARC backbone + MCP hub for ADR, OFS Triage, UDIP, and OGC Trial Tool

---

## Table of Contents

1. [ARC Backbone: What We Actually Have](#1-arc-backbone-what-we-actually-have)
2. [The Four Apps: What They Need](#2-the-four-apps-what-they-need)
3. [Where the MCP Hub Document Falls Short](#3-where-the-mcp-hub-document-falls-short)
4. [REST API Layer Design](#4-rest-api-layer-design)
5. [MCP Server Architecture](#5-mcp-server-architecture)
6. [Implementation Roadmap](#6-implementation-roadmap)

---

## 1. ARC Backbone: What We Actually Have

After reading every source file in both repositories, the picture is clear: the ARC backbone is a two-service stack built for IMS internal use. Neither service was designed to serve downstream applications.

### 1.1 FEPA Gateway (Spring Boot 3.2.1 / Java 17)

This is a BFF (backend-for-frontend) layer. It sits in front of PrEPA and a handful of other services, handling authentication, document management, and request routing. It was built for the IMS Angular frontend and FEPA partner agencies.

76+ endpoints spread across these groups:

| Group | Base Path | Count | What It Does |
|-------|-----------|-------|--------------|
| FEPA Case CRUD | `/gateway/fepagateway/v1/cases` | 18 | Case lifecycle: create, read, update; manage parties, representatives, allegations |
| Document Mgmt | `/gateway/fepagateway/v1/documents` | 7 | Multipart upload, download, delete. Proxies to ECM service |
| Credit Requests | `/gateway/fepagateway/v1/credit-request` | 8 | FEPA credit workflow with beneficiaries and benefits |
| Attorney Portal | `/gateway/efile/attorney` | 2 | E-filing of charges, attorney lookup |
| Token Exchange | `/gateway/{efile|foi}/{attorney|intake}/auth/token` | 2 | Login.gov credential swap for ARC JWT |
| Data Lookups | `/gateway/efile/attorney/data/lookup` | 5 | SBI combinations, NAICS codes, zip-to-city, employer search |
| Public Portal | `/gateway/publicportal` | ~10 | Token generation, case search, document upload for public users |
| FOIA | `/gateway/foia/v1` | 5 | Office code lookup, charge detail, event management |
| NVS (Litigation) | `/gateway/nvs` | ~5 | Litigation case details for the National Visa Service integration |
| IIG (RightNow) | `/gateway/iig` | ~5 | CRM inquiry management |
| EEOC Scheduler | `/gateway/eeocscheduler` | ~10 | Timetap appointment scheduling |

Auth is OAuth2 Resource Server with JWT (RSA public keys, environment-specific PEM files). Login.gov OIDC for the attorney and FOIA portals. Each downstream backend service gets its own credential set.

The Gateway calls six internal services and two external ones:

| Service | What It Does |
|---------|-------------|
| PrEPA (`http://prepaws/prepa`) | Case CRUD, charge management. The real system of record |
| ECM (`http://ecmsvc/ecm/v3`) | Document storage and retrieval |
| Search WS (`http://searchdataws/searchws`) | Full-text case search, event logs |
| EML (`http://employerws/empdb`) | Employer lookup, address validation, NAICS codes |
| Federal WS (`http://federalws/federalws`) | Federal sector employment data |
| Auth Service (`http://authsvc/oauth/token`) | Internal OAuth token generation |
| Timetap (`https://api.timetap.com`) | External scheduling (API key + hash auth) |
| Login.gov (`https://secure.login.gov`) | External identity verification (OIDC/JWKS) |

### 1.2 PrEPA Web Service (Spring Boot 2.4.1 / Java 11)

This is the persistence layer and the actual system of record for discrimination charges. PostgreSQL-backed, with Hibernate Envers for audit history, Azure Service Bus for event streaming, and ShedLock for distributed job scheduling.

200+ endpoints across 25+ resource groups. The important ones:

| Group | Count | What It Does |
|-------|-------|-------------|
| Case CRUD | 15 | Standard, gateway, and federal case creation; read by ID, number, or email |
| Status & Workflow | 4 | Case status transitions, atomic status + staff assignment updates |
| Staff Assignment | 4 | Assign investigators, mediators, attorneys to cases |
| Charging Party / Respondent | 9 | Contact info, address, portal account management |
| Allegations | 8 | Statute/Basis/Issue management with validation |
| Documents | 4 | Upload, list, delete, update metadata (proxied through ECM) |
| Charge of Discrimination | 5 | Generate COD documents, drafts, deformalize, resend notices |
| Closure | 3 | Close case, reopen case, get closure info |
| Mediation/ADR | 3 | Initiate mediation, get status, submit response |
| Enforcement | 4 | Conference scheduling, conciliation |
| Event/Activity Log | 2 | Write and read case activity history |
| Transfer, Suspension, Notes | 8 | Case transfer between offices, holds, free-text notes |
| Reference Data | 5 | Lookup tables for statuses, offices, SBI codes |

Core data model:

| Entity | Key Fields | Relationships |
|--------|-----------|---------------|
| ChargeInquiry | chargeNumber, fepaChargeNumber, statusId, initialInquiryDate, formalizationDate, closureDate, isFepa | Has one ChargingParty, one Respondent, many Allegations, many Staff Assignments, many Events |
| ChargingParty | name, email, phone, SSN, DOB, address, race | Belongs to one ChargeInquiry |
| Respondent | respondentName, phone, address, EIN | Belongs to one ChargeInquiry |
| ChargeAllegation | statute, basisCode, issueCode, causeFinding | Belongs to one ChargeInquiry |
| ChargeAssignment | staffId, isAdr, assignmentType, assignmentDate | Belongs to one ChargeInquiry |

Business rules worth knowing:
- Case lifecycle: Initial Inquiry -> Formalized -> Perfected -> Mediation -> Enforcement -> Closure
- Statute/Basis/Issue (SBI) validation constrains what allegations are valid
- Dual-filing rules for FEPA partner agencies
- ADR eligibility requires: formalized charge, less than 9 months old, not in enforcement, mutual consent
- Optimistic locking on every entity (version field)
- 16+ scheduled jobs running daily (notice generation, closure emails, FEPA sync, systemic case matching)

PrEPA publishes case change events to Azure Service Bus (`db-change-topic`) and consumes document events (`document-activity-topic`) and user management events (`user-management-topic`).

---

## 2. The Four Apps: What They Need

### 2.1 Data Requirements Matrix

### 2.0 Data Flow Summary (all directions)

| Direction | ADR | OFS Triage | UDIP | OGC Trial Tool |
|-----------|-----|------------|------|----------------|
| **Pulls from ARC** | Mediation-eligible cases via ARCSyncImporter | Charge metadata at upload time | Full charge lifecycle via feed endpoints | Litigation case details on demand |
| **Pushes to ARC** | Closure, settlement, signed docs, action dates | Classification results, correction events | None (read-only consumer) | Minimal (litigation milestones) |
| **Pushes to UDIP** | Daily metrics, AI reliance, model drift, scheduling analytics | Daily metrics, correction flows, reliance scores | N/A (UDIP is the destination) | None |
| **Queries UDIP** | Agency-wide analytics, case context, settlement trends | Historical patterns, case distributions | N/A (serves queries to all) | Case history, investigation context |

### 2.1 What Each App Needs from ARC

| What the app needs from ARC | ADR | OFS Triage | UDIP | OGC Trial Tool |
|----------------------------|-----|------------|------|----------------|
| **Case lookup by charge number** | Yes. The ARCSyncImporter pulls cases every 15 minutes | No. Charge numbers are typed in manually | Yes. Charges table ingested via ARC Integration API feed | No. Attorneys upload their own case files |
| **Case metadata (status, dates, office)** | Yes. Imports status, mediation eligibility date, staff assignment date | No | Yes. Full case lifecycle in the analytics schema | No |
| **Charging party details** | Yes. Name and email for participant setup | No | Yes. In the charges fact table (redacted) | No |
| **Respondent details** | Yes. Name and email for participant setup | No. Respondent is freeform text | Yes. In the charges fact table | No |
| **Allegations / SBI codes** | Yes. Imports the statutes field | No. Basis and issue codes are user-provided text | Yes. Basis and issue in the charges table | No |
| **Staff assignments** | Yes. Imports assigned mediator | No | Yes. Investigator ID from Angular cases | No |
| **Case documents** | No. ADR has its own document store | No. Has its own pipeline | No. Uses charge narratives only | No. Local upload only |
| **Office codes** | Yes. Imports office_id and office_name | No | Yes. Region and office from token claims | No |
| **Case status transitions** | Yes. Needs to know when cases enter or exit mediation | No | Yes. Status tracking in angular_cases | No |
| **ADR/mediation data** | This IS the ADR system | No | Yes. ADR outcomes table for settlement metrics | No |
| **Litigation data** | No | No | Partial. Litigation tracking | Yes. Needs court records and hearing details from NVS |
| **Closure/resolution data** | Partial. Needs closure reason | No | Yes. Closure type, days to resolution | No |

### 2.2 What Each App Currently Exposes

| Application | External APIs | MCP Server | Auth |
|-------------|--------------|------------|------|
| **ADR** | Stats API (18 endpoints), MCP REST (13 endpoints), MCP JSON-RPC at `/mcp`, calendar feeds, signature webhooks | 10 tools, 5 resources, 2 prompt templates. Feature-flagged, protocol version 2025-03-26 | Entra ID for staff, Login.gov for parties. MCP uses Entra M2M with MCP.Read/MCP.Write roles |
| **OFS Triage** | MCP REST (9 endpoints), MCP JSON-RPC at `/mcp`, stats API | 9 tools, 7 resources. Feature-flagged, protocol version 2025-03-26 | Entra ID for staff. MCP uses Entra M2M with MCP.Read/MCP.Write roles |
| **UDIP** | MCP REST (5 endpoints), MCP JSON-RPC at `/mcp`, narrative search, document API | Dynamic tool catalog: 3 built-in tools plus N auto-generated from dbt models. Feature-flagged, protocol version 2025-03-26 | Entra ID for staff. MCP uses Entra M2M with Analytics.Read/Analytics.Write roles |
| **OGC Trial Tool** | 3 web API endpoints (ai_feature, case_status, delete_case). No MCP server | None. Has MCP client code in its example_data directory but nothing wired up on the trial tool itself | Demo session auth only. Needs Entra ID before production |

### 2.3 The Three Gaps Nobody Is Talking About

**Gap A: ARC was never built to serve these apps.**

Both FEPA Gateway and PrEPA assume callers are either the IMS Angular frontend or FEPA partner agencies. There is no "ARC API for downstream applications." Each app has worked around this differently:
- ADR polls a `/api/mediation/cases` endpoint that does not exist in the FEPA Gateway or PrEPA codebase. It is either planned or lives in a service we have not seen.
- UDIP bypasses the API layer entirely and pulls from the SQL Server database directly.
- OFS Triage has zero ARC integration. Analysts type charge numbers and metadata in manually.
- OGC Trial Tool has zero ARC integration. Attorneys upload their own documents.

**Gap B: No shared event stream.**

PrEPA already publishes case changes to Azure Service Bus (`db-change-topic`), but only the IMS internal ecosystem consumes it. None of the four apps subscribe. ADR has its own webhook-based event dispatch. OFS Triage is pull-only. UDIP does watermark-based SQL sync. OGC Trial Tool has nothing.

**Gap C: No common machine-to-machine identity model.**

ARC uses OAuth2 with hardcoded service credentials (`imsnxg-ng`, `arcappuser`, etc.). The four apps use Entra ID app registrations with app roles. These two worlds have never been bridged.

---

## 3. Where the MCP Hub Document Falls Short

The MCP Hub Three-Application Integration document covers ADR, OFS Triage, and UDIP. After comparing it against the actual codebases, here is what holds up, what is missing, and where it conflicts with reality.

### 3.1 What Holds Up

| Claim | Verdict |
|-------|---------|
| ADR MCP implementation is production-ready | Confirmed. PR #181 merged, 10 tools, full JSON-RPC, HMAC event dispatch |
| OFS Triage has a complete MCP server | Confirmed. 9 tools, 7 resources, async processing for submit_case |
| UDIP has a dynamic tool catalog from dbt | Confirmed. Tools auto-generate from manifest.json on each dbt run |
| UDIP Row-Level Security is a blocker for hub integration | Confirmed. Session context must carry the caller's region claim or queries return silently wrong data |
| Distributed audit trail is the right design | Confirmed. Each app keeps its own NARA 7-year audit. The hub adds cross-system correlation |
| ADR/Triage use MCP.Read/MCP.Write; UDIP uses Analytics.Read/Analytics.Write | Confirmed. Intentional, not an oversight |
| Sequenced rollout (ADR first, then Triage, then UDIP) | Confirmed. ADR is most mature; UDIP has the RLS blocker that needs resolution first |

### 3.2 What Is Missing

**The OGC Trial Tool is not mentioned at all.** It is a fourth application that needs litigation data from ARC's NVS endpoints, has MCP client code in its codebase, and needs production authentication before any integration work can start.

**The document never addresses how the hub gets data from ARC.** It describes hub-to-spoke connections but assumes ARC data just appears. ADR's ARCSyncImporter calls an endpoint that does not exist in the codebase we reviewed. UDIP reads directly from SQL Server. There is no plan for a proper ARC data path.

**PrEPA's Service Bus is an untapped resource.** The `db-change-topic` is a ready-made event stream for case lifecycle changes. The document does not mention it.

**No plan for SBI reference data synchronization.** ADR imports statutes as freeform text. OFS Triage accepts basis and issue codes as unvalidated strings. UDIP has basis codes in its charges table. Nobody is consuming the canonical SBI combination tree from ARC.

**ARC's authentication model is unaddressed.** The hub needs to call ARC, but the document only covers hub-to-spoke auth (Entra ID M2M). ARC uses its own OAuth2 token service with client credentials. Somebody has to bridge these.

### 3.3 Where It Conflicts with Reality

| What the Document Assumes | What ARC Actually Does | What This Means |
|---------------------------|----------------------|-----------------|
| Hub calls spoke apps for case data | ARC is the system of record, not the spokes. Hub needs an ARC data path | We need a new integration layer between ARC and the hub |
| ADR has a working ARC sync endpoint | The endpoint ADR calls (`/api/mediation/cases`) does not exist in the Gateway or PrEPA codebase | That endpoint must be built as part of the integration layer |
| OFS Triage just needs the hub to understand async processing | Triage has zero ARC integration. Charge metadata is entirely manual | If we want auto-population, the hub needs a charge-lookup tool that queries ARC |
| UDIP tools are analytics, not case management | UDIP's analytics.charges table IS case data, pulled from the legacy IMS SQL Server via direct database access | Eventually UDIP should consume from the API layer instead of hitting SQL Server directly |

---

## 4. REST API Layer Design

### 4.1 Architecture: Three Components, Two Directions

The integration architecture has three components:

1. **WAL/CDC Pipeline** — streams case data from PrEPA's PostgreSQL to UDIP in real-time via logical replication (Debezium → Event Hub → UDIP Data Middleware). This is the primary data path.
2. **ARC Integration API** — handles write-back (mediation outcomes, triage results → ARC) and targeted case pushes (mediation eligibility → ADR, charge metadata → Triage)
3. **IDR Reconciliation** — twice-weekly verification of UDIP analytics tables against the IDR nightly snapshot

Apps that need case data for analytics, dashboards, or cross-system queries hit UDIP, which is kept current by the CDC pipeline.

```
        WRITE-BACK PATH                    DATA FLOW (primary)
        (results → ARC)                    (ARC → UDIP)

  ADR ──closes case──►                     PrEPA PostgreSQL
  Triage ──classifies──► ARC Integration        |
                          API              WAL (logical replication)
                           |                    |
                           ▼               Debezium → Event Hub
                         PrEPA                  |
                       (system of          UDIP Data Middleware
                        record)            (YAML translation,
                                            PII redaction)
                                                |
                                           UDIP PostgreSQL
                                          (analytics, dbt, RLS)
                                                |
                                      ┌─────────┼─────────┐
                                      ▼         ▼         ▼
                                     ADR     Triage    OGC TT
                                  (analytics) (context) (litigation)

                                     MCP Hub queries UDIP
                                     for AI consumers

        IDR (SQL Server) ─── reconciliation (Tue + Fri) ──► UDIP Middleware
```

**UDIP is the central internal data repository.** It ingests case data from PrEPA in real-time via WAL/CDC (PostgreSQL logical replication → Debezium → Event Hub → Data Middleware). All data passes through the UDIP Data Middleware, which provides YAML-driven column translation, value mapping, PII redaction, and schema validation. The IDR (nightly SQL Server snapshot) serves as a twice-weekly reconciliation source. All analytics, cross-system queries, and AI-driven lookups go through UDIP's governed, RLS-enforced views.

**The ARC Integration API has two jobs:**
1. **Push case assignments** to downstream apps (e.g., new mediation case → ADR with charge number, mediator, party emails, creation date). Forward Service Bus event notifications through the MCP Hub.
2. **Accept write-backs** from ADR and Triage and translate them into PrEPA's internal API calls

**Targeted pushes vs. general queries:** When ARC assigns a mediation case, the integration API pushes that specific case to ADR (charge number, assigned mediator, party email addresses, case creation date). ADR does not need to query ARC for everything — it gets what it needs when it needs it. Same for Triage: charge metadata is looked up at upload time, not continuously queried.

### 4.2 Why Python, Not Java

All four downstream apps are Python (Flask). The team writing and maintaining this code works in Python. Adding another Java service to the stack means a different build system, dependency chain, and deployment pipeline for people who will not touch the Spring codebase.

FastAPI on Azure Container Apps is the recommendation. It provides automatic OpenAPI docs, request validation with Pydantic, native async support, and aligns with the MCP Hub deployment target.

The alternative -- adding endpoints directly to FEPA Gateway -- avoids a new service but couples the integration API to a codebase the downstream team does not own.

### 4.3 Endpoints

Organized by direction: targeted data out of ARC, data flowing back into ARC, and reference data. UDIP feed endpoints are no longer needed here — UDIP gets its data via the WAL/CDC pipeline (see Section 4.7).

#### Service Bus Event Forwarding

The ARC Integration API subscribes to PrEPA's Azure Service Bus (`db-change-topic` and `document-activity-topic`) for event notification routing. When a case changes in PrEPA, the integration API transforms the Service Bus message into the MCP Hub's standardized event format, signs it with HMAC-SHA256, and POSTs it to the hub's `/api/v1/events` endpoint. The hub then routes the notification to interested spokes (e.g., ADR receives case status change notifications). This is for inter-app event routing, not for UDIP data ingestion.

#### Case Pushes (targeted data out of ARC to specific apps)

```
GET  /arc/v1/mediation/eligible-cases
     Returns cases eligible for mediation, with the payload ADR's
     ARCSyncImporter expects: charge_number, mediator_email, mediator_name,
     office_id, office_name, statutes, party emails, creation date.
     ADR polls this every 15 minutes. A few seconds of delay is fine.

GET  /arc/v1/mediation/cases/{charge_number}
     Single case detail for when ADR needs to look up a specific case.

GET  /arc/v1/charges/{charge_number}/metadata
     Charge metadata for OFS Triage auto-population at upload time.
     Returns: charge_number, respondent_name, basis_codes[], issue_codes[],
     statute_codes[], office_code, filing_date, status.

GET  /arc/v1/charges/batch
     Up to 100 charge numbers at once for Triage batch uploads.
```

These are the only read endpoints that apps call directly. Everything else
goes through UDIP.

#### Mediation Write-Back (ADR → ARC)

```
GET  /arc/v1/mediation/eligible-cases
     Returns cases that are formalized, less than 9 months old, not in enforcement,
     and have an assigned ADR staff member. This is the endpoint that ADR's
     ARCSyncImporter has been trying to call.

GET  /arc/v1/mediation/cases/{charge_number}
     Case detail with mediation-specific fields: eligibility date, staff assignment
     date, mediator name, participant list, statutes.

POST /arc/v1/mediation/cases/{charge_number}/status
     Updates mediation status back in PrEPA. Maps to case-status-update
     and mediation/response endpoints.
     Body: { status, charging_party_reply, respondent_reply,
             respondent_declined_reason, enforcement_reason,
             reason_not_eligible_adr, mediation_credit_staff_id }
     Maps to: PrEPA PUT /v1/cases/{caseId}/mediation (MediationVO)

PUT  /arc/v1/mediation/cases/{charge_number}/staff
     Assign or update mediation staff.
     Body: [{ staff_id, is_adr: true, assignment_reason }]
     Maps to: PrEPA POST /v1/cases/{caseId}/mediation-assignment

POST /arc/v1/mediation/cases/{charge_number}/schedule
     Record mediation session dates (scheduled and held).
     Body: { mediation_type, scheduled_time, held_time, interpreter_needed }
     Maps to: PrEPA PUT /v1/cases/{caseId}/mediation (mediationScheduleVO field)

POST /arc/v1/mediation/cases/{charge_number}/close
     Close a case through mediation with full outcome data.
     Body: {
       closure_reason,        -- e.g., "ADR_SETTLEMENT", "ADR_IMPASSE", "WITHDRAWAL"
       closure_date,
       is_adr_resolution,     -- true for mediation outcomes
       beneficiaries: [{
         type,                 -- "CHARGING_PARTY", "CLASS_MEMBER"
         persons_benefitted,
         benefits: [{
           type,               -- monetary or non-monetary code
           dollar_amount,      -- for monetary benefits (settlement amount)
           training_types,     -- for non-monetary (e.g., training ordered)
           compliance_outcome,
           compliance_date
         }]
       }]
     }
     Maps to: PrEPA PUT /v1/cases/{caseId}/charge/close/no-review (ClosureVO)
              + POST /v1/cases/{caseId}/allegations/benefits (BenefitGroupVO)
     This is the primary mediation close path. The "close/no-review" endpoint
     exists specifically for ADR/FEPA cases that bypass the review workflow.

POST /arc/v1/mediation/cases/{charge_number}/documents
     Upload a document to the case (e.g., signed settlement agreement).
     Multipart: file + { document_type, file_name }
     Maps to: PrEPA POST /v1/documents (multipart, ImsDocumentRequest)

POST /arc/v1/mediation/cases/{charge_number}/events
     Log action dates and milestones back to ARC's event log.
     Body: [{ event_code, event_date, comments, attributes: [{name, value}] }]
     Maps to: PrEPA POST /v1/cases/{caseId}/events (List<EventVO>)
     Use this for: mediation started date, mediation session held date,
     agreement signed date, settlement finalized date, etc.

POST /arc/v1/mediation/cases/{charge_number}/signed-agreements
     Trigger generation of signed Agreement to Mediate and Confidentiality
     Agreement documents in ARC.
     Body: { person_type, sequence_id }
     Maps to: PrEPA POST /v1/cases/{caseId}/mediation/signed/agreements
```

#### Triage Write-Back (OFS Triage → ARC)

```
POST /arc/v1/charges/{charge_number}/classification
     Write triage classification results back to ARC's event log.
     Body: { rank, merit_score, summary, classified_date }
     Maps to: PrEPA POST /v1/cases/{caseId}/events (EventVO with
              triage-specific event code and attributes)
     This gives investigators visibility into triage results without
     logging into the Triage app.

POST /arc/v1/charges/{charge_number}/events
     Log triage actions (correction, re-classification) as case events.
     Body: [{ event_code, event_date, comments, attributes }]
     Maps to: PrEPA POST /v1/cases/{caseId}/events
```

#### Reference Data (consumed by UDIP feed and available to all apps)

```
GET  /arc/v1/reference/sbi-combinations   (cached 24h, rarely changes)
GET  /arc/v1/reference/offices             (cached 24h)
GET  /arc/v1/reference/document-types      (cached 24h)
GET  /arc/v1/reference/statuses            (cached 24h)
```

#### Litigation (for OGC Trial Tool — targeted lookup, not general query)

```
GET  /arc/v1/litigation/cases/{charge_number}
     Court records, hearing dates, assigned attorneys. Routes through the
     Gateway's NVS and Search WS endpoints. Called when an attorney needs
     case background for trial prep, not for bulk ingestion.

GET  /arc/v1/litigation/search
     Search by court, case name, date range. Same targeted-use pattern.
```

Note: litigation data also flows into UDIP through the feed endpoints for
analytics purposes. The direct lookup is for OGC attorneys who need real-time
case detail during active trial preparation.

### 4.4 Authentication

The integration API bridges two auth worlds:

**Inbound:** Entra ID M2M bearer tokens. App roles `ARC.Read` and `ARC.Write`. The hub's managed identity gets both roles. Individual apps can be granted access directly if needed.

**Outbound:** OAuth2 service credentials stored in Key Vault. The integration API acquires ARC tokens using the existing client_id/secret pattern (`/oauth/token` endpoint), caches them, and refreshes before expiry. No changes to ARC's auth system required.

**UDIP RLS note:** When the MCP hub routes AI consumer queries to UDIP, it needs to preserve the original caller's regional identity. This is handled via OAuth 2.0 On-Behalf-Of (OBO) flow at the hub level, not at the ARC Integration API level. The ARC Integration API feeds UDIP's data pipeline using a service account with full access — RLS is enforced at query time when end users or AI consumers access the data through UDIP's own endpoints.

### 4.5 Normalized Data Model

The integration API translates PrEPA's internal entities into a clean external format:

```json
{
  "charge_number": "370-2026-00123",
  "fepa_charge_number": "NYSDHR-2026-456",
  "status": "FORMALIZED",
  "status_description": "Formally Charged",
  "office_code": "37A",
  "office_name": "New York District Office",
  "filing_date": "2026-01-15",
  "formalization_date": "2026-02-01",
  "is_fepa": false,
  "charging_party": {
    "first_name": "Jane",
    "last_name": "Smith",
    "email": "jane.smith@example.com"
  },
  "respondent": {
    "name": "Acme Corporation",
    "employee_count": 500
  },
  "statutes": ["Title VII"],
  "basis_codes": ["Race", "Color"],
  "issue_codes": ["Discharge", "Harassment"],
  "assigned_investigator": "John Doe",
  "assigned_mediator": "Sarah Johnson",
  "last_modified": "2026-03-15T14:30:00Z"
}
```

### 4.6 Caching and Event-Driven Invalidation

| Data | Cache TTL | How It Gets Invalidated |
|------|-----------|------------------------|
| Reference data (SBI, offices, statuses) | 24 hours | Scheduled refresh or manual purge |
| Case list queries | 5 minutes | Service Bus `db-change-topic` event for affected case |
| Individual case detail | 2 minutes | Service Bus event |
| Mediation eligible cases | 5 minutes | Matches ARCSyncImporter's 15-minute polling cycle |
| Document metadata | 10 minutes | Service Bus `document-activity-topic` event |

The integration API subscribes to PrEPA's existing Azure Service Bus topics (`db-change-topic` and `document-activity-topic`). When a case changes in PrEPA, the subscription fires, the cache entry is invalidated, and the event is forwarded to the MCP Hub's `/api/v1/events` endpoint with an HMAC signature for inter-app notification routing.

Note: Service Bus events are used here for cache invalidation and inter-app notifications. UDIP's primary data feed is the WAL/CDC pipeline (see Section 4.7), not the Service Bus.

### 4.7 WAL/CDC Data Pipeline

The primary path for getting case data from ARC into UDIP is PostgreSQL logical replication via WAL (Write-Ahead Log):

```
PrEPA PostgreSQL (9.x)
    │
    ├── WAL (already written for crash recovery)
    │     │
    │     └── Logical replication slot: udip_cdc (read-only)
    │           │
    │           └── Debezium PostgreSQL connector
    │                 │
    │                 └── Azure Event Hub (Kafka protocol)
    │                       │
    │                       └── UDIP Data Middleware
    │                             ├── Event Hub consumer driver (new)
    │                             ├── prepa_*.yaml mappings (new)
    │                             ├── Value maps (FK integers → names)
    │                             ├── PII redaction (existing)
    │                             ├── Computed columns (existing)
    │                             │
    │                             └── UDIP PostgreSQL analytics tables
    │                                   └── dbt → AI schema → embeddings
```

**Why WAL/CDC over REST API or Service Bus:**
- **Captures everything.** PrEPA has 16+ scheduled batch jobs (notice generation, closure emails, FEPA sync, systemic case matching) that write directly to PostgreSQL. Service Bus only captures what `PrepaEventProducer` publishes on transaction commit. WAL captures all row-level changes.
- **Zero write-path impact.** The logical replication slot reads from WAL that PostgreSQL already writes for crash recovery. No additional I/O on the write path.
- **Sub-second latency.** Changes are available in the replication stream as soon as they are committed.

**What we need from the ARC team:**
- One logical replication slot (`SELECT pg_create_logical_replication_slot('udip_cdc', 'pgoutput')`)
- A publication for all tables (`CREATE PUBLICATION udip_publication FOR ALL TABLES`). This streams every table in PrEPA — charges, allegations, staff, reference tables, mediation, closures, events. New tables auto-appear in the stream. Raw data lands in UDIP's `replica` schema; the middleware translates it into clean, AI-ready datasets in the `analytics` schema.
- `max_slot_wal_keep_size` configured to prevent disk exhaustion if the consumer falls behind

**Fallback if ARC will not grant WAL access:**
- Primary: Service Bus subscription on `db-change-topic` (application-level events, near-real-time for app-published changes)
- Supplemental: REST API feed endpoints from the ARC Integration API (watermark-based polling for bulk data the Service Bus doesn't cover)
- The middleware YAML configs work with either path — just a different source driver in the YAML

### 4.8 UDIP Data Middleware

The UDIP Data Middleware is the central translation layer between any data source and UDIP's analytics schema. It is already in production and handles all data flowing into UDIP.

**Components:**
- **YAML mapping configs** (`source_mappings/*.yaml`) — declarative column mappings from source to target, with transform specifications
- **MappingConfig / RowTransformer** (`mapping_engine.py`) — loads YAML, applies transforms per row
- **MappingValidator** (`mapping_validator.py`) — validates all mappings at startup, blocks sync on failure
- **SyncEngine** (`sync_engine.py`) — orchestrates incremental sync with watermarks, batch upserts, post-sync tasks (dbt, embeddings)

**Supported transforms:** value_map (inline dict), value_map_file (CSV lookup), parse_date, computed (DATEDIFF, NULL coalescing), redact_pii (SSN/email/phone regex), uppercase, lowercase, titlecase, trim, default

**PII governance:** Tier 1 (public), Tier 2 (internal, PII redacted), Tier 3 (restricted, raw PII). MappingValidator enforces tier consistency.

**Current source drivers:** pyodbc (SQL Server / IDR), psycopg2 (PostgreSQL / Angular app)

**New driver needed:** Azure Event Hub consumer (Kafka protocol) for WAL/CDC events. Consumes Debezium JSON envelopes (before/after row images), yields rows as dicts matching SQL cursor format. Tracks consumer group offsets — only commits after successful upsert.

**New YAML mapping configs needed:** PrEPA's PostgreSQL schema uses normalized FK integers (`shared_basis_id = 1`) where the IDR uses denormalized inline codes (`BAS_CD = 'R'`). New prepa_*.yaml files map FK integers through value_map transforms to human-readable names. Existing IDR mappings (`sqlserver_charges.yaml`, `sqlserver_adr.yaml`) remain for reconciliation.

### 4.9 IDR Reconciliation Strategy

The IDR (Integrated Data Repository) is a nightly SQL Server snapshot of ARC data. It is currently UDIP's primary data source. Under the new architecture, it transitions to a twice-weekly reconciliation source:

| Phase | IDR Role | Frequency |
|-------|----------|-----------|
| Current | Primary data source for UDIP | Nightly |
| After WAL/CDC is live | Reconciliation + backfill | Twice weekly (Tue + Fri, 03:00 UTC) |
| After 3 months of clean reconciliation | Spot-check only | Weekly or monthly |
| Eventually | Disaster recovery / decommission | On-demand |

**Reconciliation engine (`reconciliation.py`):**
1. Count rows in IDR where modified > last_reconciliation_timestamp
2. Count matching rows in analytics tables
3. Compare SHA-256 checksums on a sample (1000 random rows by primary key)
4. If discrepancy found, identify specific missing charge_ids
5. Auto-backfill missing records using existing `sqlserver_*.yaml` mappings
6. Alert if discrepancy > 0.1% of total rows

**Reconciliation log:** New `middleware.reconciliation_log` table tracks every run with row counts, mismatches, backfill counts, and discrepancy percentages.

The existing YAML mappings (`sqlserver_charges.yaml`, `sqlserver_adr.yaml`) stay alive for reconciliation and backfill. They become the safety net while the CDC pipeline proves itself.

---

## 5. MCP Server Architecture

### 5.1 How the Hub Works

The MCP Hub is a Container App that does five things:
1. Registers spokes and discovers their tool catalogs
2. Routes tool invocations to the right spoke
3. Manages Entra ID M2M tokens for spoke authentication
4. Provides a single MCP endpoint for all consumers
5. Logs every operation to its own NARA 7-year audit store

```
                        MCP Hub
                   (Container App)
                         |
        +--------+-------+-------+--------+
        |        |       |       |        |
      ADR    Triage    UDIP    OGC TT    ARC
    10 tools  9 tools  3+N    3 tools   Integration
                       tools             (write-back
                        |                 + targeted
                   PRIMARY QUERY          lookups)
                   TARGET for AI
                   consumers
```

UDIP is the primary query target for AI consumers. When someone asks "what are the settlement rates by region," that goes to UDIP, which has the data locally (kept current via WAL/CDC) in governed, RLS-enforced views. The ARC Integration API is not a query layer — it handles write-backs and targeted case pushes. UDIP's data currency comes from the WAL/CDC pipeline independently of the hub.

Each spoke registers at startup with its URL, capability categories, auth requirements, and protocol version. The hub refreshes tool catalogs every 5 minutes.

### 5.2 ARC Integration API as a Spoke

The ARC Integration API registers as a spoke, but its role is different from the other spokes. It provides **write-back tools** (ADR and Triage pushing results to ARC) and a small number of **targeted read tools** (case pushes that need real-time data from ARC, not the UDIP data store).

**Targeted read tools (for real-time lookups that cannot wait for UDIP sync):**

| Tool | Category | What It Does |
|------|----------|-------------|
| `arc_get_mediation_eligible` | case_management | Cases eligible for mediation — ADR's sync uses this |
| `arc_get_charge_metadata` | case_management | Charge metadata at Triage upload time |
| `arc_get_case_documents` | document_storage | Document metadata list (documents live in ECM, not UDIP) |
**Write-back tools (for pushing results back to ARC):**

| Tool | Category | What It Does |
|------|----------|-------------|
| `arc_update_mediation_status` | case_management | Update mediation status, party replies, eligibility |
| `arc_assign_mediation_staff` | case_management | Assign or update mediation staff on a case |
| `arc_close_mediation_case` | case_management | Close case with outcome, benefits, settlement amounts |
| `arc_upload_case_document` | document_storage | Upload document (e.g., signed settlement agreement) |
| `arc_log_case_events` | case_management | Log action dates, milestones to ARC event log |
| `arc_generate_signed_agreements` | document_storage | Trigger signed agreement document generation |
| `arc_post_triage_classification` | case_management | Write triage rank/score/summary to ARC event log |
| `arc_log_triage_events` | case_management | Log triage corrections and re-classifications |

**Not exposed as MCP tools (these are infrastructure, not user-facing):**

Note: UDIP's data feed comes from the WAL/CDC pipeline (Section 4.7), not from the ARC Integration API. The ARC Integration API's role in the hub is write-back + targeted reads. Reference data endpoints are consumed by apps directly, not through the hub.

### 5.3 Tool Counts at Full Connection

| Spoke | Read | Write | Dynamic | Total |
|-------|------|-------|---------|-------|
| ADR | 4 | 6 | 0 | 10 |
| OFS Triage | 5 | 3 | 0 | 8 |
| UDIP | 3 | 0 | N (dbt models) | 3+N |
| ARC Integration | 3 | 8 | 0 | 11 |
| OGC Trial Tool | 2 | 1 | 0 | 3 |
| **Total** | **17** | **18** | **N** | **35+N** |

Note: the ARC Integration API's read tool count dropped from 10 to 3 because most case query functionality is served by UDIP, not by live ARC lookups. The remaining 3 reads are targeted real-time lookups (mediation eligibility, charge metadata at upload, document metadata from ECM).

### 5.4 Keeping Tool Context Manageable

An AI request should not see all 35+ tools at once. The hub filters by capability category based on the request context:

| Request Type | What Gets Included | Typical Tool Count |
|-------------|-------------------|-------------------|
| Case analytics | UDIP analytics + reporting tools | ~6+N |
| Narrative search | UDIP narrative_search | ~2 |
| Mediation management | ADR case_management + ARC write-back | ~13 |
| Litigation prep | litigation + case_management | ~5 |
| Cross-system analysis | All categories, capped at 15 | ~15 |

### 5.5 Event Flow

```
Event notifications (inter-app routing):
PrEPA --Service Bus--> ARC Integration API --HTTPS/HMAC--> MCP Hub
                                                              |
                                  +--------+--------+---------+
                                  |        |        |         |
                                ADR    Triage              OGC TT
                            (subscribed)

UDIP data feed (separate path, not through hub):
PrEPA --WAL/CDC--> Debezium --> Event Hub --> UDIP Data Middleware --> UDIP PostgreSQL
```

ADR also pushes events (case.created, case.closed, case.reassigned) to the hub, which can forward them to other interested spokes. UDIP does not subscribe to hub events — it gets its data via the WAL/CDC pipeline independently.

### 5.6 Audit Standardization

Every system needs these fields in its audit records for cross-system correlation:

| Field | Format | Who Generates It |
|-------|--------|-----------------|
| `request_id` | UUIDv4 | Hub generates; spokes echo it back |
| `caller_oid` | SHA-256 of user OID + salt | Each system hashes independently |
| `tool_name` | string | The tool being invoked |
| `spoke_system` | string | Which spoke handled the request |
| `response_hash` | SHA-256 minimum, HMAC-SHA256 preferred | Each system computes |
| `retention_tag` | `FOIA_7_YEAR` | Standardized across all systems |
| `timestamp` | ISO 8601 UTC | Recorded independently at each system |

Current state:

| System | Has request_id? | Has caller hash? | Retention tag | Work needed |
|--------|-----------------|-------------------|---------------|-------------|
| Hub | Yes (generates) | Yes (from token) | FOIA_7_YEAR | None (new) |
| ADR | CorrelationID (close enough) | UserIDHash (SHA-256) | FOIA_7_YEAR | Map CorrelationID to request_id |
| Triage | No | No | NARA_7_YEAR | Add request_id, add caller hash, align tag |
| UDIP | No | client_id hashed | Not aligned | Add request_id, align tag |
| OGC Trial Tool | No | Raw email (not hashed) | NARA_7_YEAR | Add request_id, hash the email, align tag |

---

## 6. Implementation Roadmap

### Phase 1: ARC Integration API + WAL/CDC Pipeline + UDIP Middleware Updates (Weeks 1-6)

Build the integration API (write-back + targeted reads), establish the WAL/CDC pipeline, update UDIP's middleware, and build the IDR reconciliation engine. These are the foundation — everything else depends on UDIP having current data and the write-back path being operational.

| Week | What Gets Done |
|------|---------------|
| 1 | ARC Integration API: project scaffolding (FastAPI), Entra ID app registration, Key Vault integration, ARC OAuth2 client. Deploy to Container Apps in dev. Engage ARC DBA for logical replication slot. |
| 2 | WAL/CDC: Debezium connector on PrEPA PostgreSQL (dev), Event Hub namespace provisioning, middleware Event Hub consumer driver, new prepa_*.yaml YAML mapping configs for PrEPA's normalized schema. Service Bus subscription for event notification routing. |
| 3 | ARC Integration API: Mediation case push endpoint (`/arc/v1/mediation/eligible-cases`). Charge metadata endpoint for Triage. Reference data endpoints. |
| 4 | ARC Integration API: Write-back endpoints (mediation status, close, document upload, event logging). Integration tests against PrEPA dev. IDR reconciliation engine built (reconciliation.py, reconciliation configs). |
| 5 | Parallel run: UDIP ingesting from both IDR (existing sqlserver_*.yaml) and WAL/CDC pipeline (new prepa_*.yaml). Compare data parity. Run reconciliation engine against both sources. |
| 6 | UDIP cut over to WAL/CDC as primary data source. IDR shifts to reconciliation-only (twice weekly, Tue + Fri). Validate sub-second CDC latency. |

### Phase 2: MCP Hub Infrastructure (Weeks 4-7, overlapping Phase 1)

Hub deployed with spoke registration, tool routing, event ingestion, and audit logging.

| Week | What Gets Done |
|------|---------------|
| 4-5 | Hub Container App deployed. Health check, Entra ID auth, spoke registration API, VNet peering |
| 6 | Tool registry with 5-minute reconciliation. ARC Integration API registered as first spoke (write-back tools + targeted reads). Test tool invocation end-to-end |
| 7 | Event ingestion endpoint with HMAC validation. Hub audit logger. Acceptance tests |

### Phase 3: UDIP as Primary Query Spoke + OBO (Weeks 6-8)

Connect UDIP to the hub as the primary query target for AI consumers.

| Week | What Gets Done |
|------|---------------|
| 6-7 | OBO flow implementation so hub preserves caller region claims. UDIP team signs off on approach. Entra ID OBO configuration |
| 7-8 | UDIP registered as spoke. Analytics tools verified with correct regional scoping. Dynamic tool catalog reconciliation tested. Verify: AI query for settlement rates returns regionally scoped data, not empty |

### Phase 4: ADR Connection + Write-Back (Weeks 7-9)

Connect ADR with all 10 tools, event round-tripping, and mediation write-back to ARC.

| Week | What Gets Done |
|------|---------------|
| 7-8 | ADR registered as spoke. MCP.Read granted. All 10 tools callable from hub. HMAC events validated. ADR's ARCSyncImporter pointed at new mediation eligibility endpoint |
| 8-9 | Write-back tested end-to-end: ADR closes a mediation case → `arc_close_mediation_case` → PrEPA records closure with benefits → UDIP picks up the closure via feed → data visible in analytics. Document upload tested: signed agreement → ECM |

### Phase 5: OFS Triage Connection + Write-Back (Weeks 9-10)

Connect Triage with read tools, async pattern documented, and classification write-back.

| Week | What Gets Done |
|------|---------------|
| 9 | Registered as spoke. Read tools return live data. Charge metadata auto-population from `arc_get_charge_metadata` at upload time |
| 10 | Write-back tested: Triage classifies charge → `arc_post_triage_classification` → result appears in ARC event log. Async submit_case pattern documented |

### Phase 6: OGC Trial Tool Integration (Weeks 10-12)

Connect Trial Tool with production auth and litigation data.

| Week | What Gets Done |
|------|---------------|
| 10 | Replace demo auth with Entra ID Government. Stand up MCP server endpoint |
| 11 | Register as spoke. Litigation case lookups working through ARC Integration API |
| 12 | Trial Tool MCP tools callable end-to-end |

### Phase 7: Cross-Spoke Verification (Week 13)

Test multi-spoke AI sessions. These queries should route primarily through UDIP (which has the data), with write-backs going through ARC Integration API:
- "What are the triage outcomes for cases that became mediation sessions this quarter?" → UDIP (has both triage results and ADR outcomes ingested from ARC feed)
- "Show me settlement rates by region for Q1 FY2026" → UDIP `query_fct_adr_sessions` with OBO regional scoping
- "Close mediation case 370-2026-00123 as a successful settlement with $50k" → ARC Integration API `arc_close_mediation_case` → PrEPA → WAL/CDC → UDIP (data refreshes within seconds)
- "Prepare a litigation summary for charge 370-2026-00123" → UDIP for case history + ARC Integration API for real-time litigation detail from NVS

---

## Appendix A: Open Decisions

| Decision | Options | Recommendation | Owner | Deadline |
|----------|---------|----------------|-------|----------|
| ARC WAL/CDC access | Logical replication slot on PrEPA PostgreSQL (recommended) vs. Service Bus + REST API fallback | Grant read-only logical replication slot — zero write-path impact | ARC DBA team + Architecture team | Before Phase 1 |
| UDIP RLS token delegation | Explicit region param, OBO flow, or hub-managed region table | OBO flow | Hub + UDIP team | Before Phase 5 |
| Triage async polling | Document in tool description, or build hub-level polling wrapper | Document it; keep it simple | Hub + Triage team | Before Phase 4 |
| Integration API tech stack | Python/FastAPI or add to FEPA Gateway (Java). Scope: write-back + targeted reads only (no UDIP feed) | Python/FastAPI | Architecture team | Before Phase 1 |
| ARC event format through hub | Forward Service Bus events as-is, or transform to MCP event schema (for inter-app notifications) | Transform to MCP schema | Hub team | Phase 2 |
| OGC Trial Tool MCP tool set | Which AI analysis tools to expose externally | Trial team proposes | OGC team | Before Phase 6 |

## Appendix B: Security Checklist

- [ ] ARC Integration API: Entra ID app registration with ARC.Read/ARC.Write roles
- [ ] ARC Integration API: Service credentials in Key Vault, not in code
- [ ] ARC Integration API: HTTPS only, TLS 1.2 minimum
- [ ] ARC Integration API: SSRF prevention on outbound calls
- [ ] ARC Integration API: Charge number input validation (`^[A-Z0-9\-]{3,25}$`)
- [ ] ARC Integration API: Per-client rate limiting
- [ ] ARC Integration API: Hash user identifiers before logging
- [ ] Hub: Managed Identity with app roles on all spoke registrations
- [ ] Hub: HMAC webhook secret per spoke, stored in Key Vault
- [ ] Hub: OBO configuration for UDIP token delegation
- [ ] OGC Trial Tool: Replace demo auth with Entra ID Government before any integration
- [ ] All systems: Retention tags standardized to FOIA_7_YEAR
- [ ] All systems: request_id correlation in audit records

## Appendix C: ARC Endpoint Mapping

How the integration API endpoints map to ARC internals:

| Integration API | Routes Through | Underlying Endpoint |
|----------------|---------------|---------------------|
| `GET /arc/v1/cases` | PrEPA | Multiple `/v1/cases/*` queries combined |
| `GET /arc/v1/cases/{cn}` | FEPA Gateway -> PrEPA | `/fepagateway/v1/cases/{cn}` -> `/v1/cases/{id}` |
| `GET /arc/v1/cases/{cn}/allegations` | PrEPA | `/v1/cases/{id}/allegations` |
| `GET /arc/v1/cases/{cn}/staff` | PrEPA | `/v1/cases/{id}/staff-assignment` |
| `GET /arc/v1/cases/{cn}/events` | PrEPA | `/v1/cases/{id}/events` |
| `GET /arc/v1/cases/{cn}/documents` | FEPA Gateway -> ECM | `/fepagateway/v1/documents/{cn}` |
| `GET /arc/v1/mediation/eligible-cases` | PrEPA | Filtered query: status + date + ADR staff |
| `POST /arc/v1/mediation/cases/{cn}/status` | PrEPA | `PUT /v1/cases/{id}/mediation` (MediationVO) |
| `PUT /arc/v1/mediation/cases/{cn}/staff` | PrEPA | `POST /v1/cases/{id}/mediation-assignment` |
| `POST /arc/v1/mediation/cases/{cn}/close` | PrEPA | `PUT /v1/cases/{id}/charge/close/no-review` + `POST /v1/cases/{id}/allegations/benefits` |
| `POST /arc/v1/mediation/cases/{cn}/documents` | PrEPA -> ECM | `POST /v1/documents` (multipart) |
| `POST /arc/v1/mediation/cases/{cn}/events` | PrEPA | `POST /v1/cases/{id}/events` |
| `POST /arc/v1/mediation/cases/{cn}/signed-agreements` | PrEPA | `POST /v1/cases/{id}/mediation/signed/agreements` |
| `GET /arc/v1/charges/{cn}/metadata` | PrEPA | `/v1/cases/{id}` + `/allegations` flattened |
| `POST /arc/v1/charges/{cn}/classification` | PrEPA | `POST /v1/cases/{id}/events` (triage event code) |
| `POST /arc/v1/charges/{cn}/events` | PrEPA | `POST /v1/cases/{id}/events` |
| `GET /arc/v1/litigation/cases/{cn}` | FEPA Gateway -> Search WS | NVS + `/searchws/litigation/v1/*` |
| `GET /arc/v1/reference/sbi-combinations` | FEPA Gateway | `/fepagateway/v1/sbi-combo` |
| `GET /arc/v1/reference/offices` | PrEPA | `/v1/offices` |
| ~~`GET /arc/v1/feed/*`~~ | ~~PrEPA~~ | ~~Deprecated: replaced by WAL/CDC pipeline (Section 4.7)~~ |
| ~~`GET /arc/v1/analytics/charges`~~ | ~~PrEPA~~ | ~~Deprecated: replaced by WAL/CDC pipeline~~ |
