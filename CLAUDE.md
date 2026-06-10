# Dead Corps — Claude Code Project Memory

**Current version:** v0.28.0 · **Engine:** Godot 4.6 / GDScript · **Perspective:** 2D isometric (full 3D migration confirmed as next architectural direction)

This file is loaded into every Claude Code session. It is the lean orchestrator: working rules, design pillars, and pointers. Detailed reference lives in `docs/` and is read on demand — do not assume those files are in context until you've read them.

---

## What Dead Corps is

A real-time tactical puzzle game that inverts the zombie genre: the player commands a growing zombie horde against AI-controlled human defenders. The player is the apocalypse, not the survivor. Design lineage: Commandos / Shadow Tactics (tactical positioning, timing, handcrafted puzzles) and Hotline Miami (fast, iterative, score-attack pacing). Solo portfolio/learning project; community level editor is a long-term post-launch goal.

---

## Design pillars (gate every suggestion against these)

- **The player is the threat defenders react to** — not an agent navigating their patterns. Defenders respond to the horde; the player drives the encounter.
- **Predictability over simulation.** Puzzle depth comes from handcrafted level design, not from AI complexity. Enemy predictability is a prerequisite, not a weakness. Before proposing any new system, audit whether it creates a *meaningful player decision* or just adds friction — if the latter, say so and recommend against it.
- **Player agency is preserved.** Reject any solution that takes control away from the player (this is why auto-pursuit was removed in v0.25.0).
- **Morale drain benefits the player** — it is a reward signal, never a punishment mechanic.
- **Deterministic primary responses.** Randomness in *when* something happens (panic timing) is good and emergent; randomness in *what* happens is frustrating. Primary stress responses per class are deterministic; only small-percentage secondaries are random.
- **Scope control.** The validation slice comes before further system elaboration. Resist feature accumulation that hasn't been validated in play.

---

## How to work with Ben

These are firm. The first one has been a real pain point — do not skip it.

1. **Propose before implementing.** Discuss the approach, get explicit approval, *then* write code. Lead with a recommendation and reasoning, not a menu of options. Sessions are design-led: spec first, then implementation.
2. **Root cause before fix.** For any unclear bug, give a diagnosis and hypothesis before writing a fix. Prefer adding debug logging to confirm the cause over guessing.
3. **One feature at a time.** Incremental, independently testable changes. If asked for several related features, sequence them and recommend an order.
4. **Backwards compatibility.** Don't break existing levels/scenes/setups. New per-unit behaviour follows the optional-array pattern (empty = old behaviour unchanged).
5. **Version discipline.** `MAJOR.MINOR.PATCH`. MINOR = new feature/system, PATCH = bug fix only. Bumps must reflect genuine scope — logging-only or trivial fixes do not earn their own minor version.
6. **Ben commits to git himself.** Make the edits in place; do **not** run `git commit` or `git push`. He reviews diffs and commits manually — that review gate is intentional.
7. **Check before creating files.** Read the filesystem / grep before adding a new script or scene so you don't duplicate or shadow an existing one. `game_manager.gd` was once accidentally overwritten — never reuse an existing class/filename.
8. **Print clear test cases** after each implementation step so Ben can verify behaviour.
9. **Hold documentation updates.** Don't update the GDD, PROJECT_CONTEXT, or specs until Ben signals it's time. Doc sync is deliberate, not automatic.

Pushback is expected and welcome — if a request conflicts with the pillars or an earlier decision, say so directly.

---

## Repo layout

```
project.godot              # Godot 4.6 project; main scene set via UID
scripts/                   # all GDScript
scenes/                    # all .tscn (units, levels, overlays)
audio/                     # audio assets (system in progress, not yet doc-synced)
docs/
  GAME_DESIGN_DOCUMENT.md  # design intent, all 11 zombie types, 5 defender classes, level philosophy, decision log
  PROJECT_CONTEXT.md       # technical state, scripts purpose table, KNOWN ISSUES, quick-reference values
  HUMAN_DEFENDER_SYSTEM_SPEC.md
  archive/                 # superseded GDD versions, changelogs, historical notes — reference only, do not act on
```

**Read `docs/GAME_DESIGN_DOCUMENT.md` for any design question.** **Read `docs/PROJECT_CONTEXT.md` for technical state, the per-script purpose table, and the current known-issues list** before diagnosing bugs or adding to a system.

---

## Architecture at a glance

