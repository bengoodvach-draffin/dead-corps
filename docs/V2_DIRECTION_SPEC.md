# DEAD CORPS — V2 DIRECTION SPEC: The Predator Pivot

**Version:** 2.0-draft4 (final review complete June 12, 2026 — pool = plain nearest, instant retarget on shared kills, rotation-gated radial front)
**Date:** June 12, 2026
**Status:** Design locked pending PoC validation. Supersedes core-loop sections of GDD v6.1 (Sections 3, 6, and parts of 11). GDD is NOT updated until the PoC validates this direction.
**Origin:** Playtest finding — the game played like Commandos with zombies ("ninja commando zombies"), while the single most engaging moment was sending five zombies into gunfire and watching the horde get thinned, not knowing if enough would survive. This spec rebuilds the core loop around that moment.

---

## 1. THE PIVOT IN ONE PARAGRAPH

Dead Corps v1 was a stealth-puzzle game: vision cones, patrol timing, waiting for windows. Dead Corps v2 is a predation game: **bodies are ammunition, detection is a cost not a fail state, and the player's skill is corralling, releasing, and combo-routing a frenzied horde.** Stealth grammar (cones, facing, swing arcs, alerts, morale psychology) is removed. The puzzle is attrition math and chase geometry, executed at speed.

---

## 2. DESIGN PILLARS

1. **Attrition is currency.** Losses are spending, not failure. Every wall has a body price.
2. **Setup is 1/3 of the game; the chase and the combo are 2/3.** Design decisions favor pursuit and momentum over planning and positioning.
3. **Command the calm, influence the storm.** The reserve is fully controllable; released zombies are not. Released is released — no recall, ever.
4. **Bias, not command.** Influence on ferals reorders their choices; it never moves a unit anywhere prey isn't.
5. **The frenzy chases what moves; what's frozen waits for deliberate collection.**
6. **Determinism in rules, suspense in execution.** Identical inputs produce identical runs. A human approached from the same vector reacts identically every playthrough. Per-class stats never change situationally. (See §10, Determinism engineering.)
7. **The frenzy ends when nothing in the encounter is left alive or everything has escaped.**

---

## 3. ZOMBIE SYSTEM

### 3.1 States
- **CALM** — full RTS control. Idle zombies shamble within a small leash (see 3.2).
- **FERAL** — autonomous hunting. Not selectable; excluded from box select and clicks; control-group recall (1–9) returns only the calm members of the group. Visually distinct tint (calm vs feral must read at a glance).

### 3.2 Idle shamble
Persistent behavior for ALL idle calm zombies: slow wander within `shamble_leash` (v0.34: 5px) of an anchor point, with a `shamble_pause` (v0.34: 3.0s, ±50% deterministic variance) dwell at each wander point so the crowd isn't in constant motion. Anchor updates whenever a move order completes. **Deterministic:** wander pattern and dwell variance derived from a hash of unit ID (no live RNG). Leash, speed, and pause are config-tunable. *(Retuned from the original 25px/20px-per-s during 2.1 playtest — the tight leash + dwell reads as a restless idle, not a roaming crowd.)*

### 3.3 Frenzy triggers (exactly two)
1. **Release command** (player; see §5).
2. **Violence contagion:** a *kill* (zombie kills human) or a *zombie death by gunfire* ignites all idle zombies within `contagion_radius` (v0: 150px). Consequence: the reserve requires standoff distance from any violence, theirs or yours. A fill line crawling toward a parked horde is the visible "move or commit" warning.
   - **Seeding (added 2026-06-17):** a *gunfire death* seeds the woken zombies **at the shooter** — a gunshot draws the nearby horde onto the gunman ("you shot us, we're coming for you"). Without this they wake targetless and instantly calm, since a ranged shooter is usually outside the local scan radius. A *zombie-kills-human* contagion wakes them **targetless** (prey is right there at the kill — normal retarget finds it). Either way, after igniting, normal §3.4 feral rules + peel-off govern, so they converge on the shooter but still eat closer prey en route (mechanically identical to a player release aimed at the shooter).

