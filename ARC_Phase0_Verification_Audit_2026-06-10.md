# ARC Phase 0 Verification Audit
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Four-pass verification of every Phase 0 task card in
`ARC_Developer_Remediation_Runbook.md` against the actual `eeoc-arc-payloads/`
source (48 repositories, checked 2026-06-10). The trigger was the confirmed XXE
data flow in `ARC_Audit_Findings_Addendum_2026-06-10.md`: an exploitable,
secret-exfiltrating vulnerability that Phase 0 does not address. That raised the
question of what else Phase 0 misses.

Each card was run through four passes:

- **Pass 1 - Claim accuracy.** Does every cited file, line, and count exist as
  stated?
- **Pass 2 - Completeness.** Does the card cover every instance of its problem
  class, or does it miss services and files?
- **Pass 3 - Fix correctness.** Is the prescribed remediation correct and
  sufficient for the stated problem?
- **Pass 4 - Coverage gaps.** What is exploitable today and absent from Phase 0
  entirely?

Runbook corrections that come out of this audit are written into a separate
file, `ARC_Developer_Remediation_Runbook_v2_Phase0.md`, not back into the
delivered runbook. Dependency findings below CRITICAL/HIGH are handled in
`ARC_Secondary_Scan_Findings_2026-06-10.md`.

---

## Verdict Summary

| Card | Pass 1 Accuracy | Pass 2 Completeness | Verdict |
|---|---|---|---|
| P0-01 DB passwords | Accurate (6/6 keys present) | Complete | PASS |
| P0-02 OAuth/svc passwords | Mostly accurate | FepaGateway count off | MINOR FIX |
| P0-03 Private keys | **Wrong count and scope** | Misses ADR_PORTAL keys | **FIX** |
| P0-04 Other credentials | Accurate | Complete | PASS |
| P0-05 CORS wildcards | Accurate (5/5 confirmed) | Complete | PASS (base report was wrong, not this) |
| P0-06 Session timeouts | Accurate | **Misses RespondentPortal 5-hr** | **FIX** |
| P0-07 .gitignore | Accurate | Complete | PASS |
| P0-08 Pre-commit hooks | Accurate | Complete | PASS |
| P0-09 Secrets to Key Vault | Accurate | Complete | PASS |
| P0-10 History scrub | Accurate | Complete | PASS |
| P0-11 CSRF | **Wrong service listed** | **Misses 4 services** | **FIX** |
| P0-12 Security headers | Accurate (0 set) | Complete | PASS |
| P0-13 PII logs | Accurate (3/3 sites) | Scoped, acknowledged | PASS |

Four cards need correction. Five exploitable-today problem classes are missing
from Phase 0 entirely (Pass 4, below).

---

## Pass 1 and 2 - Per-Card Verification

### P0-01 - DB passwords: PASS

All six password keys are present in the cited file.

```text
$ for k in IMS_DATABASE_SERVICE_USER_PASSWORD IMS_DATABASE_REPORT_USER_PASSWORD \
    IMS_DATABASE_FEDSEP_USER_PASSWORD FEDSEP_AWSDB_PASSWORD FEDSEP_BODDB_PASSWORD \
    FEDSEP_DATABASE_PASSWORD; do grep -c "$k" \
    azure-extmgmt-helm-master/configs/prod/ims-prod-secrets.yaml; done
1  1  1  1  1  1
```

Claim holds. No change.

### P0-02 - OAuth/service passwords: MINOR FIX

FederalHearings and EmailWebService claims are exact.

```text
$ sed -n '75p;77p' FederalHearings-ims-aks/src/main/resources/application.properties
app.oauth.password=password123
app.oauth.client.password=prepa2019

$ sed -n '14,16p' EmailWebService-ims-aks-test/src/main/resources/application-LOCAL.properties
spring.datasource.hikari.password=admindev2019
spring.datasource.username=s_admin
spring.datasource.password=admindev2019
```

