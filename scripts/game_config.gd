extends Node

## GameConfig - Global singleton for all v2 spec-§9 tunables
##
## Register this as an Autoload in:
##   Project → Project Settings → Autoload
##   Path: res://scripts/game_config.gd
##   Name: GameConfig
##
## Single source of truth for every gameplay knob in the V2 PoC. Holds the
## spec v0.1 defaults always, so any scene boots with sane values even with no
## LevelConfig node present. A per-level `LevelConfig` node (level_config.gd)
## may override any of these at runtime in its `_ready()`.
##
## Invariant (V2_IMPLEMENTER_GUIDE): every §9 tunable reads from here — never
## hardcode a number that appears in the spec's knob table.
##
## Per-class arrays are indexed by DefenderClass: CIV=0, MILITIA=1, POLICE=2,
## GI=3 (the PoC roster; v1's SPEC_OPS is dropped — Phase 1.1 rebuilds the enum
## to these four). Keep this index order in sync everywhere.
##
## BASELINE (2026-07-30): these are no longer the spec's untested v0.1 numbers.
## Ten knobs were rebased onto the values Ben tuned by hand on level_docks, so a
## new level starts from playtested ground instead of from paper — see the
## "docks baseline" notes below. level_config.gd's @export defaults mirror them.

# === DEBUG ===
## Master switch for the per-unit / per-event debug prints — sieges, shelter
## entries and adoptions, cowers, breaches, releases, escapes, per-unit
## registration. OFF by default (2026-07-30): at level scale they're both console
## noise and a genuine per-event cost, since each one formats a string. The guard
## sits BEFORE the format, so a disabled line costs one bool check.
##
## One-shot system lines ignore this and always print: boot confirmations, the
## registration summary, and the win/lose verdict. Not mirrored in LevelConfig —
## this is a developer switch, not a per-level gameplay tunable.
var debug_logs: bool = false

## The perf sampler (perf_sampler.gd): one ⏱️ PERF line to the console/log every
## 5s — frame avg/worst, physics time, node count, unit census. Independent of
## debug_logs (it's the measuring instrument, and 1 line/5s is noise-free).
var perf_log: bool = true

## AUTONOMOUS LOAD TEST (Tier 3.6): > 0 = this many seconds after boot, every
## calm zombie auto-ignites FERAL (the contagion path — needs no mouse), so a
## full-frenzy load test runs from a headless boot with nobody at the keyboard:
## boot → frenzy on the timer → the sampler logs the curve → read godot.log.
## Timed on sim_tick, not wall clock, so runs are §10-comparable. 0 = off
## (normal play). Not mirrored in LevelConfig. HARD-GATED in GameManager to
## level_testing.tscn only (Ben's ruling 2026-08-05) — on any other level this
## flag does nothing, however it gets set.
var perf_auto_frenzy_delay: float = 0.0


## PER-PROCESS HARNESS OVERRIDES (2026-08-05). Claude's load tests used to flip
## the two flags above by editing this file — which leaked test behavior into
## Ben's own editor runs happening at the same time (an auto-frenzy fired inside
## a live hazard-testing session). The harness now passes environment variables
## to ITS process only; this file never changes for a test again.
##   DC_AUTO_FRENZY=<seconds>  DC_DEBUG_LOGS=1
func _ready() -> void:
	var env_frenzy := OS.get_environment("DC_AUTO_FRENZY")
	if env_frenzy != "":
		perf_auto_frenzy_delay = float(env_frenzy)
		print("⏱️ PERF: auto-frenzy %ss (env override, this process only)" % env_frenzy)
	if OS.get_environment("DC_DEBUG_LOGS") == "1":
		debug_logs = true
		print("⏱️ PERF: debug_logs on (env override, this process only)")

