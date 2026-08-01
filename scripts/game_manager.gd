extends Node
class_name GameManager

## Main game manager that coordinates all gameplay systems
## Handles zombie conversion, spawning, escape tracking, and game state

signal game_won()
signal game_lost()

@export var zombie_scene: PackedScene
@export var human_scene: PackedScene

var units_parent: Node2D
var all_zombies: Array[Zombie] = []
var all_humans: Array[Human] = []

## Combo / pot scoring (build-plan 4.2). Created in _ready; fed pounce kills from
## _on_zombie_killed_human; finalized at game end. The ComboHUD + end screen read it.
var combo: ComboSystem = null

## Component children (Tier-7 manager splits): the hunt pool (§3.4 pursuit
## claims + pool queries) and the violence pipeline (§3.3 contagion + gunfire,
## §3.6 risers + corpse commands). GameManager keeps one-line delegates for
## their public APIs, so callers never changed. The Mark system (Phase 7) lands
## as a third sibling.
var _hunt: HuntPool = null
var _violence: ViolencePipeline = null
var _mark: MarkSystem = null

## Monotonic source for unit_uid. Assigned in registration order and never
## reused — this is what makes the registry's query results stable-ordered (§10).
var _next_unit_uid: int = 0

## Counter for humans that successfully escaped to the safe zone
var escaped_humans: int = 0

## Timer tracking how long the game has been running (in seconds)
var game_time: float = 0.0

## Whether the game has ended (prevents multiple end screens)
var game_ended: bool = false


func _ready() -> void:
	# Find or create units parent
	units_parent = get_tree().get_first_node_in_group("units_parent")
	if not units_parent:
		units_parent = Node2D.new()
		units_parent.name = "Units"
		add_child(units_parent)
	
	# Component children (Tier-7 splits): hunt pool + violence pipeline.
	_hunt = HuntPool.new()
	_hunt.name = "HuntPool"
	add_child(_hunt)
	_hunt.setup(self)
	_violence = ViolencePipeline.new()
	_violence.name = "ViolencePipeline"
	add_child(_violence)
	_violence.setup(self)
	_mark = MarkSystem.new()
	_mark.name = "MarkSystem"
	add_child(_mark)
	_mark.setup(self)

	# Scoring (4.2): the combo system + its runtime HUD. Combo first so the HUD finds it.
	combo = ComboSystem.new()
	combo.name = "ComboSystem"
	add_child(combo)
	var hud := ComboHUD.new()
	hud.name = "ComboHUD"
	add_child(hud)

	# CRITICAL FIX: Register manually placed units
	# When users manually place zombies/humans in the editor, they need to be tracked.
	# PHYSICS frame, not process frame: a render frame holds time_scale-many physics
	# ticks, so waiting on it made the registration tick (= when units first perceive
	# each other) depend on the fast-forward state — a boot-time divergence that
	# flipped level outcomes under held-F. One physics tick is one physics tick.
	await get_tree().physics_frame
	register_manually_placed_units()
	_adopt_shelter_residents()


func _process(delta: float) -> void:
	# Track game time (only while game is running)
	if not game_ended:
		game_time += delta


func _physics_process(delta: float) -> void:
	# Nav-map sync per PHYSICS TICK. Godot syncs the NavigationServer once per
	# RENDER frame by default, so under fast-forward (3 ticks/frame) agents path
	# against maps up to 3 ticks stale — enough micro-divergence to flip a level's
	# outcome (found via a held-F playtest). Forcing the sync here couples pathing
	# to the tick stream: the sim is identical at any time_scale or render rate
	# (§10). GameManager ticks before the units (tree order), so every agent
	# queries a fresh map.
	NavigationServer2D.map_force_update(get_viewport().find_world_2d().navigation_map)
	# Riser countdowns tick on the physics step (fixed timestep → deterministic).
	if not game_ended:
		_violence.tick(delta)

func spawn_zombie(pos: Vector2) -> Zombie:
	if not zombie_scene:
		push_error("Zombie scene not set in GameManager!")
		return null
	
	var zombie: Zombie = zombie_scene.instantiate()
	# Convert the world-space spawn point into the parent's frame BEFORE add_child,
	# so _ready (anchors, bounds clamp) already sees the final position — and an
	# offset Units parent can't shift the spawn (Tier-4 cluster fix).
	zombie.position = units_parent.to_local(pos)
	units_parent.add_child(zombie)
	_register_zombie(zombie)
	return zombie

