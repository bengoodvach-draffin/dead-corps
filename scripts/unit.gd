extends CharacterBody2D
class_name Unit

## Base class for all units (zombies and humans)
## 
## This is the foundation for all movable units in the game. It provides core
## functionality for movement, combat, health management, and selection.
## Both Zombie and Human classes inherit from this base class.
##
## Key responsibilities:
## - Movement to target positions (constrained to game bounds)
## - Combat system (attacking and taking damage)
## - Health management and death
## - Selection and visual feedback
## - Physics-based movement using CharacterBody2D

## Enum defining all possible unit types in the game
## Used to identify what kind of unit this is for special abilities and behavior
enum UnitType {
	ZOMBIE_BASIC,        ## Standard zombie unit
	ZOMBIE_FAT,          ## Fat zombie - tank role
	ZOMBIE_FIREMAN,      ## Fireman zombie - fire resistance
	ZOMBIE_TRAFFIC,      ## Traffic controller - movement buffs
	ZOMBIE_BAND,         ## Marching band - area effects
	ZOMBIE_SCUBA,        ## Scuba zombie - water traversal
	ZOMBIE_HEADLESS,     ## Headless zombie - special pathfinding
	ZOMBIE_COSTUME,      ## Costume zombie - disguise abilities
	ZOMBIE_PETROL,       ## Petrol zombie - explosive attacks
	ZOMBIE_MOTORCYCLE,   ## Motorcycle zombie - high speed
	ZOMBIE_ORDNANCE,     ## Ordnance zombie - ranged attacks
	ZOMBIE_HEADCRAB,     ## Headcrab zombie - special mechanics
	HUMAN_CIVILIAN,      ## Basic human unit
	HUMAN_POLICE,        ## Police - medium strength
	HUMAN_SWAT,          ## SWAT - heavy armor
	HUMAN_MILITARY       ## Military - strongest human type
}

## Enum defining which team a unit belongs to
## Determines friend/foe relationships and victory conditions
enum Team {
	ZOMBIES,  ## Player-controlled zombie team
	HUMANS    ## Enemy human team
}

# === EXPORTED PROPERTIES (Configurable in Godot Editor) ===

## The specific type of this unit (determines abilities and behavior)
@export var unit_type: UnitType = UnitType.ZOMBIE_BASIC

## Which team this unit belongs to (affects targeting and conversion)
@export var team: Team = Team.ZOMBIES

# === STATS ===
@export_group("Stats")

## Maximum health points - unit dies when current_health reaches 0
@export var max_health: float = 100.0

## Movement speed in pixels per second
@export var move_speed: float = 100.0

## Collision radius of this unit in pixels - used for boundary clamping
## Must match the CollisionShape2D radius on this unit's scene
@export var unit_radius: float = 12.0

# === COMBAT ===
@export_group("Combat")

## Damage dealt per attack
@export var attack_damage: float = 10.0

## Distance in pixels at which this unit can attack
@export var attack_range: float = 30.0

## Time in seconds between attacks (prevents rapid-fire)
@export var attack_cooldown: float = 1.0

# === FORMATION ===
@export_group("Formation")

## Distance to search for nearby allies for formation cohesion
@export var formation_detection_radius: float = 100.0

## Strength of cohesion force (pulls toward group center)
## Higher values = tighter formations
@export var cohesion_strength: float = 30.0

## Rate at which units align their facing direction with group
## 0.0 = no alignment, 1.0 = instant alignment
@export var alignment_rate: float = 0.8

## Minimum number of nearby allies needed to apply formation forces
@export var min_formation_size: int = 2

## Distance to maintain separation from other units
@export var separation_radius: float = 30.0

## Strength of separation/repulsion force
@export var separation_strength: float = 100.0

@export_group("")

# === GAME BOUNDS ===
# World bounds are defined in the WorldBounds autoload singleton.
# Edit them there (Project Settings → Autoload → WorldBounds).
# This keeps bounds as a single source of truth across all units and the camera.

# === RUNTIME STATE VARIABLES ===

## Current health points (starts at max_health, decreases when taking damage)
var current_health: float

## Whether this unit is currently selected by the player
var is_selected: bool = false

## Control group number this unit is assigned to (0 = no assignment, 1-9 = group number)
var control_group_number: int = 0

## World position this unit is moving toward (only used when has_target is true)
var target_position: Vector2

## Whether this unit is currently moving to a target position
var has_target: bool = false

