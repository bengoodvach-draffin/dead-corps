# Dead Corps — Codebase Review & Future-Proofing Plan

**Date:** 2026-06-10 · **Reviewed at:** v0.27.0 · **Engine:** Godot 4.6 / GDScript

A one-off engineering audit of the project setup and codebase, plus a sequenced
improvement plan. This is a **planning document** — nothing here has been
actioned. It complements (does not replace) `PROJECT_CONTEXT.md` (technical
state) and the GDD (design intent). Specific line numbers reflect v0.27.0 and
will drift; treat them as starting points, not gospel.

---

## Verdict

The project is functional and not a disaster, but it carries real structural
debt that will fight long-term development. The debt is **concentrated in a few
specific places**, not spread evenly — which is good, because targeted work
fixes most of it.

Key framing: **the confirmed 3D migration is the fork in the road.** On
migration, camera / vision renderer / scenes get rewritten and the game logic
(state machines, morale, combat, patrol, formations) is meant to survive
intact. Today that logic is **not cleanly separable** from presentation or from
itself, so a naive migration would drag the debt across. The highest-value work
is exactly the refactoring that makes the logic portable. Avoid cosmetic 2D
cleanup that the migration will throw away.

---

## What's working well (preserve this)

- Single clean autoload (`WorldBounds`) as a genuine single source of truth.
- Scenes use external scripts by UID; near-zero sub-resource bloat — diff-friendly.
- `@tool` editor guards are mostly correct (`Engine.is_editor_hint()`).
- Decent exported-config surface on `human.gd` (~35 `@export`s, per-class defaults).
- A working signal layer exists (`game_won/lost`, `human_converted`, …) — the one testable seam.
- `nav_baker.gd` runtime auto-bake is genuinely good tooling.

---

## Findings

### 1. Architecture — coupling is tangled, not layered (highest leverage)

- **`human.gd` is a 2854-line / 116 KB god class** holding nine subsystems:
  state machine, vision, morale, shooting, alerts, patrol, formations, flee,
  grapple/conversion. `_physics_process` alone is a ~295-line method mixing
  every subsystem with deep nesting and early returns.
- **Base class knows its subclasses.** `unit.gd` casts `self as Zombie` and
  reads `Zombie.facing_direction` / `is_melee_attacker` (`unit.gd:387,496`).
  This is the worst OO smell in the repo and it directly blocks the
  "logic survives the migration" goal.
- **The 2-attacker melee protocol is split across three files** (`zombie.gd`,
  `selection_manager.gd`, `human.gd`) with no single owner.
- **Cross-file reads of underscore-"private" fields** (e.g.
  `vision_renderer` reading `human._tunnel_vision_locked_direction`) — the `_`
  convention is decorative.
- **Everything self-discovers via `get_tree()` group lookups** used as runtime
  queries rather than one-time wiring. Testability is effectively zero by
  construction (no DI; nothing instantiable without a live SceneTree +
  populated groups + the autoload).
- `GameManager` is reasonably scoped but doubles as a unit registry whose
  `get_all_*()` filter on every call.

### 2. Performance — O(n²) group scans every physics frame

Will bite as the horde grows. All of these share one fix: a cached per-frame
unit registry in `GameManager`, replacing live `get_nodes_in_group`.

- Every `Unit._physics_process` runs separation + alignment, each calling
  `get_nodes_in_group()` (fresh array alloc) + a full same-team loop →
  ~3 group fetches + 3 O(n) loops per unit per frame.
- `count_melee_attackers()` / `is_being_attacked()` re-scan all zombies,
  called per-attacker per-frame → ~zombies×humans scans/frame when a horde
  piles on.
- `_acquire_shoot_target` does a full group scan + per-zombie raycast **every
  frame, ungated, per armed human** — the hottest single cost.
- `vision_renderer._process` calls `queue_redraw()` unconditionally every frame,
  then `_draw` fires 37–65 raycasts per visible cone (×every living human with
  `show_all_cones`).
- `update_health_bar()` runs every frame even when health is unchanged — should
  be event-driven from `take_damage`.

### 3. Code health — noise and a latent bug

- **Latent bug (relevant to the validation slice):** manually-placed *zombies*
  never get `tree_exiting` / `zombie_killed_human` connected
  (`game_manager.gd:251`), while manually-placed humans do. A hand-placed zombie
  dying won't trigger the lose-condition check or kill signals.
- **~90 `print()` in `human.gd`**, plus combat/stuck prints in `zombie.gd`, all
  unguarded by `OS.is_debug_build()` — they ship and some run per-frame.
  `_physics_process` even contains per-frame `push_error` invariant checks.
- **Dead code:** `apply_cohesion_force` (~37 lines, call site commented),
  `handle_edge_scroll` body (~30 lines), the empty `_on_zombie_killed_human`
  stub + its still-connected signal, the deprecated `propagate_flee_to_group`,
  the unused `UnitType` enum (a parallel taxonomy that doesn't match
  `DefenderClass`), and `enable_debug_logging`+`pass`+`#print` stubs.
- **Four near-duplicate "find nearest human" scanners** with a hand-synced 15px
  magic radius; a copy-pasted nav-movement block (`handle_combat` vs
  `move_to_target`); LOS-raycast boilerplate duplicated ×4.
- **Tuning values scattered and duplicated** (alert clocks, damage `50`, the
  `200.0` flee range duplicated across two files). A designer can tune class
  stats but not AI *feel* without editing code.
- **Documented-rule violation:** combat/separation use local `position` while
  CLAUDE.md mandates `global_position` for cross-unit math.

### 4. Project setup & hygiene

- **~63 MB of dead Windows build binaries are permanently in git history**
  (initial commit's `Exports/` dir; removed from tree, not history). Every clone
  pays this forever. Removal requires a history rewrite (`git filter-repo`) —
  **destructive on the shared remote; requires explicit go-ahead.**
- **`.gitignore` doesn't exclude `/Exports/`, `*.exe`, `*.pck`**, and
  `export_presets.cfg` writes the `.exe` into the repo root — one careless
  `git add .` re-commits a build. Trivial fix prevents a repeat of the above.
- **Renderer mismatch:** `config/features` lists "Forward Plus" but
  `renderer/rendering_method="gl_compatibility"` — the latter wins at runtime,
  so the game is actually on the GL Compatibility backend. Harmless today;
  should be a deliberate choice at the 3D migration (GL Compat lacks several
  Forward+ lighting/post features).
- **Physics/navigation layers are unnamed** (no `[layer_names]`) while 5 scripts
  use numeric layers and nav correctness depends on "both Layer 1" conventions.
  Naming them is the cheapest bug-risk reduction available.
- **No tooling:** no `gdlint`/`gdformat`, no CI, no `.editorconfig`. A 116 KB
  script with no parse/lint gate is the real gap — a headless
  `godot --headless --check-only` would catch exactly the partial-comment parse
  errors CLAUDE.md warns about.
- **Doc sprawl:** 46 markdown files (13 active + 33 archived, incl. 7
  near-duplicate GDD copies). Three overlapping navigation docs are already
  stale vs the v0.26.0 auto-bake system.
- Cosmetic: stock Godot `icon.svg` (unbranded); no `default_clear_color`;
  `.gitattributes` has no LFS plan for incoming 3D assets.

---

## Improvement & Future-Proofing Plan

Sequenced for cheap safety/signal first, then structural work that pays off
across the 3D migration. Each item is an independent, testable pass — not one
big bang.

### Phase 0 — Cheap safety net (low risk, do first)
1. Add `/Exports/`, `*.exe`, `*.pck` to `.gitignore`.
2. Add gdtoolkit (`gdlint`/`gdformat`) config + a minimal CI step running
   `gdlint` and `godot --headless --check-only`.
3. Name the physics/navigation layers in `project.godot`.
4. Gate all `print()` behind `OS.is_debug_build()` / a debug flag; remove the
   per-frame `push_error` invariant checks.
5. **Decide** on the git-history rewrite (separate, deliberate; destructive —
   needs explicit go-ahead before any action).

### Phase 1 — Kill the noise & the latent bug (low risk)
6. Fix manually-placed-zombie signal wiring (`game_manager.gd:251`).
7. Delete dead code (cohesion force, edge-scroll body, empty kill stub + signal,
   `UnitType` enum, `propagate_flee_to_group`, debug stubs).
8. Consolidate the 3 nav docs → 1 and 3 patrol docs → 1; flag the stale ones.

### Phase 2 — Decouple logic from presentation (migration-survival work)
9. Introduce a cached unit registry in `GameManager` + helpers
   (`get_living_zombies/humans`, `nearby(radius)`); replace per-frame
   `get_nodes_in_group`. **Biggest single win** — fixes most O(n²) cost and
   removes a coupling layer.
10. Remove the base-class-knows-subclass smell: push `self as Zombie` logic down
    into the subclass / behind a virtual method so `Unit` is self-contained.
11. Make `update_health_bar` and vision redraws event-driven, not per-frame.

### Phase 3 — Decompose `human.gd` (highest effort, incremental)
12. Extract a `DefenderStats` Resource (`.tres` per class) from
    `_apply_class_defaults`.
13. Split into component child nodes, one at a time: Vision → Morale → Weapon →
    Alert → Patrol/Formation → Flee. Each is independently testable and survives
    the 3D migration unchanged.
14. Replace the 295-line `_physics_process` with per-state handler methods.

### Recommended timing
- **Now:** Phases 0–1 (cheap; one is a real bug).
- **Next:** Phase 2 — makes the 3D migration tractable *and* improves the
  current game.
- **Hold Phase 3** until the validation slice has been playtested (scope-control
  pillar: don't elaborate systems before validating the loop is fun). If the
  loop validates, decompose during/alongside the 3D migration when scenes are
  being rewritten anyway.

---

## Notes / open decisions

- Git-history rewrite is the only destructive item and is explicitly deferred to
  a deliberate decision.
- Phase 3 deliberately trails the validation slice per the project's scope-control pillar.
- Line numbers are v0.27.0 snapshots and will drift.
