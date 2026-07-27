# Dead Corps — Claude Code Project Memory

**Current version:** v0.45.0 · **Engine:** Godot 4.6 / GDScript · **Perspective:** 2D isometric — **final. The 3D migration is CANCELLED** (Ben, 2026-07-12; reaffirmed 2026-07-27). See `docs/ISO_MIGRATION_PLAN.md`.

This file is loaded into every Claude Code session. It is the lean orchestrator: working rules, design pillars, and pointers. Detailed reference lives in `docs/` and is read on demand — do not assume those files are in context until you've read them.

---

## ⚠️ Active direction: the V2 Predator Pivot (June 2026)

**Read `docs/V2_DIRECTION_SPEC.md` before any design or core-loop work.** Playtesting found v1 played like "ninja commando zombies" — a stealth-puzzle game — while the single most engaging moment was watching a wave get thinned by gunfire. The v2 spec rebuilds the core loop around predation: **bodies are ammunition, detection is a cost not a fail state, and the player corrals/releases/combo-routes a frenzied horde.** Stealth grammar (vision cones, facing, swing arcs, alerts, morale psychology) is removed.

Status: **design locked; the M1 core loop is now BUILT and feature-complete** (Phases 0–4 done, v0.43.0). Predation (shamble → feral → pounce → retarget → release → contagion → risers), defense (fill front → fear break → rout/herding → cower), win/lose (§8), and combo scoring (§6) all work end-to-end; zombies + humans nav-path around obstacles. What remains is **Phase 5 (readability pass) → Phase 6 (PoC level + the sacred-ratio sweep + the M1 validation verdict) → Phase 7 (M2: the Mark + inspect).** It supersedes the core-loop sections of the GDD (the GDD is deliberately NOT updated until the PoC validates — its sections 3, 6, and parts of 11 no longer reflect design intent). The spec §11 deprecation audit recorded what died from v1.

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
  WORK_QUEUE.md            # ⭐ THE current prioritized to-do (fixes → features → Phase 5/6/7) — start here for "what next"
  V2_REVIEW_2026-07-02.md  # architecture-review findings (bugs A1–A5, spec deviations B1–B6) at file:line
  HANDOVER_2026-07-02.md   # the review's batch queue + Ben's rulings + the doc-sync batch
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

This describes the codebase **as it exists now on `v2-poc` (v0.45.0) — the M1 core loop feature-complete, plus enterable buildings slice 1 + the terrain kit (v0.44.0, buildings spec §16) and the Mark (v0.45.0, M2's first half — behind the C key, pending a design workshop).** The v1 stealth systems (morale, alerts, vision cones, tunnel vision, HP/grapple melee, leap, the incubation pipeline, Spec Ops) are **gone**; built in their place: **predation** (feral/Pounce/contagion/risers), **defense** (fill front/fear break/rout+herding/cower), **shelters & sieges** (SHELTERED/BREACHING/breach/flush), **win/lose** (§8), **combo scoring** (§6), and **nav pathing** for both zombies and humans. Still to come: Phase 5 (readability `vision_renderer` rewrite), Phase 6 (PoC level + sacred-ratio sweep + M1 verdict), LMB fill-inspect (M2's other half). The codebase is **fully RNG-free** (spec §10) and all neighbour/unit lookups go through the GameManager registry. **Structure = dispatcher-shell + behavior-component pattern** (ARCHITECTURE_GUIDELINES): `Zombie`/`Human` are thin shells whose per-frame dispatch routes to child behavior-component nodes (one mechanic per component).

**Phase 0 foundations (the v2 substrate):**
- `game_config.gd` (autoload `GameConfig`) — single source of truth for every spec-§9 tunable, at v0.1 defaults. `level_config.gd` (`@tool LevelConfig`) optionally overrides per level. Nothing hardcodes a §9 number.
- Unit registry on `GameManager` — `unit_uid` (stable monotonic id per unit), `living_zombies()`/`living_humans()`/`neighbours_within(pos, radius, team, exclude)`, all returned in stable unit_uid order (§10). Every v2 radius query (contagion, fear, scan, seeding, shamble) reads these; never `get_nodes_in_group()` in per-frame code.
- `det_hash.gd` (`DetHash`, static) — deterministic per-unit jitter (`hash(unit_uid, salt)`), the only source of "random-looking" variation.

