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

> **The phases above are a catalogue of work items.** For the single ordered
> execution sequence — which interleaves these phases with the scaling work and
> accounts for validation now running at high unit counts — see
> **[Master Roadmap](#master-roadmap--single-ordered-execution-sequence)** below.

---

## Performance & Scaling (deep dive)

**Target scale (decided):** ~150–500 active units on screen at peak. This section
plans for that tier specifically. It supersedes the brief perf notes in Findings §2.

### Core problem

Every unit independently re-queries the entire scene tree every physics frame,
and there is no spatial index anywhere. This is the classic O(n²) crowd trap:
invisible at the current ~11-unit test scenario, it degrades quadratically and
will cliff somewhere around 50–150 active units. Doubling the horde ~quadruples
the cost.

### Where the frames go (measured against v0.27.0 code)

1. **BOID flocking — dominant cost (`unit.gd`).** Every `Unit._physics_process`
   (60 Hz) runs `apply_separation_force()` (`:383`) and `apply_alignment_force()`
   (`:479`, zombies). Each does its own `get_tree().get_nodes_in_group()` (fresh
   array alloc) + a full team loop; alignment also re-loops via
   `find_nearby_allies()` (`:359`). Net: ~2 group fetches + ~2 full O(Z) loops
   per zombie per frame → ~2·Z² distance calcs/frame.
   - Z=11 → ~240/frame (trivial); Z=150 → ~45k/frame; Z=300 → ~180k/frame (~10.8M/s).
   - Plus a fresh `Array` per `get_nodes_in_group` → constant GC churn.
2. **Melee bookkeeping — second O(n²) (`zombie.gd`).** Each attacking zombie calls
   `manage_melee_attacker_status()` → `count_melee_attackers()` every frame, which
   scans all zombies (`human.gd:2766`).
3. **Human perception — partly gated (`human.gd`).** Heavy detection IS throttled
   to 0.3 s (`detection_timer`, `:819`) — correct pattern, keep it. But
   `_acquire_shoot_target` / `_find_in_range_target` run **every frame, ungated**
   (`:1369,1395`): full zombie scan + raycast per zombie per armed human (H·Z
   raycasts/frame). 15 `get_nodes_in_group` sites total; several reachable per
   frame. Per-frame `print()` with `snapped(rad_to_deg(...))` string-building
   (`:842,868`) fires in the loop.
4. **Per-unit node weight.** Human ≈10 nodes incl. a `ProgressBar` + 3×
   `AudioStreamPlayer2D`; zombie ≈9 nodes incl. `NavigationAgent2D` + `ProgressBar`
   + `Label`. At 300 units ≈3,000 nodes, ~300 ProgressBars laying out, ~900 audio
   players. `update_health_bar()` runs every frame per unit (`unit.gd:172`) even
   at full health.
5. **Navigation churn (`zombie.gd`).** `nav_agent.target_position` set every frame
   while pursuing (`:176,202`) can force frequent repaths; nothing throttles or
   shares paths.
6. **Vision rendering — NOT the bottleneck.** `queue_redraw()` is unconditional
   (`vision_renderer.gd:61`) but normal play only draws the pinned + tunnel-vision
   cones (cheap). The 37-raycasts-per-cone cost only triggers with the `V`
   all-cones debug key. Gate the redraw eventually, but don't spend rebuild effort
   here.

### Fixes (carry across the 3D migration — pure logic/data, not throwaway)

- **A. Central spatial index + neighbour cache (the big one).** Uniform
  spatial-hash grid in `GameManager`, rebuilt once per frame from the
  `all_zombies`/`all_humans` arrays it already maintains. Units call
  `neighbours_within(pos, radius)` instead of `get_nodes_in_group` + full loop.
  Turns O(n²) → ~O(n·k); removes per-frame array allocations. This is what makes
  the target count possible at all.
- **B. AI tick decoupling / LOD.** Run flocking + AI decisions at ~10–15 Hz,
  staggered across units in buckets (not all on the same frame); tick distant /
  unengaged units even less often. Keep movement at 60 Hz for smoothness —
  decisions don't need it. Generalises the existing 0.3 s detection throttle.
- **C. Event-driven UI.** Update health bars only in `take_damage`, not per frame;
  hide/disable bars + audio players offscreen. At this tier, move to a single
  batched health overlay / `MultiMesh` rather than a `ProgressBar` per unit.
- **D. Gate the shooting scan** on a timer like detection; throttle
  `NavigationAgent2D` target updates (repath only when target moved > ~1 tile or
  every N ticks); share/reuse paths for grouped movement.
- **E. Strip hot-path prints** behind `OS.is_debug_build()` / a debug flag.

### Tier 2 specifics (150–500 units)

Beyond A–E, this count needs presentation-layer work:
- **MultiMeshInstance2D** for unit bodies; per-unit `Sprite`/`ColorRect` draw calls
  won't scale to hundreds. Pool unit nodes (don't instantiate/free mid-wave).
