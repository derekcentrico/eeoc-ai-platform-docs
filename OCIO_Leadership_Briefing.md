# ARC Integration & MCP Hub: Briefing for OCIO Leadership

**From:** Derek
**Date:** 2026-03-30
**Read time:** ~15 minutes
**Action requested:** Review and alignment on path forward

---

## The Short Version

We reviewed all six codebases involved in the ARC-to-application integration effort: the two ARC backbone services (FEPA Gateway and PrEPA), and the four downstream applications (ADR Mediation, OFS Triage, UDIP Analytics, and OGC Trial Tool). We also reviewed the existing MCP Hub integration planning document.

The core finding: **ARC was never built to serve these downstream applications.** Both ARC services were designed for the IMS Angular frontend and FEPA partner agencies. The four apps have each independently worked around this -- one polls an endpoint that does not exist, one bypasses the API entirely and reads from SQL Server, and two have no ARC integration at all.

The MCP Hub integration plan is solid on the spoke side (the three apps it covers are well-built and ready to connect), but it has a blind spot: it never addresses how the hub actually gets case data from ARC.

We are proposing a clean path forward that fills this gap without disrupting any existing systems.

---

## The Full Picture at a Glance

This diagram shows every data flow in the proposed architecture -- what feeds UDIP, what writes back to ARC, and where each app fits.

```mermaid
flowchart TB
    subgraph ARC["ARC Backbone (no changes)"]
        PrEPA["PrEPA Web Service<br/>System of Record<br/>200+ endpoints, PostgreSQL"]
        Gateway["FEPA Gateway<br/>API Gateway<br/>76+ endpoints"]
        SB["Azure Service Bus<br/>db-change-topic"]
        ECM["ECM<br/>Document Storage"]
        PrEPA --> SB
        PrEPA --> ECM
        Gateway --> PrEPA
    end

    subgraph CDC["WAL/CDC Pipeline (primary data path)"]
        WAL["PostgreSQL WAL<br/>Logical Replication"]
        Debezium["Debezium Connector"]
        EH["Azure Event Hub<br/>(Kafka protocol)"]
        WAL --> Debezium --> EH
    end

    subgraph Integration["ARC Integration API"]
        Push["Case Push Endpoints<br/>/arc/v1/mediation/*<br/>/arc/v1/charges/*"]
        WriteBack["Write-Back Endpoints<br/>Closure, Documents,<br/>Events, Benefits"]
        MCP_Spoke["MCP Spoke<br/>POST /mcp"]
    end

    subgraph Central["UDIP — Central Data Store"]
        MW["Data Middleware<br/>YAML mappings, value translation,<br/>PII redaction, validation"]
        PG["PostgreSQL<br/>analytics schema<br/>RLS-enforced views"]
        dbt["dbt Semantic Layer<br/>Governed metrics"]
        Ingest["Ingest API<br/>POST /api/v1/mcp/ingest"]
        UMCP["MCP Server<br/>query_*, search_narratives,<br/>get_metrics"]
        MW --> PG --> dbt --> UMCP
        Ingest --> PG
    end

    IDR["IDR (SQL Server)<br/>Nightly ARC snapshot"]

    subgraph Apps["Downstream Applications"]
        ADR["ADR Mediation<br/>10 MCP tools<br/>Flask + Azure Table"]
        Triage["OFS Triage<br/>9 MCP tools<br/>Flask + Azure Table"]
        OGC["OGC Trial Tool<br/>3 MCP tools (planned)<br/>Flask + Ollama"]
    end

    Hub["MCP Hub<br/>Tool routing, auth,<br/>audit, events"]

    %% WAL/CDC primary data path
    PrEPA -.->|"WAL stream"| WAL
    EH -->|"CDC events<br/>(real-time)"| MW
    IDR -.->|"reconciliation<br/>(Tue + Fri)"| MW

    %% Service Bus for event notifications
    SB -->|"event notifications"| Integration

    %% Integration API to Apps (case pushes)
    Push -->|"eligible cases"| ADR
    Push -->|"charge metadata"| Triage

    %% Apps write back through Integration API
    ADR -->|"closure, settlement,<br/>signed docs, dates"| WriteBack
    Triage -->|"classification,<br/>corrections"| WriteBack
    WriteBack -->|"translated to<br/>PrEPA endpoints"| PrEPA

    %% Apps push analytics directly to UDIP
    ADR -->|"daily metrics,<br/>reliance, drift"| Ingest
    Triage -->|"daily metrics,<br/>corrections, reliance"| Ingest

    %% Hub routes queries to UDIP
    Hub <-->|"AI queries<br/>(primary path)"| UMCP
    Hub <-->|"write-back<br/>tools"| MCP_Spoke
    Hub <--> ADR
    Hub <--> Triage
    Hub <--> OGC

    %% OGC queries
    OGC -->|"litigation<br/>lookup"| Push
    OGC -->|"case context"| UMCP

    style Central fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style CDC fill:#e8eaf6,stroke:#283593,stroke-width:2px
    style Integration fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style ARC fill:#fce4ec,stroke:#c62828,stroke-width:1px
```

