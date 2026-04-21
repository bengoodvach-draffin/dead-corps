extends Node2D
class_name VisionRenderer

## Renders vision cones and facing indicators for human defender units.
## Zombie vision removed in v0.25.0 — arcs are human-only visual language.
##
## v0.25.1 — Click-to-pin cone system:
##   - No cones shown by default.
##   - Left-click a human to pin their cone. Click again to toggle off.
##     Clicking a different human moves the pin to them.
##   - Clicking a pinned human does NOT clear zombie selection — the click
##     is intercepted before SelectionManager sees it (VisionRenderer sits
##     above SelectionManager in the scene tree).
##   - Press V to show ALL human cones simultaneously (debug mode).
##   - Facing lines always drawn for every living human.
##
## Merged/group cone logic removed entirely in v0.25.1.
## Cohesion force disabled in unit.gd — blobs no longer form.

# === COLORS ===
const HUMAN_IDLE_COLOR           := Color(0.3, 0.5, 1.0, 0.15)
const HUMAN_SENTRY_COLOR         := Color(0.5, 0.5, 1.0, 0.2)
const HUMAN_FLEEING_COLOR        := Color(1.0, 0.3, 0.3, 0.2)
const HUMAN_DETECTION_ZONE_COLOR := Color(0.5, 0.5, 1.0, 0.10)
const HUMAN_SHOOTING_ZONE_COLOR  := Color(0.5, 0.8, 1.0, 0.35)
const HUMAN_FLEE_DETECTION_COLOR := Color(1.0, 0.3, 0.3, 0.10)
const HUMAN_FLEE_SHOOTING_COLOR  := Color(1.0, 0.5, 0.3, 0.35)

const LINE_WIDTH         := 2.0
const FACING_LINE_LENGTH := 20.0
const FACING_LINE_COLOR  := Color(1.0, 1.0, 1.0, 0.9)

## Radius in pixels within which a click registers as hitting a human.
const HUMAN_CLICK_RADIUS := 15.0

# === STATE ===

## The human whose cone is currently pinned (null = no cone shown).
var pinned_human: Node2D = null

## When true, all human cones are shown simultaneously (debug mode, toggle with V).
var show_all_cones: bool = false

## Tracks whether the mouse-down landed on a human, so we can intercept
## the matching mouse-up and avoid letting SelectionManager process it.
var _human_press_detected: bool = false


func _ready() -> void:
	z_index = 1


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	# --- Left mouse button: pin cone on human click ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := get_global_mouse_position()
		var clicked_human := _get_human_at_position(world_pos)

		if event.pressed:
			# Record whether press landed on a human.
			# If so, consume it immediately so SelectionManager never sees it
			# and zombie selection is preserved.
			_human_press_detected = clicked_human != null
			if _human_press_detected:
				get_viewport().set_input_as_handled()
		else:
			# Mouse released — if press was on a human, resolve the pin.
			if _human_press_detected:
				get_viewport().set_input_as_handled()
				_human_press_detected = false
				if clicked_human != null:
					if clicked_human == pinned_human:
						# Same human clicked again — toggle off.
						pinned_human = null
						print("👁️ Vision cone cleared")
					else:
						pinned_human = clicked_human
						print("👁️ Vision cone pinned to: ", clicked_human.name)

	# --- V key: toggle debug mode (all cones) ---
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			show_all_cones = not show_all_cones
			print("👁️ Vision debug: ", "ALL cones visible" if show_all_cones else "single-cone mode")


func _draw() -> void:
	var humans: Array = get_tree().get_nodes_in_group("humans")

	# Guard pinned_human against death between frames.
	if pinned_human != null:
		if not is_instance_valid(pinned_human):
			pinned_human = null
		elif (pinned_human as Human).is_dead:
			pinned_human = null

	# Always draw facing lines for every living human.
	for unit in humans:
		if unit is Human:
			_draw_facing_line(unit as Human)

	# Draw cone(s).
	# Tunnel vision cones always shown — the narrow orange arc is the only
	# visual signal to the player that a GI/Spec Ops has entered tunnel vision.
	for unit in humans:
		if unit is Human:
			var human := unit as Human
			if human.current_state == Human.State.TUNNEL_VISION:
				draw_human_vision(human)

	if show_all_cones:
		# Debug mode: individual cone per human, no merging.
		for unit in humans:
			if unit is Human:
				var human := unit as Human
				if human.current_state != Human.State.TUNNEL_VISION:
					draw_human_vision(human)
	elif pinned_human != null:
		# Only draw pinned cone if not already drawn as tunnel vision above
		if (pinned_human as Human).current_state != Human.State.TUNNEL_VISION:
			draw_human_vision(pinned_human as Human)


# === INTERNAL HELPERS ===

## Returns the nearest living Human within HUMAN_CLICK_RADIUS of world_pos,
## or null if none found.
func _get_human_at_position(world_pos: Vector2) -> Human:
	var humans: Array = get_tree().get_nodes_in_group("humans")
	var closest: Human = null
	var min_dist := HUMAN_CLICK_RADIUS

	for unit in humans:
		if not unit is Human:
			continue
		var human := unit as Human
		if human.is_dead:
			continue
		var dist: float = world_pos.distance_to(human.position)
		if dist < min_dist:
			min_dist = dist
			closest = human

	return closest


## Draws a short white line from the human's centre in their facing direction.
## Skips DEAD and GRAPPLED states. Uses tunnel vision locked direction when active.
func _draw_facing_line(human: Human) -> void:
	if human.is_dead:
		return
	if human.current_state == Human.State.GRAPPLED:
		return

	var direction: Vector2
	if human.current_state == Human.State.TUNNEL_VISION:
		direction = human._tunnel_vision_locked_direction
	else:
		direction = human.facing_direction

	if direction.length() < 0.1:
		return

	var start := human.position
	var end   := human.position + direction.normalized() * FACING_LINE_LENGTH
	draw_line(start, end, FACING_LINE_COLOR, LINE_WIDTH)


# === CONE DRAWING ===

## Draws the appropriate vision shape for a human based on their current state.
func draw_human_vision(human: Human) -> void:
	if human.current_state == Human.State.DEAD:
		return
	if human.current_state == Human.State.GRAPPLED:
		return

	var pos      := human.position
	var is_armed := human.weapon_range > 0.0

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
				draw_vision_arc(pos, human.facing_direction,
								human.sentry_vision_range,
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
				draw_vision_arc(pos, human.facing_direction,
								human.flee_vision_range,
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
								human.sentry_vision_range,
								human.TUNNEL_VISION_ANGLE, tv_outer)


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
	draw_vision_arc(pos, direction, shooting_range,  angle_degrees, inner_color)


func draw_vision_arc(pos: Vector2, direction: Vector2, range: float, angle_degrees: float, color: Color) -> void:
	var half_angle  := deg_to_rad(angle_degrees / 2.0)
	var start_angle := direction.angle() - half_angle
	var end_angle   := direction.angle() + half_angle
	var space_state := get_world_2d().direct_space_state
	var segments    := 36
	var edge_points := PackedVector2Array()

	for i in range(segments + 1):
		var t            := float(i) / segments
		var angle: float  = lerp(start_angle, end_angle, t)
		var dir_at_angle := Vector2(cos(angle), sin(angle))
		var target_point := pos + dir_at_angle * range
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

	# Centre direction line.
	var dir_target := pos + direction * range
	var query2 := PhysicsRayQueryParameters2D.create(pos, dir_target)
	query2.collision_mask = 1
	query2.exclude = []
	var result2 := space_state.intersect_ray(query2)
	var dir_end: Vector2 = dir_target if result2.is_empty() else result2.position
	draw_line(pos, dir_end, color.lightened(0.5), LINE_WIDTH)


func draw_vision_circle(pos: Vector2, radius: float, color: Color) -> void:
	var space_state := get_world_2d().direct_space_state
	var segments    := 64
	var edge_points := PackedVector2Array()

	for i in range(segments + 1):
		var angle     := (float(i) / segments) * TAU
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
