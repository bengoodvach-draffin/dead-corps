# Dead Corps — Implementer Guide

**Purpose:** a durable, task-agnostic reference for *anyone executing changes* on
this codebase — Ben, a high-capability model, or a lower-capability model handed a
well-specified ticket. It collects the invariants that must not break, the
verification workflow (there is no automated test suite), and the engine gotchas
that have actually bitten this project.

This is the **how-to-execute** companion to:
- `CLAUDE.md` — working rules, design pillars, architecture-at-a-glance (read first).
- `docs/CODEBASE_REVIEW.md` — the audit + Master Roadmap + per-stage plan.
- `docs/PROJECT_CONTEXT.md` — technical state, per-script table, known issues.
- `docs/GAME_DESIGN_DOCUMENT.md` — design intent and decision log.

Unlike the roadmap, this guide is meant to stay stable across versions — it
describes *rules and process*, not specific tasks. Line numbers cited are
v0.27.0 snapshots and will drift; treat them as pointers, not addresses.

---

## 1. How to work (non-negotiable process)

These come from `CLAUDE.md`; they are repeated here because they gate execution,
not just design.

1. **Propose before implementing.** Discuss the approach, get explicit approval,
   *then* write code. Lead with a recommendation + reasoning, not a menu.
2. **Root cause before fix.** For an unclear bug, give a diagnosis + hypothesis
   before writing a fix. Prefer adding debug logging to confirm over guessing.
3. **One feature at a time.** Incremental, independently testable changes. If
   asked for several, sequence them and recommend an order.
4. **Backwards compatibility.** Don't break existing levels/scenes. New per-unit
   behaviour follows the optional-array pattern (empty array = old behaviour).
5. **Version discipline.** `MAJOR.MINOR.PATCH`. MINOR = new feature/system,
   PATCH = bug fix. Logging-only / trivial changes don't earn a version bump.
6. **Ben commits to git himself** (in the normal local workflow — the review
   gate is intentional). In the remote/container workflow, work may be committed
   to a feature branch so it isn't lost, but it still lands behind Ben's review.
7. **Check before creating files.** Grep / read the filesystem before adding a
   script or scene so you don't shadow an existing one. Never reuse an existing
   class/filename (`game_manager.gd` was once overwritten — do not repeat).
8. **Print clear test cases** after each step so behaviour can be verified.
9. **Hold documentation updates** (GDD / PROJECT_CONTEXT / specs) until Ben
   signals — doc sync is deliberate, not automatic.

Pushback is expected. If a request conflicts with a pillar or an earlier
decision, say so directly.

---

## 2. Invariants that must NOT break

Each of these is a real coupling in the live code. Breaking one produces a subtle
gameplay or correctness bug that manual play may not immediately surface.

### Gameplay / simulation invariants
- **Corpse-linger filtering.** A unit's `current_health` hits 0 the instant it's
  shot, but it lingers ~0.3 s before `queue_free()`. Dead units
  (`current_health <= 0`) **must stay excluded** from BOID separation and from
  targeting/melee scans during that window (`unit.gd` `apply_separation_force`).
  If you build a spatial index, replicate this skip — otherwise the living get
  pushed by, and pile up behind, corpses.
- **The melee gate is decoupled from the targeting count.** The live 2-attacker
  cap reads `human.count_melee_attackers()` (zombies *actually meleeing*), **not**
  `attacker_count` (total zombies *targeting*). Any number may pursue; only 2 hold
  melee slots and rotate in as front-rank attackers die. Do **not** merge these
  two counters.
- **`global_position` for ALL cross-unit math.** Nested scenes (notably escape
  zones, and the runtime `units_parent`) break local `position`. The base class
  currently violates this in places — do not propagate the violation into new code.
- **Player agency is preserved.** No auto-pursuit; engagements are right-click
  initiated. Do not add behaviour that takes control from the player (auto-pursuit
  was removed in v0.25.0 for exactly this reason).
- **Morale drain benefits the player** — it is a reward signal, never a punishment.
- **Deterministic primary responses.** Primary per-class stress responses are
  deterministic; only small-percentage secondaries are random. Randomness in
  *timing* (panic) is fine; randomness in *what happens* is not.
- **Special-zombie subclass pattern.** Subclasses set `is_special = true` in
  `_ready()` *before* `super._ready()`; never redeclare `is_special`.

### Engine / code invariants
- **Special-zombie checks use property duck typing** — `zombie.get("is_costumed")`,
  not `class_name`/`is` checks — to avoid GDScript cyclic-load parse errors.
  Same for `"spawn_corpse_on_death" in unit` style checks.
- **`@tool` scripts must guard game logic** with `if Engine.is_editor_hint()`.
  Units must not run AI in the editor.
- **Navigation layer matching.** `NavigationRegion2D` and `NavigationAgent2D`
  must share a layer (both Layer 1). Zombie agents have
  `avoidance_enabled = false`, so a runtime `NavigationObstacle2D` has no effect
  until avoidance is enabled (a known issue).
- **Bulk-commenting prints is dangerous.** Partially commenting a multi-line
  `print(...)` can leave an empty block body → parse error. After any bulk
  comment-out, scan for empty blocks.
- **`game_manager.gd` is the core coordinator — never rename or replace it.**
  Found via group `"game_manager"`.

### Hot-path / scaling invariants (relevant to the scaling work)
- **Don't add un-throttled per-frame scene-tree scans.** `get_nodes_in_group` in
  `_process`/`_physics_process` is the existing performance trap. New per-frame
  neighbour queries must go through the (planned) spatial index, not a fresh
  group scan. Heavy AI decisions should be gated on a timer (the 0.3 s
  `detection_timer` in `human.gd` is the model to follow).
- **Movement stays at 60 Hz; AI *decisions* may run slower.** If you add LOD
  ticking, keep velocity/movement smooth and only down-rate decision logic.
- **No debug `print()` in hot paths** without an `OS.is_debug_build()` / debug-flag
  guard — especially ones that build strings (`snapped(rad_to_deg(...))`).

---

## 3. Verification workflow (no automated test suite)

Testing is manual play + debug-print output. Every change ships with explicit,
runnable test steps.

- **Run the game:** open in Godot 4.6, run `scenes/main.tscn` with **F5**.
- **Debug overlay:** **F1** toggles it (live counts + reset).
- **Vision debug:** **V** shows all human vision cones at once.
- **Focused testing:** `scenes/sandbox_level_1.tscn`,
  `scenes/sandbox_level_human_testing.tscn`, `scenes/puzzle_test_1.tscn`.
- **Hand-built levels:** uncheck **Enabled** on the `Initializer` node (otherwise
  it auto-spawns the test scenario), then place units/buildings/escape zones.
- **The one automated gate** (once Stage A lands): `gdlint scripts/` +
  `godot --headless --check-only` (or a project import) — this catches parse
  errors, including the empty-block class above. This is the safety net that
  makes lower-capability execution viable; run it before declaring a task done.
- **Debug print legend:** 🔍 debug · ✅ success · ❌ error · ⚠️ warning ·
  ⏸️ paused · ⏱️ timer.

### Writing test cases (do this for every task)
State, in plain steps: which scene to open, what to do, and the *expected*
observable result (counts, on-screen behaviour, specific debug lines). Example
shape:
> 1. Open `sandbox_level_human_testing.tscn`, F5.
> 2. Right-click a zombie group onto the lone GI.
> 3. Expect: at most 2 zombies in melee at once (`X/2 melee attackers` prints);
>    others queue and rotate in as front-rank zombies die. No unit clips through
>    the wall. FPS stays at 60.

---

## 4. Per-task ticket template

Write a ticket against **current** code immediately before executing a task — not
all of them up front (line numbers and designs drift). Each ticket contains:

```
## Ticket: <short title>           (maps to Master Roadmap stage/item)

Scope:           one sentence — what changes, what does NOT.
Files/functions: exact paths + current signatures to touch.
Approach:        the precise change — data structures, where it's called from,
                 how existing behaviour is preserved.
Invariants touched: which §2 items this risks; how each is kept intact.
Steps:           ordered edits.
Acceptance:      observable pass criteria.
Test steps:      scene + actions + expected result (see §3).
Rollback:        how to revert if it regresses.
```

---

## 5. Division of labour (incl. lower-capability models)

This project is **design-led and propose-first**, which shapes who does what:

- **Design, ticket-writing, and review → Ben or a high-capability model.** The
  "propose / push back / judge against the pillars" step (rules 1–3 above) needs
  judgement a smaller model is weak at. Do not delegate open-ended design or
  vague "make it faster / better" tasks to a cheaper model.
- **Execution of well-specified, low-judgement tickets → fine for a cheaper
  model.** Good fits: the Stage A mechanical work (`.gitignore`, lint/CI setup,
  dead-code deletion, naming layers), applying an algorithm that's fully spec'd in
  the ticket, and mechanical refactors with a clear acceptance test.
- **Always, regardless of model:** follow the ticket, preserve the §2 invariants,
  run the §3 verification, and print test steps. A change that can't state its
  expected observable result isn't ready.

---

## 6. Engine quick-reference

- Engine: **Godot 4.6 / GDScript**. Type hints everywhere
  (`var d: float`); explicit nullability (`var t: Node2D = null`). Comments
  explain *why*, not *what*.
- Perspective: 2D isometric today; full **3D migration** is the confirmed next
  architectural direction. Game logic is meant to survive intact; camera, vision
  renderer, and scene files get rewritten. Prefer designs that separate
  simulation data from presentation (see CODEBASE_REVIEW "3D Migration Impact").
- **Waypoint ordering uses `naturalnocasecmp_to()`** so `Waypoint2` sorts before
  `Waypoint10`.
- Inter-class wiring today is mostly group lookups (`"zombies"`, `"humans"`,
  `"game_manager"`, `"selection_manager"`, `"buildings"`, `"nav_obstacle"`,
  `"escape_zone"`) + a shallow signal layer. The single autoload is `WorldBounds`.
