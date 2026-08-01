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
var _breach: CalmBreach = null         ## calm auto-breach of a door in the way

## Tracks whether we were executing a commanded move last frame, so the shamble
## anchor can reset to the arrival point the moment a move completes (spec §3.2).
var _was_moving: bool = false

## Deferred attack (#8): a human to release toward once the current move route finishes —
## "attacking is another waypoint". Set by a shift+RMB on an enemy while moves are queued;
## fires in _tick_calm when the queue empties. Cleared by a plain move and on ignite.
var queued_attack: Human = null

## Guards the nav-arrival "is_navigation_finished" check (#8 stuck fix): only trust the agent's
## finished flag once its path for the CURRENT target has actually loaded (a real next-path
## direction has appeared). Otherwise a stale finished flag from the previous target would make
## the unit "arrive" instantly and skip the new waypoint. Reset whenever the target changes.
var _nav_path_ready: bool = false

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

	_breach = CalmBreach.new()
	_breach.name = "CalmBreach"
	add_child(_breach)
	_breach.setup(self)


## Whether this zombie can receive a player command. Calm only.
func can_receive_command() -> bool:
	return current_state == State.CALM


## Whether the player can select this zombie. Calm only — feral zombies are not
## selectable (released is released, spec §3.1).
func is_selectable() -> bool:
	return current_state == State.CALM


## FINISHING (Ben's ruling 2026-07-24, the corpse-command model applied to the
## pounce recovery): a feral in its stationary post-kill second is box-selectable
## alongside calm zombies, and an order to it is STORED, applying the instant it
## calms. If the hunt continues instead (prey remains → retarget), the stored
## order is dropped — the hunt always wins; released is released stays intact.
func is_finishing_kill() -> bool:
	return current_state == State.FERAL and _pounce != null and _pounce.is_recovering()


## True while this CALM zombie is pounding a door that blocks its ordered move
## (calm auto-breach). Stays selectable and commandable throughout — this is
## terrain clearing, not a siege. Readability / debug hook.
func is_calm_breaching() -> bool:
	return current_state == State.CALM and _breach != null and _breach.is_breaching()


## Stored order for a finishing zombie (see is_finishing_kill). The attack case
## reuses queued_attack (consumed by _tick_calm once idle).
var _pending_calm_move: Vector2 = Vector2.ZERO
var _has_pending_calm_move: bool = false


func queue_finish_move(slot: Vector2) -> void:
	if not is_finishing_kill():
		return
	_pending_calm_move = slot
	_has_pending_calm_move = true
	queued_attack = null


func queue_finish_attack(human: Human) -> void:
	if not is_finishing_kill():
		return
	queued_attack = human
	_has_pending_calm_move = false


## The hunt continued past the recovery (retarget / next pounce) — the stored
## order is void (the hunt always wins).
func _drop_finish_order() -> void:
	_has_pending_calm_move = false
	queued_attack = null


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
	# CALM BREACH: a door that blocks this route, or one the player clicked
	# directly, gets broken down without leaving calm control. It drives movement
	# on the frames it pounds, and hands control back the frame the door falls.
	if _breach.tick(has_target, target_position, delta):
		_was_moving = true
		return

	if has_target:
		# Commanded move at the chase speed (§9 zombie_speed). Read live from config
		# (robust to LevelConfig push order) — same speed as feral pursuit. Nav-pathed
		# so the move routes around buildings/walls instead of stalling on them.
		if nav_move_toward(target_position, GameConfig.zombie_speed):
			# Arrived — walk to the next queued waypoint if any, else stop (idle-shamble). (#8)
			if not _advance_move_queue():
				has_target = false
		_was_moving = true
	else:
		# Route finished (or none) — if an attack was queued for the end, go feral now (#8:
		# "attacking is another waypoint" — the release waits until the moves are done).
		if queued_attack != null:
			var h := queued_attack
			queued_attack = null
			if is_instance_valid(h) and h.is_alive:
				ignite_feral(h)
			return
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
			_drop_finish_order()   # the hunt continues — a stored finish-order is void
			_pounce.start(_feral.current_target())
		FeralBrain.Result.NO_TARGET:
			_set_calm()
		FeralBrain.Result.PURSUING:
			_drop_finish_order()   # ditto — pursuit resumed after the recovery


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
	move_queue.clear()      # released is released — drop any queued route (#8)
	queued_attack = null    # and any deferred attack
	_breach.cancel()        # and any calm breach — the hunt owns the door rules now
	_feral.set_target(target)
	modulate = FERAL_TINT


## Release-at-the-building (buildings spec §5.1 + the footprint amendment):
## ignite FERAL with an occupied building as the siege seed — this zombie
## besieges its OWN nearest door (nearest-door-per-feral, no coordination).
## Same verb weight as release-on-human: released is released, no recall.
func ignite_feral_at_building(building: Node2D) -> void:
	current_state = State.FERAL
	has_target = false
	_was_moving = false
	move_queue.clear()
	queued_attack = null
	_breach.cancel()
	_feral.set_siege(building)
	modulate = FERAL_TINT