---

## How Data Flows in Each Direction

Three distinct flows make up the full integration. Each one serves a different purpose.

```mermaid
flowchart LR
    subgraph FlowA["Flow 1: ARC → UDIP (real-time via WAL/CDC)"]
        direction LR
        A1["PrEPA case change"] --> A2["PostgreSQL WAL"] --> A3["Debezium →<br/>Event Hub"] --> A4["UDIP Data<br/>Middleware"] --> A5["UDIP PostgreSQL"]
        A6["IDR snapshot"] -.->|"reconciliation<br/>Tue + Fri"| A4
    end

    subgraph FlowB["Flow 2: Apps → ARC (write back results)"]
        direction LR
        B1["ADR closes<br/>mediation"] --> B2["ARC Integration<br/>API write-back"] --> B3["PrEPA records<br/>closure + benefits"]
        B4["Triage classifies<br/>charge"] --> B2
    end

    subgraph FlowC["Flow 3: Apps → UDIP (push analytics)"]
        direction LR
        C1["ADR daily metrics,<br/>reliance, drift"] --> C2["UDIP Ingest API"]
        C3["Triage daily metrics,<br/>corrections, reliance"] --> C2
        C2 --> C4["UDIP PostgreSQL<br/>(complete picture)"]
    end

    style FlowA fill:#e3f2fd,stroke:#1565c0
    style FlowB fill:#fff3e0,stroke:#e65100
    style FlowC fill:#e8f5e9,stroke:#2e7d32
```

---

## What a Mediation Case Lifecycle Looks Like End-to-End

This is the concrete example: a charge arrives in ARC, goes through mediation in ADR, and the results flow back.

```mermaid
sequenceDiagram
    participant ARC as ARC (PrEPA)
    participant CDC as WAL/CDC Pipeline
    participant IntAPI as ARC Integration API
    participant UDIP as UDIP (Central DB)
    participant ADR as ADR Mediation
    participant Hub as MCP Hub

    Note over ARC: Charge filed, mediator assigned
    ARC->>CDC: WAL: charge_inquiry + charge_assignment rows
    CDC->>UDIP: Debezium → Event Hub → Middleware<br/>(real-time, YAML-translated)
    IntAPI->>ADR: ARCSyncImporter: eligible case<br/>(charge #, mediator, party emails, dates)

    Note over ADR: Mediator accepts case, schedules session
    ADR->>IntAPI: POST /arc/v1/mediation/.../events<br/>(mediation_started, session_date)
    IntAPI->>ARC: POST /v1/cases/{id}/events

    Note over ADR: Mediation succeeds, agreement signed
    ADR->>IntAPI: POST /arc/v1/mediation/.../close<br/>(settlement: $50k, benefits, closure reason)
    IntAPI->>ARC: PUT /v1/cases/{id}/charge/close/no-review<br/>+ POST /v1/cases/{id}/allegations/benefits
    ADR->>IntAPI: POST /arc/v1/mediation/.../documents<br/>(signed settlement agreement PDF)
    IntAPI->>ARC: POST /v1/documents (multipart → ECM)

    Note over ARC: Case closed in system of record
    ARC->>CDC: WAL: closure + settlement rows
    CDC->>UDIP: Closure data arrives in UDIP<br/>within seconds via CDC pipeline

    Note over ADR: Daily analytics push
    ADR->>UDIP: POST /api/v1/mcp/ingest<br/>(daily metrics, reliance scores, drift)

    Note over Hub: AI consumer asks a question
    Hub->>UDIP: "Settlement rates by region this quarter?"
    UDIP->>Hub: RLS-scoped results from fct_adr_sessions
```

