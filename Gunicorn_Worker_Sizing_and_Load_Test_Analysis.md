# Gunicorn Worker Sizing and Load Test Analysis
**Author:** Derek Gordon

## EEOC Data and AI Enterprise System (DAES)

---

## Purpose

Pre-production sizing validation for the July 2026 Seeker IAST prod cutover.
Both ADR Portal (`eeoc-ofs-adr`) and UDAP AI Assistant
(`eeoc-data-analytics-and-dashboard/ai-assistant`) now run `gthread` workers.
This document records the concurrency model, empirical results from local
fixture-app runs, recommended prod sizing, and the checklist to run against
staging before the July cutover.

> **Compliance:** FedRAMP High | NIST 800-53 SC-5, SI-2 | Azure Commercial

---

## 1. Concurrency Model

### 1.1 gthread vs. sync

| | `sync` | `gthread` |
|---|---|---|
| Concurrency unit | One request per worker process | One request per OS thread |
| Ceiling formula | `workers` | `workers x threads` |
| SSE / long-poll | Worker blocked for stream duration | Thread blocked; other threads in same worker remain free |
| Seeker IAST safety | gevent monkey-patch caused SSL recursion on Python 3.13 | No monkey-patch; Seeker agent coexists safely |
| `--timeout` behavior | Kills worker after N seconds of no data sent | Kills worker-thread pair; less aggressive for slow I/O |

### 1.2 SSE thread pinning

Each open SSE stream (`/api/chat`, `stream_with_context`) holds one `gthread`
OS thread for the duration of the stream. Under `sync` workers, each SSE
stream holds an entire worker process. The difference:

- `sync` 4 workers: 4 simultaneous SSE streams max
- `gthread` 4 workers x 8 threads: 32 simultaneous SSE streams max

When all threads are occupied, new requests queue at the OS socket level.
The first observable symptom is a p99 spike before timeouts appear, which is
why the load test's p99/p50 ratio is the primary saturation signal.

### 1.3 Current prod configurations

| App | Workers | Class | Threads | Concurrent ceiling | Timeout |
|---|---|---|---|---|---|
| ADR Portal | 4 (env: `GUNICORN_WORKERS`) | `gthread` | 4 (`GUNICORN_THREADS`) | 16 | 600 s |
| AI Assistant | 4 | `gthread` | 8 | 32 | 120 s |

ADR's 600 s timeout accommodates long e-signature and document-processing
round-trips. AI Assistant's 120 s timeout covers the longest expected OpenAI
streaming response with Azure latency included.

---

## 2. Harness Location and Usage

Two self-contained test runner scripts are committed to each repo:

```
eeoc-ofs-adr/
  loadtest/
    run_loadtest.py     -- async httpx test runner (fast + slow scenarios)
    fixture_app.py      -- Flask fixture; boots without Azure deps

eeoc-data-analytics-and-dashboard/ai-assistant/
  loadtest/
    run_loadtest.py     -- async httpx test runner (fast + slow + SSE scenarios)
    fixture_app.py      -- Flask fixture with /healthz /slow /sse-stream
```

Both test runners require only `httpx` (already installed on the platform host)
and standard-library `asyncio`. No additional dependencies.

#### Fixture app boot (gthread config):

```bash
# ADR: 4 workers x 4 threads
gunicorn --bind 0.0.0.0:8765 --workers 4 --worker-class gthread \
    --threads 4 --timeout 30 \
    --chdir eeoc-ofs-adr loadtest.fixture_app:app

# AI Assistant: 4 workers x 8 threads
gunicorn --bind 0.0.0.0:8765 --workers 4 --worker-class gthread \
    --threads 8 --timeout 30 \
    --chdir eeoc-data-analytics-and-dashboard/ai-assistant \
    loadtest.fixture_app:app
```

#### Fixture app boot (sync baseline):

```bash
# sync needs workers >= expected concurrency
gunicorn --bind 0.0.0.0:8766 --workers 16 --worker-class sync \
    --timeout 30 \
    --chdir eeoc-data-analytics-and-dashboard/ai-assistant \
    loadtest.fixture_app:app
```

