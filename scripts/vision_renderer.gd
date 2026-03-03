extends Node2D
class_name VisionRenderer

## Renders vision cones and circles for units
## Attached to main scene, renders all visible vision areas

## Zombie vision display modes
enum ZombieVisionMode {
	NONE,           # Nothing visible (tab off when nothing selected)
	ALL,            # All zombie vision visible (tab on when nothing selected, or mode 3 when selected)
	SELECTED_ONLY,  # Only selected zombies visible (mode 1 when zombies selected)
	HIDDEN          # All hidden even selected (mode 2 when zombies selected)
}

## Current zombie vision mode
var zombie_vision_mode: ZombieVisionMode = ZombieVisionMode.NONE

## Track selection state to auto-adjust vision mode
var had_selected_zombies_last_frame: bool = false

## Proximity threshold for showing human idle vision (in pixels)
const HUMAN_IDLE_PROXIMITY_THRESHOLD := 200.0

## Colors for different states
const HUMAN_IDLE_COLOR := Color(0.3, 0.5, 1.0, 0.15)  # Light blue
const HUMAN_SENTRY_COLOR := Color(0.5, 0.5, 1.0, 0.2)  # Blue
const HUMAN_FLEEING_COLOR := Color(1.0, 0.3, 0.3, 0.2)  # Red

const ZOMBIE_IDLE_COLOR := Color(0.3, 1.0, 0.3, 0.15)  # Light green
const ZOMBIE_ACTIVE_COLOR := Color(0.5, 1.0, 0.5, 0.2)  # Green

## Line thickness for vision edges
const LINE_WIDTH := 2.0
const MERGED_LINE_WIDTH := 3.5  # Thicker for merged groups

## Group detection parameters
const GROUP_PROXIMITY_THRESHOLD := 80.0  # Units within 80px = same group (increased from 60)
const MIN_GROUP_SIZE := 4  # Need 4+ units to merge vision


func _ready() -> void:
	# Set z-index to render ABOVE everything
	# Raycasting clips vision at buildings, so we don't need z-layering
	z_index = 1


func _input(event: InputEvent) -> void:
	# Toggle/cycle zombie vision with Tab key
	if event is InputEventKey:
		if event.keycode == KEY_TAB and event.pressed and not event.is_echo():
			cycle_zombie_vision_mode()
			queue_redraw()


## Cycles through zombie vision modes based on selection state
func cycle_zombie_vision_mode() -> void:
	# Check if any zombies are selected
	var has_selected_zombies: bool = false
	var zombies := get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie is Zombie and zombie.is_selected:
			has_selected_zombies = true
			break
	
	if has_selected_zombies:
		# 3-state cycle when zombies selected: SELECTED → ALL → HIDDEN
		match zombie_vision_mode:
			ZombieVisionMode.NONE, ZombieVisionMode.SELECTED_ONLY:
				zombie_vision_mode = ZombieVisionMode.ALL
				print("Zombie vision: ALL (everything visible)")
			ZombieVisionMode.ALL:
				zombie_vision_mode = ZombieVisionMode.HIDDEN
				print("Zombie vision: HIDDEN (all hidden)")
			ZombieVisionMode.HIDDEN:
				zombie_vision_mode = ZombieVisionMode.SELECTED_ONLY
				print("Zombie vision: SELECTED ONLY (default)")
	else:
		# 2-state toggle when nothing selected
		if zombie_vision_mode == ZombieVisionMode.NONE:
			zombie_vision_mode = ZombieVisionMode.ALL
			print("Zombie vision: ALL (tab on)")
		else:
			zombie_vision_mode = ZombieVisionMode.NONE
			print("Zombie vision: NONE (tab off)")


func _process(_delta: float) -> void:
	# Check if selection state changed
	var has_selected_zombies := check_any_zombies_selected()
	
	# Auto-adjust vision mode when selection changes
	if has_selected_zombies != had_selected_zombies_last_frame:
		if has_selected_zombies:
			# Just selected zombies - switch to SELECTED_ONLY if currently NONE
			if zombie_vision_mode == ZombieVisionMode.NONE:
				zombie_vision_mode = ZombieVisionMode.SELECTED_ONLY
		else:
			# Just deselected all zombies - switch to NONE if currently SELECTED_ONLY
			if zombie_vision_mode == ZombieVisionMode.SELECTED_ONLY:
				zombie_vision_mode = ZombieVisionMode.NONE
		
		had_selected_zombies_last_frame = has_selected_zombies
	
	# Redraw every frame to update vision
	queue_redraw()


