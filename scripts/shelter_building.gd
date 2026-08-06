@tool  # Walls, collision and door snapping follow the points you drag in the editor
extends Polygon2D
class_name ShelterBuilding

## ShelterBuilding — an enterable building humans can flee INTO (buildings spec §3).
##
## The node IS a Polygon2D: draw any closed footprint shape with the mouse (like
## Wall) and the perimeter walls GENERATE themselves along the edges — thick solid
## quads with collision (layer 1 "Environment", group "buildings" → blocks
## movement AND line of sight) and nav carving (group "nav_obstacle", quads only,
## so the interior stays walkable). Add one with Add Child Node → "ShelterBuilding"
## (not a scene instance), same as Wall.
##
## DOORS: add Door child nodes and drop them near the outline — they snap onto
## the nearest perimeter edge and open a door_width gap in the generated walls.
## The navmesh bakes with every doorway OPEN from the start (spec §15): doors
## close via the Door's physics barriers only, so breach never re-bakes nav.
##
## INTERIOR: the polygon fill is the visible floor — interiors are always visible
## to the player, no roofs, no fog (§10). Interior room walls are ordinary solid
## Wall nodes placed inside the footprint; interior doorways are plain gaps
## between them (no interior door mechanics in v1, §3).
##
## OCCUPANCY + SPOTS (step 2, spec §6): this node owns the shelter claims — one
## owner per mechanic. Fleeing humans entering a door call claim_spot(); armed
## entrants take GuardSpots in authored scene order, civilians take ShelterSpots
## deepest-first (nav-distance from their entry door), overflow shares the
## deepest spot with DetHash jitter (the huddle). Unbounded capacity (§6.2).
## Still to come: breach state (step 3), exit-set churn (step 4).

## FALSE = a "dumb box" (terrain kit, Ben's ruling 2026-07-26): identical walls,
## doors and nav — but its doors never join the flee exit set and crossing them
## shelters nobody. Plain boxed terrain with convenient gaps.
@export var is_shelter: bool = true

## Colour of the generated perimeter walls.
@export var wall_color: Color = Color(0.4, 0.4, 0.4, 1):
	set(value):
		wall_color = value
		_sync()

## Faint interior floor fill (kept translucent — the interior must stay readable).
@export var floor_color: Color = Color(0.16, 0.16, 0.2, 0.4):
	set(value):
		floor_color = value
		_sync()

## Thickness of the generated perimeter walls, in pixels.
@export_range(2, 100, 1) var wall_thickness: float = 16.0:
	set(value):
		wall_thickness = value
		_sync()

# === GENERATED INTERNAL CHILDREN (not serialized) ===

var _body: StaticBody2D
var _cols: Array = []          ## pooled CollisionPolygon2D, one per wall quad
var _wall_quads: Array = []    ## Array[PackedVector2Array], local space

## Occupancy (step 2, §6): sheltered humans, and which human claims which spot.
## Overflow entrants share the deepest spot without a claim entry.
var _occupants: Array = []
var _spot_claims: Dictionary = {}   ## ShelterSpot -> the claiming human
var _warned_no_spots: bool = false

## DetHash salt + spread (px) for the overflow huddle around the deepest spot (§6.2).
const OVERFLOW_SALT := 7301
const OVERFLOW_SPREAD := 22.0

## OVERFLOW FAN-OUT (Ben's ruling 2026-07-30). Entrants past the authored spots
## used to all target the SAME deepest spot with only a ±22px jitter, so a dozen
## arrivals read as one blob shoving at a single point. They now land on a
## phyllotaxis spiral around that anchor: even spacing, nobody sharing a point,
## and the pattern grows outward on its own as more arrive.
##
## Deterministic (§10): the index is claim order — humans tick in registry order,
## so it's stable — and the organic wobble is DetHash, not RNG. Note this is a
## POSITION spread, not physics: sheltered humans run no BOID separation (the
## SHELTERED branch doesn't call super), so the spacing has to be authored into
## the target itself rather than emerge from jostling.
const OVERFLOW_SPACING := 26.0   ## ≈ a body's width between neighbours
const GOLDEN_ANGLE := 2.39996323
const OVERFLOW_WOBBLE := 4.0     ## small per-unit offset so the spiral isn't robotic

## How many entrants have overflowed here. Monotonic; gaps from deaths are
## harmless (the pattern just keeps growing outward).
var _overflow_index: int = 0