**Units + systems (built through Phase 4):**
- `unit.gd` (`Unit` extends `CharacterBody2D`) — base: movement (`step_toward`, world-bound clamp), selection, BOID separation/alignment (registry-backed, **`global_position`**). No HP — liveness is `is_alive`; `take_damage(amount, knockback)` is the **v2 binary kill entry** (one-shot). `has_line_of_sight_to` (raycast vs buildings layer 1). Separation via `move_and_collide` (corner-safe), dead units excluded via the registry.
- `zombie.gd` (`Zombie` extends `Unit`) — player-controlled **dispatcher shell**. State {CALM, FERAL, DEAD}; `_physics_process` routes to `_tick_calm` (idle-shamble or commanded move) / `_tick_feral` (autonomous hunt — released-is-released, not selectable/commandable). **Nav-pathed** movement: `nav_move_toward` drives the `NavigationAgent2D` around obstacles for calm moves + feral pursuit (pounce flight stays straight). Components: `ShambleBehavior` (calm idle wander), `FeralBrain` (pursuit / retarget / continuous peel-off via `FeralTargeting` path-score), `PounceBehavior` (lunge → kill-at-landing → recovery; `abort()` releases the victim's claim on a mid-pounce death). `ignite_feral(target=null)` (release seed, or null = contagion self-target). `zombie_killed_human` signal. `is_special` for the PoC-excluded specials.
- `human.gd` (`Human` extends `Unit`, `@tool`) — AI defender **dispatcher shell**. States IDLE/SENTRY/**FLEEING**/**SHELTERED**/**COWER**/DEAD; `defender_class` (CIV/MIL/POL/GI — indexes GameConfig per-class arrays); patrol (LOOP/PING_PONG); armed classes stamped with a class letter (M/P/G). Components: `FillBehavior` (the fill front — armed shot mechanic with **humans blocking the shot LOS**, per-class `fire_cooldown` gating the shot, the **door-watch** pre-aim while sheltered; + the civilian reaction-clock variant), `FearDetector` (fear-radius break, **building-LOS gated**; suspended while SHELTERED, sight-only uncapped inside a breached shelter), `FleeBehavior` (permanent rout — **nav-pathed** to the threat-aware nearest exit from the **unified exit set** (zones ∪ intact shelter doors), **herding** flee-vector bend around zombies, shelter entry + the two-leg breach flush, + the cower net-displacement detector). `start_fleeing()` / `start_cowering()` / `cancel_fill()` / `enter_shelter()` / `is_safely_sheltered()`; `was_cowering` flags the terror bonus.
- `game_manager.gd` (`GameManager`) — **core coordinator, do NOT rename/replace.** A **facade** since the 2026-07-26 splits: unit registry, spawning, escape counting, **win/lose to spec §8** (win = no humans remain; the lose verdict is judged at the death instant in `report_gunfire_kill` — living zombies + pending risers == 0), shelter adoption at boot, per-tick nav-map sync; everything else lives in child systems reached by **one-line delegates** (no caller changed): `hunt_pool.gd` (`HuntPool` — pursuit claims/counts, hunted ring, pursued/fleeing queries), `violence_pipeline.gd` (`ViolencePipeline` — contagion, gunfire kills, the riser pipeline + corpse commands), `mark_system.gd` (`MarkSystem` — the Mark, §5.4 attention field: `prey_for(feral)` + purple field rendering), and the **`combo` ComboSystem**. Found via group `"game_manager"`.
- `combo_system.gd` (`ComboSystem`, child of GM) — combo/pot scoring (§6: **tiered base** + rare burst/terror multiplier; banks pot×mult on window expiry; `finalize()` at game end). `combo_hud.gd` (`ComboHUD`, built in code, GM-instantiated at runtime) — SCORE total (top-right) + live pot ×mult + draining window bar + gold bank popup.
- `selection_manager.gd` — selection (click/box/shift/ctrl; finishing zombies + rising corpses included), control groups (Ctrl+1-9 / 1-9), move orders (formation slots via static `formation_planner.gd` `FormationPlanner` + DetHash jitter), shift-RMB waypoint queues. **RMB-on-human = RELEASE** (magnetism `release_aim_radius`; `release_seeder.gd` `ReleaseSeeder` does the cluster seeding); **RMB on an occupied building / intact door = siege release variants**; recall = calm members only. Hotkeys: **F** hold = 3× fast-forward (paired `physics_ticks` × `time_scale`, tick-identical), **R** restart, **Q/E** select all calm / on-screen calm, **C** = mark mode (crosshair cursor; LMB places/clears the Mark — interim grammar pending workshop). `feral_targeting.gd` (`FeralTargeting`, static) — the path-score "bullet" rule shared by seeding + feral peel/retarget.
- `escape_zone.gd` (`EscapeZone`, `@tool`) — humans entering escape (counted + freed). Zombies blocked by a **hard physical barrier**: a runtime `StaticBody2D` on the **"EscapeBarrier" layer 4**; zombie `collision_mask = 9` (Environment + EscapeBarrier), humans Environment-only pass through.
- **The buildings kit** (enterable buildings slice 1 + terrain kit — `V2_ENTERABLE_BUILDINGS_SPEC.md`, as-built §16): `shelter_building.gd` (`ShelterBuilding` extends `Polygon2D`, `@tool` — mouse-drawn footprint, auto wall quads minus door gaps, merged nav outlines, occupancy/spot claims, `is_shelter` flag for dumb boxes, scale self-heal), `door.gd` (`Door` — zombie barrier layer 2/8 + DoorLOS layer 5/16 + DoorLock layer 6/32; lock predicate, integrity/pounds/breach, inside-burst, `starts_open` portals, per-door `integrity_override`/`thickness`; standalone in a Wall gap = a gate), `shelter_spot.gd` (`ShelterSpot`, `is_guard` variant). Zombie side: **BREACHING lives in `FeralBrain`** (building proxy → own nearest door, pound cadence, peel stays live, pour-in at breach, ordered sieges, Mark siege-pull). Collision masks: zombies 9, humans 33; LOS rays 17 (+humans 21 for fills).
- `vision_renderer.gd` — still an inert **stub**. Interim readability lives **on the units** (the fill line + calm/feral & cower tints + hunt/hover rings, drawn by Human/Zombie). The production readability layer is the **Phase 5** `vision_renderer` rewrite.
- `det_hash.gd` (`DetHash`, static jitter), `camera_controller.gd`, `world_bounds.gd` (autoload), `level_bounds.gd`, `building.gd`, `wall.gd` (`Wall` — mouse-editable polygon walls; `solid` defaults **true**, perimeter mode is legacy/soft-deprecated toward dumb boxes), `nav_baker.gd` (`NavBaker` — runtime navmesh bake from `LevelBounds` + obstacle `get_nav_footprint()`), `initializer.gd`, overlays (`debug_overlay`, `end_game_overlay`).
- Special zombies: `fat_zombie.gd` / `costume_zombie.gd` (+ `fat_zombie_corpse.gd`) — **NON-FUNCTIONAL, PoC-excluded** (parse-only; full re-audit post-validation). Subclasses set `is_special = true` in `_ready()` before `super._ready()`; if ever placed they'd need `collision_mask = 9`.

---

## GDScript / Godot conventions & gotchas

- Godot **4.6**. Type hints everywhere (`var distance: float`); explicit nullability (`var target: Node2D = null`). Comments explain *why*, not *what*.
- **On `v2-poc`: `docs/ARCHITECTURE_GUIDELINES.md` governs all new/rebuilt scripts** (component ownership, ~400-line/~40-line tripwires, dispatcher `_physics_process`, signals-up-calls-down, registry-only discovery). `docs/V2_IMPLEMENTER_GUIDE.md` has the invariants checklist for any build-plan work.
- **Always use `global_position`** for cross-unit calculations — nested scenes break local `position` (notably escape zones).
- **Waypoint ordering uses `naturalnocasecmp_to()`** so `Waypoint2` sorts before `Waypoint10`.
- `@tool` scripts must guard game logic with `Engine.is_editor_hint()` — units must not run AI in the editor.
- Navigation: `NavigationRegion2D` and `NavigationAgent2D` layers must match (both Layer 1). Zombie movement (calm commanded moves + feral pursuit) and the human rout now **path-follow** via the `NavigationAgent2D` (`Zombie.nav_move_toward` / `FleeBehavior`) around the runtime-baked navmesh; **`avoidance_enabled = false`** (no RVO → deterministic), so obstacles are excluded by the navmesh bake (`nav_baker`), not by `NavigationObstacle2D`. Pounce flight stays straight-line (in-range lunge).
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

**➡️ For the current prioritized to-do, read `docs/WORK_QUEUE.md`** (mirrored in the `v2-work-queue` memory). As of 2026-07-27: the ruled fix batches, playtest features, Tier-4 housekeeping, **enterable buildings slice 1 + the terrain kit (v0.44.0)**, the manager splits, and **the Mark (v0.45.0)** are all DONE — what remains is Phase 5 (readability) → Phase 6 (PoC level + sweep + M1 verdict) → the Mark design workshop + LMB fill-inspect (M2). Buildings slice 2 (armory/barricade) stays parked until slice 1 plays at level scale.

**Building the v2 PoC validation slice** (spec §12) — built 2D-first. Roster: Civilian, Militia, Police, GI. **No specials** (Fat/Costume excluded; re-audit post-validation), no Spec Ops, no pressure systems. Milestones: **M1** — core loop without the Mark; **M2** — add the Mark + LMB fill-line inspect.

**Progress (build plan `V2_POC_BUILD_PLAN.md`):** Phases 0–4 ✅ — the **M1 core loop is feature-complete (v0.43.0)**. Predation: idle shamble, FERAL + the Pounce (kill-at-landing, pounce-exclusion), retarget + hunt pool, release (cluster seeding) on the **peel-off + movement-vector "bullet" targeting** model, **contagion** (a kill or gunfire-death ignites nearby calm zombies; gunfire seeds the shooter), **risers** (killed humans rise CALM after `rise_time`). Defense: the **fill front** (armed shot; humans block the shot LOS), the **civilian reaction-clock flee**, the **fear break** (building-LOS gated), **rout + herding** (nav-pathed; flee-vectors bend around your zombies; threat-aware exit), and **cower** (cornered → frozen, terror-bonus flagged). Loop: **win/lose (§8)** and **combo scoring (§6 — tiered base + rare burst/terror multiplier)** with the combo HUD + end screen. **Zombies and humans nav-path** around obstacles (the old straight-line-stall flag is closed). **Built since (pulled forward ahead of Phase 5/6): enterable buildings slice 1 + the terrain kit (v0.44.0 — shelters, sieges, breaches, flushes, gates, dumb boxes; buildings spec §16) and the Mark (v0.45.0 — §5.4 attention field, behind the C key; first play found it confusing → needs a design workshop before validation Q6).** **Next: Phase 5 (readability — `vision_renderer` rewrite) → Phase 6 (build the §12 PoC level + the sacred-ratio sweep + the M1 verdict) → the Mark workshop + LMB inspect (M2).** Now-due before/at Phase 6: the **calm-mass-break balance re-judge** (does herd-everyone-out stay a hollow zero-score now that scoring exists?), a **full Phase 3 test-case re-run**, and an **uncaptured crash** to reproduce. The spec's seven validation questions (§12) are the verdict. Propose-before-implementing applies to every step.

**There is no 3D migration.** Cancelled by Ben on 2026-07-12 (reaffirmed 2026-07-27): Dead Corps ships as a **2D isometric** game — isometric is a presentation layer (diamond tiles + ¾-view sprites + Y-sort) over the existing flat 2D sim, per `docs/ISO_MIGRATION_PLAN.md`. Older docs still carry stale "confirmed 3D migration" wording (GDD §11.15, PROJECT_CONTEXT, CODEBASE_REVIEW Stage G / 3D-impact sections) — **treat all of it as superseded** (the V2 direction spec was corrected in the 2026-07-27 sync; the rest stays Ben-gated). Anything formerly parked "to 3D" (multi-storey buildings, rooftops) now needs a 2D answer or stays parked on its own merits.

The old v1 validation slice (Costume + Fat Zombie vs Police + barricaded GI) is superseded — it was played, and its findings are what produced the pivot. Several v1 known issues (morale/weapon kill-count tuning, Costume scoring edge case) are mooted by the pivot; the full annotated list lives in PROJECT_CONTEXT.md.
