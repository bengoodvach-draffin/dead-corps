# Dead Corps — Claude Code Project Memory

**Current version:** v0.32.0 · **Engine:** Godot 4.6 / GDScript · **Perspective:** 2D isometric (full 3D migration still confirmed, but now waits behind the v2 pivot PoC)

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

This describes the codebase **as it exists now on `v2-poc` — Phase 1 demolition complete (v0.30.0)**. The v1 stealth systems (morale, alerts, vision cones, tunnel vision, HP/grapple melee, leap, the incubation pipeline, Spec Ops) are **gone**; what's here is the "dumb but bootable" sterile sandbox — units select/move/patrol, BOID separation, escape-zone boundary, **no combat yet**. The predation systems (feral, Pounce, fill front, fear/break, rout, combo, risers, the Mark) get built on this skeleton in build-plan Phases 2–7. The codebase is **fully RNG-free** (spec §10) and all neighbour/unit lookups go through the GameManager registry.

**Phase 0 foundations (the v2 substrate):**
- `game_config.gd` (autoload `GameConfig`) — single source of truth for every spec-§9 tunable, at v0.1 defaults. `level_config.gd` (`@tool LevelConfig`) optionally overrides per level. Nothing hardcodes a §9 number.
- Unit registry on `GameManager` — `unit_uid` (stable monotonic id per unit), `living_zombies()`/`living_humans()`/`neighbours_within(pos, radius, team, exclude)`, all returned in stable unit_uid order (§10). Every v2 radius query (contagion, fear, scan, seeding, shamble) reads these; never `get_nodes_in_group()` in per-frame code.
- `det_hash.gd` (`DetHash`, static) — deterministic per-unit jitter (`hash(unit_uid, salt)`), the only source of "random-looking" variation.