---

## What We Found

### ARC: Two Services, 276+ Endpoints, Zero Designed for Us

**FEPA Gateway** is a Java/Spring Boot API gateway sitting in front of PrEPA and five other backend services. It handles authentication (OAuth2, Login.gov), routes requests, and manages document operations through ECM. 76+ endpoints, all built for the IMS Angular app and FEPA state agency partners.

**PrEPA Web Service** is the system of record for discrimination charges. PostgreSQL database, 200+ REST endpoints, 16 scheduled background jobs, Azure Service Bus event publishing. It manages the full charge lifecycle from initial inquiry through closure, including mediation, enforcement, and litigation.

Neither service exposes an API for downstream application consumption. The closest thing is PrEPA's Service Bus event stream (`db-change-topic`), which publishes case change events -- but today, only the IMS ecosystem subscribes to it.

### The Four Applications: Varying Levels of Readiness

**ADR Mediation Platform** -- the most integration-ready. Full MCP server (10 tools, 5 resources), dual authentication (Entra ID + Login.gov), production-grade audit logging with NARA 7-year retention. It already has an ARC sync module that polls for mediation-eligible cases every 15 minutes, but the ARC endpoint it calls does not exist in the codebase we reviewed.

**OFS Triage** -- well-built MCP server (9 tools, 7 resources), strong security posture, but zero connection to ARC. Analysts manually type in charge numbers and metadata. The system classifies charges using local AI (GPT-4o) and has no way to auto-populate case data from ARC.

**UDIP Analytics** -- the agency's analytics platform replacing Tableau and Power BI. Full MCP server with dynamic tool generation from dbt models. It has a production Data Middleware layer with YAML-based column mapping, value translation (converting ARC's cryptic internal codes to human-readable labels), PII redaction, and schema validation. However, it currently gets its charge data from the IDR (a nightly SQL Server snapshot of ARC), bypassing the API layer entirely. It also has a row-level security model tied to the caller's regional identity, which creates a real technical constraint for hub integration (more on this below).

**OGC Trial Tool** -- earliest stage. Litigation support tool for trial attorneys, running local LLM inference (Ollama) for case analysis. No MCP server, no ARC integration, and still using demo session-based authentication instead of Entra ID.

### The MCP Hub Document: Right Direction, Incomplete Picture

The existing three-application integration document correctly identifies:
- How the three spoke apps should connect to the hub
- The UDIP row-level security problem (it is a legitimate blocker)
- The right audit architecture (distributed, with correlation IDs)
- The right rollout sequence (ADR first, Triage second, UDIP third)

But it misses:
- **OGC Trial Tool** is not mentioned. It is a fourth application that needs litigation data from ARC.
- **The ARC data path.** The document describes how the hub talks to spoke apps but never addresses how case data gets from ARC into the hub ecosystem. This is the most important missing piece.
- **PrEPA's Service Bus.** There is already an event stream publishing case lifecycle changes. We should be subscribing to it, not inventing a new polling mechanism.
- **ARC's authentication model.** The hub uses Entra ID for spoke communication, but ARC uses its own OAuth2 token service. These need to be bridged.
- **UDIP as central data store.** The document treats each app as an island with its own data. The architecture should center on UDIP as the shared analytical backbone that every app feeds and every app can query.
- **Write-back to ARC.** The document is read-only. ADR and Triage both need to push results (mediation outcomes, classification results, documents) back into ARC's system of record.

---

## The Proposal

### UDIP Becomes the Central Data Store

This is the most important architectural decision. Instead of every app maintaining its own copy of case data and querying ARC independently, UDIP ingests everything from ARC and serves as the single governed data layer for the entire ecosystem.

UDIP already has the foundation: PostgreSQL with row-level security, a dbt semantic layer for governed metrics, an ingest API, and a production Data Middleware with YAML-driven column translation, value mapping, PII redaction, and schema validation. What it needs is a real-time feed from ARC via WAL/CDC (replacing the IDR nightly batch), new tables for ADR and Triage operational analytics, and a reconciliation engine to verify data completeness against the IDR twice weekly.

