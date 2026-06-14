extends Unit
class_name Zombie

## Zombie unit — player-controlled undead. Thin SHELL per ARCHITECTURE_GUIDELINES
## rule 2: it owns the state enum, identity/selectability, and the per-frame
## dispatch; the actual behaviors live in child components.
##
## State model (spec §3.1): CALM (full RTS control — idle-shamble or commanded
## move) vs FERAL (autonomous hunting) vs DEAD. _physics_process is a dispatcher
## (rule 4) routing to _tick_calm / _tick_feral; DEAD is inert.
##
## Components:
##   - ShambleBehavior (built 2.1) — calm idle wander, ticked from _tick_calm.
##   - FeralBrain / PounceBehavior (2.2–2.3) — not built yet; _tick_feral stubbed.

enum State {
	CALM,   ## RTS-controlled: idle-shamble when no target, move when commanded
	FERAL,  ## autonomous hunting (built in 2.2) — not selectable
	DEAD
}

## Emitted on a kill — re-emitted by the Pounce in 2.2. Kept wired so
## GameManager's listener survives.
signal zombie_killed_human(human: Unit, zombie: Zombie)

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null

var current_state: State = State.CALM
var facing_direction: Vector2 = Vector2.RIGHT

## Special zombies (FatZombie/CostumeZombie) set this true in their _ready().
## Read by end_game_overlay.gd. Specials are PoC-excluded / non-functional.
var is_special: bool = false

## Calm idle-wander component (child node).
var _shamble: ShambleBehavior = null

## Tracks whether we were executing a commanded move last frame, so the shamble
## anchor can reset to the arrival point the moment a move completes (spec §3.2).
var _was_moving: bool = false


func _ready() -> void:
	team = Team.ZOMBIES
	super._ready()

	# Calm idle-wander component. Created at runtime (no editor presence needed);
	# ticked by this shell's dispatcher, so it has no _physics_process of its own.
	_shamble = ShambleBehavior.new()
	_shamble.name = "ShambleBehavior"
	add_child(_shamble)
	_shamble.setup(self)


## Whether this zombie can receive a player command. Calm zombies always can;
## feral zombies are not selectable/commandable (enforced in selection, 2.4).
func can_receive_command() -> bool:
	return current_state == State.CALM


## Per-frame dispatcher (rule 4). DEAD is inert; CALM/FERAL route to handlers.
func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		velocity = Vector2.ZERO
		return

	_apply_boid_tuning()
	apply_separation_force()
	apply_alignment_force()

	match current_state:
		State.CALM:
			_tick_calm(delta)
		State.FERAL:
			_tick_feral(delta)

	clamp_position_to_bounds()

	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()


## CALM: execute a commanded move if we have one, otherwise idle-shamble. When a
## commanded move just completed, reset the shamble anchor to the arrival point.
func _tick_calm(delta: float) -> void:
	if has_target:
		move_to_target(delta)
		_was_moving = true
	else:
		if _was_moving:
			_shamble.set_anchor(global_position)
			_was_moving = false
		_shamble.tick(delta)


## FERAL: autonomous hunting — built in Phase 2.2 (FeralBrain + Pounce).
func _tick_feral(_delta: float) -> void:
	pass


## BOID separation/alignment params, tuned per state (set before the forces run).
## Cohesion is omitted — it's disabled in unit.gd.
func _apply_boid_tuning() -> void:
	match current_state:
		State.CALM:
			if has_target:
				separation_radius = 35.0
				separation_strength = 120.0
				alignment_rate = 0.8
			else:
				separation_radius = 30.0
				separation_strength = 100.0
				alignment_rate = 0.5
		State.FERAL:
			separation_radius = 45.0
			separation_strength = 150.0
			alignment_rate = 1.5


## Death: enter DEAD, stop, recolor, linger as a corpse, then free.
func die() -> void:
	is_alive = false
	current_state = State.DEAD
	velocity = Vector2.ZERO
	modulate = Color(0.4, 0.0, 0.0)
	# Living zombies stop being pushed by this corpse via the BOID separation skip
	# (dead units excluded by is_alive in the registry), not collision layers.
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		queue_free()
