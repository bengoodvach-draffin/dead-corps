extends Camera2D
class_name CameraController

## Camera controller for RTS-style navigation
## 
## Provides smooth, responsive camera controls for an RTS game including:
## - WASD keyboard panning
## - Mouse wheel zoom with smooth interpolation
## - Edge scrolling (moving mouse to screen edge scrolls camera)
## - Optional camera bounds to prevent scrolling outside the map
##
## The camera uses zoom-adjusted movement speeds so panning feels consistent
## at any zoom level. All settings are exposed as @export variables for easy
## tweaking in the Godot editor.

# === CAMERA MOVEMENT SETTINGS ===

## Speed of camera panning when using WASD keys (pixels per second)
## Higher values = faster panning
@export var pan_speed: float = 400.0

## Size of the invisible margin at screen edges that triggers scrolling (in pixels)
## Smaller values = need to move mouse closer to edge to scroll
@export var edge_scroll_margin: int = 20

## Speed of camera panning when edge scrolling (pixels per second)
## Can be different from keyboard pan speed for different feel
@export var edge_scroll_speed: float = 400.0

## Whether edge scrolling is enabled
## Set to false if you want keyboard-only camera control
@export var enable_edge_scroll: bool = true

# === ZOOM SETTINGS ===

## How much to change zoom level per mouse wheel tick
## Smaller values = more gradual zoom, larger values = faster zoom jumps
@export var zoom_speed: float = 0.1

## Minimum zoom level (0.5 = zoomed out, smaller numbers = even more zoomed out)
## Prevents zooming out too far
@export var min_zoom: float = 0.5

## Maximum zoom level (2.0 = zoomed in, larger numbers = even more zoomed in)
## Prevents zooming in too close
@export var max_zoom: float = 2.0

## Speed of zoom interpolation (higher = snappier, lower = smoother)
## Multiplied by delta time and used in lerp() for smooth transitions
@export var zoom_smoothing: float = 10.0

# === CAMERA BOUNDS SETTINGS ===

## Whether to constrain camera movement to specific bounds
## Set to true to prevent camera from leaving the map area
@export var use_bounds: bool = true

## Top-left corner of the camera bounds (world coordinates)
## Only used if use_bounds is true
## Defaults to WorldBounds.world_bounds_min - override here for per-scene control
@export var bounds_min: Vector2 = Vector2(-1000, -1000)

## Bottom-right corner of the camera bounds (world coordinates)
## Only used if use_bounds is true
## Defaults to WorldBounds.world_bounds_max - override here for per-scene control
@export var bounds_max: Vector2 = Vector2(1000, 1000)

# === RUNTIME STATE VARIABLES ===

## The zoom level we're smoothly transitioning toward
## Actual zoom interpolates toward this value for smooth animation
var target_zoom: float = 1.0

## Cached size of the viewport (in pixels)
## Used for edge scroll detection
var viewport_size: Vector2


## Called when the node enters the scene tree
## Initializes camera state
func _ready() -> void:
	# Cache the viewport size (window/screen size)
	viewport_size = get_viewport_rect().size
	
	# Initialize target zoom to current zoom
	# (zoom.x and zoom.y are always kept in sync)
	target_zoom = zoom.x
	
	# Sync bounds from WorldBounds if use_bounds is true and
	# bounds haven't been manually overridden in the Inspector
	# (i.e. they're still at the old default of ±500)
	# To override per-scene, simply set bounds_min/max in the Inspector.
	if use_bounds and bounds_min == Vector2(-500, -500) and bounds_max == Vector2(500, 500):
		bounds_min = WorldBounds.world_bounds_min
		bounds_max = WorldBounds.world_bounds_max


## Called every frame
## Handles all camera movement, zoom, and bounds checking
## @param delta: Time elapsed since last frame in seconds
func _process(delta: float) -> void:
	handle_keyboard_pan(delta)  # WASD movement
	handle_edge_scroll(delta)   # Mouse-at-edge movement
	handle_zoom(delta)          # Smooth zoom interpolation
	apply_bounds()              # Constrain to map bounds