## Another unit this unit is trying to attack (takes priority over movement)
var attack_target: Unit = null

## Countdown timer for attack cooldown (attacks only happen when this reaches 0)
var attack_timer: float = 0.0

# === NODE REFERENCES (Cached on ready) ===

## Reference to the Sprite2D child node for visual representation
@onready var sprite: Sprite2D = $Sprite

## Reference to the selection indicator node (shows when unit is selected)
@onready var selection_indicator: Node2D = $SelectionIndicator

## Reference to the health bar UI element
@onready var health_bar: ProgressBar = $HealthBar

## Reference to the control group number label (optional)
@onready var control_group_label: Label = get_node_or_null("ControlGroupLabel")


## Called when the node enters the scene tree
## Initializes the unit's starting state and ensures it's within bounds
func _ready() -> void:
	# Set health to maximum at start
	current_health = max_health
	
	# Initialize target position to current position (unit starts stationary)
	target_position = position
	
	# Make sure unit spawns within game bounds
	clamp_position_to_bounds()
	
	# Update visual elements to match initial state
	update_selection_visual()
	update_health_bar()


## Called every frame (delta is time since last frame in seconds)
## Handles non-physics updates like timers and UI
## @param delta: Time elapsed since last frame in seconds
func _process(delta: float) -> void:
	# Count down the attack cooldown timer
	if attack_timer > 0:
		attack_timer -= delta
	
	# Keep the health bar display updated
	update_health_bar()


## Called every physics frame (fixed timestep)
## Handles movement, combat logic, boundary enforcement, and separation
## @param delta: Physics timestep in seconds (usually 1/60)
func _physics_process(delta: float) -> void:
	# Apply BOID flocking forces
	apply_separation_force()   # Prevent stacking
	# apply_cohesion_force()   # Pull toward group center — disabled v0.25.1
	#                            (existed to create merged vision blobs; merged cones removed)
	#                            Re-enable here if horde clustering behaviour is wanted later.
	apply_alignment_force()    # Align facing with group
	
	# Priority 1: If we have a valid attack target, handle combat
	if attack_target and is_instance_valid(attack_target):
		handle_combat(delta)
	# Priority 2: Otherwise, if we have a movement target, move toward it
	elif has_target:
		move_to_target(delta)
	
	# Always enforce game boundaries after movement
	clamp_position_to_bounds()


## Moves the unit toward its target position
## Uses the CharacterBody2D physics system for collision handling
## Stops when within 5 pixels of the target
## @param _delta: Physics timestep (unused but required by convention)
func move_to_target(_delta: float) -> void:
	# Calculate direction vector from current position to target
	var direction := (target_position - position).normalized()
	
	# Calculate how far away we are from the target
	var distance := position.distance_to(target_position)
	
	# If we're more than 5 pixels away, keep moving
	if distance > 5.0:  # Close enough threshold
		velocity = direction * move_speed
		move_and_slide()  # Built-in Godot function that handles collision
	else:
		# We've arrived - stop moving
		velocity = Vector2.ZERO
		has_target = false


## Constrains the unit's position to stay within the game bounds
## Accounts for unit_radius so the unit's edge (not centre) stays inside the boundary
## Called after every movement to prevent units from leaving the play area
func clamp_position_to_bounds() -> void:
	var bounds_min: Vector2 = WorldBounds.world_bounds_min
	var bounds_max: Vector2 = WorldBounds.world_bounds_max
	
	# Inset bounds by unit radius so the unit edge — not its centre — hits the wall
	var min_x := bounds_min.x + unit_radius
	var max_x := bounds_max.x - unit_radius
	var min_y := bounds_min.y + unit_radius
	var max_y := bounds_max.y - unit_radius
	
	# Clamp position to inset bounds
	position.x = clamp(position.x, min_x, max_x)
	position.y = clamp(position.y, min_y, max_y)
	
	# If we hit a boundary while moving, stop velocity on that axis
	if position.x == min_x or position.x == max_x:
		velocity.x = 0
	if position.y == min_y or position.y == max_y:
		velocity.y = 0


## Commands this unit to move to a specific world position
## Target is automatically clamped to game bounds
## Cancels any current attack target
## @param target: World position (Vector2) to move toward
func set_move_target(target: Vector2) -> void:
	# Clamp the target position to game bounds via WorldBounds
	target_position = WorldBounds.clamp_to_bounds(target)
	
	has_target = true
	attack_target = null  # Clear attack target when given move command


