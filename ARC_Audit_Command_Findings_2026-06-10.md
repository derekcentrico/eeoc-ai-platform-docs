# ARC Audit Command Findings
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Evidence record for the ARC source audit. Every command in
`ARC_Audit_Commands_Reference.md` was re-run on 2026-06-10 against the
`eeoc-arc-payloads/` source set (48 extracted repositories). Each block below
shows the command exactly as run and the verbatim output it produced, followed
by why the result is a problem.

This is the artifact to show when a finding is challenged: command, output,
reason. Findings map to `ARC_Modernization_Audit_and_Phased_Plan.md` and to the
remediation task cards in `ARC_Developer_Remediation_Runbook.md`.

Counts from pattern matching size the attack surface; they are not all confirmed
exploitable defects. Classes with known false-positive rates (6.5 SQL, 6.9 PII
logging, 6.12 SSRF) are labeled as review queues.

---

## 1. Repository Extraction and Inventory

### 1.1 Repository count

```text
$ ls -d */ | wc -l
48
```

### 1.2 Total source file count

```text
$ find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/target/*' -not -name '*.zip' | wc -l
30129
```

**Why it's a problem:** 48 repositories holding ~30,000 files is a fragmented
estate. No single owner sees the whole attack surface, and any control fixed in
one service is routinely absent in the next. Every finding below multiplies
across this footprint.

---

## 2. Technology Stack Classification

### 2.1 Java runtime versions

```text
$ for dir in */; do jv=$(grep -oP '<java.version>\K[^<]+' "$dir/pom.xml" 2>/dev/null); [ -n "$jv" ] && echo "$dir java $jv"; done
AT_ScenarioRunner-main/ java 21
AuthorizationService-ims-aks/ java 11
AzureAdService-main/ java 11
ContentGeneratorWebService-ims-aks/ java 25
ECMService-ims-aks-test/ java 25
EmailWebService-ims-aks-test/ java 25
EmployerWebService-ims-aks-test/ java 11
FederalHearings-ims-aks/ java 25
FederalWebService-ims-aks/ java 25
FedSep-ims-aks-test/ java 11
FepaGateway-ims-aks/ java 17
IntakeCollectionsService-main/ java 21
LitigationWebService-main/ java 11
MessagingPoc-master/ java 1.8
PrEPAWebService-ims-aks-test/ java 11
RespondentPortal-ims-aks/ java 11
SearchDataWebService-ims-aks-test-es8/ java 21
TemplateMangementWebService-ims-aks-test/ java 25
UserManagementWebService-master/ java 11
```

**Why it's a problem:** runtimes span Java 1.8 to 25. Java 8 and 11 are past or
nearing end of free public security updates, so those services accrue unpatched
JVM and TLS CVEs, and the mixed matrix blocks a single shared base image.
Targeted by runbook Phase 1.

### 2.2 API endpoint count

```text
$ grep -rn --include='*.java' -E '@(Get|Post|Put|Delete|Patch|Request)Mapping' . | wc -l
1177
```

**Why it's a problem:** 1,177 endpoints is the denominator for the authorization
gap in 6.3. Each mapping is a reachable entry point needing auth, validation, and
rate limiting.

### 2.3 Frontend frameworks

```text
$ grep -oP '"@angular/core"\s*:\s*"\K[^"]+' */package.json 2>/dev/null
IntakeCollectionsUI-main/package.json:^19.0.0
FedSep-NG-ims-aks-test/package.json:^16.2.12

$ grep -oP '"react"\s*:\s*"\K[^"]+' */package.json 2>/dev/null
(no output)
```

**Why it's a problem:** two Angular major versions (16 and 19) coexist over a
much larger server-rendered JSP/XHTML tier (2.4). 508 fixes, CSP, and upgrades
must be done multiple ways.

### 2.4 Source file counts by language

```text
$ find . -name '*.java' -not -path '*/node_modules/*' -not -path '*/target/*' | wc -l
6454

$ find . -name '*.ts' -o -name '*.tsx' -not -path '*/node_modules/*' | wc -l
4918

$ find . -name '*.jsp' -o -name '*.xhtml' | wc -l
407
```

**Why it's a problem:** 407 JSP/XHTML files are the legacy server-rendered tier
the audit flags as not 508-remediable in place. It is where the inline-handler
and missing-label problems in Section 7 concentrate.

### 2.5 Docker base images

