# Dead Corps — Claude Code Project Memory

**Current version:** v0.30.0 · **Engine:** Godot 4.6 / GDScript · **Perspective:** 2D isometric (full 3D migration still confirmed, but now waits behind the v2 pivot PoC)

This file is loaded into every Claude Code session. It is the lean orchestrator: working rules, design pillars, and pointers. Detailed reference lives in `docs/` and is read on demand — do not assume those files are in context until you've read them.

---

## ⚠️ Active direction: the V2 Predator Pivot (June 2026)

**Read `docs/V2_DIRECTION_SPEC.md` before any design or core-loop work.** Playtesting found v1 played like "ninja commando zombies" — a stealth-puzzle game — while the single most engaging moment was watching a wave get thinned by gunfire. The v2 spec rebuilds the core loop around predation: **bodies are ammunition, detection is a cost not a fail state, and the player corrals/releases/combo-routes a frenzied horde.** Stealth grammar (vision cones, facing, swing arcs, alerts, morale psychology) is removed.

Status: **design locked pending PoC validation.** It supersedes the core-loop sections of the GDD (the GDD is deliberately NOT updated until the PoC validates — its sections 3, 6, and parts of 11 no longer reflect design intent). The codebase is still v1 — the deprecation audit in spec §11 lists what dies, what survives, and which files take major work.

---

## What Dead Corps is

A real-time tactical **predation** game that inverts the zombie genre: the player commands a growing zombie horde against AI-controlled human defenders. The player is the apocalypse, not the survivor. The puzzle is attrition math and chase geometry, executed at speed — losses are spending, not failure. Design lineage: Hotline Miami (fast, iterative, score-attack pacing) over the original Commandos / Shadow Tactics stealth framing, which the v2 pivot retired. Solo portfolio/learning project; community level editor is a long-term post-launch goal.

---

## Design pillars (gate every suggestion against these — v2, from the pivot spec)

- **Attrition is currency.** Losses are spending, not failure. Every wall has a body price.
- **Setup is 1/3 of the game; the chase and the combo are 2/3.** Favor pursuit and momentum over planning and positioning.
- **Command the calm, influence the storm.** The reserve is fully controllable; released zombies are not. Released is released — no recall, ever.
- **Bias, not command.** Influence on ferals reorders their choices; it never moves a unit anywhere prey isn't.
- **The frenzy chases what moves; what's frozen waits for deliberate collection.**
- **Determinism in rules, suspense in execution.** Identical inputs produce identical runs — no live RNG anywhere (spec §10). Randomness in *what* happens is frustrating; suspense comes from execution, not dice.
- **The frenzy ends when nothing in the encounter is left alive or everything has escaped.**

