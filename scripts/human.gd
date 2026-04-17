@tool
extends Unit
class_name Human

## Human unit - enemy units that flee from zombies but don't fight back
## 
## Humans are AI-controlled enemy units that try to survive against the zombie horde.
## Unlike zombies, humans are defenseless - they can only run away.
##
## Key features:
## - Inherits all movement from Unit base class
## - NO COMBAT ABILITY - humans don't fight back
## - Vision-based detection system (cone or circle depending on state)
## - Uses line-of-sight checks (won't flee from zombies they can't see)
## - Emits signal when dying (for tracking and game state)
## - Belongs to the HUMANS team
##
## Humans convert to zombies when killed, growing the player's army.
## The fleeing behavior makes them feel more alive and creates interesting
## chase dynamics in gameplay. They're defenseless prey, not combatants.

## Human behavioral states - determines vision shape and behavior
enum State {
	IDLE,          ## Standing around, circular vision (360°)
	SENTRY,        ## Watching a direction, arc vision (90°)
	FLEEING,       ## Running from zombies, forward arc vision (90°)
	GRAPPLED,      ## Being attacked, no vision
	DEAD,          ## Incubating corpse, no vision
	TUNNEL_VISION  ## GI/Spec Ops stress response — locked 45° cone, 10s (v0.22.4)
}

## Patrol modes for sentry movement
enum PatrolMode {
	LOOP,        ## 0→1→2→3→0 (circular patrol)
	PING_PONG    ## 0→1→2→3→2→1→0 (back and forth)
}

## Formation shapes for squad patrols (set on leader only)
enum FormationShape {
	LINE_ABREAST, ## Side by side perpendicular to travel (wide coverage)
	COLUMN,       ## Single file behind leader (narrow corridors)
	WEDGE,        ## V-shape, leader at point (general purpose)
	ECHELON,      ## Diagonal line to the right (flanking coverage)
	DIAMOND       ## Diamond shape, best for exactly 3 followers
}

## Defender class — determines combat capability, morale profile, and weapon stats
## Set this in the Inspector to define what kind of human this unit is.
## Class defaults are auto-applied in _ready() and can be overridden per-unit.
enum DefenderClass {
	CIVILIAN,   ## Unarmed, panics easily, collapses almost immediately
	MILITIA,    ## Shotgun, unreliable under pressure, dangerous up close
	POLICE,     ## Pistol, calm under sightings, breaks on social events
	GI,         ## Assault rifle, nearly unbreakable, tunnel vision response
	SPEC_OPS    ## Assault rifle, elite, effectively immune to normal pressure
}

## Signal emitted when this human dies
## GameManager listens to this for win condition checking
## @param human: This human that died
signal human_died(human: Human)

# === EXPORTED PROPERTIES (Configurable in Godot Editor) ===

## Initial state when human spawns (can be set in editor for level design)
@export var initial_state: State = State.IDLE

# === DEFENDER CLASS ===
@export_group("Defender Class")

## The class of this defender — auto-populates morale and weapon defaults on _ready().
## Override individual values below if you need per-unit tweaks.
@export var defender_class: DefenderClass = DefenderClass.CIVILIAN

# === MORALE ===
@export_group("Morale")

## Maximum morale — bar starts full and drains under stress.
## Populated automatically from defender_class on _ready().
@export var morale_max: float = 65.0

## Morale drained per second per visible zombie within weapon range (armed units)
## or within full vision range (civilians). Stacks per zombie.
## Populated automatically from defender_class on _ready().
@export var sighting_drain: float = 30.0

## Flat morale drained when a nearby ally transitions to GRAPPLED state (one-time hit per event).
## Populated automatically from defender_class on _ready().
@export var grappled_drain: float = 100.0

## Flat morale drained when a fleeing ally moves through this unit's vicinity (one-time hit).
## Populated automatically from defender_class on _ready().
@export var fleeing_drain: float = 50.0

## Flat morale drained when a nearby ally is killed (one-time hit per death).
## Populated automatically from defender_class on _ready().
@export var killed_drain: float = 150.0

# === WEAPON ===
@export_group("Weapon")

## Maximum range at which this unit will engage zombies (pixels).
## Armed units only drain morale when zombies are within this range.
## Civilians are unarmed — this value is unused for them.
## Populated automatically from defender_class on _ready().
@export var weapon_range: float = 0.0

## Time in seconds from target acquisition to shot firing.
## Populated automatically from defender_class on _ready().
@export var aim_time: float = 0.0

# === SENTRY ===
@export_group("Sentry")

## Sentry facing direction in DEGREES (0° = North/Up, 90° = East/Right, 180° = South/Down, 270° = West/Left)
## Only used if initial_state = SENTRY
@export_range(0.0, 360.0, 1.0) var sentry_facing_degrees: float = 0.0

## Whether this sentry has a swinging vision arc (looks side to side)
@export var sentry_has_swing: bool = false

## How far (in degrees) the sentry looks to each side of center
## Example: 45° means ±45° (90° total sweep from -45° to +45°)
@export_range(0.0, 90.0, 1.0) var sentry_swing_range: float = 45.0

## Speed of the swing arc in degrees per second
@export_range(1.0, 180.0, 1.0) var sentry_swing_speed: float = 30.0

## Pause duration (in seconds) at each extreme of the swing
@export_range(0.0, 2.0, 0.1) var sentry_swing_pause: float = 0.5

# === PATROL ===
@export_group("Patrol")

## Whether this sentry patrols between waypoints
@export var patrol_enabled: bool = false

## Patrol mode (LOOP or PING_PONG)
@export var patrol_mode: PatrolMode = PatrolMode.LOOP

## Movement speed while patrolling (usually slower than flee speed)
@export_range(10.0, 100.0, 5.0) var patrol_speed: float = 50.0

## Patrol waypoints (positions to walk between)
## Example: [(100, 100), (200, 100), (200, 200), (100, 200)]
@export var patrol_waypoints: Array[Vector2] = []

## Pause duration (seconds) at each waypoint. Index matches waypoint index.
## 0.0 or missing = no pause. Empty array = no pauses (backwards compatible).
## Example: [2.0, 0.0, 3.0] = pause 2s at waypoint 0, skip waypoint 1, pause 3s at waypoint 2
@export var patrol_pause_durations: Array[float] = []

## Whether to swing vision arc during pause at each waypoint. Index matches waypoint index.
## Only has effect when the corresponding pause_duration > 0.
## Example: [true, false, true] = swing at waypoints 0 and 2, stand still at 1
@export var patrol_waypoint_swing: Array[bool] = []

## Facing direction override (degrees) at each waypoint. Index matches waypoint index.
## -1.0 = no override (keep arrival facing). 0.0-360.0 = face this direction (0°=North, 90°=East).
## Example: [90.0, -1.0, 270.0] = face East at waypoint 0, no override at 1, face West at 2
@export var patrol_waypoint_facing: Array[float] = []

@export_subgroup("Leader")

## Formation shape for this squad (set on leader only - ignored on followers)
@export var formation_shape: FormationShape = FormationShape.WEDGE

## Distance in pixels between formation slots
@export_range(20.0, 120.0, 5.0) var formation_spacing: float = 40.0

## Seconds to wait at a waypoint for followers to regroup before advancing without them
@export_range(1.0, 30.0, 1.0) var formation_regroup_timeout: float = 10.0

@export_subgroup("Follower")

## NodePath to this unit's patrol leader. Set this to make this human a formation follower.
## Leave empty for leaders and standalone sentries.
@export var patrol_leader: NodePath = NodePath("")

## Which slot in the formation this follower occupies (1-based).
## Slot layout depends on leader's formation_shape setting.
@export_range(1, 7, 1) var formation_slot: int = 1

@export_subgroup("")

# === VISION ===
@export_group("Vision")

## Idle state: circular vision radius
@export var idle_vision_radius: float = 100.0  # Individual detection range (reduced from 120)

## Sentry state: arc vision range and angle
@export var sentry_vision_range: float = 350.0
@export var sentry_vision_angle: float = 90.0  # Degrees

## Fleeing state: forward arc vision range and angle
@export var flee_vision_range: float = 350.0
@export var flee_vision_angle: float = 90.0  # Degrees

## How often (in seconds) to check for nearby zombies
## Lower values = more responsive but more expensive
## Higher values = less CPU but delayed reactions
@export var detection_interval: float = 0.3

# === FLEE ===
@export_group("Flee")

## How far (in pixels) the human tries to flee from zombies
## Used to calculate flee target position
@export var flee_distance: float = 200.0

## Distance at which humans will start seeking the escape zone (in pixels)
## Humans within this range with LOS to zone will be pulled toward it
@export var escape_zone_seek_range: float = 200.0

## DEPRECATED (v0.22.2): Replaced by morale system — depth cap no longer needed.
## Morale bar naturally limits cascade spread via per-unit drain values.
## Kept for reference; has no effect when morale system is active.
## Will be removed in a future cleanup pass.
# @export_range(0, 10, 1) var panic_propagation_depth: int = 2
var panic_propagation_depth: int = 2  # Kept as non-export for any legacy references

@export_group("")

# DEPRECATED: Old vector-based direction (kept for backwards compatibility)
# Use sentry_facing_degrees instead
var sentry_direction: Vector2 = Vector2.RIGHT

## Unit collision radius (must match CollisionShape2D radius)
const UNIT_RADIUS: float = 12.0

# === RUNTIME STATE VARIABLES ===

## Current behavioral state
var current_state: State = State.IDLE

## DEBUG: Only log for first human that flees (reduces spam)
static var debug_logged_human: Human = null
var enable_debug_logging: bool = false

## Direction this human is facing (for sentry/fleeing arc calculation)
var facing_direction: Vector2 = Vector2.RIGHT

## SWING ARC STATE (for sentry swing behavior)
var swing_center_angle: float = 0.0  # Center direction in degrees
var current_swing_offset: float = 0.0  # Current offset from center (-swing_range to +swing_range)
var swing_direction: int = 1  # 1 = swinging right, -1 = swinging left
var swing_pause_timer: float = 0.0  # Countdown for pause at extremes
var is_swing_paused: bool = false  # Whether currently paused at extreme

## PATROL STATE (for sentry patrol behavior)
var current_waypoint_index: int = 0  # Which waypoint we're heading to (0-based)
var patrol_direction: int = 1  # 1 = forward through waypoints, -1 = backward (for PING_PONG)
var is_patrolling: bool = false  # Whether currently executing patrol
var patrol_move_target: Vector2 = Vector2.ZERO  # Current waypoint position we're moving to

## PHASE C: WAYPOINT OBSERVATION STATE
var is_patrol_paused: bool = false    # Whether currently paused at a waypoint
var patrol_pause_timer: float = 0.0   # Countdown for current waypoint pause (seconds)
var is_waypoint_swinging: bool = false # Whether swinging vision during current pause

## FORMATION STATE (leader)
var is_waiting_to_regroup: bool = false  # Whether holding at waypoint waiting for followers
var regroup_timer: float = 0.0           # Countdown before advancing without full squad

## FORMATION STATE (follower)
var _leader_node: Human = null  # Cached resolved reference to patrol_leader node

## Current morale value — drains under stress, triggers response when it reaches 0.
## Starts at morale_max (set after _apply_class_defaults() runs in _ready()).
## No drain logic yet — wired up in Phase 3 (v0.22.2).
var morale: float = 65.0

## Whether this unit is currently grappled (synced with State.GRAPPLED for compatibility)
## Used by zombies to check grapple status
var is_grappled: bool = false

## Number of zombies currently attacking this human
## Used to limit max attackers to 3 per human
var attacker_count: int = 0

## Timer for reaction delay
## Counts down from reaction_time before flee begins
var reaction_timer: float = 0.0

## Last time this human saw a threat (in seconds)
## Used for flee momentum timeout - stops fleeing after 5s of no visible threats
var last_threat_time: float = 0.0

## Timer for grapple duration
## Human locked while this is > 0
var grapple_timer: float = 1.0

## How long a grapple lasts if zombie moves away
var grapple_duration: float = 0.5

## Whether this human is dead but not yet converted to zombie
var is_dead: bool = false

## Timer for incubation period (5 seconds)
var incubation_timer: float = 5.0

## How long it takes for dead human to convert to zombie
var incubation_duration: float = 5.0

## Timer for periodic zombie detection checks
## Counts down from detection_interval
var detection_timer: float = 0.0

# OLD COOLDOWN SYSTEM (REPLACED by priority-based flee system in v0.10.0)
# These variables are no longer used:
# var flee_cooldown_timer: float = 0.0
# var flee_cooldown_duration: float = 0.5

## Last direction we were fleeing in (used by momentum priority in calculate_flee_direction)
var last_flee_direction: Vector2 = Vector2.ZERO

