# Dead Corps — V2 PoC Build Plan

**Date:** June 12, 2026 · **Basis:** `V2_DIRECTION_SPEC.md` (2.0-draft4) · **Branch:** `v2-poc`
**Status:** Proposed sequencing for Ben's review. Each step still gets a short propose/confirm at execution time per the working rules — this document fixes the *order* and the *scope boundaries*, not the line-level approach.
**Progress (v0.30.0):** Phase 0 ✅ and Phase 1 ✅ **complete** (1.6 vision-renderer stub was folded into 1.1). The branch is the sterile sandbox. **Next: Phase 2 — predation core.**

The goal of the ordering: the game stays **bootable and manually testable after every step**, dependencies are built before their dependents, and the demolition of v1 systems happens in one contained band rather than bleeding through the whole build.

---

## Ground rules on this branch

- **`main` is the v1 prototype; this branch is the pivot.** CLAUDE.md rule 4 (backwards compatibility with existing levels/scenes) is deliberately suspended here — v2 breaks v1 levels by design. Every other working rule applies unchanged, especially the parse gate (`tools/check.ps1`) after every `.gd` edit.
- **Determinism is a per-step acceptance criterion, not a final pass** (spec §10). Concretely, every step must: use no live RNG (`randf`/`randi`/`shuffle`/random timer offsets); take neighbour/unit lists only from the Phase-0 registry (which returns stable-ordered results); key any staggering/bucketing off the unit's stable ID; define all timing in seconds, never frames.
- **Specials are excluded but must still parse.** `fat_zombie.gd` / `costume_zombie.gd` extend `Zombie` and reference systems Phase 1 deletes. Minimal-patch them so the parse gate stays green; they are non-functional on this branch and get their full re-audit post-PoC (spec Parked Register).
- **Don't gold-plate 2D presentation.** The CODEBASE_REVIEW Stage-E guidance applies double here: fill lines, tints, and the combo meter should be the cheapest rendering that reads clearly. All of it is rewritten in 3D if the pivot validates.

---

## Phase 0 — Foundations (additive; v1 still runs after this phase) ✅ DONE

- **0.1 `level_config.gd`** — NEW `@tool` node, `level_bounds.gd` pattern: placed per level, writes all spec-§9 knobs on `_ready()` into one readable place (autoload-style static access or group lookup — propose at execution). Every later step reads its numbers from here; nothing hardcodes a tunable.
- **0.2 Unit registry + neighbour queries in `GameManager`** — cached `living_zombies()` / `living_humans()` arrays maintained by the existing registration/death signals, plus `neighbours_within(pos, radius, team)` returning results in **stable unit-ID order** (monotonic `unit_uid` assigned at registration). Internals are a naive O(n) scan — fine at PoC counts; the API is the contract (see Performance tie-in below — a spatial hash can drop in behind it later, invisible to callers).
- **0.3 Determinism utilities** — hash-based per-unit jitter helper (`hash(unit_uid, anchor)` → deterministic wander offsets, used by shamble in 2.1), and a one-time audit/grep of surviving code paths for live RNG.

*Test checkpoint: v1 game still boots and plays; registry counts match the debug overlay.*

---

## Phase 1 — Demolition (one contained band; "dumb but bootable" at the end) ✅ DONE

Strip per the spec-§11 audit. Sequenced so each commit passes the parse gate; accept that between 1.1 and the end of Phase 2 the game is a sterile sandbox (units move, nobody fights).

- **1.1 `human.gd`** — delete morale, both alert systems, tunnel vision, dual-zone vision, GRAPPLED, the aim-timer shooting model, and the old flee. Surviving skeleton: IDLE + patrol (LOOP/PING_PONG, waypoint pauses — facing/swing features deleted) + DEAD. This is most of the 2,854 lines; expect the file to shrink dramatically.
- **1.2 `zombie.gd`** — delete leap-as-speed-boost, melee/HP combat, the 2-attacker gate, the post-kill continuation scan, smart-retarget penalty. Skeleton: IDLE/MOVING/DEAD.
- **1.3 `unit.gd`** — remove HP/damage/health-bar plumbing (alive/dead boolean remains); migrate BOID separation/alignment onto registry queries, fixing the documented local-`position` violation to `global_position` while in there (IMPLEMENTER_GUIDE invariant — the registry is global-space).
- **1.4 `game_manager.gd` + `escape_zone.gd`** — delete the 5s incubation pipeline and old scoring; escape zone stops killing zombies and becomes a hard boundary for them (humans still escape).
- **1.5 `selection_manager.gd`** — delete `_resolve_group_engagement()` and the overflow/cap machinery; selection, move orders, and control groups survive.
- **1.6 `vision_renderer.gd`** — stub (cones/arcs/facing/V-key/click-to-pin all dead). Rewritten in 3.1/5.1.
- **1.7 Specials minimal-patch** so they parse (see ground rules).

