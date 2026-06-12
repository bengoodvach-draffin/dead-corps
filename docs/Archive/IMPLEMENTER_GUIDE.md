# Dead Corps — Scaling Implementation Guide

**What this is:** the detailed, code-grounded build spec for the **algorithmic
scaling core** (Master Roadmap Stage C + the Stage B benchmark) in
`docs/CODEBASE_REVIEW.md`. It exists so a lower-capability model — or a future you
without the whole codebase paged in — can implement these optimisations
*accurately*, preserving the gameplay behaviour they must not change.

**What this is NOT:** a restatement of `CLAUDE.md`. Process rules (propose-first,
one-feature-at-a-time, version discipline, Ben commits), GDScript conventions, and
the design pillars all live in `CLAUDE.md` and `docs/PROJECT_CONTEXT.md` — read
them first; they are not repeated here.

Each spec is a proposal against **v0.27.0** code. Line numbers drift — they are
pointers, not addresses; re-grep the named function before editing. A capable
reviewer (Ben) approves a spec before a lower-capability model executes it.

---

## Before you touch a hot path — invariants that break under optimisation

These are the behaviours that look fine in casual play but silently break when you
change neighbour queries or tick cadence. Every spec below lists which ones it
risks; keep this list in view.

- **Dead-unit exclusion (corpse linger).** A shot unit's `current_health` hits 0
  immediately but it lives ~0.3 s before `queue_free()`. It must stay **excluded
  from separation and from targeting/melee scans** for that window
  (`unit.gd` `apply_separation_force`, the `current_health <= 0` skip). Any new
  neighbour query must reproduce this skip.
- **Melee gate ≠ targeting count.** The live 2-attacker cap reads
  `Human.count_melee_attackers()` (zombies *actually meleeing*), never
  `attacker_count` (total *targeting*). Don't conflate them when caching counts.
- **`global_position`, not `position`.** All cross-unit distance math must use
  `global_position` (units live under a runtime `units_parent`; escape zones are
  nested). The current BOID code uses local `position` — when you migrate it to
  the grid, **fix it to `global_position`** (the grid is global-space).
- **Melee attackers don't get pushed.** `apply_separation_force` early-returns for
  a zombie that `is_melee_attacker`. Preserve that exact gate.
- **Player agency / no auto-pursuit.** Don't let a perf change (e.g. shared
  targeting) introduce automatic engagement. Engagement is right-click only.
- **Determinism.** Don't introduce randomness into *which* unit a query returns in
  a way that changes primary AI decisions frame-to-frame.

If you can't say how a change keeps each risked invariant intact, it isn't ready.

---

## Verification harness (how to prove a perf change worked)

No automated suite. For scaling work specifically:

1. **Build the benchmark scene first (Spec 0).** It is the measuring instrument.
2. **Measure, don't guess.** Record FPS (and physics frame time via
   `Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)`) at fixed unit
   counts *before* a change, then after. A spec "passes" only if (a) the metric
   improves at high counts and (b) behaviour is unchanged at low counts.
3. **Behaviour regression check at low counts.** Run the existing slice
   (`sandbox_level_human_testing.tscn`, ~11 units) and confirm flocking, melee
   rotation, detection, and shooting look identical to before. Perf wins that
   change feel at 11 units are bugs.
4. **F1** debug overlay for live counts; **F5** runs `scenes/main.tscn`.

Each spec ends with its own concrete pass criteria.

---

## Spec 0 — Benchmark scene (Stage B; do this first)

**Goal:** a throwaway scene that spawns N zombies + N humans so every later spec
can be measured. Not shipped; lives for the duration of the scaling work.

**Create:** `scenes/benchmark.tscn` + `scripts/benchmark.gd` (check neither name
exists first — `grep -ril benchmark`).

**Design:**
- A `Node2D` root with a `GameManager`, `WorldBounds`/`LevelBounds`,
  `NavBaker`+nav region, and a `CameraController` (copy from `main.tscn` so the
  environment matches real play).
- `benchmark.gd` exports `@export var spawn_count: int = 50` and an
  `@export var engaged: bool = true`. On ready, spawn `spawn_count` zombies and
  `spawn_count` humans in a grid/ring within bounds via
  `game_manager.spawn_zombie/spawn_human`. If `engaged`, issue a move/attack order
  so flocking + combat paths are exercised (worst case), not just idle.
- Draw an on-screen label each frame with `Engine.get_frames_per_second()` and
  `Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0` ms.
- Allow runtime bump: a key (e.g. `+`) that spawns +25 more, so you can watch the
  frame time climb and find the cliff live.

**Preserve:** none — isolated scene. Don't wire it into `main.tscn` or exports.

**Acceptance:** running it at 25/50/100/200/400 units produces a clear FPS curve;
record the numbers in the roadmap. This is the baseline every other spec is
measured against.

---

## Spec 1 — Spatial index + neighbour cache (the flagship; biggest win)

**Goal:** kill the O(n²). Replace every per-frame
`get_tree().get_nodes_in_group(...)` + full-team loop in the hot path with a
bucketed radius query against a grid rebuilt once per frame.

**Current code (what it replaces):**
- `unit.gd` `apply_separation_force()` — `get_nodes_in_group(my_group)` + loop all.
- `unit.gd` `apply_alignment_force()` → `find_nearby_allies()` — another
  `get_nodes_in_group` + loop all.
- (later specs reuse the same grid for human detection / melee counting.)

**Design — a uniform spatial hash, one grid per team:**

New file `scripts/unit_grid.gd` (`class_name UnitGrid extends Node`), added as a
child of `GameManager` (or an autoload). Two hashes — zombies and humans — because
every current query is single-team.

```gdscript
class_name UnitGrid extends Node

const CELL_SIZE := 100.0   # >= the largest neighbour radius queried
                           # (formation_detection_radius = 100). A radius-R query
                           # then touches a (2*ceil(R/CELL)+1)^2 block of cells.

var _zombie_cells: Dictionary = {}   # Vector2i -> Array[Unit]
var _human_cells: Dictionary = {}

func _ready() -> void:
    process_priority = -1000   # rebuild BEFORE any Unit._physics_process this frame

func _physics_process(_delta: float) -> void:
    _rebuild()

func _rebuild() -> void:
    _zombie_cells.clear()
    _human_cells.clear()
    var gm := get_parent() as GameManager
    for z in gm.all_zombies:
        if is_instance_valid(z):
            _insert(_zombie_cells, z)
    for h in gm.all_humans:
        if is_instance_valid(h):
            _insert(_human_cells, h)

func _insert(cells: Dictionary, u: Unit) -> void:
    var key := _cell_of(u.global_position)
    if not cells.has(key):
        cells[key] = []
    cells[key].append(u)

func _cell_of(p: Vector2) -> Vector2i:
    return Vector2i(floori(p.x / CELL_SIZE), floori(p.y / CELL_SIZE))

# Returns same-team units within `radius` of `center`, EXCLUDING `self_unit`
# and dead units (current_health <= 0). Caller still does any extra filtering.
func query(center: Vector2, radius: float, zombies: bool, self_unit: Unit) -> Array:
    var cells := _zombie_cells if zombies else _human_cells
    var ring := int(ceil(radius / CELL_SIZE))
    var base := _cell_of(center)
    var r2 := radius * radius
    var out: Array = []
    for dx in range(-ring, ring + 1):
        for dy in range(-ring, ring + 1):
            var bucket = cells.get(Vector2i(base.x + dx, base.y + dy))
            if bucket == null:
                continue
            for u in bucket:
                if u == self_unit:
                    continue
                if (u as Unit).current_health <= 0:   # corpse-linger skip
                    continue
                if center.distance_squared_to(u.global_position) <= r2:
                    out.append(u)
    return out
```

**Why this design:**
- One rebuild/frame at `process_priority = -1000` guarantees the grid is current
  before any unit queries it. Start-of-frame positions are fine for flocking
  (the old code was already approximate).
- `CELL_SIZE = 100` means the largest current query (alignment, radius 100) reads
  a 3×3 block; separation (radius ≤ 45) also reads 3×3. `ring` generalises it if a
  larger radius is ever queried, so it can't silently miss neighbours.
- Built from `GameManager.all_zombies/all_humans` (already maintained) — not a
  fresh group scan.

