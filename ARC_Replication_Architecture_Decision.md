# ARC Replication Architecture Decision
**Author:** Derek Gordon

---

## 1. Background

The Data and AI Enterprise System (DAES) needs data from ARC's PostgreSQL database (PrEPA) to power analytics dashboards, AI assistants, cross-domain queries, and role-based access control. The ARC DBA (Scott) maintains an existing replication pipeline from ARC PostgreSQL into an IDR (SQL Server) for Power BI reporting. He opposes granting WAL access for a new CDC pipeline, citing concerns about production database stability.

This document records the technical assessment of his concerns, what is correct and incorrect, and the two-phase data ingestion strategy the platform will follow.

---

## 2. DBA Position Summary

Scott's position: do not open WAL access. Use table-level incremental replication (his existing pattern) instead.

His key arguments:

1. WAL/log-shipping between PostgreSQL and SQL Server is impossible. Transaction logs are engine-specific.
2. Even same-engine WAL replication has a scalability ceiling. Transactions must be applied serially. Under load, the destination throttles the source ("deadly embrace").
3. Debezium is open-source, self-maintained, immature, and any failure forces a full destination rebuild.
4. His table-level incremental design is decoupled. 15-20 parallel pipelines move only the latest version of each changed row. Can be paused for days and catches up in one cycle.
5. Power BI, Fabric, and the Microsoft analytics ecosystem require SQL Server for query pushdown. That decision is locked in.

---

## 3. Technical Assessment: Correct vs. Incorrect

### What Scott Gets Right

**WAL replication between PostgreSQL and SQL Server does not work.**
WAL formats are engine-specific. The IDR is SQL Server. Scott cannot use WAL to feed it. His watermark-based incremental sync is the correct approach for his PostgreSQL-to-SQL-Server pipeline.

**His table-level incremental approach is genuinely good.**
Transfers only the latest version of each changed row (skips intermediate changes). Runs 15-20 parallel pipelines. Can be paused for days and catches up in one cycle. Fully decoupled from ARC production. Battle-tested over years.

**Power BI needs SQL Server for query pushdown.**
Correct for the Microsoft analytics ecosystem. Not relevant to DAES, which uses Apache Superset (native PostgreSQL support).

**Debezium failures can require re-snapshot.**
If a connector loses its offset position (e.g., WAL retention exceeded), it must re-read all tables. This is a real operational consideration. Debezium handles it automatically, but it takes time on large datasets.

### What Scott Gets Wrong

**"WAL replication will throttle the website / deadly embrace."**
Scott is describing **physical (synchronous) streaming replication** between HA cluster nodes. In that model, the standby replays WAL records and the primary may need to wait for the standby to catch up before releasing locks. That IS bidirectionally coupled.

DAES uses **logical replication**, which is a fundamentally different mechanism:

- PostgreSQL commits the transaction and the user's operation is complete immediately
- WAL is written to disk (PostgreSQL does this regardless for crash recovery)
- Debezium reads the WAL files afterward at its own pace, like a log file reader
- There is no feedback channel from Debezium to ARC's primary
- ARC does not wait for the consumer. ARC does not know the consumer exists
- If the consumer is slow or offline, WAL files accumulate (capped at 16GB in our config, roughly 80 hours at current write volume), but ARC continues operating normally
- When the consumer comes back online, it picks up where it left off

PostgreSQL.org documents logical replication as fully asynchronous with no impact on the publisher.

**"The so-called asynchronous distills down to synchronous under load."**
True for Microsoft's HA clusters (physical replication with synchronous commit). Not true for PostgreSQL logical replication slots. Logical replication slots are one-directional with no synchronous feedback path.

**"Everyone who tried Debezium had problems / college project."**
Likely true when he evaluated it (approximately 2022-2023). Debezium is now a CNCF incubating project maintained by Red Hat/IBM, used in production by thousands of organizations. However, his operational concern about a small team maintaining open-source infrastructure remains fair.

**"As soon as you tie into the WAL, you put your database at risk."**
WAL reading is a filesystem-level operation. PostgreSQL writes WAL files for crash recovery regardless of whether any consumer reads them. A logical replication slot reading those files puts approximately the same load as a standard WAL archiving backup, which every production PostgreSQL database already performs.

The only risk is disk space: if the consumer falls far enough behind, WAL files accumulate. The `max_slot_wal_keep_size = 16GB` setting caps this. If the cap is exceeded, the slot is invalidated (consumer must re-snapshot), but ARC's production database is unaffected.

---

## 4. Two-Phase Data Ingestion Strategy

### Phase 1: Bootstrap from IDR (one-time)

Pull the current state of available tables from the IDR (SQL Server) into UDAP PostgreSQL using the watermark-based sync engine that already exists in the data-middleware.