NOT triggers: proximity to humans, being aimed at (fill in progress), being near fleeing humans.

### 3.4 Feral behavior
*(Post-playtest model, v0.34.0 — supersedes the original "pursue until kill, then nearest-wins retarget." The release is a **shove** that aims the horde; ferals then hunt opportunistically — first-come-first-serve, distributed, and directional.)*

1. **Movement-vector targeting (the "bullet").** Every target choice — seeding, peeling, retargeting — ranks candidates by an *along-the-path* score, not raw distance: `score = forward + perp × feral_offaxis_penalty`, where `forward` is the candidate's distance along the feral's heading and `perp` its perpendicular offset from that heading (`feral_offaxis_penalty` v0: 2.0 — the bullet-vs-splay dial). Humans **behind** the heading are rejected — hard-skipped on a peel, and given a large but finite last-resort penalty on a post-kill retarget so a hemmed-in feral still engages rather than calming. Effect: the horde drives up the *centre* of a block and splays outward only as the central column clears, and never runs backward out of the swarm. Heading = the feral's current velocity; at release it is feral→click.
2. **Continuous peel-off (opportunistic retarget).** A feral does **not** blindly commit to its target until the kill. On a `feral_divert_interval` (v0: 0.25s) cadence it re-scans within `chain_scan_radius` (250px, LOS) for a **fresh** straggler — alive, not pounce-claimed, and **not already pursued by another feral** — and peels onto it if its path-score is meaningfully better than the current target's (by factor `feral_divert_hysteresis`, v0: 0.8; the hysteresis kills target-jitter). Because a peeled straggler is immediately *pursued* (claimed), every other feral's scan skips it: the nearest feral peels off to handle each straggler while the bulk keeps its momentum. **Peel = one zombie per straggler**, emergent from the pursuit claim. *(This reverses the original "pursued and unpursued treated identically / nearest wins" call — the un-pursued-first preference is exactly what produces the peel-off feel. It applies to the mid-pursuit peel only, so predictability holds.)*
3. **On kill / target loss, retarget** among the **local scan** (living humans within 250px with LOS, includes cowering) ∪ the **hunt pool** {humans pursued by any feral} ∪ {FLEEING humans anywhere} — ranked by the **same path-score** so momentum carries through the kill. Target loss = the kill lands, or the target enters an escape zone (pursuer halts at the boundary). Cowering humans are local-scan only — never in the global pool ("what's frozen waits for deliberate collection"). **Shared kills:** if two ferals chase the same human and one lands the pounce, the other **instantly retargets** per this rule — no idle beat. **Mark influence** (§5.4, unbuilt) sits on top of this — player intent reorders the menu.
4. **No target + empty pool → instant calm.** Control returns on the spot. No wind-down timer (animation sells it).
5. **No timers anywhere in the frenzy.** One engineering failsafe (not design fiction), defined as *no tangible progress*: a feral whose distance-to-target has not decreased by at least `failsafe_min_progress` (v0: 40px) over a rolling `failsafe_window` (v0: 2.0s) drops the target and calms. Same detector pattern as cowering — robust to jitter and orbiting. Currently doubles as the stopgap for the no-pursuit-pathing gap (ferals move straight-line and can wedge on obstacles); will rarely fire once pursuit pathing lands.

Pocket isolation is emergent: the pool only ever contains humans being hunted or fleeing, and FLEEING humans only exist where violence already happened. The frenzy reaches exactly as far as the consequences of the player's actions. The only way chaos jumps to a quiet area is a runner physically dragging pursuit there — the sanctioned chaos vector.

### 3.5 Melee resolution: the Pounce
The leap survives as the kill delivery. There is no HP, no damage values, no attack cooldowns, no grapple state, no escape-from-pin.

1. Feral within `pounce_range` (v0: 40px) of its target → lunges.
2. **Kill registers at landing (confirmed).** A zombie shot mid-flight (~0.2s window) does NOT complete the kill — the human survives by a hair. Once landed, the human is dead regardless of what happens to the zombie.
3. **Recovery:** 1.0s stationary on the corpse, fully vulnerable to fills. Killing deep inside a fill zone has a price.
4. Retarget per 3.4.

