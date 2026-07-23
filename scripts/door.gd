@tool
extends Node2D
class_name Door

## Door — the only opening in a ShelterBuilding's perimeter (buildings spec §4).
##
## Place one as a CHILD of a ShelterBuilding and drop it roughly on the outline:
## the parent snaps it onto the nearest perimeter edge (position + rotation) and
## opens a door_width gap in the generated walls there. Dragging a Door in the
## editor slides it along the perimeter. The node's local X axis runs along the
## door segment. A Door can also stand alone in a hand-built wall gap — it just
## won't snap or carve anything (the barriers still work at its transform).
##
## STEP-1 SCOPE (build order per V2_ENTERABLE_BUILDINGS_SPEC §15): the always-on
## barrier pair only, both runtime-built hidden StaticBody2Ds:
##   - ZOMBIE BARRIER on layer 4 "EscapeBarrier" (escape_zone.gd pattern
##     verbatim): zombies (mask 9) physically slide off it; humans (mask 1) pass
##     straight through. An intact door NEVER admits a zombie (§4.1).
##   - LOS BLOCKER on layer 5 "DoorLOS": an intact door is a wall to every sight
##     check (§7.1 — no LOS through it until breach): fill lanes, fear counts,
##     feral scans. No unit's movement mask includes bit 16, so it blocks rays
##     only, never bodies.
## Not built yet (later slice-1 steps): the lock (§4.2), integrity/pounding
## (§4.3), the engagement arc, the integrity bar (§4.4). Breach will free both
## barrier bodies.

## Width of the doorway gap in pixels — a first-class per-door level-design knob
## (spec §4.3): sets siege throughput, post-breach entry serialization, flush
## drain rate, and doorway ambushability.
@export_range(16.0, 400.0, 1.0) var door_width: float = 48.0:
	set(value):
		door_width = value
		queue_redraw()

## Placeholder door graphic colour (programmer art until the boards-on-door pass).
@export var door_color: Color = Color(0.55, 0.38, 0.15, 1.0):
	set(value):
		door_color = value
		queue_redraw()

## Wall thickness the door spans — pushed in by the parent ShelterBuilding so the
## visual and barriers match the generated walls. Read from the parent (duck-typed,
## no ShelterBuilding type reference → no class-load cycle) before the barriers build.
var thickness: float = 16.0

var _zombie_barrier: StaticBody2D = null
var _los_blocker: StaticBody2D = null


func _ready() -> void:
	_read_parent_thickness()
	queue_redraw()
	# Editor: visual only — never build barrier bodies (CLAUDE.md @tool rule).
	if Engine.is_editor_hint():
		return
	_create_barriers()


## Matches the parent building's wall thickness if there is one (exports are set
## before _ready, so this is safe regardless of ready order).
func _read_parent_thickness() -> void:
	var parent := get_parent()
	if parent != null and parent.get("wall_thickness") != null:
		thickness = parent.wall_thickness


## Builds both runtime-only barrier bodies across the doorway. Each extends half
## a wall-thickness past the gap at both ends, overlapping into the wall quads so
## the seams can never leave a hairline crack.
func _create_barriers() -> void:
	_zombie_barrier = _make_barrier("ZombieBarrier", 8)   # layer 4 "EscapeBarrier"
	_los_blocker = _make_barrier("DoorLOSBlocker", 16)    # layer 5 "DoorLOS"


func _make_barrier(body_name: String, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0   # the barrier itself collides with nothing
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(door_width + thickness, thickness)
	shape_node.shape = rect
	body.add_child(shape_node)
	add_child(body)
	return body


func _draw() -> void:
	# Placeholder: the door leaf as a flat rect spanning the gap.
	draw_rect(Rect2(-door_width * 0.5, -thickness * 0.5, door_width, thickness), door_color)
