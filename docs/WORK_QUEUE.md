# Dead Corps — v2-poc Work Queue

**Updated:** 2026-07-12 · **Branch:** `v2-poc` @ v0.43.0
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
- **CUT for now (Ben deprioritized):** zombies getting stuck on geometry — the corner-stuck investigation *and* the zombie-pursuit-nav asymmetry. Not queued.

## Blocked on Ben
- **Corpse-commands A/B/C** (Tier 3): (A) move-order-only to start? (B) box-select grabs corpses alongside calm zombies? (C) interim visual cues (corpse marker + selected ring + line to destination) ok?
- **Deter-knob test (Point 1):** Ben tests `flee_repel_strength` (1.5→2.5–3.0) / `flee_repel_radius` (180→220) to judge whether steering-only is enough or body collision is needed.

---

## Tier 1 — Ruled bug fixes (do before the next playtest; they protect the validation verdict)
Small, ruled, high-impact. Suggested PATCH bumps (or one v0.43.1 batch — Ben's call).

1. **A1 — feral pursuit-claim leak (HIGHEST).** `zombie.gd die()` aborts the pounce but never calls `_feral.clear()`, so a feral shot mid-chase never releases its pursuit claim → its straggler stays "pursued" forever, no feral peels onto it, and the hunted ring sticks. Corrupts the peel-off model the PoC exists to validate. **Fix:** add `_feral.clear()` in `die()` before the corpse-linger await.
2. **A2 — stop-to-fire.** A *moving* armed defender wipes its aim rotation each frame → can't fire >~21° off its travel direction. **Fix (ruled):** while the fill front is in the *reached* state, the human halts (patrol suspends, velocity zeroes, aim owns facing); movement resumes after the shot. Fear-break must still preempt. Natural moment to restructure `human.gd _physics_process` into a match dispatcher.
3. **B3 — cowerers block firing lanes.** `start_cowering()` doesn't zero `collision_layer` like `die()` does. One line.

## Tier 2 — Small feature + the immersion fix
4. **Release magnetism (#1).** Click pins to nearest human within a new `release_aim_radius` (~100px); fall through to a calm move order when no human is in range. Small, high-relief, ready.
5. **Point 1 — humans phase through calm zombies.** Ben tests the deter knob first; if steering-only isn't enough, add body collision (small — units currently have *no* unit-unit collision, BOID only). Optional **guard mode** later if strong intentional walls prove wanted.

## Tier 3 — Bigger playtest features
6. **Corpse commands (3.2).** Order a body before it rises; it rises already walking there. Net-new selectable corpse entity (risers are today just DEAD humans counting down in `game_manager._pending_risers`). *Blocked on A/B/C.*
7. **Select-all-non-feral hotkey (3.1).** Grabs the whole controllable set (calm + corpses). Small; builds on #6.

## Tier 4 — Housekeeping bug batch (any time, one commit)
- **A4** teardown "Defeat!" (extend the reset-guard to skip `not is_alive` exits).
- **A5** lose verdict coupled to render framerate (filter lose-count by `is_alive`, keep `+ _pending_risers`).
- Cross-owner control-group write (route through a SelectionManager method).
- **R = Restart** (spec §5.1) — unimplemented; reuse the debug-overlay reset path.
- `position`→`global_position` cluster (selection_manager click/box; unit.gd movement/bounds — some resolve by deletion).
- Dead code (shadowing LOS overrides + `space_state`, `@onready camera`, `starting_zombie_count`, unused `human_escaped` signal); stale comments.
- One-line `is_special` guard in `_apply_contagion` + `_release` (spec §3.7 insurance).

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
- **Manager splits first:** GameManager (hunt pool + violence pipeline out) and SelectionManager (formation planner out) — both over the tripwire and Phase 7 routes new systems at both.
- **A3 — GameConfig override leak** — LevelConfig pushes into the autoload and nothing resets it; must land before a 2nd level exists.
- **The Mark + LMB fill-inspect** → validation Q6 + full pass → **pivot verdict**.

---

## Trailing — doc sync (⏳ pending items from the 2026-07-02 batch)
Approved to execute (rule-9 signalled); no version bump. Two are **code-gated** — land them *after* the code fix:
- §4.1 decay clause (gun cools when no zombie *visible*), §4.3 threat-biased exit, §3.4 failsafe wording (bucketed, not rolling).
- After **A1**: implementer-guide invariant "a feral's death releases BOTH claims — pounce (abort) + pursuit (clear)."
- After **A2**: implementer-guide invariant "an armed human halts while the front is reached — stop-to-fire is the design."
- CLAUDE.md 2D-isometric wording (3D migration) — still Ben-gated.
