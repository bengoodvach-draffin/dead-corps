extends Node2D
class_name SelectionManager

## Manages unit selection for RTS-style control
## Handles click selection, box selection, group commands, and control groups
##
## Control Groups (RTS standard):
## - Ctrl+1-9: Assign selected units to control group
## - 1-9: Select control group
## - Ctrl+0: Clear control group assignment from selected units

signal selection_changed(selected_units: Array[Unit])

@export var selection_box_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var selection_box_border_color: Color = Color(0.2, 0.8, 0.2, 0.8)
@export var selection_box_border_width: float = 2.0

var selected_units: Array[Unit] = []
var is_box_selecting: bool = false
var box_start_pos: Vector2
var box_current_pos: Vector2

## Control groups - maps group number (1-9) to array of units
var control_groups: Dictionary = {}

@onready var camera: Camera2D = get_tree().get_first_node_in_group("camera")

func _ready() -> void:
	set_process_input(true)
	
	# Initialize control groups
	for i in range(1, 10):
		control_groups[i] = []

func _input(event: InputEvent) -> void:
	# Handle selection
	if event.is_action_pressed("select"):
		start_selection(event.position)
	elif event.is_action_released("select"):
		end_selection(event.position)
	elif event is InputEventMouseMotion and is_box_selecting:
		update_selection_box(event.position)
	
	# Handle commands
	elif event.is_action_pressed("command"):
		handle_command(event.position)
	
	# Handle control group hotkeys
	elif event is InputEventKey and event.pressed:
		handle_control_group_input(event)

func _draw() -> void:
	if is_box_selecting:
		draw_selection_box()

## Handles control group hotkey inputs (Ctrl+1-9, 1-9, Ctrl+0)
func handle_control_group_input(event: InputEventKey) -> void:
	var ctrl_pressed := event.ctrl_pressed or event.meta_pressed  # Meta for Mac
	
	# Get the number key pressed (1-9)
	var group_number := -1
	
	# Check number keys 1-9
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		group_number = event.keycode - KEY_0
	# Check numpad 1-9
	elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
		group_number = event.keycode - KEY_KP_0
	# Check 0 key for clearing
	elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
		if ctrl_pressed:
			clear_control_group_from_selection()
		return
	
	if group_number == -1:
		return
	
	# Assign or recall control group
	if ctrl_pressed:
		# Ctrl+Number: Assign current selection to control group
		assign_control_group(group_number)
	else:
		# Number alone: Select control group
		recall_control_group(group_number)

## Assigns the current selection to a control group
## Replaces any existing units in that group
func assign_control_group(group_number: int) -> void:
	if selected_units.is_empty():
		return

	# First, clear visual numbers from any units currently in this group
	var old_group_units: Array = control_groups.get(group_number, [])
	for old_unit in old_group_units:
		if is_instance_valid(old_unit):
			old_unit.clear_control_group_number()

	# Clear old group assignments for these units
	for unit in selected_units:
		if is_instance_valid(unit):
			remove_unit_from_all_groups(unit)

	# Set new group (only valid units)
	var valid_units: Array = selected_units.filter(func(u): return is_instance_valid(u))
	control_groups[group_number] = valid_units

	# Update visual numbers on units
	for unit in valid_units:
		unit.set_control_group_number(group_number)

	print("Assigned %d units to control group %d" % [valid_units.size(), group_number])

## Selects all units in a control group
func recall_control_group(group_number: int) -> void:
	var group_units: Array = control_groups.get(group_number, [])
	
	# Clean up dead units from group
	group_units = group_units.filter(func(u): return is_instance_valid(u))
	control_groups[group_number] = group_units
	
	if group_units.is_empty():
		return
	
	# Clear current selection and select group
	clear_selection()
	for unit in group_units:
		add_unit_to_selection(unit)
	
	print("Recalled control group %d: %d units" % [group_number, group_units.size()])

## Clears control group assignment from currently selected units
func clear_control_group_from_selection() -> void:
	if selected_units.is_empty():
		return

	for unit in selected_units:
		if is_instance_valid(unit):
			remove_unit_from_all_groups(unit)
			unit.clear_control_group_number()

	print("Cleared control group assignment from %d units" % selected_units.size())

## Removes a unit from all control groups
func remove_unit_from_all_groups(unit: Unit) -> void:
	for group_number in control_groups:
		var group := control_groups[group_number] as Array
		if unit in group:
			group.erase(unit)

func start_selection(_screen_pos: Vector2) -> void:
	# Convert screen position to world position
	box_start_pos = get_global_mouse_position()
	box_current_pos = box_start_pos
	is_box_selecting = true
	
	# If not holding shift, clear current selection —
	# UNLESS clicking on a human (cone inspection via VisionRenderer).
	# Clicking a human should pin/toggle their vision cone without
	# disturbing the current zombie selection.
	if not Input.is_key_pressed(KEY_SHIFT) and not _is_human_at_position(box_start_pos):
		clear_selection()


