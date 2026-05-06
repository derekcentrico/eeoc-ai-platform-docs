# EEOC AI Platform
**Author:** Derek Gordon

Python 3.13 · Flask · Azure Functions · Azure Table Storage · Azure Blob · Redis · Azure OpenAI  
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
| `eeoc-ochco-benefits-validation` | OCHCO benefits coding validation and overpayment detection | Yes |
| `eeoc-ai-platform-docs` | Consolidated platform documentation (architecture, deployment, compliance) | Yes |

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
├── eeoc-ochco-benefits-validation/        # OCHCO benefits coding validation
├── eeoc-ogc-trialtool/                   # OGC Trial Tool — attorney trial prep
├── eeoc-data-analytics-and-dashboard/    # Cross-platform analytics
└── eeoc-ai-platform-docs/               # Consolidated platform documentation
```

Each repo should have its own `.claude/CLAUDE.md` with repo-specific instructions.
Paths in skills and agents (e.g., `eeoc-ofs-adr/docs/`) are relative to this workspace root.
Directories ending in `-clean` (e.g., `eeoc-ofs-adr-clean/`) are sanitized export copies — ignore them entirely.

### Documentation Repo Sync

`eeoc-ai-platform-docs/` holds platform-wide documentation that spans multiple
applications. When any of the following changes are made, sync the affected files
to the docs repo before or alongside the PR:

- New or updated platform architecture docs (cross-cutting, not app-specific)
- Changes to workspace CLAUDE.md, skills, or agents
- New application onboarded to the platform
- Changes to unified access control, auth patterns, or deployment guides
- New architecture decision documents (email_*.md at workspace root)

Per-application docs stay in each repo's `docs/` directory. Only platform-level
docs that reference multiple applications belong in the docs repo.

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

## Local CI (no GitHub Actions required)

GitHub Actions billing may be off — every gate that CI runs is also runnable
locally. Always run the local sweep before pushing or opening a PR; do not wait
for CI to surface findings that the local stack would catch.

### One-shot local evidence sweep (per repo)

```bash
# Full sweep — every gate the CI pipeline runs, in one command
bash scripts/local-ci.sh

# Skip slow gates (ScanCode, Trivy image build) when iterating
bash scripts/local-ci.sh --fast

# Config/scan only, no pytest
bash scripts/local-ci.sh --skip-tests
```

`local-ci.sh` exists in eeoc-ofs-adr; copy and adapt the per-repo source paths
when adding it to other repos. The script summarizes PASS / SKIP / FAIL across
all gates and exits non-zero on the first hard failure.

### Individual gates (when triaging a single failure)

| Gate | Command | Notes |
|---|---|---|
| Lint | `ruff check <src-dirs>` | Auto-fix safe issues with `--fix` |
| Format | `ruff format --check <src-dirs>` | Apply with `ruff format` (no `--check`) |
| Types | `mypy <src-dirs> --ignore-missing-imports` | Informational, non-gating |
| Tests | `python -m pytest tests/ -v` | Includes Hypothesis fuzz |
| SAST: Bandit | `bandit -r <src-dirs> --severity-level medium` | |
| SAST: Semgrep + PII rules | `semgrep --config .semgrep/ --severity ERROR --error <src-dirs>` | Gating |
| SCA: pip-audit | `pip-audit -r <component>/requirements.txt` | Per component |
| SCA: OSV-Scanner | `osv-scanner --recursive .` | Soft fail in local-ci.sh |
| SCA: Grype | `grype dir:. --fail-on high` | |
| License | `bash scripts/license-scan.sh` | Copyleft gate |
| License (deep) | `scancode --license --copyright --json-pp results.json .` | Slow |
| Secrets | `gitleaks detect --source . --redact` | Full git history |
| SBOM | `bash scripts/generate-sbom.sh` | CycloneDX + Syft |
| IaC | `checkov -d deploy/ --soft-fail` | Per IaC dir |
| Container (fs) | `trivy fs --severity CRITICAL,HIGH --ignore-unfixed .` | |
| Container (image) | `trivy image --severity CRITICAL,HIGH --ignore-unfixed <image>` | Build first |
| DAST | `bash scripts/dast-baseline.sh` | Needs Docker + staging URL |

### Required local tools

All installed at `~/.local/bin/` on the platform host.

```bash
# Python (pip --break-system-packages)
ruff mypy pytest hypothesis bandit semgrep pip-audit pip-licenses
cyclonedx-bom scancode-toolkit pre-commit
# Checkov in its own venv at ~/.local/checkov-venv (cyclonedx-python-lib conflict)