**Pounce exclusion:** a human targeted by an in-flight pounce is excluded from all other ferals' retargeting. This single rule replaces all attacker caps and naturally spreads the horde across prey.

### 3.6 Converts (risers)
- A killed human rises **where they died** after `rise_time` — **v0: 2.5s measured from the pounce landing** (≈ the killer's 1.0s recovery plus ~1.5s after it moves on). Anchoring to the kill instant rather than "when the zombie leaves" keeps it simple and deterministic — no dependency on the killer's subsequent behavior; if the killer lingers, the corpse rises under it regardless. Tunable **at the level config**, not per-unit.
- Risers rise **CALM** and are governed by normal rules from that moment — contagion may immediately grab them if violence is still nearby; otherwise they idle-shamble where they stand. No auto-rally.
- Corpses and mid-rise bodies are not valid fill targets. Fully risen zombies count toward humans' fear counts.
- Risers count toward the zombie total for the lose condition (no false loss while corpses are about to stand).

### 3.7 Specials
**Specials never go feral** — always player-controlled, even inside a frenzy. They are the player's embedded agents in the storm. **Excluded from the PoC entirely** (no special code paths in the new systems yet). Full re-audit post-PoC (see Parked Register), including the Traffic Controller vs Mark overlap and the `is_costumed` fear-count exemption.

---

## 4. HUMAN SYSTEM

### 4.1 One mechanism for every human: the Fill
- **360° detection.** Per-class awareness range (a circle), LOS-gated — buildings and LOS-blocking obstacles cut it.
- **The fill is a radial front, not a target lock** (reconceived during final review to answer the bait exploit — see note below). While any zombie is in range, a threat front expands outward from the human at the class fill speed. **It fires at the first zombie the front reaches** (front radius ≥ that zombie's current distance, LOS checked at fire time). On firing: that zombie dies, the front resets to zero and grows again.
- Distance is still time: close zombies are reached sooner; a charging zombie compresses its own clock. The visible fill line points at the zombie the front will reach first (the nearest) — rendering is unchanged.
- **Decay:** the front decays (~2× fill speed back toward zero) only when NO zombie is in range at all. While any threat is in range the gun stays hot — it never decays and never resets except by firing. (A zombie in range but with no clear lane keeps the gun hot but produces no shot — see LOS rule below.)
- **Humans block line of sight (added 2026-06-17, extends the §4.1 LOS rule).** An armed human cannot fire *through* other humans — the fire/LOS check is blocked by the environment **and** by other (living, upright) humans, but not by zombies (the target is the nearest, so a zombie can never screen it; excluding zombies is just so the ray doesn't trip on the target itself). Consequence: a clumped knot of defenders is *less* lethal per head — only those with a clear lane fire, so approach angle and where defenders stand matter, and herding that bunches humans up weakens their return fire. Resolution: the human fires at the nearest zombie that is both reached by the front **and** has a clear lane; if the nearest is screened by a friendly it targets the next-nearest with a clear lane; if none are clear the gun holds hot (no shot) until a lane opens. Corpses and cowering (dropped) humans do **not** block; fleeing humans (upright) **do**. The fear count (§4.2) stays non-LOS. *(Lowers a cluster's effective firepower — feeds the Phase 6 sacred-ratio sweep.)*
- **Why this kills the bait:** under a target-lock model, one far zombie pins the human's aim while chargers close for free. Under the front model, the bait *raises the front* — and any charger entering inside the front's current radius gets shot almost immediately (the gun was already hot). Baiting now donates the defender a fast first kill. The peek exploit dies the same way: ducking back into cover doesn't cool a hot gun while other zombies remain visible, and re-emerging inside the front radius is near-instant death.
- **On completion, the class response:** armed classes **fire** as above; **civilians flee** (their "front" is a pure reaction clock — first zombie it reaches triggers the rout).
- **Rotation gates the shot:** when the front reaches a zombie, the human must rotate to face it before firing — turn at `turn_speed` (v0: 360°/s) until within a small facing tolerance (~15°), then the shot lands. Minimal delay if the new threat is vaguely in the same direction; a meaningful beat if it's behind them. The front **holds** (no reset, no decay) during the rotation. Consequence: attacking from two opposed angles buys a small real edge — facing's one surviving piece of gameplay meaning.
- Armed humans visually face the nearest zombie between shots.

### 4.2 Breaking: the fear radius
Independent of the fill, checked continuously:
- If the count of zombies — **any state: calm, feral, or risen** — within the global `fear_radius` (v0: 250px) exceeds the class threshold N, the human **flees** after a short reaction beat (`fear_reaction`, v0: 0.3s). **The break is committed the instant the threshold trips:** the fill cancels immediately and the fill line disappears — no shot can land during the reaction beat. The beat is animation time, not a last-stand window.
- **LOS gating (revised 2026-06-17):** the count is **building-LOS gated** — a solid building/wall blocks dread, so a zombie behind one doesn't count; one in the open or emerging from cover within the radius does. Humans do **not** block fear (it's dread, not a shot). (Supersedes the earlier "fear count is non-LOS" call — through-a-building breaks read as a bug.)
- Civilians: N = 0 — any zombie inside their fear radius breaks them. Civilians therefore have two flee paths: the fill (seen at distance) and the fear count (ambushed up close, e.g., a zombie emerging from behind cover). Both kept deliberately.

### 4.3 Fleeing = permanent rout
- A broken human paths to the **nearest escape zone** — no LOS requirement (they live here; they know the exits). Flee vectors bend the route around zombies — this is what makes humans herdable.
- No shooting while fleeing. No recovery, ever. Broken is broken.

### 4.4 Cornered: COWER
- Detection by **net displacement** (robust to ping-pong jitter): a FLEEING human whose position has net-moved less than `cower_min_displacement` (v0: 40px) over a rolling `cower_window` (v0: 1.2s) enters COWER.
- COWER is permanent and classless: drops, screams, no movement, no fill. Dies to a normal pounce like anyone else (no special touch-convert mechanic). Its kill pays the **terror bonus** (§6).
- Multiple humans fleeing into the same dead end huddle together with zero extra rules.

### 4.5 Classes (PoC roster)
Civilian, Militia, Police, GI. **Spec Ops cut** (future: timed-reinforcement concept, parked). Roster flagged as possibly shrinking further for simplicity.

| Class | Awareness | Fill speed | Threshold N | On fill completion |
|---|---|---|---|---|
| Civilian | 400px | reaction only (~0.75s fixed) | 0 | Flee |
| Militia | 450px | 250 px/s | 1 | Fire |
| Police | 450px | 300 px/s | 2 | Fire |
| GI | 550px | 450 px/s | 3 | Fire |

GI is breakable (decided — momentum preserved; no unbreakable walls in v2). All values config-tunable.

### 4.6 Properties that follow (not rules — consequences)
- **The critical-distance law:** below a distance set by fill speed vs zombie speed (~50–120px range depending on class), the zombie wins the race — the pounce lands before the fill completes. Defender placement near blind corners is therefore a deliberate level-design lever.
- **Kill counts emerge from physics:** how many zombies a defender kills per crossing = crossing time ÷ fill cycles. Nobody hand-authors kill tables anymore.
- **Two engagement regimes:** *overwhelm* (wave well above threshold — defender breaks early, cheap in bodies, but produces a runner to chase) vs *grind* (wave near threshold — defender stands and kills until pounced, expensive but dies in place). Both real strategies with different costs.
- Lone zombies always die to armed humans; trickling is donation; waves are mandatory.

### 4.7 What patrols mean now
Patrol routes survive purely as **positioning over time** — where humans are when you strike, who is near whom for fear counts and chain spacing. All facing features (per-waypoint facing, swing) are dead. Formation squad patrols survive as positioning tools (irrelevant to PoC slice).

---

## 5. PLAYER CONTROLS

### 5.1 Input sheet

| Input | Verb |
|---|---|
| LMB / drag | Select (calm zombies only) |
| **LMB on a human** | Toggle **fill-line inspect** — emphasizes that human's fill line (brighter/thicker) for detailed reading. Preserves current zombie selection. Click again to clear; click another human to move it. |
| RMB on ground (zombies selected) | Move (calm) |
| RMB on a human (zombies selected) | **RELEASE** — cursor telegraphs on hover |
| RMB on human or ground (**nothing selected**) | Place / move the **Mark** |
| RMB on the Mark (nothing selected) | Clear the Mark |
| Ctrl+1–9 / 1–9 | Control groups (recall calm members only) |
| R | Restart |

Release is unmodified and uncancelable — its weight is carried by consequence, not input friction. Pre-click telegraphing is the misclick defense: **as built (v0.34.0), the single human under the cursor gets a "release here" ring** while releasable zombies are selected — no cursor swap, and deliberately *no* cluster preview (reading the 300px reach is player skill). A faint "targeted" ring also marks any human a feral is currently hunting (driven by the hunt pool), so the player can read the engagement. Both rings are drawn by the Human itself for now — interim home; they move to the `vision_renderer` readability layer in §7. Shelved fallback if playtests produce rage-misclicks: a ~100ms hover debounce before release registers.

### 5.2 Release semantics
- All selected zombies ignite FERAL.
- **Seeding (bullet-vector, v0.34.0):** all humans within `release_cluster_radius` (v0: 300px) of the click are candidates. Each feral's heading is feral→click. First pass assigns **one feral per human** greedily by **path-score** (§3.4 rule 1 — humans along a feral's path beat off-axis ones); remaining ferals distribute by least-loaded, path-score tiebreak. No per-human cap (pounce-exclusion prevents terminal pile-ups). *(Superseded the original raw-nearest-pairs seeding, which splayed the horde evenly across the front rank instead of driving in.)*
- After seeding, §3.4 feral rules govern — the continuous peel-off takes over within a frame, so seeding sets the initial spear and the hunt does the rest.
- **One attack verb only.** There is no separate "polite attack" — surgical strikes emerge from context: release one zombie at an isolated straggler and it calms the instant the pool comes up empty after the kill. The environment decides whether a click was a scalpel or an avalanche.