Carried over from v1 and still firm: **player agency is preserved** (reject anything that takes control away — released-is-released is a deliberate spend, not lost control), **predictability over simulation** (audit every proposed system for whether it creates a *meaningful player decision* or just friction — if friction, say so and recommend against it), and **scope control** (the PoC slice comes before any further elaboration; the spec's Parked Register is parked for a reason).

Superseded by the pivot: "morale drain benefits the player" — the morale system is dead in v2, replaced by fill + fear radius.

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
  V2_DIRECTION_SPEC.md     # THE PREDATOR PIVOT — authoritative core-loop design; supersedes GDD §3/§6/parts of §11
  V2_POC_BUILD_PLAN.md     # the agreed phased implementation order for this branch (v2-poc)
  V2_IMPLEMENTER_GUIDE.md  # invariants checklist, delegation map, ticket discipline — read before executing any build-plan step
  ARCHITECTURE_GUIDELINES.md # anti-god-class rules — read before creating or substantially extending any script
  GAME_DESIGN_DOCUMENT.md  # v1 design intent, all 11 zombie types, 5 defender classes, level philosophy, decision log
  PROJECT_CONTEXT.md       # technical state, scripts purpose table, KNOWN ISSUES, quick-reference values
  Archive/                 # superseded docs (incl. the v1 defender spec, v1 implementer guide, legacy nav/patrol guides), old GDD versions, changelogs — reference only, do not act on
```

**Read `docs/V2_DIRECTION_SPEC.md` first for any core-loop design question** (zombie/human behavior, combat, scoring, controls, win/lose). The GDD remains the reference for what the pivot doesn't touch — level philosophy, the wider zombie roster, world/fiction — and for the decision log, but its core-loop sections are superseded and not yet rewritten. **Read `docs/PROJECT_CONTEXT.md` for technical state, the per-script purpose table, and the current known-issues list** before diagnosing bugs or adding to a system.

---

## Architecture at a glance

This describes the codebase **as it exists today (v1 systems)** — it is the accurate starting point for the PoC work. Spec §11 maps each system below to its v2 fate (dead / replaced / survives) and lists the files taking major work: `human.gd` (behavior-core rewrite), `zombie.gd` (feral states + pounce), `vision_renderer.gd` (rewrite), `selection_manager.gd` (release/Mark/inspect), `game_manager.gd` (rise pipeline, win/lose, score), `escape_zone.gd` (boundary), `unit.gd` (speeds, determinism), plus a NEW `level_config.gd`.

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
- **On `v2-poc`: `docs/ARCHITECTURE_GUIDELINES.md` governs all new/rebuilt scripts** (component ownership, ~400-line/~40-line tripwires, dispatcher `_physics_process`, signals-up-calls-down, registry-only discovery). `docs/V2_IMPLEMENTER_GUIDE.md` has the invariants checklist for any build-plan work.
- **Always use `global_position`** for cross-unit calculations — nested scenes break local `position` (notably escape zones).
- **Waypoint ordering uses `naturalnocasecmp_to()`** so `Waypoint2` sorts before `Waypoint10`.
- `@tool` scripts must guard game logic with `Engine.is_editor_hint()` — units must not run AI in the editor.
- Navigation: `NavigationRegion2D` and `NavigationAgent2D` layers must match (both Layer 1); use the "Groups" method (buildings in `"buildings"` group). Note: zombie agents have `avoidance_enabled = false`, so runtime `NavigationObstacle2D` has no effect yet (see known issues).
- **Special-zombie checks use property duck typing** — `zombie.get("is_costumed")` rather than class-name checks — to avoid GDScript load-order parse errors.
- **Bulk-commenting print statements is dangerous:** partially commenting a multi-line `print(...)` can leave an empty block body and a parse error. Scan for empty blocks after any bulk comment-out.
- **A NEW `class_name` script created outside the editor won't resolve until the project's global-class cache is regenerated.** The cache (`.godot/global_script_class_cache.cfg`, gitignored) is only rebuilt on an editor scan/import — so a fresh `class_name Foo` file made via the file tools fails *both* `tools/check.ps1` (parse error pinned on a *consumer* script, e.g. "Identifier Foo not declared") *and* runtime, until you regenerate it. Fix: run `<godot> --headless --import --path .` once (or open the editor). Do this immediately after creating any new global-class script, before the parse gate. Autoloads have the same staleness but resolve by their autoload name, not this cache.
- Debug print emoji legend: 🔍 debug · ✅ success · ❌ error · ⚠️ warning · ⏸️ paused · ⏱️ timer.

---

## Running & testing

- Open in Godot 4.6; run `scenes/main.tscn` with **F5**. **F1** toggles the debug overlay.
- Sandbox scenes for focused testing: `scenes/sandbox_level_1.tscn`, `scenes/sandbox_level_human_testing.tscn`.
- To hand-build a level, uncheck **Enabled** on the `Initializer` node (otherwise it auto-spawns the test scenario), then place units/buildings/escape zones from `scenes/`.
- There is **no automated test suite** — testing is manual play sessions plus debug-print output. After implementing, print explicit test steps for Ben to run.
- **Godot MCP (`mcp__godot__*`) — Claude can boot a scene and read its console itself.** `run_project` (with `scene: "res://scenes/<name>.tscn"`) → `get_debug_output` (stdout prints + stderr warnings/errors) → `stop_project`. Use this to self-verify anything observable from a fresh boot: autoload load, print values, registration counts, runtime errors, and the §10 **determinism spot-check** (boot a scripted scenario twice, diff the logs). **Limit:** there is no input-injection tool — Claude cannot click/select/drag, so anything needing live input (release a horde, issue a move order) still needs Ben at the keyboard. "Boot + observe," not "play." It does **not** replace the parse gate below — run that first.
- **Parse-error gate (run after any `.gd` edit, before telling Ben it's done):**
  `powershell -ExecutionPolicy Bypass -File tools/check.ps1`. It headlessly compiles
  every script and **hard-fails on any GDScript parse error** — catches the
  partial-comment / empty-block trap noted above, which gdlint does *not*. gdlint
  style findings are advisory only. Claude should run this itself when changing
  scripts (Ben will forget); see `tools/README.md`. Needs Godot on `GODOT_BIN` or the
  default path. This is the project's only automated safety net.

---

## Current focus

**The v2 PoC validation slice** (spec §12) — built 2D-first in the current codebase. Roster: Civilian, Militia, Police, GI. **No specials** (Fat/Costume code paths excluded from PoC; re-audit post-validation), no Spec Ops, no pressure systems. Milestones: **M1** — core loop without the Mark; **M2** — add the Mark + LMB fill-line inspect. First tuning job after the slice runs: the **sacred-ratio sweep** (fill speed vs zombie speed) until a GI position kills ~3–4 of a charging wave. The spec's seven validation questions (§12) are the verdict criteria on the pivot. Next step per the spec: PoC build plan / implementation sequencing — propose-before-implementing applies as always.

After the pivot validates: full 3D migration (low-poly geometry, simple 3D characters, rotatable isometric camera; driven by rooftop traversal and urban occlusion) — it inherits the v2 simplification, so there's far less to port.

The old v1 validation slice (Costume + Fat Zombie vs Police + barricaded GI) is superseded — it was played, and its findings are what produced the pivot. Several v1 known issues (morale/weapon kill-count tuning, Costume scoring edge case) are mooted by the pivot; the full annotated list lives in PROJECT_CONTEXT.md.