# Binaries
gitleaks syft grype trivy osv-scanner
# cosign — only needed in CI (keyless OIDC requires GitHub Actions runner)
```

### Pre-commit hook (per repo, one-time setup)

```bash
cd <repo> && pre-commit install
```

Runs gitleaks + ruff on every `git commit`. Some repos also wire `lint-508`
and `post-impl-verify` (conditional on workspace `.claude/hooks/` existing).

### Verification step requirement

Every code change must pass the local sweep before commit. The four-loop
functionality audit and the security audit in the user-global CLAUDE.md are
both satisfied by `bash scripts/local-ci.sh` returning exit 0. PII rule
findings (Semgrep ERROR severity) are gating — fix them in the same branch
or refactor to format-args style; do not weaken the rule.

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
| Any comment, docstring, markdown, or prose review | `.claude/skills/human-tone/SKILL.md` |
| Pre-commit security hardening (all PRs) | `.claude/skills/pre-pentest/SKILL.md` |

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

## Post-Implementation Verification (MANDATORY)

After completing any code change and before creating a PR, delegate to the
`post-impl-verifier` agent. Do not skip any pass. Do not ask whether to run
them. Run them automatically.

The verifier runs six passes on the changeset:
1. **Docs accuracy** (2 loops) — verify `docs/` references match changed code
2. **AI-language tone** (2 loops) — eliminate AI-generated prose patterns
3. **Security** — OWASP Top 10, secrets scan, injection review
4. **Functionality** (4 loops) — parse, trace, callers, tests
5. **SCA/SAST/DAST compliance** — license, lint, CSP, eval/exec
6. **Pre-pen-test hardening** — static analysis against the 10 pen-test
   categories in `.claude/skills/pre-pentest/SKILL.md`. Scoped to the
   changeset's affected files and the routes/endpoints they touch. Any
   CRITICAL or HIGH finding blocks the PR. MEDIUM findings are noted
   but do not block. Output appended to the verifier report.

If any pass fails and cannot be auto-fixed, stop and report. Do not create a
PR with outstanding failures.

### AI-Language Quick Reference

These terms are banned in all comments, docstrings, docs, and templates:
`leverage`, `utilize`, `streamline`, `robust`, `comprehensive`, `seamless`,
`empower`, `innovative`, `cutting-edge`, `delve`, `paradigm`, `synergy`,
`holistic`, `pivotal`, `cornerstone`, `foster`, `harness`, `testament`

Replace with plain words: `use`, `reliable`, `full`, `simplify`, `improve`.
Start docstrings with imperative verbs, not "This function/class...".
No conclusion sections in markdown. No pedagogical framing.

---

## Hard Limits

1. Never modify `eeoc-arc-payloads/` — it is a read-only ARC contract repository
2. Never call ARC APIs from any repo other than `eeoc-arc-integration-api`
3. Never log PII in any form in any repo
4. Never skip AI audit logging on any AI generation
5. Never disable or bypass 508 accessibility requirements
6. Never skip post-implementation verification before PR creation
7. Never skip reading the 508 skill before writing any template or HTML
8. Never pass a verification check by noting "tool not installed" — install it or fail the check
9. Never commit templates without running the 508 audit grep commands from the skill file
10. Never create a PR with CRITICAL or HIGH pre-pen-test findings unresolved
