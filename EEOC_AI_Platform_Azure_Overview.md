# EEOC AI Integration Platform — How It Works in Azure

**From:** Derek, OCIO AI Platform Lead
**Date:** 2026-04-03
**Classification:** CUI // FOUO
**Pages:** 3

---

## Page 1: Platform Architecture

### What This Platform Does

The EEOC AI Integration Platform connects five internal applications to a central data store, enabling real-time case data access, AI-powered analytics, and cross-system decision support — without modifying the existing ARC system of record.

Every discrimination charge filed with EEOC flows through this platform: from intake through investigation, mediation, enforcement, and closure. The platform serves investigators, mediators, attorneys, analysts, and external parties (charging parties and respondents).

### How It Runs on Azure Government

The entire platform runs on Azure Government (FedRAMP High authorized), using managed services that Microsoft operates within the government cloud boundary. No data leaves the Azure Government region.

**Six applications, one data backbone:**

```
                        Azure API Management
                         (MCP Hub - routing)
                               |
            +---------+---------+---------+---------+
            |         |         |         |         |
          ADR     Triage      UDIP     OGC TT    ARC API
       Container  Container  Container Container Container
        App        App        App       App       App
            \        \         |        /        /
             \        \        |       /        /
              \        --------+------/--------/
               \               |              /
          Azure Database for PostgreSQL Flexible Server
                    (UDIP Central Data Store)
                           |
                    Read Replica
```

| Component | Azure Service | What It Does |
|-----------|--------------|--------------|
| **ADR Mediation** | Container Apps + Azure Functions | Public-facing mediation case management for staff and external parties |
| **OFS Triage** | Container Apps + Azure Functions | AI-powered charge classification and prioritization |
| **UDIP Analytics** | Container Apps + PostgreSQL | Central data store, AI assistant, dashboards, semantic layer |
| **OGC Trial Tool** | Container Apps | Litigation support with local LLM analysis |
| **ARC Integration API** | Container Apps | Write-back bridge to ARC backbone |
| **MCP Hub** | API Management + Azure Functions | Tool routing, auth, event forwarding |

### Real-Time Data Pipeline

ARC's system of record (PrEPA) runs PostgreSQL. Rather than building API polling or batch ETL, the platform reads directly from PostgreSQL's write-ahead log (WAL) — a transaction log that the database already writes for crash recovery. This streams every data change to UDIP within seconds, with zero impact on ARC's production workload.

```
PrEPA PostgreSQL (ARC system of record)
    |
    WAL (already written for crash recovery)
    |
    Debezium Connector (reads WAL, streams changes)
    |
    Azure Event Hub (Kafka-compatible message buffer)
    |
    UDIP Data Middleware (YAML-driven translation, PII redaction)
    |
    UDIP PostgreSQL (clean, governed, AI-ready data)
    |
    AI Assistant + Dashboards + MCP Tools
```

**Why this approach:** ARC has ~800 GB across 350 tables. Traditional API polling would hit ARC's application layer with thousands of queries. WAL-based CDC reads from a log file — no queries, no locks, no load. The ARC team runs two SQL commands to enable it; nothing else changes on their side.

---

## Page 2: Security, Compliance, and Data Governance

### FedRAMP High Alignment

Every Azure service used is FedRAMP High authorized in Azure Government. The platform implements NIST 800-53 controls across all components:

| Control Family | Implementation |
|---------------|----------------|
| **AC (Access Control)** | Entra ID with app roles per service. Role-based access: Admin, Director, Analyst, Viewer. Row-level security at the database layer scopes every query to the user's region and PII tier. |
| **AU (Audit)** | Every AI query, tool invocation, and data access logged to immutable Azure Table Storage + WORM-locked Blob Storage (7-year retention, NARA compliant). HMAC-SHA256 integrity signatures on audit records. |
| **SC (System Communications)** | TLS 1.2+ on all connections. VNet isolation with private endpoints. No public internet exposure except ADR (behind Azure Front Door WAF). |
| **SI (System Integrity)** | SQL injection prevention via AST-level validation (sqlglot). PII redaction (SSN, DOB, email, phone, EIN) via regex before data enters analytics schema. Prompt injection detection on AI inputs. |
| **IA (Identification/Auth)** | Entra ID Government OIDC for staff. Login.gov OIDC+PKCE for external parties. OAuth 2.0 On-Behalf-Of for preserving caller identity through the hub to UDIP. |
| **SA (System Acquisition)** | CycloneDX SBOM generation, Bandit SAST, Semgrep, pip-audit SCA, OWASP Dependency-Check, license compliance scanning — all in CI/CD on every push. |

### Data Governance

**Two-schema architecture:** Raw ARC data lands in a `replica` schema (original column names, pre-translation). The Data Middleware transforms it into the `analytics` schema (clean labels, PII redacted, AI-ready). Nobody queries replica directly — all access goes through the analytics schema with row-level security enforced.

**Data lifecycle management:** Every record tracks when it entered UDIP, when the source case closed, and when NARA 7-year retention expires. FOIA/litigation holds block deletion regardless of age. A Data Steward CLI manages holds and approves purges. Partition-level access tracking identifies cold data for archival.

**PII tiering:** Tier 1 (aggregated, public-safe), Tier 2 (de-identified detail), Tier 3 (full PII, legal/investigation staff only). The middleware enforces tiers during ingestion; the database enforces them at query time.

### AI Safety

The AI Assistant uses Azure OpenAI GPT-4o with guardrails:
- SQL generated by the AI is validated at the AST level before execution (no injection possible)
- Row-level security scopes results to the user's authorized regions
- Prompt injection detection scrubs user input and RAG context
- Model drift detection with automatic circuit breaker (stops AI classification if output quality degrades)
- Every AI interaction logged with tokens used, SQL generated, and response hash

---

## Page 3: What It Costs and What It Enables

### Azure Infrastructure — Monthly Estimated Cost

| Resource | Tier | Monthly Cost |
|----------|------|-------------|
| PostgreSQL Flexible Server (primary, 16 vCores, 128 GB, 2 TB) | Memory Optimized | $1,400 |
| PostgreSQL Read Replica (same tier) | Memory Optimized | $1,400 |
| Container Apps (6 apps × 2-12 instances each) | Consumption + Dedicated | $800 |
| Azure API Management (MCP Hub) | Standard v2 | $700 |
| Azure Cache for Redis (Premium P1) | Premium | $400 |
| Azure Event Hub (Standard, 4 TU) | Standard | $300 |
| Azure Front Door + WAF (ADR public-facing) | Standard | $350 |
| Azure Key Vault | Standard | $10 |
| Azure Storage (audit tables + WORM blob + queues) | GRS | $200 |
| Azure OpenAI (GPT-4o, embeddings) | Pay-as-you-go | $500-2,000 |
| Azure Cognitive Search (Triage RAG) | Standard | $250 |
| Azure Monitor + Log Analytics | Pay-as-you-go | $150 |
| **Total infrastructure** | | **$6,500-8,200/month** |

### What It Enables

Once deployed, the platform provides capabilities that do not exist today:

- **Real-time cross-system visibility.** An analyst asks "what are settlement rates by region this quarter" and gets an answer in seconds, drawing from ARC charge data, ADR mediation outcomes, and Triage classification results — all in one query.
- **AI-powered case analysis.** The AI Assistant has multi-turn conversations, generates SQL, produces interactive charts, and builds dashboards — all governed by row-level security.
- **Bidirectional ARC integration.** ADR closes a mediation case and the settlement amount, signed agreement, and action dates flow back to ARC within seconds. Triage classifies a charge and the result appears in ARC's event log.
- **Operational intelligence.** Model drift detection, AI reliance scoring, and correction flow analysis give leadership visibility into how AI tools are performing and whether analysts are over-relying on or ignoring AI recommendations.
- **Self-service analytics.** Superset dashboards, JupyterHub notebooks, and the AI Assistant replace the dependency on manual SAS/Excel reporting.
- **Future-proof integration.** Any new application registers as a spoke, discovers existing tools, and queries UDIP. No custom integration code.

### Cost Comparison: In-House vs. Commercial Development

**Context on commercial costs:** Federal IT contracting carries overhead rates of 80-150% on top of direct labor. Managed service providers mark up Azure infrastructure 15-30%. Procurement cycles add 6-12 months before development begins. Change orders and SOW amendments for post-deployment modifications typically carry 4-8 week lead times and premium rates.

**What a vendor would be building:** This platform consists of a public-facing mediation application (17,900 lines, dual auth, AI chat, e-signatures, 12 Azure Functions), an AI classification pipeline (GPT-4o, Document Intelligence OCR, malware scanning, model drift detection, RAG), a complete enterprise analytics platform (CDC pipeline, dbt semantic layer, pgvector, conversational AI assistant with visualization and dashboard generation, data lifecycle management), an ARC integration service, and an MCP hub — all FedRAMP-compliant on Azure Government.

| Factor | In-House (EEOC OCIO) | Commercial Vendor |
|--------|----------------------|-------------------|
| **ADR Mediation Platform** | Built (staff time) | $3-5M (public-facing, dual auth, AI, e-sig, complex workflows) |
| **OFS Triage System** | Built (staff time) | $2-4M (AI classification pipeline, GPT-4o, OCR, drift detection) |
| **UDIP Analytics Platform** | Built (staff time) | $3-5M (enterprise analytics, CDC, dbt, AI assistant, dashboards) |
| **ARC Integration + MCP Hub** | Built (staff time) | $1-2M (integration layer, event routing, Debezium CDC) |
| **Development subtotal** | ~$200-300K labor (4 FTEs × 3 months) | **$9-16M** (competitive award, full-stack federal contractor) |
| **Procurement cycle** | N/A (internal team) | 6-12 months, $50-100K in acquisition support costs |
| **Azure infrastructure** | $6,500-8,200/month ($78-98K/year) | Same base + 15-30% managed services markup ($90-127K/year) |
| **FedRAMP assessment** | Leverages existing Azure Gov ATO; agency-level assessment ~$50-100K | 3PAO assessment for new system: $300-600K. Vendor typically bills separately. |
| **Ongoing operations** | 1-2 FTEs for maintenance + Azure costs (~$250-350K/year) | Vendor O&M contract: $1.5-3M/year (includes SLA guarantees, on-call, patching, change orders at premium rates) |
| **Change orders** | Same team implements, same week | SOW amendment: 4-8 weeks, $50-200K per significant change |
| **Time to production** | 13 weeks from kickoff | 18-30 months (6-12 procurement + 12-18 development/testing) |
| **IP ownership** | EEOC owns 100% of source code, no restrictions | Contract-dependent; commonly shared IP or vendor-retained with license-back. Switching vendors requires code escrow and transition. |
| **Vendor lock-in risk** | None | High. O&M contract renewal leverage, proprietary frameworks, knowledge concentration. |

**Total Cost of Ownership:**

| Period | In-House | Commercial |
|--------|----------|------------|
| Year 1 (build + deploy) | ~$400K | ~$10-17M (contract award + procurement + infrastructure + 3PAO) |
| Year 2 | ~$350K | ~$2-4M (O&M + infrastructure + change orders) |
| Year 3 | ~$350K | ~$2-4M |
| Year 4 | ~$350K | ~$2-4M |
| Year 5 | ~$350K | ~$2-4M |
| **5-Year Total** | **~$1.8M** | **~$18-33M** |

The in-house approach costs approximately **90% less over five years**. The gap is driven by three factors: zero procurement overhead, no contractor margin on labor, and no managed services markup on Azure infrastructure. The agency retains full IP ownership, can modify any component without a change order, and has no vendor dependency for ongoing operations.
