---
name: fedramp
description: >
  FedRAMP High control implementation patterns for EEOC Azure Commercial infrastructure.
  Read before writing Terraform, Bicep, Azure Policy, or any infrastructure code.
  Maps Azure resource configurations to NIST 800-53 Rev5 controls.
---

# FedRAMP High — Azure Commercial Infrastructure

---

## Mandatory Resource Configurations

Every Azure resource must be configured as follows:

**Storage Accounts:** TLS 1.2+, CMK AES-256, private endpoint, no public blob access.
WORM containers: time-based immutability 2555 days, locked policy.
Tag: `RetentionPolicy = "FOIA_7_YEAR"` on audit blob containers.

**Key Vault:** RBAC authorization model (not legacy access policies). Soft-delete 90 days.
Purge protection enabled. Key rotation automated ≤1 year. All operations logged to Log Analytics.

**App Service / Container Apps:** Managed identity. No public SCM. HTTPS-only. Min TLS 1.2.

**Redis Cache:** Premium tier. TLS 1.2+. Microsoft Entra auth (managed identity token).

**PostgreSQL Flexible Server (if used):** Private endpoint. Entra auth. Audit logging enabled.
`log_connections=on`, `log_disconnections=on`, `pgaudit.log='write,ddl'`.

**Azure OpenAI:** Private endpoint. Content filtering enabled. Diagnostic settings to Log Analytics.

**All resources:** Tag with `Environment`, `DataClassification`, `FedRAMPControl`, `Owner`.

---

## Terraform Patterns

```hcl
# Every resource: FedRAMP control comment
# FedRAMP: SC-28 - Protection of Information at Rest
resource "azurerm_storage_account" "audit" {
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true
  public_network_access_enabled = false
  # ...
}

# Management lock on production resources
resource "azurerm_management_lock" "audit_lock" {
  name       = "production-lock"
  scope      = azurerm_storage_account.audit.id
  lock_level = "CanNotDelete"
}
```

---

## NIST 800-53 Control Quick Reference

| Control | Implementation |
|---|---|
| AC-2/AC-3 | Entra ID + RBAC; `@require_aad_role` decorator on all routes |
| AU-2/AU-3 | Structured JSON logging; HMAC-SHA256 on every audit record |
| AU-9 | WORM blob immutability; HMAC verification on read |
| CP-9/CP-10 | East US primary, West US 2 DR; documented in Disaster_Recovery_Runbook.md |
| IA-5 | Managed identity; no service account passwords |
| SC-7 | NSGs, private endpoints, App Gateway WAF v2 |
| SC-8/SC-28 | TLS 1.2+; AES-256 CMK on all storage |
| SI-3 | MalwareScanner Azure Function; Defender for Storage |
| SI-10 | Input validation on all routes; regex on all identifiers |
| SR-4 | CycloneDX SBOM; Trivy container scanning; no GPL in production |

---

## Supply Chain (SR family)

```bash
# Generate SBOM
cyclonedx-py requirements requirements.txt -o sbom.json --format json

# GPL check — fail pipeline on any GPL dep in production
pip-licenses --order=license --fail-on="GNU General Public License"

# Container scan — fail on CRITICAL or HIGH unfixed CVEs
trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed $IMAGE

# Secrets scan — fail on any finding
detect-secrets scan --baseline .secrets.baseline --force-use-all-plugins
```

---

## Container Hardening

```dockerfile
FROM python:3.11-slim-bookworm AS builder
# ... build stage

FROM python:3.11-slim-bookworm AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd -r appgroup && useradd -r -g appgroup -u 1001 appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /install /usr/local
COPY --chown=appuser:appgroup . .
USER appuser
HEALTHCHECK --interval=30s --timeout=10s CMD curl -f http://localhost:8000/health || exit 1
```

---

## OSCAL (due September 2026)

All authorization packages must be produced in OSCAL 1.1 JSON format.
Every implemented requirement references the NIST 800-53 Rev5 control ID.
Include inheritance statements for Azure-inherited controls.