```mermaid
flowchart TB
    subgraph Sources["Data Sources"]
        ARC["ARC (PrEPA PostgreSQL)<br/>charges, allegations,<br/>staff, closures"]
        ADR_Data["ADR Analytics<br/>(metrics, reliance,<br/>model drift)"]
        Triage_Data["Triage Analytics<br/>(classifications,<br/>corrections, drift)"]
        IDR["IDR (SQL Server)<br/>Nightly ARC snapshot"]
    end

    subgraph UDIP["UDIP Central Data Store"]
        MW["Data Middleware<br/>YAML mappings, value translation,<br/>PII redaction, validation"]
        Raw["Analytics Tables<br/>analytics.charges<br/>analytics.adr_outcomes<br/>analytics.adr_daily_metrics<br/>analytics.triage_daily_metrics"]
        dbt["dbt Models<br/>fct_charges, fct_adr_sessions<br/>fct_adr_performance<br/>fct_triage_performance"]
        RLS["Row-Level Security<br/>Region + Office + PII tier"]
        MW --> Raw --> dbt --> RLS
    end

    subgraph Consumers["Every App Queries UDIP"]
        C1["ADR — case context,<br/>settlement trends"]
        C2["Triage — historical<br/>patterns"]
        C3["OGC — case history,<br/>litigation context"]
        C4["MCP Hub — AI consumer<br/>queries"]
        C5["Superset — dashboards"]
        C6["JupyterHub — notebooks"]
    end

    ARC -->|"WAL/CDC<br/>(real-time)"| MW
    IDR -.->|"reconciliation<br/>(Tue + Fri)"| MW
    ADR_Data -->|"daily push"| Raw
    Triage_Data -->|"daily push"| Raw
    RLS --> C1 & C2 & C3 & C4 & C5 & C6

    style UDIP fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
```

### Build One New Service, Change Nothing in ARC

We are recommending two infrastructure additions alongside the new service:

**1. WAL/CDC Pipeline (primary UDIP data path).** Streams all data from PrEPA's PostgreSQL database to UDIP in real-time via PostgreSQL logical replication (Debezium → Event Hub → UDIP Data Middleware). The publication covers every table in PrEPA — charges, allegations, staff, reference tables, mediation, closures, events — creating a full read replica. Raw data lands in UDIP's `replica` schema with original column names; the Data Middleware translates it into clean, AI-ready datasets in the `analytics` schema. Captures every row-level change including batch jobs and direct SQL. Zero impact on ARC's production write path.

**2. ARC Integration API (write-back + targeted case distribution).** A new Python/FastAPI service that:
- **Pushes targeted case data** to ADR (mediation-eligible cases with charge numbers, mediator assignments, party emails) and Triage (charge metadata at upload time). These are the only direct reads from ARC.
- **Writes back to ARC** from downstream apps: mediation outcomes (closure reason, settlement amounts, benefits), action dates, signed agreements, triage classification results.
- **Bridges** authentication between Entra ID (our apps) and ARC's internal OAuth2.
- **Registers** as an MCP spoke alongside the four apps.
- **Forwards Service Bus events** as notifications to the MCP Hub for inter-app routing (e.g., notifying ADR when a case status changes).

**3. IDR reconciliation.** The IDR (nightly SQL Server snapshot) transitions from UDIP's primary data source to a twice-weekly reconciliation target. The UDIP Data Middleware — already in production with YAML-driven column translation, value mapping, and PII redaction — compares analytics tables against IDR every Tuesday and Friday to verify the CDC pipeline hasn't missed records. As confidence grows, IDR dependency shrinks.

All data flowing into UDIP passes through the existing Data Middleware, which converts ARC's internal codes into clean, human-readable datasets. This middleware is already proven in production.

In parallel, UDIP also receives operational analytics directly from ADR and Triage -- daily metrics, AI reliance scores, model drift signals, correction patterns. This data does not go through ARC (it never lived there). ADR and Triage push it to UDIP's ingest API on a daily schedule.

No changes to FEPA Gateway or PrEPA are required beyond granting a read-only logical replication slot on PrEPA's PostgreSQL database.

### Five Spokes, One Hub

At full build-out, the MCP hub connects to five spokes:

| Spoke | Tools | What It Provides |
|-------|-------|-----------------|
| ADR Mediation | 10 | Case management, documents, scheduling |
| OFS Triage | 8 | Charge classification, drift detection, analytics |
| UDIP Analytics | 3 + N (dynamic) | Query analytics, narrative search, metrics catalog |
| OGC Trial Tool | 3 (planned) | Litigation analysis, case status |
| ARC Integration API | 11 | Targeted ARC reads + write-back for mediation outcomes, documents, triage results |