## Returns true if a living human is within 15px of world_pos.
## Mirrors the hit radius used in VisionRenderer._get_human_at_position().
func _is_human_at_position(world_pos: Vector2) -> bool:
	var humans := get_tree().get_nodes_in_group("humans")
	for unit in humans:
		if not unit is Human:
			continue
		if (unit as Human).is_dead:
			continue
		if world_pos.distance_to(unit.position) <= 15.0:
			return true
	return false

func update_selection_box(_screen_pos: Vector2) -> void:
	box_current_pos = get_global_mouse_position()
	queue_redraw()

func end_selection(_screen_pos: Vector2) -> void:
	box_current_pos = get_global_mouse_position()
	
	var box_size := (box_current_pos - box_start_pos).length()
	
	if box_size < 5.0:
		# Single click selection
		handle_click_selection()
	else:
		# Box selection
		handle_box_selection()
	
	is_box_selecting = false
	queue_redraw()

func handle_click_selection() -> void:
	var units := get_tree().get_nodes_in_group("zombies")
	var clicked_unit: Unit = null
	var min_distance := 30.0  # Click tolerance in pixels
	
	for unit in units:
		if unit is Unit:
			var distance := box_start_pos.distance_to(unit.position)
			if distance < min_distance:
				min_distance = distance
				clicked_unit = unit
	
	if clicked_unit:
		if Input.is_key_pressed(KEY_SHIFT):
			toggle_unit_selection(clicked_unit)
		else:
			clear_selection()
			add_unit_to_selection(clicked_unit)

func handle_box_selection() -> void:
	var selection_rect := get_selection_rect()
	var units := get_tree().get_nodes_in_group("zombies")
	
	for unit in units:
		if unit is Unit:
			if selection_rect.has_point(unit.position):
				add_unit_to_selection(unit)

func get_selection_rect() -> Rect2:
	var min_x: float = min(box_start_pos.x, box_current_pos.x)
	var min_y: float = min(box_start_pos.y, box_current_pos.y)
	var max_x: float = max(box_start_pos.x, box_current_pos.x)
	var max_y: float = max(box_start_pos.y, box_current_pos.y)
	
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func draw_selection_box() -> void:
	var rect := get_selection_rect()
	
	# Draw filled rectangle
	draw_rect(rect, selection_box_color)
	
	# Draw border
	draw_rect(rect, selection_box_border_color, false, selection_box_border_width)

func handle_command(_screen_pos: Vector2) -> void:
	if selected_units.is_empty():
		return

	var world_pos := get_global_mouse_position()

	# Check if right-clicking on an enemy
	var target_unit := get_unit_at_position(world_pos, "humans")

	if target_unit:
		# Attack command — use group engagement resolver (v0.25.0)
		_resolve_group_engagement(selected_units, target_unit)
	else:
		# Move command — only non-committed zombies respond
		var commandable_units: Array[Unit] = []
		for unit in selected_units:
			if is_instance_valid(unit):
				if unit is Zombie:
					var zombie := unit as Zombie
					if zombie.can_receive_command():
						commandable_units.append(unit)
				else:
					commandable_units.append(unit)
		
		if not commandable_units.is_empty():
			var formation_positions := calculate_formation_positions(world_pos, commandable_units)
			for i in range(commandable_units.size()):
				commandable_units[i].set_move_target(formation_positions[i])