*Test checkpoint: boot a sandbox level — select/move zombies, humans patrol, escape zone blocks zombies, zero errors.*

---

## Phase 2 — Predation core (zombie side)

- **2.1 Idle shamble** — all idle calm zombies wander within `shamble_leash` of their anchor; anchor updates on move-order completion; deterministic via 0.3's hash jitter.
- **2.2 FERAL + the Pounce (against unarmed humans)** — FERAL state, pursuit, lunge at `pounce_range`, **kill registers at landing** (a mid-flight death cancels the kill — define the flight window in seconds), 1.0s recovery, **pounce exclusion** (an in-flight target is invisible to all other ferals' retargeting). Includes a *minimal* release (RMB-on-human → selected zombies ignite, nearest seeding) purely so ferals can be triggered for testing.
- **2.3 Retargeting + the hunt pool** — local 250px LOS scan ∪ pool ({pursued} ∪ {FLEEING anywhere}); plain nearest wins; shared-kill instant retarget; cowering humans local-scan-only; **no target + empty pool → instant calm on the spot**; the no-progress failsafe (40px / 2.0s rolling window, same detector pattern as cower).
- **2.4 Release proper** — full seeding (`release_cluster_radius` candidates, one-per-human nearest-pairs first pass, remainder distributed evenly), ferals excluded from selection/box/clicks, control groups recall calm members only, calm/feral tint, cursor telegraph + target highlight on hover.
- **2.5 Contagion** — a kill or a zombie gunfire-death ignites idle zombies within `contagion_radius`. (Gunfire deaths don't exist until 3.1; wire the kill half now, confirm the gunfire half in Phase 3.)
- **2.6 Risers** — killed humans rise in place, CALM, `rise_time` from pounce landing; corpses/mid-rise invalid as fill targets (enforced in 3.1); risers count toward the lose-condition zombie total and toward fear counts.

*Test checkpoint: release a horde on unarmed humans — watch seeding spread, pounce exclusion fan the pack out, kills convert, ferals calm when the pocket is cleared, contagion ignite a parked reserve that's too close.*

---

## Phase 3 — Defense (human side)

- **3.1 The radial fill front (armed classes)** — 360° LOS-gated awareness circle; front expands at class fill speed while any zombie is in range; fires at the first zombie the front reaches (LOS checked at fire time); reset-on-fire; decay (2× speed) only when no zombie is visible; **rotation gates the shot** (`turn_speed`, ~15° tolerance; front holds during rotation); face nearest zombie between shots. **Ships with its debug fill-line rendering** — this system cannot be tuned blind. Zombie death by gunfire feeds contagion (closes 2.5).
- **3.2 Civilian variant** — fill is a pure reaction clock (~0.75s); completion = flee, not fire.
- **3.3 Fear radius + the break** — continuous count of zombies (any state) within global `fear_radius`; over class threshold N → committed break (fill cancels instantly, line vanishes, no shot can land), `fear_reaction` beat, then flee. Civilians N=0 (their second, ambush flee path — deliberate).
- **3.4 Permanent rout + herding** — broken humans path to the **nearest** escape zone (no LOS requirement); flee vectors bend around zombies — this is the herding mechanic, treat it as gameplay-critical, not pathing polish. Escape-zone entry = target lost; pursuers halt at the rim. No shooting while fleeing; no recovery ever.
- **3.5 COWER** — net-displacement detector (40px / 1.2s rolling) on FLEEING humans; permanent, classless, no fill; dies to a normal pounce; flags the kill for the terror bonus (consumed in 4.2).

*Test checkpoint: the spec's two engagement regimes — overwhelm (wave over threshold → early break → runner) vs grind (wave near threshold → stands and kills until pounced); verify the critical-distance race (a zombie inside ~50–120px wins); verify baiting donates the defender a fast kill (hot-gun property); corner a fleer into the dead end → cower.*

---

## Phase 4 — Loop closure

- **4.1 Win/lose (spec §8)** — win: no humans on the map (cowerers must be collected); lose: zombie total zero, risers counting.
- **4.2 Combo scoring + end screen** — pot model (`kill_base` per kill, 4s window, +1 multiplier per `burst_window` chain, +1 for terror kills, stacking; bank pot × multiplier on window expiry); combo meter HUD (pot, multiplier, draining window, popping increments); end screen: score, level timer (display-only), escaped count (stat, zero points).

---

## Phase 5 — Readability pass (gates M1)

- **5.1 `vision_renderer.gd` rewrite proper** — production fill lines (colored advancing portion), calm/feral tint polish, riser readability, cower indicator (pose + scream hook). The M1 bar is spec validation Q2: *can you follow who's feral, who's filling, who's breaking, at horde scale?* If a debug rendering from earlier steps already reads, this pass is small.

---

## Phase 6 — PoC level + M1 playtest

- **6.1 Build the §12 level** — 2–3 civilian clusters separated by gaps > chain-scan radius; police pair + GI position; escape zone; at least one dead end; open staging ground. Hand-built (Initializer disabled). The manually-placed-zombie signal-wiring bug this depends on was fixed in the June 10 Stage A batch on main — verify it's intact after the Phase 1 strip.
- **6.2 Sacred-ratio sweep + M1 verdict** — sweep fill speed vs zombie speed until the GI kills ~3–4 of a charging wave (target: Militia 1 / Police 2 / GI 3–4); run validation questions 1–5 and 7. **Watch Q5 (loitering) and the §14.6 "horde wandered off" feel specifically.**

---

## Phase 7 — M2: the Mark + inspect

- **7.1 The Mark** — one active mark (human or coordinate); RMB-with-nothing-selected verbs; §5.4 scope rule (marked prey wins unless another human is strictly closer AND within local scan); never interrupts active pursuit; ferals-retarget-only; decal/glow.
- **7.2 LMB fill-line inspect** — toggle emphasis on one human's fill line; preserves zombie selection.
- **7.3 M2 playtest** — validation Q6 (does the Mark earn its slot?) + a full pass on all seven questions → **verdict on the pivot.**

---

## Performance tie-in (reconciling `CODEBASE_REVIEW.md`)

The review's perf plan was written against v1. The pivot changes its math substantially:

- **Most of the measured hot paths die with v1.** The ungated shooting scan (the review's hottest single cost), melee bookkeeping (`count_melee_attackers` O(n²)), morale/alert scans, and per-frame health-bar updates are all deleted by Phase 1 — v2 has no HP, so per-unit `ProgressBar`s (a flagged Tier-2 cost) go entirely, for free. **Do not spend any effort optimising v1 systems on this branch.**
- **Fix A (spatial index + neighbour cache) is pulled forward into Phase 0 — as an API, not an implementation.** Every v2 system is a radius query (contagion, fear count, local scan, awareness, seeding, mark radius, shamble), so the registry must exist from day one; but naive O(n) internals are fine at PoC scale. The determinism requirement adds one constraint the review didn't have: **query results must be stable-ordered**, so the future spatial-hash upgrade must sort bucket results by unit ID before returning.
- **One genuinely new cost to watch:** the fear-radius count is a continuous O(H·Z) check the v1 codebase never had, and fill range/LOS maintenance (for decay) wants per-zombie LOS, not just at-fire-time. If profiling complains, the sanctioned fix is a deterministic bucketed cadence (~10Hz, staggered by `unit_uid % bucket_count` — never random offsets). Flag before implementing; spec says "checked continuously" and 0.1s granularity needs Ben's sign-off as compatible.
- **The Master Roadmap's "Stage C before validation" ruling is relaxed for the PoC.** That ruling assumed validating v1 at 150–500 units. The §12 slice is small (a few dozen units even with risers), so the Phase-0 naive registry suffices for M1/M2. Full Stage C (spatial hash internals, tick decoupling/LOD) moves to **post-PoC, before any at-scale validation** — and slots in behind the Phase-0 API without touching callers.
- **The Stage B benchmark is deferred and must be re-run against v2 systems** — the v1 measurements are obsolete once Phase 1 lands (the things it measured no longer exist).
- **`Archive/IMPLEMENTER_GUIDE.md` status (v1 guide, archived):** Spec 1 (spatial index) survives as the post-PoC reference for upgrading the Phase-0 internals; Spec 0 (benchmark) survives re-targeted at v2. Specs 3–5 and the invariants checklist are v1-bound (melee gate, corpse linger, morale, health bars) and need a v2 revision before any lower-capability-model execution on this branch. Do not hand the current guide to a cheap model against v2 code.
- **Stage A is done where it matters here:** parse gate, layer naming, gitignore, hot-path diagnostic gating, and the manually-placed-zombie signal fix all landed on main June 10 and are inherited by this branch.

---

## Open decisions for Ben

1. **Demolition shape (recommendation: as planned).** Phase 1 as one contained band means a sterile-sandbox window until Phase 2 lands. The alternative — keeping morale/alerts alive while building fill alongside — avoids that window but means every new system negotiates with code that's already dead. Recommend accepting the window.
2. **Specials handling.** Recommended: minimal-patch to keep parsing, non-functional on the branch. Alternative is deleting them here and restoring from main at re-audit — cleaner diff, riskier restore.
3. **Version numbering on the branch.** Recommend continuing `0.MINOR.PATCH` (Phase 1 lands as v0.29.0, etc.) and reserving a `1.0.0-poc`-style rename until the pivot validates. Alternative: a parallel `2.0.0-poc.N` line from the first commit.
4. **Fear/fill check cadence** — per-frame vs deterministic 10Hz buckets (see Performance tie-in). Only matters if profiling forces it; flagged now so the answer exists before it's needed.
