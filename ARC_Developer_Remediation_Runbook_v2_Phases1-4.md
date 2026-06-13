# ARC Developer Remediation Runbook v2 - Phases 1 through 4

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Consolidated developer task cards for Phases 1 through 4 of the ARC remediation
plan, assembled from the per-phase v2 files into one reference. Phase 0
(emergency security hardening) is delivered separately as
`ARC_Developer_Remediation_Runbook_v2_Phase0.md` and is not repeated here.

This document supersedes the Phases 1-4 outline in
`ARC_Developer_Remediation_Runbook.md`. The card content matches the per-phase
v2 files; each phase was drafted with a four-loop verification pass against the
`eeoc-arc-payloads/` source. Coverage against every audit finding and phased-plan
task is tracked in `ARC_Coverage_Traceability_Matrix.md`.

Beyond clearing the security backlog, the plan modernizes ARC into an
integration-ready upstream for the platform: a published API contract (P1-11),
an authenticated single-gateway boundary (P2-10), standardized health and
structured logging (P2-15), a governed MCP surface (P4-07), and extended
event-driven publishing (P4-11). These are built in during the uplift, not
bolted on per consumer later, so future platform capabilities can consume ARC
safely without re-plumbing each service.

> **Footnote on target versions and counts (applies to every phase below).**
> Version targets are the latest stable releases as of 2026-06-10, and finding
> counts are from scans on that date. Dependency releases move and the codebase
> changes; by the time a card is executed these may be stale or carry new
> advisories. Re-run the scans and re-check each target against the upstream
> release page before acting. The refresh procedure and source-data
> regeneration commands are in `ARC_Phase1to4_Runbook_Notes.md`. Treat version
> numbers here as "current latest stable, verify before use," not pinned values.

## Phases at a glance

| Phase | Theme | Timeline | Cards |
|---|---|---|---|
| 1 | Dependency modernization, crypto, JBoss/runtime, base images, API contract, efficacy validation | months 2-6 | P1-01..P1-15 |
| 2 | Security architecture (authz, injection, SQLi, validation, SSRF, rate limiting, headers, sessions, integration boundary, observability, command injection, SAST triage) | months 4-9 | P2-01..P2-17 |
| 3 | Frontend modernization, 508, USWDS, cross-app navigation | months 6-12 | P3-01..P3-07 |
| 4 | Consolidation, continuous security, governed integration, coverage, Alfresco, archival, eventing, DAST/pen-test, IaC | months 10-18 | P4-01..P4-13 |

The ~200 MEDIUM/LOW dependency findings are not a separate backlog: they are
cleared by the same Phase 1 cluster bumps that clear CRITICAL/HIGH (one bump per
package clears all severities for that package), with any residual tracked in
the Phase 4 monitoring backlog (P4-03). Package-level severity completeness
(every CRITICAL/HIGH/MEDIUM package named in a card) is confirmed in the
traceability matrix, Section 8.

---

## Phase 1 - Dependency Modernization, Cryptography, JBoss/Runtime, Base Images, API Contract

**Objective:** clear the dependency-CVE backlog across all severities and remove
the framework conditions that produced it. The base report scanned CRITICAL and
HIGH only; the full-severity backlog (CRITICAL through LOW; Grype counts 752,
Trivy 398 across the two scanners) is in
`ARC_Secondary_Scan_Findings_2026-06-10.md`. Those findings collapse into the
package clusters below, because one bump clears every finding tied to that
package at once. This is the key point for the ~200 MEDIUM/LOW: they are not a
separate backlog. A single bump of a high-fan-out package (logback, xstream,
tika, commons-*) clears its CRITICAL, HIGH, MEDIUM, and LOW findings together, so
the cluster cards P1-01 through P1-07 remediate the full severity spectrum.
Whatever MEDIUM/LOW remains after the clusters land is tracked, not ignored, in
the Phase 4 continuous-monitoring backlog (P4-03).

**Timeline:** months 2-6, following Phase 0. Phase 0 emergency patches (P0-15:
Spring4Shell, Tika, XStream) are the leading edge of this phase; this phase
completes the uplift behind them.


---

### How Phase 1 cards are organized

Cards group packages by remediation type, not one card per package, because
related libraries upgrade together and share breaking-change handling. Each card
states whether a dependency is **direct** (an explicit version in a manifest,
fixed by editing that line) or **transitive** (no version line; pulled by a
parent POM or BOM, fixed by a managed-version override or a parent bump). This
distinction was verified against the 66 build manifests (39 `pom.xml`, 12
`build.gradle`, 15 `package.json`).

Severity and finding counts cite the full-severity Grype scan.

---

### P1-01 - Patch CRITICAL Java libraries

| | |
|---|---|
| **Severity** | CRITICAL |
| **Source** | Secondary scan; base report 4.1, 5.1 |

**Why:** these Java libraries carry CRITICAL CVEs with known exploit paths.
Spring4Shell, Tika, and XStream are emergency-patched in Phase 0 (P0-15); this
card is the full set and confirms the Phase 0 patches stuck.

| Package | Current | Target (latest stable, verify) | Direct/Transitive | Notes |
|---|---|---|---|---|
| logback-core / logback-classic | 1.0.7, 1.1.8, 1.2.9 | 1.5.x | Transitive (via Spring/parent) | 1.5.x needs SLF4J 2.x; aligns with the Spring uplift in P1-01 |
| tika-core / tika-parsers | 1.5, 1.24.1, 1.28.5 | 3.x | Mixed (direct in some poms) | 1.x to 3.x is an API migration, not a bump; parser invocation changes. Ties to P0-14/P0-15 |
| log4j (1.x) | 1.2.16 | reload4j 1.2.25 (drop-in) or log4j2 2.24.x | Transitive | log4j 1.x is end-of-life. reload4j is the API-compatible interim; log4j2 is the real target |
| axis | 1.4 | Migrate off Axis 1 (JAX-WS / CXF) | Transitive (legacy SOAP) | Axis 1.4 is unmaintained since 2006. Retire, do not patch |
| springfox-swagger-ui | 2.9.2 | springdoc-openapi 2.x | Direct | springfox is abandoned; springdoc is the maintained replacement |
| spring-boot-starter-web | 2.2.4.RELEASE | 3.4.x (verify) | Direct | Spring4Shell emergency-patched in P0-15. Full move to 3.x is the javax->jakarta migration (P1-08); within 2.x the last patched line is 2.7.18 (itself EOL) |

**Steps**
1. For direct dependencies, set the target version in the manifest.
2. For transitive dependencies, add a managed-version override
   (`<dependencyManagement>` in Maven, a constraint in Gradle) rather than
   editing a version that is not present, or bump the parent/BOM that pulls them.
3. tika and axis are migrations, not bumps. Scope each as its own work item
   under this card; do not treat them as a version change.
4. After each change, run the module build and its tests, then re-scan.

**Done when**
- [ ] Every CRITICAL Java package is on a patched or replacement version.
- [ ] `grype dir:. --fail-on critical` returns clean for Java artifacts.

**Verify**
```bash
grype dir:. --output json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); \
  print([m['artifact']['name'] for m in d['matches'] \
  if m['vulnerability']['severity']=='Critical' and m['artifact']['type'].startswith('java')])"
# expect: []
```

### P1-02 - Replace unsafe-deserialization libraries

| | |
|---|---|
| **Severity** | HIGH (CRITICAL-adjacent: RCE gadgets) |
| **Source** | base report 6.1; Phase 0 P0-15 |

**Why:** these libraries deserialize untrusted input into objects and are the
Java RCE-gadget surface. This card is the dependency half of the deserialization
work; the code-site triage is P0-15.

