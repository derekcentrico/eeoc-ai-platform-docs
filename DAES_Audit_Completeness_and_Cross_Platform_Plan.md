# DAES Audit Completeness and Cross-Platform Audit Plan
**Author:** Derek Gordon

## Data and AI Enterprise System (DAES)

---

Every DAES application must carry a complete audit trail across four dimensions
(FOIA / AI-generation, NARA retention, security events, and access/authorization),
and that trail must be viewable both per application and, in aggregate, from a
single cross-platform console in Access Admin. This document inventories the
current state (ADR is the reference model), names the gaps, proposes the
cross-platform architecture, and lays out a phased roadmap.

Compliance basis: FOIA 7-year retention, NARA records schedule, NIST 800-53
Rev 5: AU-2/3 (event content), AU-5/6 (security-event capture and review),
AU-9 (audit protection / WORM), AU-10 (non-repudiation / HMAC), AU-11
(retention), and M-21-31 (event logging maturity).

---

## 1. The Four Audit Dimensions

| Dimension | What must be captured | Control |
|---|---|---|
| **FOIA / AI-generation** | Every AI generation (prompt/response hashes, model, tokens, latency, office, sector, case, user-hash), HMAC-signed, WORM-archived | AU-10, M-21-31 |
| **NARA retention** | 7-year (2555-day) immutability on the audit store; protected from disposal | AU-9, AU-11 |
| **Security events** | Auth failures, role-denied (403), CSRF rejections, rate-limit (429), SSRF rejections, written to the **immutable audit store**, not just app logs | AU-5, AU-6 |
| **Access / authorization** | Who accessed which record; grant/permission/role changes (create, revoke, bulk) | AU-2, AC-6 |

---

## 2. Reference Model: ADR (and its own gaps)

ADR is the most complete and the pattern to match. It has:

- **AI-generation audit:** `shared_code/ai_audit_logger.py` to `aigenerationaudit`
  table + `ai-generation-archive` WORM blob; HMAC-SHA256; 30+ fields;
  `RetentionPolicy=FOIA_7_YEAR`; `_verify_immutability_policy()` (AU-9 warn).
- **NARA retention:** `learning-processor-function/FinalizeDisposal/` protects
  `aigenerationaudit`, `reliancescores`, `modeldrift`, `aifeedback` from disposal.
- **Security/access audit:** four tables (`apiauditlog`, `officeauditlog`,
  `useractivityaudit`, admin-audit) covering admin actions, office changes, and
  per-user case activity.
- **Audit UI:** `/admin/audit-logs` unified viewer (filters: case, user, action,
  date range, source) + `/cases/<id>/activity` per-case timeline.
- **Audit export:** `/admin/audit-logs/export` (CSV/JSON) and `/api/v1/foia-export`
  (signed ZIP, chain-of-custody, SAS URL).
- **Fairness:** `RelianceScorer` (`reliancescores`) and `ModelDriftDetector`
  (`modeldrift`): over-reliance and PSI/JS drift monitoring.

ADR's own gaps (the "missing wiring" expected):
- **A-G1:** Auth failures, CSRF, and rate-limit (429) events are logged to
  Application Insights only, **not** to an immutable audit table (AU-5/6 gap).
- **A-G2:** No field-level PII-access audit (case-level only).
- **A-G3:** `reliancescores` / `modeldrift` are not linked back to the specific
  `aigenerationaudit` rows that produced them (no traceability).

---

## 3. Coverage Gap Matrix

Legend: ✓ complete · ◐ partial · ✗ missing · — N/A

