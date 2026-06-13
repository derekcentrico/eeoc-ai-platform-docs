# ARC Re-Audit Playbook

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Operational guide for re-running the ARC audit every few weeks as the ARC team
ships updates, so progress against the remediation plan is measurable. Written to
be picked up cold: read this top to bottom, run the commands, fill in the
progression log, and report deltas. It complements the build-state notes in
`ARC_Phase1to4_Runbook_Notes.md` (this file is the recurring measurement loop;
that one is how the runbooks were assembled).

---

## 0. What this is and how the pieces fit

The ARC system (legacy Java estate) lives read-only under
`eeoc-arc-payloads/`. It was audited in June 2026 and a phased remediation plan
written. The team executes the plan; this playbook measures their progress by
re-running the same scans and greps and comparing to the baseline.

**Document set (all in this repo, `eeoc-ai-platform-docs/`):**

| Doc | Role |
|---|---|
| `ARC_Modernization_Audit_and_Phased_Plan.md` | The original audit and the audit's own phased plan |
| `ARC_Audit_Command_Findings_2026-06-10.md` | Verbatim command-output evidence (base report) |
| `ARC_Audit_Findings_Addendum_2026-06-10.md` | XXE trace, XXE-vs-RCE risk notes, crypto-date correction |
| `ARC_Secondary_Scan_Findings_2026-06-10.md` | MEDIUM/LOW dependency tier |
| `ARC_Audit_Commands_Reference.md` | The canonical command set the audit ran |
| `ARC_Developer_Remediation_Runbook_v2_Phase0.md` | Emergency hardening cards (P0-01..17) |
| `ARC_Developer_Remediation_Runbook_v2_Phase{1,2,3,4}.md` | Phase cards (P1-01..14, P2-01..14, P3-01..07, P4-01..10) |
| `ARC_Developer_Remediation_Runbook_v2_Phases1-4.md` | Consolidated single-file view (regenerated from the per-phase files) |
| `ARC_Coverage_Traceability_Matrix.md` | Every audit finding/task -> card |
| `ARC_Phase1to4_Runbook_Notes.md` | Build-state notes, verified data snapshot |
| `ARC_Reaudit_Playbook.md` | This file |

Phase 0 is in progress as of 2026-06-12. The first re-audit should show Phase 0
items (secrets, CORS, CSRF, sessions, headers) trending toward their targets.

---

## 1. Re-audit procedure

### 1.1 Regenerate the scans (they are ephemeral; do not trust stale `/tmp`)

Run from the ARC source root. These take a few minutes; run in the background.

```bash
cd "$ARC_SRC"   # set ARC_SRC to the eeoc-arc-payloads checkout
gitleaks detect --source . --no-git --redact --report-path /tmp/arc-gl.json
grype dir:. --output json --file /tmp/arc-grype.json
trivy fs --severity CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN --format json --quiet -o /tmp/arc-trivy.json .
```

### 1.2 Run the metric collection

Each metric below maps to a remediation card. Run all of them, record the number
in the progression log (Section 3). Most are one-liners; the full command set is
in `ARC_Audit_Commands_Reference.md`.

