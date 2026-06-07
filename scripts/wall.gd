@tool  # Runs in editor so collision + outline follow the points you drag
extends Polygon2D
class_name Wall

## Wall - Flexible level geometry you draw directly with the mouse
##
## A Wall IS a Polygon2D, so the moment you select it the polygon point editor
## is live: click to add points, drag to move them, no sidebar typing. Add one
## with Add Child Node -> "Wall" (NOT by instancing a scene), so every Wall is a
## fully independent node — nothing can ever propagate between levels.
##
## The collision body (StaticBody2D + CollisionPolygon2D) and the thick outline
## (Line2D) are created automatically as HIDDEN INTERNAL children: they don't
## clutter the scene tree and aren't saved into the level — only the polygon you
## draw is stored. The body joins the "buildings" group on collision layer 1, so
## walls block movement AND line of sight (vision raycasts use collision_mask 1)
## with no extra wiring.
##
## TWO MODES (toggle `solid`):
## - solid = false → PERIMETER. Collision only on the outline edges
##   (build_mode = Segments); interior stays walkable. Use ONE Wall to enclose a
##   whole level. Drawn as a thick closed outline (width = wall_thickness).
## - solid = true  → BLOCK. The whole polygon blocks and is drawn filled. Use
##   these to carve rooms / drop obstacles of any shape.

# === EXPORTED PROPERTIES ===

## false = perimeter (hollow, edges-only collision), true = filled solid block.
@export var solid: bool = false:
	set(value):
		solid = value
		_sync()

## Colour of the wall graphic (placeholder until art exists).
@export var wall_color: Color = Color(0.4, 0.4, 0.4, 1):
	set(value):
		wall_color = value
		_sync()

## Visual thickness of perimeter (outline) walls, in pixels.
## Note: in perimeter mode collision sits on the centerline; thickness is visual.
@export_range(2, 100, 1) var wall_thickness: float = 16.0:
	set(value):
		wall_thickness = value
		_sync()

# === GENERATED INTERNAL CHILDREN (not serialized) ===

var _body: StaticBody2D
var _col: CollisionPolygon2D   # outer edge of the stroke (or the whole shape when solid)
var _col2: CollisionPolygon2D  # inner edge of the stroke (perimeter mode only)
var _outline: Line2D


func _ready() -> void:
	# Give a freshly-added Wall a default box so it's visible and reshapeable.
	if polygon.is_empty():
		polygon = PackedVector2Array([
			Vector2(-100, -100), Vector2(100, -100),
			Vector2(100, 100), Vector2(-100, 100),
		])
	# Add to "nav_obstacle" group so NavBaker carves this wall out of the mesh.
	add_to_group("nav_obstacle")
	_sync()


func _process(_delta: float) -> void:
	# In the editor, keep collision + outline in sync with the points you drag.
	if Engine.is_editor_hint():
		_sync()


## Creates the internal collision body and outline once, reusing them on reload.
func _ensure_nodes() -> void:
	if _body == null or not is_instance_valid(_body):
		_body = _find_internal(self, "_WallBody") as StaticBody2D
		if _body == null:
			_body = StaticBody2D.new()
			_body.name = "_WallBody"
			add_child(_body, false, Node.INTERNAL_MODE_FRONT)
		if not _body.is_in_group("buildings"):
			_body.add_to_group("buildings")

	if _col == null or not is_instance_valid(_col):
		_col = _find_internal(_body, "_WallCollision") as CollisionPolygon2D
		if _col == null:
			_col = CollisionPolygon2D.new()
			_col.name = "_WallCollision"
			_body.add_child(_col, false, Node.INTERNAL_MODE_FRONT)

	if _col2 == null or not is_instance_valid(_col2):
		_col2 = _find_internal(_body, "_WallCollision2") as CollisionPolygon2D
		if _col2 == null:
			_col2 = CollisionPolygon2D.new()
			_col2.name = "_WallCollision2"
			_body.add_child(_col2, false, Node.INTERNAL_MODE_FRONT)

	if _outline == null or not is_instance_valid(_outline):
		_outline = _find_internal(self, "_WallOutline") as Line2D
		if _outline == null:
			_outline = Line2D.new()
			_outline.name = "_WallOutline"
			_outline.closed = true  # Mitred closed corners — no missing-corner gap
			_outline.joint_mode = Line2D.LINE_JOINT_SHARP
			add_child(_outline, false, Node.INTERNAL_MODE_FRONT)