## Helper to check if any zombies are selected
func check_any_zombies_selected() -> bool:
	var zombies := get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie is Zombie and zombie.is_selected:
			return true
	return false


func _draw() -> void:
	# Detect and draw human vision groups (with proximity filtering for idle)
	var humans := get_tree().get_nodes_in_group("humans")
	var human_groups := detect_groups(humans)
	draw_vision_groups(human_groups, true)  # true = is_human
	
	# Detect and draw zombie vision groups (based on mode)
	if zombie_vision_mode != ZombieVisionMode.NONE:
		var zombies := get_tree().get_nodes_in_group("zombies")
		var zombie_groups := detect_groups(zombies)
		draw_vision_groups(zombie_groups, false)  # false = is_zombie


## Detects groups of units in same state within proximity threshold
## Returns array of groups, where each group is: {units: Array, state: State, center: Vector2}
func detect_groups(units: Array) -> Array:
	var groups := []
	var processed := {}  # Track which units we've already grouped
	
	for unit in units:
		if not unit is Unit or unit in processed:
			continue
		
		# Skip units with no vision (dead, grappled, melee)
		var unit_state = get_unit_state(unit)
		if unit_state < 0:  # Invalid/no vision state
			continue
		
		# Find all nearby units in same state
		var group_members := [unit]
		processed[unit] = true
		
		for other in units:
			if other == unit or not other is Unit or other in processed:
				continue
			
			var other_state = get_unit_state(other)
			if other_state != unit_state:
				continue
			
			var distance: float = unit.position.distance_to(other.position)
			if distance <= GROUP_PROXIMITY_THRESHOLD:
				group_members.append(other)
				processed[other] = true
		
		# Calculate group center
		var center := Vector2.ZERO
		for member in group_members:
			center += member.position
		center /= group_members.size()
		
		groups.append({
			"units": group_members,
			"state": unit_state,
			"center": center
		})
	
	return groups


## Gets unit state for grouping purposes
## Returns state value or -1 if unit has no vision
func get_unit_state(unit: Unit) -> int:
	if unit is Human:
		var human := unit as Human
		match human.current_state:
			Human.State.IDLE:
				return 0
			Human.State.SENTRY:
				return 1
			Human.State.FLEEING:
				return 2
			_:
				return -1  # Dead, grappled = no vision
	elif unit is Zombie:
		var zombie := unit as Zombie
		match zombie.current_state:
			Zombie.State.IDLE:
				return 10
			Zombie.State.MOVING:
				return 11
			Zombie.State.PURSUING:
				return 12
			Zombie.State.LEAPING:
				return 13
			_:
				return -1  # Dead, melee = no vision
	return -1


## Determines if a unit's vision should be displayed based on visibility rules
func should_show_vision(unit: Unit, is_human: bool) -> bool:
	if not unit is Unit:
		return false
	
	if is_human:
		var human := unit as Human
		
		# Always show sentry arcs (tactical watching)
		if human.current_state == Human.State.SENTRY:
			return true
		
		# REMOVED: Don't show fleeing arcs (reduces action clutter)
		# if human.current_state == Human.State.FLEEING:
		#     return true
		
		# Show idle ONLY if nearest zombie within 200px (early warning)
		if human.current_state == Human.State.IDLE:
			var nearest_zombie_distance := get_nearest_zombie_distance(human.position)
			return nearest_zombie_distance <= HUMAN_IDLE_PROXIMITY_THRESHOLD
		
		return false  # Don't show FLEEING, GRAPPLED, DEAD
	else:
		# Zombie vision based on mode
		var zombie := unit as Zombie
		
		match zombie_vision_mode:
			ZombieVisionMode.NONE:
				return false
			ZombieVisionMode.HIDDEN:
				return false
			ZombieVisionMode.ALL:
				return true  # Show EVERYTHING (user override)
			ZombieVisionMode.SELECTED_ONLY:
				if not zombie.is_selected:
					return false
				
				# Hide if actively pursuing/locked on target (reduces action clutter)
				# Exception: Show MOVING state (player-commanded movement)
				if zombie.is_locked_in_pursuit:
					return false  # Auto-hunting - hide
				if zombie.current_state == Zombie.State.PURSUING:
					return false  # Chasing - hide
				if zombie.current_state == Zombie.State.LEAPING:
					return false  # Leaping - hide
				
				# Show for: IDLE (tactical planning), MOVING (player control), MELEE
				return true
		
		return false


## Gets distance to nearest zombie from a given position
func get_nearest_zombie_distance(from_pos: Vector2) -> float:
	var zombies := get_tree().get_nodes_in_group("zombies")
	var min_distance := INF
	
	for zombie in zombies:
		if zombie is Zombie:
			var distance: float = from_pos.distance_to(zombie.position)
			if distance < min_distance:
				min_distance = distance
	
	return min_distance


