# ARC Phase 1-4 Vulnerability-to-Card Verification Audit
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Line-by-line verification of every Phase 1-4 task card in the v2 runbook set
(`ARC_Developer_Remediation_Runbook_v2_Phase{1,2,3,4}.md`, 47 cards: P1-01..14,
P2-01..15, P3-01..07, P4-01..11) against the live `eeoc-arc-payloads/` source
(48 repositories) and freshly regenerated scans, checked 2026-06-13.

Finding-level and package-level coverage was already confirmed in
`ARC_Coverage_Traceability_Matrix.md`. This pass is the step-level accuracy work
that the matrix left open: for each card, three checks against the current
source.

- **to-code.** The card's cited file, line, count, package, and version still
  match the source.
- **to-spec.** The remediation steps are technically correct and sufficient for
  the stated problem.
- **verify-works.** The card's own Verify command actually detects the condition
  it claims to detect, when run as written.

Phase 0 is in progress and was not modified. Where a Phase 0 card is referenced
below (P0-05 CORS), it is for context only; the correction lands in shared
measurement tooling, not the Phase 0 card.

Scans were regenerated before this pass (they are ephemeral): gitleaks, full
severity Grype, full severity Trivy on `eeoc-arc-payloads/`.

---

## Verdict Summary

| Card | to-code | to-spec | verify-works | Verdict |
|---|---|---|---|---|
| P1-01 Patch CRITICAL Java | Accurate | Correct | Detects (non-empty CRITICAL Java set) | PASS |
| P1-02 Unsafe deserialization | Accurate (xstream 1.4.9, snakeyaml 1.18, jettison, commons-beanutils 1.9.4) | Correct | Detects | PASS |
| P1-03 Commons / shared utils | Accurate (incl. v1.1 additions: easy-rules-mvel 4.1.0, wss4j 1.5.4, primefaces 7.0) | Correct | Detects | PASS |
| P1-04 Tika / POI | Versions accurate (scanner) | Correct | **POI never reported; tika output inconsistent** | **FIX** |
| P1-05 npm CRITICAL | Accurate (protobufjs 7.5.4, fast-xml-parser, jspdf 4.0.0, basic-ftp, simple-git) | Correct | Runtime (npm audit), sound | PASS |
| P1-06 npm framework libs | Accurate | Correct | n/a (done-when only) | PASS |
| P1-07 Python tooling | Accurate | Correct | n/a (done-when only) | PASS |
| P1-08 javax to jakarta | Accurate (9,436 / 1,770) | Correct | Detects | PASS |
| P1-09 Retire JBoss image | Accurate (6 services) | Correct | Detects; counts files not services | PASS (minor note) |
| P1-10 LTS consolidation | Accurate | Correct | n/a (done-when only) | PASS |
| P1-11 Stabilize API surface | Accurate | Correct | Runtime (curl), sound | PASS |
| P1-12 Replace broken crypto | **Count off: "10 sites"** | Correct | Detects (returns 30) | **MINOR FIX** |
| P1-13 Replace deprecated images | Accurate | Correct | **Misses untagged nginx (anchor break)** | **FIX** |
| P1-14 New-service language std | Accurate | Correct | n/a (done-when only) | PASS |
| P2-01 Method-level authz | Accurate (259 / 1,177; PrEPA 330 / 0) | Correct | Detects | PASS |
| P2-02 Remove permitAll | Accurate (46) | Correct | Detects | PASS |
| P2-03 XXE hardening sweep | Accurate (42 / 0) | Correct | Detects | PASS |
| P2-04 Finish deserialization | Accurate (13 / 14) | Correct | Detects | PASS |
| P2-05 Input validation | Accurate (595 / 2; 945; 299 / 251) | Correct | Detects | PASS |
| P2-06 SSRF controls | Accurate (806) | Correct | n/a (done-when only) | PASS |
| P2-07 Rate limiting | Accurate (0) | Correct | Detects | PASS |
| P2-08 Security headers | Accurate (0) | Correct | Detects | PASS |
| P2-09 CSRF posture | Accurate (8 services) | Correct | Detects | PASS |
| P2-10 Integration boundary | Accurate | Correct | Runtime (curl), sound | PASS |
| P2-11 SQL injection | Accurate (282; DocumentManager.java:146) | Correct | Detects | PASS |
| P2-12 Exceptions / traces | Accurate (1,546 / 590) | Correct | Detects | PASS |
| P2-13 Session cookies | Accurate (176) | Correct | Runtime (curl), sound | PASS |
| P2-14 Feature flags / audit | Accurate | Correct | Runtime, sound | PASS |
| P2-15 Health / structured logs | Accurate | Correct | Runtime (curl), sound | PASS |
| P3-01 Retire JSP/XHTML tier | Accurate (407; distribution) | Correct | Detects | PASS |
| P3-02 Align Angular | **Inventory claim correct; verify wrong** | Correct | **Misses ImsNXG-NG; returns 2 not 3** | **FIX** |
| P3-03 508 text/lang/keyboard | Accurate (104 / 863) | Correct | Detects | PASS |
| P3-04 508 forms/tables/ARIA | Accurate | Correct | n/a (done-when only) | PASS |
| P3-05 508 CI gate | Accurate | Correct | One-level glob misses nested frontends | MINOR FIX |
| P3-06 USWDS | Accurate (AttorneyPortal 3.7) | Correct | n/a (done-when only) | PASS |
| P3-07 Cross-app navigation | Accurate | Correct | n/a (done-when only) | PASS |
| P4-01 CI security gate | Accurate (33 / 48) | Correct | Detects | PASS |
| P4-02 SBOM per service | Accurate (6 refs) | Correct | n/a (done-when only) | PASS |
| P4-03 Continuous monitoring | Accurate | Correct | Placeholder (config-dependent) | PASS |
| P4-04 Dependency automation | Accurate (13 / 48) | Correct | Detects | PASS |
| P4-05 Secret hygiene | Accurate (11 / 48) | Correct | Detects | PASS |
| P4-06 Repo fragmentation | Accurate (48) | Correct | Detects | PASS |
| P4-07 Govern MCP surface | Accurate | Correct | Runtime, sound | PASS |
| P4-08 Test coverage | Accurate (~5% / ~3%) | Correct | Runtime, sound | PASS |
| P4-09 Alfresco EOL | Accurate (6.2.2) | Correct | n/a (decision card) | PASS |
| P4-10 Repo archival policy | Accurate | Correct | n/a (decision card) | PASS |
| P4-11 Event-driven Service Bus | **Accurate (topics grounded)** | Correct (extend, not rebuild) | Detects (63 hits) | PASS |

