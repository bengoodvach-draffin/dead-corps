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

## Behavior components (child nodes), ticked from the dispatcher.
var _shamble: ShambleBehavior = null   ## calm idle wander
var _feral: FeralBrain = null          ## feral pursuit / target
var _pounce: PounceBehavior = null     ## the lunge / kill-at-landing / recovery

## Tracks whether we were executing a commanded move last frame, so the shamble
## anchor can reset to the arrival point the moment a move completes (spec §3.2).
var _was_moving: bool = false

## Placeholder calm/feral tint for testability — the proper readability layer
## (calm/feral colors, riser/cower) is built in 2.4 / 5.1.
const CALM_TINT := Color(1, 1, 1, 1)
const FERAL_TINT := Color(1.0, 0.5, 0.2)   # orange


func _ready() -> void:
	team = Team.ZOMBIES
	super._ready()

	# Behavior components — created at runtime, ticked by this shell's dispatcher,
	# so none has its own _physics_process (single dispatcher, rule 4).
	_shamble = ShambleBehavior.new()
	_shamble.name = "ShambleBehavior"
	add_child(_shamble)
	_shamble.setup(self)

	_feral = FeralBrain.new()
	_feral.name = "FeralBrain"
	add_child(_feral)
	_feral.setup(self)

	_pounce = PounceBehavior.new()
	_pounce.name = "PounceBehavior"
	add_child(_pounce)
	_pounce.setup(self)
	_pounce.landed_kill.connect(_on_pounce_kill)


## Whether this zombie can receive a player command. Calm only.
func can_receive_command() -> bool:
	return current_state == State.CALM


## Whether the player can select this zombie. Calm only — feral zombies are not
## selectable (released is released, spec §3.1).
func is_selectable() -> bool:
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
		# Commanded move at the chase speed (§9 zombie_speed). Read live from config
		# (robust to LevelConfig push order) — same speed as feral pursuit. Nav-pathed
		# so the move routes around buildings/walls instead of stalling on them.
		if nav_move_toward(target_position, GameConfig.zombie_speed):
			has_target = false
		_was_moving = true
	else:
		if _was_moving:
			_shamble.set_anchor(global_position)
			_was_moving = false
		_shamble.tick(delta)


## FERAL: orchestrate the hunt. While a pounce is active (committed), tick only
## it; otherwise tick the brain and act on its report. The shell mediates between
## FeralBrain and PounceBehavior (rule 2 — they never call each other).
func _tick_feral(delta: float) -> void:
	if _pounce.is_active():
		_pounce.tick(delta)
		return

	match _feral.tick(delta):
		FeralBrain.Result.READY_TO_POUNCE:
			_pounce.start(_feral.current_target())
		FeralBrain.Result.NO_TARGET:
			_set_calm()
		FeralBrain.Result.PURSUING:
			pass


## Releases this zombie into the frenzy. Released is released — FERAL zombies
## aren't commandable (can_receive_command → false) and aren't selectable (filtered
## in selection). `target` is the release seed (§5.2); contagion (§3.3) passes none,
## so FeralBrain._retarget() grabs the nearest reachable prey on the first feral tick
## (and calms instantly if there's none — set_target(null) is a safe no-op).
func ignite_feral(target: Human = null) -> void:
	current_state = State.FERAL
	# Drop any pending commanded move — released is released. Otherwise, when this
	# zombie kills out and returns to CALM, _tick_calm would resume the stale move
	# order and walk back to where it was last sent.
	has_target = false
	_was_moving = false
	_feral.set_target(target)
	modulate = FERAL_TINT


## The pounce landed a kill — relay it as the zombie's kill signal (feeds
## contagion in 2.5 and risers in 2.6).
func _on_pounce_kill(human: Human) -> void:
	zombie_killed_human.emit(human, self)


## Returns to CALM control: clears the feral target, reverts the tint, and anchors
## the shamble where the zombie ended up.
func _set_calm() -> void:
	current_state = State.CALM
	_feral.clear()
	modulate = CALM_TINT
	_shamble.set_anchor(global_position)


## Moves toward `point` along the navmesh (around buildings/walls) at `speed`, returning
## true once within arrive_dist of the FINAL point. Used by calm commanded moves and
## feral pursuit (zombie pathing); pounce flight stays straight-line (in-range lunge).
## Drives the NavigationAgent2D (avoidance off — deterministic); falls back to a straight
## line if the agent is missing or the path isn't ready yet.
func nav_move_toward(point: Vector2, speed: float, arrive_dist: float = 5.0) -> bool:
	if global_position.distance_to(point) <= arrive_dist:
		velocity = Vector2.ZERO
		return true
	if nav_agent == null:
		return step_toward(point, speed, arrive_dist)
	nav_agent.target_position = point
	var dir := nav_agent.get_next_path_position() - global_position
	if dir.length() < 0.01:
		dir = point - global_position   # path not ready / next ≈ here → straight line
	if dir.length() > 0.01:
		velocity = dir.normalized() * speed
		move_and_slide()
	return false


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
	# If shot mid-pounce (3.1), release the victim's exclusion claim so it isn't left
	# permanently invisible to other ferals. No kill registers (kill is at _land only).
	if _pounce != null and _pounce.is_active():
		_pounce.abort()
	# Living zombies stop being pushed by this corpse via the BOID separation skip
	# (dead units excluded by is_alive in the registry), not collision layers.
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		queue_free()
