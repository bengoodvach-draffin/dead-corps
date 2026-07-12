@tool
extends Unit
class_name Human

## Human unit — AI defender (V2 skeleton).
##
## Phase 1.1 demolition: the v1 stealth-era behavior core (morale, detection/
## high-urgency alerts, tunnel vision, vision cones, the aim-timer shooting
## model, GRAPPLED/grapple-escape, the old flee, swing/sentry facing, formation
## squads) is GONE — see V2_DIRECTION_SPEC §11. What remains is a deliberately
## sterile skeleton: stand (IDLE), patrol between waypoints with pauses
## (positioning only — no facing/swing), and DEAD (incubation, until the rise
## pipeline replaces it in demolition step 1.4).
##
## The v2 defense behavior (radial fill front, fear radius + break, permanent
## rout/herding, cower) is rebuilt on top of this skeleton in Phase 3 — it reads
## all tunables per-class from GameConfig, not from this script.

## Human behavioral states. Live in this skeleton: IDLE, DEAD (and SENTRY, which
## now behaves like IDLE — kept so level scenes that set initial_state = SENTRY
## still load). No code transitions into SENTRY's old watching behavior.
enum State {
	IDLE,    ## Standing / calm
	SENTRY,  ## Watching (now identical to IDLE — facing behavior deleted)
	DEAD,    ## Permanent corpse (raised by the riser pipeline, step 2.6)
	FLEEING, ## Permanent rout (3.2, §4.3): paths to the nearest exit, no fill, no recovery
	COWER    ## Cornered (3.5, §4.4): frozen, classless, no fill; dies to a normal pounce
}

## Patrol modes for waypoint movement.
enum PatrolMode {
	LOOP,        ## 0→1→2→3→0 (circular)
	PING_PONG    ## 0→1→2→3→2→1→0 (back and forth)
}

## Defender class — the PoC roster. Indexes the per-class arrays in GameConfig
## (awareness / fill_speed / fear_threshold), so the order MUST stay
## CIVILIAN=0, MILITIA=1, POLICE=2, GI=3. (v1's SPEC_OPS is cut — §11.)
enum DefenderClass {
	CIVILIAN,
	MILITIA,
	POLICE,
	GI
}

## Emitted when this human dies. GameManager listens for win-condition tracking.
signal human_died(human: Human)

# === EXPORTED PROPERTIES ===

## Initial state when this human spawns (level-design hook).
@export var initial_state: State = State.IDLE

## Which defender class this unit is. Drives the v2 per-class GameConfig lookups
## (awareness, fill speed, fear threshold) built in Phase 3.
@export var defender_class: DefenderClass = DefenderClass.CIVILIAN

# === PATROL ===
@export_group("Patrol")

## Whether this human patrols between waypoints (positioning only — no watching).
@export var patrol_enabled: bool = false

## Patrol mode (LOOP or PING_PONG).
@export var patrol_mode: PatrolMode = PatrolMode.LOOP

## Movement speed while patrolling.
@export_range(10.0, 100.0, 5.0) var patrol_speed: float = 50.0

## Patrol waypoints (world positions). If empty and child "Waypoint*" nodes
## exist, they are loaded from those on _ready().
@export var patrol_waypoints: Array[Vector2] = []

## Pause duration (seconds) at each waypoint. Index matches waypoint index.
## 0.0 or missing = no pause. Empty = no pauses.
@export var patrol_pause_durations: Array[float] = []

@export_group("")

## Unit collision radius (must match CollisionShape2D radius).
const UNIT_RADIUS: float = 12.0

# === RUNTIME STATE ===

## Current behavioral state.
var current_state: State = State.IDLE

## Facing direction — updated from movement; kept for rendering/readability.
var facing_direction: Vector2 = Vector2.RIGHT

## Whether this human is dead (a corpse). Set by die(); read by GameManager
## win-check, selection, end-game overlay. In v2 a killed human becomes a
## permanent corpse here until the riser pipeline (step 2.6) raises it in place —
## the v1 incubation→conversion pipeline was removed in step 1.4.
var is_dead: bool = false

## Set true when this human enters COWER (3.5) and never cleared — so a kill can still
## tell it was cowering after die() flips the state to DEAD (the terror bonus, §6 /
## Phase 4.2). is_cowering() is the live check.
var was_cowering: bool = false

