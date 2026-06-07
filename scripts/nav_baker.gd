@tool  # Allows the editor "Bake preview" button to run
extends NavigationRegion2D
class_name NavBaker

## NavBaker - Auto-bakes this region's navigation mesh from live scene geometry
##
## Replaces hand-authored NavigationPolygon coordinates + manual editor re-bakes.
## At runtime (on level load) it rebuilds the nav mesh from the ACTUAL scene:
## - Walkable area = the LevelBounds rectangle (your single source of truth).
## - Obstacles carve themselves out: every node in the "nav_obstacle" group hands
##   the baker its footprint via get_nav_footprint(), so exclusion is explicit and
##   deterministic — no reliance on the editor's collider parsing / group config
##   (the usual cause of "my building didn't get excluded").
##
## Buildings report a rectangle; solid Walls report their polygon; perimeter Walls
## report one thin quad per edge, so only the wall band is carved — letting a
## perimeter Wall act as a level boundary (walk inside) instead of carving the
## whole interior into a hole.
##
## get_nav_footprint() returns a Dictionary in GLOBAL coordinates:
##   { "obstruction": Array[PackedVector2Array], "traversable": Array[PackedVector2Array] }

# === EXPORTED PROPERTIES ===

## Clearance kept between agents and obstacles/borders when baking (pixels).
## Keep this close to the unit collision radius (~12px). Larger values erode the
## interiors of small handcrafted rooms — clearance is applied on every obstacle side.
@export_range(0.0, 100.0, 1.0) var agent_radius: float = 12.0:
	set(value):
		agent_radius = value

## Bake resolution. Smaller = more accurate (crisper small rooms), slower bake.
@export_range(1.0, 50.0, 1.0) var bake_cell_size: float = 4.0:
	set(value):
		bake_cell_size = value

## Editor-only: tick to preview the baked mesh in the viewport (auto-resets).
@export var bake_preview: bool = false:
	set(value):
		bake_preview = false  # momentary button
		if value and Engine.is_editor_hint():
			rebake()


func _ready() -> void:
	# In the editor we only bake on demand (the button); auto-bake at runtime.
	if Engine.is_editor_hint():
		return
	# Defer so all siblings (buildings, walls, LevelBounds) are in the tree first.
	call_deferred("rebake")


## Rebuilds and bakes the navigation mesh from current scene geometry.
func rebake() -> void:
	# Scan the scene directly rather than trusting runtime-added groups, which
	# aren't reliably registered when the editor preview bake runs.
	var root := _scene_root()
	if root == null:
		push_warning("NavBaker: could not resolve the scene root — cannot bake.")
		return

	var nodes: Array[Node] = []
	_collect_nodes(root, nodes)

	var bounds_node: LevelBounds = null
	for node in nodes:
		if node is LevelBounds:
			bounds_node = node
			break
	if bounds_node == null:
		push_warning("NavBaker: no LevelBounds in the scene — cannot bake.")
		return

	var source := NavigationMeshSourceGeometryData2D.new()
	# Baked polygon lives in this region's local space; convert globals into it.
	var to_region := global_transform.affine_inverse()

	# 1. Walkable area = the LevelBounds rectangle (in its own global space).
	var bt := bounds_node.global_transform
	var b_min := bounds_node.bounds_min
	var b_max := bounds_node.bounds_max
	var walkable := PackedVector2Array([
		to_region * (bt * b_min),
		to_region * (bt * Vector2(b_max.x, b_min.y)),
		to_region * (bt * b_max),
		to_region * (bt * Vector2(b_min.x, b_max.y)),
	])
	source.add_traversable_outline(walkable)

	# 2. Each obstacle carves its own footprint.
	for node in nodes:
		if not node.has_method("get_nav_footprint"):
			continue
		var footprint: Dictionary = node.get_nav_footprint()
		for outline in footprint.get("obstruction", []):
			source.add_obstruction_outline(_to_region_space(to_region, outline))
		for outline in footprint.get("traversable", []):
			source.add_traversable_outline(_to_region_space(to_region, outline))

	# 3. Bake into a fresh NavigationPolygon and apply it.
	var poly := NavigationPolygon.new()
	poly.agent_radius = agent_radius
	poly.cell_size = bake_cell_size
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	navigation_polygon = poly


## Resolves the scene root to scan, working in both game and editor.
func _scene_root() -> Node:
	if owner != null:
		return owner
	var tree := get_tree()
	if tree == null:
		return null
	if Engine.is_editor_hint():
		return tree.edited_scene_root
	return tree.current_scene


## Flattens the subtree under `node` (inclusive) into `acc`.
func _collect_nodes(node: Node, acc: Array[Node]) -> void:
	acc.append(node)
	for child in node.get_children():
		_collect_nodes(child, acc)


## Transforms a global-space outline into this region's local space.
func _to_region_space(to_region: Transform2D, pts_global: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts_global:
		out.append(to_region * p)
	return out