## ORDERED CALM BREACH (Ben's ruling 2026-07-30): RMB on an intact door sends
## this zombie to break that specific one — a plain calm order, not a release.
## Release is for prey; orders are for terrain. It stays selectable and
## commandable throughout, and any new order cancels the job instantly.
##
## Replaces release-on-door as the door click's verb: a door isn't prey (it
## doesn't move, doesn't fight back, doesn't feed the combo, and pounds for the
## same damage either way), so going feral to break one bought nothing but the
## loss of control.
func order_breach(door: Node2D) -> void:
	if not can_receive_command():
		return
	# A plain command replaces any route, exactly like a move order does.
	has_target = false
	_was_moving = false
	move_queue.clear()
	queued_attack = null
	_breach.order(door)


## The pounce landed a kill — relay it as the zombie's kill signal (feeds
## contagion in 2.5 and risers in 2.6).
func _on_pounce_kill(human: Human) -> void:
	zombie_killed_human.emit(human, self)


## Returns to CALM control: clears the feral target, reverts the tint, and anchors
## the shamble where the zombie ended up. A stored finish-order (move) applies
## NOW; a stored finish-attack (queued_attack) fires via _tick_calm's normal path.
func _set_calm() -> void:
	current_state = State.CALM
	_feral.clear()
	modulate = CALM_TINT
	_shamble.set_anchor(global_position)
	if _has_pending_calm_move:
		_has_pending_calm_move = false
		set_move_target(_pending_calm_move)


## Moves toward `point` along the navmesh (around buildings/walls) at `speed`, returning true
## once the target is reached. Used by calm commanded moves + feral pursuit (pounce flight is
## separate). Drives the NavigationAgent2D (avoidance off — deterministic).
##
## Arrival (#8 stuck fix): the agent's target_desired_distance, NOT a tight 5px — the agent
## stops giving path guidance once inside that band, so insisting on 5px left crowded / near-
## terrain units grinding into walls forever. Falls back to is_navigation_finished() (once the
## path has loaded) so a waypoint tucked BEHIND terrain arrives at the nearest reachable point
## and the caller advances. When no path direction is available yet, it holds still for a frame
## rather than straight-lining into terrain (the old fallback dragged stuck units deeper in).
func nav_move_toward(point: Vector2, speed: float, arrive_dist: float = 5.0) -> bool:
	if nav_agent == null:
		if global_position.distance_to(point) <= arrive_dist:
			velocity = Vector2.ZERO
			return true
		return step_toward(point, speed, arrive_dist)

	# Only (re)set the target when it changes — resetting every frame churns the path solve.
	if nav_agent.target_position != point:
		nav_agent.target_position = point
		_nav_path_ready = false

	# Inside the target's neighbourhood: close the FINAL stretch straight-line to
	# a tight 2px so the unit lands ON the ordered point, not a radius short (the
	# old stop-at-band left the body's edge kissing the cursor). Fall back to the
	# agent's arrival ONLY when the straight approach is genuinely BLOCKED (point
	# tucked against terrain / crowd jam — progress toward the point collapses);
	# the agent itself reports "finished" anywhere inside its 20px band, which is
	# exactly the imprecision being closed here, so its word alone doesn't count.
	if global_position.distance_to(point) <= nav_agent.target_desired_distance:
		var before_d := global_position.distance_to(point)
		if step_toward(point, speed, 2.0):
			return true
		var progressed := before_d - global_position.distance_to(point)
		if progressed < speed * get_physics_process_delta_time() * 0.25:
			return _nav_path_ready and nav_agent.is_navigation_finished()
		return false

	var dir := nav_agent.get_next_path_position() - global_position
	if dir.length() > 0.01:
		_nav_path_ready = true
		velocity = dir.normalized() * speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO   # path not ready — wait, don't straight-line into terrain

	# Behind-terrain / blocked target: once the path has loaded, trust the agent's own
	# arrival at the nearest reachable point so the route advances instead of sticking.
	# ONLY while still outside the desired-distance band — the agent reports "finished"
	# anywhere inside it, which would end the order a radius short the very frame we
	# cross in and starve the precision branch above (the cursor-gap bug).
	if _nav_path_ready and nav_agent.is_navigation_finished() \
			and global_position.distance_to(point) > nav_agent.target_desired_distance:
		velocity = Vector2.ZERO
		return true
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
	# Release the PURSUIT claim too (A1): a feral killed mid-chase (routine since gunfire,
	# 3.1) must free its target from the hunt pool. Otherwise that straggler stays
	# is_pursued() forever — no other feral peels onto it and its hunted ring never clears,
	# silently degrading the peel-off model exactly when a defender is thinning the chasers.
	# clear() is null-safe and also used by _set_calm, so it's safe on any death path.
	if _feral != null:
		_feral.clear()
	if _breach != null:
		_breach.cancel()
	# Living zombies stop being pushed by this corpse via the BOID separation skip
	# (dead units excluded by is_alive in the registry), not collision layers.
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		queue_free()
