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
compatibility: "Claude Code, Cursor, Windsurf. Requires k6 installed (brew install k6 / apt install k6 / choco install k6). Node.js 18+ required only for TypeScript compilation."
model: sonnet
metadata:
  author: rcampos
  version: "1.1"
---

# k6 Scenario Builder

Enforces a consistent, production-ready pattern for k6 load test scripts using
**JavaScript** or **TypeScript**, covering HTTP/REST, WebSocket, and gRPC protocols.

## Output Format

When producing or fixing a script, always deliver three things:

1. **A complete, runnable script file** — never a partial snippet.
2. **The exact run command** with the environment variables needed.
3. **A one-line explanation** of the executor chosen and why it fits the load goal.

---

## Step 1 — Gather Context

Ask only what is unknown:

- **Language:** JavaScript (default) · TypeScript
- **Protocol:** HTTP/REST · WebSocket · gRPC
- **Goal:** New script · Fix existing script · Specific DSL question
- **Workload model:** Fixed concurrent users (closed) or fixed arrival rate in RPS (open)?

**Only load [references/EXECUTORS.md](references/EXECUTORS.md) when the user asks about executor types, workload models, scenario configuration, multi-scenario orchestration, or `startTime`/`exec`/`gracefulStop` parameters.**

**Only load [references/PROTOCOLS.md](references/PROTOCOLS.md) when the user mentions WebSocket or gRPC.** Contains connection setup, event handling, streaming DSL, and gotchas.

**Only load [references/DESIGN-PATTERNS.md](references/DESIGN-PATTERNS.md) when the user asks about folder structure, project architecture, sharing data between VUs, TypeScript setup, or scaling beyond a single file.**

---

## Step 2 — Apply the 5-Block Pattern

Every k6 script must have these five blocks in order. Generate the complete skeleton first, then fill in details.

```
Block 1 → Options     scenarios + thresholds (executor, VUs, duration, SLA gates)
Block 2 → Data        SharedArray for parameterized inputs — loaded once, shared across VUs
Block 3 → Setup       one-time auth or preparation — runs once before VUs start
Block 4 → Default fn  the VU workload: requests, checks, groups, sleep
Block 5 → Teardown    cleanup (optional — required for gRPC/WS connection close)
```

---

## Common Mistakes — Check Every Script for These

### 1. No `sleep()` between requests — generates unrealistic load

Without think time, VUs hammer the server at maximum speed. Always add `sleep()` between logical steps.

```javascript
// Wrong — zero think time, unrealistic throughput
export default function() {
  http.get(`${BASE_URL}/api/products`);
  http.get(`${BASE_URL}/api/cart`);
}

// Correct — realistic think time between steps
import { sleep } from 'k6';

export default function() {
  http.get(`${BASE_URL}/api/products`);
  sleep(Math.random() * 2 + 1);  // 1–3s think time
  http.get(`${BASE_URL}/api/cart`);
  sleep(1);
}
```

### 2. `check()` as a test gate — it never fails the test

`check()` records pass/fail statistics but **never stops or fails the test**. This is the most common k6 misconception. Use `thresholds` to actually fail.

```javascript
// Wrong — test always exits 0 even if every request returns 500
check(res, { 'status is 200': (r) => r.status === 200 });

// Correct — thresholds fail the test; check() provides per-request diagnostics
export const options = {
  thresholds: {
    http_req_failed:   ['rate<0.01'],   // < 1% errors — fails test if breached
    http_req_duration: ['p(95)<500'],   // p95 < 500ms — fails test if breached
    checks:            ['rate>0.99'],   // > 99% checks pass
  },
};
check(res, { 'status is 200': (r) => r.status === 200 });  // keep for diagnostics
```

**Three failure mechanisms:**
- `check()` — per-iteration assertion, records stats, never stops the test
- `threshold` — aggregate SLA gate, fails the test on breach (exit code 99)
- `fail(msg)` — stops the current iteration immediately, use for unrecoverable errors

### 3. Hardcoded base URL — breaks multi-environment usage

```javascript
// Wrong
const res = http.get('https://hardcoded-prod.example.com/api/users');

// Correct — parameterize all environment-specific values
const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';
```

Run: `k6 run --env BASE_URL=https://prod.example.com script.js`

### 4. Storing test data in a plain variable — multiplied per VU

Any variable declared at init context scope is **copied once per VU**. For a 50 MB JSON file with 200 VUs, that is 10 GB of RAM. Use `SharedArray` — loaded once, shared across all VUs as read-only.

```javascript
// Wrong — 50 MB × 200 VUs = 10 GB RAM
import { open } from 'k6';  // open() is init-context only
const users = JSON.parse(open('./data/users.json'));  // per-VU copy

// Correct — 50 MB total regardless of VU count
import { SharedArray } from 'k6/data';
const users = new SharedArray('users', () => JSON.parse(open('./data/users.json')));
```

Note: `open()` is an init-context-only function. Calling it inside `default()` throws a runtime error immediately — it does not cause OOM.

### 5. Imports inside functions — runtime error

```javascript
// Wrong — "import declarations may only appear at top level"
export default function() {
  import http from 'k6/http';  // ❌ runtime error
}

// Correct
import http from 'k6/http';
import { check, sleep } from 'k6';
export default function() { ... }
```

### 6. `ramping-vus` for a fixed RPS target — wrong workload model

`ramping-vus` controls concurrent users (closed model). Throughput varies with response time. For a fixed RPS goal, use `constant-arrival-rate`.

```javascript
// Wrong for "maintain 100 RPS" — actual RPS drops when server is slow
executor: 'ramping-vus', stages: [{ duration: '5m', target: 100 }]

// Correct — arrival rate is constant regardless of response time
executor: 'constant-arrival-rate',
rate: 100,
timeUnit: '1s',
duration: '5m',
preAllocatedVUs: 50,   // rule: ceil(rate × p95_seconds × 1.2)
maxVUs: 200,
```

### 7. Under-sized `preAllocatedVUs` — silent dropped iterations

`constant-arrival-rate` drops iterations when VUs run out. Monitor `dropped_iterations` in output.

```
preAllocatedVUs = ceil(rate × p95_response_time_in_seconds × 1.2)
Example: 100 RPS, p95 = 400ms → ceil(100 × 0.4 × 1.2) = 48 → use 50
```

### 8. `gracefulStop` shorter than p99 response time — inflated errors

k6 waits `gracefulStop` duration after the test ends for in-flight iterations to complete. If p99 is 2s and `gracefulStop` is the default 30s, you are fine. But if p99 is 45s (batch job), set `gracefulStop: '60s'` explicitly.

```javascript
scenarios: {
  load: {
    executor: 'constant-vus',
    vus: 100,
    duration: '5m',
    gracefulStop: '60s',   // set to at least 2× p99 response time
  }
}
```

### 9. One shared token for all VUs — all users share the same identity

`setup()` runs once before all VUs start. A token returned from `setup()` is shared by every VU — they all authenticate as the same user, producing unrealistic server-side behavior (single session, no per-user data isolation).

```javascript
// Wrong — 100 VUs, all acting as the same user
export function setup() {
  const res = http.post(`${BASE_URL}/auth/login`, JSON.stringify({ username: 'admin', password: 'secret' }), ...);
  return { token: res.json('access_token') };  // shared by all VUs
}

// Correct — each VU logs in with its own credentials from SharedArray
import { SharedArray } from 'k6/data';
const credentials = new SharedArray('creds', () => JSON.parse(open('./data/users.json')));

export default function() {
  const cred = credentials[(__VU - 1) % credentials.length];  // deterministic per VU
  const res = http.post(`${BASE_URL}/auth/login`,
    JSON.stringify({ username: cred.username, password: cred.password }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  const token = res.json('access_token');
  // use token for subsequent requests in this iteration
}
```

