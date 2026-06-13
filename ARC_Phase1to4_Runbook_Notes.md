# ARC Phase 1-4 Runbook - Working Notes

**Author:** Derek Gordon
**Purpose:** refresh anchor for the Phase 1-4 v2 runbook build. Read this first
when returning to the work. It records what was verified, where the source data
comes from (and how to regenerate it, because the scan outputs are ephemeral),
the target-version decisions, and per-phase status.

This is a working file, not a deliverable. Update it as phases are drafted and as
code or package releases change.

---

## Status

| Phase | File | State | Notes |
|---|---|---|---|
| Phase 0 | `..._v2_Phase0.md` | done, merged | 4 card corrections + P0-14..17 emergency cards |
| Phase 1 | `..._v2_Phase1.md` | P1-01..14 | + crypto (P1-12), base images (P1-13), language standard (P1-14) |
| Phase 2 | `..._v2_Phase2.md` | P2-01..15 | + SQLi, exceptions, session cookies, feature flags/audit, health+structured logging (P2-15) |
| Phase 3 | `..._v2_Phase3.md` | P3-01..07 | + USWDS (P3-06), cross-app nav (P3-07) |
| Phase 4 | `..._v2_Phase4.md` | P4-01..11 | + test coverage, Alfresco, archival, event-driven Service Bus (P4-11) |
| Consolidated | `..._v2_Phases1-4.md` | regenerated v1.3 | 47 cards; rebuild from sources after any per-phase edit |
| Coverage matrix | `ARC_Coverage_Traceability_Matrix.md` | created | every audit finding/task -> card; full coverage confirmed 2026-06-12 |

---

## How to refresh yourself fast (returning to this work)

1. Read this file, then the Phase 0 v2 file and the verification audit
   (`ARC_Phase0_Verification_Audit_2026-06-10.md`) for the established method.
2. The scan JSONs in `/tmp` do **not** persist. Regenerate them before trusting
   any count (commands below).
3. Re-verify every version number against the upstream release page. The targets
   in the Phase docs are stamped "latest stable as of 2026-06-10" and go stale.
4. Re-run the four-loop verification on any card you touch (method below).

### Regenerate the source scans

Run from `eeoc-arc-payloads/`:

```bash
cd /home/derek/ai-platform/workspace/eeoc-workspace/eeoc-arc-payloads
# Grype full-severity (the canonical dependency inventory)
grype dir:. --output json --file /tmp/grype-report.json
# Trivy full-severity
trivy fs --severity CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN --format json --quiet -o /tmp/trivy-all.json .
# Gitleaks (secrets, for Phase 0 cross-checks)
gitleaks detect --source . --no-git --redact --report-path /tmp/gitleaks-report.json
```

### Regenerate the clustered package inventory (Phase 1 card list)

```bash
python3 -c "
import json, collections
d=json.load(open('/tmp/grype-report.json'))
rank={'Critical':4,'High':3,'Medium':2,'Low':1,'Negligible':0,'Unknown':0}
pkg=collections.defaultdict(lambda:{'vers':set(),'sev':0,'n':0,'types':set()})
for m in d['matches']:
    a=m['artifact']; p=pkg[a['name']]
    p['vers'].add(a['version']); p['n']+=1; p['types'].add(a['type'])
    p['sev']=max(p['sev'], rank.get(m['vulnerability']['severity'],0))
for name,p in sorted(pkg.items(), key=lambda kv:(-kv[1]['sev'],-kv[1]['n'])):
    print(name, {4:'CRIT',3:'HIGH',2:'MED',1:'LOW',0:'?'}[p['sev']], p['n'], sorted(p['vers']))
"
```

### The four-loop verification method (applied to each Phase doc)

- **Loop 1 (accuracy):** every version/count cited exists in `/tmp/grype-report.json`
  or a real manifest. Grep the manifest to confirm.
- **Loop 2 (trace):** direct vs transitive is correct (a "direct" claim means an
  explicit version line exists; a "transitive" claim means it does not).
