extends CharacterBody2D
class_name Unit

## Base class for all units (zombies and humans) — V2.
##
## Provides movement (to a target position, bounds-clamped), selection/control
## groups, stable identity (unit_uid), and BOID separation/alignment.
##
## Phase 1.3 demolition: HP / damage / health-bar plumbing and the base combat
## loop are GONE (V2_DIRECTION_SPEC §11). There is no health — a unit is simply
## alive or dead (is_alive). Kills are one-shot events (the fill front in 3.1,
## the Pounce in 2.2), delivered through take_damage() → die(). BOID neighbour
## lookups now come from the GameManager registry (deterministic, global-space),
## never from a per-frame group scan.

## All unit types (legacy roster identifier — not read by v2 gameplay; kept so
## scenes that serialised unit_type still load).
enum UnitType {
	ZOMBIE_BASIC, ZOMBIE_FAT, ZOMBIE_FIREMAN, ZOMBIE_TRAFFIC, ZOMBIE_BAND,
	ZOMBIE_SCUBA, ZOMBIE_HEADLESS, ZOMBIE_COSTUME, ZOMBIE_PETROL,
	ZOMBIE_MOTORCYCLE, ZOMBIE_ORDNANCE, ZOMBIE_HEADCRAB,
	HUMAN_CIVILIAN, HUMAN_POLICE, HUMAN_SWAT, HUMAN_MILITARY
}

## Which team a unit belongs to.
enum Team {
	ZOMBIES,
	HUMANS
}

# === EXPORTED PROPERTIES ===

@export var unit_type: UnitType = UnitType.ZOMBIE_BASIC
@export var team: Team = Team.ZOMBIES

# === STATS ===
@export_group("Stats")

## Movement speed in pixels per second.
@export var move_speed: float = 100.0

## Collision radius in pixels — used for boundary clamping (match the CollisionShape2D).
@export var unit_radius: float = 12.0

# === FORMATION (BOID) ===
@export_group("Formation")

@export var formation_detection_radius: float = 100.0
## Cohesion is currently a no-op (no cohesion force is applied), kept for parity
## with child-class state tuning that still writes it.
@export var cohesion_strength: float = 30.0
@export var alignment_rate: float = 0.8
@export var min_formation_size: int = 2
@export var separation_radius: float = 30.0
@export var separation_strength: float = 100.0

@export_group("")

# === RUNTIME STATE ===

## Stable, monotonic identity assigned by GameManager at registration (-1 until
## registered). Registry queries return results in unit_uid order; all v2
## deterministic logic (spec §10) keys off this, never off chance or tree order.
var unit_uid: int = -1

## Whether this unit is alive. Replaces the v1 HP check everywhere (registry
## living_* queries, BOID dead-skip). Set false by die().
var is_alive: bool = true

var is_selected: bool = false
var control_group_number: int = 0

## World position this unit is moving toward (only used when has_target).
var target_position: Vector2
var has_target: bool = false

# === NODE REFERENCES ===
@onready var sprite: Sprite2D = $Sprite
@onready var selection_indicator: Node2D = $SelectionIndicator
@onready var control_group_label: Label = get_node_or_null("ControlGroupLabel")

## Cached GameManager (the unit registry). Resolved lazily — GameManager may
## _ready after its child units, so we can't cache it in _ready reliably.
var _game_manager: Node = null


func _ready() -> void:
	# Unit starts stationary at its own position (world space — target_position is
	# always global; local coords diverge under offset parents).
	target_position = global_position
	update_selection_visual()
	# GAME logic only (CLAUDE.md @tool rule): in the EDITOR, WorldBounds holds its
	# ±1000 defaults (LevelBounds writes at runtime only), so clamping here dragged
	# every @tool unit in a big offset-parent scene onto the default rect's edge
	# the moment the scene was opened — the puzzle_test_3 corruption. Never clamp
	# in the editor.
	if Engine.is_editor_hint():
		return
	clamp_position_to_bounds()


## Per physics frame: BOID forces, then movement, then bounds.
func _physics_process(delta: float) -> void:
	apply_boid_forces()

	if has_target:
		move_to_target(delta)

	clamp_position_to_bounds()


## Moves toward target_position (world space), stopping within 5px. global_position —
## a unit under an offset parent would otherwise steer against the wrong frame
## (Tier-4 cluster fix).
func move_to_target(_delta: float) -> void:
	var direction := (target_position - global_position).normalized()
	var distance := global_position.distance_to(target_position)
	if distance > 5.0:
		velocity = direction * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		has_target = false


## Steps toward a world point at `speed`; returns true on arrival (within
## arrive_dist). global_position-based. Used by behavior components that drive
## their own movement (shamble now; feral pursuit later) — the shell owns the
## decision of WHERE, Unit owns the movement.
func step_toward(point: Vector2, speed: float, arrive_dist: float = 2.0) -> bool:
	var to_point := point - global_position
	if to_point.length() <= arrive_dist:
		velocity = Vector2.ZERO
		return true
	velocity = to_point.normalized() * speed
	move_and_slide()
	return false


## Keeps the unit's edge (not centre) inside the world bounds. global_position —
## the bounds are world-space, so clamping local coords under an offset parent
## would pin the unit to the wrong rectangle (Tier-4 cluster fix).
func clamp_position_to_bounds() -> void:
	var bounds_min: Vector2 = WorldBounds.world_bounds_min
	var bounds_max: Vector2 = WorldBounds.world_bounds_max
	var min_x := bounds_min.x + unit_radius
	var max_x := bounds_max.x - unit_radius
	var min_y := bounds_min.y + unit_radius
	var max_y := bounds_max.y - unit_radius
	global_position.x = clamp(global_position.x, min_x, max_x)
	global_position.y = clamp(global_position.y, min_y, max_y)
	if global_position.x == min_x or global_position.x == max_x:
		velocity.x = 0
	if global_position.y == min_y or global_position.y == max_y:
		velocity.y = 0


## Queued waypoints (build-plan #8): move targets after target_position, walked in order.
## Populated by shift+RMB (queue_move); a plain move (set_move_target) clears it. Capped so
## accidental shift-spam can't grow it unbounded. Calm zombies execute it (Zombie._tick_calm
## pops the next on arrival); humans never queue, so this stays empty for them.
const MAX_WAYPOINTS := 32
var move_queue: Array[Vector2] = []


## Commands this unit to move to a world position (bounds-clamped). A plain move REPLACES any
## queued route (#8).
func set_move_target(target: Vector2) -> void:
	target_position = WorldBounds.clamp_to_bounds(target)
	has_target = true
	move_queue.clear()


## Appends a waypoint (bounds-clamped, capped) and starts moving if idle. Shift+RMB path (#8).
func queue_move(point: Vector2) -> void:
	if move_queue.size() >= MAX_WAYPOINTS:
		return
	move_queue.append(WorldBounds.clamp_to_bounds(point))
	if not has_target:
		_advance_move_queue()


## Pops the next queued waypoint into target_position. False if the queue was empty (#8).
func _advance_move_queue() -> bool:
	if move_queue.is_empty():
		return false
	target_position = move_queue.pop_front()
	has_target = true
	return true