## Cached original move_speed (set after super._ready initialises it).
## Patrol overwrites move_speed with patrol_speed; this lets flee restore the real value.
var _base_move_speed: float = 0.0

## Reference to selection circle for targeting visual (selection_indicator is inherited from Unit)
@onready var selection_circle: Line2D = $SelectionIndicator/SelectionCircle

## Audio player for the gun cocking sound — fires when a zombie enters the vision cone
@onready var _aim_sound: AudioStreamPlayer2D = $AimSoundPlayer

## Reference to the physics space for raycasting (line-of-sight checks)
## Cached for performance
var space_state: PhysicsDirectSpaceState2D

## === MORALE SYSTEM RUNTIME (v0.22.2) ===

## Number of zombies currently visible within morale drain range.
## Updated on each detection timer tick; used for per-frame sighting drain.
## For armed units: zombies within weapon_range.
## For civilians: zombies within full vision range.
var zombies_in_drain_range_count: int = 0

## Number of zombies visible within full vision range (sentry_vision_range).
## Updated each detection tick. Drives the cone timer for all classes,
## including armed units whose drain range is gated at weapon_range.
var _zombies_in_vision_count: int = 0

## Position of the nearest zombie within full vision range.
## Used as the threat position for the detection alert broadcast.
var _nearest_vision_zombie_pos: Vector2 = Vector2.ZERO

## Position of the nearest zombie currently in drain range.
## Updated each detection tick alongside zombies_in_drain_range_count.
## Used to set tunnel vision facing direction when morale empties from sighting drain.
var _nearest_drain_zombie_pos: Vector2 = Vector2.ZERO

## World position of the last event that drained morale.
## When morale hits 0, GI/Spec Ops lock their tunnel vision toward this point.
var _last_threat_position: Vector2 = Vector2.ZERO

## Last known states of nearby allies, keyed by instance_id.
## Used to detect ally state transitions (→ GRAPPLED, → FLEEING) for one-time drain hits.
## Cleared when ally leaves 150px radius or dies.
var _last_ally_states: Dictionary = {}

## Programmatically created morale bar (shown when morale is below 80%).
## Created in _ready() — no scene changes needed.
var _morale_bar: ProgressBar = null

## === TUNNEL VISION RUNTIME (v0.22.4) ===

## Countdown timer for tunnel vision duration (10 seconds).
var _tunnel_vision_timer: float = 0.0

## Facing direction locked at the moment tunnel vision triggered.
## Vision cone is fixed to this direction for the duration.
var _tunnel_vision_locked_direction: Vector2 = Vector2.RIGHT

## Tunnel vision cone angle (degrees) — narrowed from 90° to 22.5°.
const TUNNEL_VISION_ANGLE: float = 22.5

## Duration of tunnel vision state (seconds).
const TUNNEL_VISION_DURATION: float = 10.0

## === ALERT SYSTEM RUNTIME (v0.23.0) ===

## How long a zombie has been continuously in this human's vision cone.
## Resets to 0 when cone is empty. Alert fires at 5 seconds.
var _cone_timer: float = 0.0

## Whether the detection alert has already fired for the current detection event.
## Prevents repeated firing while zombie stays in cone.
## Resets when cone clears.
var _alert_fired: bool = false

## Cooldown after alert fires — 30 seconds before it can fire again.
var _alert_cooldown: float = 0.0

## Counts down after cone clears before human returns to original facing — 2 minutes.
## Resets if zombie re-enters cone.
var _facing_return_timer: float = 0.0

## Counts down after cone clears before patrolling human resumes patrol — 30 seconds.
## Resets if zombie re-enters cone.
var _patrol_resume_timer: float = 0.0

## Whether this human was patrolling before the alert fired.
## Used to correctly restore patrol state after _patrol_resume_timer expires.
var _was_patrolling: bool = false

## Whether this human is currently in an alerted state (facing overridden by alert).
## Suppresses swing arc so alert facing isn't overwritten each frame.
var _is_alerted: bool = false

## === HIGH URGENCY ALERT RUNTIME (v0.23.1) ===

## Shared cooldown across all high urgency events (grapple, kill, gunshot) — 2 seconds.
## Prevents thrashing when multiple events fire in quick succession.
var _high_urgency_cooldown: float = 0.0

## Pending high urgency event position — applied after 0.4s reaction delay.
var _high_urgency_pending_pos: Vector2 = Vector2.ZERO

## Countdown before applying high urgency facing — 0.4s reaction delay.
var _high_urgency_delay_timer: float = 0.0

## Hold timer — after high urgency event, holds alerted facing for 2s before returning.
## Only returns if no zombies are in the new sightline when it expires.
var _high_urgency_hold_timer: float = 0.0

## Target facing direction for smooth rotation toward alert events.
## Each frame, facing_direction rotates toward this at ALERT_TURN_SPEED.
## Set by _apply_alert_facing() and receive_high_urgency_alert().
## Vector2.ZERO means no active rotation target.
var _target_facing: Vector2 = Vector2.ZERO

## Turn speed for alert-driven rotation — 360°/sec = 180° in 0.5s.
const ALERT_TURN_SPEED: float = 360.0
var shoot_target: Unit = null

## Countdown timer for aim — fires when it reaches 0.
## Starts at aim_time on target acquisition, pauses if LOS lost, resets on new target.
var _aim_timer: float = 0.0

## Whether aim timer is currently paused (target temporarily lost LOS).
var _aim_paused: bool = false

## Line2D node used to draw the tracer line on firing.
## Created in _ready() as a child node.
var _tracer_line: Line2D = null

## How long the tracer line stays visible after firing (seconds).
const TRACER_FADE_DURATION: float = 0.1

## Countdown for tracer fade.
var _tracer_timer: float = 0.0


## Applies morale and weapon stat defaults based on defender_class.
## Called at the start of _ready() so all systems see correct values.
## Individual Inspector exports override these after this runs —
## so you can still tweak per-unit values on top of the class baseline.
##
## Morale values: morale_max, sighting_drain, grappled_drain, fleeing_drain, killed_drain
## Weapon values: weapon_range, aim_time
##
## Source of truth: HUMAN_DEFENDER_SYSTEM_SPEC.md v0.22.0
func _apply_class_defaults() -> void:
	match defender_class:
		DefenderClass.CIVILIAN:
			morale_max       = 65.0
			sighting_drain   = 30.0   # Drains at full vision range (350px) — no weapon threshold
			grappled_drain   = 100.0
			fleeing_drain    = 50.0
			killed_drain     = 150.0
			weapon_range     = 0.0    # Unarmed
			aim_time         = 0.0    # Unarmed
		DefenderClass.MILITIA:
			morale_max       = 150.0
			sighting_drain   = 35.0   # Drains within weapon range only
			grappled_drain   = 100.0
			fleeing_drain    = 40.0
			killed_drain     = 150.0
			weapon_range     = 150.0  # Shotgun
			aim_time         = 0.7
		DefenderClass.POLICE:
			morale_max       = 200.0
			sighting_drain   = 0.0    # Immune to sighting drain
			grappled_drain   = 100.0
			fleeing_drain    = 40.0
			killed_drain     = 150.0
			weapon_range     = 150.0  # Pistol
			aim_time         = 0.55
		DefenderClass.GI:
			morale_max       = 400.0
			sighting_drain   = 0.0    # Immune to sighting drain
			grappled_drain   = 275.0  # Primary breaking point
			fleeing_drain    = 20.0
			killed_drain     = 150.0
			weapon_range     = 250.0  # Assault rifle
			aim_time         = 0.525
		DefenderClass.SPEC_OPS:
			morale_max       = 1000.0
			sighting_drain   = 0.0    # Immune to sighting drain
			grappled_drain   = 100.0
			fleeing_drain    = 0.0    # Immune to fleeing drain
			killed_drain     = 150.0
			weapon_range     = 250.0  # Assault rifle
			aim_time         = 0.26
	
	# Initialise morale to full bar after defaults applied
	morale = morale_max
	
	print("🪖 ", name, " initialised as ", DefenderClass.keys()[defender_class],
		" | morale_max: ", morale_max,
		" | weapon_range: ", weapon_range,
		" | aim_time: ", aim_time)


## Called when the node enters the scene tree
## Ensures this unit is always on the human team
func _ready() -> void:
	# Apply morale and weapon defaults for the selected defender class.
	# Must run first — other systems may read these values.
	# Individual export overrides in the Inspector take effect after this.
	_apply_class_defaults()
	
	# Force this unit to be on the human team
	team = Team.HUMANS
	
	# Humans are defenseless - zero attack damage
	attack_damage = 0.0
	
	# Set initial state from editor configuration
	current_state = initial_state
	
	# If sentry, set facing direction from degrees
	if current_state == State.SENTRY:
		# Convert degrees to Vector2 direction
		# 0° = North (up), 90° = East (right), 180° = South (down), 270° = West (left)
		swing_center_angle = sentry_facing_degrees
		facing_direction = degrees_to_vector(sentry_facing_degrees)
		
		# Initialize swing arc state
		current_swing_offset = 0.0
		swing_direction = 1  # Start swinging right
		swing_pause_timer = 0.0
		is_swing_paused = false
		
		# Backwards compatibility: update old vector property
		sentry_direction = facing_direction
	
	# Load waypoints from child nodes (if no manual waypoints set)
	# This allows visual waypoint placement by dragging Node2D children
	# Skip for followers - they don't use waypoints directly
	if patrol_enabled and patrol_waypoints.size() == 0 and patrol_leader.is_empty():
		load_waypoints_from_children()
	
	# Initialize patrol if enabled, waypoints exist, and this is a leader (not a follower)
	if patrol_enabled and patrol_waypoints.size() > 0 and patrol_leader.is_empty():
		is_patrolling = true
		current_waypoint_index = 0
		patrol_direction = 1
		patrol_move_target = patrol_waypoints[0]
		print("Patrol initialized for ", name, " with ", patrol_waypoints.size(), " waypoints")
	
	# Call the parent class's _ready() to initialize all base unit functionality
	super._ready()
	
	# Cache the real flee speed AFTER super._ready() sets it.
	# Patrol will overwrite move_speed with patrol_speed; this lets flee restore
	# the correct speed when a patrolling human spots a zombie.
	_base_move_speed = move_speed
	
	# Cache the physics space state for raycasting
	space_state = get_world_2d().direct_space_state
	
	# Create morale bar programmatically — hidden when healthy, shown when draining
	# Sized and positioned to match the health bar (offset-based, not size-based)
	# Health bar: offset_left=-15, offset_top=-25, offset_right=15, offset_bottom=-20 (30×5px)
	# Morale bar sits just above it at offset_top=-32, offset_bottom=-27
	_morale_bar = ProgressBar.new()
	_morale_bar.min_value = 0.0
	_morale_bar.max_value = morale_max
	_morale_bar.value = morale_max
	_morale_bar.offset_left = -15.0
	_morale_bar.offset_top = -32.0
	_morale_bar.offset_right = 15.0
	_morale_bar.offset_bottom = -27.0
	_morale_bar.show_percentage = false
	_morale_bar.visible = false  # Hidden until morale starts dropping
	# Style: yellow fill on dark background
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = Color(0.9, 0.8, 0.1, 1.0)  # Yellow
	_morale_bar.add_theme_stylebox_override("background", style_bg)
	_morale_bar.add_theme_stylebox_override("fill", style_fill)
	add_child(_morale_bar)
	
	# Create tracer Line2D — hidden until a shot fires
	# Start point at bottom-center of sprite (y=15 = bottom edge in local space)
	_tracer_line = Line2D.new()
	_tracer_line.width = 1.5
	_tracer_line.default_color = Color(1.0, 0.9, 0.3, 0.9)  # Bright yellow
	_tracer_line.visible = false
	_tracer_line.z_index = 2
	add_child(_tracer_line)


## Called every frame (including in editor)
## Used to update visual indicators when properties change
func _process(_delta: float) -> void:
	# In editor, redraw when sentry properties change
	if Engine.is_editor_hint():
		queue_redraw()


