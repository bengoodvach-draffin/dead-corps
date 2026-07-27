# DEAD CORPS — ENTERABLE BUILDINGS SPEC (Shelters, Sieges & Breaches)

**Version:** 1.1 (design session 2026-07-23; as-built sync 2026-07-27)
**Status:** **SLICE 1 BUILT AND PLAY-VERIFIED (v0.44.0)** — pulled forward ahead of Phase 5/6 by Ben's 2026-07-23 timing ruling (overrides the original "build after the M1 verdict" gate below). The **terrain kit** (§16) and the **Mark siege-pull** (v0.45.0) landed on top. Slice 2 (§7.4 armory + barricade) stays parked until slice 1 has been played at level scale. **§16 records every as-built amendment** — where it contradicts the 2026-07-23 text, §16 wins.
**Relationship to V2_DIRECTION_SPEC.md:** extends it; changes no existing rule except the two explicitly amended in §5.4 and §6.3 (failsafe and cower pause-rules). Un-parks three Parked Register entries by name: *building transformation system*, *hardening/hardpoints*, *militia-arming-civilians*. Adds one new parked entry (§13).

---

## 1. THE FEATURE IN ONE PARAGRAPH

Buildings humans can flee **into** rather than off the map: polygon structures with interior rooms and doors. Humans shelter inside; pursuing ferals pile onto the doors and pound them down (more ferals = faster); the player can commit more zombies to a siege by releasing them at the door. Once a door breaks, the building becomes a normal play area — ferals pour in and the hunt continues room by room. Humans inside are **fully scored** prey. Buildings are not a punishment mechanic; they are **tactical variety and combo arenas** — concentrated prey behind a body-and-time paywall, defended (when garrisoned) by armed humans who make a last stand at the door.

**Design rationale (recorded):** the original concept was a cost-sink for sloppy play (interior kills unscored). Ruled otherwise on 2026-07-23: interiors are alternative play areas with full scoring. The remaining costs of letting humans shelter are time, siege attrition against garrisons, and (slice 2) the building hardening while you wait. Herding humans *into* a building to stock a combo arena is a **sanctioned strategy**, not an exploit.

---

## 2. PILLAR ALIGNMENT

- **Attrition is currency / every wall has a body price** — the siege is a priced crossing: garrisoned doors charge bodies (§7), and breaching spends ferality (§5).
- **Command the calm, influence the storm** — only ferals damage doors; committing to a siege is a release (uncancelable); the calm reserve can blockade and herd but never demolish.
- **The frenzy chases what moves** — a besieging feral abandons the door instantly for live prey in scan range (§5.2). The door is the lowest-priority prey.
- **Determinism in rules** — no RNG anywhere in this feature; every cadence is fixed-interval with DetHash stagger, every claim/order is unit_uid-ordered (§11).
- **Predictability over simulation** — interiors are always visible to the player (§10); no hidden state, no information ambushes.

---

## 3. THE BUILDING

- **Structure:** a NEW composite scene/class `ShelterBuilding` (`shelter_building.gd` — name verified free) — a container node composed of:
  - **Perimeter + interior walls:** `Wall` polygon segments (existing `wall.gd` — mouse-editable, already provides LOS blocking + nav footprints). Interior walls partition rooms.
  - **One or more `Door` nodes** (`door.gd`, new — §4) placed on perimeter wall gaps.
  - **`ShelterSpot` marker nodes** (`shelter_spot.gd`, new — §6.2), including guard-flagged variants.
  - Interior doorways between rooms are plain wall gaps — **no interior door mechanics in v1** (ruled: one door mechanic per building, at the perimeter only).
- The existing solid `Building` (`building.gd`) is **untouched** — it remains the simple LOS-blocking obstacle. Its reserved `is_enterable` flag stays unused; note in code comment that `ShelterBuilding` superseded it. Backwards compatibility: levels containing no `ShelterBuilding` behave byte-identically.
- **Windows are fiction, not mechanics.** All windows are boarded (they stayed quiet and nailed them shut). Mechanically they are wall — no fire, no LOS, no entry. All shooting and all movement routes through doorways. (Art pass may render boarded windows later; zero mechanical hooks.)
- **Rooms are the point.** Interior walls create room-by-room fear propagation (§8.2) and chokepoint doorway fights. Interior wall layout is a level-design pacing instrument: long sight-lines panic deep rooms early; closed rooms stay oblivious until a feral rounds the corner.

---

## 4. DOORS: TWO INDEPENDENT STATES