```text
$ grep -rn --include='Dockerfile*' '^FROM' . | sort -u
ADR_PORTAL-main/staff_portal/Dockerfile:20:FROM python:3.13-slim-bookworm
ADR_PORTAL-main/staff_portal/Dockerfile:6:FROM python:3.13-slim-bookworm AS builder
alfresco-content-repository-docker-master/Dockerfile:2:FROM eus1opsacr.azurecr.io/alfresco/alfresco-content-repository:6.2.2.23
alfresco-devops-github-runner-docker-master/Dockerfile:2:FROM debian:buster-slim
alfresco-share-docker-master/Dockerfile:1:FROM alfresco/alfresco-share:6.2.2
AttorneyPortal-main/attorney-portal/Dockerfile:1:FROM node:18-alpine AS build
AttorneyPortal-main/attorney-portal/Dockerfile:9:FROM nginx
AuthorizationService-ims-aks/Dockerfile:10:FROM eclipse-temurin:11-jre-jammy
AuthorizationService-ims-aks/Dockerfile:2:FROM maven:3.9.12-eclipse-temurin-11 AS build
AzureAdService-main/Dockerfile:10:FROM openjdk:11-jre-slim
AzureAdService-main/Dockerfile:2:FROM maven:3.6.3-adoptopenjdk-11 AS build
birtweb-master/Dockerfile:11:FROM tomcat:9-jre11
birtweb-master/Dockerfile:1:FROM eclipse-temurin:11-jdk AS build
ContentGeneratorWebService-ims-aks/Dockerfile:10:FROM eclipse-temurin:25-jre
DocumentGeneratorAdapter-master/Dockerfile:1:FROM eus1opsacr.azurecr.io/eeoc-jboss74:1.0.0
ECMService-ims-aks-test/Dockerfile:10:FROM eclipse-temurin:25-jre-jammy
EEOCWebService-master/Dockerfile:1:FROM eus1opsacr.azurecr.io/eeoc-jboss74:1.0.0
EmailWebService-ims-aks-test/Dockerfile:10:FROM eclipse-temurin:25-jre
EmployerWebService-ims-aks-test/Dockerfile:10:FROM eclipse-temurin:11-jre
FederalHearings-ims-aks/Dockerfile:9:FROM eclipse-temurin:25-jre-noble
FederalWebService-ims-aks/Dockerfile:10:FROM eclipse-temurin:25-jre
FedSep-ims-aks-test/Dockerfile:1:FROM eus1opsacr.azurecr.io/eeoc-jboss74:1.0.0
FedSep-NG-ims-aks-test/Dockerfile:10:FROM nginx
FedSep-NG-ims-aks-test/Dockerfile:2:FROM node:20-alpine AS build
FepaGateway-ims-aks/Dockerfile:10:FROM eclipse-temurin:17-jre
ImsNXG-master/Dockerfile:1:FROM eus1opsacr.azurecr.io/eeoc-jboss74:1.0.0
ImsNXG-NG-ims-aks-test/Dockerfile:13:FROM nginx
ImsNXG-NG-ims-aks-test/Dockerfile:2:FROM node:18.17-alpine AS build
IntakeCollectionsService-main/Dockerfile:19:FROM eclipse-temurin:21-jre-alpine
IntakeCollectionsUI-main/Dockerfile:20:FROM nginx:alpine
IntakeCollectionsUI-main/Dockerfile:5:FROM node:22-alpine AS builder
jboss-docker-master/Dockerfile:1:FROM eus1opsacr.azurecr.io/jboss-eap-7/eap74-openjdk11-openshift-rhel8:7.4.14-5 as base
PrEPAWebService-ims-aks-test/Dockerfile:10:FROM eclipse-temurin:11-jre
RespondentPortal-ims-aks/Dockerfile:1:FROM gradle:7-jdk11 AS build
RespondentPortal-ims-aks/Dockerfile:8:FROM eus1opsacr.azurecr.io/eeoc-jboss74:1.0.0
SearchDataWebService-ims-aks-test-es8/Dockerfile:10:FROM eclipse-temurin:22-jre
TemplateMangementWebService-ims-aks-test/Dockerfile:10:FROM eclipse-temurin:25-jre
UserManagementWebService-master/Dockerfile:10:FROM openjdk:11-jre-slim
(output trimmed to one representative line per Dockerfile stage; duplicated nested-copy paths removed)
```

