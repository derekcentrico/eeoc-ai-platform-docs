# ARC System Modernization Audit and Phased Remediation Plan
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

## Executive Brief

The ARC system is the operational backbone of the EEOC's charge management
mission. It processes discrimination complaints, manages federal hearings,
facilitates FEPA coordination, and handles respondent and attorney portal
interactions. It is not optional infrastructure - it is the mechanism through
which the agency fulfills its statutory mandate.

This document presents the results of a full security, accessibility, and
architecture audit of the ARC system. The ARC GitHub organization contains
85 repositories. Source code was provided and audited for 48 of them.
GitHub activity data classifies the remaining 37, of which 42 total repos
across the organization have not been updated since 2024 or earlier, with
the oldest dating to May 2014. The findings require executive attention.

**The immediate problem:** Production database passwords, private cryptographic
keys, Azure Container Registry credentials, SendGrid API tokens, and GitHub
personal access tokens are committed in plaintext to source code repositories.
Any current or former developer, contractor, or anyone with repository access
can read production credentials. This is not a theoretical vulnerability - the
credentials are there now, base64-encoded in Kubernetes manifests and embedded
in Java properties files, recoverable in seconds.

**The compliance exposure:** Automated scanning identified **332 leaked secrets**
(gitleaks; 228 in confirmed-live repos), **719 known vulnerabilities** in
third-party dependencies (Grype, including 43 Critical and 307 High severity),
and an additional **170 CRITICAL/HIGH vulnerabilities** confirmed by Trivy (152
in live repos). Cross-referencing against the production Helm deployment
manifests and the `create-secrets.sh` provisioning script confirms that the
worst findings - production credentials in source, broken DES encryption,
CORS wildcards, missing authorization, XXE-unprotected parsers - are all in
services confirmed running in production. Ten of the 23 Java services run on
Spring Boot
versions that reached end of life between 2020 and 2024 - vendor security patches
do not exist for these versions. Five services run on JBoss EAP 7.4, which Red
Hat ended support for in June 2024.

**The federal mandate gap:** Executive Order 14028 (Improving the Nation's
Cybersecurity, May 2021) requires federal agencies to adopt zero trust
architecture, secure software supply chains, and implement endpoint detection
and response. OMB M-22-09 sets specific zero trust implementation deadlines.
FISMA requires continuous monitoring of known vulnerabilities. Section 508 of
the Rehabilitation Act requires accessibility compliance. This audit found
**863 keyboard-inaccessible UI elements**, **300 HTML pages without language
declarations**, and **42 XML parsers with zero XXE protections**. The ARC system
is not in compliance with any of these mandates in its current state.

**The age of the problem:** Copyright notices in the source code date to 2003
and 2007. Core dependencies include Apache Axis 1.4 (released April 2006),
Log4j 1.2.16 (released December 2010), Logback 1.0.7 (released July 2012),
and Apache POI 3.10.1 (released February 2014). The encryption implementation
used for passwords in FedSep and the Respondent Portal uses PBEWithMD5AndDES,
an algorithm broken since the late 1990s, with a hardcoded salt and 19
iterations. The system carries **10 to 20 years of accumulated technical debt**,
with the oldest components predating the iPhone.

**What we are asking for:** A phased, 18-month remediation plan that prioritizes
by risk. Phase 0 (immediate, 4 weeks) rotates every exposed credential, removes
secrets from source control, and closes the most dangerous configuration gaps.
Phases 1 through 4 progressively modernize the runtime stack, harden security
controls, achieve accessibility compliance, and prepare the system for
integration with the EEOC's Data and AI Enterprise System (DAES). The alternative - continuing
to operate the system as-is - means operating federal infrastructure with known
exploitable vulnerabilities, leaked production credentials, and broken
encryption, in a posture that will not survive scrutiny from OIG, a FISMA
audit, or a security incident.

---

## Table of Contents

