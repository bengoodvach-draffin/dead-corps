@tool
extends Polygon2D
class_name HazardZone

## HazardZone — a mouse-drawn area hazard (fences/hazards spec §B6): barbed
## wire (SLOW) or a stake bed (IMPALE). A HazardZone IS a Polygon2D, so the
## point editor is live the moment you select it (the Wall pattern — add via
## Add Child Node → "HazardZone", not a scene instance).
##
## DUMB GEOMETRY + DATA (the ShelterSpot posture): the zone draws itself and
## answers questions (contains / factors / facing); it never ticks. All kills
## and every speed-factor write live in HazardField — one writer, one
## deterministic resolution for overlapping zones.
##
## TWO MODES (`toll_mode`):
##  - SLOW (barbed wire): kills nothing, slows BOTH teams by their factor
##    (ruling 8 — wire is a shared mire, not a prey shield). In NOBODY'S mesh
##    (nav_carve_layers → 0): everyone wades. Its real work is on the sacred
##    ratio — crossing time against the defender's fill clock: a wire band in
##    front of a gun position buys that gun free shots at a wading horde.
##  - IMPALE (stakes): ZOMBIES DIE — but only driving INTO the points (see the
##    directional rule below). HUMANS NEVER DIE — they weave through at
##    human_speed_factor, and that visible slow IS the readability (ruling 7:
##    no art required). Carved from the CAREFUL mesh only (nav_carve_layers →
##    2): the calm reserve routes around it; ferals and humans charge in.
##
## THE DIRECTIONAL RULE (ruling 6 + Ben's amendment 2026-08-03): the points aim
## along this node's local -Y (rotate the node to aim them — the drawn arrow is
## the authoring tell). A zombie dies when its velocity component AGAINST the
## points exceeds impale_min_speed:
##       velocity.dot(points_direction()) < -impale_min_speed
## Amended from the spec's "speed > min AND any against-component": BOID
## separation jitter could bend a safe with-the-points crossing a few degrees
## backward for one sample and phantom-kill it. The component form is immune —
## you die by how fast you drive onto the points. Stateless, deterministic.
## Falls out free: a stationary zombie in the bed is safe; shamblers (7px/s)
## can never die; crossing WITH the points is free — a one-way valve for the
## frenzy (commitment geometry, the ledge drop's best property without art).
## ALL zombie states qualify, mid-pounce excepted (§B6.4 — a lunge is
## ballistic and leaps the bed clean; contrast mines, which a lunge DOES
## trigger — pressure vs points).
##
## Mode and shape are AUTHOR-TIME properties: the careful-mesh carve bakes at
## boot and never re-bakes (§15 invariant), so don't flip toll_mode at runtime.

enum TollMode { SLOW, IMPALE }

## SLOW = barbed wire (slows, kills nothing). IMPALE = stakes (directional
## zombie kills, humans weave). Determines the careful-mesh carve at boot.
@export var toll_mode: TollMode = TollMode.SLOW:
	set(value):
		toll_mode = value
		_sync()

## Zombie speed multiplier inside a SLOW zone (1.0 = unaffected). Ignored by
## IMPALE — zombies crossing with the points move at full speed.
@export_range(0.05, 1.0, 0.05) var zombie_speed_factor: float = 0.4:
	set(value):
		zombie_speed_factor = value
		queue_redraw()

## Human speed multiplier inside the zone, both modes (1.0 = unaffected —
## "wire that doesn't slow humans" is this at 1.0, one field replaces a bool).
## v0: 0.4 for wire; drop to ~0.35 on stake beds (the weave reads slower).
@export_range(0.05, 1.0, 0.05) var human_speed_factor: float = 0.4:
	set(value):
		human_speed_factor = value
		queue_redraw()

## IMPALE only: the against-the-points speed (px/s) that kills. Below it the
## contact is a brush, not a charge. 20 keeps every idle jostle safe.
@export var impale_min_speed: float = 20.0

## The future power/objective hook (generator, §B13). An unarmed zone neither
## kills nor slows; it draws dimmed.
@export var armed: bool = true:
	set(value):
		armed = value
		_sync()

## Programmer-art fill colour.
@export var hazard_color: Color = Color(0.55, 0.35, 0.15, 1.0):
	set(value):
		hazard_color = value
		_sync()

