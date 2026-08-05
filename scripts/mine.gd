@tool
extends Node2D
class_name Mine

## Mine — a hand-placed 1:1 point hazard (fences/hazards spec §B5): one mine
## kills exactly one body, then it is SPENT, permanently. The node is never
## freed — it persists as an inert crater, which is what makes a paid-for lane
## through a field legible for the rest of the level (the corpse-road principle,
## ruling 5: zombie corpses despawn, so the road is marked by craters).
##
## DUMB GEOMETRY + DATA (the ShelterSpot posture): a mine draws itself and
## answers questions; it never ticks. ALL detonation logic — the sweep cadence,
## victim choice, the kill — lives in HazardField (§B7), because overlapping
## hazards need one deterministic resolver.
##
## Mines are in NOBODY'S navmesh (no get_nav_footprint, no nav_carve_layers):
## they're buried, so nothing routes around them — calm crew included. THE
## PLAYER IS THE ONLY ONE WHO KNOWS (§B5.1): routing around a field is a player
## decision, which is why the armed marker must always be readable (§B2 — a
## hazard hidden from the PLAYER would be a pillar violation).
##
## Spacing is the design language (§B5): a dense line is a wall priced in
## bodies, a loose scatter is a tax, a deliberate gap is a lane. Authored per
## field, never a config knob.

## Bodies (centre) within this radius on a field sweep can trigger the mine.
## ≈ one body. The 0.1s sweep moves a zombie 14px per sample, so the middle of
## the circle cannot be skipped; grazing the rim between samples can miss —
## accepted (§B8): a free graze is never an unfair death.
@export_range(4.0, 64.0, 1.0) var trigger_radius: float = 14.0:
	set(value):
		trigger_radius = value
		queue_redraw()

## Off (default): humans never trigger mines — prey blunders across your field
## for free. On (§B5.2): a human that steps in dies UNSCORED, produces NO riser,
## and CONSUMES the mine — the garrison clears your path for you. A deliberate
## per-level design choice, not something that should happen by default.
@export var affects_humans: bool = false:
	set(value):
		affects_humans = value
		queue_redraw()

## The future power/objective hook (§B13 — the generator). Unread beyond the
## field skipping unarmed mines; no disarm mechanic exists yet.
@export var armed: bool = true:
	set(value):
		armed = value
		queue_redraw()

## Programmer-art marker colour.
@export var mine_color: Color = Color(0.55, 0.12, 0.08, 1.0):
	set(value):
		mine_color = value
		queue_redraw()

## Spent = detonated. Permanent; the node stays as the crater graphic.
var _spent: bool = false


func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	# One-time wiring: HazardField finds every hazard here on its first tick.
	add_to_group("hazards")


## True while this mine can still detonate — the field skips everything else.
func is_live() -> bool:
	return armed and not _spent


func is_spent() -> bool:
	return _spent


## Called by HazardField at detonation, BEFORE the kill lands, so nothing a
## death cascades into can re-trigger this mine in the same sweep.
func spend() -> void:
	_spent = true
	queue_redraw()


func _draw() -> void:
	if _spent:
		# The crater: a scorched patch the size of the old trigger circle with a
		# darker core — unmistakably used, permanently visible (the paid road).
		draw_circle(Vector2.ZERO, trigger_radius * 0.9, Color(0.16, 0.13, 0.10, 0.9))
		draw_circle(Vector2.ZERO, trigger_radius * 0.45, Color(0.08, 0.07, 0.05, 1.0))
		return
	# Armed: the core dot + the TRUE trigger radius as a ring — the planning
	# information (§B2: fully visible to the player, always). An unarmed mine
	# (generator hook, slice 3) draws dimmed.
	var col := mine_color if armed else Color(mine_color, 0.35)
	draw_circle(Vector2.ZERO, 4.5, col)
	draw_arc(Vector2.ZERO, trigger_radius, 0.0, TAU, 24, Color(col, 0.55), 1.5)
	# Prongs: three short detonator spikes so the marker reads "mine", not "dot".
	for i in 3:
		var a := TAU * float(i) / 3.0 - TAU * 0.25
		draw_line(Vector2.from_angle(a) * 4.0, Vector2.from_angle(a) * 8.0, col, 1.5)
