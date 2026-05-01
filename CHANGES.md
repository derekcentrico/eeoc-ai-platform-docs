# Python 3.13 Upgrade — All Repos

Python 3.12 → 3.13 across all EEOC platform repositories.
Python 3.13 extends EOL from October 2028 to October 2029.

psycopg2-binary 2.9.11 already has Python 3.13 wheels — no version
bump needed. Superset and JupyterHub Dockerfiles previously pinned
2.9.9 are aligned to 2.9.11 for consistency.

---

## eeoc-ofs-adr (12 files)

### Dependencies (no version change — 2.9.11 already supports 3.13)
- `adr_webapp/requirements.txt`
- `staff_portal/requirements.txt`
- `adr_functionapp/requirements.txt`
- `learning-processor-function/requirements.txt`

### Dockerfile (python:3.12-slim-bookworm → python:3.13-slim-bookworm)
- `staff_portal/Dockerfile` — builder and runtime stages

### CI Workflows (python-version 3.12 → 3.13)
- `.github/workflows/portal-build-and-test.yml`
- `.github/workflows/security-audit-evidence.yml` (6 jobs)

### Configuration (requires-python >=3.12 → >=3.13)
- `shared_code/pyproject.toml`

### Provisioning (runtime-version 3.12 → 3.13)
- `provision_adr_system.sh` — webapp and 2 function apps

### Documentation / Scripts
- `docs/SUPPLY_CHAIN_RISK.md` — runtime version references
- `scripts/generate-sbom.sh` — SBOM runtime metadata
- `adr_webapp/requirements.txt` — comment header

---

## eeoc-ofs-triage (33 files)

### Dependencies (no version change — 2.9.11 already supports 3.13)
- `case-processor-function/requirements.txt`
- `triage_webapp/requirements.txt`
- `learning-processor-function/requirements.txt`

### CI Workflows (python-version 3.12 → 3.13)
- `.github/workflows/security-audit-evidence.yml` (5 jobs)

### Configuration (requires-python / python_requires >=3.12 → >=3.13)
- `shared/pyproject.toml`
- `shared/setup.cfg`
- `example_data/shared_code/pyproject.toml`
- `example_data/shared_code/setup.cfg`

### Provisioning (runtime-version 3.12 → 3.13)
- `provision_azure.sh` — 5 runtime version references
- `example_data/provision_adr_system.sh` — 3 runtime version references

### Documentation
- `README.md` — prerequisites
- `COMPLIANCE_AUDIT_PROMPT.md` — audit checklist
- `docs/SUPPLY_CHAIN_RISK.md`
- `docs/Azure_Portal_Provisioning_Guide.md`
- `docs/Azure_Portal_Development_Provisioning_Guide.md`
- `docs/Azure_Portal_ZIP_Deployment_Guide.md`
- `docs/Azure_Portal_OFS_Triage_Guide.md`
- `docs/ADR_Architecture_Visual.md`
- `docs/ADR_Architecture_Diagram.md`
- `docs/OFS_TRIAGE_Architecture_Diagram.md`
- `docs/OFS_Triage_Architecture_Visual.md`
- `docs/Component_Compliance_Reference_Guide.md`
- `example_data/adr_webapp/requirements.txt` — comment
- `example_data/COMPLIANCE_AUDIT_PROMPT.md`
- `example_data/docs/ADR_Architecture_Diagram.md`
- `example_data/docs/ADR_Architecture_Visual.md`
- `example_data/docs/ADR_Component_Compliance_Reference_Guide.md`
- `example_data/docs/Azure_Portal_Provisioning_Guide.md`
- `example_data/docs/Azure_Portal_Development_Provisioning_Guide.md`
- `example_data/docs/Azure_Portal_ZIP_Deployment_Guide.md`
- `example_data/docs/FedRAMP_Authorization_Boundary_Diagram.md`
- `example_data/docs/NIST_800-53_Compliance_Implementation_Analysis.md`

### Scripts
- `scripts/generate-sbom.sh` — SBOM runtime metadata

---

## eeoc-data-analytics-and-dashboard (26 files)

### Dependencies (psycopg2-binary aligned to 2.9.11)
- `deploy/docker/superset/Dockerfile` — 2.9.9 → 2.9.11
- `deploy/k8s/jupyterhub/user-image/Dockerfile` — 2.9.9 → 2.9.11

### Dockerfiles (python:3.12 → python:3.13)
- `deploy/docker/ai-assistant/Dockerfile` — base image
- `deploy/docker/data-middleware/Dockerfile` — base image
- `deploy/docker/superset/Dockerfile` — builder + runtime stages, site-packages path
- `deploy/k8s/jupyterhub/user-image/Dockerfile` — scipy-notebook base

### CI Workflows (python-version 3.12 → 3.13)
- `.github/workflows/build-and-test.yml`
- `.github/workflows/security-audit-evidence.yml` (6 jobs)

### Configuration (requires-python / python_requires >=3.12 → >=3.13)
- `shared_code/pyproject.toml`
- `shared_code/setup.cfg`
- `example_data/shared_code/pyproject.toml`
- `example_data/shared_code/setup.cfg`

### Provisioning (runtime-version 3.12 → 3.13)
- `example_data/provision_adr_system.sh`

### Documentation
- `README.md` — prerequisites
- `docs/Deployment_Guide.md`
- `docs/Azure_Portal_ZIP_Deployment_Guide.md`
- `docs/FedRAMP_Authorization_Boundary_Diagram.md`
- `example_data/adr_webapp/requirements.txt` — comment
- `example_data/COMPLIANCE_AUDIT_PROMPT.md`
- `example_data/docs/ADR_Architecture_Diagram.md`
- `example_data/docs/ADR_Architecture_Visual.md`
- `example_data/docs/ADR_Component_Compliance_Reference_Guide.md`
- `example_data/docs/Azure_Portal_Provisioning_Guide.md`
- `example_data/docs/Azure_Portal_Development_Provisioning_Guide.md`
- `example_data/docs/Azure_Portal_ZIP_Deployment_Guide.md`
- `example_data/docs/FedRAMP_Authorization_Boundary_Diagram.md`
- `example_data/docs/NIST_800-53_Compliance_Implementation_Analysis.md`

---

## eeoc-arc-integration-api (5 files)

### Dockerfile (python:3.12-slim-bookworm → python:3.13-slim-bookworm)
- `Dockerfile` — comment, builder, and runtime stages

### CI Workflows (python-version 3.12 → 3.13)
- `.github/workflows/build-and-test.yml` (3 jobs)
- `.github/workflows/security-audit-evidence.yml` (5 jobs)

### Documentation
- `README.md` — prerequisites
- `docs/SUPPLY_CHAIN_RISK.md` — container base image references

---

## eeoc-mcp-hub-functions (4 files)

### Dockerfile (python:3.12-slim-bookworm → python:3.13-slim-bookworm)
- `Dockerfile` — comment, builder, and runtime stages

### CI Workflows (python-version 3.12 → 3.13)
- `.github/workflows/build-and-test.yml` (3 jobs)
- `.github/workflows/security-audit-evidence.yml` (6 jobs)

### Documentation
- `docs/SUPPLY_CHAIN_RISK.md` — container base image reference

---

## eeoc-ogc-trialtool (10 files)

### CI Workflows (python-version 3.12 → 3.13)
- `.github/workflows/build-and-test.yml` (2 jobs)
- `.github/workflows/security-audit-evidence.yml` (4 jobs)

### Provisioning (runtime 3.11 → 3.13)
- `provision_ogc_trialtool.sh` — webapp and function app runtimes

### Documentation (Python 3.11 → 3.13)
- `README.md` — prerequisites and deployment steps
- `docs/OGC_Trial_Tool_Architecture_Diagram.md` — runtime version in diagram and resource table
- `docs/NARA_Data_Retention_Implementation_Plan.md` — provisioning step reference
- `docs/Azure_Portal_OGC_Trial_Tool_Guide.md` — webapp and function app runtime stack
- `docs/SUPPLY_CHAIN_RISK.md` — App Service runtime and deployment model
- `docs/NIST_800-53_Compliance_Implementation_Analysis.md` — CM-2 baseline description
- `docs/FedRAMP_Authorization_Boundary_Diagram.md` — boundary diagram and component table

---

## Workspace-level (1 file)

### Provisioning (runtime-version 3.12 → 3.13)
- `provision_eeoc_ai_platform.sh` — ADR and Triage function apps