## Draws vision for all groups (merged or individual based on size)
func draw_vision_groups(groups: Array, is_human: bool) -> void:
	for group in groups:
		var units: Array = group.units
		var group_state: int = group.state
		var center: Vector2 = group.center
		
		# For zombies in SELECTED_ONLY mode with groups of 4+:
		# Show entire merged group if ANY zombie in group is selected
		if not is_human and units.size() >= MIN_GROUP_SIZE and zombie_vision_mode == ZombieVisionMode.SELECTED_ONLY:
			# Check if any zombie in this group is selected
			var any_selected := false
			for unit in units:
				if unit is Zombie and unit.is_selected:
					any_selected = true
					break
			
			if any_selected:
				# Show entire merged group vision
				draw_merged_vision(units, group_state, center, is_human)
				continue
			else:
				# No zombies selected in this group - skip entire group
				continue
		
		# For humans in groups of 4+ (idle state):
		# Show entire merged group if ANY human should be visible
		if is_human and units.size() >= MIN_GROUP_SIZE and group_state == 0:  # State 0 = IDLE
			# Check if any human in group should be visible (zombie within 200px)
			var any_visible := false
			for unit in units:
				if should_show_vision(unit, is_human):
					any_visible = true
					break
			
			if any_visible:
				# Show entire merged group vision (not individual arcs)
				draw_merged_vision(units, group_state, center, is_human)
				continue
			else:
				# No humans should be visible - skip entire group
				continue
		
		# Standard visibility filtering for other cases
		var visible_units: Array = []
		for unit in units:
			if should_show_vision(unit, is_human):
				visible_units.append(unit)
		
		# Skip if no visible units
		if visible_units.is_empty():
			continue
		
		if visible_units.size() >= MIN_GROUP_SIZE:
			# Large group - draw merged vision
			draw_merged_vision(visible_units, group_state, center, is_human)
		else:
			# Small group - draw individual vision
			for unit in visible_units:
				if is_human:
					draw_human_vision(unit)
				else:
					draw_zombie_vision(unit)


## Draws merged vision for a group of 4+ units in same state
## Uses bounding circle for idle, wide arc for active states
func draw_merged_vision(units: Array, group_state: int, center: Vector2, is_human: bool) -> void:
	# Determine color based on state
	var color: Color
	var is_circle_state := false
	
	if is_human:
		match group_state:
			0:  # IDLE
				color = HUMAN_IDLE_COLOR
				is_circle_state = true
			1:  # SENTRY
				color = HUMAN_SENTRY_COLOR
			2:  # FLEEING
				color = HUMAN_FLEEING_COLOR
	else:
		match group_state:
			10:  # IDLE
				color = ZOMBIE_IDLE_COLOR
				is_circle_state = true
			11, 12, 13:  # MOVING, PURSUING, LEAPING
				color = ZOMBIE_ACTIVE_COLOR
	
	if is_circle_state:
		# Draw merged circle encompassing all units
		draw_merged_circle(units, center, color)
	else:
		# Draw merged arc based on average facing
		draw_merged_arc(units, center, color, is_human)
	
	# Draw count badge
	draw_count_badge(center, units.size(), color)


## Draws a bounding circle that encompasses all units in group
func draw_merged_circle(units: Array, center: Vector2, color: Color) -> void:
	# Find furthest unit from center
	var max_distance := 0.0
	for unit in units:
		if unit is Unit:
			var distance := center.distance_to(unit.position)
			if distance > max_distance:
				max_distance = distance
	
	# Add buffer (unit vision radius + spacing)
	var radius := max_distance + 110.0  # vision radius + buffer
	
	# Get physics space for raycasting
	var space_state := get_world_2d().direct_space_state
	
	# Draw circle with building clipping using triangle fan approach
	# This avoids polygon triangulation issues with complex clipped shapes
	var segments := 64
	
	# Collect all edge points with raycasting
	var edge_points := PackedVector2Array()
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var target_point := center + direction * radius
		
		# Raycast to check for buildings
		var query := PhysicsRayQueryParameters2D.create(center, target_point)
		query.collision_mask = 1
		query.exclude = []
		
		var result := space_state.intersect_ray(query)
		
		if result.is_empty():
			edge_points.append(target_point)
		else:
			edge_points.append(result.position)
	
	# Draw as individual triangles from center to avoid triangulation issues
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([center, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	# Draw outline with thick line
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), MERGED_LINE_WIDTH)


