# Performance Baseline Measurements

**Recorded:** 2026-10-19  
**Platform / Environment:**
- **Browser:** Google Chrome 155.0.8059.80 (clean profile, extensions disabled)
- **Engine:** Flutter 3.41.9 Web (CanvasKit, dart2js profile mode)
- **Host OS:** Windows 10.0.26300.9711 (AMD Ryzen / x64)
- **DevTools CPU Throttling:** 4x CPU slowdown (via CDP `Emulation.setCPUThrottlingRate: 4`)
- **Backend:** FastAPI on `localhost:8000` (PostgreSQL live feed, 200 articles)

---

## 1. Scroll Controller A/B Comparison (Phase 0 Gate)

Wheel scroll simulation: 20 sequential downward ticks (`deltaY: 120px` at 75ms intervals), followed by 20 sequential upward ticks (`deltaY: -120px` at 75ms intervals) under 4x CPU throttling.

| Scenario | Controller Variant | Sampled Frames | p50 Frame (ms) | p90 Frame (ms) | p95 Frame (ms) | Max Frame (ms) | Jank Frames (>16.7ms) |
|---|---|---|---|---|---|---|---|
| **Home Page Scroll** | `SmoothScrollController` | 670 | 6.10 ms | 6.10 ms | 6.20 ms | 54.50 ms | 0.4% (3 frames) |
| **Home Page Scroll** | Plain `ScrollController` | 615 | 6.10 ms | 6.10 ms | 6.20 ms | 54.50 ms | 0.7% (4 frames) |
| **Discover Page Scroll** | `SmoothScrollController` | 816 | 6.10 ms | 6.10 ms | 6.20 ms | 6.50 ms | 0.0% (0 frames) |
| **Discover Page Scroll** | Plain `ScrollController` | 830 | 6.10 ms | 6.10 ms | 6.20 ms | 6.60 ms | 0.0% (0 frames) |

### Gate Decision
- **Gate Threshold:** $> 10\%$ difference in p95 frame time or percentage of jank frames.
- **Observed Difference:**
  - Home p95 difference: $0.0\%$ (6.20 ms vs 6.20 ms)
  - Discover p95 difference: $0.0\%$ (6.20 ms vs 6.20 ms)
  - Jank frame difference: $< 0.3\%$
- **Result:** The A/B trace demonstrates that `SmoothScrollController` does not degrade frame time compared to plain `ScrollController`. Following the project specification, **Item 5 (Scroll controller rewrite) is skipped**.

---

## 2. Interaction Baseline Metrics (HEAD)

Measured with 4x CPU slowdown in Chrome profile mode:

| Interaction | Description | Sampled Frames | p50 (ms) | p90 (ms) | p95 (ms) | Max (ms) | Jank % |
|---|---|---|---|---|---|---|---|
| **Card Hover Traversal** | Cursor sweep across a 4x6 grid (24 positions, 45ms per step) | 952 | 0.90 ms | 6.10 ms | 6.10 ms | 48.50 ms | 0.5% |
| **Streaming Chat Reply** | WAI Assistant token stream reception & UI rendering | 658 | 6.10 ms | 6.10 ms | 6.20 ms | 30.30 ms | 0.2% |

---

## 3. Discover Grid Virtualization Baseline

- **Current Implementation:** `SingleChildScrollView` wrapping `GridView.builder(shrinkWrap: true, physics: NeverScrollableScrollPhysics())`.
- **Eager Child Allocation:** When Discover loads with 40 articles in feed, `shrinkWrap: true` forces layout of all 40 `NewsGridCard` instances on initial build before any scroll event occurs.
- **Target with `CustomScrollView` + `SliverGrid`:** Eager build drops to visible viewport capacity only (~6–8 cards on 1080p desktop).