**Why it's a problem:** `debian:buster-slim` is end-of-life, JBoss EAP 7.4
(`eeoc-jboss74`) and Alfresco 6.2.2 are dated platforms, and untagged
`FROM nginx` pulls a moving `:latest` tag that makes builds non-reproducible.
Each old base ships its own OS-package CVE backlog, feeding Sections 4 and 5.

### 2.6 javax vs jakarta namespace split

```text
$ grep -rn --include='*.java' '^import javax\.' . | wc -l
9436

$ grep -rn --include='*.java' '^import jakarta\.' . | wc -l
1770
```

**Why it's a problem:** 9,436 legacy `javax.*` imports against 1,770
`jakarta.*` shows the estate is mid-migration and mostly still on the old
namespace, which pins services to older Spring/servlet generations and their
CVEs.

---

## 3. Secrets Detection (Gitleaks)

### 3.1 Full-tree secret scan

```text
$ gitleaks detect --source . --no-git --redact --report-path /tmp/gitleaks-report.json
INF scan completed in 27s
WRN leaks found: 332
```

### 3.2 Findings by rule and by repository

```text
$ python3 -c "<parse /tmp/gitleaks-report.json>"
Total: 332
  generic-api-key: 245
  square-access-token: 30
  jwt: 26
  private-key: 14
  sendgrid-api-token: 8
  github-pat: 7
  microsoft-teams-webhook: 2
-- by repo --
  IntakeCollectionsWorkflow-main: 103
  AttorneyPortal-main: 38
  azure-extmgmt-helm-master: 30
  RespondentPortal-ims-aks: 24
  ContentGeneratorWebService-ims-aks: 18
  ImsNXG-NG-ims-aks-test: 18
  EmailWebService-ims-aks-test: 16
  alfresco-content-services-helm-master: 16
  SearchDataWebService-ims-aks-test-es8: 12
  AuthorizationService-ims-aks: 10
```

**Why it's a problem:** 332 secrets committed to source control, including 14
private keys and live API tokens (SendGrid, Square, GitHub PAT) and a Teams
webhook. Each grants standing access until rotated, and source history retains
it after deletion. Most urgent finding. Runbook P0-01 through P0-10.

### 3.3 Manual credential pattern scan

```text
$ grep -rn --include='*.properties' --include='*.yml' --include='*.yaml' --include='*.env' \
    -iE 'password\s*[:=]\s*[A-Za-z0-9+/]{6,}' . | grep -vi 'changeme\|example\|placeholder' | wc -l
193
```

**Why it's a problem:** 193 password assignments survive placeholder filtering,
confirming credentials are embedded in config rather than injected at runtime.
One of these is `app.oauth.password=password123` (Section 10).

---

## 4. Vulnerability Scanning (Trivy)

### 4.1 Filesystem scan, CRITICAL and HIGH

```text
$ trivy fs --severity CRITICAL,HIGH --format json --quiet -o /tmp/trivy-report.json .
$ python3 -c "<parse /tmp/trivy-report.json>"
CRITICAL unique: 12 | HIGH findings: 181
CVE-2019-17495 | io.springfox:springfox-swagger-ui 2.9.2
CVE-2020-14343 | PyYAML 5.3.1
CVE-2022-22965 | org.springframework.boot:spring-boot-starter-web 2.2.4.RELEASE
CVE-2025-54988 | org.apache.tika:tika-parsers 1.24.1
CVE-2025-66516 | org.apache.tika:tika-core 1.28.5
CVE-2025-66516 | org.apache.tika:tika-parsers 1.24.1
CVE-2026-25896 | fast-xml-parser 4.4.1
CVE-2026-25896 | fast-xml-parser 4.5.0
CVE-2026-27699 | basic-ftp 5.1.0
CVE-2026-28292 | simple-git 3.16.0
CVE-2026-31938 | jspdf 4.0.0
CVE-2026-41242 | protobufjs 7.5.4
```

**Why it's a problem:** CVE-2022-22965 (Spring4Shell) is a weaponized remote
code execution flaw against a reachable Spring Boot service, with public exploit
code. Alongside the other CRITICAL and 181 HIGH package findings, the estate is
exposed to attacks available today. Runbook Phase 1.

---

## 5. Software Composition Analysis (Grype)

### 5.1 Directory scan by severity