## Commands this unit to attack another unit
## Cancels any current movement target
## @param target: The Unit to attack
func set_attack_target(target: Unit) -> void:
	attack_target = target
	has_target = false  # Clear movement target when given attack command


## Handles combat behavior when this unit has an attack target
## Either moves closer to target (if out of range) or attacks (if in range)
## @param _delta: Physics timestep (unused but required by convention)
func handle_combat(_delta: float) -> void:
	# Safety check: make sure target still exists (could have died)
	if not is_instance_valid(attack_target):
		attack_target = null
		return
	
	# Calculate distance to target
	var distance := position.distance_to(attack_target.position)
	
	# If target is too far away, move closer
	if distance > attack_range:
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


## Executes an attack on the current attack target
## Deals damage equal to this unit's attack_damage
## Can be overridden in child classes for special attack behavior
func perform_attack() -> void:
	# Safety check before dealing damage
	if is_instance_valid(attack_target):
		attack_target.take_damage(attack_damage)


## Reduces this unit's health by the specified amount
## Triggers death if health reaches or goes below 0
## @param amount: How much damage to deal
func take_damage(amount: float) -> void:
	current_health -= amount
	update_health_bar()
	
	# Check if this damage killed the unit
	if current_health <= 0:
		die()


## Called when this unit's health reaches 0
## Default behavior is to remove the unit from the game
## Override in child classes (Zombie, Human) for special death behavior
func die() -> void:
	queue_free()  # Godot function that removes this node from the scene


## Marks this unit as selected
## Shows the selection indicator visual
func select() -> void:
	is_selected = true
	update_selection_visual()


## Marks this unit as deselected
## Hides the selection indicator visual
func deselect() -> void:
	is_selected = false
	update_selection_visual()


## Updates the visibility of the selection indicator based on selection state
## Called automatically when selection state changes
func update_selection_visual() -> void:
	if selection_indicator:
		selection_indicator.visible = is_selected


## Updates the health bar's visual state
## Shows health bar only when damaged (hides when at full health)
## Updates the progress bar value to match current health percentage
func update_health_bar() -> void:
	if health_bar:
		# Calculate health as a percentage (0-100)
		health_bar.value = (current_health / max_health) * 100.0
		
		# Only show health bar when unit is damaged
		health_bar.visible = current_health < max_health


## Applies BOID-style separation force to prevent units from stacking
## Units maintain minimum distance from teammates for better visuals
## Disabled for melee attackers to prevent bumping during combat
## === FORMATION COHESION (BOID BEHAVIOR) ===

## Finds nearby allies of the same type and team within detection radius
## Used for formation cohesion and alignment
## @param radius: Distance to search for allies (default uses formation_detection_radius)
## @return: Array of nearby Unit allies in same state
func find_nearby_allies(radius: float = -1.0) -> Array[Unit]:
	if radius < 0:
		radius = formation_detection_radius
	
	var allies: Array[Unit] = []
	
	# Get units of the same team
	var my_group := "zombies" if is_zombie() else "humans"
	var nearby_units := get_tree().get_nodes_in_group(my_group)
	
	for other_unit in nearby_units:
		if other_unit == self or not other_unit is Unit:
			continue
		
		# Check if within radius
		var distance := position.distance_to(other_unit.position)
		if distance <= radius:
			allies.append(other_unit)
	
	return allies


## Applies separation force to prevent units from stacking on each other
## Part of BOID flocking behavior - creates personal space
func apply_separation_force() -> void:
	# Don't push zombies that are actively attacking (prevents bumping)
	if is_zombie():
		var zombie := self as Zombie
		if zombie.is_melee_attacker:
			return
	
	# Use state-aware separation parameters (set by state-tuning in child classes)
	# Get units of the same team
	var my_group := "zombies" if is_zombie() else "humans"
	var nearby_units := get_tree().get_nodes_in_group(my_group)
	
	var separation_vector := Vector2.ZERO
	var neighbor_count := 0
	
	for other_unit in nearby_units:
		if other_unit == self or not other_unit is Unit:
			continue
		
		var distance := position.distance_to(other_unit.position)
		
		# If too close, add repulsion force
		if distance < separation_radius and distance > 0.1:
			# Direction away from neighbor
			var away_direction: Vector2 = (position - other_unit.position).normalized()
			
			# Stronger repulsion when closer (squared for more aggressive push)
			var normalized_distance := distance / separation_radius
			var force := (1.0 - normalized_distance * normalized_distance) * separation_strength
			
			separation_vector += away_direction * force
			neighbor_count += 1
	
	# Apply averaged separation force
	if neighbor_count > 0:
		separation_vector /= neighbor_count
		# NOTE: Separation uses position adjustment (not target adjustment)
		# This is intentional - we need immediate response to prevent stacking
		# Cohesion uses target adjustment to avoid speed artifacts
		position += separation_vector * get_physics_process_delta_time()


## Applies cohesion force to pull unit toward the center of nearby allies
## Part of BOID flocking behavior - creates group formations
## Only applies to idle units - respects player commands
func apply_cohesion_force() -> void:
	# Don't apply cohesion if disabled (state-based tuning sets to 0)
	if cohesion_strength <= 0.1:
		return
	
	# Don't apply if unit is currently moving
	# Only apply gentle drift when truly idle
	if velocity.length() > 5.0:
		return
	
	# Find nearby allies
	var allies := find_nearby_allies()
	
	# Need minimum number of allies to form a group
	if allies.size() < min_formation_size:
		return
	
	# Calculate center of mass of the group
	var center_of_mass := Vector2.ZERO
	for ally in allies:
		center_of_mass += ally.position
	center_of_mass /= allies.size()
	
	# Calculate direction toward center
	var to_center := center_of_mass - position
	var distance_to_center := to_center.length()
	
	# Only apply if not already close to group center
	# Stop pulling once within 60% of grouping distance to prevent jitter
	var cohesion_stop_distance: float = 48.0  # 60% of 80px grouping threshold
	if distance_to_center > cohesion_stop_distance:
		# Cohesion force - scales with distance for natural grouping
		var max_cohesion_per_frame: float = 8.0  # Increased from 2.0 - faster grouping
		var cohesion_vector: Vector2 = to_center.normalized() * min(cohesion_strength * 0.3, max_cohesion_per_frame)
		
		# Apply as gentle adjustment to position
		position += cohesion_vector * get_physics_process_delta_time()


## Applies alignment force to match facing direction with nearby allies
## Part of BOID flocking behavior - aligns unit heading with group
func apply_alignment_force() -> void:
	# Only apply alignment to zombies (humans don't need aligned facing)
	if not is_zombie():
		return
	
	# Find nearby allies
	var allies := find_nearby_allies()
	
	# Need minimum number of allies to form a group
	if allies.size() < min_formation_size:
		return
	
	# Calculate average facing direction of the group
	var average_facing := Vector2.ZERO
	var valid_count := 0
	
	for ally in allies:
		if ally is Zombie:
			var zombie := ally as Zombie
			if zombie.facing_direction.length() > 0.1:
				average_facing += zombie.facing_direction
				valid_count += 1
	
	# If we have valid facing directions, align with them
	if valid_count > 0:
		average_facing /= valid_count
		average_facing = average_facing.normalized()
		
		# Get current facing direction
		var zombie := self as Zombie
		if zombie and zombie.facing_direction.length() > 0.1:
			# Smoothly rotate toward average facing
			var target_facing := zombie.facing_direction.lerp(average_facing, alignment_rate * get_physics_process_delta_time() * 10.0)
			zombie.facing_direction = target_facing.normalized()


## Returns which team this unit belongs to
## @return: Team enum value (ZOMBIES or HUMANS)
func get_team() -> Team:
	return team


## Checks if this unit is on the zombie team
## @return: true if this unit is a zombie, false otherwise
func is_zombie() -> bool:
	return team == Team.ZOMBIES


## Checks if this unit is on the human team
## @return: true if this unit is a human, false otherwise
func is_human() -> bool:
	return team == Team.HUMANS


## Sets the control group number for this unit (1-9)
## Updates the visual label to display the number
## @param number: Control group number (1-9)
func set_control_group_number(number: int) -> void:
	control_group_number = number
	update_control_group_label()


## Clears the control group assignment from this unit
## Hides the control group label
func clear_control_group_number() -> void:
	control_group_number = 0
	update_control_group_label()


## Updates the control group label visual
## Shows the number if assigned (1-9), hides if not assigned (0)
func update_control_group_label() -> void:
	if control_group_label:
		if control_group_number > 0:
			control_group_label.text = str(control_group_number)
			control_group_label.visible = true
		else:
			control_group_label.visible = false
