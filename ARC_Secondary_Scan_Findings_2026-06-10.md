# ARC Secondary Scan Findings - MEDIUM and LOW Severity
**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

The base report (`ARC_Audit_Command_Findings_2026-06-10.md`) ran the dependency
scanners filtered to CRITICAL and HIGH only. Everything below HIGH was excluded
and therefore never reached the audit or the runbook. This document captures the
MEDIUM and LOW tier and maps it into the existing Phase 1-4 outline so nothing in
that band is lost.

These are not emergency findings. The point of the secondary tier is that it
shapes the volume and sequencing of Phases 1-4: it is where the real size of the
dependency, frontend, and legacy-framework debt shows up. A few MEDIUM entries
also reinforce Phase 0 emergency cards (XStream, Tika) and are cross-referenced.

Scope note: counts are scanner output. MEDIUM dependency CVEs include
unreachable and dev-only paths; this tier is a backlog to schedule, not a
break-glass list.

---

## 1. Trivy - Full Severity Breakdown

```text
$ trivy fs --severity CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN --format json -o /tmp/trivy-all.json .
  CRITICAL: 17
  HIGH:     181
  MEDIUM:   179      <- new in this report
  LOW:       21      <- new in this report
  unique MEDIUM CVE+package combinations: 109
```

**What it shows:** filtering to CRITICAL/HIGH dropped 200 findings (179 MEDIUM +
21 LOW). That roughly doubles the dependency-CVE backlog the base report
implied. Phase 1 sizing should use ~398 dependency findings, not the ~198 the
base report shows.

Representative MEDIUM CVEs:

```text
CVE-2020-10544 | org.primefaces:primefaces 7.0            (JSF UI tier)
CVE-2023-2976  | com.google.guava:guava 31.0.1-jre
CVE-2023-33201 | org.bouncycastle:bcprov-jdk15on 1.68     (crypto provider)
CVE-2023-0482  | org.jboss.resteasy:resteasy-multipart-provider 3.14.0.Final
CVE-2022-36033 | org.jsoup:jsoup 1.14.3                   (HTML sanitizer)
CVE-2023-45803 | urllib3 1.25.9 / 1.26.3
CVE-2022-23491 | certifi 2020.12.5
CVE-2023-5115  | ansible 5.5.0                            (infra tooling)
```

---

## 2. Grype - MEDIUM and LOW Package Concentration

```text
$ grype dir:. --output json   (Medium/Low slice)
distinct Medium/Low package versions: 73
  xstream 1.4.9:       39 findings    <- see Phase 0 P0-15
  axios 1.13.5:        24 findings
  guava 22.0:          18 findings
  logback-core 1.0.7:  15 findings
  logback-core 1.1.8:  15 findings
  tika-core 1.5:       15 findings    <- see Phase 0 P0-14/P0-15
  httpclient 4.3.3:    15 findings
  snakeyaml 1.18:      15 findings
  jinja2 2.11.2:       10 findings
  axios 1.15.0:        10 findings
  wss4j 1.5.4:          9 findings    (SOAP security)
  axis 1.4:             9 findings    (legacy SOAP stack)
  poi 3.10.1:           9 findings    <- old Office parser
  dompurify 3.2.5:      9 findings    (frontend XSS sanitizer)
  requests 2.25.1:      8 findings
```

**What it shows:** the MEDIUM/LOW tier is concentrated in a small set of old
libraries, which is good news for remediation because a few version bumps clear
many findings at once. Two entries change the Phase 0 picture:

- **xstream 1.4.9** is the deserialization library from base report 6.1. Its 39
  findings confirm the version is old enough to carry gadget-chain CVEs.
  Reinforces Phase 0 P0-15.
- **tika-core 1.5 and poi 3.10.1** are far older than the Tika and POI 5.3.0 seen
  in FedSep. Some module pins Office parsers from the early 2010s, which process
  external entities by default and predate years of XXE fixes. Reinforces Phase 0
  P0-14 (XXE) and P0-15 (Tika patch). The document-parser risk is worse than the
  CRITICAL/HIGH scan alone suggested.

---

## 3. Proposed Revisions to Phases 1-4

The runbook leaves Phases 1-4 as an outline with cards "written at the start of
each phase." These are the inputs that should shape those cards.

### Phase 1 - Dependency Modernization (months 2-6)

- Plan against ~398 total dependency findings (CRITICAL through LOW), not ~198.
  The MEDIUM tier roughly doubles the backlog.
- Prioritize the high-fan-out bumps that clear many findings each: xstream,
  logback-core, tika-core, poi, httpclient, snakeyaml, guava, bouncycastle.
- snakeyaml 1.18 and xstream 1.4.9 are both unsafe-deserialization libraries;
  bump them together with the Phase 0 P0-15 triage so the emergency patch and
  the bulk uplift do not diverge.
- bcprov-jdk15on 1.68 (CVE-2023-33201/33202) ties into the crypto modernization
  already in the plan; fold it into that workstream.

### Phase 2 - Security Architecture (months 4-9)

- resteasy-multipart-provider 3.14.0 (CVE-2023-0482) and wss4j 1.5.4 sit on the
  SOAP and multipart request paths; review them alongside the input-validation
  and XXE-hardening work that Phase 2 already owns for the non-emergency parser
  sites P0-14 does not reach.
- jsoup 1.14.3 (CVE-2022-36033) is server-side HTML handling; pair with the XSS
  and output-encoding workstream.

### Phase 3 - Frontend Modernization and 508 (months 6-12)

- axios (1.13.5 and 1.15.0, 34 findings combined) and dompurify 3.2.5 are
  frontend dependencies; bundle into the Angular uplift. dompurify in particular
  is the XSS sanitizer, so keeping it current is a security item, not just
  hygiene.
- primefaces 7.0 (CVE-2020-10544) and axis 1.4 belong to the legacy JSF/SOAP
  tier that Phase 3 retires; track them as retire-not-patch.

### Phase 4 - Consolidation and Continuous Security (months 10-18)

- Set the continuous-monitoring gate to fail on CRITICAL/HIGH and to report
  MEDIUM/LOW as a tracked, burning-down backlog. The lesson from this report is
  that a CRITICAL/HIGH-only filter hid 200 findings; the standing gate should
  surface the full tier even if it only blocks on the top two.
- Python tooling CVEs (urllib3, certifi, requests, jinja2, ansible) are mostly in
  build and ops tooling rather than shipped services; clear them in the pipeline
  image refresh rather than per-service.

---

## 4. One-Line Takeaway for the Plan

CRITICAL/HIGH set the Phase 0 and Phase 1 emergencies. The MEDIUM/LOW tier does
not change those emergencies, but it doubles the Phase 1 dependency backlog and
proves the document-parser exposure (old Tika and POI) is deeper than the top-tier
scan showed. Phases 1-4 cards should be written against the full-severity numbers
here, and the continuous-monitoring gate in Phase 4 should never run
CRITICAL/HIGH-only again.

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | MEDIUM/LOW dependency scan; Phase 1-4 revision inputs |

Inputs: full-severity Trivy and Grype scans of `eeoc-arc-payloads/`.
Related: `ARC_Audit_Command_Findings_2026-06-10.md`,
`ARC_Developer_Remediation_Runbook_v2_Phase0.md`.