```text
$ grype dir:. --output json --file /tmp/grype-report.json
$ python3 -c "<parse /tmp/grype-report.json>"
Total: 752
  Critical: 43
  High: 335
  Medium: 336
  Low: 38
```

**Why it's a problem:** a second independent tool confirms the dependency-CVE
picture at higher volume: 43 Critical and 335 High. 378 Critical/High findings
is a continuous-monitoring failure under FISMA and EO 14028. Runbook Phase 1.

---

## 6. Code-Level Security Analysis

### 6.1 Java deserialization (RCE surface)

```text
$ grep -rn --include='*.java' 'ObjectInputStream\|readObject()' . | wc -l
13

$ grep -rn --include='*.java' 'XStream\|xstream' . | wc -l
14

$ grep -rn --include='*.java' 'enableDefaultTyping\|@JsonTypeInfo.*As.CLASS' . | wc -l
0
```

**Why it's a problem:** 13 native-deserialization sites and 14 XStream usages
are classic RCE gadgets when fed untrusted input; each needs manual source
review. The Jackson default-typing result of 0 is the one clean outcome.

### 6.2 XML External Entity (XXE)

```text
$ grep -rn --include='*.java' 'DocumentBuilderFactory\|SAXParserFactory\|XMLInputFactory\|TransformerFactory' . | wc -l
42

$ grep -rn --include='*.java' 'setFeature.*disallow-doctype-decl\|setFeature.*external-general-entities' . | wc -l
0
```

**Why it's a problem:** 42 XML parsers, 0 hardening calls. Default JAXP settings
in older versions process external entities and DOCTYPE, enabling file
disclosure, SSRF, and DoS from crafted XML. Mechanical fix applied 42 times.

### 6.3 Authentication and authorization gaps

```text
$ grep -rn --include='*.java' '@PreAuthorize\|@Secured\|@RolesAllowed' . | wc -l
259

$ grep -rn --include='*.java' 'permitAll\|anyRequest.*permitAll' . | wc -l
46

$ grep -rn --include='*.java' 'CrossOrigin.*"\*"\|allowedOrigins.*List.of.*"\*"' . | wc -l
8

$ grep -rn --include='*.java' 'csrf.*disable\|csrf()\.disable' . | wc -l
25
```

**Why it's a problem:** only 259 of 1,177 endpoints (2.2) carry a method-level
authorization annotation, leaving 918 without one. 46 `permitAll` declarations
open routes outright, CORS wildcards allow any origin (see correction below),
and CSRF is disabled at 25 sites across 8 browser-facing services. This is the
broken-access-control core. Runbook P0-05 (CORS), P0-11 (CSRF), Phase 2
(per-endpoint authz).

**Correction (CORS count).** The single combined pattern above returned 8
because it matched the annotation form `@CrossOrigin(...)` but missed the
config form `setAllowedOrigins(List.of("*"))`. Run as two patterns, the wildcard
appears in **five services**, not the four the single pattern implied:

```text
$ sed -n '75p' FederalHearings-ims-aks/.../config/SecurityConfig.java
        configuration.setAllowedOrigins(List.of("*"));     # missed by the combined pattern
$ sed -n '45p' EmployerWebService-.../EmployerElasticResource.java
@CrossOrigin(origins = "*")
$ sed -n '39p' SearchDataWebService-.../HearingSearchResource.java
@CrossOrigin("*")
$ sed -n '56p' ECMService-.../ContentManagementResource.java
@CrossOrigin(origins = "*")
$ sed -n '31p' AzureAdService-.../AzureAdResource.java
@CrossOrigin("*")
```

The five services are FederalHearings, EmployerWebService, SearchDataWebService,
ECMService, and AzureAdService. Runbook P0-05 already lists all five correctly;
this count line was the under-report. Lesson: scan annotation-style and
config-style CORS separately. See `ARC_Phase0_Verification_Audit_2026-06-10.md`.

### 6.4 Input validation

```text
$ grep -rn --include='*.java' '@RequestParam' . | wc -l
595

$ grep -rn --include='*.java' '@RequestParam.*@Valid\|@Validated.*@RequestParam' . | wc -l
2

$ grep -rn --include='*.java' '@PathVariable' . | wc -l
945

$ grep -rn --include='*.java' '@RequestBody' . | wc -l
299

$ grep -rn --include='*.java' '@Valid.*@RequestBody\|@RequestBody.*@Valid' . | wc -l
251
```