```mermaid
flowchart TB
    AI["AI Consumer / Analyst"]
    Hub["MCP Hub<br/>Tool routing + auth"]

    AI --> Hub

    Hub <--> ADR["ADR<br/>10 tools"]
    Hub <--> Triage["Triage<br/>9 tools"]
    Hub <-->|"primary query<br/>path"| UDIP["UDIP<br/>3+N tools"]
    Hub <--> OGC["OGC Trial Tool<br/>3 tools"]
    Hub <-->|"write-back<br/>+ targeted reads"| ARC_API["ARC Integration<br/>API — 11 tools"]

    ARC_API <--> ARC["ARC Backbone<br/>(PrEPA + Gateway)"]

    style UDIP fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style ARC_API fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
```

### The UDIP Row-Level Security Problem

UDIP enforces row-level security at the database layer using the caller's regional identity from their Entra ID token. When the hub calls UDIP using its own managed identity (which has no region claim), queries return empty results without any error. The connection appears to work, but the data is silently wrong.

Three options are on the table. We recommend **OAuth 2.0 On-Behalf-Of (OBO)**: the hub acquires a token on behalf of the original caller, preserving their regional identity. UDIP's security model stays unchanged, and the data scoping works correctly.

This needs to be decided and tested before UDIP connects to the hub.

---

## Timeline

The work breaks into seven phases over roughly 13 weeks to first cross-spoke verification:

```mermaid
gantt
    title Implementation Roadmap
    dateFormat YYYY-MM-DD
    axisFormat %b %d

    section Phase 1
    ARC Integration API + WAL/CDC Pipeline + Middleware Updates    :p1, 2026-04-07, 6w

    section Phase 2
    MCP Hub infrastructure             :p2, 2026-04-28, 4w

    section Phase 3
    UDIP as primary query spoke + OBO  :p3, 2026-05-11, 3w

    section Phase 4
    ADR connection + write-back        :p4, 2026-05-25, 3w

    section Phase 5
    OFS Triage connection + write-back :p5, 2026-06-08, 2w

    section Phase 6
    OGC Trial Tool connection          :p6, 2026-06-22, 3w

    section Phase 7
    Cross-spoke verification           :p7, 2026-07-07, 1w
```

| Phase | Weeks | What Happens |
|-------|-------|-------------|
| 1. ARC Integration API + WAL/CDC Pipeline | 1-6 | New integration service built (write-back + targeted reads). WAL/CDC pipeline established (Debezium on PrEPA PostgreSQL, Event Hub provisioning, middleware Event Hub consumer driver, new prepa_*.yaml YAML mappings). IDR reconciliation engine built (twice-weekly verification). UDIP migrated from IDR nightly batch to real-time CDC as primary data source. This is foundational -- UDIP becomes the central data store for all downstream apps |
| 2. MCP Hub infrastructure | 4-7 | Hub deployed with spoke registration, tool routing, event ingestion, audit logging |
| 3. UDIP as primary query spoke | 6-8 | OBO token delegation resolved. UDIP connected as the primary query target for AI consumers |
| 4. ADR connection + write-back | 7-9 | ADR connected with all 10 tools. Mediation write-back tested end-to-end: ADR closes case -> ARC records it -> UDIP picks it up within seconds |
| 5. OFS Triage connection + write-back | 9-10 | Triage connected. Classification write-back to ARC event log. Charge metadata auto-population working |
| 6. OGC Trial Tool connection | 10-12 | Demo auth replaced. MCP server built. Litigation data flowing |
| 7. Cross-spoke verification | 13 | Multi-spoke AI queries work end-to-end |

The big change from the earlier plan: UDIP's migration off the IDR nightly batch is not Phase 8 background work anymore. It is Phase 1 infrastructure. The WAL/CDC pipeline replaces the IDR as the primary data source, with the IDR retained as a twice-weekly reconciliation check. If UDIP is the central data store that every app and every AI query depends on, it needs to be fed reliably and in real-time from ARC before anything else connects.

---

## What We Need to Decide

Five decisions need to be made before or during implementation:

