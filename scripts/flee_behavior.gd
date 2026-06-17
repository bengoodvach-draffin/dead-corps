class_name FleeBehavior
extends Node

## Permanent rout for a broken Human (build-plan 3.2/3.4, spec §4.3).
##
## A behavior component (child of the Human shell), ticked while the unit is FLEEING.
## On begin() it commits to the nearest escape zone (NO line-of-sight req — they know
## the exits) and never re-picks. Each frame it steers there at human_flee_speed; no
## shooting, no recovery — broken is broken. EscapeZone frees the human on entry, so
## there's no arrival logic here.
##
## Steering = nav path (around buildings) + the HERDING bend (around zombies), 3.4:
##   - A NavigationAgent2D (created here, parented to the human) paths to the exit
##     around walls/buildings on the runtime-baked navmesh.
##   - The route then BENDS away from every zombie within flee_repel_radius (weighted
##     stronger the closer they are, scaled by flee_repel_strength). This is the
##     herding mechanic: positioning your reserve — calm OR feral — bends the runners,
##     so you wall an exit and corner them (→ cower, 3.5).
##
## Obstacle avoidance is for the human only; zombie pursuit is still straight-line
## (the parked nav flag), so a feral chasing a runner around a building can snag.

## How far ahead to place the per-frame steering target (just needs to exceed Unit's
## ~5px arrive threshold so the runner never "arrives" and keeps fleeing).
const LOOKAHEAD: float = 40.0

var _owner: Human = null
var _gm: Node = null
var _agent: NavigationAgent2D = null

## Committed exit (a zone's global_position) and whether one was found.
var _escape_target: Vector2 = Vector2.ZERO
var _has_escape: bool = false


func setup(owner_human: Human) -> void:
	_owner = owner_human
	# Our own nav agent (the human scene has none). Avoidance off — we do our own
	# steering (the herding blend); the agent only supplies the around-walls path.
	_agent = NavigationAgent2D.new()
	_agent.avoidance_enabled = false
	_agent.path_desired_distance = 8.0
	_agent.target_desired_distance = 8.0
	_owner.add_child(_agent)


## Commits the rout: lock the best exit (no LOS, spec §4.3) and point the nav agent at
## it. Called once when the human breaks. No exit at all → the human just halts.
func begin() -> void:
	var zone := _pick_escape_zone()
	if zone != null:
		_escape_target = zone.global_position
		_has_escape = true
		_agent.target_position = _escape_target
	else:
		_has_escape = false


## Chooses the exit to flee to. With flee_exit_threat_bias 0 (or no perceived threat)
## it's the plain nearest exit. Otherwise each exit is scored by distance × (1 + bias ×
## alignment-with-threat), so exits BEHIND the breaking horde are penalised and the
## human flees away from the danger instead of straight through it. Committed once.
func _pick_escape_zone() -> Node2D:
	var bias := GameConfig.flee_exit_threat_bias
	if bias <= 0.0:
		return _owner.get_nearest_escape_zone()   # OFF — pure nearest, no threat consideration

	var threat_dir := _threat_direction()
	if threat_dir == Vector2.ZERO:
		return _owner.get_nearest_escape_zone()   # nothing nearby to flee from

	var origin := _owner.global_position
	var best: Node2D = null
	var best_score := INF
	for zone in _owner.get_tree().get_nodes_in_group("escape_zone"):
		if not is_instance_valid(zone):
			continue
		var to_zone: Vector2 = (zone as Node2D).global_position - origin
		var dist := to_zone.length()
		var align := 0.0
		if dist > 0.01:
			align = maxf(0.0, to_zone.normalized().dot(threat_dir))
		var score := dist * (1.0 + bias * align)
		if score < best_score:
			best_score = score
			best = zone
	return best


## Direction from the human toward the centroid of perceived zombies (within its
## awareness range, no LOS) — the danger it's fleeing. Zero if none are nearby.
func _threat_direction() -> Vector2:
	var gm := _game_manager()
	if gm == null:
		return Vector2.ZERO
	var origin := _owner.global_position
	var awareness: float = GameConfig.awareness[_owner.defender_class]
	var sum := Vector2.ZERO
	var count := 0
	for u in gm.neighbours_within(origin, awareness, &"zombies"):
		sum += u.global_position
		count += 1
	if count == 0:
		return Vector2.ZERO
	var to_threat := (sum / count) - origin
	if to_threat.length() < 0.01:
		return Vector2.ZERO
	return to_threat.normalized()


## One physics frame of the rout. Blends the nav-path direction with the zombie-repulsion
## bend and sets a virtual move target; the Human dispatcher's super._physics_process
## does the actual movement (+ BOID separation).
func tick(_delta: float) -> void:
	if not _has_escape:
		_owner.velocity = Vector2.ZERO
		_owner.has_target = false
		return

	var origin := _owner.global_position

	# Nav path toward the exit (around buildings). If the path isn't ready/empty, the
	# next point is ~our own position → fall back to a straight line at the exit.
	var nav_dir := _agent.get_next_path_position() - origin
	if nav_dir.length() < 0.01:
		nav_dir = _escape_target - origin
	if nav_dir.length() > 0.01:
		nav_dir = nav_dir.normalized()

	# Herding bend: steer away from nearby zombies, scaled by the herdability dial.
	var steer := nav_dir + _zombie_repulsion(origin) * GameConfig.flee_repel_strength
	if steer.length() < 0.01:
		steer = nav_dir   # fully balanced out (rare) → just hold the nav heading
	if steer.length() > 0.01:
		steer = steer.normalized()

	_owner.move_speed = GameConfig.human_flee_speed
	_owner.set_move_target(origin + steer * LOOKAHEAD)


## Sum of "away from zombie" vectors for every living zombie within flee_repel_radius,
## each weighted stronger the closer it is (linear falloff to 0 at the radius). Both
## calm and feral zombies repel — that's what lets the player herd with the reserve.
func _zombie_repulsion(origin: Vector2) -> Vector2:
	var gm := _game_manager()
	if gm == null:
		return Vector2.ZERO
	var radius := GameConfig.flee_repel_radius
	var repel := Vector2.ZERO
	for u in gm.neighbours_within(origin, radius, &"zombies"):
		var away: Vector2 = origin - u.global_position
		var d := away.length()
		if d > 0.01:
			repel += away.normalized() * (1.0 - d / radius)
	return repel


## Lazily resolves the GameManager (the unit registry). Cached after first use.
func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm
