---
name: arc
description: >
  ARC integration patterns — when to use eeoc-arc-integration-api, how to
  validate payloads, authentication methods, and cross-system data flow.
  Read before touching any ARC-related code in any repo.
---

# ARC Integration — EEOC Platform

---

## The Golden Rule

Only `eeoc-arc-integration-api` calls ARC APIs.
Every other repo calls `eeoc-arc-integration-api`.
Never call ARC directly from any other repo.

---

## Payload Validation

All ARC responses must be validated against schemas in `eeoc-arc-payloads/` before processing.
Never assume an ARC response matches expectations — validate first, process second.

---

## Authentication (configure via Key Vault — never hardcode)

| `ARC_AUTH_METHOD` | When to use | Key Vault secrets needed |
|---|---|---|
| `managed_identity` | Integration API URL configured (preferred) | None |
| `api_key` | Legacy key auth | `ARC-API-KEY` |
| `bearer` | Bearer token | `ARC-API-KEY` |
| `basic` | HTTP Basic | `ARC-API-KEY` + `ARC-API-SECRET` |

---

## Input Validation (always before any operation)

```python
import re
ARC_CASE_NUMBER_RE = re.compile(r'^[A-Za-z0-9\-\.]{1,100}$')

def validate_arc_case_number(value: str) -> str:
    if not ARC_CASE_NUMBER_RE.match(value):
        raise ValueError(f"Invalid ARC case number: {value!r}")
    return value

def mask_email(email: str) -> str:
    """_mask_pii pattern — never log raw email addresses from ARC."""
    parts = email.split('@')
    if len(parts) == 2:
        return parts[0][:2] + '***@' + parts[1]
    return '***'
```

---

## SSRF Prevention

Block private/loopback/link-local/reserved IPs on all outbound ARC calls.
This must be implemented in `eeoc-arc-integration-api` — covers IPv4, IPv6,
IPv4-mapped IPv6 (e.g., `::ffff:10.0.0.1`), and alternate IP encodings.

---

## Feature Flags (all off by default)

```python
ARC_SYNC_ENABLED    = os.environ.get("ARC_SYNC_ENABLED", "true") == "true"
ARC_LOOKUP_ENABLED  = os.environ.get("ARC_LOOKUP_ENABLED", "false") == "true"
ARC_WRITEBACK_ENABLED = os.environ.get("ARC_WRITEBACK_ENABLED", "false") == "true"
```

Every integration path must check its flag before executing.
App health check must pass with all flags false.

---

## Staged Case Status Flow (ADR pattern)

```
ARC API → ARCSyncImporter (Azure Function) → arcstagedcases table (Status: Pending)
                                                        ↓
                                              Mediator reviews on dashboard
                                                        ↓
                                         Accept → mediationcases + caseparticipants
                                         Reject → arcstagedcases (Status: Rejected, retained for audit)
```

`arcstagedcases.ARCRawPayload`: max 60 KB per record.
