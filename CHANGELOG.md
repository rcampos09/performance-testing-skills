# Changelog

All notable improvements to performance-testing-skills are documented here.
Entries are grouped by skill and ordered from newest to oldest.
Benchmark data comes from [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) iterations.

Format: `[version] — date | pass rate delta vs previous | what the eval found | what was fixed`

---

## k6-best-practices

### [1.3] — 2026-03-14
**Eval finding:** `clarifies_open_is_init_only` failed in both configs — skill had the information but no instruction to surface it when fixing OOM issues.
**Fix:** Added explicit instruction: when fixing any `open()` or OOM issue, always clarify both error variants (OOM from plain variable vs. runtime error from `open()` inside `default()`).

### [1.2] — 2026-03-07 _(prior to skill-creator benchmarking)_
**Changes:** Improved `open()` error distinction, import ordering, TS setup, and modular trigger.

### [1.1] — initial release

---

## gatling-best-practices

### [1.1] — 2026-03-14
**Benchmark (iteration 1):** 95.8% with skill vs. 59.8% without — **+36pp delta**. Biggest win on Kotlin+Gradle eval (7/7 vs. 1/7 baseline).
**Eval finding:** `uses_ramp_not_atOnce` assertion was too strict — penalized `rampConcurrentUsers()` even though it is valid and often more correct than `rampUsers()`.
**Fix:** Updated eval assertion to accept any ramp-based strategy (`rampUsers`, `rampConcurrentUsers`, `rampUsersPerSec`).

### [1.0] — initial release

---

## performance-testing-strategy

### [1.3] — 2026-03-14
**Benchmark (iteration 1):** 89.8% with skill vs. 70.6% without — **+19pp delta**.

Three findings addressed:

| Eval | Finding | Fix |
|---|---|---|
| `no-sla-defined` | Skill still recommended Stress for a 20-user internal tool — over-engineering | Added explicit row to quick-selection table: "Low-risk internal (≤50 users) → Smoke → Load only, stop here" |
| `resource-leak-investigation` | Skill output included JVM flags and Node.js API calls in metrics section | Added instruction in Step 4: express all metrics in generic terms — never include runtime flags, API calls, or platform-specific names |
| `full-production-readiness` | Eval assertion penalized skill for correctly placing Year-1 growth in Stress instead of Load | Reworded assertion to accept any test type that covers both launch and Year-1 horizons |

### [1.2] — 2026-03-07 _(prior to skill-creator benchmarking)_
**Changes:** Added test type tags to metadata.

### [1.0] — initial release

---

## Benchmark Baseline (as of 2026-03-14)

| Skill | Version | With skill | Without skill | Delta |
|---|---|---|---|---|
| `k6-best-practices` | v1.3 | 95% ± 11% | 79% ± 5% | +16pp |
| `gatling-best-practices` | v1.1 | 95.8% ± 8% | 59.8% ± 31% | +36pp |
| `performance-testing-strategy` | v1.3 | 89.8% ± 9.5% | 70.6% ± 8.7% | +19pp |
