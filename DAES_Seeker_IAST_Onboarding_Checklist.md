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
2. [Worker class: convert gevent to gthread](#2-worker-class-convert-gevent-to-gthread)
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
monkey-patch patterns. gthread workers run multiple OS threads per worker
process, so all global state mutations at request time must be converted to
thread-local before enabling gthread.

```bash
# Find direct socket.getaddrinfo replacements (the ADR arc_client.py pattern)
grep -rEn "socket\.getaddrinfo[[:space:]]*=" <app-package>/ --include="*.py"

# Find any other global monkey-patches on stdlib network modules
grep -rEn "socket\.(setdefaulttimeout|create_connection)[[:space:]]*=" <app-package>/ --include="*.py"

# Find gevent explicit monkey-patching in app code
grep -rEn "gevent\.monkey|from gevent import monkey" <app-package>/ --include="*.py"
```

Replace `<app-package>/` with the repo's actual application package root:
`adr_webapp/`, `triage_webapp/`, `trial_tool_webapp/`, etc. Do not limit the
scan to `src/` or `app/`; those paths do not match the DAES package layout.

Where global monkey-patches are found, convert them to thread-local designs
before enabling gthread. A gevent worker's cooperative scheduler and a patched
global interact unpredictably under concurrent requests; a gthread worker's OS
threads share process globals and have the same problem with unsynchronized
mutation.

**ADR example:** `eeoc-ofs-adr/adr_webapp/arc_client.py:52-77` originally
replaced `socket.getaddrinfo` for the duration of each ARC connection, then
restored it. This per-request global swap is unsafe under gthread. The correct
pattern is to store the per-request resolution override in a `threading.local`
and install any wrapper function once at module import time, not per request.

Document each finding in the repo's SAST scan dispositions file (see
`eeoc-ofs-adr/docs/SAST_Scan_Dispositions.md` for the format).

---

## 2. Worker class: convert gevent to gthread

### Root cause

Seeker's agent registers itself via `seeker-exec`, which loads
`adr_webapp/seeker/lib-inject/sitecustomize.py` at interpreter startup in the
gunicorn master process. That file imports `ssl` and `urllib3` before any
worker forks. When a gevent worker starts, it calls
`gevent.monkey.patch_all()`, which tries to replace the already-initialized
`ssl.SSLContext`. On Python 3.13, the `SSLContext.minimum_version` property
setter recurses into itself and raises `RecursionError` on the first HTTPS
call -- Key Vault on every startup. This is gevent issue #1016.

**Assume this upstream gevent bug is never fixed.**

### Standard: gthread

gthread workers use OS threads and do NOT call `monkey.patch_all()`, so the
ssl module remains unpatched and the RecursionError does not occur. gthread
also preserves concurrency for I/O-bound and streaming (SSE) workloads: each
thread handles one request, and multiple threads run simultaneously within a
single worker process.

**gthread is the platform standard for all Seeker-instrumented gunicorn
services.** Plain sync was the interim fix used before the thread-safety audit
was completed and is no longer required.

### Thread-safety preconditions

gthread runs multiple threads per worker process. Verify the following before
enabling gthread in any repo:

- **No global reassignment of `socket.*`, `ssl.*`, or `sys.*` at request
  time.** Any module that installs a wrapper on these must do so once at
  import, not per request. Per-request resolution overrides must use
  `threading.local`. The ARC client DNS-pinning adapter is the worked example:
  convert the per-request `socket.getaddrinfo` swap to a thread-local design.

- **Lazy-init module singletons with observable side effects must use
  double-checked locking or eager init at startup.** Assignment-only lazy init
  (e.g., `if _cache is None: _cache = {}`) is GIL-atomic and acceptable;
  lazy init that makes network calls, writes files, or modifies globals is not.

- **Per-request state must be thread-local or function-local, never
  module-global.** Audit all module-level variables that change during request
  handling.

### Exception

