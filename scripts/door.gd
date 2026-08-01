@tool
extends Node2D
class_name Door

## Door — the only opening in a ShelterBuilding's perimeter (buildings spec §4).
##
## Place one as a CHILD of a ShelterBuilding and drop it roughly on the outline:
## the parent snaps it onto the nearest perimeter edge (position + rotation) and
## opens a door_width gap in the generated walls there. Dragging a Door in the
## editor slides it along the perimeter. The node's local X axis runs along the
## door segment.
##
## TWO INDEPENDENT FACTS about a door (§4):
##   - THE ZOMBIE BARRIER (§4.1, always on until breached): a StaticBody2D on
##     layer 4 "EscapeBarrier" (escape_zone.gd pattern verbatim) — zombies
##     (mask 9) physically slide off; humans (mask 1) pass through. Paired with
##     an LOS blocker on layer 5 "DoorLOS": an intact door is a wall to every
##     sight check (§7.1). Both are freed permanently at breach.
##   - THE LOCK (§4.2, step 4 — stubbed): admits humans only while no feral is
##     in the engagement arc.
##
## BREACH (§4.3, step 3): ferals in the engagement arc pound on a fixed cadence
## (FeralBrain owns the cadence/stagger; this node owns integrity). Integrity 0 =
## breached, PERMANENTLY: barriers freed, the door is an open hole for everyone,
## and the whole building leaves the flee exit set forever (§9).
##
## UI (§4.4): integrity renders as a chunk-decrementing bar with a per-pound
## flash — the bar's tempo literally is the feral count. Interim programmer
## graphics; migrates to vision_renderer in Phase 5.

## Emitted once, when integrity reaches 0. Step 6 hangs the flush off this.
signal breached(door: Door)

## Width of the doorway gap in pixels — a first-class per-door level-design knob
## (§4.3): sets siege throughput, post-breach entry serialization, flush drain
## rate, and doorway ambushability.
@export_range(16.0, 400.0, 1.0) var door_width: float = 48.0:
	set(value):
		door_width = value
		queue_redraw()

## Per-door integrity override. 0 = use the GameConfig default (600); reinforced
## doors (e.g. an armory) set a higher value per level design (§4.3).
@export var integrity_override: float = 0.0

## Placeholder door graphic colour (programmer art until the boards-on-door pass).
@export var door_color: Color = Color(0.55, 0.38, 0.15, 1.0):
	set(value):
		door_color = value
		queue_redraw()

## Open doorway (terrain kit, Ben's ruling 2026-07-26): born a permanent hole —
## no barriers, no lock, no leaf, no integrity. Everyone and every sight-line
## passes from tick zero. NOTE: an open door makes its whole building count as
## breached (a hole in the wall is not shelter, §9) — it never attracts or
## protects civilians.
@export var starts_open: bool = false:
	set(value):
		starts_open = value
		queue_redraw()

## Wall thickness the door spans. A ShelterBuilding parent overwrites this on
## sync; for a STANDALONE gate door in hand-built wall geometry, set it to match
## the flanking walls.
@export_range(2.0, 100.0, 1.0) var thickness: float = 16.0:
	set(value):
		thickness = value
		queue_redraw()

## Runtime siege state (step 3). _max_integrity resolves at _ready.
var _integrity: float = 0.0
var _max_integrity: float = 0.0
var _breached: bool = false
## Per-pound bar flash (presentation only), decayed in _process.
var _pulse: float = 0.0

var _zombie_barrier: StaticBody2D = null
var _los_blocker: StaticBody2D = null

## THE LOCK (§4.2, step 4). A continuous predicate, not a latch: locked while any
## FERAL is inside the engagement arc; the instant the arc clears (plus optional
## hysteresis) the door admits humans again. Nothing is remembered. Enforced by a
## third barrier body on layer 6 "DoorLock" (bit 32) — humans (mask 33) bounce
## off it while locked; zombies never collide with it.
var _lock_barrier: StaticBody2D = null
var _locked: bool = false
var _unlock_wait: float = 0.0
var _gm: Node = null

## High-z child the integrity bar draws on (runtime only) — units render at z 0
## in tree order, so drawing the bar on the Door itself buried it under any
## zombie standing at the doorway. The leaf stays at ground level deliberately.
var _bar_layer: Node2D = null


## Which local-Y sign is the building INTERIOR (from the footprint centre); 0 for
## a standalone door (disables the inside burst).
var _inside_sign: float = 0.0


func _ready() -> void:
	_read_parent_thickness()
	queue_redraw()
	# Editor: visual only — never build barrier bodies or read config (CLAUDE.md @tool rule).
	if Engine.is_editor_hint():
		return
	_max_integrity = integrity_override if integrity_override > 0.0 else GameConfig.door_integrity
	_integrity = _max_integrity
	var b := building()
	if b != null:
		_inside_sign = signf(to_local(b.centre()).y)
	# One-time wiring: the entry check, the exit set (§9), the wedge-pound scan
	# and release-on-door all find doors here (gates included — the group name is
	# historical).
	add_to_group("shelter_doors")
	if starts_open:
		_breached = true   # born a hole: everything downstream reads "breached"
		return
	_create_barriers()
	_bar_layer = Node2D.new()
	_bar_layer.name = "BarLayer"
	_bar_layer.z_index = 10
	add_child(_bar_layer)
	_bar_layer.draw.connect(_draw_bar)


## Runtime only: decay the per-pound bar flash (presentation, never simulation).
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 5.0)
		if _bar_layer != null:
			_bar_layer.queue_redraw()


## The lock predicate (§4.2) + the INSIDE BURST, evaluated every physics frame —
## deterministic: registry-ordered query, fixed timestep.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _breached:
		return
	# INSIDE BURST (Ben's ruling 2026-07-25): any living zombie standing in the
	# arc's INSIDE half breaks this door open instantly. The body price was paid
	# at the breach that let it in — pursuit must FLOW out the back (a flushed
	# runner's head start is the run, not a second siege). Calm zombies included:
	# the cleared building's horde walks out. Outside-in stays the priced pound
	# (§4.3) — pre-breach, nothing can stand inside, so this can never pre-fire.
	if _zombie_inside_arc():
		_burst_from_inside()
		return
	var engaged := _feral_in_arc()
	if engaged:
		_set_locked(true)
		_unlock_wait = GameConfig.door_unlock_hysteresis
	elif _locked:
		_unlock_wait -= delta
		if _unlock_wait <= 0.0:
			_set_locked(false)


## True if any FERAL zombie is inside the engagement arc. Registry query with a
## radius that always covers the arc rect, then the exact arc test.
func _feral_in_arc() -> bool:
	var gm := _game_manager()
	if gm == null:
		return false
	var reach := door_width * 0.5 + ARC_SIDE_MARGIN + thickness * 0.5 + GameConfig.door_engagement_depth
	for u in gm.neighbours_within(global_position, reach, &"zombies"):
		var z := u as Zombie
		if z != null and z.current_state == Zombie.State.FERAL and in_engagement_arc(z.global_position):
			return true
	return false


## True if ANY living zombie (calm or feral) stands in the INSIDE half of the
## engagement arc. _inside_sign 0 (standalone door, no building) disables this.
func _zombie_inside_arc() -> bool:
	if _inside_sign == 0.0:
		return false
	var gm := _game_manager()
	if gm == null:
		return false
	var reach := door_width * 0.5 + ARC_SIDE_MARGIN + thickness * 0.5 + GameConfig.door_engagement_depth
	for u in gm.neighbours_within(global_position, reach, &"zombies"):
		if not in_engagement_arc(u.global_position):
			continue
		if signf(to_local(u.global_position).y) == _inside_sign:
			return true
	return false


func _burst_from_inside() -> void:
	if GameConfig.debug_logs:
		print("💥 BURST: %s broken open from the inside!" % name)
	_do_breach()


func _set_locked(value: bool) -> void:
	if _locked == value:
		return
	_locked = value
	if _lock_barrier != null:
		_lock_barrier.collision_layer = 32 if _locked else 0
	queue_redraw()   # the locked leaf tint


## Lazily resolves the GameManager (unit registry). Cached after first use.
func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm


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
	_lock_barrier = _make_barrier("LockBarrier", 0)       # layer 6 "DoorLock" while locked


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


# === SIEGE (step 3, §4.3) ===

## One pound lands (called by a besieging FeralBrain on its cadence). Chunk off
## integrity; at 0 the door breaches permanently.
func apply_pound(damage: float) -> void:
	if _breached:
		return
	_integrity = maxf(0.0, _integrity - damage)
	_pulse = 1.0
	if _bar_layer != null:
		_bar_layer.queue_redraw()
	if _integrity <= 0.0:
		if GameConfig.debug_logs:
			print("💥 BREACH: %s is down!" % name)
		_do_breach()


## Breach (§4.3): permanent. Frees BOTH barriers — the doorway becomes an open
## hole for everyone (movement AND sight) for the rest of the level.
func _do_breach() -> void:
	_breached = true
	# Zero the layers BEFORE the deferred free: queue_free removes the bodies at
	# end-of-frame, but every besieger reacts to the breach THIS frame — their
	# retarget raycasts and entry moves must not hit a dying barrier.
	if _zombie_barrier != null:
		_zombie_barrier.collision_layer = 0
		_zombie_barrier.queue_free()
		_zombie_barrier = null
	if _los_blocker != null:
		_los_blocker.collision_layer = 0
		_los_blocker.queue_free()
		_los_blocker = null
	breached.emit(self)
	queue_redraw()
	if _bar_layer != null:
		_bar_layer.queue_redraw()   # clears the bar


# === STATE QUERIES ===

## Depth beyond the wall band still counted as "crossing" the doorway (unit radius-ish,
## so a human's centre trips the entry the moment its body is in the gap).
const ENTRY_MARGIN := 8.0

## Sideways slop on the engagement arc (a body pressed near the gap's edge still pounds;
## the real crowd cap stays physical — BOID separation + door width, §4.3).
const ARC_SIDE_MARGIN := 12.0

## False once breached — a breached door is an open hole forever.
func is_intact() -> bool:
	return not _breached


func is_breached() -> bool:
	return _breached


func integrity_fraction() -> float:
	return _integrity / _max_integrity if _max_integrity > 0.0 else 0.0


## The lock (§4.2): true while a feral is inside the engagement arc (plus any
## unlock hysteresis) — an engaged door admits no humans. Compresses to one
## sentence: an engaged door admits no one. A breached door has no lock.
func is_locked() -> bool:
	return _locked and not _breached


## The owning ShelterBuilding (duck-typed), or null for a standalone door.
func building() -> Node:
	var parent := get_parent()
	if parent != null and parent.has_method("claim_spot"):
		return parent
	return null


## A global point just INSIDE the wall band at this door — what the door-watch
## (§7.1) rays at and pins its front to: the door centre itself sits inside the
## DoorLOS blocker, which would block its own watchers. Falls back to +Y for a
## standalone door.
func inside_point() -> Vector2:
	var inward := 1.0
	var b := building()
	if b != null:
		var local_centre: Vector2 = to_local(b.centre())
		if local_centre.y != 0.0:
			inward = signf(local_centre.y)
	return to_global(Vector2(0.0, inward * (thickness * 0.5 + 8.0)))


## True if `point` (global) is inside the doorway gap — the §6.1 entry test. Local
## X spans the gap, local Y crosses the wall band.
func contains_point(point: Vector2) -> bool:
	var local := to_local(point)
	return absf(local.x) <= door_width * 0.5 and absf(local.y) <= thickness * 0.5 + ENTRY_MARGIN


## True if `point` (global) is in the engagement arc (§4.2/§4.3): the shallow zone
## door_engagement_depth deep in front of the door segment. Checked on BOTH sides
## for simplicity — pre-breach no zombie can be inside, so only the outside half
## can ever match (saves tracking which side is "out").
func in_engagement_arc(point: Vector2) -> bool:
	var local := to_local(point)
	return absf(local.x) <= door_width * 0.5 + ARC_SIDE_MARGIN \
		and absf(local.y) <= thickness * 0.5 + GameConfig.door_engagement_depth


# === VISUALS (interim programmer graphics — Phase 5 moves these to vision_renderer) ===

## Release telegraph (§5.1 misclick defense): bright outline while the cursor
## hovers this door with releasable zombies selected. Toggled by SelectionManager.
var _hover_highlighted: bool = false

func set_hover_highlighted(value: bool) -> void:
	if _hover_highlighted == value:
		return
	_hover_highlighted = value
	queue_redraw()


func _draw() -> void:
	if _breached or starts_open:
		# An open hole: two splintered jamb stubs so the gap still reads as a doorway.
		var half_w := door_width * 0.5
		var half_t := thickness * 0.5
		draw_rect(Rect2(-half_w, -half_t, 6, thickness), door_color.darkened(0.4))
		draw_rect(Rect2(half_w - 6, -half_t, 6, thickness), door_color.darkened(0.4))
		return
	# The door leaf as a flat rect spanning the gap (ground level — units at the
	# doorway draw over it; the bar lives on the high-z BarLayer instead). While
	# LOCKED the leaf shifts dark-red: the barred-door tell (§10 readability).
	var leaf := door_color.lerp(Color(0.55, 0.1, 0.08), 0.55) if _locked else door_color
	draw_rect(Rect2(-door_width * 0.5, -thickness * 0.5, door_width, thickness), leaf)
	# "Release here" outline (the door hover telegraph).
	if _hover_highlighted:
		draw_rect(Rect2(-door_width * 0.5 - 3, -thickness * 0.5 - 3, door_width + 6, thickness + 6),
			Color(1.0, 1.0, 1.0, 0.95), false, 2.0)


## Integrity bar (§4.4), drawn on the high-z BarLayer so it always reads above
## the pounding crowd: appears once the door has taken a pound, decrements in
## chunks with a per-pound flash. Rotates with the door (fine for programmer art).
func _draw_bar() -> void:
	if _breached or _integrity >= _max_integrity:
		return
	var bar_w := door_width
	var bar_h := 5.0
	var bar_y := -(thickness * 0.5 + 10.0)
	var frac := integrity_fraction()
	_bar_layer.draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.8))
	var fill_col := Color(0.9, 0.25, 0.15).lerp(Color(0.35, 0.85, 0.3), frac)
	if _pulse > 0.0:
		fill_col = fill_col.lightened(_pulse * 0.6)
	_bar_layer.draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * frac, bar_h), fill_col)