### 5.3 In-storm verbs (the spectator-problem answer)
"You command the calm, you influence the storm." During a frenzy the player: **reinforces** (releases fresh waves/risers into the fight), **intercepts** (places reserves ahead of runners), **herds** (flee vectors avoid zombies — every calm placement bends the routes of everyone running; the player controls the geometry of fear and the hunt follows it), and **marks**. Specials add **deploy** post-PoC.

### 5.4 The Mark
- One active mark, on a human or a coordinate. Placed/moved/cleared freely (see input sheet).
- **Scope rule (decided):** at retarget, a feral prefers the Mark's prey — the marked human, or the nearest valid human within `mark_radius` (v0: 300px) of a marked coordinate — **unless another human is strictly closer to that feral AND within the 250px local scan.** Genuinely closer prey still wins organically; the Mark wins everything else, including ties of attention at range. No weighting math — pure priority with a proximity override.
- Consequence: a marked human 200px from a feral IS taken over an unmarked human at 220px (no closer human exists). A marked human at 400px loses to an unmarked one at 150px (closer and in scan). Predictable both ways.
- **Never interrupts an active pursuit. Zero effect if no prey is near it** — the Mark reorders the menu; it never moves a zombie anywhere prey isn't.
- Affects feral retargeting only. Reserve commands, release seeding, and contagion ignore it.
- Fiction: the pack instinct's attention — a pointed hunger, not an order.

