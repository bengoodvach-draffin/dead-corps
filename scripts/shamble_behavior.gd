class_name ShambleBehavior
extends Node

## Calm idle wander for a Zombie — build-plan 2.1, spec §3.2.
##
## A behavior component (child node of the Zombie shell, per ARCHITECTURE_GUIDELINES
## rule 2). It owns the shamble state — the anchor and the deterministic wander
## sequence — and is ticked by the shell's _physics_process dispatcher whenever the
## zombie is CALM and idle (no move target). It has no _physics_process of its own
## (single dispatcher, rule 4).
##
## All idle calm zombies slow-wander within shamble_leash of an anchor point. The
## anchor resets wherever a commanded move completes (the shell calls set_anchor).
## The wander is DETERMINISTIC — points come from hash(unit_uid, counter) via
## DetHash, not live RNG (§10) — so identical inputs replay identically. Leash and
## speed are GameConfig tunables.

## The zombie shell this drives.
var _owner: Zombie = null

## Settle point; every wander target stays within shamble_leash of this.
var _anchor: Vector2 = Vector2.ZERO

## Current point being ambled toward, and whether one is chosen yet.
var _wander_target: Vector2 = Vector2.ZERO
var _has_wander_target: bool = false

## DetHash salt — incremented each time a wander target is reached, so the
## sequence advances deterministically (same uid → same path).
var _wander_counter: int = 0

## Idle dwell at each wander point (the "shamble pause"): while dwelling the
## zombie stands still; the duration is deterministic and per-point varied.
var _is_dwelling: bool = false
var _dwell_timer: float = 0.0


## Wires the owning zombie and seeds the anchor at its current position.
func setup(owner_zombie: Zombie) -> void:
	_owner = owner_zombie
	_anchor = owner_zombie.global_position


## Resets the anchor — called by the shell when a commanded move completes, so
## the zombie shambles around wherever it was last told to be.
func set_anchor(pos: Vector2) -> void:
	_anchor = pos
	_has_wander_target = false   # repick relative to the new anchor
	_is_dwelling = false         # start the new spot's wander fresh


## One idle-frame: amble toward the current wander point at shamble_speed; on
## arrival, advance the counter and pick the next deterministic point in the leash.
func tick(delta: float) -> void:
	# unit_uid is assigned at registration (after _ready). Until then, hold still
	# so the deterministic wander always keys off the real, stable id.
	if _owner.unit_uid < 0:
		return

	# Idle pause at the current point before moving to the next.
	if _is_dwelling:
		_owner.velocity = Vector2.ZERO
		_dwell_timer -= delta
		if _dwell_timer <= 0.0:
			_is_dwelling = false
			_wander_counter += 1
			_pick_next_target()
		return

	if not _has_wander_target:
		_pick_next_target()

	if _owner.step_toward(_wander_target, GameConfig.shamble_speed):
		_begin_dwell()   # arrived → idle before picking the next point


## Picks the next wander point: a deterministic offset within the leash disc,
## relative to the anchor.
func _pick_next_target() -> void:
	var offset := DetHash.offset(_owner.unit_uid, _wander_counter, GameConfig.shamble_leash)
	_wander_target = _anchor + offset
	_has_wander_target = true


## Starts an idle pause at the current point. Duration is shamble_pause varied
## deterministically by ±50% (DetHash) so a crowd doesn't pause in lockstep.
func _begin_dwell() -> void:
	_is_dwelling = true
	var variance := DetHash.hash01(_owner.unit_uid, _wander_counter)
	_dwell_timer = GameConfig.shamble_pause * (0.5 + variance)
