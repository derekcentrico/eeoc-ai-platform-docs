# EEOC AI Platform Documentation

**Author:** Derek Gordon

Consolidated platform documentation for the EEOC AI Platform.
Per-application docs remain in each repo's `docs/` directory; this repo
holds platform-wide architecture, deployment, compliance, and governance
documents that span multiple applications.

---

## Repository Structure

```
eeoc-ai-platform-docs/
├── README.md                          # This file
├── platform-docs/                     # Cross-cutting architecture and auth
│   ├── Leadership_AI_Assistant_Architecture.md
│   ├── UDIP_Authentication_and_Authorization.md
│   └── ARC_Gap_Analysis.md
├── eeoc-workspace/                    # Workspace config (CLAUDE.md, skills, agents)
│   ├── CLAUDE.md
│   └── .claude/
│       ├── agents/
│       └── skills/
├── archive/                           # Superseded docs (kept for reference)
│   ├── ARC_API_and_MCP_Architecture_Plan.md
│   ├── Architecture_Gap_Analysis.md
│   └── ...
├── EEOC_AI_Platform_Azure_Overview.md
├── EEOC_AI_Platform_Complete_Deployment_Guide.md
├── Azure_M2131_EL3_Infrastructure_Guide.md
├── OCIO_Leadership_Briefing.md
├── OCHCO_Benefits_Validation_Integration_Plan.md
├── Implementation_Prompts.md
├── CHANGES.md
├── SESSION_HANDOFF.md
└── email_*.md                         # Architecture decision emails
```

---

## Platform Applications

| Application | Repo | Status | Docs Location |
|---|---|---|---|
| UDIP (Analytics + AI Assistant) | `eeoc-data-analytics-and-dashboard` | Production | `docs/` (55 files) |
| ADR Portal (Mediation) | `eeoc-ofs-adr` | Production | `docs/` (37 files) |
| Triage (Charge Intake) | `eeoc-ofs-triage` | Development | `docs/` (30 files) |
| Trial Tool (OGC) | `eeoc-ogc-trialtool` | Development | `docs/` (13 files) |
| Benefits Validation (OCHCO) | `eeoc-ochco-benefits-validation` | Development | `docs/` (4 files) |
| ARC Integration API | `eeoc-arc-integration-api` | Production | `docs/` (4 files) |
| MCP Hub Functions | `eeoc-mcp-hub-functions` | Production | `docs/` (3 files) |

---

## Key Platform-Wide Documents

### Architecture
- [Leadership AI Assistant Architecture](platform-docs/Leadership_AI_Assistant_Architecture.md) — Multi-domain query engine, RBAC, dashboard system, data onboarding pipeline
- [EEOC AI Platform Azure Overview](EEOC_AI_Platform_Azure_Overview.md) — Infrastructure topology and service map
- [ARC Gap Analysis](platform-docs/ARC_Gap_Analysis.md) — Integration gaps with legacy ARC systems

### Authentication and Access Control
- [UDIP Authentication and Authorization](platform-docs/UDIP_Authentication_and_Authorization.md) — Gateway auth, RBAC, RLS, unified access control
- Unified access control is integrated across all user-facing apps (ADR, Triage, Trial Tool, Benefits) via feature flag `UNIFIED_ACCESS_ENABLED`

### Deployment and Infrastructure
- [Complete Deployment Guide](EEOC_AI_Platform_Complete_Deployment_Guide.md) — Full provisioning and deployment sequence
- [Azure M-21-31 EL3 Infrastructure Guide](Azure_M2131_EL3_Infrastructure_Guide.md) — FedRAMP High logging and compliance

### Governance
- [OCIO Leadership Briefing](OCIO_Leadership_Briefing.md) — Executive summary for leadership
- [OCHCO Benefits Validation Integration Plan](OCHCO_Benefits_Validation_Integration_Plan.md) — Benefits coding validation design

### Architecture Decisions (Email Format)
- [ADR Demo Walkthrough](email_adr_demo_walkthrough.md)
- [AI Search Architecture Decision](email_ai_search_architecture_decision.md)
- [OCHCO Benefits Overpayment Tool](email_ochco_benefits_overpayment_tool.md)
- [OFP Investigative Toolkit Comparison](email_ofp_investigative_toolkit_comparison.md)

---

## Workspace Configuration

The `eeoc-workspace/` directory contains the Claude Code workspace configuration
that governs all development across the platform:

- `CLAUDE.md` — Platform rules, commands, skills table, hard limits
- `.claude/agents/` — Specialized agent definitions (post-impl-verifier, architect, security-reviewer, etc.)
- `.claude/skills/` — Domain skills (508 accessibility, AI audit, FedRAMP, ARC, doc-style, pre-pentest, human-tone)

---

## Sync Policy

This repo is synced from the workspace root and individual repos. Platform-wide
docs that span multiple applications live here. Per-application docs stay in
each repo's `docs/` directory.

Last full sync: 2026-05-01
