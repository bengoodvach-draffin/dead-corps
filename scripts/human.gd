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
	COWER,   ## Cornered (3.5, §4.4): frozen, classless, no fill; dies to a normal pounce
	## Inside a ShelterBuilding (buildings spec §6.1): entered a door while FLEEING;
	## holds a claimed spot; out of the hunt pool; cower suspended. Exits: breach-
	## flush (step 6), death, level end — never voluntary.
	SHELTERED
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

## The queued-rise ROUTE, mirrored from the riser entry PURELY for the interim _draw line
## (the entry in GameManager is the source of truth, so a freed corpse can't strand it). (#8)
var _queued_route: Array = []

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


## Editor-only redraw so patrol-path visuals update while placing waypoints.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## IDLE LOD state (PERF_REVIEW.md F2). Cold = no zombie within lod_wake_radius
## at the last check; while cold the dispatcher early-returns. The check runs
## every lod_check_interval, DetHash-staggered so the crowd never checks on one
## tick; the query early-stops at the FIRST zombie found (max_results = 1).
const LOD_SALT := 10501
var _lod_cold: bool = false
var _lod_timer: float = 0.0
var _lod_primed: bool = false


## One frame of the LOD clock. Returns true while COLD (caller skips the tick).
## Deterministic: sim-time cadence + uid stagger, no wall clock (§10).
func _lod_tick(delta: float) -> bool:
	if not _lod_eligible():
		_lod_cold = false
		return false
	if not _lod_primed:
		# Primed on first use, not in _ready — unit_uid isn't assigned until
		# registration (the FearDetector stagger lesson).
		_lod_primed = true
		_lod_timer = DetHash.hash01(unit_uid, LOD_SALT) * GameConfig.lod_check_interval
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer += GameConfig.lod_check_interval
		var gm := _get_game_manager()
		var was_cold := _lod_cold
		_lod_cold = gm != null and gm.neighbours_within(
			global_position, GameConfig.lod_wake_radius, &"zombies", null, false, 1).is_empty()
		# Going cold with residual fill state would freeze the debug line on
		# screen mid-decay; a cold front is a cold front — reset it.
		if _lod_cold and not was_cold and _fill_front != null:
			_fill_front.cancel()
	if _lod_cold:
		velocity = Vector2.ZERO
	return _lod_cold


## Cold is only legal in states where the brain is purely REACTIVE to nearby
## zombies: defending while stationary, or safely sheltered at rest. Everything
## with its own agenda (patrol routes, the fear beat, fleeing, a mid-walk
## shelter entrant, occupants of a BREACHED building) must keep ticking.
func _lod_eligible() -> bool:
	if current_state == State.IDLE or current_state == State.SENTRY:
		return not is_patrolling and not _is_breaking()
	if current_state == State.SHELTERED:
		return is_safely_sheltered() and at_shelter_spot()
	return false


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

	# IDLE LOD (PERF_REVIEW.md F2, 2026-08-02): with no zombie inside the wake
	# radius there is nothing this human's brain can legally do — fear and fill
	# can't perceive past awareness range, and awareness sits well inside the
	# wake ring — so the whole tick is skipped. This is the idle-floor fix: the
	# measured baseline showed ~460 standing humans consuming ~14ms/tick of the
	# 16.7ms budget before a single feral existed. The cowerer precedent covers
	# the physics side (no boid while cold; neighbours' own separation flows
	# around us). take_damage/die are signal-driven and unaffected.
	if _lod_tick(delta):
		return

	if current_state == State.SHELTERED:
		# Sheltered (buildings spec §6.1): walk to the claimed spot, then hold. The
		# cower detector is suspended (it only runs in the FLEEING tick — the §6.1
		# "auto-cower inside" bug can't exist). FEAR IS SUSPENDED TOO: dread cannot
		# penetrate an intact shelter, and a human standing IN the door gap sits
		# inside the DoorLOS body where outward rays leak (hit_from_inside) — with
		# fear live that leak caused a 60Hz break→re-enter loop.
		#
		# THE FLUSH (§8.1, step 6): once the building is BREACHED, dread pours in —
		# fear re-arms for CIVILIANS, LOS-gated as always (§8.2: interior walls
		# block dread, open doorways leak it — panic sweeps the floor plan room by
		# room as ferals round corners). A broken civilian start_fleeing()s: out of
		# the occupancy, out through whatever exit remains (the breached building
		# left the set). Armed humans are the LAST STAND (§7.2): fear stays
		# suspended forever — they hold their spots and fire until killed.
		if not is_armed() and not is_safely_sheltered() and _fear != null:
			_fear.tick(delta)
		if _is_breaking():
			velocity = Vector2.ZERO
		elif _flee != null:
			_flee.tick_sheltered(delta)
		# Armed interior defense (step 5): pre-breach the fill runs only FROM THE
		# CLAIMED SPOT — an entrant walking the door gap stands INSIDE the DoorLOS
		# body, where outward rays leak (hit_from_inside) and drew phantom fill
		# lines at zombies outside (Ben's step-7 catch). Once the breach opens
		# real lanes it runs anywhere. A phantom picked up in the gap is dropped.
		if is_armed() and _fill_front != null:
			if at_shelter_spot() or not is_safely_sheltered():
				_fill_front.tick(delta)
			elif _fill_front.fill_length() > 0.0 or _fill_front.current_target() != null:
				_fill_front.cancel()
	elif current_state == State.FLEEING:
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


