# EEOC AI Platform
**Author:** Derek Gordon

Python 3.11 · Flask · Azure Functions · Azure Table Storage · Azure Blob · Redis · Azure OpenAI  
FedRAMP High · Azure Commercial · NIST 800-53 Rev5 · WCAG 2.1 AA · NARA 7-year AI retention

---

## Repositories

| Repo | Role | Editable |
|---|---|---|
| `eeoc-arc-payloads` | ARC system payload schemas and contracts | **READ-ONLY — never modify** |
| `eeoc-arc-integration-api` | The only service that calls ARC APIs directly | Yes |
| `eeoc-mcp-hub-functions` | Azure API Management + Functions MCP aggregator | Yes |
| `eeoc-ofs-adr` | ADR Portal — AI-enabled mediation case management | Yes |
| `eeoc-ofs-triage` | Triage — charge intake and program routing | Yes |
| `eeoc-ogc-trialtool` | OGC Trial Tool — attorney trial preparation | Yes |
| `eeoc-data-analytics-and-dashboard` | Cross-platform leadership analytics | Yes |

When a new repo is added: create its `.claude/CLAUDE.md` (~30 lines: purpose, test commands, gotchas), add one row to this table, done.

---

## Workspace Layout

All repos are cloned as siblings under this directory. The `eeoc-arc-payloads/` directory contains
ARC system repositories (Java services, Terraform, Ansible, Helm charts) — all read-only references.

```
eeoc-workspace/
├── .claude/                              # Workspace-level config, agents, skills, hooks
├── CLAUDE.md                             # This file — platform-wide instructions
├── eeoc-arc-payloads/                    # READ-ONLY — ARC contracts and source repos
│   ├── FepaGateway-ims-aks/
│   ├── PrEPAWebService-ims-aks-test/
│   ├── azure-extmgmt-prod-master/
│   └── ...                               # ~30 ARC repos, all read-only
├── eeoc-arc-integration-api/             # ARC API gateway (only repo that calls ARC)
├── eeoc-mcp-hub-functions/               # MCP aggregator (APIM + Functions)
├── eeoc-ofs-adr/                         # ADR Portal — mediation case management
├── eeoc-ofs-triage/                      # Triage — charge intake and routing
├── eeoc-ogc-trialtool/                   # OGC Trial Tool — attorney trial prep
└── eeoc-data-analytics-and-dashboard/    # Cross-platform analytics
```

Each repo should have its own `.claude/CLAUDE.md` with repo-specific instructions.
Paths in skills and agents (e.g., `eeoc-ofs-adr/docs/`) are relative to this workspace root.
Directories ending in `-clean` (e.g., `eeoc-ofs-adr-clean/`) are sanitized export copies — ignore them entirely.

---

## Platform Rules

**Secrets:** Azure Key Vault only. Zero hardcoded credentials anywhere.  
**Auth:** Managed identity for Azure service-to-service. `@eeoc.gov` → Entra ID. All others → Login.gov OIDC + PKCE + `private_key_jwt`.  
**PII:** Never in logs. Apply `_mask_pii()` or SHA-256 + KV salt hash before any log write.  
**AI audit:** Every AI generation requires a HMAC-SHA256 signed audit record, 7-year WORM retention. This is NARA-required — a 2025 OIG inquiry required retrieval of 18-month-old records.  
**AI prompts:** Stop sequences `["Legal Advice:", "Legal Conclusion:"]` on all legal-adjacent AI calls. Human reviews every AI output before case action.  
**ARC:** Only `eeoc-arc-integration-api` calls ARC directly. Every other repo calls that service.  
**MCP:** `MCP_ENABLED=false` and `MCP_PROTOCOL_ENABLED=false` by default. Every app must start and pass its health check with all integrations disabled.  
**Sessions:** Redis only. No cookie serialization.  
**Inter-service:** HTTPS only. Propagate `X-Request-ID` through every hop. RFC 7807 Problem Details on all error responses.  
**508:** 4.5:1 contrast minimum for text. 3:1 for non-text UI elements. Every chart requires an accessible `<details>` data table. Federal law — no exceptions.  
**Docs:** Match `eeoc-ofs-adr/docs/` style exactly. Read the nearest existing doc before writing a new one.

---

## Common Commands

```bash
# Lint + type check (run from repo root)
ruff check src/ && mypy --strict src/

# Tests (adjust path per repo)
python -m pytest tests/ -v --tb=short
bash scripts/run_tests_two_loops.sh tests/   # Azure Function state leak check

# Security scans
bandit -r src/ -ll
detect-secrets scan --baseline .secrets.baseline --force-use-all-plugins

# Supply chain
cyclonedx-py requirements requirements.txt -o sbom.json --format json
pip-licenses --order=license --fail-on="GNU General Public License"
trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed "$IMAGE"
```

---

## Skills

Read the relevant skill before starting work in that domain.

| Domain | Skill |
|---|---|
| Any template, HTML, CSS, chart, form, icon, modal, email | `.claude/skills/508/SKILL.md` |
| Any AI call, prompt design, audit logging, WORM | `.claude/skills/ai-audit/SKILL.md` |
| Any Azure resource, Terraform, Bicep, container, CI/CD | `.claude/skills/fedramp/SKILL.md` |
| Any new document | `.claude/skills/doc-style/SKILL.md` |
| Any ARC integration code | `.claude/skills/arc/SKILL.md` |

---

## When to Use Agents vs. Work Directly

**Use the orchestrator agent** for planned, multi-repo, or cross-cutting work:
- New features that touch multiple repos
- Architecture analysis or gap assessments across the platform
- Broad audits (security review, 508 audit, ARC inventory)
- Writing compliance documents that reference multiple repos
- Any task where the scope spans more than one repo

**Work directly** (no agents) for:
- Debugging — tester feedback, bug reports, error traces. Investigation is iterative and
  exploratory; agent handoffs lose context mid-diagnosis. Diagnose first, then optionally
  dispatch agents for a cross-repo fix after the root cause is known.
- Single-repo changes — a fix, feature, or refactor scoped to one repo
- Research and investigation — "what changed since commit X", "does this repo need new
  env vars", "what does this function do", "find where X is configured". For these, read
  the code and git history, then answer the question. Do not write code unless asked.
- Code review of a single PR

In both modes, CLAUDE.md rules, skills, hooks, and hard limits all still apply. Agents are
an orchestration layer for parallelism and specialization — not a prerequisite for correctness.

**Tester feedback convention:** place bug reports in `debug/<date>-<short-title>/` with
`notes.md`, screenshots, and logs. Read all files in the directory, trace from UI to data
source, and show the diagnosis before writing any fix.

---

## Hard Limits

1. Never modify `eeoc-arc-payloads/` — it is a read-only ARC contract repository
2. Never call ARC APIs from any repo other than `eeoc-arc-integration-api`
3. Never log PII in any form in any repo
4. Never skip AI audit logging on any AI generation
5. Never disable or bypass 508 accessibility requirements
