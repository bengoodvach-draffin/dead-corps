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

1. **A1 — feral pursuit-claim leak (HIGHEST).** ✅ DONE 2026-07-12 (landed in the same commit as this queue; entry never got its checkmark). `zombie.gd die()` aborts the pounce AND calls `_feral.clear()` before the corpse-linger await, so a feral shot mid-chase releases both claims and its straggler returns to the peel-off pool.
2. **A2 — stop-to-fire.** ✅ CODE LANDED 2026-07-12 (UNTESTED — pre-emptive). A *moving* armed defender wipes its aim rotation each frame → can't fire >~21° off its travel direction. Fix: `human.gd` dispatcher halts an armed defender while `_fill_front.is_reached()` so aim owns facing; resumes on fire. **Only manifests for a moving armed defender — no patrols exist yet, so it can't occur today; test deferred until patrols return** (test steps in the `phase3-test-criteria` memory). Dispatcher `match`-restructure deferred to Tier 5 (Phase 5).
3. **B3 — cowerers block firing lanes.** ✅ DONE 2026-07-12. `start_cowering()` now zeroes `collision_layer` (mirrors `die()`) so a cowerer no longer screens armed defenders' shots (spec §4.1).

## Tier 2 — Small feature + the immersion fix
4. **Release magnetism (#1).** ✅ DONE 2026-07-12. New `release_aim_radius` knob (default 100px, in GameConfig + LevelConfig); `_human_at` uses it so RMB within that radius of a human = a release pinned to the nearest one (pin-and-aim: seeds from the human's position); outside it = a calm move order. **Bonus:** every LevelConfig `@export` now carries a `##` doc-comment → shows as an inspector rollover tooltip.
5. **Point 1 — humans phase through calm zombies.** ⏸️ PARKED 2026-07-12 — Ben couldn't replicate the phase-through in play, so no action for now. If it resurfaces: tune the deter knob (`flee_repel_strength`/`radius`); if steering-only isn't enough, add body collision (units currently have *no* unit-unit collision, BOID only). Optional **guard mode** later for strong intentional walls.

## Tier 3 — Bigger playtest features
6. **Corpse commands (3.2).** ✅ DONE 2026-07-12 (6a + 6b). Order a body before it rises. Model: the queued order is a stored **click**, re-resolved at rise via the live release-or-move rule (`release_aim_radius`) — human near → rises feral & attacks; else → rises calm & moves. A selected corpse's risen zombie auto-selects (if calm). 6b: assigning a control group to a corpse tags the entry so the risen zombie joins that group on rise.
8. **Zombie move-queue / shift-click waypoints.** Shift-click chains multiple move orders for the selected calm reserve, so you set up a route (stage the next encounter, round a corner) without mid-action micro — the pro-flow half of playtest point #3. Calm moves already nav-path, so it also eases the "stuck on corners / micro to avoid enemies" complaint. **Cap: queued moves only — no loops/branches/patrol-editing** (that would drag back toward the planning game the pivot fled). *(Restored 2026-07-12 — was dropped when the corner-stuck half of point #3 was cut.)*
7. **Select-all-non-feral hotkey (3.1).** ⏸️ PARKED — only ever a soft "maybe / catch-all"; corpse commands (#6) may make it unnecessary. Revisit if grabbing risers still feels fiddly after #6.

## Tier 4 — Housekeeping bug batch (any time, one commit)
- **A4** teardown "Defeat!" (extend the reset-guard to skip `not is_alive` exits).
- **A5** lose verdict coupled to render framerate (filter lose-count by `is_alive`, keep `+ _pending_risers`).
- Cross-owner control-group write (route through a SelectionManager method).
- **R = Restart** (spec §5.1) — unimplemented; reuse the debug-overlay reset path.
- ✅ `position`→`global_position` cluster — DONE 2026-07-23 (exposed by puzzle_test_3's offset `Marketplace` container: click/box selection missed nested units entirely, incl. corpses; nested humans steered/raycast in the wrong frame). Fixed: selection_manager click/box (×4), unit.gd move_to_target + clamp_position_to_bounds + _ready target init, human.gd both LOS raycasts, game_manager spawn_* (world→parent-frame conversion). The dormant-code *deletions* remain Tier 5 (rule-2 refactor).
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
- ✅ After **A1**: implementer-guide invariant "a feral's death releases BOTH claims — pounce (abort) + pursuit (clear)." (added 2026-07-23)
- After **A2**: implementer-guide invariant "an armed human halts while the front is reached — stop-to-fire is the design."
- ✅ CLAUDE.md 2D-isometric wording (3D migration) — done 2026-07-27 (Ben signalled in the trope-ideation session: "there is no longer going to be 3D — document that"). Header + Current-focus tail rewritten; CLAUDE.md now flags the stale 3D wording elsewhere as superseded. Remaining references (GDD §11.15, PROJECT_CONTEXT, CODEBASE_REVIEW, V2 spec §13) — still Ben-gated with the rest of the doc sync.
