class_name FleeBehavior
extends Node

## Permanent rout for a broken Human (build-plan 3.2, spec §4.3).
##
## A behavior component (child node of the Human shell), ticked by the Human's
## dispatcher while the unit is FLEEING. On begin() it locks onto the nearest escape
## zone (NO line-of-sight requirement — spec §4.3: they live here, they know the
## exits) and thereafter steers toward it at human_flee_speed. No shooting, no
## recovery — broken is broken. Reaching the zone is handled by EscapeZone itself
## (body_entered → counted + freed), so there's no arrival logic here.
##
## Straight-line for now: the flee-vector bend around zombies (the HERDING mechanic)
## is build-plan 3.4 — deliberately not here.

var _owner: Human = null

## The escape destination (a zone's global_position), and whether one was found.
var _escape_target: Vector2 = Vector2.ZERO
var _has_escape: bool = false


func setup(owner_human: Human) -> void:
	_owner = owner_human


## Commits the rout: pick the nearest escape zone (no LOS) and lock it in. Called once
## when the human breaks. If there's no escape zone at all, the human just halts (rare;
## a level without exits — flagged rather than crashing).
func begin() -> void:
	var zone := _owner.get_nearest_escape_zone()
	if zone != null:
		_escape_target = zone.global_position
		_has_escape = true
	else:
		_has_escape = false


## One physics frame of the rout: steer toward the locked escape zone at flee speed.
## The base Unit movement (run by the Human dispatcher's super._physics_process after
## this) does the actual stepping; EscapeZone frees the human on entry.
func tick(_delta: float) -> void:
	if not _has_escape:
		_owner.velocity = Vector2.ZERO
		return
	_owner.move_speed = GameConfig.human_flee_speed
	_owner.set_move_target(_escape_target)
