extends Node2D
class_name VisionRenderer

## Renders vision cones and circles for human defender units.
## Zombie vision removed in v0.25.0 — arcs are human-only visual language.
## Humans: always show SENTRY and TUNNEL_VISION arcs; show IDLE circle when
## a zombie is within 200px (early warning); FLEEING arcs suppressed (reduces clutter).

## Proximity threshold for showing human idle vision (in pixels)
const HUMAN_IDLE_PROXIMITY_THRESHOLD := 200.0

## Colors
const HUMAN_IDLE_COLOR := Color(0.3, 0.5, 1.0, 0.15)
const HUMAN_SENTRY_COLOR := Color(0.5, 0.5, 1.0, 0.2)
const HUMAN_FLEEING_COLOR := Color(1.0, 0.3, 0.3, 0.2)

## Dual-zone arc colors (armed humans only)
const HUMAN_DETECTION_ZONE_COLOR := Color(0.5, 0.5, 1.0, 0.10)
const HUMAN_SHOOTING_ZONE_COLOR  := Color(0.5, 0.8, 1.0, 0.35)
const HUMAN_FLEE_DETECTION_COLOR := Color(1.0, 0.3, 0.3, 0.10)
const HUMAN_FLEE_SHOOTING_COLOR  := Color(1.0, 0.5, 0.3, 0.35)

const LINE_WIDTH := 2.0
const MERGED_LINE_WIDTH := 3.5

const GROUP_PROXIMITY_THRESHOLD := 80.0
const MIN_GROUP_SIZE := 4


func _ready() -> void:
	z_index = 1


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var humans := get_tree().get_nodes_in_group("humans")
	var human_groups := detect_groups(humans)
	draw_vision_groups(human_groups)


## Detects groups of humans in the same state within proximity threshold
func detect_groups(units: Array) -> Array:
	var groups := []
	var processed := {}
	
	for unit in units:
		if not unit is Unit or unit in processed:
			continue
		
		var unit_state = get_unit_state(unit)
		if unit_state < 0:
			continue
		
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


## Gets human state for grouping. Returns -1 if unit has no displayable vision.
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
			Human.State.TUNNEL_VISION:
				return 3
			_:
				return -1
	return -1


## Whether a human's vision should be displayed
func should_show_vision(unit: Unit) -> bool:
	if not unit is Human:
		return false
	var human := unit as Human
	
	if human.current_state == Human.State.SENTRY:
		return true
	if human.current_state == Human.State.TUNNEL_VISION:
		return true
	if human.current_state == Human.State.IDLE:
		var nearest_zombie_distance := get_nearest_zombie_distance(human.position)
		return nearest_zombie_distance <= HUMAN_IDLE_PROXIMITY_THRESHOLD
	
	return false


func get_nearest_zombie_distance(from_pos: Vector2) -> float:
	var zombies := get_tree().get_nodes_in_group("zombies")
	var min_distance := INF
	for zombie in zombies:
		if zombie is Zombie:
			var distance: float = from_pos.distance_to(zombie.position)
			if distance < min_distance:
				min_distance = distance
	return min_distance


func draw_vision_groups(groups: Array) -> void:
	for group in groups:
		var units: Array = group.units
		var group_state: int = group.state
		var center: Vector2 = group.center
		
		# For idle groups of 4+: show merged if any member should be visible
		if units.size() >= MIN_GROUP_SIZE and group_state == 0:
			var any_visible := false
			for unit in units:
				if should_show_vision(unit):
					any_visible = true
					break
			if any_visible:
				draw_merged_vision(units, group_state, center)
			continue
		
		# Standard visibility filtering
		var visible_units: Array = []
		for unit in units:
			if should_show_vision(unit):
				visible_units.append(unit)
		
		if visible_units.is_empty():
			continue
		
		if visible_units.size() >= MIN_GROUP_SIZE:
			draw_merged_vision(visible_units, group_state, center)
		else:
			for unit in visible_units:
				draw_human_vision(unit)