## Corpse commands (build-plan 6a): set true when this human is killed and queued to rise
## (GameManager.mark_pending_rise). While it holds AND the human is dead, this corpse is a
## SELECTABLE, commandable body — the player can queue it a click that GameManager._raise
## re-resolves (release-or-move) when it stands. Cleared implicitly when the corpse frees.
var is_pending_rise: bool = false

## The queued-rise click, mirrored from the riser entry PURELY for the interim _draw line
## (the entry in GameManager is the source of truth, so a freed corpse can't strand it).
var _queued_rise_pos: Vector2 = Vector2.ZERO
var _has_queued_rise: bool = false

## Pounce exclusion (spec §3.5): the zombie currently mid-pounce on this human,
## or null. While claimed, other ferals' retargeting (2.3) skips this human — the
## single anti-pile-up rule (replaces all attacker caps). Typed Unit to avoid a
## class dependency on Zombie.
var _pounce_claimed_by: Unit = null

## Readability rings (build-plan 2.4) — interim home; the full readability layer
## (riser/cower/fill indicators) moves to vision_renderer in 5.1. Each is drawn as a
## ring in _draw and toggled by a setter that queues a redraw; because they're drawn
## in local space they track the human automatically without a per-frame redraw.
## `_hunted` = a feral is currently pursuing me (driven by the GameManager hunt pool).
## `_hover_highlighted` = the cursor is over me with releasable zombies selected (the
## release misclick defense, spec §5.1).
var _hunted: bool = false
var _hover_highlighted: bool = false

# --- PATROL RUNTIME ---
var current_waypoint_index: int = 0   ## Waypoint we're heading to (0-based)
var patrol_direction: int = 1         ## 1 = forward, -1 = backward (PING_PONG)
var is_patrolling: bool = false       ## Whether actively patrolling
var is_patrol_paused: bool = false    ## Paused at a waypoint
var patrol_pause_timer: float = 0.0   ## Countdown for the current waypoint pause

## Cached physics space for line-of-sight raycasts.
var space_state: PhysicsDirectSpaceState2D

## The fill front (build-plan 3.1) — armed shot mechanic / civilian reaction clock, a
## child component ticked by this shell's dispatcher (mirrors the zombie component
## pattern). Null in the editor.
var _fill_front: FillBehavior = null

## The rout (build-plan 3.2) — steers a broken human to the nearest exit while FLEEING.
## Null in the editor.
var _flee: FleeBehavior = null

## The fear break (build-plan 3.3) — counts zombies in fear_radius and breaks the human
## when the class threshold is exceeded. Null in the editor.
var _fear: FearDetector = null

## Initialise the human: team, state, patrol, base unit, LOS space.
func _ready() -> void:
	# Force onto the human team.
	team = Team.HUMANS

	current_state = initial_state

	# Load waypoints from child "Waypoint*" nodes if none were set in the Inspector.
	if patrol_enabled and patrol_waypoints.size() == 0:
		load_waypoints_from_children()

	# Start patrolling if configured with at least one waypoint.
	if patrol_enabled and patrol_waypoints.size() > 0:
		is_patrolling = true
		current_waypoint_index = 0
		patrol_direction = 1

	# Base Unit init (movement, BOID separation, bounds, selection visuals).
	super._ready()

	# Cache the physics space for line-of-sight raycasts.
	space_state = get_world_2d().direct_space_state

	# Behavior components (runtime only — no AI in the editor).
	if not Engine.is_editor_hint():
		_fill_front = FillBehavior.new()
		_fill_front.name = "FillBehavior"
		add_child(_fill_front)
		_fill_front.setup(self)

		_flee = FleeBehavior.new()
		_flee.name = "FleeBehavior"
		add_child(_flee)
		_flee.setup(self)

		_fear = FearDetector.new()
		_fear.name = "FearDetector"
		add_child(_fear)
		_fear.setup(self)

		_add_class_label()