**Unit skeletons (Phase 1):**
- `unit.gd` (`Unit` extends `CharacterBody2D`) — base: movement to target, world-bound clamp, selection, control-group labels, BOID separation/alignment (registry-backed, **`global_position`**). No HP — liveness is `is_alive` (set by `die()`); `take_damage(amount, knockback)` is the **v2 binary kill entry** (one-shot, no health accumulation). Cohesion disabled; separation via `move_and_collide` (corner-safe), dead units excluded via the registry.
- `zombie.gd` (`Zombie` extends `Unit`) — player-controlled. States IDLE/MOVING/DEAD. Select + move only; `can_receive_command()` → true. Leap/melee/pursuit/continuation all deleted — reframed as FERAL + the Pounce, built in Phase 2.2+. `zombie_killed_human` signal kept (re-emitted by the Pounce). `is_special` flag for specials.
- `human.gd` (`Human` extends `Unit`, `@tool`) — AI defenders. States IDLE / SENTRY (now behaves as IDLE) / DEAD; patrol (LOOP/PING_PONG + waypoint pauses — facing/swing deleted); LOS helpers + `get_nearest_escape_zone()`; `defender_class` enum (CIVILIAN/MILITIA/POLICE/GI — indexes GameConfig's per-class arrays). Morale/alerts/vision/flee/shooting all gone — the v2 fill front + fear/break + rout are built in Phase 3. A killed human is a permanent corpse until risers (2.6).
- `game_manager.gd` (`GameManager`) — **core coordinator, do NOT rename or replace.** The unit registry (above), spawning, escape counting, win/lose. Found via group `"game_manager"`. Win/lose + `get_total_zombie_count` still carry v1 "incubating corpse" logic (harmless; rebuilt to spec §8 in step 4.1).
- `selection_manager.gd` — selection (click/box/shift/ctrl), control groups (Ctrl+1-9 / 1-9), move orders with deterministic DetHash formation jitter. The v1 RMB-on-human engagement resolver is gone — RMB-on-human is a plain move order until it becomes the release/Pounce trigger (2.2).
- `escape_zone.gd` (`EscapeZone` extends `Area2D`, `@tool`) — humans entering escape (counted + freed). Zombies are a **hard physical boundary**: a runtime `StaticBody2D` the size of the zone on the **"EscapeBarrier" collision layer (layer 4)**; zombies (`collision_mask = 9` = Environment + EscapeBarrier) slide along it and can't enter, humans (mask = Environment only) pass through. Scales to level-border escape zones.
- `vision_renderer.gd` — inert **stub** (the v1 cone/facing/click-to-pin renderer is gone). Rebuilt as the v2 readability layer (fill lines, calm/feral tint, riser/cower indicators) in steps 3.1/5.1.
- `camera_controller.gd`, `world_bounds.gd` (autoload `WorldBounds`), `level_bounds.gd`, `building.gd`, `initializer.gd`, overlays.
- Level-geometry & nav tooling: `wall.gd` (`Wall` extends `Polygon2D`) — mouse-editable polygon walls (`perimeter` edges-only or `solid` filled), generates hidden non-serialized `StaticBody2D`/collision/`Line2D` children. `nav_baker.gd` (`NavBaker` extends `NavigationRegion2D`) — runtime auto-bake from `LevelBounds` + obstacle `get_nav_footprint()`. Both `Building` and `Wall` report footprints.
- Special zombies: `fat_zombie.gd` / `costume_zombie.gd` (+ `fat_zombie_corpse.gd`) — **minimal-patched to parse, NON-FUNCTIONAL on this branch** (excluded from the PoC; full re-audit post-validation). Pattern: subclasses set `is_special = true` in `_ready()` *before* `super._ready()`. If ever placed in a level they'd need `collision_mask = 9` (the EscapeBarrier layer).

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

**Building the v2 PoC validation slice** (spec §12) — built 2D-first. Roster: Civilian, Militia, Police, GI. **No specials** (Fat/Costume excluded; re-audit post-validation), no Spec Ops, no pressure systems. Milestones: **M1** — core loop without the Mark; **M2** — add the Mark + LMB fill-line inspect.

**Progress (build plan `V2_POC_BUILD_PLAN.md`):** Phase 0 (foundations) ✅ and Phase 1 (demolition) ✅ complete — the branch is the sterile sandbox, RNG-free, with the registry + GameConfig + EscapeBarrier in place. **Phase 2 (predation core) underway:** 2.1 idle shamble ✅ (`ShambleBehavior`; established the zombie component architecture — `Zombie` is a dispatcher shell with `State {CALM, FERAL, DEAD}`, behaviors in child components per ARCHITECTURE_GUIDELINES rule 2). 2.2 FERAL + the Pounce ✅ (`FeralBrain` pursuit + `PounceBehavior` kill-at-landing/recovery; RMB-on-human releases selected zombies feral at the clicked human; pounce-exclusion via a Human-side claim; feral pursuit + calm moves both at `zombie_speed`). **Next: 2.3 retarget + hunt pool** → 2.4 release proper → 2.5 contagion → 2.6 risers. (Flagged: zombie pursuit has no nav pathing yet — straight-line `step_toward` gets stuck on obstacles; re-wire before the Phase 6 level.) Then Phase 3 (defense: fill front, fear/break, rout, cower), Phase 4 (win/lose + combo), Phase 5 (readability), Phase 6 (PoC level + M1 + the **sacred-ratio sweep**), Phase 7 (the Mark + M2). The spec's seven validation questions (§12) are the verdict. Propose-before-implementing applies to every step.

After the pivot validates: full 3D migration (low-poly geometry, simple 3D characters, rotatable isometric camera; driven by rooftop traversal and urban occlusion) — it inherits the v2 simplification, so there's far less to port.

The old v1 validation slice (Costume + Fat Zombie vs Police + barricaded GI) is superseded — it was played, and its findings are what produced the pivot. Several v1 known issues (morale/weapon kill-count tuning, Costume scoring edge case) are mooted by the pivot; the full annotated list lives in PROJECT_CONTEXT.md.
