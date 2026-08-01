class_name HuntPool
extends Node

## The hunt pool (spec §3.4) — single owner of pursuit claims and the pool
## queries, extracted from GameManager (Tier-7 manager splits, pre-Mark).
## GameManager keeps one-line delegates, so every caller (FeralBrain, doors,
## escape zones) is unchanged. The Mark system lands as a sibling component.
##
## Determinism (§10): pursued/fleeing results are built by filtering the
## registry's living_humans(), so they inherit its unit_uid ordering.

var _gm: Node = null

## Human → number of ferals currently pursuing it. Drives the pool and the
## "targeted" readability ring.
var _pursuit_counts: Dictionary = {}


func setup(gm: Node) -> void:
	_gm = gm


## A feral started pursuing this human.
func add_pursuit(human: Human) -> void:
	var was: int = _pursuit_counts.get(human, 0)
	_pursuit_counts[human] = was + 1
	# First pursuer → light the "targeted" readability ring (build-plan 2.4).
	if was == 0 and is_instance_valid(human):
		human.set_hunted(true)


## A feral stopped pursuing this human (retargeted away, calmed, or died).
func remove_pursuit(human: Human) -> void:
	if not _pursuit_counts.has(human):
		return
	var c: int = _pursuit_counts[human] - 1
	if c <= 0:
		_pursuit_counts.erase(human)
		# Last pursuer gone → clear the ring.
		if is_instance_valid(human):
			human.set_hunted(false)
	else:
		_pursuit_counts[human] = c


## Drops a human's entry outright (it escaped/freed — no ring to clear).
func drop(human: Human) -> void:
	_pursuit_counts.erase(human)


## Living humans currently pursued by at least one feral — the {pursued} half of
## the hunt pool. unit_uid ordered; stale count keys are ignored.
func pursued_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in _gm.living_humans():
		if _pursuit_counts.has(h):
			result.append(h)
	return result


## True if any feral is currently pursuing this human — the peel-off scan (2.4)
## skips already-pursued humans so each straggler draws exactly one peeler.
func is_pursued(human: Human) -> bool:
	return _pursuit_counts.has(human)


## The {FLEEING} half of the hunt pool: living humans in the rout, unit_uid
## ordered. Ferals retarget onto these with no LOS/distance gate.
func fleeing_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in _gm.living_humans():
		if h.current_state == Human.State.FLEEING:
			result.append(h)
	return result