```bash
cd "$ARC_SRC"   # set ARC_SRC to the eeoc-arc-payloads checkout

# Secrets (P0-01..10, P4-05)
python3 -c "import json;print('secrets:',len(json.load(open('/tmp/arc-gl.json'))))"

# Dependency CVEs (P1-01..07, P4-03) - track Grype and Trivy separately (they count differently)
python3 -c "import json,collections;d=json.load(open('/tmp/arc-grype.json'));c=collections.Counter(m['vulnerability']['severity'] for m in d['matches']);print('grype:',dict(c),'total',len(d['matches']))"
python3 -c "import json,collections;d=json.load(open('/tmp/arc-trivy.json'));c=collections.Counter(v['Severity'] for r in d.get('Results',[]) for v in r.get('Vulnerabilities',[]));print('trivy:',dict(c))"

# Broken crypto (P1-12)
grep -rnE --include='*.java' 'PBEWithMD5AndDES|DesEncrypter|getInstance\(\s*"DES' . | wc -l

# Deserialization (P0-15, P1-02, P2-04)
grep -rn --include='*.java' 'ObjectInputStream\|readObject()' . | wc -l
grep -rn --include='*.java' 'XStream\|xstream' . | wc -l

# XXE: parser sites vs hardening calls (P0-14, P2-03)
grep -rn --include='*.java' 'DocumentBuilderFactory\|SAXParserFactory\|XMLInputFactory\|TransformerFactory' . | wc -l
grep -rn --include='*.java' 'disallow-doctype-decl\|FEATURE_SECURE_PROCESSING\|ACCESS_EXTERNAL_DTD' . | wc -l

# AuthZ: annotations vs endpoints (P2-01); permitAll (P2-02)
grep -rn --include='*.java' '@PreAuthorize\|@Secured\|@RolesAllowed' . | wc -l
grep -rn --include='*.java' -E '@(Get|Post|Put|Delete|Patch|Request)Mapping' . | wc -l
grep -rn --include='*.java' 'permitAll' . | wc -l

# CORS wildcard (P0-05) - both styles in one extended-regex pass, deduped to
# unique services (compare to baseline 5). A braced group of separate greps piped
# downstream truncates to the first grep's output in some shells; one grep -E
# alternation avoids that and still covers the annotation and config styles.
grep -rlnE --include='*.java' \
  'CrossOrigin\(([^)]*= *)?"\*"\)|setAllowedOrigins\(List\.of\("\*"\)\)' . \
  | sed 's|^\./||' | awk -F/ '{print $1}' | sort -u | tee /dev/stderr | wc -l

# CSRF disabled (P0-11, P2-09)
grep -rln --include='*.java' 'csrf.*disable\|csrf()\.disable' . | sed 's|^\./||' | awk -F/ '{print $1}' | sort -u | wc -l

# SQL injection - value-concat sites (P2-11)
grep -rnE --include='*.java' 'createQuery\(.*\+|createNativeQuery\(.*\+|"(SELECT|INSERT|UPDATE|DELETE)[^"]*"\s*\+' . | grep -iv test | wc -l

# Rate limiting (P2-07) - expect rising from 0
grep -rln --include='*.java' -iE 'bucket4j|Resilience4j|RateLimiter' . | grep -iv test | wc -l

# Security headers (P0-12, P2-08) - expect rising from 0
grep -rn --include='*.java' --include='*.properties' --include='*.yml' 'Content-Security-Policy\|X-Frame-Options\|Strict-Transport' . | wc -l

# Session timeouts (P0-06) and cookie usage (P2-13)
grep -rn --include='*.xml' 'session-timeout' .
grep -rn --include='*.java' 'HttpSession\|getSession()' . | wc -l

# Exceptions (P2-12)
grep -rn --include='*.java' 'catch\s*(\s*Exception\b' . | wc -l
grep -rnE --include='*.java' 'printStackTrace\s*\(\s*\)' . | wc -l

# SSRF clients (P2-06)
grep -rn --include='*.java' 'RestTemplate\|WebClient\|HttpURLConnection\|OkHttpClient' . | wc -l

# 508 (P3-03..05) and frontend (P3-01/02)
grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<img ' . | grep -v 'alt=' | wc -l
grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' 'onclick=' . | wc -l
find . \( -name '*.jsp' -o -name '*.xhtml' \) | wc -l

# JBoss base image (P1-09) and deprecated images (P1-13)
grep -rln --include='Dockerfile*' 'eeoc-jboss74\|jboss-eap' . | wc -l
grep -rhnE --include='Dockerfile*' '^FROM\s' . | grep -iE 'buster|:latest|^FROM\s+nginx\s*$|openjdk:11' | wc -l

# javax vs jakarta (P1-08)
grep -rn --include='*.java' '^import javax\.' . | wc -l
grep -rn --include='*.java' '^import jakarta\.' . | wc -l

# API contract (P1-11) - OpenAPI specs appearing
grep -rln --include='*.java' --include='pom.xml' --include='build.gradle' -iE 'springdoc|swagger-jaxrs2|OpenAPIDefinition' . | wc -l

# CI / hygiene baseline (P4-01/04/05)
{ find . -path '*/.github/workflows/*' -o -name 'azure-pipelines*.yml'; } 2>/dev/null | sed 's|^\./||' | awk -F/ '{print $1}' | sort -u | wc -l
find . -name '.pre-commit-config.yaml' | wc -l
```

### 1.3 PII-log nuance (do not regress the correction)

The PII-log count is mostly false positives. The base claim was corrected: there
are **no SSN or phone values in logs**; the real item is email addresses logged
in cleartext. When reporting, keep that distinction. Re-running
`grep ... 'log\.(info|debug|warn|error).*\b(email|ssn|phone|name)\b'` gives a raw
candidate count, not a defect count.

---

## 2. Baseline (2026-06-10 / 2026-06-12) - the "before" to measure against

