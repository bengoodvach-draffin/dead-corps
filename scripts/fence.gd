@tool
extends Node2D
class_name Fence

## Fence — the MASS GATE (fences spec Part A): freestanding terrain that nothing
## crosses. It cannot be pounded, has no integrity, and takes no damage — it
## folds when enough living zombies press against it AT ONCE, for long enough
## (§A4). Doors charge TIME; a fence charges STOCK — peak simultaneous horde
## size. It walls humans in as well as zombies out, so a fenced compound is a
## trap its own defenders built.
##
## Laid out like a Door, not a Wall: a straight segment along local +X, rotated
## to aim; local ±Y are the two sides. One Fence = one fold unit — chain short
## segments end to end for a run that opens piecewise.
##
## DELIBERATE ABSENCES (§A3.3), do not "fix":
##   - No LOS blocker: chain-link is see-through — defenders shoot the crowd
##     pressing it, fear passes through. (§1.1 assumption; reversing it is one
##     added DoorLOS-layer body.)
##   - No integrity / apply_pound / damage of any kind. One zombie left on a
##     fence overnight achieves exactly nothing — that IS the distinction from
##     a door, and it stays absolute.
##   - No get_nav_footprint() and no "nav_obstacle" group: a fence is in NOBODY'S
##     navmesh (§A9.1). Passage is denied by the physics barriers alone, which is
##     what makes an ordered move INTO a fence path up and press it. Its absence
##     here is deliberate, not an oversight.

## Emitted once at fold. Nothing consumes it in slices 1–2 — declared for the
## §A9.3 upgrade (clearing human write-offs on fold) if playtests want it.
signal folded(fence: Fence)

## Sideways slop on the press strip, mirrors Door.ARC_SIDE_MARGIN.
const STRIP_SIDE_MARGIN := 12.0
## Click-pick slop for the RMB-on-fence order (§A7).
const PICK_MARGIN := 10.0
## Effective body width along the span / rank spacing — the §A11 capacity model.
const BODY_WIDTH := 24.0
const RANK_DEPTH := 30.0
## Editor-only stand-ins for GameConfig values (the autoload doesn't exist in the
## editor, per the @tool rule): the shipped fence_press_depth / press-threshold
## defaults, used only by the scene-open capacity warning.
const EDITOR_ASSUMED_DEPTH := 40.0
const EDITOR_ASSUMED_THRESHOLD := 8
## How much of the sag is carried by sheer body weight (press count vs threshold)
## versus by the fold meter. Weight-share makes the wire bow GRADUALLY as zombies
## drip in — visible feedback long before breaking point (Ben, 2026-08-02) — and
## the meter drives the final give once the press is actually folding.
const WEIGHT_SAG_SHARE := 0.5

## Span along local X.
@export_range(32.0, 800.0, 1.0) var fence_length: float = 200.0:
	set(value):
		fence_length = value
		queue_redraw()

## Barrier band across local Y — thinner than a wall on purpose.
@export_range(2.0, 40.0, 1.0) var fence_thickness: float = 8.0:
	set(value):
		fence_thickness = value
		queue_redraw()

## Per-fence press threshold. 0 = use GameConfig.fence_press_threshold (mirrors
## Door's integrity_override pattern). Real tuning is per-fence, per level, against
## that level's horde size (§A12).
@export var threshold_override: int = 0

## Programmer-art wire colour.
@export var fence_color: Color = Color(0.45, 0.55, 0.45, 1.0):
	set(value):
		fence_color = value
		queue_redraw()

## SLICE 3 (§B9, post-PoC): declared now so levels can author it early, but
## deliberately UNREAD — no shock logic exists yet.
@export var electrified: bool = false

## Runtime fold state. The meter is a fixed-timestep accumulator (§A9.4): fills
## at 1/fence_fold_time per second while press_count >= threshold, drains at
## fence_relax_factor × that rate below it (drain, NOT reset — §A4).
var _folded: bool = false
var _fold_meter: float = 0.0
var _press_count: int = 0
## Which local-Y side holds more pressers (±1.0), lowest-unit_uid presser breaks
## ties (registry order = uid order), 0 when empty. Drives the sag direction.
var _majority_sign: float = 0.0
## Resolved at _ready (override or the GameConfig default).
var _threshold: int = 0