Four cards need a verify-command fix (P1-04, P1-13, P3-02, P3-05). One card has a
count to reconcile (P1-12). All to-code counts reproduced exactly against the
current source. No remediation step (to-spec) was found wrong or insufficient.

---

## 1. Cards Requiring Correction

### 1.1 P1-04 - Tika / POI: Verify command cannot report POI, and tika output is misleading

**verify-works: FAIL.** The card's command is:

```bash
grep -rhn 'tika-core\|name: .tika-core\|<artifactId>poi' --include='pom.xml' --include='build.gradle' . \
  | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -u   # expect: one Tika line, one POI line
```

Run as written it returns:

```text
1.21
1.28.5
```

Two defects:

1. **POI is never reported.** FedSep declares POI in Gradle group/name/version
   form, not the colon coordinate the pattern assumes:

   ```text
   FedSep-ims-aks-test/build.gradle:147:  implementation group: 'org.apache.poi', name: 'poi', version: '5.3.0'
   ```

   The Maven declarations put the artifact id and the version on separate lines
   (`FedSep-ims-aks-test/pom.xml:58` is `<artifactId>poi</artifactId>` with the
   version on a different line), so the inline version extract finds nothing for
   POI in either build system. The done-when ("one POI line") cannot be
   evaluated.

2. **The tika versions printed are not the versions the card cites.** The card
   names tika 1.5 / 1.24.1 / 1.28.5 (the scanner-observed installed versions).
   The manifest grep prints 1.21 and 1.28.5, including a 1.21 the card never
   mentions, because manifest-declared versions differ from the resolved
   artifacts the scanner sees.