---

## 6. SCORING

### 6.1 Combo (pot model)
*(Revised 2026-06-17 to a V2 TIERED-base model. The original flat `kill_base`-per-kill made the window worthless for score — only the burst multiplier paid, so kills 1.5–4s apart banked the same as kills strung far apart. Tiered base makes chain LENGTH pay, so the window now drives score; the multiplier stays the rare, high-impact lever.)*
- Each kill adds a **TIERED base** to the combo pot: **`kill_base × ceil(chain_position / combo_tier_size)`** (v0: 10 / 5 → kills 1–5 worth 10 each, 6–10 worth 20, 11–15 worth 30, …). Longer chains pay progressively more per kill. Each kill also refreshes the **combo window** (v0: 4s, flat, from last kill).
- **Multiplier** (per chain, starts ×1, kept rare): a kill within **`burst_window` (v0: 1.5s)** of the previous → **+1**; a **terror kill** (victim was COWERING) → **+1 more, stacks** (terror inside the burst window = +2).
- **Window expires → level total += pot × multiplier; pot resets to 0, multiplier resets to 1.**
- Property (chosen deliberately): the multiplier held when the combo dies applies to the whole pot — late bursts retroactively inflate earlier kills in the chain. Maximum greed.
- Window = forgiveness; **tiered base = the chain-length reward; multiplier = greed/simultaneity.** Keeping the chain alive is now strictly better than stringing kills out (length escalates the base), and corralling-for-simultaneity stacks the multiplier on top.
- **Scored event = pounce kills only.** A zombie's death by gunfire is the player's own loss, not scored. Score lands at the kill, not the rise.
- Rejected on record: **flat `kill_base` per kill** (the window did nothing for score — replaced by tiered base); freeze-while-hunting (rewarded continuity over intensity; enabled slow-rolling); tier-decaying windows (shelved).

