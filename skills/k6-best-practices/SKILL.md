---
name: k6-best-practices
description: >
  Guides developers and testers in writing, fixing, and structuring k6 load test
  scripts using JavaScript or TypeScript. Use this skill whenever the user mentions
  k6, Grafana k6, load testing with JavaScript, virtual users, VUs, scenarios,
  executors, thresholds, checks, SharedArray, ramp-up stages, arrival rate,
  open/closed workload model, or wants to benchmark an API, WebSocket, or gRPC
  service using k6 — even if they do not explicitly say "k6" or "load test".
license: MIT
compatibility: "Claude Code, Cursor, Windsurf. Requires k6 installed (brew install k6 / apt install k6 / choco install k6) and Node.js 18+ for TypeScript."
model: sonnet
metadata:
  author: rcampos
  version: "1.0"
---

# k6 Scenario Builder

Enforces a consistent, production-ready pattern for k6 load test scripts using
**JavaScript** or **TypeScript**, covering HTTP/REST, WebSocket, and gRPC protocols.

## Output Format

When producing or fixing a script, always deliver three things:

1. **A complete, runnable script file** — never a partial snippet. The user should be able to copy it and run it immediately.
2. **The exact run command** with the environment variables needed (`BASE_URL`, `VUS`, etc.).
3. **A one-line explanation** of the executor chosen and why it fits the stated load goal.

---

## Step 1 — Gather Context

Ask only what is unknown. Typical questions:

- **Language:** JavaScript (default) · TypeScript
- **Protocol:** HTTP/REST · WebSocket · gRPC
- **Goal:** New script from scratch · Fix existing script · Specific DSL question
- **Workload model:** Do you need a fixed number of concurrent users (closed) or a fixed arrival rate (open)?

**Only load [references/PROTOCOLS.md](references/PROTOCOLS.md) when the user mentions WebSocket or gRPC.** Contains connection setup, event handling, and streaming DSL — non-obvious setup that users frequently get wrong.

**Only load [references/DESIGN-PATTERNS.md](references/DESIGN-PATTERNS.md) when the user asks about folder structure, project architecture, how to share data between VUs, or how to scale beyond a single script file.** Contains the modular pattern (config → data → requests → scenarios) with SharedArray, helper modules, and TypeScript setup.

---

## Step 2 — Apply the 5-Block Pattern

Every k6 script must have these five blocks in this order. Generate the complete skeleton first, then fill in the details — starting from a partial file leads to structural errors.

```
Block 1 → Options      scenarios, thresholds, executor configuration
Block 2 → Setup        one-time auth, data preparation, shared token acquisition
Block 3 → Data         SharedArray for parameterized inputs
Block 4 → Default fn   the VU workload: requests, checks, groups, sleep
Block 5 → Teardown     cleanup, connection close (optional but required for gRPC/WS)
```

---

## Common Mistakes — Check Every Script for These

These errors appear in almost every first-draft k6 script. Scan for them before delivering any code.

### 1. Using `sleep(0)` or no sleep — generates unrealistic load

Without think time, VUs hammer the server at maximum speed, generating 10–100× more load than real users. Always add `sleep()` between logical steps.

```javascript
// Wrong — no think time, unrealistic throughput
export default function() {
  http.get(`${BASE_URL}/api/products`);
  http.get(`${BASE_URL}/api/cart`);
}

// Correct — realistic think time between actions
export default function() {
  http.get(`${BASE_URL}/api/products`);
  sleep(randomIntBetween(1, 3));
  http.get(`${BASE_URL}/api/cart`);
  sleep(1);
}
```

### 2. Using `check()` as a test gate — it never fails the test

`check()` records pass/fail statistics but **never stops or fails the test**. To enforce SLAs, you must define `thresholds`. This is the most common misconception in k6.

```javascript
// Wrong — test always exits 0 even if every request returns 500
check(res, { 'status is 200': (r) => r.status === 200 });

// Correct — define thresholds to actually fail the test
export const options = {
  thresholds: {
    'http_req_failed': ['rate<0.01'],          // < 1% errors
    'http_req_duration': ['p(95)<500'],        // p95 < 500ms
    'checks': ['rate>0.99'],                   // > 99% checks pass
  },
};
// Keep check() for granular per-request diagnostics
check(res, { 'status is 200': (r) => r.status === 200 });
```

### 3. Hardcoded base URL — prevents multi-environment usage

```javascript
// Wrong — cannot target different environments
const res = http.get('https://hardcoded-prod.example.com/api/users');

// Correct — parameterize via environment variable with a safe default
const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';
export default function() {
  http.get(`${BASE_URL}/api/users`);
}
```

Run: `k6 run --env BASE_URL=https://prod.example.com script.js`

### 4. Loading large data files inside `default` — copied per VU, crashes memory

```javascript
// Wrong — file read and parsed on every iteration, every VU
export default function() {
  const users = JSON.parse(open('./data/users.json'));  // ❌ per-iteration read
  const user = users[Math.floor(Math.random() * users.length)];
}

// Correct — loaded once in init context, shared across all VUs
import { SharedArray } from 'k6/data';
const users = new SharedArray('users', () => JSON.parse(open('./data/users.json')));

export default function() {
  const user = users[Math.floor(Math.random() * users.length)];
}
```

### 5. Imports inside functions — causes runtime error

k6's init context runs once before VUs start. Module imports MUST be at the top level — placing them inside `default` or any other function throws a runtime error.

```javascript
// Wrong — runtime error: "import declarations may only appear at top level"
export default function() {
  import http from 'k6/http';  // ❌ not allowed
  http.get(url);
}

// Correct — always import at the top of the file
import http from 'k6/http';
import { check, sleep } from 'k6';

export default function() {
  http.get(url);
}
```

### 6. Using `ramping-vus` for throughput tests — wrong workload model

`ramping-vus` controls *concurrent users* (closed model). Under slow response times, throughput drops. For a fixed arrival rate (e.g., "100 RPS"), use `constant-arrival-rate` or `ramping-arrival-rate` instead.

```javascript
// Wrong for throughput goals — RPS varies with response time
scenarios: {
  load: { executor: 'ramping-vus', stages: [{ duration: '5m', target: 100 }] }
}

// Correct for fixed RPS target — arrival rate is constant regardless of response time
scenarios: {
  load: {
    executor: 'constant-arrival-rate',
    rate: 100,
    timeUnit: '1s',
    duration: '5m',
    preAllocatedVUs: 50,
    maxVUs: 200,
  }
}
```

### 7. Forgetting `preAllocatedVUs` in arrival-rate executors — dropped iterations

`constant-arrival-rate` and `ramping-arrival-rate` require `preAllocatedVUs`. Without enough pre-allocated VUs, k6 drops iterations silently. Watch for `dropped_iterations` in the output.

```javascript
// Wrong — not enough VUs, iterations dropped silently
executor: 'constant-arrival-rate',
rate: 100,
timeUnit: '1s',
duration: '5m',
preAllocatedVUs: 1,   // ❌ way too few

// Correct — pre-allocate enough VUs; set maxVUs as safety ceiling
executor: 'constant-arrival-rate',
rate: 100,
timeUnit: '1s',
duration: '5m',
preAllocatedVUs: 50,   // estimate: rate × avg_response_time_in_seconds
maxVUs: 200,           // hard ceiling
```

Rule of thumb: `preAllocatedVUs ≈ rate × p95_response_time_in_seconds × 1.2`

### 8. Ignoring `gracefulStop` — VUs killed mid-iteration

By default, k6 stops VUs immediately when the test ends, cutting requests in half and inflating error counts. Set `gracefulStop` to let in-flight iterations complete.

```javascript
// Wrong — abrupt termination inflates error metrics
scenarios: {
  load: { executor: 'constant-vus', vus: 100, duration: '5m' }
  // gracefulStop defaults to 30s — but explicitly set it
}

// Correct — always set explicitly based on your p99 response time
scenarios: {
  load: {
    executor: 'constant-vus',
    vus: 100,
    duration: '5m',
    gracefulStop: '30s',    // allow up to 30s for in-flight requests to finish
  }
}
```