FepaGateway count is off. The card says "9 OAuth passwords starting at line 62."
Actual is **7** in the `app.oauth.*.password` family, plus one separate
publicportal token password at line 179.

```text
$ grep -nE '\.password\s*=' FepaGateway-ims-aks/src/main/resources/application.properties
62:app.oauth.portal.password=password123
64:app.oauth.client.password=prepa2019
68:app.oauth.foia.password=password123
76:app.oauth.iig.password=password123
80:app.oauth.attorney-portal.password=password123
86:app.oauth.foi-intake.password=password123
94:app.oauth.scheduler.password=password123
179:app.publicportal.token.password = LrldQiryelzwhu@epnb23wrtest$
```

Fix: change "9 OAuth passwords" to "7 OAuth passwords plus 1 public-portal token
password (line 179)." The token at 179 must be rotated too; it is a live
credential the current wording could let a developer skip.

### P0-03 - Private keys: FIX (accuracy and scope)

This is the card the audit labels "most dangerous single finding," and its
headline number is wrong.

```text
$ grep -rn 'BEGIN RSA PRIVATE KEY\|BEGIN PRIVATE KEY' AuthorizationService-ims-aks/ | wc -l
10
$ grep -rln 'BEGIN ... PRIVATE KEY' AuthorizationService-ims-aks/   # unique env files
  application.yaml      application-DEV.yaml   application-TEST.yaml
  application-UAT.yaml  application-TRAIN.yaml
```

There are **5 unique signing keys** (one per environment), which appear as 10
PEM blocks because the repo contains a nested duplicate checkout. The card body
itself lists exactly these 5 files, so "14" contradicts the card's own steps.

The "14" is the estate-wide gitleaks `private-key` rule count from the base
report. Those 14 are not all in AuthorizationService. Six are in ADR_PORTAL and
the card does not mention them:

```text
$ grep -rln 'BEGIN ... PRIVATE KEY' ADR_PORTAL-main/
adr_webapp/auth/logingov_client.py          <- live Login.gov signing key
adr_webapp/tests/test_config_validation.py  <- test fixture, still committed PEM
adr_webapp/tests/test_logingov_client.py    <- test fixture
docs/Azure_Portal_*_Provisioning_Guide.md   <- PEM material pasted into 3 docs
```

Fix: retitle to "Rotate the 5 OAuth signing keys in AuthorizationService," state
the count is 5 unique keys, and add ADR_PORTAL's Login.gov key plus the
doc-embedded PEM blocks as their own card (proposed P0-17 in the v2 file). The
Login.gov key signs `private_key_jwt` client assertions; if real it forges this
agency's identity to Login.gov and must rotate with the rest.

### P0-04 - Other credentials: PASS

ACR token, SendGrid tokens, storage key, and App Insights string are all present
in the cited files (confirmed against `create-secrets.sh` secret names and the
helm prod manifests in the base report Section 9). No change.

### P0-05 - CORS wildcards: PASS (the base report was the error, not this card)

All five cited services have a CORS wildcard, confirmed by direct line read.

```text
$ sed -n '75p' FederalHearings-ims-aks/.../config/SecurityConfig.java
        configuration.setAllowedOrigins(List.of("*"));
$ sed -n '45p' EmployerWebService-.../EmployerElasticResource.java
@CrossOrigin(origins = "*")
$ sed -n '39p' SearchDataWebService-.../HearingSearchResource.java
@CrossOrigin("*")
$ sed -n '56p' ECMService-.../ContentManagementResource.java
@CrossOrigin(origins = "*")
$ sed -n '31p' AzureAdService-.../AzureAdResource.java
@CrossOrigin("*")
```

The card is correct. The base report
(`ARC_Audit_Command_Findings_2026-06-10.md`, Section 6.3) listed only four
services because its single combined regex matched the annotation style
`@CrossOrigin` but missed the config style `setAllowedOrigins(List.of("*"))` in
FederalHearings. Correction belongs in the base report, not here: report two
patterns separately. Five services is right.

### P0-06 - Session timeouts: FIX (misses a 5-hour service)

The two cited timeouts are accurate, but a third 5-hour service is missing.

```text
$ grep -rn 'session-timeout' ImsNXG-master/.../web.xml FedSep-.../web.xml \
    RespondentPortal-ims-aks/WebContent/WEB-INF/web.xml
ImsNXG ...web.xml:91:          <session-timeout>300</session-timeout>   (5 hours, in card)
FedSep ...web.xml:99:          <session-timeout>180</session-timeout>   (3 hours, in card)
RespondentPortal ...web.xml:16: <session-timeout>300</session-timeout>  (5 hours, NOT in card)
```

RespondentPortal holds sessions for the same 5 hours as ImsNXG and is browser
facing. The card's "Why" even says "ImsNXG holds sessions for 5 hours" without
noting RespondentPortal does too. Fix: add RespondentPortal
`WebContent/WEB-INF/web.xml:16` to P0-06. (EEOCWebService at 5 minutes and
DocumentGeneratorAdapter at 3 minutes are fine and correctly excluded.)

### P0-11 - CSRF: FIX (wrong service, four missing)

The card lists IntakeCollectionsService plus "review EmailWebService,
FepaGateway, MessagingPoc, FederalHearings." FederalHearings does not disable
CSRF, and four services that do are absent.

```text
$ grep -rln --include='*.java' 'csrf.*disable\|csrf()\.disable' . | repo
ContentGeneratorWebService-ims-aks     <- missing from card
EmailWebService-ims-aks-test           (listed)
FepaGateway-ims-aks                    (listed)
IntakeCollectionsService-main          (listed, primary)
MessagingPoc-master                    (listed)
PrEPAWebService-ims-aks-test           <- missing from card
TemplateMangementWebService-ims-aks-test <- missing from card
UserManagementWebService-master        <- missing from card

$ grep -rn 'csrf' FederalHearings-ims-aks/src | grep -i disable
(no output - FederalHearings does not disable CSRF)
```

Fix: drop FederalHearings, add ContentGeneratorWebService, PrEPAWebService,
TemplateMangementWebService, and UserManagementWebService to the review list.
Each needs the browser-facing-vs-backend-only decision the card already
describes; the card's method is right, its list is wrong.

### P0-12 - Security headers: PASS

Zero CSP, HSTS, or X-Frame-Options references across the estate, matching the
card's "0 of 19" claim.

```text
$ grep -rn 'Content-Security-Policy\|X-Frame-Options\|Strict-Transport' . | wc -l
0
```

No change.

### P0-13 - PII logs: PASS

All three cited FederalHearings sites exist and log PII as described.

```text
DocumentUploadMessageProcessorService.java:226  log.info("... email :{} for {} ", userEmail, eeocCaseNumber)
HearingCaseService.java:399                     log.info("... agency contacts: {} ...", emailRecipients, ...)
EmailManagementService.java:255                 log.info("... emailRequestVO: {} ", ..., emailRequestVO.toString())
```

The card scopes itself to FederalHearings and says "then sweep others," which is
the right framing. The base report's 565 estate-wide candidates are the sweep
backlog; note in the card that the sweep is mandatory, not optional, given the
platform PII rule.

---

## Pass 4 - Coverage Gaps: Exploitable Today, Absent From Phase 0

Phase 0's stated bar is "either exploitable today or an active compliance
violation." By that bar these belong in Phase 0 and are currently deferred to
Phase 1 or 2, or not scheduled at all. Each is written as a proposed Phase 0
card in the v2 file.

### Gap 1 - XXE on the MD-715 upload (proposed P0-14)