## Group engagement resolver (v0.25.0)
## When the player right-clicks a human, finds all humans within 150px of the click
## and distributes selected zombies across the group using greedy bipartite assignment.
## Max 2 zombies per human. Overflow zombies move to the clicked position.
## @param zombies: Currently selected units
## @param clicked_human: The human that was right-clicked
func _resolve_group_engagement(zombies: Array[Unit], clicked_human: Unit) -> void:
	# Step 1: Find target group — all humans within 150px of clicked human
	var all_humans := get_tree().get_nodes_in_group("humans")
	var target_group: Array[Unit] = []
	for human in all_humans:
		if not human is Human:
			continue
		if (human as Human).is_dead:
			continue
		var dist: float = clicked_human.global_position.distance_to(human.global_position)
		if dist <= 150.0:
			target_group.append(human)
	# Safety: ensure clicked human is always included
	if clicked_human not in target_group:
		target_group.append(clicked_human)
	
	# Step 2: Filter commandable zombies
	var commandable: Array[Unit] = []
	for unit in zombies:
		if not is_instance_valid(unit):
			continue
		if unit is Zombie and (unit as Zombie).can_receive_command():
			commandable.append(unit)
	
	if commandable.is_empty():
		return
	
	print("🎯 GROUP ENGAGEMENT: ", commandable.size(), " zombies vs ", target_group.size(), " humans")
	
	# Step 3: Build zombie-human distance pairs, sort ascending
	var pairs: Array = []
	for zombie in commandable:
		for human in target_group:
			pairs.append({
				"zombie": zombie,
				"human": human,
				"dist": zombie.global_position.distance_to(human.global_position)
			})
	pairs.sort_custom(func(a, b): return a.dist < b.dist)
	
	# Step 4: Greedy bipartite assignment — max 2 zombies per human
	var assigned: Dictionary = {}      # zombie → human
	var human_counts: Dictionary = {}  # human → slot count
	
	for pair in pairs:
		if pair.zombie in assigned:
			continue
		var count: int = human_counts.get(pair.human, 0)
		if count >= 2:
			continue
		assigned[pair.zombie] = pair.human
		human_counts[pair.human] = count + 1
	
	# Step 5: Issue commands
	var overflow_count := 0
	for zombie in commandable:
		if zombie in assigned:
			(zombie as Zombie).set_attack_target(assigned[zombie])
		else:
			# Overflow: move to clicked human's position (stays with the fight)
			zombie.set_move_target(clicked_human.global_position)
			overflow_count += 1
	
	if overflow_count > 0:
		print("  ", overflow_count, " overflow zombies moving to fight position")

func get_unit_at_position(pos: Vector2, group: String) -> Unit:
	var units := get_tree().get_nodes_in_group(group)
	var closest_unit: Unit = null
	var min_distance := 30.0
	
	for unit in units:
		if unit is Unit:
			var distance := pos.distance_to(unit.position)
			if distance < min_distance:
				min_distance = distance
				closest_unit = unit
	
	return closest_unit

func add_unit_to_selection(unit: Unit) -> void:
	if unit not in selected_units:
		selected_units.append(unit)
		unit.select()
		selection_changed.emit(selected_units)

func toggle_unit_selection(unit: Unit) -> void:
	if unit in selected_units:
		remove_unit_from_selection(unit)
	else:
		add_unit_to_selection(unit)

func remove_unit_from_selection(unit: Unit) -> void:
	if unit in selected_units:
		selected_units.erase(unit)
		if is_instance_valid(unit):
			unit.deselect()
		selection_changed.emit(selected_units)

func clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()
	selection_changed.emit(selected_units)

func get_selected_units() -> Array[Unit]:
	return selected_units


## Calculates formation positions for a group of units
## Spreads units around the target position to prevent clumping
## @param target_pos: The central target position clicked by the player
## @param units: Array of units to position
## @return: Array of Vector2 positions, one for each unit
func calculate_formation_positions(target_pos: Vector2, units: Array[Unit]) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var unit_count := units.size()
	
	if unit_count == 0:
		return positions
	
	if unit_count == 1:
		# Single unit - just go to exact target
		positions.append(target_pos)
		return positions
	
	# Formation parameters
	var spacing := 40.0  # Distance between units in formation
	
	# Calculate how many units per row for a roughly square formation
	var units_per_row := int(ceil(sqrt(unit_count)))
	
	# Calculate grid dimensions
	var grid_width: float = (units_per_row - 1) * spacing
	var grid_height: float = (ceil(float(unit_count) / units_per_row) - 1) * spacing
	
	# Start position (top-left of grid, centered around target)
	var start_x: float = target_pos.x - grid_width / 2.0
	var start_y: float = target_pos.y - grid_height / 2.0
	
	# Assign positions in a grid with randomization
	for i in range(unit_count):
		var row := i / units_per_row
		var col := i % units_per_row
		
		# Add random jitter to make zombies look like a shambling horde
		# Not a regimented formation
		var jitter_x := randf_range(-15.0, 15.0)
		var jitter_y := randf_range(-15.0, 15.0)
		
		var pos := Vector2(
			start_x + col * spacing + jitter_x,
			start_y + row * spacing + jitter_y
		)
		
		# Clamp to game bounds — read from WorldBounds autoload so this
		# stays in sync when level size changes (was hardcoded ±500, broke
		# multi-unit commands in expanded levels)
		var bounds_min := WorldBounds.world_bounds_min
		var bounds_max := WorldBounds.world_bounds_max
		pos.x = clamp(pos.x, bounds_min.x, bounds_max.x)
		pos.y = clamp(pos.y, bounds_min.y, bounds_max.y)
		
		positions.append(pos)
	
	return positions


## Clears all selections and control groups
## Used when resetting the game to avoid invalid references
func cleanup_all() -> void:
	clear_selection()
	
	# Clear all control groups
	for i in range(1, 10):
		control_groups[i] = []
