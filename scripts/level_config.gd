@tool
extends Node2D
class_name LevelConfig

## LevelConfig - Per-level override of the V2 spec-§9 tunables
##
## Place one of these in a level scene to override any GameConfig knob for that
## level. Set the values in the Inspector; on game start this node writes them
## all into the GameConfig autoload, so every system reads the per-level value.
##
## Mirrors the GameConfig defaults (game_config.gd) exactly. A level with NO
## LevelConfig node simply uses the GameConfig defaults — this node is optional.
##
## Pattern copied from level_bounds.gd: @tool, runtime-only write guarded by
## Engine.is_editor_hint(), push_error if the autoload is missing.
##
## Per-class arrays are indexed by DefenderClass: CIV=0, MILITIA=1, POLICE=2,
## GI=3 (PoC roster). Keep this index order in sync with GameConfig.

# === MOVEMENT ===
## Zombie speed (px/s) — calm commanded moves AND feral pursuit both use this.
@export var zombie_speed: float = 200.0
## Speed (px/s) a broken human runs to the exit.
@export var human_flee_speed: float = 90.0

# === HUMAN AWARENESS / DEFENSE (per-class: [CIV, MILITIA, POLICE, GI]) ===
## Per-class [CIV, MIL, POL, GI] detection radius (px), LOS-gated. Zombies inside it are perceived.
@export var awareness: Array[float] = [400.0, 450.0, 450.0, 550.0]
## Per-class [CIV, MIL, POL, GI] fill-front speed (px/s). CIV slot unused — civilians use civilian_reaction.
@export var fill_speed: Array[float] = [0.0, 250.0, 300.0, 450.0]
## Per-class [CIV, MIL, POL, GI] zombie count within fear_radius that trips a break. CIV=0 (any zombie breaks them).
@export var fear_threshold: Array[int] = [0, 1, 2, 3]
## Seconds a civilian sees a zombie before fleeing (their "fill" is a pure reaction clock).
@export var civilian_reaction: float = 0.75
## Per-class [CIV, MIL, POL, GI] minimum seconds between shots — the close-range fire-rate floor. CIV unused.
@export var fire_cooldown: Array[float] = [0.0, 0.8, 0.6, 0.4]

# === FEAR ===
## Radius (px) for the fear count. Zombies (any state, building-LOS gated) inside it feed the break.
@export var fear_radius: float = 250.0
## Delay (s) between the fear threshold tripping and the flee starting (animation beat; fill already cancelled).
@export var fear_reaction: float = 0.3

# === FLEE / HERDING ===
## Fleeing humans bend their route away from zombies within this radius (px) — the herding mechanic.
@export var flee_repel_radius: float = 180.0
## THE herdability dial: how hard the flee route bends around zombies vs pulling to the exit. Higher = easier to herd/corner.
@export var flee_repel_strength: float = 1.5
## How strongly a broken human avoids an exit BEHIND the horde that scared it. 0 = pure nearest exit.
@export var flee_exit_threat_bias: float = 1.5

# === CONTAGION / HUNT ===
## A kill or a zombie gunfire-death ignites calm zombies within this radius (px).
@export var contagion_radius: float = 150.0
## Feral local-scan / peel radius (px): reach for retargeting AND opportunistic straggler peel-off.
@export var chain_scan_radius: float = 250.0
## How often (s) a pursuing feral re-scans for a closer fresh straggler to peel onto.
@export var feral_divert_interval: float = 0.25
## A straggler must score this fraction of the current target's path-score to peel (0.8 = ≥20% better). Kills jitter.
@export var feral_divert_hysteresis: float = 0.8
## Bullet-vs-splay: how strongly targeting prefers humans along the swarm's path. 0 = splay across the front rank; higher = drive up the centre.
@export var feral_offaxis_penalty: float = 2.0

# === POUNCE ===
## Distance (px) at which a feral lunges into a pounce.
@export var pounce_range: float = 40.0
## Seconds a zombie is stationary on the corpse after a kill (vulnerable to fills).
@export var pounce_recovery: float = 1.0
## Lunge duration (s). Kill registers at landing — a zombie killed mid-flight does NOT complete the kill.
@export var pounce_flight_time: float = 0.2

# === RISERS ===
## Seconds after a pounce landing before the corpse rises as a CALM zombie.
@export var rise_time: float = 2.5

# === COWER ===
## A fleeing human that net-moves less than this (px) over cower_window gets cornered → cower.
@export var cower_min_displacement: float = 40.0
## Rolling window (s) for the cower net-displacement check.
@export var cower_window: float = 2.0

# === SCORING ===
## Seconds after a kill the combo chain stays alive (refreshed each kill). On expiry it banks pot × multiplier.
@export var combo_window: float = 4.0
## A kill within this many seconds of the previous grants +1 multiplier (the rare greed lever).
@export var burst_window: float = 1.5
## Base points per kill. The tiered base = kill_base × ceil(chain_position / combo_tier_size).
@export var kill_base: int = 10
## Kills per base-value tier (e.g. 5 → kills 1–5 = kill_base, 6–10 = 2×…). Rewards chain LENGTH.
@export var combo_tier_size: int = 5

# === RELEASE / MARK ===
## On release, humans within this radius (px) of the aim point are seeded as targets.
@export var release_cluster_radius: float = 300.0
## Release magnetism (#1): RMB within this radius (px) of a human = a release pinned to the nearest one; outside it = a move order.
@export var release_aim_radius: float = 100.0
## THE MARK's attention field (px): ferals inside the circle prefer prey inside the circle.
@export var mark_radius: float = 400.0

# === IDLE SHAMBLE ===
## How far (px) an idle calm zombie wanders from its anchor.
@export var shamble_leash: float = 5.0
## Idle-wander speed (px/s).
@export var shamble_speed: float = 7.0
## Seconds a zombie idles at each wander point (varied ±50% deterministically).
@export var shamble_pause: float = 3.0

# === FILL DECAY / ROTATION ===
## Fill-front decay rate (× fill_speed), applied only when no zombie is visible.
@export var fill_decay_factor: float = 2.0
## Rotation rate (deg/s) while turning to face a target before firing.
@export var turn_speed: float = 360.0
## Angular tolerance (deg) within which an armed defender may fire.
@export var facing_tolerance: float = 15.0

# === NO-PROGRESS FAILSAFE ===
## A pursuing feral must close at least this much distance (px) per failsafe_window or it gives up (wedged-feral safety net).
@export var failsafe_min_progress: float = 40.0
## Window (s) for the no-progress failsafe check.
@export var failsafe_window: float = 2.0

# === ENTERABLE BUILDINGS ===
## Depth (px) of the door engagement arc — where a besieging feral pounds (and, step 4, what locks the door).
@export var door_engagement_depth: float = 25.0
## Seconds between one feral's pounds on a door (staggered per unit — a crowd never strikes in unison).
@export var pound_interval: float = 1.0
## Flat door damage per pound. More ferals in the arc = faster breach, capped physically by door width.
@export var pound_damage: float = 10.0
## Default door integrity (per-door override on the Door node; 0 there = use this).
@export var door_integrity: float = 600.0
## Delay (s) before a door re-admits humans after its arc clears of ferals (0 = instant).
@export var door_unlock_hysteresis: float = 0.0


## On game start, push every value into the GameConfig autoload.
## Editor-only: do nothing (don't mutate the autoload while editing).
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if GameConfig == null:
		push_error("LevelConfig: GameConfig autoload not found! Per-level overrides will not be applied.")
		return

	GameConfig.zombie_speed = zombie_speed
	GameConfig.human_flee_speed = human_flee_speed

	GameConfig.awareness = awareness
	GameConfig.fill_speed = fill_speed
	GameConfig.fear_threshold = fear_threshold
	GameConfig.civilian_reaction = civilian_reaction
	GameConfig.fire_cooldown = fire_cooldown

	GameConfig.fear_radius = fear_radius
	GameConfig.fear_reaction = fear_reaction

	GameConfig.flee_repel_radius = flee_repel_radius
	GameConfig.flee_repel_strength = flee_repel_strength
	GameConfig.flee_exit_threat_bias = flee_exit_threat_bias

	GameConfig.contagion_radius = contagion_radius
	GameConfig.chain_scan_radius = chain_scan_radius
	GameConfig.feral_divert_interval = feral_divert_interval
	GameConfig.feral_divert_hysteresis = feral_divert_hysteresis
	GameConfig.feral_offaxis_penalty = feral_offaxis_penalty

	GameConfig.pounce_range = pounce_range
	GameConfig.pounce_recovery = pounce_recovery
	GameConfig.pounce_flight_time = pounce_flight_time

	GameConfig.rise_time = rise_time

	GameConfig.cower_min_displacement = cower_min_displacement
	GameConfig.cower_window = cower_window

	GameConfig.combo_window = combo_window
	GameConfig.burst_window = burst_window
	GameConfig.kill_base = kill_base
	GameConfig.combo_tier_size = combo_tier_size

	GameConfig.release_cluster_radius = release_cluster_radius
	GameConfig.release_aim_radius = release_aim_radius
	GameConfig.mark_radius = mark_radius

	GameConfig.shamble_leash = shamble_leash
	GameConfig.shamble_speed = shamble_speed
	GameConfig.shamble_pause = shamble_pause

	GameConfig.fill_decay_factor = fill_decay_factor
	GameConfig.turn_speed = turn_speed
	GameConfig.facing_tolerance = facing_tolerance

	GameConfig.failsafe_min_progress = failsafe_min_progress
	GameConfig.failsafe_window = failsafe_window

	GameConfig.door_engagement_depth = door_engagement_depth
	GameConfig.pound_interval = pound_interval
	GameConfig.pound_damage = pound_damage
	GameConfig.door_integrity = door_integrity
	GameConfig.door_unlock_hysteresis = door_unlock_hysteresis

	print("✅ LevelConfig: pushed per-level tunables into GameConfig")
