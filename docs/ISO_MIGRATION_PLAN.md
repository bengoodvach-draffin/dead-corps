# Dead Corps — 2D Isometric Presentation Migration Plan

**Status:** PROPOSED (awaiting Ben's approval of the two headline decisions in §2–§3)
**Date:** 2026-07-12 · **Branch target:** `v2-poc` · **Supersedes:** the "full 3D migration" direction (CLAUDE.md "after the pivot validates" section, GDD references to 3D). **3D is dropped.**
**Audience:** an Opus-level implementing agent. Read `docs/ARCHITECTURE_GUIDELINES.md` and `docs/V2_IMPLEMENTER_GUIDE.md` before executing any stage. All working rules apply per stage: propose-before-implementing, one stage at a time, parse gate (`tools/check.ps1`) after every `.gd` edit, print test cases, **Ben commits manually**.

---

## 1. Why this change

Ben's decision (2026-07-12): Dead Corps ships as a **2D isometric** game. The planned post-validation 3D migration is cancelled.

- **Scope/complexity:** the 3D port (low-poly geo, 3D characters, rotatable camera) was the single largest unbuilt line item. Dropping it removes an entire engine-domain migration.
- **Assets exist:** the SmallScaleInt itch.io bundle (Summer Sale 2026, $64.99 for 18 packs) covers zombies, humans, and three full isometric zombie-themed tilesets (City / Rural / Interior) **by one creator, in one matched style and scale**. The creator confirms the character packs and iso tilesets are scale-matched.

### What the assets are (from the store pages)

| Pack | Contents | Format |
|---|---|---|
| HD 8-Directional Zombie Pack ($14.99) | 36+ zombie characters, **8 directions × 15 animations each** (idle variants, walk, run, crawl, **WakeUp**, 5 attacks, take-damage, die ± gore), + blood/acid FX | PNG spritesheets (individual-frame option), 128×128 and 192×192 per frame, shadow/no-shadow variants |
| Zombie City HD Isometric Tileset ($14.99) | 1000+ tiles: floors, walls, stairs, doors, props, cars, flora; fire/chest animations; 1 playable character + 5 zombies + **gunfire animations**, blood FX | Individual PNGs, **128×256 px tiles** (floor diamond ≈ 128×64, 2:1), recommended pivot (0.5, 0.19), ~170 MB RAR |
| Zombie Rural / Zombie Interior tilesets | 1800+ / 2000+ tiles, same system | same |
| HD Character Packs 1–2, Enemy Pack, Undead Pack | living-human 8-dir characters | same system |
| Character Creator 2D – Modern (free in bundle) | customizable modern-clothing character spritesheet generator | generator |

**Known asset risk (Stage 0 must verify):** the PoC needs **living defenders in four visually distinct classes** (Civilian / Militia / Police / GI) with at minimum idle, walk, run, **shoot**, and die animations. The zombie pack's cops/soldiers are *zombies*. Candidate sources: HD Character Pack 1/2, Enemy Pack, the tileset's playable character + gunfire FX, and Character Creator 2D – Modern. This is the one gap that could require an extra purchase outside the bundle.

---

## 2. Headline decision A — isometric is a PRESENTATION layer, not a coordinate system

**Recommendation (firm): keep the gameplay plane exactly as it is. Nothing in the spatial model changes. "Isometric" is delivered entirely by art: diamond-shaped floor tiles and ¾-view sprites living in the same flat, untransformed 2D world the game already runs in, plus Y-sorted draw order.**

There is no separate "logical world space" to project from — the game was built directly in screen space, and that is a feature, not a defect. In Godot, an isometric `TileMapLayer` is just diamond-textured tiles positioned in ordinary 2D coordinates; nothing about it requires a coordinate transform. This is how the majority of 2D iso games are built.

### What this preserves untouched (do NOT modify any of it)

- **Every §9 tunable and every radius mechanic** — fear 250, contagion 150, awareness 400–550, pounce 40, all of `game_config.gd`. Radii stay circles.
- **The registry chokepoint** `GameManager.neighbours_within` (`game_manager.gd:373`) and every `distance_to` check.
- **Determinism (spec §10)** — no transform layer means no new float math anywhere in the sim.
- **Navigation** — `nav_baker.gd`, `NavigationAgent2D` setup, footprints; the navmesh remains a flat rectangle minus obstacle holes.
- **LOS raycasts** (`unit.gd:173`, `fill_behavior.gd:173`, `fear_detector.gd:67`) — straight lines vs layer-1 colliders, unchanged.
- **Input/picking** — `selection_manager.gd` keeps `get_global_mouse_position()` 1:1; box-select stays an axis-aligned screen rect (which is what players expect anyway); the formation grid stays square.
- **Camera** — `camera_controller.gd` pan/zoom unchanged; no rotation (a fixed iso view; the rotatable camera died with 3D).

### Accepted visual fictions (deliberate, not bugs)

1. **Range indicators render as screen circles; feet decals render as ovals.** The rule (clarified 2026-07-12 off Ben's review question): a drawn shape must truthfully show what it represents.
   - *Decals* (selection ring, hover ring, hunted marker — "this unit, standing here") carry no gameplay area → draw them as 2:1 under-feet **ellipses** so they read as painted on the ground (Stage 6).
   - *Range indicators* (fear, contagion, release magnetism — "the mechanic reaches to here") encode a gameplay area that, per Decision A, genuinely IS a screen-space circle (`neighbours_within` measures plain screen distance) → they must be drawn as **circles**. A 2:1 oval would lie: a defender above the oval's top edge would look safe while standing inside the actual radius. Pretty-but-wrong indicators are forbidden.
   - Making ranges *actually* elliptical (anisotropic distance metric + compressed vertical speeds) is the projected-world architecture Decision A rejects; it would invalidate every tuned §9 value. **Not parked — rejected.**
2. **Screen-vertical movement covers the same px/sec as horizontal**, though the tile art implies it is "farther" in world terms. Imperceptible in play; changing it would anisotropize every speed and radius and break the tuned feel. **Forbidden.**

### Explicitly forbidden in this migration

- Any screen↔world projection/unprojection helper.
- Any axis-scaling of distances, speeds, radii, or BOID forces.
- Any gameplay behavior keyed to animation state or animation completion (see the invariant in §6).

## 3. Headline decision B — scale: art scales down to the world, not the world up to the art

The current world: unit collision radius 12 px, bodies ~20×30 px, map 2000×1000, fear radius 250, camera zoom 0.5–2.5 targeting "~60 px units at 1080p" (`camera_controller.gd:46`).

**Measured art dimensions (2026-07-12, from the actual files in `art/raw/` — supersedes the store-page numbers):** the 128×128 character *frame* is mostly transparent padding. The *figure* inside is far smaller:
- CityZombie 1, Idle S: opaque box **27w × 39h** px (feet at frame y≈91).
- Survivor, Idle S: opaque box **20w × 47h** px.
- Ground tile: 128×256 frame, opaque region 128w × 80h = a **128×64 floor diamond + ~16 px thickness skirt** below.
- Cars/large props: 256×512 frames, 4 directions (E/N/S/W) only.

**Recommendation: a single visual constant `ART_SCALE`, applied only to sprite and tile scale — provisional value ≈ 0.75, frozen only after a calibration scene (see below).** At 0.75 the figures render ~29–35 px tall — matching today's 30 px placeholder, so every tuned proportion (fear 250 ≈ 8 body-heights, collision r=12 vs ~20 px body width) is preserved by eye as well as by math. Floor diamonds become 96×48. Characters and tiles must share the ONE scale — splitting them would desync people against doors/cars and break the artist's proportions.

⚠️ **History of this number, kept as a warning:** this plan originally recommended 0.25, derived from the store page's "128 px frames" — reasoning from *frame* size, not *figure* size. Measurement proved that wrong by ~3×. This is also the strongest argument for the art-scales-to-world architecture itself: under the world-scales-to-art alternative, that same error would have meant a world rebuilt ×4 too large and a full re-tune to unwind. Under `ART_SCALE`, the error cost changing one number.

Why not scale the world up to native art size: it means editing ~40 GameConfig values, every hand-placed position in every scene, **and** the survey found many hardcoded pixel constants *outside* GameConfig that would each be a silent-miss risk — click tolerance 30 (`selection_manager.gd:205`), move-jitter 15 (`:437`), formation spacing 40 (`:398-454`), knockback 8 (`unit.gd:156`), hunted ring 20 / hover 24 (`human.gd:504-510`), flee `LOOKAHEAD=40` (`flee_behavior.gd:25`), nav `bake_cell_size=4`, `agent_radius=12/18/30`. One missed constant = a subtle balance bug that could poison the M1 verdict. `ART_SCALE` touches none of them.

**Calibration + freeze protocol (the real lock-in risk lives here):**
1. Stage 1 builds a throwaway **calibration scene**: one animated character + a patch of floor tiles + one building + a 250 px-radius circle drawn around the character (the fear radius, for proportion judgement), viewed at zoom 0.5 / 1.0 / 2.5.
2. Ben eyeballs and adjusts `ART_SCALE` until it reads right. Cheap: it is one number.
3. **`ART_SCALE` FREEZES before Stage 4 (the first painted `TileMapLayer`).** After levels are painted, changing the scale moves every tile relative to the fixed gameplay geometry (buildings, positions, radii) → repainting every level. Before Stage 4 it is free to change; after, it is expensive. Treat the freeze as a gate.

**Future art swaps (design for this now — Ben raised it 2026-07-12):** `ART_SCALE` is *this source's* conversion factor, not "the game's scale." What actually freezes at the gate are the **world visual metrics**: standard figure ≈ 30 world px, tile grid = 96×48 world px. Any future art source gets its own factor normalizing it to those metrics (new pack draws people 60 px tall → its factor is 0.5); sources can coexist. Implementation requirements this imposes:
- The Stage 1 generator's **manifest is per-source/per-character** (native figure height, feet-y in frame, clip names); `UnitVisual` reads scale + feet offset from generated metadata — never hardcode 0.75 on nodes. Swapping art = new manifest entries + regenerate, zero scene surgery.
- Painted levels survive a tile-art swap **only if** new tiles are normalized to the frozen 96×48 grid (a texture-scale setting on the new tileset). The *grid itself* is the expensive thing to change post-painting (repaint every level) — changing look-density later is a deliberate gate re-open, art labor only, gameplay immune either way.

Rendering-quality notes for the implementer:
- `ART_SCALE` lives in `game_config.gd` (it is a visual constant, but §9's "nothing hardcodes a tunable" rule applies in spirit).
- At ~0.75, effective texture scale spans 0.375 (zoom 0.5, minification — needs **mipmaps on import**) to 1.875 (zoom 2.5, upscaling — mild softness on the HD art; judge in the calibration scene). **Linear filtering** for all this art; the project default is nearest (`project.godot:93` — pixel-art setting), so override per-import-preset rather than flipping the default.
- `AnimatedSprite2D.offset` (feet origin) is in **texture space, applied before scale** — compute offsets from native-frame coordinates (e.g. feet at y≈91 of 128), not world px. Encode once in `UnitVisual`.
- Non-integer scale + linear filtering is fine; with nearest it would shimmer in motion — a second reason for the linear override.
- Prefer the packs' **spritesheet strips** (e.g. `2D HD Zombie pack 1/Spritesheets`, 1920×128 per clip-direction) over the individual-frame folders where both exist: thousands fewer files to import and fewer textures at runtime. The individual-frame tree (`Character\Clip\Direction\frame`, with angle-coded filenames like `Idle_270_001` — S = 270°) is the fallback and the naming source of truth for the Stage 1 tool.

---

## 4. Sequencing against the work queue

The migration **absorbs Tier 5 (Phase 5, the readability pass)** — building readability twice (once on ColorRects, again on sprites) would be waste. Proposed order:

1. **Tier 1 ruled bug fixes first** (A1 pursuit-claim leak, A2 test, B3) — unchanged; they protect the validation verdict.
2. Tier 2–4 items as already queued, at Ben's discretion — none conflict with this plan.
3. **Iso migration Stages 0–4** (assets, import, animated units, Y-sort, tile ground) — this replaces the units' placeholder look and lands the depth model.
4. **Stage 5–6 = the new Phase 5** — buildings/props as sprites + the `vision_renderer` readability rewrite (5.1 in the queue), now designed once, against the real art.
5. **Phase 6 (PoC level + sacred-ratio sweep + M1 verdict) builds on tiles** — the §12 level gets authored once, in the final presentation. Validation Q2 ("can you follow who's feral / filling / breaking at horde scale?") is answered against real sprites, which is the honest version of the question.

Scope-control note: this front-loads presentation spend before the M1 verdict, which cuts against "the PoC slice comes before elaboration." The mitigations: (a) Stages 0–4 are deliberately minimal (a handful of characters, one ground layer, no props); (b) Q2 readability genuinely cannot be judged on colored boxes; (c) Phase 6's level is built once instead of twice. If Ben prefers verdict-first, Stages 0–4 can run *after* Phase 6 on the placeholder look — the plan works in either order, but the level and readability pass would then be partially redone.

**Versioning:** each stage that lands a system is a MINOR bump; the whole migration is expected to span roughly v0.44–v0.48.

---

## 5. Stage 0 — Purchase + asset audit *(Ben + agent, ~half a day)*

**Yes, buy the bundle before execution starts.** The plan's Stages 1–2 need exact frame dimensions, sheet layouts, and file naming to build the import pipeline; guessing them would mean rework. The $64.99 bundle beats buying the zombie pack + one tileset separately ($30) the moment any human/character pack or a second tileset is needed — and both will be.

Steps:
1. Ben purchases and downloads the bundle; extract into a **new top-level `art/raw/` directory** (gitignored — see Stage 1 for what gets committed).
2. Agent audits and reports (a written checklist in the ticket, not a doc-sync):
   - [ ] Zombie pack: confirm sheet layout (frames per row, row order = direction order?), frame size, anchor consistency, animation frame counts per clip, shadow variant choice.
   - [ ] **Living defenders:** identify concrete sprite sources for CIV / MIL / POL / GI with idle + walk + run + **shoot** + die. Check HD Character Packs, Enemy Pack, the City tileset's playable character, and whether Character Creator 2D – Modern can export the four classes. **If no combination yields four readable classes, STOP and report — this gates the whole plan.**
   - [ ] Tileset: confirm floor-tile diamond dimensions (expected 128×64 within the 128×256 frame), wall/prop pivot behavior vs the recommended (0.5, 0.19) pivot, and which tiles the PoC level actually needs (a street + sidewalks + a few building footprints is enough).
   - [ ] Gunfire/muzzle FX and blood FX inventory (wanted by Stage 6 readability, not before).
   - [ ] License terms allow use in a commercial game (store page says yes; confirm the included license file).
3. Decide the PoC roster: **2–3 zombie skins** (visual variety only — all identical mechanically; specials are still excluded) + **4 defender classes**. Everything else in the packs is ignored until post-validation.

**Test case:** none (audit stage). Deliverable = the filled checklist + the chosen file list.

---

## 6. Stage 1 — Import pipeline + SpriteFrames generation *(1 session)*

Goal: raw PNGs → committed, engine-ready `SpriteFrames` resources, produced by script (36 characters × 15 anims × 8 dirs is far too much to hand-author, even for our subset).

1. Directory layout (created 2026-07-12; **the entire `/art/` tree is gitignored** because the GitHub repo is *public* and the itch license forbids redistributing the assets — committing any PNG would publish it. Ben keeps the purchased archives as the backup of record; if the repo ever goes private, the curated folders may be tracked again):
   - `art/raw/` — extracted packs as downloaded. Contains a `.gdignore` so Godot never imports the thousands of unused PNGs (editor-scan speed).
   - `art/units/`, `art/tiles/`, `art/fx/` — the curated subset actually used; imported by Godot, still not committed while the repo is public.
2. Import presets: linear filter + mipmaps for the HD art (see §3). Verify `.import` files are committed.
3. Write `tools/build_sprite_frames.gd` (an `EditorScript` or `@tool` script): given a sheet + a manifest (frame size, clips, direction row-order), emits one `.tres` `SpriteFrames` per character with animations named `<clip>_<dir>` (e.g. `run_ne`, `die_s`). Direction suffixes: `e, ne, n, nw, w, sw, s, se`.
4. Run it for the PoC roster; commit the `.tres` files.
5. **Gotcha (CLAUDE.md):** any new `class_name` script needs `<godot> --headless --import --path .` before the parse gate will pass.

**Test cases:** open one generated `SpriteFrames` in the editor and scrub every clip; place a throwaway `AnimatedSprite2D` in a sandbox scene at `ART_SCALE`, run, and eyeball sharpness at zoom 0.5 / 1.0 / 2.5.

---

## 7. Stage 2 — `UnitVisual` behavior component *(1–2 sessions; the core of the migration)*

Goal: replace the `ColorRect` bodies with animated 8-directional sprites, without touching any dispatcher or gameplay logic.

Per ARCHITECTURE_GUIDELINES this is a **new behavior component** (`scripts/unit_visual.gd`, child node on both unit scenes), one mechanic: "render the unit's state". The shells gain zero rendering logic; the component *reads* shell state (signals-up-calls-down: the shell may call `visual.play_oneshot(...)` for events; the component polls state/velocity for continuous anims).

1. **Node changes** in `zombie.tscn` / `human.tscn`: delete the `Body` ColorRects, the legacy hidden `HealthBar`s, and the dead legacy props in `zombie.tscn:13-20`; replace the textureless `$Sprite` (`unit.gd:78` expects it) with an `AnimatedSprite2D` named `Sprite` so existing references keep resolving. Add the `UnitVisual` component node.
2. **Feet origin:** sprite `offset` set so `global_position` = the character's feet. Collision circle (r=12) and all gameplay positions are already at the node origin — only the sprite offset moves. Verify against the pack's anchor (audit item).
3. **Direction bucketing:** `facing_direction` already exists on both shells (`zombie.gd:29`, `human.gd:89`, screen-space unit vector — exactly what 8-dir sprites need). Bucket by `atan2` into 8 × 45° sectors **with hysteresis** (~10° past the sector boundary before switching) so a unit walking near a 22.5° boundary doesn't flicker between directions. Hysteresis is per-unit visual state — it never feeds back into gameplay.
4. **State → clip mapping** (from the packs' 15-clip set):
   | Unit state | Clip |
   |---|---|
   | Zombie CALM idle (shamble pause) | `idle` variant |
   | Zombie CALM shamble / commanded move | `walk` |
   | Zombie FERAL pursuit | `run` |
   | Pounce (flight + kill) | an `attack` clip, fire-and-forget |
   | Zombie death | `die` |
   | **Riser rising** | **`WakeUp`** — the pack has a purpose-built clip for the game's riser mechanic; play it when `GameManager._raise` spawns the riser |
   | Human idle / SENTRY | `idle` |
   | Human patrol | `walk` |
   | Human FLEEING | `run` |
   | Human filling/firing | `shoot` (stop-to-fire — A2 — means armed humans are stationary while aiming, so no run-and-gun blend is ever needed) |
   | Human COWER | crouch/cower clip if the pack has one, else `take-damage` held on a frame, else `idle` + the existing tint |
   | Human death | `die` |
5. **THE INVARIANT (print it in the ticket): animations are cosmetic, never causal.** No gameplay timing, state transition, or kill may wait on an animation. `pounce_flight_time=0.2` etc. remain the only clocks; if a `die` clip is longer than the corpse-linger logic, the logic wins and the visual is cut or freeze-framed. `AnimatedSprite2D` runs on render frames — letting it gate logic would break spec-§10 determinism.
6. **Tints carry over:** FERAL orange / cower blue / dead dark-red currently use `modulate` (`zombie.gd:46-47,216`, `human.gd:417,457`) — they work unchanged on sprites. Revisit whether tints are still needed once real art lands (feral zombies *look* different when running) — that call belongs to the Stage 6 readability pass, not here.
7. Class letters (`human.gd:329-347`) and the `_draw` rings/fill-lines stay as-is this stage; they move in Stage 6.
8. **Walk-speed sync (optional, cheap):** scale `Sprite.speed_scale` to `velocity.length() / reference_speed` so feet don't skate. Cosmetic only.

**Test cases:** boot `puzzle_test_2` (F5): (1) calm zombies idle/shamble with idle/walk clips facing their wander direction; (2) issue a move order — walk clips, correct facing in all 8 directions (drag orders in a circle); (3) release onto a human — run clip during pursuit, attack on pounce, human plays die; (4) wait `rise_time` — riser plays WakeUp then goes calm-idle; (5) armed human plays shoot while its fill line charges; (6) fear-break → run clip toward exit; (7) cower → cower clip + tint; (8) F1 overlay still works; (9) **determinism spot-check via Godot MCP** (boot twice, diff logs) to prove the visual layer added no sim divergence.

---

## 8. Stage 3 — Depth sorting *(small, but load-bearing)*

Goal: nearer things occlude farther things. Currently overlap renders in tree order (survey §8: zero `y_sort_enabled` anywhere).

1. Enable `y_sort_enabled` on the node that parents all units and, later, on the ground `TileMapLayer` and the buildings container — **Y-sort only compares siblings under a Y-sorted parent**, so units, buildings, and props must end up under one sorted hierarchy per level scene. This is a scene-restructure of `puzzle_test_2.tscn` (units live under `TestLevel/Level 7`, buildings under `TestLevel/Buildings`).
2. Feet-origin (Stage 2) is what makes Y-sort correct — a unit sorts by where it stands.
3. Ensure non-diegetic elements stay on top: class labels already `z_index=10`; selection indicators, hunted/hover rings, and `vision_renderer` (`z_index=1`, `top_level=true`) must render above sorted sprites — verify, and bump `vision_renderer` z if needed.
4. Corpses (dead units) should sort *under* live units walking over them: on death, drop the unit's `z_index` by -1 (cosmetic only).

**Test cases:** walk a zombie behind and in front of another unit — occlusion flips as it passes; a feral pouncing over a corpse renders above it; selection rings visible on a unit standing behind another.

---

## 9. Stage 4 — Ground `TileMapLayer` *(1 session)*

Goal: replace the flat `ColorRect` ground (`puzzle_test_2.tscn:63-68`) with isometric floor tiles. Floors only — walls/props are Stage 5.

1. Build a `TileSet` resource: **Diamond Down isometric** tile shape, tile size 128×64 (native diamond), from the audited floor-tile subset (streets, sidewalk, grass — a handful of source tiles, not 1000).
2. Add a `TileMapLayer` (Godot 4.6 — not the deprecated `TileMap` node) scaled by `ART_SCALE`, painted to cover `LevelBounds`. It is **pure visuals**: no tile collision, no tile navigation — physics and nav remain owned by `building.gd`/`wall.gd`/`nav_baker.gd`.
3. The layer participates in the Y-sorted hierarchy (floor tiles sort behind everything standing on them; enable Y-sort on the layer per step 8.1).
4. Keep the `ColorRect` ground in the other sandbox scenes for now — only the run-target scene converts (backwards-compatibility rule: old scenes stay functional).

**Test cases:** boot; ground renders as tiled street/terrain with no seams at all zoom levels; units walk over it with correct occlusion; nav paths unchanged (compare a fixed move order's path before/after — should be identical, since nav never saw the ground).

---

## 10. Stage 5 — Buildings, walls, props as art *(1–2 sessions)*

Goal: replace `ColorRect`/`Polygon2D` placeholder obstacles with tileset art while keeping their **gameplay footprints identical**.

1. `building.gd` (`@tool`, already flagged "will be replaced with sprites" at `building.gd:27`): give it a sprite/tile visual whose **base** matches the existing collision rect. The collision shape and `get_nav_footprint()` (`building.gd:83-93`) stay the source of truth — art is fitted to the footprint, never the reverse, so LOS, navmesh, and shot-blocking behavior are untouched.
2. Iso building art is taller than its base — the sprite extends upward (negative y) from the feet-origin; Y-sort handles units in front/behind. Buildings join the Y-sorted hierarchy with origin at their base's visual bottom corner.
3. `wall.gd` similarly: keep the polygon collider + footprint; render with wall tiles or keep the Line2D look initially (walls are rarer; lower priority).
4. Escape zones: replace the ColorRect with an obvious art treatment (road edge, gate) — must remain readable as "exit" (spec §4.3 matters here).
5. **Parked (do not build):** fade/cutaway when units are hidden behind tall buildings. Level design (Phase 6) should simply avoid placing corridors in full occlusion shadow. Revisit only if the PoC level can't be authored around it.
6. **Parked:** interior tileset, cars-as-obstacles, destructibles, fat-zombie-corpse art (specials are PoC-excluded).

**Test cases:** LOS: a shot lane blocked by a building before is still blocked (same positions); navmesh: F1 overlay path around a building identical pre/post; a feral chasing behind a building is occluded but its hunted-target ring (Stage 6) stays visible.

---

## 11. Stage 6 — Readability pass on real art (absorbs Phase 5 / queue Tier 5) *(1–2 sessions)*

This is queue item **5.1 (vision_renderer migration)** executed against sprites instead of boxes. Scope per the existing queue entry, adjusted:

1. Move rings / fill-lines / class labels / hunted rings off the units' `_draw` (`human.gd:504-570`) into `vision_renderer.gd` (the stub is already `top_level=true`, world-space, `z_index` above the sorted world — survey §9). Takes `human.gd` back under the 400-line tripwire.
2. Re-judge each interim cue against the art: tints (feral orange may be redundant over a running zombie), class letters (may be redundant over distinct class sprites — or keep; cheap and unambiguous at horde scale), selection = an under-feet ellipse marker (reads "grounded" on iso terrain better than the current ±15px square).
3. Blood/gunfire FX from the packs wired to kills and shots — **cosmetic sprites only**, spawned from existing signals (`zombie_killed_human`, the gunshot audio call sites), zero sim impact.
4. `PatrolBehavior` extraction + `unit.gd` rule-2 fixes ride along here (already queued in Tier 5).
5. **M1 bar unchanged:** validation Q2 — at horde scale, can you follow who's feral, who's filling, who's breaking?

**Test cases:** the full Phase-3 test-case re-run (already owed — `phase3-test-criteria` memory) doubles as this stage's regression suite, plus a horde-scale eyeball session for Q2.

---

## 12. Stage 7 — the PoC level on tiles (merges into Phase 6)

Not a separate stage so much as: **Phase 6 proceeds as planned, authored with the City tileset.** Level-authoring workflow: paint the `TileMapLayer` ground, place `Building`/`Wall` nodes for anything that blocks (footprint = truth), place units/escape zones as today. The sacred-ratio sweep, calm-mass-break re-judge, and the M1 verdict are unchanged by this plan.

---

## 13. Risks & watch items

- **Living-defender asset gap** (§5 step 2) — the only plan-gating risk. Verify before anything else.
- **Performance:** ~100 units × `AnimatedSprite2D` at 128px is trivial for `gl_compatibility`; texture memory for the curated subset is small. Watch the first horde-scale boot anyway (F1 FPS).
- **Determinism:** the visual layer must add zero sim reads/writes. The Stage 2 MCP determinism spot-check is the gate; repeat it once after Stage 6 (FX wiring is the likeliest place for an accidental sim touch).
- **Direction flicker** at sector boundaries — mitigated by hysteresis (§7.3); tune the margin by eye.
- **`human.gd` line count:** Stage 2 must not push it further over the tripwire — `UnitVisual` is a component precisely so the shells shrink, not grow.
- **Scene backward compatibility:** sandbox scenes keep working un-converted at every stage (rule 4).
- **CLAUDE.md / GDD / PROJECT_CONTEXT sync:** the 3D-migration wording is now false everywhere. Doc sync stays **Ben-gated** per rule 9 — the trailing doc-sync item in `WORK_QUEUE.md` ("CLAUDE.md 2D-isometric wording") flips from Ben-gated-pending to ready-when-signalled.

## 14. Open questions for Ben

1. **Approve decision A** — ✅ APPROVED by Ben 2026-07-12 (with the decal-oval / range-circle clarification in §2).
2. **Approve decision B** (`ART_SCALE` architecture, world/tunables untouched; value ≈0.75 provisional, frozen via the §3 calibration protocol before Stage 4)?
3. **Sequencing:** iso Stages 0–4 before Phase 6 (recommended, §4), or M1 verdict first on placeholders?
4. **Purchase:** the full bundle ($64.99) up front — approved? (Stage 0 needs the files; see §5.)
5. Shadow or no-shadow character variants? (Baked shadows look good on flat-lit iso tiles and cost nothing; recommend **with shadows**.)