## IDLE LOD (PERF_REVIEW.md F2, 2026-08-02): a defending/sheltered human with no
## zombie inside lod_wake_radius goes COLD — its entire per-tick brain (fear,
## fill, boid, clamp, facing) is skipped; it only re-checks for zombies every
## lod_check_interval (DetHash-staggered). The radius deliberately exceeds the
## largest awareness (550) by a margin bigger than any zombie covers in one
## check interval (140px/s × 0.5s = 70px < 150px), so a cold human always wakes
## BEFORE anything enters perception range — cold is unobservable in play.
## Not mirrored in LevelConfig (perf knobs, not level design).
var lod_wake_radius: float = 700.0
var lod_check_interval: float = 0.5

# === MOVEMENT ===
## Docks baseline (was the spec's 200) — the pace the chase actually reads at.
var zombie_speed: float = 140.0
var human_flee_speed: float = 90.0

# === HUMAN AWARENESS / DEFENSE (per-class: [CIV, MILITIA, POLICE, GI]) ===
## Radius at which a class becomes aware of zombies (LOS-gated at use site).
var awareness: Array[float] = [400.0, 450.0, 450.0, 550.0]
## Radial fill-front speed per class. CIV slot unused — civilians use the
## reaction clock (civilian_reaction) below, not a fill front.
var fill_speed: Array[float] = [0.0, 250.0, 300.0, 450.0]
## Count of zombies within fear_radius that trips a committed break, per class.
var fear_threshold: Array[int] = [0, 1, 2, 3]
## Civilian fill is a pure reaction clock (seconds) → completion = flee.
var civilian_reaction: float = 0.75
## Minimum seconds between SHOTS per class (CIV slot unused). The front keeps
## growing during the cooldown — at range (fill time > cooldown) nothing changes;
## this is the close-range fire-rate floor (point-blank refills in ~0.07s and a
## lone militia was shredding whole waves — Ben's playtest, 2026-07-24).
## Docks baseline: slowed a further quarter-second per class (was [_, .8, .6, .4]).
var fire_cooldown: Array[float] = [0.0, 1.0, 0.8, 0.6]

# === FEAR ===
var fear_radius: float = 250.0
var fear_reaction: float = 0.3
## How often (s) a defending human re-counts the zombies in its fear radius.
## PERF (2026-07-30): that count casts an LOS ray per zombie found, per human —
## running it every frame made the raycast load scale as humans × zombies, a few
## thousand physics queries per tick at level scale. Fear already absorbs a
## fear_reaction beat before the rout, so sub-frame precision buys nothing; the
## worst case is a break landing one interval late. Each human's phase is
## DetHash-staggered so the crowd never scans on the same tick. Not mirrored in
## LevelConfig — a perf knob, not a level-design one.
var fear_scan_interval: float = 0.2

## How often (s) an armed defender re-scans for its fill target (same perf story:
## the scan is a grid query + an LOS ray per candidate, per human). The fill
## LENGTH still grows every frame — only target acquisition is on the cadence, so
## the worst case is noticing a new nearest zombie one interval late. The lane is
## re-verified at the moment of firing (one ray), so a stale target can never be
## shot through a friendly. DetHash-staggered per unit; not in LevelConfig.
var fill_scan_interval: float = 0.2

# === FLEE / HERDING (build-plan 3.4) ===
## A fleeing human nav-paths to the nearest exit; its route bends away from zombies
## within flee_repel_radius. flee_repel_strength is THE herdability dial — how hard the
## bend pushes vs the goal pull (low = punches to the exit ignoring your wall; high =
## easily herded, can be shoved backward into a dead end → cower).
var flee_repel_radius: float = 180.0
## Docks baseline: 3.0 (was 1.5) — markedly more herdable.
var flee_repel_strength: float = 3.0
## Threat-aware exit choice: how strongly a broken human avoids picking an exit that's
## BEHIND the horde that scared it (so it flees away from the danger, not through it).
## Scores each exit by distance × (1 + bias × alignment-with-threat). 0 = OFF (pure
## nearest-exit, no threat consideration).
## Docks baseline: 6.0 (was 1.5) — routs commit hard to running AWAY from you.
## KEPT high alongside exit_block_radius below: the two solve different halves of
## the problem. This one is about the ROUTE (don't sprint through the horde to
## reach something behind it, Ben's playtest 2026-07-30); the block radius is
## about the DOOR itself. Neither substitutes for the other.
var flee_exit_threat_bias: float = 6.0
## "Zombies at the door" (Ben's ruling 2026-07-30): an exit with a living zombie
## within this radius is struck off the list entirely — a bunged-up door is not
## an exit, so walling one with bodies genuinely closes it. Deliberately TIGHT:
## it should mean standing in the doorway, not merely nearby, or a single wanderer
## sends runners on an absurd cross-map detour. If EVERY exit is blocked the set
## is used unfiltered (a desperate run at the least-bad one beats freezing; the
## cower detector corners them within cower_window regardless).
var exit_block_radius: float = 120.0

# === CONTAGION / HUNT ===
var contagion_radius: float = 150.0
## Docks baseline: 150 (was 250) — a tighter feral nose, so the horde keeps its
## line instead of every feral seeing half the level.
var chain_scan_radius: float = 150.0
## Peel-off (continuous opportunistic retarget): how often a pursuing feral re-scans
## for a closer fresh straggler (seconds), and how much closer that straggler must be
## to make it peel (fraction of the current target's distance — 0.8 = must be ≥20%
## closer). Hysteresis prevents target jitter; the pursuit claim keeps it one-peeler-
## per-human so the bulk keeps its momentum.
var feral_divert_interval: float = 0.25
var feral_divert_hysteresis: float = 0.8
## How strongly seeding prefers humans ALONG the swarm's movement path over off-axis
## ones (× the perpendicular offset in the path score). 0 = pure nearest (splays
## across the front rank); higher = more bullet-like (drives up the centre, spreads
## only once the central column is taken).
## Docks baseline: 1.5 (was 2.0) — a slightly less bullet-like, wider front.
var feral_offaxis_penalty: float = 1.5

# === POUNCE ===
var pounce_range: float = 40.0
var pounce_recovery: float = 1.0
## Lunge duration (seconds). The kill registers at landing (flight end), so a
## zombie killed mid-flight (e.g. by gunfire in 3.1) does NOT complete the kill.
var pounce_flight_time: float = 0.2

# === RISERS ===
var rise_time: float = 2.5

# === COWER ===
var cower_min_displacement: float = 40.0
## Docks baseline: 1.2 (was 2.0) — cornered humans give up quicker.
var cower_window: float = 1.2

# === SCORING ===
var combo_window: float = 4.0
var burst_window: float = 1.5
var kill_base: int = 10
## Kills per base-value tier (spec §6.1, V2 tiered base): each kill adds
## kill_base × ceil(chain_position / combo_tier_size) to the pot — kills 1–5 worth
## kill_base, 6–10 worth 2×, etc. Rewards chain LENGTH; the multiplier stays the rare lever.
var combo_tier_size: int = 5

# === RELEASE / MARK ===
## Docks baseline: 150 (was 300) — a release seeds a tighter cluster.
var release_cluster_radius: float = 150.0
## Release magnetism (build-plan #1): an RMB within this radius (px) of a human counts
## as a RELEASE, pinned to the nearest human; outside it, RMB is a plain calm move order.
## Docks baseline: 50 (was 100) — less magnetism, so a near-miss click stays a move.
var release_aim_radius: float = 50.0
## THE MARK's attention field (§5.4 as amended 2026-07-26): ONE circle doing both
## jobs — ferals INSIDE it prefer prey INSIDE it. (Supersedes the old 300px
## coordinate-prey-designation-only meaning.)
## Docks baseline: 300 (was 400).
var mark_radius: float = 300.0

# === IDLE SHAMBLE ===
var shamble_leash: float = 5.0
var shamble_speed: float = 7.0
## Pause (seconds) a zombie idles at each wander point before moving to the next.
## Per-point duration is varied deterministically (±50%) so a crowd doesn't pause in lockstep.
var shamble_pause: float = 3.0

# === FILL DECAY / ROTATION ===
## Fill-front decay multiplier (× fill speed), applied only when no zombie is visible.
var fill_decay_factor: float = 2.0
## Rotation rate (degrees/sec) used to gate the shot while facing a target.
var turn_speed: float = 360.0
## Angular tolerance (degrees) within which the front may fire.
var facing_tolerance: float = 15.0

# === NO-PROGRESS FAILSAFE ===
var failsafe_min_progress: float = 40.0
var failsafe_window: float = 2.0

# === DOOR WEDGE (the breach trigger, Ben's ruling 2026-07-29) ===
## How long a zombie must gain no ground toward its goal, while sitting in an
## intact door's engagement arc, before it starts pounding. SPLIT from the
## failsafe above deliberately: the give-up clock has to tolerate a slow or
## queued chase before abandoning a hunt, while hitting a door should convert to
## pounding almost immediately. Feral pursuit and calm ordered moves share it.
var door_wedge_window: float = 0.5
## Ground (px) that counts as "getting somewhere" within a wedge window. Keeps
## the failsafe's 20px/s rate (40px per 2s), so it's the same tolerance judged
## four times as often — not a stricter test.
var door_wedge_min_progress: float = 10.0

# === ENTERABLE BUILDINGS (buildings spec §14, v0 defaults) ===
## Depth (px) of the door engagement arc — the zone in front of a door where a
## feral pounds. Unified with the step-4 lock zone: an engaged door admits no one.
var door_engagement_depth: float = 25.0
## Seconds between one feral's pounds on a door (DetHash-staggered per unit).
var pound_interval: float = 1.0
## Flat door damage per pound.
var pound_damage: float = 10.0
## Default door integrity (a Door can override per-door; e.g. armory-grade 1500).
## v0: 600 ≈ 60 solo pounds ≈ 10s under a 6-feral siege. Sweep-tuned.
var door_integrity: float = 600.0
## Delay (s) before a door re-admits humans after its arc clears of ferals.
## v0: 0 (tuning option only — raise if boundary-hovering ferals flicker the lock).
var door_unlock_hysteresis: float = 0.0

# === FENCES (fences spec §A12, v0 defaults) ===
## Press-strip depth (px) on EACH side of the wire. Tightened 60 → 40 (Ben,
## 2026-08-02): at 60 a zombie visibly hovering near the wire still counted,
## which broke the read that BODIES ON THE WIRE fold it. 40 ≈ contact plus the
## first shoving rank; note it also halves the §A11 capacity model to ~1 rank
## per side, so long spans matter more for big thresholds.
var fence_press_depth: float = 40.0
## Seconds of at-or-above-threshold press to fold a fence, from an empty meter.
var fence_fold_time: float = 2.0
## Fold-meter drain rate below the threshold, × the fill rate. Drain, not reset
## (§A4): one body squeezed out for 0.3s must not zero 1.7s of progress.
var fence_relax_factor: float = 1.0
## Global default press threshold (bodies at once). Real tuning is per-fence via
## Fence.threshold_override, against each level's horde size.
var fence_press_threshold: int = 8
## Max midpoint bow (px) of a pressed span — presentation only, never simulation.
var fence_sag_max: float = 14.0
## SLICE 3 ONLY (§B9, post-PoC): seconds between kills on an electrified fence.
## Declared for the LevelConfig/spec knob table; UNREAD until slice 3 builds.
var fence_shock_interval: float = 1.5

# === HAZARDS (fences/hazards spec §B12, v0 defaults) ===
## HazardField sweep cadence (s): mine triggers, and (stakes/wire step) IMPALE
## kills + speed factors. 0.1s = 14px of zombie travel per sample — precise
## enough for a 14px mine, cheap enough to ignore (§B8). Not mirrored in
## LevelConfig: a sim-precision knob, not a level-design one.
var hazard_scan_interval: float = 0.1