| App | FOIA/AI-gen WORM | NARA retention | Security events → audit store | Access/authz audit | Audit UI | Audit query/export |
|---|---|---|---|---|---|---|
| **ADR** (model) | ✓ | ✓ | ◐ (A-G1) | ✓ | ✓ | ✓ |
| **UDAP** | ✓ `aiassistantaudit` | ✓ | ✗ | ◐ (SQL `hold_audit_log`, not WORM) | ◐ (stub, no backend) | ✓ FOIA export |
| **MCP Hub** | ✓ `hubauditlog` | ✓ | ✗ | ◐ (caller hash only) | ✗ (backend) | ✗ |
| **ARC Integration API** | ✓ `arcintegrationaudit` | ✓ | ◐ | ✓ (grant lifecycle, fail-closed) | ✗ (backend) | ✗ |
| **Triage** | ✓ `aigenerationaudit` | ✓ | ◐ (export + admin only) | ✗ | ✓ (2 dashboards) | ◐ (no REST) |
| **OGC Trial Tool** | ✓ `aigenerationaudit` | ✓ | ◐ | — (grants live in ARC) | ◐ (FOIA export only) | ✓ FOIA export |
| **OCHCO** | ✓ (WORM blob added via #45/#46) | ✓ (post #45/#46) | ✗ | ✗ | ✗ | ✗ |
| **Access Admin** | — | — | ◐ (logs only) | ✗ (grant audit lives in ARC, not viewable here) | ✗ | ✗ |

---

## 4. Cross-Cutting Gaps (priority order)

1. **Security-event audit is missing or partial on every app, including ADR.**
   Auth failures, role-denied, CSRF, and rate-limit events go to mutable app logs,
   not the immutable audit store. This is the single largest, most universal gap
   (AU-5/6). Highest priority.
2. **No standard audit-query contract.** Table names diverge
   (`aigenerationaudit` / `aiauditlog` / `hubauditlog` / `arcintegrationaudit` /
   `aiassistantaudit`); only some apps expose any query/export; none expose a
   uniform query interface. This blocks cross-platform aggregation.
3. **Audit UI exists only in ADR (full) and Triage (partial).** UDAP is a stub;
   OGC is FOIA-export-only; OCHCO/MCP-Hub/ARC/Access-Admin have none.
4. **Access-change audit is not viewable.** ARC records grant lifecycle (well),
   but Access Admin (the tool that *makes* those changes) neither stores nor
   displays them.
5. **HMAC derivation and key validation** standardized to hex-decode (OGC #125,
   ADR #382, Triage #158), in flight; UDAP/MCP-Hub/ARC use their own consistent
   schemes (verify). Enforce a minimum 32-character (256-bit) key-length check in
   production on every app (MCP Hub already fails hard) to rule out weak keys.

---

## 5. Cross-Platform Audit UI: Architecture

The cross-platform console lives in **Access Admin**. Three ways to feed it:

- **Option A: MCP-aggregated `audit.query` (recommended).** Each app exposes a
  standardized read-only `audit.query` (and `audit.export`) MCP tool over its own
  WORM store. The MCP Hub aggregates them (it already aggregates spoke tools).
  Access Admin's console calls the Hub for a unified, filtered, cross-app view.
  *Pros:* reuses existing MCP aggregation; each app keeps its own WORM store (no
  single point); standardizes the contract; respects per-app RBAC. *Cons:* every
  app must implement the `audit.query` tool.
- **Option B: Central audit store.** All apps dual-write audit to one shared
  store; Access Admin reads it. *Pros:* trivial aggregation. *Cons:* re-architects
  every app's audit; single point of failure/compromise; cross-app PII in one
  place; large blast radius.
- **Option C: Direct storage reads.** Access Admin is granted read on every app's
  storage account and queries tables directly. *Pros:* no per-app code. *Cons:*
  tightly couples Access Admin to every schema; broad storage grants; brittle.

**Decision: Option A** (approved). It fits the MCP-native platform, keeps audit
data in each app's immutable store, and makes the contract explicit and
RBAC-gated.

### 5.1 Sequencing constraint: ADR ships to production first, siloed

ADR goes to production and runs **siloed for several months** before any other
app reaches prod. Therefore:

- **ADR must be audit-complete on its own first.** Its audit completeness must not
  depend on the MCP Hub or the cross-platform console; for months it *is* the
  production system.
- The **cross-platform console is designed now (Option A) but built later**, when
  the other apps approach production. Aggregating a siloed ADR against not-yet-prod
  apps has no value yet.
- Each later app gets its `audit.query` tool and per-app UI as it matures, so the
  console can light up cleanly when cross-platform comes online.

---

## 6. Phased Roadmap

**Phase 0: Foundation (highest value, do first)**
- Close the security-event gap on every app: write auth-failure, role-denied,
  CSRF, and rate-limit events to the immutable audit store (model on ADR's
  `apiauditlog`/`useractivityaudit`). Start with ADR (A-G1) as the template.
- Define the standard `audit.query` / `audit.export` MCP tool contract (filters:
  date range, user-hash, event type, case/charge, app) and a common record shape,
  including the standard correlation fields (request_id, caller_oid, response_hash,
  retention_tag) for cross-system traceability.

**Phase 1: Per-app audit query API**
- Implement `audit.query` (read-only, RBAC-gated) on every app over its WORM store.
  ADR/UDAP/OGC already have FOIA export to build from.

**Phase 2: Per-app audit UI**
- Audit viewer page per UI-bearing app (UDAP, OCHCO; complete OGC; Triage already
  has it). Model on ADR's `/admin/audit-logs`. Backend-only apps (MCP Hub, ARC)
  surface only through the cross-platform console.

**Phase 3: Cross-platform console in Access Admin**
- Access Admin audit dashboard querying all apps via the MCP Hub `audit.query`
  aggregate; unified filters; export. Add Access Admin's own grant-change audit
  view (surfacing ARC's `arcintegrationaudit` access events).

---

## 7. Per-App Remediation Summary

| App | Top remediation items |
|---|---|
| **ADR** | A-G1 security events → audit table (403/CSRF/rate-limit done; route local CSRF 403s through a shared validate-or-403 helper that logs); A-G3 link reliance/drift to audit rows |
| **UDAP** | Security events → WORM audit; move grant audit off mutable SQL; real audit UI; `audit.query` tool |
| **MCP Hub** | Security events (SSRF/auth/rate-limit) → `hubauditlog`; `audit.query` tool |
| **ARC** | Security events (403/429) → audit; `audit.query` tool; expose grant audit for Access Admin |
| **Triage** | Auth failures → audit table; access/authorization audit; `audit.query` tool; REST export |
| **OGC** | Security events → audit; complete audit UI; `audit.query` tool |
| **OCHCO** | Security events + access audit; audit UI; `audit.query` tool (WORM now handled #45/#46) |
| **Access Admin** | Grant-change audit (local or surfaced from ARC); security events → dedicated WORM store or routed via API to a central store (it has no local storage account); the cross-platform console |

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial audit-completeness assessment, gap matrix, cross-platform architecture, phased roadmap |
