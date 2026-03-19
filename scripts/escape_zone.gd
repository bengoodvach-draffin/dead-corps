@tool
extends Area2D
class_name EscapeZone

## Escape zone where humans can reach safety
##
## When a human enters this zone, they disappear and are counted as "escaped"
## When a zombie enters this zone, they die instantly
## This creates tactical gameplay where the player must intercept humans before they reach safety
##
## @tool allows this to update in the editor when you change zone_size

## Size of the escape zone rectangle (configurable in editor)
@export var zone_size: Vector2 = Vector2(200, 100):
	set(value):
		zone_size = value
		# Update visuals immediately when changed in editor
		update_zone()

## Color of the zone visual (red to indicate danger for zombies)
@export var zone_color: Color = Color(0.8, 0.2, 0.2, 0.3):
	set(value):
		zone_color = value
		# Update color immediately when changed in editor
		update_zone()

@onready var visual: ColorRect = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var game_manager: GameManager


## Called when the node enters the scene tree
func _ready() -> void:
	# Update the zone visuals
	update_zone()
	
	# Only connect signals when actually playing the game (not in editor)
	if not Engine.is_editor_hint():
		# Find game manager
		game_manager = get_tree().get_first_node_in_group("game_manager")
		if not game_manager:
			# GameManager not found - likely in level editor
			# This is fine, just don't connect signals
			print("EscapeZone: No GameManager found (level editor mode)")
		else:
			# Connect to body entered signal only if we have a game manager
			body_entered.connect(_on_body_entered)


## Updates both visual and collision to match current settings
## Called when properties change in editor or when scene loads
func update_zone() -> void:
	# Make sure child nodes exist (they might not during initialization)
	if not is_inside_tree():
		return
	
	setup_visual()
	setup_collision()


## Sets up the visual representation of the escape zone
func setup_visual() -> void:
	visual = get_node_or_null("Visual")
	if visual:
		visual.offset_left = -zone_size.x / 2
		visual.offset_top = -zone_size.y / 2
		visual.offset_right = zone_size.x / 2
		visual.offset_bottom = zone_size.y / 2
		visual.color = zone_color


## Sets up the collision shape to match the zone size
func setup_collision() -> void:
	collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		var shape := RectangleShape2D.new()
		shape.size = zone_size
		collision_shape.shape = shape


## Called when any body enters the escape zone
## Handles humans escaping and zombies dying
## Only runs during actual gameplay, not in editor
func _on_body_entered(body: Node2D) -> void:
	print("Escape zone: Body entered - ", body.name, " (type: ", body.get_class(), ")")
	
	# Check if it's a unit
	if not body is Unit:
		print("  -> Not a Unit, ignoring")
		return
	
	var unit: Unit = body as Unit
	
	# Handle humans escaping
	if unit.is_human():
		print("  -> Human reached escape zone!")
		if game_manager:
			game_manager.on_human_escaped(unit)
		unit.queue_free()  # Remove the human
	
	# Handle zombies dying
	elif unit.is_zombie():
		print("  -> Zombie entered escape zone - calling die()!")
		# If the zombie has a spawn_corpse_on_death flag (Fat Zombie), suppress the corpse
		# so no permanent obstacle is left behind when it exits via the escape zone.
		# Using property check avoids a class name dependency on FatZombie.
		if "spawn_corpse_on_death" in unit:
			unit.spawn_corpse_on_death = false
			print("  -> Corpse spawn suppressed for special zombie in escape zone")
		unit.die()  # Kill the zombie