func draw_merged_vision(units: Array, group_state: int, center: Vector2) -> void:
	var color: Color
	var is_circle_state := false
	
	match group_state:
		0:  # IDLE
			color = HUMAN_IDLE_COLOR
			is_circle_state = true
		1:  # SENTRY
			color = HUMAN_SENTRY_COLOR
		2:  # FLEEING
			color = HUMAN_FLEEING_COLOR
	
	if is_circle_state:
		draw_merged_circle(units, center, color)
	else:
		draw_merged_arc(units, center, color)
	
	draw_count_badge(center, units.size(), color)


func draw_merged_circle(units: Array, center: Vector2, color: Color) -> void:
	var max_distance := 0.0
	for unit in units:
		if unit is Unit:
			var distance := center.distance_to(unit.position)
			if distance > max_distance:
				max_distance = distance
	
	var radius := max_distance + 110.0
	var space_state := get_world_2d().direct_space_state
	var segments := 64
	var edge_points := PackedVector2Array()
	
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var target_point := center + direction * radius
		var query := PhysicsRayQueryParameters2D.create(center, target_point)
		query.collision_mask = 1
		query.exclude = []
		var result := space_state.intersect_ray(query)
		edge_points.append(target_point if result.is_empty() else result.position)
	
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([center, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), MERGED_LINE_WIDTH)


func draw_merged_arc(units: Array, center: Vector2, color: Color) -> void:
	var avg_facing := Vector2.ZERO
	var valid_count := 0
	var vision_range := 350.0
	var vision_angle := 90.0
	
	for unit in units:
		if unit is Human:
			var human := unit as Human
			if human.facing_direction.length() > 0.1:
				avg_facing += human.facing_direction
				valid_count += 1
			if human.current_state == Human.State.FLEEING:
				vision_range = human.flee_vision_range
				vision_angle = 90.0
	
	if valid_count == 0:
		avg_facing = Vector2.RIGHT
	else:
		avg_facing = (avg_facing / valid_count).normalized()
	
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
	
	var arc_span: float = max(abs(rightmost_angle - leftmost_angle) * 2.0, deg_to_rad(90.0))
	arc_span = min(arc_span, deg_to_rad(vision_angle))
	
	draw_vision_arc_merged(center, avg_facing, vision_range, rad_to_deg(arc_span), color)


func draw_vision_arc_merged(pos: Vector2, direction: Vector2, range: float, angle_degrees: float, color: Color) -> void:
	var half_angle := deg_to_rad(angle_degrees / 2.0)
	var start_angle := direction.angle() - half_angle
	var end_angle := direction.angle() + half_angle
	var space_state := get_world_2d().direct_space_state
	var segments := 36
	var edge_points := PackedVector2Array()
	
	for i in range(segments + 1):
		var t := float(i) / segments
		var angle: float = lerp(start_angle, end_angle, t)
		var direction_at_angle := Vector2(cos(angle), sin(angle))
		var target_point := pos + direction_at_angle * range
		var query := PhysicsRayQueryParameters2D.create(pos, target_point)
		query.collision_mask = 1
		query.exclude = []
		var result := space_state.intersect_ray(query)
		edge_points.append(target_point if result.is_empty() else result.position)
	
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([pos, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), MERGED_LINE_WIDTH)
	
	var dir_target := pos + direction * range
	var query := PhysicsRayQueryParameters2D.create(pos, dir_target)
	query.collision_mask = 1
	query.exclude = []
	var result := space_state.intersect_ray(query)
	var dir_end: Vector2 = dir_target if result.is_empty() else result.position
	draw_line(pos, dir_end, color.lightened(0.5), MERGED_LINE_WIDTH)


func draw_count_badge(center: Vector2, count: int, color: Color) -> void:
	var badge_radius := 15.0
	draw_circle(center, badge_radius, Color(0, 0, 0, 0.6))
	draw_arc(center, badge_radius, 0, TAU, 32, color.lightened(0.5), 2.0)