func _ready() -> void:
	# Give a freshly-added building a default footprint so it's visible and reshapeable.
	if polygon.is_empty():
		polygon = PackedVector2Array([
			Vector2(-150, -100), Vector2(150, -100),
			Vector2(150, 100), Vector2(-150, 100),
		])
	# NavBaker carves the wall quads (not the footprint) out of the mesh.
	add_to_group("nav_obstacle")
	if not Engine.is_editor_hint():
		add_to_group("shelter_buildings")
	_sync()


func _process(_delta: float) -> void:
	# In the editor, keep walls + collision + door snapping live while you drag.
	if Engine.is_editor_hint():
		_sync()


## The Door children, in scene order (deterministic — add order is saved).
func doors() -> Array:
	var result := []
	for child in get_children():
		if child is Door:
			result.append(child)
	return result


# === OCCUPANCY + SPOT CLAIMS (step 2, spec §6.2) ===

## True while at least one living human shelters here. Release-at-the-building
## targeting (step 3) and slice 2's armory both key off this.
func is_occupied() -> bool:
	for h in _occupants:
		if is_instance_valid(h) and h.is_alive:
			return true
	return false


## True once ANY door is breached — the whole building leaves the flee exit set
## permanently (§9: a hole in the wall is not shelter) and its sheltered
## occupants become valid prey again (§5.2: room-by-room hunting).
func is_breached() -> bool:
	for door: Door in doors():
		if door.is_breached():
			return true
	return false


## THE COMPROMISED RULE (specials spec §3.5): true while a REVEALED living
## zombie stands inside this intact building's footprint — the wolf in the
## fold. Occupants then run breached-interior rules (fear sight-gated and
## uncapped, fill against interior threats, breakers flush out) while the
## physical shell — barriers, door integrity, adoption — stays intact; and the
## building drops out of the flee exit set (§9.3 soft default). A merely
## COSTUMED infiltrator compromises nothing: infiltrate early, wait, reveal at
## the moment of maximum harvest.
##
## Memoized per sim_tick: callers hit this per-human on scan cadences, and one
## registry sweep per building per tick is plenty (deterministic — same tick,
## same answer).
var _compromised_memo_tick: int = -1
var _compromised_memo: bool = false

func is_compromised() -> bool:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return false
	if int(gm.sim_tick) == _compromised_memo_tick:
		return _compromised_memo
	_compromised_memo_tick = int(gm.sim_tick)
	_compromised_memo = false
	if polygon.is_empty() or is_breached():
		return false   # a breached building is past "compromised" — the real rules apply
	# Bounding-circle registry query, then the exact footprint test.
	var c := _footprint_centre()
	var reach := 0.0
	for p in polygon:
		reach = maxf(reach, c.distance_to(global_transform * p))
	for u in gm.neighbours_within(c, reach + 16.0, &"zombies"):
		if u.is_alive and not u.is_perception_hidden() and contains_point(u.global_position):
			_compromised_memo = true
			break
	return _compromised_memo


## True if `point` (global) is inside the drawn footprint — the release-at-the-
## building click test (step 3).
func contains_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(point), polygon)


## Release telegraph (step 3): white footprint outline while the cursor hovers an
## occupied building with releasable zombies selected — same misclick defense as
## the release-on-human ring. Toggled by SelectionManager.
var _hover_highlighted: bool = false

func set_hover_highlighted(value: bool) -> void:
	if _hover_highlighted == value:
		return
	_hover_highlighted = value
	queue_redraw()


## Registers `human` as an occupant and returns the global position it should hold.
## Armed → first free GuardSpot in authored scene order; civilians (and armed with
## no free GuardSpot) → free ShelterSpots deepest-first from `entry_door`;
## overflow → the deepest spot + DetHash jitter (the huddle). Deterministic:
## arrival order is claim order (humans tick in registry order), scene order and
## nav distances are fixed. `human` is dynamically typed — no Human class
## dependency in this script.
func claim_spot(human: Node2D, entry_door: Node2D) -> Vector2:
	add_occupant(human)

	var door_pos: Vector2 = entry_door.global_position if entry_door != null else global_position

	if human.is_armed():
		for spot in _spots(true):
			if _spot_free(spot):
				_spot_claims[spot] = human
				return spot.global_position

	var shelter_sorted := _shelter_spots_deepest_first(door_pos)
	for spot in shelter_sorted:
		if _spot_free(spot):
			_spot_claims[spot] = human
			return spot.global_position

	# Overflow (§6.2): fan out around the deepest spot rather than piling on it.
	var pool: Array = shelter_sorted if not shelter_sorted.is_empty() else _spots(true)
	if not pool.is_empty():
		return _overflow_position(pool[0].global_position, human)

	# No spots authored at all — fan out from the footprint centre so entrants
	# still clear the doorway. Authored markers remain the intended setup (§6.2)
	# for controlling exactly where people stand.
	if not _warned_no_spots:
		_warned_no_spots = true
		push_warning("ShelterBuilding '%s' has no ShelterSpot children — entrants fan out from the centre." % name)
	return _overflow_position(_footprint_centre(), human)


