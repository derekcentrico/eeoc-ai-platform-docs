# ARC Coverage Traceability Matrix

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Traceability from every finding and phased-plan task in
`ARC_Modernization_Audit_and_Phased_Plan.md`, plus
`ARC_Secondary_Scan_Findings_2026-06-10.md`, to its developer task card in the v2
runbooks (`ARC_Developer_Remediation_Runbook_v2_Phase0.md` and the Phase 1-4
set). Built from a multi-loop coverage audit on 2026-06-12: every audit item was
mapped to a card, gaps were identified, and twelve cards were added to close them.
Card steps were spot-checked against the `eeoc-arc-payloads/` source for accuracy.

**Result: full coverage.** Every actionable finding and phased-plan task maps to
at least one card. Items marked "context" are descriptive sections (inventory,
dating, diagrams) with no remediation task.

---

## 1. Security findings (audit Sections 3-4)

| Audit ref | Finding | Covering card(s) |
|---|---|---|
| 3.1 | Secrets in source control (332) | P0-01..P0-04, P0-09, P0-10, P0-17; P4-05 |
| 3.2 | Known dependency vulnerabilities (Grype/Trivy) | P0-15; P1-01, P1-04, P1-05; P4-03 |
| 4.1 | Broken cryptography (PBEWithMD5AndDES) | **P1-12** |
| 4.2 | Java deserialization (RCE surface) | P0-15; P1-02; P2-04 |
| 4.3 | XML External Entity (XXE) | P0-14; P2-03 |
| 4.4 | Authentication gaps | P2-01, P2-02, P2-10 |
| 4.5 | CORS wildcard (5 services) | P0-05 |
| 4.6 | CSRF disabled | P0-11; P2-09 |
| 4.7 | Input validation absent | P2-05 |
| 4.8 | No rate limiting | P2-07 |
| 4.9 | SQL injection patterns | **P2-11** |
| 4.10 | Security headers missing | P0-12; P2-08 |
| 4.11 | 5-hour session timeout | P0-06 |
| 4.12 | HTTP client / SSRF surface (806) | P2-06 |
| 4.13 | HttpSession without secure config (176) | **P2-13** |
| 4.14 | Broad exception catches (1,546) / printStackTrace (590) | **P2-12** |
| 4.15 | Command injection / path traversal (base report 6.11; SAST-confirmed) | **P2-16** |

## 2. Section 508 and architecture (audit Sections 5-6)

| Audit ref | Finding | Covering card(s) |
|---|---|---|
| 5.1 | 508 automated findings | P3-03, P3-04, P3-05 |
| 5.2 | Legacy JSP frontends (not remediable in place) | P3-01 |
| 5.3 | Angular frontend alignment | P3-02 |
| 6.1 | Current-state diagram | context |
| 6.2 | Key structural problems | P1-09, P1-11, P4-06 |
| 6.3 | Enterprise platform integration readiness (OpenAPI, RFC 7807, X-Request-ID, health, structured logging) | **P1-11, P2-10, P2-15, P4-07** |
| 6.4 | Test coverage (~5% core, ~3% support) | **P4-08** |

## 3. Federal compliance gaps (audit Section 7)

| Audit ref | Gap | Covering card(s) |
|---|---|---|
| 7.1 | EO 14028 (supply chain, SBOM) | P4-02; P0 secrets; P2 hardening |
| 7.2 | OMB M-22-09 (Zero Trust) | P2-01, P2-10 |
| 7.3 | FISMA continuous monitoring | P4-03 |
| 7.4 | Section 508 | P3-03, P3-04, P3-05, P3-06 |
| 7.5 | NIST 800-53 Rev5 control gaps | distributed (P0-P4): IA-5 P0-01..04/P1-12, SC-13/SC-28 P1-12, AC-12 P0-06, SC-8 P2-08/P2-13, AC-3 P2-01 |

## 4. Phased-plan tasks (audit Section: phased plan)

