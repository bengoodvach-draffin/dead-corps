extends Node2D
class_name VisionRenderer

## STUB — demolition step 1.6 (pulled forward to pair with the human.gd rewrite,
## step 1.1, which removed the vision members this used to read).
##
## The v1 renderer drew the stealth-era vision system: per-human vision cones /
## arcs / dual zones, facing lines, click-to-pin cone inspection, and the V-key
## "all cones" debug mode. All of that is deleted by the pivot (V2_DIRECTION_SPEC
## §11) — detection is no longer a fail state, so there are no cones to show.
##
## This node is kept (it is still present in the level scenes) but inert, so the
## scenes load without referencing removed Human members. It is rebuilt as the
## v2 readability layer — advancing fill lines, calm/feral tint, riser and cower
## indicators — in build-plan steps 3.1 / 5.1.
##
## Intentionally has no _input/_process/_draw: left-clicks now fall through to
## SelectionManager (humans aren't player-selectable, so this is a no-op), and
## there is nothing to draw until the readability layer is built.

func _ready() -> void:
	# Match the old world-space setup so the future readability layer can draw in
	# world coordinates directly without a transform surprise.
	z_index = 1
	top_level = true
	global_position = Vector2.ZERO
