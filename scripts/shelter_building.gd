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
## STEP-1 SCOPE: geometry + doors only. Occupancy (SHELTERED), shelter spots,
## breach state and exit-set membership arrive in later slice-1 steps — this node
## is their future home.

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


func _ready() -> void:
	# Give a freshly-added building a default footprint so it's visible and reshapeable.
	if polygon.is_empty():
		polygon = PackedVector2Array([
			Vector2(-150, -100), Vector2(150, -100),
			Vector2(150, 100), Vector2(-150, 100),
		])
	# NavBaker carves the wall quads (not the footprint) out of the mesh.
	add_to_group("nav_obstacle")
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


## Rebuilds everything from the current polygon + doors.
func _sync() -> void:
	if not is_inside_tree():
		return
	color = floor_color   # the Polygon2D's own fill = the visible floor (§10)
	_ensure_body()
	_snap_doors()
	_build_wall_quads()
	_apply_collision()
	queue_redraw()


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
