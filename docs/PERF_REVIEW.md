# Dead Corps — Performance Review (ground-up)

**Date:** 2026-08-02 · **Branch:** `v2-poc` @ v0.48.0 · **Author:** Claude, measured with Ben's hardware (GTX 1070 machine)
**Supersedes:** the "Performance & Scaling (deep dive)" + Stages B/C/E of the Master Roadmap in `CODEBASE_REVIEW.md` (June, pre-pivot). That review's predictions held up — its Fix A *is* today's spatial hash — but its framing (v1 systems, 3D migration) is dead. Status of its prescriptions: §3 below.

**Test bed:** `scenes/Levels/level_testing.tscn` — 44 zombies / 447 humans (~491 units), quiet boot (no fear contact until triggered).
**Method:** the perf sampler (`perf_sampler.gd` — one ⏱️ PERF line per 5s to `godot.log`) + `GameConfig.perf_auto_frenzy_delay` (timed map-wide release, no keyboard needed) + the editor profiler for per-function attribution. Full baseline curves archived from the 2026-08-02 runs.

---

## 1. Measured baseline (v0.48.0)

| Phase | Frame avg | Physics step (incl. script) | Notes |
|---|---|---|---|
| Idle map, 491 units | 16.7 ms (vsync-locked) | **13–16 ms** | zero ferals, zero fleeing |
| Full frenzy (44 ferals, sieges, routs) | 17–24 ms | 14–27 ms | worst frame ~50 ms |
| Post-frenzy (64 calm zombies, 365 humans) | 16.7–17 ms | 15–16 ms | risers grew the horde |

Node count: **8,552** (~17 per unit). Determinism: **PASS** — two headless runs of the identical scenario produced 119 byte-identical sim-event lines at wildly different render rates.

### The headline

**The idle map alone costs ~14 ms of the 16.7 ms budget.** The v0.47–48 optimisation rounds (spatial hash, cadences, sampling) successfully flattened the *frenzy* — it now adds only ~3–7 ms on top — but the floor under it is ~460 mostly-stationary units each paying a fixed per-tick cost (~30 µs/unit: dispatcher dispatch, boid query, fill/fear cadence checks, `move_and_slide`, nav bookkeeping). At 2–5× units the floor alone blows the budget before a single feral exists. **Further ad-hoc throttling of frenzy systems cannot fix this — the next work must attack the fixed per-unit cost.**

Profiler attribution at this scale (from the 08-01/08-02 captures): Human dispatch + fill/fear ≈ half the script time; boid + registry queries ≈ a quarter; zombie dispatch + nav ≈ the rest. Engine-side physics is real but secondary while script dominates.

---

## 2. Cost model

Per physics tick, every unit pays:
1. `_physics_process` dispatch (GDScript call overhead × 491, unconditionally)
2. BOID separation (query at 30–45 px; 1-in-3 for standing humans) — cheap since the grid, but never free
3. `move_and_slide` — called even when velocity is zero (**unaudited waste — see F5**)
4. Component cadence checks (fear/fill timers tick even when nothing is near)
5. Per-unit canvas items: `Label` (class letter / group number), `_draw` hooks

Zombies additionally pay FeralBrain/Shamble dispatch and a `NavigationAgent2D`. None of this scales with *activity* — it scales with *existence*. That is the wrong shape for a game whose premise is "more zombies than anyone else would simulate."

---

## 3. Status vs the June review's prescriptions

| June fix | Status |
|---|---|
| A. Spatial index + `neighbours_within` | ✅ v0.48.0 (64px grid, hybrid fallback, sample cap) |
| B. AI tick decoupling / LOD | 🟡 partial — fear/fill/repulsion/alignment cadences exist; **no idle/proximity LOD** (→ F2) |
| C. Event-driven UI / batched overlays | ❌ (health bars died with v1, but per-unit Labels + `_draw` remain) (→ F4) |
| D. Shooting-scan gate + nav repath throttle | ✅ v0.48.0 (0.2s fill scan; 24px repath threshold) |
| D-half: flow-field / shared paths | ❌ (→ F3) |
| E. Hot-path prints gated | ✅ (`debug_logs`) |
| Tier 2: MultiMesh bodies, node pooling, pooled audio | ❌ — audio players don't exist in v2 units; the rest → F4/F1 |
| Stage B: benchmark baseline | ✅ this document + the sampler harness |

