# k6 Executors — Detailed Reference

Loaded on demand when the user needs detailed executor parameters, stage configuration, workload model selection, or multi-scenario orchestration.

---

## The Two Workload Models

Understanding the model is required before selecting an executor.

### Closed Model (VU-Based)
A fixed number of VUs iterate continuously. A new iteration starts only after the previous one completes. If the server is slow, throughput drops because VUs are blocked waiting for responses.

- **Matches:** Systems where connection count matters — connection pools, session-based systems, backend workers.
- **Parameter you control:** Number of concurrent VUs.
- **Executors:** `constant-vus`, `ramping-vus`, `per-vu-iterations`, `shared-iterations`

### Open Model (Arrival-Rate)
New iterations are launched at a fixed rate regardless of how many are currently active. If the server is slow, k6 spawns additional VUs to maintain the rate. If it cannot, iterations are **dropped** (recorded in `dropped_iterations` metric).

- **Matches:** Real-world web traffic where users arrive independently of server state. Public APIs, REST services, anything measured in RPS.
- **Parameter you control:** Requests (iterations) per second.
- **Executors:** `constant-arrival-rate`, `ramping-arrival-rate`

---

## Executor: `constant-vus`

Runs a fixed number of VUs for a fixed duration.

```javascript
scenarios: {
  steady_load: {
    executor: 'constant-vus',
    vus: 50,
    duration: '10m',
    gracefulStop: '30s',
  }
}
```

| Option | Type | Default | Description |
|---|---|---|---|
| `vus` | integer | 1 | Number of concurrent VUs |
| `duration` | string | required | Test duration (e.g., `'5m'`, `'30s'`) |
| `gracefulStop` | string | `'30s'` | Time to wait for in-flight iterations after duration ends |

**Use when:** You want a steady-state load test and your SLA is measured in response time, not throughput.

---

## Executor: `ramping-vus`

Gradually increases or decreases VU count through defined stages. Most commonly used executor for standard load tests.

```javascript
scenarios: {
  ramp_load: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '2m', target: 50  },  // ramp up to 50
      { duration: '5m', target: 50  },  // hold at 50
      { duration: '3m', target: 100 },  // ramp up to 100
      { duration: '5m', target: 100 },  // hold at 100
      { duration: '2m', target: 0   },  // ramp down
    ],
    gracefulRampDown: '30s',
    gracefulStop: '30s',
  }
}
```

| Option | Type | Default | Description |
|---|---|---|---|
| `startVUs` | integer | 1 | VUs at test start |
| `stages` | array | required | Array of `{ duration, target }` objects |
| `gracefulRampDown` | string | `'30s'` | Time to finish in-flight iterations during ramp-down |
| `gracefulStop` | string | `'30s'` | Time after test ends to finish iterations |

**Use when:** Standard ramp-up + steady-state + ramp-down load test. Default choice for most tests.

---

## Executor: `constant-arrival-rate`

Starts iterations at a fixed rate. k6 spawns VUs as needed to maintain the rate. If `maxVUs` is hit and the rate cannot be maintained, iterations are dropped.

```javascript
scenarios: {
  fixed_rps: {
    executor: 'constant-arrival-rate',
    rate: 100,           // 100 iterations per timeUnit
    timeUnit: '1s',      // per second = 100 RPS
    duration: '10m',
    preAllocatedVUs: 50, // VUs ready before test starts
    maxVUs: 200,         // hard ceiling on VU count
    gracefulStop: '30s',
  }
}
```

| Option | Type | Default | Description |
|---|---|---|---|
| `rate` | integer | required | Number of iterations to start per `timeUnit` |
| `timeUnit` | string | `'1s'` | Rate window (e.g., `'1s'` = RPS, `'1m'` = RPM) |
| `duration` | string | required | Test duration |
| `preAllocatedVUs` | integer | required | VUs allocated before test — set to `rate × p95_seconds × 1.2` |
| `maxVUs` | integer | 0 (no limit) | Hard ceiling — set to avoid resource exhaustion |
| `gracefulStop` | string | `'30s'` | Cool-down after duration |

**preAllocatedVUs formula:**
```
preAllocatedVUs = ceil(rate × (p95_response_time_seconds) × 1.2)
Example: 100 RPS, p95 = 400ms → ceil(100 × 0.4 × 1.2) = 48 → use 50
```

**Watch for `dropped_iterations`:** If this counter is non-zero, increase `preAllocatedVUs` or reduce `rate`.

---

## Executor: `ramping-arrival-rate`

