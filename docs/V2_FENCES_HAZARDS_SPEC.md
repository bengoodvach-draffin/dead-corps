# DEAD CORPS — FENCES & HOSTILE TERRAIN SPEC

**Version:** 1.0 (2026-08-01 — design locked from the Ben/Claude session of the same day)
**Status:** **DESIGN LOCKED, NOTHING BUILT.** This doc is written to be *built from* by an implementer who was not in the design conversation: every rule is stated in full, every integration point is named, every number has a home. Rule 1 (propose-before-implementing) still applies per slice — propose the slice, get the go-ahead, then write code.
**Scheduling:** promoted out of `TROPE_IDEATION_2026-07-27.md` §2.1/§2.2, whose gate was "post-M1-verdict at the earliest". **Ben moved that gate on 2026-08-01** — both features are pulled forward so the Phase 6 PoC level can be built with the full terrain vocabulary. §C1 sequences it so the M1 verdict isn't destabilised.
**Relationship to other docs:** extends `V2_ENTERABLE_BUILDINGS_SPEC.md` (terrain kit, §16.2) and `V2_DIRECTION_SPEC.md`. It changes exactly **three** existing rules, each flagged in place:
1. the feral give-up failsafe gains a fence exemption (§A6.2);
2. `report_gunfire_kill` stops being the only way a zombie can die (§B7.1);
3. the navmesh becomes **two** meshes instead of one (§B3).

---

## 0. THE THESIS — THREE BARRIERS, THREE CURRENCIES

The pillar says *every wall has a body price*. These features split the toll into three currencies so a designer can ask the player for different things:

| Barrier | Charges | The question it asks | Status |
|---|---|---|---|
| **Door** (buildings spec §4) | **TIME** — and risk, since pounders stand still under fire | *Can you afford to stop here?* | ✅ v0.44.0 |
| **Fence** (Part A) | **STOCK** — peak simultaneous horde size | *Did you keep enough of them alive?* | this spec |
| **Hazard** (Part B) | **FLOW** — bodies or seconds per crossing | *Is this route worth what it eats?* | this spec |

Deliberately non-substitutable. A door yields to six zombies given ten seconds; a fence yields to twenty zombies or to nobody at all; a hazard takes its cut every time anything crosses.

**And the placement law that governs both, which belongs in the level-design notes:**

> **Walls go on boundaries. Hazards go on the lines the chase wants to cut.**

If a hazard is doing a wall's job, use a wall. A hazard only earns its slot where the frenzy's route and everyone else's route *differ* — that difference is the whole product.

Neither feature adds a player verb, and neither adds a zombie state. The horde behaves exactly as it does today; the terrain reads the horde and reacts.

---

## 1. RULINGS (Ben, 2026-08-01) — do not re-litigate

1. **A fence blocks everyone** — humans and zombies alike, until it folds.
2. **A folded fence stays impassable to humans** for the rest of the level. Provisional: *"we can try 'no' for now and see if it negatively impacts play"* (§A9.3 records the tell and the upgrade).
3. **Fences fold on a hard threshold** — N pressers for T seconds, binary, no partial credit below N.
4. **Mines are 1:1** — one mine kills exactly one zombie, then it's spent. Fields are hand-placed; spacing is the design language.
5. **Corpse-road principle**, delivered by rule 4: a spent mine is a permanent hole in the field. Area kill-zones do **not** pave.
6. **Stakes kill from one direction only.** Mines and wire are omnidirectional.
7. **Stakes slow humans, never kill them.** The slow *is* the readability — no art required.
8. **Barbed wire slows humans too.**
9. **Hazard deaths cause no contagion.**
10. **Fire zones are CUT.** Not parked — cut. Do not re-pitch.
11. **Ledge drops are recorded for the future, not built** — no art language for "down" yet (§B10).
12. **Electrified fences + the generator are post-PoC** (§B9).

### 1.1 Assumptions taken where no ruling exists (cheap to overturn — say so and they change)

- **A fence is transparent to sight, shot and dread** (§A3.3). It's the absence of a `DoorLOS` body, so reversing it is additive, not a rewrite.
- **The calm crew cannot be walked into a lethal hazard** — the careful navmesh routes them around, and an order *into* a stake bed walks them to the edge and stops (§B6.3).
- **`fence_press_threshold` defaults to 8** in GameConfig, with the real tuning done per-fence against each level's horde size (§A12).

---

# PART A — FENCES

## A1. THE FEATURE IN ONE PARAGRAPH

A **fence** is freestanding terrain that nothing crosses. It cannot be pounded, has no integrity, and takes no damage: it folds when **enough bodies press against it at once, for long enough**. A fence requiring twenty is a door six zombies can never open and twenty can open in two seconds. It is the **mass gate** — *a secret path, if you got this far with a big horde* — and it walls humans in as well as zombies out, so a fenced compound is a trap its own defenders built: fold the wire and the people inside have nowhere left to run.

## A2. PILLAR AUDIT

- **Attrition is currency** ✅ with a twist — the fence charges *peak stock*, not expenditure. The first mechanic that rewards the horde you still have rather than the horde you spent.
- **Command the calm, influence the storm** ✅ — a terrain verb for the reserve, exactly like the calm door-breach (v0.46.0). The reserve pushes; it never demolishes and never attacks. *Release is for prey, orders are for terrain* holds.
- **The frenzy chases what moves** ✅ — a feral pressed on a fence peels for reachable prey exactly as a besieger leaves a door (§A6.2).
- **Determinism** ✅ — registry count, fixed-timestep accumulator, no RNG (§A9.4).
- **Predictability** ✅ — the requirement is printed on the fence, readable before you commit (§A8).
- **Agency** ✅ — a calm crew ordered into a fence keeps its selection and its orders and leaves the moment you say so.

## A3. THE OBJECT

### A3.1 Structure

**New script `scripts/fence.gd` — `class_name Fence`, `@tool`, `extends Node2D`.** Name verified free against `scripts/` on 2026-08-01.

Deliberately the **Door pattern, not the Wall pattern**: a straight segment laid along local **+X**, with rotation, so Door's segment maths (arc test, barrier quad, bar placement) transfers directly. Local **±Y** is the two sides.

- A fence is its **own fold unit**. A long run is one long `Fence` (folds whole) or several short ones end to end (folds **piecewise** — the crowd opens the section it pressed). Chained fences share no state.
- A fence may be a child of a `ShelterBuilding` or standalone. **No shelter semantics either way**: it never joins the flee exit set, never converts anyone to SHELTERED, never locks.
- **A fence is never carved from any navmesh** (§A9.1). It defines no `get_nav_footprint()` and does not join `"nav_obstacle"`. Leave a comment saying so — its absence is deliberate, not an oversight.
- `_ready()` joins group **`"fences"`** (one-time wiring; the static lookup in §A6.2 uses it).

### A3.2 Exports

| Export | Type | Default | Notes |
|---|---|---|---|
| `fence_length` | float, range 32–800 | 200.0 | span along local X |
| `fence_thickness` | float, range 2–40 | 8.0 | barrier band; thinner than a wall on purpose |
| `threshold_override` | int | 0 | 0 = use `GameConfig.fence_press_threshold`. Mirrors Door's `integrity_override` pattern |
| `fence_color` | Color | grey-green | programmer art |
| `electrified` | bool | false | **slice 3, §B9** — declare it now, leave it unread |

All setters `queue_redraw()`.

### A3.3 Barriers and the two deliberate absences

Two runtime `StaticBody2D`s across the span, built exactly like `Door._make_barrier` (rect shape `Vector2(fence_length + fence_thickness, fence_thickness)`, `collision_mask = 0`):

- **`ZombieBarrier`** — `collision_layer = 8` (layer 4 "EscapeBarrier"). Zombies (mask 9) slide off it.
- **`HumanBarrier`** — `collision_layer = 32` (layer 6 "DoorLock"). Humans (mask 33) bounce off it; zombies never collide with it. **Also `add_to_group("fence_barriers")`** — §A10 keys off that group membership.

**No project-settings change and no new collision layer.** Both layers already exist for Door.

At fold: **zero both `collision_layer`s, then `queue_free()` the bodies** — the same breach-frame race fix Door needed, for the same reason (same-frame raycasts and moves must not hit a dying blocker).

The two absences, both deliberate:

1. **No LOS blocker.** Chain-link is see-through: defenders behind an intact fence shoot the crowd pressing it, and fear counts pass through. *(Assumption, §1.1 — reversing it means adding a `DoorLOS`-layer body, nothing more.)*
2. **No integrity, no `apply_pound`, no damage of any kind.** One zombie left on a fence overnight achieves exactly nothing. This is the whole distinction from a door and it stays absolute.

## A4. THE FOLD RULE

> While **`press_count` ≥ `threshold`**, the fold meter fills at `1 / fence_fold_time` per second. At 1.0 the fence **folds, permanently**. Below the threshold the meter **drains** at `fence_relax_factor ×` that rate, clamped to 0.

**`press_count`** = living zombies whose `global_position` lies in the **press strip**, in local coordinates:

```
abs(local.x) <= fence_length * 0.5 + STRIP_SIDE_MARGIN      # const 12.0, mirrors Door.ARC_SIDE_MARGIN
abs(local.y) <= fence_thickness * 0.5 + GameConfig.fence_press_depth
```

Both sides count and are not distinguished — a fence has no "inside", and a crowd split across it is still weight on the wire.

**Registry query radius must cover the strip's corners, not its centre:**
```
reach = Vector2(fence_length * 0.5 + STRIP_SIDE_MARGIN,
                fence_thickness * 0.5 + GameConfig.fence_press_depth).length()
gm.neighbours_within(global_position, reach, &"zombies")   # then the exact strip test
```
A radius computed from the half-length alone misses the ends of a long fence.

**Rules that follow:**

- **Presence, not intent.** No check that a zombie is "pushing". Ordered there, jammed there, or idle-shambling there all count (`shamble_leash` is 5px, so a parked crew stays parked). Intent-detection would be invisible state; the dwell timer is what stops incidental contact folding anything.
- **Drain, not reset.** One body squeezed out of the strip for 0.3s must not zero 1.7s of progress, and a bar visibly sagging back teaches the rule without a tutorial.
- **No partial credit below the threshold.** Nineteen zombies against a twenty-fence do nothing, forever. Doors own the "more bodies = faster" continuum; if fences graded smoothly, the third currency in §0 would collapse into the second.

### A4.1 Who counts

- **Calm zombies count.** Ferals only go where prey went, so a feral-only fence with nothing behind it would never be pressed and the secret-path fantasy dies. Fiction carries it: **structural failure under weight**, not demolition — so "the calm reserve never demolishes" survives; the reserve gains a terrain verb, not an attack verb.
- **Ferals count.** Same weight, no distinction.
- **Risers count** once alive. Consequence: bodies shot off a fence by a defender behind it **rise in the strip and rejoin the press**.
- **Corpses and pending-rise bodies do not count** (not living units). **Specials count** (they are bodies; PoC-excluded regardless).
- **Humans never count.** Only the dead press.

## A5. FOLDING

`_fold()`:
1. `_folded = true`
2. Zero both barrier `collision_layer`s, then `queue_free()` both, null the references.
3. `folded.emit(self)` — signal declared for future listeners; nothing consumes it in slices 1–2.
4. `queue_redraw()` on the node and the bar layer.

Fold is **permanent and irreversible**. There is no repair, no re-erection, no barricading — that is a door mechanic, and a fence that comes back turns a stock check into a timing check.

No score, no contagion, no combo interaction. A fold is not violence.

## A6. THE ZOMBIE SIDE

### A6.1 Calm zombies need no new code at all

A calm zombie ordered past a fence nav-paths toward the goal (fences are in nobody's mesh, §A9.1), hits the barrier, and jams. Calm zombies have **no give-up clock** — `_tick_calm` keeps calling `nav_move_toward` and simply never arrives. It presses until told otherwise.

`CalmBreach` is untouched and does not fire: `DoorBreach.door_in_arc` finds no *door*, so the wedge window closes on an ordinary jam and the move keeps trying — exactly right here.

**Zero lines change in `zombie.gd`, `calm_breach.gd`, `shamble_behavior.gd`.**

### A6.2 Ferals need one rule — AMENDMENT to direction spec §3.4 rule 5

Without this, a feral chasing prey across a fence wedges, makes no progress, and **calms out after `failsafe_window` (2s)** — evaporating the press. This mirrors what the buildings spec solved with the BREACHING exemption (§5.4.1 there).

**A feral whose no-progress wedge window closes while it stands in an intact fence's press strip, with a live target, enters PRESSING:**

1. **The target is KEPT** — mirrors the door wedge siege exactly. The chase resumes the instant the fence folds, and the pursuit claim keeps that human off other ferals' menus.
2. **The failsafe clock is exempt** while PRESSING.
3. **Peel-off stays live** — the 0.25s scan runs as normal; reachable prey pulls the feral off the fence immediately. A fence is the lowest-priority thing a feral can be doing, identically to a door.
4. **PRESSING clears** when the fence folds or becomes invalid, when the target dies or is lost, when the feral peels, or on `clear()` / `set_target()`.

**Implementation — a flag, not a state.** In `feral_brain.gd`:

- `var _pressing_fence: Node2D = null`
- In the wedge-check block that currently consults `DoorBreach.door_in_arc(_owner)`: if that returns null, try `Fence.strip_at(_owner)`; a live result sets `_pressing_fence`.
- `_check_failsafe()` returns "no give-up" while `_pressing_fence` is valid and intact.
- Clear it at the four points above.
- **Movement is untouched.** The feral keeps nav-moving at its target and physically jams on the barrier. No new movement code, no dispatcher sub-state, no `PounceBehavior` change.

**Static helper on `Fence`** (mirrors `DoorBreach.door_in_arc`; lives on Fence rather than a shared static because only FeralBrain needs it):

```gdscript
static func strip_at(zombie: Node2D) -> Fence:
    for f in zombie.get_tree().get_nodes_in_group("fences"):
        if not is_instance_valid(f) or not f.is_intact():
            continue
        if f.in_press_strip(zombie.global_position):
            return f
    return null
```
Group lookup is legal here: it runs on the **wedge cadence, never per frame** (same justification as `door_in_arc`). Scene order resolves overlapping strips, deterministically.

### A6.3 The Mark

Unchanged and untouched. The Mark reorders prey; a fence is not prey. A marked human beyond an intact fence pulls ferals to the fence and no further, which is correct and readable.

## A7. THE VERB — ORDERS ARE FOR TERRAIN

No new grammar. Two ways to press:

1. **Implicit** — RMB on ground beyond the fence. The crew paths into it and presses. Needs nothing.
2. **Explicit** — **RMB on the fence itself** issues a plain calm move order with slots **spread along the fence's near side**, so the crew arrives across the strip instead of funnelling into one point. Still an ordinary move order: no new state, no commitment, cancelable by any later order, **selection retained** (v0.45.3 behaviour).

**`selection_manager.gd` changes:**
- New `_fence_at(world_pos) -> Node2D` — hit-test in each fence's local space: `abs(local.x) <= fence_length*0.5 + PICK_MARGIN and abs(local.y) <= fence_thickness*0.5 + PICK_MARGIN` (PICK_MARGIN ≈ 10). Intact fences only.
- Insert into `handle_command`'s resolution chain **after the door case**: human → building → door → **fence** → ground.
- New `_order_press_at_fence(fence, calm_zombies)` — assigns `Fence.press_slots(n, from)` in **unit_uid order** and calls `set_move_target` per zombie (same shape as `_order_breach_at_door`).
- `_update_release_hover` gains the fence case → `fence.set_hover_highlighted(true)` (mirror Door's).

**`Fence.press_slots(count, from_pos) -> Array[Vector2]`:** `count` points spread evenly along the span on the side nearest `from_pos`, offset `fence_press_depth * 0.5` out from the band. If spacing would fall below 24px, wrap into a second rank at `fence_press_depth * 0.9`. Deterministic and stateless.

**Release-on-fence does not exist.** The v0.46.0 grammar ruling settles it: *release is for prey, orders are for terrain.*

## A8. THE INDICATOR

Three tiers, each answering a different question. All are **presentation reading simulation state** (guideline 6), drawn on the node now, migrating to `vision_renderer` in Phase 5. Drawn on a **z-10 child layer** (`Door._bar_layer` pattern) so a crowd at the fence never buries them.

| Tier | Shows | Answers | When |
|---|---|---|---|
| **Requirement badge** | `⛓ 20` at the span midpoint | *What will this cost me?* | **Always.** Planning information — the pillar requires it be readable before you commit, not discovered by failing |
| **Live counter** | `12 / 20`, red below threshold, amber-green at or above | *Am I actually folding it?* | While `press_count > 0`. **The colour flip is the single most important readable moment on the object** |
| **Fold bar + sag** | Bar filling (Door's bar language, continuous rather than chunked) **and the span bowing** toward the pressing side | *How much longer?* | While the meter is non-zero, **including while it drains** — watching it sag back teaches the drain rule for free |

**The sag** is the trope image (WWZ's Jerusalem wall, TWD's prison fence) and is nearly free: draw the span as a 3-point polyline with the midpoint offset by `fold_fraction() * GameConfig.fence_sag_max * majority_sign`.

**`majority_sign`** = the local-Y sign of whichever side holds more pressers; tie → the side of the **lowest-`unit_uid`** presser; nobody → 0. Deterministic.

**Folded state** draws two end posts plus the span darkened and fully offset — a collapsed line on the ground. No collision, permanently.

## A9. NAVMESH AND HUMANS — THE CHEAP ANSWER

### A9.1 Fences are in nobody's mesh

Both meshes (§B3) leave fence lines **open**, exactly as doors do. Passage is denied by physics barriers alone. No fence, folded or intact, is ever carved from anything, so **no runtime re-bake ever happens** and the buildings-spec §15 invariant survives untouched.

Consequences, all intended:
- A calm move order *through* a fence paths into it and presses — which is what makes §A7.1 work at all.
- A feral pursuit paths into it and wedges → PRESSING (§A6.2).
- **Humans path into it too** — see §A9.2, which is the whole reason this is affordable.
- Accepted cost, identical to doors today: a zombie route goes through a fence line even when an open gate is 80px away. Level-design guidance (§A11), not an engine rule.

### A9.2 Humans: bump, write off, re-pick

The reason humans *seemed* to need a navmesh carve isn't the blocking — it's what they do after. A zombie that jams on a fence is doing the intended thing. A human that jams trips the cower detector after `cower_window` (1.2s) and cowers there, which is a stuck-human bug.

**Fixed reactively, reusing two mechanisms that already exist:**

> A **FLEEING** human whose blocking collision is a `fence_barriers` body **writes its committed exit off permanently (for that human only)** and immediately re-picks from the exit set.

- The per-human write-off is the **no-return latch** shipped in v0.47.0 (a flushed runner writing off shelters inside a breached footprint). Generalise that set from "written-off shelters" to "written-off exits" and add the bumped exit to it.
- The re-pick is the **exit-churn re-path** already in `FleeBehavior` (it tracks its committed exit node and re-picks when that exit drops out).
- Collision detection: test whether the collider is in group `"fence_barriers"` — cheap, robust, no name matching. Read it from the human's existing move result; do not add a second physics query.
- If every exit ends up written off, the existing **unfiltered fallback** applies (a desperate run at the least-bad exit beats freezing), and the cower detector corners them within `cower_window` regardless — which is correct, because a human with no route genuinely is trapped.

**Cost: about ten lines, no navmesh work, and no exit-reachability query.**

**It also looks better than perfect pathing.** A panicked civilian sprinting the wrong way, hitting the wire, turning and running elsewhere is exactly right. Flawless avoidance would have them calmly never making the mistake.

**Accepted imperfection:** a human whose exit lies past a long fence writes that exit off entirely rather than walking around the end of the fence to the same exit. Suboptimal routing, invisible in most layouts, not worth machinery.

### A9.3 A folded fence stays impassable to humans (provisional — ruling 2)

Humans keep the write-off after a fold; zombies of course walk straight through (their meshes never had it carved and the barriers are gone).

**Why this is nearly free in play:** a freshly folded fence has your horde standing in the gap, and `exit_block_radius` (120px) already strikes off any exit with a living zombie in it — so even a correct implementation would refuse that route for the first several seconds anyway.

**Tells that it needs upgrading:** humans visibly declining an obvious open gap long after the horde has moved on; or a compound whose occupants huddle and cower when a folded fence was their only way out.

**The upgrade if it happens:** clear the fence from each human's write-off set on the `folded` signal — which is why §A5 emits it. That is a handful of lines and needs no navmesh change at all. *(This is strictly better than the runtime re-bake considered earlier and supersedes it.)*

**Level-design law while it stands:** always leave humans a fence-free route to at least one exit. A fenced-in pocket with no way out is a legitimate authored trap — it should just be authored, not accidental.

### A9.4 Determinism (§10 holds in full)

- `press_count` from `GameManager.neighbours_within(...)` — registry, `unit_uid`-ordered — then the exact strip test. Never a per-frame group scan (guideline 8).
- The fold meter is a fixed-timestep accumulator in `_physics_process`. No wall-clock.
- Every tiebreak resolves by lowest `unit_uid`. No RNG; no DetHash needed, because nothing about a fence is per-unit.
- Add a fence-fold scenario to the **boot-twice-and-diff** spot-check.

## A10. INTERACTIONS WORTH STATING

1. **Flee exit set** — a fence is not an exit and never joins the set. What ruling 1 changes is that a fence can *cut off* exits, which §A9.2 handles reactively.
2. **The fill front** sees through, fires through, and is never blocked by a fence. Defenders behind a fence are the fence's teeth, and the bodies they drop rise inside the strip (§A4.1).
3. **Fear** passes through — a crowd massing on the wire terrifies the compound. Intended: the mass gate announces itself.
4. **Herding into a fence is a real play.** `flee_repel` bends runners away from your zombies with no knowledge of terrain, so a fence at their back is a hard stop: shove them against it and the cower detector does the rest.
5. **The compound trap.** Fold a perimeter and the occupants have nowhere to go — every exit is on the wrong side of your horde. Fenced compounds are terror-harvest arenas, not just obstacles.
6. **Contagion is not LOS-gated** (existing rule), so violence on one side ignites the reserve on the other. Note it when placing staging ground.
7. **No pouncing over a fence.** The lunge triggers at 40px and flies straight; a target beyond an intact fence is beyond the barrier, so the lunge lands on the wire. *(Contrast §B6.4 — leaping a hazard band is possible and is a feature.)*

## A11. THE LEVEL-DESIGN LAW: CAPACITY vs THRESHOLD

**A threshold the span physically cannot hold is an unopenable fence and a designer error.** With ~24px of effective body width along the span and ~30px of BOID separation between ranks:

```
max_pressers ≈ floor(fence_length / 24) × floor(fence_press_depth / 30) × 2 sides
```

A 200px span at 60px depth holds roughly `8 × 2 × 2 = 32`, so a threshold of 20 is demanding but achievable and 40 is a wall.

**Ship a `@tool` `push_warning()` when `threshold > 0.75 × max_pressers`**, printing both numbers. Five lines; prevents the likeliest authoring mistake.

Corollary: **make a fence harder with a bigger threshold OR a shorter span.** A short fence is hard because only so many bodies fit — and that reads visually, which beats a big number.

## A12. NUMBERS v0

All in `GameConfig` with `LevelConfig` `@export` mirrors carrying `##` doc-comments (the inspector-tooltip convention).

| Knob | v0 | Notes |
|---|---|---|
| `fence_press_depth` | **60 px** | each side. ~2 ranks at 30px BOID separation — a 25px door-style arc would cap the count at one rank and make thresholds depend on span alone |
| `fence_fold_time` | **2.0 s** | at/above threshold, from an empty meter |
| `fence_relax_factor` | **1.0** | drain rate below threshold, × the fill rate |
| `fence_press_threshold` | **8** | global default; real tuning is per-fence via `threshold_override` |
| `fence_sag_max` | **14 px** | presentation only |
| `fence_shock_interval` | **1.5 s** | slice 3 only (§B9) |

Per-fence: `fence_length` 200, `fence_thickness` 8, `threshold_override` 0.

**Sweep jobs:** does the threshold read as a *stock check* — does a player consciously bank bodies for it? Does 2.0s feel like weight or a formality? Is drain-vs-reset the right forgiveness? Do humans behave sensibly around fences, folded and intact (§A9.3)?

## A13. PARKED (Part A — do not build)

- **The one-way membrane** (`blocks_humans = false`): the zombie-only fence — humans vault, zombies pile. Ruled against as the default, but it's the *cheap* variant (it removes the human barrier and §A9.2 entirely), so it stays a per-fence flag if a level ever wants prey-favouring terrain.
- **Graded overpressure** (`fence_overpressure_factor`, default 1.0 = off) — only if the hard threshold plays badly.
- **Opaque fences** (`blocks_los`) — corrugated hoarding. One line, but it changes the tactical meaning entirely; ship transparent first.
- **Rubble on fold** (`folds_to_rubble` → leaves a SLOW zone where it fell) — cheap once Part B exists; a garnish.
- **Repairable fences** — no. See §A5.

---

# PART B — HOSTILE TERRAIN

## B1. THE FEATURE IN ONE PARAGRAPH

**Hazards** are placeable terrain that charges the horde for crossing: minefields, stake beds, barbed wire. No AI, no state, no new player verb. The core is the asymmetry — **the calm reserve routes around what would kill it; the frenzy runs straight through** — which turns every hazard into a live question about *how* you attack rather than *whether* you can. Walk the crew around under full control and lose tempo, or release through and pay in bodies for the speed. It gives release a permanent, legible, deterministic cost exactly where a designer chooses to put one.

## B2. PILLAR AUDIT

- **Attrition is currency** ✅ — the purest expression of it; a hazard's whole existence is a price list.
- **Command the calm / released is released** ✅ and *sharpened*: the reserve is safe because it's controlled, the storm is expensive because it isn't.
- **Predictability** ✅ **conditionally** — hazards must be **fully visible to the player**, minefields included (§B5). Hidden-from-the-*player* hazards convert planning into guessing and are a straight pillar violation. The zombies not knowing is fiction; the player not knowing is a bug.
- **Determinism** ✅ — fixed cadence, registry order, no RNG (§B8).
- **Agency** ⚠️ **one risk, mitigated.** A contagion ignition beside a minefield could send the reserve into it with no player input. Two mitigations: **hazard deaths cause no contagion** (ruling 9), so a hazard can never start a chain reaction; and ferals only run at *prey*, so a hazard only bites when a human is on the far side — the trigger is always visible. Residual risk is level-design hygiene (§B11).
- **Meaningful decision or friction?** ✅ Route choice, release timing, and calm-vs-feral commitment are all real. Watch for a hazard with no alternative route — that's pure friction and a level-design error, not a mechanic error.

## B3. TWO MESHES

> **You route around what kills you. You wade through what merely slows you.**

| Mesh | `navigation_layers` | Used by | Carves |
|---|---|---|---|
| **Reckless** | 1 | **all humans**, **FERAL zombies** | walls, buildings, level bounds — **exactly today's mesh, unchanged** |
| **Careful** | 2 | **CALM zombies** | the above **+ zombie-lethal visible hazards** (stakes) |

Fences are in neither (§A9.1). Wire is in neither — it slows, so everyone wades. Mines are in neither — nobody can see a buried mine.

**Why humans share the feral mesh:** nothing in the shipped kit kills humans by default, so there is nothing for a human mesh to carve. Keep `NavBaker` generic (N layer-filtered regions) so a future human-lethal hazard can split them, but **ship two**.

### B3.1 Building it

`nav_baker.gd` currently bakes one `NavigationRegion2D` (itself). Change:

1. Collect the geometry **once**, as today.
2. Bake the existing region as **reckless**, `navigation_layers = 1`, consuming only footprints whose owner reports carve-layer bit 1.
3. Create an internal child `NavigationRegion2D` named `_CarefulRegion` (`Node.INTERNAL_MODE_FRONT`, the `wall.gd` internal-child pattern), `navigation_layers = 2`, baked from the same source **plus** footprints reporting bit 2.
4. Both bakes complete in the same `rebake()` call, at boot, before the first physics tick.

**Carve-layer protocol — additive, no existing script changes:**

```gdscript
# NavBaker asks each footprint owner, defaulting to "both meshes" when unimplemented.
var layers := 3
if node.has_method("nav_carve_layers"):
    layers = node.nav_carve_layers()
```
`wall.gd`, `building.gd`, `shelter_building.gd` don't implement it → 3 (both), unchanged. `HazardZone` implements it: **IMPALE → 2** (careful only), **SLOW → 0** (neither). `Mine` and `Fence` define no `get_nav_footprint()` at all.

**Agent side:**
- `zombie.tscn`'s `NavigationAgent2D` — set `navigation_layers = 2` in `Zombie._ready()` (calm is the birth state), `= 1` in `ignite_feral()`, `= 2` in `_set_calm()`. Two lines plus the ready line.
- Human agents (created in `flee_behavior.gd`) — leave at 1.
- Risers rise CALM, so they inherit careful pathing automatically. Nice property: fresh bodies don't immediately re-walk the minefield that made them.

### B3.2 Flagged risk — prototype before building

Overlapping `NavigationRegion2D`s on different navigation layers is the Godot-native way to express "different agent types avoid different things", but overlapping regions can interact oddly at edge-connection time.

**Prototype in a throwaway scene first:** one stake zone, one calm zombie, one feral, one human; confirm the calm path detours and the other two cut straight through, and that no agent's path snaps to the wrong region.

**Fallbacks, in order of preference:** (1) separate `NavigationMap` RIDs instead of layer-filtered regions — heavier but fully isolated; (2) for hazards only, deliver calm avoidance as a steering repulsion term reusing the `flee_repel` maths — cheap, but it cannot route around a large field (local minimum), so it is a genuine downgrade.

**Known edge:** a zombie that goes feral, enters a stake bed from the safe side, then calms is standing off-mesh on the careful mesh. Agents snap to the nearest mesh point, so it walks out; log it once if it looks wrong in play. Rare by construction — most zombies that enter stakes die there.

### B3.3 Upgrade path (do not build now)

Godot's `NavigationRegion2D.enter_cost` / `travel_cost` would give **graded** avoidance — short detours taken, long ones not — instead of a binary carve. It needs one region per hazard, which multiplies the §B3.2 risk. Binary first; revisit only if binary avoidance produces visibly silly detours.

## B4. THE KIT AT A GLANCE

| Object | Zombies | Humans | Routed around by | Slice |
|---|---|---|---|---|
| **Mine** | Kills 1, any direction, then spent | Untouched by default (`affects_humans` opt-in) | nobody | 2 |
| **Stakes** (`HazardZone`, IMPALE) | **Kills — one direction only** | **Slows, never kills** | calm zombies | 2 |
| **Barbed wire** (`HazardZone`, SLOW) | Slows | **Slows** | nobody | 2 |
| **Electrified fence** (`Fence.electrified`) | Kills on touch while powered | Wall — it's a fence | humans (write-off) | 3, post-PoC |
| *Bear trap / rubble* | *presets of the above* | | | free |

## B5. MINES — `scripts/mine.gd`

**`class_name Mine`, `@tool`, `extends Node2D`.** Name verified free.

A **point** hazard, hand-placed. One mine kills exactly one zombie, then it is spent — permanently.

| Export | Type | Default | Notes |
|---|---|---|---|
| `trigger_radius` | float | 14.0 | ≈ one body |
| `affects_humans` | bool | **false** | on = prey sets them off too (§B5.2) |
| `armed` | bool | true | the future power/objective hook |
| `mine_color` | Color | dark red | programmer art |

**Rules:**
1. On the field cadence, if `armed and not _spent`, the field collects living units within `trigger_radius` (zombies always; humans only if `affects_humans`).
2. If any, the **lowest `unit_uid`** among them dies. Exactly one — 1:1 (ruling 4).
3. The mine sets `_spent = true`. **The node is not freed** — it persists as an inert crater graphic, which is what makes the paid road permanently visible.
4. A spent mine never triggers again and is skipped by the field.
5. Mines define **no `get_nav_footprint()`** — nobody routes around them, which is the point.
6. Group `"hazards"` at `_ready()` for the field's one-time registration.

**The corpse road (ruling 5):** because each mine self-consumes, the cleared lane exists with no sub-geometry bookkeeping. **Honest caveat:** zombie corpses despawn after their linger, so the road is marked by **craters, not bodies**. Permanent and legible, which is what matters.

**Spacing is the design language.** A dense line is a wall priced in bodies; a loose scatter is a tax; a deliberate gap is a lane for the player to find. Tune by eye per field.

### B5.1 Who walks into them

**Ferals and calm zombies both.** Hidden means carved from no mesh, so nothing routes around a minefield. **The player is the only one who knows**, which is exactly why the field must read clearly (§B7) — routing around mines is a *player* decision, not an AI one.

### B5.2 `affects_humans` (default off — recommended)

Turning it on: prey that blunders in dies **unscored and does not rise**, and **consumes the mine** — so the humans clear your path for you. A fun thing for a level to do deliberately; not something that should happen by default.

## B6. AREA HAZARDS — `scripts/hazard_zone.gd`

**`class_name HazardZone`, `@tool`, `extends Polygon2D`.** Name verified free. Mouse-drawn footprint following the `wall.gd` pattern exactly: a default box when `polygon.is_empty()`, `_sync()` on setters, `_process` re-sync while `Engine.is_editor_hint()`.

| Export | Type | Default | Applies to |
|---|---|---|---|
| `toll_mode` | enum `{SLOW, IMPALE}` | SLOW | — |
| `zombie_speed_factor` | float 0.05–1.0 | 0.4 | SLOW |
| `human_speed_factor` | float 0.05–1.0 | 0.4 (SLOW) / 0.35 (IMPALE weave) | both |
| `impale_min_speed` | float | 20.0 | IMPALE |
| `armed` | bool | true | both |
| `hazard_color` | Color | — | both |

A factor of **1.0 means unaffected**, so "wire that doesn't slow humans" is `human_speed_factor = 1.0` — one field replaces a boolean.

Group `"hazards"` at `_ready()`.

### B6.1 SLOW — barbed wire

Slows everything inside by its per-team factor. Kills nothing. `nav_carve_layers()` → **0**: in nobody's mesh, so everyone wades.

**It still shifts the sacred ratio hard**, because the ratio that matters is *crossing time against the defender's fill clock*, not zombie speed against human speed. The shooter isn't in the wire; the hunter and the hunted both are. A wire band in front of a gun position buys that gun several free shots at a horde that's wading — which is what you'd install it for.

Ruling 8 (wire slows humans too) makes wire a **shared mire** rather than a prey shield, which is the real distinction from stakes.

### B6.2 IMPALE — stakes, and the directional rule

- **Zombies die** — but only when moving **into** the points.
- **Humans never die.** They are slowed to `human_speed_factor` (they weave through).
- `nav_carve_layers()` → **2**: calm zombies route around it; ferals and humans don't.

**Directionality (ruling 6) is a velocity check, not entry-side tracking** — stateless and deterministic:

```
facing = the global direction the points aim  (node's local -Y, rotate the node to aim them)
inside the polygon
  AND velocity.length() > impale_min_speed
  AND velocity.normalized().dot(facing) < 0        # moving against the points
  → dies
```

**The `@tool` draw must include a facing arrow**, or the zone is unauthorable.

Two properties that fall out and belong on the record:

- **It gives the ledge drop's best property for free.** Lethal inbound, harmless outbound is a **one-way valve for the frenzy** — commitment geometry — with no visual language for "down" required.
- **A stationary zombie in a stake bed is safe** (no velocity into the points). No exploit exists today: zombies have exactly one speed and shamblers are leashed at 5px. If a slow special ever ships it survives stakes automatically — a counter-key falling out of the mechanic rather than being authored.

### B6.3 The slow is the readability (ruling 7)

**No art is required to explain stakes.** A human visibly decelerating and picking their way through the bed while ferals die at its edge communicates the entire rule in one moment of play — legible at horde scale, and it teaches on first encounter.

**Assumption (§1.1):** the calm crew can't be walked into a lethal hazard. The careful mesh routes them around, and an order *into* a stake bed paths them to the edge and stops (the agent's nearest-reachable-point arrival, which `nav_move_toward` already handles). If that reads as "my order was ignored", the fix is a refusal tell, not a rule change.

### B6.4 Pouncing over a hazard is legal and is a feature

The lunge is straight-line and lands on the prey, so a feral reaching pounce range at the edge of a wire band or stake bed leaps it clean. **`terrain_speed_factor` must NOT be applied to pounce flight** (§B7.3) — a lunge is ballistic. Zombie-movie-correct and emergent; do not "fix" it.

## B7. THE SYSTEM — `scripts/hazard_field.gd`

**`class_name HazardField`, `extends Node`.** Name verified free. A **child of `GameManager`**, alongside `ViolencePipeline`, `HuntPool`, `MarkSystem`, reached by one-line delegates like its siblings.

**Why a system and not per-node ticking (which is what `Door` does): overlapping zones.** Two hazards touching one unit need a single deterministic resolution — slowest factor wins, kills in one order — and per-node ticking would make that depend on scene order. `HazardZone` and `Mine` are **dumb geometry and data** (the `ShelterSpot` posture): they draw themselves, answer `contains(point)` / `triggers_on(unit)` and `nav_carve_layers()`, and never tick.

**Registration:** at `_ready()`, collect group `"hazards"` once and assign each a monotonic `hazard_uid` in tree order. All later iteration is in `hazard_uid` order. No per-frame group scans.

**`tick(delta)`, called from `GameManager._physics_process`,** accumulates to `GameConfig.hazard_scan_interval` (0.1s) and then, in one pass:

1. **Gather.** For each armed, unspent hazard in `hazard_uid` order: registry query on its bounding radius (both teams), then the exact containment test.
2. **Kills, applied in `unit_uid` order.** Mines first (one victim each, lowest `unit_uid` in radius), then IMPALE zones (every qualifying zombie).
   - Zombies → `GameManager.report_hazard_kill(zombie, hazard)` (§B7.1).
   - Humans → `human.take_damage(1.0)`; the existing `human_died` → `_on_human_died` → `check_win_condition()` path covers the rest. **Verify that signal is wired for hand-placed humans, not only spawned ones.**
3. **Speed factors.** For each unit inside any SLOW-or-IMPALE zone, `terrain_speed_factor = min(factors)`. The field keeps the set it modified last tick and **restores 1.0** to units that have left. Never write the factor from the zone nodes themselves — one writer only.

### B7.1 A second way for a zombie to die — CHANGES AN EXISTING RULE

`ViolencePipeline.report_gunfire_kill` carries a load-bearing comment: *"gunfire is the only way a zombie dies in v2, so this is frame-exact and teardown-immune"* — the A4/A5 lose-verdict fix depends on it. Hazards break that invariant, **and the fix lands in the same commit**:

```gdscript
## The SECOND zombie-death source (hazard terrain). Mirrors report_gunfire_kill's
## contract: the lose verdict is judged HERE, at the death instant. NO contagion —
## terrain has no agency to charge at, and igniting the reserve beside a minefield
## would take control away from the player (Ben's ruling 2026-08-01).
func report_hazard_kill(zombie: Zombie, hazard: Node) -> void:
    if not is_instance_valid(zombie) or not zombie.is_alive:
        return
    zombie.take_damage(1.0)
    _gm.check_lose_condition()
```
Plus a one-line `GameManager` delegate, and **update the comment on `report_gunfire_kill` to say "one of the two zombie-death sources"** so the next reader isn't misled.

### B7.2 Scoring, contagion, risers

- **Zombie hazard deaths:** unscored, **no contagion** (ruling 9), lose-check at the instant. They cost you a body and nothing else.
- **Human hazard deaths:** they do **not** route through `register_pounce_kill`, so they are **unscored** and produce **no riser** — kill-context riser denial for free. State it plainly for the designer: *herding prey across your own minefield throws the body away.*
- The combo is untouched: it counts pounce kills only and is time-windowed.

### B7.3 The one seam in `unit.gd`

```gdscript
## Terrain speed multiplier (hazard SLOW / stake weave). 1.0 = unaffected.
## Written ONLY by HazardField; never by hazard nodes. Not applied to pounce
## flight — a lunge is ballistic (spec §B6.4).
var terrain_speed_factor: float = 1.0
```
Applied inside `step_toward`, `nav_move_toward` and `move_to_target` (the latter multiplies `move_speed`). **Also check `flee_behavior.gd`** — if it drives movement without going through those three, apply it at that site too.

No call site changes anywhere. Default 1.0 means every existing level is byte-identical.

## B8. DETERMINISM (§10 holds in full)

- Field cadence 0.1s — 14px of travel per tick at `zombie_speed` 140: precise enough for a mine, cheap enough to ignore.
- Containment: registry radius query on the bounding circle → exact `Geometry2D.is_point_in_polygon` (zones) or radius (mines). Registry order = `unit_uid` order.
- Hazards iterate in `hazard_uid` order; units within a hazard in `unit_uid` order. A given field always eats the same zombies in the same order.
- No wall-clock, no RNG, no DetHash needed (nothing here is per-unit-staggered).
- Add a hazard-crossing scenario to the boot-twice-and-diff spot-check.

## B9. ELECTRIFIED FENCE + GENERATOR (slice 3 — post-PoC, specced so nothing forecloses it)

**One object, one knob.** `Fence.electrified = true` kills pressers while powered:
- `fence_shock_interval > 0` → one presser dies per interval (**exactly one**, lowest `unit_uid` in the strip). The fence is foldable if you can hold the threshold while it eats.
- `fence_shock_interval == 0` → **touch-death**: any zombie entering the strip dies. The fence cannot be fed down at all; the generator is the only key.

Kills route through `report_hazard_kill` (§B7.1) — same silence, same lose-check.

**The generator is mechanically a door.** A poundable box with integrity, breakable by the calm crew (`CalmBreach`) or by ferals, that flips `armed = false` on whatever it powers when destroyed. Every piece of that machinery already exists. It keeps the body price honest: you don't pay at the fence, you pay at whatever guards the generator.

**Why it's post-PoC, both reasons:** it depends on the generator, *and* a live touch-kill fence is a trap for the **player** — calm zombies ordered past it walk into it and die one at a time, and unlike a hazard they can't route around it, because a fence is deliberately left open in the zombie meshes so they can press it. Fixable with a loud enough powered tell (arcing, plus a visible link line to its generator), but "how loud does the tell need to be" is not a question to answer during a validation playtest.

## B10. RECORDED FOR THE FUTURE — LEDGE DROPS (do not build)

A one-way ledge or embankment anything can descend and nothing can climb. Mechanically a fence with the barrier on one side only — nearly free once fences exist.

**Design value:** it makes *released is released* geographic. Send the horde down into the sunken yard and they're in there until they come out the far end; it traps humans identically. That's commitment geometry, a decision type nothing else in the game produces.

**Why it's not in the PoC (Ben, 2026-08-01):** with no art, there is no visual language for "down" — a one-way barrier would read as a bug rather than a ledge. Revisit with the art pass.

Note that **directional stakes (§B6.2) already deliver the one-way-valve property for the frenzy**, which is most of what made drops attractive.

## B11. LEVEL-DESIGN GUIDANCE (doc, not engine)

- **Always leave an alternative route.** A hazard with no way around it is a toll booth, not a decision.
- **Walls on boundaries, hazards on the lines the chase wants to cut** (§0). If a wall would do the same job, use a wall.
- **Keep hazards outside `contagion_radius` (150px) of natural staging ground** (§B2's residual risk).
- **Mine spacing is authored, not tuned by config** — dense line, loose scatter, deliberate lane.
- **Hazards pair with counter-specials** at the post-PoC specials re-audit: the Fat Zombie's corpse bridges wire and mines (the body-on-the-wire trope), the Headless's straight-line charge is a natural minesweeper. Nothing to build now; recorded so the re-audit inherits it.

## B12. NUMBERS v0

| Knob | v0 | Home |
|---|---|---|
| `hazard_scan_interval` | **0.1 s** | GameConfig |
| `trigger_radius` (mine) | **14 px** | per-mine |
| `zombie_speed_factor` (SLOW) | **0.4** | per-zone |
| `human_speed_factor` (SLOW / IMPALE weave) | **0.4 / 0.35** | per-zone |
| `impale_min_speed` | **20 px/s** | per-zone |
| `fence_shock_interval` | **1.5 s** (0 = touch-death) | GameConfig, slice 3 |

**Sweep jobs:** does a stake bed read as "go around" without being told? Is a mine field's remaining density legible mid-crossing? Does wire change how a defender position *feels*, or only how long it takes to reach?

## B13. PARKED (Part B — do not build)

- **The generator / power grid** — `armed` is the hook, unread until slice 3.
- **Dynamic hazards** (petrol you ignite, a fuel tank a defender's gunfire sets off, collapsing terrain) — needs a trigger system. The tank is the interesting one: you bait the garrison into destroying its own position. Nothing here forecloses it beyond `armed`.
- **Graded nav avoidance** via `travel_cost` (§B3.3).
- **Hazards that damage buildings or doors** — no. Terrain hurts units.
- **Per-unit hazard resistances** — that's the counter-specials answer; it belongs to the specials re-audit.
- **CUT, not parked: fire zones** (ruling 10). Do not re-pitch.

---

# PART C — BUILD ORDER, TESTS, COMPATIBILITY

## C1. Slices

One feature at a time (rule 3). The order front-loads the risky shared foundation and keeps every slice independently testable and revertible.

| Slice | Contents | Files touched | Suggested bump |
|---|---|---|---|
| **1a — mesh layering** | `NavBaker` bakes two layer-filtered regions from one geometry scan; agents choose a mesh; the `nav_carve_layers()` protocol. **With no hazards in a level both meshes are identical, so this slice is a provable no-op** — which is exactly what makes it a safe first step | `nav_baker.gd`; 3 lines in `zombie.gd` | v0.47.1 (PATCH) |
| **1b — fences** | `fence.gd`; the press rule + fold; the indicator; the `FeralBrain` PRESSING flag; the `SelectionManager` fence case; the human bump-and-write-off | new `fence.gd`; `feral_brain.gd`, `selection_manager.gd`, `flee_behavior.gd`, `game_config.gd`, `level_config.gd` | v0.48.0 (MINOR) |
| **2 — hazards** | `mine.gd`, `hazard_zone.gd`, `hazard_field.gd`; `report_hazard_kill`; `Unit.terrain_speed_factor` | 3 new scripts; `game_manager.gd`, `violence_pipeline.gd`, `unit.gd`, `nav_baker.gd` (careful-mesh carving goes live), `flee_behavior.gd`, config | v0.49.0 (MINOR) |
| **3 — electrified fence + generator** | §B9 | `fence.gd` + a new generator node | post-PoC |

**Sequencing notes for the implementer:**

- **Prototype §B3.2 before writing any of slice 1a.** If overlapping layer-filtered regions misbehave, the whole shape changes, and that is far cheaper to learn on a throwaway scene than inside slice 1b.
- **Run the sacred-ratio sweep on a terrain-free control level first.** Fence thresholds and hazard tolls are priced *in bodies*, and bodies-per-crossing is exactly what the sweep establishes. Tune the ratio bare, then tune terrain on top of a known baseline, or the two calibrations chase each other.
- **The calm-mass-break re-judge (work-queue Tier 6) gets more interesting after 1b, not less.** Fences are the first mechanical *reward* for hoarding a big calm horde, rather than a scoring punishment for it. Re-ask that question after fences exist.
- **New `class_name` scripts created outside the editor** need `<godot> --headless --import --path .` before the parse gate, or `tools/check.ps1` fails on a *consumer* script with a misleading error.
- **Parse gate after every `.gd` edit:** `powershell -ExecutionPolicy Bypass -File tools/check.ps1`.

## C2. Acceptance tests (manual, per project convention)

**Slice 1a — mesh layering**
1. **Provable no-op:** a level with no hazards plays byte-identically; boot-twice-and-diff a known scenario against a pre-slice log.
2. **Two paths:** in a throwaway scene with one stake zone, a calm zombie detours and a feral cuts straight through.

**Slice 1b — fences**
3. **Under threshold:** park `threshold − 1` calm zombies in the strip for 30s → the meter never leaves zero, the counter reads red, nothing folds.
4. **At threshold:** add one more → the counter flips colour, the bar fills, the span sags, it folds at `fence_fold_time`, and the crew walks through **still selected and under control**.
5. **Drain:** reach ~70%, walk two zombies out → the bar visibly drains; walk them back → it refills from where it drained to, not from zero.
6. **Feral press:** release a crew at a human beyond the fence → they wedge, **do not calm out after 2s** (§A6.2), hold their targets, and resume the chase the instant it folds.
7. **Peel wins:** with ferals pressed, walk a live human within `chain_scan_radius` on *their* side → they abandon the fence immediately.
8. **Human bump:** a fleeing human whose nearest exit is beyond a fence runs at it, bumps, **re-routes to another exit, and does not cower there**.
9. **Folded fence stays shut to humans** (provisional, ruling 2): after a fold, humans still decline the gap. Log it if it looks stupid — that's the §A9.3 tell.
10. **Defenders shoot through:** a militia behind an intact fence kills pressers; the corpses **rise in the strip and rejoin the press**.
11. **Explicit order:** RMB the fence itself → the crew spreads *along* the span, not into a knot.
12. **Herd into a fence:** shove a runner against a fence with a wall of calm bodies → it corners and cowers (§A10.4).
13. **Determinism + compat:** boot-twice-and-diff a scripted fold; a level with no `Fence` plays byte-identically.

**Slice 2 — hazards**
14. **The asymmetry:** order a calm crew beyond a stake bed → it routes around. Release at a human beyond the same bed → the ferals run in and die.
15. **Directionality:** a feral crossing the stakes *with* the points survives; the same feral crossing *into* them dies (§B6.2).
16. **Humans weave:** a fleeing human crosses the stake bed **slowed and alive**, with the deceleration clearly visible.
17. **1:1 mines:** a five-mine field kills exactly five zombies; each spent mine leaves a permanent crater; a sixth crossing is free.
18. **Wire:** both a zombie and a human visibly wade; a defender covering the band kills more than it would in the open.
19. **Lose verdict:** march the last surviving zombies into a minefield → defeat registers **at the death instant**, not on teardown.
20. **No chain reaction:** park the reserve inside `contagion_radius` of a minefield and set one off → **nothing ignites**.
21. **Riser denial:** with `affects_humans = true`, herd a civilian into a mine → it dies unscored, **does not rise**, and **consumes the mine**.
22. **Pounce-over:** a feral reaching pounce range at a wire edge leaps the band and lands clean.
23. **Determinism + compat:** boot-twice-and-diff a crossing; a level with no hazard nodes plays byte-identically.

## C3. Backwards compatibility

Purely additive. No existing level contains a `Fence`, `Mine` or `HazardZone`; `Unit.terrain_speed_factor` defaults to 1.0; with no hazards present both meshes are identical to today's single mesh; `report_hazard_kill` is unreachable without a hazard; `nav_carve_layers()` defaults to "both meshes" for every existing obstacle script, so none of them change. Tests 1, 13 and 23 exist to prove it at each step.

---

**END OF SPEC v1.0** — slice 1a is the next thing to propose for build, preceded by the §B3.2 throwaway-scene prototype.