- **Loop 3 (impact):** the affected-service/repo list is real (grep it).
- **Loop 4 (consistency):** counts match across docs; no em/en dashes; no banned
  AI terms; no internal tooling-path or skill references; cross-doc numbers
  reconciled.

Loop 4 hygiene, run per phase doc:
- em/en dash sweep: `grep -nP '[\x{2013}\x{2014}]' "$F"` should return nothing.
- banned-AI-term sweep: grep the doc against the term list in the workspace
  writing-style guide; should return nothing.
- tooling-reference sweep: grep for internal development-tooling path and skill
  references per the clean-export rules; should return nothing.

---

## Verified data snapshot (2026-06-10)

Re-verify before reuse. Source: full-severity Grype/Trivy on `eeoc-arc-payloads/`.

### Estate sizing
- 48 repos, ~30,129 source files.
- Build manifests: **39 pom.xml, 12 build.gradle, 15 package.json = 66**.
- Dependency findings (the two scanners count differently; keep them separate):
  Grype 752 all-severity (CRIT 43 / HIGH 335 / MED 336 / LOW 38).
  Trivy 398 (CRIT 17 / HIGH 181 / MED 179 / LOW 21).
- Distinct vulnerable packages: ~61 (Trivy names), 114 package+version (Grype).

### Phase 1 high-fan-out clusters (current versions verified in scan)
- logback-core/classic: 1.0.7, 1.1.8, 1.2.9 (transitive) -> 1.5.x
- tika-core/parsers: 1.5, 1.24.1, 1.28.5 (mixed) -> 3.x (API migration)
- log4j 1.2.16 (transitive, EOL) -> reload4j 1.2.25 or log4j2 2.24.x
- xstream 1.4.9 (transitive, **102 findings, largest cluster**) -> 1.4.21 + allowlist
- snakeyaml 1.18 (transitive) -> 2.3 (SafeConstructor default change)
- poi/poi-ooxml 3.10.1 and 5.3.0 (mixed) -> 5.4.x (standardize)
- commons-fileupload 1.5 (direct, build.gradle) -> commons-fileupload2 2.0.0
- spring-boot-starter-web 2.2.4.RELEASE (direct, Spring4Shell) -> 3.4.x via P1-08
- axios 1.13.5/1.15.0/1.15.2, next 15.5.14/15.5.18, @angular 16.2.12 + 19.x

### Direct vs transitive (verified, critical for card accuracy)
- **Direct** (explicit version line exists): tika-core (some poms), poi 5.3.0,
  commons-fileupload 1.5, axios, next, @angular/core, hibernate-core, postgresql.
- **Transitive** (no version line; managed by parent/BOM): log4j, xstream,
  snakeyaml, logback, jettison, gson, bcprov, jackson. These need a managed
  override or a parent bump, NOT an in-place edit.

### JBoss base-image services (verified, Phase 1 P1-09 / Phase 3)
Six on `eus1opsacr.azurecr.io/eeoc-jboss74`: DocumentGeneratorAdapter,
EEOCWebService, FedSep, ImsNXG, RespondentPortal, jboss-docker (base).

### Phase 2 surface (from base report, verified)
- 918 of 1,177 endpoints without method-level auth.
- 42 XML parser sites, 0 hardened (P0-14 covers the emergency subset).
- 27 deserialization sites (13 ObjectInputStream + 14 XStream).
- 806 outbound HTTP client sites (SSRF surface).
- 595 @RequestParam (2 validated), 945 @PathVariable, 299 @RequestBody (251 valid).
- 8 services CSRF-disabled (P0-11 list corrected); 0 services set CSP/HSTS.

### Phase 3 surface (from base report + Phase 3 recon, verified)
- 407 JSP/XHTML files (FedSep 258, ImsNXG 122, RespondentPortal 24,
  EEOCWebService 2, DocumentGeneratorAdapter 1); 2,296 JSF API usages.