**Fix.** Read the installed-package inventory from the SBOM (Syft), not a
manifest grep and not Grype. Grype rows are vulnerability matches, so once
Tika/POI are upgraded to non-vulnerable versions they drop out of Grype and the
convergence check would print an empty or one-sided result even though the work
is done. Syft lists every installed version, vulnerable or not, which is exactly
what a one-line-each convergence check needs:

```bash
syft dir:. -o json | python3 -c "import json,sys,collections; \
  d=json.load(sys.stdin); v=collections.defaultdict(set); \
  [v[a['name']].add(a['version']) for a in d.get('artifacts',[]) \
   if a['name'] in ('tika-core','tika-parsers','poi','poi-ooxml')]; \
  print({k:sorted(x) for k,x in v.items()})"
# expect: one Tika line and one POI line as modules converge
```

The to-code claim (3.10.1, with 5.3.0 elsewhere) holds, and Syft makes it richer:
it reports poi 3.10.1 / 5.3.0 / 5.4.1 and tika-core 1.5 / 1.28.5 / 3.3.0 across
modules, where Grype matches showed only the vulnerable 3.10.1 / 1.5 / 1.28.5.
The newer non-vulnerable versions present in some modules are invisible to a
vulnerability scanner but are the convergence signal the card depends on.

### 1.2 P1-13 - Replace deprecated base images: Verify misses the untagged nginx it targets

**verify-works: FAIL.** The card's command is:

```bash
grep -rhnE --include='Dockerfile*' '^FROM\s' . | grep -iE 'buster|:latest|^FROM\s+nginx\s*$|openjdk:11'
```

Run as written it returns buster and four openjdk:11 lines, but no nginx. The
`-n` flag on the first grep prefixes every line with `<lineno>:`, so the lines
fed to the second grep look like `13:FROM nginx`. The `^FROM\s+nginx\s*$` sub
pattern is anchored to the start of line and can no longer match, because the
line now starts with the line number. The unanchored sub patterns (`buster`,
`openjdk:11`) still match, which is why those appear and nginx does not.

Untagged `FROM nginx` is present in three repos (AttorneyPortal, FedSep-NG,
ImsNXG-NG, six lines total counting nested checkouts), exactly the moving-tag
target the card lists. The card cannot detect its own finding.

**Fix.** Drop `-n` (the line number is not needed for a presence check):

```bash
grep -rhE --include='Dockerfile*' '^FROM\s' . | grep -iE 'buster|:latest|^FROM\s+nginx\s*$|openjdk:11'   # expect: no output
```

Validated: the corrected command returns buster (1), nginx (6), openjdk:11 (4).

### 1.3 P3-02 - Align Angular: Verify reproduces the old two-app undercount the card corrects

**verify-works: FAIL.** The card text correctly raises the Angular inventory
from the base report's two apps to three (FedSep-NG and ImsNXG-NG on 16.2.12,
IntakeCollectionsUI on 19.x). Its Verify command, however, is:

```bash
grep -rh '"@angular/core"' */package.json 2>/dev/null | sort -u   # one version line
```

The `*/package.json` glob descends exactly one level. FedSep-NG and
IntakeCollectionsUI keep their `package.json` at the repo root, but ImsNXG-NG
keeps the Angular app under `client/`:

```text
ImsNXG-NG-ims-aks-test/client/package.json:    "@angular/core": "^16.2.12",
```

So the command returns only two version lines and never sees ImsNXG-NG, which is
the same one-level-glob blind spot that produced the base report's two-app
undercount. The verify cannot confirm the card's own three-app correction.

**Fix.** Recurse and collapse the nested self-copies:

