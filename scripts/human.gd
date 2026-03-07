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
	IDLE,        ## Standing around, circular vision (360°)
	SENTRY,      ## Watching a direction, arc vision (90°)
	FLEEING,     ## Running from zombies, forward arc vision (90°)
	GRAPPLED,    ## Being attacked, no vision
	DEAD         ## Incubating corpse, no vision
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

## Signal emitted when this human dies
## GameManager listens to this for win condition checking
## @param human: This human that died
signal human_died(human: Human)

# === EXPORTED PROPERTIES (Configurable in Godot Editor) ===

## Initial state when human spawns (can be set in editor for level design)
@export var initial_state: State = State.IDLE

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
@export var sentry_vision_range: float = 180.0
@export var sentry_vision_angle: float = 90.0  # Degrees

## Fleeing state: forward arc vision range and angle
@export var flee_vision_range: float = 100.0
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

## How many hops panic can propagate from the original zombie sighting.
## 0 = only the direct detector flees. 1 = detector + immediate neighbours.
## 2 = detector + 2 rings outward (recommended). 99 = unlimited (old behaviour).
@export_range(0, 10, 1) var panic_propagation_depth: int = 2

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

## Whether this human is currently grappled (synced with State.GRAPPLED for compatibility)
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

## Reference to the physics space for raycasting (line-of-sight checks)
## Cached for performance
var space_state: PhysicsDirectSpaceState2D


## Called when the node enters the scene tree
## Ensures this unit is always on the human team
func _ready() -> void:
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
	
	# Update sentry swing arc (if applicable)
	# Only swing when stationary (not actively patrolling), and only for leaders/standalone
	# Followers face their leader's direction instead
	if current_state == State.SENTRY and sentry_has_swing and not is_patrolling and patrol_leader.is_empty():
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


