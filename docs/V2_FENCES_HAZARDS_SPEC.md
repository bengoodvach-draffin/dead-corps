# DEAD CORPS — FENCES & HOSTILE TERRAIN SPEC

**Version:** 0.2 (2026-08-01 — Ben's rulings folded in)
**Status:** **DESIGN DRAFT — NOTHING BUILT.** The four load-bearing calls are ruled (§1); the design is ready to be sliced and proposed for build. Rule 1 (propose-before-implementing) still applies to every slice below — this doc licenses the *design*, not the code.
**Scheduling:** promoted out of `TROPE_IDEATION_2026-07-27.md` (§2.1 foldable fences, §2.2 hazard terrain), whose own gate was "post-M1-verdict at the earliest". **Ben moved that gate on 2026-08-01: both features are pulled forward**, the way enterable buildings were on 2026-07-23, so the Phase 6 PoC level can be built with the full terrain vocabulary available. See §C1 for the sequencing that keeps this from destabilising the M1 verdict.
**Relationship to other docs:** extends `V2_ENTERABLE_BUILDINGS_SPEC.md` (the terrain kit, §16.2) and `V2_DIRECTION_SPEC.md`. It changes **three** existing rules, each flagged where it appears: the feral give-up failsafe gains an exemption (§A6.2), `report_gunfire_kill` stops being the only way a zombie can die (§B6.1), and — the big one — **the navmesh stops being one mesh for everybody** (§A9 / §B3). Everything else is additive.

---

## 0. THE THESIS — THREE BARRIERS, THREE CURRENCIES

The pillar says *every wall has a body price*. In practice the game charges one price in one way. These two features split the toll into three currencies, so a level designer can ask the player for different things:

| Barrier | Charges | The question it asks | Built |
|---|---|---|---|
| **Door** (buildings spec §4) | **TIME** — and risk, since pounders stand still under fire | *Can you afford to stop here?* | ✅ v0.44.0 |
| **Fence** (Part A) | **STOCK** — peak simultaneous horde size | *Did you keep enough of them alive?* | this spec |
| **Hazard** (Part B) | **FLOW** — bodies per crossing | *Is this route worth what it eats?* | this spec |

Deliberately non-substitutable. A door yields to six zombies given ten seconds; a fence yields to twenty zombies or to nobody at all; a hazard takes its cut every time anything walks over it. A level that mixes all three asks three different questions on one map, which is the point.

Both features share a property worth stating up front: **neither adds a player verb, and neither adds a zombie state.** The horde behaves exactly as it does today. The terrain reads the horde and reacts. That is what keeps them cheap.

---

## 1. RULINGS (Ben, 2026-08-01)

1. **A fence blocks EVERYONE** — humans and zombies alike. It is a wall until it folds. *(Chosen over the zombie-only "one-way membrane"; the membrane survives as a parked per-fence flag, §A13.)* This is what forces §A9's navmesh work.
2. **A folded fence stays impassable to HUMANS for the rest of the level** — provisional: *"we can try 'no' for now and see if it negatively impacts play."* This is the cheap answer (no runtime re-bake, the buildings-spec invariant survives); §A9.3 records exactly what to watch for and what the upgrade costs if it reads badly.
3. **Fences fold on a hard threshold** — N pressers for T seconds, binary, no partial credit below N. The fence is a pass/fail stock check, not another damage race.
4. **Hazard avoidance is a blanket rule plus a `hidden` flag** — calm zombies and humans route around visible hazards, ferals route around nothing, and a `hidden` hazard (minefield) is avoided by nobody.
5. **Both features are pulled forward** ahead of / alongside Phase 5–6.

**Still open (recommendations made, not yet ruled):** hazard deaths cause no contagion (§B6.2); `affects_humans` defaults false (§B7.2); the fire zone + riser-denial rider stays parked (§B5.6).

---

# PART A — FENCES

## A1. THE FEATURE IN ONE PARAGRAPH

A **fence** is freestanding terrain that nothing crosses. It cannot be pounded, has no integrity, and takes no damage: it folds when **enough bodies press against it at once, for long enough**. A fence with a requirement of twenty is a door that six zombies can never open and twenty can open in two seconds. It is the **mass gate** — Ben's framing: *a secret path, if you got this far with a big horde* — and its natural home in level design is a shortcut, a flank, or a compound perimeter the player can only breach on a run where they were thrifty with bodies. Because it walls humans in as well as zombies out, a fenced compound is also a trap the defenders built for themselves: fold the wire and the people inside have nowhere left to run.

## A2. PILLAR AUDIT

- **Attrition is currency / every wall has a body price** ✅ — with a twist: the fence charges *peak stock*, not expenditure. It is the first mechanic that rewards the horde you still have rather than the horde you spent. That is a new axis and a good one — it gives "don't feed the GI position" a concrete payoff beyond not losing.
- **Command the calm, influence the storm** ✅ — a **terrain verb for the reserve**, exactly like the calm door-breach (v0.46.0) that set the precedent. The reserve pushes; it never demolishes and never attacks. *Release is for prey, orders are for terrain* holds unchanged.
- **The frenzy chases what moves** ✅ — a feral pressed on a fence peels off for reachable prey exactly as a besieger leaves a door (§A6.2).
- **Determinism** ✅ — a registry count, a fixed-timestep accumulator, no RNG (§A9.4).
- **Predictability over simulation** ✅ — the requirement is a printed number on the fence, readable before you commit (§A8). *Meaningful decision or friction?* The decision is real and new: **spend now, or bank the stock for the gate.**
- **Player agency** ✅ — nothing about a fence takes control away. A calm crew ordered into one keeps its selection, keeps its orders, and walks off the moment you say so.

## A3. THE OBJECT

### A3.1 Structure

New script `fence.gd` (`class_name Fence`, `@tool`, extends `Node2D`) — **name verified free against `scripts/` on 2026-08-01**. Deliberately the **Door pattern, not the Wall pattern**: a straight segment with a length, laid along local X, with rotation, so Door's segment maths (the arc test, the barrier quad, the bar placement) transfers directly.

- `fence_length` (px, export) — the span. `fence_thickness` (px, export, v0 **8**) — the band it occupies.
- **A fence is its own fold unit.** A long run is either one long `Fence` (folds whole, one threshold) or several short ones end to end (folds **piecewise** — the crowd opens the section it pressed and the rest stays up). Both are legitimate; chained fences share no state.
- A fence may be a **child of a `ShelterBuilding`** (snapped to the perimeter like a Door) or standalone. No shelter semantics either way — a fence never joins the flee exit set, never converts anyone to SHELTERED, and never locks.

### A3.2 The barriers

Two runtime `StaticBody2D`s across the span, both freed permanently at fold:

- **Zombie barrier** on **layer 4 "EscapeBarrier"** — the escape-zone/door pattern verbatim; zombies (mask 9) slide off it.
- **Human barrier** on **layer 6 "DoorLock"** (bit 32) — the layer Door already uses to bounce humans off a locked door; humans (mask 33) hit it, zombies never do. Reusing it means **no project-settings change and no new collision layer** for either barrier.

At fold: zero both collision layers, *then* free the bodies — the same **breach-frame race fix** the door needed, for the same reason (same-frame raycasts must not hit a dying blocker). Fold is **permanent**.

### A3.3 The two deliberate absences

1. **A fence does not block line of sight.** No `DoorLOS` body. Chain-link is see-through, and the tactical consequence is the good one: **defenders behind an intact fence shoot the crowd pressing it**, and fear counts pass through. A fence with a militia behind it is a priced crossing in two currencies at once, with no extra rules. *(An opaque variant — hoarding, corrugated — is a one-line parked flag, §A13.)*
2. **A fence takes no damage.** No integrity, no `apply_pound`, no pounding animation state. One zombie left on a fence overnight achieves exactly nothing. This is the whole distinction from a door and it should stay absolute.

## A4. THE FOLD RULE

One rule, three knobs:

> While **`press_count` ≥ `press_threshold`**, the fold meter fills at 1/`fence_fold_time` per second. At 1.0 the fence **folds, permanently**. Below the threshold the meter **drains** at `fence_relax_factor` × that rate.

- **`press_count`** = living zombies whose `global_position` lies in the **press strip**: the band `fence_press_depth` deep on **both** sides of the span, plus a small side margin (Door's `ARC_SIDE_MARGIN` equivalent). Both sides count and are not distinguished — a fence has no "inside", and a crowd split across it is still weight on the wire.
- **Presence, not intent.** No check that a zombie is "pushing". A zombie in the strip counts whether it was ordered there, jammed there, or is idle-shambling there (`shamble_leash` is 5px, so a parked crew stays parked). Intent-detection would be invisible state and a support-ticket generator; the dwell timer is what stops incidental contact folding anything.
- **Drain, not reset.** A hard reset makes a marginal press feel arbitrary and punishes BOID jostle — one body squeezed out for 0.3s should not zero 1.7s of progress. Drain also renders as a bar visibly sagging back, which teaches the rule without a tutorial.
- **No partial credit below the threshold.** Nineteen zombies against a twenty-fence do nothing, forever (ruling 3). This is the feature: doors already own the "more bodies = faster" continuum, and if fences grade smoothly then a fence is a door with a different skin and the third currency in §0 collapses into the second.

*Parked escape hatch if the cliff-edge plays badly: `fence_overpressure_factor`, default 1.0 = off (§A13).*

## A5. WHO COUNTS

- **Calm zombies count.** Ferals only go where prey went, so a feral-only fence with nothing behind it would never be pressed and the secret-path fantasy dies on arrival. Fiction carries it: this is **structural failure under weight**, not demolition, so "the calm reserve never demolishes" survives intact — the reserve gains a terrain verb, not an attack verb, exactly as it did with the calm door-breach.
- **Ferals count.** Same weight, no distinction.
- **Risers count** once they are living zombies. Consequence worth naming: bodies shot off a fence by a defender behind it **rise where they fell — inside the strip — and rejoin the press**. A fenced gun position feeding its own siege is a great emergent image and it falls out of existing rules.
- **Corpses and pending-rise bodies do not count** (not living units). **Specials count** (they are bodies; PoC-excluded regardless).
- **Humans never count.** A crowd of civilians pinned against the inside of a fence by your horde does not fold it. Only the dead press.

## A6. THE ZOMBIE SIDE

### A6.1 Calm zombies need no new code at all

A calm zombie ordered to a point beyond a fence nav-paths toward it (the zombie mesh leaves fences open, §A9.1), hits the barrier, and jams. Calm zombies have no give-up clock — `_tick_calm` keeps calling `nav_move_toward` and simply never arrives. It presses until told otherwise. `CalmBreach` is untouched and does not fire: `DoorBreach.door_in_arc` finds no *door*, so the wedge window closes on an ordinary jam and the move keeps trying — exactly right here.

**Zero lines change in `zombie.gd`, `calm_breach.gd`, or `shamble_behavior.gd`.**

### A6.2 Ferals need one rule — and it is an amendment

A feral chasing prey across a fence wedges on it, makes no progress, and — as the code stands — **calms out after `failsafe_window` (2s)**, wanders off, and evaporates the press. That is a bug in waiting, and it mirrors what the buildings spec solved with the BREACHING exemption (§5.4.1 there).

**AMENDMENT to direction spec §3.4 rule 5 (the give-up failsafe):** a feral whose no-progress wedge window closes **while it stands in an intact fence's press strip, with its target on the far side**, enters **PRESSING**:

1. **The target is KEPT** (mirrors the door wedge siege exactly) — the chase resumes the instant the fence folds, and the pursuit claim keeps that human off other ferals' menus.
2. **The failsafe clock is exempt** while PRESSING.
3. **Peel-off stays live** — the 0.25s scan runs as normal; reachable prey pulls the feral off the fence immediately. A fence is the lowest-priority thing a feral can be doing, identically to a door.
4. PRESSING clears when the fence folds, when the target dies or is lost, or when the feral peels.

Implementation: a **flag, not a state** — `_pressing_fence: Node2D` on `FeralBrain`, three guards, ~15 lines. No component, no dispatcher sub-state, no `PounceBehavior` change. The strip lookup mirrors `DoorBreach.door_in_arc` as a static on `Fence` (`Fence.strip_at(zombie)`), run on the wedge cadence, never per frame.

### A6.3 The Mark

Unchanged and untouched. The Mark reorders prey; a fence is not prey. A marked human beyond an intact fence pulls ferals to the fence and no further, which is correct and readable.

## A7. THE VERB — ORDERS ARE FOR TERRAIN

No new grammar. Two ways to press a fence, both already-legal clicks:

1. **Implicit** — RMB on ground beyond the fence. The crew paths into it and presses. The common case; needs nothing.
2. **Explicit** — **RMB on the fence itself** resolves to a **move order distributed along the fence's near-side press line**: `FormationPlanner` slots spread *along the span* rather than in a circle, so the crew arrives spread across the strip instead of funnelling into one point. Still a plain calm move order — no new state, no commitment, cancelable by any later order, selection retained.

`SelectionManager.handle_command` gains one case after the door case (human → building → door → **fence** → ground), plus `_fence_at()` and a hover telegraph matching the door's. **Release-on-fence does not exist** — the v0.46.0 grammar ruling (*release is for prey, orders are for terrain*) settles it.

## A8. THE INDICATOR

Three tiers, each answering a different question:

| Tier | Shows | Answers | When |
|---|---|---|---|
| **Requirement badge** | `⛓ 20` at the span's midpoint | *What will this cost me?* | **Always visible.** Planning information — the same role door integrity plays. The predictability pillar requires it be readable before you commit, not discovered by failing. |
| **Live counter** | `12 / 20`, red below threshold, amber-green at or above | *Am I actually folding it?* | While `press_count > 0`. The colour flip is the single most important readable moment on the object. |
| **Fold bar + sag** | A filling bar (Door's bar-layer visual language, z-10, continuous rather than chunked) **and the span visibly bowing** toward the pressing side, offset ∝ fold progress | *How much longer?* | While the meter is non-zero, **including while it drains** — watching it sag back when a body wanders off teaches the drain rule for free. |

- **The sag is the trope image** (WWZ's Jerusalem wall, TWD's prison fence) and it is nearly free: draw the span as a 3-point polyline whose midpoint offsets by `fold_progress × fence_sag_max` toward the majority-press side. Creak audio when the audio system is ready.
- **Majority side** for the sag: whichever side holds more pressers; tie → the side of the lowest-`unit_uid` presser (deterministic).
- All of it is **presentation reading simulation state** (guideline 6), drawn on the node for now, migrating to `vision_renderer` in Phase 5.

## A9. THE NAVMESH — THE ONE REAL COST OF "BLOCKS EVERYONE"

### A9.1 Three meshes, one sentence each

A human-blocking fence cannot use the door trick (bake the gap open, deny passage with physics). Doors get away with it because a door is somewhere humans *want* to go; a fence is a wall to them, so an open-in-the-mesh fence means humans nav-path into it, jam, and trip the cower detector after `cower_window` (1.2s). Humans cowering against every fence on the map is not an acceptable failure mode. So the fence must be **carved from the human navmesh** — and once there is more than one mesh, the hazard asymmetry in Part B rides the same machinery:

| Mesh | Used by | Fences | Visible hazards | Hidden hazards |
|---|---|---|---|---|
| **H** | all humans | **carved** | carved | open |
| **C** | CALM zombies | **open** *(they must reach a fence to press it)* | carved | open |
| **F** | FERAL zombies | **open** | open | open |

Walls, buildings, and level bounds carve all three identically — that part is unchanged.

Note the incremental shape: **mesh F is exactly today's mesh**, unchanged. Slice 1 adds mesh H (which is today's mesh plus fences). Slice 2 splits off mesh C. Nothing is rewritten at either step.

### A9.2 How it's built

`NavBaker` already collects `get_nav_footprint()` from every node that has one and bakes one `NavigationRegion2D`. The change is to bake **N regions from one geometry scan**, each with its own `navigation_layers` bit and its own filter over which footprints it consumes. Agents pick a mesh via `NavigationAgent2D.navigation_layers`:

- Zombies flip theirs in `ignite_feral()` / `_set_calm()` — two lines in `zombie.gd`. Risers rise CALM, so they inherit careful pathing automatically (fresh bodies don't immediately re-walk the minefield that made them).
- Humans set layer H once, where `FleeBehavior` creates its agent.

All bakes happen at boot, before the first physics tick, deterministically. **No runtime re-bake, ever** — the buildings-spec §15 invariant survives.

**Flagged risk:** overlapping `NavigationRegion2D`s on different navigation layers is the Godot-native way to say "different agent types avoid different things", but overlapping regions can interact oddly at edge-connection time. **Prototype this in a throwaway scene before committing** — one fence, one hazard, one human, one calm zombie, one feral; confirm three different paths and that no agent's path snaps to the wrong region. *Fallback if it misbehaves:* separate `NavigationMap` RIDs instead of layer-filtered regions (heavier but fully isolated); as a last resort for hazards only, calm avoidance can be delivered as a steering repulsion term reusing the `flee_repel` maths — that fallback does **not** work for fences, which genuinely need the human mesh carved.

### A9.3 A folded fence stays impassable to humans (provisional — ruling 2)

The fence is carved from mesh H for the whole level, folded or not. Zombies of course walk straight through the fold (their meshes never had it carved and the barriers are gone).

**Why this is nearly free in play:** a freshly folded fence has your horde standing in the gap, and `exit_block_radius` (120px) already strikes off any exit with a living zombie in it — so even a correct implementation would usually refuse that route for the first several seconds anyway.

**Watch for these tells that it needs upgrading:** humans visibly declining an obvious open gap long after the horde has moved on; or a compound whose occupants huddle and cower when a folded fence was their only way out. **The upgrade if it happens:** re-bake mesh H alone on fold, on a physics frame (folds are rare — a handful per level — so the hitch is a one-off, and one physics frame is one physics frame under fast-forward). That is a contained change and this design deliberately does not foreclose it.

**Level-design law while it stands: always leave humans a fence-free route to at least one exit.** A fenced-in pocket with no way out is a legitimate authored trap, but it should be an authored one, not an accident.

### A9.4 The flee exit picker needs a reachability check

The exit picker scores by straight-line distance × threat bias, not nav distance. With fences opaque to human pathing, a human can commit to the "nearest" exit that sits behind a fence, walk to the wire, and cower there. That is systematic, not an edge case, and it is the second real cost of ruling 1.

**Fix (contained):** at exit-pick time only — never per frame — ask the nav server for a path to the candidate and drop the exit if the path does not actually arrive (compare the path's final point to the target). This slots into the existing three-pass picker as a fourth filter, ahead of the threat-biased score, and reuses the pattern `FeralBrain._nav_distance` already establishes. If everything fails the check, fall through to the existing unfiltered fallback — a desperate run at the least-bad exit still beats freezing.

### A9.5 Determinism (§10 holds in full)

- `press_count` comes from `GameManager.neighbours_within(centre, reach, &"zombies")` — registry, `unit_uid`-ordered — then the exact strip test. Never a group scan (guideline 8).
- The fold meter is a fixed-timestep accumulator on `_physics_process`. No wall-clock.
- Every tiebreak resolves by lowest `unit_uid`. No RNG; the fence needs no DetHash stagger because nothing about it is per-unit.
- All bakes complete at boot in a fixed order. Add a fence-fold scenario to the **boot-twice-and-diff** spot-check when built.

## A10. INTERACTIONS WORTH STATING

1. **Flee exit set** — a fence is not an exit and never joins the set. What changes under ruling 1 is that a fence can *cut off* exits, which is what §A9.4 is for.
2. **The fill front** sees through, fires through, and cannot be blocked by a fence. Defenders behind a fence are the fence's teeth, and the bodies they drop rise inside the strip (§A5).
3. **Fear** passes through — a crowd massing on the wire terrifies the compound. Intended: the mass gate announces itself.
4. **Herding into a fence is now a real play.** `flee_repel` bends runners away from your zombies with no knowledge of terrain, so a fence at their back is a hard stop: shove them against it and the cower detector does the rest. This is the most advanced expression of the herding verb the game has, and ruling 1 is what enables it.
5. **The compound trap.** Fold a perimeter fence and the people inside have nowhere to go — every exit they had is on the wrong side of your horde. Fenced compounds should be authored as terror-harvest arenas, not just as obstacles.
6. **Contagion is not LOS-gated** (existing rule), so violence on one side ignites the reserve on the other. Consistent with the buildings-spec treatment; note it when placing staging ground.
7. **No pouncing over a fence.** The lunge triggers at 40px from a target and flies straight; a target beyond an intact fence is beyond the barrier, so the lunge lands on the wire. (Contrast §B7.3, where leaping a hazard band *is* possible and is a feature.)

## A11. THE LEVEL-DESIGN LAW: CAPACITY vs THRESHOLD

**A threshold the span physically cannot hold is an unopenable fence and a designer error.** With ~24px of effective body width along the span and ~30px of BOID separation between ranks:

```
max_pressers ≈ floor(fence_length / 24) × floor(fence_press_depth / 30) × 2 sides
```

A 200px span at 60px depth holds roughly `8 × 2 × 2 = 32` — so a threshold of 20 is demanding but achievable, and 40 is a wall. **Recommend a `@tool` `push_warning()` when `press_threshold > 0.75 × max_pressers`**, printing both numbers. Five lines; prevents the most likely authoring mistake.

Corollary worth internalising: **the way to make a fence harder is a bigger threshold OR a shorter span.** A short fence is hard because only so many bodies fit, and that reads visually — better than a big number.

## A12. NUMBERS v0 (GameConfig + LevelConfig-overridable; per-fence where marked)

| Knob | v0 | Notes |
|---|---|---|
| `fence_press_depth` | **60 px** | each side. Deep enough for ~2 ranks (BOID separation is 30px) — a 25px door-style arc would cap the count at one rank and make thresholds depend on span alone |
| `fence_fold_time` | **2.0 s** | at/above threshold, from an empty meter |
| `fence_relax_factor` | **1.0** | drain rate below threshold, × the fill rate |
| `fence_press_threshold` | **10** *(per-fence)* | THE level-design knob. 10 = "a decent crew"; 20+ = "a hoarded horde" |
| `fence_length` | **200 px** *(per-fence)* | span |
| `fence_thickness` | **8 px** *(per-fence)* | barrier band; thinner than a wall on purpose |
| `fence_sag_max` | **14 px** | presentation only |

Sweep jobs: does the threshold read as a *stock check* (does a player consciously bank bodies for it)? Does 2.0s feel like weight or like a formality? Is drain-vs-reset the right forgiveness? Do humans behave sensibly around fences, folded and intact (§A9.3)?

## A13. PARKED (from Part A — do not build)

- **The one-way membrane** (`blocks_humans = false`) — the zombie-only fence: humans vault, zombies pile. Ruled against as the default on 2026-08-01, but it is the cheap variant (it *removes* the human barrier and the mesh-H carve), so if a level ever wants prey-favouring terrain it is a per-fence flag, not a redesign.
- **Graded overpressure** (`fence_overpressure_factor`) — §A4; only if the hard threshold plays badly.
- **Opaque fences** (`blocks_los`) — hoarding/corrugated. One line, but it changes the tactical meaning entirely; ship transparent first.
- **Rubble on fold** (`folds_to_rubble`) — leaves a SLOW hazard band where it fell. Cheap once Part B exists; a slice-3+ garnish.
- **Repairable fences** — no. Barricading is a door mechanic; a fence that comes back turns a stock check into a timing check and muddies the currency.

---

# PART B — HOSTILE TERRAIN

## B1. THE FEATURE IN ONE PARAGRAPH

**Hazards** are placeable areas that charge the horde for crossing: minefields, stake beds, barbed wire, electrified fence lines. No AI, no state, no new player verb. The design core, and the thing that makes them interesting rather than merely annoying, is Ben's own instinct: **the calm reserve routes around a hazard; the frenzy runs straight through it.** That asymmetry turns every hazard into a live question about *how* you attack rather than *whether* you can — walk the crew around the wire under full control and lose the tempo, or release through it and pay in bodies for the speed. It gives release a permanent, legible, deterministic cost in exactly the places a designer chooses to put one.

## B2. PILLAR AUDIT (including the one real risk)

- **Attrition is currency** ✅ — the purest expression of it in the game. The hazard's whole existence is a price list.
- **Command the calm / released is released** ✅ and *sharpened*: the reserve is safe because it is controlled; the storm is expensive because it is not.
- **Predictability over simulation** ✅ **conditionally** — hazards must be **fully visible to the player**, minefields included (§B5.1). Hidden hazards convert planning into guessing and are a straight pillar violation. The zombies not knowing is fiction; the player not knowing is a bug.
- **Determinism** ✅ — fixed cadence, registry order, DetHash stagger for anything periodic, no RNG (§B9).
- **Player agency** ⚠️ **one genuine risk, mitigated.** A **contagion** ignition next to a minefield could send the reserve into it with no player input — control lost, which the pillars forbid. Two mitigations: (a) **hazard deaths cause no contagion** (§B6.2), so a hazard can never start a chain reaction; (b) ferals only run at *prey*, so a hazard only bites when a human is on the far side — the trigger is always something the player can see. Residual risk is level-design hygiene (§B10.3), not an engine rule.
- **Meaningful decision or friction?** ✅ Route choice, release timing, and calm-vs-feral commitment are all real decisions. The failure mode to watch is a hazard with no alternative route — that is pure friction and a level-design error, not a mechanic error.

## B3. THE CORE MECHANISM

Rides §A9's mesh layering. In one sentence: **CALM zombies and all humans path on meshes with visible hazards carved out; FERAL zombies path on a mesh with nothing carved; and a `hidden` hazard is carved from none of them, so nobody routes around it** (ruling 4).

That is the entire mechanism: binary, memorable, no per-hazard AI, no per-frame cost. See §A9.1 for the mesh table and §A9.2 for the build and its flagged risk.

**Explicitly rejected:** per-hazard "should I avoid this" logic on the units. It puts terrain knowledge in `zombie.gd`, violates one-owner-per-mechanic, and scales badly with hazard count.

## B4. THE DATA MODEL — ONE NODE, DATA NOT BRANCHES

New script `hazard_zone.gd` (`class_name HazardZone`, `@tool`, extends `Polygon2D`) — **name verified free**. Mouse-drawn footprint exactly like `Wall`, so authoring is drag-and-draw. Guideline 7 (*data over branches*) says the named hazards are **export presets on one class, not four classes**:

| Export | Type | Meaning |
|---|---|---|
| `toll_mode` | enum `{KILL_ON_ENTER, KILL_PERIODIC, SLOW}` | what it does to what's inside |
| `charges` | int | uses before the zone is spent. `-1` = infinite |
| `blast_radius` | float | on a KILL_ON_ENTER trigger, everything within this radius of the trigger point dies. `0` = only the trigger |
| `tick_period` | float | KILL_PERIODIC only — seconds between casualties |
| `speed_factor` | float | SLOW only — multiplier on movement speed inside |
| `hidden` | bool | `true` = carved from **no** mesh (nobody routes around it) |
| `affects_humans` | bool | default **false** — the toll is on the horde unless the designer says otherwise (§B7) |
| `armed` | bool | default `true` — the power switch the generator concept (ideation §3.1) will drive later. An unarmed hazard is inert terrain |
| `denies_risers` | bool | default `false` — parked rider, §B5.6 |

A "minefield" is a saved set of export values, not a code path. Adding a hazard type later should be a row in a table, never a new script.

## B5. THE KIT

### B5.1 Minefield — the one that hits everyone
`KILL_ON_ENTER`, `charges = N`, `blast_radius ≈ 60px`, **`hidden = true`**.

Answers Ben's own question ("minefield affects everyone?") with **yes, in the sense that matters**: nobody routes around it, calm or feral, because nobody can see a buried mine. Each entry consumes a charge and kills every zombie in the blast — a tight column pays badly, a spread crossing pays once. A spent field is inert ground, permanently: **the minefield is the only hazard the player can exhaust**, which makes "walk the cheap bodies through first" a real and satisfying play.

**The player sees the whole field, always** (§B2). Render `hidden` zones with a **dashed danger border** vs a solid one for avoided zones, so "my units will not route around this" is a visual property, plus remaining charges printed.

### B5.2 Stakes / spike perimeter — the pure asymmetry
`KILL_ON_ENTER`, `charges = -1`, `blast_radius = 0`, `hidden = false`.

The clean expression of the calm/feral rule: the crew walks around the spike bed, the frenzy impales itself on it forever at one body per crossing. Cheapest to reason about and the best teaching object for the whole mechanic — recommend it be the **first** hazard built and the one the PoC level leans on.

### B5.3 Barbed wire — the one that spends time, not bodies
`SLOW`, `speed_factor ≈ 0.4`, `hidden = false`, `affects_humans = false`.

Kills nobody. It locally **shifts the sacred ratio**: inside the wire the fill front wins races it normally loses, so a defender covering a wire band is worth several defenders in the open. Strategically the most interesting hazard in the kit precisely because it charges the *other* currency, and nearly free to build (a speed multiplier). `affects_humans = false` is a deliberate asymmetry — it's a defensive installation built to slow attackers, and making it symmetric would mostly cancel its own effect.

### B5.4 Electrified fence — the join (slice 3)
A **`Fence` with `electrified = true`**, not a separate hazard node: the fence already owns the strip geometry and the press count, so the shock lives there — one owner per mechanic, and one node for the designer instead of two overlapping ones.

While powered, one presser dies every `shock_interval` — **exactly one**, the lowest `unit_uid` in the strip (deterministic). The maths a designer should carry: threshold 10, `fence_fold_time` 2.0s, `shock_interval` 1.5s → folding it costs about **two bodies**, provided you can *hold* ten in the strip while it eats them. Raise `fence_fold_time` and the toll climbs proportionally; make the shock fast enough and the fence becomes genuinely unfoldable, a valid level statement so long as another route exists. Depowering it (generator, deep pocket) leaves an ordinary fence — the side objective literally opens the secret path, as the ideation record framed it.

### B5.5 Free by-products (no extra code)
- **The bear trap** — `charges = 1`, `blast_radius = 0`. Single-use, cheap to scatter, makes a corridor feel mined without a minefield's cost.
- **Rubble / choke** — `SLOW` with `affects_humans = true`: a neutral pacing tool for both teams.
- **The moat** — a `Fence` with an unreachable threshold (or a parked `foldable = false`) is a canal or ha-ha: permanent terrain that reads as breakable-in-principle. Free from Part A.

### B5.6 Fire zone — PARKED to a later slice
`KILL_PERIODIC` + `denies_risers = true`, carrying the ideation record's §2.3 **kill-context riser denial**: a human killed inside it does not stand back up. *Where* you kill decides whether you keep the body — a genuinely deep addition to the attrition maths.

Parked not because it is bad but because it is the only kit member that reaches into the riser pipeline (`register_pounce_kill` would have to ask "was this kill inside a denial zone?"), and one feature at a time. **The hook to leave in place:** `denies_risers` exists on the data model from day one, unread. Land it with the flamethrower/vehicle defender it was designed alongside.

## B6. THE DEATH PATH — AND THE RULE THIS CHANGES

### B6.1 A second way for a zombie to die

`ViolencePipeline.report_gunfire_kill` carries a load-bearing comment: *"gunfire is the only way a zombie dies in v2, so this is frame-exact and teardown-immune"* — the A4/A5 lose-verdict fix depends on it. **Hazards break that invariant**, and the fix lands in the same commit:

```
ViolencePipeline.report_hazard_kill(zombie, hazard)
    → zombie.take_damage(1.0)
    → _gm.check_lose_condition()      # the verdict stays at the death instant
    → (no contagion — see B6.2)
```

Update the comment on both functions to read *"the two zombie-death sources"*. A player who marches their last bodies into a minefield must lose at that instant, exactly as they do to gunfire.

### B6.2 Hazard deaths cause NO contagion (recommended, not yet ruled)

Contagion models *"you shot us, we're coming for you"* — human violence drawing the horde onto the human. A mine has nobody to charge at. Igniting the reserve on a hazard death would be actively harmful three ways: it wakes zombies targetless; it makes hazards **self-detonating traps** (walk one zombie in, the reserve ignites and pours into the field); and that third one is a straight agency-pillar violation — control lost with no player input. **Rule: hazard deaths are silent.** No contagion, no score change, no combo effect (the combo counts pounce kills only and is untouched). They cost you a body and nothing else.

### B6.3 Human deaths in hazards — riser denial for free

If `affects_humans` is true and a human dies to terrain, it dies through the normal `Human.die()` path — so `human_died` fires, `GameManager._on_human_died` runs, and `check_win_condition()` is called. It does **not** route through `register_pounce_kill`, so:

- it is **not scored** (correct — the pounce is the scored event),
- it produces **no riser** — kill-context riser denial achieved with no new code,
- and it is a body you didn't get, exactly like an escape.

State it as the design consequence it is: **herding prey across your own minefield throws the body away.** A real, learnable, deterministic trade.

## B7. HUMANS AND HAZARDS

1. **Humans path on mesh H**, which carves every visible hazard — so they route around their own installations with no new code, which is also the right fiction (they know where the safe lane is).
2. **Hidden hazards catch humans too** *if* `affects_humans` is true, since nobody routes around them. Default false keeps the toll on the horde per Ben's stated intent; a designer wanting the "herd them into the minefield" beat flips one flag and accepts §B6.3's cost.
3. **Flee repulsion can shove a human into a hazard** — `flee_repel` bends routes around zombies without consulting the mesh. Not a bug: it is **herding into terrain**, and it only ever happens because the player built the wall of bodies that caused it. Same family as herding into a fence (§A10.4).
4. **Pouncing over a hazard is legal and is a feature.** The lunge is straight-line and lands on the prey, so a feral reaching pounce range at the edge of a wire band leaps it clean. Zombie-movie-correct, emergent, and worth calling out so nobody "fixes" it.

## B8. READABILITY

- **Footprint fill** in a danger tint, distinct per `toll_mode` — lethal / periodic / slow should be three different reads at map scale.
- **Border encodes avoidance:** solid = your calm crew routes around it; **dashed = nobody routes around it**. The single most important piece of information on the object; it gets its own visual channel.
- **Charge counter** on consumable zones; **spent zones grey out** and read as inert.
- **A kill flash** at the point of every hazard death — hazards must never kill invisibly, or the player learns nothing from losing bodies.
- Interim on-node drawing; migrates to `vision_renderer` in Phase 5 with everything else.

## B9. DETERMINISM (§10 holds in full)

- The field ticks on a fixed `hazard_scan_interval` (v0 **0.1s**) — 14px of travel per tick at `zombie_speed` 140: precise enough for a mine, cheap enough to ignore.
- Containment: registry radius query on the zone's bounding circle → exact `Geometry2D.is_point_in_polygon`. Registry order = `unit_uid` order.
- Units entering on the same tick are processed in `unit_uid` order; charge consumption and blast resolution follow that order, so a two-charge field always eats the same two zombies.
- Periodic damage (electrified, fire) is **DetHash-staggered per unit** — the house pattern, reusing `DoorBreach.first_pound_delay`'s shape with its own salt.
- No wall-clock, no RNG. Add a hazard-crossing scenario to the boot-twice-and-diff spot-check.

## B10. ARCHITECTURE

### B10.1 One owner, and it is a system not a node

`hazard_field.gd` (`class_name HazardField`, **name verified free**) — a child of `GameManager` alongside `ViolencePipeline`, `HuntPool`, and `MarkSystem`, reached by one-line delegates like its siblings. It owns the tick, the containment tests, the kill calls, and the slow-factor bookkeeping. `HazardZone` nodes are **dumb geometry and data** (like `ShelterSpot`): they draw themselves, answer `contains(point)` and `get_nav_footprint()`, and never tick.

Why a system rather than per-node ticking (which is what `Door` does): **overlapping zones.** Two hazards touching the same unit need one deterministic resolution — slowest factor wins, kills resolve in one order — and per-node ticking would make that depend on scene order. The field computes one verdict per unit per cadence.

### B10.2 The one seam in `unit.gd`

SLOW needs to scale movement, and speed is passed per call (`nav_move_toward(point, GameConfig.zombie_speed)`). Add **one field**: `Unit.terrain_speed_factor: float = 1.0`, applied inside `step_toward` / `nav_move_toward` / `move_to_target`. `HazardField` sets it on entry and restores it on exit (tracking which units it slowed last tick and diffing). No call site changes; default 1.0 means every existing level is byte-identical.

### B10.3 Level-design guidance (doc, not engine)

- **Always leave an alternative route.** A hazard with no way around it is not a decision, it is a toll booth — pure friction, and the pillars say reject it.
- **Keep hazards outside `contagion_radius` (150px) of natural staging ground** (§B2's residual risk).
- **Hazards pair with counter-specials** — from the ideation record, for the post-PoC specials re-audit: the Fat Zombie's corpse bridges wire and mines (the body-on-the-wire trope), the Headless's straight-line charge is a natural minesweeper, the Scuba answers moats. **Every hazard should eventually ship with its counter-key.** Nothing to build now; recorded so the re-audit inherits it.

## B11. NUMBERS v0 (GameConfig + LevelConfig-overridable; per-zone where marked)

| Knob | v0 | Notes |
|---|---|---|
| `hazard_scan_interval` | **0.1 s** | global field cadence |
| `mine_blast_radius` | **60 px** *(per-zone)* | a tight column pays badly; a spread crossing pays once |
| `charges` | **−1 / per-zone** | −1 = infinite (stakes, wire); finite = exhaustible (mines, traps) |
| `speed_factor` (SLOW) | **0.4** *(per-zone)* | barbed wire; the sacred-ratio shifter |
| `tick_period` (KILL_PERIODIC) | **1.5 s** *(per-zone)* | one casualty per period |
| `shock_interval` (electrified fence) | **1.5 s** *(per-fence)* | ≈2 bodies to fold a threshold-10 fence at `fence_fold_time` 2.0s |

Sweep jobs: does a stake bed read as "go around" without being told? Is a minefield's charge count legible mid-crossing? Does barbed wire change how a defender position *feels*, or only how long it takes to reach?

## B12. PARKED (from Part B — do not build)

- **Fire zone + `denies_risers`** (§B5.6) — later slice, with its defender.
- **The generator / power grid** (ideation §3.1) — `armed` is the hook, unread until then.
- **Dynamic hazards** (petrol you ignite, collapsing terrain) — needs a trigger system; nothing here anticipates it beyond `armed`.
- **Hazards that damage buildings or doors** — no. Terrain hurts units.
- **Per-unit hazard resistances** — that's the counter-specials answer; it belongs to the specials re-audit.

---

# PART C — BUILD ORDER, TESTS, COMPATIBILITY

## C1. Slicing (one feature at a time, per rule 3)

Ruling 5 pulls both forward, so the sequencing job is to keep new variance away from the M1 verdict. The order below front-loads the risky shared foundation and keeps every slice independently testable and independently revertible.

| Slice | Contents | Touches | Bump |
|---|---|---|---|
| **1a — mesh layering** | `NavBaker` bakes N layer-filtered regions from one geometry scan; agents choose a mesh. **With no fences and no hazards in a level, mesh H == mesh F == today's mesh** — so this slice is provably a no-op and that is exactly what makes it a safe first step. | `nav_baker.gd`, 2 lines in `zombie.gd`, 1 in `flee_behavior.gd` | PATCH |
| **1b — fences** | `fence.gd`, the press rule, the indicator, the `FeralBrain` PRESSING flag, the `SelectionManager` fence-click, the exit reachability filter (§A9.4) | 1 new script + ~40 lines across three existing | MINOR |
| **2 — hazards** | `hazard_zone.gd`, `hazard_field.gd`, mesh C splits off mesh F, `report_hazard_kill`, `Unit.terrain_speed_factor` | 2 new scripts + `nav_baker`, `violence_pipeline`, `unit` | MINOR |
| **3 — electrified fence** | `electrified` on `Fence`, wired to `report_hazard_kill` | ~20 lines | PATCH |
| **4 — parked** | fire zone + riser denial | — | later |

**Sequencing notes:**

- **Prototype 1a's overlapping-region behaviour before writing any of it** (§A9.2). If it misbehaves, the whole shape changes and it is far cheaper to learn that on a throwaway scene than inside slice 1b.
- **The sacred-ratio sweep should run on a terrain-free control level first.** Fence thresholds and hazard tolls are priced *in bodies*, and bodies-per-crossing is exactly what the sweep is trying to establish. Tune the ratio bare, then tune terrain on top of a known baseline — otherwise the two calibrations chase each other.
- **The calm-mass-break re-judge (work-queue Tier 6) interacts with fences and gets more interesting, not less.** Fences reward hoarding a big calm horde, which is the first mechanical *reward* for the herd-everyone-out playstyle rather than a scoring punishment for it. Worth re-asking that question after slice 1b rather than before.
- New `class_name` scripts created outside the editor need `<godot> --headless --import --path .` before the parse gate, or `tools/check.ps1` fails on a *consumer* script with a misleading error.

## C2. Acceptance tests (manual, per project convention)

**Slice 1a — mesh layering**
1. **Provable no-op:** a level with no fences and no hazards plays byte-identically; boot-twice-and-diff a known scenario against a pre-slice log.
2. **Three paths:** in a throwaway scene with one fence and one hazard, a human, a calm zombie and a feral each produce the path their mesh predicts.

**Slice 1b — fences**
3. **Under threshold:** park `threshold − 1` calm zombies in the strip for 30s → the meter never leaves zero, the counter reads red, nothing folds.
4. **At threshold:** add one more → the counter flips colour, the bar fills, the span sags, it folds at `fence_fold_time`, and the crew walks through still selected and under control.
5. **Drain:** reach ~70%, walk two zombies out → the bar visibly drains; walk them back → it refills from where it drained to, not from zero.
6. **Feral press:** release a crew at a human beyond the fence → they wedge, **do not calm out after 2s** (the §A6.2 amendment), hold their targets, and resume the chase the instant it folds.
7. **Peel wins:** with ferals pressed, walk a live human within `chain_scan_radius` on *their* side → they abandon the fence immediately.
8. **Humans treat it as a wall:** a fleeing human never paths into a fence line and **never cowers against one**; with a fence between it and the nearest exit it routes to a reachable exit instead (§A9.4).
9. **Folded fence stays shut to humans (provisional, ruling 2):** after a fold, humans still route around the gap. Log it if it looks stupid — that is the §A9.3 tell.
10. **Defenders shoot through:** a militia behind an intact fence kills pressers; the corpses **rise in the strip and rejoin the press**.
11. **Explicit order:** RMB the fence itself → the crew spreads *along* the span, not into a knot at one point.
12. **Herd into a fence:** shove a runner against a fence with a wall of calm bodies → it corners and cowers (§A10.4).
13. **Determinism + compat:** boot-twice-and-diff a scripted fold; a level with no `Fence` plays byte-identically.

**Slice 2 — hazards**
14. **The asymmetry:** order a calm crew beyond a stake bed → it routes around. Release at a human beyond the same bed → the ferals run straight in and die at one body per crossing.
15. **Exhaustion:** a 3-charge minefield eats exactly three crossings (blast included), then reads spent and is inert.
16. **Lose verdict:** march the last surviving zombies into a minefield → defeat registers **at the death instant**, not on teardown.
17. **No chain reaction:** park the reserve inside `contagion_radius` of a minefield and detonate one mine → **nothing ignites**.
18. **Slow:** a zombie crossing barbed wire visibly halves its pace and dies to a defender it would otherwise have reached.
19. **Riser denial:** with `affects_humans = true`, herd a civilian into a mine → it dies unscored and **does not rise**.
20. **Pounce-over:** a feral reaching pounce range at a wire edge leaps the band and lands clean.
21. **Determinism + compat:** boot-twice-and-diff a crossing; a level with no `HazardZone` plays byte-identically.

## C3. Backwards compatibility

Both features are **purely additive**. No existing level contains a `Fence` or a `HazardZone`; `Unit.terrain_speed_factor` defaults to 1.0; with neither object present all three meshes are identical to today's single mesh; `report_hazard_kill` is unreachable without a hazard. Every existing scene plays byte-identically, and tests 1, 13 and 21 exist to prove it at each step.

---

**END OF DRAFT v0.2** — slice 1a is the next thing to propose for build, and it should be preceded by the throwaway-scene prototype in §A9.2.
