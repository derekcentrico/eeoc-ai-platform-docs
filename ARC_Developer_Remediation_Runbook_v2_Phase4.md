# ARC Developer Remediation Runbook - v2 Phase 4

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Phase 4 developer task cards: consolidation and continuous security. Extends the
v2 set and replaces the Phase 4 outline in
`ARC_Developer_Remediation_Runbook.md` when v2 is assembled.

**Objective:** make the fixes from Phases 0-3 durable. Standardize the CI
security gate across every repo, generate SBOMs, stand up continuous monitoring
that never hides findings again, automate dependency updates so the backlog does
not re-accumulate, and reduce the 48-repo fragmentation that multiplied every
finding.

**Timeline:** months 10-18, running alongside the tail of Phases 1-3 and
continuing as steady-state operations.

> **Footnote on targets.** Baseline counts are from a Phase 4 recon on
> 2026-06-10. Tool versions named here are the latest stable at that date and go
> stale; verify before adoption. Regeneration commands are in
> `ARC_Phase1to4_Runbook_Notes.md`.

---

### P4-01 - Standardize the CI security gate across all repos

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | Phase 4 recon; platform agency-repo CI checklist |

**Why:** CI coverage is partial and inconsistent. The recon found CI workflows in
**33 of 48 repos**, so 15 have none, and the ones that exist do not run a uniform
security gate. Without a standard gate, a fixed finding reappears on the next
change.

**Steps**
1. Adopt one standard gate definition for all repos, matching the platform's
   established suite: secret scan (gitleaks), SAST (Bandit/Semgrep for Python,
   the Java equivalent for JVM repos), SCA (pip-audit / OSV-Scanner / Grype),
   license scan, SBOM generation, container scan (Trivy), and DAST baseline (ZAP)
   for deployable services.
2. Roll it to the 15 repos with no CI first, then normalize the 33 that have
   inconsistent pipelines.
3. Gate the build on CRITICAL/HIGH for SCA, SAST, and container scans; record
   MEDIUM/LOW as a tracked backlog (P4-03).

**Done when**
- [ ] Every repo runs the standard security gate.
- [ ] The gate blocks on CRITICAL/HIGH and reports the full severity spectrum.

**Verify**
```bash
# every repo has the gate workflow
for d in */; do test -e "$d/.github/workflows/security.yml" && echo "OK $d" || echo "MISSING $d"; done
```

### P4-02 - Generate an SBOM per deployable service

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | Phase 4 recon; EO 14028 SBOM requirement |

**Why:** only 6 files across the estate reference SBOM tooling. EO 14028 requires
a software bill of materials per deliverable. An SBOM is also what lets a future
CVE be matched to affected services in minutes instead of a full re-scan.

**Steps**
1. Add CycloneDX (build-plugin for Maven/Gradle/npm) and a Syft step in CI for
   every deployable service.
2. Publish the SBOM as a build artifact and store it with the release.
3. Use the SBOM as the authority for the Phase 1 P1-07 check that no shipped
   service bundles a vulnerable Python dependency.

**Done when**
- [ ] Every deployable service emits a CycloneDX SBOM per build.
- [ ] SBOMs are retained with releases.

### P4-03 - Continuous monitoring that surfaces the full severity spectrum

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | `ARC_Secondary_Scan_Findings_2026-06-10.md` |

**Why:** the lesson from the secondary scan. The base report ran CRITICAL/HIGH
only and hid ~200 MEDIUM/LOW findings. The standing monitoring must never do
that again: gate on the top tiers, but always surface and track the rest.

**Steps**
1. Schedule a recurring full-severity Grype/Trivy scan per repo (not just at
   build).
2. Gate on CRITICAL/HIGH; route MEDIUM/LOW to a tracked, burning-down backlog
   with an SLA, not to `/dev/null`.
3. Wire new-CVE alerts (a CVE published against an in-use package version) to the
   owning team via the SBOM mapping from P4-02.

**Done when**
- [ ] Scheduled full-severity scans run per repo.
- [ ] MEDIUM/LOW findings are tracked with an SLA, not filtered out.
- [ ] New-CVE alerts route to service owners.

**Verify**
```bash
# monitoring config asserts full severity, not CRITICAL/HIGH-only
grep -rn 'severity' <monitoring-config>   # includes MEDIUM and LOW
```

### P4-04 - Automate dependency updates

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | Phase 4 recon |

**Why:** only 13 of 48 repos have Dependabot or Renovate. The Phase 1 backlog
exists because dependencies were never updated. Automation prevents it from
rebuilding.

**Steps**
1. Add Dependabot or Renovate to the 35 repos without it, configured for
   security updates plus grouped minor/patch updates.
2. Route the auto-PRs through the standard CI gate (P4-01) so an update that
   breaks a build is caught before merge.

**Done when**
- [ ] Every active repo has automated dependency updates wired to CI.

**Verify**
```bash
for d in */; do test -e "$d/.github/dependabot.yml" -o -e "$d/renovate.json" && echo "OK $d" || echo "MISSING $d"; done
```

### P4-05 - Standardize secret hygiene across all repos

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | Phase 0 P0-07, P0-08; Phase 4 recon |

**Why:** Phase 0 added `.gitignore` rules and pre-commit hooks to the active
repos as an emergency. The recon found only 11 pre-commit configs across 48
repos. This card makes the secret-blocking standard universal and permanent, so
the 332-secret finding cannot recur.

**Steps**
1. Bring the P0-07 `.gitignore` secret rules and the P0-08 gitleaks pre-commit
   hook to every repo that still lacks them (37 repos).
2. Add the gitleaks gate to the standard CI suite (P4-01) as a second line behind
   the pre-commit hook.
3. Confirm the Key Vault reference pattern (P0-09) is the only secret-delivery
   mechanism; no repo reintroduces a `*-secrets.yaml`.

**Done when**
- [ ] Every repo has the secret `.gitignore` rules and the gitleaks pre-commit
      hook.
- [ ] gitleaks runs in CI for every repo.

**Verify**
```bash
for d in */; do test -e "$d/.pre-commit-config.yaml" && echo "OK $d" || echo "MISSING $d"; done
```

### P4-06 - Reduce repository fragmentation

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | base report 1.1 |

**Why:** 48 repositories holding ~30,000 files is the fragmentation that
multiplied every finding: no single owner sees the whole surface, and a control
fixed in one service is absent in the next. Consolidation reduces the per-repo
drift.

**Steps**
1. Use the audit's repository tiering (active / recently active / maintenance /
   stale / dormant) to identify consolidation candidates. Dormant and duplicate
   repos are archived or merged.
2. Consolidate the duplicated nested checkouts (several repos contain a nested
   copy of themselves, which doubled scan counts) into a single source of truth.
3. Group services that share a deployment and ownership where a monorepo or a
   shared-pipeline arrangement reduces drift, without forcing unrelated services
   together.

**Done when**
- [ ] Dormant and duplicate repos archived or merged.
- [ ] Nested duplicate checkouts removed.
- [ ] Active repo count reflects the real service inventory.

**Verify**
```bash
ls -d */ | wc -l   # trends down from 48 as dormant/duplicate repos are retired
```

---

## Phase 4 exit gate

- [ ] Standard security gate runs in every repo, blocking on CRITICAL/HIGH (P4-01).
- [ ] Every deployable service emits an SBOM per build (P4-02).
- [ ] Scheduled full-severity monitoring; MEDIUM/LOW tracked with an SLA (P4-03).
- [ ] Automated dependency updates wired to CI on every active repo (P4-04).
- [ ] Secret `.gitignore` and gitleaks hook on every repo; gitleaks in CI (P4-05).
- [ ] Dormant/duplicate repos retired; nested checkouts removed (P4-06).

---

## Program close

With Phases 0-4 complete, the conditions that produced the audit findings are
addressed: secrets are out of source and blocked from returning, the known-
exploited and full-backlog dependencies are patched and kept current, the access-
control and injection surfaces are systemically closed, the legacy frontend tier
is retired and the remainder meets 508, and continuous monitoring surfaces the
full severity spectrum rather than the top two tiers. The remaining work is
steady-state operations against the gates this phase established.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 4 task cards: CI gate, SBOM, continuous monitoring, dep automation, secret hygiene, consolidation |

Inputs: `ARC_Secondary_Scan_Findings_2026-06-10.md`, base report, Phase 4 recon.
Refresh: `ARC_Phase1to4_Runbook_Notes.md`.
