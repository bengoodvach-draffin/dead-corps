@tool
extends Node2D
class_name LevelBounds

## LevelBounds - Per-level playable area definition
##
## Place one of these in each level scene. Set bounds_min and bounds_max
## in the Inspector to define the playable area for that level.
##
## On game start, writes its values into the WorldBounds autoload so all
## units and the camera automatically respect these bounds without any
## other changes required.
##
## Also draws a visible rectangle in both editor and game so you can
## see the boundary while placing units and debugging.

# === EXPORTED PROPERTIES ===

## Minimum corner of the playable area (top-left)
@export var bounds_min: Vector2 = Vector2(-500, -500):
	set(value):
		bounds_min = value
		queue_redraw()

## Maximum corner of the playable area (bottom-right)
@export var bounds_max: Vector2 = Vector2(500, 500):
	set(value):
		bounds_max = value
		queue_redraw()

## Colour of the boundary rectangle outline
@export var line_color: Color = Color(1.0, 0.3, 0.0, 0.9):
	set(value):
		line_color = value
		queue_redraw()

## Thickness of the boundary line in pixels
@export_range(1.0, 8.0, 0.5) var line_width: float = 2.0:
	set(value):
		line_width = value
		queue_redraw()

## Subtle fill colour inside the boundary (use low alpha)
@export var fill_color: Color = Color(1.0, 0.3, 0.0, 0.04):
	set(value):
		fill_color = value
		queue_redraw()

## Whether to draw corner labels showing the coordinate values
@export var show_labels: bool = true:
	set(value):
		show_labels = value
		queue_redraw()


## Called when node enters scene tree
## In game: pushes bounds into WorldBounds autoload
func _ready() -> void:
	# Always redraw when entering tree
	queue_redraw()

	# Don't update WorldBounds in editor - only at runtime
	if Engine.is_editor_hint():
		return

	# Push this level's bounds into the global WorldBounds singleton
	# so all units and the camera clamp to the correct area
	if WorldBounds:
		WorldBounds.world_bounds_min = bounds_min
		WorldBounds.world_bounds_max = bounds_max
		print("✅ LevelBounds: set world bounds to ", bounds_min, " → ", bounds_max)
	else:
		push_error("LevelBounds: WorldBounds autoload not found! Bounds will not be applied.")


## Redraws the boundary rectangle each frame in editor
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## Draws the boundary rectangle and optional corner labels
func _draw() -> void:
	var rect := Rect2(bounds_min, bounds_max - bounds_min)

	# Draw filled rectangle (subtle tint)
	draw_rect(rect, fill_color, true)

	# Draw outline rectangle
	draw_rect(rect, line_color, false, line_width)

	# Draw corner tick marks (slightly longer than the line, for clarity)
	var tick: float = 20.0
	var corners := [
		bounds_min,                          # top-left
		Vector2(bounds_max.x, bounds_min.y), # top-right
		bounds_max,                          # bottom-right
		Vector2(bounds_min.x, bounds_max.y), # bottom-left
	]
	for corner in corners:
		draw_circle(corner, line_width * 2.0, line_color)

	if not show_labels:
		return

	# Draw coordinate labels at each corner using small line-drawn markers
	# Godot _draw() can't render fonts without a FontFile reference,
	# so we draw small cross markers instead, which are always visible
	var marker_size: float = 8.0
	var label_color: Color = line_color

	# Top-left marker — extra prominent (origin reference)
	draw_line(
		bounds_min + Vector2(-marker_size, 0),
		bounds_min + Vector2(marker_size, 0),
		label_color, line_width
	)
	draw_line(
		bounds_min + Vector2(0, -marker_size),
		bounds_min + Vector2(0, marker_size),
		label_color, line_width
	)

	# Centre crosshair — helps with placement
	var center := (bounds_min + bounds_max) / 2.0
	var crosshair: float = 16.0
	var center_color := Color(line_color.r, line_color.g, line_color.b, 0.4)
	draw_line(
		center + Vector2(-crosshair, 0),
		center + Vector2(crosshair, 0),
		center_color, 1.0
	)
	draw_line(
		center + Vector2(0, -crosshair),
		center + Vector2(0, crosshair),
		center_color, 1.0
	)

	# Size indicator lines along the edges (dashed-style using segments)
	var dash_length: float = 10.0
	var gap_length: float = 8.0
	var dash_color: Color = Color(line_color.r, line_color.g, line_color.b, 0.35)
	var width: float = bounds_max.x - bounds_min.x
	var height: float = bounds_max.y - bounds_min.y

	# Top edge dashes
	var x := bounds_min.x + dash_length
	while x < bounds_max.x - dash_length:
		draw_line(Vector2(x, bounds_min.y), Vector2(x + dash_length, bounds_min.y), dash_color, 1.0)
		x += dash_length + gap_length

	# Left edge dashes
	var y := bounds_min.y + dash_length
	while y < bounds_max.y - dash_length:
		draw_line(Vector2(bounds_min.x, y), Vector2(bounds_min.x, y + dash_length), dash_color, 1.0)
		y += dash_length + gap_length