1. [Scope and Methodology](#1-scope-and-methodology)
2. [Codebase Age Analysis](#2-codebase-age-analysis)
3. [Security Findings - Tool-Verified](#3-security-findings---tool-verified)
4. [Security Findings - Code-Level Analysis](#4-security-findings---code-level-analysis)
5. [Section 508 / WCAG 2.1 AA Compliance](#5-section-508--wcag-21-aa-compliance)
6. [Architecture Assessment](#6-architecture-assessment)
7. [Federal Compliance Gap Analysis](#7-federal-compliance-gap-analysis)
8. [Phased Remediation Plan](#8-phased-remediation-plan)
9. [Risk Matrix](#9-risk-matrix)
10. [Success Criteria](#10-success-criteria)
11. [Attestation and Document Control](#11-attestation-and-document-control)

---

## 1. Scope and Methodology

### 1.1 What Was Audited

| **Attribute** | **Value** |
|---|---|
| **Total ARC repositories (GitHub)** | 85 |
| **Repositories audited (source code provided)** | 48 |
| **Repositories not audited (no source provided)** | 37 (see Section 1.3 for full inventory) |
| **Total source files (audited repos)** | 30,129 (excluding `node_modules`, `.git`, `target`, build artifacts) |
| **Java source files** | 6,454 |
| **TypeScript/JavaScript source files** | 4,918 |
| **JSP/XHTML legacy UI templates** | 407 |
| **HTML files** | 619 |
| **API endpoints** | 1,177 across 19 services |
| **Dockerfiles** | 53 |
| **Helm charts** | 28 |
| **Configuration/properties files** | 353 |

### 1.2 Tools Used

| Tool | Version | Purpose | Result |
|---|---|---|---|
| **Gitleaks** | Current | Secrets detection across all source files | **332 findings** |
| **Trivy** | Current | Filesystem vulnerability scanning (CRITICAL/HIGH) | **170 findings** (17 Critical, 153 High) |
| **Grype** | Current (DB 3 weeks stale) | Software composition analysis | **719 findings** (43 Critical, 307 High, 332 Medium, 37 Low) |
| **Manual grep analysis** | n/a | Code-level vulnerability patterns (SQL injection, deserialization, XXE, auth bypass, input validation, crypto, CORS, CSRF, session management) | **Extensive findings documented in Section 4** |

All scans were run on 28-29 May 2026. Grype's vulnerability database was three
weeks old at scan time; re-running against a current database returns somewhat
higher High and Medium totals as new advisories are published, while the
Critical counts (Grype 43, Trivy 17) are stable. The Black Duck report
previously cited 2,000+ vulnerabilities; this independent audit corroborates
that order of magnitude and identifies the root causes.

### 1.3 Full Repository Inventory and Activity Classification

The ARC GitHub organization contains **85 repositories**. This audit examined
48 of them (the repos for which source code was provided). GitHub activity
data as of May 2026 allows us to classify all 85 by current status.

Deployment status for the audited repos was further verified by
cross-referencing the production `create-secrets.sh` provisioning script,
the Helm production configs in `azure-extmgmt-helm-master/configs/prod/`,
and the Terraform infrastructure in `azure-extmgmt-prod-master/`.

#### Tier 1: Active Development (updated within 30 days) - 23 repos

All of these are confirmed active and were included in this audit.

| Repository | Language | Last Updated | Branches | Contributors |
|---|---|---|---|---|
| ImsNXG-NG | TypeScript | Hours ago | 3 | 7 |
| FederalHearings | Java | Hours ago | 19 | 4 |
| FedSep | Java | Hours ago | 5 | 5 |
| AuthorizationService | Java | Hours ago | 11 | 3 |
| ContentGeneratorWebService | Java | Hours ago | 0 | 3 |
| TemplateMangementWebService | Java | Hours ago | 10 | 11 |
| SearchDataWebService | Java | Hours ago | 0 | 0 |
| LitigationWebService | Java | Hours ago | 10 | 6 |
| PrEPAWebService | Java | Hours ago | 21 | 15 |
| IntakeCollectionsUI | TypeScript | Yesterday | 10 | 20 |
| FepaGateway | Java | 2 days ago | 10 | 2 |
| EmailWebService | Java | 2 days ago | 10 | 7 |
| ECMService | Java | 3 days ago | 11 | 12 |
| IntakeCollectionsWorkflow | Python | 3 days ago | 0 | 0 |
| ADR_PORTAL | Python | 4 days ago | 0 | 1 |
| AttorneyPortal | JavaScript | Last week | 0 | 0 |
| azure-extmgmt-ansible | Perl | Last week | 0 | 6 |
| FederalWebService | Java | Last week | 10 | 3 |
| ImsNXG | Java | Last week | 0 | 1 |
| EEOCWebService | Java | Last week | 0 | 1 |
| DocumentGeneratorAdapter | Java | Last week | 0 | 1 |
| IntakeCollectionsService | Java | Last week | 0 | 0 |
| Database_Release_Scripts | (empty) | Hours ago | 0 | 0 |

Note: Database_Release_Scripts is an empty repository (no source content).
ImsNXG and EEOCWebService show minimal branch/contributor activity but are
actively maintained and remain in production.

#### Tier 2: Recently Active (updated 2-8 weeks ago) - 9 repos

| Repository | Language | Last Updated | Status |
|---|---|---|---|
| FedSep-NG | TypeScript | 2 weeks ago | NG rewrite of FedSep |
| UserManagementWebService | Java | 2 weeks ago | Active service |
| AzureAdService | Java | 2 weeks ago | Active service |
| azure-extmgmt-prod | HCL | 3 weeks ago | Production infrastructure |
| RespondentPortal | Java | Apr 15 | Active service (legacy, needs replacement) |
| EmployerWebService | Java | Apr 15 | Active service |
| PublicPortalWorkflow | (empty) | Apr 10 | Empty repository (no source content) |
| azure-extmgmt-helm | Shell | Apr 7 | Helm charts for all environments |
| AT_ARC_UI | Java | Apr 2 | UI automation test suite |

#### Tier 3: Maintenance Mode (updated Q1 2026) - 3 repos

| Repository | Language | Last Updated | Status |
|---|---|---|---|
| AT_ScenarioRunner | Java | Mar 30 | API test runner |
| Utilities | Java | Feb 26 | Shared Java library |
| azure-extmgmt-er | HCL | Jan 22 | ExpressRoute configuration |

#### Tier 4: Stale (updated in 2025) - 8 repos

| Repository | Language | Last Updated | Status | Audited? |
|---|---|---|---|---|
| azure-extmgmt-design | Shell | Jul 2025 | Architecture design artifacts | Yes |
| UIComponentLibrary | (internal) | Jun 2025 | Empty repository, no source content | No (empty) |
| alfresco-content-services-helm | Smarty | Jun 2025 | Alfresco Helm charts | Yes |
| BIRTReports | HTML | May 2025 | Report definitions (1,732 files) | Yes |
| FED_MD715_TEST_Utility | Java | Apr 2025 | Unused, MD-715 process discontinued per Administration | No (unused) |
| FMW_Repository | (none) | Mar 2025 | Empty repository, no source content | No (empty) |
| azure-extmgmt-test | HCL | Jan 2025 | **Already archived in GitHub** | Yes |
| azure-extmgmt-uat | HCL | Jan 2025 | **Already archived in GitHub** | Yes |

#### Tier 5: Dormant (not updated since 2024 or earlier) - 42 repos

These repos have not received a commit in over 18 months. Many date back
5 to 12 years. They represent the largest archival opportunity and the
highest risk for accidental code reuse.

| Last Updated | Repos | Notable |
|---|---|---|
| 2024 | birtweb, PostmanUtilities, jboss-docker | JBoss base image repo, last touched Feb 2024 |
| 2023 | alfresco-share-docker, alfresco-content-repository-docker, alfresco-bulk-import, MessagingPoc | MessagingPoc contains Spring4Shell CVE |
| 2022 | AccountCertification, EmailWebServiceNG, AT_ARC_REGRESSION, SendGrid_Email_templates, alfresco-devops-runner, ARC_EmailWebService, ARC_UI, SecurityServices, SeleniumTestScripts | EmailWebServiceNG superseded, contains deserialization vuln |
| 2021 | alfresco-azurerm-aks, alfresco-azurerm-terraform, ImsDataWebService, IigGatewayAzureFunction, TDCS, PerformanceTestScripts, alfresco-terraform-aks-devops, AT_UserMgmtWS, AT_SearchDataWS, AT_PrEPAWebService, AT_FepaGateway, AT_ECMService | 12 repos, mostly abandoned automation tests |
| 2020 | EEOCPhoneDirectory (ASP), STANDALONE_SPRINGBOOT | ASP.NET phone directory, 6 years untouched |
| 2019 | LdapWebService, EmployerDbIdAssigner | LDAP service, 7 years untouched |
| 2016-2017 | NVS, CTS, eVersity, NVS_WebServices | Notation Vote System (2017), Correspondence Tracking (2016), eVersity (2016) |
| 2014-2015 | ImsServiceClient, TDCS-FILE_EXPORT, OFO, Maintainer, DMS | **DMS last updated May 2014 - 12 years old** |

Of these 42 dormant repos, 32 were not included in this audit because no
source code was provided. The 37 total unaudited repos across all tiers
break down as follows: 3 are confirmed empty or unused (UIComponentLibrary,
FED_MD715_TEST_Utility, FMW_Repository), 2 are empty active
shells with no source content (Database_Release_Scripts,
PublicPortalWorkflow), and the remaining 32 are dormant Tier 5 repos
already on the archival list. **This means every active repository that
contains source code was covered by this audit. There are no coverage
gaps in the active portfolio.**

The 32 unaudited dormant repos likely contain the same classes of
vulnerabilities found in the audited repos (hardcoded credentials, EOL
dependencies, broken crypto patterns), and should be scanned before archival.

#### Impact on Vulnerability Counts

| Metric | Total (48 audited) | In Active Repos (Tiers 1-3) | In Stale/Dormant Repos (Tiers 4-5) |
|---|---|---|---|
| Gitleaks secrets | 332 | 228 | 104 (IntakeCollectionsWorkflow: 103, PostmanUtilities: 1) |
| Trivy CRITICAL/HIGH | 170 | 152 | 18 (alfresco-bulk-import: 14, MessagingPoc: 2, AT_ScenarioRunner: 2) |
| Grype (all severities) | 719 | ~710 | ~9 (MessagingPoc) |

**Every code-level finding in Section 4** (DES crypto, XXE, deserialization,
CORS wildcard, auth gaps, SQL injection, input validation, security headers)
**is in an active repo (Tier 1 or 2).** The stale and dormant repos reduce the
headline numbers slightly but do not change the severity assessment.

Secrets committed to dormant repos are still a risk. Anyone with repository
access can read them. If any credential is shared with a live service, the
exposure is real regardless of whether the repo that contains it is deployed.

#### Tier breakdown

| Tier | Repos | In Audit | Unaudited Status | Recommendation |
|---|---|---|---|---|
| 1: Active Development | 23 | 22 of 23 | 1 empty (Database_Release_Scripts) | Full remediation per this plan |
| 2: Recently Active | 9 | 8 of 9 | 1 empty (PublicPortalWorkflow) | Full remediation per this plan |
| 3: Maintenance Mode | 3 | 3 of 3 | n/a | Remediate or archive based on usage |
| 4: Stale (2025) | 8 | 5 of 8 | 2 empty (UIComponentLibrary, FMW_Repository), 1 unused (MD-715 discontinued) | Archive per Section 4.6 policy |
| 5: Dormant (pre-2025) | 42 | 10 of 42 | 32 unaudited dormant | **Archive immediately per Section 4.6 policy** |
| **Total** | **85** | **48** | **0 active coverage gaps** | |

### 1.4 Repository Classification

#### Core Business Services (8 repos - the mission-critical tier)

| Repository | Java | Spring Boot | Endpoints | Purpose |
|---|---|---|---|---|
| EEOCWebService-master | 11 | JBoss 7.4 (EOL) | 226 | Main charge management API |
| PrEPAWebService-ims-aks-test | 11 | 2.4.1 (EOL) | 330 | Pre-complaint processing - largest endpoint surface |
| FederalHearings-ims-aks | 25 | 4.0.6 | 261 | Federal sector hearings management |
| FederalWebService-ims-aks | 25 | 4.0.6 | 96 | Federal sector web services |
| FedSep-ims-aks-test | 11 | JBoss 7.4 (EOL) | 166 | Federal sector EEO processing |
| ImsNXG-master | 11 | JBoss 7.4 (EOL) | 196 | IMS case management |
| FepaGateway-ims-aks | 17 | 3.2.1 (EOL) | 128 | FEPA state/local agency gateway |
| LitigationWebService-main | 11 | 2.6.5 (EOL) | minimal | Litigation tracking |

#### Frontend/Portal Applications (6 repos)

| Repository | Framework | Assessment |
|---|---|---|
| AttorneyPortal-main | Next.js 14 / USWDS 3.7 / React 18 | Modern stack - security and 508 audit needed |
| ImsNXG-NG-ims-aks-test | Angular 16.2 (EOL) / Material 16 | NG rewrite - 72 Trivy vulns in dependencies |
| FedSep-NG-ims-aks-test | Angular 16.2 (EOL) | NG rewrite - early stage |
| IntakeCollectionsUI-main | Angular 19 | Current framework version |
| RespondentPortal-ims-aks | Java 11 / JBoss / JSP | Legacy - broken DES crypto, 24 JSP pages |
| ADR_PORTAL-main | Python 3.13 / Flask | DAES platform application (our code) |

#### Support Services (9 repos)

| Repository | Java | Spring Boot | Critical Finding |
|---|---|---|---|
| AuthorizationService-ims-aks | 11 | 2.3.2 (EOL) | **14 private keys committed to source** |
| UserManagementWebService-master | 11 | 2.2.4 (EOL) | Deprecated Docker images |
| AzureAdService-main | 11 | 2.3.6 (EOL) | CORS wildcard `*` on controller |
| EmailWebService-ims-aks-test | 25 | 4.0.6 | 8 SendGrid API tokens in properties |
| SearchDataWebService-ims-aks-test-es8 | 21 | n/a | CORS wildcard `*` on controller |
| ECMService-ims-aks-test | 25 | 4.0.6 | CORS wildcard `*` on controller |
| ContentGeneratorWebService-ims-aks | 25 | 4.0.6 | 26 JWTs in test files |
| TemplateMangementWebService-ims-aks-test | 25 | 4.0.6 | (modernized) |
| DocumentGeneratorAdapter-master | 11 | JBoss 7.4 (EOL) | Path traversal via `getRealPath()` |

#### Infrastructure (14 repos), Test Automation (7 repos)

Infrastructure repos (azure-extmgmt-*, alfresco-*, jboss-docker, birtweb) manage
AKS clusters, Helm charts, and Ansible automation. 30 gitleaks findings in the
Helm configs alone. Test/utility repos include AT_ARC_UI (Selenium), AT_ScenarioRunner,
Postman collections, BIRT reports (1,732 files), SendGrid templates, and shared
utilities.

The functional groupings above cover the audited repositories that contain
substantive source; a few audited infrastructure and already-archived repos are
inventoried in Section 1.3 but not re-listed by function here.

**Service-count conventions used in this report:** "23 Java services" refers to
all Java backend services across the audited repos; "19 services" refers to the
deployable Spring Boot and web services assessed for security-header, rate-limiting,
and OpenAPI coverage (JBoss-only modules, shared libraries, and test/automation
projects are excluded from the 19).

---

## 2. Codebase Age Analysis

The ARC system did not accumulate its current state overnight. Multiple
independent evidence streams allow us to date the architectural layers.

### 2.1 Dependency Archaeology

| Dependency | Version in ARC | Original Release Date | Age |
|---|---|---|---|
| Apache Axis | 1.4 | April 2006 | **20 years** |
| wss4j | 1.5.4 | 2008 | **18 years** |
| Log4j | 1.2.16 | December 2010 | **16 years** |
| Logback | 1.0.7 | July 2012 | **14 years** |
| Apache POI | 3.10.1 | February 2014 | **12 years** |
| XStream | 1.4.9 | March 2016 | **10 years** |
| Apache Tika | 1.5 | October 2013 | **13 years** |
| GSON | 2.8.2 | September 2017 | **9 years** |
| SnakeYAML | 1.18 | June 2016 | **10 years** |
| PrimeFaces | 8.x (FedSep) | ~2020 | **6 years** |
| JSF API | 2.3 (JBoss-provided) | April 2017 | **9 years** |

### 2.2 Source Code Dating

| Evidence | Date Range | Implication |
|---|---|---|
| Copyright notices in Java files | **2003, 2007, 2012, 2019** | Oldest code predates any current Java version |
| `javax.*` imports | **9,436** across codebase | Pre-2020 Java EE namespace (vs. 1,770 `jakarta.*`) |
| Password strings: `prepa2019`, `admindev2019` | 2019 | Credentials created ~2019, never rotated |
| Password string: `arcdev@2024!` | 2024 | Most recent credential creation |
| Spring Boot 2.1.5.RELEASE | Released May 2019 | EmailWebServiceNG last touched ~2019 |
| Spring Boot 2.2.4.RELEASE | Released Feb 2020 | UserMgmt, MessagingPoc last touched ~2020 |
| JBoss EAP 7.4 base image (7.4.14) | Released 2023 | Container was rebased, but app code unchanged |
| PBEWithMD5AndDES encryption | Broken since ~1998 | Algorithm was already legacy when implemented |

### 2.3 Architecture Eras

The codebase shows three distinct eras of development:

**Era 1 (2005-2015): Original J2EE/JBoss Foundation**
- Java EE servlets, JSF 2.x, JSP, XHTML templates
- JBoss application server deployments as WAR files
- PBEWithMD5AndDES encryption with hardcoded salts
- Apache Axis 1.4 SOAP services, XStream serialization
- Oracle database with native SQL queries via string concatenation
- No test coverage
- Repos: EEOCWebService, ImsNXG, FedSep, RespondentPortal, DocumentGeneratorAdapter

**Era 2 (2018-2022): Spring Boot Migration (Partial)**
- Spring Boot 2.x microservices alongside JBoss monoliths
- OAuth2 authentication via deprecated `@EnableAuthorizationServer`
- Docker containerization on `openjdk:11-jre-slim`
- Kubernetes deployment via Helm charts
- Some test files added (2-8 per service)
- Repos: PrEPAWebService, AuthorizationService, AzureAdService, UserMgmtWS,
  EmployerWS, EmailWebServiceNG, LitigationWS, MessagingPoc

**Era 3 (2023-2026): Modern Services (Selective)**
- Spring Boot 4.0.6 on Java 25 with Eclipse Temurin
- Angular 16-19 frontend rewrites (ImsNXG-NG, FedSep-NG, IntakeCollectionsUI)
- Next.js/USWDS (AttorneyPortal)
- JWT-based OAuth2 resource server security
- Repos: FederalHearings, FederalWebService, ContentGenerator, ECMService,
  EmailWebService (modernized), TemplateMgmt, FepaGateway, IntakeCollections

**The problem is that all three eras coexist in production.** The system did not
complete any migration - it started new services on modern stacks while leaving
the old services running. The result is a runtime environment that spans 20
years of Java ecosystem evolution, with each era carrying its own class of
vulnerabilities.

---

## 3. Security Findings - Tool-Verified

### 3.1 CRITICAL: Secrets in Source Control (332 Gitleaks Findings)

Gitleaks detected 332 instances of secrets committed to source code across 25
of the 48 repositories.

| Secret Type | Count | Risk |
|---|---|---|
| Generic API keys | 245 | Varies - includes database connection strings, service tokens, config values |
| Square access tokens | 30 | Third-party payment service credentials |
| JSON Web Tokens | 26 | Signed auth tokens - can be replayed if not expired |
| Private cryptographic keys | 14 | **CRITICAL** - enables impersonation, token forging, data decryption |
| SendGrid API tokens | 8 | Email service credentials - enables sending as EEOC |
| GitHub Personal Access Tokens | 7 | Repository access - lateral movement vector |
| Microsoft Teams webhooks | 2 | Internal communication channel injection |

**Worst offenders by repository:**

| Repository | Findings | Key Secret Types |
|---|---|---|
| IntakeCollectionsWorkflow-main | 103 | API keys, GitHub PATs in recording files |
| AttorneyPortal-main | 38 | API keys embedded in frontend code |
| azure-extmgmt-helm-master | 30 | Production DB passwords, ACR tokens, App Insights keys, Storage keys |
| RespondentPortal-ims-aks | 24 | API keys |
| ContentGeneratorWebService-ims-aks | 18 | JWTs in test files |
| ImsNXG-NG-ims-aks-test | 18 | API keys |
| EmailWebService-ims-aks-test | 16 | SendGrid tokens, database passwords |
| alfresco-content-services-helm-master | 16 | Helm deployment secrets |
| AuthorizationService-ims-aks | 10 | **14 private keys** across DEV/TEST/UAT/TRAIN environments |

**The AuthorizationService finding is the most dangerous:** 14 private keys for
the OAuth2 authorization server are committed across environment-specific YAML
files. These keys sign and validate every authentication token in the system.
An attacker with any one of these keys can forge valid authentication tokens for
any user, including administrative accounts.

**Production Helm secrets (decoded from base64):**

The file `azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml` contains:
- `IMS_DATABASE_SERVICE_USER_PASSWORD` - production Oracle database service account
- `IMS_DATABASE_REPORT_USER_PASSWORD` - production report database account
- `IMS_DATABASE_FEDSEP_USER_PASSWORD` - production FedSep database account
- `FEDSEP_AWSDB_PASSWORD` - FedSep AWS database password
- `FEDSEP_BODDB_PASSWORD` - FedSep BOD database password
- `FEDSEP_DATABASE_PASSWORD` - FedSep primary database password
- `APPLICATIONINSIGHTS_CONNECTION_STRING` - Azure monitoring instrumentation key

The file `azure-extmgmt-helm-master/configs/DEV/dockerconfig.yaml` contains a
full Docker registry authentication JSON with credentials for
`eus1devaksregistry.azurecr.io`.

### 3.2 CRITICAL: Known Vulnerabilities (719 Grype + 170 Trivy)

#### Critical CVEs Confirmed by Scanning

| CVE | Package | Version | Fix Available | Repo | Description |
|---|---|---|---|---|---|
| **CVE-2022-22965** | spring-boot-starter-web | 2.2.4.RELEASE | 2.5.12, 2.6.6 | MessagingPoc **(stale - POC, not deployed)** | **Spring4Shell** - remote code execution via data binding. Actively exploited since March 2022. Not confirmed in a live service, but the vulnerable Spring Boot 2.x versions are present in 6 live services (PrEPA, Auth, UserMgmt, AzureAd, Employer, Litigation) - verify whether their specific version+JDK combinations are exploitable. |
| CVE-2020-14343 | PyYAML | 5.3.1 | 5.4 | azure-extmgmt-ansible | Arbitrary code execution via `yaml.load()` |
| CVE-2019-17495 | springfox-swagger-ui | 2.9.2 | 2.10.0 | MessagingPoc | XSS via Swagger UI |
| CVE-2025-54988 | tika-parsers | 1.24.1 | 2.0.0-ALPHA | EmailWebService | Denial of service via crafted document |
| CVE-2025-66516 | tika-core | 1.28.5 | 3.2.2 | FedSep | Denial of service via crafted document |
| CVE-2026-25896 | fast-xml-parser | 4.4.1 | 4.5.4 | ImsNXG-NG | XML parsing vulnerability |
| CVE-2026-28292 | simple-git | 3.16.0 | 3.32.3 | ImsNXG-NG | Command injection via git operations |
| CVE-2026-31938 | jspdf | 4.0.0 | 4.2.1 | ImsNXG-NG | PDF generation vulnerability |
| CVE-2026-41242 | protobufjs | 7.5.4 | 7.5.5 | ImsNXG-NG | Prototype pollution |
| GHSA-2qrg-x229-3v8q | log4j | 1.2.16 | None | transitive | Log4j 1.x - multiple RCE/deserialization CVEs, **no fix available** (EOL) |
| GHSA-65fg-84f6-3jq3 | log4j | 1.2.16 | None | transitive | Log4j 1.x JMSAppender RCE |
| GHSA-rmqp-9w4c-gc7w | axis | 1.4 | None | transitive | SSRF in Axis 1.x - **no fix available** (project abandoned 2006) |
| GHSA-vmfg-rjjm-rjrj | logback-classic | 1.0.7 | 1.2.0 | transitive | JNDI injection in Logback |
| GHSA-vmfg-rjjm-rjrj | logback-core | 1.0.7 | 1.2.0 | transitive | JNDI injection in Logback |

#### High-Severity Vulnerable Packages (63 unique package+version combinations)

Key packages with HIGH-severity CVEs include:

| Package | Version | Affected Area |
|---|---|---|
| @angular/core, @angular/common, @angular/compiler | 16.2.12 | ImsNXG-NG, FedSep-NG |
| @angular/compiler, @angular/core | 19.2.18 | IntakeCollectionsUI |
| ansible | 5.5.0 | azure-extmgmt-ansible |
| axios | 1.13.5, 1.15.0 | Frontend HTTP clients |
| commons-fileupload | 1.4, 1.5 | File upload handling |
| commons-io | 2.4, 2.11.0, 2.13.0 | File I/O operations |
| hibernate-core | 5.4.30.Final | ORM - deserialization surface |
| json | 20180130, 20180813, 20230618 | JSON parsing |
| jsoup | 1.10.1 | HTML parsing |
| next | 15.5.14 | AttorneyPortal |
| postgresql | 42.7.3 | Database driver |
| snakeyaml | 1.18 | YAML parsing - deserialization |
| xstream | 1.4.9 | XML serialization - deserialization RCE |

#### Vulnerability Distribution by Repository

| Repository | Trivy (CRIT+HIGH) | Grype (all) | Primary Cause |
|---|---|---|---|
| ImsNXG-NG-ims-aks-test | 72 | ~100+ | Angular 16 npm dependency tree |
| AttorneyPortal-main | 21 | ~40+ | Next.js/npm dependency tree |
| azure-extmgmt-ansible-master | 16 | ~20+ | Python 2.x/3.x dependencies (PyYAML, urllib3, certifi) |
| alfresco-bulk-import-staging | 14 | ~15+ | Python dependencies |
| FedSep-NG-ims-aks-test | 10 | ~15+ | Angular 16 npm dependency tree |
| FedSep-ims-aks-test | 4 | ~20+ | Tika, commons, JBoss transitive deps |
| Utilities-master | 6 | ~15+ | Legacy Java dependencies (log4j 1.x, axis, logback) |
| EmailWebService-ims-aks-test | 4 | ~10+ | Tika 1.24, legacy deps in old Dockerfile path |

---

## 4. Security Findings - Code-Level Analysis

### 4.1 CRITICAL: Broken Cryptography (PBEWithMD5AndDES)

Two repositories contain identical password encryption implementations using
`PBEWithMD5AndDES`:

- `FedSep-ims-aks-test/src/gov/eeoc/fedsep/util/DesEncrypter.java`
- `RespondentPortal-ims-aks/src/gov/eeoc/respondent/utility/DesEncrypter.java`

**Every aspect of this implementation is broken:**

| Problem | Detail | Severity |
|---|---|---|
| **Algorithm** | `PBEWithMD5AndDES` - DES uses a 56-bit key, brute-forceable in hours on commodity hardware. MD5 is collision-broken. | CRITICAL |
| **Salt** | Hardcoded 8-byte salt `{0xA9, 0x9B, 0xC8, 0x32, 0x56, 0x35, 0xE3, 0x03}` - identical in both repos. Defeats the purpose of salting. | CRITICAL |
| **Iterations** | 19 iterations. OWASP recommends **600,000+** for PBKDF2. | CRITICAL |
| **Error handling** | All security exceptions silently swallowed by empty catch blocks - `InvalidAlgorithmParameterException`, `InvalidKeySpecException`, `NoSuchPaddingException`, `NoSuchAlgorithmException`, `InvalidKeyException` - meaning the cipher can fail silently and the application continues with null cipher objects. | HIGH |

The class is used for password encryption before database storage. Any password encrypted
with this implementation is recoverable in minutes with known plaintext.

### 4.2 CRITICAL: Java Deserialization (Remote Code Execution Surface)

`ObjectInputStream.readObject()` is used in production code:

| File | Risk |
|---|---|
| `EmailWebServiceNG-master-pe/consumer/src/main/java/gov/eeoc/email/ws/service/MessageProcessingServiceImpl.java:96-97` | Deserializes `EmailForm` from `ObjectInputStream`. Direct RCE vector via gadget chains (ysoserial). **(Stale repo - superseded by EmailWebService. Verify the modernized service does not carry this pattern.)** |
| `FedSep-ims-aks-test/src/gov/eeoc/fedsep/util/SystemUtil.java:314-317` | `Object clone = is.readObject()` - generic deserialization of any Object type. |

XStream 1.4.9 is present in the Utilities-master dependency tree. XStream
versions prior to 1.4.18 have multiple deserialization RCE CVEs
(CVE-2021-39139 through CVE-2021-39154). While the XStream references in
EEOCWebService are commented out, the library remains on the classpath.

### 4.3 CRITICAL: XML External Entity (XXE) - Zero Protections

**42 XML parser instantiations** were found across the codebase
(`DocumentBuilderFactory`, `SAXParserFactory`, `XMLInputFactory`,
`TransformerFactory`).

**Zero of those 42 instances configure XXE protections** - no
`disallow-doctype-decl`, no `external-general-entities` feature disabled,
no `SUPPORT_DTD` set to false.

This means every XML processing endpoint is potentially vulnerable to:
- Local file disclosure (reading `/etc/passwd`, application properties, keys)
- Server-Side Request Forgery (SSRF) via external entity URLs
- Denial of service via recursive entity expansion (billion laughs attack)

### 4.4 CRITICAL: Authentication Gaps

**918 of 1,177 API endpoints (78%) have no method-level authorization.**

| Metric | Count |
|---|---|
| Total `@RequestMapping` / `@GetMapping` / etc. | 1,177 |
| With `@PreAuthorize`, `@Secured`, or `@RolesAllowed` | 259 |
| **Without any method-level authorization** | **918** |

These endpoints rely entirely on the Spring Security filter chain for access
control. While the filter chain provides authentication on most services, it
does not enforce **authorization** - meaning any authenticated user may be able
to access any endpoint, regardless of their role.

**IntakeCollectionsService is fully open:**

```java
// IntakeCollectionsService SecurityConfig.java
.authorizeHttpRequests(auth -> auth
    .anyRequest().permitAll()
)
```

Every endpoint on IntakeCollectionsService accepts requests without any
authentication or authorization. This is configured in both the OAuth2-enabled
and the fallback security filter chains.

### 4.5 CRITICAL: CORS Wildcard on 5 Services

CORS is configured with `@CrossOrigin("*")` or `setAllowedOrigins(List.of("*"))`
on the following services:

| Service | Location | Data Exposed |
|---|---|---|
| FederalHearings-ims-aks | `SecurityConfig.java` - global CORS config | Federal hearing case data |
| EmployerWebService-ims-aks-test | `EmployerElasticResource.java:45` - controller annotation | Employer search data |
| SearchDataWebService-ims-aks-test-es8 | `HearingSearchResource.java:39` - controller annotation | Hearing search indices |
| ECMService-ims-aks-test | `ContentManagementResource.java:56` - controller annotation | Document management API |
| AzureAdService-main | `AzureAdResource.java:31` - controller annotation | Azure AD user directory |
| FepaGateway-ims-aks | Properly scoped to `*.eeoc.gov` + localhost | (Correctly configured) |

Five of six services permit any website on the internet to make authenticated
cross-origin requests to EEOC APIs.

### 4.6 HIGH: CSRF Protection Disabled on Browser-Facing Services

| Service | Configuration | Browser-Facing? |
|---|---|---|
| IntakeCollectionsService | `csrf(csrf -> csrf.disable())` on both filter chains | **Yes** - Angular frontend |
| EmailWebService | `http.csrf().disable()` (legacy) / `csrf(csrf -> csrf.disable())` (current) | Yes - called by frontend portals |
| FepaGateway | `csrf(csrf -> csrf.disable())` | **Yes** - serves AttorneyPortal |
| MessagingPoc | `http.csrf().disable()` | Unclear |
| FederalHearings | CSRF bypassed on all whitelisted paths (Swagger, actuator, API docs) | Partially |

These five CSRF-affected services are a different set from the five CORS-wildcard
services in §4.5; only FederalHearings appears on both lists. Track them
separately during remediation.

### 4.7 HIGH: Input Validation Nearly Absent

| Metric | Count | Validated | Gap |
|---|---|---|---|
| `@RequestParam` parameters | 595 | **2** (0.3%) | 593 unvalidated query parameters |
| `@RequestBody` parameters | 299 | 251 (84%) | 48 unvalidated request bodies |
| `@PathVariable` parameters | 945 | **0** (0%) | 945 unvalidated path variables |

**593 query parameters and 945 path variables accept arbitrary input with no
validation.** This is the injection surface for SQL injection, XSS, path
traversal, and LDAP injection attacks.

### 4.8 HIGH: No Rate Limiting Anywhere

Zero rate limiting configuration found across all 19 services and 1,177
endpoints. No Bucket4j, no Spring Cloud Gateway rate limiting, no API Management
throttling policies. Every endpoint can be called without limit.

### 4.9 HIGH: SQL Injection Patterns in Legacy Code

ImsNXG-master contains extensive native SQL query construction:

| File | Pattern Count | Risk |
|---|---|---|
| `SharedGroupsManager.java` | 9 `createNativeQuery()` with string concatenation | HIGH |
| `ComplaintantDataService.java` | Multiple native queries | HIGH |
| `Lookup.java` | 15+ `createNativeQuery()` constructions | HIGH |
| `TemplateData.java` | Complex multi-line native queries | HIGH |
| `CacheValues.java` | Native queries for session data | MEDIUM |
| `DocumentManager.java` | Native INSERT/UPDATE | HIGH |

### 4.10 HIGH: Security Headers Almost Entirely Missing

| Header | Services Implementing | Required By |
|---|---|---|
| `Content-Security-Policy` | **0** of 19 | OWASP, NIST |
| `X-Frame-Options` | **0** of 19 | OWASP, NIST |
| `X-Content-Type-Options` | **2** of 19 (FedSep, EEOCWebService) | OWASP, NIST |
| `Strict-Transport-Security` | **0** of 19 | OWASP, NIST, HSTS Preload |
| `Referrer-Policy` | **0** of 19 | OWASP |
| `Permissions-Policy` | **0** of 19 | OWASP |

### 4.11 MEDIUM: 5-Hour Session Timeout

ImsNXG-master configures a **300-minute (5-hour) session timeout** in
`web.xml:91`. FedSep configures 180 minutes (3 hours). Federal systems
typically require 15-30 minute idle timeouts per NIST 800-53 AC-12.

### 4.12 MEDIUM: 806 HTTP Client Instances (SSRF Surface)

806 `RestTemplate`, `WebClient`, `HttpURLConnection`, and `OkHttpClient`
usages across the codebase (632 outside test code). If any URL parameter is influenced by user input,
these are SSRF vectors. Without URL allowlisting, an attacker could potentially
use these services to make requests to internal infrastructure.

### 4.13 MEDIUM: 176 HttpSession Usages Without Secure Configuration

176 `HttpSession` usages with no explicit secure cookie configuration
(`Secure`, `HttpOnly`, `SameSite`) on most services. Only
IntakeCollectionsService configures a `SessionCreationPolicy`.

### 4.14 MEDIUM: 1,546 Broad Exception Catches

1,546 `catch(Exception)` blocks across the codebase. While `printStackTrace()`
has been eliminated (0 instances), broad exception catching masks specific
failure modes and can silently swallow security-relevant exceptions - as
demonstrated by the `DesEncrypter` class silently ignoring cipher initialization
failures.

---

## 5. Section 508 / WCAG 2.1 AA Compliance

### 5.1 Automated Findings

| Finding | Count | WCAG Criterion | Severity |
|---|---|---|---|
| Inline `onclick` handlers (keyboard-inaccessible) | **863** | 2.1.1 Keyboard | CRITICAL |
| HTML documents missing `lang` attribute | **300** | 3.1.1 Language of Page | HIGH |
| Images missing `alt` attribute | **104** | 1.1.1 Non-text Content | HIGH |
| Form inputs (996) vs. label elements (2,377) | Gap requires audit | 1.3.1 Info and Relationships | MEDIUM |
| Tables (291) vs. `<th>` elements (2,241) | Ratio suggests some coverage | 1.3.1 Info and Relationships | MEDIUM |

### 5.2 Legacy JSP Frontends - Not Remediable

| Repository | JSP/XHTML | HTML | CSS | Recommendation |
|---|---|---|---|---|
| FedSep-ims-aks-test | 258 | 12 | 74 | **Retire** - migrate to FedSep-NG |
| ImsNXG-master | 122 | 6 | 80 | **Retire** - ImsNXG-NG replacement exists |
| RespondentPortal-ims-aks | 24 | 8 | 20 | **Rewrite** - no NG replacement exists |
| BIRTReports-master | 0 | 497 | 108 | Report output HTML - template-level fixes |
| SendGrid_Email_templates-main | 0 | 212 | 0 | Email HTML - add `lang`, improve structure |

The 863 `onclick` handlers concentrate in the legacy JSP repos. These attach
JavaScript behavior to `<div>`, `<span>`, and `<td>` elements without `role`,
`tabindex`, or keyboard event equivalents. Fixing this in JSP is not practical.
The correct path is completing the NG frontend migration.

### 5.3 Angular Frontend Alignment

| Frontend | Angular | Status | 508 Impact |
|---|---|---|---|
| ImsNXG-NG | 16.2 (EOL) | Uses deprecated `@angular/flex-layout` (never released from beta) | Upgrade to 19; replace flex-layout with CSS Grid |
| FedSep-NG | 16.2 (EOL) | Early-stage rewrite | Upgrade to 19 with WCAG built-in |
| IntakeCollectionsUI | 19 (current) | Modern | Audit for compliance |

---

## 6. Architecture Assessment

### 6.1 Current State Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                              ARC SYSTEM - CURRENT ARCHITECTURE                            │
│                                                                                           │
│   Three runtime eras coexisting in production - no migration was completed                │
└──────────────────────────────────────────────────────────────────────────────────────────┘

┌───────────── FRONTEND TIER ──────────────────────────────────────────────────────────────┐
│                                                                                           │
│  ERA 1: JBoss-hosted JSP             ERA 3: SPA (Nginx)          DAES                    │
│  ┌─────────────────────┐             ┌───────────────────┐       ┌───────────────────┐   │
│  │ ImsNXG (122 JSP)    │             │ ImsNXG-NG (Ang16) │       │ ADR Portal (Flask)│   │
│  │ FedSep (258 JSP)    │             │ FedSep-NG (Ang16) │       │ Triage            │   │
│  │ Respondent (24 JSP) │             │ AttorneyPortal    │       │ OGC Trial Tool    │   │
│  │                     │             │ (Next.js 14)      │       │ OCHCO Benefits    │   │
│  │ BROKEN DES CRYPTO   │             │ IntakeCollUI      │       │ UDAP Analytics    │   │
│  │ 5-HOUR SESSIONS     │             │ (Angular 19)      │       │                   │   │
│  │ 863 onclick handlers│             │ 72 TRIVY VULNS    │       │ MODERN STACK      │   │
│  └──────────┬──────────┘             └─────────┬─────────┘       └─────────┬─────────┘   │
│             │                                  │                           │              │
└─────────────┼──────────────────────────────────┼───────────────────────────┼──────────────┘
              │                                  │                           │
              │      NO API GATEWAY              │       eeoc-arc-           │
              │      NO RATE LIMITING            │       integration-api     │
              │      NO SERVICE MESH             │       (sole gateway)      │
              │                                  │                           │
┌─────────────┼──────────────────────────────────┼───────────────────────────┼──────────────┐
│             │           BACKEND SERVICE TIER   │                           │              │
│─────────────────────────────────────────────────────────────────────────────────────────│
│                                                                                           │
│  ERA 1: JBoss 7.4 (EOL)        ERA 2: Spring Boot 2.x (EOL)                             │
│  ┌──────────────────────┐      ┌──────────────────────┐                                  │
│  │ EEOCWebService       │      │ PrEPAWebService      │      ERA 3: Spring Boot 4.0     │
│  │  226 endpoints       │      │  330 endpoints       │      ┌──────────────────────┐   │
│  │  Java 11 / JBoss     │      │  Java 11 / SB 2.4    │      │ FederalHearings      │   │
│  │  PROD PASSWORDS IN   │      │  44 deps, 1 test     │      │  261 endpoints       │   │
│  │  SOURCE CONTROL      │      │  NO RATE LIMITING    │      │  Java 25 / SB 4.0    │   │
│  ├──────────────────────┤      ├──────────────────────┤      │  CORS WILDCARD *     │   │
│  │ FedSep               │      │ AuthorizationService │      │  PII IN LOGS         │   │
│  │  166 endpoints       │      │  Java 11 / SB 2.3    │      ├──────────────────────┤   │
│  │  DESERIALIZATION     │      │  14 PRIVATE KEYS     │      │ FederalWebService    │   │
│  │  SQL INJECTION       │      │  IN SOURCE CONTROL   │      │  96 endpoints        │   │
│  ├──────────────────────┤      ├──────────────────────┤      │  Java 25 / SB 4.0    │   │
│  │ ImsNXG               │      │ UserMgmt / AzureAd   │      ├──────────────────────┤   │
│  │  196 endpoints       │      │  Java 11 / SB 2.2    │      │ ContentGen / ECM     │   │
│  │  NATIVE SQL CONCAT   │      │  DEPRECATED IMAGES   │      │ EmailWS / Template   │   │
│  │  42 XXE PARSERS      │      │  CORS WILDCARD *     │      │  Java 25 / SB 4.0    │   │
│  │  0 XXE PROTECTIONS   │      │                      │      │  CORS WILDCARD *     │   │
│  └──────────────────────┘      └──────────────────────┘      └──────────────────────┘   │
│                                                                                           │
│  ┌── AUTH EVERYWHERE ──────────────────────────────────────────────────────────────────┐  │
│  │  918 of 1,177 endpoints lack method-level authorization                             │  │
│  │  CSRF disabled on 5 services    |    0 of 19 services set Content-Security-Policy   │  │
│  │  0 rate limiting on any endpoint |    593 query params + 945 path vars unvalidated  │  │
│  └─────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                           │
└──────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                              INFRASTRUCTURE TIER                                          │
│─────────────────────────────────────────────────────────────────────────────────────────│
│  AKS Cluster (Helm)  │  Alfresco CMS 6.2.2 (EOL)  │  Oracle DB  │  Elasticsearch 8     │
│  PROD SECRETS IN     │  5 repos managing EOL CMS    │  PASSWORDS  │                      │
│  HELM YAML FILES     │                              │  IN SOURCE  │                      │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Key Structural Problems

1. **Three-era runtime bifurcation** - JBoss 7.4, Spring Boot 2.x, and Spring
   Boot 4.0 all in production simultaneously. Unified patching impossible.

2. **No API gateway** - 1,177 endpoints exposed directly. Authentication,
   authorization, rate limiting, CORS, and logging are managed (or not managed)
   independently per service. 18 separate `SecurityConfig` files.

3. **NG migration stalled** - ImsNXG-NG appears near-complete (3,284 TS files
   vs. 730 Java + 122 JSP), but FedSep-NG is early (202 TS vs. 786 Java + 258
   JSP). RespondentPortal has no NG replacement at all. Legacy JBoss services
   are still running alongside their NG replacements.

4. **No OpenAPI specifications** - none of the 19 services publish structured
   API documentation. This blocks API gateway integration, automated testing,
   and cross-platform integration schema generation.

5. **No RFC 7807 error responses** - error formats vary across services and eras.

6. **84% of code on pre-2020 Java EE namespace** - 9,436 `javax.*` imports vs.
   1,770 `jakarta.*`. The `javax` → `jakarta` migration is a prerequisite for
   any Spring Boot 3.x+ upgrade.

### 6.3 Enterprise Platform Integration Readiness

The EEOC's Data and AI Enterprise System (DAES) applications - UDAP, ADR,
Triage, OGC Trial Tool, OCHCO Benefits Validation, and Access Admin - follow a
common integration pattern: structured
APIs with OpenAPI documentation, JWT-based auth, request tracing, and
feature-flagged integration endpoints. ARC currently supports none of this.

| Requirement | Current State | Gap |
|---|---|---|
| OpenAPI specifications | None on any service | Must generate for all services |
| RFC 7807 Problem Details | Not implemented | Must implement on all services |
| `X-Request-ID` propagation | Not implemented | Required for distributed tracing and audit logging |
| Health check endpoints | Spring Actuator on some; absent on JBoss | Must standardize |
| Structured JSON logging | Not implemented | Required for observability |
| Token-based auth (not session) | Mixed - some JWT, some session | Must standardize on JWT |
| Feature flags for integrations | None | Every integration must start disabled and degrade gracefully |

### 6.4 Test Coverage

| Category | Repos with Tests | Quality | Risk |
|---|---|---|---|
| Core business (8) | 6 have tests, but most have 2-8 test files | PrEPAWebService: 47 test files (best). Others: 2 each. | Regression risk on any change |
| Frontend (6) | ImsNXG-NG: 529 tests. Others: 0-50. | One well-tested repo. | FedSep-NG, IntakeCollectionsUI, RespondentPortal effectively untested |
| Support (9) | 7 have tests | 2-4 test files each | Insufficient for services handling auth and email |
| Infrastructure (14) | 0 | None | No Helm chart tests, no IaC validation, no Ansible tests |

---

## 7. Federal Compliance Gap Analysis

### 7.1 Executive Order 14028 (Improving the Nation's Cybersecurity)

| Requirement | ARC Status | Gap |
|---|---|---|
| Zero Trust Architecture | Not implemented | No microsegmentation, no least-privilege network, no continuous verification |
| Software Supply Chain Security | No SBOMs, no provenance, no image signing | Full implementation needed |
| Endpoint Detection and Response | Not evident in configuration | Microsoft Defender for Containers or equivalent needed |
| Multi-Factor Authentication | Entra ID provides MFA for EEOC staff; unclear for service accounts | Audit service account auth |
| Encryption in transit and at rest | TLS likely at ingress; DES encryption in application code | Replace DES with AES-256-GCM |
| Log retention and monitoring | Application Insights instrumentation key committed to source | Centralize logging, secure credentials |

### 7.2 OMB M-22-09 (Zero Trust Strategy)

| Pillar | ARC Status | Gap |
|---|---|---|
| Identity | OAuth2 on some services; 918 endpoints lack method-level authz | Full identity verification at every request |
| Devices | Not assessed | Device trust posture checking |
| Networks | Flat AKS network (no evidence of microsegmentation) | Network segmentation per service tier |
| Applications and Workloads | No runtime protection, no container scanning in CI/CD | Continuous vulnerability scanning |
| Data | PII in logs, passwords in source, DES encryption | Data classification, encryption modernization |

### 7.3 FISMA Continuous Monitoring

| Requirement | ARC Status | Gap |
|---|---|---|
| Vulnerability scanning | No evidence of automated scanning in CI/CD | Integrate Trivy/Grype into build pipeline |
| Configuration management | Secrets in source control; inconsistent configs | Centralize in Key Vault + GitOps |
| Incident detection | No WAF, no runtime detection, no anomaly alerting | Deploy WAF + runtime monitoring |
| Patch management | 10 services on EOL - patches don't exist | Modernize to supported versions |

### 7.4 Section 508 (Rehabilitation Act)

| Requirement | ARC Status | Gap |
|---|---|---|
| WCAG 2.1 AA keyboard accessibility | 863 `onclick` handlers on non-interactive elements | Complete NG migration + remediation |
| Language of page | 300 HTML documents missing `lang` | Add `lang="en"` to all documents |
| Alternative text | 104 images missing `alt` | Add descriptive alt text |
| Color contrast (4.5:1 text, 3:1 non-text) | Not audited - requires runtime testing | Run axe-core on all pages |

### 7.5 NIST 800-53 Rev5 Control Gaps

| Control | Finding | Priority |
|---|---|---|
| **AC-2** (Account Management) | 918 endpoints without method-level authorization | CRITICAL |
| **AC-12** (Session Termination) | 300-minute and 180-minute session timeouts | HIGH |
| **AU-2** (Audit Events) | No structured audit logging | HIGH |
| **IA-5** (Authenticator Management) | Passwords in source control, DES encryption, 19-iteration PBKDF | CRITICAL |
| **SC-8** (Transmission Confidentiality) | CSP/HSTS headers absent on 19 of 19 services | HIGH |
| **SC-12** (Cryptographic Key Management) | Private keys in source control; hardcoded salts | CRITICAL |
| **SC-13** (Cryptographic Protection) | PBEWithMD5AndDES in production | CRITICAL |
| **SC-28** (Protection of Information at Rest) | DES encryption for stored passwords | CRITICAL |
| **SI-2** (Flaw Remediation) | 719+ known vulnerabilities, 43 Critical, 10 services on EOL | CRITICAL |
| **SI-10** (Information Input Validation) | 1,538 unvalidated parameters (593 query + 945 path) | HIGH |

---

## 8. Phased Remediation Plan

### Design Principle: Platform Conformance

The EEOC's Data and AI Enterprise System (DAES) applications - UDAP, ADR,
Triage, OGC Trial Tool, OCHCO Benefits Validation, and Access Admin -
share a common operational standard: pre-commit hooks that catch secrets and
lint violations before code leaves a developer's machine, a unified local CI
script that runs 20+ security and compliance gates, feature flags on every
integration endpoint, validated configuration management (no YAML files with
embedded credentials), and structured audit logging with HMAC integrity
signatures. These patterns exist and work today.

The goal of this remediation is not just to patch vulnerabilities - it is to
bring ARC into conformance with the same operational standard so that the
entire EEOC application portfolio is maintainable, auditable, and secure
under one set of practices. Every phase below includes platform conformance
tasks alongside the vulnerability remediation, because fixing a CVE without
fixing the process that allowed it just creates next year's audit finding.

Where new services or rewrites are required, they should follow the platform's
Python 3.13 / Flask or FastAPI stack rather than adding more Java - not because
Java is wrong, but because maintaining one technology standard across the
portfolio is cheaper and easier to staff than maintaining two. The existing
Java services that are modernized to Spring Boot 4.0 remain Java; the pattern
for new work is Python.

### Phase 0: Emergency Security Hardening (Weeks 1-4)

Nothing in this phase is optional. These findings represent immediate
exploitability or active compliance violations.

#### 0.1 Credential Rotation (CRITICAL, Week 1)

Rotate every credential identified in Section 3.1. This is the single most
urgent task in the entire plan. The following credentials are in source
control right now and must be changed immediately.

**Database passwords** (coordinate with DBA team):
1. Open `azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml`
2. Decode each base64 value: `echo "VALUE" | base64 -d`
3. Generate new passwords (minimum 24 characters, mixed case, numbers, symbols)
4. Update in Oracle: `ALTER USER s_ims IDENTIFIED BY "new_password";`
5. Update in Azure Key Vault: `az keyvault secret set --name arcdb-s-admin-password --vault-name VAULT --value "new_password"`
6. Restart affected pods to pick up the new secret
7. Repeat for all six database passwords in the prod secrets file:
   `IMS_DATABASE_SERVICE_USER_PASSWORD`, `IMS_DATABASE_REPORT_USER_PASSWORD`,
   `IMS_DATABASE_FEDSEP_USER_PASSWORD`, `FEDSEP_AWSDB_PASSWORD`,
   `FEDSEP_BODDB_PASSWORD`, `FEDSEP_DATABASE_PASSWORD`

**OAuth and service passwords** (in application.properties files):
1. `FederalHearings-ims-aks/src/main/resources/application.properties:75` -
   `app.oauth.password=password123` and `:77` `app.oauth.client.password=prepa2019`
2. `FepaGateway-ims-aks/src/main/resources/application.properties` - 9 OAuth
   passwords starting at line 62
3. `EmailWebService-ims-aks-test/src/main/resources/application-LOCAL.properties` -
   database passwords at lines 14-16
4. Move all of these to Key Vault. Do not replace one hardcoded password with
   another hardcoded password.

**Private keys in AuthorizationService** (14 keys across 7 files):
1. `AuthorizationService-ims-aks/src/main/resources/application-DEV.yaml:3`
2. `AuthorizationService-ims-aks/src/main/resources/application-TEST.yaml:3`
3. `AuthorizationService-ims-aks/src/main/resources/application-UAT.yaml:3`
4. `AuthorizationService-ims-aks/src/main/resources/application-TRAIN.yaml:3`
5. `AuthorizationService-ims-aks/src/main/resources/application.yaml:92`
6. Generate new RSA key pairs: `openssl genrsa -out private.pem 2048`
7. Store in Key Vault, not in YAML files
8. Update all environments with the new public keys

**Other credentials to rotate:**
- Azure Container Registry token in `azure-extmgmt-helm-master/configs/DEV/dockerconfig.yaml`
- SendGrid API tokens in `EmailWebService-ims-aks-test/src/test/resources/application.properties`
  and `EmailWebService-ims-aks-test/src/main/resources/application-LOCAL.properties`
- Azure Storage account key in `azure-extmgmt-helm-master/configs/prod/prod-birt-reports-storage.yaml`
- Application Insights instrumentation key in `azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml`

#### 0.2 Remove Secrets Files from Repositories (CRITICAL, Weeks 1-2)

After rotating, delete the files that contained the old credentials. Do not
leave rotated secrets in git history as "safe because they're old."

**Files to delete:**
```
azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml
azure-extmgmt-helm-master/configs/prod/eml-prod-secrets.yaml
azure-extmgmt-helm-master/configs/prod/prod-birt-reports-storage.yaml
azure-extmgmt-helm-master/configs/TEST/ims-test-secrets.yaml
azure-extmgmt-helm-master/configs/TEST/ims-uat-secrets.yaml
azure-extmgmt-helm-master/configs/DEV/dockerconfig.yaml
azure-extmgmt-test-master/cicd/secrets.tf
azure-extmgmt-test-master/tmf_app/tmf_aks/tmf-secrets.yaml
```

**Replace with Key Vault references.** For Spring Boot services, add this
dependency and property pattern:

```xml
<!-- pom.xml -->
<dependency>
    <groupId>com.azure.spring</groupId>
    <artifactId>spring-cloud-azure-starter-keyvault</artifactId>
</dependency>
```

```properties
# application.properties - no secrets, just Key Vault reference
spring.cloud.azure.keyvault.secret.property-sources[0].endpoint=https://your-vault.vault.azure.net/
spring.datasource.password=${arcdb-s-admin-password}
```

**A note on Key Vault delivery mechanisms.** There are two ways to get
secrets from Key Vault into a running service:

1. **Application-level (Phase 0):** `spring-cloud-azure-starter-keyvault`
   connects directly to Key Vault via managed identity and resolves secrets
   as application properties at startup. This works with any AKS cluster
   regardless of whether the CSI driver add-on is provisioned. This is the
   fast path for Phase 0: add a Maven dependency, set one endpoint property,
   and reference secrets by name. No infrastructure changes required.

2. **Infrastructure-level (Phase 4):** The Azure Key Vault CSI driver
   mounts secrets as files in the pod filesystem. This is the Kubernetes-
   native approach for non-Spring Boot workloads (Helm chart secrets,
   sidecar configs, init containers) and for standardizing the pattern
   across the entire cluster.

Phase 0 uses option 1. Phase 4 adds option 2 for full cluster coverage.
Both options read from the same Key Vault. The hardcoded YAML files are
deleted in Phase 0 regardless of which delivery mechanism is in place.

**Before starting Phase 0, confirm with the infrastructure team whether
the CSI driver add-on is already enabled on the AKS cluster.** If it is,
the Kubernetes secret manifests can also be migrated to `SecretProviderClass`
immediately:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: ims-secrets
spec:
  provider: azure
  parameters:
    keyvaultName: "your-vault-name"
    objects: |
      array:
        - |
          objectName: arcdb-s-admin-password
          objectType: secret
```

If the CSI driver is not yet enabled, those Kubernetes-level secrets remain
in Key Vault but are injected through the Spring Boot starter until the
infrastructure team provisions the add-on in Phase 4.

**Reference implementation:** See how `eeoc-arc-integration-api` handles
configuration in `eeoc-arc-integration-api/app/config/__init__.py`. All
settings come from environment variables with no defaults for secrets:

```python
class Settings(BaseSettings):
    key_vault_uri: str = ""
    arc_client_secret: str = ""    # empty default, fails explicitly if unset
    redis_url: str = "redis://localhost:6379/0"  # safe defaults only for non-secrets
```

#### 0.3 Git History Scrub (CRITICAL, Week 2)

Removing files from HEAD does not remove them from git history. Anyone who
clones the repo can still check out old commits and read every password.

```bash
# For each high-risk repo, run gitleaks against full history:
gitleaks detect --source ./azure-extmgmt-helm-master --redact --report-path gitleaks-helm.json
gitleaks detect --source ./AuthorizationService-ims-aks --redact --report-path gitleaks-auth.json

# If the history contains production credentials, scrub with BFG:
# (Make a backup first)
cp -r azure-extmgmt-helm-master azure-extmgmt-helm-master-backup
java -jar bfg.jar --delete-files '*-secrets.yaml' azure-extmgmt-helm-master
cd azure-extmgmt-helm-master && git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

Document every file scrubbed, the date range of exposure, and the commit
hashes that contained credentials. This documentation goes to the security
team.

#### 0.4 Fix CORS Wildcards (CRITICAL, Week 1)

Five services allow any website to make cross-origin requests. Here are the
exact files and what to change:

**FederalHearings-ims-aks** - `src/main/java/gov/eeoc/hearing/config/SecurityConfig.java:75`:
```java
// BEFORE (broken):
configuration.setAllowedOrigins(List.of("*"));

// AFTER (fixed):
configuration.setAllowedOrigins(List.of(
    "https://hearings.eeoc.gov",
    "https://hearings-uat.eeoc.gov"
));
```

**EmployerWebService** - `src/main/java/gov/eeoc/employer/ws/resource/es/EmployerElasticResource.java:45`:
```java
// BEFORE: @CrossOrigin(origins = "*")
// AFTER:  @CrossOrigin(origins = {"https://eeoc.gov", "https://*.eeoc.gov"})
```

Same pattern for:
- `SearchDataWebService-ims-aks-test-es8/src/main/java/gov/eeoc/searchws/resource/HearingSearchResource.java:39`
- `ECMService-ims-aks-test/src/main/java/gov/eeoc/ecm/resource/ContentManagementResource.java:56`
- `AzureAdService-main/src/main/java/gov/eeoc/azure/ad/resource/AzureAdResource.java:31`

**Reference implementation:** See how FepaGateway does it correctly in
`FepaGateway-ims-aks/src/main/java/gov/eeoc/bff/fepa/security/OAuth2ResourceServerSecurityConfiguration.java` -
it scopes to `https://*.eeoc.gov` plus localhost for development.

#### 0.5 Re-enable CSRF (HIGH, Week 2)

**IntakeCollectionsService** - `src/main/java/gov/eeoc/foi/config/SecurityConfig.java:56`:
```java
// BEFORE:
.csrf(csrf -> csrf.disable())

// AFTER (for browser-facing endpoints):
.csrf(csrf -> csrf
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
    .ignoringRequestMatchers("/api/webhooks/**", "/actuator/**"))
```

For services that are purely backend-to-backend (not called by browsers),
CSRF disable is acceptable. Add a comment explaining why:
```java
// CSRF disabled: this service is called only by other backend services
// via bearer token auth, never by browser clients with cookies.
.csrf(csrf -> csrf.disable())
```

#### 0.6 Add Security Headers (HIGH, Weeks 2-3)

Zero of 19 services set Content-Security-Policy or HSTS headers. The
platform has a working reference implementation to copy from.

**Reference file:** `eeoc-arc-integration-api/app/middleware/security_headers.py`

For Spring Boot services, add a filter or configure in `SecurityConfig`:

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.headers(headers -> headers
        .contentTypeOptions(Customizer.withDefaults())           // X-Content-Type-Options: nosniff
        .frameOptions(frame -> frame.deny())                     // X-Frame-Options: DENY
        .httpStrictTransportSecurity(hsts -> hsts
            .includeSubDomains(true)
            .maxAgeInSeconds(31536000))                          // Strict-Transport-Security
        .contentSecurityPolicy(csp -> csp
            .policyDirectives("default-src 'self'; script-src 'self'; style-src 'self'"))
        .referrerPolicy(referrer -> referrer
            .policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN))
    );
    return http.build();
}
```

For JBoss services (EEOCWebService, ImsNXG, FedSep, RespondentPortal,
DocumentGeneratorAdapter), add a servlet filter in `web.xml` and create a
`SecurityHeadersFilter.java` that sets the same headers on every response.

#### 0.7 Reduce Session Timeouts (HIGH, Week 1)

**ImsNXG** - `ImsNXG-master/ImsNXG/WebContent/WEB-INF/web.xml:91`:
```xml
<!-- BEFORE: <session-timeout>300</session-timeout> -->
<session-timeout>30</session-timeout>
```

**FedSep** - `FedSep-ims-aks-test/WebContent/WEB-INF/web.xml:99`:
```xml
<!-- BEFORE: <session-timeout>180</session-timeout> -->
<session-timeout>30</session-timeout>
```

NIST 800-53 AC-12 requires session termination after a period of inactivity.
30 minutes is the standard for federal systems.

#### 0.8 PII Log Redaction (HIGH, Week 3)

**FederalHearings** logs email addresses and case participant data at INFO
level. The specific files:

- `FederalHearings-ims-aks/src/main/java/gov/eeoc/hearing/service/DocumentUploadMessageProcessorService.java:226` -
  logs `userEmail` with case number
- `FederalHearings-ims-aks/src/main/java/gov/eeoc/hearing/service/HearingCaseService.java:399` -
  logs `emailRecipients` for hearing cases
- `FederalHearings-ims-aks/src/main/java/gov/eeoc/hearing/service/common/email/EmailManagementService.java:255` -
  logs full `emailRequestVO.toString()`

Replace with redacted versions:
```java
// BEFORE:
log.info("Sending email to {} for case {}", userEmail, caseNumber);

// AFTER:
log.info("Sending email to [REDACTED] for case {}", caseNumber);
```

Or hash the PII before logging:
```java
log.info("Sending email to hash={} for case {}",
    DigestUtils.sha256Hex(userEmail).substring(0, 8), caseNumber);
```

#### 0.9 Gitignore Rules (HIGH, Week 1)

Add these patterns to `.gitignore` in every repo that does not already have
them. Copy the patterns from `eeoc-arc-integration-api/.gitignore` and
`eeoc-ofs-adr/.gitignore` as references:

```
# Secrets and credentials
*-secrets.yaml
*.pem
*.key
*.p12
*.jks
*.pfx
application-LOCAL.properties
application-DEV.properties
.env
.env.*
```

#### 0.10 Platform Conformance: Pre-Commit Hooks

Install the same pre-commit hooks used across the rest of the EEOC platform
on every ARC repository. This is the single most effective preventive control
available. Every credential finding in Section 3.1 would have been caught by
a gitleaks pre-commit hook before it ever reached the repository.

**Step-by-step setup for each repo:**

```bash
cd <repo-directory>

# 1. Install pre-commit (if not already installed)
pip install pre-commit

# 2. Copy the config from an existing EEOC repo
cp ../eeoc-arc-integration-api/.pre-commit-config.yaml .

# 3. Install the hooks
pre-commit install

# 4. Run against all files to verify
pre-commit run --all-files
```

**Reference file:** `eeoc-arc-integration-api/.pre-commit-config.yaml`

The config includes:
- **gitleaks** (v8.18.0+) - scans for secrets on every commit
- **ruff** (Python repos) or add **checkstyle** (Java repos) - lint and format
- **508 lint** - catches accessibility regressions on HTML/template changes

For Java repos, replace `ruff` hooks with:
```yaml
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v4.5.0
  hooks:
    - id: trailing-whitespace
    - id: end-of-file-fixer
    - id: check-yaml
    - id: check-added-large-files
```

The cost to install is one afternoon across all repos. The cost of not having
it is the credential rotation exercise described in tasks 0.1 through 0.3.

**Evidence gate:** All credentials rotated and confirmed working in all
environments. Gitleaks scan returns 0 findings on HEAD of all repos. CORS
wildcards eliminated. Security headers present on all services. Session
timeouts at 30 minutes. PII redaction verified in logs. Pre-commit hooks
installed and running on all 48 repos.

### Phase 1: Dependency Modernization and JBoss Retirement (Months 2-6)

**Objective:** Eliminate every end-of-life runtime. Establish a single,
supported technology stack.

#### 1.1 JBoss EAP 7.4 Retirement (5 services)

| Service | Endpoints | Target | Approach | Effort |
|---|---|---|---|---|
| EEOCWebService | 226 | Java 21 / Spring Boot 4.0 | Service-by-service migration. Largest and most critical - prioritize. | HIGH |
| FedSep | 166 | Retire - FedSep-NG replaces | Accelerate NG frontend. Build new Spring Boot API layer. | HIGH |
| ImsNXG | 196 | Retire - ImsNXG-NG replaces | NG appears near feature-complete. Validate and cutover. | MEDIUM |
| DocumentGeneratorAdapter | minimal | Java 21 / Spring Boot 4.0 | Small service (66 files). Straightforward migration. Fix `getRealPath()` path traversal. | LOW |
| RespondentPortal | 18 | Angular 19 + Spring Boot 4.0 API | New frontend required - 24 JSP pages. Replace `DesEncrypter` with AES-256-GCM. | HIGH |

**Migration path for JBoss to Spring Boot (detailed):**

Each JBoss service follows this sequence. Do NOT attempt to migrate all
five at once. Start with DocumentGeneratorAdapter (smallest) to prove the
process, then EEOCWebService (largest), then the rest.

1. **Inventory the service.** List every servlet, EJB, JSF managed bean,
   and REST endpoint. Count them. Map which ones are called by other
   services vs. called by the frontend vs. called by batch jobs.
   For example, ImsNXG has 196 endpoints, 730 Java files, and 122 JSP
   templates. You need to know this number before you start.

2. **Create a new Spring Boot project.** Use Spring Initializr or copy
   the structure from `FederalHearings-ims-aks` (already on SB 4.0/Java 25)
   as a template. Set up:
   - `pom.xml` with Spring Boot 4.0.x parent
   - Java 21 source/target
   - spring-boot-starter-web, spring-boot-starter-data-jpa,
     spring-boot-starter-security, spring-boot-starter-actuator
   - `spring-cloud-azure-starter-keyvault` for secrets

3. **Replace `javax.*` with `jakarta.*`.** This is a global find-and-replace
   but test after every package. The big ones:
   - `javax.servlet` to `jakarta.servlet`
   - `javax.persistence` to `jakarta.persistence`
   - `javax.inject` to `jakarta.inject`
   - `javax.validation` to `jakarta.validation`
   - `javax.ws.rs` to Spring `@RestController` annotations (different API)

4. **Replace native SQL with Spring Data JPA.** Every `createNativeQuery()`
   call with string concatenation must become a parameterized `@Query` or
   a Spring Data repository method. Example from ImsNXG:
   ```java
   // BEFORE (ImsNXG-master SharedGroupsManager.java:35):
   Query query = em.createNativeQuery(" SELECT a.* " +
       " FROM shared_group_members a WHERE a.staff_seq = " + staffSeq);

   // AFTER:
   @Query(value = "SELECT a.* FROM shared_group_members a WHERE a.staff_seq = :staffSeq",
          nativeQuery = true)
   List<Object[]> findByStaffSeq(@Param("staffSeq") Long staffSeq);
   ```

5. **Replace ObjectInputStream.readObject().** In FedSep
   (`SystemUtil.java:314-317`), replace Java serialization with Jackson:
   ```java
   // BEFORE:
   ObjectInputStream is = new ObjectInputStream(bin);
   Object clone = is.readObject();

   // AFTER:
   ObjectMapper mapper = new ObjectMapper();
   Object clone = mapper.readValue(data, targetClass);
   ```

6. **Create a Dockerfile.** Use the same pattern as modernized services:
   ```dockerfile
   FROM maven:3.9-eclipse-temurin-21 AS build
   WORKDIR /app
   COPY pom.xml .
   RUN mvn dependency:go-offline
   COPY src ./src
   RUN mvn package -DskipTests

   FROM eclipse-temurin:21-jre-jammy
   COPY --from=build /app/target/*.jar app.jar
   EXPOSE 8080
   ENTRYPOINT ["java", "-jar", "app.jar"]
   ```

7. **Run in parallel.** Deploy the new service alongside the old JBoss
   service. Route a percentage of traffic to the new service. Compare
   responses. Run for at least two weeks before full cutover.

#### 1.2 Spring Boot 2.x → 4.0 Migration (6 services)

| Service | Current | Complexity | Key Changes |
|---|---|---|---|
| PrEPAWebService | SB 2.4.1 | HIGH (330 endpoints, 44 deps) | `javax` → `jakarta`, Spring Security 6.x API |
| AuthorizationService | SB 2.3.2 | HIGH (replace deprecated `@EnableAuthorizationServer`) | Full rewrite to Spring Authorization Server |
| UserManagementWebService | SB 2.2.4 | MEDIUM (40 endpoints) | Standard migration + Docker image replacement |
| AzureAdService | SB 2.3.6 | MEDIUM (14 endpoints) | Standard migration + Docker image replacement |
| EmployerWebService | SB 2.2.6 | MEDIUM (78 endpoints) | Standard migration, fix `@CrossOrigin("*")` |
| LitigationWebService | SB 2.6.5 | LOW (minimal endpoints) | Standard migration |

**Also update:** FepaGateway (SB 3.2.1 → 4.0) and IntakeCollectionsService
(SB 3.3.5 → 4.0) - both low effort.

#### 1.3 Deprecated Docker Image Replacement

| Current Image | Replacement |
|---|---|
| `eeoc-jboss74:1.0.0` | Eliminate (migrate to Spring Boot) |
| `openjdk:11-jre-slim` | `eclipse-temurin:21-jre-jammy` |
| `maven:3.6.3-adoptopenjdk-11` | `maven:3.9-eclipse-temurin-21` |
| `gradle:7-jdk11` | `gradle:8-jdk21` |
| `debian:buster-slim` | `debian:bookworm-slim` |
| `alfresco/alfresco-content-repository:6.2.2` | Phase 4 Alfresco decision |
| `alfresco/alfresco-share:6.2.2` | Phase 4 Alfresco decision |

#### 1.4 Broken Cryptography Replacement

The `DesEncrypter` class exists in two repos and must be fully replaced:
- `FedSep-ims-aks-test/src/gov/eeoc/fedsep/util/DesEncrypter.java` (16 references)
- `RespondentPortal-ims-aks/src/gov/eeoc/respondent/utility/DesEncrypter.java` (14 references)

**Write a replacement class** (call it `AesEncrypter` or `SecureEncrypter`):

```java
public class SecureEncrypter {
    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final int GCM_TAG_LENGTH = 128;
    private static final int IV_LENGTH = 12;
    private static final int KEY_LENGTH = 256;
    private static final int PBKDF2_ITERATIONS = 600_000;

    public String encrypt(String plaintext, String passphrase) {
        byte[] salt = new byte[16];
        new SecureRandom().nextBytes(salt);
        byte[] iv = new byte[IV_LENGTH];
        new SecureRandom().nextBytes(iv);

        SecretKeyFactory factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
        KeySpec spec = new PBEKeySpec(passphrase.toCharArray(), salt, PBKDF2_ITERATIONS, KEY_LENGTH);
        SecretKey key = new SecretKeySpec(factory.generateSecret(spec).getEncoded(), "AES");

        Cipher cipher = Cipher.getInstance(ALGORITHM);
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_LENGTH, iv));
        byte[] ciphertext = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));

        // Prepend salt + IV to ciphertext for storage
        byte[] output = new byte[salt.length + iv.length + ciphertext.length];
        System.arraycopy(salt, 0, output, 0, salt.length);
        System.arraycopy(iv, 0, output, salt.length, iv.length);
        System.arraycopy(ciphertext, 0, output, salt.length + iv.length, ciphertext.length);
        return Base64.getEncoder().encodeToString(output);
    }
    // decrypt() is the reverse: extract salt + IV, derive key, decrypt
}
```

**Key differences from the old code:**
- AES-256-GCM instead of DES (brute-force infeasible)
- Random salt per encryption instead of hardcoded bytes
- 600,000 PBKDF2 iterations instead of 19
- Random IV per encryption (GCM requires unique IV)
- No empty catch blocks. Exceptions propagate.

**Migration plan for stored passwords:**
1. Write a one-time migration script that reads each stored password row
2. Decrypt with the old `DesEncrypter` (using the known hardcoded salt)
3. Re-encrypt with the new `SecureEncrypter`
4. Update the database row
5. Remove the old `DesEncrypter` class entirely
6. Grep the codebase for any remaining references: `grep -rn 'DesEncrypter' .`

**Handling corrupt or unrecoverable rows.** The old `DesEncrypter` silently
swallows `InvalidKeyException`, `NoSuchAlgorithmException`, and three other
security exceptions with empty catch blocks. If any of those exceptions
fired during the original encryption, the cipher objects would have been
null, and the stored ciphertext could be corrupt, truncated, or empty. The
migration script must handle this:

- **Happy path:** Row decrypts successfully. Re-encrypt and update.
- **Corrupt/null ciphertext:** Row fails to decrypt (null value, malformed
  base64, `BadPaddingException`, or any other decryption error). Log the
  row ID, the user identifier (hashed, not plaintext), and the failure
  reason. Do NOT update the row. Add the user to a forced-password-reset
  queue.
- **Already-null field:** Row has a null password value (account may never
  have had a password set, or the original encryption failed silently and
  nothing was stored). Flag for review but do not treat as a migration
  error.

After the migration completes, any user whose password could not be
migrated gets a forced password reset on next login. Nobody gets locked
out permanently. The migration report documents exactly how many rows fell
into each category so there are no surprises during rollout.

Run the migration against a copy of the production database first. Compare
row counts: total rows, successfully migrated, forced-reset, already-null.
Only run against production after the numbers are reviewed and accepted.

#### 1.5 Platform Conformance: Local CI and Config Management

Every migrated service gets the unified local CI script. The reference
implementation is at `eeoc-ofs-adr/scripts/local-ci.sh`. Copy it and
adapt the source paths for each repo.

**What local-ci.sh does (in order):**
1. `ruff check` or `checkstyle` - lint
2. `ruff format --check` or `spotless` - format verification
3. `mypy` or `spotbugs` - type checking (informational, non-gating)
4. `pytest` or `mvn test` - unit tests
5. `bandit -r src/` - Python SAST (or `spotbugs` for Java)
6. `semgrep scan --config .semgrep/ --severity ERROR` - PII detection rules (GATING)
7. `pip-audit` or `mvn org.owasp:dependency-check-maven:check` - dependency audit
8. `osv-scanner --recursive .` - Open Source Vulnerability scanner
9. `grype dir:. --fail-on high` - filesystem vulnerability scan (GATING)
10. `gitleaks detect --source .` - secrets scan (GATING)
11. `bash scripts/license-scan.sh` - copyleft license gate
12. `bash scripts/generate-sbom.sh` - CycloneDX SBOM generation
13. `checkov -d deploy/` - IaC scanning (if deploy/ directory exists)
14. `trivy fs --severity CRITICAL,HIGH --exit-code 1 .` - filesystem CVE scan (GATING)
15. `trivy image --severity CRITICAL,HIGH --exit-code 1 $IMAGE` - container scan (GATING)

**Reference files to copy:**
- `eeoc-ofs-adr/scripts/local-ci.sh` - the full orchestration script
- `eeoc-ofs-adr/scripts/generate-sbom.sh` - SBOM generation
- `eeoc-ofs-adr/scripts/license-scan.sh` - copyleft license detection
- `eeoc-ofs-adr/scripts/run_tests_two_loops.sh` - state leak detection for tests

**For each Java ARC repo, create `scripts/local-ci.sh` that runs:**
```bash
#!/bin/bash
set -euo pipefail

echo "=== Lint ==="
mvn checkstyle:check || { echo "FAIL: checkstyle"; exit 1; }

echo "=== Tests ==="
mvn test || { echo "FAIL: tests"; exit 1; }

echo "=== SAST: SpotBugs ==="
mvn spotbugs:check || echo "WARN: spotbugs (non-gating)"

echo "=== SCA: Grype ==="
grype dir:. --fail-on high || { echo "FAIL: grype"; exit 1; }

echo "=== Secrets: Gitleaks ==="
gitleaks detect --source . --redact || { echo "FAIL: gitleaks"; exit 1; }

echo "=== License ==="
# check for GPL/copyleft
mvn license:check || echo "WARN: license (non-gating)"

echo "=== SBOM ==="
cyclonedx-maven-plugin:makeBom || echo "WARN: sbom generation"

echo "=== Container: Trivy ==="
trivy fs --severity CRITICAL,HIGH --exit-code 1 . || { echo "FAIL: trivy"; exit 1; }

echo "ALL GATES PASSED"
```

Any developer should be able to clone a repo, run `bash scripts/local-ci.sh`,
and get a clear PASS or FAIL within five minutes. No excuses about "I didn't
know about that tool" or "I don't have the scanner installed." All required
tools (ruff, mypy, pytest, bandit, semgrep, pip-audit, grype, trivy,
osv-scanner, gitleaks, scancode, checkov, syft, cyclonedx-bom) are
documented in the platform workspace setup guide under "Required local tools."

**Configuration management** also aligns with the platform pattern:

The platform standard (`eeoc-arc-integration-api/app/config/__init__.py`)
loads all configuration from environment variables. Secrets come from Key
Vault in production, from `.env` files (gitignored) in local development.
No properties files with passwords are ever committed.

For Spring Boot services, the equivalent pattern is:
- `spring-cloud-azure-starter-keyvault` resolves secrets directly from
  Key Vault into `@Value("${secret-name}")` properties
- `application.properties` contains only non-secret configuration
  (port numbers, feature flags, service URLs with placeholders)
- `application-LOCAL.properties` is in `.gitignore` for local dev overrides
- The service validates required configuration at startup and refuses to
  start if a required secret is missing, rather than crashing at runtime
  when the first request hits a null password

#### 1.6 New Service Language Standard

When a JBoss service is being fully rewritten (not just migrated), consider
the Python 3.13 / Flask or FastAPI stack that the rest of the EEOC platform
uses. Candidates:

- **AuthorizationService** - a full rewrite is already required (deprecated
  `@EnableAuthorizationServer`). Building the new authorization server in
  Python/FastAPI with the same JWT validation patterns used by
  `eeoc-arc-integration-api` gives us one auth pattern across the platform.
- **RespondentPortal** - no NG replacement exists. Building it as a Flask
  app with Jinja2 templates (matching ADR Portal) rather than Angular + Spring
  Boot API reduces the number of distinct stacks in production.
- **DocumentGeneratorAdapter** - small service (66 files), currently on JBoss.
  A Python rewrite with `python-docx`/`reportlab` would be straightforward.

Existing services that are functional and just need a version bump (PrEPA,
EmployerWS, UserMgmtWS, etc.) stay Java. The standard is: keep what works,
build new things in the platform language.

**Evidence gate:** All services on Java 17+ and Spring Boot 3.2+. Zero JBoss
containers. All Docker images on supported versions. `DesEncrypter` eliminated.
`local-ci.sh` passing on all migrated services. Grype rescan shows > 60% CVE
reduction.

### Phase 2: Security Architecture (Months 4-9)

**Objective:** Implement the security controls that the platform already has
on its newer applications. Align with EO 14028 and OMB M-22-09.

#### 2.1 API Gateway Deployment

Deploy Azure API Management or Spring Cloud Gateway:
- Centralized JWT validation (replaces 18 `SecurityConfig` files)
- Uniform rate limiting per client/endpoint
- CORS policy enforcement at the gateway
- Request/response logging with PII redaction
- `X-Request-ID` propagation
- OpenAPI specification aggregation
- WAF integration (OWASP ModSecurity Core Rule Set)

#### 2.2 Authentication and Authorization Overhaul

**Fix IntakeCollectionsService first** (most urgent within this section):

Open `IntakeCollectionsService-main/src/main/java/gov/eeoc/foi/config/SecurityConfig.java:59`.
The line `.anyRequest().permitAll()` means every endpoint is open to the
internet. Replace with role-based access:

```java
// BEFORE:
.authorizeHttpRequests(auth -> auth
    .anyRequest().permitAll()
)

// AFTER:
.authorizeHttpRequests(auth -> auth
    .requestMatchers("/actuator/health").permitAll()
    .requestMatchers("/api/public/**").permitAll()
    .anyRequest().authenticated()
)
```

Do this for BOTH security filter chains in that file (lines 56 and 101).

**Add method-level authorization to all 918 unprotected endpoints:**

This is the largest single task by volume. For each service, add
`@PreAuthorize` annotations to controller methods. The pattern:

```java
@PreAuthorize("hasRole('ARC_USER')")
@GetMapping("/api/cases/{id}")
public ResponseEntity<Case> getCase(@PathVariable Long id) { ... }

@PreAuthorize("hasRole('ARC_ADMIN')")
@DeleteMapping("/api/cases/{id}")
public ResponseEntity<Void> deleteCase(@PathVariable Long id) { ... }
```

Services sorted by number of unprotected endpoints (do them in this order):
1. PrEPAWebService - 330 endpoints, zero method-level auth
2. FepaGateway - 128 endpoints
3. FederalHearings - 102 unprotected of 261
4. FederalWebService - 96 endpoints
5. EmployerWebService - 78 endpoints
6. IntakeCollectionsService - 46 endpoints
7. SearchDataWebService - 46 endpoints
8. EmailWebService - 44 endpoints
9. UserManagementWebService - 40 endpoints
10. ECMService - 26 endpoints
11. TemplateMgmtWebService - 26 endpoints
12. AzureAdService - 14 endpoints

**Reference implementation** for the auth pattern used by the EEOC platform:
`eeoc-arc-integration-api/app/auth/inbound.py` validates Entra ID JWT tokens
with JWKS auto-discovery and enforces `ARC.Read` / `ARC.Write` app roles.
`eeoc-ofs-adr/adr_webapp/helpers/auth_decorators.py` shows the Flask
equivalent with role-based decorators.

**Replace AuthorizationService:** The current service uses the deprecated
`@EnableAuthorizationServer` from Spring Security OAuth2 (removed in
Spring Security 6.x). It must be rewritten. Two options:
- Spring Authorization Server (Java, if staying in the Java ecosystem)
- FastAPI with python-jose JWT (Python, matching the platform standard)

Either way, the new service must:
- Issue JWTs with app roles (`ARC.Read`, `ARC.Write`, `ARC.Admin`)
- Validate against Entra ID for EEOC staff
- Support Login.gov OIDC for external parties
- Store signing keys in Key Vault, not in YAML files

**Standardize auth patterns across all services:**
- Entra ID for EEOC staff (same as ADR, Triage, OGC Trial Tool)
- Login.gov OIDC + PKCE for external parties (same pattern as ADR Portal)
- Managed identity for service-to-service calls (no shared secrets)

#### 2.3 XXE Remediation

Configure XXE protections on all 42 XML parser instances:

```java
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
```

#### 2.4 SQL Injection Remediation

If ImsNXG is still running (not yet retired in favor of ImsNXG-NG), every
`createNativeQuery()` call with string concatenation must be fixed. There are
1,337 native SQL calls across the legacy repos. The worst files:

- `ImsNXG-master/ImsNXG/src/eeoc/gov/groups/service/SharedGroupsManager.java` - 9 calls
- `ImsNXG-master/ImsNXG/src/eeoc/gov/common/utilities/Lookup.java` - 15+ calls
- `ImsNXG-master/ImsNXG/src/eeoc/gov/common/utilities/TemplateData.java` - complex multi-line queries
- `FedSep-ims-aks-test/src/gov/eeoc/fedsep/` - 587 native queries
- `EEOCWebService-master/src/gov/eeoc/` - 216 native queries
- `DocumentGeneratorAdapter-master/src/eeoc/gov/server/` - 13 native queries

For each one, the fix is the same: replace string concatenation with
parameterized queries. See the example in Section 1.1 step 4 above.

If the service is being retired (ImsNXG, FedSep), confirm the NG replacement
does NOT carry forward the same patterns. Grep the NG repos:
```bash
grep -rn 'createNativeQuery' ImsNXG-NG-ims-aks-test/
grep -rn 'createNativeQuery' FedSep-NG-ims-aks-test/
```

#### 2.5 Input Validation

593 `@RequestParam` parameters and 945 `@PathVariable` parameters have zero
validation. Add Bean Validation annotations to all controller methods:

```java
// BEFORE:
@GetMapping("/api/cases")
public List<Case> search(@RequestParam String chargeNumber) { ... }

// AFTER:
@GetMapping("/api/cases")
public List<Case> search(
    @RequestParam @NotBlank @Size(max = 20) @Pattern(regexp = "[A-Z0-9-]+") String chargeNumber
) { ... }
```

For `@PathVariable`, add validation:
```java
@GetMapping("/api/cases/{id}")
public Case getCase(@PathVariable @Positive Long id) { ... }
```

Add a global validation error handler so all services return consistent
RFC 7807 error responses:
```java
@RestControllerAdvice
public class ValidationExceptionHandler {
    @ExceptionHandler(ConstraintViolationException.class)
    public ProblemDetail handleValidation(ConstraintViolationException ex) {
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, "Validation failed");
        detail.setTitle("Invalid Request");
        return detail;
    }
}
```

Work through the services in the same order as the authorization task (2.2),
starting with PrEPAWebService (595 unvalidated params) and working down.

#### 2.6 Supply Chain Security (EO 14028 Compliance)

- Generate CycloneDX SBOMs for all services in CI/CD
- Implement container image signing with cosign/Notation
- Add Trivy and Grype scans as CI/CD gates (fail on CRITICAL/HIGH)
- Implement dependency update automation (Dependabot or Renovate)
- Establish a vulnerability review SLA: Critical=24h, High=7d, Medium=30d

#### 2.7 OpenAPI and RFC 7807

- Add `springdoc-openapi` to all Spring Boot services
- Implement RFC 7807 Problem Details error responses
- Publish aggregated API specification through API Gateway
- Generate integration schemas from OpenAPI specs for consumption by
  `eeoc-arc-integration-api` and other platform applications

#### 2.8 Platform Conformance: Feature Flags and Audit Logging

**Feature flags.** The platform's newer applications gate every outbound
integration behind a boolean environment variable. If the variable is `false`
or missing, the integration is skipped and the service operates in standalone
mode. This means any service can start, pass its health check, and serve
requests even if every external system is down.

**Reference implementation:**
`eeoc-ofs-adr/staff_portal/shared/unified_access_client.py:23-29`:
```python
UNIFIED_ACCESS_ENABLED: bool = (
    os.environ.get("UNIFIED_ACCESS_ENABLED", "false").lower() == "true"
)
ARC_ROLES_ENABLED: bool = (
    os.environ.get("ARC_ROLES_ENABLED", "false").lower() == "true"
)
```

For Spring Boot services, the equivalent:
```java
@Value("${arc.email-service.enabled:false}")
private boolean emailServiceEnabled;

public void sendNotification(Case caseData) {
    if (!emailServiceEnabled) {
        log.info("Email service integration disabled, skipping notification");
        return;
    }
    // actual call to EmailWebService
}
```

Apply this to every service-to-service call in ARC. The list of integrations
to flag:
- AuthorizationService calls (token validation)
- EmailWebService calls (notification sending)
- ECMService calls (document storage)
- SearchDataWebService calls (Elasticsearch queries)
- ContentGeneratorWebService calls (document generation)
- FepaGateway outbound calls (FEPA state agency communication)
- Any call to external systems (SendGrid, Azure AD, Alfresco)

**Structured audit logging.** Every service gets:

1. **Structured JSON log output.** Replace `log.info("message " + variable)`
   with structured key-value logging:
   ```java
   // BEFORE:
   log.info("Processing case " + caseNumber + " for user " + userId);

   // AFTER:
   log.info("Processing case", Map.of("caseNumber", caseNumber, "userId", "[REDACTED]"));
   ```
   For Spring Boot, configure Logback with `logstash-logback-encoder` for
   automatic JSON output.

2. **X-Request-ID propagation.** Add a servlet filter that reads
   `X-Request-ID` from incoming requests (or generates a UUID if missing)
   and includes it in all outbound calls and log entries. The API Gateway
   from section 2.1 will generate the initial ID; downstream services
   propagate it.

3. **HMAC-SHA256 signed audit records** for case management operations.
   Reference implementation: `eeoc-ofs-adr/shared_code/ai_audit_logger.py`.
   The pattern is dual-write: one copy to Azure Table Storage for fast query,
   one copy to immutable Blob Storage (WORM) for tamper-proof retention.
   NARA requires 7-year retention for case management records.

4. **PII redaction at the logging layer.** Do not leave redaction to individual
   developers. Add a log filter that strips email addresses, SSNs, phone
   numbers, and names from log output before it reaches the log sink.

**Evidence gate:** API Gateway routing all traffic. Rate limiting active. Method-level
authorization on all endpoints. XXE protections on all parsers. Input validation
on all parameters. CI/CD pipeline with SCA gating. OpenAPI specs published.
Feature flags on all integration endpoints. Audit logging operational.
Grype rescan shows > 80% CVE reduction.

### Phase 3: Frontend Modernization and 508 Compliance (Months 6-12)

**Objective:** Complete every stalled NG migration. Achieve WCAG 2.1 AA
compliance across all user-facing applications.

#### 3.1 Complete NG Migrations

| Migration | Current Gap | Work |
|---|---|---|
| ImsNXG → ImsNXG-NG | NG appears near-complete | Validate feature parity, cutover, retire JBoss |
| FedSep → FedSep-NG | Large gap (202 TS vs. 258 JSP + 786 Java) | Significant frontend development |
| RespondentPortal → New | No replacement exists | Full new Angular 19 + Spring Boot API |

#### 3.2 Angular 19 Alignment

Upgrade ImsNXG-NG and FedSep-NG from Angular 16.2 (EOL) to Angular 19.
Remove deprecated `@angular/flex-layout`. Upgrade TypeScript from 4.9.5 to
current. This eliminates the 72+ Trivy findings from the Angular 16 dependency tree.

#### 3.3 USWDS Adoption

AttorneyPortal already uses USWDS 3.7 (the US Web Design System).
Standardize all frontends on USWDS for:
- Federal standard look-and-feel
- Built-in WCAG 2.1 AA compliance in base components
- Consistent cross-app navigation with DAES applications
- Reduced 508 remediation effort (USWDS components pass axe-core by default)

#### 3.4 508 Remediation Checklist

1. Eliminate all inline `onclick` handlers - use Angular event bindings on
   `<button>` and `<a>` elements
2. Add `lang="en"` to all HTML root elements
3. Add `alt` attributes to all images
4. Audit all 291 tables for `<th>` headers with `scope` attributes
5. Run axe-core on every page - zero critical/serious violations
6. Manual keyboard navigation test on all critical workflows
7. Color contrast audit: 4.5:1 text, 3:1 non-text

#### 3.5 Cross-App Navigation

Users should be able to move between ARC portals and the rest of the EEOC
application suite without friction - one login, consistent navigation,
consistent look and feel:

- Shared USWDS header/navigation component across all EEOC applications
- SSO session sharing via Entra ID / Login.gov (one authentication for all apps)
- Deep linking between related data across applications (e.g., from an ADR
  mediation case to the corresponding ARC charge record)
- Shared CSS design tokens so visual style is consistent regardless of which
  app is serving the page

#### 3.6 Platform Conformance: 508 Enforcement in CI

The platform's existing applications enforce WCAG 2.1 AA compliance at two
checkpoints: a pre-commit lint hook that catches regressions when a developer
saves a template file, and axe-core automated tests that run against rendered
pages in the test suite. ARC frontends need both:

- Pre-commit 508 lint hook on all frontend repos
- axe-core integration tests for every page in every Angular and Next.js app
- Two-loop test execution (`run_tests_two_loops.sh`) to catch state leakage
  between test runs - a pattern the platform already uses to prevent false
  passes from shared test state

**Evidence gate:** All JSP frontends retired. All Angular apps on version 19.
axe-core passes on all pages. USWDS adopted. Cross-app navigation functional.
Pre-commit 508 hook and axe-core tests in CI on all frontend repos.

### Phase 4: Consolidation and Continuous Security (Months 10-18)

**Objective:** Establish sustainable operational posture. Prepare for ongoing
compliance and integration.

#### 4.1 Alfresco Decision

Alfresco 6.2.2 is EOL. Choose one:

| Option | Recommendation |
|---|---|
| Upgrade to Alfresco 23.x | If ECM features actively used |
| Migrate to Azure Blob + metadata | If Alfresco is primarily file storage |
| Maintain 6.2.2 with manual patching | **Not recommended** - no vendor support |

#### 4.2 Infrastructure Modernization

- Terraform or Bicep for all Azure resources (replace shell scripts)
- Standardized Helm base chart across all services
- GitOps deployment (ArgoCD or Flux)
- Azure Key Vault CSI driver for all Kubernetes-level secrets (complements
  the application-level Key Vault starter deployed in Phase 0; see the note
  in Section 0.2 on delivery mechanisms)
- Microsoft Defender for Containers (runtime protection)
- Azure Monitor + OpenTelemetry for distributed tracing

#### 4.3 Test Coverage

| Tier | Current | Target |
|---|---|---|
| Core business services | ~5% | 60% line coverage |
| Support services | ~3% | 50% |
| Frontend (Angular/Next.js) | ImsNXG-NG only | 40%+ all apps |
| Infrastructure | 0% | Helm unittest + Terraform validate |

#### 4.4 Enterprise Platform Integration

With the API Gateway, OpenAPI specs, and standardized auth from Phase 2 in
place, ARC becomes a first-class participant in the EEOC enterprise platform:

1. **Structured integration endpoints** - `eeoc-arc-integration-api` exposes
   ARC operations as typed, documented endpoints with role-based access
   (`ARC.Read`, `ARC.Write`) consumed by ADR, Triage, OGC Trial Tool,
   and any future application
2. **Health check aggregation** - unified `/health` endpoint per service,
   aggregated at the API Gateway for platform-wide monitoring
3. **Event-driven integration** - Azure Service Bus for async operations
   (case status changes, document uploads, charge updates) so consuming
   applications do not poll
4. **HMAC-signed audit records** for case management operations that cross
   system boundaries - required for NARA 7-year retention and traceable
   end-to-end across applications

#### 4.5 Repository Consolidation

| Repository | Action | Reason |
|---|---|---|
| EmailWebServiceNG-master-pe | Archive | Superseded (Java 8, deserialization vuln) |
| MessagingPoc-master | Archive | POC, Spring4Shell present, Java 8 |
| ImsNXG-master | Archive after NG cutover | Replaced by ImsNXG-NG |
| FedSep-ims-aks-test | Archive after NG cutover | Replaced by FedSep-NG |
| jboss-docker-master | Archive after Phase 1 | No consumers after JBoss retirement |
| Utilities-master | Publish as Maven artifact | Stop using as standalone repo |
| AT_ARC_UI-ARC_UI_Automation | Update | Align Selenium tests with NG frontends |

#### 4.6 Repository Archival Policy

Stale, superseded, and proof-of-concept repositories represent a real risk
even when they are not deployed. Developers looking for code to reuse will
find patterns in old repos and copy them into new work. If the old repo
contains hardcoded credentials, DES encryption, `ObjectInputStream` usage,
CORS wildcards, or any of the other patterns identified in this audit, those
patterns propagate into new code. This has likely already happened across the
ARC codebase (the identical `DesEncrypter` class in both FedSep and
RespondentPortal is evidence of copy-paste reuse of insecure code).

**Archival process for each decommissioned repository:**

1. **Confirm the repo is no longer deployed.** Check the production Helm
   configs (`azure-extmgmt-helm-master/configs/prod/`), the
   `create-secrets.sh` script, and the AKS cluster to verify no pods are
   running from this repo's container image.

2. **Run a final security scan.** Execute `gitleaks detect --source .` and
   `grype dir:.` on the repo. Document the findings for the security record.

3. **Remove all secrets from git history.** Even though the repo is being
   archived, its git history may still be cloned. Use BFG Repo-Cleaner or
   `git filter-repo` to purge any credentials from history before archiving.

4. **Archive the repository in GitHub.** Use Settings > Archive this
   repository. This makes the repo read-only: no new commits, no new
   branches, no new PRs. The code remains visible for historical reference
   but cannot be modified.

5. **Add a DEPRECATED notice.** Before archiving, add a `DEPRECATED.md` at
   the repo root:
   ```markdown
   # DEPRECATED

   This repository is archived and no longer maintained. Do not use code
   from this repository in new work. It contains known security
   vulnerabilities that will not be patched.

   Replacement: [name of replacement repo, if applicable]
   Archived: [date]
   Reason: [brief explanation]
   ```

6. **Remove from CI/CD pipelines.** Delete any build triggers, webhooks,
   or pipeline configurations that reference the archived repo. Remove
   its container image from ACR if it is no longer used by any environment.

7. **Document in this plan.** Update the repository consolidation table
   above with the archive date and the name of the replacement (if any).

**Repositories to archive immediately (Phase 0, no dependencies):**

The 42 dormant repos (Tier 5, not updated since 2024 or earlier) should
be archived in GitHub during Phase 0. These repos serve no active purpose
but remain cloneable, searchable, and available for copy-paste reuse by
any developer with org access. The identical `DesEncrypter` class found
in both FedSep and RespondentPortal is evidence that insecure patterns
have already propagated through code reuse. Archiving removes the temptation.

Two repos are already archived in GitHub (azure-extmgmt-test,
azure-extmgmt-uat). The remaining 40 dormant repos should follow:

Priority 1 (contain known vulnerabilities or superseded code):
- EmailWebServiceNG (superseded, contains ObjectInputStream deserialization)
- MessagingPoc (POC, contains Spring4Shell CVE-2022-22965)
- SecurityServices (Dec 2021, likely contains EOL dependencies)
- ARC_EmailWebService (Jan 2022, superseded)
- ARC_UI (Jan 2022, superseded)

Priority 2 (ancient, pre-date current architecture):
- DMS (May 2014), Maintainer (Jun 2015), OFO (Jun 2015),
  TDCS-FILE_EXPORT (Jun 2015), ImsServiceClient (Jul 2015),
  NVS_WebServices (Jun 2016), eVersity (Sep 2016), CTS (Oct 2016),
  NVS (Jan 2017)

Priority 3 (abandoned test automation and tooling):
- AT_ECMService, AT_FepaGateway, AT_PrEPAWebService,
  AT_SearchDataWebService, AT_UserManagementWebService (all Feb 2021)
- AT_ARC_REGRESSION (Jun 2022), SeleniumTestScripts (Dec 2021),
  PerformanceTestScripts (May 2021)

Priority 4 (abandoned infrastructure and utilities):
- alfresco-azurerm-aks-staging, alfresco-azurerm-terraform-staging,
  alfresco-terraform-azurerm-aks-devops (all 2021)
- alfresco-devops-github-runner-docker, alfresco-bulk-import-staging (2022-2023)
- STANDALONE_SPRINGBOOT (Jun 2020), LdapWebService (Apr 2019),
  EmployerDbIdAssigner (Feb 2019), EEOCPhoneDirectory (Jul 2020, ASP.NET),
  ImsDataWebService (Aug 2021), IigGatewayAzureFunction (Jun 2021),
  TDCS (Jun 2021), AccountCertification (Oct 2022)

Priority 5 (empty or confirmed unused Tier 4 repos):
- UIComponentLibrary (empty, no source content)
- FED_MD715_TEST_Utility (unused, MD-715 process discontinued per Administration)
- FMW_Repository (empty, no source content)
- Database (unused, materials from ~4 years ago)
- Database_Release_Scripts (empty shell)
- PublicPortalWorkflow (empty shell)

**Repositories to archive after migration (Phase 1):**
- jboss-docker-master (after all JBoss services are retired)

**Repositories to archive after NG cutover (Phase 3):**
- ImsNXG (after ImsNXG-NG is validated and cut over)
- FedSep (after FedSep-NG is validated and cut over)

**Ongoing policy:** Any time a service is replaced or a repository stops
receiving active development, it follows this same 7-step process. Do not
leave unmaintained code accessible in an active state. Read-only archived
repos are safe to reference for historical context; active repos with
unpatched vulnerabilities are a liability that invites reuse of dangerous
code.

#### 4.7 Mandatory Security Tooling Standard

Every active ARC repository must replicate the security tooling stack that
the EEOC platform already uses on its newer applications. This is not
optional and not phased. Phase 0 installs the pre-commit hooks; Phase 1
adds the local CI script. By Phase 2, every repo should be running the
full stack. The tooling catches problems at three checkpoints: on every
commit (pre-commit hooks), before every push (local CI), and on every PR
(CI/CD pipeline gates).

**Checkpoint 1: Pre-Commit Hooks (runs on every `git commit`)**

Every repo gets a `.pre-commit-config.yaml` with these hooks. The reference
file is `eeoc-arc-integration-api/.pre-commit-config.yaml`.

| Hook | Purpose | Blocking? | Reference Config |
|---|---|---|---|
| **gitleaks** (v8.18.0+) | Scans staged changes for secrets: passwords, API keys, private keys, tokens, connection strings. Uses regex + entropy detection. | Yes - commit is rejected if secrets found | `repos: [{repo: https://github.com/gitleaks/gitleaks, rev: v8.18.0, hooks: [{id: gitleaks}]}]` |
| **ruff** (Python) or **checkstyle** (Java) | Lint and auto-format. Ruff runs `--fix` to auto-correct safe issues. | Yes - commit is rejected on unfixed lint errors | `repos: [{repo: https://github.com/astral-sh/ruff-pre-commit, rev: v0.8.6, hooks: [{id: ruff, args: [--fix]}, {id: ruff-format}]}]` |
| **lint-508** | Scans HTML and CSS files for WCAG 2.1 AA violations: missing alt text, missing lang attributes, contrast ratio issues, missing form labels. | Yes - commit is rejected on 508 violations in HTML/CSS | Local hook, runs on `types_or: [html, css]` |
| **pre-commit-verify** | Orchestrates the fast subset of local-ci.sh: ruff/lint, semgrep PII rules (gating), gitleaks (gating), lint-508, and bandit (advisory). | Yes - commit is rejected on any gating failure | Local hook, `always_run: true`, `stages: [pre-commit]` |

**Setup for each repo (one-time, 10 minutes per repo):**

```bash
# 1. Install pre-commit
pip install pre-commit

# 2. Copy config from platform reference
cp ../eeoc-arc-integration-api/.pre-commit-config.yaml .

# 3. For Java repos, replace the ruff hooks with checkstyle:
#    (edit .pre-commit-config.yaml, replace ruff section)

# 4. Install hooks into the repo's .git/hooks/
pre-commit install

# 5. Verify against all existing files
pre-commit run --all-files

# 6. Fix any findings before proceeding
```

**What happens when a hook blocks a commit:** The developer sees a clear
error message explaining what failed and where. For gitleaks, it shows the
file, line, and rule that matched. For ruff, it shows the lint violation.
The developer fixes the issue and commits again. No override mechanism
exists. Developers cannot bypass pre-commit hooks without explicitly
uninstalling them (`pre-commit uninstall`), which is a deliberate action
that will be visible in code review.

**Checkpoint 2: Local CI Script (runs before every push/PR)**

Every repo gets `scripts/local-ci.sh`. The reference implementation is
`eeoc-ofs-adr/scripts/local-ci.sh`. The script runs 15+ security and
compliance gates in sequence and reports PASS/FAIL for each.

**Mandatory gates (blocking - must pass before PR creation):**

| Gate | Tool | What It Catches | Reference |
|---|---|---|---|
| Lint | ruff (Python) / checkstyle (Java) | Code style, import ordering, unused variables | ruff config in `pyproject.toml` or `ruff.toml` |
| Format | ruff format / spotless | Inconsistent formatting | Same config |
| Tests | pytest / mvn test | Regressions, broken logic | `tests/` directory |
| PII Detection | semgrep with `.semgrep/pii-leak-detection.yml` | PII fields (email, SSN, phone, name, DOB) passed to log statements, exception messages, or API responses without hashing | Reference: `eeoc-ofs-adr/.semgrep/pii-leak-detection.yml` |
| Secrets | gitleaks | Credentials in any file (not just staged) | Built-in rules + optional `.gitleaks.toml` overrides |
| SCA Vulnerabilities | grype | Known CVEs in dependencies (CRITICAL/HIGH) | `grype dir:. --fail-on high` |
| Container CVEs | trivy | Known CVEs in container images and filesystem | `trivy fs --severity CRITICAL,HIGH --exit-code 1 .` |
| License Compliance | license-scan.sh / pip-licenses | GPL/copyleft dependencies that cannot ship in federal software | `scripts/license-scan.sh` |

**Advisory gates (non-blocking - findings reported but do not fail the build):**

| Gate | Tool | What It Catches |
|---|---|---|
| Type Checking | mypy (Python) / spotbugs (Java) | Type errors, null safety issues |
| SAST | bandit (Python) / spotbugs (Java) | Security anti-patterns, weak crypto, exec() usage |
| Dependency Audit | pip-audit / OWASP dependency-check | Known vulnerabilities (different DB than grype, catches different findings) |
| OSV Scanner | osv-scanner | Google Open Source Vulnerabilities database |
| IaC Scanning | checkov | Terraform/Bicep/Helm misconfigurations, CIS benchmarks |
| License Inventory | pip-licenses (Python) / maven license plugin (Java) | Per-component license inventory in CSV and JSON format |
| License Deep Scan | scancode-toolkit | File-level license and copyright detection across all source files (slow) |
| SBOM Generation | CycloneDX (cyclonedx-bom) + syft | Software Bill of Materials in CycloneDX JSON format |
| Secrets Baseline | detect-secrets | Baseline-managed secrets detection (complements gitleaks) |

**Full tooling inventory (all tools required on developer machines):**

Python tools (install via pip):
```
ruff mypy pytest pytest-cov hypothesis bandit semgrep pip-audit pip-licenses
cyclonedx-bom scancode-toolkit pre-commit detect-secrets
```

Binary tools (install to `~/.local/bin/` or system path):
```
gitleaks syft grype trivy osv-scanner checkov
```

CI-only tools (not required locally):
```
cosign          # container image signing (keyless OIDC, requires CI runner)
```

**Checkov runs in its own virtual environment** at `~/.local/checkov-venv/`
due to a dependency conflict with cyclonedx-python-lib. Install separately:
```bash
python3 -m venv ~/.local/checkov-venv
~/.local/checkov-venv/bin/pip install checkov
ln -s ~/.local/checkov-venv/bin/checkov ~/.local/bin/checkov
```

**Checkpoint 3: CI/CD Pipeline (runs on every PR)**

The CI/CD pipeline runs the same `local-ci.sh` script in a clean
environment. If local-ci.sh passes on the developer's machine, it passes
in CI. No surprises.

Additional CI-only gates:
- Container image build and scan (`trivy image`)
- Container image signing (cosign, keyless OIDC in GitHub Actions)
- axe-core 508 tests against rendered pages (frontend repos)
- Two-loop test execution for state leak detection
  (reference: `eeoc-ofs-adr/scripts/run_tests_two_loops.sh`)

**Semgrep PII Rules (critical - must be replicated to every repo)**

The semgrep PII detection rules are the most important gating check after
gitleaks. They prevent developers from logging, returning in API responses,
or including in exception messages any field that matches PII patterns:
`email`, `ssn`, `social_security`, `phone`, `first_name`, `last_name`,
`street_address`, `date_of_birth`, `dob`, `password`, `secret`, `token`,
`api_key`, `connection_string`.

The rules are defined in `eeoc-ofs-adr/.semgrep/pii-leak-detection.yml`.
Copy this file to `.semgrep/` in every ARC repo. For Java repos, adapt the
patterns from Python logging calls to Java `log.info()` / `log.debug()`
calls:

```yaml
# Java equivalent PII rule (add to .semgrep/pii-leak-detection.yml)
- id: pii-in-java-log
  patterns:
    - pattern-either:
        - pattern: log.$METHOD("...", (String) $VAR)
        - pattern: log.$METHOD("..." + $VAR)
    - metavariable-regex:
        metavariable: $VAR
        regex: "(?i).*(email|ssn|phone|firstName|lastName|dateOfBirth|password|secret|token|apiKey).*"
  message: >
    PII field passed to log statement. Hash or redact before logging.
  severity: ERROR
  languages: [java]
  metadata:
    cwe: "CWE-532"
```

Run `semgrep scan --config .semgrep/ --severity ERROR --error <src-dirs>`
to verify. The `--error` flag makes semgrep return exit code 1 on any
ERROR-severity finding, which causes local-ci.sh to fail.

**Jackson Deserialization Safety Rule (critical for Phase 1 migrations)**

The Phase 1 migration plan replaces `ObjectInputStream.readObject()` with
Jackson's `ObjectMapper.readValue()`. Jackson is safer by default, but it
can be made vulnerable to the same class of gadget-chain RCE attacks if a
developer enables polymorphic default typing. This has happened in
production systems (CVE-2017-7525, CVE-2019-12384, CVE-2020-36518, among
others). Add this rule to `.semgrep/` alongside the PII rules to prevent
trading one deserialization RCE for another:

```yaml
- id: jackson-unsafe-deserialization
  patterns:
    - pattern-either:
        - pattern: $MAPPER.enableDefaultTyping(...)
        - pattern: $MAPPER.activateDefaultTyping(...)
        - pattern: "@JsonTypeInfo(use = JsonTypeInfo.Id.CLASS, ...)"
        - pattern: "@JsonTypeInfo(use = JsonTypeInfo.Id.MINIMAL_CLASS, ...)"
  message: >
    Unsafe Jackson polymorphic deserialization. enableDefaultTyping()
    and CLASS/MINIMAL_CLASS type info allow an attacker to specify
    arbitrary classes for instantiation, enabling remote code execution
    via gadget chains. Use explicit @JsonSubTypes with a closed set of
    permitted subtypes instead.
  severity: ERROR
  languages: [java]
  metadata:
    cwe: "CWE-502"
    owasp: "A08:2021"
```

This rule gates at ERROR severity, which means a commit that enables
default typing will be blocked by both the pre-commit hook and
local-ci.sh. The correct alternative is to use `@JsonSubTypes` with an
explicit list of permitted classes:

```java
// BLOCKED by semgrep (unsafe):
mapper.enableDefaultTyping();

// CORRECT (safe):
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME)
@JsonSubTypes({
    @JsonSubTypes.Type(value = EmailForm.class, name = "email"),
    @JsonSubTypes.Type(value = CaseForm.class, name = "case")
})
public abstract class BaseForm { }
```

**Gitleaks Custom Configuration**

Some repos need a `.gitleaks.toml` to suppress false positives (test
fixtures, example data, documentation). The reference file is
`eeoc-ofs-adr/.gitleaks.toml`. Only suppress findings that are confirmed
false positives. Never suppress a finding to make the build pass without
verifying the credential is not real.

```toml
# .gitleaks.toml - only for confirmed false positives
[allowlist]
  paths = [
    '''example_data/''',
    '''docs/.*\.md''',
  ]
```

**Ongoing policy:** Any new repository created in the EEOC portfolio starts
with these three files copied from the platform reference repos before any
application code is written:
1. `.pre-commit-config.yaml` (from `eeoc-arc-integration-api`)
2. `.semgrep/pii-leak-detection.yml` (from `eeoc-ofs-adr`)
3. `scripts/local-ci.sh` (from `eeoc-ofs-adr`, adapted for source paths)

No PR is merged without `local-ci.sh` passing. No exception. The tooling
is the floor, not the ceiling.

**Release gate: zero known CRITICAL/HIGH vulnerabilities.**

The goal is simple: when Black Duck, Grype, Trivy, or any external security
vendor scans the ARC codebase at any release point, the result is zero
CRITICAL and zero HIGH findings. Not "under 50." Not "reduced by 95%." Zero.

This is achievable because every tool in the stack above runs continuously.
If a new CVE is published for a dependency we use, Dependabot or Renovate
creates a PR within 24 hours. If the PR passes local-ci.sh (which runs
grype and trivy), it merges. If it fails, a developer investigates within
the SLA (Critical: 24 hours, High: 7 days). By the time a vendor runs their
scan, the finding is already patched.

The tooling makes this sustainable, not heroic. It is not a one-time cleanup
followed by three years of drift. It is a process that keeps the count at
zero as a steady state. Every SBOM generated by `scripts/generate-sbom.sh`
and every license inventory from `scripts/license-scan.sh` becomes release
evidence that goes into the audit package alongside the scan results.

To be explicit about what "zero at release" means:
- `grype dir:. --fail-on high` returns exit code 0
- `trivy fs --severity CRITICAL,HIGH --exit-code 1 .` returns exit code 0
- `trivy image --severity CRITICAL,HIGH --exit-code 1 <image>` returns exit code 0
- `gitleaks detect --source .` returns zero findings
- `semgrep scan --config .semgrep/ --severity ERROR --error <src>` returns exit code 0
- `pip-licenses --fail-on="GNU General Public License"` returns exit code 0
- CycloneDX SBOM is generated and archived with the release

If any of those commands fail, the release does not ship. Period.

#### 4.8 Continuous Compliance and Platform Conformance (Steady State)

At this point, ARC repositories operate under the same standards as the rest
of the EEOC application portfolio. The steady-state posture:

- `local-ci.sh` runnable on every repo - all 20+ gates passing
- Pre-commit hooks (gitleaks, linter, 508 lint) on every repo
- Trivy/Grype scan on every PR (gate on CRITICAL/HIGH)
- axe-core in CI for every frontend change
- SBOM generation and publication on every release
- Feature flags on all integration endpoints, health checks passing with
  integrations disabled
- Structured JSON logging with PII redaction and `X-Request-ID` propagation
- HMAC-signed audit records on sensitive operations
- Quarterly vulnerability review and dependency update cycle
- Annual penetration test
- Dependabot or Renovate managing dependency updates with automated PR creation

The point of all this is maintainability. The EEOC should not need another
audit like this one in three years. The guardrails prevent regression, the
automation catches drift, and the unified tooling means any developer who
can work on ADR Portal can also work on ARC without learning a different
set of practices.

**Evidence gate:** Alfresco upgraded or replaced. IaC in Terraform/Bicep. Test
coverage at targets. Platform integration functional. Continuous scanning in
CI/CD. Final Grype + Trivy scan shows zero CRITICAL and zero HIGH findings. All repos pass
`local-ci.sh`.

---

## 9. Risk Matrix

| Risk | Likelihood | Impact | If Unaddressed |
|---|---|---|---|
| **Credential exploitation** from committed secrets | Already exposed | CRITICAL | Unauthorized database access, token forgery, data exfiltration |
| **Spring4Shell (CVE-2022-22965)** exploitation | HIGH - actively exploited since 2022 | CRITICAL | Remote code execution on any affected service |
| **DES-encrypted passwords** recovered | HIGH - minutes to brute-force | CRITICAL | Mass credential compromise for stored passwords |
| **XXE exploitation** on any of 42 unprotected parsers | MEDIUM | HIGH | Local file disclosure, SSRF, denial of service |
| **Deserialization RCE** via ObjectInputStream | MEDIUM | CRITICAL | Remote code execution on EmailWebServiceNG and FedSep |
| **CORS wildcard** cross-origin data theft | MEDIUM | HIGH | Authenticated data accessible from any website |
| **508 audit finding** | HIGH - 863 violations minimum | HIGH | Federal compliance violation, potential legal action |
| **OIG or FISMA audit** flags 2,000+ known CVEs | HIGH | HIGH | Audit finding, potential funding impact |
| **Rate-limit abuse / brute force** | MEDIUM | MEDIUM | Account takeover, denial of service |
| **SQL injection** via legacy native queries | MEDIUM | CRITICAL | Database compromise, data exfiltration |

---

## 10. Success Criteria

| Metric | Baseline (Now) | Phase 0 | Phase 1 | Phase 2 | Phase 4 |
|---|---|---|---|---|---|
| Gitleaks findings | 332 | **0** | 0 | 0 | 0 |
| Grype Critical+High CVEs | 350 | 350 | < 150 | < 70 | **0** |
| EOL runtime versions | 10 services | 10 | **0** | 0 | 0 |
| JBoss containers | 5 | 5 | **0** | 0 | 0 |
| CORS wildcard services | 5 | **0** | 0 | 0 | 0 |
| CSRF-disabled browser services | 3+ | **0** | 0 | 0 | 0 |
| Endpoints without method-level authz | 918 | 918 | 918 | **0** | 0 |
| Rate-limited endpoints | 0 / 1,177 | 0 | 0 | **1,177** | 1,177 |
| XXE-unprotected XML parsers | 42 | 42 | 42 | **0** | 0 |
| Unvalidated parameters | 1,538 | 1,538 | 1,538 | **0** | 0 |
| Security headers (CSP, HSTS, etc.) | 0 / 19 services | **19** | 19 | 19 | 19 |
| 508 critical violations | 863+ | 863 | 863 | 863 | **0** |
| OpenAPI specifications | 0 | 0 | 6 | **19** | 19 |
| Test coverage (avg) | ~5% | ~5% | 20% | 30% | **50%+** |
| Broken crypto (DES) | 2 implementations | 2 | **0** | 0 | 0 |
| **Platform Conformance** | | | | | |
| Repos with pre-commit hooks | 0 / 48 | **48** | 48 | 48 | 48 |
| Repos with `local-ci.sh` passing | 0 / 48 | 0 | **19** (services) | 30+ | **48** |
| Services with feature-flagged integrations | 0 | 0 | 0 | **19** | 19 |
| Services with structured JSON logging | 0 | 0 | 6 | **19** | 19 |
| Services with HMAC audit logging | 0 | 0 | 0 | **19** | 19 |
| Repos passing axe-core 508 tests | 0 | 0 | 0 | 0 | **6** (frontends) |

---

## 11. Attestation and Document Control

### Attestation

- [x] All 48 repositories in `eeoc-arc-payloads/` have been inventoried and classified
- [x] Security findings are verified by automated tooling (Gitleaks, Trivy, Grype) and manual code analysis
- [x] Black Duck 2,000+ vulnerability count corroborated at order-of-magnitude and root causes identified
- [x] Codebase age is estimated from multiple independent evidence streams
- [x] Section 508 findings are from automated pattern scanning of all frontend source
- [x] Federal compliance gaps mapped to EO 14028, OMB M-22-09, FISMA, Section 508, and NIST 800-53
- [x] All CRITICAL and HIGH CVE IDs are from scanning tool output, not estimated
- [x] No credentials from this audit have been transmitted outside the local environment

**Authorized Official:** ________________________________
**Date:** ________________________________

---

### Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | May 2026 | Derek Gordon / OCIO | Initial audit with tool-verified findings and phased remediation plan |
| 1.1 | May 2026 | Derek Gordon / OCIO | Added platform conformance requirements, live/stale repo classification, new service language standard, codebase age analysis |
| 1.2 | May 2026 | Derek Gordon / OCIO | Expanded phases with developer-level instructions, added repository archival policy, mandatory security tooling standard, zero-vulnerability release gate |
| 1.3 | May 2026 | Derek Gordon / OCIO | Updated to full 85-repo inventory from GitHub activity data, classified all repos into 5 tiers, identified 42 dormant repos for immediate archival, corrected scope from 48 to 85 total |
| 1.4 | June 2026 | Derek Gordon / OCIO | Re-verified findings against live source: corrected CORS heading to 5 services, reconciled EOL service count, updated SSRF and 508 onclick counts to reproducible figures, added explicit scan date, aligned platform references to Data and AI Enterprise System (DAES) and current component names, added service-count conventions |
