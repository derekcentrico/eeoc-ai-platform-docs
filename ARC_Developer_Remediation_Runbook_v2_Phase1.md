# ARC Developer Remediation Runbook - v2 Phase 1

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Phase 1 developer task cards: dependency modernization, JBoss retirement, and
runtime consolidation. This file extends the v2 set
(`ARC_Developer_Remediation_Runbook_v2_Phase0.md`) and replaces the Phase 1
outline in `ARC_Developer_Remediation_Runbook.md` when v2 is assembled.

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

> **Footnote on target versions.** Target versions in this document are the
> latest stable releases as of 2026-06-10. Dependency releases move; by the time
> a phase card is executed these may be stale or themselves carry new advisories.
> Re-run the scan and re-check each target against the upstream release page
> before bumping. The refresh procedure is in
> `ARC_Phase1to4_Runbook_Notes.md`. Treat the version numbers here as "current
> latest stable, verify before use," not as pinned values.

---

## How Phase 1 cards are organized

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

## Phase 1 exit gate

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

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 1 task cards: dependency clusters, jakarta migration, JBoss retirement, runtime consolidation |

Inputs: `ARC_Secondary_Scan_Findings_2026-06-10.md`,
`ARC_Audit_Command_Findings_2026-06-10.md`, full-severity Grype/Trivy scans.
Refresh procedure and source-data regeneration: `ARC_Phase1to4_Runbook_Notes.md`.
