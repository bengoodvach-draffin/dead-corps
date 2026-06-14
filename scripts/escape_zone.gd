@tool
extends Area2D
class_name EscapeZone

## Escape zone where humans reach safety.
##
## Humans that enter disappear and are counted as "escaped". Zombies are kept out
## by a HARD PHYSICAL BOUNDARY: a runtime StaticBody2D the size of the zone, on
## the "EscapeBarrier" collision layer (layer 4). Zombies' collision_mask includes
## layer 4, so move_and_slide sweeps them along it — they physically cannot enter
## (no death, no teleport, no jank). Humans (mask = Environment only) pass straight
## through to escape. The barrier is on its own layer, so it doesn't affect
## nav-baking — humans still path into the zone normally.
##
## This scales to level borders: place escape zones around the perimeter and
## zombies are walled off the map edge while humans escape through.
##
## @tool allows this to update in the editor when you change zone_size.

## Size of the escape zone rectangle (configurable in editor)
@export var zone_size: Vector2 = Vector2(200, 100):
	set(value):
		zone_size = value
		# Update visuals immediately when changed in editor
		update_zone()

## Color of the zone visual (red to indicate it blocks zombies)
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
	# Update the zone visuals (editor + runtime)
	update_zone()

	# Editor: visuals only — don't build the barrier or wire signals.
	if Engine.is_editor_hint():
		return

	# Build the physical zombie barrier (replaces the v1 instant-kill, step 1.4).
	_create_zombie_barrier()

	# Wire human-escape detection if a GameManager is present.
	game_manager = get_tree().get_first_node_in_group("game_manager")
	if not game_manager:
		# GameManager not found — likely a standalone test scene. That's fine;
		# the barrier still works, humans just won't be counted as escaped.
		print("EscapeZone: No GameManager found (level editor mode)")
	else:
		body_entered.connect(_on_body_entered)


## Builds a runtime-only StaticBody2D the size of the zone on the EscapeBarrier
## layer (layer 4 / value 8). Zombies collide with it (their mask includes it) and
## slide along the rim; humans don't (their mask is Environment only) and pass
## through. Hidden-body pattern mirrors wall.gd; never built in the editor.
func _create_zombie_barrier() -> void:
	var barrier := StaticBody2D.new()
	barrier.name = "ZombieBarrier"
	barrier.collision_layer = 8   # layer 4 "EscapeBarrier"
	barrier.collision_mask = 0    # the barrier itself collides with nothing
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	shape_node.shape = rect
	barrier.add_child(shape_node)
	add_child(barrier)


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


## Sets up the Area2D collision shape (human-escape detection) to match zone size
func setup_collision() -> void:
	collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		var shape := RectangleShape2D.new()
		shape.size = zone_size
		collision_shape.shape = shape


## Humans escape on entry. Zombies are stopped by the physical barrier, not here.
## Gameplay only, not editor.
func _on_body_entered(body: Node2D) -> void:
	if not body is Unit:
		return
	var unit: Unit = body as Unit
	if unit.is_human():
		print("  -> Human reached escape zone!")
		if game_manager:
			game_manager.on_human_escaped(unit)
		unit.queue_free()  # Remove the human
