extends Node

## WorldBounds - Global singleton for game-wide configuration
##
## Register this as an Autoload in:
##   Project → Project Settings → Autoload
##   Path: res://scripts/world_bounds.gd
##   Name: WorldBounds
##
## This is the single source of truth for world bounds.
## Both unit.gd and camera_controller.gd read from here,
## so you only ever need to change bounds in ONE place.

# === WORLD BOUNDS ===
# Defines the playable area of the level.
# Units cannot move outside these bounds.
# Camera scroll is also constrained to these bounds by default.
#
# To resize your level:
#   Change these two values - everything updates automatically.
#
# Examples:
#   Small level:  min(-500,-500)   max(500,500)    = 1000x1000px
#   Medium level: min(-1000,-1000) max(1000,1000)  = 2000x2000px
#   Large level:  min(-2000,-1500) max(2000,1500)  = 4000x3000px

@export var world_bounds_min: Vector2 = Vector2(-1000, -1000)
@export var world_bounds_max: Vector2 = Vector2(1000, 1000)


## Returns the size of the world as a Vector2 (width, height)
func world_size() -> Vector2:
	return world_bounds_max - world_bounds_min


## Returns the center point of the world
func world_center() -> Vector2:
	return (world_bounds_min + world_bounds_max) / 2.0


## Returns true if the given position is inside the world bounds
func is_within_bounds(pos: Vector2) -> bool:
	return (
		pos.x >= world_bounds_min.x and pos.x <= world_bounds_max.x and
		pos.y >= world_bounds_min.y and pos.y <= world_bounds_max.y
	)


## Clamps a position to stay within world bounds
func clamp_to_bounds(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, world_bounds_min.x, world_bounds_max.x),
		clamp(pos.y, world_bounds_min.y, world_bounds_max.y)
	)
