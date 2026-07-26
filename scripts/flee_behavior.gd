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

## Committed exit: the NODE (zone or shelter door — needed to notice it dropping
## out of the exit set, §9 churn), its position, and whether one was found.
var _escape_exit: Node2D = null
var _escape_target: Vector2 = Vector2.ZERO
var _has_escape: bool = false

## Cower detector (3.5, §4.4): the anchor we measure net displacement from, and how long
## we've stayed within cower_min_displacement of it. A full cower_window without escaping
## that radius means we're cornered → cower.
var _cower_ref: Vector2 = Vector2.ZERO
var _cower_elapsed: float = 0.0

## Shelter (buildings spec §6, step 2): the claimed spot this human walks to while
## SHELTERED, and the level's shelter doors (cached once — static per level).
## Arrival slack is ABOVE Unit's ~5px stop so the walker settles instead of orbiting.
const SPOT_ARRIVE: float = 8.0
var _spot_target: Vector2 = Vector2.ZERO

## Flush door-leg ("fix 2"): the just-outside-the-chosen-door waypoint a flushing
## runner clears before heading to its committed exit.
const VIA_ARRIVE: float = 30.0
var _via_point: Vector2 = Vector2.ZERO
var _has_via: bool = false
var _doors_cache: Array = []
var _doors_cached: bool = false


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
	_commit_exit()
	_cower_ref = _owner.global_position
	_cower_elapsed = 0.0


## Picks + commits the current best exit (threat-aware). Used at the break AND on
## a re-path when the committed exit drops out of the set (§9 churn).
## FLUSH DOOR-LEG ("fix 2", Ben's ruling 2026-07-26): committing while inside a
## breached building routes the FIRST leg via that building's best passable door
## (threat-scored like exits), so a runner never paths through the breach when a
## safer door exists — then onward to the exit from there.
func _commit_exit() -> void:
	var exit := _pick_escape_zone()
	_has_via = false
	if exit != null:
		_escape_exit = exit
		_escape_target = exit.global_position
		_has_escape = true
		var via := _pick_flush_door()
		if via != Vector2.INF:
			_via_point = via
			_has_via = true
			_agent.target_position = _via_point
		else:
			_agent.target_position = _escape_target
		print("🔍 FLEE: %s → exit %s at %s" % [_owner.name, exit.name, _escape_target.round()])
	else:
		_escape_exit = null
		_has_escape = false


## True while the committed exit is still a member of the exit set (§9): escape
## zones always are; a shelter door only while intact, unlocked, and its building
## unbreached. Duck-typed — zones have no is_locked.
func _exit_valid(exit: Node2D) -> bool:
	if exit == null or not is_instance_valid(exit):
		return false
	if not exit.has_method("is_locked"):
		return true   # an escape zone never churns
	if not exit.is_intact() or exit.is_locked():
		return false
	var building: Node = exit.building()
	return building != null and building.is_shelter and not building.is_breached()


## Chooses the exit to flee to, from THE unified exit set (escape zones ∪ open
## shelter doors, buildings spec §9). With flee_exit_threat_bias 0 (or no perceived
## threat) it's the plain nearest exit. Otherwise each exit is scored by distance ×
## (1 + bias × alignment-with-threat), so exits BEHIND the breaking horde are
## penalised and the human flees away from the danger instead of straight through
## it. Committed once.
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
	for exit in _owner.get_exit_set():
		var to_exit: Vector2 = exit.global_position - origin
		var dist := to_exit.length()
		var align := 0.0
		if dist > 0.01:
			align = maxf(0.0, to_exit.normalized().dot(threat_dir))
		var score := dist * (1.0 + bias * align)
		if score < best_score:
			best_score = score
			best = exit
	return best


