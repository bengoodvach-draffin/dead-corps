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


## Drops the target and leaves the hunt pool (calming / dying).
func clear() -> void:
	_release_pursuit()
	_target = null


## One frame of hunting. Returns the action the shell should take.
func tick(delta: float) -> Result:
	# Validate the current target; if it's gone (dead/lost), retarget — the
	# kill-driven chain.
	if not _target_valid():
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

	_owner.step_toward(_target.global_position, GameConfig.zombie_speed)
	return Result.PURSUING


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
func _target_valid() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_alive


## A NEW retarget candidate must be alive AND not under an in-flight pounce — the
## exclusion rule that spreads the horde (§3.5).
func _is_candidate(h: Human) -> bool:
	return h != null and is_instance_valid(h) and h.is_alive and not h.is_pounce_claimed()


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
func _check_failsafe(delta: float) -> bool:
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
