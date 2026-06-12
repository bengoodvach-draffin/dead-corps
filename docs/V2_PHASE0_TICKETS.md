# V2 PoC — Phase 0 Tickets (foundations)

**Written:** June 12, 2026, against `v2-poc` @ `c660681` (v0.28.0 code). Line
numbers and signatures were re-grepped at writing time; if commits have landed
since, re-verify them before editing.
**Read first:** `CLAUDE.md`, then `V2_IMPLEMENTER_GUIDE.md` (invariants
checklist + verification recipe), then `ARCHITECTURE_GUIDELINES.md`.
**Execution order:** 0.1 → 0.2 → 0.3, one ticket per session/commit, parse gate
(`tools/check.ps1`) after each. All three are delegation-map "Yes" rows.
All three are **additive** — v1 gameplay must be byte-for-byte unchanged after
each ticket (nothing reads the new code yet, except the 0.3 jitter swap).
**Version:** when all three land, bump to **v0.29.0** (one minor for Phase 0,
per the agreed branch versioning).

---

## Ticket 0.1 — `GameConfig` autoload + `LevelConfig` node

**Scope:** every spec-§9 knob readable from one place, with v0.1 defaults
always present and optional per-level overrides. Nothing consumes the values
yet.

**Approach (decision baked in):** copy the proven `WorldBounds`/`LevelBounds`
pattern exactly — see `scripts/level_bounds.gd` (`@tool`, `class_name`, exports,
`_ready()` guarded by `Engine.is_editor_hint()`, writes into the autoload at
runtime, `push_error` if the autoload is missing). Chosen over group-lookup
discovery: zero per-frame discovery (ARCHITECTURE_GUIDELINES rule 8), defaults
work in scenes with no config node, pattern already exists in this codebase.

**Files:**
- NEW `scripts/game_config.gd` — autoload `GameConfig`, plain `extends Node`.
  One typed var per knob, initialised to the §9 v0.1 default (table below).
- NEW `scripts/level_config.gd` — `@tool`, `class_name LevelConfig`,
  `extends Node2D`. Mirrors every knob as `@export`; on `_ready()` (runtime
  only) writes all values into `GameConfig` and prints a ✅ confirmation.
- `project.godot` — add `GameConfig` to `[autoload]` (alongside `WorldBounds`).

**Knobs (var name = v0.1 default):**
```
zombie_speed = 200.0            human_flee_speed = 90.0
awareness = [400.0, 450.0, 450.0, 550.0]      # indexed CIV=0, MILITIA=1, POLICE=2, GI=3
fill_speed = [0.0, 250.0, 300.0, 450.0]       # CIV slot unused (reaction clock below)
fear_threshold = [0, 1, 2, 3]
civilian_reaction = 0.75
fear_radius = 250.0             fear_reaction = 0.3
contagion_radius = 150.0        chain_scan_radius = 250.0
pounce_range = 40.0             pounce_recovery = 1.0
rise_time = 2.5
cower_min_displacement = 40.0   cower_window = 1.2
combo_window = 4.0              burst_window = 1.5      kill_base = 10
release_cluster_radius = 300.0  mark_radius = 300.0
shamble_leash = 25.0            shamble_speed = 20.0
fill_decay_factor = 2.0         # × fill speed, only when no zombie visible
turn_speed = 360.0              facing_tolerance = 15.0   # degrees
failsafe_min_progress = 40.0    failsafe_window = 2.0
```
Per-class arrays are 4 entries (Civ/Militia/Police/GI — the PoC roster); the
v1 `DefenderClass` enum still has SPEC_OPS but no v1 code reads `GameConfig`,
and Phase 1.1 rebuilds the enum to these four. Document the index order in a
comment at the array declarations.

**Invariants touched:** every-§9-tunable-from-config (this ticket creates the
mechanism); `@tool` editor guard; check-before-creating-files (grep for name
collisions on `GameConfig`/`LevelConfig` before creating — none existed at
writing time).

**Steps:** write `game_config.gd` → register autoload in `project.godot` →
write `level_config.gd` → parse gate.

**Acceptance / manual test:**
1. `tools/check.ps1` green.
2. Boot `scenes/main.tscn` (no LevelConfig node anywhere): no errors; from the
   debug console or a temporary print, `GameConfig.pounce_range == 40.0`.
3. Add a `LevelConfig` node to `scenes/sandbox_level_1.tscn`, set
   `pounce_range = 99` in the Inspector, boot it: ✅ print fires and
   `GameConfig.pounce_range == 99.0`. Remove the test value (or the node)
   after verifying.
4. v1 gameplay unchanged (nothing reads the config yet).

**Rollback:** delete both new files + the `[autoload]` line.

---

## Ticket 0.2 — Unit registry: `unit_uid` + living/neighbour queries

**Scope:** stable per-unit IDs and deterministic, dead-excluding query helpers
on `GameManager`. Additive only — no existing caller migrates in this ticket
(BOID migration is build-plan step 1.3).

**Current code facts (re-verify):**
- `game_manager.gd:17-18` — `var all_zombies: Array[Zombie]` /
  `var all_humans: Array[Human]`.
- Registration paths: `spawn_zombie()` (`:51`) and `spawn_human()` (`:69`)
  append + wire signals; `register_manually_placed_units()` (`:247`) iterates
  `get_tree().get_nodes_in_group(...)` (scene-tree order → deterministic) and
  duplicates the same wiring.
- `get_all_zombies()` / `get_all_humans()` (`:220,:225`) lazily filter invalid
  refs in place — filtering preserves array order.
- `unit.gd` — `class_name Unit extends CharacterBody2D`; `current_health`
  declared `:111`, set in `_ready()` `:150`.

**Approach:**
- `unit.gd`: add `var unit_uid: int = -1` (one line, near `current_health`).
- `game_manager.gd`:
  - `var _next_unit_uid: int = 0`.
  - Private `_register_zombie(zombie: Zombie) -> void` /
    `_register_human(human: Human) -> void`: assign
    `unit.unit_uid = _next_unit_uid; _next_unit_uid += 1`, append to the
    array, wire the signals. Refactor `spawn_*()` and
    `register_manually_placed_units()` to call these — this *removes* the
    currently duplicated wiring rather than adding a third copy
    (ARCHITECTURE_GUIDELINES rule 1).
  - `living_zombies() -> Array[Zombie]` / `living_humans() -> Array[Human]`:
    valid + `current_health > 0`. (After demolition step 1.3 removes HP, the
    health check becomes the alive flag — the *contract* is "dead units are
    excluded", which is the v1 corpse-linger invariant carried into v2.)
  - `neighbours_within(pos: Vector2, radius: float, team: StringName,
    exclude: Unit = null) -> Array[Unit]` — `team` is `&"zombies"` or
    `&"humans"`; naive O(n) scan of the corresponding living array;
    `global_position.distance_to(pos) <= radius`; result order = array order.
- **Ordering contract (document in a comment on the API):** arrays are in
  `unit_uid` order by construction — uid is assigned in registration order,
  appends preserve it, and the lazy validity filtering preserves relative
  order. All v2 systems will iterate these results; never re-sort them by
  anything non-deterministic.

**Invariants touched:** stable unit ordering (§10); dead-unit exclusion;
`global_position` for cross-unit math; registry-only discovery (this ticket
creates the registry).

**Acceptance / manual test:**
1. Parse gate green.
2. Boot `main.tscn` (Initializer scenario): F1 overlay unit counts unchanged
   from before the ticket; play one engagement — combat, conversion, win/lose
   all behave as before.
3. Temporary print at registration (`uid=N name=X`): uids are sequential and
   cover both spawned and manually-placed units (boot a sandbox scene with
   hand-placed units to confirm the second path).
4. Determinism spot-check: boot the same scene twice — the uid→name mapping is
   identical both runs.
5. Temporary one-shot sanity print: `neighbours_within(some unit's position,
   200.0, &"zombies")` count matches a hand-count from the overlay.
   Remove temporary prints after verification.

**Rollback:** revert the two files; nothing else references the new API yet.

---

## Ticket 0.3 — `DetHash` utilities + live-RNG removal

**Scope:** the deterministic-jitter helper that idle shamble (2.1) and any
future organic variation must use, plus removal of the codebase's live RNG.

**Files:**
- NEW `scripts/det_hash.gd` — `class_name DetHash`, static funcs only
  (pure logic; no node needed per ARCHITECTURE_GUIDELINES rule 2):
  - `static func hash01(uid: int, salt: int) -> float` — `hash([uid, salt])`
    scaled to `[0, 1)`.
  - `static func angle(uid: int, salt: int) -> float` — `hash01(...) * TAU`.
  - `static func offset(uid: int, salt: int, max_radius: float) -> Vector2` —
    deterministic point in the disc (use two salts internally for angle vs
    radius so they don't correlate).
  - Comment the determinism scope: Godot's `hash()` is stable for a given
    build/platform — sufficient, since §10 promises identical *runs on the
    same machine*, not cross-platform replays.

**RNG audit results (full grep of `scripts/` at writing time — only two live
sites):**
1. `selection_manager.gd:449-450` — `randf_range(-15, 15)` jitter on group
   move-order destinations. **Replace in this ticket** (spec §10 names
   move-jitter explicitly): use
   `DetHash.offset(zombie.unit_uid, _move_order_counter, 15.0)`, where
   `_move_order_counter` is a new int on `SelectionManager`, incremented once
   per issued group order — successive orders still vary, identically every
   run.
2. `game_manager.gd:97-98` — `randf_range` conversion spawn offset.
   **Leave untouched.** The whole incubation pipeline dies in demolition step
   1.4 (risers rise exactly in place, no offset wanted). Removing it now is
   wasted motion; it's listed here so nobody "fixes" it separately.

**Invariants touched:** no-live-RNG (§10); stagger-by-identity.

**Acceptance / manual test:**
1. Parse gate green.
2. `grep -rn "randf\|randi\|randomize\|shuffle\|pick_random" scripts/` returns
   only `game_manager.gd:97-98`.
3. Boot a sandbox, select 4+ zombies, issue the same group move order from the
   same start (fresh boot ×2): printed destination points are identical across
   runs (temporary print, removed after), and zombies still spread out rather
   than stacking on one point.

**Rollback:** revert `selection_manager.gd`; delete `det_hash.gd`.

---

**After Phase 0:** bump to v0.29.0, then proceed to build-plan Phase 1
(demolition) — which requires fresh per-file tickets written against the
post-Phase-0 code. Do not reuse this document's line numbers for Phase 1.
