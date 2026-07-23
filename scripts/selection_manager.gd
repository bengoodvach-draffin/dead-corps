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

## The fixed clicked waypoints of the current group route, for the interim viz (#8). Appended
## on shift+RMB; cleared by a plain command or a new selection. Fixed coords → the drawn line
## stays put (it does NOT recompute from live unit positions each frame).
var _group_route: Array[Vector2] = []

func _ready() -> void:
	set_process_input(true)

	# Initialize control groups
	for i in range(1, 10):
		control_groups[i] = []


## Per-frame: keep the release-hover highlight in sync with the cursor (recomputed
## each frame so it tracks both cursor and human movement). Cheap — one radius query.
func _process(_delta: float) -> void:
	_update_release_hover()
	queue_redraw()   # keep the group-route viz anchored as the selection moves (#8)

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
	_draw_group_route()


## Draws the group-route viz (#8): dots at each shift-clicked waypoint, lines between — the
## actual clicked path (one line, which is the averaged centre line for free). Fixed coords,
## so it doesn't wander as the units move; cleared on a plain command / new selection. Drawn in
## SelectionManager's space (untransformed = world), so the stored world points are used directly.
func _draw_group_route() -> void:
	if _group_route.is_empty():
		return
	var col := Color(1.0, 1.0, 1.0, 0.5)
	var prev: Vector2 = _group_route[0]
	draw_circle(prev, 4.0, col)
	for i in range(1, _group_route.size()):
		var p: Vector2 = _group_route[i]
		draw_line(prev, p, col, 2.0)
		draw_circle(p, 4.0, col)
		prev = p

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

	# Zombies join the group now; a selected CORPSE instead records the group on its riser
	# entry (6b) so the risen zombie joins on rise — putting the corpse node in the group
	# would leave a stale ref when it frees. Old assignments clear only for the units we keep.
	var gm := _game_manager()
	var valid_units: Array = []
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		if unit is Human and (unit as Human).is_selectable_corpse():
			if gm != null:
				gm.queue_rise_group(unit, group_number)
			unit.set_control_group_number(group_number)   # show the number on the corpse now (6b)
			continue
		remove_unit_from_all_groups(unit)
		valid_units.append(unit)

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
			# global_position — units nested under offset parents (e.g. an encounter
			# container) have local coords nowhere near the click (Tier-4 cluster fix).
			var distance := box_start_pos.distance_to(unit.global_position)
			if distance < min_distance:
				min_distance = distance
				clicked_unit = unit

	# Corpse commands (6a): pending-rise corpses are selectable too — pick the nearest.
	var gm := _game_manager()
	if gm != null:
		for corpse in gm.rising_corpses():
			var d := box_start_pos.distance_to((corpse as Node2D).global_position)
			if d < min_distance:
				min_distance = d
				clicked_unit = corpse

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
			if selection_rect.has_point(unit.global_position):
				add_unit_to_selection(unit)

	# Corpse commands (6a): sweep pending-rise corpses in alongside calm zombies.
	var gm := _game_manager()
	if gm != null:
		for corpse in gm.rising_corpses():
			if selection_rect.has_point((corpse as Node2D).global_position):
				add_unit_to_selection(corpse)

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
	var append := Input.is_key_pressed(KEY_SHIFT)   # shift+RMB = queue a waypoint/attack (#8)
	var clicked_human := _human_at(world_pos, gm)

	# Partition the selection into commandable calm zombies and pending-rise corpses.
	var calm_zombies: Array[Unit] = []
	var corpses: Array[Unit] = []
	for u in selected_units:
		if not is_instance_valid(u):
			continue
		if u is Zombie and (u as Zombie).can_receive_command():
			calm_zombies.append(u)
		elif u is Human and (u as Human).is_selectable_corpse():
			corpses.append(u)

	if append:
		# SHIFT — extend the route. On an enemy it's an ATTACK terminal (deferred to the end of
		# the route, "attacking is another waypoint"); on ground it's a move waypoint. The click
		# is recorded for the fixed viz line either way.
		_group_route.append(world_pos)
		if clicked_human != null:
			for z in calm_zombies:
				(z as Zombie).queued_attack = clicked_human   # fires when its move route ends
		elif not calm_zombies.is_empty():
			var slots := calculate_formation_positions(world_pos, calm_zombies)
			for i in range(calm_zombies.size()):
				calm_zombies[i].queue_move(slots[i])
		if gm != null:
			for c in corpses:
				gm.queue_rise_waypoint(c, world_pos)   # last waypoint → reclicked at rise
		return

	# PLAIN — single command; REPLACES any queued route/attack, and clears the viz line.
	_group_route.clear()
	if gm != null:
		for c in corpses:
			gm.set_rise_route(c, world_pos)
	if clicked_human != null:
		# Immediate release now (attack, forget the route). Pin-and-aim (magnetism #1).
		_release(clicked_human.global_position, gm)
		return
	if not calm_zombies.is_empty():
		var slots := calculate_formation_positions(world_pos, calm_zombies)
		for i in range(calm_zombies.size()):
			calm_zombies[i].set_move_target(slots[i])
			(calm_zombies[i] as Zombie).queued_attack = null


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

	# Candidate humans: living, within the cluster radius of the click. Sheltered
	# humans are excluded (buildings spec §6.1 — not valid targets behind walls;
	# release-at-the-building becomes the siege verb in step 3).
	var candidates: Array[Human] = []
	for u in gm.neighbours_within(click_pos, GameConfig.release_cluster_radius, &"humans"):
		var h := u as Human
		if h != null and h.is_alive and not h.is_sheltered():
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