## Editor-only redraw so patrol-path visuals update while placing waypoints.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## Per-physics-frame dispatcher (V2 skeleton): DEAD handling → patrol → base unit.
## @param delta: Physics timestep in seconds.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Self-correct a stale state if anything left is_dead out of sync with DEAD.
	if is_dead and current_state != State.DEAD:
		current_state = State.DEAD
		velocity = Vector2.ZERO
		has_target = false

	# DEAD: permanent corpse — hold still. (The riser pipeline in step 2.6 will
	# raise it in place; the v1 incubation→conversion was removed in step 1.4.)
	if current_state == State.DEAD:
		velocity = Vector2.ZERO
		return

	if current_state == State.COWER:
		# Frozen but alive (§4.4): no flee, no fill, NO MOVEMENT — still a normal pounce
		# target. We deliberately DON'T call super here: its BOID separation moves the unit
		# via move_and_collide, so a passing/huddling crowd would shove the cowerer around
		# ("cowerer ran away"). Other units still flow around it — their own separation
		# pushes THEM off the cowerer (it stays in the registry). Trade-off: two humans
		# cowering at the same spot may overlap — acceptable (§4.4 "huddle together").
		velocity = Vector2.ZERO
		return

	if current_state == State.FLEEING:
		# Permanent rout (§4.3): steer to the exit. No patrol, no fill.
		if _flee != null:
			_flee.tick(delta)
	else:
		# Defending (IDLE / SENTRY). Fear is checked first — it can commit a break
		# (cancels the fill) and, after the reaction beat, start the rout (3.3).
		if _fear != null:
			_fear.tick(delta)
		if _is_breaking():
			# Frozen during the fear reaction beat (spec §4.2: animation time, not a
			# last-stand window) — no patrol, no fill, no shot.
			velocity = Vector2.ZERO
		elif is_armed() and _fill_front != null and _fill_front.is_reached():
			# Stop-to-fire (A2): once the front has reached its target, halt so the aim
			# rotation owns facing — a MOVING defender would otherwise overwrite the turn
			# each frame (the facing = velocity line below) and never complete it off-axis.
			# has_target/velocity are cleared so super() won't drive a move; patrol resumes
			# automatically once the shot fires and the front resets (is_reached → false).
			# NOTE: only manifests for a MOVING armed defender (i.e. patrol). No patrols
			# exist yet, so this is pre-emptive and UNTESTED — deferred test lives in the
			# phase3-test-criteria memory; re-run it when patrols return.
			has_target = false
			velocity = Vector2.ZERO
		elif is_patrolling:
			update_patrol(delta)

	# Face the direction of travel (readability only).
	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()

	# Fill front (3.1): scan/aim/fire (or the civilian reaction clock). Runs after the
	# movement-facing line so an aiming defender's facing wins; a stationary one
	# (velocity 0) is controlled purely here. Only in the defending states — NOT while
	# fleeing, mid-break, or cowering. (A cower triggered THIS frame flips FLEEING→COWER
	# inside _flee.tick above; without the state gate the fill would run once on a cowerer.)
	if (current_state == State.IDLE or current_state == State.SENTRY) and not _is_breaking() and _fill_front != null:
		_fill_front.tick(delta)

	# Base Unit physics (movement, BOID separation).
	super._physics_process(delta)


# === PATROL ===

## Moves between waypoints in LOOP or PING_PONG mode, pausing at waypoints whose
## patrol_pause_durations entry is > 0. Facing overrides, swing, and formation
## regroup are deleted (§11 — patrols are positioning only now).
## @param delta: Time since last frame in seconds.
func update_patrol(delta: float) -> void:
	if patrol_waypoints.size() == 0:
		is_patrolling = false
		return

	# Hold position while paused at a waypoint.
	if is_patrol_paused:
		patrol_pause_timer -= delta
		if patrol_pause_timer <= 0.0:
			is_patrol_paused = false
			advance_to_next_waypoint()
			set_move_target(patrol_waypoints[current_waypoint_index])
			move_speed = patrol_speed
		return

	var target_waypoint := patrol_waypoints[current_waypoint_index]
	var distance_to_waypoint := global_position.distance_to(target_waypoint)

	if distance_to_waypoint < 10.0:
		# Arrived. Pause here if this waypoint has a configured pause.
		var pause_duration := 0.0
		if current_waypoint_index < patrol_pause_durations.size():
			pause_duration = patrol_pause_durations[current_waypoint_index]

		if pause_duration > 0.0:
			is_patrol_paused = true
			patrol_pause_timer = pause_duration
			has_target = false
			velocity = Vector2.ZERO
			return

		# No pause — advance immediately.
		advance_to_next_waypoint()
		target_waypoint = patrol_waypoints[current_waypoint_index]

	# Move toward the current waypoint at patrol speed.
	set_move_target(target_waypoint)
	move_speed = patrol_speed