### 9. Hardcoded auth tokens — all VUs share the same identity

```javascript
// Wrong — every VU authenticates as the same user
const headers = { Authorization: 'Bearer eyJhbGciOiJIUzI1NiJ9.abc123' };

// Correct — each VU authenticates independently in setup or default
export function setup() {
  const res = http.post(`${BASE_URL}/auth/login`, JSON.stringify({
    username: 'admin', password: __ENV.ADMIN_PASSWORD,
  }), { headers: { 'Content-Type': 'application/json' } });
  return { token: res.json('access_token') };
}

export default function(data) {
  const res = http.get(`${BASE_URL}/api/users`, {
    headers: { Authorization: `Bearer ${data.token}` },
  });
}
```

### 10. Missing `Content-Type` on POST requests — server returns 415

```javascript
// Wrong — server rejects with 415 Unsupported Media Type
http.post(`${BASE_URL}/api/users`, JSON.stringify({ name: 'Alice' }));

// Correct — always set Content-Type when sending a body
http.post(`${BASE_URL}/api/users`, JSON.stringify({ name: 'Alice' }), {
  headers: { 'Content-Type': 'application/json' },
});
```

---

## The 5-Block Pattern — Reference

### Block 1: Options (Scenarios + Thresholds)

```javascript
export const options = {
  scenarios: {
    load: {
      executor: 'ramping-vus',        // closed model: controls concurrent VUs
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },   // ramp up
        { duration: '5m', target: 50 },   // hold steady
        { duration: '2m', target: 0  },   // ramp down
      ],
      gracefulRampDown: '30s',
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],  // response time SLA
    http_req_failed:   ['rate<0.01'],                  // < 1% errors
    checks:            ['rate>0.99'],                  // > 99% checks pass
  },
};
```

### Block 2: Setup (One-time authentication or data preparation)

```javascript
const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';

export function setup() {
  const res = http.post(`${BASE_URL}/auth/login`,
    JSON.stringify({ username: __ENV.USERNAME, password: __ENV.PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  if (res.status !== 200) {
    fail(`Login failed: ${res.status} ${res.body}`);
  }
  return { token: res.json('access_token') };
}
```

### Block 3: Data (SharedArray for parameterized inputs)

```javascript
import { SharedArray } from 'k6/data';

const users = new SharedArray('users', () =>
  JSON.parse(open('./data/users.json'))
);
// Access in default: const user = users[exec.vu.idInTest % users.length];
// idInTest is 1-based; modulo gives deterministic, non-random distribution
```

### Block 4: Default Function (VU workload)

```javascript
import { group, check, sleep } from 'k6';
import { randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

export default function(data) {
  group('Authentication', () => {
    const res = http.get(`${BASE_URL}/api/profile`, {
      headers: { Authorization: `Bearer ${data.token}` },
      tags: { endpoint: 'profile' },
    });
    check(res, {
      'profile status 200':         (r) => r.status === 200,
      'profile has user id':        (r) => r.json('id') !== undefined,
      'profile time < 500ms':       (r) => r.timings.duration < 500,
    });
    sleep(randomIntBetween(1, 3));
  });

  group('Product Catalog', () => {
    const res = http.get(`${BASE_URL}/api/products`, {
      headers: { Authorization: `Bearer ${data.token}` },
      tags: { endpoint: 'products' },
    });
    check(res, {
      'products status 200':        (r) => r.status === 200,
      'products list not empty':    (r) => r.json('#') > 0,
    });
    sleep(randomIntBetween(2, 5));
  });
}
```

### Block 5: Teardown (Cleanup)

```javascript
export function teardown(data) {
  // Invalidate the session token
  http.post(`${BASE_URL}/auth/logout`, null, {
    headers: { Authorization: `Bearer ${data.token}` },
  });
}
```

---

## Executor Selection Guide

