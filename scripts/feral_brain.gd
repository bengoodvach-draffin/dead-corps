class_name FeralBrain
extends Node

## Autonomous hunting for a FERAL Zombie — build-plan 2.2 (spec §3.4).
##
## A behavior component (child node of the Zombie shell). Owns the current target
## and the pursuit; ticked by the shell's _tick_feral dispatcher. Per frame it
## pursues the target at zombie_speed and REPORTS UPWARD which action the shell
## should take (rule 5: signals/returns up, the shell decides). It never calls the
## PounceBehavior directly — the shell mediates (rule 2).
##
## SCOPE (2.2): single seeded target. Retargeting from the hunt pool + the
## no-progress failsafe are 2.3 — for now "no target" means the shell goes CALM.

## What the shell should do after this frame's pursuit.
enum Result {
	PURSUING,         ## still closing on the target — keep going
	READY_TO_POUNCE,  ## within pounce_range — the shell should start a pounce
	NO_TARGET,        ## target gone/invalid — the shell should go CALM (2.2)
}

var _owner: Zombie = null
var _target: Human = null


func setup(owner_zombie: Zombie) -> void:
	_owner = owner_zombie


func set_target(human: Human) -> void:
	_target = human


func current_target() -> Human:
	return _target


func clear() -> void:
	_target = null


## One frame of hunting. Returns the action the shell should take.
func tick(_delta: float) -> Result:
	# Target lost if it died, was freed (escaped → queue_free), or is gone.
	if _target == null or not is_instance_valid(_target) or not _target.is_alive:
		return Result.NO_TARGET

	var dist := _owner.global_position.distance_to(_target.global_position)
	if dist <= GameConfig.pounce_range:
		return Result.READY_TO_POUNCE

	# Pursue at full chase speed.
	_owner.step_toward(_target.global_position, GameConfig.zombie_speed)
	return Result.PURSUING
