# DEAD CORPS — READABILITY SPEC (Phase 5 proper)

**Version:** 1.0 (2026-08-07 — design session, Ben/Claude)
**Status:** **DESIGN — NOTHING BUILT.** This branch carries specs only. Companion to `V2_PAUSE_INSPECT_SPEC.md` — the two are intended to be built in the same window and share a drawing altitude (§6). Rule 1 applies per slice when built.
**What this executes:** direction spec **§7** (fill lines, tints, riser read, cower indicator, Mark decal, combo pops) and build plan **5.1**, on top of the **F4 scaffold** (`vision_renderer.gd`, built 2026-08-03 — one camera-culled canvas item drawing all unit presentation, pixel-parity with the old per-unit visuals). F4's own header says it: *"the actual readability DESIGN pass (Phase 5 proper, the M1 Q2 bar) iterates on top of this scaffold, with Ben, later."* This is that pass, on paper.
**The bar it gates:** validation **Q2** — *can you follow who's feral, who's filling, who's breaking, at horde scale?* Phase 6 (the PoC level + M1 verdict) waits on it.

---

## 0. THE THESIS — READABILITY IS GAME INFORMATION, NOT DECORATION

The pillars make perfect information a design commitment: determinism in rules, no hidden information, suspense from execution. That promise is only kept if the state actually *reads*. Today it mostly does at 6 units and mostly doesn't at 200: feral-vs-calm is a tint on a 20px rectangle, "about to fire" is a line whose meaning you have to already know, a fear break looks identical to a casual stroll, and a riser is a red rectangle that abruptly isn't.

The scaffold (F4) solved *where* presentation lives and *what it costs*. This spec decides *what it says*. Three reads must survive a 200-unit brawl at min zoom:

1. **Who's mine and in what mode** — calm reserve vs committed frenzy vs bodies-becoming-zombies.
2. **Who's about to hurt me** — which humans are filling, how close each is to firing.
3. **What just changed** — ignitions, kills, breaks, breaches: the one-tick events that drive every player decision, currently invisible between frames.

Not art. The units stay programmer-art rectangles until the iso skin (`ISO_MIGRATION_PLAN.md`) replaces the *bodies* — everything in this spec is the **informational layer that survives that skin** (rings, lines, tints, traces map onto sprites and animations later; §7 records the slots).

---

## 1. INVENTORY — what already reads (this pass is a delta, not a rebuild)

| Layer | Exists today |
|---|---|
| Unit tints (modulate) | zombie calm white / feral orange / dead dark-red; human cower pale-blue, corpse red |
| `vision_renderer.gd` | selection boxes, group numbers, class letters M/P/G, special ★, hunted ring, hover ring, fill line (grows toward target, flips red at reached), corpse route cues |
| `selection_manager.gd` | box-select rect, group-route waypoint viz, release/siege/breach/press hover telegraphs |
| MarkSystem | the purple attention-field render |
| Terrain self-draws | door bar + lock, fence posts/sag + press badge + count, mine dot + true-radius ring + crater, wire/stake glyphs + stake arrow, shelter walls/floor, escape zone rect |
| ComboHUD | SCORE, live pot ×mult, draining window bar, gold bank popup |

Build plan 5.1's caveat applies: *"if a debug rendering from earlier steps already reads, this pass is small."* Much of it does. The gaps are: state variants inside FERAL (finishing/pouncing/breaching read as plain feral), fill *progress* (the line grows but carries no "how close" anchor), fear breaks and ignitions (one-tick events, invisible), the riser timeline (corpse → rising → standing has no cue), and cower (a tint that reads "odd blue" not "frozen prey").

---

## 2. THE LAWS (design constraints, non-negotiable)

1. **One altitude.** All unit-attached information draws in `vision_renderer.gd`; terrain draws itself; screen-space HUD is ComboHUD + the overlay. No per-unit presentation nodes, ever (the F4 invariant — it bought nodes 8,552 → 5,229 and the batched render).
2. **Color is state, shape is identity, motion is event.** The palette is a *vocabulary*, kept small on purpose: **orange = the frenzy** (feral family), **blue = fear** (cower/break family), **gold = score** (combo family), **white = player attention** (selection/hover/rings), **red = death/danger** (corpses, reached fills). A new visual must reuse the family it belongs to, not mint a color.
3. **Deterministic animation.** Every pulse, flash, and decay is keyed to `GameManager.sim_tick` (or per-unit `DetHash` phase off it) — never wall clock, never RNG. Two identical runs render identically; a §10 log diff stays clean; and a *paused* frame freezes mid-flash correctly, which the pause-inspect feature turns into a study surface.
4. **Invisible in the sampler.** The whole pass must not move the perf floor: still one culled item, no allocations in `_draw` hot loops, event traces bounded (§5). F4 was the perf fix and the readability plan as one piece of work; keep it true.
5. **Iso-forward.** Anything that is really a *body* read (a pose, a gait, a scream) is specced as a **slot** — a named hook the iso animations fill later — with a cheap geometric stand-in now. No sprite work, no audio assets (hooks only).
6. **Events get traces, not frames.** A one-tick sim event rendered for one tick is invisible at 60fps. Events that matter draw a short decaying glyph (§5), long enough to catch peripherally (~0.5s), short enough not to smear the board.

---

## 3. THE UNIT STATE LANGUAGE

Per state: what it shows today → what it shows after. Constants live in `vision_renderer.gd` beside the existing F4 block; all tint values stay in the unit scripts (tints are cheap and already there).

### 3.1 Zombies

| State | Today | After |
|---|---|---|
| CALM idle/moving | white | unchanged — white is the "yours, obedient" baseline everything else deviates from |
| CALM breaching (`is_calm_breaching`) | white, nothing | white + a short **pound tick** toward the door each pound (a 6px chevron pulsing on the door line, sim-tick keyed) — reads "working on terrain, still yours" |
| FERAL pursuing | orange | unchanged orange body; the *target end* is already carried by the hunted ring on prey — no per-feral line (200 chase lines is smear, the ring aggregates) |
| FERAL mid-pounce (`is_mid_pounce`) | orange | orange + **motion streak** (a 12px fading tail along velocity) — the lunge is the game's signature moment and currently draws nothing |
| FERAL finishing (`is_finishing_kill`) | orange | orange + **white corner brackets** (selection-box corners, not the full box) — "this one is briefly selectable/commandable" is a real decision window the player can't currently see |
| DEAD (corpse linger) | dark red 0.3s | unchanged |
| Special (costume/fat) | ★-adjacent reads per specials spec §5 | unchanged (ruled 2026-08-06 — do not re-open) |

**Ignition** (calm → feral, contagion or release) is an event, not a state → §5.

### 3.2 Humans

| State | Today | After |
|---|---|---|
| IDLE / SENTRY | brown + class letter | unchanged |
| Filling | line grows toward target, red at reached | **two-tone fill line**: a faint full-length track from human to target + the bright portion advancing along it — "how close to firing" becomes a glance read at any zoom (the Q2 "who's breaking [me]" answer). Red at reached, unchanged. |
| Fires (kill or miss-block) | nothing — shots are invisible | **shot trace**: one bright 2-tick line human→victim + a muzzle tick, then §5 decay. Gunfire is the lose-condition engine; it must be visible where it happens, not only in the count. |
| FLEEING | motion only | motion + **heading tick** (a 5px arrow at the body's leading edge) — at horde scale "running" vs "walking somewhere" needs one glyph; also the read for herding feedback (the arrow bends where your wall bends them) |
| Fear break (the *instant*) | nothing | event trace, §5 — a blue burst ring at break position. *This is the single highest-value item in the spec:* "who's breaking" is Q2 verbatim and currently renders as nothing at all. |
| SHELTERED | invisible (inside walls) + armed door-watch line | building-side read instead: **occupancy badge** on the shelter (small `N` chip near its centre, already how fences show their count). Door-watch lines unchanged. |
| COWER | pale-blue tint | tint + **huddle mark** (the rectangle draws ~20% shorter via a scale-y modulate — the "pose" slot, iso crouch later) + the **scream hook** (named audio event slot, no asset). Cower is a scoring object (terror bonus); it should look like prize, frozen. |
| Corpse, pending rise | red + route cue | red + **rise arc**: a thin circular progress arc over the body filling as `rise_remaining` counts down (accessor shared with the inspect tooltip — one read, two consumers). The riser timeline is player resource planning; §7's "riser state readable" verbatim. |
| Corpse, permanent | red | unchanged (no arc = not rising — the absence is the information) |

### 3.3 Aggregate reads (unchanged, listed for completeness)

Hunted ring (the engagement read), release/siege/breach/press telegraphs, the Mark's purple field, patrol path visuals. The Mark's *decal polish* waits for the Mark workshop — same rule as its tooltip card (pause spec §E6): don't polish a verb that's about to change.

---

## 4. TERRAIN DELTAS (small on purpose — terrain mostly reads)

- **Door:** intact bar + integrity + lock read fine. Add the **breach burst** to §5 (the door's `breached` signal already exists) — a breach mid-horde currently just *disappears a bar*.
- **Fence:** posts/sag/badge/count read fine. Add the **fold burst** (§5, `folded` signal exists).
- **Mine:** detonation gets a §5 burst at the crater (the kill itself routes through `report_hazard_kill` — trace hooks there). Armed/crater states already read (fences spec §B2/§B5 — the corpse-road).
- **Wire/stakes/escape/walls/shelters:** no change beyond the shelter occupancy badge (§3.2).

---

## 5. EVENT TRACES — the one structural addition

A tiny ring buffer on `vision_renderer.gd`: `{type, pos, tick}` entries, drawn each frame with alpha/size decayed by `(sim_tick - tick)`, evicted after ~30 ticks (0.5s) or when the buffer caps at **64** (oldest first — a mass release must not turn the renderer into the perf problem it replaced; a capped, silent-drop buffer of *cosmetic* traces is acceptable loss).

| Trace | Trigger source | Glyph (all sim-tick decayed) |
|---|---|---|
| Ignition | `ignite_feral` / contagion (report via GM — one call site each) | orange ring expanding from the zombie, 12→28px |
| Pounce kill | `zombie_killed_human` (GM already receives it) | red slash burst at the victim |
| Gunfire kill | `report_gunfire_kill` (exists) | white-red tick at the zombie + the §3.2 shot trace |
| Fear break | `start_fleeing` when triggered by FearDetector (thin report call, D2) | blue ring burst, 10→40px |
| Breach / fold | `Door.breached` / `Fence.folded` (exist) | dust burst at the gap |
| Mine detonation | `report_hazard_kill` (exists) | flash + smoke tick over the crater |
| Combo pop | ComboSystem multiplier increment (§7 "burst increments should pop") | HUD-side: the ×mult text scales up-and-settles over ~10 ticks — in ComboHUD, not the world layer |

Determinism note: traces are *read-only observers* of sim events, keyed to the tick the event occurred — they can never influence the sim, and identical runs produce identical trace streams. Under pause the whole board freezes mid-decay, which is exactly right.

## 6. SHARED ALTITUDE WITH PAUSE-INSPECT

Built in the same window, these must agree on the stack: units (z 0) → VisionRenderer (z 10, world) → InspectLayer highlights (z 11, world) → CanvasLayers (ComboHUD, overlay at 100). The inspect layer's rings reuse the **white = attention** family; its tooltip text refers to states by the same names this spec draws (a card saying "Filling — will fire when full" points at the two-tone line). The `rise_remaining` accessor and the fear/ignition report calls are specced once (pause spec D2 + this §5) and consumed by both features. **Recommended build order: this spec's slice R1 first, then the pause/menu, then the inspect layer** — the inspect layer highlights whatever language R1 lands, not the other way around.

## 7. NON-GOALS (do not build)

- No sprites, animations, or audio assets — iso skin territory (`ISO_MIGRATION_PLAN.md`); this spec's poses/screams are named slots with geometric stand-ins.
- No vision cones, arcs, facing lines — deleted by the pivot, stay deleted (direction spec §7).
- No minimap, no floating score numbers in the world (the combo lives in the HUD; a +N at every kill site during a 20-kill chain is confetti, not information — revisit only on playtest demand).
- No ComboHUD layout redesign — the pop (§5) is the only change.
- No per-feral chase lines (§3.1 — the hunted ring aggregates on the prey side, where the player's eye already is).

## 8. ARCHITECTURE & NEW SURFACE

| File | Change | Notes |
|---|---|---|
| `scripts/vision_renderer.gd` | the state-language deltas (§3) + the trace buffer (§5) | est. ~197 → ~420 lines. **At the ~400 tripwire:** if it lands over, split the trace buffer to `scripts/event_traces.gd` (a child drawing node owned by the renderer) — pre-approved split, don't agonize |
| `scripts/fill_behavior.gd` | `fill_fraction() -> float` (progress 0–1 for the two-tone line) | thin accessor, rule 5 |
| `scripts/violence_pipeline.gd` (+GM delegate) | `rise_remaining(corpse)` | **shared with pause spec D2** — one accessor, two consumers |
| `scripts/flee_behavior.gd` or `human.gd` | one `report_fear_break` call to GM → renderer | the only new cross-system call |
| `scripts/zombie.gd` | one trace report in `ignite_feral`/`ignite_feral_at_building` | |
| `scripts/combo_hud.gd` | the ×mult pop | ~10 lines |
| Unit scripts | tint constants only if values change | tints stay where they live |

No new input, no new config knobs (decay lengths and glyph sizes are renderer constants — they're presentation, not §9 tunables), no sim writes anywhere.

## 9. BUILD SLICES (each: propose → approve → build → parse gate → cache regen if new class_name → test cases)

1. **R1 — the state language** (§3 tables + §4 badge): tints, brackets, streaks, two-tone fill, rise arc, huddle. One MINOR (target v0.5x.0 in sequence with the pause feature — Ben's call on ordering per §6's recommendation).
2. **R2 — event traces** (§5): buffer + the seven trace types + report calls. Same minor or the next — scope call at proposal time.
3. **R3 — Q2 drill + tuning**: the validation exercise below, with Ben, adjusting constants only. No version bump (tuning).

## 10. TEST CASES / THE Q2 DRILL

- Boot docks, release a wave, **look away for 5 seconds, look back**: within ~2s of watching, answer — who's feral, who's filling (and who fires *next*), who broke since you looked away (blue rings still decaying). That's Q2 passed or failed, live.
- Same board, **paused**: the frozen frame alone must answer "who's feral / filling / breaking" — every state readable with zero motion (this is the pause-inspect synergy test; motion may *help* but must not be load-bearing).
- Fast-forward (held F) — traces decay 3× faster in wall time, identically in ticks: confirm no flicker artifacts.
- §10 determinism spot-check unchanged: traces observe, never write — auto-frenzy boot-twice diff stays byte-identical.
- Perf: standard load test (44z/447h), sampler before/after — presentation delta must be within noise at the mass-frenzy census.

## 11. RULINGS (Ben, 2026-08-07 — asked and answered at spec time; do not re-open at R1)

1. **Palette approved as specced** (§2 law 2) — the five families are law.
2. **The readability contract is 1.0×.** The full state language must read at 1.0× zoom and closer; at 0.5× only the loud layer — event traces, hunted rings, tints — needs to read, and the overview being strategic-blob-scale is intentional.
3. **The fleeing heading tick is IN for R1** — and is the designated *first cut* if the Q2 drill shows a busy board. No other item gets cut before it.
4. **The cower scream is once per cower-cluster**, not per cowerer — a punctuation mark, not a chorus. Write the hook that way now (fires on the first cower in a cluster within a short window; dedupe by proximity), so the audio pass inherits the right shape.
