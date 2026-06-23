# DAES Seeker IAST Onboarding Checklist
**Author:** Derek Gordon

## EEOC Data and AI Enterprise System (DAES)

---

## Purpose

Step-by-step checklist for onboarding a DAES application repo to Black Duck
Seeker IAST. All findings and workarounds apply to Python 3.13 gunicorn
services on the DAES platform. The ADR Portal (`eeoc-ofs-adr`) is the
verified reference implementation: Seeker-connected and tested in TEST
environment as of PR #409.

> **Audience:** Platform engineers onboarding a new DAES component repo.
> **Compliance:** FedRAMP High | NIST 800-53 SA-11 | Azure Commercial Cloud

---

## Table of Contents

1. [Pre-scan: thread-unsafe monkey-patch audit](#1-pre-scan-thread-unsafe-monkey-patch-audit)
2. [Worker class: convert gevent to sync](#2-worker-class-convert-gevent-to-sync)
3. [Gunicorn sizing after the conversion](#3-gunicorn-sizing-after-the-conversion)
4. [Kill switch and instrumentation flags](#4-kill-switch-and-instrumentation-flags)
5. [Collector firewall reachability](#5-collector-firewall-reachability)
6. [Cache-Control header hook](#6-cache-control-header-hook)
7. [beautifulsoup4 version pin](#7-beautifulsoup4-version-pin)
8. [First-boot TLS reconnect](#8-first-boot-tls-reconnect)
9. [Per-repo onboarding sequence](#9-per-repo-onboarding-sequence)

---

## 1. Pre-scan: thread-unsafe monkey-patch audit

Before touching any gunicorn config, scan the repo for global, thread-unsafe
monkey-patch patterns.

```bash
# Find direct socket.getaddrinfo replacements (the ADR arc_client.py pattern)
grep -rn "socket\.getaddrinfo\s*=" src/ app/ --include="*.py"

# Find any other global monkey-patches on stdlib network modules
grep -rn "socket\.\(setdefaulttimeout\|create_connection\)\s*=" src/ app/ --include="*.py"

# Find gevent explicit monkey-patching in app code
grep -rn "gevent\.monkey\|from gevent import monkey" src/ app/ --include="*.py"
```

Where global monkey-patches are found, sync workers are not merely safer; they
are the correct execution model. A gevent worker's cooperative scheduler and
the patched global interact unpredictably under concurrent requests.

**ADR example:** `eeoc-ofs-adr/adr_webapp/arc_client.py:52-77` replaces
`socket.getaddrinfo` for the duration of each ARC connection, then restores it.
This pattern is safe under sync workers and unreliable under gevent.

Document each finding in the repo's SAST scan dispositions file (see
`eeoc-ofs-adr/docs/SAST_Scan_Dispositions.md` for the format).

---

## 2. Worker class: convert gevent to sync

### Root cause

Seeker's agent registers itself via `seeker-exec`, which loads
`adr_webapp/seeker/lib-inject/sitecustomize.py` at interpreter startup in the
gunicorn master process. That file imports `ssl` and `urllib3` before any
worker forks. When a gevent worker starts, it calls
`gevent.monkey.patch_all()`, which tries to replace the already-initialized
`ssl.SSLContext`. On Python 3.13, the `SSLContext.minimum_version` property
setter recurses into itself and raises `RecursionError` on the first HTTPS
call -- Key Vault on every startup. This is gevent issue #1016. Sync workers
never call `monkey.patch_all()`, so the agent and the app coexist without
conflict.

**Assume this upstream gevent bug is never fixed.** Sync is the permanent
standard for every Seeker-instrumented gunicorn service on this platform.

### Exception

Apache Superset (DAES analytics component) runs a `GeventWebSocketWorker` for
its own async WebSocket features. Superset runs as a separate, non-Seeker-
instrumented process and is excluded from this requirement.

### Configuration change

Remove `--worker-class gevent` (or `geventwebsocket.gunicorn.workers.GeventWebSocketWorker`)
from the gunicorn command and from any `GUNICORN_WORKER_CLASS` env var.

Replace with `--worker-class sync` or omit the flag (sync is the gunicorn
default).

**ADR reference files:**
- `eeoc-ofs-adr/adr_webapp/startup.sh` -- App Service startup wrapper
- `eeoc-ofs-adr/deploy/k8s/adr-webapp/deployment.yaml:53` -- AKS deployment command
- `eeoc-ofs-adr/deploy/k8s/adr-webapp/configmap.yaml` -- `GUNICORN_WORKER_CLASS: "sync"`

```yaml
# deploy/k8s/<repo>-webapp/configmap.yaml
GUNICORN_WORKER_CLASS: "sync"
GUNICORN_TIMEOUT: "120"
```

```bash
# deploy/k8s/<repo>-webapp/deployment.yaml: inline command block
GUNICORN_CMD="gunicorn --bind=0.0.0.0:8000 \
    --workers=4 --worker-class=sync \
    --timeout=120 --graceful-timeout=30 \
    --keep-alive=5 --max-requests=1000 \
    --max-requests-jitter=50 \
    --access-logfile=- \
    <module>:<app>"
if command -v seeker-exec >/dev/null 2>&1; then
  exec seeker-exec $GUNICORN_CMD
else
  exec $GUNICORN_CMD
fi
```

---

## 3. Gunicorn sizing after the conversion

Sync workers each handle one request at a time. A gevent worker handled
thousands of concurrent lightweight coroutines. After converting, raise the
worker count and lower timeout to avoid request queuing.

### Recommended baseline (matching ADR)

| Flag | Value | Notes |
|---|---|---|
| `--workers` | `4` (App Service) / `4` (AKS, adjust per replica CPU) | Scale horizontally via HPA rather than per-pod |
| `--timeout` | `120` | Down from the 600s gevent setting in earlier ADR versions |
| `--graceful-timeout` | `30` | Allows in-flight requests to drain before SIGKILL |
| `--keep-alive` | `5` | HTTP keep-alive seconds |
| `--max-requests` | `1000` | Recycle worker after N requests (guards memory growth) |
| `--max-requests-jitter` | `50` | Staggers recycling across workers |

### SSE and streaming endpoints

Each open Server-Sent Events (SSE) or streaming response pins one sync worker
for its entire duration. For any service with SSE or streaming:

1. Count the maximum expected concurrent streams.
2. Set `--workers` to `(concurrent_streams + overhead_headroom)` at minimum.
3. Run a load test against the streaming endpoint before enabling Seeker in a
   production-equivalent environment. Verify that non-streaming requests are
   not blocked while streams are open.

---

## 4. Kill switch and instrumentation flags

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `SEEKER_ENABLED` | `false` | Master kill switch. Set to `true` only in environments where Seeker is active. |
| `SEEKER_SERVER_URL` | (required when enabled) | URL of the Seeker collector/enterprise server, e.g. `https://seeker.azurems.eeoc.gov:443` |
| `SEEKER_PROJECT_KEY` | (required when enabled) | Project identifier in the Seeker console |
| `SEEKER_SOURCE_CODE_INST_ENABLED` | `false` | Source-code instrumentation. Off by default. |

### SEEKER_SOURCE_CODE_INST_ENABLED

The Seeker `sitecustomize.py` sets `SEEKER_SOURCE_CODE_INST_ENABLED=true` when
the variable is absent from the environment. On Python 3.13, Seeker's source-
code instrumentation triggers caught circular-import errors during its own
package enumeration. These are not fatal, but they generate log noise on every
startup and obscure real errors.

Default it off in `startup.sh`:

```bash
# startup.sh: set before Seeker loads
export SEEKER_SOURCE_CODE_INST_ENABLED="${SEEKER_SOURCE_CODE_INST_ENABLED:-false}"
```

Because `sitecustomize.py` only writes the default when the variable is unset,
an explicit app setting (via ConfigMap or App Service app setting) overrides it.

### Fail-safe startup wrapper

The `seeker-exec` wrapper must not be required for the app to start. The guard
in `startup.sh` and the deployment command both follow this pattern:

```bash
command -v seeker-exec >/dev/null 2>&1 && exec seeker-exec gunicorn ...
exec gunicorn ...
```

If `seeker-exec` is not on PATH (wheel not installed, agent disabled), gunicorn
starts directly. This pattern is verified in
`eeoc-ofs-adr/adr_webapp/startup.sh:49-55`.

### Kill switch default in ConfigMap

```yaml
# deploy/k8s/<repo>-webapp/configmap.yaml
SEEKER_ENABLED: "false"
```

Enable per environment via Kustomize overlay. Never set `SEEKER_ENABLED=true`
in the base ConfigMap.

---

## 5. Collector firewall reachability

The Seeker agent performs a synchronous registration call to the collector
during each worker's startup. The registration uses `connecttimeout=None`,
meaning it blocks indefinitely if the collector is unreachable. When multiple
workers fail to register, the pod never becomes ready and the load balancer
returns 502s.

Verify outbound connectivity before enabling `SEEKER_ENABLED=true` in any
environment:

```bash
# From a pod or node in the target cluster/VNET
curl -v --max-time 10 https://seeker.azurems.eeoc.gov:443/rest/api/status
```

Check each environment independently:

| Environment | Collector reachable | Verification date | Verified by |
|---|---|---|---|
| DEV | | | |
| TEST | Yes | 2026-06-22 | ADR PR #409 | 
| STAGING | | | |
| PROD | | | |

If the collector is not reachable, leave `SEEKER_ENABLED=false` and open a
network-policy or NSG ticket before proceeding.

---

## 6. Cache-Control header hook

Seeker's first verified finding on a newly onboarded service is typically
**MISSING-CACHE-CONTROL-HEADER** (OWASP A5/A6 Security Misconfiguration,
CWE-16/CWE-933): dynamic and authenticated responses ship without a
`Cache-Control` header, allowing intermediate proxies or browsers to cache
sensitive content.

Add a global response hook that sets `Cache-Control: no-store` on dynamic
responses that do not already set it. Static assets (hashed CSS, JS, images)
must remain cacheable; do not apply `no-store` to the static file handler.

### Flask (primary pattern for DAES Flask services)

```python
@app.after_request
def set_cache_control(response):
    if request.endpoint != "static" and "Cache-Control" not in response.headers:
        response.headers["Cache-Control"] = "no-store"
    return response
```

Register this hook once in the application factory or the main app module,
not in individual Blueprints. Blueprint-level `after_request` hooks run only
for requests handled by that Blueprint.

### FastAPI (UDAP AI Assistant and any FastAPI services)

```python
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

class CacheControlMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        if not response.headers.get("Cache-Control"):
            response.headers["Cache-Control"] = "no-store"
        return response

app.add_middleware(CacheControlMiddleware)
```

Exclude the static files mount if one is configured.

### Azure Functions (DAES Function Apps)

Set the header on the `func.HttpResponse` object in each function that returns
dynamic content:

```python
headers = {**response_headers, "Cache-Control": "no-store"}
return func.HttpResponse(body, status_code=200, headers=headers)
```

For Functions that serve only authenticated API responses and never static
content, apply `no-store` unconditionally.

---

## 7. beautifulsoup4 version pin

The `seeker-agent` wheel declares a dependency constraint of
`beautifulsoup4<4.14`. Pin to `4.13.5` in any repo that installs the Seeker
wheel. There is no CVE driving this pin; it is a wheel dependency constraint.

```
# requirements.txt
# beautifulsoup4 held below 4.14: seeker-agent wheel constraint.
beautifulsoup4==4.13.5
```

**ADR reference:** `eeoc-ofs-adr/adr_webapp/requirements.txt:121-123`,
`eeoc-ofs-adr/staff_portal/requirements.txt:87-89`.

If a later `seeker-agent` release relaxes this constraint, update the pin to
match and note it in CHANGES.md.

---

## 8. First-boot TLS reconnect

On the first startup after Seeker registration, expect a single
`bad_record_mac` TLS error in the collector WebSocket connection log. This is a
known one-time reconnect on initial key exchange. The agent reconnects
automatically and the error does not recur in normal operation.

If the `bad_record_mac` error repeats on every request or loops continuously,
the collector TLS configuration or the cluster egress path is misconfigured.
Open a support ticket with the Seeker server URL, the Python version, and the
agent version before re-enabling.

---

## 9. Per-repo onboarding sequence

Complete steps in order. Do not enable `SEEKER_ENABLED=true` before the
prerequisites are verified.

| Step | Action | Done |
|---|---|---|
| 1 | Run the pre-scan grep commands from §1. Document findings. | [ ] |
| 2 | Convert gunicorn worker class to sync (§2). Update startup.sh and ConfigMap. | [ ] |
| 3 | Apply sizing parameters from §3. Identify SSE/streaming endpoints and plan worker count. | [ ] |
| 4 | Add `Cache-Control: no-store` hook to the app (§6). | [ ] |
| 5 | Pin `beautifulsoup4==4.13.5` in requirements.txt (§7). | [ ] |
| 6 | Set `SEEKER_SOURCE_CODE_INST_ENABLED=false` default in startup.sh (§4). | [ ] |
| 7 | Verify collector reachability from the target environment (§5). Record result in §5 table. | [ ] |
| 8 | Set `SEEKER_ENABLED=false` in base ConfigMap and `SEEKER_ENABLED=true` in the target overlay only (§4). | [ ] |
| 9 | Deploy to TEST. Watch pod startup logs for registration success. Check for looping `bad_record_mac` (§8). | [ ] |
| 10 | Confirm that `/health` or `/healthz` becomes ready and the app serves authenticated requests. | [ ] |
| 11 | Review the Seeker console for this project key. Triage any new findings against SAST_Scan_Dispositions.md. | [ ] |

---

## Attestation

- [x] Gunicorn worker class is sync on all Seeker-instrumented services.
- [x] `SEEKER_ENABLED=false` is the base ConfigMap default for all repos.
- [x] `SEEKER_SOURCE_CODE_INST_ENABLED=false` is set before Seeker loads.
- [x] Fail-safe startup wrapper verified: app starts without `seeker-exec` on PATH.
- [x] `Cache-Control: no-store` applied to all dynamic authenticated responses.
- [x] `beautifulsoup4==4.13.5` pinned in requirements.txt for all Seeker-instrumented repos.
- [x] Collector reachability verified per environment before enabling agent.

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial release |
