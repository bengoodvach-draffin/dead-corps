class_name FillBehavior
extends Node

## The fill front — armed-defender shot mechanic (build-plan 3.1, spec §4.1).
##
## A behavior component (child node of the Human shell, mirroring the zombie
## component pattern, ARCHITECTURE_GUIDELINES rule 2). Ticked by the Human's
## _physics_process dispatcher for a live armed unit; no _physics_process of its own.
##
## Model (spec §4.1): a scalar fill length grows at the class `fill_speed` while a
## zombie is in awareness range. The visible debug line points at the nearest zombie
## with a CLEAR LANE; when the fill reaches that zombie (length ≥ its distance), the
## human rotates to face it (turn_speed / facing_tolerance — fill frozen during the
## turn) and fires. Firing kills the zombie and resets the fill to zero. The fill
## decays (fill_decay_factor × speed) only when NO zombie is in range at all.
##
## LOS (spec §4.1 extension, 2026-06-17): the lane is blocked by environment AND by
## other humans — an armed human can't shoot through its own ranks. Corpses don't
## block (they drop to collision_layer 0 in die()). If the nearest zombie is screened
## by a friendly, the front targets the next-nearest with a clear lane; if none are
## clear the gun holds hot (no shot) until a lane opens.
##
## Civilians (the one unarmed class) use a pure reaction clock instead (build-plan
## 3.2): no fill/fire — see a clear-lane zombie for civilian_reaction seconds → flee.

## Raycast blocker mask: Environment (1) + Humans (4) + intact-door "DoorLOS"
## blockers (16). Zombies (layer 2) never block — the target is the nearest, so no
## zombie can screen it; excluding it from the mask just keeps the ray from
## tripping on the target/its neighbours. Intact doors block the shot like a wall
## (buildings spec §7.1 — no LOS through a door until breach).
const LOS_BLOCKER_MASK := 21

var _owner: Human = null
var _gm: Node = null

## Current fill-front length in px (a distance). Grows toward the nearest visible
## zombie; resets to 0 on a shot; decays when nothing is in range. The debug line is
## this long. Held (frozen) while screened or while rotating to fire.
var _fill: float = 0.0

## Nearest zombie with a clear lane — what the front points at / will fire on, or null
## (nothing visible). Rendering reads this.
var _target: Zombie = null

## True while the front has reached its target and the human is rotating to face it
## (fill frozen). Drives the debug line color (filling vs about-to-fire).
var _reached: bool = false

## Tracks whether the debug line was drawn last frame, so we issue exactly one extra
## redraw when it clears (and avoid redrawing idle humans every frame).
var _was_drawing: bool = false

## Civilian reaction clock (build-plan 3.2): seconds a clear-lane zombie has been
## visible. At civilian_reaction it triggers the flee. Resets when sight is lost.
var _civ_clock: float = 0.0


func setup(owner_human: Human) -> void:
	_owner = owner_human


## One physics frame, dispatched by class. Armed (Militia/Police/GI) run the fill
## front + fire; the lone unarmed class (Civilian) runs a reaction clock → flee (3.2).
func tick(delta: float) -> void:
	var gm := _game_manager()
	if gm == null:
		return

	var nearest_visible := _nearest_visible_zombie(gm)
	if _owner.is_armed():
		_tick_armed(delta, nearest_visible)
	else:
		_tick_civilian(delta, nearest_visible)

	# Debug-line redraw: only while there's something to draw, plus one frame after.
	var drawing := _fill > 0.0 or _target != null
	if drawing or _was_drawing:
		_owner.queue_redraw()
	_was_drawing = drawing


## Armed fill front: grow toward / fire at the nearest CLEAR-LANE zombie; cool when none
## is visible. Humans block perception as well as the shot (spec §4.1), so a fully
## screened zombie is "not there" for this defender — the gun cools rather than holding
## (the peek/bait exploit is still covered: ANY visible zombie keeps it hot).
func _tick_armed(delta: float, nearest_visible: Zombie) -> void:
	var speed := _fill_speed()
	if nearest_visible != null:
		_target = nearest_visible
		var d := _owner.global_position.distance_to(nearest_visible.global_position)
		if _fill < d:
			# Still filling toward the target — grow (not yet reached).
			_reached = false
			_fill += speed * delta
		else:
			# Reached: rotation gates the shot, fill frozen during the turn (§4.1).
			_reached = true
			if _rotate_toward(nearest_visible, delta):
				_fire(nearest_visible)
	else:
		_reached = false
		_target = null
		_fill = maxf(0.0, _fill - GameConfig.fill_decay_factor * speed * delta)


