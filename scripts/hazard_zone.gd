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
## THE DIRECTIONAL RULE (ruling 6 + Ben's amendments 2026-08-03 / 2026-08-06):
## the points aim along this node's local -Y (rotate the node to aim them — the
## drawn arrow is the authoring tell). A zombie dies when its velocity component
## AGAINST the points exceeds impale_min_speed AND its heading is predominantly
## INTO the points (against-component > impale_kill_dot × its speed):
##       against > impale_min_speed  and  against > kill_dot × |velocity|
## First amendment (03): component form, not "speed > min AND any against-
## component" — BOID jitter could bend a safe crossing a few degrees backward
## for one sample and phantom-kill it. Second (06): the angle gate — component-
## only made ~half of all headings lethal inside the bed (anything ~8° past
## perpendicular at walk speed), so a zombie that entered safely couldn't move
## without dying. Now only genuinely charging the points kills. Stateless,
## deterministic.
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

## Mode-default palette (Ben, 2026-08-06) — traffic-light readability: amber =
## slows everyone (caution), red = kills zombies (lethal to YOUR units). A zone
## whose hazard_color is still one of these defaults follows its mode (flipping
## toll_mode re-colours it live); any custom colour a level set is respected.
## The old shared brown is recognised as "never customised" too.
const DEFAULT_LEGACY := Color(0.55, 0.35, 0.15, 1.0)
const DEFAULT_WIRE := Color(0.85, 0.62, 0.15, 1.0)
const DEFAULT_STAKES := Color(0.78, 0.18, 0.14, 1.0)

## SLOW = barbed wire (slows, kills nothing). IMPALE = stakes (directional
## zombie kills, humans weave). Determines the careful-mesh carve at boot.
@export var toll_mode: TollMode = TollMode.SLOW:
	set(value):
		toll_mode = value
		_apply_mode_default_color()
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

## IMPALE only — the ANGLE gate (Ben, 2026-08-06): kill only when the heading is
## predominantly INTO the points — against-component > this fraction of the
## zombie's own speed. 0.7 ≈ within ~45° of dead-into. Before this gate the safe
## cone was ~8° past perpendicular (any heading with >20px/s backward component
## died at full walk speed), so a zombie inside the bed could barely move without
## dying. 0 restores the old component-only rule.
@export_range(0.0, 1.0, 0.05) var impale_kill_dot: float = 0.7

## The future power/objective hook (generator, §B13). An unarmed zone neither
## kills nor slows; it draws dimmed.
@export var armed: bool = true:
	set(value):
		armed = value
		_sync()

## Programmer-art fill colour. Left untouched it follows the mode default
## (amber wire / red stakes); set it explicitly to override per zone.
@export var hazard_color: Color = DEFAULT_WIRE:
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
	_apply_mode_default_color()
	_sync()
	if Engine.is_editor_hint():
		return
	# One-time wiring: HazardField finds every hazard here on its first tick.
	add_to_group("hazards")


func _process(_delta: float) -> void:
	# In the editor, keep visuals + the bounding circle following dragged points.
	if Engine.is_editor_hint():
		_sync()


## A hazard_color that is still one of the three defaults counts as "never
## customised" and snaps to the current mode's colour. A designer's explicit
## colour never matches a default exactly (unless they deliberately pick one, in
## which case following the mode is exactly what that colour means).
func _apply_mode_default_color() -> void:
	if hazard_color == DEFAULT_LEGACY or hazard_color == DEFAULT_WIRE \
			or hazard_color == DEFAULT_STAKES:
		hazard_color = DEFAULT_STAKES if toll_mode == TollMode.IMPALE else DEFAULT_WIRE


func _sync() -> void:
	# Contrast swap (Ben, 2026-08-06): the FILL takes the dark ink shade the
	# pattern used to be drawn in, and the pattern is drawn near-white on top —
	# light-on-dark reads far better than dark-on-light-of-the-same-hue.
	var fill := hazard_color.darkened(0.35)
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

## Glyph-tile spacing (local px). Chosen so the pattern reads at gameplay zoom
## without carpeting a big zone in thousands of draws.
const TILE_X := 26.0
const TILE_Y := 22.0

## Pattern colour: light grey, not the zone hue — the hue lives in the fill
## now; the glyphs' job is contrast without glare.
const PATTERN_INK := Color(0.78, 0.78, 0.75)

func _draw() -> void:
	var ink := PATTERN_INK
	ink.a = 1.0 if armed else 0.4
	if polygon.size() < 3:
		return
	# Crisp boundary — the polygon edge is the gameplay line, so draw it exactly
	# rather than leaving it to the soft alpha fill.
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, ink, 2.0)
	# Symbols TILE THE WHOLE ZONE (Ben, 2026-08-06 — the old centroid doodle
	# vanished on any decently sized polygon): a local-space grid over the
	# bounding box, drawing each glyph whose centre lies inside the polygon.
	# Local space, so stake chevrons rotate with the node and always agree with
	# the facing arrow (both are "local -Y is the kill direction").
	var bounds := _polygon_bounds()
	if toll_mode == TollMode.IMPALE:
		_draw_stake_glyphs(bounds, ink)
		_draw_facing_arrow(ink)
	else:
		_draw_wire_glyphs(bounds, ink)


## Stakes: quincunx ranks of chevrons pointing the kill direction (local -Y).
func _draw_stake_glyphs(bounds: Rect2, ink: Color) -> void:
	var row := 0
	var y := bounds.position.y + TILE_Y * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + TILE_X * 0.5 + (TILE_X * 0.5 if row % 2 == 1 else 0.0)
		while x < bounds.end.x:
			var o := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(o, polygon):
				_draw_clipped_line(o + Vector2(-6, 5), o + Vector2(0, -5), ink, 2.0)
				_draw_clipped_line(o + Vector2(0, -5), o + Vector2(6, 5), ink, 2.0)
			x += TILE_X
		y += TILE_Y
		row += 1


## Barbed wire: horizontal strand segments with an X barb at each tile centre —
## adjacent inside tiles connect into continuous strands across the zone.
func _draw_wire_glyphs(bounds: Rect2, ink: Color) -> void:
	var y := bounds.position.y + TILE_Y * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + TILE_X * 0.5
		while x < bounds.end.x:
			var o := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(o, polygon):
				_draw_clipped_line(o + Vector2(-TILE_X * 0.5, 0), o + Vector2(TILE_X * 0.5, 0), ink, 1.5)
				_draw_clipped_line(o + Vector2(-4, -4), o + Vector2(4, 4), ink, 2.0)
				_draw_clipped_line(o + Vector2(-4, 4), o + Vector2(4, -4), ink, 2.0)
			x += TILE_X
		y += TILE_Y


## Draws the a→b stroke TRIMMED to the polygon (Ben, 2026-08-06 — a glyph whose
## centre is inside can still poke its ends over the boundary). Interior strokes
## come back as a single unchanged piece; edge strokes are cut exactly at the
## outline. Redraw-time only, so the clip cost never touches the sim tick.
func _draw_clipped_line(a: Vector2, b: Vector2, ink: Color, width: float) -> void:
	var pieces := Geometry2D.intersect_polyline_with_polygon(
		PackedVector2Array([a, b]), polygon)
	for piece in pieces:
		if piece.size() >= 2:
			draw_polyline(piece, ink, width)


## The facing arrow — REQUIRED (§B6.2: without it the zone is unauthorable).
## Local -Y is where the points aim. Bolder than the glyphs so it stays the
## authoring tell on top of the tiled pattern.
func _draw_facing_arrow(ink: Color) -> void:
	var tip := _bound_centre + Vector2(0, -44)
	draw_line(_bound_centre + Vector2(0, 32), tip, ink, 4.0)
	draw_line(tip, tip + Vector2(-12, 15), ink, 4.0)
	draw_line(tip, tip + Vector2(12, 15), ink, 4.0)


## Axis-aligned local-space bounding box of the polygon.
func _polygon_bounds() -> Rect2:
	var r := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		r = r.expand(p)
	return r