### 6.2 Other scoring
- **Survivor counting:** kept as an **end-screen stat only** ("4 escaped" = lost converts = the gap to a full-clear mastery run). Worth zero points. The old 25pts-per-surviving-zombie rule is dead — it punished the core fantasy.
- Score lands at the **kill**, not the rise.
- Full scoring balance pass deferred post-PoC; all values config.

---

## 7. RENDERING / UI (vision_renderer.gd is a rewrite)

- **Fill lines:** thin line from human toward current fill target, colored portion advancing — visible whenever a fill is active. Replaces all vision cones. At horde scale, lines read; wedges smear.
- **LMB inspect** (see §5.1): emphasized rendering for one chosen human's fill line.
- **Calm vs feral tint** on zombies; riser state readable.
- **Mark decal** on ground / glow on marked human.
- **Cower indicator** (pose + audio scream).
- **Combo meter:** pot, multiplier, and draining window — visible and readable; burst increments should pop.
- Deleted: cones, dual-zone arcs, click-to-pin (superseded by LMB inspect), V-key all-cones mode, facing lines, swing/facing editor visuals (patrol path visuals survive).

---

## 8. WIN / LOSE

- **Win:** no humans remain on the map — every human dead/converted or escaped. Cowering humans are neither: they must be collected (pounced) to end the level. The closing sweep of stored cowerers — harvesting terror bonuses on the way out — is the natural final beat.
- **Lose:** zombie total reaches zero, **with risers counting toward the total.**
- **Escape zones:** hard boundary for ALL zombies (feral and calm) — nobody dies, nobody enters. A pursued human entering the zone = target lost; pursuers halt at the rim. Consequence (accepted): the zone mouth is pounce-range ambush ground — the final sprint is a gauntlet.
- End screen (win or lose): combo-accumulated score, **level timer**, and escaped stat. No survivor points. (Timer is display-only for the PoC; possible score tie-in later — parked.)

---

## 9. NUMBERS v0.1

All values live in **`level_config.gd`** — a NEW per-level @tool node (name checked against the scripts inventory; no collision) following the `level_bounds.gd` pattern: placed in each level scene, writes values on `_ready()`. One place to tune a level; different levels can feel different for free.