func spawn_human(pos: Vector2) -> Human:
	if not human_scene:
		push_error("Human scene not set in GameManager!")
		return null
	
	var human: Human = human_scene.instantiate()
	human.position = units_parent.to_local(pos)   # world→parent frame; see spawn_zombie
	units_parent.add_child(human)
	_register_human(human)
	return human


## === UNIT REGISTRY (V2) ===
## Single owner of unit tracking: assigns the stable unit_uid, appends to the
## tracking array, and wires the unit's signals. Both spawn_*() and
## register_manually_placed_units() route through these so the wiring lives in
## exactly one place (ARCHITECTURE_GUIDELINES rule 1).
##
## Idempotent: a unit already tracked is skipped (the manual-placement path may
## re-encounter an already-spawned unit). uid is assigned in registration order
## and never reused — successive registrations strictly increase it. That, plus
## order-preserving appends and validity filtering, is the ordering contract the
## query helpers below rely on.

func _register_zombie(zombie: Zombie) -> void:
	if all_zombies.has(zombie):
		return
	zombie.unit_uid = _next_unit_uid
	_next_unit_uid += 1
	all_zombies.append(zombie)
	# Guarded so a re-encountered or pre-connected instance can't double-connect.
	if not zombie.zombie_killed_human.is_connected(_on_zombie_killed_human):
		zombie.zombie_killed_human.connect(_on_zombie_killed_human)
	if not zombie.tree_exiting.is_connected(_on_zombie_removed):
		zombie.tree_exiting.connect(_on_zombie_removed.bind(zombie))


func _register_human(human: Human) -> void:
	if all_humans.has(human):
		return
	human.unit_uid = _next_unit_uid
	_next_unit_uid += 1
	all_humans.append(human)
	if not human.human_died.is_connected(_on_human_died):
		human.human_died.connect(_on_human_died)

## Pounce-kill signal handler: the violence pipeline handles contagion + the
## riser; the combo (GM's child) scores it here — gunfire deaths never reach
## this (the player's losses, unscored).
func _on_zombie_killed_human(human: Human, zombie: Zombie) -> void:
	_violence.register_pounce_kill(human, zombie)
	if combo != null:
		combo.register_kill(human)


# === VIOLENCE PIPELINE DELEGATES (owner: violence_pipeline.gd) ===

func report_gunfire_kill(zombie: Zombie, shooter: Human) -> void:
	_violence.report_gunfire_kill(zombie, shooter)


func rising_corpses() -> Array:
	return _violence.rising_corpses()


func set_rise_route(corpse: Human, point: Vector2) -> void:
	_violence.set_rise_route(corpse, point)


func queue_rise_waypoint(corpse: Human, point: Vector2) -> void:
	_violence.queue_rise_waypoint(corpse, point)


func queue_rise_group(corpse: Human, group_number: int) -> void:
	_violence.queue_rise_group(corpse, group_number)


# === MARK DELEGATES (owner: mark_system.gd) ===

func mark_prey_for(feral: Zombie) -> Node:
	return _mark.prey_for(feral)


func place_mark(pos: Vector2, human: Human, building: Node2D) -> void:
	_mark.place(pos, human, building)


func clear_mark() -> void:
	_mark.clear()


func mark_active() -> bool:
	return _mark.is_active()


func mark_position() -> Vector2:
	return _mark.centre()

func _on_human_died(human: Human) -> void:
	# Remove from tracking array
	all_humans.erase(human)
	
	# Check win condition
	check_win_condition()


## Called when a zombie leaves the scene tree — registry bookkeeping ONLY. The
## lose verdict is judged at the death instant (report_gunfire_kill), never here:
## tree exits also happen during scene-reset teardowns, where a draining registry
## spuriously read as "all zombies eliminated" (A4).
func _on_zombie_removed(zombie: Zombie) -> void:
	all_zombies.erase(zombie)