## Separation cadence override (perf, 2026-07-30): a standing crowd — idle,
## sentry, sheltered — barely moves, so it runs separation 1-in-3 ticks (impulse
## compensated in Unit; same net spread). FLEEING keeps every-tick separation:
## a rout shoves through crowds and gets herded, and that's gameplay.
func separation_cadence() -> int:
	return 1 if current_state == State.FLEEING else 3


## The class letter the roster reads at a glance — M/P/G for the armed classes,
## blank for civilians (they're the bulk). Was a per-unit Label; since F4 the
## VisionRenderer draws it from this accessor.
func class_letter() -> String:
	match defender_class:
		DefenderClass.MILITIA:
			return "M"
		DefenderClass.POLICE:
			return "P"
		DefenderClass.GI:
			return "G"
	return ""


## F4: extend the base strip — the three AudioStreamPlayer2Ds in human.tscn are
## v1 vestiges with no script references (the June review's "3 players × 500
## units" finding); at 447 humans that's ~1,300 dead nodes.
func _strip_presentation_nodes() -> void:
	super._strip_presentation_nodes()
	for player_name in ["AimSoundPlayer", "GunshotSoundPlayer", "WhistleSoundPlayer"]:
		var n := get_node_or_null(player_name)
		if n != null:
			n.queue_free()


# === LINE OF SIGHT (buildings + intact doors block) ===
# The has_line_of_sight_to OVERRIDE is gone (Tier-4 dead code): since the
# cluster fix it was byte-identical to Unit's — the base method serves.

## True if no building or intact door blocks the straight line from this human to
## `point` (a world-space coordinate, e.g. an escape zone).
func has_line_of_sight_to_point(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, point)
	query.collision_mask = 17           # Environment (1) + intact-door "DoorLOS" blockers (16)
	query.exclude = [self]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## THE unified exit set (buildings spec §9): escape zones ∪ shelter doors that are
