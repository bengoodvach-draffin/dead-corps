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
@export var zombie_speed: float = 200.0
@export var human_flee_speed: float = 90.0

# === HUMAN AWARENESS / DEFENSE (per-class: [CIV, MILITIA, POLICE, GI]) ===
@export var awareness: Array[float] = [400.0, 450.0, 450.0, 550.0]
@export var fill_speed: Array[float] = [0.0, 250.0, 300.0, 450.0]
@export var fear_threshold: Array[int] = [0, 1, 2, 3]
@export var civilian_reaction: float = 0.75

# === FEAR ===
@export var fear_radius: float = 250.0
@export var fear_reaction: float = 0.3

# === FLEE / HERDING ===
@export var flee_repel_radius: float = 180.0
@export var flee_repel_strength: float = 1.5
@export var flee_exit_threat_bias: float = 1.5

# === CONTAGION / HUNT ===
@export var contagion_radius: float = 150.0
@export var chain_scan_radius: float = 250.0
@export var feral_divert_interval: float = 0.25
@export var feral_divert_hysteresis: float = 0.8
@export var feral_offaxis_penalty: float = 2.0

# === POUNCE ===
@export var pounce_range: float = 40.0
@export var pounce_recovery: float = 1.0
@export var pounce_flight_time: float = 0.2

# === RISERS ===
@export var rise_time: float = 2.5

# === COWER ===
@export var cower_min_displacement: float = 40.0
@export var cower_window: float = 2.0

# === SCORING ===
@export var combo_window: float = 4.0
@export var burst_window: float = 1.5
@export var kill_base: int = 10

# === RELEASE / MARK ===
@export var release_cluster_radius: float = 300.0
@export var mark_radius: float = 300.0

# === IDLE SHAMBLE ===
@export var shamble_leash: float = 5.0
@export var shamble_speed: float = 7.0
@export var shamble_pause: float = 3.0

# === FILL DECAY / ROTATION ===
@export var fill_decay_factor: float = 2.0
@export var turn_speed: float = 360.0
@export var facing_tolerance: float = 15.0

# === NO-PROGRESS FAILSAFE ===
@export var failsafe_min_progress: float = 40.0
@export var failsafe_window: float = 2.0


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

	GameConfig.release_cluster_radius = release_cluster_radius
	GameConfig.mark_radius = mark_radius

	GameConfig.shamble_leash = shamble_leash
	GameConfig.shamble_speed = shamble_speed
	GameConfig.shamble_pause = shamble_pause

	GameConfig.fill_decay_factor = fill_decay_factor
	GameConfig.turn_speed = turn_speed
	GameConfig.facing_tolerance = facing_tolerance

	GameConfig.failsafe_min_progress = failsafe_min_progress
	GameConfig.failsafe_window = failsafe_window

	print("✅ LevelConfig: pushed per-level tunables into GameConfig")
