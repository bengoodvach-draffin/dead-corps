# Iso Migration — Execution Spec & Test Scenarios (Stages 1–4)

**Status:** PROPOSED 2026-07-12 · **Parent:** `docs/ISO_MIGRATION_PLAN.md` (decisions A + B approved; ART_SCALE ≈ 0.75 provisional)
**Purpose:** the concrete, testable plan Ben required before any asset work (Character Creator exports, further purchases). Every part ends in numbered test scenarios with pass criteria. **Ben's asset-work gates are in Part E** — nothing on his side starts until the gate's tests are green.
**Working rules apply per part:** propose-before-implement (this spec is the proposal; each part still gets a go-ahead before code), parse gate after every `.gd` edit, Ben commits manually.

Measured ground truth this spec builds on (from the 2026-07-12 audit of `art/raw/`):
- Zombie pack: 36 characters × 15 clips × 8 dirs (`E,NE,N,NW,W,SW,S,SE` folders) × 15 frames, 128×128 frames, figure ~27×39 px, feet ~y=91, names `Clip_<angle>_<frame>.png`.
- Survivor (City tileset): 20 clips incl. `GunFire`, `CrouchIdle`, `Die`, `Idle`, `Run` (no `Walk` — patrol uses slowed `Run`).
- Tiles: 128×256 frames, floor diamond 128×64 + 16 px skirt; large props 256×512, 4 dirs.

---

## Part A — the asset pipeline tool (Stage 1a)

**New file:** `tools/build_iso_assets.gd` (EditorScript; run from the editor's Script panel, or headless via `<godot> --headless -s`). **New file:** `tools/iso_manifest.json` — the single source of truth for every art source.

Manifest schema (one entry per source pack; per-character overrides allowed):

```json
{
  "world_metrics": { "figure_height_px": 30, "tile_diamond": [96, 48] },
  "sources": [
    {
      "id": "ssi_zombies",
      "root": "art/raw/2D HD Zombie individual sprites",
      "frame_size": [128, 128],
      "native_figure_height": 39,
      "feet_y": 91,
      "fps": 15,
      "characters": ["ZombieMale1", "ZombieFemale1", "ZombieCop1"],
      "clips": { "Idle": {"loop": true}, "Walk": {"loop": true}, "Run": {"loop": true},
                 "Attack1": {"loop": false}, "Die": {"loop": false}, "WakeUp": {"loop": false} }
    },
    {
      "id": "ssi_survivor",
      "root": "art/raw/2D HD Zombie City Tileset/Animations/Individual sprites",
      "characters": ["Survivor"],
      "clips": { "Idle": {"loop": true}, "Run": {"loop": true}, "GunFire": {"loop": false},
                 "CrouchIdle": {"loop": true}, "Die": {"loop": false} }
    }
  ]
}
```

Behavior: for each character, read `<root>/<char>/<clip>/<dir>/*.png` (sorted `naturalnocasecmp_to`), pack all frames into **one atlas texture per character** (a generated PNG in `art/units/<char>/atlas.png` — thousands of separate imports would crawl), and emit `art/units/<char>/frames.tres` (a `SpriteFrames` with animations named `<clip_lowercase>_<dir_lowercase>`, e.g. `walk_ne`, using `AtlasTexture` regions) plus `art/units/<char>/meta.tres` (custom Resource: `source_scale = world.figure_height / native_figure_height`, `feet_offset` from `feet_y`, `fps`). `UnitVisual` (Stage 2) consumes `frames.tres` + `meta.tres` and never hardcodes a scale.

Notes: only manifest-listed clips/characters are processed (PoC roster stays small); the derived source_scale for this pack = 30/39 ≈ **0.77** — the calibration scene (Part B) adjusts `world_metrics.figure_height_px`, not per-node scales. Import preset for `art/units/`: linear filter + mipmaps (project default stays nearest).

**Test scenarios (run before Part B starts):**
| ID | Scenario | Pass criteria |
|---|---|---|
| A1 | Run the tool twice on the same manifest | Byte-identical outputs (deterministic tool; safe re-runs) |
| A2 | Open a generated `frames.tres` in the editor | All `clip_dir` animations present: listed clips × 8 dirs; frames scrub cleanly; loop flags match manifest |
| A3 | Frame-count integrity | Each animation has exactly the source folder's frame count (15); tool errors loudly on a missing dir/clip, never emits silently-partial output |
| A4 | Parse gate + fresh `--headless --import` | `tools/check.ps1` green; no import errors on `art/units/` |
| A5 | Atlas sanity | Generated atlas ≤ 4096×4096 per character (GL compatibility limit); tool splits to multiple atlases if exceeded |

## Part B — the calibration scene (Stage 1b) — where ART_SCALE gets frozen

**New file:** `scenes/iso_calibration.tscn` (throwaway; never shipped). Contents: a hand-built patch of ~12×12 floor tiles (placed as plain `Sprite2D`s at diamond offsets — the real TileSet comes in Part D; this only judges scale), one `ZombieMale1` and one `Survivor` as bare `AnimatedSprite2D`s cycling their clips (a 10-line script, no gameplay), one current-size placeholder unit (a 20×30 ColorRect) beside them for direct comparison, one `building.tscn` instance, and a drawn 250 px circle around the zombie (the fear radius) plus a 40 px circle (pounce range). Standard camera.

**Test scenarios (Ben at the keyboard — this is the eyeball gate):**
| ID | Scenario | Pass criteria |
|---|---|---|
| B1 | Proportion check at zoom 1.0 | Sprite figure height visually matches the placeholder box (±20%); fear circle reads as "about 8 body-heights" — same as today's game feel |
| B2 | Readability at zoom 0.5 (widest) | You can tell zombie from survivor from building at a glance; no shimmer/aliasing in motion |
| B3 | Sharpness at zoom 2.5 (closest) | Upscale softness acceptable (art is ~1.9× magnified); if not, we revisit filtering, not scale |
| B4 | Tile-to-figure ratio | A character standing on the tile patch occupies roughly one diamond's width; cars/props (drop one in) read correctly sized vs the person |
| B5 | Scale tuning loop | Ben adjusts `figure_height_px` in the manifest → re-run tool → reload scene, until B1–B4 all pass. The surviving value is the **freeze candidate** |
| B6 | Freeze | Ben declares the value; recorded in `GameConfig.ART_SCALE` + manifest; after Part D's first painted level it is locked (plan §3 gate) |

## Part C — characters in game (Stage 2) — `UnitVisual` component

**New file:** `scripts/unit_visual.gd` (behavior component per ARCHITECTURE_GUIDELINES; child node of both unit scenes). Scene edits: `zombie.tscn` / `human.tscn` — `$Sprite` becomes an `AnimatedSprite2D` (name kept — `unit.gd:78` resolves unchanged), ColorRect bodies + legacy HealthBars + dead legacy props deleted. The component: buckets `facing_direction` into 8 sectors with ~10° hysteresis; maps shell state → clip (table in plan §7.4: calm idle/walk, feral run, pounce attack, die, riser **WakeUp**; human idle / run-as-patrol-and-flee / **GunFire** on fill / **CrouchIdle** on cower / die); applies `meta.tres` scale + feet offset; `speed_scale` synced to velocity so feet don't skate. **Invariant: animations are cosmetic, never causal — no gameplay timing may read or wait on the sprite.**

**Test scenarios (in `puzzle_test_2`, F5):**
| ID | Scenario | Pass criteria |
|---|---|---|
| C1 | Calm idle + shamble | Idle clip during pauses; walk clip while wandering; facing tracks wander direction |
| C2 | 8-direction move orders | Order a zombie around a circle of waypoints: all 8 clips appear, no flicker at boundary angles (hysteresis works) |
| C3 | Release → pursuit → pounce → kill | Run clip while feral; attack clip fires on pounce; victim plays die and stays as a corpse sprite |
| C4 | Riser | After `rise_time`, riser plays WakeUp exactly at the corpse spot, then calm-idles; still selectable/commandable as before |
| C5 | Armed defender fires | GunFire clip while the fill line charges and the shot lands; stationary while aiming (A2 stop-to-fire visual match) |
| C6 | Fear break + cower | Fleeing human plays run toward exit; cornered human plays CrouchIdle + existing blue tint |
| C7 | Full-map regression | All ~90 humans + 9 zombies animate at once; F1 overlay: no frame-rate collapse (>55 fps on Ben's machine) |
| C8 | **Determinism boot-diff** (Godot MCP) | Boot the scripted scenario twice, diff debug logs — byte-identical; the visual layer added zero sim divergence |
| C9 | Interim readability intact | Selection squares, hunted/hover rings, fill lines, class letters all still visible over sprites (they migrate in Stage 6, not here) |

## Part D — terrain (Stage 4, pulled forward into this spec per Ben's request)

**How painting works (mechanics recap):** build a `TileSet` resource once — every floor PNG registered onto a Diamond-Down isometric grid of **96×48 world px** (native 128×64 × ART_SCALE), with per-tile texture offsets so tall art rises from the cell. Then any level scene gets a `TileMapLayer` using that TileSet; selecting it in the editor opens the tile palette panel, and you paint cells in the viewport with pencil/line/rect/bucket tools that snap to the diamond grid. Ground only — buildings/cars/walls remain placed scene nodes carrying colliders and nav footprints. Optional later: Godot *terrains* (autotiling) so road edges pick themselves.

Work items: extend `build_iso_assets.gd` to emit a tile atlas + `art/tiles/city.tres` TileSet from a manifest tile list (start: ~10 tiles — asphalt, sidewalk, 2 grass/dirt, road markings); **new file** `scenes/iso_terrain_test.tscn` — a sandbox with a painted ground layer + 2 buildings + a few units; then convert `puzzle_test_2`'s Ground ColorRect.

**Test scenarios:**
| ID | Scenario | Pass criteria |
|---|---|---|
| D1 | Seam check | Painted 20×20 patch shows no gaps/overlaps/grid lines between tiles at zoom 0.5 / 1.0 / 2.5 |
| D2 | Paint workflow acceptance (Ben) | Ben paints a two-lane road with sidewalks in **under 10 minutes** using palette tools, no doc-reading required. If this fails, we invest in autotiling before Phase 6 level work |
| D2b | Template workflow (Ben) | Ben saves a painted selection (e.g. an intersection) as a TileMap **pattern** and stamps it 3+ times; pattern persists after editor restart (stored with the TileSet). Structure templates: instance a composite scene (building + props) and confirm all child footprints register in the navmesh bake — templates rule: ground chunks = patterns, structures = scenes; never a TileMapLayer inside a prefab |
| D3 | Y-sort integration | Units walking across the patch always render above floor tiles; a unit behind a placed building is occluded, in front is not |
| D4 | Nav unchanged | Fixed move order across the test scene: nav path identical before/after ground conversion (tiles carry zero collision/nav — compare debug path logs) |
| D5 | Full-scene regression in `puzzle_test_2` | Ground swapped to tiles; win/lose, contagion, fear, riser flows all behave identically (spot-check + C8-style boot-diff) |
| D6 | Perf | 2000×1000 map fully tiled: stable fps at all zooms (TileMapLayer batches — expected trivial; verify anyway) |

## Part E — Ben's asset-work gates

| Ben's task | Gated on | Why |
|---|---|---|
| Nothing yet — Stage 1 runs entirely on already-downloaded assets | — | Zombies + Survivor + City tiles cover Parts A–D |
| Character Creator: export Civilian, Police, GI (8-dir; min clips: Idle, Run, GunFire-equivalent, Die; Civilian needs no shoot) | **C5 green** (Survivor proves the armed-human pipeline end-to-end) | Never export into an unproven pipeline; the manifest tells us exactly what format/clips to export to |
| Shadow vs shadowless decision | Before A-runs (tool takes a variant path) | Recommend shadows; one-line manifest change either way |
| Any further pack purchases (Rural/Interior tilesets etc.) | After the M1 verdict | PoC needs only City |
| Buy/keep decision on unused bundle packs | Post-validation | Scope control |

## Sequencing & version bumps

Parts land in order A → B → C → D, each proposed → built → tested → Ben verifies. A+B together = one MINOR bump (v0.44.0 "iso asset pipeline + calibration"); C = v0.45.0 ("animated units"); D = v0.46.0 ("tile terrain"). Y-sort (plan Stage 3) rides with C (it's what makes C3/D3 pass). Stage 5 (buildings as art), Stage 6 (readability/vision_renderer), and the Phase 6 level follow per the parent plan.