Use `setup()` only for shared, stateless initialization (e.g., seeding a test dataset via an admin API call).

### 10. Missing `Content-Type` on POST — server returns 415

```javascript
// Wrong — 415 Unsupported Media Type
http.post(`${BASE_URL}/api/users`, JSON.stringify({ name: 'Alice' }));

// Correct
http.post(`${BASE_URL}/api/users`, JSON.stringify({ name: 'Alice' }), {
  headers: { 'Content-Type': 'application/json' },
});
```

---

## The 5-Block Pattern — Reference

### Block 1: Options

```javascript
export const options = {
  scenarios: {
    load: {
      executor:         'ramping-vus',
      startVUs:         0,
      stages: [
        { duration: '2m', target: 50 },   // ramp up
        { duration: '5m', target: 50 },   // hold
        { duration: '2m', target: 0  },   // ramp down
      ],
      gracefulRampDown: '30s',
      gracefulStop:     '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed:   ['rate<0.01'],
    checks:            ['rate>0.99'],
  },
};
```

### Block 2: Data (SharedArray)

```javascript
import { SharedArray } from 'k6/data';

// JSON file
const users = new SharedArray('users', () => JSON.parse(open('./data/users.json')));

// CSV file (manual parse — k6 has no built-in CSV parser)
const csvUsers = new SharedArray('csv-users', () =>
  open('./data/users.csv')
    .split('\n')
    .slice(1)                                   // skip header row
    .filter(line => line.trim().length > 0)
    .map(line => {
      const [username, password] = line.split(',');
      return { username: username.trim(), password: password.trim() };
    })
);

// Access pattern — deterministic: each VU always uses the same record
const user = users[(__VU - 1) % users.length];

// Access pattern — random: any VU may pick any record
const user = users[Math.floor(Math.random() * users.length)];
```

### Block 3: Setup

```javascript
const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';

export function setup() {
  // Use only for stateless, shared initialization — NOT per-VU auth
  const res = http.post(`${BASE_URL}/api/seed`, null, {
    headers: { Authorization: `Bearer ${__ENV.ADMIN_TOKEN}` },
  });
  if (res.status !== 200) {
    fail(`Seed failed: ${res.status} — aborting test`);
  }
  return { seedId: res.json('id') };
}
```

### Block 4: Default Function (VU workload)

```javascript
import http         from 'k6/http';
import { group, check, sleep } from 'k6';

export default function(data) {
  const cred  = users[(__VU - 1) % users.length];
  const token = login(cred);   // per-VU auth

  group('Browse', () => {
    const res = http.get(`${BASE_URL}/api/products`, {
      headers: { Authorization: `Bearer ${token}` },
      tags:    { endpoint: 'products' },
    });
    check(res, {
      'products 200':       (r) => r.status === 200,
      'products not empty': (r) => r.json('#') > 0,
      'products < 500ms':   (r) => r.timings.duration < 500,
    });
    sleep(Math.random() * 2 + 1);
  });

  group('Checkout', () => {
    const res = http.post(`${BASE_URL}/api/orders`,
      JSON.stringify({ productId: data.seedId }),
      { headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        tags: { endpoint: 'checkout' } }
    );
    check(res, {
      'order created 201': (r) => r.status === 201,
      'order has id':      (r) => r.json('id') !== undefined,
    });
    sleep(1);
  });
}
```

### Block 5: Teardown

```javascript
export function teardown(data) {
  // Clean up seed data
  http.del(`${BASE_URL}/api/seed/${data.seedId}`, null, {
    headers: { Authorization: `Bearer ${__ENV.ADMIN_TOKEN}` },
  });
}
```

---

## Executor Selection Guide

**Closed model** — controls concurrent users. Use when connection count or session state matters.

