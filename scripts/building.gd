@tool  # Allows script to run in editor
extends StaticBody2D
class_name Building

## Building - Static obstacle that blocks unit movement and line of sight
##
## Buildings serve as obstacles in the game world. They have several key properties:
## - Physical collision: Units cannot walk through buildings
## - Line of sight blocking: Zombies and humans cannot see through buildings
## - Static: Buildings don't move or change during gameplay
##
## Buildings are StaticBody2D nodes, which means they:
## - Have collision shapes that block CharacterBody2D units
## - Don't move (unlike RigidBody2D which has physics)
## - Are optimized for static level geometry
##
## HOW TO RESIZE IN EDITOR:
## 1. Expand the Building node in Scene Tree
## 2. Select the CollisionShape2D child node
## 3. Drag the ORANGE HANDLES in the viewport
## 4. Visual updates automatically!

# === EXPORTED PROPERTIES ===

## Color of the building placeholder graphic
## Will be replaced with sprites in future versions
@export var building_color: Color = Color(0.4, 0.4, 0.4, 1):
	set(value):
		building_color = value
		# Update color in real-time (works in editor with @tool)
		if is_node_ready() and visual:
			visual.color = building_color

## Whether this building can be entered (for future interactive features)
## Currently unused, but reserved for future building interaction mechanics
@export var is_enterable: bool = false

## Width of the building in pixels
@export_range(20, 1000, 10) var building_width: float = 100:
	set(value):
		building_width = value
		update_size_from_properties()

## Height of the building in pixels
@export_range(20, 1000, 10) var building_height: float = 150:
	set(value):
		building_height = value
		update_size_from_properties()

# === NODE REFERENCES ===

## Visual representation of the building (placeholder colored rectangle)
@onready var visual: ColorRect = $Visual

## Collision shape that prevents units from walking through
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


## Called when the node enters the scene tree
## Sets up the building's visual appearance based on collision shape
func _ready() -> void:
	# CRITICAL: Duplicate the collision shape so each building has its own
	# Without this, all buildings share the same shape resource!
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
		
		# Apply exported properties to shape (not the other way around!)
		# This ensures user's width/height settings are preserved
		var shape = collision_shape.shape as RectangleShape2D
		if shape:
			shape.size = Vector2(building_width, building_height)
	
	update_visual_from_collision()
	
	# Add to "buildings" group so other systems can find all buildings
	add_to_group("buildings")


## Called every frame in editor mode to keep visual in sync with collision shape
func _process(_delta: float) -> void:
	# Only run in editor
	if Engine.is_editor_hint():
		update_visual_from_collision()


## Reads size from CollisionShape2D and updates the visual to match
## This allows you to resize buildings by dragging collision shape handles!
func update_visual_from_collision() -> void:
	if not collision_shape or not visual:
		return
	
	# Get the collision shape (should be RectangleShape2D)
	var shape := collision_shape.shape as RectangleShape2D
	if not shape:
		return
	
	# Read size from collision shape
	var size := shape.size
	
	# Update visual to match
	visual.offset_left = -size.x / 2
	visual.offset_top = -size.y / 2
	visual.offset_right = size.x / 2
	visual.offset_bottom = size.y / 2
	visual.color = building_color


## Updates collision shape size from exported width/height properties
## Called when you change building_width or building_height in inspector
func update_size_from_properties() -> void:
	if not is_inside_tree():
		return
	
	if not collision_shape or not collision_shape.shape:
		return
	
	var shape := collision_shape.shape as RectangleShape2D
	if not shape:
		return
	
	# Update collision shape size
	shape.size = Vector2(building_width, building_height)
	
	# Update visual to match
	update_visual_from_collision()