- Source: IDR SQL Server (Scott's existing replicated store)
- Destination: UDAP PostgreSQL analytics schema
- Driver: pyodbc (already implemented in `data-middleware/sync_engine.py`)
- Load on ARC production: zero (reads from the IDR, not from ARC directly)
- Data freshness: up to 24 hours stale (IDR is a nightly snapshot)
- Purpose: gives us a populated starting point without touching ARC

The IDR currently contains only 2 of the 38 tables the platform needs (dbo.CHG_TBL for charges, dbo.ADR_OUT for ADR outcomes). For the remaining tables, options are:

- Ask Scott for a one-time pg_dump of the needed tables (one-time ask, not ongoing)
- Let Debezium perform its built-in initial snapshot when Phase 2 activates (automatically reads current state of all published tables before switching to streaming)

### Phase 2: Switch to WAL/CDC (ongoing real-time)

Enable PostgreSQL logical replication on ARC's PrEPA database. Debezium reads changes going forward from the point the replication slot was created. The IDR bootstrap from Phase 1 ensures historical data is already in place.

- Source: ARC PostgreSQL (PrEPA) via logical replication slot
- Destination: UDAP PostgreSQL via Azure Event Hub
- Driver: Debezium PostgreSQL connector with pgoutput decoder
- Load on ARC production: equivalent to WAL archiving (filesystem reads, no table scans)
- Data freshness: sub-second
- Purpose: real-time ongoing sync of all published tables

Two SQL commands required from the ARC DBA:

```sql
SELECT pg_create_logical_replication_slot('udap_cdc', 'pgoutput');
CREATE PUBLICATION udap_publication FOR ALL TABLES;
```

No code changes to ARC. No schema changes. No new APIs. Read-only access to log files the database already writes.

### How the Two Phases Connect

Phase 1 populates the analytics database with the current state. Phase 2 picks up all changes from the point the replication slot was created. If there is a gap between the IDR snapshot time and the slot creation time, the Tuesday/Friday reconciliation engine (already implemented) detects and backfills missing records automatically.

The IDR continues to operate independently for Scott's Power BI reporting. The UDAP pipeline and the IDR pipeline do not interact with each other.

---

## 5. RBAC Role Sync

The four ARC authorization tables (user_detail, user_office_domain_role_membership, access_role, access_office) are NOT in the IDR. They exist only in ARC's admin schema.

Current approach: the ARC Integration API polls these tables via ODBC every 15 minutes using a read-only credential (implemented in `arc_role_sync.py`). This requires Scott to grant a read-only SQL credential scoped to those 4 tables.

When Phase 2 (WAL/CDC) is active, the authorization tables would flow through the same logical replication stream as all other tables, and the 15-minute ODBC poll would be retired. Until then, the poll is the correct interim approach.

---

## 6. What the IDR Contains vs. What We Need

| Source | Tables in IDR | Tables needed by platform | Gap |
|---|---|---|---|
| PrEPA (private-sector charges) | 2 (charges, ADR outcomes) | 18 | 16 tables |
| Federal Hearings | 0 | 14 | 14 tables |
| Angular case management | 0 | 1 | 1 table |
| ARC admin schema (auth) | 0 | 4 | 4 tables |
| HR systems | 0 | 2 | 2 tables |
| **Total** | **2** | **39** | **37 tables** |

The IDR is useful for bootstrapping charge data and ADR outcomes. Everything else requires either WAL/CDC (Phase 2), REST API polling (fallback), or one-time data exports from the ARC team.

---

## 7. Fallback Paths (if WAL access is delayed)

Three fallback paths are documented in `deploy/cdc-pipeline/docs/fallback-path.md`:

1. **Service Bus events.** The ARC Integration API publishes database change events to Azure Service Bus. The data middleware can consume these instead of Event Hub. Latency: 1-5 seconds. Requires the ARC Integration API to be notified of changes (via webhook or polling).

2. **REST API polling.** The ARC Integration API provides `GET /api/v1/feeds/{table_name}?since={timestamp}&limit=1000` endpoints. The sync engine polls these on intervals. Latency: polling interval (configurable, typically 1-5 minutes). Zero dependency on ARC's database layer.

3. **Watermark-based sync.** Direct ODBC read from ARC PostgreSQL using timestamp watermarks (same pattern as the IDR pipeline but targeting PostgreSQL). Latency: sync interval. Requires a read-only credential.

All three fallbacks are implemented in the data-middleware codebase. The driver abstraction (`eventhub`, `servicebus`, `rest`, `postgresql`, `pyodbc`) allows switching between them via YAML configuration, not code changes.

---

## 8. Key Files

| File | Purpose |
|---|---|
| `eeoc-data-analytics-and-dashboard/data-middleware/sync_engine.py` | Watermark-based incremental sync (IDR and fallback) |
| `eeoc-data-analytics-and-dashboard/deploy/cdc-pipeline/sql/001-replication-slot.sql` | Logical replication slot creation |
| `eeoc-data-analytics-and-dashboard/deploy/cdc-pipeline/sql/002-publication.sql` | Publication creation (all tables) |
| `eeoc-data-analytics-and-dashboard/deploy/cdc-pipeline/sql/003-replication-permissions.sql` | CDC user permissions |
| `eeoc-data-analytics-and-dashboard/deploy/cdc-pipeline/sql/004-wal-retention.sql` | WAL retention cap (16GB) |
| `eeoc-data-analytics-and-dashboard/deploy/cdc-pipeline/docs/fallback-path.md` | All fallback paths documented |
| `eeoc-data-analytics-and-dashboard/docs/Source_System_Reference_Guide.md` | Complete source system inventory |
| `eeoc-arc-integration-api/app/services/arc_role_sync.py` | 15-minute RBAC poll (interim until CDC) |
| `eeoc-arc-integration-api/docs/ARC_Role_Sync.md` | RBAC sync documentation |