**Why it's a problem:** 595 request params with only 2 validated, and 945 path
variables with no validation pattern, means almost all scalar inputs reach
business logic unchecked. Request bodies are the bright spot: 251 of 299 carry
`@Valid`. Unvalidated scalars feed the injection and traversal surfaces below.

### 6.5 SQL injection patterns

```text
$ grep -rn --include='*.java' 'createNativeQuery\|createQuery.*+' . | wc -l
1424
```

**Why it's a problem:** 1,424 native-query/string-built-query sites. This
over-counts (catches safe parameterized JPQL), so it is a review queue, not
1,424 injections. Any site concatenating a request value into native SQL is a
direct injection; triage the concatenation cases.

### 6.6 Broken cryptography

```text
$ grep -rn --include='*.java' 'PBEWithMD5AndDES\|DesEncrypter' . | wc -l
30

$ grep -rn --include='*.java' 'MD5\|getInstance.*MD5' . | wc -l
6

$ grep -rn --include='*.java' 'java.util.Random\b' . | wc -l
4
```

**Why it's a problem:** `PBEWithMD5AndDES` pairs a broken hash (MD5) with a
broken cipher (56-bit DES), 30 occurrences across two portals; data protected
this way should be treated as recoverable. The 6 raw-MD5 and 4
`java.util.Random` hits are weaker and need a quick context check. Runbook
Phase 2.

### 6.7 Security headers

```text
$ grep -rn --include='*.java' --include='*.properties' --include='*.yml' \
    'Content-Security-Policy\|X-Frame-Options\|Strict-Transport' . | wc -l
0
```

**Why it's a problem:** zero references to CSP, X-Frame-Options, or HSTS across
the estate. No service sets XSS containment, clickjacking, or TLS-downgrade
protection. Baseline gap. Runbook P0-12.

### 6.8 Session management

```text
$ grep -rn --include='*.xml' 'session-timeout' .
ImsNXG-master/ImsNXG-master/ImsNXG/WebContent/WEB-INF/web.xml:91:  <session-timeout>300</session-timeout>
ImsNXG-master/ImsNXG/WebContent/WEB-INF/web.xml:91:  <session-timeout>300</session-timeout>
DocumentGeneratorAdapter-master/WebContent/WEB-INF/web.xml:16:    <session-timeout>3</session-timeout>
FedSep-ims-aks-test/WebContent/WEB-INF/web.xml:99:  <session-timeout>180</session-timeout>
FedSep-ims-aks-test/FedSep-ims-aks-test/WebContent/WEB-INF/web.xml:99:  <session-timeout>180</session-timeout>
RespondentPortal-ims-aks/WebContent/WEB-INF/web.xml:16:    <session-timeout>300</session-timeout>
RespondentPortal-ims-aks/RespondentPortal-ims-aks/WebContent/WEB-INF/web.xml:16:    <session-timeout>300</session-timeout>
EEOCWebService-master/WebContent/WEB-INF/web.xml:30:    <session-timeout>5</session-timeout>
EEOCWebService-master/EEOCWebService-master/WebContent/WEB-INF/web.xml:30:    <session-timeout>5</session-timeout>

$ grep -rn --include='*.java' 'HttpSession\|getSession()' . | wc -l
176
```

**Why it's a problem:** ImsNXG and RespondentPortal set 300-minute (5-hour)
session timeouts. A 5-hour idle window on portals handling charge and PII data is
far outside NIST AC-12 / 800-63 guidance and widens hijacked-session and
unattended-workstation exposure. 176 ad-hoc `HttpSession` usages indicate no
single hardened mechanism. Runbook P0-06.

### 6.9 PII in logs

```text
$ grep -rn --include='*.java' -E 'log\.(info|debug|warn|error).*\b(email|ssn|phone|name)\b' . | wc -l
565
```

**Why it's a problem:** 565 log statements reference an identity field. Heavy
over-count (matches a variable named `name`), so a review list rather than 565
leaks. Any statement writing a real email/SSN/phone violates the platform
no-PII-in-logs rule and bypasses the masking pipeline. Runbook P0-13.

### 6.10 Exception handling

```text
$ grep -rn --include='*.java' 'catch\s*(\s*Exception\b' . | wc -l
1546

$ grep -rn --include='*.java' 'printStackTrace()' . | wc -l
590
```

