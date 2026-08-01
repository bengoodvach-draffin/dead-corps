@tool
extends Node2D
class_name ShelterSpot

## ShelterSpot — an authored interior position inside a ShelterBuilding
## (buildings spec §6.2). Placed as a child of a ShelterBuilding in the editor.
##
## Entrants claim spots via ShelterBuilding.claim_spot():
##   - CIVILIANS claim plain spots DEEPEST-FIRST (nav-distance from their entry
##     door), in arrival order — this is what distributes bodies across rooms and
##     kills the doorway clump. Where this house huddles is authorial.
##   - ARMED humans claim GUARD spots first (is_guard), in SCENE ORDER — list the
##     most important guard position first. A guard spot should face a perimeter
##     door with interior LOS: the door-watch (§7.1, slice-1 step 5) fires from
##     here, using this node's rotation as the authored facing.
##   - Overflow shares the deepest spot with DetHash jitter — the huddle.
##
## Pure marker: no runtime behavior, editor-only visual. Claims live on the
## ShelterBuilding (one owner per mechanic).

## True = a GuardSpot (armed humans claim these first; the node's rotation is the
## authored door-facing for the step-5 door-watch). False = a plain shelter spot.
@export var is_guard: bool = false:
	set(value):
		is_guard = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


## Editor-only marker: cyan dot = shelter spot; orange dot + facing tick = guard.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if is_guard:
		draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.6, 0.15, 0.9))
		draw_line(Vector2.ZERO, Vector2(16, 0), Color(1.0, 0.6, 0.15, 0.9), 2.0)
	else:
		draw_circle(Vector2.ZERO, 6.0, Color(0.3, 0.85, 0.9, 0.9))