## Finds an existing internal child by name (survives script hot-reload).
func _find_internal(parent: Node, child_name: String) -> Node:
	for child in parent.get_children(true):  # true = include internal children
		if child.name == child_name:
			return child
	return null


## Pushes the current polygon + mode + colour into the generated children.
func _sync() -> void:
	if not is_inside_tree():
		return
	_ensure_nodes()

	# Fill: the Polygon2D itself draws the solid block; transparent for perimeter
	# so only the thick outline shows.
	color = wall_color if solid else Color(0, 0, 0, 0)

	# Collision. Solid mode uses the full filled polygon (already matches its
	# visual). Perimeter mode puts segment collision on BOTH the inner and outer
	# edges of the visual stroke — offset by half the thickness — so units stop
	# at the painted edge from either side instead of clipping to the centerline.
	if solid:
		_col.disabled = false
		_col.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		_col.polygon = polygon
		_col2.disabled = true
		_col2.polygon = PackedVector2Array()
	else:
		var half := wall_thickness * 0.5
		var outer := _offset_ring(polygon, half)
		var inner := _offset_ring(polygon, -half)
		if outer.is_empty() or inner.is_empty():
			# Wall too thin to offset cleanly — fall back to centerline collision.
			_col.disabled = false
			_col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
			_col.polygon = polygon
			_col2.disabled = true
			_col2.polygon = PackedVector2Array()
		else:
			_col.disabled = false
			_col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
			_col.polygon = outer
			_col2.disabled = false
			_col2.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
			_col2.polygon = inner

	# Outline: thick closed stroke for perimeter walls only.
	_outline.visible = not solid
	_outline.width = wall_thickness
	_outline.default_color = wall_color
	_outline.points = polygon


## Returns the drawn polygon grown (delta > 0) or shrunk (delta < 0) by |delta|.
## Returns an empty array if the offset collapses the shape (e.g. too thin).
func _offset_ring(poly: PackedVector2Array, delta: float) -> PackedVector2Array:
	var rings := Geometry2D.offset_polygon(poly, delta, Geometry2D.JOIN_MITER)
	if rings.is_empty():
		return PackedVector2Array()
	return rings[0]


## Reports this wall's footprint to NavBaker so it's carved from the nav mesh.
## Returns global-space outlines: { obstruction: [...], traversable: [...] }.
## Solid walls carve their whole polygon. Perimeter walls carve only the thin
## wall band — one solid quad per edge — so the enclosed interior stays navigable
## (lets a perimeter Wall act as a level boundary you walk inside).
func get_nav_footprint() -> Dictionary:
	var obstruction := []
	if solid:
		obstruction.append(_to_global_poly(polygon))
	else:
		for quad in _edge_quads(polygon, wall_thickness):
			obstruction.append(_to_global_poly(quad))
	return {"obstruction": obstruction, "traversable": []}


## Builds one thickened quad per polygon edge (closed loop), each extended by
## half-thickness at both ends so adjacent quads overlap and fill the corners.
func _edge_quads(poly: PackedVector2Array, thickness: float) -> Array:
	var quads := []
	var count := poly.size()
	if count < 2:
		return quads
	var half := thickness * 0.5
	for i in range(count):
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var edge := b - a
		var length := edge.length()
		if length < 0.001:
			continue
		var dir := edge / length
		var nrm := Vector2(-dir.y, dir.x)
		var a2 := a - dir * half  # extend back to cover the corner
		var b2 := b + dir * half  # extend forward to cover the corner
		quads.append(PackedVector2Array([
			a2 + nrm * half, b2 + nrm * half,
			b2 - nrm * half, a2 - nrm * half,
		]))
	return quads


## Converts a local-space polygon into global space.
func _to_global_poly(local_pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in local_pts:
		out.append(global_transform * p)
	return out