| Metric | Baseline | Card | Target (done-when) |
|---|---|---|---|
| Repos / files / manifests | 48 / ~30,129 / 66 | P4-06 | fewer repos |
| Secrets (gitleaks) | 332 | P0-01..10 | 0 |
| Grype total (C/H/M/L) | 752 (43/335/336/38) | P1-01..07 | 0 C/H |
| Trivy total | 398 (17/181/179/21) | P1-01..07 | 0 C/H |
| Broken crypto sites | 30 (15 deduped) | P1-12 | 0 |
| ObjectInputStream / XStream | 13 / 14 | P0-15,P1-02,P2-04 | 0 untrusted |
| XML parsers / hardened | 42 / 0 | P0-14,P2-03 | hardened == parsers |
| Method-auth annotations / endpoints | 259 / 1,177 | P2-01 | every endpoint ruled |
| permitAll | 46 | P2-02 | scoped + justified |
| CORS wildcard services | 5 | P0-05 | 0 |
| CSRF-disabled services | 8 | P0-11,P2-09 | justified only |
| SQL value-concat sites | ~286 | P2-11 | 0 |
| Rate limiting libs | 0 | P2-07 | present on sensitive endpoints |
| Security-header refs | 0 | P0-12,P2-08 | all 19 services |
| Session timeouts (min) | ImsNXG 300, RespondentPortal 300, FedSep 180 | P0-06 | 30 |
| HttpSession usages | 176 | P2-13 | secure cookie flags set |
| Broad catch / printStackTrace | 1,546 / 590 | P2-12 | 0 printStackTrace |
| SSRF clients | 806 | P2-06 | allowlisted |
| 508: img-no-alt / onclick / JSP files | 104 / 863 / 407 | P3-01..05 | 0 / 0 / 0 |
| JSF usages | 2,296 | P1-09,P3-01 | 0 |
| Angular apps / versions | 3 (16,16,19) | P3-02 | one current major |
| JBoss base-image services | 6 | P1-09 | 0 |
| Deprecated/untagged images | present (buster, nginx, openjdk:11, alfresco 6.2.2) | P1-13,P4-09 | 0 |
| javax / jakarta imports | 9,436 / 1,770 | P1-08 | jakarta dominant |
| CI repos / pre-commit / SBOM / dependabot | 33 / 11 / 6 / 13 (of 48) | P4-01/02/04/05 | all 48 |
| Test coverage (core / support) | ~5% / ~3% | P4-08 | 60% / 50% |

The PII-log baseline: email 456, name 113, **ssn 0, phone 0** (candidate counts;
email is the real one, in cleartext).

---

## 3. Progression log (append one row block per re-audit)

Copy this block, date it, fill the deltas. Trend toward the targets above.

```
### Re-audit YYYY-MM-DD
- Secrets: ___ (was 332)        Grype C/H: ___/___ (was 43/335)
- Broken crypto: ___ (was 30)   SQL concat: ___ (was 286)
- XXE hardened/parsers: ___/___ (was 0/42)
- AuthZ annotations: ___/endpoints ___ (was 259/1177)
- CORS wildcards: ___ (was 5)   CSRF-disabled: ___ (was 8)
- Rate-limit libs: ___ (was 0)  Security-header refs: ___ (was 0)
- Sessions >30min: ___ (was 3)  printStackTrace: ___ (was 590)
- JSP files: ___ (was 407)      JBoss images: ___ (was 6)
- jakarta/javax: ___/___ (was 1770/9436)
- CI repos: ___ /48 (was 33)    Test coverage core/support: ___/___ (was 5/3)
- Notes: <what landed since last cycle; which cards are closing; surprises>
```

No re-audits recorded yet. First one is due after the team reports the next batch
of Phase 0 / Phase 1 updates.

---

## 4. Operational notes for the re-audit (things that bite)

- **Scans are ephemeral.** `/tmp/*.json` does not survive; always regenerate
  (Section 1.1) before trusting a number.
- **Working directory persists between bash calls but `cd` into a subdir sticks.**
  Use absolute paths or re-`cd` each batch.
- **The branch flips mid-session and direct push to `main` is blocked.** Do
  re-audit findings as a doc + PR: branch off `origin/main`
  (`git checkout -B feature/<name> origin/main`), commit, push, open PR. After a
  push, mergeability can read "not mergeable" for a few seconds while GitHub
  computes it; re-check `gh pr view <n> --json mergeable` and retry.
- **Gemini must review before merge** (platform rule). Open the PR, let the bots
  comment, address findings, then merge. `git reset --hard` is blocked by a hook;
  use `git checkout -B main origin/main` to resync local main after a merge.
- **Regenerate the consolidated from sources** after editing any per-phase file:
  the consolidated is built, not hand-edited. The build approach (front matter +
  per-phase body extraction, strip `^>` footnotes, demote `^## ` to `### `) is in
  the git history of `ARC_Developer_Remediation_Runbook_v2_Phases1-4.md`.
- **Writing rules:** no em dashes, no banned AI terms, no internal tooling-path or
  skill references (clean-export pipeline). Never name a specific consuming
  application (for example say "downstream platform services," not the app name).
  Run the hygiene sweep before commit.
- **CORS needs two grep styles** (annotation `@CrossOrigin` and config
  `setAllowedOrigins(List.of("*"))`); a single combined pattern under-counts (it
  missed FederalHearings in the first base report).
- **Counts are surface counts.** SQL, PII-log, and SSRF numbers include false
  positives; they are review queues, not defect counts. Say so when reporting.

---

## 5. What to report each cycle

1. The filled progression-log block (Section 3).
2. A one-paragraph read: which cards are visibly closing, which are stalled, any
   regression (a count that went up).
3. If a finding is fully closed, note the card can be marked done.
4. If a new finding type appears (new dependency, new endpoint pattern), flag it
   and check whether an existing card covers it or a new one is needed.
5. Offer to update the traceability matrix and the progression log in a PR.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-12 | Derek Gordon / OCIO | Initial re-audit playbook; baseline captured |

Source command set: `ARC_Audit_Commands_Reference.md`. Baseline source:
`ARC_Audit_Command_Findings_2026-06-10.md` and the 2026-06-12 coverage audit.