## Draws visual indicators in the editor
## Shows sentry facing direction and swing arc range
func _draw() -> void:
	# Only draw in editor
	if not Engine.is_editor_hint():
		return
	
	# Only draw for sentries
	if initial_state != State.SENTRY:
		return
	
	# Draw facing direction arrow
	var arrow_length = 60.0
	var arrow_dir = degrees_to_vector(sentry_facing_degrees)
	var arrow_end = arrow_dir * arrow_length
	
	# Main arrow line (thicker, bright color)
	draw_line(Vector2.ZERO, arrow_end, Color.CYAN, 3.0)
	
	# Arrowhead
	var arrow_size = 12.0
	var arrow_angle = 25.0  # degrees
	var arrow_left = arrow_end - arrow_dir.rotated(deg_to_rad(arrow_angle)) * arrow_size
	var arrow_right = arrow_end - arrow_dir.rotated(deg_to_rad(-arrow_angle)) * arrow_size
	draw_line(arrow_end, arrow_left, Color.CYAN, 3.0)
	draw_line(arrow_end, arrow_right, Color.CYAN, 3.0)
	
	# Draw swing arc range if enabled
	if sentry_has_swing and sentry_swing_range > 0:
		var arc_radius = 50.0
		var arc_color = Color(0.5, 1.0, 0.5, 0.4)  # Semi-transparent green
		
		# Calculate arc endpoints
		var left_angle_deg = sentry_facing_degrees - sentry_swing_range
		var right_angle_deg = sentry_facing_degrees + sentry_swing_range
		
		var left_dir = degrees_to_vector(left_angle_deg)
		var right_dir = degrees_to_vector(right_angle_deg)
		
		# Draw arc lines
		draw_line(Vector2.ZERO, left_dir * arc_radius, arc_color, 2.0)
		draw_line(Vector2.ZERO, right_dir * arc_radius, arc_color, 2.0)
		
		# Draw arc curve (approximate with line segments)
		var segments = 10
		var angle_step = (sentry_swing_range * 2.0) / segments
		for i in range(segments):
			var angle1 = left_angle_deg + (angle_step * i)
			var angle2 = left_angle_deg + (angle_step * (i + 1))
			var p1 = degrees_to_vector(angle1) * arc_radius
			var p2 = degrees_to_vector(angle2) * arc_radius
			draw_line(p1, p2, arc_color, 2.0)
	
	# Draw patrol waypoints if enabled
	if patrol_enabled and patrol_waypoints.size() > 0:
		var path_color = Color(1.0, 0.8, 0.0, 0.6)  # Yellow/orange, semi-transparent
		var waypoint_color = Color(1.0, 0.8, 0.0, 1.0)  # Solid yellow
		
		# Draw lines connecting waypoints
		for i in range(patrol_waypoints.size()):
			var current_wp = patrol_waypoints[i] - global_position  # Convert to local
			
			# Draw waypoint dot
			draw_circle(current_wp, 8.0, waypoint_color)
			
			# Draw waypoint number
			var number_offset = Vector2(0, -15)
			# Note: Can't draw text in _draw() without a font, just use circles
			
			# Draw line to next waypoint
			var next_index = -1
			if patrol_mode == PatrolMode.LOOP:
				next_index = (i + 1) % patrol_waypoints.size()  # Wrap around
			elif patrol_mode == PatrolMode.PING_PONG:
				if i < patrol_waypoints.size() - 1:
					next_index = i + 1  # Forward
			
			if next_index >= 0:
				var next_wp = patrol_waypoints[next_index] - global_position
				draw_line(current_wp, next_wp, path_color, 2.0)
		
		# For PING_PONG, draw return path in different color
		if patrol_mode == PatrolMode.PING_PONG and patrol_waypoints.size() > 1:
			var return_color = Color(0.5, 0.8, 1.0, 0.4)  # Light blue, more transparent
			# Return path is implicit - shown by patrol behavior


## Called every physics frame (before the base Unit._physics_process)
## Checks for nearby zombies and triggers fleeing if needed
## Handles grapple state when caught by zombies
## @param delta: Physics timestep in seconds
func _physics_process(delta: float) -> void:
	# Don't run game logic in editor
	if Engine.is_editor_hint():
		return
	
	# DEBUG: Detect state mismatch
	if is_dead and current_state != State.DEAD:
		push_error("BUG FOUND! is_dead=true but current_state=", State.keys()[current_state], " at ", position)
		# Force correct state
		current_state = State.DEAD
		velocity = Vector2.ZERO
		has_target = false
		attack_target = null
	
	# Handle incubation (dead but converting)
	if current_state == State.DEAD:
		# Force stop all movement every frame
		velocity = Vector2.ZERO
		
		# Debug: Check if velocity is somehow non-zero AFTER we clear it
		if velocity.length() > 0.01:
			push_warning("DEAD HUMAN MOVING! Velocity: ", velocity, " at ", position)
		
		incubation_timer -= delta
		if incubation_timer <= 0.0:
			# Incubation complete - spawn zombie
			print("DEBUG: Incubation timer reached 0, spawning zombie")
			spawn_zombie_conversion()
			queue_free()  # Remove corpse
		return  # Dead humans don't move or react
	
	# Update detection timer
	detection_timer -= delta
	
	# Handle grapple state transitions
	if current_state == State.GRAPPLED:
		is_grappled = true  # Sync flag for compatibility
		# Once grappled, stay grappled until killed - NO ESCAPE
		# Zombies hold humans until they're converted or die
	else:
		is_grappled = false  # Sync flag for compatibility
		# Not currently grappled - check if we should be
		if is_being_attacked():
			# Just got grappled - transition to grappled state
			print("Human at ", position, " grappled by zombie!")
			current_state = State.GRAPPLED
			is_grappled = true  # Sync flag
	
	# While grappled, can't move
	if current_state == State.GRAPPLED:
		velocity = Vector2.ZERO
		return  # Skip normal movement processing
	
	# Update patrol if enabled and in SENTRY state
	# Followers use update_formation_follow() instead of update_patrol()
	if not patrol_leader.is_empty() and current_state == State.SENTRY:
		update_formation_follow(delta)
	elif is_patrolling and current_state == State.SENTRY and not (current_state == State.FLEEING):
		update_patrol(delta)
	
	# Check for nearby zombies periodically (not every frame for performance)
	if detection_timer <= 0.0:
		check_for_nearby_zombies()
		detection_timer = detection_interval
	
	# === MORALE SIGHTING DRAIN (v0.22.2) ===
	# Apply continuous drain from visible zombies in range — runs every frame for smoothness.
	# Suppressed during TUNNEL_VISION (immune to all drain while active).
	if zombies_in_drain_range_count > 0 and current_state != State.DEAD and current_state != State.GRAPPLED and current_state != State.TUNNEL_VISION:
		_last_threat_position = _nearest_drain_zombie_pos
		_drain_morale(sighting_drain * zombies_in_drain_range_count * delta)
	
	# === CONE TIMER (v0.23.0) ===
	# Tracks how long any zombie has been continuously in this human's vision cone.
	# Drives the detection alert system — alert fires at 5 seconds.
	_alert_cooldown = max(0.0, _alert_cooldown - delta)
	_high_urgency_cooldown = max(0.0, _high_urgency_cooldown - delta)
	
	# === HIGH URGENCY DELAY TIMER (v0.23.1) ===
	# Applies pending high urgency facing after 0.4s reaction delay.
	if _high_urgency_delay_timer > 0.0:
		_high_urgency_delay_timer -= delta
		if _high_urgency_delay_timer <= 0.0 and _high_urgency_pending_pos != Vector2.ZERO:
			_target_facing = (_high_urgency_pending_pos - global_position).normalized()
			_high_urgency_pending_pos = Vector2.ZERO
	
	# === HIGH URGENCY HOLD TIMER (v0.23.1) ===
	# After 2s with no zombies in new sightline, return to original facing.
	if _high_urgency_hold_timer > 0.0:
		_high_urgency_hold_timer -= delta
		if _high_urgency_hold_timer <= 0.0 and _zombies_in_vision_count == 0:
			print("👁️ ", name, " high urgency hold expired — returning to original facing")
			facing_direction = degrees_to_vector(sentry_facing_degrees)
			swing_center_angle = sentry_facing_degrees
			_is_alerted = false
	
	var zombies_in_cone := _zombies_in_vision_count > 0
	if zombies_in_cone and current_state != State.TUNNEL_VISION:
		# Zombie in cone — increment timer, freeze return timers
		_cone_timer += delta
		_facing_return_timer = 30.0
		_patrol_resume_timer = 30.0
		
		# Fire detection alert at 5 seconds if not in cooldown
		if _cone_timer >= 5.0 and not _alert_fired and _alert_cooldown <= 0.0:
			_alert_fired = true
			_alert_cooldown = 30.0
			_was_patrolling = is_patrolling
			if is_patrolling:
				is_patrolling = false  # Pause patrol during alert
			print("🚨 ", name, " alert fired — broadcasting to nearby allies")
			_is_alerted = true
			_broadcast_detection_alert(_nearest_vision_zombie_pos)
	else:
		# Cone clear — reset cone timer and alert flag, count down return timers
		if _cone_timer > 0.0:
			# Cone just cleared — note patrol state before timers start
			if _cone_timer >= 5.0:
				# Alert had fired — start return timers
				_facing_return_timer = max(_facing_return_timer, 30.0)
				_patrol_resume_timer = max(_patrol_resume_timer, 30.0)
		_cone_timer = 0.0
		_alert_fired = false
		
		# Count down return timers
		if _facing_return_timer > 0.0:
			_facing_return_timer -= delta
			if _facing_return_timer <= 0.0:
				print("👁️ ", name, " returning to original facing")
				facing_direction = degrees_to_vector(sentry_facing_degrees)
				swing_center_angle = sentry_facing_degrees
				_is_alerted = false
		
		if _patrol_resume_timer > 0.0:
			_patrol_resume_timer -= delta
			if _patrol_resume_timer <= 0.0 and _was_patrolling and not is_patrolling:
				# Resume patrol
				print("🚶 ", name, " resuming patrol after alert")
				is_patrolling = true
				_was_patrolling = false
	
	# === TUNNEL VISION TIMER (v0.22.4) ===
	if current_state == State.TUNNEL_VISION:
		_tunnel_vision_timer -= delta
		if _tunnel_vision_timer <= 0.0:
			print("🔓 ", name, " tunnel vision ended → SENTRY")
			current_state = State.SENTRY
			facing_direction = _tunnel_vision_locked_direction
			morale = morale_max * 0.5
			_update_morale_visual()
		# Don't return here — fall through to shooting system below
	
	# Adjust formation cohesion based on state (BEFORE calling super)
	# Idle/sentry: moderate cohesion (maintain patrol formations)
	# Fleeing: strong cohesion (panic as a group)
	match current_state:
		State.IDLE, State.SENTRY:
			# Formation followers reduce separation while converging to avoid shoving each other
			# off their paths. Once in position they restore normal values.
			if not patrol_leader.is_empty() and _leader_node != null and is_instance_valid(_leader_node):
				var slot_target := _leader_node.global_position + _leader_node.get_formation_offset(formation_slot)
				var dist_to_slot := global_position.distance_to(slot_target)
				if dist_to_slot > formation_slot * 5.0:  # Still converging
					self.cohesion_strength = 0.0
					self.alignment_rate = 0.0
					self.separation_radius = 8.0    # Much smaller — let them pass through
					self.separation_strength = 20.0  # Much weaker — soft nudge only
				else:
					self.cohesion_strength = 0.0    # No cohesion — slot target handles positioning
					self.alignment_rate = 0.0
					self.separation_radius = 20.0   # Normal-ish once in position
					self.separation_strength = 80.0
			else:
				self.cohesion_strength = 12.0
				self.alignment_rate = 0.3
				self.separation_radius = 30.0
				self.separation_strength = 100.0
		State.FLEEING:
			self.cohesion_strength = 0.0  # DISABLED when fleeing - no pull
			self.alignment_rate = 0.0      # No alignment when fleeing
			self.separation_radius = 35.0   # More space while fleeing
			self.separation_strength = 120.0
		State.GRAPPLED, State.DEAD:
			# Disable formation forces
			self.cohesion_strength = 0.0
			self.alignment_rate = 0.0
			self.separation_radius = 20.0
			self.separation_strength = 50.0
	
	# === ALERT ROTATION (v0.23.0) ===
	# Smoothly rotate toward _target_facing when alerted.
	if _target_facing != Vector2.ZERO and _is_alerted:
		var angle_diff := facing_direction.angle_to(_target_facing)
		var max_turn := deg_to_rad(ALERT_TURN_SPEED) * delta
		if abs(angle_diff) <= max_turn:
			facing_direction = _target_facing
			_target_facing = Vector2.ZERO  # Reached target — stop rotating
		else:
			facing_direction = facing_direction.rotated(sign(angle_diff) * max_turn)
	
	# Update sentry swing arc (if applicable)
	# Suppressed during alert — swing would overwrite the alert facing each frame
	if current_state == State.SENTRY and sentry_has_swing and not is_patrolling and patrol_leader.is_empty() and not _is_alerted:
		update_swing_arc(delta)
	
	# Update facing direction based on movement
	# Patrol and formation following both face movement direction
	if velocity.length() > 0.1:
		if is_patrolling or not patrol_leader.is_empty():
			# Leaders face where they're walking; followers face their movement direction
			facing_direction = velocity.normalized()
		elif current_state != State.SENTRY:
			# Non-sentries face movement direction
			facing_direction = velocity.normalized()
		# Stationary sentries (not patrolling, not following) maintain swing direction
	
	# === SHOOTING SYSTEM (v0.22.3) ===
	# Armed units shoot in IDLE, SENTRY, or TUNNEL_VISION states
	if weapon_range > 0.0 and (current_state == State.IDLE or current_state == State.SENTRY or current_state == State.TUNNEL_VISION):
		_update_shooting(delta)
	
	# Fade tracer line
	if _tracer_timer > 0.0:
		_tracer_timer -= delta
		if _tracer_timer <= 0.0:
			_tracer_line.visible = false
	
	# Run normal Unit physics processing (movement/combat)
	super._physics_process(delta)


## === VISION SYSTEM ===

## Checks if this human can see a specific unit based on current state
## Uses vision cones (arc) or circles depending on state
## Also performs raycast for line-of-sight obstacle checking
## @param target: The unit to check vision for
## @return: true if target is visible, false otherwise
func can_see_unit(target: Unit) -> bool:
	if not target or not is_instance_valid(target):
		return false
	
	# Dead and grappled humans have no vision
	if current_state == State.DEAD or current_state == State.GRAPPLED:
		return false
	
	# Calculate distance from center to center
	var distance := position.distance_to(target.position)
	
	# Account for unit radius - vision triggers when edge touches, not center
	# Subtract target's radius so vision triggers at edge
	var effective_distance := distance - UNIT_RADIUS
	
	var in_range := false
	
	# Check range and angle based on current state
	match current_state:
		State.IDLE:
			# Circular vision - 360° awareness
			in_range = effective_distance <= idle_vision_radius
		
		State.SENTRY:
			# Arc vision - directed watching
			in_range = effective_distance <= sentry_vision_range
			if in_range:
				in_range = is_in_vision_arc(target.position, facing_direction, sentry_vision_angle)
		
		State.TUNNEL_VISION:
			# Locked 45° cone — uses stored locked direction, not current facing
			in_range = effective_distance <= sentry_vision_range
			if in_range:
				in_range = is_in_vision_arc(target.position, _tunnel_vision_locked_direction, TUNNEL_VISION_ANGLE)
		
		State.FLEEING:
			# Fleeing vision - hyper-aware panic state with 360° awareness!
			# Use 200px range with NO arc restriction (see threats from all directions)
			# Momentum system handles continued fleeing after losing sight
			# Panicked humans have "eyes in the back of their head"
			in_range = effective_distance <= 200.0
			# NO arc check - can see zombies from any direction when panicked!
	
	# If not in range/angle, can't see it
	if not in_range:
		return false
	
	# Check line of sight (buildings can block vision)
	return has_line_of_sight_to(target)


## Checks if a target position is within a vision arc
## @param target_pos: World position to check
## @param arc_direction: Direction the arc is facing (normalized)
## @param arc_angle_degrees: Total angle of arc in degrees (e.g., 90° means 45° on each side)
## @return: true if target is within the arc
func is_in_vision_arc(target_pos: Vector2, arc_direction: Vector2, arc_angle_degrees: float) -> bool:
	# Get direction to target
	var to_target := (target_pos - position).normalized()
	
	# Calculate angle between arc direction and target direction
	var angle_to_target := arc_direction.angle_to(to_target)
	
	# Check if within half-angle on either side
	var half_angle_rad := deg_to_rad(arc_angle_degrees / 2.0)
	
	return abs(angle_to_target) <= half_angle_rad