## intact and unlocked — one set, no class preferences. A broken human runs to
## whatever safety is closest. Membership churn (engaged doors dropping out,
## breached buildings leaving forever) arrives with steps 3–4 via is_locked() /
## is_intact() going live.
func get_exit_set() -> Array[Node2D]:
	var exits: Array[Node2D] = []
	for zone in get_tree().get_nodes_in_group("escape_zone"):
		if is_instance_valid(zone):
			exits.append(zone)
	for door in get_tree().get_nodes_in_group("shelter_doors"):
		if not is_instance_valid(door) or not door.is_intact() or door.is_locked():
			continue
		# Only doors of a true, unbreached SHELTER are exits: standalone gate
		# doors (no building) and dumb boxes (is_shelter false) are plain
		# terrain, and a breached building leaves the set permanently — all its
		# doors, even intact ones (§9: a hole in the wall is not shelter).
		var b: Node = door.building()
		if b == null or not b.is_shelter or b.is_breached():
			continue
		exits.append(door)
	return exits




## Breaks this human into a permanent rout (spec §4.3) — called by the civilian
## reaction clock (3.2) and the fear break (3.3). Cancels patrol/fill; FleeBehavior
## steers to the nearest exit. No-op if already fleeing or dead (broken is broken).
## From SHELTERED this is the flush (buildings spec §8.1, wired fully in step 6):
## occupancy is released — a flushed human is out, the building forgets it.
func start_fleeing() -> void:
	if current_state == State.FLEEING or current_state == State.DEAD:
		return
	if current_state == State.SHELTERED and _shelter_building != null:
		_shelter_building.release_occupant(self)
		_shelter_building = null
	current_state = State.FLEEING
	is_patrolling = false
	has_target = false
	if _flee != null:
		_flee.begin()


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
	if GameConfig.debug_logs:
		print("🔍 COWER: %s cornered at %s" % [name, global_position.round()])
	velocity = Vector2.ZERO
	has_target = false
	# Drop off the Humans collision layer so a cowerer no longer blocks armed defenders'
	# firing lanes (B3, spec §4.1: corpses AND cowerers don't screen shots) — mirrors die().
	# Layer only: the pounce is claim/range-based (still kills a cowerer) and huddle
	# separation is registry-based, so neither depends on this.
	collision_layer = 0
	modulate = COWER_TINT


## Live check: is this human currently cowering? Used by FeralBrain to keep cowering
## humans LOCAL-SCAN-ONLY in the hunt pool (§3.4 seam).
func is_cowering() -> bool:
	return current_state == State.COWER


# === SHELTER (buildings spec §6, slice-1 step 2) ===

## The ShelterBuilding this human occupies while SHELTERED (dynamically typed — no
## class dependency). Read by step 3+ (BREACHING prey-proxy, flush routing).
var _shelter_building: Node2D = null


## Enters SHELTERED — the §6.1 transition, only reachable from FLEEING (crossing an
## intact, unlocked door; FleeBehavior detects the crossing). Atomically: leaves
## FLEEING (→ out of the fleeing pool; pursuers drop via FeralBrain's sheltered
## check, draining the pursued pool), suspends the cower detector (not ticked in
## SHELTERED), claims a spot and walks to it. Blocks the win by simply remaining
## alive on the map (§6.1) — no extra wiring.
func enter_shelter(building: Node2D, door: Node2D) -> void:
	if current_state != State.FLEEING:
		return
	current_state = State.SHELTERED
	has_target = false
	velocity = Vector2.ZERO
	_shelter_building = building
	var spot: Vector2 = building.claim_spot(self, door)
	if _flee != null:
		_flee.begin_sheltered(spot)
	if GameConfig.debug_logs:
		print("🔍 SHELTER: %s entered %s via %s → spot %s" % [name, building.name, door.name, spot])


