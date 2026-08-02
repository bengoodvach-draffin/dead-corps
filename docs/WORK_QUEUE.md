# Dead Corps — v2-poc Work Queue

**Updated:** 2026-07-30 · **Branch:** `v2-poc` @ v0.47.0 *(since 07-12: enterable buildings slice 1 + terrain kit v0.44.0 — see `V2_ENTERABLE_BUILDINGS_SPEC.md` §16; Tier 4 batch done; manager splits + the Mark v0.45.0; the breach + flee batch v0.45.3–v0.47.0 — see Tier 3.5)*
**What this is:** the single **prioritized** to-do for the branch — it merges the **2026-07-02 architecture review** bugs with the **2026-07-12 friends'-playtest** feature requests into one tier order. Fixes that are small or impactful come first; larger features and the phase-gated work follow.

**Companion docs (detail lives there, not here):**
- `docs/V2_REVIEW_2026-07-02.md` — every review finding at file:line, incl. §K commit-log validation.
- `docs/HANDOVER_2026-07-02.md` — the review's own batch queue + Ben's rulings + the doc-sync batch.
- `docs/V2_POC_BUILD_PLAN.md` — the Phase 0–7 structure (Tiers 5–7 below are its Phases 5–7).
- `docs/V2_DIRECTION_SPEC.md` — authoritative core-loop design.

**Working rules unchanged:** propose-before-implementing per step, one feature at a time, parse gate (`tools/check.ps1`) after every `.gd` edit, print test cases, **Ben commits manually**. Review line numbers drift — re-grep before editing.

---

## Locked decisions (do not re-litigate)
- **Risers stay CALM** (matches spec §3.6) — fresh zombies are a controllable resource (stage the next combo / cut off runners).
- **Release = pin to the nearest human at the click** (a direct hit is the degenerate case); needs an aim/magnetism radius.
- **Stop-to-fire** is the chosen A2 fix.
- **Tiered combo base is correct as built**; the spec syncs to the code.
- **Release is for prey, orders are for terrain** (2026-07-30). RMB on a human or occupied building = a release (feral, committed); RMB on a door or bare ground = a calm order. Breaking a door is terrain clearing, not an attack — release-on-door was deleted.
- **Flushed humans hiding DEEPER into an interior shelter is intended, not a bug** (2026-07-30). Nesting depth is a level-design lever, not an engine rule. Removal proposed twice, declined twice.
- **`flee_exit_threat_bias` stays 6.0** — it governs the route (no sprinting through the horde); `exit_block_radius` governs the door. Not redundant.
- **CUT for now (Ben deprioritized):** zombies getting stuck on geometry — the corner-stuck investigation *and* the zombie-pursuit-nav asymmetry. Not queued.

## Blocked on Ben
- **The Mark design workshop** — the Mark is built (v0.45.0, attention field, behind C) but first play found it confusing; validation Q6 can't be judged until the verb is re-designed.
- **Phase 6 level questions** — scale/roster/building-density/difficulty for the §12 PoC level.
- ✅ **Deter-knob test (Point 1)** — effectively answered 2026-07-30: Ben settled on `flee_repel_strength` 3.0 in play and it is now the default (docks rebaseline). Steering-only stands; body collision still not needed.
- **Deter-knob remainder:** `flee_repel_radius` (180→220) untested if herding ever feels short-reach. *(Corpse-commands A/B/C — resolved; feature shipped 2026-07-12.)*

---

## Tier 1 — Ruled bug fixes (do before the next playtest; they protect the validation verdict)
Small, ruled, high-impact. Suggested PATCH bumps (or one v0.43.1 batch — Ben's call).

1. **A1 — feral pursuit-claim leak (HIGHEST).** ✅ DONE 2026-07-12 (landed in the same commit as this queue; entry never got its checkmark). `zombie.gd die()` aborts the pounce AND calls `_feral.clear()` before the corpse-linger await, so a feral shot mid-chase releases both claims and its straggler returns to the peel-off pool.
2. **A2 — stop-to-fire.** ✅ CODE LANDED 2026-07-12 (UNTESTED — pre-emptive). A *moving* armed defender wipes its aim rotation each frame → can't fire >~21° off its travel direction. Fix: `human.gd` dispatcher halts an armed defender while `_fill_front.is_reached()` so aim owns facing; resumes on fire. **Only manifests for a moving armed defender — no patrols exist yet, so it can't occur today; test deferred until patrols return** (test steps in the `phase3-test-criteria` memory). Dispatcher `match`-restructure deferred to Tier 5 (Phase 5).
3. **B3 — cowerers block firing lanes.** ✅ DONE 2026-07-12. `start_cowering()` now zeroes `collision_layer` (mirrors `die()`) so a cowerer no longer screens armed defenders' shots (spec §4.1).

## Tier 2 — Small feature + the immersion fix
4. **Release magnetism (#1).** ✅ DONE 2026-07-12. New `release_aim_radius` knob (default 100px, in GameConfig + LevelConfig); `_human_at` uses it so RMB within that radius of a human = a release pinned to the nearest one (pin-and-aim: seeds from the human's position); outside it = a calm move order. **Bonus:** every LevelConfig `@export` now carries a `##` doc-comment → shows as an inspector rollover tooltip.
5. **Point 1 — humans phase through calm zombies.** ⏸️ PARKED 2026-07-12 — Ben couldn't replicate the phase-through in play, so no action for now. If it resurfaces: tune the deter knob (`flee_repel_strength`/`radius`); if steering-only isn't enough, add body collision (units currently have *no* unit-unit collision, BOID only). Optional **guard mode** later for strong intentional walls.

## Tier 3 — Bigger playtest features
6. **Corpse commands (3.2).** ✅ DONE 2026-07-12 (6a + 6b). Order a body before it rises. Model: the queued order is a stored **click**, re-resolved at rise via the live release-or-move rule (`release_aim_radius`) — human near → rises feral & attacks; else → rises calm & moves. A selected corpse's risen zombie auto-selects (if calm). 6b: assigning a control group to a corpse tags the entry so the risen zombie joins that group on rise.
8. **Zombie move-queue / shift-click waypoints.** ✅ DONE (confirmed in code 2026-07-27): shift+RMB chains move orders (`Unit.queue_move`, capped queue, fixed-coord route viz line); shift+RMB on a human = an attack terminal deferred to the end of the route. Queued moves only — no loops/branches/patrol-editing, per the cap.
7. **Select-all-non-feral hotkey (3.1).** ✅ DONE 2026-07-26 as TWO keys (Ben's design): **Q** = select all calm zombies, **E** = select all calm zombies on screen — the riser-roundup answer. Corpses/finishers remain box-select-only.

## Tier 3.5 — Breach + flee batch ✅ DONE 2026-07-29/30 (v0.45.3 → v0.47.0)
Unplanned; came out of playtesting the terrain kit at docks scale. All parse-gated + boot-checked.
- ✅ **v0.45.3 — selection retention.** An ordered gate siege used to clear the selection at the click, forcing a re-box at every breach. Selection is kept; a new per-frame `_prune_selection` drops members that stop being selection-worthy (also fixes contagion-ignited zombies lingering as ghost members).
- ✅ **v0.46.0 — calm door-breaching + the door-click grammar.** New `calm_breach.gd` (`CalmBreach` component) + `door_breach.gd` (`DoorBreach` static: arc lookup, pound stagger, the reusable `Wedge` bucket). A calm zombie breaks a door blocking its ordered move, or one you RMB directly, **without leaving calm control**. `door_wedge_window` (0.5s) split out of `failsafe_window` (2s) so a feral wedged at a door converts to pounding at once instead of after two seconds. Release-on-door **deleted** (dormant 07-30, removed same day once Ben confirmed).
- ✅ **v0.46.0 — docks config rebaseline.** Ten hand-tuned `level_docks` values promoted to `GameConfig`/`LevelConfig` defaults. NOTE the knock-on: a `.tscn` only stores non-default values, so every existing level now follows the docks baseline for knobs it never set explicitly (each level's own overrides survive). `puzzle_test_3` is now effectively identical to docks.
- ✅ **v0.47.0 — flee exit rules.** Three-pass exit choice: availability → the **zombie-at-the-door filter** (new `exit_block_radius`, 120px; all-blocked → unfiltered fallback so nobody freezes) → threat-biased distance. Plus the **no-return latch** (a flushed runner committing to the street writes off every shelter inside the breached footprint — outermost when nested — and written-off doors can't absorb it on the walk past) and the **flush door-leg fix** (the "get out of the building first" leg no longer fires when the destination is inside that same building — the out-and-back bug).

- ✅ **Placed shelter residents hold position (2026-07-30).** Boot adoption no longer claims a ShelterSpot — a hand-placed human stays exactly where the designer put it (new `ShelterBuilding.add_occupant`, occupancy without a position). Spots are now a runtime-entrant mechanic only. Kills the level-authoring busywork of placing a spot per resident, and the "has no ShelterSpot children" warning with it.

**Still open from this batch (not scheduled):** nested-building click resolution — `_shelter_building_at` returns the first group-order building whose footprint contains the click, so RMB on a shop inside a market can target the market. Fix would be innermost/smallest-footprint wins. Same first-match shape affects the Mark's building aggro.

## Tier 3.6 — Performance at scale (2026-08-01 batch ✅ · next round pending a proper load test)
The v0.48.0 perf overhaul (spatial hash, scan cadences, BOID sample/cadence, nav re-path throttle — see the commit) took the docks load test (44 zombies / 447 humans) from unplayable to "better but still chuggy" at full-conversion mega-horde scale. Ben wants 2–5× unit counts, so a second round is expected. **Remaining known costs scale linearly per unit: FeralBrain.tick, NavigationServer queries, engine physics (`move_and_slide` × ~500 bodies).**

- **⭐ FIRST STEP NEXT ROUND — build the perf sampler.** A debug-only monitor (GM child or overlay hook) that appends frame-time / physics-time / script-time / unit-counts (calm/feral/fleeing/sheltered) to the log every few seconds while `debug_logs` is on. The 08-01 session diagnosed everything through hand-copied profiler screenshots — one frame at a time, whichever frame Ben happened to click. With the sampler Claude reads the whole session's performance curve from `godot.log` itself (file logging is already enabled) and the load test produces numbers from real play. Build it BEFORE optimizing anything further.
- Then: the proper load-test assessment (2–5× counts, full-conversion frenzy, mass rout) → decide between feral-brain cadence work and a design-side cap on simultaneous ferals. Both are design conversations, not free optimizations.
- **Still owed from the 08-01 batch: the §10 determinism check** — `debug_logs = true`, boot the same scenario twice, diff the logs. Every cadence is sim_tick+uid staggered and should be identical run-to-run; verify before trusting the batch.

## Tier 4 — Housekeeping bug batch ✅ DONE 2026-07-26 (landed with v0.45.0)
- ✅ **A4 + A5** — solved together: the lose verdict moved to the death instant (`report_gunfire_kill`, the only zombie-death source) — frame-exact, framerate-independent, teardown-immune; `_on_zombie_removed` is bookkeeping only; `get_total_zombie_count` = living + pending risers.
- ✅ Cross-owner control-group write — GM rise-handoff routes via new `SelectionManager.set_control_group`.
- ✅ **R = Restart** — `reload_current_scene`; `_ready` re-normalizes `time_scale`/`physics_ticks` (Engine state survives reloads — a restart mid-held-F stayed at 3×).
- ✅ `position`→`global_position` cluster — DONE 2026-07-23 (exposed by puzzle_test_3's offset `Marketplace` container: click/box selection missed nested units entirely, incl. corpses; nested humans steered/raycast in the wrong frame). Fixed: selection_manager click/box (×4), unit.gd move_to_target + clamp_position_to_bounds + _ready target init, human.gd both LOS raycasts, game_manager spawn_* (world→parent-frame conversion). The dormant-code *deletions* remain Tier 5 (rule-2 refactor).
- ✅ Dead code (shadowing LOS overrides + `space_state`, `@onready camera`, `starting_zombie_count`, unused `human_escaped` signal) — removed 2026-07-26.
- ✅ One-line `is_special` guard in contagion + all three release collectors (spec §3.7 insurance) — 2026-07-26.

## Tier 5 — Phase 5 (readability + refactor, while in those files)
- **5.1 vision_renderer migration** — move rings/fill-lines/tints/labels off the units into `vision_renderer.gd` (accessor seam already exists); takes `human.gd` back under 400.
- Extract **PatrolBehavior** from `human.gd`; `unit.gd` rule-2 fix (hoist `facing_direction`, delete dormant `move_speed`/`move_to_target`); optional fill-target hysteresis.
- **M1 bar:** validation Q2 — can you follow who's feral / filling / breaking at horde scale?

## Tier 6 — Phase 6 (PoC level + balance + M1 verdict)
- **Build the §12 level** applying the playtest principles: **levels must be perfectable** (escapes = punishment for imperfect play, never structural) and **linear/longer** for flow.
- **Sacred-ratio sweep** (fill speed vs zombie speed) → target Militia 1 / Police 2 / GI 3–4 → **M1 verdict** (validation Q1–5, 7).
- **Combo-continuity across encounters** — solve via a "chase sustains the combo" mechanic rather than just a bigger window.
- **Calm-mass-break re-judge** (is herd-everyone-out a hollow zero-score non-strategy now scoring exists?); **full Phase 3 test re-run** (see `phase3-test-criteria` memory); **crash watch** (keep console polled).

## Tier 7 — Phase 7 (M2: the Mark)
- ✅ **Manager splits** — DONE 2026-07-26: `hunt_pool.gd` + `violence_pipeline.gd` out of GameManager (one-line delegates kept, no caller changed; 595→~430) and `formation_planner.gd` (static) out of SelectionManager. Siege regression byte-identical. SM stays ~750 until the Phase-5 viz migration (accepted).
- **A3 — GameConfig override leak** — LevelConfig pushes into the autoload and nothing resets it; must land before a 2nd level exists.
- 🔶 **The Mark** — BUILT 2026-07-27 (v0.45.0, attention-field model — direction spec §5.4) but **first play found it confusing; grammar moved behind the C key (mark mode + crosshair cursor) to keep it out of the way. NEEDS A DESIGN WORKSHOP before validation Q6 can be judged.**
- **LMB fill-inspect** (M2's other half) — not yet built → then validation Q6 + full pass → **pivot verdict**.

---

## Trailing — doc sync (⏳ pending items from the 2026-07-02 batch)
Approved to execute (rule-9 signalled); no version bump. Two are **code-gated** — land them *after* the code fix:
- ✅ §4.1 decay clause (gun cools when no zombie *visible*), §4.3 threat-biased exit-set clause, §3.4 failsafe wording (bucketed, not rolling) — landed 2026-07-27 with the v0.45.0 doc sync (which also rewrote direction-spec §5.1/§5.4 to the as-built Mark and added buildings-spec §16 as-built amendments).
- ✅ After **A1**: implementer-guide invariant "a feral's death releases BOTH claims — pounce (abort) + pursuit (clear)." (added 2026-07-23)
- After **A2**: implementer-guide invariant "an armed human halts while the front is reached — stop-to-fire is the design."
- ✅ CLAUDE.md 2D-isometric wording (3D migration) — done 2026-07-27 (Ben signalled in the trope-ideation session: "there is no longer going to be 3D — document that"). Header + Current-focus tail rewritten; CLAUDE.md now flags the stale 3D wording elsewhere as superseded. Remaining references (GDD §11.15, PROJECT_CONTEXT, CODEBASE_REVIEW, V2 spec §13) — still Ben-gated with the rest of the doc sync.