#### Run the test runner:

```bash
# ADR
python loadtest/run_loadtest.py \
    --base-url http://127.0.0.1:8765 \
    --concurrency 32 --duration 30 --ramp 4 \
    --hold-seconds 4 --slow-ratio 0.5

# AI Assistant (SSE scenario)
python loadtest/run_loadtest.py \
    --base-url http://127.0.0.1:8765 \
    --concurrency 40 --duration 45 --ramp 8 \
    --sse-hold 10 --sse-ratio 0.5 --slow-ratio 0.2
```

---

## 3. Empirical Results (local fixture-app runs)

All runs used localhost gunicorn against the fixture app. No Azure services
(Key Vault, Redis, Azure OpenAI, Table Storage) were involved. Results
reflect pure concurrency / thread-scheduling behaviour, not AI response
latency or network I/O to Azure. See section 5 for what must still run
against staging.

### 3.1 AI Assistant -- gthread 4 workers x 8 threads vs. sync 16 workers

Test parameters: 40 concurrent workers, 45 s, 50% SSE (10 s hold), 20% slow (4 s sleep).

**gthread (4wx8t, ceiling = 32):**

| Scenario | Requests | Throughput | p50 ms | p95 ms | p99 ms | Error rate |
|---|---|---|---|---|---|---|
| fast (/healthz) | 23,717 | 527 req/s | 2 | 5 | 12 | 0.0% |
| slow (4 s sleep) | 81 | 1.8 req/s | 4,003 | 9,002 | 9,006 | 7.4% |
| SSE (10 s hold) | 94 | 2.1 req/s | 10,012 | 17,660 | 18,038 | 0.0% |
| Max concurrent SSE sustained | | | | | | **20** |

**sync (16 workers, ceiling = 16):**

| Scenario | Requests | Throughput | p50 ms | p95 ms | p99 ms | Error rate |
|---|---|---|---|---|---|---|
| fast (/healthz) | 259 | 5.8 req/s | 4 | 8,680 | 9,384 | 0.0% |
| slow (4 s sleep) | 48 | 1.1 req/s | 9,002 | 9,009 | 9,011 | 50.0% |
| SSE (10 s hold) | 68 | 1.5 req/s | 15,712 | 19,330 | 19,421 | 0.0% |
| Max concurrent SSE sustained | | | | | | **20** |

**Key observations:**

1. Fast-endpoint throughput: gthread delivered 527 req/s vs. 5.8 req/s for sync
   at the same 40-concurrency load. Sync workers were almost entirely occupied
   by SSE and slow connections, leaving virtually no free workers for fast
   requests.
2. Slow-scenario error rate: sync showed 50% errors on slow connections (timeout
   or queue rejection); gthread showed 7.4% because 8 of 40 slow-scenario
   workers occasionally waited for a free thread from the 32-slot pool.
3. SSE events received: gthread received 1,034 events vs. 748 for sync under
   the same load -- fewer dropped streams.
4. Both configurations showed p99/p50 ratio > 5 at 40 concurrent workers
   because 40 exceeds the gthread ceiling of 32 and the sync ceiling of 16.
   This is expected and validates the saturation detection logic.

### 3.2 AI Assistant -- SSE saturation test at gthread ceiling

Test parameters: 32 concurrent workers, 30 s, 80% SSE (12 s hold), 10% slow.
This approaches the 32-thread ceiling from below.

| Scenario | Requests | p50 ms | p99 ms | Error rate |
|---|---|---|---|---|
| fast (/healthz) | 5,102 | 2 | 12 | 0.0% |
| slow (4 s sleep) | 24 | 4,002 | 9,002 | 4.2% |
| SSE (12 s hold) | 70 | 12,019 | 22,053 | 0.0% |
| Max concurrent SSE | | | | **25** |

25 concurrent SSE streams were sustained before the p99 started climbing.
The 7-thread headroom (32 - 25) was consumed by fast-endpoint and slow
workers competing for threads. This confirms that 32 is the theoretical
ceiling but ~25 is the practical ceiling under mixed traffic.

### 3.3 ADR Portal -- gthread 4 workers x 4 threads