## Direction from the human toward the centroid of perceived zombies — the danger
## it's fleeing. Outdoors: within awareness range, no LOS (spec §4.3). INSIDE A
## BREACHED SHELTER (the flush — Ben's ruling 2026-07-26, mirror of the sight-only
## breach fear): uncapped and SIGHT-gated instead — the awareness cap went blind
## to invaders across a big warehouse, the exit-threat bias switched off, and
## flushed civs charged the breach head-on. They flee what they SAW, however far.
## Re-evaluated per re-path, so the sampling reverts to normal once outside.
func _threat_direction() -> Vector2:
	var gm := _game_manager()
	if gm == null:
		return Vector2.ZERO
	var origin := _owner.global_position
	var sum := Vector2.ZERO
	var count := 0
	if _inside_breached_shelter(origin):
		for u in gm.living_zombies():
			if _owner.has_line_of_sight_to(u):
				sum += u.global_position
				count += 1
	else:
		var awareness: float = GameConfig.awareness[_owner.defender_class]
		for u in gm.neighbours_within(origin, awareness, &"zombies"):
			sum += u.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	var to_threat := (sum / count) - origin
	if to_threat.length() < 0.01:
		return Vector2.ZERO
	return to_threat.normalized()


## The just-outside point of the flushing owner's best passable door, or
## Vector2.INF when not inside a breached building (ordinary breaks skip the
## leg). Doors scored like exits: distance × (1 + bias × alignment-with-threat),
## so the door AWAY from what they saw wins. Passable = fallen/open, or intact
## and unlocked. Deterministic: doors in scene order, strict best.
func _pick_flush_door() -> Vector2:
	var origin := _owner.global_position
	var building: Node2D = null
	for b in _shelter_buildings():
		if is_instance_valid(b) and b.is_breached() and b.contains_point(origin):
			building = b
			break
	if building == null:
		return Vector2.INF
	var threat := _threat_direction()
	var bias := GameConfig.flee_exit_threat_bias
	var best := Vector2.INF
	var best_score := INF
	for door in building.doors():
		var passable: bool = (not door.is_intact()) or (not door.is_locked())
		if not passable:
			continue
		# Mirror inside_point() through the door centre = a point just OUTSIDE.
		var out_point: Vector2 = door.global_position * 2.0 - door.inside_point()
		var to_door := out_point - origin
		var dist := to_door.length()
		var align := 0.0
		if dist > 0.01 and threat != Vector2.ZERO:
			align = maxf(0.0, to_door.normalized().dot(threat))
		var score := dist * (1.0 + bias * align)
		if score < best_score:
			best_score = score
			best = out_point
	return best


## True if `pos` lies inside any breached shelter's footprint — the flush state
## (the fleeing human's building ref is already released by then, so this is
## geometric on purpose; also covers re-paths while still indoors).
func _inside_breached_shelter(pos: Vector2) -> bool:
	for b in _shelter_buildings():
		if is_instance_valid(b) and b.is_breached() and b.contains_point(pos):
			return true
	return false


## The level's shelter buildings, fetched once from the group — static per level.
var _shelters_cache: Array = []
var _shelters_cached: bool = false

func _shelter_buildings() -> Array:
	if not _shelters_cached:
		_shelters_cached = true
		_shelters_cache = _owner.get_tree().get_nodes_in_group("shelter_buildings")
	return _shelters_cache


## One physics frame of the rout. Blends the nav-path direction with the zombie-repulsion
## bend and sets a virtual move target; the Human dispatcher's super._physics_process
## does the actual movement (+ BOID separation).
func tick(delta: float) -> void:
	# Shelter entry (buildings spec §6.1): crossing an intact, unlocked door while
	# FLEEING converts to SHELTERED — the only entry path, checked BEFORE the cower
	# detector so a diving entrant can never cower-trip on the threshold. Human-side
	# polling (not Area2D signals): humans tick in registry order, so same-frame
	# entries claim spots in deterministic order (§10).
	for door in _shelter_doors():
		if door.is_intact() and not door.is_locked() and door.contains_point(_owner.global_position):
			var building: Node = door.building()
			# Only true shelters convert (terrain kit): gates have no building,
			# dumb boxes don't shelter, and a breached building shelters nobody
			# even through its intact doors (§9).
			if building != null and building.is_shelter and not building.is_breached():
				_owner.enter_shelter(building, door)
				return
	# Cower detection (3.5, §4.4): a full cower_window spent within cower_min_displacement
	# of our anchor → cornered → cower. Runs even with no exit (a halted human cowers in
	# place). Net displacement (anchor distance), so ping-ponging in a corner still trips.
	if _owner.global_position.distance_to(_cower_ref) >= GameConfig.cower_min_displacement:
		_cower_ref = _owner.global_position
		_cower_elapsed = 0.0
	elif not _blocked_by_fleeing_human():
		# §8.3 fleeing-queue pause rule: the cower clock does NOT accumulate while
		# our blocking collision is another FLEEING human — a live, draining queue
		# (e.g. a back-door flush) is legitimate non-progress, not "cornered". A
		# wall or a COWERER still runs the clock, so the genuine dead-end cascade
		# survives: the front rank cowers, its blockers' clocks resume, the huddle
		# collapses inward exactly as §4.4 intends. NOTE: currently LATENT — units
		# carry no unit-unit collision (BOID separation only), so this guard can
		# only fire if body collision is ever enabled (work-queue Point 1).
		_cower_elapsed += delta
		if _cower_elapsed >= GameConfig.cower_window:
			_owner.start_cowering()
			return

	# Exit-set churn (§9): the committed exit dropped out (door locked by a feral
	# in its arc, or its building breached) → re-path via the same threat-aware
	# picker. Predicate-driven both ways: a door that clears re-enters the picks,
	# and a human with NO exit keeps watching for one to reopen (bounded — the
	# cower detector corners it within cower_window if nothing opens). The player
	# herds runners by which exits they leave looking open.
	if not _has_escape or not _exit_valid(_escape_exit):
		_commit_exit()

	if not _has_escape:
		_owner.velocity = Vector2.ZERO
		_owner.has_target = false
		return

	var origin := _owner.global_position

	# Flush door-leg ("fix 2"): once through/past the chosen door, head to the exit.
	if _has_via and origin.distance_to(_via_point) <= VIA_ARRIVE:
		_has_via = false
		_agent.target_position = _escape_target

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


# === SHELTER (buildings spec §6, step 2) ===

## Points the nav agent at the claimed spot. Called by Human.enter_shelter.
func begin_sheltered(spot: Vector2) -> void:
	_spot_target = spot
	_agent.target_position = spot


## One physics frame while SHELTERED: nav-walk to the claimed spot (interior walls
## respected), then hold. No herding bend (nothing hunts in here pre-breach) and no
## cower detection — its suspension (§6.1) is simply this method never touching it.
func tick_sheltered(_delta: float) -> void:
	var origin := _owner.global_position
	var remaining := origin.distance_to(_spot_target)
	if remaining <= SPOT_ARRIVE:
		_owner.velocity = Vector2.ZERO
		_owner.has_target = false
		return

	var nav_dir := _agent.get_next_path_position() - origin
	if nav_dir.length() < 0.01:
		nav_dir = _spot_target - origin
	if nav_dir.length() > 0.01:
		nav_dir = nav_dir.normalized()

	_owner.move_speed = GameConfig.human_flee_speed
	# Inside LOOKAHEAD, target the spot itself so the walker settles rather than
	# overshooting on the lookahead carrot.
	if remaining <= LOOKAHEAD:
		_owner.set_move_target(_spot_target)
	else:
		_owner.set_move_target(origin + nav_dir * LOOKAHEAD)


## True once the sheltered owner has reached its claimed spot (the door-watch
## only arms from the defensive position, not mid-walk — Ben's playtest ruling).
func at_spot() -> bool:
	return _owner.global_position.distance_to(_spot_target) <= SPOT_ARRIVE


## §8.3: whether the owner's last movement collision was another FLEEING human
## (see the pause rule in tick). Latent until unit-unit body collision exists.
func _blocked_by_fleeing_human() -> bool:
	var col := _owner.get_last_slide_collision()
	if col == null:
		return false
	var other := col.get_collider() as Human
	return other != null and other.current_state == Human.State.FLEEING


## The level's shelter doors, fetched once from the group (one-time wiring per rule 8;
## shelters are static per level in the PoC — revisit if buildings ever spawn mid-run).
func _shelter_doors() -> Array:
	if not _doors_cached:
		_doors_cached = true
		_doors_cache = _owner.get_tree().get_nodes_in_group("shelter_doors")
	return _doors_cache


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
