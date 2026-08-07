# DEAD CORPS — PAUSE & INSPECT SPEC

**Version:** 1.0 (2026-08-07 — design session, Ben/Claude)
**Status:** **DESIGN — core decisions ruled, NOTHING BUILT.** This branch carries the spec only, by Ben's instruction. Rule 1 (propose-before-implementing) applies per slice when it is built: propose the slice, get the go-ahead, then write code.
**Relationship to other docs:** extends `V2_DIRECTION_SPEC.md` (no core-loop rules change); consumes the readability scaffold from PERF_REVIEW F4 (the `vision_renderer` single-canvas-item pattern); shares its info-provider seam with **M2's LMB fill-line inspect** (build plan Phase 7). It changes **zero** sim rules. The only touches to existing sim-adjacent code are two one-argument timer fixes (§A3) and `process_mode` assignments (§A2).

---

## 0. THE THESIS — THE PAUSE IS A READING TOOL

The debug panel has outgrown its column: one word-wrapped label currently carries controls, scoring, and the unit legend (`debug_overlay.gd:31–47`), and the instructions it needs to carry keep growing. Meanwhile the game has accumulated a full terrain vocabulary — doors, gates, fences, mines, wire, stakes, shelters, marks, corpses-about-to-rise — each with state worth reading and none of it inspectable.

The answer is one feature with two faces:

1. **The menu** — Esc pauses the game and opens a panel that holds the full, expanded instructions (and later: settings, restart, quit). The in-game HUD shrinks to a slim strip: live stats + a Menu button + Reset.
2. **The inspect layer** — while paused, the play area stays alive *read-only*: the camera pans and zooms normally, and hovering anything highlights it and pops a small info card — its name, its state, its useful numbers, and a line of flavor.

Why this fits the pillars rather than fighting them: v2 deliberately killed information-hiding. Detection is a cost, not a fail state; **determinism in rules, suspense in execution** *wants* a player who can read the board perfectly and still sweat the chase. Free information during a pause is the "setup is 1/3" phase given a proper surface. And a paused, frozen battlefield is the one place a tooltip can be studied without eating the 2/3 that is momentum.

**What this feature is not:** a tactical-pause layer. See ruling 1.

---

## 1. RULINGS (Ben, 2026-08-07) — do not re-litigate

1. **Inspect-only pause. No actions while paused.** No selection, no orders, no mark placement, no breach clicks — pan, zoom, hover, read. The moment orders work while paused, Dead Corps becomes a tactical-pause game, and planning pressure is supposed to live in real time ("the chase and the combo are 2/3").
2. **Esc opens the menu.** (And closes it — Esc toggles.)
3. **The in-game HUD keeps:** some stats + a Menu button + a Reset button. Everything instructional moves into the menu.
4. **The play area stays interactable while paused** — camera controls live, hover-inspect live — covering humans, zombies, shelter buildings, fences, mines, barbed wire, stakes, escape zones, and the rest of the roster in §C3.

### 1.1 Assumptions taken where no ruling exists (cheap to overturn — say so and they change)

- **Pause and menu are one state.** There is no "bare pause" without the menu panel (no Space-to-pause). One key, one state, one affordance. A separate quick-pause can be added later without touching the design.
- **Pausing is always allowed** — including mid-frenzy with a combo window open. The window freezes with everything else and resumes intact. See §E1 for the score-attack-integrity question this parks.
- **Tooltips show real numbers** (door integrity %, fence press count/threshold, rise countdown), not qualitative fuzz — plus one flavor line. Matches the mine precedent (§B2 of the fences spec: the trigger ring shows the TRUE radius; a hazard hidden from the player is a pillar violation).
- **The existing `debug_overlay.tscn` is evolved in place**, keeping its file path and scene name. All 11 level scenes instance it; keeping the path means zero level-scene edits (rule 4, backwards compatibility).

---

# PART A — THE PAUSE

## A1. Grammar

- **Esc** (or clicking **Menu** on the HUD strip) → `get_tree().paused = true`, menu panel opens.
- **Esc again** (or **Resume** button) → menu closes, `paused = false`. Play resumes exactly where it stopped.
- **Precedence:** if mark mode is armed, Esc cancels mark mode and is consumed (`selection_manager.gd:122` already does this via `set_input_as_handled`); the *next* Esc opens the menu. The pause controller therefore listens in `_unhandled_input`, not `_input` — anything the game consumed first stays consumed.
- **U (restart) while paused: allowed.** `reload_current_scene` tears down the paused tree; the fresh scene's `_ready` hygiene (see A4) restores unpaused state. The Reset button behaves identically.
- **After game end** (end-game overlay visible): Esc still opens the menu — harmless, occasionally useful (reading the final board).

## A2. What freezes, what runs — the `process_mode` map

Godot's tree pause is the whole mechanism. Nothing in the codebase sets `process_mode` today (verified — no occurrences in scripts or scenes), so every node is `INHERIT` → `PAUSABLE`: setting `paused = true` freezes the entire sim for free, `_physics_process` and `_process` and `_input` alike. The work is *exempting* the handful of nodes that must stay awake:

| Node | Mode | Why |
|---|---|---|
| Camera (`camera_controller.gd`) | `ALWAYS` | Ruling 4 — pan + zoom while paused. Its `_process` and `_input` are pure presentation; zero sim effect. |
| DebugOverlay (HUD strip + menu, Part B) | `ALWAYS` | Owns the Esc handler, the Menu/Reset buttons, and must keep updating its stats display (values are frozen anyway — cheap). |
| Inspect layer (Part C) | `ALWAYS` | Hover pick + tooltip + highlight drawing, paused-only by its own gate. |
| End-game overlay | `ALWAYS` | Its buttons must work if a game ends and the player then pauses. (Today it has none — future-proofing, one line.) |
| **Everything else** | default (`PAUSABLE`) | GameManager, all units, all components, doors, fences, HazardField, ComboSystem, ComboHUD, VisionRenderer, SelectionManager — all freeze. |

Two free wins from the default:

- **SelectionManager freezes → ruling 1 costs nothing.** A paused node receives no `_input`, so clicks, box-drags, hotkeys, F, Q/E, C, and control groups are all inert while paused with **zero changes to selection code**. No "if paused return" guards sprinkled anywhere.
- **ComboHUD and VisionRenderer freeze → the picture holds.** Canvas items persist when processing stops; the last drawn frame of selection boxes, fill lines, and the combo bar simply stays put — a correct frozen snapshot of the moment. (`queue_redraw` on a paused node still repaints — drawing is not processing — which C5 exploits.)

## A3. Determinism (§10) — pause is safe by construction, with one audit

`get_tree().paused` stops the physics tick stream entirely; it does not scale, skip, or fractionalize ticks. Tick N+1 after unpause follows tick N exactly as it would have — a paused run and an unpaused run produce byte-identical sim streams. This is verifiable with the existing harness: boot `level_testing` with auto-frenzy twice, pause/unpause erratically during one run, diff the event logs (the §10 boot-twice diff, third variation).

**The one leak: `SceneTreeTimer` ignores pause by default.** `get_tree().create_timer(0.3)` has `process_always = true` unless told otherwise. Both live call sites are the corpse-linger awaits — `zombie.gd:452` and `fat_zombie.gd:78`. Left alone, a corpse would finish its linger and *free itself mid-pause* — a body vanishing off the frozen board, possibly while the tooltip is reading it. Fix is one argument at each site: `create_timer(0.3, false)`. No behavior change unpaused; corpses hold under pause. **This is the only edit the pause makes inside a unit script.**

(`game_time` accrues in `GameManager._process` — freezes with its node. The combo window drains in ComboSystem — freezes. Riser countdowns tick in `ViolencePipeline.tick` from `_physics_process` — freeze. No other wall-clock sources exist in sim code.)

## A4. Fast-forward interplay — one blunt rule

F's handler lives in the (paused, inert) SelectionManager, so if the player pauses *while holding F*, the key-release event is never delivered and `Engine.time_scale`/`physics_ticks_per_second` would stay at 3× behind a frozen tree — then resume at 3× on unpause. Engine singletons also survive scene reloads (the known restart-mid-held-F trap, `selection_manager.gd:62–67`).

**Rule: opening the menu force-resets fast-forward** — the pause controller sets `time_scale = 1.0`, `physics_ticks_per_second = 60` (the same normalization `_ready` already does). Unpause always resumes at 1×; the player re-holds F if they want it. Blunt, stateless, no edge cases. Do not build "restore the held-F state on unpause" — it saves half a keypress and buys a state machine.

## A5. What pausing must NOT do

- Not clear the selection, the group route viz, queued waypoints, or mark mode's armed state — everything resumes untouched. (Exception: fast-forward, A4, deliberately reset.)
- Not affect `game_time`, the combo window, rise timers, door/fence meters, or cooldowns — all frozen, all resume in place.
- Not change the cursor except via the inspect layer's own hover affordance. If mark mode was armed, the crosshair persists through the pause — correct, since the armed state does.

---

# PART B — THE HUD SPLIT

## B1. The in-game strip (replaces the debug panel)

Top-left, one compact `PanelContainer` (evolving the existing `InfoPanel`):

```
Zombies 12   Humans 34   Escaped 2   Selected 6
[ MENU (Esc) ]  [ RESET (U) ]
```

- Stats stay the current four (`debug_overlay.gd:73-78` unchanged in substance). The strip shows *state*, never *instructions*.
- Buttons show their hotkey — that's most of the key-teaching surface players actually read.
- The `ControlsLabel` and its separators are deleted from the strip; the text moves into the menu, expanded (B2).
- Reset keeps its existing cleanup path (`cleanup_all()` then reload).

## B2. The menu panel

Opens centered-left (Ben's sketch: "a menu in the top left"), sized for reading, over a dimmed backdrop that does NOT cover the whole screen — the play area must stay visibly alive for inspection, so dim the panel's own region only, or use no backdrop at all. Content, in order:

1. **CONTROLS** — the full current sheet, correcting everything the old label understates or gets wrong (it still says nothing about doors, fences, buildings, corpses, F, Q/E, C, U, shift-waypoints):
   - Selection: LMB / drag / Shift+LMB; Q all calm; E on-screen calm; Ctrl+1-9 / 1-9 groups.
   - Orders: RMB move; Shift+RMB waypoint chain (attack as final waypoint); RMB on human = **RELEASE** (no recall, ever); RMB on occupied building = siege release; RMB on intact door = calm breach order; RMB on fence = press order; corpse commands (select a body, order it before it rises).
   - The Mark: C arms, LMB places/clears, Esc/RMB cancels.
   - Time: hold F = 3× fast-forward; U = restart; Esc = this menu.
   - Camera: WASD/arrows pan, wheel zoom.
2. **SCORING** — the tiered combo base, burst/terror multipliers, window banking, and that gunfire losses and escapes score zero (spec §6, current text carried over and slightly expanded).
3. **READING THE BOARD** — the unit legend (calm white / feral orange / dead red / cower pale-blue; M/P/G class stamps; ★ special; hunted ring; fill line) plus a **new object legend**: door bar, fence posts + press badge, mine dot + true-radius ring, wire/stake glyphs + the stake arrow, shelter footprint, escape zone. One line each — the tooltip (Part C) is the detail surface; the legend just teaches "hover it to learn more."
4. **Buttons:** Resume · Restart. (Settings/quit are post-PoC — the panel's VBox is the seam.)

Instruction text lives as `const` blocks in the overlay script, exactly as today — one home, no content files, no i18n machinery for a PoC.

## B3. File plan

`scenes/UI/debug_overlay.tscn` + `scripts/debug_overlay.gd` keep their paths and evolve (assumption §1.1). The scene gains the menu panel and the script gains pause ownership — it is already instanced by every level, already `layer = 100`, already owns Reset. Rename of node/class is deliberately NOT done (rule 7's spirit: don't shadow/duplicate; PROJECT_CONTEXT's purpose-table entry updates at the next Ben-gated doc sync).

Estimated size after: ~250 lines — under the ARCHITECTURE_GUIDELINES tripwire. If the menu content pushes it past ~400, the split is `pause_menu.gd` (panel + text) owned by the overlay shell, not a second CanvasLayer.

---

# PART C — THE INSPECT LAYER

## C1. Interaction

While paused (and only while paused — M1 scope), the object under the cursor gets:

1. **A highlight** — the existing hover affordance where one exists, a drawn ring/outline where one doesn't (C5).
2. **A tooltip card** — screen-space panel near the cursor, offset down-right, edge-clamped to the viewport. Title line + state lines + one flavor line (C3/C4). Follows the cursor; disappears when nothing is picked.

No click behavior exists while paused, on anything (ruling 1). The card is hover-only.

## C2. The pick model — deterministic, physics-free

One pick per rendered frame, paused only (perf: trivial). **No physics queries** — registry + geometry only, consistent with registry-only discovery, and all of it works identically under pause:

| Priority | Type | Test |
|---|---|---|
| 1 | Living units (zombie, human) | nearest within **30px** of cursor via `neighbours_within` ×2 teams (the click-selection tolerance, `selection_manager.gd:347`) |
| 2 | Pending-rise corpses | nearest within 30px via `gm.rising_corpses()` |
| 3 | Mines | cursor within `trigger_radius` (min 14px), nearest; group `"hazards"` |
| 4 | Doors (incl. gates) | the `_door_at` rule: within `door_width/2 + 16px` — but hitting breached doors too (a breached door is readable: "BREACHED") |
| 5 | Fences | `click_hit(pos)` (existing pick strip + margin), folded included |
| 6 | Hazard zones (wire/stakes) | `contains(global_pos)` |
| 7 | The Mark | within the placement-clear radius (28px) of `gm.mark_position()` when active |
| 8 | Escape zones | point in zone rect |
| 9 | Shelter buildings | `contains_point`, **innermost wins**: among containing footprints pick the smallest area — the inspect layer must not inherit the known first-match nested-building bug (WORK_QUEUE "still open"), and its innermost rule is the model for that fix |
| 10 | Walls / dumb boxes / legacy buildings | `contains_point` on footprint — lowest priority, one-line card |

Priority = the table order: first category with a hit wins (point objects beat area objects; small beats large). Ties inside a category break nearest-first, then `unit_uid`/tree order — the registry's own contract. Static object groups are cached once on first pick (the SelectionManager `_fences_cache` pattern).

## C3. Tooltip content — the roster

Format: **TITLE** · state line(s) · *flavor line* (italic, C4). Numbers are live reads through existing public accessors; the two starred rows need new thin accessors (D2).

| Object | Title | State lines |
|---|---|---|
| Zombie (calm) | name (C4) — "Zombie" | `Calm` / `Calm — breaching <door>` (`is_calm_breaching`); group # if any |
| Zombie (feral) | name — "Feral" | `Hunting <prey name>` / `Besieging <building>` ★ (feral target accessor); `Finishing` during recovery |
| Special zombie | "Fat Zombie" / "Costume" | costume: `Disguised — humans ignore it`; excluded-verb notes kept to one line |
| Human | name — class ("Police") | state: `Idle` / `Fleeing` / `Sheltered in <building>` / `Cowering` / `Filling — will fire when full` (`fill_front().is_reached()`); armed y/n; ★ special: "Special — kill to earn the <type>; escapes are gone for good" |
| Corpse (pending rise) | name — "Corpse" | `Rises in N.Ns` ★ (rise-remaining accessor); queued order/group if any |
| Corpse (permanent) | name — "Corpse" | `Not rising` (gunfire-made corpses / risers already spent) |
| Door / gate | "Door" / "Gate" | `Integrity N%` (`integrity_fraction`); `Locked` (`is_locked`); `Breached`; `Starts open` portals: `Open` |
| Fence | "Fence" | `Pressing: N of M` (`press_count`/`threshold`); fold meter % when filling; `Folded — humans still can't cross` |
| Mine | "Mine" | `Armed — kills one zombie, once` / `Disarmed` / `Spent (crater)`; `Triggers on humans too` when `affects_humans` |
| Wire zone | "Barbed wire" | `Slows everyone who crosses` (+ factors) |
| Stake bed | "Stakes" | `Kills zombies charging INTO the points` (+ the arrow direction); `Humans weave through, slowed` |
| Shelter building | "Shelter" | `Occupants: N` (`living_occupants().size()`); `Intact` / `Breached`; door count |
| Escape zone | "Escape route" | `Humans escape here — zombies cannot follow`; `Escaped so far: N` |
| The Mark | "The Mark" | `Ferals are drawn here` (one line; the verb is pre-workshop — keep the card from over-promising) |
| Wall / dumb box | "Terrain" | `Solid` — nothing else |

The card is also the home for **genuinely useful info that has no other surface**: the mine's humans-trigger flag, a door's lock state before anything has touched it, which building a flusher wrote off — none of that is currently readable at all.

## C4. Names and flavor — deterministic bios

- **Humans get names and a one-line bio**; a zombie's card reuses the identity machinery ("Shambler #7"-grade names acceptable for M1; see the riser rule below for where it gets good).
- Source: static content tables in the inspect content script — arrays of names and per-class bio lines. Selection is `DetHash.jitter(unit_uid, BIO_SALT)` indexed into the table: stable for the whole run, identical across identical runs, **zero RNG** (§10). No storage, no assignment pass — pure function of uid.
- Tone: dry gallows humor, Hotline-Miami-adjacent, one line, never mechanical advice. ("Militia. Dave, 34. Misses his boat." / "Civilian. Was told the docks were safe.")
- **The riser carryover (the flavor payoff):** when a corpse rises, the new zombie's card shows the human's name — "Dave — Feral". Requires passing one string through `ViolencePipeline._raise` → `spawn_zombie` → a `display_name` field on Unit (default empty = named by uid table). Optional; ship the layer without it if it drags — but it is the single best line item in this spec for making the horde *yours*.
- Flavor content is a **content pass**, separable from the layer build (D3 slice 3).

## C5. Highlight rendering

- **Reuse where it exists:** Human, Door, Fence, ShelterBuilding already have `set_hover_highlighted` with their own drawn affordances. `queue_redraw` repaints paused nodes fine (drawing is not processing) — these work under pause untouched. The inspect layer must clear the flag on unhover/unpause (the SelectionManager hover pattern, `_update_release_hover`).
- **Draw the rest itself:** zombies, corpses, mines, zones, escape zones, the Mark get a simple ring/outline drawn by the inspect layer's own world-space `Node2D` (`top_level`, z above VisionRenderer's 10) — the F4 single-canvas-item pattern, one item, redrawn once per frame while paused.
- No new drawing added to any unit script (F4 invariant: units carry no presentation).

## C6. The seam with M2

The card's data comes from one static provider: `InspectInfo.info_for(object) -> Dictionary {title, lines, flavor}`. The pause layer is its first consumer; **M2's live LMB fill-line inspect is its second** — same cards, unpaused, for whatever that design lands on. Build the provider as if both callers exist. This is why the inspect layer gates on `paused` itself rather than assuming it (one `if` to delete when live inspect arrives).

---

# PART D — ARCHITECTURE & BUILD PLAN

## D1. Files

| File | Change | Est. size | Owner/notes |
|---|---|---|---|
| `scripts/debug_overlay.gd` + `scenes/UI/debug_overlay.tscn` | evolve in place: strip + menu + pause ownership (Esc, `paused`, FF reset) | ~250 | the pause state's single owner; ALWAYS |
| `scripts/inspect_layer.gd` (new, `class_name InspectLayer`) | pick + highlight node + tooltip panel; paused-gated | ~300 | ALWAYS; spawned by GameManager if absent (the `_ensure_vision_renderer` pattern) — levels need no edit |
| `scripts/inspect_info.gd` (new, static) | the per-type card provider (C3) | ~200 | static, no state — component rule for statics |
| `scripts/inspect_bios.gd` (new, static) | name/bio tables + DetHash lookup (C4) | content-sized | pure data + one function |
| `scripts/camera_controller.gd` | `process_mode = ALWAYS` in `_ready` | +1 line | |
| `scripts/zombie.gd`, `scripts/fat_zombie.gd` | `create_timer(0.3, false)` | 2×1 arg | §A3 — the only sim-script edits |
| `scripts/violence_pipeline.gd` + GM delegate | `rise_remaining(corpse) -> float` | ~6 | ★ C3 |
| `scripts/zombie.gd` | `feral_target_name() -> String` (or equivalent thin read over FeralBrain state) | ~8 | ★ C3, rule 5 — no reaching into components |
| `scripts/end_game_overlay.gd` | `process_mode = ALWAYS` | +1 line | future-proofing |

New `class_name` scripts ⇒ regenerate the global-class cache (`--headless --import`) before the parse gate — the known trap.

## D2. New accessors — and nothing else

The two starred accessors above are the entire sim-facing API this feature needs. Everything else in C3 reads accessors that already exist (built for VisionRenderer/F4, which is exactly why this layer is cheap now). If an implementer finds themselves adding a third accessor, the card is over-reaching — cut the line instead.

## D3. Build slices (each: propose → approve → build → parse gate → test cases)

1. **v0.50.0 — Pause + menu + HUD split.** Parts A + B whole. Independently shippable and testable with no inspect layer.
2. **v0.51.0 — The inspect layer.** Part C with placeholder names ("Zombie", "Police"). Provider seam included.
3. **Content pass — bios + riser carryover.** No version bump on its own unless the carryover plumbing lands (then it rides the next minor).

## D4. Test cases (for Ben, when built)

Slice 1: Esc opens menu + freezes everything (watch a mid-flee human, a draining combo bar, a pounding door — all stone); WASD/zoom still work; clicks/hotkeys do nothing; Esc resumes and all three continue exactly where they stopped; pause while holding F → unpause runs at 1×; kill a zombie, pause during the 0.3s corpse linger → corpse persists until unpause; U works while paused; mark mode armed → first Esc drops crosshair, second opens menu; §10 spot-check: auto-frenzy run with erratic pausing diffs clean against an unpaused run.
Slice 2: hover each roster row in C3 on a docks boot and confirm the card + highlight; corpse card counts down only while unpaused; overlapping cases (corpse on mine, gate in wall, shop in market) pick per the C2 priority; card follows cursor and clamps at screen edges; unpause → layer disappears and hover-release rings return to SelectionManager's rules.

---

# PART E — PARKED / OPEN QUESTIONS

1. **Pause during an active combo window** — allowed for now (§1.1). If post-PoC score-attack play makes free mid-frenzy scouting feel like cheating, the cheap lever is banking/freezing rules, not banning pause. Revisit only on a real playtest signal.
2. **Live (unpaused) hover inspect** — deliberately not in scope; it is M2's LMB fill-inspect question and goes through that design conversation. The provider (C6) is built for it.
3. **Bare pause without menu (Space)** — cut for one-state simplicity; trivial to add later.
4. **Settings in the menu** (volume, edge-scroll toggle) — post-PoC; the panel's button column is the seam.
5. **Tooltip verbosity toggle** (numbers vs terse) — not unless playtesting says the cards are noisy.
6. **The Mark's card text** — placeholder until the Mark workshop lands; the card must not document a verb that is about to change.
