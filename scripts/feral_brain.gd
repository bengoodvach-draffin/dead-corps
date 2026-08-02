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

## BREACHING (buildings spec §5): the siege sub-state. Two ways in, one loop:
##   - building proxy — pursued prey sheltered (§5.1) or release-at-the-building
##     (_siege_building set, _target cleared);
##   - door OBSTACLE (terrain kit) — the pursuit wedged on an intact door with
##     the target still live beyond it (_target KEPT: the chase resumes the
##     moment the door falls).
##
## There is no ORDERED feral siege: the door click is a CALM order now (Ben's
## ruling 2026-07-30, CalmBreach) — a feral only ever besieges a door because
## prey is behind it.
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

## The SHORT door-wedge bucket (Ben's ruling 2026-07-29) — independent of the
## give-up failsafe above, and much faster: a pursuit stopped dead at a door
## should start pounding within half a second, while the give-up clock still
## needs 2s of tolerance before abandoning a hunt.
var _wedge := DoorBreach.Wedge.new()

## PRESSING (fences spec §A6.2) — a flag, not a state: the intact fence this
## pursuit is wedged against with live prey beyond it. Movement is untouched
## (we keep nav-moving at the target and physically jam on the barrier — that
## jam IS the press). THRESHOLD-GATED give-up exemption (Ben's amendment
## 2026-08-02): the failsafe clock holds ONLY while the fence is actually
## folding (press >= threshold). An under-strength press runs the normal 2s
## give-up, so the feral calms out IN the strip — where its body still counts
## toward the press and control returns to the player — instead of being
## committed forever to wire it cannot fold. Peel-off stays live throughout:
## a fence is the lowest-priority thing a feral can be doing, same as a door.
var _pressing_fence: Fence = null

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
	_pressing_fence = null   # a new pursuit re-earns PRESSING via its own wedge
	_target = human
	if human != null:
		_game_manager().add_pursuit(human)
		_progress_ref_dist = _owner.global_position.distance_to(human.global_position)
		_progress_timer = GameConfig.failsafe_window
		_wedge.reset(_progress_ref_dist)


func current_target() -> Human:
	return _target


## Drops the target and leaves the hunt pool (calming / dying). Ends any siege.
func clear() -> void:
	_release_pursuit()
	_target = null
	_pressing_fence = null
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
	# BREACHING (buildings spec §5): besieging a door — the door is the
	# lowest-priority prey. Handled in its own branch; no pounce, no failsafe.
	# Keyed on the DOOR, not the building: a gate in plain wall geometry has
	# no building at all (terrain kit — routing on the building silently
	# calmed every gate siege).
	if _siege_door != null:
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
			# The Mark's BUILDING AGGRO may have begun a siege inside _retarget
			# (no human target, but a door to pound) — route to the siege loop.
			if _siege_door != null:
				return _tick_breaching(delta)
			return Result.NO_TARGET
	else:
		# Target still alive: peel onto a closer FRESH straggler if one crosses our
		# path (continuous opportunistic retarget, §2.4), then run the wedged-feral
		# failsafe. No tangible progress for a window = wedged (no pursuit pathing
		# yet) → give up and return to the reserve, rather than loop forever on an
		# unreachable target. The real fix is pursuit pathing (flagged); once that
		# lands a real chase closes ~400px in 2s so this rarely fires.
		_maybe_divert(delta)
		# Prey beyond a barred door (terrain kit): a pursuit that stops gaining
		# ground while pressed in an intact door's arc converts to pounding THAT
		# door — from either side (gates are symmetric; a building's inside never
		# wedges, the instant burst preempts it). The target is KEPT: the chase
		# resumes the moment the door falls. On the SHORT wedge window, not the
		# 2s give-up clock, so it reads as hitting the door and clawing at it.
		if _wedge.check(_owner.global_position.distance_to(_target.global_position), delta):
			var wedge_door := DoorBreach.door_in_arc(_owner)
			if wedge_door != null:
				_begin_door_siege(wedge_door)
				return Result.PURSUING
			# No door in reach — an intact FENCE under us means the pursuit is
			# wedged on wire (fences spec §A6.2): enter PRESSING. The target is
			# KEPT, so the chase resumes the instant the fence folds.
			_pressing_fence = Fence.strip_at(_owner)
		# PRESSING upkeep: the flag drops when the fence folds or we leave the
		# strip (peel and retarget clear it via set_target/clear).
		if _pressing_fence != null and (not is_instance_valid(_pressing_fence) \
				or not _pressing_fence.is_intact() \
				or not _pressing_fence.in_press_strip(_owner.global_position)):
			_pressing_fence = null
		if _pressing_fence != null and _pressing_fence.is_filling():
			# THRESHOLD-GATED exemption (Ben's amendment 2026-08-02): the give-up
			# clock holds ONLY while the fence is actually folding. Re-baselining
			# each tick means a press that dips below threshold restarts a clean
			# failsafe window rather than inheriting a nearly-expired one.
			_progress_ref_dist = _owner.global_position.distance_to(_target.global_position)
			_progress_timer = GameConfig.failsafe_window
		elif _check_failsafe(delta):
			# Standing in a door's arc at the give-up moment converts rather than
			# abandoning the hunt (the wedge bucket may have just re-baselined) —
			# a feral never walks away from prey it can still smell through a door.
			var late_door := DoorBreach.door_in_arc(_owner)
			if late_door != null:
				_begin_door_siege(late_door)
				return Result.PURSUING
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
		# THE MARK's siege-pull (Ben's ruling 2026-07-26): a besieger INSIDE the
		# field abandons its door for the field's human prey — ORDERED sieges
		# included. Checked after the fresh-prey scan, so genuinely closer live
		# prey still wins organically (the override rule's spirit).
		var gm_pull := _game_manager()
		if gm_pull != null:
			var pulled: Node = gm_pull.mark_prey_for(_owner)
			if pulled is Human and _is_candidate(pulled):
				_end_siege()
				set_target(pulled)
				return Result.PURSUING

	# 2. Siege validity — two prey bases (terrain kit): a door-obstacle siege needs
	#    its KEPT target; a building proxy needs occupants (§5.2.4). Neither left →
	#    retarget or calm. Every feral siege has a prey basis; a door with nothing
	#    behind it is a job for the calm crew.
	var occupied: bool = _siege_building != null and is_instance_valid(_siege_building) \
			and _siege_building.is_occupied()
	if not occupied and not _target_valid():
		_end_siege()
		if not _retarget(false):
			return Result.NO_TARGET
		return Result.PURSUING

	# 2b. DOWN: the door fell. A kept target resumes its chase straight through
	#     the hole; otherwise normal retarget first (nearer outside prey still
	#     wins, §3.4), then the pour-in fallback (Ben's ruling, 2026-07-23):
	#     the NEAREST living occupant, no LOS gate — we've been pounding after
	#     them, we know they're in there. Once one feral pursues an occupant
	#     it's in the pool, and the rest converge normally.
	if _siege_door == null or not is_instance_valid(_siege_door) or not _siege_door.is_intact():
		var building := _siege_building
		_end_siege()
		if _target_valid():
			return Result.PURSUING
		if _retarget(false):
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
	_pound_timer = DoorBreach.first_pound_delay(_owner.unit_uid)
	if GameConfig.debug_logs:
		print("🔍 SIEGE: %s besieges %s at %s" % [_owner.name, building.name, door.name])


func _end_siege() -> void:
	_siege_building = null
	_siege_door = null
	# Leaving a door: re-baseline the wedge window so a resumed chase (kept
	# target pouring through the breach) doesn't inherit a stale reference
	# distance and instantly "wedge" on the door it just knocked down.
	_wedge.reset(INF)


## Starts pounding `door` — the WEDGE siege (prey beyond a barred door). The
## KEPT target is the prey basis, so the chase resumes the moment it falls. The
## building may be null: a gate in plain wall geometry has none.
func _begin_door_siege(door: Node2D) -> void:
	if door == null or not is_instance_valid(door) or not door.is_intact():
		return
	_siege_door = door
	_siege_building = door.building()
	_pound_timer = DoorBreach.first_pound_delay(_owner.unit_uid)
	if GameConfig.debug_logs:
		print("🔍 SIEGE: %s pounds %s (prey beyond)" % [_owner.name, door.name])


func is_breaching() -> bool:
	return _siege_door != null   # door, not building — gates have no building


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


## Nearest valid living occupant of `building` (pour-in ruling). UN-PURSUED
## occupants are preferred — the peel philosophy (one feral per straggler)
## applied indoors, so an entry wave fans out across the occupants instead of
## dog-piling the nearest one; pile-on only once everyone inside is claimed.
## Deterministic: arrival order, strict nearest.
func _nearest_occupant(building: Node2D) -> Human:
	if building == null or not is_instance_valid(building):
		return null
	var gm := _game_manager()
	var best: Human = null
	var best_dist := INF
	var best_fresh: Human = null
	var best_fresh_dist := INF
	for occ in building.living_occupants():
		var h := occ as Human
		if not _is_candidate(h):
			continue
		var d := _owner.global_position.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h
		if gm != null and not gm.is_pursued(h) and d < best_fresh_dist:
			best_fresh_dist = d
			best_fresh = h
	return best_fresh if best_fresh != null else best


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
## deterministically (§10). THE MARK (§5.4, field model) is consulted here: a
## feral inside the field prefers the field's prey unless some candidate is
## strictly closer AND within its own local scan; a building-aggro mark begins a
## siege as the last resort (the caller routes on _siege_building when we return
## false). `allow_mark_building` is off for calls from inside the siege loop.
func _retarget(allow_mark_building: bool = true) -> bool:
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

	# THE MARK (§5.4, field model): inside the field, the field's HUMAN prey is
	# preferred — beaten only by a candidate strictly closer to this feral AND
	# within its own local scan (genuinely closer prey wins organically). The
	# marked prey need not be in the pool at all — that's the influence.
	var marked: Node = gm.mark_prey_for(_owner)
	if marked is Human and _is_candidate(marked):
		var m := marked as Human
		var marked_d := _owner.global_position.distance_to(m.global_position)
		var closer_in_scan := false
		for h in candidates:
			if h == m:
				continue
			var d := _owner.global_position.distance_to(h.global_position)
			if d < marked_d and d <= GameConfig.chain_scan_radius and _owner.has_line_of_sight_to(h):
				closer_in_scan = true
				break
		if not closer_in_scan:
			set_target(m)
			return true

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

	# BUILDING AGGRO (the Mark on an occupied building): nothing else bid — the
	# field's attention points at the walls themselves. Begin the siege; the
	# caller routes to the siege loop on our false return (no human target).
	if allow_mark_building and marked != null and not (marked is Human):
		_begin_siege(marked)
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