Apache Superset (DAES analytics component) runs a `GeventWebSocketWorker` for
its own async WebSocket features. Superset runs as a separate, non-Seeker-
instrumented process and is excluded from this requirement.

### Configuration change

Remove `--worker-class gevent` (or `geventwebsocket.gunicorn.workers.GeventWebSocketWorker`)
from the gunicorn command and from any `GUNICORN_WORKER_CLASS` env var.

Replace with `--worker-class gthread`.

**ADR reference files:**
- `eeoc-ofs-adr/adr_webapp/startup.sh` -- App Service startup wrapper
- `eeoc-ofs-adr/deploy/k8s/adr-webapp/deployment.yaml:53` -- AKS deployment command
- `eeoc-ofs-adr/deploy/k8s/adr-webapp/configmap.yaml` -- `GUNICORN_WORKER_CLASS: "gthread"`

```yaml
# deploy/k8s/<repo>-webapp/configmap.yaml
GUNICORN_WORKER_CLASS: "gthread"
GUNICORN_TIMEOUT: "120"
```

```bash
# deploy/k8s/<repo>-webapp/deployment.yaml: inline command block
GUNICORN_CMD="gunicorn --bind=0.0.0.0:8000 \
    --workers=4 --worker-class=gthread --threads=4 \
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

gthread workers each handle `--threads` concurrent requests (one per OS
thread). Total concurrency is `workers * threads`. This replaces the previous
sync guidance where each worker handled one request at a time.

### Recommended baseline

| Flag | Value | Notes |
|---|---|---|
| `--worker-class` | `gthread` | Platform standard for Seeker-instrumented services |
| `--workers` | `4` (App Service) / `4` (AKS, adjust per replica CPU) | Scale horizontally via HPA rather than per-pod |
| `--threads` | `4` | Threads per worker; effective concurrency = workers * threads |
| `--timeout` | `120` | Per-request timeout |
| `--graceful-timeout` | `30` | Allows in-flight requests to drain before SIGKILL |
| `--keep-alive` | `5` | HTTP keep-alive seconds |
| `--max-requests` | `1000` | Recycle worker after N requests (guards memory growth) |
| `--max-requests-jitter` | `50` | Staggers recycling across workers |

### SSE and streaming endpoints

Each open Server-Sent Events (SSE) or streaming response pins one THREAD (not
a whole worker process) for its entire duration. For services with SSE or
streaming:

1. Count the maximum expected concurrent streams.
2. Raise `--threads` so that `workers * threads` exceeds
   `concurrent_streams + overhead_headroom`.
3. Run a load test against the streaming endpoint before enabling Seeker in a
   production-equivalent environment. Verify that non-streaming requests are
   not blocked while streams are open.

Confirm final `--workers` and `--threads` values with a load test before
promoting to PROD.

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
from flask import request

@app.after_request
def set_cache_control(response):
    endpoint = request.endpoint or ""
    if endpoint != "static" and not endpoint.endswith(".static") and "Cache-Control" not in response.headers:
        response.headers["Cache-Control"] = "no-store"
    return response
```

The `request.endpoint` check covers both the app-level static endpoint and
Blueprint static endpoints (which have the form `<blueprint_name>.static`).
The `or ""` guard handles the case where `endpoint` is `None` (e.g., 404
before routing completes).

Register this hook once in the application factory or the main app module,
not in individual Blueprints. Blueprint-level `after_request` hooks run only
for requests handled by that Blueprint.

### FastAPI (UDAP AI Assistant and any FastAPI services)

```python
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

STATIC_PATH_PREFIX = "/static"  # adjust to match your StaticFiles mount path

class CacheControlMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        if request.url.path.startswith(STATIC_PATH_PREFIX):
            # Static assets are content-hashed; leave them cacheable.
            return response
        if not response.headers.get("Cache-Control"):
            response.headers["Cache-Control"] = "no-store"
        return response

app.add_middleware(CacheControlMiddleware)
```

