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
   license scan, SBOM generation, container scan (Trivy), IaC misconfiguration
   scan (checkov or `trivy config`) for deployment manifests, and DAST baseline
   (ZAP) for deployable services.
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

### P4-07 - Govern the integration surface: MCP exposure, contract tests, end-to-end tracing

| | |
|---|---|
| **Severity** | MEDIUM (modernization enabler; prevents integration debt) |
| **Source** | platform integration and MCP architecture |

**Why:** by this point ARC has a published contract (P1-11) and an enforced,
authenticated boundary (P2-10). This card makes the integration durable: expose
ARC capabilities through the MCP aggregator as a governed spoke, keep the
contract and the consumers from drifting, and trace a request end to end. Doing
it on top of the clean contract and boundary, rather than letting each future
consumer wire its own path into ARC, is the modernization payoff: one governed,
audited surface that future AI-assisted or cross-system case workflows plug into,
instead of bespoke direct access bolted on per feature with its own auth and no
audit trail.

**Steps**
1. **Expose ARC through the MCP-governed surface as a spoke fronted by the
   integration gateway.** Generate the MCP tool schemas from the OpenAPI specs
   (P1-11) so the tool surface and the API contract stay one definition. The
   aggregator authenticates spokes with a machine-to-machine identity and stores
   spoke registration centrally; register the gateway-fronted ARC capabilities
   the same way.
2. **Honor the default-off integration posture.** `MCP_ENABLED` and
   `MCP_PROTOCOL_ENABLED` default to false; every service must start and pass its
   health check with all integrations disabled. Confirm ARC exposure inherits
   this default and is opt-in per environment.
3. **Audit any AI-mediated capability.** A capability exposed through MCP that
   drives an AI generation requires the platform AI audit record (HMAC-signed,
   7-year WORM retention). Wire the audit on the exposure, not as an afterthought.
4. **Consumer-driven contract tests in CI.** Add contract tests between the
   gateway and each ARC service so a contract change that would break the gateway
   fails the build, not production.
5. **End-to-end observability.** Confirm `X-Request-ID` (P2-10) traces a request
   across ARC, the gateway, and the MCP surface, with structured logs at each hop.

**Done when**
- [ ] ARC capabilities are reachable only through the gateway-fronted MCP spoke,
      not by direct consumer access.
- [ ] MCP exposure defaults off and the service is healthy with it disabled.
- [ ] AI-mediated capabilities emit the HMAC-signed, WORM-retained audit record.
- [ ] Consumer-driven contract tests gate the gateway/ARC boundary in CI.
- [ ] A single request is traceable end to end by `X-Request-ID`.

**Verify**
```bash
# default-off posture: MCP flags default false and the service is healthy with them off
grep -rn 'MCP_ENABLED\|MCP_PROTOCOL_ENABLED' <service>/  # defaults resolve to false
MCP_ENABLED=false MCP_PROTOCOL_ENABLED=false <run health check>   # expect: healthy
# contract tests present in CI for the gateway/ARC boundary
grep -rln 'contract' <gateway-repo>/tests/ <ci-config>
```

---

### P4-08 - Raise test coverage

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | base report 6.4; audit 4.3 |

**Why:** test coverage is near zero (the audit measured roughly 5% on core
business services and 3% on support services). Every other phase changes code,
and without tests the changes ship unverified and regress silently.

**Steps**
1. Set coverage targets per tier: 60% line coverage on core business services,
   50% on support services.
2. Backfill tests on the highest-risk paths first: the auth boundary (P2-01,
   P2-10), the upload/parse paths (P0-14), and the crypto and SQL changes
   (P1-12, P2-11).
3. Add a coverage gate to CI (P4-01) that ratchets: coverage may not drop below
   the current number on any change.

**Done when**
- [ ] Core services at 60%, support services at 50% line coverage.
- [ ] CI enforces a non-decreasing coverage ratchet.

**Verify**
```bash
# coverage report meets the tier target (tool varies: jacoco for Java, pytest-cov for Python)
<run coverage> && echo "core >= 60% / support >= 50%"
```

### P4-09 - Resolve the Alfresco end-of-life decision

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | audit 4.1 |

**Why:** Alfresco 6.2.2 is end-of-life (it is the content repository behind the
`alfresco-share` and `alfresco-content-repository` images in P1-13). An EOL
content platform accrues unpatched CVEs and blocks the base-image cleanup.

**Steps**
1. Make the decision explicitly: upgrade to a supported Alfresco line, migrate
   the content to the platform's content store, or retire if the capability is
   no longer needed.
2. Whichever path, record it and sequence the P1-13 Alfresco base-image work
   behind it.

**Done when**
- [ ] A recorded Alfresco decision (upgrade / migrate / retire) with an owner.
- [ ] The P1-13 Alfresco images are resolved per that decision.

### P4-10 - Repository archival policy

| | |
|---|---|
| **Severity** | LOW (governance) |
| **Source** | audit 4.6 |

**Why:** stale, superseded, and proof-of-concept repos are a reuse risk even when
not deployed. A developer looking for code to copy will find the old patterns,
hardcoded credentials, DES encryption, and `ObjectInputStream` usage, and carry
them into new work. This complements the consolidation in P4-06.

**Steps**
1. Define an archival policy: repos past an inactivity threshold, or marked
   superseded/PoC, are archived (read-only) or deleted.
2. Add a visible banner or README note on archived repos warning against reuse.
3. Apply the policy as part of the P4-06 consolidation sweep.

**Done when**
- [ ] Archival policy documented and applied; stale/PoC repos archived.

### P4-11 - Extend event-driven integration (Azure Service Bus)

| | |
|---|---|
| **Severity** | MEDIUM (completes the platform integration) |
| **Source** | audit 4.4; `DAES_Component_Integration_Map.md` (existing eventing) |

**Why:** async eventing already partly exists, do not rebuild it. The Integration
API already consumes two ARC Service Bus topics, `db-change-topic` and
`document-activity-topic`, and forwards selected events to the Hub over
HMAC-signed webhooks (`/api/v1/events`), which routes case-lifecycle events to
downstream spokes. What is missing is explicit, schema'd domain events
(case status change, charge update) rather than raw database-change
notifications, so consumers bind to meaningful events instead of inferring them
from CDC rows. Extend the existing topics; keep the established forward-to-Hub
path.

**Steps**
1. Inventory the existing eventing (`db-change-topic`, `document-activity-topic`
   in `eeoc-arc-integration-api/app/config`) and the Hub forward path before
   adding anything; do not duplicate it.
2. Define explicit domain events (case status change, charge update) with a
   versioned schema aligned to the OpenAPI contract (P1-11), published onto the
   existing topics or a new domain-event topic as the design dictates.
3. Gate any new publisher behind the default-off integration flag (P2-14) so the
   service is healthy with eventing disabled.
4. Propagate `X-Request-ID` onto the event for end-to-end tracing (P2-10 / P2-15).

**Done when**
- [ ] Explicit domain events published on the existing Service Bus path, schema'd
      and correlation-tagged.
- [ ] No duplication of the existing CDC/forward mechanism.

**Verify**
```bash
# existing topics and any new publisher are present and flag-gated
grep -rnE 'db-change-topic|document-activity-topic|ServiceBus|service[._]bus|EVENT.*ENABLED' <service>/
```

### P4-12 - DAST and pre-ATO penetration test validation

| | |
|---|---|
| **Severity** | HIGH (ATO gate; confirms exploitability) |
| **Source** | Phase 1-4 verification audit (2026-06-13); platform pre-pen-test requirements |

**Why:** every finding to date is static. The XXE path is traced but "not proven
exploited," the authorization gaps are counted but not exercised, and roughly
half the card Verify commands are runtime checks (curl, health, coverage) that
were never executed because there was no running target. A DAST baseline and a
scoped penetration test against a staging instance move the high-impact findings
from reachable to confirmed or refuted, prove the remediations hold at runtime,
and run the verify commands static review cannot.

**Steps**
1. Stand up a staging instance with the Phase 0-2 remediations applied. Run an
   OWASP ZAP baseline scan against each deployable service; gate on new high-risk
   alerts.
2. Commission a scoped penetration test on the high-impact classes: XXE on the
   MD-715 upload path, authorization bypass on the previously unguarded endpoints
   (P2-01), SSRF to the metadata endpoint (P2-06), and session and CSRF handling.