Confirmed reachable in `ARC_Audit_Findings_Addendum_2026-06-10.md`: `POST
/uploadXml` feeds attacker XML into two unhardened parsers (JAXP `Validator`
and a JAXB `Unmarshaller`) with no `FEATURE_SECURE_PROCESSING` and no
`ACCESS_EXTERNAL_DTD` restriction. Impact is arbitrary file read and SSRF to the
AKS metadata endpoint. The runbook defers all XXE work to Phase 2 (months 4-9).

This is the sharpest contradiction in the plan: Phase 0 spends four weeks
rotating secrets out of source, while a reachable file-read primitive that can
exfiltrate those same secrets at parse time stays open until Phase 2. Rotating
the secrets does not close the read path. The XXE hardening is a small, bounded
change (set two parser features) and should run inside Phase 0.

### Gap 2 - Java deserialization, RCE surface (proposed P0-15)

13 `ObjectInputStream`/`readObject` sites and 14 XStream usages (base report
6.1). XStream in this estate is version 1.4.9, which the secondary scan flags
with 39 findings including known RCE gadget chains. Deserialization of untrusted
input is the classic Java remote-code-execution path. The runbook places this in
Phase 2. At minimum the reachable sites need triage in Phase 0, and the XStream
version bump is cheap.

### Gap 3 - Known-exploited dependency CVEs (proposed P0-15, same card)

Spring4Shell (CVE-2022-22965) in `spring-boot-starter-web 2.2.4.RELEASE` is a
weaponized, public-exploit RCE. The Apache Tika CVEs (CVE-2025-54988,
CVE-2025-66516) sit in the document parser that ingests uploads. The runbook
folds all dependency work into "Phase 1 - Dependency Modernization (months
2-6)." A known-exploited RCE should not wait two-to-six months behind a general
modernization effort. Emergency-patch the actively-exploited CVEs in Phase 0;
leave the bulk dependency uplift in Phase 1.

### Gap 4 - Unauthenticated dev controller (proposed P0-16)

`IntakeCollectionsService` ships a live `@RestController` at `/api/dev` with no
method-level or profile-level guard.

```text
$ grep -n 'PreAuthorize\|Secured\|RolesAllowed\|@Profile' \
    IntakeCollectionsService-main/.../controller/DevController.java
(no output)
```

Its endpoints include `POST /reset-to-element`, `POST /subroutines/{id}/start`,
and `POST /embedded-subprocesses/{id}/run` - process-control operations exposed
without an auth annotation or a non-prod profile gate. Either gate it behind a
dev profile or remove it from the deployable artifact. This is a Phase 0 item
because it is reachable now.

### Gap 5 - ADR_PORTAL Login.gov signing key (proposed P0-17)

Covered under P0-03 above: a committed Login.gov `private_key_jwt` signing key
and PEM material pasted into three provisioning docs, none of it in the current
P0-03 scope.

---

## What This Means for the Plan

Phase 0 is sound on the work it does cover: 9 of 13 cards pass clean, and the 4
that need fixes are corrections to counts and service lists, not wrong
diagnoses. The real finding is Pass 4. Phase 0 was built almost entirely around
secrets, CORS, CSRF, sessions, and headers, which are the configuration-hygiene
layer. It does not address the three reachable code-execution-adjacent classes
(XXE, deserialization, known-exploited CVEs) or the open dev controller, all of
which meet Phase 0's own "exploitable today" bar. The v2 Phase 0 adds four cards
(P0-14 through P0-17) and corrects four existing ones.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Four-pass Phase 0 verification; 4 card corrections, 5 coverage gaps |

Inputs: `ARC_Developer_Remediation_Runbook.md`,
`ARC_Audit_Command_Findings_2026-06-10.md`,
`ARC_Audit_Findings_Addendum_2026-06-10.md`.
Outputs: `ARC_Developer_Remediation_Runbook_v2_Phase0.md`,
`ARC_Secondary_Scan_Findings_2026-06-10.md`.