| Audit task | Description | Covering card(s) |
|---|---|---|
| 0.1 | Credential rotation | P0-01..P0-04 |
| 0.2 | Remove secrets files | P0-09 |
| 0.3 | Git history scrub | P0-10 |
| 0.4 | Fix CORS wildcards | P0-05 |
| 0.5 | Re-enable CSRF | P0-11 |
| 0.6 | Add security headers | P0-12 |
| 0.7 | Reduce session timeouts | P0-06 |
| 0.8 | PII log redaction | P0-13 |
| 0.9 | Gitignore rules | P0-07 |
| 0.10 | Pre-commit hooks | P0-08 |
| 1.1 | JBoss EAP 7.4 retirement | P1-09 |
| 1.2 | Spring Boot 2.x migration | P1-01, P1-08 |
| 1.3 | Deprecated Docker image replacement | **P1-13** (+P1-09) |
| 1.4 | Broken cryptography replacement | **P1-12** |
| 1.5 | Local CI and config management | P4-01 (+P0-09 Key Vault) |
| 1.6 | New service language standard | **P1-14** |
| 2.1 | API gateway deployment | P2-10, P1-11 (gateway exists in `eeoc-arc-integration-api`) |
| 2.2 | Authentication/authorization overhaul | P2-01, P2-02, P2-10 |
| 2.3 | XXE remediation | P2-03 |
| 2.4 | SQL injection remediation | **P2-11** |
| 2.5 | Input validation | P2-05 |
| 2.6 | Supply chain security (EO 14028) | P4-02 |
| 2.7 | OpenAPI and RFC 7807 | P1-11, P2-10 |
| 2.8 | Feature flags and audit logging | **P2-14** |
| 3.1 | Complete NG migrations | P3-01 |
| 3.2 | Angular 19 alignment | P3-02 |
| 3.3 | USWDS adoption | **P3-06** |
| 3.4 | 508 remediation checklist | P3-03, P3-04 |
| 3.5 | Cross-app navigation | **P3-07** |
| 3.6 | 508 enforcement in CI | P3-05 |
| 4.1 | Alfresco decision | **P4-09** |
| 4.2 | Infrastructure modernization | P4-06 (+P1-13) |
| 4.3 | Test coverage | **P4-08** |
| 4.4 | Enterprise platform integration (structured endpoints, health aggregation, event-driven) | P4-07, P2-15, **P4-11** |
| 4.5 | Repository consolidation | P4-06 |
| 4.6 | Repository archival policy | **P4-10** |
| 4.7 | Mandatory security tooling standard | P4-01 |
| 4.8 | Continuous compliance (steady state) | P4-03, P4-08 |

## 5. Secondary scan (MEDIUM/LOW dependency tier)

| Source | Finding | Covering card(s) |
|---|---|---|
| Secondary scan | ~200 MEDIUM/LOW dependency findings | P1-01..P1-07 (cleared by the same cluster bumps as CRITICAL/HIGH); residual tracked in P4-03 |
| Secondary scan | Phase 1-4 sequencing inputs | folded into P1-01..07, P3-02, P4-03 |

## 6. Gaps closed in this pass (2026-06-12)

The coverage audit found the bulk already covered and twelve items missing.
All twelve were added:

| Gap (audit ref) | New card | Severity |
|---|---|---|
| Broken crypto (4.1 / 1.4) | P1-12 | CRITICAL |
| SQL injection (4.9 / 2.4) | P2-11 | HIGH |
| Exception/printStackTrace cleanup (4.14) | P2-12 | MEDIUM |
| HttpSession secure config (4.13) | P2-13 | MEDIUM |
| Deprecated base images beyond JBoss (1.3) | P1-13 | HIGH |
| Test coverage (6.4 / 4.3) | P4-08 | MEDIUM |
| USWDS adoption (3.3) | P3-06 | MEDIUM |
| Cross-app navigation (3.5) | P3-07 | LOW |
| Alfresco decision (4.1 plan) | P4-09 | MEDIUM |
| Repo archival policy (4.6) | P4-10 | LOW |
| New-service language standard (1.6) | P1-14 | LOW |
| Feature flags and audit logging (2.8) | P2-14 | MEDIUM |