## The next fan-out position around `anchor`. See the OVERFLOW_* constants: a
## phyllotaxis spiral (radius ∝ √n, golden-angle turns) gives even coverage with
## no clumping, plus a small DetHash wobble so a packed room doesn't look like a
## sunflower diagram. 1-based so the first overflow entrant clears the anchor
## itself, which whoever claimed that spot is already standing on.
func _overflow_position(anchor: Vector2, human: Node2D) -> Vector2:
	_overflow_index += 1
	var n := float(_overflow_index)
	# NOT named `offset` — that shadows Polygon2D.offset on this node.
	var spiral := Vector2(cos(n * GOLDEN_ANGLE), sin(n * GOLDEN_ANGLE)) * (OVERFLOW_SPACING * sqrt(n))
	return anchor + spiral + DetHash.offset(human.unit_uid, OVERFLOW_SALT, OVERFLOW_WOBBLE)


## Registers `human` as an occupant WITHOUT assigning it a position — the boot
## adoption path (Ben's ruling 2026-07-30). A hand-placed resident holds exactly
## where the designer put it: the level author has already decided where these
## people stand, and making them all walk to authored ShelterSpots meant placing
## a spot per human across dozens of them. Occupancy still matters (every siege /
## flush / pour-in / win check keys off it) — only the spot claim is skipped, so
## the authored spots stay free for humans who genuinely flee in later.
func add_occupant(human: Node2D) -> void:
	if _occupants.has(human):
		return
	_occupants.append(human)
	# Signals up: free the claim + occupancy when the occupant dies.
	if human.has_signal("human_died") and not human.human_died.is_connected(_on_occupant_died):
		human.human_died.connect(_on_occupant_died)


## Living occupants, in arrival order (deterministic). Read by besiegers at
## breach — the pour-in ruling (2026-07-23): a besieger with no other prey takes
## the nearest occupant, no LOS gate.
func living_occupants() -> Array:
	var result := []
	for h in _occupants:
		if is_instance_valid(h) and h.is_alive:
			result.append(h)
	return result


## Frees a human's claim + occupancy (death now; the breach-flush in step 6).
func release_occupant(human: Node2D) -> void:
	_occupants.erase(human)
	for spot in _spot_claims.keys():
		if _spot_claims[spot] == human:
			_spot_claims.erase(spot)
			break


func _on_occupant_died(human: Node2D) -> void:
	release_occupant(human)


## A spot is free if unclaimed, or its claimant is gone/dead (claims outlive
## nothing — a dead occupant's spot re-opens for later entrants).
func _spot_free(spot: Node2D) -> bool:
	if not _spot_claims.has(spot):
		return true
	var claimant = _spot_claims[spot]
	return not is_instance_valid(claimant) or not claimant.is_alive


## Spot children of one kind, in scene order (guard claiming order is authored).
func _spots(guard: bool) -> Array:
	var result := []
	for child in get_children():
		if child is ShelterSpot and child.is_guard == guard:
			result.append(child)
	return result


## Plain shelter spots sorted deepest-first: nav-distance from the entry door,
## descending; scene order breaks ties. Recomputed per claim (few spots, and the
## ordering depends on which door the entrant used).
func _shelter_spots_deepest_first(door_pos: Vector2) -> Array:
	var entries := []
	var index := 0
	for spot in _spots(false):
		entries.append({"spot": spot, "dist": _nav_distance(door_pos, spot.global_position), "order": index})
		index += 1
	entries.sort_custom(func(a, b):
		if a.dist != b.dist:
			return a.dist > b.dist
		return a.order < b.order)
	var result := []
	for e in entries:
		result.append(e.spot)
	return result


## Nav-path length between two global points (spec §6.2 "deepest" is nav-distance,
## so interior walls count). Falls back to straight-line if no path resolves.
func _nav_distance(from_pos: Vector2, to_pos: Vector2) -> float:
	var map := get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(map, from_pos, to_pos, true)
	if path.size() < 2:
		return from_pos.distance_to(to_pos)
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total


