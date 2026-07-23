class_name FeralBrain
extends Node

## Autonomous hunting for a FERAL Zombie — build-plan 2.2/2.3 (spec §3.4).
##
## A behavior component (child node of the Zombie shell), ticked by the shell's
## _tick_feral dispatcher. Owns the current target, pursuit, RETARGETING, and the
## no-progress failsafe. Reports the shell which action to take each frame (rule 5);
## never touches the PounceBehavior directly (rule 2 — the shell mediates).
##
## Retarget (§3.4): on a dead/lost target or a fired failsafe, take the NEAREST of
## { local scan: living humans within chain_scan_radius, LOS-gated }
## ∪ { hunt pool: humans pursued by any feral, plus FLEEING humans (Phase 3) },
## excluding humans under an in-flight pounce. Empty → NO_TARGET (shell calms).
##
## PHASE-3 SEAM: FLEEING and cowering humans don't exist yet, so the pool is
## effectively {pursued} for now. Cowering, once it exists (3.5), is local-scan
## only — add that exclusion to the pool loops then.

## What the shell should do after this frame.
enum Result {
	PURSUING,
	READY_TO_POUNCE,
	NO_TARGET,
}

var _owner: Zombie = null
var _target: Human = null
var _gm: Node = null

## BREACHING (buildings spec §5): the siege sub-state. The building is a prey
## PROXY, not a tracked target — set when pursued prey shelters (§5.1) or by
## release-at-the-building. _siege_door is this feral's own nearest door.
var _siege_building: Node2D = null
var _siege_door: Node2D = null
## Countdown to the next pound; starts DetHash-staggered so a crowd never
## strikes in robotic unison (§4.3). No RNG.
var _pound_timer: float = 0.0

## No-progress failsafe (§3.4.4): if distance-to-target hasn't dropped by
## failsafe_min_progress over a failsafe_window, the feral gives up the hunt and
## calms. Should never fire in normal play — the safety net for a wedged feral.
var _progress_ref_dist: float = INF
var _progress_timer: float = 0.0

## Peel-off cadence (§2.4): countdown to the next opportunistic divert scan. Starts at
## 0 so a freshly-released feral peels onto its nearest fresh straggler immediately.
var _divert_timer: float = 0.0


func setup(owner_zombie: Zombie) -> void:
	_owner = owner_zombie


## Sets the pursued target (release seed or retarget). Reports the pursuit to the
## GameManager hunt pool and resets the failsafe window.
func set_target(human: Human) -> void:
	if _target == human:
		return
	_release_pursuit()
	_target = human
	if human != null:
		_game_manager().add_pursuit(human)
		_progress_ref_dist = _owner.global_position.distance_to(human.global_position)
		_progress_timer = GameConfig.failsafe_window


func current_target() -> Human:
	return _target


## Drops the target and leaves the hunt pool (calming / dying). Ends any siege.
func clear() -> void:
	_release_pursuit()
	_target = null
	_end_siege()


## Release-at-the-building (spec §5.1 + the footprint amendment): ignite straight
## into a siege of `building` at this feral's own nearest door. The peel scan
## stays live en route — it may abandon the door for live prey (§5.1, correctly).
func set_siege(building: Node2D) -> void:
	_release_pursuit()
	_target = null
	_begin_siege(building)


## One frame of hunting. Returns the action the shell should take.
func tick(delta: float) -> Result:
	# BREACHING (buildings spec §5): besieging a shelter — the door is the
	# lowest-priority prey. Handled in its own branch; no pounce, no failsafe.
	if _siege_building != null:
		return _tick_breaching(delta)

	# Validate the current target; if it's gone (dead/lost), retarget — the
	# kill-driven chain.
	if not _target_valid():
		# Prey dove into an intact shelter (§5.1): the BUILDING becomes the prey
		# proxy — transition to BREACHING at our own nearest door. The pursuit
		# claim does not follow humans through walls.
		if _target_safely_sheltered():
			var building := _target.shelter_building()
			clear()
			_begin_siege(building)
			return _tick_breaching(delta)
		if not _retarget():
			return Result.NO_TARGET
	else:
		# Target still alive: peel onto a closer FRESH straggler if one crosses our
		# path (continuous opportunistic retarget, §2.4), then run the wedged-feral
		# failsafe. No tangible progress for a window = wedged (no pursuit pathing
		# yet) → give up and return to the reserve, rather than loop forever on an
		# unreachable target. The real fix is pursuit pathing (flagged); once that
		# lands a real chase closes ~400px in 2s so this rarely fires.
		_maybe_divert(delta)
		if _check_failsafe(delta):
			return Result.NO_TARGET

	var dist := _owner.global_position.distance_to(_target.global_position)
	# Pounce only if in range AND no other feral has it claimed in-flight — keep
	# pursuing a claimed target (we'll retarget when it dies), but don't waste a
	# second pounce on it (§3.4.2 / §3.5).
	if dist <= GameConfig.pounce_range and not _target.is_pounce_claimed():
		return Result.READY_TO_POUNCE

	# Nav-pathed pursuit — routes around buildings/walls toward the prey (the final
	# ~pounce_range closes straight-line, handled by the range check above).
	_owner.nav_move_toward(_target.global_position, GameConfig.zombie_speed)
	return Result.PURSUING


# === BREACHING (buildings spec §5, slice-1 step 3) ===

## One frame of the siege. Order matters: peel first (§5.2.1 — live prey beats
## the door, always), then siege validity, then press-and-pound.
func _tick_breaching(delta: float) -> Result:
	# 1. The continuous peel-off stays LIVE: on the normal cadence, any fresh
	#    prey in scan+LOS pulls this feral off the door instantly. Ranked by
	#    plain nearest — a pounder has no meaningful heading.
	_divert_timer -= delta
	if _divert_timer <= 0.0:
		_divert_timer = GameConfig.feral_divert_interval
		var prey := _best_prey_off_door()
		if prey != null:
			_end_siege()
			set_target(prey)
			return Result.PURSUING

	# 2. Siege validity. An emptied building ends its siege (§5.2.4): no prey
	#    proxy without prey — retarget or calm.
	if _siege_building == null or not is_instance_valid(_siege_building) \
			or not _siege_building.is_occupied():
		_end_siege()
		if not _retarget():
			return Result.NO_TARGET
		return Result.PURSUING

	# 2b. BREACHED: the siege COMMITS (Ben's pour-in ruling, 2026-07-23) — the
	#     besiegers enter and hunt until nobody inside remains. Normal retarget
	#     first (nearer outside prey still wins, §3.4); occupants aren't in the
	#     global pool though (not fleeing, not pursued), so when the scan comes
	#     up empty take the NEAREST living occupant, no LOS gate — we've been
	#     pounding after them, we know they're in there. Once one feral pursues
	#     an occupant it's in the pool, and the rest converge normally.
	if _siege_door == null or not is_instance_valid(_siege_door) or _siege_door.is_breached():
		var building := _siege_building
		_end_siege()
		if _retarget():
			return Result.PURSUING
		var occupant := _nearest_occupant(building)
		if occupant != null:
			set_target(occupant)
			return Result.PURSUING
		return Result.NO_TARGET

	# 3. Press the door and pound (§4.3). Nav-pathed; the zombie barrier stops us
	#    inside the engagement arc. NO distance-progress failsafe here (§5.4.1 —
	#    a besieger's progress is door damage, guaranteed by the cadence).
	_owner.nav_move_toward(_siege_door.global_position, GameConfig.zombie_speed)
	if _siege_door.in_engagement_arc(_owner.global_position):
		_pound_timer -= delta
		if _pound_timer <= 0.0:
			_pound_timer += GameConfig.pound_interval
			_siege_door.apply_pound(GameConfig.pound_damage)
	return Result.PURSUING


## Starts a siege of `building` at this feral's own nearest intact door (§5.1 —
## nearest-door-per-feral; no coordination, so envelopment besieges multiple
## doors emergently). Doorless/invalid building → no siege (caller falls through
## to normal rules next tick).
func _begin_siege(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		return
	var door := _nearest_door(building)
	if door == null:
		return
	_siege_building = building
	_siege_door = door
	# First pound lands after a DetHash-staggered fraction of the interval (§4.3).
	_pound_timer = DetHash.hash01(_owner.unit_uid, 4501) * GameConfig.pound_interval
	print("🔍 SIEGE: %s besieges %s at %s" % [_owner.name, building.name, door.name])


func _end_siege() -> void:
	_siege_building = null
	_siege_door = null


func is_breaching() -> bool:
	return _siege_building != null


## This feral's nearest intact door of `building`, by NAV distance (a back door
## through a wall is not "near"). Deterministic: fixed mesh, scene-order ties.
func _nearest_door(building: Node2D) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for door in building.doors():
		if not door.is_intact():
			continue
		var d := _nav_distance(_owner.global_position, door.global_position)
		if d < best_dist:
			best_dist = d
			best = door
	return best


## Nav-path length between two global points (falls back to straight-line if no
## path resolves).
func _nav_distance(from_pos: Vector2, to_pos: Vector2) -> float:
	var map := _owner.get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(map, from_pos, to_pos, true)
	if path.size() < 2:
		return from_pos.distance_to(to_pos)
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


## Fresh prey worth abandoning the door for (§5.2.1): alive, unclaimed,
## un-pursued, in scan radius with LOS — plain nearest (no forward gate: the
## farmhouse horde turns as one when the guy runs for the truck).
func _best_prey_off_door() -> Human:
	var gm := _game_manager()
	if gm == null:
		return null
	var best: Human = null
	var best_dist := INF
	for u in gm.neighbours_within(_owner.global_position, GameConfig.chain_scan_radius, &"humans"):
		var h := u as Human
		if not _is_candidate(h) or gm.is_pursued(h):
			continue
		if not _owner.has_line_of_sight_to(h):
			continue
		var d := _owner.global_position.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h
	return best


## Nearest valid living occupant of `building` (pour-in ruling): candidates in
## arrival order, strict nearest — deterministic. Pounce-claimed ones excluded
## per the normal exclusion (§3.5).
func _nearest_occupant(building: Node2D) -> Human:
	if building == null or not is_instance_valid(building):
		return null
	var best: Human = null
	var best_dist := INF
	for occ in building.living_occupants():
		var h := occ as Human
		if not _is_candidate(h):
			continue
		var d := _owner.global_position.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h
	return best


## True if the (lost) target is alive but SAFELY sheltered — the §5.1 trigger to
## convert this pursuit into a siege of its building.
func _target_safely_sheltered() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_alive \
		and _target.is_safely_sheltered()


# === INTERNAL ===

## Continuous opportunistic retarget — the "peel-off" (§2.4). On a cadence, if a FRESH
## straggler is meaningfully closer than the current target, peel onto it. Switching
## pursues→claims it (pursuit count → 1), so other ferals' scans skip it: the nearest
## feral peels while the bulk keeps its momentum. No cone/facing — "forward" is
## emergent (living prey sits ahead of the wave, corpses behind), so nearest-fresh
## naturally trends into the crowd. Hysteresis avoids target jitter.
func _maybe_divert(delta: float) -> void:
	_divert_timer -= delta
	if _divert_timer > 0.0:
		return
	_divert_timer = GameConfig.feral_divert_interval
	var candidate := _best_fresh_human()
	if candidate == null:
		return
	# Switch only if the candidate is a meaningfully better PATH target than the current
	# one — so the feral keeps driving up its vector and eats front-to-back, rather than
	# splaying onto whatever side human is merely nearest.
	var heading := _heading()
	var cur_score := FeralTargeting.path_score(_owner.global_position, heading, _target.global_position)
	var cand_score := FeralTargeting.path_score(_owner.global_position, heading, candidate.global_position)
	if cand_score < cur_score * GameConfig.feral_divert_hysteresis:
		set_target(candidate)


## Nearest alive + unclaimed + UN-pursued + in-LOS human within chain_scan_radius, or
## null. "Un-pursued" (no other feral already on it) is what makes the peel one-per-
## straggler. Candidates arrive in unit_uid order so distance ties resolve
## deterministically (§10).
## Best FRESH straggler to peel onto — alive, unclaimed, un-pursued, in-LOS, ahead of
## our motion, within scan radius — ranked by path-score (on-axis-forward beats off-
## axis), or null. Behind humans are HARD-skipped (not just penalised): if the only
## fresh prey is behind, we don't peel — we keep driving toward the current target.
func _best_fresh_human() -> Human:
	var gm := _game_manager()
	if gm == null:
		return null
	var heading := _heading()
	var best: Human = null
	var best_score := INF
	for u in gm.neighbours_within(_owner.global_position, GameConfig.chain_scan_radius, &"humans"):
		var h := u as Human
		if not _is_candidate(h) or gm.is_pursued(h):
			continue
		if not _is_forward(h, heading):
			continue   # behind the swarm's motion — don't peel backwards out of it
		if not _owner.has_line_of_sight_to(h):
			continue
		var s := FeralTargeting.path_score(_owner.global_position, heading, h.global_position)
		if s < best_score:
			best_score = s
			best = h
	return best


## Current movement vector — actual velocity if moving, else the last facing.
func _heading() -> Vector2:
	if _owner.velocity.length() > 0.1:
		return _owner.velocity.normalized()
	return _owner.facing_direction


## True if `h` is not behind the heading (in the forward hemisphere). No heading (a
## stationary feral with no facing) → always true, so nothing gets stranded.
func _is_forward(h: Human, heading: Vector2) -> bool:
	if heading == Vector2.ZERO:
		return true
	return (h.global_position - _owner.global_position).dot(heading) >= 0.0

## The CURRENT target stays valid while alive — even if another feral has claimed
## it mid-pounce (we keep pursuing and retarget only when it actually dies).
## A target that enters an INTACT ShelterBuilding is LOST (buildings spec §6.1):
## tick() converts that loss into BREACHING of its building. Occupants of a
## BREACHED building are normal prey again (§5.2 room-by-room hunting).
func _target_valid() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_alive \
		and not _target.is_safely_sheltered()


## A NEW retarget candidate must be alive, not under an in-flight pounce (the
## exclusion rule that spreads the horde, §3.5), and not SAFELY sheltered
## (state-excluded behind intact walls, §6.1; breached-building occupants count).
func _is_candidate(h: Human) -> bool:
	return h != null and is_instance_valid(h) and h.is_alive \
		and not h.is_pounce_claimed() and not h.is_safely_sheltered()


## Picks the nearest valid candidate from local scan ∪ hunt pool. Returns true if
## a new target was set. Candidates are sorted by unit_uid so distance ties resolve
## deterministically (§10).
func _retarget() -> bool:
	var gm := _game_manager()
	if gm == null:
		return false

	var seen := {}
	var candidates: Array[Human] = []

	# Local scan — within chain_scan_radius, LOS-gated (includes cowering once it exists).
	for u in gm.neighbours_within(_owner.global_position, GameConfig.chain_scan_radius, &"humans"):
		var h := u as Human
		if _is_candidate(h) and not seen.has(h) and _owner.has_line_of_sight_to(h):
			seen[h] = true
			candidates.append(h)

	# Hunt pool — pursued ∪ fleeing, no LOS / no distance gate. Cowering humans are
	# EXCLUDED here (§3.4/§4.4): a silent, still cowerer is found only by ferals that can
	# locally see it (the scan above), not drawn at from across the map via the pool.
	for h in gm.pursued_humans():
		if _is_candidate(h) and not h.is_cowering() and not seen.has(h):
			seen[h] = true
			candidates.append(h)
	for h in gm.fleeing_humans():
		if _is_candidate(h) and not h.is_cowering() and not seen.has(h):
			seen[h] = true
			candidates.append(h)

	candidates.sort_custom(func(a, b): return a.unit_uid < b.unit_uid)

	# Pick the best PATH target — keeps momentum up our heading after a kill instead of
	# whipping around. path_score prefers humans ahead; ones behind carry a large but
	# finite penalty, so a feral hemmed in with only prey behind it still engages (last
	# resort) rather than calming.
	var heading := _heading()
	var best: Human = null
	var best_score := INF
	for h in candidates:
		var s := FeralTargeting.path_score(_owner.global_position, heading, h.global_position)
		if s < best_score:
			best_score = s
			best = h

	if best != null:
		set_target(best)
		return true
	return false


## Bucketed failsafe window: every failsafe_window seconds, if the distance to the
## target dropped by less than failsafe_min_progress, report "no progress".
## BREACHING never runs this (§5.4.1 — a besieger's progress is door damage).
func _check_failsafe(delta: float) -> bool:
	# §5.4.2 doorway-jam pause rule: the clock does NOT accumulate on a frame
	# where our movement collision is with another FERAL zombie — a healthy
	# draining queue is legitimate non-progress, while a wall-wedge still runs
	# the clock (and a jam head calming flips its blockers' colliders to CALM,
	# cascading the whole jam back to the reserve gracefully). NOTE: currently
	# LATENT — units have no unit-unit collision (BOID separation only), so this
	# guard can only fire if body collision is ever enabled (work-queue Point 1).
	var col := _owner.get_last_slide_collision()
	if col != null:
		var other := col.get_collider() as Zombie
		if other != null and other.current_state == Zombie.State.FERAL:
			return false
	_progress_timer -= delta
	if _progress_timer > 0.0:
		return false
	var dist := _owner.global_position.distance_to(_target.global_position)
	var progressed := _progress_ref_dist - dist
	_progress_ref_dist = dist
	_progress_timer = GameConfig.failsafe_window
	return progressed < GameConfig.failsafe_min_progress


func _release_pursuit() -> void:
	if _target != null and is_instance_valid(_target):
		_game_manager().remove_pursuit(_target)


## Lazily resolves the GameManager (the hunt-pool registry). Cached after first use.
func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm
