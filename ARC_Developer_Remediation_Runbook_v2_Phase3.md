# ARC Developer Remediation Runbook - v2 Phase 3

**Author:** Derek Gordon

## EEOC Office of the Chief Information Officer

---

Phase 3 developer task cards: frontend modernization and Section 508 / WCAG 2.1
AA compliance. Extends the v2 set and replaces the Phase 3 outline in
`ARC_Developer_Remediation_Runbook.md` when v2 is assembled.

**Objective:** retire the legacy server-rendered frontend tier, bring the Angular
applications onto one current version, and make the remediable frontends meet
508. Section 508 is federal law; the legacy JSP/XHTML tier cannot reach AA in
place, so this phase retires it rather than patching it.

**Timeline:** months 6-12, overlapping Phase 1's JBoss retirement (P1-09) and
Phase 2's header rollout (P2-08). The JBoss base-image services and the JSP tier
are the same services; retire them together.

> **Footnote on targets.** Counts and versions are from the verified base report
> and a Phase 3 recon on 2026-06-10. Frontend framework releases move fast;
> re-check Angular and the npm targets against upstream before executing.
> Regeneration commands are in `ARC_Phase1to4_Runbook_Notes.md`.

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

## Phase 3 exit gate

- [ ] No deployable service serves JSP/XHTML; JBoss image removed (P3-01).
- [ ] All three Angular apps on one current version; npm audit clean (P3-02).
- [ ] Images, language, and keyboard access remediated in retained UIs (P3-03).
- [ ] Forms, tables, charts, and ARIA meet 508 (P3-04).
- [ ] axe-core 508 gate in CI for every frontend (P3-05).

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-06-10 | Derek Gordon / OCIO | Phase 3 task cards: JSP retirement, Angular alignment, 508 remediation and gate |

Inputs: `ARC_Audit_Command_Findings_2026-06-10.md`, Phase 3 recon.
Note: corrects the Angular app count from two to three.
Refresh: `ARC_Phase1to4_Runbook_Notes.md`.
