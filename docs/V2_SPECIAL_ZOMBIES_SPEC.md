# DEAD CORPS — V2 SPECIAL ZOMBIES SPEC: Special Humans & the Costume Zombie

**Version:** 1.0
**Date:** 2026-08-06 (design session, Ben + Claude — all rulings below are Ben's, 2026-08-06)
**Status:** **APPROVED by Ben 2026-08-06** (draft reviewed same day, no corrections; the §9 soft flags stand as chosen defaults pending playtest). Design spec — **no code exists for any of this yet**; next step is a build proposal (rule 1 applies to every implementation step). The Costume Zombie special is **approved for inclusion in the PoC slice** (amends direction spec §12's "no specials").
**Supersedes:**
- GDD §7.1/§7.2 (the building-transformation creation system) — **superseded as the creation grammar for specials.** Buildings no longer transform zombies; specials are earned by killing special humans. ("For now" — Ben; revisit only if this model fails in play.)
- GDD §5.7 (Costume Zombie v1) — the v1 ability text was written against systems the pivot deleted (vision cones, morale, alerts, grapple). §3 below is the v2 replacement.
- The v1 broken-costume scoring edge case (GDD §11 known issue) — mooted: on disguise break the unit stops being special entirely (§3.6), and v2 has no per-unit survival scoring anyway (direction spec §6.2).
**Amends:**
- Direction spec §3.7 ("specials never go feral") — refined, not overturned: a *costumed* special never goes feral; the break ends its specialness (§3.6). The never-feral default stands for future specials until their own re-audits.
- Direction spec §12 (PoC roster) — the Costume Zombie special (and its special human) joins the slice.
- The 2026-07-30 grammar ruling "release is for prey, orders are for terrain" — gains one rider (§3.4): the **ordered kill** is the special's prey-order. The ruling's real axis is *commitment* (release is uncancelable; orders cancel), and the ordered kill is a cancelable, controlled act — a scalpel, not an avalanche.

---

## 1. THE FEATURE IN ONE PARAGRAPH

Specials are **earned, not spawned**: each level may contain **special humans** — normal defenders in every mechanical respect, visually distinct at a glance — and killing one converts it, through the normal riser pipeline, into the mapped **special zombie**. The player must locate the special human on the map and get a pounce onto it before it escapes; an escaped special human is that special **lost for the run**. The PoC's special is the **Costume Zombie**: undetectable by every human-perception system while costumed, able to open doors like a human, and armed with a player-**ordered kill** — walk it through the defended line, through the front door, point at the prize, and the disguise breaks as it leaps. From that moment it is a mechanically ordinary zombie standing in the middle of everything the disguise carried it past.

---

## 2. THE FRAMEWORK — SPECIAL HUMANS

Everything in this section is generic: it is the creation grammar for the whole future roster. The Costume Zombie (§3) is its first instance.

### 2.1 The special human
- A designer-placed human carrying one export: `special_type` (PoC: `COSTUME`; the enum grows with the roster). Placed in the editor like any other human.
- **Completely normal otherwise (ruled).** It has a `defender_class` and fills, fears, flees, shelters, and cowers by that class's normal rules. It counts toward the win condition like any human; its kill scores as a normal combo kill (terror bonus applies if it was cowering). No special-side behavior changes of any kind. *(Ben: "this may change in the future but for now it's fine.")*
- **Class is the designer's choice per placement.** The PoC level's costume-special human defaults to **Civilian** — a pure prize that flees early and creates a chase, not a prize that fights.
- Multiple special humans per level are allowed (each yields its own special). The PoC level carries exactly one.

### 2.2 "Locate" = find on screen (ruled)
The special human is **always visibly distinct in-game** (§5). Locating it means finding *where it is* — behind which line, inside which shelter, in which fleeing crowd — never *identifying which* human it is. There is no hidden-information mechanic here (consistent with the predictability pillar and the standing fog-of-war rejection). The hunt is geographic: it may be sheltered (breach to reach it), it may rout with the crowd (chase geometry), it may cower (deliberate collection).

### 2.3 The creation pipeline
- **Trigger: any pounce kill of a special human** — an ordered special kill, a released feral, or a contagion-ignited feral all count. The player "locates and kills" loosely: the storm can do the killing so long as the player put the storm there.
- **Delivery: the existing riser pipeline, unchanged.** The special human dies like anyone; after the normal level `rise_time` it rises **at the death spot, CALM, as the mapped special zombie** instead of a standard zombie. One new branch at `_raise` (spawn the mapped scene), nothing else.
- **Corpse commands (6a/6b) work on a special corpse**, with one re-mapping: the queued click's release-or-move re-resolution cannot release a costumed special (never feral, §3.6), so *human near the first waypoint* resolves to an **ordered kill** on rise instead of a feral release. Move orders and control-group tagging (6b) apply verbatim.
- A pending special riser counts toward the lose-condition zombie total like any pending riser.

### 2.4 Denial
- **Escape = lost for the run (ruled).** A special human that reaches an escape zone is freed like any human, and the special it carried is gone. No second chance, no respawn. This is the existing "escaped = lost converts" body economy with the stakes turned up.
- The end screen's escaped stat calls it out when it happens (one line, e.g. "Escaped: 4 — including the Costume"). *(Minor; wording at build time.)*
- Interaction noted for later: if kill-context riser denial (trope record §2.3) ever ships, a special human killed in a denial context would also deny the special. Consistent by construction; decide when that feature is real.

---

## 3. THE COSTUME ZOMBIE (v2)

**Fantasy:** the Trojan in disguise — the horde's embedded agent. **Fiction:** a zombie in a silly disguise (sombrero, fake mustache, clown suit) that fools every human until the moment it leaps.

### 3.1 State
One latch: `is_costumed`, starts **true**, breaks **permanently** (§3.6). While costumed the unit is CALM-only: it can never go feral, can never be released, and is immune to contagion ignition (the existing `is_special` guard). It is always selectable and commandable — the player's control over it is never taken away.

### 3.2 Undetectable — the v2 surface list
**The rule of thumb: while costumed, the unit is absent from every *human-perception* query and present in every *physical and player-side* query.** Exhaustively, while costumed it is skipped by:

- **The fill front** (§4.1) — it never starts, holds, or hots a front; it can never be the shot target; it does not gate decay ("no zombie visible" ignores it).
- **The civilian reaction clock** (the civilian fill variant).
- **The fear count** (§4.2) — contributes nothing toward any break threshold, at any range.
- **Flee-vector herding** — fleeing humans' routes do **not** bend around it (`flee_repel` ignores it).
- **The zombie-at-the-door exit filter** (v0.47.0) — it never strikes an exit off the list; humans will flee straight past it, even through it (units have no unit-unit collision — nothing to bump).
- **The door-watch** (buildings §7.1) and every other "zombies in range/arc" human query.

Consequence, accepted and ruled: **the disguise trades away all presence-based power.** A costumed zombie cannot herd, cannot block a door, cannot hold a gun hot, cannot tip a fear count. Its only powers are *going where zombies can't* and the ordered kill. This is the self-balancing heart of the special.

Still fully in effect while costumed (the physical/player side): selection and orders, BOID separation against other zombies, the world-bounds clamp, the **escape-zone barrier** (it bypasses *door* barriers, §3.3, but the EscapeBarrier still stops it — no special ever enters an escape zone), the lose-condition count (it is a zombie), and gunfire… vacuously (no fill can ever target it — but see §3.5 for the reveal window).

### 3.3 Doors open for it (ruled — "a big part of the utility")
**While costumed, the unit passes doors under exactly the human admission rules.** Mirror, don't invent:

- An **intact, unlocked** door admits it: it walks through as a human would. The transit is **personal and stateless** — the door "opens for it and closes behind it": the door's state never changes, its zombie barriers stay up throughout, and **no other zombie can follow** (by construction — the barrier exemption is per-body, there is no open interval to tailgate).
- A **locked** door (feral in the engagement arc, §4.2 of the buildings spec) bars it exactly as it bars a human: an engaged door admits no one. You cannot walk your infiltrator through a doorway your own frenzy is pounding on.
- A **breached** door or `starts_open` portal is a hole; anyone passes, nothing to say.
- It **never engages a door**: calm units never trigger the lock (existing rule), it never pounds, and — critically — **it is exempt from the inside burst while costumed.** Without this exemption it would smash open every door it entered (any living zombie in the arc's inside half bursts the door — Ben's 2026-07-25 ruling); the exemption *is* the "closes behind them" ruling, mechanically.
- It is **excluded from `CalmBreach`** while costumed — ordered or incidental. Doors are not obstacles to it, so it never converts to pounding; an ordered move through a building simply paths through the doorways (the navmesh is baked with doorways open — buildings spec §13 — so pathing is free; only the barrier exemption is new).
- Entering an intact shelter this way has **no shelter-side effect**: it claims no spot, counts toward no occupancy, triggers no door-watch, and — being perception-exempt — alarms nobody. It stands among them, waiting for your order.

### 3.4 The ordered kill (ruled — the kill verb)
The costumed special's attack is a **player-ordered, controlled, cancelable pounce on one named human** — model (c) of the design session:

- **Grammar:** with the special selected, **RMB on a human = ordered kill on that human** (same `release_aim_radius` magnetism and hover-ring telegraph as a release — the pin-to-nearest feel is identical; what differs is what the click *means* for this unit).
- **Mixed selection (soft default, flag for playtest):** RMB-on-human with normals + a costumed special selected → the releasable normals **release** as today, and the special receives the **ordered kill** on the same pinned human. One click, one target, everyone attacks per their nature. Accepted risk: an accidental spend of the disguise — mitigated because the order is cancelable up to the lunge (below). Fallback if playtests produce rage-misclicks: specials ignore RMB-on-human inside mixed selections.
- **Execution:** the special nav-paths to the target like any calm move — at zombie speed, through any doors that admit it (§3.3), chasing if the target moves or flees. It remains CALM, selected, and commandable throughout. **Any new order cancels the kill instantly** (the `CalmBreach` cancellation pattern). No failsafe timer — the player is the failsafe; agency is never taken.
- **Target loss:** the target dying (someone else got there) or entering an escape zone cancels the order on the spot; the special stands calm where it is.
- **The lunge:** within `pounce_range`, it launches a **normal Pounce** — same flight time, same kill-at-landing, same mid-flight-death-means-no-kill, same 1.0s recovery, no new numbers.
- **The break is at pounce launch (ruled §3.6)** — from the instant it leaves the ground it is a visible, valid, ordinary zombie. During the ~0.2s flight it can be shot like any pouncing zombie; a defender whose front is already hot (against *other* zombies — it could never be hot against the costume) can kill it mid-flight and save the victim by a hair. Revealing inside an already-hot fill zone is a real risk; revealing among cold defenders is the assassination working as intended.
- **Aftermath:** the kill is a normal pounce kill in every system — it **scores** (combo event, window refresh, terror bonus if the victim cowered), it **fires contagion** at the kill site (killer excluded, as ever), and the victim **rises** by §2.3/§3.6 of the direction spec (a special-human victim rises special, per §2.3 here).

### 3.5 Interior aftermath — the Trojan horse payoff
The ordered kill's signature use is *inside an intact shelter*. What follows falls almost entirely out of existing machinery, plus one new rule:

- **The compromised rule (new, one sentence):** *a revealed (non-costumed) living zombie inside an intact shelter's footprint puts that building's occupants under breached-interior rules — fear sight-gated and uncapped, normal fill rules against interior threats, breakers flee via the flush machinery — while the physical shell (barriers, door integrity, adoption) stays intact.* Without this, the fear-suspension that protects sheltered humans from exterior pounding would have occupants placidly ignoring a zombie eating their neighbor. With it, panic propagates by sight through the floor plan exactly as buildings spec §8.2 intends.
- **Compromised buildings drop out of the flee exit set** while a revealed zombie is inside (soft call — flag for playtest). Consistent with the existing churn machinery: engaged, locked, and breached doors already drop out live; "safe shelter" is the criterion and a wolf in the fold fails it. Fleeing humans elsewhere re-pick exits by the standing three-pass rule. *(Note the converse: a merely costumed infiltrator compromises nothing — the building stays a valid, calm shelter while your agent stands in it. Infiltrate early, wait, reveal at the moment of maximum harvest.)*
- **The inside burst opens the gates:** the revealed zombie — and, 2.5s later, the victim's riser — are ordinary living zombies, and any of them walking into a door's inside arc **bursts it open instantly** (existing rule, buildings §4.3). The Trojan-horse loop is therefore already built end-to-end: costume in through the front door → ordered kill inside → the riser stands up → walk either body to the door → burst → the building is breached and the siege/flush machinery takes over → the waiting horde pours in. No new mechanics beyond the compromised rule; this payoff should be a named PoC test case.

### 3.6 The break — permanent, and the end of being special (ruled)
- **Trigger:** pounce launch (§3.4). *(The only trigger — while costumed it cannot pound, go feral, or be released, so no other violence source exists.)*
- **Permanent.** No re-costuming, ever.
- **On break the unit becomes mechanically ordinary** — it stops being special entirely: `is_special` drops with the costume. Concretely, it is now contagion-eligible, releasable, feral-capable, herd-repellent, fear-countable, fill-targetable, inside-burst-capable, subject to `CalmBreach`, and included in every query that reads "zombies." It keeps its identity (selection, control-group membership, unit_uid) and is CALM at the moment of landing recovery — still your unit, just no longer a special one. One zombie in the roster that used to be pink; nothing else remembers.

### 3.7 Interactions inventory (for the implementer's checklist)
- **Contagion:** never ignites it while costumed (existing `is_special` guard); its own kill ignites *others* normally; post-break it ignites like anyone.
- **The Mark:** affects feral retargeting only → zero interaction while costumed; normal post-break.
- **Selection & prune:** always selection-worthy while costumed (never feral → `_prune_selection` never drops it). Post-break, normal rules.
- **Q/E select-all-calm (soft default, flag for playtest):** the costumed special is **excluded** from Q and E — it is a precious, deliberately-positioned unit, and a riser-roundup sweep must not yank the infiltrator out of the shelter it took two minutes to walk into. It remains reachable by click, box, and control group. Fallback if the exclusion confuses: include it and rely on player care.
- **Win/lose:** the special *human* counts as a human for the win condition; the special *zombie* (costumed or broken) counts as a zombie for the lose condition, as does its pending riser.
- **Hazards:** it is a zombie — mines/wire/stakes affect it normally (a hazard death of your infiltrator is the standing "costs you a body and nothing else").
- **F fast-forward, R restart, waypoint queues:** nothing special; it is a calm unit.

---

## 4. DETERMINISM AUDIT (§10)

Clean by construction. No RNG anywhere: the ordered kill is wholly player-driven; door transit is a physics-layer exemption; the break is a deterministic event (pounce launch); the compromised rule is a registry predicate ("any revealed living zombie inside the footprint") evaluated like every other cadenced check. The riser branch spawns by `special_type`, not by roll. Identical inputs, identical runs.

---

## 5. VISUAL LANGUAGE (placeholder art tier)

Distinct **at a glance, in-game and in-editor** (`@tool` preview shows the same read the game does) — per the standing requirement.

| Unit | Read |
|---|---|
| **Costume-special human** | Normal class body + class letter (it *is* its class), plus a **bright pink ring** and a **★ badge** where armed classes carry their letter stamp. Pink = the costume family's color, carried from v1. |
| **Costume Zombie (costumed)** | **Bright pink body** (v1's `COSTUMED_COLOR`, `(1.0, 0.4, 0.8)`) — unmistakably not zombie green, unmissable in a horde. |
| **Costume Zombie (broken)** | Standard zombie green from the launch frame. The break gets a **readable pop** (flash/scale beat — the sombrero flying off) so the reveal moment lands at horde scale. |
| **Ordered-kill telegraph** | The target wears the existing hunted/"targeted" ring while the order is live (reuse, not new grammar). |

Rendering home: on the units for now (the interim pattern), migrating with everything else in the Phase 5 `vision_renderer` rewrite.

---

## 6. NUMBERS

**Zero new §9 knobs — deliberate.** The ordered kill reuses `pounce_range` / flight / recovery; door transit reuses the door rules wholesale; the compromised rule reuses the breached-interior values; creation reuses `rise_time`. The only new data is the `special_type` export on the human and the `is_costumed` latch on the zombie. If playtests demand a dial (e.g. a reveal-radius shout, an ordered-kill leash), it gets proposed then — not pre-built.

---

## 7. PoC SCOPE, VALIDATION & TEST CASES

**In the slice (ruled):** the framework (§2) + the Costume Zombie (§3), one costume-special human (Civilian) in the §12 PoC level.

**New validation questions (append to the direction spec's seven at verdict time):**
8. Does the locate-and-kill hunt read as an objective — do players *go after* the special human unprompted, and does losing it to an escape sting the right amount?
9. Does the infiltration verb earn its slot — is walking the costume through the front door a plan players form on their own, and does the reveal moment land?

**Named test cases for the build (print concrete steps at implementation time, per rule 8):**
1. Costumed walk-through: fill never starts, fear never counts, fleeing humans path straight past it.
2. Door transit: through an intact door with no state change; barred by a locked (engaged) door; no burst on entry; a trailing normal zombie is stopped by the same door.
3. Ordered kill in the open: order → chase → lunge → break at launch → kill → score → contagion → victim rises.
4. Mid-flight save: a hot defender kills it during the 0.2s flight → victim survives, no kill, no score.
5. The Trojan horse end-to-end (§3.5): infiltrate intact shelter → interior kill → compromised behavior (panic by sight, no shell change) → riser → inside burst → flush into the waiting horde.
6. Creation & denial: a feral's kill of the special human still yields the special riser; the special human escaping loses the special and the end screen says so.
7. Break permanence: post-break it ignites by contagion, releases, herds fleers, and blocks a door for the exit filter.

---

## 8. OUT OF SCOPE / PARKED

- **The other 9 roster specials** — each needs its own re-audit against the v2 pillars before speccing (several can't pass as written: Ordnance's 50% rolls violate no-live-RNG; Headless's fog-reveal has no fog to reveal). The framework (§2) is written to receive them: one `special_type` each, one riser branch each.
- **Traffic Controller vs the Mark overlap** — stays parked with the specials re-audit.
- **Specials-nested-in-groups as the abilities replacement** — parked (Parked Register).
- **Multi-special interactions** beyond simple coexistence — nothing designed; nothing needed for one-per-level.
- **The Bitten** (trope record §3.2) — a future special using this framework's creation grammar; unchanged, still deep-pocket.
- **Kill-context denial of specials** (§2.4 note) — decide when that feature ships.

## 9. SOFT FLAGS (defaults chosen, playtest may flip them)

1. Mixed-selection RMB-on-human: special joins with the ordered kill (§3.4). Fallback: specials ignore it.
2. Q/E exclude the costumed special (§3.7). Fallback: include.
3. Compromised buildings drop from the flee exit set (§3.5). Fallback: stay in (humans "don't know"), accepting re-break churn at the door.
4. End-screen lost-special callout wording (§2.4).

---

**END OF SPEC**

*Next steps: Ben reviews → corrections folded in → build proposal (sequencing: the framework riser branch → the costumed exemption surface → door transit → the ordered kill → the compromised rule → visuals), one step at a time, propose-before-implementing throughout.*
