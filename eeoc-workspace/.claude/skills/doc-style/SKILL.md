---
name: doc-style
description: >
  Documentation style guide for the EEOC platform. Read before writing any
  document. All docs across all repos match the style established in
  eeoc-ofs-adr/docs/. Consistency is ATO evidence integrity.
---

# Documentation Style — EEOC Platform

All documents across all repos match the style in `eeoc-ofs-adr/docs/`.
Before writing any document, read the most relevant existing doc from that directory.

---

## Header (every document)

```markdown
# Document Title
**Author:** Derek Gordon

## EEOC [Application Name]

---
```

---

## Structure

- Numbered sections: `1.`, `1.1`, `1.2`, `2.` — never skip levels
- Attribute tables: `| **Bold Key** | Value |`
- Data tables: plain columns
- Code references: backtick inline paths with line numbers: `` `adr_functionapp/RelianceScorer/__init__.py:47` ``
- Mermaid diagrams: `flowchart TB` or `flowchart LR`
- ASCII art boxes: `┌─┐│└─┘` box-drawing characters (see `ADR_Architecture_Diagram.md`)

---

## Gap Table Convention

```markdown
| Gap ID | Description | Priority | Remediation Target |
|---|---|---|---|
| A-19 | Active gap description | High | Q3 2026 |
| A-18 | ~~Resolved gap description~~ | ~~High~~ | **Implemented 2026-03-31** — what was done and where |
```

---

## End of Every Compliance Document

```markdown
## N. Attestation

- [x] [statement]
- [x] [statement]

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | Month Year | Derek Gordon / OIT | Initial release |
```

---

## Reference Docs by Topic

| Writing about | Read first |
|---|---|
| Architecture, components | `eeoc-ofs-adr/docs/ADR_Architecture_Diagram.md` |
| API routes, integration | `eeoc-ofs-adr/docs/API_Architecture_and_Integration_Guide.md` |
| NIST controls, ATO evidence | `eeoc-ofs-adr/docs/NIST_800-53_Compliance_Implementation_Analysis.md` |
| AI governance, model cards | `eeoc-ofs-adr/docs/AI_Model_Governance_Card.md` |
| AI bias, fairness | `eeoc-ofs-adr/docs/AI_Bias_Fairness_and_Equitable_Treatment_Assessment.md` |
| Section 508, accessibility | `eeoc-ofs-adr/docs/Section_508_Accessibility_Conformance_Statement.md` |
| Data schema, tables | `eeoc-ofs-adr/docs/Data_Dictionary_and_Schema.md` |
| Configuration, env vars | `eeoc-ofs-adr/docs/Configuration_Management_Plan.md` |
| FedRAMP boundary | `eeoc-ofs-adr/docs/FedRAMP_Authorization_Boundary_Diagram.md` |
| Disaster recovery | `eeoc-ofs-adr/docs/Disaster_Recovery_Runbook.md` |
| ARC integration | `eeoc-ofs-adr/docs/ARC_Integration_Guide.md` |
| Azure provisioning | `eeoc-ofs-adr/docs/Azure_Portal_Provisioning_Guide.md` |