## Level-start adoption (Ben's ruling 2026-07-26): a human PLACED inside an
## intact shelter becomes SHELTERED at boot as if it had fled in — same flush,
## same last stand. Called by GameManager after registration; eligibility
## (intact + is_shelter building, not patrolling) is the caller's job.
##
## HOLDS ITS PLACED POSITION (Ben's ruling 2026-07-30): unlike a runtime entrant,
## an adoptee claims NO ShelterSpot — it stands exactly where the designer put
## it. Authoring a spot per resident was busywork across dozens of hand-placed
## humans who were already positioned deliberately. Consequences, all wanted:
## the authored spots stay free for humans who actually flee in later, and a
## shelter full of placed residents no longer warns about having no spots.
func adopt_into_shelter(building: Node2D) -> void:
	if current_state == State.DEAD or current_state == State.SHELTERED:
		return
	current_state = State.SHELTERED
	is_patrolling = false
	has_target = false
	velocity = Vector2.ZERO
	_shelter_building = building
	building.add_occupant(self)
	# Target where we already stand: the SHELTERED tick sees itself inside
	# SPOT_ARRIVE immediately and simply holds, with no walk and no drift.
	if _flee != null:
		_flee.begin_sheltered(global_position)
	if GameConfig.debug_logs:
		print("🔍 SHELTER: %s adopted by %s (holds placed position)" % [name, building.name])


## Live check: is this human in the SHELTERED state (regardless of whether the
## building still protects it)?
func is_sheltered() -> bool:
	return current_state == State.SHELTERED


## Sheltered AND the building is still intact — the protection check. Safely
## sheltered humans are not valid feral targets (§6.1: pursuers besiege instead)
## and can't be release-pinned. Once the building is BREACHED, its occupants are
## normal prey again (§5.2 room-by-room hunting) even while still SHELTERED.
func is_safely_sheltered() -> bool:
	if current_state != State.SHELTERED:
		return false
	return _shelter_building != null and is_instance_valid(_shelter_building) \
		and not _shelter_building.is_breached()


## The occupied building, or null (the siege prey-proxy, read by FeralBrain).
func shelter_building() -> Node2D:
	return _shelter_building


## True while sheltered AND settled on the claimed spot — the door-watch (§7.1)
## only arms from the defensive position, not mid-walk.
func at_shelter_spot() -> bool:
	return current_state == State.SHELTERED and _flee != null and _flee.at_spot()


# === CORPSE COMMANDS (build-plan 6a) ===

## Marks this dead human as a pending-rise corpse — makes it selectable/commandable.
## Called by GameManager when the kill is queued into the riser pipeline.
func mark_pending_rise() -> void:
	is_pending_rise = true


## True while this is a selectable corpse: dead AND still counting down to rise. Selection
## (click/box) includes these alongside calm zombies; a move/release order is STORED and
## re-resolved when it stands (GameManager._raise).
func is_selectable_corpse() -> bool:
	return is_pending_rise and not is_alive


## Mirrors the queued rise-route for the interim debug line (source of truth is the riser
## entry in GameManager). Called from GameManager.set_rise_route / queue_rise_waypoint. (#8)
func set_queued_route(route: Array) -> void:
	_queued_route = route.duplicate()


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
## pursuing me — the "targeted" ring (drawn by VisionRenderer since F4).
func set_hunted(value: bool) -> void:
	_hunted = value


func is_hunted() -> bool:
	return _hunted


## Toggled by the SelectionManager when the cursor hovers me with releasable zombies
## selected — the "release here" ring (misclick defense; VisionRenderer draws it).
func set_hover_highlighted(value: bool) -> void:
	_hover_highlighted = value


func is_hover_highlighted() -> bool:
	return _hover_highlighted


## The fill-front component, for the VisionRenderer's fill line (rendering
## accessor — gameplay code must keep going through the shell's methods).
func fill_front() -> FillBehavior:
	return _fill_front


## The mirrored queued-rise route (rendering accessor for the corpse cue).
func queued_route() -> Array:
	return _queued_route


# === VISUALS ===

## EDITOR-ONLY since F4: every runtime visual (hunted/hover rings, fill line,
## corpse cues) moved to VisionRenderer, drawn in one batched canvas item. Only
## the editor patrol-path viz remains here (the renderer doesn't run in-editor).
func _draw() -> void:
	if not Engine.is_editor_hint():
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


# _draw_fill_line and _draw_corpse_cues moved to VisionRenderer (F4) — the
# logic is verbatim there, reading through fill_front() / queued_route().
