@tool
extends Unit
class_name Human

## Human unit — AI defender (V2 skeleton).
##
## Phase 1.1 demolition: the v1 stealth-era behavior core (morale, detection/
## high-urgency alerts, tunnel vision, vision cones, the aim-timer shooting
## model, GRAPPLED/grapple-escape, the old flee, swing/sentry facing, formation
## squads) is GONE — see V2_DIRECTION_SPEC §11. What remains is a deliberately
## sterile skeleton: stand (IDLE), patrol between waypoints with pauses
## (positioning only — no facing/swing), and DEAD (incubation, until the rise
## pipeline replaces it in demolition step 1.4).
##
## The v2 defense behavior (radial fill front, fear radius + break, permanent
## rout/herding, cower) is rebuilt on top of this skeleton in Phase 3 — it reads
## all tunables per-class from GameConfig, not from this script.
##
## NOTE (transitional): one vestigial enum value and a small combat-compat shim
## block survive ONLY so the still-v1 zombie.gd / specials keep parsing until
## their own demolition step strips them. Each is tagged with the step that
## deletes it. They carry no live behavior here.

## Human behavioral states. Live in this skeleton: IDLE, DEAD (and SENTRY, which
## now behaves like IDLE — kept so level scenes that set initial_state = SENTRY
## still load). GRAPPLED is a vestigial label still referenced by
## costume_zombie.gd; remove it when specials are patched (step 1.7). No code
## transitions into GRAPPLED here. (Enum int values for IDLE=0 / SENTRY=1 are
## preserved so scene-serialized initial_state still loads.)
enum State {
	IDLE,      ## Standing / calm
	SENTRY,    ## Watching (now identical to IDLE — facing behavior deleted)
	GRAPPLED,  ## VESTIGIAL — pounce replaces grapple; remove with specials (1.7)
	DEAD       ## Incubating corpse (rise pipeline replaces this in step 1.4)
}

## Patrol modes for waypoint movement.
enum PatrolMode {
	LOOP,        ## 0→1→2→3→0 (circular)
	PING_PONG    ## 0→1→2→3→2→1→0 (back and forth)
}

## Defender class — the PoC roster. Indexes the per-class arrays in GameConfig
## (awareness / fill_speed / fear_threshold), so the order MUST stay
## CIVILIAN=0, MILITIA=1, POLICE=2, GI=3. (v1's SPEC_OPS is cut — §11.)
enum DefenderClass {
	CIVILIAN,
	MILITIA,
	POLICE,
	GI
}

## Emitted when this human dies. GameManager listens for win-condition tracking.
signal human_died(human: Human)

# === EXPORTED PROPERTIES ===

## Initial state when this human spawns (level-design hook).
@export var initial_state: State = State.IDLE

## Which defender class this unit is. Drives the v2 per-class GameConfig lookups
## (awareness, fill speed, fear threshold) built in Phase 3.
@export var defender_class: DefenderClass = DefenderClass.CIVILIAN

# === PATROL ===
@export_group("Patrol")

## Whether this human patrols between waypoints (positioning only — no watching).
@export var patrol_enabled: bool = false

## Patrol mode (LOOP or PING_PONG).
@export var patrol_mode: PatrolMode = PatrolMode.LOOP

## Movement speed while patrolling.
@export_range(10.0, 100.0, 5.0) var patrol_speed: float = 50.0

## Patrol waypoints (world positions). If empty and child "Waypoint*" nodes
## exist, they are loaded from those on _ready().
@export var patrol_waypoints: Array[Vector2] = []

## Pause duration (seconds) at each waypoint. Index matches waypoint index.
## 0.0 or missing = no pause. Empty = no pauses.
@export var patrol_pause_durations: Array[float] = []

@export_group("")

## Unit collision radius (must match CollisionShape2D radius).
const UNIT_RADIUS: float = 12.0

# === RUNTIME STATE ===

## Current behavioral state.
var current_state: State = State.IDLE

## Facing direction — updated from movement; kept for rendering/readability.
var facing_direction: Vector2 = Vector2.RIGHT

## Whether this human is dead but not yet converted (incubating).
var is_dead: bool = false

## Incubation countdown (seconds). The whole incubation→conversion pipeline is
## replaced by rise-in-place in demolition step 1.4.
var incubation_timer: float = 5.0
var incubation_duration: float = 5.0

# --- PATROL RUNTIME ---
var current_waypoint_index: int = 0   ## Waypoint we're heading to (0-based)
var patrol_direction: int = 1         ## 1 = forward, -1 = backward (PING_PONG)
var is_patrolling: bool = false       ## Whether actively patrolling
var is_patrol_paused: bool = false    ## Paused at a waypoint
var patrol_pause_timer: float = 0.0   ## Countdown for the current waypoint pause

## Cached physics space for line-of-sight raycasts.
var space_state: PhysicsDirectSpaceState2D

# === V1 COMBAT COMPAT SHIM (transitional) ===
# zombie.gd (still v1 until step 1.2) reads/writes these on its Unit-typed
# attack_target during its leap/grapple/melee path. They carry NO behavior —
# they exist only so zombie.gd parses AND so its now-defunct grapple write
# (attack_target.grapple_timer = attack_target.grapple_duration) doesn't crash
# at runtime. The human ignores all of them; it dies via Unit.take_damage like
# any unit. DELETE this whole block in step 1.2 with zombie.gd's melee combat.
var is_grappled: bool = false
var grapple_timer: float = 1.0
var grapple_duration: float = 0.5
var attacker_count: int = 0   ## read by zombie.gd's target-selection (_find_nearest_human_simple)
func count_melee_attackers() -> int: return 0
func add_attacker() -> void: pass
func remove_attacker() -> void: pass
# === END COMPAT SHIM ===


## Initialise the human: team, state, patrol, base unit, LOS space.
func _ready() -> void:
	# Force onto the human team; humans deal no melee damage (pounce model owns kills).
	team = Team.HUMANS
	attack_damage = 0.0

	current_state = initial_state

	# Load waypoints from child "Waypoint*" nodes if none were set in the Inspector.
	if patrol_enabled and patrol_waypoints.size() == 0:
		load_waypoints_from_children()

	# Start patrolling if configured with at least one waypoint.
	if patrol_enabled and patrol_waypoints.size() > 0:
		is_patrolling = true
		current_waypoint_index = 0
		patrol_direction = 1

	# Base Unit init (movement, BOID separation, bounds, selection visuals).
	super._ready()

	# Cache the physics space for line-of-sight raycasts.
	space_state = get_world_2d().direct_space_state


## Editor-only redraw so patrol-path visuals update while placing waypoints.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## Per-physics-frame dispatcher (V2 skeleton): DEAD handling → patrol → base unit.
## @param delta: Physics timestep in seconds.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Self-correct a stale state if anything left is_dead out of sync with DEAD.
	if is_dead and current_state != State.DEAD:
		current_state = State.DEAD
		velocity = Vector2.ZERO
		has_target = false

	# DEAD: incubating corpse — hold still, count down, convert. (Replaced in 1.4.)
	if current_state == State.DEAD:
		velocity = Vector2.ZERO
		incubation_timer -= delta
		if incubation_timer <= 0.0:
			spawn_zombie_conversion()
			queue_free()
		return

	# Patrol movement (positioning only — no facing/swing/regroup).
	if is_patrolling:
		update_patrol(delta)

	# Face the direction of travel (readability only).
	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()

	# Base Unit physics (movement, BOID separation).
	super._physics_process(delta)


# === PATROL ===

## Moves between waypoints in LOOP or PING_PONG mode, pausing at waypoints whose
## patrol_pause_durations entry is > 0. Facing overrides, swing, and formation
## regroup are deleted (§11 — patrols are positioning only now).
## @param delta: Time since last frame in seconds.
func update_patrol(delta: float) -> void:
	if patrol_waypoints.size() == 0:
		is_patrolling = false
		return

	# Hold position while paused at a waypoint.
	if is_patrol_paused:
		patrol_pause_timer -= delta
		if patrol_pause_timer <= 0.0:
			is_patrol_paused = false
			advance_to_next_waypoint()
			set_move_target(patrol_waypoints[current_waypoint_index])
			move_speed = patrol_speed
		return

	var target_waypoint := patrol_waypoints[current_waypoint_index]
	var distance_to_waypoint := global_position.distance_to(target_waypoint)

	if distance_to_waypoint < 10.0:
		# Arrived. Pause here if this waypoint has a configured pause.
		var pause_duration := 0.0
		if current_waypoint_index < patrol_pause_durations.size():
			pause_duration = patrol_pause_durations[current_waypoint_index]

		if pause_duration > 0.0:
			is_patrol_paused = true
			patrol_pause_timer = pause_duration
			has_target = false
			velocity = Vector2.ZERO
			return

		# No pause — advance immediately.
		advance_to_next_waypoint()
		target_waypoint = patrol_waypoints[current_waypoint_index]

	# Move toward the current waypoint at patrol speed.
	set_move_target(target_waypoint)
	move_speed = patrol_speed


## Advances current_waypoint_index per patrol mode.
func advance_to_next_waypoint() -> void:
	if patrol_mode == PatrolMode.LOOP:
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
	elif patrol_mode == PatrolMode.PING_PONG:
		current_waypoint_index += patrol_direction
		if current_waypoint_index >= patrol_waypoints.size():
			current_waypoint_index = patrol_waypoints.size() - 2  # reverse
			patrol_direction = -1
		elif current_waypoint_index < 0:
			current_waypoint_index = 1
			patrol_direction = 1


## Loads patrol waypoints from child "Waypoint*" Node2Ds, natural-sorted by name
## (so Waypoint2 precedes Waypoint10). Allows visual waypoint placement.
func load_waypoints_from_children() -> void:
	var waypoint_nodes: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("Waypoint"):
			waypoint_nodes.append(child)
	if waypoint_nodes.size() == 0:
		return
	waypoint_nodes.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	patrol_waypoints.clear()
	for waypoint in waypoint_nodes:
		if waypoint is Node2D:
			patrol_waypoints.append(waypoint.global_position)


# === LINE OF SIGHT (buildings block) ===

## True if no building blocks the straight line from this human to `target`.
func has_line_of_sight_to(target: Unit) -> bool:
	var query := PhysicsRayQueryParameters2D.create(position, target.position)
	query.collision_mask = 1            # buildings only
	query.exclude = [self, target]
	return space_state.intersect_ray(query).is_empty()


## True if no building blocks the straight line from this human to `point`
## (e.g. an escape zone).
func has_line_of_sight_to_point(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(position, point)
	query.collision_mask = 1            # buildings only
	query.exclude = [self]
	return space_state.intersect_ray(query).is_empty()


## Nearest escape zone with clear line of sight, or null. (Used by the v2 rout in
## Phase 3.4; harmless here.)
func get_nearest_escape_zone() -> Node2D:
	var escape_zones := get_tree().get_nodes_in_group("escape_zone")
	if escape_zones.is_empty():
		return null
	var nearest_zone: Node2D = null
	var nearest_distance := INF
	for zone in escape_zones:
		if not is_instance_valid(zone):
			continue
		# global_position — escape zones are nested scenes.
		if not has_line_of_sight_to_point(zone.global_position):
			continue
		var distance := global_position.distance_to(zone.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_zone = zone
	return nearest_zone


# === DEATH / CONVERSION ===

## Kills this human: notify GameManager, enter DEAD (incubating corpse).
## The morale-shock broadcast and attacker bookkeeping of the v1 die() are gone.
func die() -> void:
	if current_state == State.DEAD:
		return

	human_died.emit(self)

	current_state = State.DEAD
	is_dead = true
	incubation_timer = incubation_duration

	velocity = Vector2.ZERO
	has_target = false
	attack_target = null

	modulate = Color(0.8, 0.2, 0.2, 1.0)   # red corpse
	collision_layer = 0                     # corpses block nothing
	collision_mask = 0


## Asks GameManager to spawn a zombie at this corpse's position once incubation
## completes. (Replaced by rise-in-place in demolition step 1.4.)
func spawn_zombie_conversion() -> void:
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("on_human_converted"):
		game_manager.on_human_converted(self)


# === EDITOR VISUALS ===

## Draws patrol-path visuals in the editor only (waypoint dots + connecting
## lines). Sentry facing arrow and swing arc visuals are deleted (§11).
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if not patrol_enabled or patrol_waypoints.size() == 0:
		return

	var path_color := Color(1.0, 0.8, 0.0, 0.6)
	var waypoint_color := Color(1.0, 0.8, 0.0, 1.0)

	for i in range(patrol_waypoints.size()):
		var current_wp := patrol_waypoints[i] - global_position   # to local
		draw_circle(current_wp, 8.0, waypoint_color)

		var next_index := -1
		if patrol_mode == PatrolMode.LOOP:
			next_index = (i + 1) % patrol_waypoints.size()
		elif patrol_mode == PatrolMode.PING_PONG:
			if i < patrol_waypoints.size() - 1:
				next_index = i + 1
		if next_index >= 0:
			var next_wp := patrol_waypoints[next_index] - global_position
			draw_line(current_wp, next_wp, path_color, 2.0)