## Bounding circle around the polygon (local space), computed on sync — the
## field's registry-query envelope before the exact containment test.
var _bound_centre: Vector2 = Vector2.ZERO
var _bound_radius: float = 0.0


func _ready() -> void:
	# A freshly-added zone gets a default box so it's visible and reshapeable.
	if polygon.is_empty():
		polygon = PackedVector2Array([
			Vector2(-80, -60), Vector2(80, -60),
			Vector2(80, 60), Vector2(-80, 60),
		])
	_sync()
	if Engine.is_editor_hint():
		return
	# One-time wiring: HazardField finds every hazard here on its first tick.
	add_to_group("hazards")


func _process(_delta: float) -> void:
	# In the editor, keep visuals + the bounding circle following dragged points.
	if Engine.is_editor_hint():
		_sync()


func _sync() -> void:
	var fill := hazard_color
	fill.a = 0.30 if toll_mode == TollMode.SLOW else 0.38
	if not armed:
		fill.a *= 0.4
	color = fill
	# Bounding circle: centroid + max vertex reach, padded a body radius so the
	# registry query can never miss a unit whose centre is inside the polygon.
	if polygon.size() > 0:
		var c := Vector2.ZERO
		for p in polygon:
			c += p
		c /= float(polygon.size())
		var r := 0.0
		for p in polygon:
			r = maxf(r, c.distance_to(p))
		_bound_centre = c
		_bound_radius = r + 16.0
	queue_redraw()


# === THE FIELD'S QUESTIONS (HazardField owns all consequences) ===

func is_active() -> bool:
	return armed


## Exact containment test, global space.
func contains(global_pos: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(global_pos), polygon)


## Registry-query envelope (global).
func query_centre() -> Vector2:
	return to_global(_bound_centre)


func bounding_reach() -> float:
	return _bound_radius * maxf(absf(global_scale.x), absf(global_scale.y))


## The GLOBAL direction the stakes aim — this node's local -Y, rotated with it.
func points_direction() -> Vector2:
	return (-global_transform.y).normalized()


# === NAVMESH (fences/hazards spec §B3.1 carve protocol) ===

## IMPALE carves the CAREFUL mesh only (bit 2) — the calm reserve routes
## around what would kill it. SLOW carves nothing — everyone wades.
func nav_carve_layers() -> int:
	return 2 if toll_mode == TollMode.IMPALE else 0


## The drawn polygon, global space, for NavBaker (filtered by the bits above).
func get_nav_footprint() -> Dictionary:
	var pts := PackedVector2Array()
	for p in polygon:
		pts.append(global_transform * p)
	return {"obstruction": [pts], "traversable": []}


# === VISUALS (interim programmer graphics — Phase 5 moves these to vision_renderer) ===

func _draw() -> void:
	var ink := hazard_color.darkened(0.35)
	ink.a = 1.0 if armed else 0.4
	if toll_mode == TollMode.IMPALE:
		# The facing arrow — REQUIRED (§B6.2: without it the zone is
		# unauthorable). Local -Y is where the points aim.
		var tip := _bound_centre + Vector2(0, -36)
		draw_line(_bound_centre + Vector2(0, 24), tip, ink, 3.0)
		draw_line(tip, tip + Vector2(-9, 12), ink, 3.0)
		draw_line(tip, tip + Vector2(9, 12), ink, 3.0)
		# Chevron ranks echoing the points across the bed.
		for row in [-1, 1]:
			var base := _bound_centre + Vector2(28.0 * row, 8.0)
			for i in 3:
				var o := base + Vector2(-12.0 + 12.0 * i, 0)
				draw_line(o + Vector2(-5, 6), o, ink, 2.0)
				draw_line(o, o + Vector2(5, 6), ink, 2.0)
	else:
		# Barbed wire: two sagging strands with barb ticks, centroid-anchored.
		for row in 2:
			var y := -8.0 + 16.0 * row
			var a := _bound_centre + Vector2(-30, y)
			var b := _bound_centre + Vector2(30, y)
			draw_line(a, b, ink, 2.0)
			for i in 4:
				var x := a.lerp(b, 0.125 + 0.25 * i)
				draw_line(x + Vector2(-3, -3), x + Vector2(3, 3), ink, 1.5)
				draw_line(x + Vector2(-3, 3), x + Vector2(3, -3), ink, 1.5)