```bash
grep -rl --exclude-dir=node_modules --include=package.json '"@angular/core"' . \
  | sed -E 's#([^/]+)/\1/#\1/#' | sort -u \
  | while read f; do echo "$f -> $(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <(grep '@angular/core' "$f") | head -1)"; done
```

Validated: returns FedSep-NG 16.2.12, ImsNXG-NG (client) 16.2.12,
IntakeCollectionsUI 19.0.0 - the three apps the card claims.

### 1.4 P3-05 - 508 CI gate: Same one-level glob limitation as P3-02

**verify-works: MINOR.** The command shares the P3-02 blind spot:

```bash
grep -rln 'axe-core\|@axe-core' */package.json 2>/dev/null
```

When the frontends adopt axe-core, this will not see ImsNXG-NG (its
`package.json` is under `client/`). The card's intent (axe-core present in every
retained frontend) cannot be confirmed for that app.

**Fix.** Apply the same recursion as P3-02:

```bash
grep -rln --exclude-dir=node_modules --include=package.json 'axe-core\|@axe-core' .
```

### 1.5 P1-12 - Replace broken crypto: "10 sites" does not match any reproduction

**to-code: MINOR FIX.** The card, `ARC_Coverage_Traceability_Matrix.md` Section
7, and the playbook baseline all state the broken-crypto scheme appears at
"10 sites." The card's own Verify command returns 30:

```bash
grep -rnE --include='*.java' 'PBEWithMD5AndDES|DesEncrypter|getInstance\(\s*"DES' .   # returns 30
```

Deduplicated to a single checkout (the source carries nested self-copies, see
Section 2) the count is 15 occurrences across five files in two services:

```text
FedSep:           FedSepAppCache.java (3), ValidateUtils.java (1), util/DesEncrypter.java (4)
RespondentPortal: service/AuthorizationManager.java (3), utility/DesEncrypter.java (4)
```

The cited `DesEncrypter.java:41` (`"PBEWithMD5AndDES").generateSecret(keySpec);`)
is accurate, and the remediation steps are correct. Only the site count is wrong;
it matches neither the raw command (30), the deduplicated occurrence count (15),
the distinct-file count (5), nor the service count (2).

**Fix.** Reconcile the figure to the Verify command: "30 occurrences (15 after
removing nested-checkout duplicates) across five files in two services
(RespondentPortal and FedSep)." Update the card, matrix Section 7, and the
playbook baseline row together.

### 1.6 Re-audit playbook CORS command returns 3 of 5 services (shared tooling, not a Phase 0 card)

**verify-works: FAIL (measurement tooling).** `ARC_Reaudit_Playbook.md` Section
1.2 reproduces the CORS-wildcard count with a braced group of three greps piped
downstream:

```bash
{ grep -rln --include='*.java' 'setAllowedOrigins(List.of("\*"))' . ; \
  grep -rln --include='*.java' 'CrossOrigin(origins = "\*")' . ; \
  grep -rln --include='*.java' 'CrossOrigin("\*")' . ; } \
  | sed 's|^\./||' | awk -F/ '{print $1}' | sort -u | tee /dev/stderr | wc -l
```

Run as written it returns three services (ECMService, FederalHearings,
SearchDataWebService). Each pattern run on its own matches correctly, and the
union is the documented five. But when the braced (or subshell) group of multiple
`grep -r .` runs has its combined stdout connected to a pipe, only the first
grep's output survives in this environment; the second and third greps contribute
nothing. Reordering confirms it: whichever grep is first is the only one whose
matches reach the pipe.

The documented baseline of five is correct - the Phase 0 verification audit
already confirmed 5 of 5 (EmployerWebService and AzureAdService are the two the
combined command drops). The defect is in the reproduction command, not the
finding.

**Fix.** Replace the braced group with a single extended-regex grep, which is not
subject to the multi-grep-into-pipe truncation:

