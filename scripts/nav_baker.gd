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
##
## TWO MESHES (fences/hazards spec §B3, slice 1a): one geometry scan, two bakes —
##   RECKLESS (this node, navigation_layers 1): all humans + FERAL zombies.
##     Exactly the pre-slice mesh, unchanged.
##   CAREFUL (a server-direct region RID, navigation_layers 2): CALM zombies.
##     Additionally carves zombie-lethal visible hazards (stake beds), so the
##     controlled reserve routes around what would kill it while the frenzy
##     runs straight through.
## Which meshes a footprint carves is the nav_carve_layers() protocol: owners
## without the method carve BOTH (3) — every pre-hazard obstacle is unchanged,
## and with no hazards in a level the two meshes are identical (provable no-op).
## The careful region is a raw NavigationServer2D RID, NOT a child
## NavigationRegion2D node: the §B3.2 prototype found runtime-created region
## NODES failing to commit their polygon to the map, while server-direct regions
## sync reliably (and GameManager's per-tick map_force_update keeps both regions
## on the deterministic tick stream). Fences and Mines define no footprint at
## all — a fence is in NOBODY'S mesh on purpose (§A9.1).

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


## The CAREFUL mesh's server-direct region (runtime only; editor previews show
## the reckless mesh on this node). Freed on exit — R restarts included.
var _careful_region: RID = RID()


func _ready() -> void:
	# In the editor we only bake on demand (the button); auto-bake at runtime.
	if Engine.is_editor_hint():
		return
	# One PHYSICS tick so all siblings (buildings, walls, LevelBounds) are in the
	# tree first. Physics-frame, not call_deferred: deferred calls flush per RENDER
	# frame, so under fast-forward the navmesh would appear time_scale-many ticks
	# later — a boot-time divergence (§10). One physics tick is one physics tick.
	_rebake_next_tick()


func _exit_tree() -> void:
	if _careful_region.is_valid():
		NavigationServer2D.free_rid(_careful_region)
		_careful_region = RID()


func _rebake_next_tick() -> void:
	await get_tree().physics_frame
	rebake()


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

	var source_reckless := NavigationMeshSourceGeometryData2D.new()
	var source_careful := NavigationMeshSourceGeometryData2D.new()
	# Baked polygons live in this region's local space; convert globals into it.
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
	source_reckless.add_traversable_outline(walkable)
	source_careful.add_traversable_outline(walkable)

	# 2. Each obstacle carves its own footprint — into the meshes its carve-layer
	#    mask names (§B3.1 protocol; no method = both, so pre-hazard obstacles are
	#    untouched). Bit 1 = reckless, bit 2 = careful.
	for node in nodes:
		if not node.has_method("get_nav_footprint"):
			continue
		var carve := 3
		if node.has_method("nav_carve_layers"):
			carve = node.nav_carve_layers()
		var footprint: Dictionary = node.get_nav_footprint()
		for outline in footprint.get("obstruction", []):
			var pts := _to_region_space(to_region, outline)
			if carve & 1:
				source_reckless.add_obstruction_outline(pts)
			if carve & 2:
				source_careful.add_obstruction_outline(pts)
		for outline in footprint.get("traversable", []):
			var pts := _to_region_space(to_region, outline)
			if carve & 1:
				source_reckless.add_traversable_outline(pts)
			if carve & 2:
				source_careful.add_traversable_outline(pts)

	# 3. RECKLESS bake → this node (layer 1: humans + ferals — today's mesh).
	navigation_layers = 1
	navigation_polygon = _bake(source_reckless)

	# 4. CAREFUL bake → the server-direct region (layer 2: calm zombies).
	#    Runtime only: the editor preview button shows the reckless mesh, and
	#    editor-created server RIDs would leak into the editing session.
	if Engine.is_editor_hint():
		return
	if not _careful_region.is_valid():
		_careful_region = NavigationServer2D.region_create()
		NavigationServer2D.region_set_map(_careful_region, get_world_2d().navigation_map)
		NavigationServer2D.region_set_navigation_layers(_careful_region, 2)
	NavigationServer2D.region_set_transform(_careful_region, global_transform)
	NavigationServer2D.region_set_navigation_polygon(_careful_region, _bake(source_careful))


## One bake with this baker's settings.
func _bake(source: NavigationMeshSourceGeometryData2D) -> NavigationPolygon:
	var poly := NavigationPolygon.new()
	poly.agent_radius = agent_radius
	poly.cell_size = bake_cell_size
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	return poly


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