3. Execute the runtime card Verify commands against staging (P1-11, P2-10, P2-13,
   P2-15, P4-07, P4-08) and record pass/fail.
4. Clear the pre-pen-test configuration-hygiene items first so the paid test
   spends its budget on real issues; feed confirmed exploitable findings back as
   targeted fixes.

**Done when**
- [ ] ZAP baseline runs against every deployable service and gates on high-risk.
- [ ] A scoped penetration test has confirmed or refuted the high-impact static
      findings.
- [ ] The runtime Verify commands have been executed against staging.

### P4-13 - Remediate infrastructure-as-code misconfiguration

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | IaC misconfiguration scan (2026-06-13) |

**Why:** the dependency and code scans never covered the deployment
configuration. A checkov scan of the Helm, Ansible, and production manifests
returned 764 failed checks (azure-extmgmt Helm 168, Ansible 10, prod 562,
Alfresco Helm 24). The recurring failures are missing CPU/memory requests and
limits, no container security context, root containers admitted, no seccomp
profile, images referenced by tag rather than digest, and use of the default
namespace. Each is a hardening gap in how the services run, independent of the
code inside them.

**Steps**
1. Add an IaC misconfiguration scanner (checkov or `trivy config`) to the
   standard CI gate (P4-01), covering Kubernetes/Helm, Ansible, and any Terraform.
2. Remediate the recurring classes: set resource requests and limits, apply a
   restrictive `securityContext` (run as non-root, drop capabilities, seccomp),
   pin images by digest, and move workloads off the default namespace.
3. Gate the pipeline on CRITICAL/HIGH IaC findings; track the rest into the P4-03
   backlog.

**Done when**
- [ ] IaC scanning runs in CI and gates on CRITICAL/HIGH.
- [ ] Resource limits, security contexts, non-root, and digest-pinned images set
      across the deployment manifests.

**Verify**
```bash
checkov -d <iac-dir> --compact --quiet   # failed-check count trends down from the 764 baseline
```

---

## Phase 4 exit gate

- [ ] Standard security gate runs in every repo, blocking on CRITICAL/HIGH (P4-01).
- [ ] Every deployable service emits an SBOM per build (P4-02).
- [ ] Scheduled full-severity monitoring; MEDIUM/LOW tracked with an SLA (P4-03).
- [ ] Automated dependency updates wired to CI on every active repo (P4-04).
- [ ] Secret `.gitignore` and gitleaks hook on every repo; gitleaks in CI (P4-05).
- [ ] Dormant/duplicate repos retired; nested checkouts removed (P4-06).
- [ ] ARC governed through the gateway-fronted MCP spoke; contract tests and
      end-to-end tracing in place; AI-mediated capabilities audited (P4-07).
- [ ] Test coverage at tier targets; CI coverage ratchet in place (P4-08).
- [ ] Alfresco EOL decision recorded and actioned (P4-09).
- [ ] Repository archival policy documented and applied (P4-10).
- [ ] ARC publishes domain events to Service Bus (flag-gated, schema'd) (P4-11).
- [ ] DAST baseline and a scoped penetration test validate the high-impact
      findings; runtime Verify commands executed against staging (P4-12).
- [ ] IaC misconfiguration scanned in CI and the recurring classes remediated
      across the deployment manifests (P4-13).

---

## Program close

With Phases 0-4 complete, the conditions that produced the audit findings are
addressed: secrets are out of source and blocked from returning, the known-
exploited and full-backlog dependencies are patched and kept current, the access-
control and injection surfaces are systemically closed, the legacy frontend tier
is retired and the remainder meets 508, and continuous monitoring surfaces the
full severity spectrum rather than the top two tiers. A side effect of doing the
modernization properly is that ARC ends up integration-ready: a published
contract (P1-11), an authenticated single-gateway boundary (P2-10), and a
governed MCP surface (P4-07), built in during the uplift rather than bolted on
per consumer later. That is what lets future platform capabilities consume ARC
safely without re-plumbing. The remaining work is steady-state operations
against the gates this phase established.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 4 task cards: CI gate, SBOM, continuous monitoring, dep automation, secret hygiene, consolidation |

Inputs: `ARC_Secondary_Scan_Findings_2026-06-10.md`, base report, Phase 4 recon.
Refresh: `ARC_Phase1to4_Runbook_Notes.md`.
