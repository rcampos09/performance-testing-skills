# Custom Load Shapes — LoadTestShape

Use `LoadTestShape` when you need load profiles beyond a simple linear ramp:
multi-stage ramps, spike tests, wave patterns, or Black Friday simulations.

## How it works

Locust calls `tick()` approximately every second. Return a tuple `(user_count, spawn_rate)`
to set the desired state, or `None` to stop the test.

```python
from locust import LoadTestShape

class MyShape(LoadTestShape):
    def tick(self):
        run_time = self.get_run_time()
        # return (user_count, spawn_rate) or None to stop
```

---

## Pattern 1 — Staged ramp (most common)

Simulates a gradual ramp-up, sustained peak, and ramp-down:

```python
from locust import LoadTestShape

class StagesShape(LoadTestShape):
    """
    Stage  Duration  Users  Spawn rate
    1      0–60s     10     2/s   (warm-up)
    2      60–180s   50     5/s   (ramp to peak)
    3      180–480s  50     —     (hold peak for 5 min)
    4      480–540s  0      10/s  (ramp-down)
    """
    stages = [
        {"duration": 60,  "users": 10, "spawn_rate": 2},
        {"duration": 180, "users": 50, "spawn_rate": 5},
        {"duration": 480, "users": 50, "spawn_rate": 5},
        {"duration": 540, "users": 0,  "spawn_rate": 10},
    ]

    def tick(self):
        run_time = self.get_run_time()
        for stage in self.stages:
            if run_time < stage["duration"]:
                return stage["users"], stage["spawn_rate"]
        return None  # stop test
```

---

## Pattern 2 — Spike test

Sudden traffic burst — simulates flash sale or viral event:

```python
class SpikeShape(LoadTestShape):
    """
    0–30s:   10 users  (baseline)
    30–60s:  200 users (spike — 20× burst)
    60–90s:  10 users  (recovery)
    90–120s: end
    """
    stages = [
        {"duration": 30,  "users": 10,  "spawn_rate": 2},
        {"duration": 60,  "users": 200, "spawn_rate": 100},  # fast spike
        {"duration": 90,  "users": 10,  "spawn_rate": 100},  # fast recovery
        {"duration": 120, "users": 0,   "spawn_rate": 10},
    ]

    def tick(self):
        run_time = self.get_run_time()
        for stage in self.stages:
            if run_time < stage["duration"]:
                return stage["users"], stage["spawn_rate"]
        return None
```

---

## Pattern 3 — Double wave (two peak periods)

Simulates morning and afternoon traffic peaks:

```python
class DoubleWaveShape(LoadTestShape):
    stages = [
        {"duration": 60,  "users": 5,  "spawn_rate": 1},   # quiet
        {"duration": 120, "users": 50, "spawn_rate": 10},  # morning peak
        {"duration": 240, "users": 10, "spawn_rate": 10},  # midday dip
        {"duration": 300, "users": 50, "spawn_rate": 10},  # afternoon peak
        {"duration": 360, "users": 0,  "spawn_rate": 10},  # end of day
    ]

    def tick(self):
        run_time = self.get_run_time()
        for stage in self.stages:
            if run_time < stage["duration"]:
                return stage["users"], stage["spawn_rate"]
        return None
```

---

## Key rules for LoadTestShape

- **One shape per locustfile** — Locust ignores any second `LoadTestShape` subclass.
- **spawn_rate during ramp-down** should be high (e.g., 50–100) to reduce users quickly.
- **Do not set `-u` or `-r` flags** when using a shape — the shape controls everything.
- **`get_run_time()`** returns elapsed seconds since test start — use it to advance stages.
- The shape class must be in the **same locustfile** or imported into it.

---

## Run command for shaped tests

```bash
# Shape controls users/rate — do NOT pass -u or -r
locust -f locustfile.py --headless -t 10m \
  --host https://api.example.com \
  --html report.html
```