## Global centre of the footprint (public — Door.inside_point() uses it to know
## which side of the wall band is "inside").
func centre() -> Vector2:
	return _footprint_centre()


## Average of the footprint's points, in global space (the no-spots fallback).
func _footprint_centre() -> Vector2:
	if polygon.is_empty():
		return global_position
	var sum := Vector2.ZERO
	for p in polygon:
		sum += p
	return global_transform * (sum / polygon.size())


## Rebuilds everything from the current polygon + doors.
func _sync() -> void:
	if not is_inside_tree():
		return
	_normalize_scale()
	color = floor_color   # the Polygon2D's own fill = the visible floor (§10)
	_ensure_body()
	_snap_doors()
	_build_wall_quads()
	_apply_collision()
	queue_redraw()


## Folds any node-level scale INTO the polygon (and door/spot children), then
## resets scale to 1:1 — self-healing. The editor's scale gizmo would otherwise
## stretch the generated wall THICKNESS non-uniformly and distort every piece of
## door math (barrier sizes, arcs, entry margins) that assumes unscaled locals.
## The footprint keeps the size the designer dragged; the walls keep their true
## thickness. Runs in _sync, so saved scaled scenes heal on open/load too.
func _normalize_scale() -> void:
	if scale.is_equal_approx(Vector2.ONE):
		return
	if absf(scale.x) < 0.001 or absf(scale.y) < 0.001:
		push_warning("ShelterBuilding '%s': degenerate scale %s reset (fold skipped)." % [name, scale])
		scale = Vector2.ONE
		return
	var s := scale
	var pts := polygon
	for i in pts.size():
		pts[i] = pts[i] * s
	# A mirrored (negative) scale flips the winding — the nav merge treats
	# clockwise outlines as holes, so restore counter-clockwise.
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	polygon = pts
	for child in get_children():
		if child is Node2D:
			child.position = child.position * s
	scale = Vector2.ONE


## Creates (or refinds after a reload) the internal collision body.
func _ensure_body() -> void:
	if _body == null or not is_instance_valid(_body):
		_body = _find_internal(self, "_ShelterWallBody") as StaticBody2D
		if _body == null:
			_body = StaticBody2D.new()
			_body.name = "_ShelterWallBody"
			_body.collision_layer = 1   # "Environment" — blocks movement + LOS raycasts
			_body.collision_mask = 0
			add_child(_body, false, Node.INTERNAL_MODE_FRONT)
		if not _body.is_in_group("buildings"):
			_body.add_to_group("buildings")
		# Re-adopt the collision pool after a script hot-reload.
		_cols.clear()
		for child in _body.get_children(true):
			if child is CollisionPolygon2D:
				_cols.append(child)


## Finds an existing internal child by name (survives script hot-reload).
func _find_internal(parent: Node, child_name: String) -> Node:
	for child in parent.get_children(true):
		if child.name == child_name:
			return child
	return null


## Snaps every Door child onto the nearest perimeter edge: position onto the edge,
## rotation along it. Dragging a Door in the editor slides it around the outline.
func _snap_doors() -> void:
	if polygon.size() < 3:
		return
	for door: Door in doors():
		var best_dist := INF
		var best_point := Vector2.ZERO
		var best_angle := 0.0
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if a.distance_to(b) < 0.001:
				continue
			var p := Geometry2D.get_closest_point_to_segment(door.position, a, b)
			var d := door.position.distance_to(p)
			if d < best_dist:
				best_dist = d
				best_point = p
				best_angle = (b - a).angle()
		if best_dist == INF:
			continue
		# Only write when meaningfully different, so the editor scene isn't dirtied
		# every frame just by having the node selected.
		if door.position.distance_to(best_point) > 0.01:
			door.position = best_point
		if absf(angle_difference(door.rotation, best_angle)) > 0.001:
			door.rotation = best_angle
		if absf(door.thickness - wall_thickness) > 0.001:
			door.thickness = wall_thickness
			door.queue_redraw()


