extends Unit
class_name Zombie

## Zombie unit - player-controlled undead unit
## 
## Zombies are the units controlled by the player. Their key features are:
## - Converting humans into new zombies when they kill them
## - Leap attack when close to humans for catching fleeing targets
## - Vision-based detection (cone or circle depending on state)
##
## Key features:
## - Inherits all movement and combat from Unit base class
## - Emits a signal when killing a human (GameManager listens for this)
## - Special attack behavior that triggers conversion
## - Leap attack for short-range speed boost
## - Belongs to the ZOMBIES team
##
## The conversion mechanic is the core of the game - as you kill humans,
## your army grows organically, creating a satisfying snowball effect.
##
## The leap attack helps zombies catch fleeing humans by giving a speed
## boost when they get close, simulating a lunge/grab motion.

## Zombie behavioral states - determines vision shape and behavior
enum State {
	IDLE,        ## Standing around, circular vision (360°)
	MOVING,      ## Player commanded, forward arc vision (150°)
	PURSUING,    ## Auto-locked on human, forward arc vision (150°)
	LEAPING,     ## Speed boost active, forward arc vision (150°)
	MELEE,       ## Attacking in melee range, no vision
	DEAD         ## Dead zombie (shouldn't happen often!)
}

## Signal emitted when this zombie kills a human unit
## The GameManager listens to this signal to spawn a new zombie at the human's location
## @param human: The Human unit that was killed
## @param zombie: This zombie that did the killing
signal zombie_killed_human(human: Unit, zombie: Zombie)

# === NAVIGATION ===

## Optional NavigationAgent2D for pathfinding around obstacles
## If present, zombie will use navigation mesh for pathfinding
## If not present, zombie uses direct movement (current behavior)
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null

# === VISION PARAMETERS ===

## Idle state: circular vision radius
## Also used for auto-pursuit detection when idle
@export var idle_vision_radius: float = 100.0

## Moving/Pursuing/Leaping state: forward arc vision range and angle
@export var active_vision_range: float = 200.0  # Reduced from 260 for better balance
@export var active_vision_angle: float = 70.0  # Degrees - narrowed for better stealth gameplay

# === LEAP ATTACK SETTINGS ===

## Distance at which zombie will start leap attack (in pixels)
## When a human is within this range, zombie gets speed boost
## Reduced to 40px to prevent zombies blocking each other during leaps
@export var leap_range: float = 40.0

## Speed multiplier during leap attack
## 2x normal speed for lunge to catch fleeing humans
@export var leap_speed_multiplier: float = 2.0


# === RUNTIME STATE ===

## Current behavioral state
var current_state: State = State.IDLE

## Direction this zombie is facing (for vision arc calculation)
var facing_direction: Vector2 = Vector2.RIGHT

## Whether this zombie is currently performing a leap attack
var is_leaping: bool = false

## The original move speed (cached when leap starts)
var normal_speed: float = 0.0

## Whether this zombie is currently counted as a melee attacker on its target
## Only true when in attack range and actively hitting the target
var is_melee_attacker: bool = false

## Whether we've already triggered the leap grapple for current target
## Prevents repeated grappling, resets when leap ends or target changes
var has_leap_grappled: bool = false

## The specific human that was grappled during this leap (prevents pinning multiple humans)
var leap_grappled_target: Human = null

## Whether the current target was assigned by player command (vs auto-pursuit)
## Player-commanded targets shouldn't switch even if closer targets appear
var is_player_commanded: bool = false

## Whether this zombie is locked in pursuit and cannot be commanded
## Once a zombie auto-pursues, player loses control until target dies
var is_locked_in_pursuit: bool = false

## Whether this zombie has engaged in melee combat with current target
## Once engaged in melee, zombie is committed and won't switch targets
var is_committed_to_target: bool = false

## Time when zombie entered MELEE state (for vision delay)
var melee_enter_time: float = 0.0