## V2 binary kill entry. No HP — any lethal event (gunfire in 3.1, the Pounce in
## 2.2) calls this to kill the unit. The knockback arg + 2-arg signature exist
## for fat_zombie's gunshot knockback.
func take_damage(_amount: float, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	die()
	if knockback_direction != Vector2.ZERO and is_instance_valid(self):
		var tween := create_tween()
		tween.tween_property(self, "position", position + knockback_direction * 8.0, 0.15)


## Base death: mark dead and remove. Overridden by Zombie/Human for corpse
## linger / incubation — those overrides also set is_alive = false.
func die() -> void:
	is_alive = false
	queue_free()


## True if no building or intact door blocks the straight line to `target`.
## Used by feral local-scan (2.3) and the fill front (3.1). global_position-based.
func has_line_of_sight_to(target: Unit) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collision_mask = 17           # Environment (1) + intact-door "DoorLOS" blockers (16)
	query.exclude = [self, target]
	return space.intersect_ray(query).is_empty()


func select() -> void:
	is_selected = true
	update_selection_visual()


func deselect() -> void:
	is_selected = false
	update_selection_visual()


func update_selection_visual() -> void:
	if selection_indicator:
		selection_indicator.visible = is_selected


# === BOID FLOCKING (registry-backed, global-space) ===

## Lazily resolves and caches the GameManager (unit registry). Returns null until
## a GameManager exists in the scene — and always in the editor: the @tool Human
## subclass would otherwise run this BOID path on a placeholder GameManager
## instance (CLAUDE.md @tool rule — no game logic in the editor).
func _get_game_manager() -> Node:
	if Engine.is_editor_hint():
		return null
	if _game_manager == null or not is_instance_valid(_game_manager):
		_game_manager = get_tree().get_first_node_in_group("game_manager")
	return _game_manager


## Living same-team units within radius (excluding self), from the registry.
## Replaces the v1 get_nodes_in_group scan — deterministic + global-space (§10).
func find_nearby_allies(radius: float = -1.0) -> Array[Unit]:
	if radius < 0:
		radius = formation_detection_radius
	var gm := _get_game_manager()
	if gm == null:
		return []
	var my_team: StringName = &"zombies" if is_zombie() else &"humans"
	# gm is typed Node (avoiding a Unit→GameManager→Unit class cycle), so the
	# call is dynamic — annotate the result explicitly.
	var allies: Array[Unit] = gm.neighbours_within(global_position, radius, my_team, self)
	return allies


## BOID separation + alignment from ONE registry query (perf, 2026-07-30).
##
## These were two methods, each with its own per-tick query; they were merged,
## then re-split with the cadence/sample scheme below once the mega-horde profile
## showed the combined 100px query degenerating. Humans never run alignment.
##
## ALIGNMENT CADENCE + SAMPLE (perf, 2026-07-30 → 08-01): alignment runs 1-in-3
## ticks (staggered by uid off the GM's sim_tick — deterministic, restart-safe)
## with the lerp weight scaled by the cadence, and reads a CAPPED sample rather
## than everyone in radius. In a packed mega-horde the 100px query legitimately
## returns the whole horde — no grid fixes "they really are all in range"
## (measured ~1.1ms per boid call in the converted-blob spike) — but an average
## facing over ~16 neighbours IS the horde's facing; iterating 300 buys
## noise-level precision. So alignment now runs its own small sampled query on
## its cadence tick, and separation queries its own small radius per tick,
## uncapped — its genuinely-in-range set stays small even when packed, and
## missing a pusher would let units stack.
const ALIGN_CADENCE := 3
const ALIGN_SAMPLE := 16

## How often (in ticks) this unit runs separation; 1 = every tick. Overridden by
## Human: an idle/sheltered crowd barely moves, so spending a grid query per
## STANDING human per tick was the single biggest cost of the 447-human blob.
## Skipped ticks scale the applied impulse up to match (same net push per second).
func separation_cadence() -> int:
	return 1


func apply_boid_forces() -> void:
	var gm := _get_game_manager()
	if gm == null:
		return
	var sep_n := separation_cadence()
	if sep_n > 1 and (int(gm.sim_tick) + unit_uid) % sep_n != 0:
		return   # off-cadence tick: no query at all (only zombies align, and they run n=1)
	var my_team: StringName = &"zombies" if is_zombie() else &"humans"
	# gm is typed Node (avoiding a class cycle), so annotate the result explicitly.
	# Unsorted (see neighbours_within): both consumers here are order-insensitive
	# force sums, and the uid re-sort was measurable at frenzy scale.
	var neighbours: Array[Unit] = gm.neighbours_within(global_position, separation_radius, my_team, self, false)

	# --- SEPARATION: push apart from neighbours inside separation_radius ---
	var separation_vector := Vector2.ZERO
	var neighbor_count := 0
	for other in neighbours:
		var distance := global_position.distance_to(other.global_position)
		if distance > 0.1:
			var away_direction := (global_position - other.global_position).normalized()
			var normalized_distance := distance / separation_radius
			var force := (1.0 - normalized_distance * normalized_distance) * separation_strength
			separation_vector += away_direction * force
			neighbor_count += 1

	if neighbor_count > 0:
		separation_vector /= neighbor_count
		# move_and_collide (NOT raw position +=) so the push sweeps against walls;
		# a direct write would teleport a corner pile-up straight through geometry.
		# × sep_n: a 1-in-n cadence applies n ticks' worth per invocation — the
		# same net push per second as per-tick had (the alignment compensation
		# pattern; the per-application step stays sub-pixel-to-a-few-px).
		move_and_collide(separation_vector * get_physics_process_delta_time() * sep_n)

	# --- ALIGNMENT: zombies smoothly match the group's average facing (sampled) ---
	if not is_zombie() or (int(gm.sim_tick) + unit_uid) % ALIGN_CADENCE != 0:
		return
	var allies: Array[Unit] = gm.neighbours_within(
		global_position, formation_detection_radius, my_team, self, false, ALIGN_SAMPLE)
	if allies.size() < min_formation_size:
		return

	var average_facing := Vector2.ZERO
	var valid_count := 0
	for ally in allies:
		if ally is Zombie:
			var ally_zombie := ally as Zombie
			if ally_zombie.facing_direction.length() > 0.1:
				average_facing += ally_zombie.facing_direction
				valid_count += 1

	if valid_count > 0:
		average_facing = (average_facing / valid_count).normalized()
		var zombie := self as Zombie
		if zombie and zombie.facing_direction.length() > 0.1:
			# × ALIGN_CADENCE: the lerp runs a third as often, so each application
			# is three ticks' worth — the same smoothing rate as per-tick had.
			var weight := alignment_rate * get_physics_process_delta_time() * 10.0 * ALIGN_CADENCE
			var target_facing := zombie.facing_direction.lerp(average_facing, weight)
			zombie.facing_direction = target_facing.normalized()


# === TEAM / IDENTITY ===

func get_team() -> Team:
	return team


func is_zombie() -> bool:
	return team == Team.ZOMBIES


func is_human() -> bool:
	return team == Team.HUMANS


# === CONTROL GROUPS ===

func set_control_group_number(number: int) -> void:
	control_group_number = number
	update_control_group_label()


func clear_control_group_number() -> void:
	control_group_number = 0
	update_control_group_label()


func update_control_group_label() -> void:
	if control_group_label:
		if control_group_number > 0:
			control_group_label.text = str(control_group_number)
			control_group_label.visible = true
		else:
			control_group_label.visible = false
