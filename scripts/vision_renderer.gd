extends Node2D
class_name VisionRenderer

## THE READABILITY LAYER (Phase 5 scaffold · PERF_REVIEW F4, built 2026-08-03).
##
## One canvas item draws EVERY unit's presentation each frame: selection boxes,
## control-group numbers, class letters, hunted/hover rings, fill lines, corpse
## route cues. This replaces the per-unit machinery those visuals used to live
## in — a Label control or two per unit plus per-unit _draw hooks — which at
## ~500 units meant thousands of canvas items rasterizing whenever the horde
## massed on camera (the measured ~90ms/frame render chug; the sim itself was
## ~5ms/tick). Units now carry only their Sprite; everything informational is
## drawn here, culled to the camera view, in a single item.
##
## PIXEL-PARITY MIGRATION (Ben's ruling 2026-08-03): this pass reproduces the
## old visuals as closely as one canvas item can — same colors, radii, widths,
## offsets. The actual readability DESIGN pass (Phase 5 proper, the M1 Q2 bar)
## iterates on top of this scaffold, with Ben, later. Resist redesigning here.
##
## Reads unit state through public accessors only (rule 5 — no reaching into
## components); the units' rendering accessors were built for exactly this.

# — Selection (the old SelectionIndicator Line2D box, ±15px green) —
const SELECTION_HALF := 15.0
const SELECTION_COLOR := Color(0.2, 0.8, 0.2, 1.0)
const SELECTION_WIDTH := 2.0
# — Human readability rings (values verbatim from human.gd pre-F4) —
const HUNTED_RING_RADIUS := 20.0
const HUNTED_RING_COLOR := Color(0.95, 0.35, 0.15, 0.35)
const HOVER_RING_RADIUS := 24.0
const HOVER_RING_COLOR := Color(1.0, 1.0, 1.0, 0.95)
# — Fill line (fill_behavior debug viz) —
const FILL_COLOR := Color(1.0, 0.85, 0.2, 0.5)
const FILL_REACHED_COLOR := Color(1.0, 0.3, 0.2, 0.5)
const FILL_WIDTH := 2.0
# — Corpse route cue —
const CORPSE_CUE_COLOR := Color(0.55, 0.9, 0.4, 0.55)
# — Special human (specials spec §5): the pink locate read. Toned down from a
#   ring to a pink ★ beside the class stamp (Ben, 2026-08-06 — "a bit much"). —
const SPECIAL_STAR_COLOR := Color(1.0, 0.4, 0.8, 1.0)
# — Text: the old ControlGroupLabel (14px white, 2px black outline, offset
#   right-and-above) and the class letter (16px white, roughly centred). Label
#   rects positioned by top-left; draw_string draws at BASELINE, so the offsets
#   below bake in an ascent correction to land where the labels rendered. —
const GROUP_FONT_SIZE := 14
const GROUP_OFFSET := Vector2(10.0, -9.0)
const GROUP_OUTLINE := 2
const CLASS_FONT_SIZE := 16
const CLASS_OFFSET := Vector2(-5.0, 1.0)
# — Cull margin: covers every offset/radius above plus a body. —
const CULL_MARGIN := 64.0

var _gm: Node = null
var _font: Font = null


func _ready() -> void:
	# World-space overlay above the units (labels used to ride z 10 on children;
	# one layer above the unit plane gives the same stacking).
	z_index = 10
	top_level = true
	global_position = Vector2.ZERO
	_font = ThemeDB.fallback_font
	# GameManager's spawn-if-absent fallback finds us here (older scenes carry a
	# VisionRenderer node; new/bare scenes get one at runtime).
	add_to_group("vision_renderer")


func _process(_delta: float) -> void:
	# One redraw of ONE item per frame — this replaces every per-unit
	# queue_redraw that used to fire on state changes.
	queue_redraw()