A door is not one gate with one state. It has two independent facts about it:

### 4.1 State 1 — the zombie barrier (always on until breached)

**An intact door NEVER admits a zombie. Period.** The only zombie route into a building is breach. Implemented with the proven escape-barrier pattern (`escape_zone.gd`): a layer-4 "EscapeBarrier" StaticBody2D across the doorway — zombies (mask 9) physically slide off it; humans pass through. No open/closed timing races exist, which is what makes §11 determinism trivial here.

- **The Trojan zombie is ruled OUT** (a feral slipping inside before the door shuts). Every version of it requires resolving "the door closed the frame the feral crossed" — exactly the race class §10 of the direction spec forbids. The concept survives elsewhere: the **Costume Zombie walking in through the front door** is the sanctioned infiltrator — parked to the post-PoC specials re-audit (§13).
- The slam-behind moment needs no rule: a pursued human dives through, the feral thuds off the barrier a half-second later and begins pounding. Physics provides the drama.

### 4.2 State 2 — the lock (governs humans only)

- **Rule: a door admits humans only while NO feral is inside its engagement arc.** The lock is a **continuous predicate, not a latch**: the instant the arc is clear of ferals, the door admits humans again. Nothing is remembered.
- **The engagement arc IS the lock zone** (unified — one zone, one knob): a shallow zone in front of the door segment, depth `door_engagement_depth` (v0: **25px** — "effectively on the doorstep", ruled; deliberately below pounce range). Measured from the door segment, not the building centre. The rule compresses to one sentence: **an engaged door admits no one.**
- **Feral-only trigger** (ruled). Calm zombies never lock a door. Rationale: if any zombie locked doors, optimal play is parking one calm zombie per door in setup and the feature never fires. Calm presence still *soft*-denies a door via existing flee-vector herding (repel radius 180px) — a bias fleers can fight through, not a wall. Graded denial: calm discourages, feral locks. Fiction: nobody unbars a door with frenzied ones on the doorstep; a docile shambler doesn't trigger the panic-bar.
- **Consequence at 25px:** the slam-behind is the dominant moment (a human with a feral even 50px behind still gets in); the lock's real job is that **a besieged door admits nobody** — latecomers bounce and re-flee (§9). Doorstep lockout deaths are rare, correctly: at 110px/s closing speed, genuinely slow humans die in the open first.
- **Optional tuning knob:** `door_unlock_hysteresis` (v0: 0s) — delay before re-admitting after the arc clears, if boundary-hovering ferals make the lock flicker in play. Expected unnecessary at 25px depth.
- Human-side implementation: a second doorway barrier on a human-blocking layer, active only while the lock predicate holds.

### 4.3 Breach mechanics: pounds, not drain