| Package | Current | Target (verify) | Direct/Transitive | Notes |
|---|---|---|---|---|
| xstream | 1.4.9 | 1.4.21 | Transitive | 102 findings across all severities (the secondary report's 39 was the MEDIUM/LOW slice), the largest single cluster. After bump, call `XStream.setupDefaultSecurity` with an explicit allowlist wherever it reads external input |
| snakeyaml | 1.18 | 2.3 | Transitive | 2.x changes the default constructor to `SafeConstructor`; code that relied on arbitrary-type loading needs review |
| jettison | 1.2 | 1.5.4 | Transitive | JSON/XML stream parser, DoS and entity issues |
| commons-beanutils | 1.9.4 | 1.11.0 (or commons-beanutils2 2.0.0-M2) | Transitive | CVE-2025-48734: `declaredClass` property-access gadget; 1.11.0 suppresses it by default |

**Steps**
1. Apply the bumps as managed overrides (all four are transitive).
2. For XStream, add the security framework allowlist on every reader that takes
   request or file input. A version bump alone does not close the gadget path.
3. For snakeyaml 2.x, confirm every `new Yaml(...)` load path either uses
   `SafeConstructor` or is fed only trusted input.

**Done when**
- [ ] All four on target versions.
- [ ] XStream readers on untrusted input have an explicit allowlist.
- [ ] snakeyaml load paths reviewed for the SafeConstructor change.

**Verify**
```bash
grype dir:. --output json | grep -E 'xstream|snakeyaml|jettison|commons-beanutils'
# expect: no HIGH/CRITICAL rows
grep -rn 'setupDefaultSecurity\|addPermission' . --include='*.java'   # present at XStream readers
```

### P1-03 - Apache Commons and shared Java utilities

| | |
|---|---|
| **Severity** | HIGH / MEDIUM |
| **Source** | secondary scan |

**Why:** a cluster of widely-shared utility libraries with HIGH/MEDIUM CVEs.
High fan-out: bumping these clears findings across many modules at once.

| Package | Current | Target (verify) | Direct/Transitive | Notes |
|---|---|---|---|---|
| commons-io | 2.4, 2.11.0, 2.13.0 | 2.18.0 | Mixed | |
| commons-fileupload | 1.4, 1.5 | commons-fileupload2 2.0.0 | Direct | API change; ties to the upload paths in P0-14 |
| commons-email | 1.3.3 | 2.0.0 | Direct | |
| commons-lang3 | 3.2.1-3.17.0 | 3.17.0 | Mixed | |
| commons-lang (1.x/2.x) | 2.6 | Migrate to commons-lang3 | Transitive | |
| commons-beanutils | 1.9.4 | 1.11.0 (see P1-02) | Transitive | |
| gson | 2.8.2, 2.8.5 | 2.11.0 | Transitive | |
| guava | 22.0, 31.0.1-jre | 33.4.x | Mixed | |
| httpclient | 4.3.3, 4.5.2 | 4.5.14 or httpclient5 5.x | Transitive | 4.5.14 is the last 4.x; 5.x is the real target |
| jsoup | 1.10.1, 1.14.3 | 1.18.x | Direct | |
| json (org.json) | 20180130-20230618 | 20240303 | Transitive | |
| xalan | 2.7.0 | 2.7.3 or remove (JDK built-in) | Transitive | |
| bcprov-jdk15on / bcpkix-jdk15on | 1.68 | bcprov-jdk18on 1.79 / bcpkix-jdk18on 1.79 | Transitive | artifact id changes from jdk15on to jdk18on |
| jackson-core | 2.16.1 | 2.18.x | Transitive | |
| hibernate-core | 5.4.30.Final | 5.6.15 or 6.x | Direct | 6.x is jakarta; ties to P1-08 |
| postgresql (JDBC) | 42.7.3 | 42.7.4+ | Direct | |
| easy-rules-mvel (org.jeasy) | 4.1.0 | 4.1.x patched or remove | Transitive | HIGH: MVEL expression evaluation is an injection/RCE surface; confirm rules are not built from untrusted input |
| wss4j | 1.5.4 | 3.0.x | Transitive | HIGH: WS-Security; ties to the SOAP path (Axis retirement, P1-01) |
| jakarta.mail / com.sun.mail | 2.0.1 | 2.1.3 (verify) | Transitive | MEDIUM |
| opentelemetry-api | (in tree) | 1.45.x (verify) | Transitive | MEDIUM; observability lib, aligns with P2-15 |
| resteasy-multipart-provider | 3.14.0.Final | patched/jakarta line | Transitive | MEDIUM: multipart parser on the upload path (ties to P0-14) |
| openapi-generator | 4.2.3 | 7.x (verify) | Transitive (build) | MEDIUM; build-time tool |
| primefaces | 7.0 | retire with JSF tier (P3-01) | Transitive | MEDIUM: JSF UI library; retire-not-patch, removed when the JSP/JSF tier is retired |

**Steps**
1. Bump direct dependencies in the manifest; override transitive ones.
2. Note the artifact-id renames: `commons-fileupload` to `commons-fileupload2`,
   `bcprov-jdk15on` to `bcprov-jdk18on`. These are not in-place version edits.
3. `commons-lang` 2.x to `commons-lang3` is a package-path change
   (`org.apache.commons.lang` to `.lang3`); scope per usage.

**Done when**
- [ ] All listed packages on target or replacement versions.
- [ ] Artifact-id renames applied where required.

**Verify**
```bash
grype dir:. --output json | python3 -c "import json,sys; d=json.load(sys.stdin); \
  print(sorted({m['artifact']['name'] for m in d['matches'] \
  if m['artifact']['type'].startswith('java') and m['vulnerability']['severity'] in ('High','Medium')}))"
# expect: shrinks to empty as cards land
```

### P1-04 - Document-parsing stack (Tika and POI)

| | |
|---|---|
| **Severity** | CRITICAL / HIGH |
| **Source** | base report 4.1, Findings Addendum; secondary scan |

**Why:** the parsers that ingest uploaded documents. Old versions process
external entities by default (the XXE amplifier from the Findings Addendum) and
carry their own CVEs. Some modules pin Tika 1.5 and POI 3.10.1, far older than
the Tika and POI 5.3.0 seen elsewhere.

| Package | Current | Target (verify) | Notes |
|---|---|---|---|
| tika-core / tika-parsers | 1.5, 1.24.1, 1.28.5 | 3.x | API migration. `tika-parsers` split into modules in 2.x; `tika-parsers-standard-package` is the 2.x/3.x coordinate. Ties to P0-15 emergency patch |
| poi / poi-ooxml | 3.10.1 (and 5.3.0 elsewhere) | 5.4.x | Bring every module to one POI line. 3.10.1 predates the OOXML XXE hardening |

**Steps**
1. Standardize every module on one Tika line and one POI line. The split
   versions (Tika 1.5 vs 1.28.5, POI 3.10.1 vs 5.3.0) are the root issue.
2. Tika 1.x to 3.x changes the parser invocation API; update call sites
   (`AutoDetectParser`, `Tika.parseToString`) per the 3.x API.
3. Confirm the hardened-parser settings from P0-14 still apply after the bump.

**Done when**
- [ ] One Tika version and one POI version across all modules.
- [ ] Parser call sites updated to the new API and still XXE-hardened.

**Verify**
```bash
# Read the installed-package inventory from the SBOM, not the manifests and not
# Grype matches. POI is declared group/name/version in Gradle and split across
# lines in Maven poms, so an inline manifest extract misses it; and Grype rows
# are vulnerability matches, so a remediated (non-vulnerable) Tika/POI drops out
# of Grype and the convergence check would miss it. Syft lists every installed
# version, vulnerable or not, which is what the one-line-each check needs.
syft dir:. -o json | python3 -c "import json,sys,collections; \
  d=json.load(sys.stdin); v=collections.defaultdict(set); \
  [v[a['name']].add(a['version']) for a in d.get('artifacts',[]) \
   if a['name'] in ('tika-core','tika-parsers','poi','poi-ooxml')]; \
  print({k:sorted(x) for k,x in v.items()})"
# expect: one Tika line and one POI line as modules converge
```

### P1-05 - npm CRITICAL packages

| | |
|---|---|
| **Severity** | CRITICAL |
| **Source** | base report 4.1; secondary scan |

**Why:** CRITICAL CVEs in the Angular/Node frontends and build tooling.

| Package | Current | Target (verify) | Direct/Transitive |
|---|---|---|---|
| protobufjs | 7.5.4 | 7.5.5+ | Transitive |
| fast-xml-parser | 4.4.1, 4.5.0, 4.5.5 | 5.x (or patched 4.5.x) | Transitive |
| jspdf | 4.0.0 | latest 4.x patched | Direct |
| basic-ftp | 5.1.0, 5.2.2 | 5.2.5+ | Transitive |
| simple-git | 3.16.0, 3.32.3 | 3.33.0+ | Transitive |
| pyyaml | 5.3.1 | 6.0.2 | Direct (python, build) |
| springfox-swagger-ui | 2.9.2 | (see P1-01) | Java |

**Steps**
1. `npm audit fix` clears the transitive set where a compatible tree exists.
2. For direct deps (jspdf), bump in `package.json`.
3. fast-xml-parser 5.x is a major; check the parser-options API if pinned
   directly. Where it is transitive (pulled by a tool), update the parent.

**Done when**
- [ ] `npm audit --audit-level=critical` clean in every frontend.

**Verify**
```bash
for d in $(find . -name package.json -not -path '*/node_modules/*' -exec dirname {} \;); do
  (cd "$d" && npm audit --audit-level=critical >/dev/null 2>&1 && echo "OK $d" || echo "FAIL $d")
done
```

### P1-06 - npm framework and frontend libraries

| | |
|---|---|
| **Severity** | HIGH / MEDIUM |
| **Source** | secondary scan |

**Why:** HIGH/MEDIUM CVEs in the frontend frameworks. Several overlap Phase 3
(frontend modernization); bump here, complete the framework uplift in Phase 3.

| Package | Current | Target (verify) | Notes |
|---|---|---|---|
| next | 15.5.14, 15.5.18 | latest 15.x patched | direct |
| axios | 1.13.5, 1.15.0, 1.15.2 | latest 1.x | direct; consolidate to one version |
| @angular/* (core, common, compiler, platform-server) | 16.2.12 and 19.x | align all to 19.x | the FedSep-NG app on 16 lags; Phase 3 owns the full Angular uplift |
| dompurify | 3.2.5, 3.3.2 | latest 3.x | XSS sanitizer; security-relevant, keep current |
| lodash / lodash-es | 4.17.21 | latest | prototype-pollution advisories |
| minimatch, picomatch, brace-expansion, glob, tmp, uuid, follow-redirects, ajv, ip-address, postcss, js-yaml | various | latest | mostly transitive; `npm audit fix` |

**Steps**
1. Bump direct deps (next, axios, angular, dompurify) in `package.json`.
2. `npm audit fix` for the transitive cluster.
3. Hand the Angular 16->19 alignment to Phase 3 if it requires component
   changes; do the security-only bumps here.

**Done when**
- [ ] Direct frontend deps current; `npm audit --audit-level=high` clean or
      tracked into Phase 3.

### P1-07 - Python build and ops tooling

| | |
|---|---|
| **Severity** | HIGH / MEDIUM |
| **Source** | secondary scan |

**Why:** Python CVEs are in build and ops tooling (CI images, ansible), not in
shipped services. Clear them in the pipeline image refresh rather than per
service.

| Package | Current | Target (verify) |
|---|---|---|
| urllib3 | 1.25.9, 1.26.3 | 2.2.x |
| requests | 2.25.1 | 2.32.x |
| certifi | 2020.12.5 | latest |
| jinja2 | 2.11.2 | 3.1.x |
| pyyaml | 5.3.1 | 6.0.2 |
| ansible | 5.5.0 | latest core |
| idna, dnspython, zipp, pyarrow | various | latest |

**Steps**
1. Pin these in the CI/build base image requirements, rebuild the image.
2. Confirm no shipped service bundles them (they should not; verify with the
   per-service SBOM from Phase 4).

**Done when**
- [ ] Pipeline image rebuilt with patched Python deps.
- [ ] No shipped service SBOM lists a vulnerable Python package.

### P1-08 - javax to jakarta namespace migration

| | |
|---|---|
| **Severity** | structural (blocks the framework uplift) |
| **Source** | base report 2.6 |

**Why:** 9,436 `javax.*` imports against 1,770 `jakarta.*`. The estate is
mid-migration and mostly on the legacy namespace, which pins services to
pre-Jakarta-EE-9 framework generations (Spring Boot 2.x, old servlet, old
Hibernate) and their CVEs. Spring Boot 3.x, Hibernate 6.x, and current
RESTEasy/Jersey all require the jakarta namespace. This is the gate that the
major framework bumps in P1-01 and P1-03 depend on.

**Steps**
1. Per service, run the Eclipse Transformer (or `org.eclipse.transformer`) to
   rewrite `javax.*` to `jakarta.*` for the EE namespaces (servlet, persistence,
   validation, ws, annotation, xml.bind).
2. Bump the framework to the jakarta-based major (Spring Boot 3.x, Hibernate
   6.x) in the same change; the namespace move and the framework bump are one
   migration, not two.
3. Do not rewrite `javax.*` packages that stayed in the JDK (for example
   `javax.xml.parsers`, `javax.crypto`, `javax.sql`). Only the EE namespaces
   moved to jakarta.
4. Sequence the migration per service, lowest-risk first; this is the largest
   single workstream in Phase 1.

**Done when**
- [ ] Each migrated service compiles and passes tests on the jakarta namespace.
- [ ] Framework bumped to the jakarta-based major in the same change.

**Verify**
```bash
grep -rn --include='*.java' '^import javax\.\(servlet\|persistence\|validation\|ws\|annotation\)' <service>
# expect: shrinks to 0 per migrated service (JDK javax.* untouched)
```

### P1-09 - Retire JBoss EAP base image

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 2.5, 8.2 |

**Why:** six services run on the `eeoc-jboss74` / JBoss EAP 7.4 base image, the
JSF/JBoss-era stack (base report 8.2: 2,296 JSF API usages). The base image
carries its own OS and middleware CVE backlog and ties these services to the old
namespace.

Affected services (verified): the six on the
`eus1opsacr.azurecr.io/eeoc-jboss74` base image are DocumentGeneratorAdapter,
EEOCWebService, FedSep, ImsNXG, RespondentPortal, and the `jboss-docker` base.

**Steps**
1. For each service, decide rebase vs rewrite. Spring-Boot-portable services
   rebase onto an `eclipse-temurin` JRE image (the pattern the newer services
   already use). JSF/JSP services that cannot move without a frontend rewrite are
   handed to Phase 3.
2. Rebase the portable ones first; track the JSF-bound ones into Phase 3's
   frontend retirement.

**Done when**
- [ ] No deployable service uses the `eeoc-jboss74` base image, or the remaining
      ones are explicitly deferred to Phase 3 with a recorded reason.

**Verify**
```bash
grep -rln --include='Dockerfile*' 'eeoc-jboss74\|jboss-eap' .   # shrinks toward 0
```

### P1-10 - Consolidate Java runtimes onto an LTS

| | |
|---|---|
| **Severity** | MEDIUM (EOL-runtime risk) |
| **Source** | base report 2.1 |

**Why:** runtimes span Java 1.8 to 25. Java 8 and 11 are past or nearing end of
free public security updates; Java 25 is not an LTS. A mixed matrix blocks a
shared base image and a single patch pipeline.

**Steps**
1. Target one current LTS (Java 21) for the estate. Move Java 8 and 11 services
   up first (they carry the EOL risk); bring the Java 22/25 services back to the
   LTS.
2. Pair the JVM move with the framework and namespace work in P1-01 and P1-08;
   they share the same build changes.

**Done when**
- [ ] Every service builds and runs on the chosen LTS.
- [ ] No service ships on Java 8, 11, or a non-LTS feature release.

### P1-11 - Stabilize the service API surface for downstream consumption

| | |
|---|---|
| **Severity** | MEDIUM (modernization enabler; prevents integration debt) |
| **Source** | base report 2.2; platform integration architecture |

**Why:** the estate exposes 1,177 endpoints with no published contract and no
versioning. Today a downstream caller binds to undocumented behavior and breaks
on the next change. The platform model is that a single integration gateway is
the only service permitted to call ARC, with every application reaching ARC
through that gateway and, where appropriate, through the MCP-governed surface.
That model only works if the ARC services present a stable, described contract.
Building the contract now, while the framework uplift is already touching these
services, is the modernization-vs-hack-it-later decision: define the surface once
and correctly, instead of each future consumer reverse-engineering it and pinning
to quirks. A clean contract is also what lets capabilities be exposed safely
later (for example future AI-assisted or cross-system case workflows) without
re-plumbing each service.

**Steps**
1. Publish an OpenAPI specification per service. For Spring Boot services,
   springdoc-openapi (adopted in P1-01, replacing the abandoned springfox)
   generates it from the controllers. For RESTEasy/Jersey (JAX-RS) services, use
   the corresponding OpenAPI integration (for example `swagger-jaxrs2` or the
   RESTEasy OpenAPI extension). JSF/JSP-bound services that do not expose a REST
   API and are deferred to Phase 3 are out of scope here; they get a contract
   only if and when they expose REST endpoints. Commit the spec as the
   integration contract.
2. Introduce explicit API versioning (path or header), so a contract change is a
   new version, not a silent break for the gateway.
3. Normalize the response envelope and content types across services so the
   gateway's per-service clients bind to one shape, not many.
4. Treat the OpenAPI spec as the source for generated client code and, later, for
   MCP tool schemas (P4-07); do not hand-maintain parallel definitions.

**Done when**
- [ ] Every service publishes a versioned OpenAPI spec, committed to the repo.
- [ ] The integration gateway's clients are generated from or validated against
      those specs.

**Verify**
```bash
# each deployable service exposes an OpenAPI document (path varies: /v3/api-docs for springdoc, /openapi.json for JAX-RS)
curl -fsSL https://<service-url>/v3/api-docs | python3 -c "import json,sys; json.load(sys.stdin)" && echo OK
```

### P1-12 - Replace broken cryptography

| | |
|---|---|
| **Severity** | CRITICAL |
| **Source** | base report 6.6; audit 4.1 / Phase 1.4 |

**Why:** `PBEWithMD5AndDES` pairs a broken hash (MD5) with a broken cipher
(56-bit DES, brute-forceable in hours). Anything protected with it should be
treated as recoverable by an attacker. The Verify pattern returns 30 occurrences
(15 after removing nested-checkout duplicates) across five files in two services,
including a dedicated utility:
`RespondentPortal-ims-aks/.../utility/DesEncrypter.java:41` and FedSep
(`FedSepAppCache.java`, `hearingappeal/.../ValidateUtils.java`,
`util/DesEncrypter.java`).

**Steps**
1. Replace the DES/MD5 scheme with AES-256-GCM (authenticated encryption). Derive
   keys with a modern KDF (PBKDF2-HMAC-SHA256 with a high iteration count, or
   Argon2) and a per-value random salt and IV; do not reuse the hardcoded salt.
2. Pull the key from Key Vault (Phase 0 P0-01..04 pattern), never a constant.
3. Re-encrypt existing stored ciphertext: decrypt with the legacy routine once
   during a migration window, re-encrypt with AES-256-GCM, then remove the legacy
   decryptor.
4. Delete `DesEncrypter` and any `PBEWithMD5AndDES` references.

**Do NOT**
- Do not leave the legacy decrypt path in place "for old data" after migration;
  it is a downgrade gadget.

**Done when**
- [ ] No `PBEWithMD5AndDES`, `DesEncrypter`, or bare `DES` cipher remains.
- [ ] Stored values are re-encrypted with AES-256-GCM; keys come from Key Vault.

**Verify**
```bash
grep -rnE --include='*.java' 'PBEWithMD5AndDES|DesEncrypter|getInstance\(\s*"DES' .   # expect: no output (covers DES, DESede, spaced args)
```

### P1-13 - Replace remaining deprecated base images

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 2.5; audit Phase 1.3 |

**Why:** beyond the JBoss base (P1-09), the estate still ships end-of-life or
unpinned base images: `debian:buster-slim` (EOL), `alfresco/alfresco-share:6.2.2`
and `alfresco-content-repository:6.2.2.23` (EOL, see P4-09), `openjdk:11-jre-slim`
(superseded), and untagged `FROM nginx` (a moving `:latest` that makes builds
non-reproducible). Each carries its own OS-package CVE backlog.

**Steps**
1. Rebase Java services onto a current `eclipse-temurin` JRE image on the chosen
   LTS (P1-10).
2. Pin every base image to a digest or explicit version; replace untagged
   `nginx` with `nginx:<version>-alpine`.
3. Replace `debian:buster-slim` with a supported slim base.
4. The Alfresco images depend on the P4-09 Alfresco decision; rebase or retire
   per that outcome.

**Done when**
- [ ] No EOL or untagged base image in any Dockerfile.
- [ ] Every `FROM` is pinned to a version or digest.

**Verify**
```bash
# No -n: the line-number prefix would push the FROM token off the start of line
# and break the anchored nginx sub-pattern, hiding the untagged-nginx images.
grep -rhE --include='Dockerfile*' '^FROM\s' . | grep -iE 'buster|:latest|^FROM\s+nginx\s*$|openjdk:11'   # expect: no output
```

### P1-14 - New-service language standard

| | |
|---|---|
| **Severity** | LOW (governance) |
| **Source** | audit Phase 1.6 |

**Why:** when a JBoss/JSF service is fully rewritten (not just migrated), it
should land on the platform's standard stack rather than perpetuating the legacy
one. The rest of the EEOC platform runs Python 3.13 with Flask or FastAPI.

**Steps**
1. For any service slated for full rewrite (not in-place migration), default to
   Python 3.13 / Flask or FastAPI, matching the platform standard.
2. Record the decision per service; a straight migration that preserves the Java
   service stays Java on the current LTS (P1-10).

**Done when**
- [ ] Rewrite candidates have a recorded target-stack decision aligned to the
      platform standard.

### P1-15 - Validate remediation efficacy before scaling

| | |
|---|---|
| **Severity** | MEDIUM (program assurance) |
| **Source** | Phase 1-4 verification audit (2026-06-13) |

**Why:** the cards are remediation plans; their efficacy is unproven until a
service is actually changed and re-scanned. The plan should not scale a fix
across all nineteen services before one service confirms the fix closes its
finding. This card sets the pilot-then-scale discipline the later phases inherit.

**Steps**
1. For each high-fan-out card (dependency clusters P1-01..07, jakarta P1-08,
   crypto P1-12, authz P2-01, SQLi P2-11), apply the remediation to one pilot
   service first.
2. Re-run the card's Verify command and the relevant scan on the pilot before and
   after; confirm the finding count drops as predicted and nothing regresses.
3. Only after the pilot passes, schedule the same change across the remaining
   services. Record the before/after numbers in the progression log of
   `ARC_Reaudit_Playbook.md`.

**Done when**
- [ ] Each high-fan-out remediation has a pilot service that passed re-scan before
      the change was scaled.
- [ ] Before/after deltas are recorded in the re-audit progression log.

---

### Phase 1 exit gate

- [ ] CRITICAL Java and npm dependency findings cleared (P1-01, P1-04, P1-05).
- [ ] Deserialization libraries replaced and XStream allowlisted (P1-02).
- [ ] Shared utility libraries on patched/replacement versions (P1-03).
- [ ] Frontend security bumps applied; Angular uplift handed to Phase 3 (P1-06).
- [ ] Pipeline image rebuilt with patched Python tooling (P1-07).
- [ ] javax to jakarta migration complete per service, framework bumped (P1-08).
- [ ] JBoss base image retired or remaining services deferred to Phase 3 (P1-09).
- [ ] Runtimes consolidated onto the chosen LTS (P1-10).
- [ ] Each service publishes a versioned OpenAPI contract (P1-11).
- [ ] Broken crypto replaced with AES-256-GCM; no PBEWithMD5AndDES/DES (P1-12).
- [ ] No EOL or untagged base images; all pinned (P1-13).
- [ ] Rewrite candidates have a recorded target-stack decision (P1-14).
- [ ] High-fan-out remediations piloted on one service and re-scanned before
      scaling; before/after deltas logged (P1-15).
- [ ] Full-severity re-scan: no CRITICAL/HIGH dependency findings remain; the
      MEDIUM/LOW cleared by the cluster bumps is confirmed gone, and any residual
      MEDIUM/LOW is tracked into the Phase 4 monitoring backlog (P4-03).

---

---

## Phase 2 - Security Architecture, Integration Boundary, Observability

**Objective:** close the access-control, injection, and request-handling gaps
that Phase 0 only emergency-patched. Phase 0 stopped the bleeding on the
reachable items (one XXE path, the known-exploited CVEs, the worst CSRF and CORS
holes); Phase 2 makes the controls systemic across all 19 deployable services.

**Timeline:** months 4-9, overlapping the tail of Phase 1. The framework uplift
in Phase 1 (P1-08 jakarta migration) is a prerequisite for the current
Spring Security idioms used below.


---

### P2-01 - Apply method-level authorization across all endpoints

| | |
|---|---|
| **Severity** | CRITICAL |
| **Source** | base report 6.3; Phase 2 recon |

**Why:** only 259 of 1,177 endpoints carry a method-level authorization
annotation, and the recon shows that coverage is almost entirely in two
services. The rest are effectively unguarded at the method layer.

Verified distribution (annotations vs endpoints, by service):

```text
method-auth annotations:   FederalHearings 159, EEOCWebService 92,
                           ContentGenerator 6, ECMService 2  (= 259 total)
endpoints (denominator):   PrEPAWebService 330, FederalHearings 261,
                           FepaGateway 128, FederalWebService 96,
                           EmployerWebService 78, SearchData 46, Intake 46, ...
```

PrEPAWebService has **330 endpoints and zero** method-level authorization
annotations. It is the highest-priority target. FederalHearings (159 of 261) has
the best existing coverage and is the reference pattern.

**Steps**
1. Define the role model first. Map the platform roles to coarse endpoint
   classes (public, authenticated-user, case-worker, admin, service-to-service).
   This is the input the cards cannot pre-fill (see Do NOT / open decision).
2. Enable global method security per service (`@EnableMethodSecurity`).
3. Apply `@PreAuthorize` at the controller-method or service level, working
   service by service in priority order: PrEPAWebService, FepaGateway,
   FederalWebService, EmployerWebService, then the smaller services.
4. Default-deny: configure the `SecurityFilterChain` so an endpoint with no
   explicit rule is rejected, not permitted.
5. Use FederalHearings as the worked reference for the annotation pattern.
6. Remove or profile-gate non-production controllers. Phase 0 P0-16 gated the one
   known unauthenticated dev controller (`IntakeCollectionsService /api/dev`);
   generalize that here. Inventory every `@RestController`/`@Controller` that
   exposes dev, test, or debug operations, and either exclude it from the
   deployable artifact or guard it behind a non-prod `@Profile`, so default-deny
   is not the only thing standing between a privileged caller and a process-control
   endpoint that should not ship at all.
7. Produce the authorization matrix as a tracked deliverable, not a standing open
   decision. Enumerate all 1,177 endpoints and, with the product and data owners,
   assign each to a role class (public, authenticated-user, case-worker, admin,
   service-to-service). Commit it as a per-service artifact (for example
   `authz-matrix.csv`) with named owners and a due date. This is the input step 1
   names; without it the rest of the card cannot be executed beyond default-deny.

**Do NOT**
- Do not invent the role-to-endpoint mapping. The role matrix is a product and
  data-owner decision. This card prescribes the mechanism and the inventory;
  the mapping is supplied at execution. Recorded as an open decision in the
  notes file.

**Done when**
- [ ] Every deployable service has `@EnableMethodSecurity` and a default-deny
      chain.
- [ ] Every endpoint resolves to an explicit authorization rule.
- [ ] PrEPAWebService and the other zero-coverage services are remediated.
- [ ] No dev/test/debug controller is reachable in a production build; each is
      removed from the artifact or behind a non-prod profile (generalizes P0-16).
- [ ] The role-to-endpoint authorization matrix exists as a checked-in artifact
      with named owners, covering every endpoint.

**Verify**
```bash
# annotation count rises toward endpoint count per service
grep -rn --include='*.java' '@PreAuthorize\|@Secured\|@RolesAllowed' <service> | wc -l
grep -rn --include='*.java' -E '@(Get|Post|Put|Delete|Patch|Request)Mapping' <service> | wc -l
```

### P2-02 - Remove blanket permitAll

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 6.3 |

**Why:** 46 `permitAll` declarations open routes with no authentication. Some are
legitimate (health, login, public assets); most are not.

**Steps**
1. List every `permitAll` and classify: legitimately public (health, login,
   static) vs accidentally open.
2. Replace the accidental ones with an authentication requirement; scope the
   legitimate ones to the exact path, never a broad pattern.

**Done when**
- [ ] Every remaining `permitAll` is path-scoped and has a one-line justification.

**Verify**
```bash
grep -rn --include='*.java' 'permitAll' .   # each hit path-scoped + justified
```

### P2-03 - Complete the XXE hardening sweep

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 6.2; Findings Addendum; Phase 0 P0-14 |

**Why:** 42 XML parser instantiations, 0 hardened. P0-14 hardened the reachable
upload path (FedSep `/uploadXml`) as an emergency; this card finishes the
remaining sites so the control is uniform.

**Steps**
1. For every `DocumentBuilderFactory`, `SAXParserFactory`, `XMLInputFactory`,
   `TransformerFactory`, and JAXB unmarshal, set the secure-processing feature
   and disable external DTD/entity resolution (the pattern from P0-14).
2. Centralize it: add a `SecureXmlFactory` helper and route parser creation
   through it, so new code inherits the hardening.

**Done when**
- [ ] Every parser site uses the hardened factory or sets the features inline.
- [ ] `disallow-doctype-decl` / `FEATURE_SECURE_PROCESSING` present at each site.

**Verify**
```bash
# parser sites vs hardening calls should converge
grep -rn --include='*.java' 'DocumentBuilderFactory\|SAXParserFactory\|XMLInputFactory\|TransformerFactory' . | wc -l
grep -rn --include='*.java' 'disallow-doctype-decl\|FEATURE_SECURE_PROCESSING\|ACCESS_EXTERNAL_DTD' . | wc -l
```

### P2-04 - Finish deserialization remediation

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 6.1; Phase 0 P0-15; Phase 1 P1-02 |

**Why:** 27 sites (13 `ObjectInputStream`/`readObject`, 14 XStream). P0-15
triaged the reachable ones and P1-02 bumped the libraries; this card closes the
remainder and sets the standard.

**Steps**
1. For each `ObjectInputStream` site, replace native Java serialization with a
   data format that does not deserialize arbitrary types (JSON via a hardened
   Jackson, or a schema-bound format) where the source is untrusted.
2. For XStream sites, confirm the P1-02 allowlist is applied everywhere, not just
   the P0-15 emergency subset.
3. Add a static-analysis rule to fail the build on new `ObjectInputStream` over
   untrusted input.

**Done when**
- [ ] No native deserialization of untrusted input remains.
- [ ] Every XStream reader has an allowlist.

**Verify**
```bash
grep -rn --include='*.java' 'ObjectInputStream\|readObject()' . | wc -l   # only trusted-source sites remain, each documented
```

### P2-05 - Input validation on request parameters and path variables

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 6.4 |

**Why:** 595 `@RequestParam` with only 2 validated, and 945 `@PathVariable` with
no validation pattern. Request bodies are mostly fine (251 of 299 carry
`@Valid`); the scalar inputs feeding the same endpoints are not.

**Steps**
1. Enable class-level `@Validated` on controllers so constraint annotations on
   method parameters are enforced.
2. Add constraint annotations (`@NotBlank`, `@Pattern`, `@Size`, `@Min/@Max`) to
   `@RequestParam` and `@PathVariable` parameters per their domain type.
3. Add a `@ControllerAdvice` to translate `ConstraintViolationException` into
   the platform RFC 7807 Problem Details response.

**Done when**
- [ ] Controllers are `@Validated`; scalar inputs carry constraints.
- [ ] Validation failures return RFC 7807, not a stack trace.

**Verify**
```bash
grep -rn --include='*.java' '@RequestParam' . | wc -l
grep -rn --include='*.java' '@RequestParam.*@Valid\|@Validated' . | wc -l   # ratio rises
```

### P2-06 - SSRF controls on outbound HTTP

| | |
|---|---|
| **Severity** | MEDIUM (HIGH where a destination is user-influenced) |
| **Source** | base report 6.12; Findings Addendum (metadata-endpoint risk) |

**Why:** 806 outbound HTTP client usages (`RestTemplate`, `WebClient`,
`HttpURLConnection`, `OkHttpClient`). Where a destination URL is user-influenced,
the service can be steered to internal endpoints, including the AKS metadata
endpoint that surfaces the managed-identity token.

**Steps**
1. Triage the 806 sites for which take a URL from request data. Those are the
   real SSRF surface; the rest call fixed internal services.
2. For the user-influenced ones, validate the destination against an allowlist
   of permitted hosts and block link-local / metadata ranges
   (`169.254.0.0/16`, `127.0.0.0/8`, internal CIDRs).
3. Centralize via an outbound-request filter so new clients inherit the guard.

**Done when**
- [ ] Every user-influenced outbound call validates against a host allowlist.
- [ ] Link-local and metadata ranges are blocked at the HTTP-client layer.

### P2-07 - Introduce rate limiting

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 4.8; Phase 2 recon (zero rate limiting found) |

**Why:** there is no rate limiting anywhere in the estate (verified: 0 usages of
Bucket4j, Resilience4j, or any rate limiter). Authentication endpoints, search,
and the upload paths are exposed to brute force and resource exhaustion.

**Steps**
1. Prefer gateway-level rate limiting (Azure API Management / ingress) for a
   uniform policy across services.
2. For service-level needs (per-principal auth-attempt throttling), add
   Resilience4j or Bucket4j on the sensitive endpoints: login/token, search,
   document upload.
3. Return RFC 7807 with HTTP 429 on limit breach.

**Done when**
- [ ] Auth, search, and upload endpoints are rate limited at the gateway or
      service layer.
- [ ] Limit breaches return 429 + RFC 7807.

**Verify**
```bash
grep -rln --include='*.java' -iE 'bucket4j|Resilience4j|RateLimiter' . | wc -l   # rises from 0
```

### P2-08 - Complete the security-header rollout

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 6.7; Phase 0 P0-12 |

**Why:** zero services set CSP, HSTS, or X-Frame-Options. P0-12 added the headers
to the priority services as an emergency; this card completes all 19 deployable
services, including the JBoss/JSP tier that needs a servlet filter rather than a
Spring config.

**Steps**
1. Spring Boot services: the `SecurityConfig` header block from P0-12.
2. JBoss/JSP services (EEOCWebService, ImsNXG, FedSep, RespondentPortal,
   DocumentGeneratorAdapter): a `SecurityHeadersFilter` registered in `web.xml`,
   setting the same headers on every response.

**Done when**
- [ ] All 19 services return CSP, HSTS, X-Frame-Options, X-Content-Type-Options,
      Referrer-Policy.

**Verify**
```bash
grep -rn --include='*.java' --include='*.properties' --include='*.yml' \
  'Content-Security-Policy\|X-Frame-Options\|Strict-Transport' . | wc -l   # rises from 0
```

### P2-09 - Standardize CSRF posture

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | base report 6.3; Phase 0 P0-11 |

**Why:** P0-11 corrected the CSRF list and enforced it on the primary
browser-facing service. This card makes the decision explicit and documented for
all eight services that currently disable CSRF, so the posture is auditable.

**Steps**
1. For each of the eight services (ContentGeneratorWebService, EmailWebService,
   FepaGateway, IntakeCollectionsService, MessagingPoc, PrEPAWebService,
   TemplateMangementWebService, UserManagementWebService), apply the
   browser-facing-vs-backend-only decision from P0-11.
2. Every retained `csrf.disable()` carries the one-line justification comment.

**Done when**
- [ ] Browser-facing services enforce CSRF; backend-only disables are justified
      in code.

**Verify**
```bash
grep -rn --include='*.java' 'csrf.*disable' .   # each hit justified
```

### P2-10 - Establish the governed integration boundary

| | |
|---|---|
| **Severity** | HIGH (security control and integration foundation) |
| **Source** | platform integration architecture; base report 6.3 |

**Why:** the platform rule is that one integration gateway is the only service
permitted to call ARC, and every application reaches ARC through it. Right now
that is a convention, not an enforced control: the ARC services do not
authenticate their callers, so any service, or an attacker who reaches the
network, can call ARC's endpoints directly. Enforcing the boundary is both a
security control (defense in depth behind the per-endpoint authz in P2-01) and
the foundation that makes downstream integration safe to build. Doing it during
modernization, rather than bolting per-consumer access on later, is what keeps
the surface governed: one authenticated entry, one place to audit, one contract.
The downstream gateway already implements the consumer half of this pattern
(inbound bearer auth, outbound service auth, correlation propagation, SSRF-guarded
outbound URLs, rate limiting); this card builds the ARC half so the two meet.

**Steps**
1. **Authenticate the caller on the ARC side.** Require a service identity on
   inbound calls (Entra ID machine-to-machine token, managed identity, or mTLS,
   matching the platform auth model) and accept only the integration gateway's
   identity. Reject unauthenticated or unknown callers.
2. **Consistent error contract.** Every ARC endpoint returns RFC 7807 Problem
   Details on error, so the gateway and any downstream surface get uniform error
   semantics instead of leaking exception detail to the caller. This is the
   response-path control; it does not by itself address the 590 `printStackTrace`
   calls in base report 6.10, which write to stdout/stderr and are remediated
   separately as part of logging cleanup.
3. **Correlation propagation.** Accept and propagate `X-Request-ID` on every hop,
   so a request can be traced end to end across ARC, the gateway, and the
   MCP-governed surface. The gateway already emits and forwards it; ARC must
   honor and echo it.
4. **HTTPS only** for every inter-service hop, per the platform standard.

**Do NOT**
- Do not rely on network placement alone (private VNet) as the boundary. Network
  controls are a layer, not the control; the caller identity is the control.

**Done when**
- [ ] ARC services authenticate inbound callers and accept only the gateway
      identity.
- [ ] Every ARC endpoint returns RFC 7807 on error and propagates `X-Request-ID`.
- [ ] Direct calls to ARC from a non-gateway identity are rejected.

**Verify**
```bash
# an unauthenticated or non-gateway call is rejected
curl -s -o /dev/null -w '%{http_code}\n' https://<arc-service>/<protected-endpoint>   # expect 401/403
```

---

### P2-11 - Remediate SQL injection

| | |
|---|---|
| **Severity** | HIGH |
| **Source** | base report 6.5; audit 4.9 / Phase 2.4 |

**Why:** native queries and string-built queries appear at ~1,900 sites; the
real injection surface is the subset that concatenates a value into the query
text, ~286 sites, concentrated in ImsNXG (e.g.
`ImsNXG/.../service/DocumentManager.java:146`). Any one that concatenates request
input into native SQL is a direct injection.

**Steps**
1. Triage the ~286 concatenation sites: separate those that concatenate a
   request-derived value (real injection) from those that concatenate an internal
   constant (lower risk, still fix for consistency).
2. Convert to parameter binding: JPA named/positional parameters
   (`setParameter`), or `PreparedStatement` placeholders. Never concatenate a
   value into the query string.
3. Where a dynamic identifier (table/column) must be interpolated, validate it
   against an allowlist of known identifiers; never bind it from user input.
4. Add a SAST rule (the Java equivalent of Bandit B608) to fail the build on new
   string-concatenated queries.

**Done when**
- [ ] No query concatenates a request-derived value; all values are bound.
- [ ] Dynamic identifiers are allowlisted, not user-supplied.

**Verify**
```bash
# indicative only: catches inline concat. Also review variable-built queries (String sql = "..." + x; em.createQuery(sql))
grep -rnE --include='*.java' 'createQuery\(.*\+|createNativeQuery\(.*\+|"(SELECT|INSERT|UPDATE|DELETE)[^"]*"\s*\+' . | grep -iv test | wc -l   # trends to 0
```

### P2-12 - Exception handling and stack-trace cleanup

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | base report 6.10; audit 4.14 |

**Why:** 1,546 broad `catch (Exception)` blocks swallow specific failures, and
590 `printStackTrace()` calls write stack traces to stdout/stderr, leaking class
names, paths, and SQL fragments and bypassing the masking pipeline. This is the
logging cleanup that P2-10 defers to (RFC 7807 fixes the response path; this
fixes the log path).

**Steps**
1. Replace `printStackTrace()` with a structured logger call at the appropriate
   level, logging a message and the exception, never the raw trace to stdout.
2. Narrow broad `catch (Exception)` to the specific exceptions actually thrown;
   where a catch-all is genuinely needed, log and rethrow or handle explicitly.
3. Route through the platform logging pattern so PII masking (Phase 0 P0-13)
   applies on the log path.

**Done when**
- [ ] No `printStackTrace()` in application code.
- [ ] Broad catches narrowed or justified; exceptions logged via the structured
      logger.

**Verify**
```bash
grep -rnE --include='*.java' 'printStackTrace\s*\(\s*\)' . | wc -l   # expect: 0
```

### P2-13 - Harden session cookie configuration

| | |
|---|---|
| **Severity** | MEDIUM |
| **Source** | base report 6.8; audit 4.13 |

**Why:** 176 `HttpSession` usages with no secure cookie configuration. Beyond the
timeout fix (Phase 0 P0-06), the session cookie itself needs the security flags,
or the session is exposed to theft over HTTP and to script access.

**Steps**
1. Set the session cookie flags on every service: `Secure` (HTTPS only),
   `HttpOnly` (no script access), and `SameSite=Lax` (or `Strict` where no
   cross-site flow needs it).
2. For Spring Boot, set `server.servlet.session.cookie.secure/http-only/same-site`;
   for the JBoss/servlet services, set them in `web.xml` `<cookie-config>`.
3. Confirm session fixation protection is enabled (Spring Security default;
   verify on the servlet services).

**Done when**
- [ ] Every service sets Secure, HttpOnly, and SameSite on the session cookie.

**Verify**
```bash
curl -s -I https://<service-url>/<login> | grep -i 'set-cookie'   # shows Secure; HttpOnly; SameSite
```

### P2-14 - Feature-flag gating and audit-logging conformance

| | |
|---|---|
| **Severity** | MEDIUM (platform conformance) |
| **Source** | audit 2.8 |

**Why:** the platform standard gates every outbound integration behind a boolean
environment flag that defaults off, so a service starts and passes its health
check in standalone mode with all integrations disabled. ARC services must adopt
this so integration (P2-10, P4-07) is opt-in per environment, and any AI-mediated
action carries the platform audit record.

**Steps**
1. Gate each outbound integration behind a default-off environment flag
   (matching `MCP_ENABLED`/`MCP_PROTOCOL_ENABLED` and the per-integration
   pattern); the service must be healthy with all flags false.
2. For any AI-mediated capability, emit the HMAC-signed, 7-year WORM audit record
   (the platform AI-audit standard; see P4-07).

**Done when**
- [ ] Every outbound integration is behind a default-off flag; health passes with
      all integrations disabled.
- [ ] AI-mediated actions emit the signed, WORM-retained audit record.

**Verify**
```bash
# service starts healthy with all integration flags off
<run health check with integration flags unset/false>   # expect: healthy
```

### P2-15 - Standardize health endpoints and structured logging

| | |
|---|---|
| **Severity** | MEDIUM (integration readiness / observability) |
| **Source** | audit 6.3 (DAES integration requirements) |

**Why:** the platform's DAES applications share an integration baseline that ARC
does not yet meet. Two pieces are observability: a standardized health endpoint
per service (Spring Actuator exists on some services, is absent on the JBoss
ones) and structured JSON logging (not implemented). Without them, ARC cannot be
monitored or traced as a first-class platform participant, and the gateway cannot
aggregate health. This pairs with the RFC 7807 and X-Request-ID work in P2-10.

**Steps**
1. Expose a standardized health endpoint on every service: Spring Boot Actuator
   `/actuator/health` (liveness + readiness), and an equivalent `/health` servlet
   on the JBoss/JSP services. The gateway aggregates these (P4-07 / P4-11).
2. Emit structured JSON logs (one event per line, with `X-Request-ID`, level,
   service, and message fields) so logs are queryable and correlate across hops.
   Route through the platform logging pattern so PII masking (P0-13) applies.
3. Confirm the health endpoint is reachable without authentication only for the
   liveness probe; readiness and detail require the service identity.

**Done when**
- [ ] Every service exposes a standardized health endpoint.
- [ ] Logs are structured JSON carrying X-Request-ID.

**Verify**
```bash
# liveness is the public probe (the main /actuator/health may require auth); JBoss services expose /health
curl -fsS https://<service-url>/actuator/health/liveness | python3 -c "import json,sys;json.load(sys.stdin)" && echo OK
# structured logging: a log line parses as JSON and carries the correlation id
<tail a log line> | python3 -c "import json,sys;d=json.load(sys.stdin);assert 'X-Request-ID' in str(d) or 'request_id' in d"
```

### P2-16 - Remediate command injection and path traversal

| | |
|---|---|
| **Severity** | HIGH (low count, high per-instance severity) |
| **Source** | base report 6.11; SAST sweep (2026-06-13) |

**Why:** base report 6.11 flagged process-execution and request-driven
file-access sites but no card was written for the class, so it stayed uncovered
until the SAST sweep surfaced it. Semgrep confirms two tainted-file-path flows
(CWE-23), and the source carries six `Runtime.exec`/`ProcessBuilder` sites and
three request-driven `new File(...)`/`getRealPath` sites (deduplicated). Any one
that builds a command or a path from request input is command injection or path
traversal, each high-impact on its own.

**Steps**
1. Triage every process-execution site for whether an argument derives from
   request input. Replace shell-string construction with a fixed-command
   `ProcessBuilder` and validated argument array; never pass user input through a
   shell.
2. For file-access sites, canonicalize the resolved path and confirm it stays
   within an allowed base directory (reject `..` traversal); validate the
   filename against an allowlist pattern.
3. Add the Semgrep command-injection and `tainted-file-path` rules to the CI gate
   (P4-01) so a new instance fails the build.

**Done when**
- [ ] No process execution builds a command from unvalidated request input.
- [ ] File access is canonicalized and confined to an allowed base directory.

**Verify**
```bash
grep -rnE --include='*.java' 'Runtime\.getRuntime\(\)\.exec|ProcessBuilder|getRealPath|new File\([^)]*request' . | grep -iv test   # each remaining site reviewed and constrained
```

### P2-17 - SAST taint-flow analysis and review-queue triage

| | |
|---|---|
| **Severity** | HIGH (discovery; converts surface counts to confirmed defects) |
| **Source** | Phase 1-4 verification audit (2026-06-13) |

**Why:** the code-level findings to date are pattern-match counts the audit
itself labels review queues with false positives (SQL ~282, SSRF 806, PII-log
565), and a line-oriented grep cannot follow a value across method calls or
lines. A SAST sweep (Semgrep `p/java` + `p/owasp-top-ten`) on the nine heaviest
services returned 68 data-flow findings: 48 SQL injection (CWE-89, concentrated
in ImsNXG and FedSep), 16 XXE (CWE-611), 2 weak-hash (MD5), and 2 path traversal
(CWE-23). The SQL result proves the gap: the value concatenated into the query
sits on the line after `createNativeQuery(`, so the single-line grep in P2-11
cannot see it but the taint analysis can.

**Steps**
1. Run SAST (Semgrep registry rules or CodeQL) across every deployable service,
   not just the nine sampled; export findings by CWE.
2. Triage each review-queue class to confirmed defects and route them to the
   owning card: SQL injection to P2-11, SSRF (the roughly 33 of 500 clients whose
   URL derives from request input) to P2-06, PII-in-log (the roughly 113 email
   sites) to P2-12, XXE to P2-03, path traversal and command injection to P2-16.
3. Track residual lower-confidence findings into the P4-03 monitoring backlog;
   add the gating SAST rules to CI (P4-01).

**Done when**
- [ ] SAST run across every deployable service; findings exported by CWE.
- [ ] Each review-queue class triaged to a confirmed-defect list routed to its
      remediation card.

**Verify**
```bash
semgrep scan --config p/java --config p/owasp-top-ten --include='*.java' --no-git-ignore --json <service> \
  | python3 -c "import json,sys,collections; d=json.load(sys.stdin); print(collections.Counter(r['extra']['severity'] for r in d['results']))"
```

---

### Phase 2 exit gate

- [ ] Every endpoint resolves to an explicit authorization rule; default-deny
      chains in place (P2-01).
- [ ] No blanket `permitAll`; remaining ones path-scoped and justified (P2-02).
- [ ] All XML parser sites hardened against XXE (P2-03).
- [ ] No untrusted-input deserialization; XStream allowlisted everywhere (P2-04).
- [ ] Scalar inputs validated; failures return RFC 7807 (P2-05).
- [ ] User-influenced outbound calls allowlisted; metadata ranges blocked (P2-06).
- [ ] Rate limiting on auth, search, and upload endpoints (P2-07).
- [ ] Security headers on all 19 services (P2-08).
- [ ] CSRF posture explicit and justified per service (P2-09).
- [ ] Authenticated integration boundary enforced; ARC accepts only the gateway
      identity, returns RFC 7807, and propagates X-Request-ID (P2-10).
- [ ] SQL queries parameterized; no value concatenation (P2-11).
- [ ] No printStackTrace; broad catches narrowed; exceptions logged safely (P2-12).
- [ ] Session cookies set Secure, HttpOnly, SameSite (P2-13).
- [ ] Integrations behind default-off flags; AI actions audited (P2-14).
- [ ] Standardized health endpoints and structured JSON logging (P2-15).
- [ ] Command injection and path traversal remediated; no command or path built
      from unvalidated request input (P2-16).
- [ ] SAST run across all services; review-queue classes triaged to confirmed
      defects and routed to their cards (P2-17).

---

---

## Phase 3 - Frontend Modernization, Section 508, USWDS, Navigation

**Objective:** retire the legacy server-rendered frontend tier, bring the Angular
applications onto one current version, and make the remediable frontends meet
508. Section 508 is federal law; the legacy JSP/XHTML tier cannot reach AA in
place, so this phase retires it rather than patching it.

**Timeline:** months 6-12, overlapping Phase 1's JBoss retirement (P1-09) and
Phase 2's header rollout (P2-08). The JBoss base-image services and the JSP tier
are the same services; retire them together.


---

### P3-01 - Retire the legacy JSP/XHTML frontend tier

| | |
|---|---|
| **Severity** | HIGH (508 non-compliance + unmaintainable stack) |
| **Source** | base report 2.4, 5.2, 8.2; Phase 1 P1-09 |

**Why:** 407 JSP/XHTML files and 2,296 JSF API usages make up the server-rendered
tier. It is tied to the JBoss base image (P1-09) and cannot be brought to WCAG
2.1 AA without a rewrite, so this card retires it. The work concentrates in two
services.

Verified distribution:

```text
JSP/XHTML by repo:  FedSep 258, ImsNXG 122, RespondentPortal 24,
                    EEOCWebService 2, DocumentGeneratorAdapter 1  (= 407)
```

FedSep and ImsNXG hold 380 of 407. Both already have a parallel Angular front
end (FedSep-NG, ImsNXG-NG), which is the migration target.

**Steps**
1. For FedSep and ImsNXG, complete the migration to the existing Angular
   frontends (FedSep-NG, ImsNXG-NG) and decommission the JSP UI. The Angular apps
   already exist; the work is feature parity and cutover, not a greenfield build.
2. For RespondentPortal (24 JSP), EEOCWebService (2), and DocumentGeneratorAdapter
   (1), scope per service: small JSP counts may be converted to a thin Angular or
   static frontend, or folded into an existing portal.
3. Retire the JBoss base image per service as its JSP tier is removed (closes the
   P1-09 deferral for these services).

**Done when**
- [ ] No deployable service serves JSP/XHTML.
- [ ] The JBoss base image is removed from the retired services.

**Verify**
```bash
find . \( -name '*.jsp' -o -name '*.xhtml' \) | wc -l   # shrinks toward 0
```

### P3-02 - Align the Angular applications on one current version

| | |
|---|---|
| **Severity** | MEDIUM (HIGH for the security-relevant deps) |
| **Source** | base report 2.3; Phase 3 recon; Phase 1 P1-06 |

**Why:** there are **three** Angular applications on two major versions. The
recon corrects the base report, which listed two.

Verified inventory:

```text
FedSep-NG-ims-aks-test     : @angular/core ^16.2.12
ImsNXG-NG-ims-aks-test     : @angular/core ^16.2.12
IntakeCollectionsUI-main   : @angular/core ^19.0.0
```

Two apps lag on Angular 16 (out of active support); one is on 19. Bring all three
to one current version. The security-only dependency bumps (axios, dompurify,
lodash, etc.) are done in Phase 1 P1-06; this card handles the framework-major
move that requires component changes.

**Steps**
1. Move FedSep-NG and ImsNXG-NG from Angular 16 to the current major (verify
   latest; 19.x at time of writing), one major at a time per the Angular update
   guide, addressing deprecations at each step.
2. Bring IntakeCollectionsUI to the same minor as the other two so all three
   share one version line.
3. Confirm the Phase 1 P1-06 security bumps are present after the framework move.

**Done when**
- [ ] All three Angular apps on one current major/minor.
- [ ] `npm audit --audit-level=high` clean in each.

**Verify**
```bash
# Recurse (ImsNXG-NG keeps its app under client/, so a one-level */package.json
# glob misses it) and collapse nested self-copies.
grep -rl --exclude-dir=node_modules --include=package.json '"@angular/core"' . \
  | sed -E 's#([^/]+)/\1/#\1/#' | sort -u \
  | while read f; do echo "$f -> $(grep '@angular/core' "$f" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"; done
# expect: one version line across all three apps
```

### P3-03 - Section 508: text alternatives, language, keyboard access

| | |
|---|---|
| **Severity** | HIGH (federal law) |
| **Source** | base report 7 |

**Why:** the automated 508 scan found concrete WCAG failures. These are in the
remediable (Angular and remaining HTML) tier; the JSP-tier instances are resolved
by retirement (P3-01).

Verified counts (whole estate; subtract the JSP tier as P3-01 retires it):

```text
images without alt:      104   (WCAG 1.1.1)
documents missing lang:  300   (WCAG 3.1.1)
inline onclick handlers: 863   (WCAG 2.1.1 keyboard access)
```

**Steps**
1. Add `alt` text to every `<img>`; empty `alt=""` for decorative images.
2. Add `lang="en"` to every document root.
3. Replace click-only `onclick` handlers with elements that are keyboard
   operable (native `<button>`/`<a>`, or a handler plus `keydown` and
   `tabindex`/`role`). In Angular, use `(click)` on focusable elements with
   keyboard bindings, not `onclick` on a `<div>`.

**Done when**
- [ ] No `<img>` without `alt`.
- [ ] Every document has a `lang`.
- [ ] No keyboard-inaccessible click handler in the retained frontends.

**Verify**
```bash
grep -rn --include='*.html' '<img ' . | grep -v 'alt=' | wc -l    # 0 in retained UIs
grep -rn --include='*.html' '<html' . | grep -v 'lang=' | wc -l   # 0
```

### P3-04 - Section 508: forms, tables, and ARIA

| | |
|---|---|
| **Severity** | HIGH (federal law) |
| **Source** | base report 7; platform 508 requirements |

**Why:** the input/label and table/header ratios look healthy in aggregate but
say nothing about correct association, which only per-page review confirms. Form
fields need programmatic labels; data tables need header associations.

**Steps**
1. Every form control has a programmatically associated `<label for>` or
   `aria-label`; no placeholder-as-label.
2. Every data table uses `<th scope>` and a `<caption>`; layout tables are
   replaced with CSS.
3. Charts and data visualizations include the accessible `<details>` data table
   the platform 508 requirements mandate.
4. Live regions (`aria-live`) on async status updates; visible focus indicators
   meeting the 3:1 non-text contrast minimum.

**Done when**
- [ ] All form controls have associated labels.
- [ ] All data tables have `<th scope>` and captions.
- [ ] Charts have an accessible data table.

### P3-05 - Add an automated 508 gate to CI

| | |
|---|---|
| **Severity** | MEDIUM (prevents regression) |
| **Source** | platform 508 requirements; base report 7 |

**Why:** manual 508 fixes regress without an automated gate. An axe-core scan in
CI catches the mechanical failures (alt, lang, label association, contrast) on
every change.

**Steps**
1. Add axe-core to each Angular app's test suite, asserting zero violations on
   the key pages.
2. Wire it into the CI pipeline as a gating check for the frontends.
3. Document residual manual-review items (screen-reader walkthroughs) that
   automation cannot cover.

**Done when**
- [ ] axe-core runs in CI for every retained frontend and gates the build.

**Verify**
```bash
# per frontend: axe test target exists and runs (recurse so nested frontends
# such as ImsNXG-NG/client are included, not just root-level package.json)
grep -rln --exclude-dir=node_modules --include=package.json 'axe-core\|@axe-core' .
```

---

### P3-06 - Standardize frontends on USWDS

| | |
|---|---|
| **Severity** | MEDIUM (508 and consistency) |
| **Source** | audit Phase 3.3 |

**Why:** AttorneyPortal already uses USWDS 3.7 (the US Web Design System). Its
base components ship WCAG 2.1 AA compliance and the federal standard look and
feel. Standardizing the other frontends on USWDS reduces the per-component 508
work in P3-03/P3-04 and gives the suite one design system.

**Steps**
1. Adopt USWDS in each Angular frontend as the component and design-token base,
   using AttorneyPortal (USWDS 3.7) as the reference.
2. Replace bespoke components with USWDS equivalents where one exists; the
   built-in accessibility carries the 508 baseline.
3. Keep the EEOC contrast overrides where the design system defaults fall short
   of the platform 4.5:1 / 3:1 requirements.

**Done when**
- [ ] Each frontend uses USWDS for its base components and tokens.

### P3-07 - Cross-application navigation

| | |
|---|---|
| **Severity** | LOW (UX consistency) |
| **Source** | audit Phase 3.5 |

**Why:** users should move between the ARC portals and the rest of the EEOC
application suite without friction: one login, consistent navigation, consistent
look and feel. This builds on the unified auth from Phase 2 and the USWDS
baseline (P3-06).

**Steps**
1. Adopt a shared navigation pattern and header across the portals, aligned with
   the platform's cross-application navigation.
2. Reuse the single sign-on established by the auth work so a user does not
   re-authenticate moving between portals.

**Done when**
- [ ] Portals share a consistent navigation and a single sign-on session.

---

### Phase 3 exit gate

- [ ] No deployable service serves JSP/XHTML; JBoss image removed (P3-01).
- [ ] All three Angular apps on one current version; npm audit clean (P3-02).
- [ ] Images, language, and keyboard access remediated in retained UIs (P3-03).
- [ ] Forms, tables, charts, and ARIA meet 508 (P3-04).
- [ ] axe-core 508 gate in CI for every frontend (P3-05).
- [ ] Frontends standardized on USWDS (P3-06).
- [ ] Cross-application navigation and single sign-on across portals (P3-07).

---

---

## Phase 4 - Consolidation, Continuous Security, Governed Integration, Coverage, Archival, Eventing

**Objective:** make the fixes from Phases 0-3 durable. Standardize the CI
security gate across every repo, generate SBOMs, stand up continuous monitoring
that never hides findings again, automate dependency updates so the backlog does
not re-accumulate, and reduce the 48-repo fragmentation that multiplied every
finding.

**Timeline:** months 10-18, running alongside the tail of Phases 1-3 and
continuing as steady-state operations.


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

### Phase 4 exit gate

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

### Program close

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

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Consolidated Phases 1-4 task cards into one runbook |
| 1.1 | 2026-06-12 | Derek Gordon / OCIO | Add integration-readiness cards (P1-11, P2-10, P4-07); reinforce MEDIUM/LOW coverage; review fixes |
| 1.2 | 2026-06-12 | Derek Gordon / OCIO | Close coverage gaps: 12 cards; verify-command robustness |
| 1.3 | 2026-06-12 | Derek Gordon / OCIO | Package-level completeness (+7 deps); +P2-15 health/logging, +P4-11 eventing; review fixes (pinned versions, liveness probe, existing-eventing correction) |

Assembled from `ARC_Developer_Remediation_Runbook_v2_Phase{1,2,3,4}.md`. Phase 0
is delivered separately. Coverage matrix: `ARC_Coverage_Traceability_Matrix.md`.
Refresh and source-data regeneration: `ARC_Phase1to4_Runbook_Notes.md`.