| Executor | When to use | Required params |
|---|---|---|
| `constant-vus` | Steady-state, fixed concurrency | `vus`, `duration` |
| `ramping-vus` | Ramp up/down, standard load test | `stages`, `startVUs` |
| `per-vu-iterations` | Each VU runs exactly N iterations | `vus`, `iterations`, `maxDuration` |
| `shared-iterations` | Exactly N total iterations across all VUs | `vus`, `iterations`, `maxDuration` |

**Open model** — controls arrival rate. Use for public APIs where RPS is the goal.

| Executor | When to use | Required params |
|---|---|---|
| `constant-arrival-rate` | Fixed RPS target | `rate`, `timeUnit`, `preAllocatedVUs`, `maxVUs`, `duration` |
| `ramping-arrival-rate` | Escalating RPS (stress test) | `stages`, `timeUnit`, `preAllocatedVUs`, `maxVUs` |
| `externally-controlled` | Live VU adjustment via REST API | `vus`, `maxVUs`, `duration` |

**Default choice:** `ramping-vus`. Switch to `constant-arrival-rate` when the SLA is expressed in RPS.

---

## Thresholds Reference

```javascript
export const options = {
  thresholds: {
    // Global response time
    http_req_duration: ['p(95)<500', 'p(99)<1000'],

    // Per-tagged endpoint (tag set on the request)
    'http_req_duration{endpoint:checkout}': ['p(99)<2000'],

    // Error rate
    http_req_failed: ['rate<0.01'],

    // Check pass rate
    checks: ['rate>0.99'],

    // Throughput floor
    http_reqs: ['rate>50'],

    // Custom metric
    'checkout_duration_ms': ['p(95)<300'],
  },
};

// Abort test early if a threshold is breached:
export const options = {
  thresholds: {
    http_req_duration: [
      { threshold: 'p(95)<500', abortOnFail: true, delayAbortEval: '1m' },
      // delayAbortEval: wait 1m before evaluating — avoids aborting during ramp-up
    ],
  },
};
```

---

## Custom Metrics

```javascript
import { Counter, Gauge, Trend, Rate } from 'k6/metrics';

const checkoutMs   = new Trend('checkout_duration_ms');
const authErrors   = new Counter('auth_errors_total');
const cacheHits    = new Rate('cache_hit_rate');

export default function(data) {
  const start = Date.now();
  const body  = JSON.stringify({ productId: '123' });
  const res   = http.post(`${BASE_URL}/api/orders`, body, {
    headers: { 'Content-Type': 'application/json',
               Authorization: `Bearer ${data.token}` },
    tags: { endpoint: 'checkout' },
  });

  checkoutMs.add(Date.now() - start, { step: 'payment' });
  if (res.status === 401) authErrors.add(1);
  cacheHits.add(res.headers['X-Cache'] === 'HIT');
}
```

---

## Run Commands

```bash
# Basic run
k6 run script.js

# Override VUs and duration from CLI (useful for quick smoke test)
k6 run --vus 2 --duration 30s script.js

# Pass environment variables
k6 run --env BASE_URL=https://staging.example.com \
       --env USERNAME=perf_user \
       --env PASSWORD=secret \
       script.js

# Output to JSON for post-analysis
k6 run --out json=results.json script.js

# Output to InfluxDB + Grafana
k6 run --out influxdb=http://localhost:8086/k6 script.js

# TypeScript — compile first, then run the output
npx esbuild src/load.ts --bundle --outfile=dist/load.js --target=es2015
k6 run dist/load.js

# Grafana Cloud execution
k6 cloud run script.js
```

---

## References

- [Executors & Scenarios — Detailed Parameters](references/EXECUTORS.md)
- [Protocols — WebSocket & gRPC](references/PROTOCOLS.md)
- [Modular Design Patterns & TypeScript](references/DESIGN-PATTERNS.md)
- [k6 JavaScript API](https://grafana.com/docs/k6/latest/javascript-api/)
- [Thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/)
- [Metrics Reference](https://grafana.com/docs/k6/latest/using-k6/metrics/reference/)