## Builds one thickened quad per wall run: each polygon edge, minus the door gaps
## snapped onto it. Corner ends extend by half-thickness so adjacent edges overlap
## and fill the corner (wall.gd pattern); door-cut ends do NOT extend, keeping the
## gap exactly door_width wide (the Door's barriers overlap the seam instead).
func _build_wall_quads() -> void:
	_wall_quads.clear()
	var count := polygon.size()
	if count < 3:
		return
	var half := wall_thickness * 0.5
	var door_list := doors()
	for i in count:
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		var edge := b - a
		var edge_len := edge.length()
		if edge_len < 0.001:
			continue
		var dir := edge / edge_len

		# Door gaps on this edge, as [start, end] spans along it. A snapped door
		# sits ON its edge, so membership is a near-zero distance test.
		var cuts: Array = []
		for door: Door in door_list:
			var p := Geometry2D.get_closest_point_to_segment(door.position, a, b)
			if p.distance_to(door.position) > 0.5:
				continue
			var t := (door.position - a).dot(dir)
			cuts.append([t - door.door_width * 0.5, t + door.door_width * 0.5])
		cuts.sort_custom(func(x, y): return x[0] < y[0])

		# Complement of the (clamped, merged) cuts = the wall runs.
		var cursor := 0.0
		var runs: Array = []
		for cut in cuts:
			var s: float = clampf(cut[0], 0.0, edge_len)
			var e: float = clampf(cut[1], 0.0, edge_len)
			if s > cursor:
				runs.append([cursor, s])
			cursor = maxf(cursor, e)
		if cursor < edge_len:
			runs.append([cursor, edge_len])

		for run in runs:
			var s: float = run[0]
			var e: float = run[1]
			if e - s < 1.0:
				continue
			var p0 := a + dir * s
			var p1 := a + dir * e
			if s <= 0.0:
				p0 -= dir * half   # polygon corner — extend to overlap the next edge
			if e >= edge_len:
				p1 += dir * half
			var nrm := Vector2(-dir.y, dir.x)
			_wall_quads.append(PackedVector2Array([
				p0 + nrm * half, p1 + nrm * half,
				p1 - nrm * half, p0 - nrm * half,
			]))


## Pushes the wall quads into the pooled collision polygons (solid build mode —
## a closed run's BUILD_SEGMENTS closing edge would cut corners on L-runs).
func _apply_collision() -> void:
	while _cols.size() < _wall_quads.size():
		var col := CollisionPolygon2D.new()
		col.name = "_ShelterWallCol%d" % _cols.size()
		col.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		_body.add_child(col, false, Node.INTERNAL_MODE_FRONT)
		_cols.append(col)
	for i in _cols.size():
		if i < _wall_quads.size():
			_cols[i].disabled = false
			_cols[i].polygon = _wall_quads[i]
		else:
			_cols[i].disabled = true
			_cols[i].polygon = PackedVector2Array()


func _draw() -> void:
	for quad in _wall_quads:
		draw_colored_polygon(quad, wall_color)
	# "Release here" telegraph (step 3): bright footprint outline under the cursor.
	if _hover_highlighted and polygon.size() >= 3:
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, Color(1.0, 1.0, 1.0, 0.95), 3.0)


## Reports the wall band (NOT the footprint) to NavBaker: walls are carved from
## the navmesh, doorways and the interior stay navigable (spec §15 — nav bakes
## with doorways open; doors close via physics barriers only).
##
## The quads are MERGED into non-overlapping outlines first: adjacent quads
## overlap at every polygon corner (the half-thickness extension), and their
## collinear overlapping edges rasterize into the same navmesh cells — the
## "more than 2 edges occupy the same rasterization space" bake warning.
## Physics collision keeps the raw quads (overlap is harmless there).
func get_nav_footprint() -> Dictionary:
	var obstruction := []
	for outline in _merged_wall_outlines():
		obstruction.append(_to_global_poly(outline))
	return {"obstruction": obstruction, "traversable": []}


## Unions the wall quads into disjoint outlines (local space). Interior holes —
## only possible when a wall loop has no door, sealing it — are dropped: that
## over-carves the unreachable interior, which is harmless. Merge order follows
## _wall_quads order, so the result is deterministic.
func _merged_wall_outlines() -> Array:
	var outlines: Array = []
	for quad in _wall_quads:
		var pending: PackedVector2Array = quad
		var i := 0
		while i < outlines.size():
			var result := Geometry2D.merge_polygons(pending, outlines[i])
			var outers: Array = []
			for poly in result:
				if not Geometry2D.is_polygon_clockwise(poly):
					outers.append(poly)
			if outers.size() == 1:
				# Overlapping (or touching) — absorb and rescan against the rest.
				pending = outers[0]
				outlines.remove_at(i)
				i = 0
			else:
				i += 1
		outlines.append(pending)
	return outlines


## Converts a local-space polygon into global space.
func _to_global_poly(local_pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in local_pts:
		out.append(global_transform * p)
	return out
