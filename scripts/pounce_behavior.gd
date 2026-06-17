class_name PounceBehavior
extends Node

## The Pounce — kill delivery for a feral Zombie (build-plan 2.2, spec §3.5).
##
## A behavior component (child node of the Zombie shell), ticked by the shell when
## a pounce is active. Owns the lunge mechanic: a short committed flight, the kill
## registering AT LANDING (not at lunge-start), the pounce-exclusion claim, and the
## stationary recovery. Reports upward (rule 5); the shell mediates with FeralBrain.
##
## No HP, no damage values, no grapple — the human dies outright at landing.

## Emitted at landing, just before the human dies — the shell relays it as
## zombie_killed_human (feeds contagion 2.5 / risers 2.6).
signal landed_kill(human: Human)

enum Phase { IDLE, FLIGHT, RECOVERY }

var _owner: Zombie = null
var _phase: Phase = Phase.IDLE
var _target: Human = null
var _timer: float = 0.0


func setup(owner_zombie: Zombie) -> void:
	_owner = owner_zombie


## Whether a pounce (flight or recovery) is in progress — the shell ticks us only
## while this is true, and won't run normal pursuit meanwhile (committed).
func is_active() -> bool:
	return _phase != Phase.IDLE


## Begins the lunge at `target`. Claims the target for exclusion (spec §3.5) so no
## other feral retargets onto it during the flight.
func start(target: Human) -> void:
	_target = target
	_phase = Phase.FLIGHT
	_timer = GameConfig.pounce_flight_time
	if is_instance_valid(_target):
		_target.claim_pounce(_owner)


func tick(delta: float) -> void:
	match _phase:
		Phase.FLIGHT:
			# Lunge toward the target. Kill is NOT registered until landing, so a
			# zombie killed mid-flight (gunfire, 3.1) leaves the human alive.
			if is_instance_valid(_target):
				_owner.step_toward(_target.global_position, GameConfig.zombie_speed)
			_timer -= delta
			if _timer <= 0.0:
				_land()
		Phase.RECOVERY:
			# Stationary on the corpse, fully vulnerable to fills (matters in 3.1).
			# On finish, go IDLE — the shell polls is_active() and resumes ticking
			# the brain, which retargets the (now dead) target per §3.4.
			_owner.velocity = Vector2.ZERO
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.IDLE
				_target = null


## Aborts an in-flight / recovering pounce because the OWNER died (e.g. shot mid-lunge
## by a fill front, 3.1). Releases the victim's exclusion claim so other ferals can
## retarget it, and goes IDLE. No kill registers — the kill only happens at _land(), so
## a zombie killed mid-flight leaves its target alive (spec §3.5 / pounce_flight_time).
func abort() -> void:
	if _phase == Phase.IDLE:
		return
	if is_instance_valid(_target):
		_target.release_pounce()
	_phase = Phase.IDLE
	_target = null


## Landing: the kill registers. Release the claim and kill the target, then enter
## recovery. If the target became invalid mid-flight (e.g. escaped), no kill.
func _land() -> void:
	if is_instance_valid(_target) and _target.is_alive:
		_target.release_pounce()
		landed_kill.emit(_target)
		_target.die()
	_phase = Phase.RECOVERY
	_timer = GameConfig.pounce_recovery
	_owner.velocity = Vector2.ZERO