- Each feral in the engagement arc **pounds on a fixed cadence**: one pound per `pound_interval` (v0: **1.0s**), **staggered per-unit by DetHash** (so a crowd doesn't strike in robotic unison — same jitter source as everything else, no RNG). Each pound deals flat `pound_damage` (v0: **10**) to `door_integrity` (per-door, v0 default: **600** ≈ 60 solo pounds ≈ 10s under a 6-feral siege; reinforced doors per level design, e.g. armory 1500). All rough — sweep-tuned.
- More ferals = faster breach, **capped physically** by how many bodies fit the arc (BOID separation + door width do the capping; no numeric cap). **`door_width` is a first-class tuning knob per door** — it sets siege throughput, post-breach entry serialization, flush drain rate, and doorway ambushability. A wide warehouse door and a farmhouse's single door are different tactical objects.
- **Only ferals damage doors — ever.** No calm demolition, no passive damage. Breaching always costs ferality (ruled).
- **Empty buildings cannot be pre-breached:** ferals only besiege a building their prey entered (§5.1) and calm zombies can't scratch a door — no prey, no siege.
- `door_integrity` reaching 0 = **breached, permanently**: the zombie barrier is freed, the door is an open hole for everyone for the rest of the level, and the building leaves the flee exit set forever (§9).

### 4.4 Door UI (ruled: bar, pound-quantized; no art dependencies)

- Door integrity renders as a plain **health bar** at the door (current programmer-graphics primitives). It decrements in **visible chunks per pound**, with a small per-hit pulse/shake on the bar — visceral rhythm whose tempo literally is the feral count. It refills in chunks under barricading (slice 2).
- **Parked for the art pass** (mechanics already support it — integrity is chunk-quantized): boards-on-the-door visual — each damage threshold splinters a board off; barricading nails boards back on; remaining boards ARE the display. Do not build any of this now.

---

## 5. ZOMBIE SIDE: THE `BREACHING` FERAL SUB-STATE

Narrative ruling: passive/calm demolition is wrong — in the genre, pursuing zombies keep pursuing and break in. Breaching is feral behavior.

### 5.1 Entering BREACHING

- A feral whose target enters a ShelterBuilding does **not** lose the target into a calm (contrast: escape zones). It transitions to **BREACHING**: nav-paths to **its own nearest door** of that building (ruled — no coordination logic; emergent consequence: an enveloped building gets besieged on multiple doors at once, and the back-door flush gets riskier the more thoroughly the player surrounded it) and pounds per §4.3.
- The **building is a prey proxy**, not a tracked target — the pursuit-claim machinery does not follow humans through walls. Target loss bookkeeping: the human leaves the hunt pool on entering SHELTERED (§6.1); the feral holds a reference to the building only.
- **Committing more zombies = release-at-the-door:** RMB on a door with calm zombies selected is a **release variant** — selected zombies ignite FERAL with the door as seed target, run there (normal peel rules en route — they may peel onto live prey on the way, correctly), and join the siege. Same verb weight, same telegraph-ring pattern as release-on-human, same uncancelability. There is still exactly one attack verb in the game: release.

### 5.2 BREACHING behavior rules

1. **Continuous peel-off stays LIVE (hard requirement, ruled).** A besieging feral keeps its 0.25s scan cadence; live prey within the 250px scan with LOS pulls it off the door via the normal peel rules. The door is the feral's lowest-priority prey — it pounds only while nothing moves nearby. (The farmhouse horde turns as one when the guy runs for the truck.)
2. **On breach**, besieging ferals enter and normal §3.4 feral rules take over — scan, retarget, peel — now with interior LOS through the doorway. Room-by-room hunting is the existing feral system in tighter geometry. Interior cleared + empty pool → instant calm, inside the building: the player now owns controllable zombies in the new play area. No post-siege rules needed.
3. **Feral capture is accepted (ruled):** one human diving through a door can convert an entire pursuing wave into a long siege. Released-is-released — no recall off a door. This is release-weight working (a real cost buildings impose on sloppy releases). **The relief valve is now BUILT (v0.45.0): the Mark siege-pull** — a besieging feral inside the Mark's 400px attention field (ordered sieges included) abandons its door for a valid marked human (direction spec §5.4). Influence, not command: it only fires when the field designates real prey.
4. If the building's occupants all die or flush out (§8) while the door holds: the pool logic governs as normal — flushed humans are FLEEING (global pool; the besiegers at the *other* door retarget onto them per normal rules); an emptied building ends its siege via rule 1/normal calm (no prey proxy without prey — a feral besieging a now-empty building drops BREACHING and calms).

### 5.3 Fear counts

Besieging ferals are zombies like any other: they count toward nearby humans' fear counts **subject to the existing building-LOS gate** — so they terrify passers-by outside, and terrify nobody through the walls. Sheltered humans stay calm while forty ferals dismantle their door (dread is the player's, not theirs) — deliberate, ruled via the existing rule.

### 5.4 AMENDMENT to the §3.4 rule-5 failsafe (required — sieges self-cancel without it)

The no-progress failsafe (target distance must shrink ≥40px per rolling 2s) would calm every besieging feral after 2s, and would calm ferals queued in doorways. Two changes:

1. **BREACHING is exempt from the distance-progress failsafe.** (Progress for a besieger is door damage, which is guaranteed by the pound cadence — no stall is possible at the door.)
2. **The doorway-jam pause-rule (applies to ALL ferals, not just BREACHING):** the failsafe clock does **not accumulate on any frame where the feral's movement collision is with another FERAL zombie** (`move_and_collide` already reports the collider — free signal). Doorways are the first geometry that serializes movement; queued ferals make near-zero progress legitimately.
   - **Why specifically feral, not any zombie — the graceful-cascade property:** a front-of-queue feral wedged on actual geometry collides with the wall (its clock runs) → calms → those behind now collide with a CALM zombie → their clocks resume → they calm too. A jam dissolves into a recallable calm cluster in seconds instead of a permanent feral deadlock; a healthy draining queue (everyone pressed against ferals) never fires at all.

---

## 6. HUMAN SIDE: THE `SHELTERED` STATE (formal definition)

New state on `Human`, alongside IDLE/SENTRY/FLEEING/COWER/DEAD. This section is the bug-prevention centrepiece — implement the transitions exactly.