**Why it's a problem:** 1,546 broad `catch (Exception)` blocks swallow specific
failures, against the platform standard. 590 `printStackTrace()` calls write
stack traces to stdout/stderr, leaking class names, paths, and SQL fragments and
bypassing masking. Information-disclosure plus code-quality at scale.

### 6.11 Command injection and path traversal

```text
$ grep -rn --include='*.java' 'Runtime.getRuntime().exec\|ProcessBuilder' . | wc -l
12

$ grep -rn --include='*.java' 'getRealPath\|new File.*request' . | wc -l
5
```

**Why it's a problem:** 12 process-execution sites and 5 request-driven
file-access sites. If any concatenates user input into the command or path, that
is command injection or path traversal. Low count, high per-instance severity:
confirm input construction at all 17.

### 6.12 SSRF surface

```text
$ grep -rn --include='*.java' 'RestTemplate\|WebClient\|HttpURLConnection\|OkHttpClient' . | wc -l
806
```

**Why it's a problem:** 806 outbound HTTP client usages. Where a destination URL
comes from user input without an allowlist, the service can be steered to
internal endpoints (cloud metadata, internal APIs) = SSRF. Surface-size signal:
URL allowlisting and metadata-endpoint blocking should be a standard control.

---

## 7. Section 508 / WCAG 2.1 AA Scanning

### 7.1 Images without alt text

```text
$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<img ' . | grep -v 'alt=' | wc -l
104
```

### 7.2 Documents missing lang attribute

```text
$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<html' . | grep -v 'lang=' | wc -l
300
```

### 7.3 Inline onclick handlers

```text
$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' 'onclick=' . | wc -l
863
```

### 7.4 Inputs vs labels

```text
$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<input ' . | wc -l
1006

$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<label' . | wc -l
2381
```

### 7.5 Tables vs header cells

```text
$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<table' . | wc -l
291

$ grep -rn --include='*.html' --include='*.jsp' --include='*.xhtml' '<th' . | wc -l
2243
```

**Why it's a problem:** 104 images without alt fail WCAG 1.1.1 (screen readers
announce nothing), 300 documents missing `lang` fail 3.1.1, and 863 inline
`onclick` handlers are the keyboard-access concern (2.1.1) when there is no
keyboard equivalent. The input/label and table/header ratios look healthy in
aggregate but say nothing about correct association, which needs per-page review.
508 is federal law; the JSP tier is not AA-remediable in place.

---

## 8. Codebase Age Analysis

### 8.1 Copyright year distribution

```text
$ grep -rn --include='*.java' --include='*.jsp' --include='*.xml' -i 'copyright.*20[0-9][0-9]' . | grep -oP '20[0-9]{2}' | sort | uniq -c
      2 2003
     10 2007
      5 2012
      5 2019
      1 2021
```

### 8.2 JSF / PrimeFaces footprint

```text
$ grep -rn --include='*.java' 'FacesContext\|ManagedBean\|SessionScoped' . | wc -l
2296

$ grep -rn --include='pom.xml' 'jboss-jsf-api' . | wc -l
4
```

**Why it's a problem:** copyright headers cluster in 2003 and 2007, dating the
oldest code to ~20 years. 2,296 JSF API usages and 4 poms pulling the JBoss JSF
API confirm a large JBoss/JSF-era stack tied to the JBoss base image (2.5).
This is the target of the JBoss-retirement track in runbook Phase 1.

---

## 9. Deployment Verification

### 9.1 Production secret-delivery script

```text
$ cat azure-extmgmt-prod-master/arc/create-secrets.sh | grep -oE '\-\-name [a-z0-9-]+' | sed 's/--name //' | head -30
arcdb-emluser-password
arcdb-s-admin-password
arcdb-s-ecm-password
arcdb-s-private-password
arcdb-s-tmplmgmt-password
ecm-alfresco-password
emldb-emluser-password
imsdb-report-user-password
imsdb-service-user-password
oit-application-mailbox-password
ews-sendgrid-api-key
authsvc-ecm-client-secret
authsvc-prepa-client-secret
authsvc-imsnxg-client-secret
authsvc-arcappuser-password
authsvc-publicportaluser-password
authsvc-rspdntportaluser-password
authsvc-foia-password
authsvc-iiggateway-password
fepagateway-rightnow-auth-code
authsvc-ecm-oauth-header
authsvc-private-key
```

### 9.2 Production Helm configs