var _zombie_barrier: StaticBody2D = null
var _human_barrier: StaticBody2D = null
var _gm: Node = null

## High-z child the fold bar + labels live on (Door._bar_layer pattern) so a
## crowd at the wire never buries them.
var _bar_layer: Node2D = null
var _badge_label: Label = null
var _count_label: Label = null

## Release-telegraph-style hover outline while the cursor is on this fence with
## calm zombies selected. Toggled by SelectionManager.
var _hover_highlighted: bool = false


func _ready() -> void:
	queue_redraw()
	# Editor: visual only — never build barrier bodies or read config (@tool rule).
	# The §A11 capacity warning still runs, on assumed defaults.
	if Engine.is_editor_hint():
		_capacity_warning(EDITOR_ASSUMED_DEPTH,
			threshold_override if threshold_override > 0 else EDITOR_ASSUMED_THRESHOLD)
		return
	_threshold = threshold_override if threshold_override > 0 else GameConfig.fence_press_threshold
	_capacity_warning(GameConfig.fence_press_depth, _threshold)
	# One-time wiring: FeralBrain's strip_at and SelectionManager's pick find
	# fences here (rule 8 — group lookups are wiring, not per-frame discovery).
	add_to_group("fences")
	_create_barriers()
	_bar_layer = Node2D.new()
	_bar_layer.name = "BarLayer"
	_bar_layer.z_index = 10
	add_child(_bar_layer)
	_bar_layer.draw.connect(_draw_bar)
	_create_labels()


## The press rule (§A4), on the physics tick: count living zombies in the strip
## (registry query then the exact strip test — never a group scan), integrate the
## fold meter. Presence, not intent: ordered, jammed, or shambling there all count.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _folded:
		return
	var prev_count := _press_count
	var prev_meter := _fold_meter
	_update_press()
	if _press_count >= _threshold:
		_fold_meter = minf(1.0, _fold_meter + delta / GameConfig.fence_fold_time)
		if _fold_meter >= 1.0:
			_fold()
			return
	elif _fold_meter > 0.0:
		_fold_meter = maxf(0.0, _fold_meter - delta * GameConfig.fence_relax_factor / GameConfig.fence_fold_time)
	# The PHYSICAL wire gives with the bend (Ben, 2026-08-02): both barrier
	# bodies translate by the midpoint's sag, so the crowd visibly gains ground
	# as it presses in — and gets nudged back out as a draining wire recovers.
	# Deterministic: the offset is a pure function of sim state.
	var sag := _sag_offset()
	if _zombie_barrier != null:
		_zombie_barrier.position.y = sag
	if _human_barrier != null:
		_human_barrier.position.y = sag
	if _press_count != prev_count or _fold_meter != prev_meter:
		_refresh_presentation(prev_count)


## press_count = living zombies whose position lies in the press strip, BOTH
## sides summed (§A4 — a crowd split across the wire is still weight on it; Ben
## reconfirmed 2026-08-02). Calm, feral, risers-once-alive and specials all
## count; corpses and humans never do. The registry query radius covers the
## strip's CORNERS, not its centre — a half-length radius misses the ends.
func _update_press() -> void:
	var gm := _game_manager()
	if gm == null:
		return
	var reach := Vector2(fence_length * 0.5 + STRIP_SIDE_MARGIN,
			fence_thickness * 0.5 + GameConfig.fence_press_depth).length()
	var count := 0
	var pos_side := 0
	var neg_side := 0
	var first_sign := 0.0   # lowest-uid presser's side (registry order = uid order)
	for u in gm.neighbours_within(global_position, reach, &"zombies"):
		if u == null or not u.is_alive:
			continue
		var local := to_local(u.global_position)
		if absf(local.x) > fence_length * 0.5 + STRIP_SIDE_MARGIN:
			continue
		if absf(local.y) > fence_thickness * 0.5 + GameConfig.fence_press_depth:
			continue
		count += 1
		var s := signf(local.y)
		if first_sign == 0.0 and s != 0.0:
			first_sign = s
		if s > 0.0:
			pos_side += 1
		elif s < 0.0:
			neg_side += 1
	_press_count = count
	if pos_side > neg_side:
		_majority_sign = 1.0
	elif neg_side > pos_side:
		_majority_sign = -1.0
	else:
		_majority_sign = first_sign   # tie → lowest-uid presser's side; empty → 0


## Fold (§A5): PERMANENT and irreversible — no repair, no re-erection, no
## barricade (those are door mechanics). No score, no contagion, no combo — a
## fold is not violence. Humans keep treating the line as impassable (ruling 2,
## provisional — the write-off in FleeBehavior simply never clears).
func _fold() -> void:
	_folded = true
	# Zero layers BEFORE the deferred free (the Door breach-frame race fix):
	# same-frame raycasts and moves must not hit a dying blocker.
	if _zombie_barrier != null:
		_zombie_barrier.collision_layer = 0
		_zombie_barrier.queue_free()
		_zombie_barrier = null
	if _human_barrier != null:
		_human_barrier.collision_layer = 0
		_human_barrier.queue_free()
		_human_barrier = null
	if _majority_sign == 0.0:
		_majority_sign = 1.0   # fold needs a side to collapse toward
	folded.emit(self)
	if GameConfig.debug_logs:
		print("💥 FOLD: %s collapses under the press!" % name)
	if _badge_label != null:
		_badge_label.visible = false
	if _count_label != null:
		_count_label.visible = false
	queue_redraw()
	if _bar_layer != null:
		_bar_layer.queue_redraw()


## Both runtime barrier bodies across the span (Door._make_barrier pattern; both
## layers already exist — no project-settings change):
##   ZombieBarrier — layer 4 "EscapeBarrier" (8): zombies (mask 9) slide off.
##   HumanBarrier  — layer 6 "DoorLock" (32): humans (mask 33) bounce off;
##     zombies never collide with it. Group "fence_barriers" is what the human
##     bump-and-write-off (FleeBehavior, §A9.2) keys on.
func _create_barriers() -> void:
	_zombie_barrier = _make_barrier("ZombieBarrier", 8)
	_human_barrier = _make_barrier("HumanBarrier", 32)
	_human_barrier.add_to_group("fence_barriers")