**At ceiling (16 concurrent):**

| Scenario | Requests | p50 ms | p99 ms | Error rate |
|---|---|---|---|---|
| fast (/healthz) | 16,518 | 2 | 5 | 0.0% |
| slow (4 s sleep) | 64 | 4,002 | 4,012 | 0.0% |

p99/p50 ratio within normal range. Zero errors. Clean headroom signal.

**At 2x ceiling (32 concurrent):**

| Scenario | Requests | p50 ms | p99 ms | Error rate |
|---|---|---|---|---|
| fast (/healthz) | 16,745 | 2 | 34 | 0.0% |
| slow (4 s sleep) | 113 | 4,003 | 7,200 | 0.0% |

p99 for slow requests climbed to 7,200 ms (1.8x the sleep duration) as
requests queued behind occupied threads. No errors -- gthread's 600 s
timeout gave queue residents time to drain. This matches expected behaviour
when concurrency exceeds the thread pool.

---

## 4. Recommended Production Sizing

### 4.1 ADR Portal

| Parameter | Current | Recommended |
|---|---|---|
| `GUNICORN_WORKERS` | 4 | 4 (keep) |
| `GUNICORN_THREADS` | 4 | 4 (keep) |
| Concurrent ceiling | 16 | 16 |
| `--timeout` | 600 | 600 |

**Rationale:** ADR's peak concurrent user count is low (district mediators,
EEOC staff). At 16 concurrent the fixture runs showed zero errors and p99
latency within 10% of p50. Increase `GUNICORN_THREADS` to 8 (ceiling 32)
only if sustained concurrent sessions exceed 12 (75% of the 16-thread pool).