## Called when a human successfully escapes to the safe zone
## Increments the escaped counter and removes the human from tracking
func on_human_escaped(human: Human) -> void:
	escaped_humans += 1
	all_humans.erase(human)
	# A fleeing human can be mid-pursuit when it reaches the exit (3.2+) — drop its
	# hunt-pool entry so the freed instance doesn't linger as a stale pursuit key.
	_hunt.drop(human)
	print("Human escaped! Total escaped: ", escaped_humans)
	
	# Check win condition (all humans either dead or escaped)
	check_win_condition()


## Win (spec §8): no humans remain on the map — all dead/converted or fled. A live
## human is one that's still valid and not a corpse; cowering humans are alive, so they
## count here and must be pounced to end the level (no special case — it just falls out).
func check_win_condition() -> void:
	if game_ended:
		return

	var remaining_humans := 0
	for human in all_humans:
		if is_instance_valid(human) and not human.is_dead:
			remaining_humans += 1

	if remaining_humans == 0:
		game_ended = true
		if combo != null:
			combo.finalize()   # bank any in-progress chain before the end screen reads it
		print("Victory! All humans dealt with! (%d zombies, %d escaped)" % [get_total_zombie_count(), escaped_humans])
		game_won.emit()


## Lose (spec §8): the zombie total reaches zero, with risers counting (get_total_zombie_count).
func check_lose_condition() -> void:
	if game_ended:
		return

	if get_total_zombie_count() == 0:
		game_ended = true
		if combo != null:
			combo.finalize()   # bank any in-progress chain before the end screen reads it
		print("Defeat! All zombies eliminated!")
		game_lost.emit()

func setup_test_scenario() -> void:
	"""Spawn a simple test scenario with a few zombies and humans"""
	# Spawn starting zombies (6 total)
	spawn_zombie(Vector2(-100, 0))
	spawn_zombie(Vector2(-120, 20))
	spawn_zombie(Vector2(-80, -20))
	spawn_zombie(Vector2(-140, 0))
	spawn_zombie(Vector2(-90, 40))
	spawn_zombie(Vector2(-110, -40))

	# Auto-assign control groups to starting zombies (for testing convenience)
	await get_tree().process_frame  # Wait for zombies to be fully initialized
	auto_assign_starting_control_groups()
	
	# Spawn humans (5 total)
	spawn_human(Vector2(100, 50))
	spawn_human(Vector2(120, -30))
	spawn_human(Vector2(150, 0))
	spawn_human(Vector2(80, 80))
	spawn_human(Vector2(140, 60))


## Auto-assigns the first 6 zombies to control groups 1-6
## Called after initial zombie spawn for testing convenience
func auto_assign_starting_control_groups() -> void:
	var zombies := get_all_zombies()
	var selection_manager := get_tree().get_first_node_in_group("selection_manager")
	
	if not selection_manager:
		push_warning("SelectionManager not found - cannot auto-assign control groups")
		return
	
	# Assign first 6 zombies to groups 1-6, through the SelectionManager's own
	# method (single owner of the groups dict — no cross-owner writes).
	for i in range(min(6, zombies.size())):
		var group_number := i + 1  # Groups are 1-indexed
		selection_manager.set_control_group(group_number, [zombies[i]])
		print("Auto-assigned zombie to control group ", group_number)

func get_all_zombies() -> Array[Zombie]:
	# Clean up invalid references
	all_zombies = all_zombies.filter(func(z): return is_instance_valid(z))
	return all_zombies

func get_all_humans() -> Array[Human]:
	# Clean up invalid references
	all_humans = all_humans.filter(func(h): return is_instance_valid(h))
	return all_humans


## === REGISTRY QUERIES (V2) ===
## Living-unit and neighbour lookups for v2 systems (contagion, fear count,
## local scan, awareness, seeding, mark/shamble radii — all radius queries).
##
## ORDERING CONTRACT: results are in unit_uid order by construction. uid is
## assigned in registration order, the tracking arrays only ever append, and
## the validity filtering below preserves relative order. All v2 systems iterate
## these results — NEVER re-sort them by anything non-deterministic (spec §10).
## Internals are a naive O(n) scan: fine at PoC counts; a spatial hash can drop
## in behind this API later (it must still return unit_uid order).

## Living zombies (valid + alive). Dead units are excluded — the corpse-linger
## invariant carried from v1. Liveness is the is_alive flag (HP was removed in
## demolition step 1.3); the "dead excluded" contract holds.
func living_zombies() -> Array[Zombie]:
	var result: Array[Zombie] = []
	for z in get_all_zombies():
		if z.is_alive:
			result.append(z)
	return result


## Living humans (valid + alive). Same dead-exclusion contract as living_zombies().
func living_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in get_all_humans():
		if h.is_alive:
			result.append(h)
	return result


## Living units of `team` (&"zombies" or &"humans") within `radius` of `pos`,
## excluding `exclude` if given. Result is in unit_uid order (inherits the
## living_*() ordering). global_position for all distance math — nested scenes
## break local position (CLAUDE.md invariant).
func neighbours_within(pos: Vector2, radius: float, team: StringName, exclude: Unit = null) -> Array[Unit]:
	var result: Array[Unit] = []
	var pool: Array
	if team == &"zombies":
		pool = living_zombies()
	else:
		pool = living_humans()
	for u in pool:
		if u == exclude:
			continue
		if u.global_position.distance_to(pos) <= radius:
			result.append(u)
	return result


## === HUNT POOL (V2, spec §3.4) ===
## Delegates to hunt_pool.gd (the single owner since the Tier-7 splits). Ferals
## report up here (rule 5) instead of peeking into each other's FeralBrain.


func add_pursuit(human: Human) -> void:
	_hunt.add_pursuit(human)


func remove_pursuit(human: Human) -> void:
	_hunt.remove_pursuit(human)


func pursued_humans() -> Array[Human]:
	return _hunt.pursued_humans()


func is_pursued(human: Human) -> bool:
	return _hunt.is_pursued(human)


func fleeing_humans() -> Array[Human]:
	return _hunt.fleeing_humans()


## Total zombies for the lose condition (spec §8): LIVING zombies + corpses about
## to rise. Living, not registered (A5) — dead zombies linger in all_zombies for
## their corpse-linger frames, which coupled the verdict's timing to framerate.
func get_total_zombie_count() -> int:
	return living_zombies().size() + _violence.pending_count()


## Shelter adoption (Ben's ruling 2026-07-26): humans PLACED inside an intact
## shelter at level start become SHELTERED as if they'd fled in — the occupants
## list is what every siege / flush / pour-in / win system keys off, and
## hand-placed units weren't on it (besiegers calmed at the breach; the building
## read unoccupied). Eligibility: intact `is_shelter` buildings only (dumb boxes
## and ruins keep their bystanders); patrol-enabled humans keep their authored
## routes. Deterministic: buildings in tree order, humans in unit_uid order.
func _adopt_shelter_residents() -> void:
	for b in get_tree().get_nodes_in_group("shelter_buildings"):
		if not b.is_shelter or b.is_breached():
			continue
		for h in living_humans():
			if h.patrol_enabled or h.is_sheltered():
				continue
			if not b.contains_point(h.global_position):
				continue
			h.adopt_into_shelter(b, _nearest_intact_door(b, h.global_position))


## The building's intact door nearest `pos` — the adoptee's notional entry for
## the deepest-first spot sort. Null for a doorless building (claim falls back).
func _nearest_intact_door(building: Node, pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for door in building.doors():
		if not door.is_intact():
			continue
		var d: float = pos.distance_to(door.global_position)
		if d < best_d:
			best_d = d
			best = door
	return best


## Registers manually placed units in the scene
## Called during _ready() to track units placed via the editor
## Without this, manually placed units won't trigger win/loss conditions
func register_manually_placed_units() -> void:
	print("Registering manually placed units...")
	
	# Find all zombies in the scene. get_nodes_in_group returns scene-tree order
	# (deterministic), so manually-placed uids are assigned in a stable order.
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Zombie and not all_zombies.has(zombie):
			_register_zombie(zombie)
			print("  Registered manually placed zombie: ", zombie.name)

	# Find all humans in the scene
	for human in get_tree().get_nodes_in_group("humans"):
		if human is Human and not all_humans.has(human):
			_register_human(human)
			print("  Registered manually placed human: ", human.name)
	
	print("Registration complete: %d zombies, %d humans" % [all_zombies.size(), all_humans.size()])
