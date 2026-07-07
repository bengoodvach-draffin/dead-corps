# Dead Corps — Project Context

**Current version:** v0.43.0 · **Branch:** v2-poc · **Engine:** Godot 4.6 / GDScript · **Location:** Amsterdam, NL

Technical state, per-script purpose table, known issues, and quick-reference values. For design intent, zombie/defender specs, and the decision log, see `GAME_DESIGN_DOCUMENT.md`. For working rules, see the root `CLAUDE.md`. For the full feature history, see `archive/` changelogs and GDD §2.

---

## ⚠️ STALE BELOW — v2-poc Phases 1–4 COMPLETE (v0.43.0)

`V2_DIRECTION_SPEC.md` is the authoritative core-loop design; `V2_POC_BUILD_PLAN.md` tracks implementation. On branch `v2-poc`, **Phases 0–4 are done (v0.43.0) — the M1 core loop is feature-complete.** The v1 stealth systems (morale, alerts, vision cones, tunnel vision, HP/grapple melee, leap, Spec Ops, the incubation pipeline) were removed, then built on the new substrate: **predation** (feral/Pounce/contagion/risers), **defense** (fill front/fear break/rout+herding/cower), **win/lose** (§8), **combo scoring** (§6), and **nav pathing** for zombies + humans. Substrate: GameConfig/LevelConfig, the GameManager unit registry, DetHash, the EscapeBarrier (layer 4), `is_alive` liveness, and the **dispatcher-shell + behavior-component** architecture.

**So the "Current state", the Scripts table, and the Known Issues below describe the PRE-demolition v1 codebase and are now substantially STALE.** They are kept for historical reference and bug-archaeology only. For the *current* architecture, read **CLAUDE.md → "Architecture at a glance"** (kept in sync). This document gets a full v1→v2 rewrite once the PoC validates and the v2 systems are stable — deferred deliberately because Phases 2–7 will churn it heavily.

---

## Current state (high level) — ⚠️ describes pre-demolition v1, see banner above

The prototype has core RTS control, combat/conversion, vision, navigation, a full patrol system (manual + visual waypoints, Phase C per-waypoint behaviour, formation squads), five human defender classes with a morale bar and shooting, a low/high-urgency alert system, a click-to-pin vision-cone system, player-controlled engagement (no auto-pursuit), and two special zombies (Fat, Costume). Not yet built: the entire v2 core loop (feral/calm states, pounce, fill, fear radius, Mark, combo scoring, rise-in-place — see `V2_DIRECTION_SPEC.md`), multiple levels, campaign, audio (in progress), final art, and the 3D migration (now gated behind the v2 PoC).

GDD §2 has the authoritative implemented/not-implemented breakdown **for v1 systems**; the spec's §11 audit maps each to its v2 fate.

---

## Scripts (`scripts/`) — ⚠️ STALE: this table describes the pre-demolition v1 scripts. For the current v2 skeletons see CLAUDE.md → "Architecture at a glance".

| File | Class / role | Notes |
|------|--------------|-------|
| `unit.gd` | `Unit` : `CharacterBody2D` | Base for all units. Movement, combat, health, selection, BOID separation + alignment, world-bound clamping. Cohesion force disabled (commented out, v0.25.1). `apply_separation_force()` moves via `move_and_collide` (not raw `position +=`) so corner pile-ups can't punch a unit through a wall, and skips dead neighbours (`current_health <= 0`) so a freshly-shot unit immediately stops pushing the living during its 0.3s corpse linger (v0.28.0). Contains a legacy `UnitType` enum (HUMAN_SWAT/HUMAN_MILITARY) that does **not** map to `DefenderClass` — appears unused, audit/remove. |
| `zombie.gd` | `Zombie` : `Unit` | States IDLE/MOVING/PURSUING/LEAPING/MELEE/DEAD. No auto-pursuit (v0.25.0). `can_receive_command()` false while leaping/committed. Post-kill 250px LOS continuation scan. `take_damage(amount, knockback_direction)` override with death knockback tween. `is_special` base flag disables leap/continuation/recruitment. **Melee cap (2/human) is gated live on `attack_target.count_melee_attackers()` — actual meleeing zombies — not `attacker_count` (total targeting), so any number may pursue and rotate into a freed slot when a front attacker dies (v0.28.0).** `die()` clears all engagement flags (incl. `has_leap_grappled`) so a grappled human detects the grappler is gone. |
| `human.gd` | `Human` : `Unit` | States IDLE/SENTRY/FLEEING/GRAPPLED/DEAD/TUNNEL_VISION (FREEZE, MELEE_CHARGE designed but deferred). `DefenderClass` enum, morale system, shooting (aim timer, tracer, LOS pause, weapon-range gating), dual-zone vision arcs, tunnel vision, alert system (low + high urgency; high-urgency broadcaster now self-reacts so a lone witness still turns), shoot-target facing, smart retargeting, `_pre_alert_facing`, smooth return rotation, patrol (LOOP/PING_PONG + Phase C), formation squads, escape-zone seeking, instant facing toward attacker on GRAPPLED, get-up release if the grappler dies first (3s `grapple_getup_delay`, then → SENTRY facing the came-from direction; re-pin cancels). `@tool` for editor visuals. `propagate_flee_to_group()` deprecated (commented out). `attacker_count` tracks zombies *targeting* this human (uncapped — drives the red border + "being targeted" detection); `count_melee_attackers()` scans for zombies actually meleeing it and backs the live 2-slot cap — the two are decoupled (v0.28.0). |
| `game_manager.gd` | `GameManager` : `Node` | **Core coordinator — do NOT rename/replace.** Tracks `all_zombies`/`all_humans`, spawning, conversion after 5s incubation, escape counting, win/loss, game time. Found via group `"game_manager"`. |
| `selection_manager.gd` | `SelectionManager` : `Node2D` | Click/box/Shift/Ctrl selection, Ctrl+1-9 control groups. Clicking a human preserves zombie selection (v0.25.1). Group `"selection_manager"`. `_resolve_group_engagement()` spreads selected zombies across the human group within 150px (greedy, 2 per human first wave); **overflow zombies attack the nearest human in the group** (via `_nearest_in_group()`) instead of a dead-end move order, so a horde keeps engaging and rotating in as the front rank dies (v0.28.0). The 2-at-a-time limit is enforced live by the zombie melee gate, not as a one-shot assignment cap. |
| `camera_controller.gd` | `CameraController` : `Camera2D` | WASD pan, wheel zoom, edge scroll, bounds synced from `WorldBounds` on ready. Group `"camera"`. |
| `vision_renderer.gd` | `VisionRenderer` : `Node2D` | Human vision cones + facing lines. Click-to-pin cone, V key shows all, white 20px facing lines always drawn, tunnel-vision cones always shown. Merged-blob logic removed; zombie vision removed (v0.25.0). |
| `building.gd` | `Building` : `StaticBody2D` | Blocks movement + LOS. `@tool` preview. In `"buildings"` + `"nav_obstacle"` groups; exposes `get_nav_footprint()` (rect) for `NavBaker`. |
| `wall.gd` | `Wall` : `Polygon2D` | **Mouse-editable level geometry** (v0.26.0). Add via Add Child Node → "Wall"; edit points directly in the 2D editor. `solid=false` = perimeter (edges-only segment collision on inner+outer offset rings so units don't clip the stroke; thick `Line2D` outline); `solid=true` = filled block. `wall_color`/`wall_thickness` exports. Generates hidden, non-serialized internal `StaticBody2D`/`CollisionPolygon2D`×2/`Line2D` (`@tool`). In `"nav_obstacle"` group; `get_nav_footprint()` returns solid polygon, or thin per-edge quads for perimeter (interior stays walkable). Independent per placement — no scene-instance propagation. |
| `nav_baker.gd` | `NavBaker` : `NavigationRegion2D` | **Runtime auto-bake of the nav mesh** (v0.26.0). On level load (and via editor `bake_preview` button) rebuilds the `NavigationPolygon` from live geometry: walkable area = `LevelBounds`, obstacles carve their own `get_nav_footprint()`. Scans the scene tree directly (not groups) so it's robust in editor + game. `agent_radius` (default 12) / `bake_cell_size` (default 4) exports. Replaces hand-authored coordinates + manual editor re-bakes; deterministic obstacle exclusion (no collider/group-parse config). |
| `escape_zone.gd` | `EscapeZone` : `Area2D` | Humans entering = escaped; zombies entering die. Sets Fat Zombie `spawn_corpse_on_death = false` to suppress corpse on escape. `@tool`. |
| `world_bounds.gd` | autoload `WorldBounds` : `Node` | Single source of truth for world bounds. Read by unit + camera. |
| `level_bounds.gd` | `@tool` : `Node2D` | Placed per level; writes `bounds_min`/`bounds_max` into `WorldBounds` on ready. Draws orange boundary. Use this instead of editing `world_bounds.gd`. |
| `fat_zombie.gd` | `FatZombie` : `Zombie` | `is_special = true`, `attack_damage = 0`. Gunshot-only death → spawns `FatZombieCorpse`. |
| `fat_zombie_corpse.gd` | `FatZombieCorpse` : `StaticBody2D` | Permanent obstacle, layer 1, `"buildings"` group. 60×60 procedural. `NavigationObstacle2D` omitted (see known issues). |
| `costume_zombie.gd` | `CostumeZombie` : `Zombie` | Undetectable while `is_costumed == true` (humans skip it in all detection systems via `zombie.get("is_costumed")`). Disguise breaks permanently on pinning a human (GRAPPLED), then behaves as a regular zombie. Pink → green on break. **Scoring edge case:** `_break_disguise()` sets `is_special = false`, so a broken-disguise Costume Zombie scores 25pts not 100 — undecided. |
| `initializer.gd` | bootstrap | Calls `game_manager.setup_test_scenario()` after one frame. Uncheck **Enabled** to hand-build levels. |
| `debug_overlay.gd` / `end_game_overlay.gd` | HUD / win-loss screen | Live counts + reset; score breakdown on `game_won`/`game_lost`. |

---

## Scenes (`scenes/`)

Units: `zombie.tscn` (NavigationAgent2D r30, CollisionShape2D r12), `human.tscn` (add `Waypoint1`, `Waypoint2`… child Node2Ds for patrol), `fat_zombie.tscn` (r18, `corpse_scene` wired), `fat_zombie_corpse.tscn` (spawned at runtime — don't place manually), `costume_zombie.tscn` (pink).
Props: `building.tscn`, `escape_zone.tscn`. **Walls have no scene** — add `Wall` as a node (Add Child Node → "Wall"), not an instance. Keep `Wall` near the top of each level group so it doesn't steal viewport clicks from buildings/units underneath it.
Levels: `main.tscn` (camera, managers, renderer, GameManager, Initializer, overlays), `test_level_1.tscn`, `sandbox_level_1.tscn`, `sandbox_level_human_testing.tscn`, `puzzle_test_1.tscn`. For auto-nav, give the level's `NavigationRegion2D` the `nav_baker.gd` script + a `LevelBounds`; obstacles bake automatically.
UI: `debug_overlay.tscn`, `end_game_overlay.tscn`.

---

## Known issues — ⚠️ STALE (pre-demolition v1)

Most entries here concerned v1 systems that **Phase 1 demolition has now removed** (morale, alerts, vision cones, HP/grapple melee, the incubation pipeline, etc.), so they no longer apply on `v2-poc`. Kept for historical reference; a fresh v2 issues list comes with the post-PoC rewrite.

- **Fat Zombie corpse navigation:** `FatZombieCorpse` blocks movement physically, but zombies don't path around it cleanly because `avoidance_enabled = false` on the zombie `NavigationAgent2D` — `NavigationObstacle2D` has no effect without it. Fix = enable avoidance + add `NavigationObstacle2D` to `fat_zombie_corpse.gd`. Deferred to a future avoidance pass.
- **Morale / shooting tuning:** per-class kill counts run higher than spec because the aim timer starts at vision range. Fundamentally working; left for playtest tuning. *(Mooted by v2: morale and the aim-timer shooting model are both dead — replaced by fill + fear radius; kill counts become emergent from the fill-speed/zombie-speed ratio.)*
- **Costume Zombie scoring:** broken-disguise = 25pts (it sets `is_special = false`). Pending design decision on whether that's intended. *(Mooted by v2: per-zombie survivor scoring is dead; specials are excluded from the PoC and re-audited after.)*
- **Costume Zombie reaction strength:** the grappled-drain event fires when a costumed zombie bites an ally, but the visual surprise may warrant a larger morale hit / extra response. Flagged for post-validation tuning. *(Mooted by v2: morale and GRAPPLED are both dead.)*
- **Patrol resume:** by design, a sentry that detects a zombie stops patrolling permanently and does not resume. Re-evaluate in playtesting. *(v2: patrols survive as positioning-over-time; the detection/sentry model around them changes — re-evaluate inside the new fill model.)*
- **Navigation baking:** levels using `NavBaker` (`nav_baker.gd` on the `NavigationRegion2D`) auto-bake from geometry on load — no manual coordinates/re-bake, deterministic building/wall exclusion. Tune `agent_radius` to ≈ unit radius (12px); larger values erode small handcrafted rooms. Legacy levels with hand-baked `NavigationPolygon` still work but won't pick up geometry changes. The old "Groups" / collider-parse method is superseded for `NavBaker` levels.
- **No current README** — the stale v0.12.4 `docs/README.md` was archived (`Archive/README_v0.12.4.md`); write a fresh one in a separate pass, sensibly after the PoC verdict.
- **3D_MIGRATION_ANALYSIS.md** was created in a March 2026 session but never committed — needs re-creating.

---

## Key technical decisions

- **Degrees for sentry facing** (0°=N, 90°=E, 180°=S, 270°=W); converted to Vector2 internally. Designer-friendly.
- **Always `global_position`** for calculations (nested-scene safety).
- **BOID flocking** for spacing instead of physics collision; separation/alignment only (cohesion disabled).
- **Vision is state-dependent** (idle circle vs moving/sentry arc) with LOS raycasting. Zombie vision arcs removed in v0.25.0 — arcs are human-only visual language.
- **Navigation is optional/opt-in** per level; falls back to direct movement. Levels opt in by putting `nav_baker.gd` on their `NavigationRegion2D` (auto-bakes from `LevelBounds` + obstacle `get_nav_footprint()`); obstacles report footprints rather than the baker parsing colliders, so exclusion is explicit.
- **Conversion/incubation:** dead humans stay on map in DEAD state 5s, counted in the zombie total for scoring + lose checks, then convert.
- **3D migration** is the confirmed architectural direction (low-poly, simple 3D characters, rotatable isometric camera) — driven by rooftop traversal and urban occlusion. **Now gated behind the v2 pivot PoC** (built 2D-first); the migration inherits the v2 simplification, so there is less to port.

---

## Quick-reference values

These are the **v1 values currently in the code**. The v2 numbers (fill speeds, fear radius, pounce, combo, etc.) live in `V2_DIRECTION_SPEC.md` §9 and will move into the new `level_config.gd`.

**Units:** zombie/human radius 12px · zombie speed 105 (leap 210 at 40px) · human speed 90 · patrol speed 50 · zombie `NavigationAgent2D` radius 30px (path-following clearance) · formation spacing 40px · regroup timeout 10s · grapple proximity 50px (70px during leap) · grapple get-up delay 3s · incubation 5s.

**Level geometry / nav (v0.26.0):** `Wall` thickness default 16px, perimeter collision on inner+outer offset rings · `NavBaker` bake `agent_radius` default 12px (≈ unit radius; keep below room sizes), `bake_cell_size` default 4px.

**Vision:** human IDLE 100px circle · SENTRY/FLEEING 350px arc 90° · TUNNEL_VISION 350px arc 22.5° threat-facing 10s. Dual-zone inner ranges: Militia/Police 150px, GI/Spec Ops 250px, Civilian single-zone.

**Scoring:** regular zombie 25pts, special 100pts (but broken-disguise Costume reverts to 25). Time bonus ≤1m +200, ≤2m +150, ≤3m +100, ≤4m +50.

**Weapons:** Civilian unarmed · Militia shotgun 150px 0.7s · Police pistol 150px 0.55s · GI rifle 250px 0.525s · Spec Ops rifle 250px 0.26s. One-shot kills (50 dmg). No shooting while fleeing.

**Morale:**

| Unit | Max | Sighting/sec | Grappled | Fleeing | Killed |
|------|-----|--------------|----------|---------|--------|
| Civilian | 65 | 30 | 100 | 50 | 150 |
| Militia | 150 | 35 | 100 | 40 | 150 |
| Police | 200 | 0 | 100 | 40 | 150 |
| GI | 400 | 0 | 275 | 20 | 150 |
| Spec Ops | 1000 | 0 | 100 | 0 | 150 |

Sighting drains within weapon range for armed units; Civilians drain across full 350px vision. Morale recovers to 50% on flee end / tunnel-vision expiry. Primary response at empty: Civilian/Militia/Police flee; GI/Spec Ops tunnel vision.

**Alerts:** Low urgency (detection) — 5s cone threshold, 150px radius, 30s cooldown, 30s facing return, all classes face threat directly (per-class offsets removed v0.25.5; preserved as commented `ALERT_OFFSETS`). High urgency (ally grappled/killed 75px, gunshot 150px) — 0.4s delay, 2s shared cooldown, 2s hold, direct facing, Civilians included. All rotations smooth at 360°/sec. Excluded: units with a shoot_target, or in FLEEING/GRAPPLED/DEAD/TUNNEL_VISION.

**Collision layers:** 1 buildings (movement + LOS + nav), 2 zombies, 3 humans (no unit-unit collision; BOID only).

---

## Terminology

**Sentry** guard with directional vision/swing · **Waypoint** patrol marker · **BOID** flocking · **Grappled** human pinned · **Morale bar** continuous stress drain (replaced old panic spreading) · **Tunnel Vision** GI/Spec Ops 22.5° locked threat-facing cone · **Detection Alert** 5s sighting → allies face threat · **LOOP/PING_PONG** patrol modes · **Phase A/B/C** patrol dev phases.