## Finds the nearest zombie that is both within vision range AND visible
## Uses vision cones/circles and line-of-sight raycasting
## @return: The nearest visible zombie, or null if none found
func find_nearest_visible_zombie() -> Unit:
	# Get all zombie units
	var zombies := get_tree().get_nodes_in_group("zombies")
	
	var nearest_visible: Unit = null
	var nearest_distance := INF
	
	# Check each zombie
	for zombie in zombies:
		if not zombie is Zombie:
			continue
		
		# Skip dead zombies (incubating corpses)
		if zombie.is_dead if zombie.has_method("is_dead") else false:
			continue
		
		# Costumed zombies are invisible to all human detection
		if zombie.get("is_costumed") == true:
			continue
		
		# Check if this zombie is in our vision (cone or circle)
		if can_see_unit(zombie):
			var distance := position.distance_to(zombie.position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_visible = zombie
	
	return nearest_visible


## Checks for nearby zombies and allies each detection tick.
## Drives the morale system:
##   - Counts zombies in drain range → stored for per-frame sighting drain
##   - Detects ally state transitions → applies one-time morale hits
##   - Continues updating flee direction if already fleeing
## (v0.22.2 — replaces binary flee trigger and propagate_flee_to_group cascade)
func check_for_nearby_zombies() -> void:
	# Skip if dead or grappled (no detection)
	# Also skip during tunnel vision — immune to all morale drain events while active
	if current_state == State.DEAD or current_state == State.GRAPPLED or current_state == State.TUNNEL_VISION:
		return
	
	var all_humans := get_tree().get_nodes_in_group("humans")
	var morale_event_radius: float = 150.0  # Radius for ally event hooks
	
	# === ALLY STATE TRANSITION HOOKS ===
	# Scan nearby allies and detect state transitions since last tick.
	# One-time flat morale hits are applied on the tick the transition is first detected.
	var current_ally_states: Dictionary = {}
	
	for other in all_humans:
		if other == self or not other is Human:
			continue
		var ally := other as Human
		if not is_instance_valid(ally) or ally.current_state == State.DEAD:
			continue
		
		var dist := position.distance_to(ally.position)
		if dist > morale_event_radius:
			continue
		
		var ally_id := ally.get_instance_id()
		var current_ally_state := ally.current_state
		current_ally_states[ally_id] = current_ally_state
		
		# Only fire transition events if we knew this ally before
		if _last_ally_states.has(ally_id):
			var last_state = _last_ally_states[ally_id]
			
			# Ally just transitioned to GRAPPLED → apply grappled_drain + high urgency alert
			if current_ally_state == State.GRAPPLED and last_state != State.GRAPPLED:
				print("💛 ", name, " morale hit: ally grappled nearby (", int(dist), "px) — -", grappled_drain)
				_last_threat_position = _find_closest_zombie_to(ally.position)
				_drain_morale(grappled_drain)
				_broadcast_high_urgency_alert(ally.position, 75.0)
			
			# Ally just transitioned to FLEEING (moving past) → apply fleeing_drain
			if current_ally_state == State.FLEEING and last_state != State.FLEEING:
				if ally.velocity.length() > 10.0:  # Must be actually moving (fleeing past)
					print("💛 ", name, " morale hit: ally fleeing past (", int(dist), "px) — -", fleeing_drain)
					_last_threat_position = _find_closest_zombie_to(ally.position)
					_drain_morale(fleeing_drain)
	
	# Replace last known ally states with current snapshot (only tracked allies)
	_last_ally_states = current_ally_states
	
	# === ZOMBIE DRAIN RANGE COUNT ===
	# Count visible zombies within morale drain range.
	# For armed units: weapon_range threshold. For civilians: full vision range.
	# Result stored in zombies_in_drain_range_count for per-frame sighting drain.
	var drain_threshold: float = weapon_range if weapon_range > 0.0 else sentry_vision_range
	var zombies := get_tree().get_nodes_in_group("zombies")
	var new_drain_count: int = 0
	var new_vision_count: int = 0
	var nearest_drain_dist := INF
	var nearest_vision_dist := INF
	
	for zombie in zombies:
		if not zombie is Zombie or not is_instance_valid(zombie):
			continue
		var z := zombie as Zombie
		if z.current_state == Zombie.State.DEAD:
			continue
		# Costumed zombies are invisible to all human detection
		if z.get("is_costumed") == true:
			continue
		var dist_to_zombie := position.distance_to(z.position)
		var visible := can_see_unit(z)
		if dist_to_zombie <= drain_threshold and visible:
			new_drain_count += 1
			if dist_to_zombie < nearest_drain_dist:
				nearest_drain_dist = dist_to_zombie
				_nearest_drain_zombie_pos = z.position
		if dist_to_zombie <= sentry_vision_range and visible:
			new_vision_count += 1
			if dist_to_zombie < nearest_vision_dist:
				nearest_vision_dist = dist_to_zombie
				_nearest_vision_zombie_pos = z.position
	
	zombies_in_drain_range_count = new_drain_count
	_zombies_in_vision_count = new_vision_count
	
	# === FLEE DIRECTION UPDATE ===
	# If already fleeing, keep updating movement direction toward safety.
	# (Flee initiation is now handled by _check_morale(), not here.)
	if current_state == State.FLEEING:
		var flee_dir := calculate_flee_direction()
		if flee_dir == Vector2.ZERO:
			# Priority system says we're safe — stop fleeing
			print("Human at ", position, " stopped fleeing - truly safe")
			last_flee_direction = Vector2.ZERO
			zombies_in_drain_range_count = 0
			current_state = State.SENTRY if initial_state == State.SENTRY else State.IDLE
			# Recover to half morale — still rattled, more vulnerable to second trigger
			morale = morale_max * 0.5
			_update_morale_visual()
		else:
			var flee_target := position + flee_dir * flee_distance
			set_move_target(flee_target)


## === SHOOTING SYSTEM METHODS (v0.22.3) ===

## Main shooting update — called every frame for armed units in IDLE/SENTRY.
## Handles target acquisition, aim countdown, LOS pause, and firing.
## @param delta: Time since last frame
func _update_shooting(delta: float) -> void:
	# If we have a target, check it's still valid
	if shoot_target != null:
		if not is_instance_valid(shoot_target) or shoot_target.current_state == Zombie.State.DEAD:
			shoot_target = null
			_aim_timer = 0.0
			_aim_paused = false
			return
		
		var in_vision := can_see_unit(shoot_target)  # Full vision cone check
		var in_weapon_range := position.distance_to(shoot_target.position) <= weapon_range
		
		if in_vision:
			# Target visible in cone — run aim timer regardless of weapon range
			_aim_paused = false
			_aim_timer -= delta
			if _aim_timer <= 0.0:
				if in_weapon_range:
					# In range — fire
					_fire_at(shoot_target)
					# Reacquire immediately
					shoot_target = _acquire_shoot_target()
					_aim_timer = aim_time if shoot_target != null else 0.0
					_aim_paused = false
				else:
					# Timer expired but not in range yet — hold at 0, wait for zombie to close
					_aim_timer = 0.0
		else:
			# Lost vision entirely (building or left cone) — pause timer
			if not _aim_paused:
				_aim_paused = true
				print("⏸️ ", name, " aim paused — target lost from vision cone")
			# If target has also left vision range entirely, drop it and reacquire
			if position.distance_to(shoot_target.position) > sentry_vision_range:
				shoot_target = _acquire_shoot_target()
				_aim_timer = aim_time if shoot_target != null else 0.0
				_aim_paused = false
	else:
		# No target — try to acquire within vision cone
		shoot_target = _acquire_shoot_target()
		if shoot_target:
			_aim_timer = aim_time
			_aim_paused = false
			_aim_sound.play()
			print("🎯 ", name, " acquired target: ", shoot_target.name, " (", int(position.distance_to(shoot_target.position)), "px)")


## Finds the closest zombie visible in the vision cone (full vision range).
## Acquisition range = full vision (350px), not weapon range.
## @return: Closest valid shoot target, or null if none found
func _acquire_shoot_target() -> Unit:
	var zombies := get_tree().get_nodes_in_group("zombies")
	var best_target: Unit = null
	var best_dist := INF
	
	for z in zombies:
		if not z is Zombie or not is_instance_valid(z):
			continue
		var zombie := z as Zombie
		if zombie.current_state == Zombie.State.DEAD:
			continue
		# Costumed zombies cannot be targeted
		if zombie.get("is_costumed") == true:
			continue
		if not can_see_unit(zombie):  # Uses full vision range + cone + LOS
			continue
		var dist := position.distance_to(zombie.position)
		if dist < best_dist:
			best_dist = dist
			best_target = zombie
	
	return best_target


## Fires a shot at the target — draws tracer first, then applies damage.
## Tracer drawn before damage so it's visible even if the zombie dies instantly.
## @param target: The zombie to shoot
func _fire_at(target: Unit) -> void:
	if not is_instance_valid(target):
		return
	
	print("⚡ ", name, " fired at ", target.name, " (", int(position.distance_to(target.position)), "px)")
	
	# Broadcast high urgency alert to nearby allies — gunshot radius 150px
	_broadcast_high_urgency_alert(target.global_position, 150.0)
	
	# Draw tracer FIRST — before damage — so it's visible even if zombie dies this frame
	var start_local := Vector2(0.0, 15.0)  # Bottom edge of sprite
	var target_local := to_local(target.global_position)
	_tracer_line.clear_points()
	_tracer_line.add_point(start_local)
	_tracer_line.add_point(target_local)
	_tracer_line.visible = true
	_tracer_timer = TRACER_FADE_DURATION
	
	# Apply damage after tracer is set up — 50 = one-shot kill (humans have 75hp)
	# Knockback pushes zombie AWAY from shooter (target - shooter = toward target, so negate it)
	var shot_direction := (target.global_position - global_position).normalized()
	if target is Zombie:
		(target as Zombie).take_damage(50.0, shot_direction)
	else:
		target.take_damage(50.0)


## === ALERT SYSTEM (v0.23.0) ===

## Facing offsets per defender class, relative to threat direction.
## Index 0 = the alerting human themselves. Subsequent indices assigned to
## nearby allies sorted by distance. Degrees are relative to threat direction,
## not world north. Civilians have no offsets — flee response only.
## Facing offset magnitudes per defender class.
## Index 0 = the alerting human (always 0° — faces threat directly).
## Index 1+ = magnitude assigned to the 1st, 2nd, 3rd... ally on each side.
## Sign is determined by which side of the alerter the ally is on — right = positive, left = negative.
## If more allies than entries, last entry is reused.
const ALERT_OFFSETS: Dictionary = {
	# All face threat directly — inexperience, tunnel focus
	DefenderClass.MILITIA:   [0, 0, 0, 0],
	# Fan out around threat
	DefenderClass.POLICE:    [0, 45, 90],
	# Secure perimeter — first ally covers flank, second covers further around
	DefenderClass.GI:        [0, 105, 165],
	# Same as GI for now
	DefenderClass.SPEC_OPS:  [0, 105, 165],
}

## Radius within which detection alert propagates to nearby allies.
const ALERT_RADIUS: float = 150.0


## Broadcasts a detection alert to nearby allies.
## Each ally rotates to a class-appropriate facing offset relative to the threat.
## Civilians are excluded — their flee response cascades through existing morale system.
## @param threat_pos: World position of the detected zombie
func _broadcast_detection_alert(threat_pos: Vector2) -> void:
	if threat_pos == Vector2.ZERO:
		return
	
	print("🚨 ALERT BROADCAST from ", name, " | threat_pos: ", threat_pos, " | my_pos: ", global_position)
	
	# Apply offset 0 to self — alerter always faces threat directly
	_apply_alert_facing(threat_pos, 0.0)
	
	var threat_dir := (threat_pos - global_position).normalized()
	
	# Find nearby eligible allies
	var all_humans := get_tree().get_nodes_in_group("humans")
	var right_allies: Array = []  # Allies to the right of the threat direction
	var left_allies: Array = []   # Allies to the left of the threat direction
	
	for other in all_humans:
		if other == self or not other is Human:
			continue
		var ally := other as Human
		if not is_instance_valid(ally):
			continue
		if ally.current_state in [State.FLEEING, State.GRAPPLED, State.DEAD, State.TUNNEL_VISION]:
			continue
		if ally.shoot_target != null:
			continue
		if ally.defender_class == DefenderClass.CIVILIAN:
			continue
		var dist := global_position.distance_to(ally.global_position)
		if dist > ALERT_RADIUS:
			continue
		
		# Determine which side of the alerter this ally is on
		# Cross product of threat_dir and ally_dir: positive = right, negative = left
		var to_ally := (ally.global_position - global_position).normalized()
		var cross := threat_dir.x * to_ally.y - threat_dir.y * to_ally.x
		if cross >= 0.0:
			right_allies.append({"human": ally, "dist": dist})
		else:
			left_allies.append({"human": ally, "dist": dist})
		print("  📋 ally: ", ally.name, " side: ", ("right" if cross >= 0.0 else "left"), " dist: ", int(dist), "px")
	
	right_allies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	left_allies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	# Get offset magnitudes for this class (index 1, 2, 3... for right; mirror for left)
	var offsets: Array = ALERT_OFFSETS.get(defender_class, [])
	
	# Assign positive offsets to right allies, negative to left allies
	# Index into magnitudes: i=0 is first ally on that side → offsets[1], i=1 → offsets[2], etc.
	for i in right_allies.size():
		var ally: Human = right_allies[i]["human"]
		var idx: int = min(i + 1, offsets.size() - 1)
		var offset_deg: float = abs(float(offsets[idx]))  # Always positive for right
		ally._receive_detection_alert(threat_pos, offset_deg)
		print("  📡 ", ally.name, " → right offset +", offset_deg, "°")
	
	for i in left_allies.size():
		var ally: Human = left_allies[i]["human"]
		var idx: int = min(i + 1, offsets.size() - 1)
		var offset_deg: float = -abs(float(offsets[idx]))  # Always negative for left
		ally._receive_detection_alert(threat_pos, offset_deg)
		print("  📡 ", ally.name, " → left offset ", offset_deg, "°")


## Called by an alerting ally to apply a facing offset to this human.
## @param threat_dir: Normalised direction toward the detected zombie
## @param offset_index: Index into this human's ALERT_OFFSETS array
func _receive_detection_alert(threat_pos: Vector2, offset_deg: float) -> void:
	if current_state in [State.FLEEING, State.GRAPPLED, State.DEAD, State.TUNNEL_VISION]:
		return
	if shoot_target != null:
		return
	_alert_cooldown = 30.0
	_was_patrolling = is_patrolling
	if is_patrolling:
		is_patrolling = false
	_facing_return_timer = 120.0
	_patrol_resume_timer = 30.0
	_is_alerted = true
	_apply_alert_facing(threat_pos, offset_deg)


## Applies a single facing offset to this human toward a threat position.
## Calculates threat direction from this unit's own position (not the alerter's).
## Sets _target_facing for smooth rotation rather than snapping instantly.
## @param threat_pos: World position of the detected zombie
## @param offset_index: Index into ALERT_OFFSETS for this class
func _apply_alert_facing(threat_pos: Vector2, offset_deg: float) -> void:
	if not ALERT_OFFSETS.has(defender_class) and offset_deg == 0.0:
		# Civilians — no offset, no rotation
		return
	var own_threat_dir := (threat_pos - global_position).normalized()
	var offset_rad := deg_to_rad(offset_deg)
	_target_facing = own_threat_dir.rotated(offset_rad)
	print("  👁️ ", name, " | my_pos: ", global_position.snapped(Vector2(1,1)), " | threat_pos: ", threat_pos.snapped(Vector2(1,1)), " | own_threat_dir: ", own_threat_dir.snapped(Vector2(0.01,0.01)), " | offset: ", offset_deg, "° | target_facing: ", _target_facing.snapped(Vector2(0.01,0.01)))


## === HIGH URGENCY ALERT SYSTEM (v0.23.1) ===

## Broadcasts a high urgency alert to nearby humans within radius.
## Used for ally grappled (75px), ally killed (75px), and gunshot (150px) events.
## All classes respond identically — direct facing, no class offsets.
## Civilians included — FLEEING state check excludes them naturally once running.
## @param event_pos: World position of the event
## @param radius: Broadcast radius
func _broadcast_high_urgency_alert(event_pos: Vector2, radius: float) -> void:
	var all_humans := get_tree().get_nodes_in_group("humans")
	for other in all_humans:
		if other == self or not other is Human:
			continue
		var ally := other as Human
		if not is_instance_valid(ally):
			continue
		if global_position.distance_to(ally.global_position) <= radius:
			ally.receive_high_urgency_alert(event_pos)


## Called when a nearby high urgency event occurs (grapple, kill, or gunshot).
## All classes respond identically — direct facing toward event position.
## 0.4s reaction delay before facing updates. 2s shared cooldown. 2s hold after event.
## @param event_pos: World position of the event to face
func receive_high_urgency_alert(event_pos: Vector2) -> void:
	if _high_urgency_cooldown > 0.0:
		return
	if current_state not in [State.IDLE, State.SENTRY]:
		return
	if shoot_target != null:
		return
	_high_urgency_pending_pos = event_pos
	_high_urgency_delay_timer = 0.4
	_high_urgency_cooldown = 2.0
	_high_urgency_hold_timer = 2.0
	_is_alerted = true
	print("⚡ ", name, " high urgency alert — reacting in 0.4s")

## Applies a morale drain, clamps to 0, and checks for response trigger.
## @param amount: Amount to subtract from current morale (positive value)
func _drain_morale(amount: float) -> void:
	if current_state == State.DEAD or current_state == State.GRAPPLED:
		return
	morale = max(0.0, morale - amount)
	_update_morale_visual()
	_check_morale()


## Checks if morale has hit 0 and triggers the primary stress response.
## For Civilian, Militia, Police: flee.
## Tunnel Vision (GI, Spec Ops) implemented in Phase 5.
func _check_morale() -> void:
	if morale > 0.0 or current_state == State.FLEEING:
		return
	if current_state == State.DEAD or current_state == State.GRAPPLED:
		return
	
	match defender_class:
		DefenderClass.CIVILIAN, DefenderClass.MILITIA, DefenderClass.POLICE:
			print("💀 ", name, " morale empty → FLEEING (", DefenderClass.keys()[defender_class], ")")
			current_state = State.FLEEING
			is_patrolling = false
			# Find nearest visible zombie to flee from; fall back to direction-only if none
			var threat := find_nearest_visible_zombie()
			if threat:
				start_fleeing(threat)
			else:
				# No visible zombie — flee away from nearest zombie in any direction
				var zombies := get_tree().get_nodes_in_group("zombies")
				var nearest_zombie: Unit = null
				var nearest_dist := INF
				for z in zombies:
					if z is Zombie and z.current_state != Zombie.State.DEAD:
						var d := position.distance_to(z.position)
						if d < nearest_dist:
							nearest_dist = d
							nearest_zombie = z
				if nearest_zombie:
					var away := (position - nearest_zombie.position).normalized()
					start_fleeing_in_direction(away)
		DefenderClass.GI, DefenderClass.SPEC_OPS:
			print("🔍 ", name, " tunnel vision → locked toward threat")
			current_state = State.TUNNEL_VISION
			is_patrolling = false
			# Lock toward the event that broke morale — face the threat, not just forward
			if _last_threat_position != Vector2.ZERO:
				_tunnel_vision_locked_direction = ((_last_threat_position - position).normalized())
			else:
				_tunnel_vision_locked_direction = facing_direction  # Fallback to current facing
			_tunnel_vision_timer = TUNNEL_VISION_DURATION


## Updates the morale bar visibility based on current morale.
## Bar appears below 80% morale only when unit is IDLE or SENTRY.
## Hidden when fleeing, grappled, or dead — no longer actionable in those states.
func _update_morale_visual() -> void:
	if not _morale_bar:
		return
	
	# Only show bar when unit is standing their ground
	if current_state != State.IDLE and current_state != State.SENTRY:
		_morale_bar.visible = false
		return
	
	var ratio := morale / morale_max if morale_max > 0.0 else 0.0
	_morale_bar.max_value = morale_max
	_morale_bar.value = morale
	_morale_bar.visible = ratio < 0.8


## Finds the world position of the closest zombie to a given point.
## Used to point tunnel vision toward the zombie causing an ally event,
## rather than toward the ally themselves.
## Falls back to the reference point if no zombies found.
## @param point: World position to search near
## @return: Position of closest zombie, or point if none found
func _find_closest_zombie_to(point: Vector2) -> Vector2:
	var zombies := get_tree().get_nodes_in_group("zombies")
	var closest_pos := point  # Fallback
	var closest_dist := INF
	for z in zombies:
		if not z is Zombie or not is_instance_valid(z):
			continue
		if (z as Zombie).current_state == Zombie.State.DEAD:
			continue
		var d := point.distance_to(z.position)
		if d < closest_dist:
			closest_dist = d
			closest_pos = z.position
	return closest_pos


## Called by a dying nearby ally to apply killed_drain to this unit.
## Invoked from die() on humans within 150px.
## @param ally_position: World position of the ally that died
func receive_ally_killed_shock(ally_position: Vector2) -> void:
	if current_state == State.DEAD or current_state == State.GRAPPLED:
		return
	print("💛 ", name, " morale hit: ally killed nearby — -", killed_drain)
	_last_threat_position = _find_closest_zombie_to(ally_position)
	_drain_morale(killed_drain)
	_broadcast_high_urgency_alert(ally_position, 75.0)


## Uses raycasting to detect if buildings are blocking the view
## @param target: The Unit to check line of sight to
## @return: true if we can see the target, false if buildings block the view
func has_line_of_sight_to(target: Unit) -> bool:
	# Create a raycast query from this human to the target
	var query := PhysicsRayQueryParameters2D.create(position, target.position)
	
	# Exclude units from the raycast - we only want to hit buildings
	# This checks collision layer 1 (default layer for StaticBody2D)
	query.collision_mask = 1
	
	# Don't collide with the human or zombie themselves
	query.exclude = [self, target]
	
	# Perform the raycast
	var result := space_state.intersect_ray(query)
	
	# If the raycast hit something (a building), LOS is blocked
	# If it didn't hit anything, we have clear line of sight
	return result.is_empty()


## Checks if there's a clear line of sight to a specific point (like escape zone)
## Uses raycasting to detect if buildings are blocking the view
## @param point: The world position to check line of sight to
## @return: true if we can see the point, false if buildings block the view
func has_line_of_sight_to_point(point: Vector2) -> bool:
	# Create a raycast query from this human to the point
	var query := PhysicsRayQueryParameters2D.create(position, point)
	
	# Exclude units from the raycast - we only want to hit buildings
	query.collision_mask = 1
	
	# Don't collide with the human itself
	query.exclude = [self]
	
	# Perform the raycast
	var result := space_state.intersect_ray(query)
	
	# If the raycast hit something (a building), LOS is blocked
	return result.is_empty()


## Finds the nearest VISIBLE escape zone to this human
## Only considers zones with clear line of sight (no walls blocking)
## @return: The closest visible EscapeZone node, or null if none visible
func get_nearest_escape_zone() -> Node2D:
	var escape_zones := get_tree().get_nodes_in_group("escape_zone")
	if escape_zones.is_empty():
		return null
	
	var nearest_zone: Node2D = null
	var nearest_distance := INF
	
	for zone in escape_zones:
		if not is_instance_valid(zone):
			continue
		
		# CRITICAL: Use global_position for nested zones
		var distance := global_position.distance_to(zone.global_position)
		
		# Only consider zones we can actually see (no walls blocking)
		if not has_line_of_sight_to_point(zone.global_position):
			continue
		
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_zone = zone
	
	return nearest_zone


## Converts degrees to a normalized Vector2 direction
## 0° = North (up), 90° = East (right), 180° = South (down), 270° = West (left)
## @param degrees: Angle in degrees (0-360)
## @return: Normalized direction vector
func degrees_to_vector(degrees: float) -> Vector2:
	# Convert to radians
	# Godot's coordinate system: 0° right, 90° down
	# We want: 0° up, 90° right
	# So subtract 90° to rotate the reference
	var radians = deg_to_rad(degrees - 90.0)
	return Vector2(cos(radians), sin(radians)).normalized()


## Loads patrol waypoints from child Node2D nodes
## Looks for children named "Waypoint1", "Waypoint2", etc.
## Sorts them by name and uses their global positions as waypoints
## This allows visual waypoint placement in the editor
func load_waypoints_from_children() -> void:
	var waypoint_nodes: Array[Node] = []
	
	# Find all children with "Waypoint" in their name
	for child in get_children():
		if child.name.begins_with("Waypoint"):
			waypoint_nodes.append(child)
	
	# If no waypoints found, nothing to do
	if waypoint_nodes.size() == 0:
		return
	
	# Sort waypoints by name (Waypoint1, Waypoint2, etc.)
	# Using natural sort to handle numbers correctly (Waypoint1 < Waypoint2 < Waypoint10)
	waypoint_nodes.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	
	# Debug: Print sort order
	print("Waypoint sort order for ", name, ":")
	for i in range(waypoint_nodes.size()):
		print("  [", i, "] ", waypoint_nodes[i].name)
	
	# Extract global positions
	patrol_waypoints.clear()
	for i in range(waypoint_nodes.size()):
		var waypoint = waypoint_nodes[i]
		if waypoint is Node2D:
			patrol_waypoints.append(waypoint.global_position)
			print("  Loaded waypoint: ", waypoint.name, " at ", waypoint.global_position)
	
	print("Loaded ", patrol_waypoints.size(), " waypoints from child nodes for ", name)


## Updates the swing arc for sentry behavior
## Uses smooth sin/cos oscillation for natural head-turning motion
## Called every frame when in SENTRY state with swing enabled
## @param delta: Time since last frame in seconds
## @param force: If true, bypasses sentry_has_swing check (used for per-waypoint swing)
func update_swing_arc(delta: float, force: bool = false) -> void:
	if not sentry_has_swing and not force:
		return
	
	# Handle pause at extremes
	if is_swing_paused:
		swing_pause_timer -= delta
		if swing_pause_timer <= 0.0:
			is_swing_paused = false
			swing_direction *= -1  # Reverse direction after pause
		return
	
	# Update swing offset using smooth oscillation
	# Instead of linear movement, use sin wave for natural acceleration/deceleration
	var swing_progress = current_swing_offset / sentry_swing_range if sentry_swing_range > 0 else 0
	
	# Smooth speed adjustment: slower at extremes, faster in middle
	# Using cos(progress) to slow down at edges
	var speed_multiplier = 1.0
	if abs(swing_progress) > 0.7:  # Near extremes
		speed_multiplier = 0.5 + 0.5 * (1.0 - abs(swing_progress))
	
	current_swing_offset += sentry_swing_speed * delta * swing_direction * speed_multiplier
	
	# Check if reached extreme
	if abs(current_swing_offset) >= sentry_swing_range:
		# Clamp to range
		current_swing_offset = sentry_swing_range * swing_direction
		
		# Start pause
		is_swing_paused = true
		swing_pause_timer = sentry_swing_pause
	
	# Update facing direction based on swing
	var current_angle = swing_center_angle + current_swing_offset
	facing_direction = degrees_to_vector(current_angle)


## Updates patrol movement for sentries
## Moves between waypoints in LOOP or PING_PONG mode
## Phase C: Supports per-waypoint pause, swing, and facing overrides
## v0.21.0: Supports formation regroup waiting before advancing
## @param delta: Time since last frame in seconds
func update_patrol(delta: float) -> void:
	if patrol_waypoints.size() == 0:
		is_patrolling = false
		return
	
	# === PHASE C: HANDLE ACTIVE WAYPOINT PAUSE ===
	if is_patrol_paused:
		# Run swing if enabled for this waypoint (force=true bypasses sentry_has_swing)
		if is_waypoint_swinging:
			update_swing_arc(delta, true)
		
		patrol_pause_timer -= delta
		if patrol_pause_timer <= 0.0:
			is_patrol_paused = false
			is_waypoint_swinging = false
			print("▶️ PATROL RESUMING from waypoint ", current_waypoint_index)
			# Check regroup before advancing
			if _has_followers() and not all_followers_in_formation():
				is_waiting_to_regroup = true
				regroup_timer = formation_regroup_timeout
				has_target = false
				velocity = Vector2.ZERO
				print("⏳ WAITING TO REGROUP after pause at waypoint ", current_waypoint_index)
				return
			# All followers in position (or no followers) - advance now
			advance_to_next_waypoint()
			if patrol_waypoints.size() > 0:
				set_move_target(patrol_waypoints[current_waypoint_index])
				move_speed = patrol_speed
		return  # Stay stopped until pause completes
	
	# === FORMATION REGROUP WAIT ===
	if is_waiting_to_regroup:
		regroup_timer -= delta
		if all_followers_in_formation() or regroup_timer <= 0.0:
			if regroup_timer <= 0.0:
				print("⏱️ REGROUP TIMEOUT - advancing without full squad at waypoint ", current_waypoint_index)
			else:
				print("✅ SQUAD REGROUPED - advancing from waypoint ", current_waypoint_index)
			is_waiting_to_regroup = false
			advance_to_next_waypoint()
			if patrol_waypoints.size() > 0:
				set_move_target(patrol_waypoints[current_waypoint_index])
				move_speed = patrol_speed
		return  # Hold position while waiting
	
	# === WAYPOINT ARRIVAL CHECK ===
	var target_waypoint = patrol_waypoints[current_waypoint_index]
	var distance_to_waypoint = global_position.distance_to(target_waypoint)
	
	if distance_to_waypoint < 10.0:
		# Arrived - apply Phase C observation behaviour if configured
		
		# 1. FACING OVERRIDE: Turn to face a specific direction on arrival
		if current_waypoint_index < patrol_waypoint_facing.size():
			var override_degrees = patrol_waypoint_facing[current_waypoint_index]
			if override_degrees >= 0.0:  # -1.0 = no override
				swing_center_angle = override_degrees
				facing_direction = degrees_to_vector(override_degrees)
				current_swing_offset = 0.0  # Reset swing to center of new facing
				print("🧭 FACING OVERRIDE at waypoint ", current_waypoint_index, ": ", override_degrees, "°")
		
		# 2. PAUSE: Stop and observe for a duration
		var pause_duration := 0.0
		if current_waypoint_index < patrol_pause_durations.size():
			pause_duration = patrol_pause_durations[current_waypoint_index]
		
		if pause_duration > 0.0:
			is_patrol_paused = true
			patrol_pause_timer = pause_duration
			
			# Stop movement for duration of pause
			has_target = false
			velocity = Vector2.ZERO
			
			# 3. SWING: Look around during the pause
			var should_swing := false
			if current_waypoint_index < patrol_waypoint_swing.size():
				should_swing = patrol_waypoint_swing[current_waypoint_index]
			
			if should_swing:
				is_waypoint_swinging = true
				# Reset swing state for a clean start from current facing
				current_swing_offset = 0.0
				swing_direction = 1
				is_swing_paused = false
				print("⏸️ PATROL PAUSED at waypoint ", current_waypoint_index,
						" for ", pause_duration, "s (🔍 swinging)")
			else:
				print("⏸️ PATROL PAUSED at waypoint ", current_waypoint_index,
						" for ", pause_duration, "s")
			return  # Don't advance until pause completes
		
		# 4. REGROUP CHECK (no pause configured)
		if _has_followers() and not all_followers_in_formation():
			is_waiting_to_regroup = true
			regroup_timer = formation_regroup_timeout
			has_target = false
			velocity = Vector2.ZERO
			print("⏳ WAITING TO REGROUP at waypoint ", current_waypoint_index)
			return
		
		# No pause, no regroup needed - advance immediately
		advance_to_next_waypoint()
		
		# Get new target after advancing
		if current_waypoint_index < patrol_waypoints.size():
			target_waypoint = patrol_waypoints[current_waypoint_index]
	
	# Move toward current waypoint at patrol speed
	set_move_target(target_waypoint)
	move_speed = patrol_speed


## Advances to the next waypoint based on patrol mode
func advance_to_next_waypoint() -> void:
	if patrol_mode == PatrolMode.LOOP:
		# LOOP mode: 0→1→2→3→0 (wraps around)
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
	
	elif patrol_mode == PatrolMode.PING_PONG:
		# PING_PONG mode: 0→1→2→3→2→1→0
		current_waypoint_index += patrol_direction
		
		# Check if reached either end
		if current_waypoint_index >= patrol_waypoints.size():
			# Reached end, reverse
			current_waypoint_index = patrol_waypoints.size() - 2  # Go back one
			patrol_direction = -1
		elif current_waypoint_index < 0:
			# Reached beginning, reverse
			current_waypoint_index = 1  # Go forward one
			patrol_direction = 1


## Returns true if this human is a formation follower (has a patrol_leader set)
func is_follower() -> bool:
	return not patrol_leader.is_empty()


## Returns true if this leader has any formation followers
func _has_followers() -> bool:
	if not get_tree():
		return false
	var humans := get_tree().get_nodes_in_group("humans")
	for human in humans:
		if not human is Human or human == self:
			continue
		var follower := human as Human
		if follower.patrol_leader.is_empty():
			continue
		var leader_node = follower.get_node_or_null(follower.patrol_leader)
		if leader_node == self:
			return true
	return false


## Returns true if all SENTRY-state followers are within range of their formation slots
## Ignores followers who are fleeing or grappled (out of action)
func all_followers_in_formation() -> bool:
	if not get_tree():
		return true
	var humans := get_tree().get_nodes_in_group("humans")
	var threshold := formation_spacing * 2.0  # Generous tolerance
	for human in humans:
		if not human is Human or human == self:
			continue
		var follower := human as Human
		if follower.patrol_leader.is_empty():
			continue
		var leader_node = follower.get_node_or_null(follower.patrol_leader)
		if leader_node != self:
			continue
		# Only count SENTRY followers - fleeing/grappled ones are out of action
		if follower.current_state != State.SENTRY:
			continue
		var target_pos := global_position + get_formation_offset(follower.formation_slot)
		if follower.global_position.distance_to(target_pos) > threshold:
			return false
	return true


## Calculates the world-space offset for a given formation slot number
## Based on this leader's current facing_direction and formation_shape
## @param slot: 1-based slot index
## @return: Offset vector to add to leader's global_position
func get_formation_offset(slot: int) -> Vector2:
	# Use facing direction, fall back to UP if stationary
	var forward := facing_direction if facing_direction.length() > 0.1 else Vector2.UP
	var right := forward.rotated(PI / 2.0)
	var back := -forward
	var s := formation_spacing
	
	match formation_shape:
		FormationShape.LINE_ABREAST:
			# Side by side perpendicular to travel: R1, L1, R2, L2, R3...
			var side_index := int(ceil(float(slot) / 2.0))
			var side_sign := 1 if slot % 2 == 1 else -1
			return right * side_sign * side_index * s
		
		FormationShape.COLUMN:
			# Single file directly behind leader
			return back * slot * s
		
		FormationShape.WEDGE:
			# V-shape: followers spread behind and to the sides
			var row := int(ceil(float(slot) / 2.0))
			var side_sign := 1 if slot % 2 == 1 else -1
			return back * row * s + right * side_sign * row * s * 0.75
		
		FormationShape.ECHELON:
			# Diagonal line extending right and behind
			return back * slot * s + right * slot * s * 0.75
		
		FormationShape.DIAMOND:
			# Diamond: right, left, behind — overflow to column for 4+
			match slot:
				1: return right * s
				2: return -right * s
				3: return back * s
				_: return back * (slot - 2) * s
	
	return Vector2.ZERO


## Formation follower update — called each frame instead of update_patrol()
## Resolves leader reference lazily (handles node ordering in scene)
## Moves this follower to their assigned formation slot behind the leader
## @param delta: Physics timestep in seconds
func update_formation_follow(delta: float) -> void:
	# Lazy-resolve leader NodePath to a cached node reference
	if _leader_node == null or not is_instance_valid(_leader_node):
		if not patrol_leader.is_empty():
			_leader_node = get_node_or_null(patrol_leader) as Human
		# Still null - node not found yet, try again next frame
		if _leader_node == null:
			return
	
	# Leader validity check every frame — handles leader death
	if not is_instance_valid(_leader_node):
		_leader_node = null
		# Go idle if we were still on patrol duty
		if current_state == State.SENTRY:
			print("⚠️ ", name, ": leader gone — going idle")
			current_state = State.IDLE
			has_target = false
			velocity = Vector2.ZERO
		return
	
	# If we're not in a moveable state, don't try to hold formation
	if current_state == State.FLEEING or current_state == State.GRAPPLED or current_state == State.DEAD:
		return
	
	# If the leader is fleeing, don't try to follow them
	# Our own check_for_nearby_zombies() will trigger our flee independently
	if _leader_node.current_state == State.FLEEING:
		return
	
	# Calculate where our slot is right now
	var slot_target: Vector2 = _leader_node.global_position + _leader_node.get_formation_offset(formation_slot)
	var distance_to_slot: float = global_position.distance_to(slot_target)
	var base_speed: float = _leader_node.patrol_speed
	
	# Ramp speed smoothly based on distance from slot.
	# In position: 1× speed. Far behind: up to 2.5× speed.
	# Uses lerp for smooth acceleration/deceleration rather than sudden jumps.
	var distance_ratio: float = distance_to_slot / 15.0
	var target_speed_multiplier: float = clamp(distance_ratio, 1.0, 1.5)
	# Smooth the multiplier over time to avoid sudden speed changes
	var current_multiplier: float = move_speed / max(base_speed, 1.0)
	var smooth_multiplier: float = lerp(current_multiplier, target_speed_multiplier, 0.1)
	move_speed = base_speed * smooth_multiplier
	
	if distance_to_slot > 5.0:
		set_move_target(slot_target)
	else:
		# In position — stop and face same direction as leader
		has_target = false
		velocity = Vector2.ZERO
		facing_direction = _leader_node.facing_direction


## Adjusts flee direction to avoid obstacles (buildings)
## Uses raycasting to detect obstacles and steers around them
## Picks angle closest to desired direction (maintains flee vector)
## @param desired_direction: The direction the human wants to flee
## @return: Adjusted direction that avoids obstacles
func avoid_obstacles(desired_direction: Vector2) -> Vector2:
	# Check if path is clear in desired direction
	var check_distance: float = 80.0  # Look ahead distance
	var target_point := position + desired_direction * check_distance
	
	var query := PhysicsRayQueryParameters2D.create(position, target_point)
	query.collision_mask = 1  # Only hit buildings
	query.exclude = [self]
	
	var result := space_state.intersect_ray(query)
	
	# If path is clear, use desired direction
	if result.is_empty():
		return desired_direction
	
	# Path is blocked - find angle closest to desired direction
	# Test smaller angles first (max ±45°, not ±90°)
	var test_angles := [-15.0, 15.0, -30.0, 30.0, -45.0, 45.0]
	var best_direction := desired_direction
	var best_alignment := -1.0  # Dot product score (-1 to 1)
	var best_clearance := 0.0
	
	for angle in test_angles:
		var test_direction := desired_direction.rotated(deg_to_rad(angle))
		var test_point := position + test_direction * check_distance
		
		var test_query := PhysicsRayQueryParameters2D.create(position, test_point)
		test_query.collision_mask = 1
		test_query.exclude = [self]
		
		var test_result := space_state.intersect_ray(test_query)
		
		if test_result.is_empty():
			# Path is clear - check alignment with desired direction
			# Dot product: 1.0 = same direction, -1.0 = opposite
			var alignment := desired_direction.dot(test_direction)
			
			if alignment > best_alignment:
				best_alignment = alignment
				best_direction = test_direction
		else:
			# Partially blocked - track clearance as fallback
			var clearance := position.distance_to(test_result.position)
			if clearance > best_clearance:
				best_clearance = clearance
				best_direction = test_direction
	
	# Return direction with best alignment (or most clearance if all blocked)
	return best_direction


## Checks if any zombie has locked onto this human as their target
## Used to keep fleeing even when zombie is out of sight (behind wall, etc.)
## @return: true if being actively pursued by a zombie
func is_being_pursued() -> bool:
	var zombies := get_tree().get_nodes_in_group("zombies")
	for zombie in zombies:
		if zombie is Zombie:
			var zombie_unit := zombie as Zombie
			# Check if this zombie is locked onto THIS human
			if zombie_unit.attack_target == self:
				if enable_debug_logging:
					print("  ⚠️ BEING PURSUED by zombie at ", zombie_unit.position)
				return true
	return false


## Calculates optimal flee direction based on all nearby zombie threats
## and pull toward escape zone if nearby
## Uses weighted threat vectors - closer zombies have more influence
## Escape zone adds attraction force scaled by distance (20% at 200px, 80% at 50px)
## @return: Normalized direction vector for fleeing
func calculate_flee_direction() -> Vector2:
	if enable_debug_logging:
		print("\n=== CALCULATE_FLEE_DIRECTION ===")
		print("Human at position: ", position)
		print("Current state: ", State.keys()[current_state])
	
	var zombies := get_tree().get_nodes_in_group("zombies")
	if enable_debug_logging:
		print("Total zombies in scene: ", zombies.size())
	
	var total_threat := Vector2.ZERO
	var visible_zombie_count := 0
	
	# Calculate threat from zombies
	for zombie in zombies:
		if not zombie is Unit:
			if enable_debug_logging:
				print("  Skipping non-Unit zombie")
			continue
		
		var distance := position.distance_to(zombie.position)
		if enable_debug_logging:
			print("  Zombie at ", zombie.position, " - distance: ", distance)
		
		# Use wider vision range when calculating flee (hyper-aware panic state)
		# 200px range - momentum system handles continued fleeing after losing sight
		var max_range: float = 200.0
		if distance > max_range:
			if enable_debug_logging:
				print("    SKIP: Too far (> 200px)")
			continue
		
		# Check if zombie is visible (in vision cone/circle + line of sight)
		if not can_see_unit(zombie):
			if enable_debug_logging:
				print("    SKIP: Not visible (LOS blocked or out of arc)")
			continue
		
		visible_zombie_count += 1
		
		# Calculate direction away from this zombie
		var away_direction: Vector2 = (position - zombie.position).normalized()
		if enable_debug_logging:
			print("    ✓ VISIBLE ZOMBIE #", visible_zombie_count)
			print("      Away direction: ", away_direction)
		
		# Weight by inverse distance (closer = stronger influence)
		var weight := 1.0 - (distance / max_range)
		if enable_debug_logging:
			print("      Weight: ", weight)
			print("      Contribution: ", away_direction * weight)
		
		# Add weighted threat
		total_threat += away_direction * weight
	
	if enable_debug_logging:
		print("Total visible zombies: ", visible_zombie_count)
		print("Total threat vector (before normalization): ", total_threat)
		print("Total threat length: ", total_threat.length())
	
	# NOTE: Human separation forces disabled - not needed with current physics
	# Godot's CharacterBody2D collision handles human-human avoidance naturally
	
	# SMART ESCAPE ZONE BLENDING
	# When zone is nearby, blend zone direction with threat avoidance
	# Closer to zone = stronger pull toward it, weaker threat response
	# This allows humans to escape even during active chases!
	var escape_zone := get_nearest_escape_zone()
	if escape_zone:
		# Use global_position for nested zones
		var distance_to_zone := global_position.distance_to(escape_zone.global_position)
		
		# Active blending within 200px
		if distance_to_zone < 200.0:
			var to_zone: Vector2 = (escape_zone.global_position - global_position).normalized()
			
			# Calculate zone weight based on distance
			# 50px away = 90% zone pull, 10% threat avoidance
			# 100px away = 75% zone pull, 25% threat avoidance
			# 150px away = 60% zone pull, 40% threat avoidance
			# 200px away = 40% zone pull, 60% threat avoidance
			var zone_weight := 0.4 + (0.5 * (1.0 - (distance_to_zone / 200.0)))
			var threat_weight := 1.0 - zone_weight
			
			# If there are visible threats, blend with zone direction
			if total_threat.length() > 0.01:
				var threat_normalized := total_threat.normalized()
				var blended := (to_zone * zone_weight) + (threat_normalized * threat_weight)
				
				# Return blended direction (escape toward zone while dodging zombies)
				return blended.normalized()
			else:
				# No threats, just head straight to zone
				return to_zone
	
	# If no nearby zone, use pure threat avoidance or fallback priorities
	if total_threat.length() > 0.01:
		# Visible threats detected - flee directly away
		if enable_debug_logging:
			print("Visible threats detected!")
			print("FINAL FLEE DIRECTION: ", total_threat.normalized())
		last_threat_time = Time.get_ticks_msec() / 1000.0
		return total_threat.normalized()
	else:
		# No visible threats - use intelligent fallback priority system
		if enable_debug_logging:
			print("No visible threats - checking fallback priorities...")
		
		# PRIORITY 0.5: Being actively targeted (attacker_count > 0)?
		# This catches cases where zombies are pursuing but temporarily out of vision
		if attacker_count > 0:
			if enable_debug_logging:
				print("  Priority 0.5: BEING TARGETED (", attacker_count, " attackers)")
				print("  Continuing in last direction: ", last_flee_direction)
				print("=================================\n")
			# Continue fleeing in last known direction
			if last_flee_direction.length() > 0.1:
				return last_flee_direction
			else:
				# No last direction, flee away from center
				return (position - Vector2.ZERO).normalized()
		
		# PRIORITY 1: Being actively pursued by a zombie?
		if is_being_pursued():
			if enable_debug_logging:
				print("  Priority 1: BEING PURSUED - keep fleeing!")
				print("  Using last flee direction: ", last_flee_direction)
				print("=================================\n")
			return last_flee_direction
		
		# PRIORITY 2: Escape zone nearby? (fallback when NO visible threats)
		# Main zone seeking happens in blending system above
		# This is just for humans who are safe but still fleeing
		if current_state == State.FLEEING:
			var escape_zone_fallback := get_nearest_escape_zone()
			if escape_zone_fallback:
				var distance_to_zone := global_position.distance_to(escape_zone_fallback.global_position)
				if distance_to_zone < 200.0:
					var to_zone: Vector2 = (escape_zone_fallback.global_position - global_position).normalized()
					if enable_debug_logging:
						print("  Priority 2: ESCAPE ZONE FALLBACK (no threats)")
						print("  Distance to zone: ", distance_to_zone)
						print("  Heading straight to zone")
					return to_zone
		
		# PRIORITY 3: Momentum (continue fleeing if recent threat)
		if last_flee_direction.length() > 0.1:
			var time_elapsed := (Time.get_ticks_msec() / 1000.0) - last_threat_time
			if time_elapsed < 5.0:  # 5 second timeout
				if enable_debug_logging:
					print("  Priority 3: MOMENTUM (", time_elapsed, "s since last threat)")
					print("  Continuing in last direction: ", last_flee_direction)
					print("=================================\n")
				return last_flee_direction
			else:
				if enable_debug_logging:
					print("  TIMEOUT REACHED (", time_elapsed, "s since last threat)")
		
		# PRIORITY 4: Truly safe - stop fleeing
		if enable_debug_logging:
			print("  Priority 4: TRULY SAFE - stopping")
			print("=================================\n")
		return Vector2.ZERO


## Initiates flee behavior - human abandons everything and runs from zombie
## Calculates a flee direction away from the threatening zombie
## @param threat: The zombie that triggered the flee response
func start_fleeing(threat: Unit) -> void:
	# State is already set to FLEEING by caller
	
	# Restore full flee speed — patrol_speed may have lowered move_speed
	if _base_move_speed > 0.0:
		move_speed = _base_move_speed
	is_patrolling = false
	
	# DEBUG: Enable logging for first human that flees
	if Human.debug_logged_human == null:
		Human.debug_logged_human = self
		enable_debug_logging = true
		print("\n🎯 DEBUG LOGGING ENABLED FOR THIS HUMAN (first to flee)")
		print("Position: ", position)
		print("============================================\n")
	
	# IMMEDIATELY stop current movement to prevent moving toward zombie
	velocity = Vector2.ZERO
	has_target = false
	
	# Stop any current attack (though humans can't attack anyway)
	attack_target = null
	
	# Calculate flee direction and target
	update_flee_direction(threat)


## Starts fleeing with an inherited direction from nearby panicking humans
## Used for cascading panic propagation - creates natural spreading patterns
## @param threat: The zombie that triggered the group panic
## @param inherited_direction: Direction from the human who first detected threat
func start_fleeing_with_direction(threat: Unit, inherited_direction: Vector2) -> void:
	# Set state
	current_state = State.FLEEING
	# Restore full flee speed — patrol_speed may have lowered move_speed
	if _base_move_speed > 0.0:
		move_speed = _base_move_speed
	is_patrolling = false
	velocity = Vector2.ZERO
	has_target = false
	attack_target = null
	
	# Calculate own threat assessment
	var my_threats := calculate_flee_direction()
	
	# Blend: 70% inherited direction, 30% own calculation
	# This creates wave effect while still being responsive
	var blended_direction: Vector2 = (inherited_direction * 0.7 + my_threats * 0.3).normalized()
	
	# Apply obstacle avoidance
	blended_direction = avoid_obstacles(blended_direction)
	
	# Calculate proposed flee target
	var flee_target := position + blended_direction * flee_distance
	
	# DISABLED FOR TESTING: DANGER ZONE CHECK
	# var zombies := get_tree().get_nodes_in_group("zombies")
	# for zombie in zombies:
	#     if not zombie is Zombie:
	#         continue
	#     var zombie_unit := zombie as Zombie
	#     var distance_to_target: float = flee_target.distance_to(zombie_unit.position)
	#     if distance_to_target < 60.0:
	#         blended_direction = blended_direction.rotated(PI / 2.0)
	#         flee_target = position + blended_direction * flee_distance
	#         break
	
	# Store direction and set target
	last_flee_direction = blended_direction.normalized()
	set_move_target(flee_target)


## Updates the flee target position based on current threat
## Recalculates threat vector from all nearby zombies and avoids obstacles
## @param _threat: The zombie to flee from (deprecated - now uses all zombies)
func update_flee_direction(_threat: Unit) -> void:
	if enable_debug_logging:
		print("\n>>> UPDATE_FLEE_DIRECTION called <<<")
		print("Current position: ", position)
	
	# Recalculate flee direction from ALL nearby zombies
	var flee_direction := calculate_flee_direction()
	
	if enable_debug_logging:
		print("Flee direction from calculate: ", flee_direction)
		print("flee_distance: ", flee_distance)
	
	# Apply smart obstacle avoidance (picks angle closest to desired flee direction)
	flee_direction = avoid_obstacles(flee_direction)
	
	# Calculate proposed flee target
	var flee_target := position + flee_direction * flee_distance
	if enable_debug_logging:
		print("Calculated flee_target: ", flee_target)
		print("Vector from position to flee_target: ", flee_target - position)
	
	# NOTE: Danger zone check disabled - weighted threat system handles multiple zombies
	# If humans flee into ambushes, consider re-enabling with gentler rotation
	
	# Store this direction for cooldown period
	if flee_direction.length() > 0.1:
		last_flee_direction = flee_direction.normalized()
	
	# Command ourselves to move to that flee point
	set_move_target(flee_target)
	print("Called set_move_target with: ", flee_target)
	print(">>> END UPDATE_FLEE_DIRECTION <<<\n")


## Starts fleeing in a specific direction (for panic spreading)
## Used when nearby humans are attacked but zombie isn't visible
## @param direction: The direction to flee in (should be normalized)
func start_fleeing_in_direction(direction: Vector2) -> void:
	# Restore full flee speed — patrol_speed may have lowered move_speed
	if _base_move_speed > 0.0:
		move_speed = _base_move_speed
	is_patrolling = false
	# Stop current movement
	velocity = Vector2.ZERO
	has_target = false
	attack_target = null
	
	# Apply obstacle avoidance
	var safe_direction := avoid_obstacles(direction)
	
	# Calculate flee target
	var flee_target := position + safe_direction * flee_distance
	
	# Store direction and set target
	last_flee_direction = safe_direction.normalized()
	last_threat_time = Time.get_ticks_msec() / 1000.0
	set_move_target(flee_target)


## Called when this human's health reaches 0
## Enters dead state and starts incubation timer
## Override of Unit.die()
func die() -> void:
	# Guard: Don't run if already dead (prevents infinite loop)
	if current_state == State.DEAD:
		return
	
	# Let GameManager know this human died
	# (GameManager uses this to check win conditions and track remaining humans)
	human_died.emit(self)
	
	# Notify nearby humans of this death — triggers killed_drain on their morale bars
	var all_humans := get_tree().get_nodes_in_group("humans")
	for other in all_humans:
		if other is Human and other != self and is_instance_valid(other):
			if position.distance_to(other.position) <= 150.0:
				other.receive_ally_killed_shock(position)
	
	# Enter dead state (don't remove immediately)
	current_state = State.DEAD
	is_dead = true  # Keep for compatibility with other systems
	incubation_timer = incubation_duration
	
	# Clear attacker tracking - no longer being chased
	attacker_count = 0
	update_targeting_visual()  # Remove red border
	
	# Clear all movement and targets
	velocity = Vector2.ZERO
	has_target = false
	attack_target = null
	
	# Change color to red (dead corpse)
	modulate = Color(0.8, 0.2, 0.2, 1.0)
	
	# Disable collision - corpses don't block line of sight or movement
	collision_layer = 0  # Remove from all collision layers
	collision_mask = 0   # Don't collide with anything
	
	print("Human died - incubating for ", incubation_duration, " seconds")


## Spawns a zombie at this human's position after incubation complete
## Called when incubation timer reaches 0
func spawn_zombie_conversion() -> void:
	# Let GameManager know to spawn zombie
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("on_human_converted"):
		game_manager.on_human_converted(self)
		print("Human converted to zombie after incubation!")


## Checks if any zombie is in melee range (30 pixels)
## Used to determine if human should stay grappled
## @return: true if at least one zombie is very close AND targeting this human
## Checks if any zombie is close enough to keep this human grappled
## @return: true if any zombie within grapple range (50px) AND attacking this human
func is_being_attacked() -> bool:
	var zombies := get_tree().get_nodes_in_group("zombies")
	
	for zombie in zombies:
		if zombie is Zombie:
			var distance := position.distance_to(zombie.position)
			
			# FIXED: Only grapple if zombie is actually in combat (leaping or melee)
			# Not just walking nearby!
			if distance <= 50.0 and zombie.attack_target == self:
				# Check if zombie is actively engaging (not just walking nearby)
				var is_combat_engaged = zombie.has_leap_grappled or zombie.is_melee_attacker
				
				if not is_combat_engaged:
					# Zombie is just walking toward target, not in combat yet
					continue
				
				# If not yet grappled, initiate grapple (state transition happens in _physics_process)
				# Don't grapple if already dead!
				if not is_grappled and current_state != State.DEAD:
					is_grappled = true
					current_state = State.GRAPPLED
					grapple_timer = grapple_duration
				return true  # Return true whether newly grappled or already grappled
	
	return false


## Humans don't attack - they're defenseless
## This override prevents any combat behavior
## Override of Unit.perform_attack()
func perform_attack() -> void:
	# Humans cannot attack - do nothing
	# This function exists only to override the base Unit behavior
	pass


## Takes damage and enters grappled state
## Override of Unit.take_damage()
## @param amount: How much damage to take
func take_damage(amount: float) -> void:
	# Call parent to handle health reduction
	super.take_damage(amount)
	
	# Don't change state if already dead (die() was called by super)
	if current_state == State.DEAD:
		print("DEBUG: take_damage called on dead human - NOT setting grappled state")
		return
	
	# Getting hit means we're grappled by a zombie!
	if not is_grappled:
		print("Human at ", position, " grappled by zombie!")
	is_grappled = true
	current_state = State.GRAPPLED
	grapple_timer = grapple_duration


## Humans don't pursue attack targets since they can't attack
## This override prevents combat targeting
## Override of Unit.set_attack_target()
func set_attack_target(_target: Unit) -> void:
	# Humans cannot attack - ignore attack commands
	# They can only flee
	pass


## Checks if this human can accept more attackers
## Returns false if already has 3 zombies attacking
## @return: true if can accept more attackers, false if at max (3)
func can_accept_attacker() -> bool:
	return attacker_count < 3


## Increments the attacker count when a zombie targets this human
## Called by zombie when setting this human as attack target
func add_attacker() -> void:
	attacker_count += 1
	update_targeting_visual()  # Show red border when targeted
	# Debug logging
	if attacker_count > 3:
		push_warning("Human has more than 3 attackers! Count: ", attacker_count)


## Decrements the attacker count when a zombie stops targeting this human
## Called when zombie dies, switches targets, or goes idle
func remove_attacker() -> void:
	attacker_count = max(0, attacker_count - 1)  # Prevent negative
	update_targeting_visual()  # Hide border when no longer targeted


## Updates visual indicator showing this human is being targeted
## Shows dark red border when zombies are pursuing
func update_targeting_visual() -> void:
	if not selection_indicator or not selection_circle:
		return
	
	if attacker_count > 0:
		# Show dark red targeting indicator
		selection_indicator.visible = true
		selection_circle.default_color = Color(0.6, 0.0, 0.0, 1.0)  # Dark red
		selection_circle.width = 2.0
	else:
		# Hide indicator when not targeted
		selection_indicator.visible = false


## === GROUP STATE PROPAGATION — DEPRECATED (v0.22.2) ===
##
## propagate_flee_to_group() is replaced by the morale system.
## Every unit now drains morale independently based on proximity to events.
## Explicit propagation chains are no longer needed — runaway cascades are
## naturally limited by per-class morale_max values rather than a depth cap.
##
## Kept for reference. This function is no longer called anywhere.
## Will be removed in a future cleanup pass.
##
## func propagate_flee_to_group(threat: Unit, depth: int = 0) -> void:
## 	if depth >= panic_propagation_depth:
## 		print("🛑 PANIC CHAIN stopped at depth ", depth, " for ", name)
## 		return
## 	var propagation_radius: float = 80.0
## 	var min_group_size: int = 4
## 	var nearby_allies: Array[Human] = []
## 	var humans := get_tree().get_nodes_in_group("humans")
## 	for other in humans:
## 		if other == self or not other is Human:
## 			continue
## 		var human := other as Human
## 		if human.current_state != State.IDLE and human.current_state != State.SENTRY:
## 			continue
## 		var distance: float = position.distance_to(human.position)
## 		if distance <= propagation_radius:
## 			nearby_allies.append(human)
## 	if nearby_allies.size() < min_group_size - 1:
## 		return
## 	print("PANIC MOB (depth ", depth, "): ", nearby_allies.size() + 1, " humans fleeing together!")
## 	for ally in nearby_allies:
## 		var max_delay: float = 0.4
## 		var distance: float = position.distance_to(ally.position)
## 		var delay: float = (distance / propagation_radius) * max_delay
## 		if delay > 0.01:
## 			get_tree().create_timer(delay).timeout.connect(
## 				func():
## 					if is_instance_valid(ally) and ally.current_state != State.FLEEING:
## 						ally.current_state = State.FLEEING
## 						ally.start_fleeing(threat)
## 						ally.propagate_flee_to_group(threat, depth + 1)
## 			)
## 		else:
## 			if ally.current_state != State.FLEEING:
## 				ally.current_state = State.FLEEING
## 				ally.start_fleeing(threat)
## 				ally.propagate_flee_to_group(threat, depth + 1)
