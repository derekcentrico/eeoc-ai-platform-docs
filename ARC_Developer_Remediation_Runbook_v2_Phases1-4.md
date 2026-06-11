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
`eeoc-arc-payloads/` source.

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
| 1 | Dependency modernization, JBoss retirement, runtime consolidation | months 2-6 | P1-01..P1-10 |
| 2 | Security architecture (authz, injection, validation, SSRF, rate limiting, headers) | months 4-9 | P2-01..P2-09 |
| 3 | Frontend modernization and Section 508 | months 6-12 | P3-01..P3-05 |
| 4 | Consolidation and continuous security | months 10-18 | P4-01..P4-06 |

---

## Phase 1 - Dependency Modernization, JBoss Retirement, Runtime Consolidation

**Objective:** clear the dependency-CVE backlog across all severities and remove
the framework conditions that produced it. The base report scanned CRITICAL and
HIGH only; the full-severity backlog (CRITICAL through LOW; Grype counts 752,
Trivy 398 across the two scanners) is in
`ARC_Secondary_Scan_Findings_2026-06-10.md`. Those findings collapse into the
package clusters below, because one bump clears every finding tied to that
package at once.

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
| commons-beanutils | 1.9.4 | (see P1-02) | Transitive | |
| gson | 2.8.2, 2.8.5 | 2.11.0 | Transitive | |
| guava | 22.0, 31.0.1-jre | 33.4.x | Mixed | |
| httpclient | 4.3.3, 4.5.2 | 4.5.14 or httpclient5 5.x | Transitive | 4.5.14 is the last 4.x; 5.x is the real target |
| jsoup | 1.10.1, 1.14.3 | 1.18.x | Direct | |
| json (org.json) | 20180130-20230618 | 20240303 | Transitive | |
| xalan | 2.7.0 | 2.7.3 or remove (JDK built-in) | Transitive | |
| bcprov-jdk15on / bcpkix-jdk15on | 1.68 | bcprov-jdk18on 1.79 | Transitive | artifact id changes from jdk15on to jdk18on |
| jackson-core | 2.16.1 | 2.18.x | Transitive | |
| hibernate-core | 5.4.30.Final | 5.6.15 or 6.x | Direct | 6.x is jakarta; ties to P1-08 |
| postgresql (JDBC) | 42.7.3 | 42.7.4+ | Direct | |

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
grep -rhn 'tika-core\|name: .tika-core\|<artifactId>poi' --include='pom.xml' --include='build.gradle' . \
  | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -u   # expect: one Tika line, one POI line
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
- [ ] Full-severity re-scan: no CRITICAL/HIGH dependency findings remain, MEDIUM/
      LOW tracked into the Phase 4 monitoring backlog.

---


---

## Phase 2 - Security Architecture

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

---


---

## Phase 3 - Frontend Modernization and Section 508

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
grep -rh '"@angular/core"' */package.json 2>/dev/null | sort -u   # one version line
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
# per frontend: axe test target exists and runs
grep -rln 'axe-core\|@axe-core' */package.json 2>/dev/null
```

---

### Phase 3 exit gate

- [ ] No deployable service serves JSP/XHTML; JBoss image removed (P3-01).
- [ ] All three Angular apps on one current version; npm audit clean (P3-02).
- [ ] Images, language, and keyboard access remediated in retained UIs (P3-03).
- [ ] Forms, tables, charts, and ARIA meet 508 (P3-04).
- [ ] axe-core 508 gate in CI for every frontend (P3-05).

---


---

## Phase 4 - Consolidation and Continuous Security

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

### Phase 4 exit gate

- [ ] Standard security gate runs in every repo, blocking on CRITICAL/HIGH (P4-01).
- [ ] Every deployable service emits an SBOM per build (P4-02).
- [ ] Scheduled full-severity monitoring; MEDIUM/LOW tracked with an SLA (P4-03).
- [ ] Automated dependency updates wired to CI on every active repo (P4-04).
- [ ] Secret `.gitignore` and gitleaks hook on every repo; gitleaks in CI (P4-05).
- [ ] Dormant/duplicate repos retired; nested checkouts removed (P4-06).

---

### Program close

With Phases 0-4 complete, the conditions that produced the audit findings are
addressed: secrets are out of source and blocked from returning, the known-
exploited and full-backlog dependencies are patched and kept current, the access-
control and injection surfaces are systemically closed, the legacy frontend tier
is retired and the remainder meets 508, and continuous monitoring surfaces the
full severity spectrum rather than the top two tiers. The remaining work is
steady-state operations against the gates this phase established.

---


---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Consolidated Phases 1-4 task cards into one runbook |

Assembled from `ARC_Developer_Remediation_Runbook_v2_Phase{1,2,3,4}.md`. Phase 0
is delivered separately. Refresh and source-data regeneration:
`ARC_Phase1to4_Runbook_Notes.md`.
