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

## Incremented once per issued group move order. Used as the DetHash salt so
## successive orders jitter differently while staying deterministic (spec §10) —
## no live RNG. (Was randf_range; replaced in Phase 0.3.)
var _move_order_counter: int = 0

@onready var camera: Camera2D = get_tree().get_first_node_in_group("camera")

## The human currently under the cursor while releasable zombies are selected — gets
## the "release here" ring (build-plan 2.4 misclick defense). Cached GameManager for
## the per-frame hover query.
var _hovered_human: Human = null
var _gm_cache: Node = null

func _ready() -> void:
	set_process_input(true)

	# Initialize control groups
	for i in range(1, 10):
		control_groups[i] = []


## Per-frame: keep the release-hover highlight in sync with the cursor (recomputed
## each frame so it tracks both cursor and human movement). Cheap — one radius query.
func _process(_delta: float) -> void:
	_update_release_hover()

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

	# Recall the CALM members only (spec §3.1) — released ferals stay in the group
	# (they rejoin when they calm) but can't be selected while feral. "Command the
	# calm, influence the storm."
	clear_selection()
	var recalled := 0
	for unit in group_units:
		if unit is Zombie and not (unit as Zombie).is_selectable():
			continue
		add_unit_to_selection(unit)
		recalled += 1

	print("Recalled control group %d: %d calm of %d" % [group_number, recalled, group_units.size()])

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

	# If not holding shift, clear current selection.
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()

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
		if unit is Zombie and (unit as Zombie).is_selectable():
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
		if unit is Zombie and (unit as Zombie).is_selectable():
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
	var gm := get_tree().get_first_node_in_group("game_manager")

	# RMB on a human → RELEASE the selected calm zombies at that human (spec §5.2).
	# Otherwise → formation move order.
	var clicked_human := _human_at(world_pos, gm)
	if clicked_human != null:
		_release(world_pos, gm)
		return

	# Move command (calm zombies only).
	var commandable_units: Array[Unit] = []
	for unit in selected_units:
		if is_instance_valid(unit):
			if unit is Zombie:
				if (unit as Zombie).can_receive_command():
					commandable_units.append(unit)
			else:
				commandable_units.append(unit)

	if not commandable_units.is_empty():
		var formation_positions := calculate_formation_positions(world_pos, commandable_units)
		for i in range(commandable_units.size()):
			commandable_units[i].set_move_target(formation_positions[i])


## RELEASE (2.4, spec §5.2): every selected calm zombie ignites FERAL, seeded across
## the cluster of humans near the CLICK. Candidates = living humans within
## release_cluster_radius of click_pos (the clicked human is always one — distance ~0).
## First pass assigns one feral per human (greedy nearest-pairs); any remaining ferals
## distribute evenly (least-loaded human, nearest tiebreak). No per-human cap —
## pounce-exclusion (§3.5) prevents real pile-ups. Then hunt-pool rules (§3.4) govern.
## Released zombies leave the selection — released is released. Deterministic (§10):
## all ordering breaks on unit_uid, no RNG.
func _release(click_pos: Vector2, gm: Node) -> void:
	if gm == null:
		clear_selection()
		return

	# Candidate humans: living, within the cluster radius of the click.
	var candidates: Array[Human] = []
	for u in gm.neighbours_within(click_pos, GameConfig.release_cluster_radius, &"humans"):
		var h := u as Human
		if h != null and h.is_alive:
			candidates.append(h)

	# Ferals to seed: the selected calm zombies, in unit_uid order (determinism).
	var ferals: Array[Zombie] = []
	for unit in selected_units:
		if is_instance_valid(unit) and unit is Zombie and (unit as Zombie).can_receive_command():
			ferals.append(unit)
	ferals.sort_custom(func(a: Zombie, b: Zombie) -> bool: return a.unit_uid < b.unit_uid)

	if candidates.is_empty() or ferals.is_empty():
		clear_selection()
		return

	var assignment := ReleaseSeeder.assign(ferals, candidates, click_pos)
	for f in assignment:
		(f as Zombie).ignite_feral(assignment[f])
	print("🔥 RELEASE: ", ferals.size(), " zombies across ", candidates.size(), " human(s)")
	clear_selection()


## Nearest living human within click tolerance of `pos`, or null (release vs move).
func _human_at(pos: Vector2, gm: Node) -> Human:
	if gm == null:
		return null
	var humans: Array[Unit] = gm.neighbours_within(pos, 30.0, &"humans")
	var best: Human = null
	var best_dist := INF
	for h in humans:
		var d := pos.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h
	return best


## Updates which human shows the "release here" ring: the one under the cursor, but
## only while the selection contains a releasable (calm) zombie — otherwise RMB is a
## plain move and there's nothing to telegraph. Clears the prior hover on any change.
func _update_release_hover() -> void:
	var target: Human = null
	if _selection_has_releasable():
		var gm := _game_manager()
		if gm != null:
			target = _human_at(get_global_mouse_position(), gm)
	if target == _hovered_human:
		return
	if _hovered_human != null and is_instance_valid(_hovered_human):
		_hovered_human.set_hover_highlighted(false)
	_hovered_human = target
	if _hovered_human != null:
		_hovered_human.set_hover_highlighted(true)


## True if any selected unit is a calm zombie (so a release is possible).
func _selection_has_releasable() -> bool:
	for u in selected_units:
		if is_instance_valid(u) and u is Zombie and (u as Zombie).can_receive_command():
			return true
	return false


## Cached GameManager lookup for the per-frame hover query.
func _game_manager() -> Node:
	if _gm_cache == null or not is_instance_valid(_gm_cache):
		_gm_cache = get_tree().get_first_node_in_group("game_manager")
	return _gm_cache


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
	
	# One salt per group order so successive orders vary; captured before the
	# loop so every unit in THIS order shares it (decorrelated only by unit_uid).
	var order_salt := _move_order_counter
	_move_order_counter += 1

	# Assign positions in a grid with deterministic jitter (spec §10 — no RNG)
	for i in range(unit_count):
		var row := i / units_per_row
		var col := i % units_per_row

		# Deterministic per-unit jitter so zombies look like a shambling horde,
		# not a regimented formation. Keyed off unit_uid + order_salt → identical
		# every run, different per unit and per order.
		var jitter := DetHash.offset(units[i].unit_uid, order_salt, 15.0)

		var pos := Vector2(
			start_x + col * spacing + jitter.x,
			start_y + row * spacing + jitter.y
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