Starlette's `StaticFiles` sets no `Cache-Control` header by default, so
without the path exclusion the middleware would apply `no-store` to hashed
assets and break browser caching. Adjust `STATIC_PATH_PREFIX` to match the
mount path used in `app.mount(...)`.

### Azure Functions (DAES Function Apps)

Set the header on the `func.HttpResponse` object in each function that returns
dynamic content:

```python
# Merge with any headers the function already sets (e.g. the correlation ID).
existing_headers = {"X-Request-ID": request_id}
headers = {**existing_headers, "Cache-Control": "no-store"}
return func.HttpResponse(body, status_code=200, headers=headers)
```

For Functions that serve only authenticated API responses and never static
content, apply `no-store` unconditionally.

---

## 7. beautifulsoup4 version pin

The `seeker-agent` wheel declares a dependency constraint of
`beautifulsoup4<4.14`. Pin to `4.13.5` in any repo that installs the Seeker
wheel. There is no CVE driving this pin; it is a wheel dependency constraint.
4.13.x is the current pinned release; the pin tracks the seeker-agent wheel
constraint and should be updated only when the agent relaxes it.

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
| 1 | Run the pre-scan grep commands from §1 against the repo's actual package root. Document findings. | [ ] |
| 2 | Verify thread-safety preconditions from §2. Convert any per-request global mutations to thread-local designs. | [ ] |
| 3 | Convert gunicorn worker class to gthread (§2). Update startup.sh and ConfigMap. | [ ] |
| 4 | Apply sizing parameters from §3. Set --threads; identify SSE/streaming endpoints and plan thread count. | [ ] |
| 5 | Add `Cache-Control: no-store` hook to the app (§6). | [ ] |
| 6 | Pin `beautifulsoup4==4.13.5` in requirements.txt (§7). | [ ] |
| 7 | Set `SEEKER_SOURCE_CODE_INST_ENABLED=false` default in startup.sh (§4). | [ ] |
| 8 | Verify collector reachability from the target environment (§5). Record result in §5 table. | [ ] |
| 9 | Set `SEEKER_ENABLED=false` in base ConfigMap and `SEEKER_ENABLED=true` in the target overlay only (§4). | [ ] |
| 10 | Deploy to TEST. Watch pod startup logs for registration success. Check for looping `bad_record_mac` (§8). | [ ] |
| 11 | Confirm that `/health` or `/healthz` becomes ready and the app serves authenticated requests. | [ ] |
| 12 | Run a load test confirming workers * threads handles peak concurrency including open SSE streams. | [ ] |
| 13 | Review the Seeker console for this project key. Triage any new findings against SAST_Scan_Dispositions.md. | [ ] |

---

## Attestation

- [ ] Gunicorn worker class is gthread on all Seeker-instrumented services.
- [ ] Thread-safety preconditions verified: no per-request global socket/ssl/sys mutation.
- [ ] `SEEKER_ENABLED=false` is the base ConfigMap default for all repos.
- [ ] `SEEKER_SOURCE_CODE_INST_ENABLED=false` is set before Seeker loads.
- [ ] Fail-safe startup wrapper verified: app starts without `seeker-exec` on PATH.
- [ ] `Cache-Control: no-store` applied to all dynamic authenticated responses.
- [ ] `beautifulsoup4==4.13.5` pinned in requirements.txt for all Seeker-instrumented repos.
- [ ] Collector reachability verified per environment before enabling agent.
- [ ] Load test completed; --workers and --threads values confirmed for PROD.

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial release |
| 1.1 | June 2026 | Derek Gordon / OIT | Worker standard: sync replaced by gthread; thread-safety preconditions added; sizing updated for workers*threads model; Flask after_request guard handles blueprint static and None endpoint; FastAPI middleware excludes static path prefix; pre-scan grep updated to use actual package roots; attestation checkboxes reset to unchecked for per-repo use |