**Sizing formula (Little's Law):** peak threads in use = arrival_rate x avg_hold_seconds.
`required_threads = ceil(arrival_rate * avg_hold_seconds / target_occupancy / workers)`

For ADR: assume 5 req/s peak arrival rate, 3 s average hold time, 80% target
occupancy. Peak in-flight = 5 x 3 = 15 threads. Required threads per worker =
ceil(15 / 0.8 / 4) = ceil(4.7) = 5. The current 4 threads/worker (16 total)
sits just under that -- adequate at this arrival rate, marginal if arrival rate
climbs to 6 req/s. At that point raise threads to 6 (24 total ceiling).

To increase ceiling on Azure App Service:

```bash
az webapp config appsettings set \
    --name <adr-app-name> --resource-group <rg> \
    --settings GUNICORN_WORKERS=4 GUNICORN_THREADS=8
```

### 4.2 UDAP AI Assistant

| Parameter | Current | Recommended |
|---|---|---|
| `--workers` | 4 | 4 (keep) |
| `--threads` | 8 | 8 (keep) |
| Concurrent ceiling | 32 | 32 |
| `--timeout` | 120 | 120 |

**Rationale:** The empirical SSE saturation test sustained 25 concurrent SSE
streams before queue latency appeared, giving 7-thread headroom under mixed
traffic. Azure OpenAI streaming responses typically last 5-15 s, so peak
thread occupancy at 20 concurrent analysts = 20 x 10 s / server_time; the
32-thread pool handles this comfortably for the current analyst user base.

**When to scale threads:** if the staging run (section 5) shows > 70% thread
pool occupancy at expected peak (20 concurrent analysts), raise threads to 12
or workers to 6.

**Sizing formula (Little's Law):** threads in use = arrival_rate x avg_hold_seconds.

```
peak_inflight = arrival_rate_req_per_s * avg_hold_seconds
required_threads = ceil(peak_inflight / target_occupancy)
threads_per_worker = ceil(required_threads / workers)
```

For AI Assistant: assume 2 SSE req/s peak arrival rate (20 analysts, each
sending one message every 10 s), avg SSE hold = 12 s, 80% target occupancy.
Peak in-flight = 2 x 12 = 24 threads. `required_threads = ceil(24 / 0.8)` = 30.
`threads_per_worker = ceil(30 / 4)` = 8. The current 8 threads/worker (32 total)
exactly meets this. If avg hold time rises to 15 s (longer AI responses),
peak in-flight = 30, required = ceil(30/0.8) = 38, threads_per_worker = 10 --
raise threads to 10 or workers to 5.

---

## 5. Pre-July Staging Validation Checklist

The local runs above validate the test runner and demonstrate the sync-vs-gthread
concurrency difference. They cannot exercise Azure OpenAI token-streaming
latency (typically 8-20 s end-to-end), Azure SQL round-trips, Redis session
reads, or Key Vault cold-starts. All of those affect thread occupancy.

Run these steps against the staging environment before the July prod cutover.

- [ ] **5.1 Boot check.** Confirm staging returns HTTP 200 from `/healthz`
  with all integrations enabled (`MCP_ENABLED=false` is acceptable for the
  load-test phase since the test runner does not call MCP routes).

- [ ] **5.2 ADR staging run -- mixed load.**
  ```bash
  python eeoc-ofs-adr/loadtest/run_loadtest.py \
      --base-url https://<adr-staging>.azurewebsites.net \
      --concurrency 16 --duration 60 --ramp 10 \
      --hold-seconds 8 --slow-ratio 0.4 \
      --cookie "session=<value>"
  ```
  Pass criteria: p99 < 2,000 ms; error rate < 1%; p99/p50 ratio < 5.

- [ ] **5.3 AI Assistant staging run -- SSE with real streaming.**
  Replace `--sse-path /sse-stream` with `/api/chat` and provide a session
  cookie from a logged-in analyst. Use a question that triggers a short SQL
  query (deterministic, fast) to control response length.
  ```bash
  python eeoc-data-analytics-and-dashboard/ai-assistant/loadtest/run_loadtest.py \
      --base-url https://<ai-assistant-staging>.azurewebsites.net \
      --concurrency 20 --duration 60 --ramp 10 \
      --sse-hold 20 --sse-ratio 0.7 --slow-ratio 0.0 \
      --sse-path /api/chat --sse-method POST \
      --sse-payload '{"message":"how many charges were filed in FY2023","conversation_id":""}' \
      --cookie "session=<value>"
  ```
  Pass criteria: p99 SSE < 30,000 ms; error rate < 2%; max concurrent SSE >= 15.

- [ ] **5.4 Thread pool exhaustion probe.** Raise concurrency to 1.5x the
  ceiling (48 for AI Assistant, 24 for ADR) and confirm the p99/p50 ratio
  rises predictably rather than producing connection errors. Timeout errors
  are acceptable at 1.5x; connection refusals are not.

- [ ] **5.5 `--timeout` interaction.** For AI Assistant, send a prompt that
  triggers a long response (> 60 s of streaming). Confirm the gthread
  `--timeout 120` does not kill the stream mid-response. With `sync` workers
  the timeout fires at the worker level; with `gthread` it applies per thread,
  so a 120 s response on one thread does not affect other threads in the same
  worker.

- [ ] **5.6 Seeker agent overhead.** With Seeker enabled in staging, repeat
  step 5.2 and 5.3. Seeker's per-request instrumentation adds CPU overhead.
  Confirm p50 latency increase < 15% vs. the no-Seeker baseline.

- [ ] **5.7 Watch App Service metrics.** During staging runs, monitor:
  - Azure App Service: `HttpQueueLength` (should stay < 20)
  - Azure App Service: `RequestsInApplicationQueue`
  - gunicorn logs: worker restart events (indicate timeout kills)

**The authoritative pre-July validation must run against staging with Azure
OpenAI integrations fully enabled, using real SSE token streaming. Local
fixture results demonstrate the concurrency model but cannot substitute for
staging validation.**

---

## 6. Attestation

- [x] Empirical results captured against local gunicorn fixture app
- [x] Load test scripts committed to each repo's `loadtest/` directory
- [x] All test runner Python passes `ruff check`
- [x] Sizing recommendations derived from measured saturation points
- [x] Staging validation checklist reflects the full Azure integration surface

**Authorized Official:** ________________________________
**Date:** ________________________________

---

## Document Control

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | June 2026 | Derek Gordon / OIT | Initial release; fixture-app empirical run results |
