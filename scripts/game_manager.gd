extends Node
class_name GameManager

## Main game manager that coordinates all gameplay systems
## Handles zombie conversion, spawning, escape tracking, and game state

signal human_converted(position: Vector2)
signal human_escaped()
signal game_won()
signal game_lost()

@export var zombie_scene: PackedScene
@export var human_scene: PackedScene
@export var conversion_spawn_offset: float = 20.0

var units_parent: Node2D
var all_zombies: Array[Zombie] = []
var all_humans: Array[Human] = []

## Counter for humans that successfully escaped to the safe zone
var escaped_humans: int = 0

## Number of zombies at game start (usually 6)
var starting_zombie_count: int = 0

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
	
	# CRITICAL FIX: Register manually placed units
	# When users manually place zombies/humans in the editor, they need to be tracked
	await get_tree().process_frame  # Wait for all nodes to be ready
	register_manually_placed_units()


func _process(delta: float) -> void:
	# Track game time (only while game is running)
	if not game_ended:
		game_time += delta

func spawn_zombie(pos: Vector2) -> Zombie:
	if not zombie_scene:
		push_error("Zombie scene not set in GameManager!")
		return null
	
	var zombie: Zombie = zombie_scene.instantiate()
	zombie.position = pos
	units_parent.add_child(zombie)
	
	# Connect to zombie's signal
	zombie.zombie_killed_human.connect(_on_zombie_killed_human)
	
	# Connect to tree_exiting to track when zombie dies
	zombie.tree_exiting.connect(_on_zombie_removed.bind(zombie))
	
	all_zombies.append(zombie)
	return zombie

func spawn_human(pos: Vector2) -> Human:
	if not human_scene:
		push_error("Human scene not set in GameManager!")
		return null
	
	var human: Human = human_scene.instantiate()
	human.position = pos
	units_parent.add_child(human)
	
	# Connect to human's signal
	human.human_died.connect(_on_human_died)
	
	all_humans.append(human)
	return human

func _on_zombie_killed_human(human: Human, _zombie: Zombie) -> void:
	# With incubation system, we DON'T spawn immediately
	# The human will enter "dead" state and spawn zombie after 5 seconds
	# This is handled by on_human_converted()
	pass

func on_human_converted(human: Human) -> void:
	# Called after incubation period (5 seconds)
	# Spawn a new zombie at the human's position
	var spawn_pos := human.position
	
	# Add small random offset so they don't overlap perfectly
	var random_offset := Vector2(
		randf_range(-conversion_spawn_offset, conversion_spawn_offset),
		randf_range(-conversion_spawn_offset, conversion_spawn_offset)
	)
	spawn_pos += random_offset
	
	# Create new zombie
	spawn_zombie(spawn_pos)
	
	human_converted.emit(spawn_pos)

func _on_human_died(human: Human) -> void:
	# Remove from tracking array
	all_humans.erase(human)
	
	# Check win condition
	check_win_condition()


## Called when a zombie is removed from the scene tree (died)
## Triggers lose condition check
func _on_zombie_removed(zombie: Zombie) -> void:
	# Remove from tracking array
	all_zombies.erase(zombie)
	
	# Check lose condition
	check_lose_condition()


## Called when a human successfully escapes to the safe zone
## Increments the escaped counter and removes the human from tracking
func on_human_escaped(human: Human) -> void:
	escaped_humans += 1
	all_humans.erase(human)
	human_escaped.emit()
	print("Human escaped! Total escaped: ", escaped_humans)
	
	# Check win condition (all humans either dead or escaped)
	check_win_condition()


## Checks if all humans are dead/escaped (player wins)
## Emits game_won signal with scoring data
func check_win_condition() -> void:
	# Don't check if game already ended
	if game_ended:
		return
	
	# Count remaining LIVE humans (exclude dead/incubating ones)
	var remaining_live_humans := 0
	for human in all_humans:
		if is_instance_valid(human) and not human.is_dead:
			remaining_live_humans += 1
	
	if remaining_live_humans == 0:
		game_ended = true
		var final_zombie_count := get_total_zombie_count()  # Includes corpses
		print("Victory! All humans dealt with! (%d zombies, %d escaped)" % [final_zombie_count, escaped_humans])
		game_won.emit()


## Checks if all zombies are dead while humans remain (player loses)
## Emits game_lost signal
func check_lose_condition() -> void:
	# Don't check if game already ended
	if game_ended:
		return
	
	# Count remaining zombies (including incubating corpses)
	var remaining_zombies := get_total_zombie_count()
	
	# Player loses if all zombies dead (and no corpses) AND at least one human alive or escaped
	if remaining_zombies == 0:
		var total_humans_accounted_for := escaped_humans + (get_all_humans().size())
		if total_humans_accounted_for > 0 or escaped_humans > 0:
			game_ended = true
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
	
	# Record starting zombie count for scoring
	starting_zombie_count = get_all_zombies().size()
	
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
	
	# Assign first 6 zombies to groups 1-6
	for i in range(min(6, zombies.size())):
		var zombie := zombies[i]
		var group_number := i + 1  # Groups are 1-indexed
		
		# Manually assign to control group (simulating Ctrl+1 through Ctrl+6)
		selection_manager.control_groups[group_number] = [zombie]
		zombie.set_control_group_number(group_number)
		print("Auto-assigned zombie to control group ", group_number)

func get_all_zombies() -> Array[Zombie]:
	# Clean up invalid references
	all_zombies = all_zombies.filter(func(z): return is_instance_valid(z))
	return all_zombies

func get_all_humans() -> Array[Human]:
	# Clean up invalid references
	all_humans = all_humans.filter(func(h): return is_instance_valid(h))
	return all_humans

## Gets total zombie count including incubating corpses (dead humans)
## For scoring purposes, dead humans count as zombies since they're converting
func get_total_zombie_count() -> int:
	var zombie_count := get_all_zombies().size()
	
	# Count dead humans (incubating corpses)
	var dead_human_count := 0
	for human in get_all_humans():
		if human.is_dead:
			dead_human_count += 1
	
	return zombie_count + dead_human_count


## Registers manually placed units in the scene
## Called during _ready() to track units placed via the editor
## Without this, manually placed units won't trigger win/loss conditions
func register_manually_placed_units() -> void:
	print("Registering manually placed units...")
	
	# Find all zombies in the scene
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Zombie and not all_zombies.has(zombie):
			all_zombies.append(zombie)
			print("  Registered manually placed zombie: ", zombie.name)
	
	# Find all humans in the scene  
	for human in get_tree().get_nodes_in_group("humans"):
		if human is Human and not all_humans.has(human):
			all_humans.append(human)
			# Connect death signal
			if not human.human_died.is_connected(_on_human_died):
				human.human_died.connect(_on_human_died)
			print("  Registered manually placed human: ", human.name)
	
	print("Registration complete: %d zombies, %d humans" % [all_zombies.size(), all_humans.size()])