## Advances current_waypoint_index per patrol mode.
func advance_to_next_waypoint() -> void:
	if patrol_mode == PatrolMode.LOOP:
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
	elif patrol_mode == PatrolMode.PING_PONG:
		current_waypoint_index += patrol_direction
		if current_waypoint_index >= patrol_waypoints.size():
			current_waypoint_index = patrol_waypoints.size() - 2  # reverse
			patrol_direction = -1
		elif current_waypoint_index < 0:
			current_waypoint_index = 1
			patrol_direction = 1


## Loads patrol waypoints from child "Waypoint*" Node2Ds, natural-sorted by name
## (so Waypoint2 precedes Waypoint10). Allows visual waypoint placement.
func load_waypoints_from_children() -> void:
	var waypoint_nodes: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("Waypoint"):
			waypoint_nodes.append(child)
	if waypoint_nodes.size() == 0:
		return
	waypoint_nodes.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	patrol_waypoints.clear()
	for waypoint in waypoint_nodes:
		if waypoint is Node2D:
			patrol_waypoints.append(waypoint.global_position)


## True if this human is an armed class (uses the fill front + fires). Civilians are
## the only unarmed class — they flee on fill completion (3.2) instead.
func is_armed() -> bool:
	return defender_class != DefenderClass.CIVILIAN


## Stamps a class letter on the unit so the roster reads at a glance: M/P/G for the
## armed classes; civilians stay blank (they're the bulk). Runtime only.
func _add_class_label() -> void:
	var letter := ""
	match defender_class:
		DefenderClass.MILITIA:
			letter = "M"
		DefenderClass.POLICE:
			letter = "P"
		DefenderClass.GI:
			letter = "G"
	if letter == "":
		return
	var label := Label.new()
	label.text = letter
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.position = Vector2(-5.0, -11.0)   # roughly centred on the ~24px unit
	label.z_index = 10                       # above the body
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE   # don't eat selection clicks
	add_child(label)


# === LINE OF SIGHT (buildings block) ===

## True if no building blocks the straight line from this human to `target`.
func has_line_of_sight_to(target: Unit) -> bool:
	var query := PhysicsRayQueryParameters2D.create(position, target.position)
	query.collision_mask = 1            # buildings only
	query.exclude = [self, target]
	return space_state.intersect_ray(query).is_empty()