## Draws a merged arc based on average facing direction of group
func draw_merged_arc(units: Array, center: Vector2, color: Color, is_human: bool) -> void:
	# Calculate average facing direction
	var avg_facing := Vector2.ZERO
	var valid_count := 0
	
	# Get vision range based on type
	var vision_range := 130.0  # Default for zombies
	var vision_angle := 150.0
	
	for unit in units:
		if unit is Zombie:
			var zombie := unit as Zombie
			if zombie.facing_direction.length() > 0.1:
				avg_facing += zombie.facing_direction
				valid_count += 1
			vision_range = zombie.active_vision_range
			vision_angle = zombie.active_vision_angle
		elif unit is Human:
			var human := unit as Human
			if human.facing_direction.length() > 0.1:
				avg_facing += human.facing_direction
				valid_count += 1
			# Humans use flee vision params
			if human.current_state == Human.State.FLEEING:
				vision_range = human.flee_vision_range
				vision_angle = 90.0
	
	if valid_count == 0:
		# Fallback: face right
		avg_facing = Vector2.RIGHT
	else:
		avg_facing /= valid_count
		avg_facing = avg_facing.normalized()
	
	# Find leftmost and rightmost units to determine arc width
	var leftmost_angle := 0.0
	var rightmost_angle := 0.0
	
	for unit in units:
		if unit is Unit:
			var to_unit: Vector2 = (unit.position - center).normalized()
			var angle_diff: float = avg_facing.angle_to(to_unit)
			if angle_diff < leftmost_angle:
				leftmost_angle = angle_diff
			if angle_diff > rightmost_angle:
				rightmost_angle = angle_diff
	
	# Arc should span from leftmost to rightmost, but at least 90 degrees
	var arc_span: float = max(abs(rightmost_angle - leftmost_angle) * 2.0, deg_to_rad(90.0))
	arc_span = min(arc_span, deg_to_rad(vision_angle))  # Cap at vision angle
	
	# Draw the merged arc
	draw_vision_arc_merged(center, avg_facing, vision_range, rad_to_deg(arc_span), color)


## Draws a vision arc with thicker lines (for merged groups)
func draw_vision_arc_merged(pos: Vector2, direction: Vector2, range: float, angle_degrees: float, color: Color) -> void:
	var half_angle := deg_to_rad(angle_degrees / 2.0)
	var start_angle := direction.angle() - half_angle
	var end_angle := direction.angle() + half_angle
	
	# Get physics space for raycasting
	var space_state := get_world_2d().direct_space_state
	
	# Create arc with building clipping using triangle fan approach
	var segments := 36  # Sample every 10 degrees
	
	# Collect all edge points with raycasting
	var edge_points := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / segments
		var angle: float = lerp(start_angle, end_angle, t)
		var direction_at_angle := Vector2(cos(angle), sin(angle))
		var target_point := pos + direction_at_angle * range
		
		# Raycast to check for buildings
		var query := PhysicsRayQueryParameters2D.create(pos, target_point)
		query.collision_mask = 1
		query.exclude = []
		
		var result := space_state.intersect_ray(query)
		
		if result.is_empty():
			edge_points.append(target_point)
		else:
			edge_points.append(result.position)
	
	# Draw as individual triangles from center to avoid triangulation issues
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([pos, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	# Draw arc outline with THICKER line
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), MERGED_LINE_WIDTH)
	
	# Draw direction line (with clipping)
	var dir_target := pos + direction * range
	var query := PhysicsRayQueryParameters2D.create(pos, dir_target)
	query.collision_mask = 1
	query.exclude = []
	var result := space_state.intersect_ray(query)
	
	var dir_end: Vector2 = dir_target if result.is_empty() else result.position
	draw_line(pos, dir_end, color.lightened(0.5), MERGED_LINE_WIDTH)


## Draws a count badge showing number of units in group
func draw_count_badge(center: Vector2, count: int, color: Color) -> void:
	# Draw semi-transparent background circle
	var badge_radius := 15.0
	draw_circle(center, badge_radius, Color(0, 0, 0, 0.6))
	draw_arc(center, badge_radius, 0, TAU, 32, color.lightened(0.5), 2.0)
	
	# Draw count text
	var font_size := 14
	var text := "×" + str(count)
	# Note: Can't easily draw text in _draw() without a font resource
	# For now, just the circle badge is visible
	# TODO: Add proper text rendering if needed