- **Drop per-unit Control nodes** (`ProgressBar`, `Label`) in favour of batched
  drawing — Control layout is the heaviest per-unit cost at this scale.
- **Shared audio** — a small pooled audio manager instead of 3 players × 500 units.
- **Throttled / shared navigation** — flow-field or shared group paths rather than
  per-agent repaths.
- (Tiers for reference: ≤150 = A–E only, keep nodes. 1000+ = data-oriented rebuild
  on `PhysicsServer2D`/`RenderingServer`, no per-unit nodes — out of current scope.)

> The scaling fixes A–E and the Tier-2 presentation work are sequenced together
> with the rest of the project in the **Master Roadmap** below — not as a separate
> track.

---

## Master Roadmap — single ordered execution sequence

This is **the** order of work. It merges the improvement phases (P0–P3) and the
scaling fixes (A–E + Tier 2) into one line. The key scheduling decision:
**because the validation slice will now be played at 150–500 units, the
algorithmic scaling core (Stage C) moves *before* validation** — you cannot
validate "is the loop fun at scale" on an engine that cliffs at 80 units.

Tags: `P#.n` = phase item above · `Fix X` = scaling fix above.

### Stage A — Safety net & cleanup *(do now; low risk; unblocks the rest)*
1. `.gitignore` exports `/Exports/`, `*.exe`, `*.pck` *(P0.1)*
2. gdlint/gdformat + a headless `godot --headless --check-only` CI gate *(P0.2)* —
   doubly important now: it's the parse-error safety net for any
   lower-capability model doing the mechanical work below.
3. Name physics/navigation layers in `project.godot` *(P0.3)*
4. Gate all hot-path `print()` behind `OS.is_debug_build()` / a debug flag
   *(P0.4 + Fix E)* — also a real per-frame win.
5. Fix manually-placed-zombie signal wiring `game_manager.gd:251` *(P1.6)* — latent bug.
6. Delete dead code *(P1.7)*; consolidate nav/patrol docs *(P1.8)*.
- *Standalone decision:* git-history rewrite for the ~63 MB of dead binaries
  (destructive — needs explicit go-ahead; not blocking).

### Stage B — Benchmark baseline *(before any scaling work)*
7. Throwaway scene spawning N idle + N engaged units; record the FPS cliff per
   count on target hardware. Proves the baseline and measures each later step.
   *(Perf step 1)*

### Stage C — Algorithmic scaling core *(REQUIRED before validation)*
8. **Spatial index + neighbour cache** in `GameManager`, rebuilt once/frame from
   the `all_*` arrays; units call `neighbours_within(pos, radius)` instead of
   `get_nodes_in_group` + full loop. *(P2.9 + Fix A — biggest single win.)*
   **Design it on a 2D ground-plane projection so it transfers to 3D unchanged
   (see 3D Migration Impact).**
9. Remove the base-class-knows-subclass smell while in `unit.gd` *(P2.10)*.
10. AI tick decoupling / bucketed LOD — decisions at ~10–15 Hz, movement at 60 Hz
    *(Fix B)*.
11. Gate the shooting scan on a timer + throttle `NavigationAgent2D` repaths *(Fix D)*.
12. Event-driven health bars + gate the vision redraw *(P2.11 + Fix C)*.