---

## 4. Fundamental options (ranked by win ÷ disruption)

**F2 — Idle LOD. ✅ BUILT 2026-08-02 (the "cold human" model).** A defending or
safely-sheltered-at-rest human with no zombie inside `lod_wake_radius` (700px)
goes COLD: its entire tick — fear, fill, boid, clamp, facing — is skipped; it
only decrements a wake timer and re-checks for zombies every 0.5s (staggered;
the query early-stops at the first zombie via `max_results = 1`). The wake
margin (700 vs 550 max awareness) exceeds the maximum ground a zombie covers in
one check interval, so a cold human always wakes before anything can enter its
perception — cold is unobservable in play. Patrollers, mid-fear-beat, fleeing,
breached-building occupants and mid-walk entrants are never cold.

**Measured result (level_testing, 44z/447h):** idle physics step 13.6–14.1 ms →
**6–9 ms**; the whole 95s frenzy run holds a locked 16.7 ms vsync average
(baseline: 17–24 ms avgs, 30–50 ms worsts). Determinism re-verified: two runs,
full event streams identical. Frenzy-contact spike (~26 ms for one window as
hundreds wake + fight) unchanged — that's genuine work.

**F5 — WITHDRAWN (premise was wrong).** The doc claimed stationary units waste
a `move_and_slide` per tick; a full read of `unit.gd` shows movement only runs
`if has_target` — idle units never call it. What idle units actually paid was
the brain/bookkeeping tick, which F2's cold return now removes wholesale.

**F4 — Batched presentation (FOLD INTO PHASE 5).** Per-unit `Label` Controls and `_draw` hooks → the `vision_renderer` rewrite that Phase 5 already owes. One canvas layer drawing rings/lines/letters for everyone is both the readability plan *and* the perf fix — do them as one piece of work, not two.

**F1 — Components: child Nodes → RefCounted.** Sheds ~2,000 tree nodes and per-node overhead while keeping the dispatcher-shell pattern intact (components already have no `_physics_process`; the shell ticks them). **Blocked on a deliberate ARCHITECTURE_GUIDELINES amendment — Ben's ruling required.** Do opportunistically after F2/F5 show what's left.

**F3 — Flow-field pursuit (THE 1000-ZOMBIE ENABLER — PARKED).** Replace per-feral `NavigationAgent2D` pursuit with shared direction fields toward target clusters; per-agent path cost becomes shared cost that barely grows with horde size. High effort, touches chase feel (validation Q1/Q3 territory). Park until the PoC validates and counts genuinely exceed what F2+F5 buy. Revisit trigger: feral count > ~300 sustained, or nav > 25% of a frenzy tick in the sampler+profiler.

**Not recommended:** GDScript → C#/GDExtension rewrites (disproportionate for a solo portfolio project while F2/F4/F5 remain unplayed); further frenzy-math cadences (measured: no longer the problem).

## 5. Recommended sequence

1. ~~F2 + F5~~ ✅ **DONE 2026-08-02** — idle floor 14 → 6–9 ms; locked 60fps through the full standard load test.
2. **Phase 5 readability = F4** — one workstream, two goals. NOW THE NEXT PERF STEP.
3. **F1** after Ben rules on the guidelines amendment.
4. Re-baseline at 2–5× units on `level_testing`; only then decide if F3 leaves the car park.

## 6. The harness (how to rerun all of this)

- Sampler: always on (`GameConfig.perf_log`); read `%APPDATA%\Godot\app_userdata\Dead Corps Prototype\logs\godot.log`.
- Load test: set `GameConfig.perf_auto_frenzy_delay = 20.0` (+ `debug_logs = true` for the event trace), boot `level_testing`, ~100s, revert. Two runs + a diff of the sim-event lines = the §10 check. Claude runs this end-to-end unattended via the Godot MCP.
- **Flush caveat:** Godot's file logger buffers — a log copied right after a kill holds only a flushed prefix. For the determinism diff, compare the MCP console streams (complete), or let the run idle ~30s before stopping so the file catches up.
