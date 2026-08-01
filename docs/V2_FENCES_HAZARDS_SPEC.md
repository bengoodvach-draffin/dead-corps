# DEAD CORPS — FENCES & HOSTILE TERRAIN SPEC

**Version:** 0.1 (draft for Ben's rulings — 2026-08-01)
**Status:** **DESIGN DRAFT — NOTHING APPROVED, NOTHING BUILT.** Written to be ruled on, then built. Rule 1 (propose-before-implementing) applies to every step below even after the design is ruled; this doc is the proposal for the *design*, not a licence to code.
**Scheduling:** both features are promotions out of `TROPE_IDEATION_2026-07-27.md` (§2.1 foldable fences, §2.2 hazard terrain), whose own gate is **post-M1-verdict at the earliest**. That gate is Ben's to move — the enterable-buildings milestone was pulled forward the same way on 2026-07-23 — but this spec does not assume it has moved. Nothing here belongs in front of Phase 5/6 unless Ben says so.
**Relationship to other docs:** extends `V2_ENTERABLE_BUILDINGS_SPEC.md` (the terrain kit, §16.2) and `V2_DIRECTION_SPEC.md`. **Changes no existing rule** except two, both explicitly flagged: the feral give-up failsafe gains one more exemption (§A6.2), and `report_gunfire_kill` stops being the only way a zombie can die (§B6). Everything else is additive.

---

## 0. THE THESIS — THREE BARRIERS, THREE CURRENCIES

The pillar says *every wall has a body price*. In practice the game has been charging one price in one way. These two features split the toll into three distinct currencies, so a level designer can ask the player for different things:

| Barrier | Charges | The question it asks | Built |
|---|---|---|---|
| **Door** (buildings spec §4) | **TIME** — and risk, since pounders stand still under fire | *Can you afford to stop here?* | ✅ v0.44.0 |
| **Fence** (Part A) | **STOCK** — peak simultaneous horde size | *Did you keep enough of them alive?* | this spec |
| **Hazard** (Part B) | **FLOW** — bodies per crossing | *Is this route worth what it eats?* | this spec |

They are deliberately non-substitutable. A door yields to six zombies given ten seconds; a fence yields to twenty zombies or to nobody at all; a hazard takes its cut every single time anything walks over it. A level that mixes all three asks the player three different questions on one map, which is the point.

Both features also share one design property worth stating up front: **neither adds a new player verb, and neither adds a new zombie state.** The horde behaves exactly as it does today; the terrain reads the horde and reacts. That is what keeps them cheap.

---

## 1. RULINGS NEEDED FROM BEN

Everything below is a recommendation with reasoning. These are the ones where a different call changes the build materially:

1. **Fences are transparent to humans** — humans vault/gate through freely; a fence is a zombie-only barrier (§A3.3). *This is the biggest single call in Part A.*
2. **Fences fold on a hard threshold, not a damage race** — N pressers for T seconds, binary, no partial credit below N (§A4). The alternative (rate scales with mass) is written up and recommended against.
3. **Calm zombies count toward the press** (carried forward from the ideation record, re-argued here — §A5).
4. **Feral movement uses a "reckless" navmesh; calm zombies and humans use a "careful" one that routes around visible hazards** (§B3). This is the mechanism behind Ben's "calm path around, ferals walk in" instinct, and the one place with a real technical risk (§B3.3).
5. **Hazard deaths cause NO contagion** (§B6.2). Reasoning is an agency-pillar argument; worth reading before ruling.
6. **Minefields are visible to the player but avoided by nobody** (§B5.1) — the predictability pillar forbids hiding them from the *player*; the *units* not routing around them is the mechanic.
7. **Build order:** Fences (slice 1) → Hazards (slice 2) → the electrified fence, which is the join (slice 3). One feature at a time, per rule 3.

---

# PART A — FENCES

## A1. THE FEATURE IN ONE PARAGRAPH

A **fence** is freestanding terrain that stops zombies and only zombies. Humans cross it as if it were not there. It cannot be pounded down, has no integrity and takes no damage: it folds when **enough bodies press against it at once, for long enough**. A fence with a requirement of twenty is a door that six zombies can never open and twenty can open in two seconds. It is the **mass gate** — Ben's framing: *a secret path, if you got this far with a big horde* — and its natural home in level design is a shortcut, a flank, or a compound wall that the player can only use on a run where they have been thrifty with bodies. Because humans pass it freely, an intact fence is also the cleanest way in the game to give prey a genuine head start.

## A2. PILLAR AUDIT

- **Attrition is currency / every wall has a body price** ✅ — with a twist: the fence charges *peak stock*, not expenditure. It is the first mechanic that rewards the player for the horde they still have rather than the horde they spent. That is a new axis, and it is a good one: it gives "don't feed the GI position" a concrete payoff besides not losing.
- **Command the calm, influence the storm** ✅ — this is a **terrain verb for the reserve**, precisely like the calm door-breach (v0.46.0) that already established the precedent. The reserve pushes; it never demolishes and never attacks. *Release is for prey, orders are for terrain* holds unchanged.
- **The frenzy chases what moves** ✅ — a feral pressed on a fence peels off for reachable prey exactly as a besieger leaves a door (§A6.2).
- **Determinism** ✅ — a registry count, a fixed-timestep accumulator, no RNG (§A9).
- **Predictability over simulation** ✅ — the requirement is a printed number on the fence, readable before you commit (§A8). *Meaningful decision or friction?* The decision is real and it is a new one: **spend now or keep the stock for the gate**.
- **Player agency** ✅ — nothing about a fence takes control away. A calm crew ordered into one keeps its selection, keeps its orders, and walks off the moment you say so.

## A3. THE OBJECT

### A3.1 Structure

New script `fence.gd` (`class_name Fence`, `@tool`, extends `Node2D`) — **name verified free against `scripts/` on 2026-08-01**. It is deliberately the **Door pattern, not the Wall pattern**: a straight segment with a length, laid along local X, with rotation, so all of Door's segment math (the arc test, the barrier quad, the bar placement) transfers directly.

- `fence_length` (px, export) — the span. `fence_thickness` (px, export, v0 **8**) — the band it occupies.
- **A fence is its own fold unit.** A long run is either one long `Fence` (folds whole, one threshold) or several short ones placed end to end (folds **piecewise** — the crowd opens the section it pressed and the rest stays up). Both are legitimate and the choice is a real level-design lever; chained fences share no state.
- A fence may be a **child of a `ShelterBuilding`** (snapped to the perimeter like a Door) or standalone in the world. There is no shelter semantics either way — a fence never joins the flee exit set, never converts anyone to SHELTERED, and never locks (§A10.1).

### A3.2 The barrier

One runtime `StaticBody2D` across the span on **layer 4 "EscapeBarrier"** — the escape-zone/door pattern verbatim. Zombies (mask 9) slide off it; humans (mask 33) never see it. No project-settings change, no new layer.

At fold: zero the collision layer, then free the body (the same **breach-frame race fix** the door needed — same-frame raycasts must not hit a dying blocker). Fold is **permanent**; the span is open ground for the rest of the level.

### A3.3 What a fence does NOT do — the three deliberate absences

1. **It does not block humans.** Recommended, and the load-bearing call of Part A. Fiction: chain-link — survivors vault it, unbar the gate, or squeeze the gap; the dead can't climb, so they pile. Mechanically this buys three things at once: (a) the fence needs **zero** new human code — no exit-set membership, no lock predicate, no bounce-and-re-flee, no navmesh consequences; (b) it creates the **one-way membrane**, the cleanest head-start-for-prey primitive the game has; (c) it gives the player a legible reason the fence exists in the fiction — it's a fence *against zombies*, and it works, until it doesn't.
   *If Ben rules the other way (fences block humans too), the cost is not small: a human-blocking barrier must be carved from the human navmesh or fleeing humans will nav-path into it and jam, and carving it re-opens the runtime-rebake problem the buildings spec spent §15 avoiding.*
2. **It does not block line of sight.** No `DoorLOS` body. Chain-link is see-through, and the tactical consequence is the good one: **defenders behind an intact fence can shoot the crowd pressing it**, and fear counts pass through. A fence with a militia behind it is a priced crossing in two currencies at once, with no extra rules. (An opaque variant — hoarding, corrugated wall — is a one-line parked flag, §A13.)
3. **It takes no damage.** There is no integrity, no pound, no `apply_pound`. A single zombie left on a fence overnight achieves exactly nothing. This is the whole distinction from a door and it should stay absolute.

## A4. THE FOLD RULE

One rule, three knobs:

> While **`press_count` ≥ `press_threshold`**, the fold meter fills at 1/`fence_fold_time` per second. At 1.0 the fence **folds, permanently**. Below the threshold the meter **drains** at `fence_relax_factor` × that rate.

- **`press_count`** = living zombies whose `global_position` lies in the **press strip**: the band `fence_press_depth` deep on **both** sides of the fence span, plus a small side margin (Door's `ARC_SIDE_MARGIN` equivalent). Both sides count and they are not distinguished — a fence has no "inside", and a crowd split across it is still weight on the wire.
- **Presence, not intent.** No check that a zombie is "pushing". A zombie standing in the strip counts, whether it was ordered there, jammed there, or is idle-shambling there (`shamble_leash` is 5px, so a parked crew stays parked). Intent-detection would be invisible state and a support-ticket generator; the dwell timer is what stops incidental contact from folding anything.
- **Drain, not reset** (recommended). A hard reset makes a marginal press feel arbitrary and punishes BOID jostle — one body squeezed out of the strip for 0.3s should not zero 1.7s of progress. Drain is forgiving, and it renders as a bar that visibly sags back, which teaches the rule.
- **No partial credit below the threshold.** Nineteen zombies against a twenty-fence do nothing, forever. This is the feature.

### A4.1 Why a hard threshold and not a damage race (recommended, argue-with-me)

The tempting alternative is proportional: fold rate scales with `press_count / press_threshold`, so forty zombies fold it twice as fast as twenty. **Recommend against.** Doors already own the "more bodies = faster" continuum, and they own it well. If fences also grade smoothly then a fence is just a door with a different verb skin, and the third currency in §0 collapses back into the second. The hard threshold makes the fence a **pass/fail attrition check** — a different question, asked once, answered by the state of your horde. Keep the currencies distinct.

*If it plays badly (Ben's judgement in the first sweep), the graded version is a one-line change and a parked knob is reserved for it: `fence_overpressure_factor`, default 1.0 = off.*

## A5. WHO COUNTS — CALM ZOMBIES DO (ruling carried forward)

Recommended, per the ideation record's own note and re-argued here:

- **Calm zombies count.** Ferals only ever go where prey went, so a feral-only fence with nothing behind it would never be pressed and the whole secret-path fantasy dies on arrival. Fiction carries it: this is **structural failure under weight**, not demolition, so "the calm reserve never demolishes" survives intact — the reserve gains a terrain verb, not an attack verb, exactly as it did with the calm door-breach.
- **Ferals count.** Same weight, no distinction.
- **Risers count** once they are living zombies. Consequence worth naming: bodies shot off a fence by a defender behind it **rise where they fell — inside the press strip — and rejoin the press**. A fenced gun position feeding its own siege is a genuinely great emergent image, and it falls out of existing rules.
- **Corpses and pending-rise bodies do not count** (not living units).
- **Specials count** (they are bodies). PoC-excluded regardless; note only.
- **Cowering humans, dead zombies, and anything else: irrelevant.** The count is `living_zombies` filtered by geometry, nothing more.

## A6. THE ZOMBIE SIDE

### A6.1 Calm zombies need NO new code at all

A calm zombie ordered to a point beyond a fence nav-paths toward it (fences are never carved from the navmesh, §A9.1), hits the barrier, and jams. Calm zombies have no give-up clock — `_tick_calm` simply keeps calling `nav_move_toward` and never arrives. It presses until told otherwise. `CalmBreach` is untouched and does not fire: `DoorBreach.door_in_arc` finds no *door*, so the wedge window closes on an ordinary jam and the move keeps trying — which is precisely correct behaviour here.

**Zero lines change in `zombie.gd`, `calm_breach.gd`, or `shamble_behavior.gd`.**

### A6.2 Ferals need exactly one rule — and it is an amendment

A feral chasing prey across a fence will wedge on it, make no progress, and — as the code stands — **calm out after `failsafe_window` (2s)**, wander off, and evaporate the press. That is a bug in waiting, and it is the mirror of the problem the buildings spec solved with the BREACHING failsafe exemption (§5.4.1 there).

**AMENDMENT to direction spec §3.4 rule 5 (the give-up failsafe):** a feral whose no-progress wedge window closes **while it stands in an intact fence's press strip, with its target on the far side**, enters **PRESSING**:

1. **The target is KEPT** (mirrors the door wedge siege exactly) — so the chase resumes the instant the fence folds, and the pursuit claim keeps that human off other ferals' menus.
2. **The failsafe clock is exempt** while PRESSING.
3. **Peel-off stays live** — the 0.25s scan runs as normal, and reachable prey pulls the feral off the fence immediately. A fence is the lowest-priority thing a feral can be doing, identical to a door.
4. PRESSING clears when the fence folds, when the target dies or is lost, or when the feral peels.

Implementation note: this is a **flag, not a state** — `_pressing_fence: Node2D` on `FeralBrain`, three guards, ~15 lines. It needs no component, no new sub-state in the dispatcher, and no changes to `PounceBehavior`. The strip lookup mirrors `DoorBreach.door_in_arc` as a static on `Fence` (`Fence.strip_at(zombie)`); it runs on the wedge cadence, never per frame.

### A6.3 The Mark

Unchanged and untouched. The Mark reorders prey; a fence is not prey. A marked human beyond an intact fence pulls ferals to the fence and no further, which is correct and readable.

## A7. THE VERB — ORDERS ARE FOR TERRAIN

No new grammar. Two ways to press a fence, both already-legal clicks:

1. **Implicit** — RMB on ground beyond the fence. The crew paths into it and presses. This is the common case and it needs nothing.
2. **Explicit (recommended, cheap)** — **RMB on the fence itself** resolves to a **move order distributed along the fence's near-side press line**: `FormationPlanner` slots spread *along the span* rather than in a circle, so the crew arrives spread across the strip instead of funnelling into one point. This is still a plain calm move order — no new state, no commitment, cancelable by any later order, selection retained.

`SelectionManager.handle_command` gains one case, slotted after the door case (human → building → door → **fence** → ground), plus `_fence_at()` and a hover telegraph on the fence outline matching the door's. **Release-on-fence does not exist** — a fence is terrain, and the v0.46.0 grammar ruling (*release is for prey, orders are for terrain*) settles it without further debate.

## A8. THE INDICATOR (Ben's explicit ask)

Three tiers of information, each answering a different question:

| Tier | Shows | Answers | When |
|---|---|---|---|
| **Requirement badge** | `⛓ 20` at the span's midpoint | *What will this cost me?* | **Always visible.** This is planning information — the same role door integrity plays, and the predictability pillar requires it be readable before you commit, not discovered by failing. |
| **Live counter** | `12 / 20`, red below threshold, amber-green at or above | *Am I actually folding it?* | While `press_count > 0`. The colour flip is the single most important readable moment on the object. |
| **Fold bar + sag** | A filling bar (Door's bar-layer visual language, z-10, continuous rather than chunked) **and the span visibly bowing** toward the pressing side, offset ∝ fold progress | *How much longer?* | While the meter is non-zero, including while it drains — watching it sag back when a body wanders off teaches the drain rule for free. |

- **The sag is the trope image** (WWZ's Jerusalem wall, TWD's prison fence) and it is nearly free: draw the span as a 3-point polyline whose midpoint offsets by `fold_progress × fence_sag_max` toward the majority-press side. Creak audio when the audio system is ready.
- **Majority side** for the sag direction: whichever side holds more pressers; tie → the side of the lowest-`unit_uid` presser (deterministic, §A9.2).
- All of it is **presentation reading simulation state** (guideline 6), drawn on the node for now and migrating to `vision_renderer` with everything else in Phase 5.

## A9. NAV, LOS AND DETERMINISM

### A9.1 The navmesh never changes — same rule as doors

A fence is **never carved from any navmesh**, intact or folded. Passage is denied by the physics barrier alone, exactly as the buildings spec §15 ruled for doors, and for the same reason: no runtime re-bake, so no bake-order determinism hazard. Consequences, both intended:

- A calm move order *through* a fence line paths into it and presses — which is what makes §A7.1 work at all.
- Humans path across it freely and correctly, because for them the mesh is telling the truth.
- **Accepted cost, identical to doors today:** a zombie route will go through a fence line even when an open gate is 80px away. Level-design guidance, not an engine rule (§A11).

### A9.2 Determinism (§10 holds in full)

- `press_count` comes from `GameManager.neighbours_within(centre, reach, &"zombies")` — registry, `unit_uid`-ordered — then the exact strip test. Never a group scan (guideline 8).
- The fold meter is a fixed-timestep accumulator on `_physics_process`. No wall-clock.
- Every tiebreak (sag side, and anything else that needs one) resolves by lowest `unit_uid`.
- No RNG anywhere; the fence needs no DetHash stagger because nothing about it is per-unit.
- Add a fence-fold scenario to the **boot-twice-and-diff** spot-check when built.

## A10. INTERACTIONS WORTH STATING

1. **Flee exit set** — a fence is not an exit and never joins the set. Humans cross fences on the way to real exits, so the existing threat-biased picker keeps working with zero changes and gains, for free, the property that a fenced route is a *safe* route for prey.
2. **`exit_block_radius` (120px)** — a known false-positive: zombies pressed against a fence within 120px of an escape zone on the *far* side will strike that exit off the list even though they cannot reach it. Low severity, purely a routing suboptimality, no freeze risk (the all-blocked fallback covers it). **Flagged to watch in play, not to fix pre-emptively** — the fix (LOS/reachability-gate the block test) is more machinery than the symptom justifies.
3. **The fill front** — sees through the fence, fires through the fence, and cannot be blocked by it. Defenders behind a fence are the fence's teeth.
4. **Fear** — passes through (fences don't block dread any more than they block sight). A crowd massing on the fence terrifies the compound. Intended: the mass gate announces itself.
5. **Herding** — `flee_repel` bends humans away from your zombies with no knowledge of fences, so a fence line with your crew behind it is a soft wall that pushes runners along it. Free and good.
6. **Contagion is not LOS-gated** (existing rule), so violence on one side of a fence ignites the reserve on the other. Consistent with the buildings-spec treatment; note it in level design when placing staging ground.
7. **Pounce over a fence?** No. Pounce triggers at 40px from a *target*, and the flight is straight-line; a target beyond an intact fence is beyond the barrier, so a lunge lands the zombie on the wire, not past it. (Contrast the hazard case, §B7.3, where leaping *is* possible and is a feature.)

## A11. THE LEVEL-DESIGN LAW: CAPACITY vs THRESHOLD

**A threshold that the span physically cannot hold is an unopenable fence and a designer error.** With ~24px of effective body width along the span and ~30px of BOID separation between ranks:

```
max_pressers ≈ floor(fence_length / 24) × floor(fence_press_depth / 30) × 2 sides
```

A 200px span at 60px depth holds roughly `8 × 2 × 2 = 32` — so a threshold of 20 is demanding but achievable, and a threshold of 40 is a wall. **Recommend the `@tool` script `push_warning()` in the editor when `press_threshold > 0.75 × max_pressers`**, printing both numbers. It costs five lines and prevents the single most likely authoring mistake.

Corollary the designer should internalise: **the way to make a fence harder is a bigger threshold OR a shorter span** — a short fence is hard because only so many bodies fit, and that reads visually, which is better than a big number.

## A12. NUMBERS v0 (all GameConfig + LevelConfig-overridable, per-fence where marked)

| Knob | v0 | Notes |
|---|---|---|
| `fence_press_depth` | **60 px** | each side. Deep enough for ~2 ranks (BOID separation is 30px) — a 25px door-style arc would cap the count at one rank and make thresholds depend on span alone |
| `fence_fold_time` | **2.0 s** | at/above threshold, from empty meter |
| `fence_relax_factor` | **1.0** | drain rate below threshold, × the fill rate |
| `fence_press_threshold` | **10** *(per-fence)* | THE level-design knob. 10 = "a decent crew"; 20+ = "a hoarded horde" |
| `fence_length` | **200 px** *(per-fence)* | span |
| `fence_thickness` | **8 px** *(per-fence)* | barrier band; thinner than a wall on purpose |
| `fence_sag_max` | **14 px** | presentation only |

Sweep jobs when it exists: does the threshold read as a *stock check* in play (does a player consciously bank bodies for it)? Does 2.0s feel like weight or like a formality? Is drain-vs-reset the right forgiveness?

## A13. PARKED (from Part A — do not build)

- **Graded overpressure** (`fence_overpressure_factor`) — §A4.1; only if the hard threshold plays badly.
- **Opaque fences** (`blocks_los: bool`) — hoarding/corrugated variant. One line, but it changes the tactical meaning entirely; ship the transparent one first and see if the other is even wanted.
- **Rubble on fold** (`folds_to_rubble`) — a folded fence leaves a SLOW hazard band (Part B) where it fell. Charming, cheap once Part B exists, and strictly a slice-3+ garnish.
- **Repairable / re-erected fences** — no. Barricading is a door mechanic (slice 2 there); a fence that comes back turns a stock check into a timing check and muddies the currency.
- **Human-blocking fences** — parked with the §A3.3 ruling, not rejected outright; needs the navmesh answer first.

---

# PART B — HOSTILE TERRAIN

## B1. THE FEATURE IN ONE PARAGRAPH

**Hazards** are placeable areas that charge the horde for crossing them: minefields, stake beds, barbed wire, electrified fence lines. They add no AI, no state, and no player verb. The design core, and the thing that makes them interesting rather than merely annoying, is Ben's own instinct: **the calm reserve routes around a hazard; the frenzy runs straight through it.** That single asymmetry turns every hazard into a live question about *how* you attack rather than *whether* you can — walk the crew around the wire under full control and lose the tempo, or release through it and pay in bodies for the speed. It also gives release a new, permanent, legible cost in exactly the places a designer chooses to put one.

## B2. PILLAR AUDIT (including the one real risk)

- **Attrition is currency** ✅ — this is the purest expression of it in the game. The hazard's whole existence is a price list.
- **Command the calm / released is released** ✅ — and *sharpened*. The reserve is safe because it is under control; the storm is expensive because it is not. Hazards make the pillar tangible instead of abstract.
- **Predictability over simulation** ✅ **— conditionally.** Hazards must be **fully visible to the player**, including minefields (§B5.1). Hidden hazards would convert planning into guessing and are a straight pillar violation. The zombies not knowing is fiction; the player not knowing is a bug.
- **Determinism** ✅ — fixed cadence, registry order, DetHash stagger for anything periodic, no RNG (§B9).
- **Player agency** ⚠️ **— one genuine risk, mitigated.** A **contagion** ignition next to a minefield could send the reserve into it with no player input — control taken away, which the pillars forbid. Two mitigations, both recommended: (a) **hazard deaths cause no contagion** (§B6.2), so a hazard can never start a chain reaction; (b) ferals only run at *prey*, so a hazard only ever bites when a human is on the far side — the trigger is always something the player can see. Residual risk is level-design hygiene (don't put a minefield within `contagion_radius` of the natural staging ground), and that belongs in the level-design notes, not in engine rules.
- **Meaningful decision or friction?** ✅ Route choice, release timing, and calm-vs-feral commitment are all real decisions. The failure mode to watch for in play is a hazard placed where there is no alternative route — that is pure friction, and it is a level-design error, not a mechanic error (§B10.3).

## B3. THE CORE MECHANISM — TWO NAVMESHES

### B3.1 The rule, in one sentence

> **CALM zombies and all humans path on the *careful* navmesh (visible hazards carved out). FERAL zombies path on the *reckless* navmesh (nothing carved).**

That is the entire mechanism. It is binary, memorable, needs no per-hazard AI, costs nothing per frame, and it produces Ben's stated intent exactly: the crew walks around the wire, the frenzy doesn't care. Risers rise CALM, so they inherit careful pathing automatically — a nice touch: fresh bodies don't immediately re-walk into the minefield that made them.

### B3.2 How it's built

`NavBaker` already collects `get_nav_footprint()` from every node that has one and bakes a single `NavigationRegion2D`. The change:

- **Region 1 (existing, `navigation_layers = 1`) = reckless.** Unchanged: walls and buildings carve it; hazards do **not**.
- **Region 2 (new, `navigation_layers = 2`) = careful.** Same source geometry **plus** the obstruction outlines of every hazard whose `hidden` flag is false.
- Each agent picks its mesh via `NavigationAgent2D.navigation_layers`: zombies flip theirs in `ignite_feral()` / `_set_calm()` (two lines in `zombie.gd`); humans set layer 2 once, where `FleeBehavior` creates its agent.
- Two bakes at boot instead of one. Both deterministic, both before the first physics tick, no runtime re-bake ever.

### B3.3 The risk, and the fallback (flag this before building)

Two `NavigationRegion2D`s overlapping in space on different navigation layers is the Godot-native way to express "different agent types avoid different things", but overlapping regions can interact oddly at edge-connection time. **Prototype this in a throwaway scene before committing to it** — one hazard, one calm zombie, one feral, confirm the two paths differ and neither agent's path snaps to the wrong region.

**Fallback if it misbehaves:** keep one navmesh (hazards carved from nothing, everyone free to walk in) and deliver calm avoidance as a **steering repulsion term** on calm movement — the same maths `flee_repel_strength` already uses to bend humans around zombies, applied to calm zombies around hazard centroids. Cheaper to build, reuses a proven pattern, and degrades gracefully (a calm crew may clip a hazard corner, which is a small toll and arguably characterful). Its real weakness is that steering cannot route around a *large* field — a wide minefield becomes a local minimum the crew grinds against. So: two-mesh first, steering as the retreat.

**A third option, explicitly rejected:** per-hazard "should I avoid this" logic on the units. It puts terrain knowledge in `zombie.gd`, violates one-owner-per-mechanic, and scales badly with hazard count.

## B4. THE DATA MODEL — ONE NODE, DATA NOT BRANCHES

New script `hazard_zone.gd` (`class_name HazardZone`, `@tool`, extends `Polygon2D`) — **name verified free**. Mouse-drawn footprint exactly like `Wall`, so authoring is drag-and-draw with no sidebar typing. Guideline 7 (*data over branches*) says the named hazards are **export presets on one class, not four classes**:

| Export | Type | Meaning |
|---|---|---|
| `toll_mode` | enum `{KILL_ON_ENTER, KILL_PERIODIC, SLOW}` | what it does to what's inside |
| `charges` | int | uses before the zone is spent. `-1` = infinite |
| `blast_radius` | float | on a KILL_ON_ENTER trigger, everything within this radius of the trigger point dies. `0` = only the trigger |
| `tick_period` | float | KILL_PERIODIC only — seconds between casualties |
| `speed_factor` | float | SLOW only — multiplier on movement speed inside |
| `hidden` | bool | `true` = carved from **neither** navmesh (nobody routes around it). `false` = carved from the careful mesh |
| `affects_humans` | bool | default **false** — the toll is on the horde unless the designer says otherwise (§B7) |
| `armed` | bool | default `true` — the power switch the generator concept (ideation §3.1) will drive later. An unarmed hazard is inert terrain |
| `denies_risers` | bool | default `false` — parked rider, §B5.6 |

A "minefield" is then a saved set of export values, not a code path. Adding a hazard type later should be a row in a table, never a new script.

## B5. THE KIT

### B5.1 Minefield — the one that hits everyone
`KILL_ON_ENTER`, `charges = N`, `blast_radius ≈ 60px`, **`hidden = true`**.

Answers Ben's own question ("minefield affects everyone?") with **yes, in the sense that matters**: nobody routes around it, calm and feral alike, because nobody can see a buried mine. Each entry consumes a charge and kills every zombie in the blast — so a tight column pays badly and a spread crossing pays once. A spent field is inert ground, permanently: **the minefield is the only hazard the player can exhaust**, which makes "walk the cheap bodies through first" a real and satisfying play.

**The player sees the whole field, always** (§B2). Render it distinctly from avoided hazards — recommend a **dashed danger border** for `hidden` zones vs a solid one for avoided zones, so "my units will not route around this" is a visual property, plus remaining charges printed.

### B5.2 Stakes / spike perimeter — the pure asymmetry
`KILL_ON_ENTER`, `charges = -1`, `blast_radius = 0`, `hidden = false`.

The clean expression of Ben's instinct: the crew walks around the spike bed, the frenzy impales itself on it, forever, one body per crossing. Cheapest hazard to reason about and the best teaching object for the whole calm/feral rule — recommend it be the **first** hazard built and the one the tutorial-ish level leans on.

### B5.3 Barbed wire — the one that spends time, not bodies
`SLOW`, `speed_factor ≈ 0.4`, `hidden = false`, `affects_humans = false`.

Kills nobody. It locally **shifts the sacred ratio**: inside the wire the fill front wins races it normally loses, so a defender covering a wire band is worth several defenders in the open. This is strategically the most interesting hazard in the kit precisely because it charges the *other* currency, and it is nearly free to build (a speed multiplier). `affects_humans = false` by default is a deliberate asymmetry — it's a defensive installation, built to slow attackers, and making it symmetric would mostly cancel its own effect.

### B5.4 Electrified fence — the join (slice 3)
A **`Fence` with `electrified = true`**, not a separate hazard node: the fence already owns the strip geometry and the press count, so putting the shock on the fence keeps one owner per mechanic and gives the designer one node instead of two overlapping ones.

While powered, one presser dies every `shock_interval` — **exactly one**, the lowest `unit_uid` in the strip (deterministic, §B9). The maths a designer should have in their head: threshold 10, `fence_fold_time` 2.0s, `shock_interval` 1.5s → folding it costs about **two bodies**, provided you can *hold* ten in the strip while it eats them. Raise `fence_fold_time` and the toll climbs proportionally; make the shock fast enough and the fence becomes genuinely unfoldable, which is a valid level statement so long as another route exists. Depowering it (generator, deep pocket) leaves an ordinary fence — the side objective literally opens the secret path, exactly as the ideation record framed it.

### B5.5 Free by-products of the model (no extra code)
- **The moat / one-way membrane** — a `Fence` with `press_threshold` set impossibly high (or a dedicated `foldable = false`) is a river, canal, or ha-ha: humans cross, zombies never do. A pure level-geometry primitive, free from Part A.
- **The bear trap** — a `HazardZone` with `charges = 1`, `blast_radius = 0`. Single-use, cheap to scatter, and it makes a corridor feel mined without a minefield's cost. Free from the data model.
- **Rubble / choke** — `SLOW` with `affects_humans = true`, a neutral pacing tool for both teams. Free.

### B5.6 Fire zone — recommend PARKING to a later slice
`KILL_PERIODIC` + `denies_risers = true`, carrying the ideation record's §2.3 **kill-context riser denial**: a human killed inside it does not stand back up. *Where* you kill decides whether you keep the body, which is a genuinely deep addition to the attrition maths.

It is parked not because it is bad but because it is the only member of the kit that reaches into the riser pipeline (`ViolencePipeline.register_pounce_kill` would have to ask "was this kill inside a denial zone?"), and one feature at a time. **The hook to leave in place:** `denies_risers` exists on the data model from day one, unread. Land it as slice 4 with the flamethrower/vehicle defender it was designed alongside.

## B6. THE DEATH PATH — AND THE ONE EXISTING RULE THIS CHANGES

### B6.1 A second way for a zombie to die

`ViolencePipeline.report_gunfire_kill` currently carries a load-bearing comment: *"gunfire is the only way a zombie dies in v2, so this is frame-exact and teardown-immune"* — the A4/A5 lose-verdict fix depends on it. **Hazards break that invariant**, and the fix must land in the same commit:

```
ViolencePipeline.report_hazard_kill(zombie, hazard)
    → zombie.take_damage(1.0)
    → _gm.check_lose_condition()      # the verdict stays at the death instant
    → (no contagion — see B6.2)
```

Update the comment on both functions to read *"the two zombie-death sources"*. A player who marches their last bodies into a minefield must lose at that instant, exactly as they do to gunfire.

### B6.2 Hazard deaths cause NO contagion (recommended)

Contagion exists to model *"you shot us, we're coming for you"* — human violence drawing the horde onto the human. A mine has nobody to charge at. Igniting the reserve on a hazard death would be actively harmful in three ways: it would wake zombies targetless, it would make hazards **self-detonating traps** (walk one zombie in, the reserve ignites and pours into the field), and that third one is a straight agency-pillar violation — control lost with no player input. **Rule: hazard deaths are silent.** No contagion, no score change, no combo effect (the combo counts pounce kills only and is untouched). They cost you a body and nothing else.

### B6.3 Human deaths in hazards — riser denial for free

If `affects_humans` is true and a human dies to terrain, it dies through the normal `Human.die()` path — which means it emits `human_died`, `GameManager._on_human_died` fires, and `check_win_condition()` runs. It does **not** route through `register_pounce_kill`, so:

- it is **not scored** (correct — the pounce is the scored event),
- it produces **no riser** — kill-context riser denial, achieved with no new code,
- and the escaped-stat equivalent applies conceptually: a body you didn't get.

State it as the design consequence it is: **herding prey across your own minefield throws the body away.** That is a real, learnable, deterministic trade.

## B7. HUMANS AND HAZARDS

1. **Humans path on the careful mesh**, so they route around every visible hazard without any new code — including their own installations, which is the right fiction (they know where the safe lane is).
2. **Hidden hazards (minefields) catch humans too** *if* `affects_humans` is true, since nobody routes around them. Default false keeps the toll on the horde per Ben's stated intent; a designer wanting the "herd them into the minefield" beat flips one flag and accepts §B6.3's cost.
3. **Flee repulsion can shove a human into a hazard** — `flee_repel` bends routes around zombies without consulting the navmesh. That is not a bug: it is **herding into terrain**, the most advanced expression of the herding verb the game has, and it only ever happens because the player built the wall of bodies that caused it.
4. **Pouncing over a hazard is legal and is a feature.** The lunge is straight-line and lands on the prey, so a feral that reaches pounce range at the edge of a wire band leaps it clean. Zombie-movie-correct, emergent, and worth calling out so nobody "fixes" it.

## B8. READABILITY

- **Footprint fill** in a danger tint, distinct per `toll_mode` (lethal / periodic / slow should be three different reads at map scale).
- **Border encodes avoidance:** solid = your calm crew will route around it; **dashed = nobody routes around it**. This is the single most important piece of information on the object and it deserves its own visual channel.
- **Charge counter** on consumable zones; **spent zones grey out** and read as inert.
- **A kill flash** at the point of a hazard death — hazards must never kill invisibly, or the player learns nothing from losing bodies.
- Interim on-node drawing; migrates to `vision_renderer` in Phase 5 with everything else.

## B9. DETERMINISM (§10 holds in full)

- The field ticks on a fixed `hazard_scan_interval` (v0 **0.1s**) — 14px of travel per tick at `zombie_speed` 140, precise enough for a mine and cheap enough to ignore.
- Containment: registry radius query on the zone's bounding circle → exact `Geometry2D.is_point_in_polygon`. Registry order = `unit_uid` order.
- Multiple units entering on the same tick are processed in `unit_uid` order; charge consumption and blast resolution follow that order, so a two-charge field always eats the same two zombies.
- Periodic damage (electrified, fire) is **DetHash-staggered per unit**, the house pattern — reusing `DoorBreach.first_pound_delay`'s shape with its own salt.
- No wall-clock, no RNG anywhere.
- Add a hazard-crossing scenario to the boot-twice-and-diff spot-check.

## B10. ARCHITECTURE

### B10.1 One owner, and it is a system not a node

`hazard_field.gd` (`class_name HazardField`, **name verified free**) — a child of `GameManager` alongside `ViolencePipeline`, `HuntPool`, and `MarkSystem`, reached by one-line delegates like its siblings. It owns the tick, the containment tests, the kill calls, and the slow-factor bookkeeping. `HazardZone` nodes are **dumb geometry and data** (like `ShelterSpot`) — they draw themselves and answer `contains(point)` and `get_nav_footprint()`, and they never tick.

Why a system rather than per-node ticking (which is what `Door` does): overlapping zones. Two hazards touching the same unit need a single deterministic resolution — slowest factor wins, kills resolve in one order — and per-node ticking would make that depend on scene order. The field computes, per cadence, one verdict per unit.

### B10.2 The one seam in `unit.gd`

SLOW needs to scale movement, and speed is currently passed per call (`nav_move_toward(point, GameConfig.zombie_speed)`). Add **one field**: `Unit.terrain_speed_factor: float = 1.0`, applied inside `step_toward` / `nav_move_toward` / `move_to_target`. `HazardField` sets it on entry and restores it on exit (it tracks which units it slowed last tick and diffs). No call site changes; default 1.0 means every existing level is byte-identical.

### B10.3 Level-design guidance (belongs in the doc, not the engine)

- **Always leave an alternative route.** A hazard with no way around it is not a decision, it is a toll booth — pure friction, and the pillars say to reject it.
- **Keep hazards outside `contagion_radius` (150px) of natural staging ground** (§B2's residual risk).
- **Hazards pair with counter-specials** — from the ideation record, for the post-PoC specials re-audit: the Fat Zombie's corpse bridges wire and mines (the body-on-the-wire trope), the Headless's straight-line charge is a natural minesweeper, the Scuba answers moats. **Every hazard should eventually ship with its counter-key.** Nothing to build now; record it so the re-audit inherits it.

## B11. NUMBERS v0 (all GameConfig + LevelConfig-overridable; per-zone where marked)

| Knob | v0 | Notes |
|---|---|---|
| `hazard_scan_interval` | **0.1 s** | global field cadence |
| `mine_blast_radius` | **60 px** *(per-zone)* | a tight column pays badly; a spread crossing pays once |
| `charges` | **−1 / per-zone** | −1 = infinite (stakes, wire); finite = exhaustible (mines, traps) |
| `speed_factor` (SLOW) | **0.4** *(per-zone)* | barbed wire; the sacred-ratio shifter |
| `tick_period` (KILL_PERIODIC) | **1.5 s** *(per-zone)* | one casualty per period |
| `shock_interval` (electrified fence) | **1.5 s** *(per-fence)* | ≈2 bodies to fold a threshold-10 fence at `fence_fold_time` 2.0s |

Sweep jobs: does a stake bed read as "go around" without being told? Is a minefield's charge count legible mid-crossing? Does barbed wire change how a defender position feels, or just how long it takes to reach?

## B12. PARKED (from Part B — do not build)

- **Fire zone + `denies_risers`** (§B5.6) — slice 4, with its defender.
- **The generator / power grid** (ideation §3.1) — `armed` is the hook, unread until then.
- **Dynamic hazards** (petrol spill you ignite, collapsing terrain) — needs a trigger system; nothing here anticipates it beyond `armed`.
- **Hazards that damage buildings or doors** — no. Terrain hurts units.
- **Per-hazard unit resistances** — that's the counter-specials answer, and it belongs to the specials re-audit, not here.

---

# PART C — BUILD ORDER, TESTS, COMPATIBILITY

## C1. Slicing (one feature at a time, per rule 3)

| Slice | Contents | Touches | Suggested bump |
|---|---|---|---|
| **1 — Fences** | `fence.gd`, the press rule, the indicator, the `FeralBrain` PRESSING flag, the `SelectionManager` fence-click | 1 new script + ~20 lines across two existing | MINOR |
| **2 — Hazards** | `hazard_zone.gd`, `hazard_field.gd`, the two-mesh `NavBaker` change, `report_hazard_kill`, `Unit.terrain_speed_factor` | 2 new scripts + `nav_baker`, `violence_pipeline`, `unit`, `zombie`, `flee_behavior` | MINOR |
| **3 — Electrified fence** | `electrified` on `Fence`, wired to `report_hazard_kill` | ~20 lines | PATCH or MINOR |
| **4 — parked** | fire zone + riser denial | — | later |

**Fences first**, deliberately: they need no navmesh work, no new death source, and no changes to the win/lose invariants — so slice 1 is a clean, self-contained, independently testable feature, and slice 2's riskier navmesh work lands on a stable base. Slice 3 is the join and cannot precede either.

Reminder for whoever builds it: a new `class_name` script created outside the editor needs `<godot> --headless --import --path .` before the parse gate, or `tools/check.ps1` fails on a *consumer* script with a misleading error.

## C2. Acceptance tests (manual, per project convention)

**Slice 1 — fences**
1. **Under threshold:** park `threshold − 1` calm zombies in the strip for 30s → the meter never leaves zero, the counter reads red, nothing folds.
2. **At threshold:** add one more → the counter flips colour, the bar fills, the span sags, and it folds at `fence_fold_time`. The whole crew then walks through under full control, still selected.
3. **Drain:** reach ~70% fill, walk two zombies out → the bar visibly drains; walk them back → it refills from where it drained to, not from zero.
4. **Feral press:** release a crew at a human on the far side → they wedge, **do not calm out after 2s** (the §A6.2 amendment), hold their targets, and resume the chase the instant it folds.
5. **Peel wins:** with ferals pressed on a fence, walk a live human within `chain_scan_radius` on *their* side → they abandon the fence immediately.
6. **Humans ignore it:** a fleeing human crosses an intact fence without pausing, and pursuit stops dead at the wire.
7. **Defenders shoot through:** a militia behind an intact fence kills pressers; the corpses **rise in the strip and rejoin the press**.
8. **Explicit order:** RMB the fence itself → the crew spreads *along* the span, not into a knot at one point.
9. **Determinism:** boot-twice-and-diff a scripted fold (count timings, fold frame, sag side identical).
10. **Backwards compat:** a level with no `Fence` plays byte-identically.

**Slice 2 — hazards**
11. **The asymmetry:** order a calm crew to a point beyond a stake bed → it routes around. Release at a human beyond the same bed → the ferals run straight in and die at one body per crossing.
12. **Exhaustion:** a 3-charge minefield eats exactly three crossings (blast included), then reads spent and is inert.
13. **Lose verdict:** march the last surviving zombies into a minefield → defeat registers **at the death instant**, not on teardown.
14. **No chain reaction:** park the calm reserve inside `contagion_radius` of a minefield and detonate one mine → **nothing ignites**.
15. **Slow:** a zombie crossing barbed wire visibly halves its pace and dies to a defender it would otherwise have reached (the sacred-ratio shift).
16. **Riser denial:** with `affects_humans = true`, herd a civilian into a mine → it dies unscored and **does not rise**.
17. **Pounce-over:** a feral reaching pounce range at a wire edge leaps the band and lands clean.
18. **Determinism + compat:** boot-twice-and-diff a crossing; a level with no `HazardZone` plays byte-identically.

## C3. Backwards compatibility

Both features are **purely additive**. No existing level contains a `Fence` or a `HazardZone`; `Unit.terrain_speed_factor` defaults to 1.0; the careful navmesh with no hazards in it is identical to the reckless one; `report_hazard_kill` is unreachable without a hazard. Every existing scene plays byte-identically, and that is test 10/18's job to prove.

---

**END OF DRAFT** — Ben rules §1, corrections fold in, then slice 1 is proposed for build as its own step.
