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

## Seconds until the next shot may land (per-class fire_cooldown, set on firing).
## The front grows freely during it — this is only the close-range rate floor.
var _cooldown: float = 0.0

## Civilian reaction clock (build-plan 3.2): seconds a clear-lane zombie has been
## visible. At civilian_reaction it triggers the flee. Resets when sight is lost.
var _civ_clock: float = 0.0

## The door-watch (buildings spec §7.1, step 5): while the owner shelters in a
## building with an ENGAGED door (ferals in its arc = the lock predicate) that it
## has interior LOS to, the front runs HOT against a virtual target pinned just
## inside that door — no decay, no shot, facing pre-aligned. At breach the first
## zombie through is already inside the front, so it eats a near-instant shot and
## normal fill rules resume (rotation gate, humans-block-LOS, critical distance).
var _watching: bool = false
var _watch_pos: Vector2 = Vector2.ZERO

## Target-scan cadence (perf, 2026-07-30) — the FearDetector pattern: the scan
## (grid query + an LOS ray per candidate) runs every fill_scan_interval, phase
## DetHash-staggered per unit; between scans the cached target holds. The FILL
## MATH stays per-frame — growth, decay, rotation, cooldown, the civilian clock —
## so only acquisition is coarser: a new nearest zombie is noticed up to one
## interval late. A cached target that dies drops immediately (checked per frame,
## cheap); the firing lane is re-verified with one ray at the shot itself, so a
## stale target can never be fired on through a friendly who stepped into line.
const SCAN_SALT := 9203
var _scan_timer: float = 0.0
var _scan_primed: bool = false
var _cached_visible: Zombie = null


func setup(owner_human: Human) -> void:
	_owner = owner_human


## One physics frame, dispatched by class. Armed (Militia/Police/GI) run the fill
## front + fire; the lone unarmed class (Civilian) runs a reaction clock → flee (3.2).
func tick(delta: float) -> void:
	var gm := _game_manager()
	if gm == null:
		return

	var nearest_visible := _scan(gm, delta)
	if _owner.is_armed():
		_tick_armed(delta, nearest_visible)
	else:
		_tick_civilian(delta, nearest_visible)
	# (The old per-frame debug-line redraw is gone — VisionRenderer redraws
	# itself every frame and reads this component's accessors, F4.)


## Armed fill front: grow toward / fire at the nearest CLEAR-LANE zombie; cool when none
## is visible. Humans block perception as well as the shot (spec §4.1), so a fully
## screened zombie is "not there" for this defender — the gun cools rather than holding
## (the peek/bait exploit is still covered: ANY visible zombie keeps it hot).
func _tick_armed(delta: float, nearest_visible: Zombie) -> void:
	var speed := _fill_speed()
	_cooldown = maxf(0.0, _cooldown - delta)
	if nearest_visible != null:
		_watching = false
		_target = nearest_visible
		var d := _owner.global_position.distance_to(nearest_visible.global_position)
		if _fill < d:
			# Still filling toward the target — grow (not yet reached).
			_reached = false
			_fill += speed * delta
		else:
			# Reached: rotation AND the fire cooldown gate the shot; the front
			# holds meanwhile (§4.1). The cooldown is the close-range rate floor —
			# at point-blank the front refills near-instantly, so without it a
			# lone defender machine-gunned whole waves.
			_reached = true
			# The lane re-check is the cadence's safety: the target was clear at
			# scan time, up to fill_scan_interval ago — a friendly may have stepped
			# into the line since. One ray, only at the moment everything else says
			# fire. Blocked → hold; the next scan retargets around the screen.
			if _rotate_toward(nearest_visible.global_position, delta) and _cooldown <= 0.0 \
					and _has_clear_lane(nearest_visible):
				_fire(nearest_visible)
	else:
		_reached = false
		_target = null
		_update_door_watch()
		if _watching:
			# Door-watch (§7.1): hot against the engaged door — grow to the door
			# distance and hold there. No decay, no fire (nothing to kill yet);
			# facing pre-aligns so the at-breach shot is genuinely near-instant.
			var d := _owner.global_position.distance_to(_watch_pos)
			_fill = minf(_fill + speed * delta, d)
			_rotate_toward(_watch_pos, delta)
		else:
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


