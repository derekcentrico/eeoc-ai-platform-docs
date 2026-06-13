# ARC Developer Remediation Runbook - v2 Phase 2

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Phase 2 developer task cards: security architecture. Extends the v2 set and
replaces the Phase 2 outline in `ARC_Developer_Remediation_Runbook.md` when v2 is
assembled.

**Objective:** close the access-control, injection, and request-handling gaps
that Phase 0 only emergency-patched. Phase 0 stopped the bleeding on the
reachable items (one XXE path, the known-exploited CVEs, the worst CSRF and CORS
holes); Phase 2 makes the controls systemic across all 19 deployable services.

**Timeline:** months 4-9, overlapping the tail of Phase 1. The framework uplift
in Phase 1 (P1-08 jakarta migration) is a prerequisite for the current
Spring Security idioms used below.

> **Footnote on targets.** Counts in this document are from the verified base
> report and a Phase 2 recon on 2026-06-10. Re-run the greps before executing a
> card; the surface shifts as Phase 1 lands. Regeneration commands are in
> `ARC_Phase1to4_Runbook_Notes.md`.

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
grep -rnE --include='*.java' 'Runtime\.getRuntime\(\)\.exec|ProcessBuilder|getRealPath|new File\([^)]*request' . | grep -ivE '/test/|/tests/'   # exclude test sources, not the -ims-aks-test service repos; each remaining site reviewed and constrained
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
   sites) to P2-18, XXE to P2-03, path traversal and command injection to P2-16.
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

### P2-18 - Systemic PII-in-log redaction

| | |
|---|---|
| **Severity** | HIGH (platform no-PII-in-logs rule) |
| **Source** | base report 6.9; Findings Addendum; Phase 0 P0-13 |

**Why:** P0-13 masks the reachable FederalHearings email-in-log sites as an
emergency; the estate-wide cleanup was never carded. The triage in P2-17 confirms
roughly 113 sites that log an email value in cleartext, the real leak class from
base report 6.9 (the 565 count is mostly false positives on a `name` variable).
P2-12 narrows broad exceptions and removes `printStackTrace`, but its done-when
and verify cover only the exception path, so a PII-in-log site can survive both
P2-12 and P2-17. This card is the dedicated home that closes the class, the
estate-wide completion of the P0-13 emergency subset.

**Steps**
1. Add the platform PII-masking pattern (`_mask_pii()` or a SHA-256 + Key Vault
   salt hash) to every service that lacks one; the ARC Java services have none.
2. Route every log statement that references an identity field (email, SSN,
   phone, name) through the masking pattern; never log a raw email or other PII.
3. Remediate the triaged P2-17 sites and add a Semgrep/CI rule that fails the
   build on a new unmasked PII-in-log statement.

**Done when**
- [ ] A PII-masking utility exists in every service that logs identity fields.
- [ ] No log statement writes a raw email/SSN/phone/name; the P2-17 sites are
      masked.

**Verify**
```bash
grep -rnE --include='*.java' 'log\.(info|debug|warn|error)\([^)]*(email|ssn|phone)' . | grep -ivE '/test/|/tests/' | grep -iv mask   # trends to 0
```

---

## Phase 2 exit gate

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
- [ ] PII-masking utility present; no raw email/SSN/phone/name logged; the
      triaged PII-in-log sites are masked (P2-18).

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 2 task cards: authz, injection, validation, SSRF, rate limiting, headers |

Inputs: `ARC_Audit_Command_Findings_2026-06-10.md`,
`ARC_Audit_Findings_Addendum_2026-06-10.md`, Phase 2 recon.
Refresh: `ARC_Phase1to4_Runbook_Notes.md`.
