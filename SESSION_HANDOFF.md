# Session Handoff — EEOC AI Integration Platform

**Date:** 2026-04-05 (updated from 2026-04-04 session)
**Working Directory:** `/home/derek/ai-platform/workspace/`
**Purpose:** Everything a new Claude session needs to pick up where this one left off.

---

## What This Project Is

The EEOC (Equal Employment Opportunity Commission) is building an enterprise AI integration platform that connects 5 internal applications to a central data store (UDIP), enabling real-time case data access, AI-powered analytics, cross-system decision support, and bidirectional write-back to the ARC system of record — all on Azure Government (FedRAMP High).

The platform replaces fragmented, siloed applications with a unified data backbone where every app feeds and every app queries the same governed data.

---

## Architecture (One Paragraph)

PrEPA (ARC's PostgreSQL system of record) streams all database changes via WAL/CDC (logical replication → Debezium → Azure Event Hub) into UDIP's PostgreSQL database, where the Data Middleware (YAML-driven column translation, PII redaction, validation) transforms raw ARC data into clean, AI-ready analytics tables. The MCP Hub (Azure API Management + lightweight aggregator function) routes tool calls from AI consumers to 5 spoke applications (ADR Mediation, OFS Triage, UDIP Analytics, OGC Trial Tool, ARC Integration API). ADR and Triage push operational analytics to UDIP daily and write mediation/classification results back to ARC through the Integration API. The AI Assistant in UDIP provides multi-turn conversations, SQL generation, interactive chart/dashboard creation, all governed by row-level security. ARC requires only 2 SQL commands (replication slot + publication) and read-only DB credentials — zero code changes on their side.

---

## Repositories

| Repo | Path | What |
|------|------|------|
| UDIP Analytics | `eeoc-data-analytics-and-dashboard/` | Central data store, AI assistant, CDC pipeline, middleware, lifecycle management |
| ADR Mediation | `eeoc-ofs-adr/` | Public-facing mediation case management (staff + external parties via Login.gov) |
| OFS Triage | `eeoc-ofs-triage/` | AI-powered charge classification with GPT-4o |
| OGC Trial Tool | `eeoc-ogc-trialtool/` | Litigation support, case analysis (replacing Ollama with Azure OpenAI) |
| ARC Integration API | `eeoc-arc-integration-api/` | Write-back bridge to ARC backbone, targeted case pushes |
| MCP Hub Functions | `eeoc-mcp-hub-functions/` | Tool catalog aggregator (hub routing is Azure APIM, not custom code) |
| ARC Payloads (reference) | `eeoc-arc-payloads/` | ARC source code (read-only, not ours to modify) |

---

## Planning Documents in Workspace Root

| File | What | Lines |
|------|------|-------|
| `Implementation_Prompts.md` | **51 implementation prompts** — the master plan. Each prompt targets a specific repo with exact code changes. | ~4500 |
| `ARC_API_and_MCP_Architecture_Plan.md` | Full technical architecture: endpoints, auth, data flows, roadmap | ~800 |
| `Architecture_Gap_Analysis.md` | Every gap found: security audit, scalability audit, FOIA/NARA, M-21-31 EL3 | ~400 |
| `Azure_MCP_Hub_Setup_Guide.md` | Portal step-by-step for APIM-based MCP Hub | ~554 |
| `Azure_Full_Deployment_Guide.md` | Portal step-by-step for all Azure resources | ~580 |
| `Azure_Deployment_Sequence.md` | 5-phase deployment order with dependencies and gate criteria | ~400 |
| `EEOC_AI_Platform_Azure_Overview.md` | 3-page CIO briefing: architecture, security, cost comparison (in-house $1.8M vs commercial $18-33M over 5 years) | ~180 |
| `OCIO_Leadership_Briefing.md` | Executive summary with mermaid diagrams for leadership | ~430 |
| `MCP_Hub_Build_Guide_Supplement.md` | Detailed hub build guide covering all 5 spokes | ~560 |
| `UDIP_Database_Selection_PostgreSQL_vs_Azure_SQL.md` | PostgreSQL vs Azure SQL justification | ~150 |
| `draft.email.to.fix.docx` | Email draft to leadership (updated for WAL/CDC approach) | docx |

---

## Prompt Status (51 Prompts)

### Completed and pushed (Prompts 1-38): ALL DONE

- Prompts 1-26: Executed 2026-04-03 (core infrastructure, integration, security, scaling, AI assistant, CI/CD)
- Prompts 27-38: Executed 2026-04-05 (tests, K8s manifests, scaling fix-ups, graceful degradation, AI fix-ups, FOIA retention, data layer migration)

### Pending (Prompts 39-52): NOT YET RUN

| Prompt | Repo | What | Priority |
|--------|------|------|----------|
| ~~27~~ | All repos | Unit tests for 14 uncovered modules | **DONE** |
| ~~28~~ | ADR | Production K8s + Front Door WAF | **DONE** |
| ~~29~~ | Triage | Production K8s + HPA | **DONE** |
| ~~30~~ | ARC Integration API | Production K8s + HPA | **DONE** |
| ~~31~~ | Triage | Scaling fix-up: OpenAI retry wiring, repartition, ZIP streaming | **DONE** |
| ~~32~~ | ADR | Graceful degradation: standalone operation | **DONE** |
| ~~33~~ | UDIP | Read replica routing | **DONE** |
| ~~34~~ | UDIP | AI Assistant fix-up: get_messages→get_history, tiktoken, error refinement | **DONE** |
| ~~35~~ | Triage | MSAL token cache to Redis | **DONE** |
| ~~36~~ | UDIP | Schema for ADR + Triage operational tables | **DONE** |
| ~~37~~ | ADR | Data layer migration: Table Storage → PostgreSQL | **DONE** |
| ~~38~~ | Triage | Data layer migration: Table Storage → PostgreSQL | **DONE** |
| **39** | UDIP | **FOIA/NARA: conversation history 7-year retention (currently 90-day TTL)** | **Critical** |
| **40** | All repos | FOIA export API: /api/foia-export with ZIP + chain-of-custody | High |
| **41** | All repos | Litigation hold mechanism: centralized hold table, FinalizeDisposal integration | High |
| **42** | ARC Integration API | M-21-31/FedRAMP: HMAC audit logging, retention policy, audit table | High |
| **43** | MCP Hub Functions | M-21-31/FedRAMP: HMAC audit, PII hashing, correlation IDs | High |
| **44** | OGC Trial Tool | M-21-31/FedRAMP: Structured JSON logging, HMAC, correlation IDs | High |
| **45** | Infrastructure | M-21-31 EL3: Azure Sentinel, NSG flow logs, DNS Analytics, UBA, SOAR | Medium |
| **46** | OGC Trial Tool | License remediation: remove poppler/GPL, replace python-jose, pin deps | High |
| **47** | All repos | Supply chain: Trivy container scanning, Dependabot, system dep SBOM | High |
| **48** | OGC Trial Tool | **Replace Ollama with FoundryModelProvider (default Azure OpenAI GA)** | High |
| **49** | Triage | Adopt FoundryModelProvider pattern (default Azure OpenAI GA, Foundry optional) | High |
| **50** | Workspace root | **Complete deployment guide (zero-assumption, 1500-2000 lines)** | High |
| **51** | Workspace root | **Provisioning script (provision_eeoc_ai_platform.sh, 800-1200 lines)** | High |
| **52** | UDIP | Auto-schema detection: new tables auto-created, labeled via column registry, dbt models generated, AI-discoverable | Medium |
| **53** | Triage | Multi-tenancy: OFS/OFP sector, office hierarchy, district scoping, 3-layer access control, 508 compliance | High |
| **54** | Triage | OFP intake pipeline: CDC case detection, configurable 5-day delay, OFP system prompt, scoring, document refresh | High |
| **55** | Triage + ARC API | ARC write-back: classification routing endpoints, NRTS trigger, configurable field mapping, approval workflow | High |
| **56** | Triage | OFS Rank C decision letter: AI-assisted DOCX generation, attorney review, ARC closure (disabled by default) | Medium |
| **57** | Triage | RAG library expansion: SEP, Compliance Manual, Commission Guidance categories, OFS/OFP sector filtering | High |
| **58** | Triage | OFS submission window: configurable timer, extension handling, CDC monitoring, manual early review | High |

### Recommended Execution Order (from Prompt 39 onward)

**Prompts 27-38 are DONE.** Start from here:

**Run first (FOIA/NARA — legal compliance):**
```
Prompt 39 (Conversation 7-year retention — currently 90-day TTL)
Prompt 40 (FOIA export API — all repos)
Prompt 41 (Litigation hold mechanism)
```

**Run second (compliance logging — M-21-31 / FedRAMP):**
```
Prompt 42 (ARC Integration API HMAC audit logging)
Prompt 43 (MCP Hub Functions HMAC audit logging)
Prompt 44 (OGC Trial Tool structured JSON + HMAC logging)
```

**Run third (OGC remediation — license + Ollama removal):**
```
Prompt 46 (OGC license: remove poppler/GPL, replace python-jose, pin deps)
Prompt 48 (OGC replace Ollama with FoundryModelProvider / Azure OpenAI GA)
```

**Run fourth (supply chain + Triage provider):**
```
Prompt 47 (supply chain hardening all repos — Trivy, Dependabot, SBOM)
Prompt 49 (Triage adopt FoundryModelProvider)
```

**Run fifth (infrastructure + deployment):**
```
Prompt 45 (Azure Sentinel, NSG flow logs, DNS Analytics, UBA, SOAR)
Prompt 50 (complete deployment guide — zero-assumption)
Prompt 51 (provisioning script — provision_eeoc_ai_platform.sh)
```

**Run sixth (automation):**
```
Prompt 52 (auto-schema detection, column registry, AI discovery)
```

**Run seventh (Triage OFP expansion — Prompts 53-58):**
```
Prompt 53 (multi-tenancy foundation: hierarchy, scoping, 508) ← must be first
Prompt 57 (RAG library expansion: new categories, sector filtering) ← before 54
Prompt 58 (OFS submission window timer and CDC monitoring)
Prompt 54 (OFP intake pipeline: case pull, classification, document refresh)
Prompt 55 (ARC write-back: classification routing — run in BOTH repos)
Prompt 56 (OFS Rank C decision letter — optional, disabled by default)
```

### How to Run Prompts

Each prompt targets a single repo. Start a new Claude session, paste:

```
Working directory: ~/ai-platform/workspace/{repo-name}/

Read the prompt from ~/ai-platform/workspace/Implementation_Prompts.md
Find "## Prompt {N}:" and implement everything it specifies.

For each change:
1. Implement the code
2. Run existing tests if they exist
3. Commit with a descriptive message
4. Move to next item in the prompt

After all items done, create a PR.
```

Prompts targeting multiple repos (27, 40, 41, 47) should be run once per repo.

---

## Known Bugs (Found During Verification)

| Bug | Repo | Status | Prompt |
|-----|------|--------|--------|
| `chat.py` calls `store.get_messages()` but method is `get_history()` | UDIP | **FIXED** (Prompt 34 ran) | 34 |
| No tiktoken context window management | UDIP | **FIXED** (Prompt 34 ran) | 34 |
| Conversation history 90-day TTL (FOIA requires 7 years) | UDIP | **UNFIXED** — Prompt 39 NOT YET RUN | 39 |
| `call_openai_with_retry()` not wired to actual calls | Triage | **FIXED** (Prompt 31 ran) | 31 |
| Cases table `PartitionKey = "cases"` hot partition | Triage | **FIXED** (Prompt 31 ran) | 31 |
| CaseFileProcessor ZIP `io.BytesIO(myblob.read())` OOM risk | Triage | **FIXED** (Prompt 31 ran) | 31 |
| `case_partition_key` missing from ADR constants.py | ADR | **FIXED** (direct push) | — |
| MCP Hub protocol version 2024-11-05 | Hub | **FIXED** (direct push) | — |
| Triage UDIP ingest payload key `target_table` | Triage | **FIXED** (direct push) | — |

**Only remaining unfixed bug:** Conversation 90-day TTL (Prompt 39 — next to run).

---

## Work Done Since 2026-04-04 (Latest Session)

### New Documents Created
- `EEOC_AI_Platform_Azure_Overview.md` — 3-page CIO briefing with cost comparison (in-house $1.8M vs commercial $18-33M over 5 years)
- `Azure_Full_Deployment_Guide.md` — Portal step-by-step for all Azure resources (580 lines)
- Updated `SESSION_HANDOFF.md` (this file)

### New Prompts Added (42-52)
- **42-44**: M-21-31/FedRAMP compliance logging for ARC API, MCP Hub, OGC (HMAC audit, PII hashing, correlation IDs)
- **45**: Azure Sentinel + NSG flow logs + DNS Analytics + UBA + SOAR (M-21-31 EL3 infrastructure)
- **46**: OGC license remediation (remove poppler/GPL, replace python-jose, pin deps, document Ollama model licenses)
- **47**: Supply chain hardening all repos (Trivy scanning, Dependabot, system dep SBOM)
- **48**: OGC replace Ollama with FoundryModelProvider (default Azure OpenAI GA, Foundry optional)
- **49**: Triage adopt FoundryModelProvider pattern (same as ADR, default Azure OpenAI GA)
- **50**: Complete platform deployment guide (zero-assumption, 1500-2000 lines target)
- **51**: Azure provisioning script (provision_eeoc_ai_platform.sh, 800-1200 lines target)
- **52**: Auto-schema detection with column registry, dbt model generation, AI discovery

### Key Decisions Made
- Azure OpenAI (GA) is the default AI provider for ALL apps — Foundry wired but NOT enabled (beta packages fail SCA)
- OGC Trial Tool must replace Ollama entirely — not FedRAMP authorized, no managed identity, no audit
- poppler-utils (GPL-2.0) in OGC Docker container is a license violation — must be removed (Prompt 46)
- python-jose in OGC is deprecated — replace with PyJWT (Prompt 46)
- M-21-31 EL3 requires Azure Sentinel, SOAR playbooks, UBA, NSG flow logs, DNS Analytics (Prompt 45)
- FedRAMP Rev5 SR (Supply Chain) family requires Trivy container scanning, Dependabot, system dep SBOM (Prompt 47)
- OSCAL format required for authorization packages by September 2026
- PgBouncer QUERY_TIMEOUT was updated from 30s to 60s by Derek (external edit noted)
- YAML FK mappings updated by Derek for charge_inquiry_id consistency across prepa_*.yaml files

### Audits Completed (2026-04-03 to 2026-04-04)
1. **Cross-repo interface audit** (96 checks): 92 passed, 2 fixed (protocol version + ingest payload key), 2 noted
2. **Test coverage audit**: 9 of 14 new modules uncovered → Prompt 27
3. **Scaling verification** (ADR/Triage/UDIP): Found case_partition_key missing in ADR (fixed), OpenAI retry unwired in Triage, ZIP still BytesIO in Triage
4. **Security fixes verification** (Prompts 18-20): 19/20 landed, only MSAL token cache still in cookie
5. **AI Assistant verification** (Prompts 24-26): 14/17, crash bug (get_messages vs get_history), missing tiktoken, incomplete error refinement
6. **OGC + CI/CD verification** (Prompts 5, 12-13): 17/17 all clean
7. **ADR + Triage integration verification** (Prompts 2-3, 7-8, 10-11): 22/22 all clean
8. **UDIP core pipeline verification** (Prompts 4, 9, 15-17): 20/20 all clean
9. **FOIA/NARA compliance audit**: Conversation 90-day TTL violates 7-year requirement, no FOIA export API (3 repos), no litigation hold mechanism
10. **M-21-31 EL3 + FedRAMP Rev5 audit**: ARC API, Hub, OGC missing HMAC audit logging; no Sentinel/SOAR/UBA; no container scanning
11. **License/SCA audit**: OGC has poppler (GPL), python-jose (deprecated), all deps unpinned; Ollama not production-grade

---

## Fixes Made Directly in This Session

| What | Repo | Commit |
|------|------|--------|
| Added `case_partition_key()` to ADR constants.py | eeoc-ofs-adr | `c714e25` |
| Fixed MCP Hub protocol version `2024-11-05` → `2025-03-26` | eeoc-mcp-hub-functions | `041be2d` |
| Fixed Triage UDIP ingest payload key `target_table` → `dataset` | eeoc-ofs-triage | `81c604c` |
| PgBouncer configmap: 500/50 → 3000/80/200 (two commits) | eeoc-data-analytics-and-dashboard | `31b13c0`, `7b8488d` |
| Lifecycle schema + RLS (PR #61, merged) | eeoc-data-analytics-and-dashboard | Squash merge |
| YAML mapping configs (PR #62, merged) | eeoc-data-analytics-and-dashboard | Squash merge |

---

## Database Sizing

- PrEPA source: ~800 GB, ~350 tables, ~8,500 columns
- UDIP target: ~1.7 TB total (replica 800GB + analytics 400GB + vectors 100GB + indexes 200GB + headroom 200GB)
- Instance: Memory Optimized, 16 vCores, 128 GB RAM, 2 TB storage
- PgBouncer: 3000 client connections → 200 PostgreSQL connections
- Read replica for query offloading (AI, Superset, JupyterHub → replica; CDC writes → primary)
- ADR: 2000 new cases/month, ~6000 active cases, ~18,000 registered users (public-facing)

---

## Key Architectural Decisions

1. **WAL/CDC over REST API polling** — reads PostgreSQL transaction log, zero impact on ARC
2. **`FOR ALL TABLES`** — full replica of PrEPA, not just 5 tables
3. **Two-schema architecture** — `replica` (raw ARC data) → middleware → `analytics` (clean, AI-ready)
4. **YAML mappings with lookup_table transforms** — JOINs against replicated reference tables instead of hardcoded value maps
5. **Azure OpenAI (GA) as default, AI Foundry wired but not enabled** — Foundry packages are beta, won't pass SCA audit
6. **MCP Hub is APIM + aggregator function, not a custom service** — portal-configured routing with one ~200-line Azure Function
7. **ADR must work standalone** — all integration feature-flagged, defaults to disabled
8. **Conversation history tied to case lifecycle** — 7-year retention from closure, not 90-day TTL
9. **IDR as twice-weekly reconciliation** — not primary source, safety net while CDC proves itself
10. **PostgreSQL over Azure SQL** — pgvector, native CDC from PrEPA, dbt-postgres, lower cost

---

## Compliance Requirements

- **FedRAMP Rev5 High** (Azure Government, NIST 800-53 Rev5, 410 controls)
- **M-21-31 EL3** (Advanced logging: Sentinel, SOAR, UBA, flow logs, DNS, packet capture)
- **NARA 7-year retention** on all AI audit records (WORM blob, 2555 days)
- **FOIA export capability** with chain-of-custody audit trail
- **Litigation hold mechanism** preventing deletion of held records
- **OSCAL format** required for authorization packages by September 2026
- **Supply chain (SR family)**: SBOM, Trivy scanning, Dependabot, vendor assessment
- **License compliance**: No GPL in production containers (poppler flagged in OGC — Prompt 46 fixes)

---

## How to Read Implementation_Prompts.md

The file is ~4500 lines with 51 prompts. Each prompt has:
- Header: `## Prompt N: Title`
- Metadata: Repository, Owner, Phase
- Body inside triple-backtick code block — this is what you paste into a Claude session
- Some prompts have multiple sub-prompts (e.g., Prompt 27 has 4 sub-prompts, one per repo)

The summary table near line 610 shows all prompts with status (DONE/PENDING).
The execution order section near line 640 shows dependencies.

---

## Memory Files

Saved to `/home/derek/.claude/projects/-home-derek-ai-platform-workspace/memory/`:
- `project_arc_integration.md` — Architecture decisions and context
- `user_derek.md` — Derek's role and preferences

---

## What NOT to Do

- **Do NOT modify ARC code** (eeoc-arc-payloads/) — their code, their responsibility
- **Do NOT enable AI Foundry in production** — azure-ai-inference is beta, use Azure OpenAI GA
- **Do NOT remove the YAML middleware** — it's the translation layer between ARC's internal labels and human-readable data
- **Do NOT set conversation retention below 7 years** for case-linked conversations (FOIA requirement)
- **Do NOT connect spokes out of sequence** — ARC Integration API first, then ADR, Triage, UDIP, OGC
- **Do NOT deploy without PgBouncer** — direct PostgreSQL connections will exhaust at scale
- **Do NOT use Ollama in production** — replace with Azure OpenAI via FoundryModelProvider (Prompt 48)
- **Do NOT assume Table Storage partition keys are correct** — ADR was fixed, Triage still needs Prompt 31
