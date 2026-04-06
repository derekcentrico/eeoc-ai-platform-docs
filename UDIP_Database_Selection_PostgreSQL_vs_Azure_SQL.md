# UDIP Database Selection: Azure PostgreSQL vs Azure SQL

**Date:** 2026-04-01
**Purpose:** Justify database engine selection for UDIP Analytics Platform before operational launch
**Audience:** OCIO Leadership

---

## Context

UDIP is the agency's centralized analytics and AI platform. It serves as the governed data layer for all downstream applications, AI consumers, dashboards, and data mining. Before UDIP begins operations, the database engine selection must be confirmed.

Both options under consideration are fully managed Azure services. This is not an open-source-vs-Microsoft decision — it is choosing the right Azure database service for the workload.

---

## UDIP's Database Requirements

UDIP is not a transactional system. It is a read-optimized analytical data store with AI capabilities. The database must support:

1. **Real-time change data capture ingestion** from ARC's PostgreSQL system of record (PrEPA)
2. **Row-level security** enforcing regional data boundaries based on caller identity
3. **Semantic layer generation** via dbt for governed metrics and fact tables
4. **Vector embedding storage and similarity search** for AI-powered narrative search across charge documents
5. **Full-text search** across redacted case narratives
6. **YAML-driven middleware integration** for column translation, PII redaction, and data validation
7. **FedRAMP High compliance** and Entra ID authentication

---

## Feature Comparison

| Requirement | Azure Database for PostgreSQL | Azure SQL Database |
|---|---|---|
| **Managed Azure service** | Yes. Flexible Server, SLA-backed. | Yes. Fully managed, SLA-backed. |
| **FedRAMP High authorized** | Yes | Yes |
| **Entra ID authentication** | Yes, native support | Yes, native support |
| **Microsoft Defender for Cloud** | Yes | Yes |
| **Azure Private Link** | Yes | Yes |
| **Azure portal management** | Yes | Yes |
| **CDC from PrEPA (PostgreSQL)** | Native logical replication. Same engine, same wire protocol, same data types. Zero translation. | Requires Debezium to convert PostgreSQL WAL events into SQL Server inserts. Additional translation layer for every row and data type. |
| **Row-level security** | Native RLS with session variables (`SET app.current_regions`). Policies apply transparently to all queries. | Supported via `SESSION_CONTEXT` + `SECURITY_POLICY` with inline predicates. Functionally similar but requires different policy architecture. |
| **dbt semantic layer** | dbt-postgres adapter is the most mature and widely deployed. Full support for incremental models, snapshots, and custom materializations. | dbt-sqlserver adapter exists but has known limitations with incremental models and snapshot strategies. Smaller community, fewer production deployments. |
| **Vector embeddings (AI search)** | pgvector extension. Native SQL queries with vector indexes (`ivfflat`, `hnsw`). Embedding storage and similarity search in the same database as the data. | No native equivalent. Requires a separate Azure AI Search instance, adding cost, latency, network hops, and another service to manage and secure. |
| **Full-text search** | tsvector + GIN indexes. Trigger-based auto-indexing on insert/update. Mature, fast, integrated. | Full-text indexing supported but uses different syntax (CONTAINS, FREETEXT). Requires rewriting all search logic. |
| **JSON support** | jsonb with indexing. Used by middleware for audit records and CDC event payloads. | JSON support via OPENJSON. Functional but no native indexing on JSON fields. |
| **Python ecosystem** | psycopg2 / asyncpg. The standard for Python database connectivity. All four downstream apps already use it. | pyodbc / pymssql. Requires ODBC driver installation. Different connection patterns. |
| **Team skills** | All downstream app teams work in Python + PostgreSQL. | No team members write T-SQL. Learning curve for operations and troubleshooting. |

---

## Cost Comparison

| Tier | Azure PostgreSQL Flexible Server | Azure SQL Database |
|---|---|---|
| 4 vCores, 32 GB RAM, 512 GB storage | ~$350/month | ~$750/month (General Purpose) |
| 8 vCores, 64 GB RAM, 1 TB storage | ~$700/month | ~$1,500/month (General Purpose) |
| **16 vCores, 128 GB RAM, 2 TB storage** | **~$1,400/month** | **~$3,200/month (Memory Optimized)** |
| + Read replica (same tier) | ~$1,400/month additional | ~$3,200/month additional |

**Production sizing note:** PrEPA source is ~800 GB across ~350 tables. UDIP needs ~1.7 TB total (replica + analytics + vectors + indexes). Memory Optimized tier recommended for RLS predicate evaluation, pgvector HNSW searches, and GIN index scans under concurrent load.
| Licensing model | Open source. No per-core licensing. | Per-core or DTU licensing. Enterprise features (columnstore, in-memory) require Premium tier. |
| Vector search | Included (pgvector extension, no additional cost) | Requires separate Azure AI Search ($250+/month for basic tier) |