## Handles camera panning via WASD or arrow keys
## Movement speed is adjusted by zoom level so it feels consistent
## @param delta: Time elapsed since last frame in seconds
func handle_keyboard_pan(delta: float) -> void:
	# Start with no movement
	var direction := Vector2.ZERO
	
	# Check each direction key and build up direction vector
	# Input actions are defined in project.godot (WASD)
	if Input.is_action_pressed("camera_up"):
		direction.y -= 1  # Negative Y is up in Godot
	if Input.is_action_pressed("camera_down"):
		direction.y += 1  # Positive Y is down
	if Input.is_action_pressed("camera_left"):
		direction.x -= 1  # Negative X is left
	if Input.is_action_pressed("camera_right"):
		direction.x += 1  # Positive X is right
	
	# ALSO check arrow keys directly
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1
	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1
	
	# If any keys are pressed, move the camera
	if direction.length() > 0:
		# Normalize so diagonal movement isn't faster than cardinal
		direction = direction.normalized()
		
		# Move camera: speed * delta (for frame-rate independence) / zoom
		# Dividing by zoom.x makes panning feel consistent at any zoom level
		position += direction * pan_speed * delta / zoom.x


## Handles camera panning when mouse is near screen edges
## Only active if enable_edge_scroll is true
## @param delta: Time elapsed since last frame in seconds
func handle_edge_scroll(delta: float) -> void:
	# DISABLED: Edge scrolling (too sensitive during testing)
	# Keeping code for potential re-enable later
	return
	
	## Exit early if edge scrolling is disabled
	#if not enable_edge_scroll:
	#	return
	#
	## Exit if window doesn't have focus (prevents scrolling when alt-tabbed or cursor leaves window)
	#if not get_viewport().has_focus():
	#	return
	#
	## Get current mouse position in screen coordinates (pixels from top-left)
	#var mouse_pos := get_viewport().get_mouse_position()
	#var direction := Vector2.ZERO
	#
	## Check if mouse is near the left or right edge
	#if mouse_pos.x < edge_scroll_margin:
	#	direction.x -= 1  # Near left edge = scroll left
	#elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
	#	direction.x += 1  # Near right edge = scroll right
	#
	## Check if mouse is near the top or bottom edge
	#if mouse_pos.y < edge_scroll_margin:
	#	direction.y -= 1  # Near top edge = scroll up
	#elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
	#	direction.y += 1  # Near bottom edge = scroll down
	#
	## If mouse is near any edge, scroll the camera
	#if direction.length() > 0:
	#	direction = direction.normalized()
	#	position += direction * edge_scroll_speed * delta / zoom.x


## Handles smooth zoom interpolation
## Actual zoom level smoothly transitions toward target_zoom
## Mouse wheel input (which changes target_zoom) is handled in _input()
## @param delta: Time elapsed since last frame in seconds
func handle_zoom(delta: float) -> void:
	# Smoothly interpolate current zoom toward target zoom
	# lerp(a, b, weight) = linear interpolation from a to b
	# Higher zoom_smoothing * delta = faster transition
	zoom.x = lerp(zoom.x, target_zoom, zoom_smoothing * delta)
	
	# Keep Y zoom in sync with X zoom (cameras need both for 2D)
	zoom.y = zoom.x


## Handles mouse wheel input to change target zoom level
## Called by Godot whenever an input event occurs
## @param event: The input event (mouse button, key press, etc.)
func _input(event: InputEvent) -> void:
	# Check if this is a zoom in event (mouse wheel up)
	if event.is_action_pressed("zoom_in"):
		# Increase target zoom, but clamp to valid range
		target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
	
	# Check if this is a zoom out event (mouse wheel down)
	elif event.is_action_pressed("zoom_out"):
		# Decrease target zoom, but clamp to valid range
		target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)


## Constrains camera position to stay within defined bounds
## Only active if use_bounds is true
## Called every frame after all movement has been applied
func apply_bounds() -> void:
	# Exit early if bounds are disabled
	if not use_bounds:
		return
	
	# Clamp X position to horizontal bounds
	position.x = clamp(position.x, bounds_min.x, bounds_max.x)
	
	# Clamp Y position to vertical bounds
	position.y = clamp(position.y, bounds_min.y, bounds_max.y)


## Sets camera movement bounds dynamically at runtime
## Useful for constraining camera to the current map size
## @param min_pos: Top-left corner of bounds (world coordinates)
## @param max_pos: Bottom-right corner of bounds (world coordinates)
func set_camera_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	use_bounds = true
	bounds_min = min_pos
	bounds_max = max_pos