```text
$ find azure-extmgmt-helm-master/configs/prod/ -name '*.yaml' | sort
azure-extmgmt-helm-master/configs/prod/custom-nxg-backend.yaml
azure-extmgmt-helm-master/configs/prod/eeo1-ext.yaml
azure-extmgmt-helm-master/configs/prod/eeo1-internal-ingress.yaml
azure-extmgmt-helm-master/configs/prod/eml-prod-config.yaml
azure-extmgmt-helm-master/configs/prod/eml-prod-secrets.yaml
azure-extmgmt-helm-master/configs/prod/ims-prod-config.yaml
azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml
azure-extmgmt-helm-master/configs/prod/prod-birt-reports-storage.yaml
azure-extmgmt-helm-master/configs/prod/rsp-redirect.yaml
```

### 9.3 Production image references

```text
$ grep -rn --include='*.yaml' 'image:.*eus1' azure-extmgmt-helm-master/ azure-extmgmt-prod-master/ | wc -l
6
```

**Why it's a problem:** the production secret list names the database accounts,
service-to-service client secrets, mailbox password, private key, and SendGrid
key the live system depends on. Read with Section 3, this maps exactly which
credentials are production-impacting and must rotate. The 9 prod Helm files
(including committed `*-secrets.yaml`) and 6 `eus1` image references scope the
CORS/CSRF/CVE findings to live-exposure services, not dormant repos.

---

## 10. Line-Number Verification (4-Loop Pass)

### 10.1 Cited file and line references

```text
$ sed -n '75p' FederalHearings-ims-aks/src/main/resources/application.properties
app.oauth.password=password123

$ sed -n '45p' EmployerWebService-ims-aks-test/src/main/java/gov/eeoc/employer/ws/resource/es/EmployerElasticResource.java
@CrossOrigin(origins = "*")

$ sed -n '56p' IntakeCollectionsService-main/src/main/java/gov/eeoc/foi/config/SecurityConfig.java
            .csrf(csrf -> csrf.disable())
```

**Why it's a problem:** the cited lines resolve to exactly the defects claimed:
a hardcoded OAuth password (`password123`), a wildcard CORS annotation, and an
explicit CSRF-disable. The audit's file-and-line citations are accurate, and the
abstract counts above have concrete code behind them.

---

## Findings Summary

| # | Command area | Verbatim headline | Severity | Runbook |
|---|---|---|---|---|
| 3 | Secrets (gitleaks) | leaks found: 332 (14 private keys) | CRITICAL | P0-01..P0-10 |
| 4 | Trivy CVEs | 12 unique CRITICAL / 181 HIGH, incl. Spring4Shell | CRITICAL | Phase 1 |
| 5 | Grype SCA | Critical 43 / High 335 | CRITICAL | Phase 1 |
| 6.1 | Deserialization | 13 native + 14 XStream | HIGH | Phase 2 |
| 6.2 | XXE | 42 parsers, 0 hardened | HIGH | Phase 2 |
| 6.3 | AuthZ / CORS / CSRF | 259 of 1177 annotated, 8 CORS `*`, 25 CSRF off | CRITICAL | P0-05, P0-11, Phase 2 |
| 6.4 | Input validation | 595 params, 2 validated | HIGH | Phase 2 |
| 6.6 | Crypto | 30 PBEWithMD5AndDES | CRITICAL | Phase 2 |
| 6.7 | Security headers | 0 across estate | HIGH | P0-12 |
| 6.8 | Sessions | two 300-min timeouts | MEDIUM | P0-06 |
| 6.9 | PII logging | 565 candidate sites (review list) | HIGH | P0-13 |
| 6.10 | Exceptions | 1546 broad catch, 590 printStackTrace | MEDIUM | Phase 2 |
| 7 | 508 / WCAG | 104 no-alt, 300 no-lang, 863 onclick | HIGH | Phase 3 |
| 8 | Age | oldest ~2003, 2296 JSF usages | context | Phase 1 |

Review-queue counts (6.5 SQL, 6.9 PII, 6.12 SSRF) carry known false positives
and require manual triage before being cited as defects. All other counts are
direct command output.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Verbatim command run against eeoc-arc-payloads; output captured per command |

Source command set: `ARC_Audit_Commands_Reference.md`.
Cross-references: `ARC_Modernization_Audit_and_Phased_Plan.md`,
`ARC_Developer_Remediation_Runbook.md`.