Choose the executor that matches the test goal — using the wrong one produces misleading results.

**Closed model** — controls *concurrent users*. Use for systems where the number of simultaneous connections matters (connection pools, session limits).

| Executor | When to use | Key params |
|---|---|---|
| `constant-vus` | Steady-state, fixed concurrency | `vus`, `duration` |
| `ramping-vus` | Ramp up/down, standard load test | `stages`, `startVUs` |
| `per-vu-iterations` | Each VU must run exactly N times | `vus`, `iterations` |
| `shared-iterations` | Total N iterations shared across VUs | `vus`, `iterations` |

**Open model** — controls *arrival rate*. Use for public APIs and stateless services where throughput (RPS) is the goal.

| Executor | When to use | Key params |
|---|---|---|
| `constant-arrival-rate` | Fixed RPS target, capacity test | `rate`, `timeUnit`, `preAllocatedVUs`, `maxVUs` |
| `ramping-arrival-rate` | Gradually increasing RPS | `stages`, `timeUnit`, `preAllocatedVUs`, `maxVUs` |
| `externally-controlled` | Live adjustment via k6 REST API, long soak tests | `vus`, `maxVUs`, `duration` |

**Rule of thumb:** Use `ramping-vus` for most tests. Switch to `constant-arrival-rate` when the SLA is expressed in RPS, not users.

---

## Thresholds Reference

```javascript
export const options = {
  thresholds: {
    // Response time
    http_req_duration:              ['p(95)<500', 'p(99)<1000'],
    // Per-tagged endpoint
    'http_req_duration{endpoint:checkout}': ['p(99)<2000'],
    // Error rate
    http_req_failed:                ['rate<0.01'],
    // Check pass rate
    checks:                         ['rate>0.99'],
    // Throughput floor
    http_reqs:                      ['rate>50'],
    // Abort test if threshold breached
    http_req_duration: [
      { threshold: 'p(95)<500', abortOnFail: true, delayAbortEval: '1m' },
    ],
    // Custom metric
    'my_custom_trend':              ['p(95)<300'],
  },
};
```

Use `abortOnFail: true` with `delayAbortEval` to avoid aborting during the ramp-up phase before metrics stabilize.

---

## Custom Metrics

```javascript
import { Counter, Gauge, Trend, Rate } from 'k6/metrics';

const checkoutDuration  = new Trend('checkout_duration_ms');
const authErrors        = new Counter('auth_errors_total');
const cacheHitRate      = new Rate('cache_hit_rate');
const activeCheckouts   = new Gauge('active_checkouts');

export default function(data) {
  const start = Date.now();
  const res   = http.post(`${BASE_URL}/api/checkout`, body, params);
  checkoutDuration.add(Date.now() - start, { step: 'payment' });

  if (res.status === 401) authErrors.add(1);
  cacheHitRate.add(res.headers['X-Cache'] === 'HIT');
}
```

---

## Run Commands

```bash
# Basic run (JS)
k6 run script.js

# With environment variables and duration override
k6 run --env BASE_URL=https://staging.example.com \
       --env USERNAME=perf_user \
       --env PASSWORD=secret \
       script.js

# Output to JSON for post-analysis
k6 run --out json=results.json script.js

# Output to InfluxDB + Grafana dashboard
k6 run --out influxdb=http://localhost:8086/k6 script.js

# TypeScript (transpile first via esbuild or webpack, or use k6-typescript-framework)
k6 run dist/script.js

# Cloud execution (requires Grafana Cloud account)
k6 cloud script.js
```

---

## References

- [Scenarios & Executors](references/EXECUTORS.md)
- [Protocols: WebSocket & gRPC](references/PROTOCOLS.md)
- [Modular Design Patterns](references/DESIGN-PATTERNS.md)
- [k6 JavaScript API](https://grafana.com/docs/k6/latest/javascript-api/)
- [Executors](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/)
- [Thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/)
- [Metrics Reference](https://grafana.com/docs/k6/latest/using-k6/metrics/reference/)