```bash
grep -rlnE --include='*.java' \
  'CrossOrigin\(([^)]*= *)?"\*"\)|setAllowedOrigins\(List\.of\("\*"\)\)' . \
  | sed 's|^\./||' | awk -F/ '{print $1}' | sort -u
```

Validated: returns all five - AzureAdService, ECMService, EmployerWebService,
FederalHearings, SearchDataWebService.

This affects only the re-audit measurement tooling. The Phase 0 card P0-05, which
lists all five services correctly, is in progress and was not touched.

---

## 2. Systemic Observation: Nested-Checkout Duplication

Not a card defect, recorded so the counts are read correctly. 32 of the 48
extracted repositories contain a nested copy of themselves
(`RespondentPortal-ims-aks/RespondentPortal-ims-aks/...`). The audit's grep-based
counts run over the whole tree and therefore include the duplication. Effect
varies by repo because some nested copies are full and some are partial or empty:

- JSP/XHTML files: 407 as cited, ~204 deduplicated (FedSep 258 vs 129, ImsNXG 122
  vs 61, RespondentPortal 24 vs 12).
- FederalHearings method-auth annotations: 159 as cited = 79 (nested) + 80
  (outer).
- P1-09 JBoss verify returns 10 file matches for 6 distinct services.

This is already named in P4-06 ("nested copy of themselves, which doubled scan
counts") and the base report deduplicated it for the Dockerfile listing but not
for the grep counts. The consequence for this audit:

- The findings and the coverage ratios are unaffected (the 259/1,177 authz ratio,
  the 0-hardened-of-42 XXE ratio, and so on hold regardless of duplication).
- Re-audit deltas remain valid because the baseline and every re-audit run over
  the same tree.
- Absolute per-service counts should be read as upper bounds until the P4-06
  consolidation removes the nested checkouts, after which the counts should be
  re-baselined.

No card text was changed for this; the cards faithfully report the command
output, and the duplication is a source-tree condition P4-06 already owns.

---

## 3. Scan Deltas Since the 2026-06-12 Baseline

Regenerated full-severity scans, for the playbook progression log:

| Scan | Baseline (2026-06-10/12) | 2026-06-13 | Note |
|---|---|---|---|
| Gitleaks secrets | 332 | 332 | Unchanged |
| Grype total (C/H/M/L) | 752 (43/335/336/38) | 762 (43/339/342/38) | +4 High, +6 Medium |
| Trivy total (C/H/M/L) | 398 (17/181/179/21) | 408 (17/185/185/21) | +4 High, +6 Medium |

CRITICAL counts are unchanged on both scanners. The High/Medium increase is
vulnerability-database drift (new advisories published against already-present
package versions), not new code or new dependencies; no package bump has landed
yet. This is the expected pre-remediation signal and is logged, not actioned.

---

## 4. P4-11 Grounding Re-Confirmation

The prior session framed P4-11 as greenfield eventing, which was wrong. The
current card is correctly grounded and was re-verified against the consumer repo:

- `eeoc-arc-integration-api/app/config/__init__.py:25` -
  `service_bus_db_change_topic: str = "db-change-topic"`.
- `eeoc-arc-integration-api/app/config/__init__.py:26` -
  `service_bus_document_topic: str = "document-activity-topic"`.

The card correctly directs the work to extend the existing topics and keep the
established forward-to-Hub path, not to rebuild eventing. to-spec PASS. One
follow-up: a quick search did not locate the Hub `/api/v1/events` receive route
named in `DAES_Component_Integration_Map.md` Section 3.8 by literal path; it may
be expressed as a Functions route binding. Worth confirming during execution, but
it does not change the card's direction.

---

## 5. Phase 0 Completion Coverage in Phases 1-4

The Phase 0 verification audit (`ARC_Phase0_Verification_Audit_2026-06-10.md`)
added four emergency cards (P0-14..17) for exploitable-today classes that the
original plan deferred. Three of those are deliberate emergency subsets that must
be completed later. This pass confirms each completion lands in Phases 1-4, and
flags the one that did not.

| Phase 0 card | Class | Completion in Phases 1-4 | Status |
|---|---|---|---|
| P0-14 | XXE on `/uploadXml` (emergency subset) | P2-03 finishes the remaining 42 parser sites; P1-04 confirms hardening survives the Tika/POI bump | Covered |
| P0-15 | Deserialization + known-exploited CVEs (emergency subset) | P1-01 / P1-04 (CVEs and Tika/POI), P1-02 (deserialization libraries), P2-04 (code sites) | Covered |
| P0-17 | Login.gov signing key in source (single instance) | Class covered systemically by P4-05 (gitignore + gitleaks pre-commit + CI gate on every repo) so it cannot recur | Covered |
| P0-16 | Unauthenticated dev controller (single instance) | **Not generalized** - no Phase 1-4 card kept dev/test/debug controllers out of production builds | **Gap, now closed** |

**The P0-16 gap.** P0-16 gates or removes the one known dev controller
(`IntakeCollectionsService /api/dev`, with `POST /reset-to-element` and
subroutine-start operations). P2-01's default-deny chain would reject such an
endpoint at runtime if it were unguarded, but default-deny is not the right
control for a dev controller: a privileged caller could still reach a
process-control endpoint that should not be in the production artifact at all,
and nothing systemically stopped a new one from shipping. This is the one Phase 0
item whose completion was missing from Phases 1-4.

**Closed in this change.** P2-01 gains a step and a done-when: inventory every
controller exposing dev/test/debug operations and either remove it from the
deployable artifact or guard it behind a non-prod `@Profile`, generalizing the
single P0-16 fix across all 19 services. With that, every Phase 0 emergency card
has a complete Phase 1-4 home.

Everything else maps cleanly: the traceability matrix already routes the original
audit findings (Sections 3-7) to cards, and package-level severity was confirmed
complete in matrix Section 8. After this change the answer to "is every Phase 0
item carried to completion" is yes.

---

## 6. Corrections Applied in the Accompanying Change

| Item | File | Change |
|---|---|---|
| P1-04 verify | `ARC_Developer_Remediation_Runbook_v2_Phase1.md` | Replace manifest grep with a Syft SBOM inventory (works post-remediation) |
| P1-12 count | `ARC_Developer_Remediation_Runbook_v2_Phase1.md` | Reconcile "10 sites" to the reproducible count |
| P1-13 verify | `ARC_Developer_Remediation_Runbook_v2_Phase1.md` | Drop `-n` so the nginx anchor matches |
| P2-01 dev controllers | `ARC_Developer_Remediation_Runbook_v2_Phase2.md` | Add step + done-when generalizing the P0-16 dev-controller fix |
| P3-02 verify | `ARC_Developer_Remediation_Runbook_v2_Phase3.md` | Recurse, exclude node_modules, dedup so ImsNXG-NG is seen |
| P3-05 verify | `ARC_Developer_Remediation_Runbook_v2_Phase3.md` | Recurse and exclude node_modules for nested frontends |
| P1-12 count | `ARC_Coverage_Traceability_Matrix.md` | Section 7 figure reconciled |
| Crypto baseline / CORS command | `ARC_Reaudit_Playbook.md` | Baseline row reconciled; CORS command replaced with single grep |
| Consolidated rebuild | `ARC_Developer_Remediation_Runbook_v2_Phases1-4.md` | Reconciled to the per-phase sources |

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-13 | Derek Gordon / OCIO | Line-by-line Phase 1-4 vuln-to-card verification; five verify-command and count corrections; nested-checkout and scan-delta notes |

Inputs: `ARC_Developer_Remediation_Runbook_v2_Phase{1,2,3,4}.md`,
`ARC_Coverage_Traceability_Matrix.md`, `ARC_Reaudit_Playbook.md`, regenerated
gitleaks / Grype / Trivy scans of `eeoc-arc-payloads/`, and the consumer repos
`eeoc-arc-integration-api/` and `eeoc-mcp-hub-functions/`.