| Knob | v0.1 |
|---|---|
| Zombie speed / human flee speed | 200 / 90 px/s |
| Awareness: Civ / Mil / Pol / GI | 400 / 450 / 450 / 550 px |
| Fill speed: Mil / Pol / GI | 250 / 300 / 450 px/s |
| Civilian reaction | 0.75 s |
| Threshold N: Civ / Mil / Pol / GI | 0 / 1 / 2 / 3 |
| Fear radius (global) | 250 px |
| Fear reaction beat | 0.3 s |
| Contagion radius | 150 px |
| Chain scan radius (= peel radius) | 250 px |
| Feral divert interval / hysteresis | 0.25 s / 0.8 |
| Feral off-axis penalty (bullet ↔ splay) | 2.0 |
| Pounce range / recovery / flight time | 40 px / 1.0 s / 0.2 s |
| Rise time (from pounce landing) | 2.5 s |
| Cower: min displacement / window | 40 px / 2.0 s |
| Combo: window / burst / kill base / tier size | 4 s / 1.5 s / 10 pts / 5 kills |
| Flee herding: repel radius / strength / exit-threat bias | 180 px / 1.5 / 1.5 |
| Release cluster radius | 300 px |
| Mark radius (coordinate marks) | 300 px |
| Shamble leash / speed / pause | 5 px / 7 px/s / 3.0 s (±50%) |
| Fill front decay (only when no zombie visible) | 2× fill speed |
| Turn speed / facing tolerance | 360°/s / 15° |
| Failsafe: min progress / window | 40 px / 2.0 s |

**THE SACRED RATIO: fill speed vs zombie speed.** It sets the critical pounce distance, emergent kill counts, and crossing tolls — everything. The slice's first tuning job: sweep this ratio until a GI position kills ~3–4 of a charging wave. All v0.1 values are deliberately rough.

---

## 10. DETERMINISM ENGINEERING (hard constraint)

Identical inputs must produce identical runs. Concretely:
- **No live RNG anywhere.** Idle shamble and formation move-jitter become hash-based (unit ID + anchor), organic-looking but replay-identical.
- Flee vectors, fill targeting, retarget selection: pure deterministic math with **fixed evaluation/iteration order** (e.g., stable unit ordering, not dictionary iteration).
- A human approached from the same vector at the same time reacts identically every run.

---

## 11. DEPRECATION AUDIT (what the PoC disables/removes)

| System | Fate |
|---|---|
| Morale drain system (tables, sighting drain, ally events, recovery) | DEAD — fear radius + threshold replaces it |
| Detection alert (5s cone timer) + high urgency alert system | DEAD — the fill loop IS the reaction; fear radius IS the panic |
| Tunnel Vision state | CUT (GIs flee like everyone — momentum preserved) |
| Spec Ops defender class | CUT (parked as future timed reinforcement) |
| Vision cones, dual-zone arcs, click-to-pin, V-key, facing lines | DEAD — fill lines + LMB inspect replace |
| Sentry facing gameplay, swing arcs, per-waypoint facing/swing | DEAD (waypoints + pauses survive as positioning) |
| Auto-pursuit remnants, smart retargeting 50% penalty | DEAD |
| Leap (as chase speed-boost) | REFRAMED as the Pounce (kill delivery) |
| HP / damage / attack cooldowns / GRAPPLED / grapple escape | DEAD — pounce model replaces all melee |
| Old flee (150px detect, LOS-gated zone seek, flee-vector recompute loops) | REPLACED by break → permanent rout; cower replaces the ping-pong jitter bug |
| Group resolver max-2 cap, overflow-to-click | REPLACED by one-per-human seeding + pounce exclusion |
| Escape zone kills zombies | REPLACED by hard boundary for all zombies |
| 25pts/survivor scoring, old time bonuses | DEAD — combo pot model replaces (time bonuses re-evaluated post-PoC) |
| 5s GameManager incubation pipeline | REPLACED by rise-in-place at level-config `rise_time` |
| BOID cohesion (already disabled), zombie vision arcs (already removed) | Stay dead |
| BOID separation, NavigationAgent2D pathfinding, selection, control groups, WorldBounds/level_bounds, buildings/LOS | SURVIVE |
| Fat Zombie, Costume Zombie code paths | EXCLUDED from PoC (re-audit post-validation) |

Files with major work: `human.gd` (rewrite of behavior core), `zombie.gd` (feral states + pounce), `vision_renderer.gd` (rewrite), `selection_manager.gd` (release/Mark/inspect), `game_manager.gd` (rise pipeline, win/lose, score), `escape_zone.gd` (boundary), `unit.gd` (speeds, determinism), NEW `level_config.gd`.

