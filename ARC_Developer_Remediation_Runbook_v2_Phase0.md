# ARC Developer Remediation Runbook - v2 Phase 0 Changes
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

This file holds the Phase 0 changes for runbook v2. It does not modify the
delivered `ARC_Developer_Remediation_Runbook.md`. When v2 of the full runbook is
assembled, the corrections and new cards here replace and extend the
corresponding v1 Phase 0 content.

Source of these changes: `ARC_Phase0_Verification_Audit_2026-06-10.md` (four-pass
verification) and `ARC_Audit_Findings_Addendum_2026-06-10.md` (confirmed XXE
path). Each change states what it supersedes.

Two parts:

- **Part A - Corrections** to existing cards P0-02, P0-03, P0-06, P0-11.
- **Part B - New emergency cards** P0-14 through P0-17, for exploitable-today
  classes that v1 Phase 0 omits.

Phases 1-4 v2 changes are tracked separately in
`ARC_Secondary_Scan_Findings_2026-06-10.md`.

---

## Part A - Corrections to Existing Cards

### P0-02 correction - FepaGateway password count

**Supersedes:** v1 P0-02, step 1, second bullet.

v1 says "FepaGateway - 9 OAuth passwords starting at line 62." Verified count is
**7** in the `app.oauth.*.password` family (lines 62, 64, 68, 76, 80, 86, 94)
plus **one** public-portal token password at line 179. Replace the bullet with:

> - `FepaGateway-ims-aks/src/main/resources/application.properties` - 7 OAuth
>   passwords (lines 62, 64, 68, 76, 80, 86, 94) and 1 public-portal token
>   password (line 179). Rotate all eight; do not skip line 179, it is a live
>   token credential.

The v1 verify grep already catches line 179 (`password\s*=\s*[A-Za-z0-9]`), so no
verify change is needed.

### P0-03 correction - private key count and scope

**Supersedes:** v1 P0-03 title, Why, and Repos.

v1 title "Rotate the 14 private keys in AuthorizationService" is wrong on both
count and scope. AuthorizationService holds **5 unique signing keys**, one per
environment, appearing as 10 PEM blocks only because of a nested duplicate
checkout. The "14" was the estate-wide gitleaks `private-key` count, which also
includes 6 PEM blocks in ADR_PORTAL that v1 P0-03 does not cover.

Replace the title and Why with:

> ### P0-03 - Rotate the 5 OAuth signing keys in AuthorizationService
>
> **Why:** 5 RSA private keys (one per environment: DEV, TEST, UAT, TRAIN, and
> the default in `application.yaml`) sign and validate every auth token in the
> system. One key forges tokens for any user, including admins. They are
> committed in:
> - `application-DEV.yaml:3`, `application-TEST.yaml:3`,
>   `application-UAT.yaml:3`, `application-TRAIN.yaml:3`, `application.yaml:92`

The steps (generate per-environment key pairs, store in Key Vault, distribute
public keys, shred locals) are unchanged. The committed Login.gov key and the
doc-embedded PEM material move to the new card P0-17.

### P0-06 correction - add RespondentPortal

**Supersedes:** v1 P0-06 Repos, Why, and Steps.

RespondentPortal holds sessions for 5 hours, same as ImsNXG, and is browser
facing. It is missing from v1 P0-06. Add to Repos `RespondentPortal`, change the
Why to "ImsNXG and RespondentPortal hold sessions for 5 hours, FedSep for 3,"
and add a third step:

> 3. `RespondentPortal-ims-aks/WebContent/WEB-INF/web.xml:16`:
>    ```xml
>    <!-- BEFORE: <session-timeout>300</session-timeout> -->
>    <session-timeout>30</session-timeout>
>    ```

Add the file to the verify grep.

### P0-11 correction - fix the CSRF service list

**Supersedes:** v1 P0-11 Repos and step 3.

FederalHearings does not disable CSRF and must be removed from the list. Four
services that do disable it are missing. The full set of services with
`csrf.disable()` is:

> IntakeCollectionsService (primary), EmailWebService, FepaGateway, MessagingPoc,
> ContentGeneratorWebService, PrEPAWebService, TemplateMangementWebService,
> UserManagementWebService.

Replace the Repos line and step 3 to review all seven non-primary services with
the existing browser-facing-vs-backend-only decision rule. The decision method
in v1 is correct; only the list changes.

---

## Part B - New Emergency Cards

These four cards are new in v2. Each meets the v1 Phase 0 bar ("exploitable today
or an active compliance violation") and so belongs in Phase 0, not the later
phases where v1 leaves the work.

### P0-14 - Harden XML parsers against XXE on the upload path

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `FedSep`, then sweep `EEOCWebService`, `IntakeCollectionsService`, `ImsNXG`, `ECMService` |
| **Depends on** | none |
| **Source** | Findings Addendum 2026-06-10, base report Section 6.2 |

**Why:** `FedSep` `POST /uploadXml` parses attacker-supplied XML through two
unhardened parsers, giving arbitrary file read (including the secrets Phase 0 is
rotating) and SSRF to the AKS metadata endpoint. 42 parser instantiations across
the estate have zero hardening calls. Rotating secrets does not close this; the
read path stays open until the parsers are fixed.

**Steps**

1. `AggregateDataValidator.java` - harden the JAXB unmarshal at line 2236. Build
   an XXE-safe `SAXSource` instead of unmarshalling the stream directly:
   ```java
   SAXParserFactory spf = SAXParserFactory.newInstance();
   spf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
   spf.setFeature("http://xml.org/sax/features/external-general-entities", false);
   spf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
   Source safe = new SAXSource(spf.newSAXParser().getXMLReader(),
       new InputSource(new ByteArrayInputStream(bytes)));
   MD715WORKFORCEFILE file = (MD715WORKFORCEFILE) um.unmarshal(safe);
   ```
2. Same file, harden the JAXP validation at line 211. On the `SchemaFactory` and
   the `Validator`:
   ```java
   sf.setProperty(XMLConstants.ACCESS_EXTERNAL_DTD, "");
   sf.setProperty(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
   validator.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
   validator.setProperty(XMLConstants.ACCESS_EXTERNAL_DTD, "");
   validator.setProperty(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
   ```
3. `EEOCWebService` `XMLValidator.java:46` - the same `disallow-doctype-decl`
   feature on the `SAXParserFactory` before `reader.parse(...)`.
4. Sweep the remaining parser sites (base report 6.2) and apply the matching
   guard per parser type.

**Done when**
- [ ] Every parser on a request-reachable path sets the secure-processing
      feature or `disallow-doctype-decl`.
- [ ] A DOCTYPE-bearing test payload to `/uploadXml` is rejected, not resolved.

**Verify**
```bash
grep -rn 'disallow-doctype-decl\|FEATURE_SECURE_PROCESSING\|ACCESS_EXTERNAL_DTD' \
  FedSep-ims-aks-test EEOCWebService-master   # present at each parser site
```

### P0-15 - Emergency-patch known-exploited RCE dependencies and triage deserialization

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1-2 |
| **Repos** | Spring4Shell-affected service(s); XStream users; Tika users |
| **Depends on** | none |
| **Source** | base report 4.1, 6.1; secondary scan |

**Why:** Three remote-code-execution exposures are reachable now and v1 defers
all three to Phase 1/2. Spring4Shell (CVE-2022-22965) in
`spring-boot-starter-web 2.2.4.RELEASE` has public exploit code. XStream 1.4.9
(39 secondary-scan findings) carries known deserialization gadget chains. The
Apache Tika CVEs (CVE-2025-54988, CVE-2025-66516) sit in the parser that ingests
uploaded documents.

**Steps**

1. Bump `spring-boot-starter-web` past the Spring4Shell fix line on the affected
   service and redeploy. This is a targeted patch, not the Phase 1 framework
   uplift.
2. Bump XStream off 1.4.9 to a current release, and where XStream reads
   untrusted input, apply its security framework (`XStream.setupDefaultSecurity`
   plus an explicit allowlist).
3. Bump Tika to a release past both CVEs on every service that parses uploads.
4. Triage the 13 `ObjectInputStream`/`readObject` sites (base report 6.1): for
   each, confirm whether the byte source is untrusted. Any that read request or
   upload data get fixed now; the rest are logged for Phase 2.

**Done when**
- [ ] Spring4Shell-affected service is on a patched Spring Boot line.
- [ ] XStream and Tika are off the vulnerable versions.
- [ ] Every untrusted-input deserialization site is fixed or confirmed
      unreachable, with the decision recorded.

**Verify**
```bash
trivy fs --severity CRITICAL --quiet . | grep -E 'CVE-2022-22965|CVE-2025-54988|CVE-2025-66516'
# expect: no output after patching
```

### P0-16 - Gate or remove the unauthenticated dev controller

| | |
|---|---|
| **Severity** | HIGH |
| **Week** | 1 |
| **Repos** | `IntakeCollectionsService` |
| **Depends on** | none |
| **Source** | Phase 0 Verification Audit, Gap 4 |

**Why:** `DevController` is a live `@RestController` at `/api/dev` with no
method-level or profile guard, exposing process-control endpoints
(`/reset-to-element`, `/subroutines/{id}/start`,
`/embedded-subprocesses/{id}/run`).

**Steps**

1. Preferred: exclude `DevController` from the deployable artifact entirely.
2. If it must ship, gate the whole class behind a non-production profile and
   require authentication:
   ```java
   @Profile("dev")
   @PreAuthorize("hasRole('PLATFORM_ADMIN')")
   @RestController
   @RequestMapping("/api/dev")
   public class DevController { ... }
   ```

**Done when**
- [ ] `/api/dev` is unreachable in production, or gated by profile and auth.

**Verify**
```bash
grep -n '@Profile\|@PreAuthorize' \
  IntakeCollectionsService-main/.../controller/DevController.java   # both present
```

### P0-17 - Rotate the ADR_PORTAL Login.gov key and scrub PEM from docs

| | |
|---|---|
| **Severity** | CRITICAL |
| **Week** | 1 |
| **Repos** | `ADR_PORTAL` |
| **Depends on** | none |
| **Source** | Phase 0 Verification Audit, P0-03 scope |

**Why:** A committed Login.gov `private_key_jwt` signing key in
`adr_webapp/auth/logingov_client.py`, plus PEM material pasted into three
provisioning docs and two test fixtures. The signing key authenticates this
agency to Login.gov; if real, it forges the agency's client identity.

**Steps**

1. Generate a new Login.gov client key pair, register the new public key with
   Login.gov, store the private key in Key Vault, and load it from there in
   `logingov_client.py`. Remove the literal.
2. Remove the PEM blocks from the three provisioning docs; replace with a
   pointer to the Key Vault secret name.
3. Replace the test-fixture keys with generated throwaway keys created at test
   time, never committed.
4. Include ADR_PORTAL in the P0-10 history scrub scope.

**Done when**
- [ ] New Login.gov key registered and loading from Key Vault.
- [ ] No PEM blocks remain in ADR_PORTAL source, docs, or tests.

**Verify**
```bash
grep -rn 'BEGIN RSA PRIVATE KEY\|BEGIN PRIVATE KEY' ADR_PORTAL-main/   # no output
```

---

## Updated Phase 0 Exit Gate Additions

Add to the v1 Section 3.4 checklist:

- [ ] XML parsers on request-reachable paths hardened against XXE (P0-14).
- [ ] Spring4Shell, Tika, and XStream patched; untrusted-input deserialization
      sites fixed or cleared (P0-15).
- [ ] `/api/dev` removed or profile-and-auth gated (P0-16).
- [ ] ADR_PORTAL Login.gov key rotated; no PEM in source/docs/tests (P0-17).

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 0 v2: 4 card corrections, 4 new emergency cards |

Supersedes Phase 0 content in `ARC_Developer_Remediation_Runbook.md` when v2 is
assembled. Basis: `ARC_Phase0_Verification_Audit_2026-06-10.md`.