## Duration to keep vision visible after entering MELEE (seconds)
const MELEE_VISION_DELAY: float = 0.5

# Reference to selection circle for color changes
@onready var selection_circle: Line2D = $SelectionIndicator/SelectionCircle

# === STUCK DETECTION ===

## How long zombie must be stuck before finding new target (seconds)
var stuck_timeout: float = 2.0

## Timer tracking how long zombie has been stuck
var stuck_timer: float = 0.0

## Last position (used to detect if zombie is moving)
var last_position: Vector2 = Vector2.ZERO

## Minimum distance zombie must move to not be considered stuck
var stuck_threshold: float = 5.0


## Called when the node enters the scene tree
## Ensures this unit is always on the zombie team and caches normal speed
func _ready() -> void:
	# Force this unit to be on the zombie team
	team = Team.ZOMBIES
	
	# Cache the normal movement speed for leap mechanics
	normal_speed = move_speed
	
	# Initialize position tracking for stuck detection
	last_position = position
	
	# Call the parent class's _ready() to initialize all base unit functionality
	super._ready()
	
	# DEBUG: Check navigation setup
	print("\n=== ZOMBIE NAVIGATION DEBUG ===")
	print("Zombie: ", name)
	if nav_agent:
		print("✓ HAS NavigationAgent2D")
		print("  Enabled: ", nav_agent.is_inside_tree())
		print("  Navigation Layers: ", nav_agent.navigation_layers)
		print("  Path Desired Distance: ", nav_agent.path_desired_distance)
		print("  Target Desired Distance: ", nav_agent.target_desired_distance)
	else:
		print("✗ NO NavigationAgent2D - will use direct movement")
	print("===============================\n")


## Override selection visual to show red when locked in pursuit
## This provides visual feedback that the zombie cannot be commanded
## IMPORTANT: Shows indicator even when NOT selected if zombie is locked
func update_selection_visual() -> void:
	if selection_indicator:
		# Show indicator if EITHER selected OR locked in pursuit
		selection_indicator.visible = is_selected or is_locked_in_pursuit
	
	# Change color based on lock status
	if selection_circle:
		if is_locked_in_pursuit:
			selection_circle.default_color = Color(0.8, 0.2, 0.2, 1)  # Red
		else:
			selection_circle.default_color = Color(0.2, 0.8, 0.2, 1)  # Green


## Called every physics frame
## Handles auto-pursuit, leap attack detection, stuck detection, melee attacker management, and speed management
## @param delta: Physics timestep in seconds
func _physics_process(delta: float) -> void:
	# Update state based on current activity FIRST (before vision checks)
	update_zombie_state()
	
	# Adjust formation cohesion based on state
	# Idle zombies: gentle drift into loose groups
	# Active zombies: strong pull into tight formations
	match current_state:
		State.IDLE:
			self.cohesion_strength = 15.0  # Increased from 10 - slightly stronger pull
			self.alignment_rate = 0.5
			self.separation_radius = 30.0
			self.separation_strength = 100.0
		State.PURSUING, State.LEAPING:
			self.cohesion_strength = 0.0  # DISABLED when pursuing - no pull
			self.alignment_rate = 1.5
			self.separation_radius = 45.0   # Increased - more personal space
			self.separation_strength = 150.0  # Stronger push when too close
		State.MOVING:
			self.cohesion_strength = 0.0  # DISABLED when moving - no pull
			self.alignment_rate = 0.8
			self.separation_radius = 35.0
			self.separation_strength = 120.0
		State.MELEE, State.DEAD:
			# Disable formation forces during combat/death
			self.cohesion_strength = 0.0
			self.alignment_rate = 0.0
			self.separation_radius = 25.0  # Tighter for melee
			self.separation_strength = 80.0
	
	# Update facing direction based on movement
	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()
	elif attack_target and is_instance_valid(attack_target):
		# Face toward target if not moving
		facing_direction = (attack_target.position - position).normalized()
	
	# Clear pursuit lock and commitment if target is dead/invalid
	if attack_target:
		# Check if target is invalid OR dead (for humans in incubation)
		var target_dead := false
		if attack_target is Human and attack_target.is_dead:
			target_dead = true
		
		if not is_instance_valid(attack_target) or target_dead:
			# Target died or became invalid - clear everything
			if target_dead:
				print("Zombie's target died (incubating) - clearing target and commitment")
			clear_attack_target()
			return  # Exit early, zombie is now idle
	
	# Clear pursuit lock if no target
	if is_locked_in_pursuit and not attack_target:
		is_locked_in_pursuit = false
		is_player_commanded = false
		update_selection_visual()  # Update color to green
	
	# Auto-pursue nearby humans if we don't have a target
	# But don't override player-commanded targets
	# Works whether zombie is idle OR moving to a position
	if not attack_target or not is_instance_valid(attack_target):
		check_auto_pursuit()
	elif not is_player_commanded:
		# Only switch targets if current target wasn't player-commanded
		check_auto_pursuit()
	
	# Check if zombie is stuck (has target but not moving)
	if attack_target and is_instance_valid(attack_target):
		check_if_stuck(delta)
	else:
		# Reset stuck timer if no target
		stuck_timer = 0.0
	
	# Manage melee attacker status (only for humans)
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		manage_melee_attacker_status()
	
	# Check if we should start or stop leaping
	update_leap_state()
	
	# Update last position for next frame
	last_position = position
	
	# Call parent physics processing (movement/combat)
	super._physics_process(delta)


## Override of Unit.handle_combat() to add navigation support
## Uses NavigationAgent2D for pathfinding when available
func handle_combat(_delta: float) -> void:
	# Safety check: make sure target still exists
	if not is_instance_valid(attack_target):
		attack_target = null
		return
	
	# Calculate distance to target
	var distance := position.distance_to(attack_target.position)
	
	# If target is too far away, move closer
	if distance > attack_range:
		# Use navigation if available, otherwise direct movement
		if nav_agent and nav_agent.is_inside_tree():
			# Update navigation target
			nav_agent.target_position = attack_target.position
			
			# DEBUG
			print("\n🧭 NAVIGATION ACTIVE (COMBAT)")
			print("  Zombie pos: ", position)
			print("  Target pos: ", attack_target.position)
			print("  Distance: ", distance)
			print("  Nav finished: ", nav_agent.is_navigation_finished())
			print("  Distance to target: ", nav_agent.distance_to_target())
			
			# Get next position on navigation path
			if not nav_agent.is_navigation_finished():
				var next_position = nav_agent.get_next_path_position()
				print("  Next waypoint: ", next_position)
				print("  Direction to waypoint: ", (next_position - position).normalized())
				
				var direction = (next_position - position).normalized()
				velocity = direction * move_speed
				print("  Velocity set: ", velocity)
				move_and_slide()
			else:
				# Path finished but still out of range - move direct
				print("  ⚠️ Path finished but still out of range - using direct")
				var direction := (attack_target.position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
		else:
			# No navigation - use direct movement (original behavior)
			print("\n❌ NO NAVIGATION - using direct movement")
			var direction := (attack_target.position - position).normalized()
			velocity = direction * move_speed
			move_and_slide()
	else:
		# Target is in range - stop moving and attack
		velocity = Vector2.ZERO
		
		# Only attack if cooldown timer has finished
		if attack_timer <= 0:
			perform_attack()
			attack_timer = attack_cooldown  # Reset cooldown timer


## Override of Unit.move_to_target() to add navigation support
## Uses NavigationAgent2D for pathfinding when available
func move_to_target(_delta: float) -> void:
	# Calculate distance to target
	var distance := position.distance_to(target_position)
	
	# If we're more than 5 pixels away, keep moving
	if distance > 5.0:
		# Use navigation if available, otherwise direct movement
		if nav_agent and nav_agent.is_inside_tree():
			# Update navigation target
			nav_agent.target_position = target_position
			
			# Get next position on navigation path
			if not nav_agent.is_navigation_finished():
				var next_position = nav_agent.get_next_path_position()
				var direction = (next_position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
			else:
				# Path finished but still out of range - move direct
				var direction := (target_position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
		else:
			# No navigation - use direct movement (original behavior)
			var direction := (target_position - position).normalized()
			velocity = direction * move_speed
			move_and_slide()
	else:
		# We've arrived - stop moving
		velocity = Vector2.ZERO
		has_target = false  # Clear the movement target


## Updates zombie state based on current activity
func update_zombie_state() -> void:
	var old_state := current_state
	
	# Check if in melee combat
	if is_melee_attacker and attack_target and is_instance_valid(attack_target):
		var distance_to_target := position.distance_to(attack_target.position)
		if distance_to_target <= attack_range:
			# Entering MELEE - track time for vision delay
			if old_state != State.MELEE:
				melee_enter_time = Time.get_ticks_msec() / 1000.0
			current_state = State.MELEE
			return
	
	# Check if leaping
	if is_leaping:
		current_state = State.LEAPING
		return
	
	# Check if pursuing
	if is_locked_in_pursuit or (attack_target and not is_player_commanded):
		current_state = State.PURSUING
		return
	
	# Check if moving with purpose (has movement target or attack target)
	# Movement target = right-click move, Attack target = pursuing/attacking
	if attack_target or has_target:
		current_state = State.MOVING
		return
	
	# No target = always IDLE (circle vision), even if drifting from momentum or separation
	# This ensures zombies return to circle vision immediately when losing sight of target
	current_state = State.IDLE


## === VISION SYSTEM ===

## Checks if this zombie can see a specific unit based on current state
## Uses vision cones (arc) or circles depending on state
## Also performs raycast for line-of-sight obstacle checking
## @param target: The unit to check vision for
## @return: true if target is visible, false otherwise
func can_see_unit(target: Unit) -> bool:
	if not target or not is_instance_valid(target):
		return false
	
	# Dead and melee zombies have no vision
	if current_state == State.DEAD or current_state == State.MELEE:
		return false
	
	var distance := position.distance_to(target.position)
	var in_range := false
	
	# Check range and angle based on current state
	match current_state:
		State.IDLE:
			# Circular vision - 360° awareness
			in_range = distance <= idle_vision_radius
		
		State.MOVING, State.PURSUING, State.LEAPING:
			# Arc vision - forward facing
			in_range = distance <= active_vision_range
			if in_range:
				in_range = is_in_vision_arc(target.position, facing_direction, active_vision_angle)
	
	# If not in range/angle, can't see it
	if not in_range:
		return false
	
	# Check line of sight (buildings can block vision)
	return has_line_of_sight_to(target)


## Checks if a target position is within a vision arc
## @param target_pos: World position to check
## @param arc_direction: Direction the arc is facing (normalized)
## @param arc_angle_degrees: Total angle of arc in degrees (e.g., 150° means 75° on each side)
## @return: true if target is within the arc
func is_in_vision_arc(target_pos: Vector2, arc_direction: Vector2, arc_angle_degrees: float) -> bool:
	# Get direction to target
	var to_target := (target_pos - position).normalized()
	
	# Calculate angle between arc direction and target direction
	var angle_to_target := arc_direction.angle_to(to_target)
	
	# Check if within half-angle on either side
	var half_angle_rad := deg_to_rad(arc_angle_degrees / 2.0)
	
	return abs(angle_to_target) <= half_angle_rad


## Checks if there's a clear line of sight between this zombie and a target
## Uses raycasting to detect if buildings are blocking the view
## @param target: The Unit to check line of sight to
## @return: true if we can see the target, false if buildings block the view
func has_line_of_sight_to(target: Unit) -> bool:
	# Create a raycast query from this zombie to the target
	var query := PhysicsRayQueryParameters2D.create(position, target.position)
	
	# Only check collision with buildings (layer 1)
	# Ignore units (players and enemies) so they don't block vision
	query.collision_mask = 1
	
	# Perform the raycast
	var space_state := get_world_2d().direct_space_state
	var result := space_state.intersect_ray(query)
	
	# If raycast hit nothing, we have clear line of sight
	# If it hit something, that building is blocking our view
	return result.is_empty()


## Updates the leap attack state based on distance to target
## Activates leap when close to human, deactivates when far or no target
## HYBRID: Continuous speed boost + guaranteed pin at 40px
func update_leap_state() -> void:
	# Only leap when attacking a human
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		var distance := position.distance_to(attack_target.position)
		
		# Start leap if close enough and not already leaping
		if distance <= leap_range and not is_leaping:
			start_leap()
		
		# GUARANTEED PIN: When zombie gets within 40px during leap → force grapple
		# Only pins THIS specific target (prevents pinning multiple humans if target switches)
		if is_leaping and distance <= 40.0 and not has_leap_grappled:
			# Force grapple on the target
			attack_target.is_grappled = true
			attack_target.grapple_timer = attack_target.grapple_duration
			has_leap_grappled = true
			leap_grappled_target = attack_target  # Remember who we pinned
			is_committed_to_target = true  # COMMIT immediately - no target switching!
			print("Zombie landed leap - target PINNED!")
		
		# Stop leap if target moved out of range
		if distance > leap_range and is_leaping:
			stop_leap()
	else:
		# No valid target - stop leaping if we were
		if is_leaping:
			stop_leap()


## Activates leap attack - boosts movement speed
## Human will be pinned when zombie lands (reaches melee range)
func start_leap() -> void:
	is_leaping = true
	move_speed = normal_speed * leap_speed_multiplier
	print("Zombie leaping toward human!")
	# Pin happens when zombie lands (in melee range check)


## Deactivates leap attack - returns to normal speed
## Note: has_leap_grappled is NOT cleared here - it persists until target switch
## This prevents stuck detection from abandoning grappled targets
func stop_leap() -> void:
	is_leaping = false
	move_speed = normal_speed
	# Don't clear has_leap_grappled here - zombie should stay committed to grappled target
	# It gets cleared when switching targets in set_attack_target()
	# Could remove visual/audio feedback here in future


## Checks for nearby humans and automatically pursues them
## Only triggers when zombie has no current attack target
## Creates aggressive "mindless predator" behavior
func check_auto_pursuit() -> void:
	# CRITICAL FIX: Don't check vision or clear target if zombie is in combat
	# When grappling/in melee, target may be too close to see with vision cone
	if attack_target and is_instance_valid(attack_target):
		var in_combat = is_melee_attacker or is_committed_to_target or has_leap_grappled
		if in_combat:
			# In combat - stay locked to target, ignore vision
			return
	
	# Check if current target is still visible (only for non-combat pursuit)
	# If not, clear it so zombie returns to IDLE
	if attack_target and is_instance_valid(attack_target) and not is_player_commanded:
		if not can_see_unit(attack_target):
			# Lost sight of target - clear it
			print("🔍 ZOMBIE LOST TARGET:")
			print("  Zombie: ", name, " at ", position)
			print("  Lost: ", attack_target.name, " at ", attack_target.position)
			print("  Distance: ", position.distance_to(attack_target.position), "px")
			print("  State: ", State.keys()[current_state])
			print("  Combat: melee=", is_melee_attacker, " committed=", is_committed_to_target, " grappled=", has_leap_grappled)
			print("  Reason: Vision lost (line of sight blocked or out of arc)")
			clear_attack_target()
			is_locked_in_pursuit = false
			update_selection_visual()
			return
	
	# Determine search range based on current state (FIX #3)
	# IDLE = circle vision (100px), MOVING/PURSUING = arc vision (200px)
	var search_range: float
	if current_state == State.IDLE:
		search_range = idle_vision_radius
	else:
		search_range = active_vision_range
	
	var nearest_human := find_nearest_human_in_range(search_range)
	
	# If we already have a target, check if new target is significantly closer (FIX #5)
	# BUT ONLY if not already in ANY form of combat
	if attack_target and is_instance_valid(attack_target) and nearest_human and not is_player_commanded:
		# Don't switch if zombie is in combat OR target is grappled
		var in_combat = is_melee_attacker or is_committed_to_target or has_leap_grappled
		var target_grappled = attack_target.is_human() and attack_target.is_grappled
		
		if in_combat or target_grappled:
			# Zombie is engaged in combat or target is pinned - don't switch
			return
		
		var current_distance := position.distance_to(attack_target.position)
		var new_distance := position.distance_to(nearest_human.position)
		
		# Switch if new target is at least 50px closer (prevents constant switching)
		if new_distance < current_distance - 50.0 and nearest_human != attack_target:
			set_attack_target(nearest_human, false)
			is_locked_in_pursuit = true
			update_selection_visual()
			return
	
	if nearest_human:
		# Found a human within range - attack!
		set_attack_target(nearest_human, false)  # Not player-commanded
		is_locked_in_pursuit = true  # Lock zombie from player control
		update_selection_visual()  # Update color to red
		
		# GROUP STATE PROPAGATION: Tell nearby allies to pursue too
		propagate_pursuit_to_group(nearest_human)


## Finds the best human target within vision range
## Uses vision cones/circles to determine visibility
## Prioritizes unpinned humans over pinned ones to spread attacks
## Also respects the 3-attacker limit per human
## @param search_range: Maximum distance to search for humans (in pixels)
## @return: Best human Unit within vision, or null if none found/available
func find_nearest_human_in_range(search_range: float) -> Unit:
	var humans := get_tree().get_nodes_in_group("humans")
	
	var best_unpinned: Unit = null
	var best_unpinned_distance := search_range
	
	var best_pinned: Unit = null
	var best_pinned_distance := search_range
	
	for human in humans:
		if not human is Human:
			continue
		
		# Skip dead humans (they're incubating)
		if human.is_dead:
			continue
		
		# Skip humans with 3+ attackers (full)
		if human.attacker_count >= 3:
			continue
		
		var distance := position.distance_to(human.position)
		
		# Check if within range
		if distance >= search_range:
			continue
		
		# Check if zombie can see this human (vision cone/circle + line of sight)
		var can_see := can_see_unit(human)
		if not can_see:
			# DEBUG: Only log if we're IDLE and human is nearby
			if current_state == State.IDLE and distance < 100.0:
				print("DEBUG: IDLE zombie at ", position, " can't see human at ", human.position, 
					  " (dist: ", snappedf(distance, 0.1), "px)")
			continue
		
		# Prioritize unpinned humans
		if human.current_state != Human.State.GRAPPLED:
			if distance < best_unpinned_distance:
				best_unpinned_distance = distance
				best_unpinned = human
		else:
			# Pinned but still available
			if distance < best_pinned_distance:
				best_pinned_distance = distance
				best_pinned = human
	
	# Return unpinned first, then pinned, then null
	if best_unpinned:
		return best_unpinned
	else:
		return best_pinned


## Manages whether this zombie is counted as a melee attacker on its target
## Only zombies in attack range are counted (limits to 3 melee attackers per human)
## Zombies can chase any human, but only 3 can hit at once
func manage_melee_attacker_status() -> void:
	var distance_to_target := position.distance_to(attack_target.position)
	
	# Check if we're in melee range
	if distance_to_target <= attack_range:
		# We're in melee range - should be counted as attacker
		if not is_melee_attacker:
			# Not yet counted - try to become melee attacker
			if attack_target.attacker_count < 3:
				# Human has space - we can attack
				is_melee_attacker = true
				is_committed_to_target = true  # COMMIT to this target (no switching)
				print("Zombie entered melee with human (", attack_target.attacker_count, "/3 attackers)")
			else:
				# Human is full (3 attackers already)
				# If not yet committed, can switch. If committed, wait for opening
				if not is_committed_to_target:
					print("Human already has 3 melee attackers - finding different target")
					var new_target := find_nearest_human_in_range(active_vision_range)
					
					if new_target and new_target != attack_target:
						set_attack_target(new_target, false)
					else:
						# No other targets, stay on this one but don't add to count
						# Zombie will keep trying to find openings
						pass
				# else: Already committed, wait for opening (don't switch)
	else:
		# We're not in melee range - should not be counted
		if is_melee_attacker:
			# Currently in melee but moved out of range - no longer melee attacker
			is_melee_attacker = false
			print("Zombie left melee range (", attack_target.attacker_count, "/3 attackers)")


## Checks if zombie is stuck (not moving despite having a target)
## If stuck for too long, finds new target or goes idle
## @param delta: Physics timestep in seconds
func check_if_stuck(delta: float) -> void:
	# Don't check stuck for player-commanded zombies
	# Players know what they want - let them command freely!
	if is_player_commanded:
		stuck_timer = 0.0
		return
	
	var distance_moved := position.distance_to(last_position)
	
	# Check if zombie moved significantly
	if distance_moved > stuck_threshold:
		# Moving fine, reset timer
		stuck_timer = 0.0
	else:
		# Not moving much, increment timer
		stuck_timer += delta
		
		# If stuck too long, find new target
		if stuck_timer >= stuck_timeout:
			# Don't abandon target if we're in combat (melee, committed, or grappling from leap)
			# Being "stuck" during combat is normal - you're fighting!
			if is_committed_to_target or is_melee_attacker or has_leap_grappled:
				print("⏸️ Zombie stuck but in combat - staying engaged")
				stuck_timer = 0.0  # Reset timer, keep fighting
				return
			
			print("🚧 ZOMBIE STUCK - FINDING NEW TARGET:")
			print("  Zombie: ", name, " at ", position)
			print("  Current target: ", attack_target.name if attack_target else "NONE")
			print("  Distance moved: ", position.distance_to(last_position), "px")
			print("  Stuck duration: ", stuck_timeout, "s")
			
			# Try to find a different target
			var new_target := find_nearest_human_in_range(active_vision_range)
			
			if new_target and new_target != attack_target:
				# Found a different target - this is auto-pursuit, not player command
				set_attack_target(new_target, false)
				is_locked_in_pursuit = true  # Lock from player control
				update_selection_visual()  # Update color to red
				print("Zombie switched to new target")
			else:
				# No other targets available, go idle
				clear_attack_target()
				print("Zombie going idle - no available targets")
			
			# Reset stuck timer
			stuck_timer = 0.0


## Override set_attack_target to clean up melee attacker status and leap tracking
## @param target: The Unit to attack
## @param player_commanded: Whether this target was assigned by player (vs auto-pursuit)
func set_attack_target(target: Unit, player_commanded: bool = false) -> void:
	# Guard: If setting the same target, just update player_commanded flag and return
	if attack_target == target and is_instance_valid(target):
		is_player_commanded = player_commanded
		if player_commanded:
			is_locked_in_pursuit = false
			update_selection_visual()
		return  # Don't re-add to attacker count
	
	# Remove from old target's attacker count (switching to different target)
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		attack_target.remove_attacker()
	
	# Remove melee attacker status from old target
	if is_melee_attacker and attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		is_melee_attacker = false
	
	# Reset leap grapple tracking when changing targets
	has_leap_grappled = false
	leap_grappled_target = null  # Clear pinned target
	
	# Clear commitment when changing targets (new engagement)
	is_committed_to_target = false
	
	# Track whether this is a player command or auto-pursuit
	is_player_commanded = player_commanded
	
	# If player commanded, clear pursuit lock (player has control)
	# If auto-pursuit, zombie is locked from further commands
	if player_commanded:
		is_locked_in_pursuit = false
		update_selection_visual()  # Update color to green
	# Note: is_locked_in_pursuit is set separately in check_auto_pursuit
	
	# Call parent to set the new target
	super.set_attack_target(target)
	
	# Add to new target's attacker count (for red border on humans being chased)
	if target and is_instance_valid(target) and target.is_human():
		target.add_attacker()


## Clears the current attack target and goes idle
## Used when zombie is stuck and can't find new targets
func clear_attack_target() -> void:
	# Remove from target's attacker count
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		attack_target.remove_attacker()
	
	# Remove melee attacker status from current target
	if is_melee_attacker:
		is_melee_attacker = false
	
	# Clear leap grapple tracking
	has_leap_grappled = false
	leap_grappled_target = null
	
	# Clear the target
	attack_target = null
	
	# Clear commitment (no longer engaged)
	is_committed_to_target = false
	
	# Clear pursuit lock - zombie is now idle and controllable
	is_locked_in_pursuit = false
	is_player_commanded = false
	update_selection_visual()  # Update color to green


## Called when this zombie's health reaches 0
## Removes self from target's melee attacker count before dying
## Override of Unit.die()
func die() -> void:
	# Clean up: remove melee attacker status
	if is_melee_attacker and attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		attack_target.remove_attacker()
		is_melee_attacker = false
	
	# Just remove this zombie from the game
	queue_free()


## Performs an attack on the current target
## Special zombie version that detects when a human is killed and emits a signal
## Override of Unit.perform_attack()
func perform_attack() -> void:
	# Safety checks: make sure target exists and is actually a human
	if is_instance_valid(attack_target) and attack_target.is_human():
		# Record if the human was alive before we attack
		var was_alive := attack_target.current_health > 0
		
		# Deal damage to the human
		attack_target.take_damage(attack_damage)
		
		# Check if our attack killed the human
		if was_alive and attack_target.current_health <= 0:
			# Emit signal so GameManager can spawn a new zombie
			# This is the core conversion mechanic!
			zombie_killed_human.emit(attack_target, self)


## === GROUP STATE PROPAGATION ===

## Propagates pursuit state to nearby allies when this zombie spots a human
## Creates pack hunting behavior - one zombie detects, whole group reacts
## @param target: The human to pursue
func propagate_pursuit_to_group(target: Unit) -> void:
	# Find nearby idle zombies within propagation radius
	var propagation_radius: float = 80.0
	var min_group_size: int = 4
	
	var nearby_allies: Array[Zombie] = []
	var zombies := get_tree().get_nodes_in_group("zombies")
	
	for other in zombies:
		if other == self or not other is Zombie:
			continue
		
		var zombie := other as Zombie
		
		# Only propagate to idle zombies with no current orders
		# Don't override player move commands or active pursuits
		if zombie.current_state != State.IDLE:
			continue
		
		# Don't override zombies that are moving to a player-commanded position
		if zombie.has_target:
			continue
		
		# Check distance
		var distance: float = position.distance_to(zombie.position)
		if distance <= propagation_radius:
			nearby_allies.append(zombie)
	
	# Only propagate if we have enough allies to form a pack
	if nearby_allies.size() >= min_group_size - 1:  # -1 because we don't count self
		print("PACK BEHAVIOR: ", nearby_allies.size() + 1, " zombies hunting together!")
		for ally in nearby_allies:
			ally.set_attack_target(target, false)
			# DON'T lock pack members - they should still be commandable
			# Only the zombie that detected the threat gets locked
			# ally.is_locked_in_pursuit = true  # REMOVED
			ally.update_selection_visual()