- `unit.gd` (`Unit` extends `CharacterBody2D`) — base for all units: movement, combat, health, selection, BOID separation/alignment, world-bound clamping. Cohesion force is disabled (commented out). Separation moves via `move_and_collide` (not raw `position +=`) so a corner pile-up can't shove a unit through a wall, and skips dead neighbours (`current_health <= 0`) so a freshly-shot unit stops pushing the living during its corpse linger.
- `zombie.gd` (`Zombie` extends `Unit`) — player-controlled. States IDLE/MOVING/PURSUING/LEAPING/MELEE/DEAD. No auto-pursuit; all engagements are right-click initiated. `can_receive_command()` is false while LEAPING or committed. Post-kill 250px LOS continuation scan. Melee is capped at 2 attackers per human, gated live on `human.count_melee_attackers()` (actual meleeing zombies) — *not* on `attacker_count` (total targeting), so any number may pursue and rotate into a freed slot when a front-rank attacker dies.
- `human.gd` (`Human` extends `Unit`) — AI defenders. States IDLE/SENTRY/FLEEING/GRAPPLED/DEAD/TUNNEL_VISION. `DefenderClass` enum (CIVILIAN/MILITIA/POLICE/GI/SPEC_OPS), morale bar, shooting, dual-zone vision arcs, low/high-urgency alert system, patrol (LOOP/PING_PONG) with Phase C per-waypoint behaviour, formation squads. Uses `@tool` for editor visuals.
- `game_manager.gd` (`GameManager`) — **core coordinator, do NOT rename or replace.** Tracks units, spawning, conversion-after-incubation, win/loss. Found via group `"game_manager"`.
- `selection_manager.gd` — selection + right-click group engagement. `_resolve_group_engagement()` spreads selected zombies across the human group within 150px (greedy, 2 per human for the first wave); **overflow zombies now attack the nearest human in the group** rather than getting a dead-end move order, so a horde keeps engaging as the front rank dies. The 2-at-a-time limit is enforced live downstream by the melee gate, not as a one-shot assignment cap.
- `camera_controller.gd`, `vision_renderer.gd`, `world_bounds.gd` (autoload `WorldBounds`), `level_bounds.gd`, `building.gd`, `escape_zone.gd`, `initializer.gd`, overlays.
- Level-geometry & nav tooling (v0.26.0): `wall.gd` (`Wall` extends `Polygon2D`) — mouse-editable polygon walls added via Add Child Node → "Wall", `perimeter` (hollow, edges-only collision + thick outline) or `solid` (filled) via the `solid` toggle. Independent per placement (no scene-instance propagation); generates a hidden, non-serialized `StaticBody2D`/collision/`Line2D` as internal children. `nav_baker.gd` (`NavBaker` extends `NavigationRegion2D`) — auto-bakes the nav mesh at runtime (+ editor "Bake preview" button) from `LevelBounds` + obstacle `get_nav_footprint()`; no hand-authored coordinates, no manual re-bake. Both `Building` and `Wall` report footprints so exclusion is deterministic.
- Special zombies: `fat_zombie.gd` (gunshot-only death → spawns `fat_zombie_corpse.gd` blocking obstacle) and `costume_zombie.gd` (undetectable until it pins a human, then permanently reverts). Pattern: subclasses set `is_special = true` in `_ready()` *before* `super._ready()`; never redeclare `is_special`.

---

## GDScript / Godot conventions & gotchas

- Godot **4.6**. Type hints everywhere (`var distance: float`); explicit nullability (`var target: Node2D = null`). Comments explain *why*, not *what*.
- **Always use `global_position`** for cross-unit calculations — nested scenes break local `position` (notably escape zones).
- **Waypoint ordering uses `naturalnocasecmp_to()`** so `Waypoint2` sorts before `Waypoint10`.
- `@tool` scripts must guard game logic with `Engine.is_editor_hint()` — units must not run AI in the editor.
- Navigation: `NavigationRegion2D` and `NavigationAgent2D` layers must match (both Layer 1); use the "Groups" method (buildings in `"buildings"` group). Note: zombie agents have `avoidance_enabled = false`, so runtime `NavigationObstacle2D` has no effect yet (see known issues).
- **Special-zombie checks use property duck typing** — `zombie.get("is_costumed")` rather than class-name checks — to avoid GDScript load-order parse errors.
- **Bulk-commenting print statements is dangerous:** partially commenting a multi-line `print(...)` can leave an empty block body and a parse error. Scan for empty blocks after any bulk comment-out.
- Debug print emoji legend: 🔍 debug · ✅ success · ❌ error · ⚠️ warning · ⏸️ paused · ⏱️ timer.

---

## Running & testing

- Open in Godot 4.6; run `scenes/main.tscn` with **F5**. **F1** toggles the debug overlay.
- Sandbox scenes for focused testing: `scenes/sandbox_level_1.tscn`, `scenes/sandbox_level_human_testing.tscn`.
- To hand-build a level, uncheck **Enabled** on the `Initializer` node (otherwise it auto-spawns the test scenario), then place units/buildings/escape zones from `scenes/`.
- There is **no automated test suite** — testing is manual play sessions plus debug-print output. After implementing, print explicit test steps for Ben to run.

---

## Current focus

**Validation slice (the actual next work):** build one handcrafted level — Costume Zombie + Fat Zombie vs Police + a barricaded GI — and run focused play sessions to confirm the core puzzle loop is fun *before* adding more systems. Systems exist but haven't been meaningfully playtested together.

After that: full 3D migration (low-poly geometry, simple 3D characters, rotatable isometric camera; driven by rooftop traversal and urban occlusion). Game logic — state machines, morale, combat, patrol, formations — survives intact; camera, vision renderer, and all scene files get rewritten.

Open known issues to keep in mind (full list in PROJECT_CONTEXT.md): Fat Zombie corpse navigation avoidance is deferred; morale/weapon kill counts run higher than spec and await playtest tuning; the broken-disguise Costume Zombie scoring edge case (25 vs 100 pts) is undecided.