func draw_human_vision(human: Human) -> void:
	if human.current_state == Human.State.DEAD or human.current_state == Human.State.GRAPPLED:
		return
	
	var pos := human.position
	var is_armed: bool = human.weapon_range > 0.0
	
	match human.current_state:
		Human.State.IDLE:
			draw_vision_circle(pos, human.idle_vision_radius, HUMAN_IDLE_COLOR)
		
		Human.State.SENTRY:
			if is_armed:
				draw_vision_arc_dual_zone(
					pos, human.facing_direction,
					human.sentry_vision_range, human.weapon_range,
					human.sentry_vision_angle,
					HUMAN_DETECTION_ZONE_COLOR, HUMAN_SHOOTING_ZONE_COLOR
				)
			else:
				draw_vision_arc(pos, human.facing_direction, human.sentry_vision_range,
								human.sentry_vision_angle, HUMAN_SENTRY_COLOR)
		
		Human.State.FLEEING:
			if is_armed:
				draw_vision_arc_dual_zone(
					pos, human.facing_direction,
					human.flee_vision_range, human.weapon_range,
					human.flee_vision_angle,
					HUMAN_FLEE_DETECTION_COLOR, HUMAN_FLEE_SHOOTING_COLOR
				)
			else:
				draw_vision_arc(pos, human.facing_direction, human.flee_vision_range,
								human.flee_vision_angle, HUMAN_FLEEING_COLOR)
		
		Human.State.TUNNEL_VISION:
			var tv_outer := Color(1.0, 0.5, 0.1, 0.12)
			var tv_inner := Color(1.0, 0.6, 0.1, 0.45)
			if is_armed:
				draw_vision_arc_dual_zone(
					pos, human._tunnel_vision_locked_direction,
					human.sentry_vision_range, human.weapon_range,
					human.TUNNEL_VISION_ANGLE,
					tv_outer, tv_inner
				)
			else:
				draw_vision_arc(pos, human._tunnel_vision_locked_direction,
								human.sentry_vision_range, human.TUNNEL_VISION_ANGLE, tv_outer)


func draw_vision_arc_dual_zone(
	pos: Vector2,
	direction: Vector2,
	detection_range: float,
	shooting_range: float,
	angle_degrees: float,
	outer_color: Color,
	inner_color: Color
) -> void:
	draw_vision_arc(pos, direction, detection_range, angle_degrees, outer_color)
	draw_vision_arc(pos, direction, shooting_range, angle_degrees, inner_color)


func draw_vision_arc(pos: Vector2, direction: Vector2, range: float, angle_degrees: float, color: Color) -> void:
	var half_angle := deg_to_rad(angle_degrees / 2.0)
	var start_angle := direction.angle() - half_angle
	var end_angle := direction.angle() + half_angle
	var space_state := get_world_2d().direct_space_state
	var segments := 36
	var edge_points := PackedVector2Array()
	
	for i in range(segments + 1):
		var t := float(i) / segments
		var angle: float = lerp(start_angle, end_angle, t)
		var direction_at_angle := Vector2(cos(angle), sin(angle))
		var target_point := pos + direction_at_angle * range
		var query := PhysicsRayQueryParameters2D.create(pos, target_point)
		query.collision_mask = 1
		query.exclude = []
		var result := space_state.intersect_ray(query)
		edge_points.append(target_point if result.is_empty() else result.position)
	
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([pos, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), LINE_WIDTH)
	
	var dir_target := pos + direction * range
	var query := PhysicsRayQueryParameters2D.create(pos, dir_target)
	query.collision_mask = 1
	query.exclude = []
	var result := space_state.intersect_ray(query)
	var dir_end: Vector2 = dir_target if result.is_empty() else result.position
	draw_line(pos, dir_end, color.lightened(0.5), LINE_WIDTH)


func draw_vision_circle(pos: Vector2, radius: float, color: Color) -> void:
	var space_state := get_world_2d().direct_space_state
	var segments := 64
	var edge_points := PackedVector2Array()
	
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var target_point := pos + direction * radius
		var query := PhysicsRayQueryParameters2D.create(pos, target_point)
		query.collision_mask = 1
		query.exclude = []
		var result := space_state.intersect_ray(query)
		edge_points.append(target_point if result.is_empty() else result.position)
	
	for i in range(edge_points.size() - 1):
		var triangle := PackedVector2Array([pos, edge_points[i], edge_points[i + 1]])
		draw_colored_polygon(triangle, color)
	
	if edge_points.size() > 1:
		draw_polyline(edge_points, color.lightened(0.3), LINE_WIDTH)