Like `ramping-vus` but controls arrival rate instead of VU count. Use for stress tests that escalate RPS progressively.

```javascript
scenarios: {
  stress_test: {
    executor: 'ramping-arrival-rate',
    startRate: 10,
    timeUnit: '1s',
    stages: [
      { duration: '2m', target: 50  },   // ramp to 50 RPS
      { duration: '5m', target: 50  },   // hold at 50 RPS
      { duration: '5m', target: 200 },   // stress to 200 RPS
      { duration: '2m', target: 0   },   // ramp down
    ],
    preAllocatedVUs: 50,
    maxVUs: 500,
  }
}
```

| Option | Type | Default | Description |
|---|---|---|---|
| `startRate` | integer | 0 | Iterations per `timeUnit` at start |
| `timeUnit` | string | `'1s'` | Rate window |
| `stages` | array | required | Array of `{ duration, target }` — target is iterations/timeUnit |
| `preAllocatedVUs` | integer | required | Starting VU pool |
| `maxVUs` | integer | 0 | Hard ceiling |

---

## Executor: `per-vu-iterations`

Each VU runs the default function exactly `iterations` times. Total iterations = `vus × iterations`.

```javascript
scenarios: {
  fixed_iterations: {
    executor: 'per-vu-iterations',
    vus: 10,
    iterations: 100,    // each VU runs 100 times → 1000 total
    maxDuration: '5m',  // safety timeout
    gracefulStop: '30s',
  }
}
```

**Use when:** Each user must execute a fixed number of actions (e.g., user registration test where each VU registers exactly once).

---

## Executor: `shared-iterations`

All VUs share a pool of iterations. Faster VUs complete more. Stops when the iteration pool is exhausted.

```javascript
scenarios: {
  shared_work: {
    executor: 'shared-iterations',
    vus: 10,
    iterations: 500,    // 500 total, distributed across 10 VUs
    maxDuration: '5m',
    gracefulStop: '30s',
  }
}
```

**Use when:** You want exactly N total test executions regardless of how they are distributed.

---

## Executor: `externally-controlled`

Allows VU count to be adjusted live via the k6 REST API during execution. Useful for long soak tests and manual load injection.

```javascript
scenarios: {
  soak: {
    executor: 'externally-controlled',
    vus: 10,
    maxVUs: 100,
    duration: '8h',
  }
}
```

Control via REST API:
```bash
# Increase VUs during execution
curl -X PATCH http://localhost:6565/v1/status \
     -H 'Content-Type: application/json' \
     -d '{"data":{"attributes":{"vus":50},"type":"status"}}'
```

---

## Multi-Scenario Configuration

Scenarios run in parallel by default. Use `startTime` to sequence them.

```javascript
export const options = {
  scenarios: {
    smoke: {
      executor: 'constant-vus',
      vus: 1,
      duration: '1m',
      tags: { type: 'smoke' },
    },
    load: {
      executor: 'ramping-vus',
      startTime: '1m',     // starts after smoke completes
      startVUs: 0,
      stages: [
        { duration: '5m', target: 50 },
        { duration: '10m', target: 50 },
        { duration: '5m', target: 0 },
      ],
      tags: { type: 'load' },
    },
  },
  thresholds: {
    // Apply threshold only to load scenario
    'http_req_duration{type:load}': ['p(95)<500'],
  },
};
```

---

## Scenario-Scoped Options

Each scenario can override global options:

```javascript
scenarios: {
  api_test: {
    executor: 'constant-vus',
    vus: 50,
    duration: '5m',
    env:  { API_KEY: 'test-key' },     // scenario-level env vars
    tags: { scenario: 'api' },         // applied to all metrics in this scenario
    gracefulStop: '30s',
    exec: 'apiFlow',                   // call a named export instead of default
  }
}

export function apiFlow() {
  // this runs for the api_test scenario instead of default()
}
```

---

## Test Lifecycle with Scenarios

```
init context (once, before any VU starts)
  → setup() (once, before VUs start)
    → VU iterations run (default function or named exec)
  → teardown() (once, after all VUs complete)
```

**setup() return value is passed to both `default(data)` and `teardown(data)`.**

If `setup()` fails, k6 aborts. Use `fail()` explicitly for critical pre-conditions:

```javascript
export function setup() {
  const res = http.post(`${BASE_URL}/auth/login`, ...);
  if (res.status !== 200) {
    fail(`Setup failed — cannot proceed without auth token: ${res.status}`);
  }
  return { token: res.json('access_token') };
}
```