| Decision | Why It Matters | Recommended |
|----------|---------------|-------------|
| ARC WAL/CDC access | Logical replication slot on PrEPA's PostgreSQL is the primary UDIP data path. Read-only, zero write-path impact, but requires ARC DBA cooperation | Grant read-only logical replication slot |
| UDIP token delegation approach | Without this, UDIP data will be silently wrong | OBO flow |
| Integration API tech stack | Python (matches downstream team skills) vs. Java (matches ARC stack). Scope: write-back + targeted reads only | Python / FastAPI |
| Triage async pattern | Triage's submit_case returns immediately; consumers need to poll | Document it in the tool description; keep it simple |
| ARC event format through hub | Forward PrEPA Service Bus events as-is, or transform to MCP schema for inter-app notifications | Transform to MCP schema for consistency |
| OGC Trial Tool MCP scope | Which of the 9 AI analysis tools should be externally accessible | Trial team to propose |

---

## What This Enables

Once the integration is live, we can do things that are currently impossible:

- **UDIP as the single source of truth for internal data.** Every app and every AI query draws from the same governed, RLS-enforced data store, kept current in real-time via WAL/CDC and validated by automated reconciliation. No more IDR nightly batches as the primary source, no more each-app-has-its-own-copy fragmentation.
- **Bidirectional ARC integration.** ADR closes a mediation case and pushes the outcome (closure reason, settlement amount, signed agreement) back to ARC within seconds. Triage classifies a charge and the result appears in ARC's event log for investigators. These results flow from ARC back into UDIP automatically, closing the loop.
- **Cross-system queries through UDIP.** "What are the triage outcomes for cases that became mediation sessions this quarter?" -- UDIP already has both the triage results and the mediation outcomes because it ingests everything from ARC. One query, one data store.
- **Charge metadata auto-population.** Triage analysts stop typing charge numbers and respondent names by hand. The system looks it up from ARC at upload time.
- **New apps plug in without custom integration.** Any future application registers as a spoke, discovers existing tools, and queries UDIP for case data.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| ARC team does not grant WAL/CDC access | No real-time CDC; falls back to Service Bus events + REST API feed endpoints (works but misses batch job changes, higher latency) | Engage ARC DBA early — this is a read-only logical replication slot with zero write-path impact. Frame as reading from the transaction log PostgreSQL already writes for crash recovery |
| UDIP OBO flow is more complex than expected | UDIP connection delayed | Start OBO investigation in Phase 1 so there is runway before Phase 3 |
| OGC Trial Tool auth replacement takes longer | Pushed to a later phase | Trial Tool can connect after the other three; does not block the hub |
| CDC pipeline falls behind or misses records | UDIP has stale or incomplete data | IDR reconciliation engine runs twice weekly (Tue + Fri) comparing analytics tables against the nightly snapshot. Auto-backfills missing records. Alerts if discrepancy exceeds 0.1% |
| PrEPA's Service Bus message format changes | Event notifications to apps break | Pin to a schema version; the integration API transforms events before forwarding. Does not affect the CDC pipeline (WAL reads row-level changes directly) |
| ADR/Triage analytics push fails | UDIP has incomplete analytics picture | Non-fatal by design; each app retries next cycle. UDIP still has ARC data via CDC. App-specific analytics catch up on next successful push |

---

## Next Steps

1. **Review this document** and flag any concerns or questions.
2. **Align on the six open decisions** above, particularly WAL/CDC access and the UDIP token delegation approach.
3. **Engage the ARC DBA team** for logical replication slot access on PrEPA's PostgreSQL. This is the most critical external dependency.
4. **Schedule a kickoff** for Phase 1 (ARC Integration API + WAL/CDC pipeline + UDIP middleware updates) and Phase 2 (MCP Hub infrastructure), which overlap and can start in parallel.
5. **Engage the ARC application team** for Service Bus subscription access (for event notifications between apps) and to confirm PrEPA's event schema.

The detailed architecture plan, endpoint mappings, security checklist, and implementation prompts are available in the workspace if you want to go deeper on any specific area.

---

*Full technical plan: `ARC_API_and_MCP_Architecture_Plan.md`*
*Architecture gap analysis: `Architecture_Gap_Analysis.md`*
*MCP Hub build guide: `MCP_Hub_Build_Guide_Supplement.md`*
*Implementation prompts (14 total): `Implementation_Prompts.md`*