## Draws vision for a human unit
func draw_human_vision(human: Human) -> void:
	# Skip dead or grappled humans (no vision)
	if human.current_state == Human.State.DEAD or human.current_state == Human.State.GRAPPLED:
		return
	
	var pos := human.position
	var color: Color
	
	match human.current_state:
		Human.State.IDLE:
			# Circle vision with building clipping
			color = HUMAN_IDLE_COLOR
			draw_vision_circle(pos, human.idle_vision_radius, color)
		
		Human.State.SENTRY:
			# Arc vision
			color = HUMAN_SENTRY_COLOR
			draw_vision_arc(pos, human.facing_direction, human.sentry_vision_range, 
							human.sentry_vision_angle, color)
		
		Human.State.FLEEING:
			# Forward arc
			color = HUMAN_FLEEING_COLOR
			draw_vision_arc(pos, human.facing_direction, human.flee_vision_range,
							human.flee_vision_angle, color)


## Draws vision for a zombie unit
func draw_zombie_vision(zombie: Zombie) -> void:
	# Skip dead or melee zombies (no vision)
	if zombie.current_state == Zombie.State.DEAD or zombie.current_state == Zombie.State.MELEE:
		return
	
	var pos := zombie.position
	var color: Color
	
	match zombie.current_state:
		Zombie.State.IDLE:
			# Circle vision with building clipping
			color = ZOMBIE_IDLE_COLOR
			draw_vision_circle(pos, zombie.idle_vision_radius, color)
		
		Zombie.State.MOVING, Zombie.State.PURSUING, Zombie.State.LEAPING:
			# Forward arc
			color = ZOMBIE_ACTIVE_COLOR
			draw_vision_arc(pos, zombie.facing_direction, zombie.active_vision_range,
							zombie.active_vision_angle, color)


## Draws a vision arc (cone)
## @param pos: Center position
## @param direction: Direction the arc is facing (normalized)
## @param range: How far the arc extends
## @param angle_degrees: Total angle of the arc
## @param color: Fill color
func draw_vision_arc(pos: Vector2, direction: Vector2, range: float, angle_degrees: float, color: Color) -> void:
	var half_angle := deg_to_rad(angle_degrees / 2.0)
	var start_angle := direction.angle() - half_angle
	var end_angle := direction.angle() + half_angle
	
	# Get physics space for raycasting
	var space_state := get_world_2d().direct_space_state
	
	# Create arc with building clipping using triangle fan approach
	var segments := 36  # Sample every 10 degrees for better accuracy
	
	# Collect all edge points with raycasting
	var edge_points := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / segments
		var angle: float = lerp(start_angle, end_angle, t)
		var direction_at_angle := Vector2(cos(angle), sin(angle))
		var target_point := pos + direction_at_angle * range
		
		# Raycast to check for buildings
		var query := PhysicsRayQueryParameters2D.create(pos, target_point)
		query.collision_mask = 1  # Only hit buildings (layer 1)
		query.exclude = []
		
		var result := space_state.intersect_ray(query)
		
		if result.is_empty():
			# No building in the way - use full range
			edge_points.append(target_point)
		else:
			# Building blocking - clip at collision point
			edge_points.append(result.position)
	
	# Draw as individual triangles from center to avoid triangulation issues
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([pos, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	# Draw arc outline
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), LINE_WIDTH)
	
	# Draw direction line (with clipping)
	var dir_target := pos + direction * range
	var query := PhysicsRayQueryParameters2D.create(pos, dir_target)
	query.collision_mask = 1
	query.exclude = []
	var result := space_state.intersect_ray(query)
	
	var dir_end: Vector2 = dir_target if result.is_empty() else result.position
	draw_line(pos, dir_end, color.lightened(0.5), LINE_WIDTH)


## Draws a vision circle (360°) with building clipping
## @param pos: Center position
## @param radius: Circle radius
## @param color: Fill color
func draw_vision_circle(pos: Vector2, radius: float, color: Color) -> void:
	# Get physics space for raycasting
	var space_state := get_world_2d().direct_space_state
	
	# Draw circle with building clipping using triangle fan approach
	# This avoids polygon triangulation issues with complex clipped shapes
	var segments := 64
	
	# Collect all edge points with raycasting
	var edge_points := PackedVector2Array()
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var target_point := pos + direction * radius
		
		# Raycast to check for buildings
		var query := PhysicsRayQueryParameters2D.create(pos, target_point)
		query.collision_mask = 1  # Only buildings
		query.exclude = []
		
		var result := space_state.intersect_ray(query)
		
		if result.is_empty():
			edge_points.append(target_point)
		else:
			edge_points.append(result.position)
	
	# Draw as individual triangles from center to avoid triangulation issues
	# This is more robust than trying to triangulate a complex polygon
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([pos, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	# Draw outline
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), LINE_WIDTH)