---

## 12. PoC VALIDATION SLICE

**Built 2D-first** in the current codebase. 3D migration waits until the pivot validates — and inherits the simplification (far less to port).

**Roster:** Civilian, Militia, Police, GI. No specials, no Spec Ops, no pressure systems.

**Level needs:** 2–3 civilian clusters separated by gaps larger than the chain scan radius (so frenzies burn out between them); one armed position (police pair + a GI); an escape zone; at least one dead-end for cornering/huddles; open staging ground for the reserve (standoff distance must be possible).

**Milestones:** M1 — core loop without the Mark (one less variable; feel what it's missing). M2 — add the Mark + LMB inspect.

**Validation questions:**
1. Does release feel like a weighty decision (and never an accident)?
2. Does the thrash read on screen — can you follow who's feral, who's filling, who's breaking?
3. Does the chase carry its 2/3 — is pursuit/interception/herding the fun, not just the cleanup?
4. Does the combo create greed — do players corral for bursts unprompted?
5. **Did anyone loiter?** (Pressure systems are parked, so the slice level is static and waiting is free. If playtesters wait, evacuation un-parks first.)
6. Does the Mark earn its slot (M2)?
7. Sacred-ratio sweep: do emergent kill counts land near Militia 1 / Police 2 / GI 3–4?

---

## 13. PARKED REGISTER (post-PoC)

Pressure systems wholesale (noise propagation via radii, civilian evacuation, hardening/hardpoints, killable clocks, radio operator, Spec Ops reinforcement squads, alert-changes-position-never-power rule), convoy escorts, specials re-audit (Traffic Controller vs Mark overlap; `is_costumed` fear exemption; specials-as-embedded-agents framing; specials-nested-in-groups as the abilities replacement), full scoring balance + time bonuses, fear-fill texture ("race of two fills"), fleeing-ally +1 fear patch, tier-decaying combo window, smooth Mark weighting (replaced by the closer-within-scan override rule, §5.4), contagion-as-difficulty-modifier, release hover-debounce, roster reduction, militia-arming-civilians, snipers, building transformation system, remaining 9 specials, 3D migration.

---

## 14. AMBIGUITIES & FLAGGED ASSUMPTIONS

### Resolved (June 12, 2026 review)
- **Mid-flight pounce death = no kill — CONFIRMED.** Kill registers at landing; a zombie shot during flight does not complete the kill.
- **Terror + burst stacking — CONFIRMED.** A terror kill within the burst window grants +2 multiplier total.
- **Mark vs nearby prey — RULED.** A marked human is taken unless another human is strictly closer to the feral AND within the 250px local scan (see §5.4). Replaces the earlier hard "local scan always wins" rule; the weighting math is removed entirely.

### Still soft
1. **`fear_reaction` beat (0.3s) was never discussed** — a small delay before fear-triggered flee, added for animation/readability. Could be 0 (instant). Tunable either way.
2. **Civilian dual flee path** (fill at distance + fear count up close) — kept both deliberately so ambushes from cover still trigger instant panic. Slight redundancy, accepted.
3. **Fill speeds vs the new larger ranges are rough guesses.** The sacred-ratio sweep is expected to move them substantially.
4. **Shamble speed (~20px/s) was never discussed** — placeholder, config.
5. **Human non-flee movement speeds** (old patrol 50px/s etc.) untouched by this spec — revisit if patrols feature in the slice.
6. **Pool with zero distance cap** — a newly free feral can sprint cross-map after a distant fleer. Decided (pursue until caught or escaped), but worth watching in the slice for "my horde wandered off" feel; the Mark is the counter-tool.
7. **GDD update deferred** — per working convention, the GDD is only updated when the feature set is confirmed; this spec stands alone until the PoC validates.

---

**END OF SPEC**

*Next steps: Ben reviews → corrections folded in → PoC build plan (implementation sequencing in Claude Code) → slice → sacred-ratio sweep → verdict on the pivot.*
