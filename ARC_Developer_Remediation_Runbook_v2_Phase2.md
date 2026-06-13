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
   semantics instead of stack traces (this also closes the `printStackTrace`
   leakage from base report 6.10 on the response path).
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
curl -s -o /dev/null -w '%{http_code}' https://<arc-service>/<endpoint>   # expect 401/403
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

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 2 task cards: authz, injection, validation, SSRF, rate limiting, headers |

Inputs: `ARC_Audit_Command_Findings_2026-06-10.md`,
`ARC_Audit_Findings_Addendum_2026-06-10.md`, Phase 2 recon.
Refresh: `ARC_Phase1to4_Runbook_Notes.md`.