### Stage D — VALIDATION SLICE *(the current design focus, now at representative counts)*
13. Playtest the handcrafted level at 150–500 units. Confirm the loop is fun and
    the scaling core holds. Scope-control pillar gates everything below this line.

### Stage E — Presentation-layer scaling *(after counts confirmed; fold into 3D)*
14. `MultiMeshInstance2D` unit bodies + node pooling *(Tier 2)*.
15. Drop per-unit `ProgressBar`/`Label` → batched health overlay *(Tier 2)*.
16. Shared/pooled audio manager *(Tier 2)*.
17. Flow-field / shared group paths *(Fix D nav half + Tier 2)*.
> Do Stage E **lightly** in 2D — just enough to validate counts. The full version
> belongs in 3D (Stage G), where this exact code is rewritten anyway. Don't
> gold-plate 2D rendering you're about to replace.

### Stage F — `human.gd` decomposition *(after validation; alongside 3D)*
18. Extract `DefenderStats` resource *(P3.12)*.
19. Component split: Vision → Morale → Weapon → Alert → Patrol/Formation → Flee *(P3.13)*.
20. Per-state handler methods replacing the 295-line `_physics_process` *(P3.14)*.

### Stage G — 3D migration
21. Presentation rewrite (see next section). Stages E and F naturally fold in here.

---

## 3D Migration Impact

Short answer to "do we keep the performance improvements?": **yes — all of the
algorithmic ones, and most of the architectural ones.** The split is clean
because performance work here is logic/data and the migration is presentation.

### Survives 100% (logic/data — engine-dimension-agnostic)
- Spatial index + neighbour cache *(Fix A)* — **if** built on a 2D ground-plane
  (x/z) projection, which is standard for tactical games even in 3D. Design it
  that way now and it transfers with ~zero change.
- AI tick decoupling / LOD scheduling *(Fix B)*; gated scans + nav throttling
  logic *(Fix D)*; event-driven state logic *(Fix C — the logic; the widget changes)*.
- `human.gd` decomposition + `DefenderStats` *(Stage F)* — pure logic/components.
- All game systems: state machines, morale, combat, patrol, formations, alerts.

### Rewritten (presentation — expected, already in the plan)
- `Sprite2D`/`ColorRect` → `MeshInstance3D` / `MultiMeshInstance3D`.
- `vision_renderer` 2D `_draw` → 3D cone meshes/decals/shaders + 3D raycasts.
- `camera_controller` → 3D camera; selection picking → screen→world 3D raycast.
- `CharacterBody2D`/`CollisionShape2D`/`NavigationAgent2D` → their 3D equivalents.
- All `.tscn` scene files.

### Partially redone (the Tier-2 presentation-scaling work, Stage E)
- `MultiMeshInstance2D` → `MultiMeshInstance3D`: same architecture (pooling,
  batched health overlay, no per-unit Control), parallel API. The *pattern*
  carries; the *code* is partly rewritten. Hence the "do Stage E lightly in 2D"
  guidance above.

### New issues that arise in 3D (did not exist in 2D)
1. **Rendering becomes the dominant cost.** 500 sprites is cheap; 500 animated,
   lit, shadow-casting 3D characters is not. Mitigations: low-poly, MultiMesh,
   mesh LODs / billboard impostors at distance, no per-unit shadows, GPU/vertex
   animation over skeletal for the crowd. **Re-benchmark rendering in 3D — the 2D
   benchmark does not predict it.**
2. **Physics is heavier.** Consider keeping crowd units kinematic / off the
   physics server (units already don't collide with each other), rather than full
   `CharacterBody3D` per unit.
3. **Navigation/avoidance.** `NavigationServer3D` + navmesh baking on multi-level
   geometry. Upside: RVO avoidance becomes available and could *replace* the
   hand-rolled BOID separation — a net simplification.
4. **Vertical occlusion / LOS.** The reason for 3D (rooftops, urban occlusion)
   means vision/LOS now care about height and floors; the spatial index may need a
   coarse vertical band.
5. **Asset/animation pipeline.** Rigs, animation states, import settings, LODs — a
   content cost 2D didn't have.
6. **Renderer choice now matters** — resolve the `Forward Plus` vs
   `gl_compatibility` mismatch (Findings §4) deliberately; 3D lighting needs it.

**Recommendation:** to maximise survival, build Stage C with a light model/view
separation — keep unit *simulation* data (position, state, stats) addressable
independently of the node — so 3D becomes mostly a view swap. Expect rendering,
not AI, to be the new bottleneck in 3D.

---

## Executing this plan (implementer notes — incl. lower-capability models)

**Is more technical documentation needed for a cheaper model to execute safely?
Yes — but not all of it up front.** Today's docs (CLAUDE.md, GDD,
PROJECT_CONTEXT, rich inline comments) are excellent *context and guardrails* but
the roadmap items are *intent-level*, not executable specs. A smaller model holds
less context, infers less, and is likelier to silently break an invariant it
can't see. Two-part fix:

### 1. Durable invariants & verification (write once, stable)
> Implemented as **`docs/Archive/IMPLEMENTER_GUIDE.md`** (archived during the v2 pivot — its specs target v1 code; see `V2_IMPLEMENTER_GUIDE.md`) — the detailed, code-grounded
> build spec for the Stage C scaling work (one spec per optimisation: data
> structures, exact functions, pseudocode, invariants-to-preserve, pass criteria),
> plus the optimisation-specific invariants checklist and the ticket template.
> The summary below is the headline invariants list only.

The cross-cutting rules any model MUST preserve when touching hot paths (these are
scattered through CLAUDE.md / PROJECT_CONTEXT today — a single checklist is the gap):
- **Corpse-linger filtering:** dead units (`current_health <= 0`) must stay
  excluded from separation/targeting during the 0.3 s linger (`unit.gd:406`).
- **Melee gate is decoupled:** the live 2-attacker cap reads
  `count_melee_attackers()`, **not** `attacker_count` (total targeting). Don't
  merge them.
- **`global_position` for all cross-unit math** — never local `position`
  (already violated in `unit.gd`; don't propagate it).
- **`@tool` scripts must guard game logic** with `Engine.is_editor_hint()`.
- **Special-zombie checks use duck typing** (`zombie.get("is_costumed")`), never
  `class_name` checks — avoids load-order parse errors.
- **Optional-array / empty-default pattern** for new per-unit behaviour
  (backwards compatibility — empty = old behaviour).
- **Bulk-commenting prints can leave empty blocks** → parse error; scan after.
- **Verification = manual play** (no automated suite). Each task ships with
  explicit test steps; the Stage A lint + headless `--check-only` gate is the
  only automated safety net, which is why it's first.

### 2. Just-in-time per-task tickets (write immediately before each task)
Don't pre-write all tickets — line numbers and the spatial-index design will
drift (and may change after the Stage B benchmark). Write each ticket against
*current* code right before execution, containing: scope · exact files/functions
+ current signatures · the precise approach/data structures · which invariants it
touches · step-by-step edits · acceptance criteria + manual test steps · rollback note.

### Division of labour (respects the design-led, propose-first workflow)
- **Design, ticket-writing, and review** → Ben or a high-capability model. Smaller
  models are weak at the "propose / push back / judge against the pillars" step
  this project requires.
- **Execution of well-specified, low-judgement tickets** → fine for a cheaper
  model: the Stage A mechanical work (gitignore, lint setup, dead-code deletion,
  layer naming), applying a spec'd algorithm, mechanical refactors with a clear
  acceptance test. Do **not** hand it open-ended design or "make it faster" tasks.

---

## Notes / open decisions

- The **Master Roadmap** is the authoritative execution order; the phase
  catalogue and the scaling fixes feed into it.
- Scaling core (Stage C) is scheduled **before** validation (Stage D) because the
  validation slice now runs at 150–500 units.
- `human.gd` decomposition (Stage F) deliberately trails validation per the
  scope-control pillar, and folds into the 3D migration.
- Git-history rewrite is the only destructive item — explicitly deferred to a
  deliberate decision.
- Detailed per-task tickets are written just-in-time against current code (see
  "Executing this plan"), not pre-written here.
- Line numbers are v0.27.0 snapshots and will drift.