## Checks for zombies within vision that have line of sight
## If any are found, initiates flee behavior
func check_for_nearby_zombies() -> void:
	# Skip if dead or grappled (no detection)
	if current_state == State.DEAD or current_state == State.GRAPPLED:
		return
	
	# PANIC SPREADING: Check if nearby humans are being attacked
	# This allows sentries to react even when facing away from zombies
	var panic_radius: float = 40.0  # Close range - only immediate neighbors panic
	var all_humans := get_tree().get_nodes_in_group("humans")
	
	for other in all_humans:
		if other == self or not other is Human:
			continue
		
		var ally := other as Human
		var distance_to_ally := position.distance_to(ally.position)
		
		# Check if nearby ally is in distress
		if distance_to_ally <= panic_radius:
			# Only panic when ally is actually GRAPPLED (pinned/in melee)
			# Not just being chased - has to be in serious danger
			if ally.current_state == State.GRAPPLED:
				# PANIC! Friend is being attacked!
				if current_state != State.FLEEING:
					print("Human at ", position, " panicking - ally grappled nearby!")
					current_state = State.FLEEING
					
					# Flee away from the ally's position (zombies are there)
					var flee_away := (position - ally.position).normalized()
					start_fleeing_in_direction(flee_away)
					return  # Start fleeing immediately
	
	# GROUP VISION SYSTEM:
	# When humans are grouped (within 50px), they share a collective vision radius
	# Only the human CLOSEST to a detected zombie reacts first (maintains cascade effect)
	
	# Find nearby humans to form a group (reuse all_humans from above)
	var group_radius: float = 50.0
	var nearby_humans := []
	for other in all_humans:  # Reuse all_humans variable from panic spreading check
		if other == self or not other is Human:
			continue
		if position.distance_to(other.position) <= group_radius:
			nearby_humans.append(other)
	
	# Determine vision range: individual or group
	var effective_vision_range: float = idle_vision_radius  # 100px
	
	# Check for zombies within vision range (individual or group shared)
	var zombies_in_vision := []
	var zombies := get_tree().get_nodes_in_group("zombies")
	
	for zombie in zombies:
		if not zombie is Unit:
			continue
		
		var zombie_unit := zombie as Unit
		var distance_to_me := position.distance_to(zombie_unit.position)
		
		# If zombie is within effective vision range of this human or any group member
		# NOTE: Don't subtract UNIT_RADIUS here - can_see_unit() handles it internally!
		var in_group_vision := false
		
		# Check my own vision (can_see_unit does range + LOS + radius adjustment)
		if can_see_unit(zombie_unit):
			in_group_vision = true
		
		# Check group members' vision (if I'm in a group)
		if not in_group_vision and nearby_humans.size() > 0:
			for ally in nearby_humans:
				var ally_human := ally as Human
				# Check if ally can see it (can_see_unit handles range + LOS + radius)
				if ally_human.can_see_unit(zombie_unit):
					in_group_vision = true
					break
		
		if in_group_vision:
			zombies_in_vision.append({"zombie": zombie_unit, "distance": distance_to_me})
	
	# If zombies detected in group vision, determine which human should react
	if zombies_in_vision.size() > 0:
		# Find closest zombie to THIS human
		zombies_in_vision.sort_custom(func(a, b): return a.distance < b.distance)
		var nearest_zombie: Unit = zombies_in_vision[0].zombie
		
		# In a group, only the human CLOSEST to the zombie reacts first
		if nearby_humans.size() > 0:
			# Find which human in the group is closest to the zombie
			var closest_human: Human = self
			var closest_distance := position.distance_to(nearest_zombie.position)
			
			for ally in nearby_humans:
				var ally_human := ally as Human
				var ally_distance: float = ally_human.position.distance_to(nearest_zombie.position)
				if ally_distance < closest_distance:
					closest_distance = ally_distance
					closest_human = ally_human
			
			# Only react if I'm the closest (maintains cascade effect)
			if closest_human != self:
				return  # Let the closer human react first
		
		# This human is the designated detector - react!
		if current_state != State.FLEEING:
			# Not fleeing yet - start fleeing immediately
			print("Human at ", position, " detected zombie - fleeing!")
			current_state = State.FLEEING
			
			# Stop patrolling if we were
			is_patrolling = false
			
			start_fleeing(nearest_zombie)
			
			# GROUP STATE PROPAGATION: Tell nearby allies to flee too
			propagate_flee_to_group(nearest_zombie)
		else:
			# Already fleeing, update flee direction based on new threat
			update_flee_direction(nearest_zombie)
	else:
		# No zombies visible - use intelligent priority system
		if current_state == State.FLEEING:
			# Call our smart flee system which handles:
			# - Being pursued detection
			# - Escape zone seeking
			# - 5-second momentum timeout
			# - Stopping when truly safe
			var flee_dir := calculate_flee_direction()
			
			if flee_dir == Vector2.ZERO:
				# Priority system determined we're truly safe - stop fleeing
				print("Human at ", position, " stopped fleeing - truly safe (timeout/no threats)")
				last_flee_direction = Vector2.ZERO
				if initial_state == State.SENTRY:
					current_state = State.SENTRY
				else:
					current_state = State.IDLE
			else:
				# Priority system says keep fleeing (momentum/pursuit/escape zone)
				var flee_target := position + flee_dir * flee_distance
				set_move_target(flee_target)


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
		
		# Check if this zombie is in our vision (cone or circle)
		if can_see_unit(zombie):
			var distance := position.distance_to(zombie.position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_visible = zombie
	
	return nearest_visible


## Checks if there's a clear line of sight between this human and a target
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


## === GROUP STATE PROPAGATION ===

## Propagates flee state to nearby allies when this human spots a zombie.
## Uses distance-based reaction delays (closer allies react sooner).
## Depth parameter limits how many hops the panic can spread from the original sighting.
## @param threat: The zombie that triggered the flee
## @param depth: How many hops this propagation is from the original sighting (0 = direct detector)
func propagate_flee_to_group(threat: Unit, depth: int = 0) -> void:
	# Stop propagating if we've reached the depth cap
	if depth >= panic_propagation_depth:
		print("🛑 PANIC CHAIN stopped at depth ", depth, " for ", name)
		return
	
	var propagation_radius: float = 80.0
	var min_group_size: int = 4
	
	var nearby_allies: Array[Human] = []
	var humans := get_tree().get_nodes_in_group("humans")
	
	for other in humans:
		if other == self or not other is Human:
			continue
		
		var human := other as Human
		
		# Only propagate to idle/sentry humans (not already fleeing/grappled)
		if human.current_state != State.IDLE and human.current_state != State.SENTRY:
			continue
		
		var distance: float = position.distance_to(human.position)
		if distance <= propagation_radius:
			nearby_allies.append(human)
	
	# Only propagate if we have enough allies to form a panic mob
	if nearby_allies.size() < min_group_size - 1:
		return
	
	print("PANIC MOB (depth ", depth, "): ", nearby_allies.size() + 1, " humans fleeing together!")
	
	for ally in nearby_allies:
		# Distance-based delay: 0px away = 0.0s, 80px away = max_delay
		# Closer allies react sooner — tight formations react near-simultaneously
		var max_delay: float = 0.4
		var distance: float = position.distance_to(ally.position)
		var delay: float = (distance / propagation_radius) * max_delay
		
		if delay > 0.01:
			get_tree().create_timer(delay).timeout.connect(
				func():
					if is_instance_valid(ally) and ally.current_state != State.FLEEING:
						ally.current_state = State.FLEEING
						ally.start_fleeing(threat)
						# Propagate onwards at depth + 1
						ally.propagate_flee_to_group(threat, depth + 1)
			)
		else:
			# Close enough to react immediately
			if ally.current_state != State.FLEEING:
				ally.current_state = State.FLEEING
				ally.start_fleeing(threat)
				ally.propagate_flee_to_group(threat, depth + 1)