Costs are approximate and vary by region. The gap widens at higher tiers because Azure SQL licensing compounds with core count.

---

## CDC Compatibility

ARC's system of record (PrEPA) runs PostgreSQL. The proposed data pipeline uses PostgreSQL logical replication to stream changes to UDIP in real-time.

| Path | Azure PostgreSQL | Azure SQL |
|---|---|---|
| **PrEPA → UDIP** | PostgreSQL → PostgreSQL. Native logical replication. Same data types, no conversion. Debezium optional (can use native pgoutput subscriber). | PostgreSQL → SQL Server. Requires Debezium to read PostgreSQL WAL, convert row images to SQL Server-compatible inserts, handle data type mismatches (e.g., PostgreSQL UUID → SQL Server UNIQUEIDENTIFIER, PostgreSQL TIMESTAMPTZ → SQL Server DATETIMEOFFSET). |
| **Failure mode** | If types match natively, fewer silent data corruption risks. | Type conversion mismatches can cause silent truncation or precision loss. |
| **Operational complexity** | One database engine to understand. | Two database engines (PostgreSQL source + SQL Server target) with different behaviors, locking semantics, and diagnostic tools. |

---

## Migration Cost if Azure SQL Were Chosen

UDIP is built but not yet operational. Switching to Azure SQL before launch would require:

| Component | Effort |
|---|---|
| RLS policies | Redesign from PostgreSQL session variables to SQL Server SECURITY_POLICY predicates |
| dbt models (all staging + fact tables) | Port from dbt-postgres to dbt-sqlserver, work around adapter limitations |
| Vector embedding pipeline | Replace pgvector with Azure AI Search. New service provisioning, new API integration, new index management |
| Full-text search | Rewrite tsvector/GIN queries to CONTAINS/FREETEXT syntax |
| Middleware sync engine | Replace psycopg2 driver with pyodbc. Rewrite batch upsert logic (PostgreSQL ON CONFLICT → SQL Server MERGE) |
| All YAML mapping configs | Update target column types, quoting rules (PostgreSQL `""` vs SQL Server `[]`), computed expressions |
| Audit tables | Restructure for SQL Server conventions |
| CDC pipeline | Add data type translation layer between PostgreSQL source and SQL Server target |
| Analytics table definitions | Rewrite CREATE TABLE statements, indexes, constraints |
| Connection management | Replace psycopg2 connection pooling with pyodbc + ODBC driver installation in all containers |

Estimated effort: 4-6 weeks of rework before UDIP can begin operations, with ongoing risk from dbt adapter limitations and the added CDC translation layer.

---

## Compliance Posture

Both services meet the same compliance requirements:

| Control | Azure PostgreSQL | Azure SQL |
|---|---|---|
| FedRAMP High | Authorized | Authorized |
| NIST 800-53 (SI-10, SA-4, AC-6, AU-3, SC-8) | Supported | Supported |
| Encryption at rest | AES-256, Azure-managed or customer-managed keys | AES-256, TDE enabled by default |
| Encryption in transit | TLS 1.2 enforced | TLS 1.2 enforced |
| Audit logging | pgAudit extension + Azure Diagnostic Logs | Built-in auditing + Azure Diagnostic Logs |
| Threat detection | Microsoft Defender for Cloud | Microsoft Defender for Cloud |
| Backup/PITR | Automated, up to 35 days retention | Automated, up to 35 days retention |
| Private networking | Azure Private Link, VNet integration | Azure Private Link, VNet integration |

There is no compliance gap between the two options.

---

## Recommendation

**Azure Database for PostgreSQL Flexible Server** is the recommended engine for UDIP.

The decision comes down to three factors:

1. **ARC is PostgreSQL.** Native CDC between the same database engine eliminates an entire class of data type translation bugs and reduces operational complexity.

2. **The AI workload requires vector search.** pgvector provides this natively at no additional cost. Azure SQL requires a separate Azure AI Search service — more cost, more latency, more infrastructure to secure and maintain.

3. **It is an Azure service.** Fully managed by Microsoft, FedRAMP High authorized, Entra ID integrated, visible in the Azure portal, covered by Azure support plans. Choosing PostgreSQL on Azure is choosing an Azure product.

The cost is lower, the CDC path is simpler, the AI capabilities are native, and the team already knows the tooling. There is no compliance, security, or operational gap that would justify the 4-6 week rework cost of switching to Azure SQL.