### 6.1 Transitions

- **Enter:** crossing an unlocked door of an intact ShelterBuilding while FLEEING (the only entry path — nobody strolls in; buildings join the flee exit set, §9). On entry, atomically:
  - leaves FLEEING; **leaves the global hunt pool** (this is what converts pursuers to BREACHING);
  - **cower detector suspended** (without this, everyone inside auto-cowers within ~2s of stopping — the known bug-in-waiting);
  - claims a spot (§6.2) and nav-paths to it, then idles there.
- **While SHELTERED:**
  - **blocks the win condition** (§12) — a sheltered human "remains on the map";
  - not a valid feral target (state-excluded for safety; walls deny LOS anyway);
  - **armed classes: fearless last stand** (§7.2); **civilians: normal fear rules** against whatever becomes visible through doorways/breaches;
  - armory conversion runs here (slice 2, §7.4).
- **Exit paths (exhaustive):** breach-flush (civilians → FLEEING, rejoin exit-set logic; §8), death (→ riser inside per normal rules), level end. **No voluntary exit.**

### 6.2 Interior distribution: shelter markers (prevents the doorway clump)

Without an answer to "where do they go inside?", entrants stop just inside the door and clump. Ruled: **authored markers**, placed per building in the editor (waypoint-like `ShelterSpot` nodes; one script, guard variant by exported flag or two scripts — implementer's call, names free):

- **ShelterSpot:** civilians claim these **deepest-first** (sorted by nav-distance from the entry door), in arrival order, **unit_uid tiebreak** — deterministic. They path there and wait. This distributes bodies across rooms and is authorial: the designer decides this house huddles in the back bedroom.
- **GuardSpot:** armed humans claim these first; each faces a perimeter door with interior LOS — the door-watch (§7.1) fires from here. No GuardSpots in the building → armed fall back to ShelterSpots and door-watch from wherever they stand.
- **Overflow** (entrants > spots): latecomers share the deepest spot, spread by existing DetHash jitter — a huddle; correct fiction for an overcrowded shelter.
- **Capacity: unbounded in v1 (ruled).** No hard cap; a "door refuses the 9th human" rule has no good fiction; an overstuffed building is a richer piñata and self-punishing. Revisit only on playtest absurdity.

---

## 7. INTERIOR DEFENSE

### 7.1 The door-watch (pre-aim)

Problem being solved: with the door intact there is no LOS, so every interior gun is cold at breach; naively, the garrison is either useless or (if fear is simply disabled) a small room makes a lone GI impregnable.

**Rule:** while a building door is **engaged** (ferals in the arc — they can hear the pounding), armed SHELTERED humans with interior LOS to that door train on it: their fill runs **hot against the door itself** (a virtual target pinned to the door position). At breach, the first zombie through eats a near-instant shot; the front then resets and **normal fill rules govern** — including rotation gating, humans-block-LOS, and the critical-distance law.

### 7.2 The last stand (ruled — and it is a simplification)

**Armed humans in SHELTERED are fearless: no fear break, no cower, ever. They hold their spots and fire until killed.** This *deletes* rules for them (no fear checks, no flee, no cower detector) rather than adding any. Civilians inside keep normal fear rules — they are the ones who panic and flush.

**Accepted consequence (ruled explicitly):** armed humans who shelter **never flush** — a garrisoned building always ends in a grind at the guard spots, never a chase. A mixed building at breach produces both at once: civilians burst out the back while the militia die covering the door.

### 7.3 No artificial caps — impregnability self-solves via existing rules

- **Multi-door breaching** (nearest-door-per-feral): enveloped buildings are entered from multiple sides; the **rotation gate** (360°/s turn-to-face before firing) makes opposed entry streams genuinely costly for a lone defender.
- **Humans-block-LOS:** a bunched garrison auto-nerfs in cramped rooms — only clear lanes fire.
- **Critical-distance law:** a defender standing too close to the door loses the pounce race outright. **Interior room size is the fortress dial** — level design, not rules.
- Net intent: a GI shelter costs ~3–6 bodies (the grind regime working as designed); exact numbers are sacred-ratio-sweep territory.

### 7.4 SLICE 2 — the building hardens while you wait (per-building flags, off by default)

Both un-park existing Parked Register concepts; both are deliberately the ONLY hardening levers (alarms/noise/reinforcements stay parked with the pressure systems):

- **The armory (`arms_cache: N` per building):** sheltered **civilians convert to Militia one at a time**, each conversion taking `arming_time` (v0: 8s), unit_uid order, until the cache is empty (cap = cache size). The converted human takes a GuardSpot if free and gets the standard class-letter stamp (M) — the visible tell. Level design owns the difficulty dial: the gun shop is a terrible building to let civilians reach; the bakery is harmless. Organic time pressure — every second the stocked armory is left alone, the piñata grows teeth (this is also the feature's partial answer to direction-spec validation question 5, loitering).
- **Barricading:** while a building is **occupied** and a door is **unengaged**, that door regains `barricade_amount` integrity per `barricade_interval` (v0: 20 per 2s), up to its max (they're pushing furniture against it). Consequences: breaking off a siege un-does progress; slow play lets every shelter harden. One accumulator, fully deterministic. Renders as the bar refilling in chunks.
- **Build order rationale:** both are small *because* SHELTERED exists, but they're tuning-sensitive — feel the bare building in play before weaponizing it.

### 7.5 Free emergent (no code — verify it, don't build it): gunfire summons the horde

Gunfire-death contagion already seeds woken calm zombies **at the shooter** (§3.3 of the direction spec). A shooter inside a building means ignited zombies outside have prey inside a building — which is precisely the BREACHING trigger. **The moment the garrison fires through the breach, every calm zombie within contagion radius wakes and joins the siege.** Gunshots draw the horde to the farmhouse — the most famous rule in zombie fiction, falling out of three already-locked systems. Last-standers' defiance recruits the neighborhood against the player. Test for it explicitly (§14).

---

## 8. THE BREACH MOMENT

### 8.1 The flush

**Breach is a fear event, LOS-gated like all fear (ruled).** When ferals pour in:

- Humans with LOS to them (within fear radius) break per class rules — **civilians flush**: → FLEEING, route to the next-nearest valid exit (another building or an escape zone; the breached building itself has left the exit set). Multi-exit buildings burst out the back — the chase restarts outdoors, into whatever the player left waiting at that door.
- Single-exit buildings: flushed civilians can't get past the doorway horde → jam → cascade into a COWER huddle (per §8.3) → terror harvest.
- **Armed humans do not flush** (§7.2) — they die at their spots.

### 8.2 Room-by-room propagation (sight AND radius — the existing rule, reused verbatim)

The fear count already requires zombies within the 250px radius **and** building-LOS-visible. Interior walls block dread; open interior doorways leak it. A feral bursting into the kitchen panics the kitchen; the bedroom two walls away stays oblivious until a feral rounds into its sight-line. The frenzy sweeps the floor plan and panic propagates by sight — the room-by-room hunt is zero new mechanics. Corollary for level design: aligned doorways/corridors are long sight-lines — deep rooms with them panic early.

### 8.3 AMENDMENT to the §4.4 cower detector: the fleeing-queue pause-rule

Mirror of §5.4.2, same detector class, same fix: **the cower clock does not accumulate while the human's blocking collision is another FLEEING human.** Without this, a back-door flush queue draining slower than ~20px/s trips COWER — humans "cornering" permanently in an open doorway one body-length from a valid exit, which violates cower's meaning (trapped, not waiting in line).

- Cascade property preserved: in a genuine dead end, humans at the wall collide with the wall (clocks run) → front rank cowers (drops; no longer FLEEING) → those behind are blocked by cowerers, not fleers → their clocks run → the huddle cascades into COWER exactly as §4.4 intends. Only live, draining queues are protected.
- Applies **globally** (any flee queue at any chokepoint), not just inside buildings — doorways are simply the first geometry that will trigger it.

---

## 9. FLEE ROUTING: ONE UNIFIED EXIT SET (ruled)

- ShelterBuilding doors and escape zones live in **one exit set**; broken humans pick by the existing rule — **nearest, with the existing threat-aware bias**. No class preferences, no weighting math. A human runs to whatever safety is closest.
- **Membership churn is the strategic texture:**
  - an **engaged door** (ferals in the arc) leaves the set **temporarily** (predicate-driven, returns when clear);
  - a **breached building** leaves the set **permanently** (a hole in the wall is not shelter);
  - humans en route re-path via the existing threat-aware flee cadence when their target exit drops out.
- **Accepted consequence (ruled):** the player can steer runners toward buildings by which exits they leave unbesieged — herding prey into the arena by controlling which exits look open. Sanctioned.

---

## 10. SCORING, VISIBILITY & READABILITY

- **Interior kills are fully scored (ruled)** — normal tiered base, burst, and terror rules. Cower huddles inside pay terror bonuses as anywhere. Combo chains indoors are the arena payoff. Scored event remains pounce kills only; zombies shot by the garrison are the player's loss, unscored, and do **not** rise.
- **Humans killed inside rise CALM inside** per normal riser rules — post-breach interiors refuel the horde from its victims.
- **Contagion is NOT LOS-gated** (existing rule, kept deliberately): a kill inside ignites calm zombies outside through the wall — the building leaks violence outward; paired with §7.5, both directions are consistent (indoor violence wakes the street; the street's dread never penetrates walls because fear IS LOS-gated).
- **Interiors are always visible to the player (ruled):** walls render as outlines/cutaway; no fog, no roofs, no hidden occupancy. Predictability-pillar call — hidden interior state ("how many in there? is one arming?") converts planning into guessing. The hiding fiction survives because the *zombies* can't see in; the player is the apocalypse, not the horde.
- **Readability inventory** (interim on-unit rendering now; migrates to the Phase-5 `vision_renderer` layer like everything else):
  - door integrity bar, chunk-decrement + per-pound pulse (§4.4); refill chunks under barricade;
  - engaged-door tell (so active sieges read at map scale);
  - locked-vs-admitting state tell;
  - arming conversion = class letter (M) stamp appearing on the civilian (existing stamp system);
  - door-watch = the existing fill line, pinned at the door.

---

## 11. DETERMINISM (§10 of the direction spec applies in full)

- Pound cadence: fixed interval, DetHash per-unit stagger. No RNG anywhere in the feature.
- All claims and orders in unit_uid order: shelter/guard spot claims, arming queue, pound accounting.
- Lock predicate and exit-set membership: evaluated on fixed cadences, registry-ordered.
- The two collision-pause rules (§5.4.2, §8.3) read `move_and_collide` results — deterministic here (no RVO; avoidance disabled project-wide), but **explicitly include both in the §10 boot-twice-and-diff determinism spot-check**, since they're per-frame physics reads.
- No wall-clock time anywhere; all accumulators tick on physics frames.

---

## 12. WIN / LOSE

- **SHELTERED humans block the win** — they remain on the map; the level cannot end until every occupied building is breached and cleared (or its occupants flushed and dealt with). With full interior scoring, the mandatory endgame siege is a payoff (arena + terror harvest + risers), not a chore.
- Lose condition unchanged (zombie total zero, risers counting) — a player who feeds their entire horde into a garrisoned door can absolutely lose to it. Working as intended.

---

## 13. PARKED (from this feature — do not build)

- ✅ **Mark-lures-ferals-off-doors** — UN-PARKED and built (v0.45.0) as the Mark **siege-pull**; see §5.2.3 and direction spec §5.4.
- **Costume Zombie as door-walking infiltrator** — the sanctioned Trojan; goes to the post-PoC specials re-audit.
- **Boards-on-doors visual language** (§4.4) — art pass; mechanics already chunk-quantized for it.
- **Interior door mechanics** (locking/breaching room doors) — flatly recommended against for v1; revisit only if room-by-room play proves too fast.
- **Windows as fire/LOS ports** — rejected for v1 (complexity); boarded-window fiction covers it. Revisit with the art pass or 3D.
- Multi-storey / rooftops — 3D migration territory.

---

## 14. NUMBERS v0 (all GameConfig, LevelConfig-overridable; all deliberately rough)

| Knob | v0 | Notes |
|---|---|---|
| `door_engagement_depth` | 25px | lock zone = breach arc, unified; "on the doorstep" |
| `door_unlock_hysteresis` | 0s | tuning option only |
| `pound_interval` | 1.0s | DetHash-staggered per feral |
| `pound_damage` | 10 | flat per pound |
| `door_integrity` (default door) | 600 | per-door; ≈10s under a 6-feral siege; armory-grade e.g. 1500 |
| `door_width` | per-door | first-class level-design knob |
| `arming_time` (slice 2) | 8s | per civilian, sequential, unit_uid order |
| `barricade_interval` / `barricade_amount` (slice 2) | 2s / 20 | only while occupied + door unengaged |

Sweep jobs for this feature: siege duration feel (pound math), garrison toll (~3–6 bodies for a GI shelter), lock feel at 25px, flush drain vs door width.

---

## 15. IMPLEMENTATION NOTES FOR THE BUILD SESSION

- **No runtime navmesh re-bake needed:** bake the navmesh **with doorways open** from the start. Doors close via physics barriers only — layer-4 zombie barrier (always on until breach; escape-barrier pattern verbatim) + a human-blocking barrier active while locked. Breach = free the zombie barrier. Physics changes; nav never does — sidestepping runtime-re-bake determinism entirely.
- Interior walls: `wall.gd` polygons (existing — LOS + nav footprints already handled by `nav_baker`).
- New scripts (names verified free against `scripts/` on 2026-07-23): `shelter_building.gd` (`ShelterBuilding`), `door.gd` (`Door`), `shelter_spot.gd` (`ShelterSpot`). Remember the global-class cache gotcha: run `--headless --import` after creating them, before the parse gate.
- `building.gd` untouched; comment its `is_enterable` flag as superseded.
- New Human state `SHELTERED` in the dispatcher; new Zombie feral sub-state `BREACHING` routed from `_tick_feral` (dispatcher-shell + component pattern per ARCHITECTURE_GUIDELINES — a `BreachBehavior` component is the natural home; door-watch likely extends `FillBehavior`; flush/spot logic extends `FleeBehavior`/a small `ShelterBehavior`).
- Release-at-door: `selection_manager.gd` RMB handling gains the door case (telegraph ring on hover, like release-on-human); `release_seeder.gd` seeds with the door as target.
- The two detector amendments (§5.4, §8.3) touch the failsafe in `feral_brain.gd` and the cower detector in `flee_behavior.gd` — smallest possible diffs: gate the clock accumulation on the collider's type/state.
- Propose-before-implementing applies to every step; slice 1 before slice 2; per-building flags default off.

### Acceptance test scenarios (manual, per project convention)

1. **Shelter + slam:** civilian flees into building with feral 60px behind → enters; feral thuds and begins pounding; bar chunks down per pound; human claims deepest ShelterSpot.
2. **Besieged door admits no one:** second human arrives at engaged door → bounces, re-paths to next exit.
3. **Peel-off from siege:** walk a live human within 250px of a besieging feral → it abandons the door instantly.
4. **No failsafe self-cancel:** solo feral pounds >10s without calming; doorway queue of 6 pours in post-breach with zero mid-queue calms.
5. **Flush:** breach a two-door building of civilians → they burst out the far door; single-door variant → doorway huddle cowers (no cower during the draining queue itself).
6. **Last stand:** Militia on a GuardSpot never breaks; first zombie through the breach dies near-instantly (door-watch); garrison costs multiple bodies; garrison never flushes.
7. **Gunfire summons:** calm zombies parked within contagion radius outside ignite and join the siege when the garrison fires.
8. **Determinism:** boot-twice-and-diff a scripted siege scenario (pound timings, spot claims, flush routes identical).
9. **Backwards compat:** a level with no ShelterBuilding plays byte-identically.

---

## 16. AS-BUILT AMENDMENTS (2026-07-23 → 27, all rulings Ben's — this section wins over §1–§15 where they differ)

### 16.1 Structure
- **ShelterBuilding is a mouse-editable `Polygon2D`** (`shelter_building.gd`, `@tool`), not a container of Wall segments: the drawn footprint IS the building — wall quads auto-generate from its edges minus door gaps, nav outlines merge from the same geometry, and `Door` nodes snap and slide along the perimeter. Any shape, not just rectangles.
- **Scale self-heal:** `_normalize_scale()` folds any editor-applied node scale into the polygon + child positions at load (restoring winding) — a scaled building can no longer silently corrupt geometry.
- **Occupied-building targeting:** with zombies selected, the **whole footprint** is the release target (hover outline telegraph) — no picking individuals through walls.
- **Shelter adoption:** hand-placed humans inside an intact `is_shelter` building become SHELTERED occupants at boot (`GameManager._adopt_shelter_residents`; nearest intact door = notional entry). Patrollers, dumb boxes, and ruined buildings are skipped. This closes the "spawned-inside humans act oblivious" gap and makes pre-placed garrisons real.

### 16.2 The terrain kit (2026-07-25 ruling — one door mechanic, many terrain shapes)
- **Gates:** a standalone `Door` in plain `Wall` geometry (hand-carved gap; no building). Full barrier/lock/pound/breach mechanics; no shelter semantics; no inside-burst (no "inside" exists).
- **Dumb boxes:** `is_shelter = false` on ShelterBuilding — enterable geometry whose doors never join the flee exit set and never convert entrants to SHELTERED. Pure terrain. (This soft-deprecates perimeter-mode `Wall`; `Wall.solid` now defaults `true`.)
- **Door dials:** per-door `integrity_override` and `thickness`; **`starts_open`** = a pure portal, born breached — no barriers, no lock, no leaf. Consequence (ruled): an open door is a permanent hole, so its building **counts breached from birth and never shelters** — otherwise `is_safely_sheltered` would protect occupants of a walk-in building.
- **Prey-beyond-door pounding (both sides):** a feral wedged at any intact door with a live target beyond it converts to pounding it — gates get besieged from either side.
- **RMB-release-on-door:** an ordered siege of a specific intact door (you can't building-click a wall). Hover telegraph. Still the one attack verb.

### 16.3 Siege & breach behavior
- **Pour-in at breach (supersedes the interim calm-at-the-door):** the siege COMMITS. At breach a besieger retargets normally first; on an empty scan it takes the **nearest living occupant** of its besieged building, no LOS gate (occupants aren't in the global pool), preferring un-pursued occupants (the peel philosophy indoors). Once one is pursued the rest converge via the pool.
- **Breach-frame race fix:** the dying door zeroes its barrier collision layers **before** `queue_free` — the same-frame LOS raycast otherwise still hit the freed blocker and calmed besiegers at the mouth.
- **Inside burst:** any living zombie (calm included) in the **inside** half of an intact door's arc breaks it open **instantly** — the body price was paid at the entry breach; pursuit flows out the back. (Supersedes symmetric-barrier wedging at back doors. Standalone gates excluded.)
- **Engagement arc is double-sided** for the prey-beyond-door case; pre-breach, only the outside half locks/pounds a shelter door.
- **Failsafe status:** the §5.4.1 BREACHING exemption is live; the §5.4.2 feral-collider pause and §8.3 fleeing-queue pause are implemented but **latent** (units have no unit-unit body collision yet).

### 16.4 Human side
- **Fear and cower are FULLY suspended while SHELTERED** (sharpens §6.1) — fear ticking inside caused a 60Hz break→re-enter loop (door-gap humans sit inside the DoorLOS body; outward rays leak via hit-from-inside). Civilian fear re-arms only at `not is_safely_sheltered()` (breach); armed humans stay suspended forever (§7.2 last stand as specced).
- **Sight-only breach fear (sharpens §8.2):** inside a breached building the 250px fear cap **drops** — the count is all living zombies, LOS-only. Interior walls still stage the room-by-room sweep; outdoor fear keeps its radius. (Big-building civilians otherwise didn't flush until ferals were halfway in.)
- **The flush is routed, two-leg:** `_threat_direction` inside a breached shelter is uncapped + sight-gated, and the flush commits a **door-leg route** — first waypoint = the just-outside point of the building's best passable door (threat-scored like exits), then the committed exit. Cures the "charge the breach, reverse, die" dither. Single-door flush jams remain designed (§8.1 jam → cower).
- **Exit churn re-path:** a fleeing human tracks its committed exit NODE and re-picks via the threat-aware picker whenever that exit drops out (engaged/locked/breached) or a better one returns.
- **Door-watch arms only from the claimed spot** (`at_shelter_spot()` gate) — mid-walk entrants were drawing phantom fill lines through the door (the same hit-from-inside ray leak).

### 16.5 Combat numbers & feel
- **Per-class `fire_cooldown`** (v0: Civ 0 / Mil 0.8 / Pol 0.6 / GI 0.4s) gates the **shot, not the front** — point-blank refills (~0.07s) let a lone militia shred waves; at range (fill time > cooldown) nothing changes. Direction-spec §9 table updated.
- **Pounce lunge speed** derives from `pounce_range / flight_time × 1.5` (was zombie_speed — slow configs landed short, killing "from afar").
- **Finishing zombies** (pounce recovery) are box-selectable; orders are **stored** and apply at calm, dropped if the hunt continues — the corpse-command model applied to the recovery beat.
- **Door integrity bar** renders on a z-10 layer (above units), chunk-decrement + pulse per §4.4; locked doors tint the leaf dark-red; doors and buildings hover-outline as release telegraphs.

### 16.6 Status of the acceptance scenarios (§15)
Scenarios 1–6, 8, 9 verified in play/headless across 2026-07-23→26 (scripted end-to-end siege = `scenes/shelter_test_siege.tscn`, kept as the standing boot-twice regression; fast-forward determinism harness = `shelter_test_siege_ff.tscn`). Scenario 7 (gunfire-summons) observed emergent during play — an explicit staged verify remains a Phase 6 item.

---

**END OF SPEC** — slice 1 + terrain kit are live on `v2-poc` (v0.44.0→v0.45.0); slice 2 remains gated on level-scale play.