## The cadence wrapper around _nearest_visible_zombie (see the SCAN constants).
## First tick scans immediately (no blind boot window), then holds the stagger.
func _scan(gm: Node, delta: float) -> Zombie:
	if not _scan_primed:
		_scan_primed = true
		_scan_timer = DetHash.hash01(_owner.unit_uid, SCAN_SALT) * GameConfig.fill_scan_interval
		_cached_visible = _nearest_visible_zombie(gm)
		return _cached_visible
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer += GameConfig.fill_scan_interval
		_cached_visible = _nearest_visible_zombie(gm)
	elif _cached_visible != null and (not is_instance_valid(_cached_visible) or not _cached_visible.is_alive):
		_cached_visible = null   # died between scans — never aim at a corpse
	return _cached_visible


## Nearest zombie within awareness with a clear lane (environment + humans block), or
## null. Shared by the armed front and the civilian clock — both "perceive" the same way.
func _nearest_visible_zombie(gm: Node) -> Zombie:
	var in_range: Array = gm.neighbours_within(_owner.global_position, _awareness(), &"zombies")
	var best: Zombie = null
	var best_d := INF
	for u in in_range:
		var z := u as Zombie
		# COSTUMED specials are invisible to human perception (specials spec
		# §3.2). This one skip covers the whole fill surface: never a fill
		# target, never shot, never holds a gun hot, never gates decay — and
		# the civilian reaction clock shares this scan, so it never trips that
		# either. Checked before the lane ray to save the physics query.
		if z == null or z.is_perception_hidden() or not _has_clear_lane(z):
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
	_watching = false
	_cached_visible = null   # a cold front re-acquires fresh on its next scan


## Selects the door-watch point (§7.1): the nearest ENGAGED door of the owner's
## building with a clear interior lane, or none. Engagement reuses the lock
## predicate — one zone, one truth (§4.2). Deterministic: doors in scene order,
## strict nearest.
func _update_door_watch() -> void:
	_watching = false
	# Only from the defensive position (Ben's ruling): a garrison walking to its
	# spot doesn't aim over its shoulder — it settles first, then trains on the
	# door. Normal fill (real targets through an open breach) stays live mid-walk.
	if not _owner.at_shelter_spot():
		return
	var building: Node = _owner.shelter_building()
	if building == null or not is_instance_valid(building):
		return
	var best_d := INF
	for door in building.doors():
		if not door.is_locked():
			continue
		var p: Vector2 = door.inside_point()
		if not _clear_lane_to_point(p):
			continue
		var d := _owner.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			_watching = true
			_watch_pos = p


# === RENDERING ACCESSORS (read by Human._draw for the debug line, → vision_renderer in 5.1) ===

func fill_length() -> float:
	return _fill


func current_target() -> Zombie:
	return _target


func is_reached() -> bool:
	return _reached


## True while the front is pinned to an engaged door (the door-watch, §7.1).
func watching() -> bool:
	return _watching


func watch_pos() -> Vector2:
	return _watch_pos


# === INTERNAL ===

## True if no environment or friendly human blocks the straight line to `z`.
## global_position-based (as is Human.has_line_of_sight_to since the Tier-4
## cluster fix — this one differs only in its mask). Excludes the firing human
## and the target.
func _has_clear_lane(z: Zombie) -> bool:
	var space := _owner.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_owner.global_position, z.global_position)
	query.collision_mask = LOS_BLOCKER_MASK
	query.exclude = [_owner, z]
	return space.intersect_ray(query).is_empty()


## Lane check to a POINT (the door-watch): same blockers, no target to exclude.
func _clear_lane_to_point(point: Vector2) -> bool:
	var space := _owner.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_owner.global_position, point)
	query.collision_mask = LOS_BLOCKER_MASK
	query.exclude = [_owner]
	return space.intersect_ray(query).is_empty()


## Rotates the owner's facing toward a world point at turn_speed; returns true
## once within facing_tolerance (clear to fire). The front holds while this is
## false (§4.1). Point-based so the door-watch can pre-align too.
func _rotate_toward(point: Vector2, delta: float) -> bool:
	var to := point - _owner.global_position
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
	_cooldown = GameConfig.fire_cooldown[_owner.defender_class]
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
