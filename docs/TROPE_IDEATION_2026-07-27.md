# DEAD CORPS — ZOMBIE-MEDIA TROPE IDEATION RECORD

**Date:** 2026-07-27 (design conversation, Ben + Claude)
**Status:** IDEATION RECORD — nothing here is design-locked, scheduled, or approved for build. It supersedes nothing. Every item is **post-M1-verdict at the earliest**, and most sit behind the enterable-buildings milestone (`V2_ENTERABLE_BUILDINGS_SPEC.md`), which itself waits on the Phase 6 verdict. Rule 1 (propose-before-implementing) applies to every entry when its time comes.
**Method:** full sweep of zombie film/TV/game tropes, filtered through the inversion lens (*the iconic survivor moments, experienced from the predator side*) and gated against the v2 pillars. All keep/cut rulings below are Ben's (2026-07-27).

**Session side-effect (actioned same day):** Ben confirmed the 3D cancellation should be documented — CLAUDE.md's stale "3D migration confirmed" wording was rewritten and the Ben-gated WORK_QUEUE doc-sync item flipped. See `ISO_MIGRATION_PLAN.md` for the cancellation decision itself (2026-07-12).

---

## 1. Tropes the design already owns (no action — inventory only)

Recorded so future ideation doesn't re-pitch them: the farmhouse siege + pounding on the door (buildings spec), gunshots-summon-the-horde (emergent, buildings §7.5), the door slammed in the latecomer's face (lock predicate), boarding the windows (barricade, slice 2), the gun-shop race (armory, slice 2), "they got back up" (risers), one runner dooms the quiet street (the sanctioned chaos vector), the crush at the exit (cower cascade), special infected (the 11-roster), the Trojan-in-disguise (Costume Zombie, parked to the specials re-audit), noise systems / evacuation / snipers / radio operator / convoy escorts (Parked Register).

---

## 2. NEAR-TERM POCKET — candidate successors to the buildings milestone

### 2.1 Foldable fences — mass breaks barriers
*WWZ's Jerusalem wall; TWD's prison fence bowing under bodies.*
Variable-length fence segments (door-machinery cousin) that collapse under zombie **mass**, not pounds: N zombies within the engagement strip for a dwell period → the fence folds, permanently. A **mass gate** where doors are a time gate — "a secret path if you got this far with a big horde" (Ben's framing).
- **Ruling to make at spec time:** calm zombies **count** toward the press. Rationale: ferals only besiege where prey went, so a feral-only fence with nothing behind it would never be pressed and the secret-path fantasy dies. Fiction carries it — this is *structural failure under weight*, not demolition, so "the calm reserve never demolishes" survives; the reserve gains a terrain verb, not an attack verb.
- Telegraph: visible bend/creak state as the count approaches threshold; dwell requirement so brushing past doesn't trip it.
- Pillar audit: clean; deterministic by construction; reuses the door engagement-strip geometry.

### 2.2 Hazard terrain — the priced perimeter
*WWZ's layered defenses; TWD spike moats; every fortified checkpoint.*
Level-design vocabulary that charges crossings: **barbed wire** (slow zones — locally shifts the critical-distance law, so the fill wins races it normally loses), **landmines** (deterministically kill the first N crossers), **fire zones**. Zero new AI; slow-zones are nearly free (area speed modifier).
- **Design as a pair with counter-specials** at the specials re-audit — the existing roster already counter-picks: Fat Zombie's corpse bridges wire/mines (the body-on-the-wire trope), Headless's straight-line charge is a natural mine-sweeper, Scuba answers moats. Every hazard should ship with its counter-key.
- Overlaps the parked hardpoints/pressure-systems space — reconcile at spec time.

### 2.3 Kill-context riser denial (rider on 2.2)
*Burning the dead / the pyre; "destroy the brain."*
One rule: **a human killed inside a fire zone or by an explosion (mine, future area weapons) does not rise.** Where you kill decides whether you keep the body — herding prey *out* of the burning zone before the pounce is harvest skill; grinding against a future flamethrower/vehicle defender burns your ammunition stockpile, not just your count. Deepens attrition math with no new AI and no corpse-racing (see §4.1 for the rejected version this replaces). Also worth naming: escapes are already body denial — the end-screen "escaped" stat is the body-economy scoreboard.

---

## 3. DEEP POCKET — post-validation / campaign-tier

### 3.1 The generator — cut-the-power as chase geometry (NOT darkness)
*"They cut the power" — the siege staple.* Moved to deep pocket (Ben, 2026-07-27). A destructible side-objective (defended/walled — it has a body price) whose reward pays in the game's real currency:
- **Powers an escape route** (electric gate at the evac, the tram): killing it removes that exit from the exit set → every fleeing human map-wide re-routes toward the exits the player left open, i.e. into the ambush. Reuses the buildings-spec exit-set-churn machinery.
- **Powers the electric fence**: electrified perimeter kills/blocks pressers; depowered, it's an ordinary foldable fence (§2.1). The side objective literally opens the secret path.
- Optionally powers emplacements/floodlit awareness-*bonus* pools.
- **Explicitly rejected form:** global darkness / reduced-visibility play (§4.3). Night/weather survive as mission *skins* only.

### 3.2 The Bitten — a visible time bomb inside the shelter
*The universal hidden-bite trope, made predictability-safe.* A special zombie's **non-lethal bite** puts a **player-visible countdown** on a human, who flees, shelters… and turns inside. The Trojan the buildings spec ruled out at the door (§4.1 there) comes in through the fiction instead; sieges gain a second solution besides pounds. Hidden infection stays banned (§4.5) — the visible timer is the whole trick. **Filed to the specials re-audit** (delivery needs a bite-that-doesn't-kill, which belongs on a special, not the core pounce).

### 3.3 The Flare — the horde's attention hijacked
*Land of the Dead's "sky flowers."* A defender counter-tool: a fired flare acts as a **hostile Mark** for its burn duration — ferals rank the flare point above prey outside local scan; humans slip away while the storm gawks; the player counters by intercepting or pre-marking. Gives the enemy one move in the influence game, which makes the Mark feel earned. Must obey the same scope discipline as the Mark (reorders the menu; never summons across the map). **Sequenced strictly after the Mark validates in M2** — it's the Mark's evil twin; don't build the twin first.

### 3.4 Herd-escort mission type
Ben's reframe of the wandering-herd idea (the ambient version is dead, §4.4): a mission archetype where the player shepherds an **uncontrolled** horde through a hostile area — including narrative "seed zombies" that must survive the crossing. Filed alongside the parked convoy-escort entry (it's that concept mirrored onto the player's side). Far-future; new-mission-types territory.

### 3.5 Boss survivor + armoured vehicle
The hero-protagonist unit, salvaged as a **scripted set-piece boss** — fixed, learnable patterns, so determinism is no obstacle (a boss with fixed patterns is a puzzle, which is this game). The **armoured vehicle** is a mobile hardpoint whose area kills also deny corpses (§2.3) — it threatens the player's economy, not just their count. Campaign-tier.

### 3.6 Multi-storey buildings — wanted, unsolved
Ben wants multi-storey. It was formerly parked "to 3D"; **3D is cancelled**, so it now needs a 2D-isometric visual answer on its own merits — candidate directions when its time comes: floor-peel/cutaway (render the active storey, ghost the rest — X-Com/Divinity floor-slicing adapted to fixed iso) or linked off-map sub-grids (the upstairs as a separate room block connected by stair markers). No approach chosen; no schedule; genuinely hard visually — deep pocket.

---

## 4. KILLED ON THE RECORD (don't re-litigate)

1. **Double tap / corpse racing** (defenders destroy corpses pre-rise) — dead: at `rise_time` 2.5s nobody can race a corpse, and a surviving shooter mops risers anyway. The salvage is kill-*context* denial (§2.3).
2. **Gut-smeared walker** (broken human walks slow, invisible to feral targeting, must be deliberately collected) — dead: survivor-fantasy leaking into a predator game; complex and confusing; cowerers already own "deliberate collection."
3. **Literal darkness / blackout play** — dead as a mechanic (playing in the dark isn't fun); the generator's reward is rerouted to chase geometry (§3.1); night/weather are skins.
4. **Wandering herd as ambient level furniture** — dead in that form; survives only as the herd-escort mission type (§3.4).
5. **Bring the house down** (poundable structural pillars → collapse kills everyone inside, unscored, risers denied) — cut by Ben 2026-07-27.
6. **The post-breach-agency exploration, wholesale** (calm follow-in framing, scalpel-vs-avalanche interior regimes, interior Mark emphasis, extra playtest questions) — cut by Ben 2026-07-27: "nothing there I really like." Interiors post-breach stay exactly as specced in `V2_ENTERABLE_BUILDINGS_SPEC.md`; no additions.
7. **Pillar-violation rejects from the sweep** (for completeness): hidden infection / unknown bite status (predictability — §3.2 is the salvage); the L4D-style AI director (determinism-in-rules forbids situational rule changes); crawlers/wounded half-zombies (reintroduces partial states the pounce model deleted); any chance-based mechanic (no live RNG — note the Ordnance Zombie's 50% rolls will need the same re-audit); loyal/recallable pet zombies (released-is-released); a dynamically-fighting hero unit (salvaged only as the scripted boss, §3.5); fog of war / hidden building occupancy (already ruled in the buildings spec).

---

**END OF RECORD** — promote entries out of here via normal spec work (propose → rule → spec → build), one at a time.
