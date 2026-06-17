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

# === MOVEMENT ===
var zombie_speed: float = 200.0
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

# === FEAR ===
var fear_radius: float = 250.0
var fear_reaction: float = 0.3

# === FLEE / HERDING (build-plan 3.4) ===
## A fleeing human nav-paths to the nearest exit; its route bends away from zombies
## within flee_repel_radius. flee_repel_strength is THE herdability dial — how hard the
## bend pushes vs the goal pull (low = punches to the exit ignoring your wall; high =
## easily herded, can be shoved backward into a dead end → cower).
var flee_repel_radius: float = 180.0
var flee_repel_strength: float = 1.5
## Threat-aware exit choice: how strongly a broken human avoids picking an exit that's
## BEHIND the horde that scared it (so it flees away from the danger, not through it).
## Scores each exit by distance × (1 + bias × alignment-with-threat). 0 = OFF (pure
## nearest-exit, no threat consideration).
var flee_exit_threat_bias: float = 1.5

# === CONTAGION / HUNT ===
var contagion_radius: float = 150.0
var chain_scan_radius: float = 250.0
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
var feral_offaxis_penalty: float = 2.0

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
var cower_window: float = 1.2

# === SCORING ===
var combo_window: float = 4.0
var burst_window: float = 1.5
var kill_base: int = 10

# === RELEASE / MARK ===
var release_cluster_radius: float = 300.0
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