func _make_barrier(body_name: String, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0   # the barrier itself collides with nothing
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(fence_length + fence_thickness, fence_thickness)
	shape_node.shape = rect
	body.add_child(shape_node)
	add_child(body)
	return body


# === STATE QUERIES ===

func is_intact() -> bool:
	return not _folded


func is_folded() -> bool:
	return _folded


func press_count() -> int:
	return _press_count


## True while the press is at/above threshold on an intact fence — the meter is
## actively filling. FeralBrain's give-up exemption keys on THIS, not on mere
## presence (Ben's ruling 2026-08-02): an under-strength press gets no exemption,
## so its ferals calm out in the strip (where they still count) instead of being
## committed forever to a fence they cannot fold.
func is_filling() -> bool:
	return not _folded and _press_count >= _threshold


func fold_fraction() -> float:
	return _fold_meter


func threshold() -> int:
	return _threshold


## True if `point` (global) lies in the press strip (§A4) — both sides.
func in_press_strip(point: Vector2) -> bool:
	var local := to_local(point)
	return absf(local.x) <= fence_length * 0.5 + STRIP_SIDE_MARGIN \
		and absf(local.y) <= fence_thickness * 0.5 + GameConfig.fence_press_depth


## Click hit-test for the RMB-on-fence order (SelectionManager).
func click_hit(pos: Vector2) -> bool:
	var local := to_local(pos)
	return absf(local.x) <= fence_length * 0.5 + PICK_MARGIN \
		and absf(local.y) <= fence_thickness * 0.5 + PICK_MARGIN


## The intact fence whose press strip contains `zombie`, or null — FeralBrain's
## wedge fallback (§A6.2), mirroring DoorBreach.door_in_arc. The group lookup is
## legal here: it runs on the WEDGE CADENCE, never per frame, and a live lookup
## survives scene reloads. Scene order resolves overlapping strips (§10).
static func strip_at(zombie: Node2D) -> Fence:
	for f in zombie.get_tree().get_nodes_in_group("fences"):
		if not is_instance_valid(f) or not f.is_intact():
			continue
		if f.in_press_strip(zombie.global_position):
			return f
	return null


## `count` move slots spread evenly along the span on the side nearest
## `from_pos`, offset half the press depth out from the band — the explicit
## RMB-on-fence order arrives ACROSS the strip instead of funnelling into one
## point (§A7). Below ~one body width of spacing the overflow wraps into a
## second rank deeper out. Deterministic and stateless.
func press_slots(count: int, from_pos: Vector2) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	if count <= 0:
		return slots
	var side := signf(to_local(from_pos).y)
	if side == 0.0:
		side = 1.0
	var depth: float = GameConfig.fence_press_depth
	var rank_cap := maxi(1, int(floorf(fence_length / BODY_WIDTH)))
	var n1 := mini(count, rank_cap)
	var n2 := count - n1
	var y1 := side * (fence_thickness * 0.5 + depth * 0.5)
	var y2 := side * (fence_thickness * 0.5 + depth * 0.9)
	for i in n1:
		var x := -fence_length * 0.5 + fence_length * (float(i) + 0.5) / float(n1)
		slots.append(to_global(Vector2(x, y1)))
	for i in n2:
		var x := -fence_length * 0.5 + fence_length * (float(i) + 0.5) / float(n2)
		slots.append(to_global(Vector2(x, y2)))
	return slots


## §A11: a threshold the span physically cannot hold is an unopenable fence and
## a designer error. max ≈ bodies-per-rank × ranks-per-side × 2 sides.
func _capacity_warning(depth: float, thr: int) -> void:
	# Explicit type: := inference off these operands fails the headless
	# --check-only parse gate (it can't resolve them in single-script context).
	var max_pressers: float = floorf(fence_length / BODY_WIDTH) * floorf(depth / RANK_DEPTH) * 2.0
	if float(thr) > 0.75 * max_pressers:
		push_warning("Fence '%s': threshold %d exceeds 75%% of physical capacity (~%d bodies fit) — likely unopenable. Lower the threshold or lengthen the span." % [name, thr, int(max_pressers)])


## Lazily resolves the GameManager (unit registry). Cached after first use.
func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm


# === VISUALS (interim programmer graphics — Phase 5 moves these to vision_renderer) ===

func set_hover_highlighted(value: bool) -> void:
	if _hover_highlighted == value:
		return
	_hover_highlighted = value
	queue_redraw()


## The three-tier indicator (§A8): requirement badge (always — planning info,
## readable BEFORE committing), live counter (while pressed; the red→green flip
## at threshold is the single most important readable moment on the object), and
## the fold bar + sag (while the meter is non-zero, draining included).
func _create_labels() -> void:
	_badge_label = Label.new()
	_badge_label.text = "⛓ %d" % _threshold
	_badge_label.add_theme_font_size_override("font_size", 14)
	_badge_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_layer.add_child(_badge_label)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.visible = false
	_bar_layer.add_child(_count_label)
	# Labels read UPRIGHT and sit world-above the midpoint regardless of the
	# node's rotation (a 180°-rotated fence must not read upside down — Ben,
	# 2026-08-02). Fences are static per level, so one-time placement is enough.
	_badge_label.rotation = -global_rotation
	_badge_label.global_position = global_position + Vector2(-16.0, -(fence_thickness * 0.5 + 48.0))
	_count_label.rotation = -global_rotation
	_count_label.global_position = global_position + Vector2(-18.0, -(fence_thickness * 0.5 + 30.0))


func _refresh_presentation(_prev_count: int) -> void:
	if _count_label != null:
		_count_label.visible = _press_count > 0
		if _press_count > 0:
			_count_label.text = "%d / %d" % [_press_count, _threshold]
			_count_label.add_theme_color_override("font_color",
				Color(0.55, 0.95, 0.35) if _press_count >= _threshold else Color(0.95, 0.35, 0.25))
	# The sag tracks the meter continuously — redraw the span while it moves.
	queue_redraw()
	if _bar_layer != null:
		_bar_layer.queue_redraw()


func _draw() -> void:
	var half_l := fence_length * 0.5
	if _folded:
		# Collapsed: two standing end posts + the span darkened and fully offset
		# AWAY from the side that pressed it over — a dead line on the ground.
		var down := fence_color.darkened(0.5)
		var offset: float = -GameConfig.fence_sag_max * _majority_sign
		draw_polyline(PackedVector2Array([
			Vector2(-half_l, 0.0), Vector2(0.0, offset * 1.5), Vector2(half_l, 0.0)
		]), down, maxf(2.0, fence_thickness * 0.5))
		_draw_posts(down)
		return
	# Intact: the span as a 3-point polyline, midpoint bowed AWAY from the
	# pressing side — the sag IS the trope image (§A8) and teaches the drain rule
	# for free as it eases back.
	var sag := 0.0
	if not Engine.is_editor_hint():
		sag = _sag_offset()
	draw_polyline(PackedVector2Array([
		Vector2(-half_l, 0.0), Vector2(0.0, sag), Vector2(half_l, 0.0)
	]), fence_color, fence_thickness)
	# Chain-link hatching along the straight base line (identity, not simulation).
	var hatch := fence_color.lightened(0.35)
	hatch.a = 0.7
	var x := -half_l + 8.0
	while x < half_l - 8.0:
		draw_line(Vector2(x - 4.0, -fence_thickness * 0.5 - 2.0),
			Vector2(x + 4.0, fence_thickness * 0.5 + 2.0), hatch, 1.0)
		draw_line(Vector2(x + 4.0, -fence_thickness * 0.5 - 2.0),
			Vector2(x - 4.0, fence_thickness * 0.5 + 2.0), hatch, 1.0)
		x += 16.0
	_draw_posts(fence_color.darkened(0.25))
	if _hover_highlighted:
		draw_rect(Rect2(-half_l - 3.0, -fence_thickness * 0.5 - 3.0,
			fence_length + 6.0, fence_thickness + 6.0),
			Color(1.0, 1.0, 1.0, 0.95), false, 2.0)


## Midpoint bow in local Y, NEGATIVE of the pressing side (wire bends away from
## the bodies shoving it). Two stacked components: body WEIGHT (press count vs
## threshold — grows a little with every zombie that drips in, far below
## breaking point) and the FOLD METER (the final give once actually folding).
## Presentation only, derived purely from sim state.
func _sag_offset() -> float:
	if _threshold <= 0:
		return 0.0
	var weight := minf(float(_press_count) / float(_threshold), 1.0)
	var frac := WEIGHT_SAG_SHARE * weight + (1.0 - WEIGHT_SAG_SHARE) * _fold_meter
	return -frac * GameConfig.fence_sag_max * _majority_sign


func _draw_posts(col: Color) -> void:
	var half_l := fence_length * 0.5
	var post := Vector2(4.0, fence_thickness + 8.0)
	draw_rect(Rect2(-half_l - post.x * 0.5, -post.y * 0.5, post.x, post.y), col)
	draw_rect(Rect2(half_l - post.x * 0.5, -post.y * 0.5, post.x, post.y), col)


## Fold bar (Door's bar language, continuous rather than chunked), on the high-z
## layer: visible while the meter is non-zero — INCLUDING while it drains.
func _draw_bar() -> void:
	if _folded or _fold_meter <= 0.0:
		return
	var bar_w := fence_length
	var bar_h := 5.0
	var bar_y := -(fence_thickness * 0.5 + 12.0)
	_bar_layer.draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.1, 0.8))
	var fill_col := Color(0.9, 0.25, 0.15).lerp(Color(0.35, 0.85, 0.3), _fold_meter)
	_bar_layer.draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * _fold_meter, bar_h), fill_col)