## Civilian reaction clock (spec §4.1): no fill front, no fire — while a clear-lane
## zombie is visible, count up to civilian_reaction, then flee. The clock resets the
## instant sight is lost (a civilian panics at a present threat, doesn't track). Drives
## the debug line from the clock fraction so it reads like a filling defender that
## bolts instead of firing.
func _tick_civilian(delta: float, nearest_visible: Zombie) -> void:
	if nearest_visible != null:
		_target = nearest_visible
		_civ_clock += delta
		var d := _owner.global_position.distance_to(nearest_visible.global_position)
		var frac := clampf(_civ_clock / GameConfig.civilian_reaction, 0.0, 1.0)
		_fill = frac * d
		_reached = frac >= 1.0
		if _civ_clock >= GameConfig.civilian_reaction:
			_owner.start_fleeing()
	else:
		_civ_clock = 0.0
		_target = null
		_fill = 0.0
		_reached = false


## Nearest zombie within awareness with a clear lane (environment + humans block), or
## null. Shared by the armed front and the civilian clock — both "perceive" the same way.
func _nearest_visible_zombie(gm: Node) -> Zombie:
	var in_range: Array = gm.neighbours_within(_owner.global_position, _awareness(), &"zombies")
	var best: Zombie = null
	var best_d := INF
	for u in in_range:
		var z := u as Zombie
		if z == null or not _has_clear_lane(z):
			continue
		var d := _owner.global_position.distance_to(z.global_position)
		if d < best_d:
			best_d = d
			best = z
	return best


## Resets the front to cold (no fill, no target, civilian clock zeroed) — called when a
## fear break commits (3.3) so no shot lands during the reaction beat and the debug line
## clears. The dispatcher stops ticking us once the break commits / the human flees.
func cancel() -> void:
	_fill = 0.0
	_target = null
	_reached = false
	_civ_clock = 0.0
	_owner.queue_redraw()


# === RENDERING ACCESSORS (read by Human._draw for the debug line, → vision_renderer in 5.1) ===

func fill_length() -> float:
	return _fill


func current_target() -> Zombie:
	return _target


func is_reached() -> bool:
	return _reached


# === INTERNAL ===

## True if no environment or friendly human blocks the straight line to `z`. Uses
## global_position (the Human.has_line_of_sight_to override is local-position based;
## this is the correct cross-unit check). Excludes the firing human and the target.
func _has_clear_lane(z: Zombie) -> bool:
	var space := _owner.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_owner.global_position, z.global_position)
	query.collision_mask = LOS_BLOCKER_MASK
	query.exclude = [_owner, z]
	return space.intersect_ray(query).is_empty()


## Rotates the owner's facing toward `z` at turn_speed; returns true once within
## facing_tolerance (clear to fire). The front holds while this is false (§4.1).
func _rotate_toward(z: Zombie, delta: float) -> bool:
	var to := z.global_position - _owner.global_position
	if to == Vector2.ZERO:
		return true
	var desired := to.normalized()
	var cur := _owner.facing_direction
	if cur == Vector2.ZERO:
		cur = Vector2.RIGHT
	var max_step := deg_to_rad(GameConfig.turn_speed) * delta
	var ang := cur.angle_to(desired)
	if absf(ang) <= max_step:
		_owner.facing_direction = desired
	else:
		_owner.facing_direction = cur.rotated(signf(ang) * max_step)
	return absf(_owner.facing_direction.angle_to(desired)) <= deg_to_rad(GameConfig.facing_tolerance)


## Fires: resets the front and routes the kill through the GameManager (the binary
## kill + the gunfire-death half of violence contagion, spec §3.3). Passes the shooter
## so contagion can send the woken horde at it ("you shot us — we're coming for you").
func _fire(z: Zombie) -> void:
	_fill = 0.0
	_reached = false
	var gm := _game_manager()
	if gm != null:
		gm.report_gunfire_kill(z, _owner)


func _fill_speed() -> float:
	return GameConfig.fill_speed[_owner.defender_class]


func _awareness() -> float:
	return GameConfig.awareness[_owner.defender_class]


## Lazily resolves the GameManager (registry + contagion). Cached after first use.
func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm
