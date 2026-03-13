# k6 Design Patterns — Modular Project Structure

Loaded on demand when the user asks about folder structure, project architecture, how to share data or configuration, or how to scale beyond a single script file.

---

## Modular 4-Layer Architecture

For projects with multiple test scenarios, split concerns into layers:

```
k6-tests/
├── config/
│   └── options.js          ← shared executor/threshold definitions
├── data/
│   ├── users.json          ← test data files
│   └── products.csv
├── lib/
│   ├── auth.js             ← authentication helpers
│   ├── http.js             ← request wrappers with default headers/tags
│   └── checks.js           ← reusable check bundles
├── scenarios/
│   ├── smoke.js            ← smoke test (2–5 VUs, 2–5 min)
│   ├── load.js             ← standard load test
│   └── stress.js           ← stress / breakpoint test
└── package.json            ← for TypeScript or npm dependencies
```

---

## Layer 1 — Config Module

```javascript
// config/options.js
export const smokeOptions = {
  scenarios: {
    smoke: {
      executor: 'constant-vus',
      vus: 2,
      duration: '2m',
      gracefulStop: '10s',
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
  },
};

export const loadOptions = {
  scenarios: {
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50  },
        { duration: '8m', target: 50  },
        { duration: '2m', target: 0   },
      ],
      gracefulRampDown: '30s',
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    checks:            ['rate>0.99'],
  },
};
```

---

## Layer 2 — Auth Helper

```javascript
// lib/auth.js
import http from 'k6/http';
import { fail } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';

export function login(username, password) {
  const res = http.post(`${BASE_URL}/auth/login`,
    JSON.stringify({ username, password }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  if (res.status !== 200) {
    fail(`Login failed for ${username}: status ${res.status}`);
  }
  return res.json('access_token');
}

export function authHeaders(token) {
  return {
    'Authorization':  `Bearer ${token}`,
    'Content-Type':   'application/json',
    'Accept':         'application/json',
  };
}
```

---

## Layer 3 — Shared Data with SharedArray

```javascript
// data/loader.js
import { SharedArray } from 'k6/data';

// SharedArray: loaded once in init context, shared across all VUs — no per-VU copy
export const users = new SharedArray('users', () =>
  JSON.parse(open('../data/users.json'))
);

export const products = new SharedArray('products', () =>
  JSON.parse(open('../data/products.json'))
);

// Deterministic selection — each VU always picks the same user (avoids conflicts)
export function pickUser(vuId) {
  return users[(vuId - 1) % users.length];  // vuId is 1-based
}

// Random selection — multiple VUs may pick the same record
export function randomUser() {
  return users[Math.floor(Math.random() * users.length)];
}
```

**When to use deterministic vs random:**
- **Deterministic** (`vuId % length`): When each VU must operate on a distinct record (e.g., each user logs into their own account).
- **Random**: When any record can be reused (e.g., reading product catalog data).

---

## Layer 4 — Scenario Script

```javascript
// scenarios/load.js
import http          from 'k6/http';
import { group, check, sleep } from 'k6';
import { randomIntBetween }    from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { loadOptions }         from '../config/options.js';
import { login, authHeaders }  from '../lib/auth.js';
import { pickUser }            from '../data/loader.js';

export const options = loadOptions;

const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com';

export function setup() {
  const adminToken = login(__ENV.ADMIN_USER, __ENV.ADMIN_PASSWORD);
  return { adminToken };
}

export default function(data) {
  const user = pickUser(__VU);  // deterministic per VU

  group('Login', () => {
    const token = login(user.username, user.password);
    __ITER === 0
      ? console.log(`VU ${__VU} logged in as ${user.username}`)
      : null;

    group('Browse Catalog', () => {
      const res = http.get(`${BASE_URL}/api/products`, {
        headers: authHeaders(token),
        tags:    { flow: 'browse', endpoint: 'products' },
      });
      check(res, {
        'products 200':       (r) => r.status === 200,
        'has items':          (r) => r.json('#') > 0,
        'products < 500ms':   (r) => r.timings.duration < 500,
      });
      sleep(randomIntBetween(1, 3));
    });

    group('View Product', () => {
      const products = http.get(`${BASE_URL}/api/products`, {
        headers: authHeaders(token),
      }).json();
      const productId = products[0].id;

      const res = http.get(`${BASE_URL}/api/products/${productId}`, {
        headers: authHeaders(token),
        tags:    { flow: 'browse', endpoint: 'product-detail' },
      });
      check(res, {
        'product detail 200': (r) => r.status === 200,
        'product has price':  (r) => r.json('price') > 0,
      });
      sleep(randomIntBetween(2, 5));
    });
  });
}

export function teardown(data) {
  console.log('Load test complete');
}
```

Run:
```bash
k6 run \
  --env BASE_URL=https://staging.example.com \
  --env ADMIN_USER=admin@example.com \
  --env ADMIN_PASSWORD=secret \
  scenarios/load.js
```

---

## TypeScript Setup

### package.json

```json
{
  "name": "k6-tests",
  "scripts": {
    "build":      "esbuild src/**/*.ts --bundle --outdir=dist --platform=node --format=esm",
    "test:smoke": "k6 run dist/smoke.js",
    "test:load":  "k6 run dist/load.js"
  },
  "devDependencies": {
    "@types/k6":    "^0.54.0",
    "esbuild":      "^0.20.0",
    "typescript":   "^5.0.0"
  }
}
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target":           "ES2017",
    "module":           "ES2020",
    "moduleResolution": "node",
    "lib":              ["ES2017"],
    "strict":           true,
    "noEmit":           true,
    "types":            ["k6"]
  },
  "include": ["src/**/*.ts"]
}
```

### TypeScript Example

```typescript
// src/load.ts
import http                    from 'k6/http';
import { Options }             from 'k6/options';
import { group, check, sleep } from 'k6';

interface SetupData {
  token: string;
}

export const options: Options = {
  scenarios: {
    load: {
      executor:    'ramping-vus',
      startVUs:    0,
      stages:      [
        { duration: '2m', target: 50 },
        { duration: '5m', target: 50 },
        { duration: '2m', target: 0  },
      ],
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed:   ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL ?? 'https://staging.example.com';

export function setup(): SetupData {
  const res = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({ username: __ENV.USERNAME, password: __ENV.PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  return { token: res.json('access_token') as string };
}

export default function(data: SetupData): void {
  group('API', () => {
    const res = http.get(`${BASE_URL}/api/users`, {
      headers: { Authorization: `Bearer ${data.token}` },
    });
    check(res, { 'status 200': (r) => r.status === 200 });
    sleep(1);
  });
}
```

Build and run:
```bash
npm run build
k6 run --env BASE_URL=https://staging.example.com dist/load.js
```

---

## Global Variables Reference

k6 exposes these without any import:

| Variable | Type | Description |
|---|---|---|
| `__VU` | number | VU ID (1-based) — unique per VU within the test |
| `__ITER` | number | Iteration count for current VU (0-based) |
| `__ENV` | object | Environment variables passed via `--env` |
| `__ENV.K6_CLOUD_RUN_ID` | string | Grafana Cloud run ID (cloud execution only) |

Usage:
```javascript
export default function() {
  console.log(`VU ${__VU}, iteration ${__ITER}`);
  const userIndex = (__VU - 1) % users.length;  // deterministic selection
}
```

---

## Reusable Check Bundles

Define standard check sets once and reuse across scenarios:

```javascript
// lib/checks.js
export const statusChecks = (endpoint) => ({
  [`${endpoint}: status 200`]:      (r) => r.status === 200,
  [`${endpoint}: not empty body`]:  (r) => r.body.length > 0,
  [`${endpoint}: < 500ms`]:         (r) => r.timings.duration < 500,
});

export const createChecks = (endpoint) => ({
  [`${endpoint}: status 201`]:      (r) => r.status === 201,
  [`${endpoint}: has id`]:          (r) => r.json('id') !== undefined,
});

// Usage in scenario:
import { check } from 'k6';
import { statusChecks } from '../lib/checks.js';

check(res, statusChecks('GET /api/products'));
```

---

## Metrics Cardinality — Avoid Tag Explosion

Every unique combination of tag values creates a new metric series. Too many unique values causes memory issues and unusable dashboards.

```javascript
// BAD — unique URL per request creates unbounded cardinality
http.get(`${BASE_URL}/api/users/${userId}`, {
  tags: { url: `${BASE_URL}/api/users/${userId}` },  // ❌ 1000 users = 1000 series
});

// GOOD — normalize dynamic segments in tag values
http.get(`${BASE_URL}/api/users/${userId}`, {
  tags: { endpoint: 'GET /api/users/:id' },  // ✓ single series for all users
});
```

**Rule:** Tag values should be a small, finite set (< 20 values per tag key). Never use user IDs, timestamps, or generated values as tag values.