## 6b. Additional-audit cards (2026-06-13)

A follow-on pass ran the validation layers the original grep + SCA + secrets
method could not: SAST, IaC misconfiguration, and review-queue triage. It
surfaced one uncarded class (command injection / path traversal) and added five
cards. Detail in `ARC_Phase1to4_VulnToCard_Audit_2026-06-13.md` Sections 5-7.

| Driver | New card | Severity |
|---|---|---|
| Remediation efficacy (pilot then scale) | P1-15 | MEDIUM |
| Command injection / path traversal (uncarded; SAST-confirmed) | P2-16 | HIGH |
| SAST taint-flow analysis + review-queue triage | P2-17 | HIGH |
| DAST + pre-ATO penetration test validation | P4-12 | HIGH |
| IaC misconfiguration remediation | P4-13 | HIGH |

P2-01 was also strengthened with an explicit authorization-matrix deliverable,
and P4-01 now lists IaC misconfiguration scanning in the standard CI gate.

## 7. Accuracy verification (against `eeoc-arc-payloads/`)

Card steps were spot-checked against the current source:

- P1-12 crypto: `PBEWithMD5AndDES` confirmed at `RespondentPortal/.../DesEncrypter.java:41`; the Verify pattern returns 30 occurrences (15 after removing nested-checkout duplicates) across five files in RespondentPortal and FedSep.
- P2-11 SQL: ~286 value-concatenating query sites confirmed, heaviest in ImsNXG (e.g. `DocumentManager.java:146`).
- P2-12 exceptions: 1,546 broad catches and 590 `printStackTrace()` confirmed.
- P2-13 sessions: 176 `HttpSession` usages confirmed.
- P1-13 images: `debian:buster-slim`, untagged `nginx`, `openjdk:11-jre-slim`, Alfresco 6.2.2 confirmed in Dockerfiles.
- P0-06 / P2-07 (existing cards re-checked): RespondentPortal still 300-minute timeout; zero rate-limiting libraries present.
- P0-16 dev controller: the single P0-16 fix is generalized into P2-01 (inventory and remove or profile-gate dev/test/debug controllers across all services), so no Phase 0 emergency item is left without a Phase 1-4 completion. See `ARC_Phase1to4_VulnToCard_Audit_2026-06-13.md` Section 5.

## 8. Package-level severity completeness (re-confirmed 2026-06-12)

Beyond finding-level mapping, every distinct vulnerable package from the Grype
and Trivy scans was cross-checked by severity against the Phase 1 cards:

- **CRITICAL: 0 unnamed.** Every critical-severity package is named in a card.
- **HIGH: all named after this pass.** `@angular/*` is covered by the wildcard
  row (P1-06) and P3-02; `easy-rules-mvel` and `wss4j` were unnamed and are now
  added to P1-03.
- **MEDIUM: all named after this pass.** `jakarta.mail`/`com.sun.mail`,
  `opentelemetry-api`, `resteasy-multipart-provider`, `openapi-generator`, and
  `primefaces` (retire-with-JSF) were unnamed and are now added to P1-03;
  `@protobufjs/utf8` is cleared transitively by the `protobufjs` bump (P1-05).

Integration completeness for DAES (audit 6.3 / 4.4) was likewise re-confirmed:
synchronous API (P1-11) + auth/RFC 7807/correlation (P2-10) + MCP (P4-07), plus
the two pieces that were missing and are now added: health + structured logging
(P2-15) and event-driven Service Bus (P4-11).

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-12 | Derek Gordon / OCIO | Initial traceability matrix; multi-loop coverage audit; twelve gap cards added |
| 1.1 | 2026-06-12 | Derek Gordon / OCIO | Package-level severity re-confirmation; +7 dependency rows (P1-03), +P2-15 health/logging, +P4-11 event-driven |

Inputs: `ARC_Modernization_Audit_and_Phased_Plan.md`,
`ARC_Secondary_Scan_Findings_2026-06-10.md`, the v2 runbook set.