**Exact changes to `unit.gd`:**
- Cache a reference: `@onready var _grid: UnitGrid = get_tree().get_first_node_in_group("unit_grid")` (put `UnitGrid` in group `"unit_grid"`), or fetch via `GameManager`.
- `apply_separation_force()`: keep the melee-attacker early return; replace
  `get_nodes_in_group(...)` + loop with
  `var neighbours := _grid.query(global_position, separation_radius, is_zombie(), self)`
  then the existing repulsion math over `neighbours` (now already self/dead-filtered).
  **Switch all `position` reads in this function to `global_position`.**
- `find_nearby_allies(radius)`: replace its body with
  `return _grid.query(global_position, radius, is_zombie(), self)`. (Return type
  becomes `Array`; adjust callers/typing, or keep `Array[Unit]` by typing the
  query buffer.)

**Preserve (invariants):** dead-unit skip (done in `query`); melee-attacker
early-return (keep in `apply_separation_force`); `global_position` switch; behaviour
identical at low counts.

**Acceptance:**
- At 11 units: flocking/separation visually identical to pre-change.
- At 200+ units (Spec 0 scene): physics frame time drops substantially vs baseline;
  FPS curve flattens. No unit clips through walls (separation still uses
  `move_and_collide`).
- `grep` confirms no `get_nodes_in_group` remains inside `unit.gd`'s flocking path.

---

## Spec 2 — Decouple the base class from `Zombie` (do while in `unit.gd`)

**Goal:** remove `Unit`'s references to its own subclass so the base compiles and
reasons standalone (also a prerequisite for clean 3D migration). Small refactor;
fold into the Spec 1 pass since it touches the same functions.

**Current code:** `apply_separation_force` does `var zombie := self as Zombie; if zombie.is_melee_attacker: return`; `apply_alignment_force` reads `Zombie.facing_direction` and is zombie-only.

**Design — virtual hooks, default no-op in `Unit`, overridden in `Zombie`:**
```gdscript
# unit.gd
func _skip_separation() -> bool: return false          # Zombie overrides
func _apply_alignment() -> void: pass                   # Zombie overrides
```
- In `unit.gd` `apply_separation_force`, replace the `self as Zombie` block with
  `if _skip_separation(): return`.
- Move the entire alignment body out of `unit.gd` into `zombie.gd` as the override
  of `_apply_alignment()`; `Unit._physics_process` just calls `_apply_alignment()`.
- `zombie.gd`: `func _skip_separation() -> bool: return is_melee_attacker` and
  `func _apply_alignment() -> void: <the moved alignment code>`.

**Preserve:** behaviour identical; alignment still zombie-only; melee skip intact.

**Acceptance:** `grep "as Zombie"` and `grep "Zombie\." ` return nothing in
`unit.gd`; flocking unchanged in play.

---

## Spec 3 — AI tick decoupling / LOD (decisions slow, movement smooth)

**Goal:** stop running every AI decision at 60 Hz. Run decisions at ~10–15 Hz,
staggered so units don't all tick the same frame; tick off-screen/idle units even
less. Movement (velocity, `move_and_slide`) stays at 60 Hz.

**Design:**
- `GameManager.spawn_*` assigns each unit an `ai_phase: int` from an incrementing
  counter (`ai_phase = _spawn_counter % AI_BUCKETS`). Manually-placed units get a
  phase in `register_manually_placed_units`.
- `const AI_BUCKETS := 5` → AI at 12 Hz. Helper on `Unit`:
```gdscript
func _should_tick_ai() -> bool:
    var period := AI_BUCKETS
    if _is_far_from_camera():     # LOD: distant units tick at half rate
        period *= 2
    return (Engine.get_physics_frames() + ai_phase) % period == 0
```
- `_is_far_from_camera()`: compare `global_position` to the camera (group
  `"camera"`) centre against a generous threshold (e.g. > 1.5× viewport). Engaged
  units (have `attack_target`/grappled) should NOT be down-rated — gate the LOD
  multiplier on "not engaged".
- **What moves to the gate vs stays per-frame:**
  - *Per frame (60 Hz):* applying `velocity`/`move_and_slide`, leap/grapple
    distance checks, the existing `human.gd` morale smoothing, facing lerp.
  - *Gated (`_should_tick_ai`):* `apply_separation_force`/`_apply_alignment`
    (flocking), zombie stuck-check and continuation scans, and any decision that
    re-targets. (`human.gd` detection is already gated at 0.3 s — leave it; just
    make sure it stays staggered.)
- When a gated decision sets a `velocity`/`target`, the per-frame movement keeps
  using that value between ticks, so motion stays smooth.

**Preserve:** no auto-pursuit; engaged units keep full responsiveness (don't LOD
them); determinism (phase offset is fixed per unit, not random per frame).

**Acceptance:** at 200+ units the per-frame cost drops again vs Spec 1 alone;
flocking still looks smooth (no visible stutter from the 12 Hz flocking tick);
engaged combat feels identical at low counts.

---

## Spec 4 — Gate the shooting scan + throttle navigation

**Goal:** stop the per-frame, per-armed-human full zombie scan + per-zombie
raycast, and stop re-pathing every frame.

**Shooting (`human.gd`):**
- Today `_update_shooting` calls `_acquire_shoot_target` every frame (full
  `get_nodes_in_group("zombies")` + raycast per zombie).
- Add `_shoot_scan_timer` (mirror `detection_timer`, interval ~0.15 s). Each frame:
  if a `shoot_target` is set and still valid + visible (**one** raycast to it via
  the existing LOS helper), keep it. Only when the timer elapses do a full
  re-acquire — and route the candidate scan through `UnitGrid.query` (Spec 1)
  within `weapon_range`, not a group scan.
- Net: per-frame cost per armed human drops from "scan all + N raycasts" to "≤1
  raycast", with a full re-scan ~7×/sec.

**Navigation (`zombie.gd` `handle_combat` / `move_to_target`):**
- Today `nav_agent.target_position = ...` is set every frame while pursuing.
- Store `_last_nav_target: Vector2`. Only re-assign `target_position` when the new
  target has moved more than a threshold (e.g. `> 16.0` px) from `_last_nav_target`,
  or every M ticks. Between updates, keep following the current path
  (`get_next_path_position`).

**Preserve:** target-loss-on-cone-exit behaviour (don't keep shooting something out
of view — the per-frame single raycast still validates current target); melee
gate; the human detection/cone-timer logic that reads vision counts.

**Acceptance:** armed humans behave identically at low counts (acquire, fire, drop
on LOS loss); at high counts the raycast count per frame is roughly
`armed_humans` (one per current target) instead of `armed_humans × zombies`;
nav profiler shows far fewer path recomputations.

---

## Spec 5 — Event-driven health bars + capped vision redraw (cleanup)

**Goal:** stop per-frame UI work that doesn't depend on per-frame state.

**Health bars (`unit.gd`):**
- Remove the `update_health_bar()` call from `_process` (it runs every frame even
  when health is unchanged). Call it only from `take_damage()` and once in
  `_ready()`. The bar already hides itself at full health.
- Keep the `attack_timer` countdown in `_process` (it is genuinely per-frame).

**Vision redraw (`vision_renderer.gd`):**
- Today `_process` calls `queue_redraw()` unconditionally. This is **not** the
  bottleneck (normal play only draws the pinned/tunnel cones), so keep it light:
  cap redraw to ~30 Hz (redraw every other frame) rather than restructuring. Only
  worth doing after Specs 1–4; do not over-invest here.

**Preserve:** health bar still updates the instant a unit is damaged; cones/facing
lines still track moving units acceptably at 30 Hz.

**Acceptance:** health bars visually correct on damage; `_process` per-unit cost
drops; vision overlay still readable.

---

## Per-task ticket template (use for each spec when you execute it)

```
## Ticket: <spec name>            (Master Roadmap Stage C, item N)
Scope:           what changes / what does NOT.
Files+funcs:     exact paths + current signatures (re-grep first — lines drift).
Approach:        from the spec above, adapted to current code.
Invariants:      which "invariants under optimisation" this risks + how each is kept.
Steps:           ordered edits.
Acceptance:      the spec's pass criteria + the low-count regression check.
Test:            benchmark scene numbers (before/after) + sandbox behaviour check.
Rollback:        revert plan.
```

---

## Order of execution (from the Master Roadmap)

Spec 0 (benchmark) → Spec 1 (grid) → Spec 2 (decouple base) → Spec 3 (LOD tick)
→ Spec 4 (shooting + nav) → Spec 5 (UI). Specs 1–4 land **before** the validation
slice, because that slice is played at 150–500 units. Spec 5 is low-risk cleanup
that can ride along any time.
