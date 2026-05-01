---
name: 508
description: >
  Section 508 / WCAG 2.1 AA accessibility requirements for EEOC applications.
  Bootstrap 5.3.3 dangerous-defaults table with exact hex overrides and measured
  contrast ratios. Chart, form, table, modal, icon, live region, and email
  patterns. Audit grep commands for template review. Read before writing any
  template, HTML, CSS, chart, form, icon, modal, badge, or email template.
---

# Section 508 / WCAG 2.1 AA — EEOC Platform

All EEOC applications are federal software under Section 508. WCAG 2.1 AA
conformance is not optional — it is law. Every template change must pass
these requirements before merge.

---

## Bootstrap 5.3.3 Dangerous Defaults

Bootstrap ships color utilities that fail WCAG 1.4.3 (4.5:1 text) and
1.4.11 (3:1 non-text). The overrides below are applied globally in `app.css`.
**Never use the Bootstrap default values — always use the EEOC overrides.**

### Text Utilities (4.5:1 minimum on white `#fff` / body `#f8f9fa`)

Ratios below use the WCAG 2.x piecewise sRGB-to-linear formula
(IEC 61966-2-1), verified 2026-04-15. Earlier revisions of this table used
a gamma-2.2 approximation that inflated values; do not revert to those.

| Utility | Bootstrap Default | Ratio | EEOC Override | Ratio (white / #f8f9fa) | CSS Rule |
|---|---|---|---|---|---|
| `.text-primary` | `#0d6efd` | ~4.5:1 | `#0a58ca` | 6.44:1 / 6.11:1 | `.text-primary { color: #0a58ca !important; }` |
| `.text-info` | `#0dcaf0` | ~1.9:1 | `#087990` | 5.06:1 / 4.80:1 | `.text-info { color: #087990 !important; }` |
| `.text-warning` | `#ffc107` | ~1.6:1 | `#7f6500` | 5.58:1 / 5.29:1 | `.text-warning { color: #7f6500 !important; }` |
| `.text-danger` | `#dc3545` | ~4.0:1 | `#b02a37` | 6.50:1 / 6.16:1 | `.text-danger { color: #b02a37 !important; }` |
| `.text-success` | `#198754` | ~4.0:1 | `#146c43` | 6.45:1 / 6.12:1 | `.text-success { color: #146c43 !important; }` |
| `.text-muted` | `#6c757d` | ~4.45:1 | `#5a6472` | 6.00:1 / 5.69:1 | `.text-muted { color: #5a6472 !important; }` |

**History:** The previous `.text-warning` override `#997404` was published in
this table as "~5.7:1 / ~5.4:1". Correct WCAG 2.x math gives 4.33:1 / 4.10:1 —
fails AA. All EEOC repos using `#997404` for `.text-warning` are being
corrected to `#7f6500`. When reading past POA&M entries that cite `#997404`
with a passing ratio, treat the ratio as the error — the color itself fails.

### Button Variants — CSS Custom Property Overrides Required

**Critical:** Bootstrap 5.3 resolves hover/active colors from CSS custom
properties (`--bs-btn-hover-color`, `--bs-btn-hover-bg`) via the generic
`.btn:hover` rule. Direct `!important` overrides on `:hover` selectors alone
do NOT reliably prevent Bootstrap's `var()` from resolving its defaults
during state transitions. This causes buttons to briefly show wrong text
colors on hover (e.g., dark text on colored backgrounds instead of white).

**Every btn-outline-\* override must set BOTH CSS custom properties AND
direct property overrides.** Template for each variant:

```css
.btn-outline-VARIANT {
    --bs-btn-color: OVERRIDE;
    --bs-btn-border-color: OVERRIDE;
    --bs-btn-hover-color: #fff;          /* #000 for light-bg variants */
    --bs-btn-hover-bg: OVERRIDE;
    --bs-btn-hover-border-color: OVERRIDE;
    --bs-btn-active-color: #fff;
    --bs-btn-active-bg: OVERRIDE;
    --bs-btn-active-border-color: OVERRIDE;
    --bs-btn-disabled-color: OVERRIDE;
    --bs-btn-disabled-border-color: OVERRIDE;
    color: OVERRIDE !important;
    border-color: OVERRIDE !important;
}
.btn-outline-VARIANT:hover,
.btn-outline-VARIANT:active,
.btn-outline-VARIANT.active {
    background-color: OVERRIDE !important;
    border-color: OVERRIDE !important;
    color: #fff !important;
}
```

| Variant | OVERRIDE color | Hover text |
|---|---|---|
| `.btn-outline-primary` | `#0a58ca` (6.44:1) | `#fff` |
| `.btn-outline-info` | `#087990` (5.06:1) | `#fff` |
| `.btn-outline-warning` | `#7f6500` (5.58:1) | `#fff` |
| `.btn-outline-danger` | `#b02a37` (6.50:1) | `#fff` |
| `.btn-outline-success` | `#146c43` (6.45:1) | `#fff` |
| `.btn-outline-secondary` | `#5a6472` (6.00:1) | `#fff` |
| `.btn-info` | N/A (light bg) | `#000` |
| `.btn-warning` | N/A (light bg) | `#000` |
| `.btn-danger` | bg `#b02a37` | `#fff` |
| `.btn-success` | bg `#146c43` | `#fff` |
| `.btn-primary` | bg `#0a58ca` | `#fff` |

### Navbar Text Contrast

Bootstrap `.navbar-dark .navbar-text` uses `rgba(255,255,255,0.55)` which
achieves only ~3.2:1 on the `#212529` dark navbar — fails 4.5:1 AA.

```css
.navbar-dark .navbar-text,
.navbar-dark .navbar-text a {
    color: #fff !important;
}
```

### Background Utilities

| Utility | Fix |
|---|---|
| `.bg-danger` | Darkened via `--bs-danger-rgb: 176, 42, 55` |
| `.bg-success` | Darkened via `--bs-success-rgb: 20, 108, 67` |
| `.bg-secondary` | Darkened via `--bs-secondary-rgb: 90, 100, 114` |

### Badges and Reduced-Opacity

| Pattern | Issue | Fix |
|---|---|---|
| `.badge.bg-info`, `.badge.bg-warning` | White text on light bg | `color: #000 !important` |
| `.badge.bg-primary.bg-opacity-75/50/25` | White on diluted blue | `color: #000 !important` |
| `.badge.bg-dark.bg-opacity-50/25` | White on diluted dark | `color: #000 !important` |

### CSS Custom Properties (`:root` overrides)

```css
:root {
    --bs-border-color: #737373;        /* ~4.7:1 on white (was #dee2e6) */
    --bs-danger-rgb: 176, 42, 55;
    --bs-danger: #b02a37;
    --bs-success-rgb: 20, 108, 67;
    --bs-success: #146c43;
    --bs-secondary-rgb: 90, 100, 114;
    --bs-secondary: #5a6472;
}
```

### Focus Indicators (WCAG 2.4.7 + 1.4.11)

All interactive elements use `:focus-visible` (not `:focus`) with a solid
`2px solid #0a58ca` outline + `2px` offset. No box-shadow focus rings —
Bootstrap's default 50% opacity ring fails 3:1.

### Chart Colors (WCAG 1.4.11 — 3:1 non-text minimum)

Danger-red in Chart.js: use `rgb(176, 42, 55)` — not `rgb(220, 53, 69)`.
The `getStatusColor()` function must return the darkened value for "Error".
All chart segment colors must exceed 3:1 against white canvas background.

---

## Chart Accessibility Pattern — Non-Negotiable

Every `<canvas>` chart requires all three:

```html
<!-- 1. ARIA on the canvas -->
<canvas id="myChart" role="img" aria-label="[Descriptive label of chart content]"></canvas>

<!-- 2. Accessible data table immediately after -->
<details class="mt-2">
  <summary>Chart data is available in the table below.</summary>
  <table class="table table-sm">
    <caption class="visually-hidden">[Same description as aria-label]</caption>
    <thead>
      <tr>
        <th scope="col">Label</th>
        <th scope="col">Value</th>
      </tr>
    </thead>
    <tbody>
      <tr><th scope="row">Category A</th><td>42</td></tr>
      <!-- ... -->
    </tbody>
  </table>
</details>
```

The fallback text "Chart data is not available in text form" is **wrong** and was
replaced in POA&M A-18. Use "Chart data is available in the table below."

---

## Form Patterns

```html
<!-- Explicit label association -->
<label for="case-number" class="form-label">Case Number</label>
<input type="text" id="case-number" class="form-control"
       aria-required="true" required>

<!-- Required fields -->
<input aria-required="true" required>

<!-- Error regions -->
<div role="alert" aria-live="assertive">
  <!-- Error messages injected here -->
</div>

<!-- Toggle switches -->
<div class="form-check form-switch">
  <input class="form-check-input" type="checkbox" role="switch"
         id="autoFinalize" aria-describedby="autoFinalizeHelp">
  <label class="form-check-label" for="autoFinalize">Auto-Finalize</label>
  <div id="autoFinalizeHelp" class="form-text">Helper text here.</div>
</div>
```

---

## Table Patterns

```html
<table class="table">
  <caption class="visually-hidden">Description of table content</caption>
  <thead>
    <tr>
      <th scope="col">Column 1</th>
      <th scope="col">Column 2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">Row label</th>
      <td>Value</td>
    </tr>
  </tbody>
</table>

<!-- Empty state: colspan must match actual column count -->
<tr><td colspan="5" class="text-center">No records found.</td></tr>
```

---

## Modal Pattern

```html
<div class="modal" tabindex="-1" role="dialog" aria-labelledby="modalTitle" aria-modal="true">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h2 class="modal-title" id="modalTitle">Title</h2>
        <button type="button" class="btn-close" data-bs-dismiss="modal"
                aria-label="Close"></button>
      </div>
      <div class="modal-body">...</div>
    </div>
  </div>
</div>
```

Focus traps: Tab/Shift-Tab must wrap within the modal per ARIA APG.

---

## Icon Pattern

```html
<!-- Decorative icons — hidden from AT -->
<i class="fa-solid fa-check" aria-hidden="true"></i>

<!-- Meaningful icons — provide label -->
<i class="fa-solid fa-warning" aria-hidden="true"></i>
<span class="visually-hidden">Warning</span>

<!-- Note: use fa-solid, not the legacy fas prefix (Font Awesome 6) -->
```

---

## Live Regions

```html
<!-- Flash messages / alerts -->
<div role="alert" aria-live="assertive">...</div>

<!-- Chat / log regions -->
<div role="log" aria-live="polite" aria-atomic="false">...</div>

<!-- Notification badges -->
<span class="badge" aria-live="polite" aria-atomic="true">3</span>
```

---

## Links Opening in New Tab

```html
<a href="..." target="_blank" rel="noopener">
  Link Text <span class="visually-hidden">(opens in new tab)</span>
</a>
```

---

## Page Template Requirements

- `<html lang="en">` on every page and email template
- `{% block title %}Page Title{% endblock %}` — every page needs a `<title>`
- Skip link: `<a href="#main-content" class="skip-link">Skip to main content</a>`
- Heading hierarchy: h1 → h2 → h3, never skip levels
- All displayed strings wrapped in Flask-Babel `_()`
- Color is never the sole means of conveying information — badges use color + text

---

## HTML Email Template Requirements

- `<html lang="en">`
- Data tables use `<th scope="row">` for label cells
- No images in email bodies
- No auto-playing media
- Plain-text fallback for ICS calendar invite emails

---

## Sortable Table Columns (WCAG 4.1.2 + 1.3.1)

When `<th>` elements act as sort controls, they must communicate the current
sort direction to screen readers. Visual arrows alone (`▲`/`▼`) are not
accessible.

```html
<!-- th for a currently-sorted column -->
<th scope="col" aria-sort="ascending">
  <a href="?sort_by=age&amp;sort_order=desc"
     aria-label="Staff Age, sorted ascending">
    Staff Age ▲
  </a>
</th>

<!-- th for a sortable but not currently-sorted column -->
<th scope="col">
  <a href="?sort_by=name&amp;sort_order=asc"
     aria-label="Case Name">
    Case Name
  </a>
</th>
```

Rules:
- `aria-sort` on `<th>`: `"ascending"`, `"descending"`, or omit when unsorted
- `aria-label` on the `<a>`: include current sort state so SR users hear
  "Staff Age, sorted ascending" rather than just "Staff Age"
- Visual arrows (`▲`/`▼`) remain for sighted users

---

## Chat / Real-Time Message Regions (WCAG 4.1.3)

Chat windows that poll for new messages and re-render the full list via
`innerHTML = ''` defeat `aria-live` — screen readers either re-read everything
or miss the update. Use a separate SR-only announcer for new messages.

```html
<!-- Announcer region — outside the chat window -->
<div id="chat-sr-announcer" class="visually-hidden"
     role="status" aria-live="polite" aria-atomic="true"></div>

<!-- Chat window still uses role="log" for structural semantics -->
<div class="chat-window" id="chat-window-main"
     role="log" aria-live="polite" aria-atomic="false"
     aria-label="All participants chat messages">
  <!-- messages rendered here -->
</div>
```

In the render function, track message counts per container and push only new
messages into the announcer:

```javascript
const _prevMsgCounts = {};
const _chatAnnouncer = document.getElementById('chat-sr-announcer');

function renderMessages(container, messages, emptyMessage) {
    const cid = container.id;
    const prevCount = _prevMsgCounts[cid] || 0;
    // ... rebuild container.innerHTML as before ...

    // Announce only genuinely new messages
    if (!isInitialLoad && messages.length > prevCount && _chatAnnouncer) {
        const newMsgs = messages.slice(prevCount);
        const text = newMsgs.map(m => m.Author + ': ' + m.Text).join('. ');
        _chatAnnouncer.textContent = '';
        setTimeout(() => { _chatAnnouncer.textContent = text; }, 100);
    }
    _prevMsgCounts[cid] = messages.length;
}
```

---

## Focus Indicator Coverage (WCAG 2.4.7 + 1.4.11)

The `:focus-visible` overrides in `app.css` must cover **all** interactive
element types. Bootstrap's `:focus` box-shadow (50% opacity) must also be
suppressed globally to prevent a low-contrast double indicator.

Minimum `:focus-visible` selector list (solid `2px solid #0a58ca`):
- `.btn`, `a`, `.form-control`, `.form-select`, `.form-check-input`
- `.nav-link`, `.btn-close`, `.dropdown-item`, `.page-link`, `.accordion-button`

Global `:focus` box-shadow suppression:
```css
.btn:focus, .nav-link:focus, .btn-close:focus, .dropdown-item:focus,
.page-link:focus, .accordion-button:focus, .form-control:focus,
.form-select:focus, .form-check-input:focus {
    box-shadow: none !important;
}
```

---

## Chart Color Contrast (WCAG 1.4.11)

Chart.js segment and bar colors must use solid `rgb()` values — never `rgba()`
with reduced opacity. The canvas background is white; opacity-blended colors
can drop below the 3:1 non-text minimum.

```javascript
// WRONG — rgba dilutes contrast against white canvas
return 'rgba(13, 110, 253, 0.7)';

// RIGHT — solid color, verified >= 3:1 on white
return 'rgb(10, 88, 202)';
```

Status color mapping (matches CSS overrides):
| Status    | Color              | Hex      |
|-----------|--------------------|----------|
| Active    | `rgb(10, 88, 202)` | `#0a58ca` |
| Closed    | `rgb(90, 100, 114)`| `#5a6472` |
| Error     | `rgb(176, 42, 55)` | `#b02a37` |
| Default   | `rgb(108, 117, 125)` | `#6c757d` |

---

## Audit Grep Commands — Run Before Every Template PR

```bash
# Missing alt text on images
grep -rin '<img ' templates/ | grep -vi 'alt='

# Missing form labels
grep -rinE '<input|<select|<textarea' templates/ | grep -viE 'aria-label|<label|aria-labelledby'

# Unsafe use of | safe filter on potentially user-controlled data
# Pattern matches both "| safe" and "|safe" (Jinja2 filter, optional whitespace)
grep -rnE '\|\s*safe\b' templates/

# Missing lang attribute
grep -rn '<html' templates/ | grep -v 'lang='

# Missing scope on table headers
grep -rn '<th' templates/ | grep -v 'scope='

# Icons missing aria-hidden
grep -rn '<i class="fa' templates/ | grep -v 'aria-hidden'

# Links with target="_blank" missing screen reader indicator
grep -rn 'target="_blank"' templates/ | grep -v 'visually-hidden'

# Canvas elements missing role="img"
grep -rn '<canvas' templates/ | grep -v 'role="img"'

# Auto-submit on change (WCAG 3.2.2 violation)
grep -rn '\.on.*change.*submit\|addEventListener.*change.*submit' templates/ static/

# Missing aria-required on required fields
grep -rn 'required' templates/ | grep -v 'aria-required'

# Sortable column headers missing aria-sort
grep -rinE 'sort_by|sort_order' templates/ | grep -i '<th' | grep -vi 'aria-sort'

# Chat windows using innerHTML clear without SR announcer
grep -rn 'innerHTML.*=' templates/ static/ | grep -i 'chat\|message'

# Chart colors using rgba (should be solid rgb for contrast)
grep -rn "rgba(" templates/ static/ | grep -i 'chart\|color\|status'

# Bootstrap default #0d6efd used instead of EEOC override #0a58ca
grep -rn '0d6efd' templates/ static/css/
```

Fix all findings before opening the PR.

---

## ADR POA&M Reference

Resolved gaps are documented in `docs/Section_508_Accessibility_Conformance_Statement.md`
Section 4. The gap table format uses strikethrough for resolved items:

```markdown
| A-18 | ~~Description~~ | ~~High~~ | **Implemented 2026-03-31** — what changed |
```

New findings follow the same format with the next sequential gap ID.