- 508: 104 images no alt, 300 docs no lang, 863 inline onclick.
- **3 Angular apps, not 2** (base report undercounted): FedSep-NG and ImsNXG-NG
  on 16.2.12, IntakeCollectionsUI on 19.x. Align all three to one current major.

### Logging / PII (corrected in two-pass review, 2026-06-11)
- **No SSN, no phone in logs.** The 565 PII-log "candidates" are email (456) +
  name (113); the SSN/phone tokens returned 0. SSN exists in the model (78 field
  refs) but is never logged.
- Real leak: email addresses logged cleartext at INFO in FederalHearings / email
  services. No PII-masking utility exists in the ARC Java services.
- PrEPAWebService (212, the biggest contributor) is mostly false positives: the
  word "email" in message text, with charge numbers/IDs as the actual values.

### Integration readiness (verified platform-consumer patterns, 2026-06-12)

The integration cards (P1-11, P2-10, P4-07) describe what the ARC side must
provide. They are grounded in the existing consumers, which already implement the
other half of the pattern. Verified by reading the repos:

- `eeoc-arc-integration-api` is the mature gateway: inbound bearer auth
  (`app/auth/inbound.py`), outbound service auth (`app/auth/outbound.py`),
  per-ARC-service clients (`services/federal_hearings_client.py`, `prepa_client`,
  `employer_client`, `fepa_client`), correlation middleware
  (`middleware/correlation.py`), rate limiting (`middleware/rate_limit.py`),
  RFC 7807, SSRF-guarded outbound URLs (`validate_url`, blocks private/loopback),
  and an MCP hub integration (`services/mcp_hub.py`).
- `eeoc-mcp-hub-functions` aggregates "spokes": Entra ID M2M token spoke auth
  (`hub_functions/auth.py`), spokes registered in Table Storage
  (`SPOKE_TABLE_NAME = "mcpspokes"`), SSRF CIDR allowlist for spoke URLs
  (`hub_functions/security.py`).
- Platform rules applied in the cards: `MCP_ENABLED`/`MCP_PROTOCOL_ENABLED`
  default false and every service must be healthy with integrations disabled;
  AI generations require an HMAC-signed, 7-year WORM audit record; inter-service
  is HTTPS only with X-Request-ID propagation and RFC 7807 errors.
- The gap is the ARC side: legacy services do not authenticate the gateway, do
  not emit RFC 7807, do not propagate X-Request-ID, and publish no contract. The
  cards build that half. Framing is generic ("downstream platform services",
  "future AI-assisted or cross-system workflows"); ADR is never named.

---

## Open decisions that cannot be pre-baked (flag at execution)

1. **Major-bump breaking changes.** Version targets are listed, but XStream
   allowlist wiring, POI 3.x->5.x API changes, snakeyaml 1.x->2.x constructor
   change, tika 1.x->3.x parser API, and Spring Boot 2.x->3.x (jakarta) are real
   engineering resolved against the actual build at execution time.
2. **The 918-endpoint authorization matrix (Phase 2).** Which role guards which
   endpoint needs product/role input we do not have. Phase 2 cards prescribe the
   method and hand over the inventory; they cannot fill the role-to-endpoint map.
3. **JSP retirement scope (Phase 3).** The JSF-bound JBoss services need a
   frontend rewrite to leave the old namespace; that is a program, not a card.
4. **Integration auth mechanism (P2-10).** The exact service-to-service auth on
   the ARC side (Entra ID M2M token vs managed identity vs mTLS) is a platform
   decision aligned with how the gateway already authenticates outbound. The card
   prescribes "authenticate the caller, accept only the gateway"; the mechanism
   is chosen at execution to match the gateway's outbound model.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Initial notes; Phase 1 drafted and verified |
| 1.1 | 2026-06-12 | Derek Gordon / OCIO | All phases verified; integration-readiness cards added (P1-11, P2-10, P4-07); MEDIUM/LOW coverage clarified; P1-03 table fix folded in |