## True if no building blocks the straight line from this human to `point`
## (e.g. an escape zone).
func has_line_of_sight_to_point(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(position, point)
	query.collision_mask = 1            # buildings only
	query.exclude = [self]
	return space_state.intersect_ray(query).is_empty()


## Nearest escape zone, or null. NO line-of-sight requirement (spec §4.3: a routed
## human knows the exits) — used by the rout (FleeBehavior, 3.2).
func get_nearest_escape_zone() -> Node2D:
	var escape_zones := get_tree().get_nodes_in_group("escape_zone")
	if escape_zones.is_empty():
		return null
	var nearest_zone: Node2D = null
	var nearest_distance := INF
	for zone in escape_zones:
		if not is_instance_valid(zone):
			continue
		# global_position — escape zones are nested scenes.
		var distance := global_position.distance_to(zone.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_zone = zone
	return nearest_zone


## Breaks this human into a permanent rout (spec §4.3) — called by the civilian
## reaction clock (3.2) and the fear break (3.3). Cancels patrol/fill; FleeBehavior
## steers to the nearest exit. No-op if already fleeing or dead (broken is broken).
func start_fleeing() -> void:
	if current_state == State.FLEEING or current_state == State.DEAD:
		return
	current_state = State.FLEEING
	is_patrolling = false
	has_target = false
	if _flee != null:
		_flee.begin()
	queue_redraw()   # drop the fill-line debug viz


## Cancels the fill front (called by the fear break, 3.3, the instant it commits, so
## no shot lands during the reaction beat). Safe if the component isn't built.
func cancel_fill() -> void:
	if _fill_front != null:
		_fill_front.cancel()


## True while a fear break has committed (during the reaction beat or the frame it
## flees). The dispatcher freezes movement and skips the fill while this holds.
func _is_breaking() -> bool:
	return _fear != null and _fear.is_breaking()


## Interim cower tint (a cold, helpless pale-blue) — the readable "this one's cornered"
## cue. Proper cower readability (pose + scream) is the vision_renderer pass in 5.1.
const COWER_TINT := Color(0.45, 0.6, 1.0, 1.0)


## Drops this human into COWER (spec §4.4) — cornered, frozen, classless, no fill, no
## recovery. Called by FleeBehavior's net-displacement detector (3.5). Still alive, so
## it dies to a normal pounce; was_cowering records it for the terror bonus (4.2).
func start_cowering() -> void:
	if current_state == State.COWER or current_state == State.DEAD:
		return
	current_state = State.COWER
	was_cowering = true
	velocity = Vector2.ZERO
	has_target = false
	# Drop off the Humans collision layer so a cowerer no longer blocks armed defenders'
	# firing lanes (B3, spec §4.1: corpses AND cowerers don't screen shots) — mirrors die().
	# Layer only: the pounce is claim/range-based (still kills a cowerer) and huddle
	# separation is registry-based, so neither depends on this.
	collision_layer = 0
	modulate = COWER_TINT
	queue_redraw()   # drop the fill-line debug viz


## Live check: is this human currently cowering? Used by FeralBrain to keep cowering
## humans LOCAL-SCAN-ONLY in the hunt pool (§3.4 seam).
func is_cowering() -> bool:
	return current_state == State.COWER


# === CORPSE COMMANDS (build-plan 6a) ===

## Marks this dead human as a pending-rise corpse — makes it selectable/commandable.
## Called by GameManager when the kill is queued into the riser pipeline.
func mark_pending_rise() -> void:
	is_pending_rise = true
	queue_redraw()


## True while this is a selectable corpse: dead AND still counting down to rise. Selection
## (click/box) includes these alongside calm zombies; a move/release order is STORED and
## re-resolved when it stands (GameManager._raise).
func is_selectable_corpse() -> bool:
	return is_pending_rise and not is_alive


## Mirrors the queued rise-click for the interim debug line (source of truth is the riser
## entry in GameManager). Called from SelectionManager via GameManager.queue_rise_order.
func set_queued_rise(pos: Vector2) -> void:
	_queued_rise_pos = pos
	_has_queued_rise = true
	queue_redraw()


# === DEATH / CONVERSION ===

## Kills this human: notify GameManager, enter DEAD (incubating corpse).
## The morale-shock broadcast and attacker bookkeeping of the v1 die() are gone.
func die() -> void:
	if current_state == State.DEAD:
		return

	human_died.emit(self)

	is_alive = false
	current_state = State.DEAD
	is_dead = true

	velocity = Vector2.ZERO
	has_target = false

	modulate = Color(0.8, 0.2, 0.2, 1.0)   # red corpse
	collision_layer = 0                     # corpses block nothing
	collision_mask = 0


# === POUNCE EXCLUSION (spec §3.5) ===

## Claimed by a feral when it starts an in-flight pounce on this human.
func claim_pounce(zombie: Unit) -> void:
	_pounce_claimed_by = zombie


## Released when the pounce lands or aborts.
func release_pounce() -> void:
	_pounce_claimed_by = null


## True while an in-flight pounce has this human claimed — other ferals' retarget
## (2.3) treats a claimed human as invisible.
func is_pounce_claimed() -> bool:
	return _pounce_claimed_by != null and is_instance_valid(_pounce_claimed_by)


# === READABILITY HIGHLIGHTS (build-plan 2.4) ===

## Toggled by the GameManager hunt pool when the first/last feral starts/stops
## pursuing me — the "targeted" ring.
func set_hunted(value: bool) -> void:
	if _hunted == value:
		return
	_hunted = value
	queue_redraw()


## Toggled by the SelectionManager when the cursor hovers me with releasable zombies
## selected — the "release here" ring (misclick defense).
func set_hover_highlighted(value: bool) -> void:
	if _hover_highlighted == value:
		return
	_hover_highlighted = value
	queue_redraw()


# === VISUALS ===

## "Targeted" ring — amber/red, drawn while a feral is hunting this human. Kept low-
## alpha so a crowd full of them reads as ambient state, not an in-your-face overlay.
const HUNTED_RING_RADIUS := 20.0
const HUNTED_RING_COLOR := Color(0.95, 0.35, 0.15, 0.35)
## "Release here" ring — white, opaque, drawn under the cursor (slightly larger so it
## reads concentric when the hovered human is already hunted). This is the active
## cursor telegraph, so it stays prominent.
const HOVER_RING_RADIUS := 24.0
const HOVER_RING_COLOR := Color(1.0, 1.0, 1.0, 0.95)


## Runtime: the readability rings (alive humans only — corpses show nothing). In the
## editor: the patrol-path visuals instead (units don't run AI there).
func _draw() -> void:
	if not Engine.is_editor_hint():
		if is_alive:
			if _hunted:
				draw_arc(Vector2.ZERO, HUNTED_RING_RADIUS, 0.0, TAU, 48, HUNTED_RING_COLOR, 2.0, true)
			if _hover_highlighted:
				draw_arc(Vector2.ZERO, HOVER_RING_RADIUS, 0.0, TAU, 48, HOVER_RING_COLOR, 2.0, true)
			_draw_fill_line()
		elif is_selectable_corpse():
			_draw_corpse_cues()
		return

	# --- Editor patrol-path visuals (waypoint dots + connecting lines). Sentry
	# facing arrow and swing arc visuals are deleted (§11). ---
	if not patrol_enabled or patrol_waypoints.size() == 0:
		return

	var path_color := Color(1.0, 0.8, 0.0, 0.6)
	var waypoint_color := Color(1.0, 0.8, 0.0, 1.0)

	for i in range(patrol_waypoints.size()):
		var current_wp := patrol_waypoints[i] - global_position   # to local
		draw_circle(current_wp, 8.0, waypoint_color)

		var next_index := -1
		if patrol_mode == PatrolMode.LOOP:
			next_index = (i + 1) % patrol_waypoints.size()
		elif patrol_mode == PatrolMode.PING_PONG:
			if i < patrol_waypoints.size() - 1:
				next_index = i + 1
		if next_index >= 0:
			var next_wp := patrol_waypoints[next_index] - global_position
			draw_line(current_wp, next_wp, path_color, 2.0)


## Debug fill-line rendering (build-plan 3.1 — the front can't be tuned blind; interim
## home, moves to vision_renderer in 5.1). A line from the human toward the zombie the
## front is on, length = the current fill progress (clamped to the target's distance).
## Orange while filling; red once the front has reached the target (rotating to fire).
func _draw_fill_line() -> void:
	# Only defenders draw it; a fleeing human has no front.
	if current_state != State.IDLE and current_state != State.SENTRY:
		return
	if _fill_front == null:
		return
	var t := _fill_front.current_target()
	if t == null or not is_instance_valid(t):
		return
	var length := _fill_front.fill_length()
	if length <= 0.0:
		return
	var to := t.global_position - global_position   # local delta (the node is unrotated)
	if to == Vector2.ZERO:
		return
	var seg_len := minf(length, to.length())
	# Half-transparent so a field of fill lines reads as ambient, not in-your-face.
	var col := Color(1.0, 0.3, 0.2, 0.5) if _fill_front.is_reached() else Color(1.0, 0.85, 0.2, 0.5)
	draw_line(Vector2.ZERO, to.normalized() * seg_len, col, 2.0)


## Interim corpse-command cues (build-plan 6a; → vision_renderer 5.1): a sickly-green ring
## marking a body as commandable-before-it-rises, plus a faint line to its queued destination.
## (The selection ring itself is the base Unit selection_indicator, shown on select().)
const CORPSE_MARKER_RADIUS := 14.0
const CORPSE_CUE_COLOR := Color(0.55, 0.9, 0.4, 0.55)   # "will rise / commandable" green

func _draw_corpse_cues() -> void:
	draw_arc(Vector2.ZERO, CORPSE_MARKER_RADIUS, 0.0, TAU, 24, CORPSE_CUE_COLOR, 1.5, true)
	if _has_queued_rise:
		draw_line(Vector2.ZERO, _queued_rise_pos - global_position, CORPSE_CUE_COLOR, 1.5)