## Nearest living human within release_aim_radius of `pos`, or null (release vs move).
## The radius is the release-magnetism knob (#1): a click this close to a human is a
## release pinned to the nearest one; a direct click is just the degenerate case.
## Sheltered humans never pin (buildings spec §6.1) — a click near them is a plain
## move order until step 3 makes the occupied BUILDING the release target.
func _human_at(pos: Vector2, gm: Node) -> Human:
	if gm == null:
		return null
	var humans: Array[Unit] = gm.neighbours_within(pos, GameConfig.release_aim_radius, &"humans")
	var best: Human = null
	var best_dist := INF
	for h in humans:
		if (h as Human).is_sheltered():
			continue
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
	_group_route.clear()   # a new/cleared selection drops the route viz (#8)
	selection_changed.emit(selected_units)

func get_selected_units() -> Array[Unit]:
	return selected_units


## True if `unit` is in the current selection. GameManager checks this at rise (6a) to
## decide whether to auto-select the risen zombie.
func is_selected(unit: Node) -> bool:
	return unit in selected_units


## Applies a risen zombie's queued order (build-plan 6a), called by GameManager._raise. The
## stored click is re-resolved through the SAME rule as a live RMB: a living human within
## release_aim_radius → ignite feral toward it (attack-at-rise); otherwise → a calm move.
## If it stays calm AND the corpse was still selected, keep the zombie in the selection.
func apply_rise_order(zombie: Zombie, entry: Dictionary, was_selected: bool) -> void:
	var route: Array = entry.get("queued_route", [])
	if not route.is_empty():
		var gm := _game_manager()
		# The LAST waypoint is re-resolved release-or-move ("attacking is another waypoint"):
		# prey there → walk the earlier moves, THEN attack it (queued_attack); else it's a move.
		var last: Vector2 = route[route.size() - 1]
		var human := _human_at(last, gm)
		var move_count := route.size()
		if human != null:
			move_count -= 1
			zombie.queued_attack = human
		for i in range(move_count):
			if i == 0:
				zombie.set_move_target(route[i])
			else:
				zombie.queue_move(route[i])
	# 6b: join the queued control group, if any — works whether it rose calm or feral (a
	# feral member becomes selectable again once it calms, like any released group member).
	var group: int = entry.get("queued_group", -1)
	if group >= 0:
		_join_control_group(zombie, group)
	if was_selected and zombie.is_selectable():
		add_unit_to_selection(zombie)


## Adds a risen zombie to a control group (build-plan 6b) without disturbing existing members
## and stamps its group number. Used by apply_rise_order for a corpse that was tagged to a group.
func _join_control_group(unit: Node, group_number: int) -> void:
	var g: Array = control_groups.get(group_number, [])
	if unit not in g:
		g.append(unit)
		control_groups[group_number] = g
	unit.set_control_group_number(group_number)


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