func _draw() -> void:
	var gm := _game_manager()
	if gm == null:
		return
	var view := _view_rect()

	for z in gm.living_zombies():
		var pos: Vector2 = z.global_position
		if not view.has_point(pos):
			continue
		if z.is_selected:
			_draw_selection_box(pos)
		if z.control_group_number > 0:
			_draw_group_number(pos, z.control_group_number)

	for h in gm.living_humans():
		var pos: Vector2 = h.global_position
		if not view.has_point(pos):
			continue
		if h.is_hunted():
			draw_arc(pos, HUNTED_RING_RADIUS, 0.0, TAU, 48, HUNTED_RING_COLOR, 2.0, true)
		if h.is_hover_highlighted():
			draw_arc(pos, HOVER_RING_RADIUS, 0.0, TAU, 48, HOVER_RING_COLOR, 2.0, true)
		_draw_fill_line(h, pos)
		var letter: String = h.class_letter()
		if letter != "":
			draw_string(_font, pos + CLASS_OFFSET, letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, CLASS_FONT_SIZE, Color.WHITE)
		# SPECIAL HUMAN (specials spec §5): a pink ★ beside the class stamp —
		# the subtle locate read (the ring was too loud — Ben, 2026-08-06).
		if h.is_special_human():
			var star_at := pos + CLASS_OFFSET + (Vector2(10.0, 0.0) if letter != "" else Vector2.ZERO)
			draw_string(_font, star_at, "★",
				HORIZONTAL_ALIGNMENT_LEFT, -1, CLASS_FONT_SIZE, SPECIAL_STAR_COLOR)
		if h.control_group_number > 0:
			_draw_group_number(pos, h.control_group_number)

	# Pending-rise corpses: selectable + commandable, so they keep their
	# selection box, group number, and the queued-route cue.
	for c in gm.rising_corpses():
		if not is_instance_valid(c):
			continue
		var pos: Vector2 = (c as Node2D).global_position
		if not view.has_point(pos):
			continue
		if c.is_selected:
			_draw_selection_box(pos)
		if c.control_group_number > 0:
			_draw_group_number(pos, c.control_group_number)
		var route: Array = c.queued_route()
		if not route.is_empty():
			var prev := pos
			for p in route:
				draw_line(prev, p as Vector2, CORPSE_CUE_COLOR, 1.5)
				prev = p


## The old SelectionIndicator: a green square outline, ±15px.
func _draw_selection_box(pos: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(SELECTION_HALF, SELECTION_HALF),
		Vector2(SELECTION_HALF * 2.0, SELECTION_HALF * 2.0)),
		SELECTION_COLOR, false, SELECTION_WIDTH)


## The old ControlGroupLabel: white digits, black outline, above-right.
func _draw_group_number(pos: Vector2, number: int) -> void:
	var at := pos + GROUP_OFFSET
	var text := str(number)
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		GROUP_FONT_SIZE, GROUP_OUTLINE, Color.BLACK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		GROUP_FONT_SIZE, Color.WHITE)


## The fill-front debug line, verbatim logic from the old Human._draw_fill_line:
## defenders and sheltered garrisons only; toward the live target or the
## door-watch point; length clamped; orange filling, red once reached.
func _draw_fill_line(h: Human, pos: Vector2) -> void:
	if h.current_state != Human.State.IDLE and h.current_state != Human.State.SENTRY \
			and h.current_state != Human.State.SHELTERED:
		return
	# Sheltered lines are ARMED-ONLY (Ben, 2026-08-06): a sheltered civilian never
	# ticks its fill front, so anything it could show is stale state, not a lane.
	if h.current_state == Human.State.SHELTERED and not h.is_armed():
		return
	var front: FillBehavior = h.fill_front()
	if front == null:
		return
	var end_g: Vector2
	var t := front.current_target()
	if t != null and is_instance_valid(t):
		end_g = t.global_position
	elif front.watching():
		end_g = front.watch_pos()
	else:
		return
	var length := front.fill_length()
	if length <= 0.0:
		return
	var to := end_g - pos
	if to == Vector2.ZERO:
		return
	var seg_len := minf(length, to.length())
	var col := FILL_REACHED_COLOR if front.is_reached() else FILL_COLOR
	draw_line(pos, pos + to.normalized() * seg_len, col, FILL_WIDTH)


## Camera view rect in world space, grown by the cull margin. No camera (a bare
## test scene) → draw everything.
func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2(Vector2(-1e9, -1e9), Vector2(2e9, 2e9))
	var world_size: Vector2 = get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - world_size * 0.5, world_size) \
		.grow(CULL_MARGIN)


func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm
