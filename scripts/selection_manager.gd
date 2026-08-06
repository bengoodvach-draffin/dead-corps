extends Node2D
class_name SelectionManager

## Manages unit selection for RTS-style control
## Handles click selection, box selection, group commands, and control groups
##
## Control Groups (RTS standard):
## - Ctrl+1-9: Assign selected units to control group
## - 1-9: Select control group
## - Ctrl+0: Clear control group assignment from selected units

signal selection_changed(selected_units: Array[Unit])

@export var selection_box_color: Color = Color(0.2, 0.8, 0.2, 0.3)
@export var selection_box_border_color: Color = Color(0.2, 0.8, 0.2, 0.8)
@export var selection_box_border_width: float = 2.0

var selected_units: Array[Unit] = []
var is_box_selecting: bool = false
var box_start_pos: Vector2
var box_current_pos: Vector2

## Control groups - maps group number (1-9) to array of units
var control_groups: Dictionary = {}

## Incremented once per issued group move order. Used as the DetHash salt so
## successive orders jitter differently while staying deterministic (spec §10) —
## no live RNG. (Was randf_range; replaced in Phase 0.3.)
var _move_order_counter: int = 0


## The human currently under the cursor while releasable zombies are selected — gets
## the "release here" ring (build-plan 2.4 misclick defense). Cached GameManager for
## the per-frame hover query.
var _hovered_human: Human = null
var _gm_cache: Node = null

## The fixed clicked waypoints of the current group route, for the interim viz (#8). Appended
## on shift+RMB; cleared by a plain command or a new selection. Fixed coords → the drawn line
## stays put (it does NOT recompute from live unit positions each frame).
var _group_route: Array[Vector2] = []

## Held-F time multiplier (the fast-forward affordance). Paired with a matching
## physics_ticks_per_second raise so each tick keeps the exact 1/60 step — the
## sim is tick-identical, just faster (see the F handler for the why).
const FAST_FORWARD_SCALE := 3.0
const BASE_PHYSICS_TICKS := 60

## A mark-mode click this close to the active Mark clears it.
const MARK_CLEAR_RADIUS := 28.0

## MARK MODE (Ben's ruling 2026-07-27, supersedes the RMB-with-nothing-selected
## placement — that grammar was confusing in play): C arms placement, the cursor
## becomes a crosshair, and the NEXT LMB click places/moves/clears the mark
## (then disarms). C again / Esc / RMB cancels without placing. Interim shape —
## the verb is parked pending a workshop.
var _mark_mode: bool = false

func _ready() -> void:
	set_process_input(true)

	# Fast-forward hygiene: Engine singleton state SURVIVES a scene reload — a
	# restart mid-held-F would otherwise leave the game running at 3×. The
	# cursor shape is the same kind of global (a restart mid-mark-mode would
	# strand the crosshair).
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = BASE_PHYSICS_TICKS
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	# Initialize control groups
	for i in range(1, 10):
		control_groups[i] = []


## Per-frame: keep the release-hover highlight in sync with the cursor (recomputed
## each frame so it tracks both cursor and human movement). Cheap — one radius query.
func _process(_delta: float) -> void:
	_prune_selection()
	_update_release_hover()
	queue_redraw()   # keep the group-route viz anchored as the selection moves (#8)


## Selection hygiene (2026-07-28): drop members that stopped being
## selection-worthy — freed/dead units, and ferals off on a genuine hunt (a
## selected calm zombie ignited by contagion, say). Calm door-breachers are
## simply calm, so they ride the selection through the pound and are still
## selected when the door falls. Pure UI, no sim effect.
func _prune_selection() -> void:
	var removed := false
	for i in range(selected_units.size() - 1, -1, -1):
		var u: Unit = selected_units[i]
		if is_instance_valid(u) and _selection_keeps(u):
			continue
		selected_units.remove_at(i)
		if is_instance_valid(u):
			u.deselect()
		removed = true
	if removed:
		selection_changed.emit(selected_units)


## Whether a (valid) selected unit still belongs in the selection: calm zombies,
## finishers, pending-rise corpses.
func _selection_keeps(u: Unit) -> bool:
	if u is Zombie:
		var z := u as Zombie
		return z.is_selectable() or z.is_finishing_kill()
	if u is Human:
		return (u as Human).is_selectable_corpse()
	return true

func _input(event: InputEvent) -> void:
	# MARK MODE intercepts the mouse while armed: LMB places, RMB/Esc cancels.
	# Checked first so an armed click can never start a box-select underneath.
	if _mark_mode:
		if event.is_action_pressed("select"):
			_place_mark_at_cursor()
			_set_mark_mode(false)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("command") \
				or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			_set_mark_mode(false)
			get_viewport().set_input_as_handled()
			return

	# Handle selection
	if event.is_action_pressed("select"):
		start_selection(event.position)
	elif event.is_action_released("select"):
		end_selection(event.position)
	elif event is InputEventMouseMotion and is_box_selecting:
		update_selection_box(event.position)
	
	# Handle commands
	elif event.is_action_pressed("command"):
		handle_command(event.position)
	
	# FAST-FORWARD (Ben's ruling 2026-07-24): hold F for 3× time. BOTH knobs are
	# set so the physics DELTA stays exactly 1/60: Godot scales the tick delta by
	# time_scale (delta = time_scale / ticks_per_second — measured 0.05 at plain
	# 3×, which coarsened every integration step and flipped level outcomes).
	# 3× ticks_per_second × 3× time_scale = 3× as many ticks of the SAME 1/60
	# step → a tick-identical sim, just faster (§10-safe, verified boot-to-boot).
	elif event is InputEventKey and event.keycode == KEY_F and not event.echo:
		if event.pressed:
			Engine.physics_ticks_per_second = BASE_PHYSICS_TICKS * int(FAST_FORWARD_SCALE)
			Engine.time_scale = FAST_FORWARD_SCALE
		else:
			Engine.time_scale = 1.0
			Engine.physics_ticks_per_second = BASE_PHYSICS_TICKS

	# U = RESTART (spec §5.1 input sheet; Tier-4). Same path as the debug
	# overlay's Reset button; _ready normalizes the fast-forward state after.
	# Moved off R (Ben, 2026-08-06): R sat next to the E roundup key and a
	# fat-finger wiped the whole run.
	elif event is InputEventKey and event.pressed and event.keycode == KEY_U and not event.echo:
		get_tree().reload_current_scene()

	# Q / E — reserve roundup (Ben's ruling 2026-07-26): Q selects every calm
	# zombie on the map; E only those on screen. Rounds up fresh risers without
	# walking back through the killing fields. Ferals excluded (not selectable);
	# corpses and finishing zombies stay box-select-only for now.
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and not event.echo:
		_select_all_calm(false)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_E and not event.echo:
		_select_all_calm(true)

	# C — arm/disarm MARK MODE (Ben's ruling 2026-07-27).
	elif event is InputEventKey and event.pressed and event.keycode == KEY_C and not event.echo:
		_set_mark_mode(not _mark_mode)

	# Handle control group hotkeys
	elif event is InputEventKey and event.pressed:
		handle_control_group_input(event)

func _draw() -> void:
	if is_box_selecting:
		draw_selection_box()
	_draw_group_route()


## Draws the group-route viz (#8): dots at each shift-clicked waypoint, lines between — the
## actual clicked path (one line, which is the averaged centre line for free). Fixed coords,
## so it doesn't wander as the units move; cleared on a plain command / new selection. Drawn in
## SelectionManager's space (untransformed = world), so the stored world points are used directly.
func _draw_group_route() -> void:
	if _group_route.is_empty():
		return
	var col := Color(1.0, 1.0, 1.0, 0.5)
	var prev: Vector2 = _group_route[0]
	draw_circle(prev, 4.0, col)
	for i in range(1, _group_route.size()):
		var p: Vector2 = _group_route[i]
		draw_line(prev, p, col, 2.0)
		draw_circle(p, 4.0, col)
		prev = p

## Handles control group hotkey inputs (Ctrl+1-9, 1-9, Ctrl+0)
func handle_control_group_input(event: InputEventKey) -> void:
	var ctrl_pressed := event.ctrl_pressed or event.meta_pressed  # Meta for Mac
	
	# Get the number key pressed (1-9)
	var group_number := -1
	
	# Check number keys 1-9
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		group_number = event.keycode - KEY_0
	# Check numpad 1-9
	elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
		group_number = event.keycode - KEY_KP_0
	# Check 0 key for clearing
	elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
		if ctrl_pressed:
			clear_control_group_from_selection()
		return
	
	if group_number == -1:
		return
	
	# Assign or recall control group
	if ctrl_pressed:
		# Ctrl+Number: Assign current selection to control group
		assign_control_group(group_number)
	else:
		# Number alone: Select control group
		recall_control_group(group_number)

## Assigns the current selection to a control group
## Replaces any existing units in that group
func assign_control_group(group_number: int) -> void:
	if selected_units.is_empty():
		return

	# First, clear visual numbers from any units currently in this group
	var old_group_units: Array = control_groups.get(group_number, [])
	for old_unit in old_group_units:
		if is_instance_valid(old_unit):
			old_unit.clear_control_group_number()

	# Zombies join the group now; a selected CORPSE instead records the group on its riser
	# entry (6b) so the risen zombie joins on rise — putting the corpse node in the group
	# would leave a stale ref when it frees. Old assignments clear only for the units we keep.
	var gm := _game_manager()
	var valid_units: Array = []
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		if unit is Human and (unit as Human).is_selectable_corpse():
			if gm != null:
				gm.queue_rise_group(unit, group_number)
			unit.set_control_group_number(group_number)   # show the number on the corpse now (6b)
			continue
		remove_unit_from_all_groups(unit)
		valid_units.append(unit)

	control_groups[group_number] = valid_units

	# Update visual numbers on units
	for unit in valid_units:
		unit.set_control_group_number(group_number)

	if GameConfig.debug_logs:
		print("Assigned %d units to control group %d" % [valid_units.size(), group_number])

## Selects all units in a control group
func recall_control_group(group_number: int) -> void:
	var group_units: Array = control_groups.get(group_number, [])
	
	# Clean up dead units from group
	group_units = group_units.filter(func(u): return is_instance_valid(u))
	control_groups[group_number] = group_units
	
	if group_units.is_empty():
		return

	# Recall the CALM members only (spec §3.1) — released ferals stay in the group
	# (they rejoin when they calm) but can't be selected while feral. "Command the
	# calm, influence the storm."
	clear_selection()
	var recalled := 0
	for unit in group_units:
		if unit is Zombie and not (unit as Zombie).is_selectable():
			continue
		add_unit_to_selection(unit)
		recalled += 1

	if GameConfig.debug_logs:
		print("Recalled control group %d: %d calm of %d" % [group_number, recalled, group_units.size()])

## Clears control group assignment from currently selected units
func clear_control_group_from_selection() -> void:
	if selected_units.is_empty():
		return

	for unit in selected_units:
		if is_instance_valid(unit):
			remove_unit_from_all_groups(unit)
			unit.clear_control_group_number()

	if GameConfig.debug_logs:
		print("Cleared control group assignment from %d units" % selected_units.size())

## Removes a unit from all control groups
func remove_unit_from_all_groups(unit: Unit) -> void:
	for group_number in control_groups:
		var group := control_groups[group_number] as Array
		if unit in group:
			group.erase(unit)

func start_selection(_screen_pos: Vector2) -> void:
	# Convert screen position to world position
	box_start_pos = get_global_mouse_position()
	box_current_pos = box_start_pos
	is_box_selecting = true

	# If not holding shift, clear current selection.
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()

func update_selection_box(_screen_pos: Vector2) -> void:
	box_current_pos = get_global_mouse_position()
	queue_redraw()

func end_selection(_screen_pos: Vector2) -> void:
	# A release with no live press is a stray (e.g. the release of a consumed
	# mark-mode placement click) — acting on it would select from stale coords.
	if not is_box_selecting:
		return
	box_current_pos = get_global_mouse_position()
	
	var box_size := (box_current_pos - box_start_pos).length()
	
	if box_size < 5.0:
		# Single click selection
		handle_click_selection()
	else:
		# Box selection
		handle_box_selection()
	
	is_box_selecting = false
	queue_redraw()

func handle_click_selection() -> void:
	var units := get_tree().get_nodes_in_group("zombies")
	var clicked_unit: Unit = null
	var min_distance := 30.0  # Click tolerance in pixels

	for unit in units:
		if unit is Zombie and ((unit as Zombie).is_selectable() or (unit as Zombie).is_finishing_kill()):
			# global_position — units nested under offset parents (e.g. an encounter
			# container) have local coords nowhere near the click (Tier-4 cluster fix).
			var distance := box_start_pos.distance_to(unit.global_position)
			if distance < min_distance:
				min_distance = distance
				clicked_unit = unit

	# Corpse commands (6a): pending-rise corpses are selectable too — pick the nearest.
	var gm := _game_manager()
	if gm != null:
		for corpse in gm.rising_corpses():
			var d := box_start_pos.distance_to((corpse as Node2D).global_position)
			if d < min_distance:
				min_distance = d
				clicked_unit = corpse

	if clicked_unit:
		if Input.is_key_pressed(KEY_SHIFT):
			toggle_unit_selection(clicked_unit)
		else:
			clear_selection()
			add_unit_to_selection(clicked_unit)

func handle_box_selection() -> void:
	var selection_rect := get_selection_rect()
	var units := get_tree().get_nodes_in_group("zombies")

	for unit in units:
		if unit is Zombie and ((unit as Zombie).is_selectable() or (unit as Zombie).is_finishing_kill()):
			if selection_rect.has_point(unit.global_position):
				add_unit_to_selection(unit)

	# Corpse commands (6a): sweep pending-rise corpses in alongside calm zombies.
	var gm := _game_manager()
	if gm != null:
		for corpse in gm.rising_corpses():
			if selection_rect.has_point((corpse as Node2D).global_position):
				add_unit_to_selection(corpse)

func get_selection_rect() -> Rect2:
	var min_x: float = min(box_start_pos.x, box_current_pos.x)
	var min_y: float = min(box_start_pos.y, box_current_pos.y)
	var max_x: float = max(box_start_pos.x, box_current_pos.x)
	var max_y: float = max(box_start_pos.y, box_current_pos.y)
	
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

func draw_selection_box() -> void:
	var rect := get_selection_rect()
	
	# Draw filled rectangle
	draw_rect(rect, selection_box_color)
	
	# Draw border
	draw_rect(rect, selection_box_border_color, false, selection_box_border_width)

# === MARK MODE (C) ===

## Arm/disarm mark placement. The crosshair cursor is the armed tell.
func _set_mark_mode(armed: bool) -> void:
	_mark_mode = armed
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if armed else Input.CURSOR_ARROW)


## The armed LMB click: clear if on the mark, else place/move it — same
## resolution as always (human rides > occupied-building bullseye > ground).
func _place_mark_at_cursor() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	var world_pos := get_global_mouse_position()
	if gm.mark_active() and world_pos.distance_to(gm.mark_position()) <= MARK_CLEAR_RADIUS:
		gm.clear_mark()
		return
	var mark_human := _human_at(world_pos, gm)
	var mark_building: Node2D = null
	if mark_human == null:
		mark_building = _shelter_building_at(world_pos)
	gm.place_mark(world_pos, mark_human, mark_building)


func handle_command(_screen_pos: Vector2) -> void:
	var world_pos := get_global_mouse_position()
	var gm := get_tree().get_first_node_in_group("game_manager")

	# The Mark is NOT placed here anymore — placement lives behind C (mark
	# mode, Ben's 2026-07-27 ruling). RMB with nothing selected does nothing.
	if selected_units.is_empty():
		return
	var append := Input.is_key_pressed(KEY_SHIFT)   # shift+RMB = queue a waypoint/attack (#8)
	var clicked_human := _human_at(world_pos, gm)

	# Partition the selection into commandable calm zombies, FINISHING zombies
	# (post-kill recovery — orders are stored, applying at calm; the hunt wins if
	# it continues), and pending-rise corpses.
	var calm_zombies: Array[Unit] = []
	var finishers: Array[Unit] = []
	var corpses: Array[Unit] = []
	for u in selected_units:
		if not is_instance_valid(u):
			continue
		if u is Zombie and (u as Zombie).can_receive_command():
			calm_zombies.append(u)
		elif u is Zombie and (u as Zombie).is_finishing_kill():
			finishers.append(u)
		elif u is Human and (u as Human).is_selectable_corpse():
			corpses.append(u)

	if append:
		# SHIFT — extend the route. On an enemy it's an ATTACK terminal (deferred to the end of
		# the route, "attacking is another waypoint"); on ground it's a move waypoint. The click
		# is recorded for the fixed viz line either way.
		_group_route.append(world_pos)
		if clicked_human != null:
			for z in calm_zombies:
				(z as Zombie).queued_attack = clicked_human   # fires when its move route ends
		elif not calm_zombies.is_empty():
			var slots := FormationPlanner.plan(world_pos, calm_zombies, _next_order_salt())
			for i in range(calm_zombies.size()):
				calm_zombies[i].queue_move(slots[i])
		if gm != null:
			for c in corpses:
				gm.queue_rise_waypoint(c, world_pos)   # last waypoint → reclicked at rise
		return

	# PLAIN — single command; REPLACES any queued route/attack, and clears the viz line.
	_group_route.clear()
	if gm != null:
		for c in corpses:
			gm.set_rise_route(c, world_pos)
	# ORDERED KILL (specials spec §3.4, mixed-selection soft default §9.1):
	# costumed specials pick their prey with safely-SHELTERED humans INCLUDED
	# (Ben's playtest find 2026-08-06) — the scalpel reaches through intact
	# walls, because the Trojan payoff IS a kill inside the shelter (§3.5),
	# while releases keep targeting the building. One click, one target,
	# everyone attacks per their nature; cancelable up to the lunge. The
	# special stays SELECTED throughout.
	var killers: Array[Zombie] = []
	for u in selected_units:
		if is_instance_valid(u) and u is Zombie and (u as Zombie).can_receive_command() \
				and u.has_method("order_kill") and (u as Zombie).is_perception_hidden():
			killers.append(u)
	var kill_target: Human = clicked_human
	if kill_target == null and not killers.is_empty():
		kill_target = _human_at(world_pos, gm, true)   # sheltered occupants are valid scalpel prey
	if kill_target != null:
		for k in killers:
			k.order_kill(kill_target)

	if clicked_human != null:
		# Immediate release now (attack, forget the route). Pin-and-aim (magnetism #1).
		# Finishers store the attack — it fires when they calm, or drops if they retarget.
		for f in finishers:
			(f as Zombie).queue_finish_attack(clicked_human)
		_release(clicked_human.global_position, gm)
		for k in killers:
			if is_instance_valid(k):
				add_unit_to_selection(k)
		return
	# RELEASE-AT-THE-BUILDING (buildings spec §5.1 + the footprint amendment): RMB
	# anywhere on an OCCUPIED intact building = a release variant — each selected
	# calm zombie besieges its own nearest door. Still exactly one attack verb.
	# Finishers just walk toward it once calm (a stored re-siege would outlive the
	# click's context — keep the stored order to the simple verbs).
	var clicked_building := _shelter_building_at(world_pos)
	if clicked_building != null and not calm_zombies.is_empty():
		for f in finishers:
			(f as Zombie).queue_finish_move(world_pos)
		_release_at_building(clicked_building, calm_zombies, world_pos, kill_target != null)
		return
	# ORDERED CALM BREACH (Ben's ruling 2026-07-30, supersedes release-on-door):
	# RMB on any INTACT door — a gate in a wall, an empty building's door — sends
	# the selected calm zombies to break that specific one. They stay CALM: this
	# is the explicit form of what a move order does incidentally, not a release.
	# Release is for prey (humans, occupied buildings); orders are for terrain.
	var clicked_door := _door_at(world_pos)
	if clicked_door != null and not calm_zombies.is_empty():
		for f in finishers:
			(f as Zombie).queue_finish_move(world_pos)
		_order_breach_at_door(clicked_door, calm_zombies)
		return
	# ORDERED PRESS (fences spec §A7): RMB on an intact fence = a plain calm
	# move order with slots spread ALONG the span's near side, so the crew
	# arrives across the strip instead of funnelling into one point. Not a new
	# verb and not a commitment — any later order cancels it, selection kept.
	# Release-on-fence does not exist: release is for prey, orders are for terrain.
	var clicked_fence := _fence_at(world_pos)
	if clicked_fence != null and not calm_zombies.is_empty():
		for f in finishers:
			(f as Zombie).queue_finish_move(world_pos)
		_order_press_at_fence(clicked_fence, calm_zombies)
		return
	var movers: Array[Unit] = calm_zombies + finishers
	if not movers.is_empty():
		var slots := FormationPlanner.plan(world_pos, movers, _next_order_salt())
		for i in range(movers.size()):
			var z := movers[i] as Zombie
			if z.can_receive_command():
				z.set_move_target(slots[i])
				z.queued_attack = null
			else:
				z.queue_finish_move(slots[i])   # applies at calm; void if the hunt continues


## RELEASE (2.4, spec §5.2): every selected calm zombie ignites FERAL, seeded across
## the cluster of humans near the CLICK. Candidates = living humans within
## release_cluster_radius of click_pos (the clicked human is always one — distance ~0).
## First pass assigns one feral per human (greedy nearest-pairs); any remaining ferals
## distribute evenly (least-loaded human, nearest tiebreak). No per-human cap —
## pounce-exclusion (§3.5) prevents real pile-ups. Then hunt-pool rules (§3.4) govern.
## Released zombies leave the selection — released is released. Deterministic (§10):
## all ordering breaks on unit_uid, no RNG.
func _release(click_pos: Vector2, gm: Node) -> void:
	if gm == null:
		clear_selection()
		return

	# Candidate humans: living, within the cluster radius of the click. SAFELY
	# sheltered humans are excluded (buildings spec §6.1 — not valid targets
	# behind intact walls; the building itself is the siege target). Occupants of
	# a breached building seed like anyone.
	var candidates: Array[Human] = []
	for u in gm.neighbours_within(click_pos, GameConfig.release_cluster_radius, &"humans"):
		var h := u as Human
		if h != null and h.is_alive and not h.is_safely_sheltered():
			candidates.append(h)

	# Ferals to seed: the selected calm zombies, in unit_uid order (determinism).
	# Specials never go feral (§3.7 insurance) — they stay selected, unreleased.
	var ferals: Array[Zombie] = []
	for unit in selected_units:
		if is_instance_valid(unit) and unit is Zombie and (unit as Zombie).can_receive_command() \
				and not (unit as Zombie).is_special:
			ferals.append(unit)
	ferals.sort_custom(func(a: Zombie, b: Zombie) -> bool: return a.unit_uid < b.unit_uid)

	if candidates.is_empty() or ferals.is_empty():
		clear_selection()
		return

	var assignment := ReleaseSeeder.assign(ferals, candidates, click_pos)
	for f in assignment:
		(f as Zombie).ignite_feral(assignment[f])
	if GameConfig.debug_logs:
		print("🔥 RELEASE: ", ferals.size(), " zombies across ", candidates.size(), " human(s)")
	clear_selection()


## Nearest living human within release_aim_radius of `pos`, or null (release vs move).
## The radius is the release-magnetism knob (#1): a click this close to a human is a
## release pinned to the nearest one; a direct click is just the degenerate case.
## SAFELY sheltered humans never pin (buildings spec §6.1) — the occupied BUILDING
## is the release target instead; breached-building occupants pin like anyone.
## `include_sheltered` is the COSTUME's pick (specials §3.4/§3.5): the ordered
## kill reaches through intact walls — an occupant is valid scalpel prey.
func _human_at(pos: Vector2, gm: Node, include_sheltered: bool = false) -> Human:
	if gm == null:
		return null
	var humans: Array[Unit] = gm.neighbours_within(pos, GameConfig.release_aim_radius, &"humans")
	var best: Human = null
	var best_dist := INF
	for h in humans:
		if not include_sheltered and (h as Human).is_safely_sheltered():
			continue
		var d := pos.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h
	return best


## RELEASE-AT-THE-BUILDING (step 3): ignite the given calm zombies onto an
## occupied building — each besieges its own nearest door. Uncancelable;
## released zombies leave the selection. Deterministic: unit_uid order.
##
## COSTUMED specials INFILTRATE instead (specials spec §3.3 — Ben's playtest
## find 2026-08-06: this click is the ONLY way to point inside an occupied
## footprint, and the release filter left the costume with no order at all).
## They get a plain calm move to the click point — the door transit carries
## them in through the front door — and STAY SELECTED, mirroring the
## mixed-selection kill grammar: one click, everyone attacks per their nature.
func _release_at_building(building: Node2D, calm_zombies: Array[Unit], click_pos: Vector2,
		killers_already_ordered: bool = false) -> void:
	var ferals: Array[Zombie] = []
	var infiltrators: Array[Zombie] = []
	for u in calm_zombies:
		if not is_instance_valid(u) or not (u is Zombie) or not (u as Zombie).can_receive_command():
			continue
		if (u as Zombie).is_perception_hidden():
			infiltrators.append(u)
		elif not (u as Zombie).is_special:
			ferals.append(u)
	ferals.sort_custom(func(a: Zombie, b: Zombie) -> bool: return a.unit_uid < b.unit_uid)
	for z in ferals:
		z.ignite_feral_at_building(building)
	# When the click also pinned a KILL TARGET inside (an occupant — the caller
	# ordered the kill already), the infiltrators' pursuit routes them in by
	# itself; a move order here would CANCEL that kill. Otherwise: walk in.
	if not killers_already_ordered:
		for z in infiltrators:
			z.set_move_target(click_pos)
	if not ferals.is_empty() and GameConfig.debug_logs:
		print("🔥 RELEASE: %d zombies onto building %s" % [ferals.size(), building.name])
	if not infiltrators.is_empty() and GameConfig.debug_logs:
		print("🎭 INFILTRATE: %d costume(s) walking into %s" % [infiltrators.size(), building.name])
	clear_selection()
	for z in infiltrators:
		if is_instance_valid(z):
			add_unit_to_selection(z)


## ORDERED CALM BREACH: send the calm zombies to break one specific door. A
## plain calm order — they stay CALM, stay selected, and any new order cancels
## it; nothing here is a commitment. Deterministic: unit_uid order.
##
## This is what release-on-door became (Ben's ruling 2026-07-30). The old verb
## ignited them, which cost the player the crew for no mechanical gain — the
## pound damage is identical either way, so the frenzy bought nothing. It also
## read as backwards next to calm auto-breach: clicking the door deliberately
## gave you LESS control than blundering into it.
func _order_breach_at_door(door: Node2D, calm_zombies: Array[Unit]) -> void:
	var crew: Array[Zombie] = []
	for u in calm_zombies:
		if is_instance_valid(u) and u is Zombie and (u as Zombie).can_receive_command() \
				and not (u as Zombie).is_special:
			crew.append(u)
	crew.sort_custom(func(a: Zombie, b: Zombie) -> bool: return a.unit_uid < b.unit_uid)
	for z in crew:
		z.order_breach(door)


## ORDERED PRESS (fences spec §A7): an ordinary move order per crew member, to
## slots spread evenly along the fence's near side (unit_uid order — same shape
## as _order_breach_at_door). The crew stays CALM, stays selected, and presses
## by simply jamming on the barrier; leaving is one click away.
func _order_press_at_fence(fence: Node2D, calm_zombies: Array[Unit]) -> void:
	var crew: Array[Zombie] = []
	for u in calm_zombies:
		if not is_instance_valid(u) or not (u is Zombie) or not (u as Zombie).can_receive_command():
			continue
		# COSTUMED specials join the press (Ben's ruling 2026-08-06: pressing
		# is physical mass, not perception) — it's a plain move order, so
		# nothing about the disguise is at stake. Other specials stay excluded.
		if (u as Zombie).is_special and not (u as Zombie).is_perception_hidden():
			continue
		crew.append(u)
	crew.sort_custom(func(a: Zombie, b: Zombie) -> bool: return a.unit_uid < b.unit_uid)
	if crew.is_empty():
		return
	# Approach side = the crew's centroid (deterministic: same members, same side).
	var centroid := Vector2.ZERO
	for z in crew:
		centroid += z.global_position
	centroid /= float(crew.size())
	var slots: Array[Vector2] = fence.press_slots(crew.size(), centroid)
	for i in range(crew.size()):
		crew[i].set_move_target(slots[i])
		crew[i].queued_attack = null


## The intact fence under `pos`, or null. Fences are static per level — cached once.
var _fences_cache: Array = []
var _fences_cached: bool = false

func _fence_at(pos: Vector2) -> Node2D:
	if not _fences_cached:
		_fences_cached = true
		_fences_cache = get_tree().get_nodes_in_group("fences")
	for f in _fences_cache:
		if is_instance_valid(f) and f.is_intact() and f.click_hit(pos):
			return f
	return null


## The intact door under/near `pos` (within its half-width + a small pad), or
## null. Doors are static per level — cached once.
var _doors_cache: Array = []
var _doors_cached: bool = false

func _door_at(pos: Vector2) -> Node2D:
	if not _doors_cached:
		_doors_cached = true
		_doors_cache = get_tree().get_nodes_in_group("shelter_doors")
	var best: Node2D = null
	var best_d := INF
	for door in _doors_cache:
		if not is_instance_valid(door) or not door.is_intact():
			continue
		var d: float = pos.distance_to(door.global_position)
		if d <= door.door_width * 0.5 + 16.0 and d < best_d:
			best_d = d
			best = door
	return best


## The occupied, unbreached ShelterBuilding whose footprint contains `pos`, or
## null. Buildings are static per level — cached once (rule 8: group lookups are
## one-time wiring, and the hover check runs per frame).
var _shelters_cache: Array = []
var _shelters_cached: bool = false

func _shelter_building_at(pos: Vector2) -> Node2D:
	if not _shelters_cached:
		_shelters_cached = true
		_shelters_cache = get_tree().get_nodes_in_group("shelter_buildings")
	for b in _shelters_cache:
		if is_instance_valid(b) and b.contains_point(pos) and b.is_occupied() and not b.is_breached():
			return b
	return null


## Updates the release telegraphs: the "release here" ring on the human under the
## cursor, or (step 3) the footprint outline on an occupied building under it —
## only while the selection contains a releasable (calm) zombie. Clears the prior
## hover on any change.
func _update_release_hover() -> void:
	var target: Human = null
	var target_building: Node2D = null
	var target_door: Node2D = null
	var target_fence: Node2D = null
	# The HUMAN ring telegraphs both verbs — release AND the costume's ordered
	# kill (specials §3.4: same pin-and-aim feel). Building/door/fence outlines
	# telegraph release/breach/press and need a genuine RELEASABLE: a lone
	# costume infiltrates via a plain move, so those must stay dark for it
	# (Ben, 2026-08-06).
	var has_releasable := _selection_has_releasable()
	var has_costumed := _selection_has_costumed()
	if has_releasable or has_costumed:
		var gm := _game_manager()
		if gm != null:
			var mouse := get_global_mouse_position()
			target = _human_at(mouse, gm)
			var ring_is_sheltered := false
			if target == null and has_costumed:
				# The scalpel's ring reaches sheltered occupants too (§3.5).
				target = _human_at(mouse, gm, true)
				ring_is_sheltered = target != null
			if has_releasable:
				# A sheltered ring doesn't suppress the building outline: in a
				# mixed selection that click means BOTH (costume kills the
				# occupant, normals besiege the shell) — telegraph both.
				if target == null or ring_is_sheltered:
					target_building = _shelter_building_at(mouse)
				if target == null and target_building == null:
					target_door = _door_at(mouse)   # gates + empty buildings' doors (§5.1 telegraph)
				if target == null and target_building == null and target_door == null:
					target_fence = _fence_at(mouse)   # the ordered-press telegraph (fences §A7)
	if target != _hovered_human:
		if _hovered_human != null and is_instance_valid(_hovered_human):
			_hovered_human.set_hover_highlighted(false)
		_hovered_human = target
		if _hovered_human != null:
			_hovered_human.set_hover_highlighted(true)
	if target_building != _hovered_building:
		if _hovered_building != null and is_instance_valid(_hovered_building):
			_hovered_building.set_hover_highlighted(false)
		_hovered_building = target_building
		if _hovered_building != null:
			_hovered_building.set_hover_highlighted(true)
	if target_door != _hovered_door:
		if _hovered_door != null and is_instance_valid(_hovered_door):
			_hovered_door.set_hover_highlighted(false)
		_hovered_door = target_door
		if _hovered_door != null:
			_hovered_door.set_hover_highlighted(true)
	if target_fence != _hovered_fence:
		if _hovered_fence != null and is_instance_valid(_hovered_fence):
			_hovered_fence.set_hover_highlighted(false)
		_hovered_fence = target_fence
		if _hovered_fence != null:
			_hovered_fence.set_hover_highlighted(true)


## The building / door / fence currently showing the release-telegraph outline.
var _hovered_building: Node2D = null
var _hovered_door: Node2D = null
var _hovered_fence: Node2D = null


## True if any selected unit is a calm zombie that can actually IGNITE — the
## release/siege/breach/press telegraph gate. Specials are excluded: they never
## release, so lighting release targets for a lone costume was a lie (Ben,
## 2026-08-06).
func _selection_has_releasable() -> bool:
	for u in selected_units:
		if is_instance_valid(u) and u is Zombie and (u as Zombie).can_receive_command() \
				and not (u as Zombie).is_special:
			return true
	return false


## True if any selected unit is a costumed special — the ordered-kill verb's
## own telegraph gate (the human ring only).
func _selection_has_costumed() -> bool:
	for u in selected_units:
		if is_instance_valid(u) and u is Zombie and (u as Zombie).can_receive_command() \
				and (u as Zombie).is_perception_hidden():
			return true
	return false


## Cached GameManager lookup for the per-frame hover query.
func _game_manager() -> Node:
	if _gm_cache == null or not is_instance_valid(_gm_cache):
		_gm_cache = get_tree().get_first_node_in_group("game_manager")
	return _gm_cache


func add_unit_to_selection(unit: Unit) -> void:
	if unit not in selected_units:
		selected_units.append(unit)
		unit.select()
		selection_changed.emit(selected_units)

func toggle_unit_selection(unit: Unit) -> void:
	if unit in selected_units:
		remove_unit_from_selection(unit)
	else:
		add_unit_to_selection(unit)

func remove_unit_from_selection(unit: Unit) -> void:
	if unit in selected_units:
		selected_units.erase(unit)
		if is_instance_valid(unit):
			unit.deselect()
		selection_changed.emit(selected_units)

## Q/E roundup: replaces the selection with every selectable (calm) zombie —
## optionally only those inside the camera's current world-space view rect.
func _select_all_calm(on_screen_only: bool) -> void:
	var gm := _game_manager()
	if gm == null:
		return
	var view := Rect2()
	if on_screen_only:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			on_screen_only = false   # no camera → degrade to select-all
		else:
			var world_size: Vector2 = get_viewport_rect().size / cam.zoom
			view = Rect2(cam.get_screen_center_position() - world_size * 0.5, world_size)
	clear_selection()
	for z in gm.living_zombies():
		if not (z as Zombie).is_selectable():
			continue
		# The COSTUMED special is excluded from the Q/E roundup (specials spec
		# §9.2 soft default): a riser sweep must not yank the infiltrator out
		# of the shelter it took two minutes to walk into. Click, box, and
		# control groups still reach it.
		if (z as Zombie).is_perception_hidden():
			continue
		if on_screen_only and not view.has_point(z.global_position):
			continue
		add_unit_to_selection(z)


## Sets `units` as control group `number` directly (bypassing the selection) —
## the ONLY sanctioned way for other systems to write a group (single owner; no
## cross-owner dict writes). assign_control_group above is the Ctrl+N/selection path.
func set_control_group(number: int, units: Array) -> void:
	control_groups[number] = units.duplicate()
	for u in units:
		if is_instance_valid(u):
			u.set_control_group_number(number)


func clear_selection() -> void:
	for unit in selected_units:
		if is_instance_valid(unit):
			unit.deselect()
	selected_units.clear()
	_group_route.clear()   # a new/cleared selection drops the route viz (#8)
	selection_changed.emit(selected_units)

func get_selected_units() -> Array[Unit]:
	return selected_units


## True if `unit` is in the current selection. GameManager checks this at rise (6a) to
## decide whether to auto-select the risen zombie.
func is_selected(unit: Node) -> bool:
	return unit in selected_units


## Applies a risen zombie's queued order (build-plan 6a), called by GameManager._raise. The
## stored click is re-resolved through the SAME rule as a live RMB: a living human within
## release_aim_radius → ignite feral toward it (attack-at-rise); otherwise → a calm move.
## If it stays calm AND the corpse was still selected, keep the zombie in the selection.
func apply_rise_order(zombie: Zombie, entry: Dictionary, was_selected: bool) -> void:
	var route: Array = entry.get("queued_route", [])
	if not route.is_empty():
		var gm := _game_manager()
		# The LAST waypoint is re-resolved release-or-move ("attacking is another waypoint"):
		# prey there → walk the earlier moves, THEN attack it (queued_attack); else it's a move.
		var last: Vector2 = route[route.size() - 1]
		var human := _human_at(last, gm)
		var move_count := route.size()
		# SPECIALS (specials spec §2.3): a special riser can't release — the
		# prey-click re-resolves to an ORDERED KILL on rise instead (fires
		# after the earlier move waypoints via the queued_attack remap in
		# Zombie._tick_calm, which routes specials to order_kill).
		if human != null:
			move_count -= 1
			zombie.queued_attack = human
		for i in range(move_count):
			if i == 0:
				zombie.set_move_target(route[i])
			else:
				zombie.queue_move(route[i])
	# 6b: join the queued control group, if any — works whether it rose calm or feral (a
	# feral member becomes selectable again once it calms, like any released group member).
	var group: int = entry.get("queued_group", -1)
	if group >= 0:
		_join_control_group(zombie, group)
	if was_selected and zombie.is_selectable():
		add_unit_to_selection(zombie)


## Adds a risen zombie to a control group (build-plan 6b) without disturbing existing members
## and stamps its group number. Used by apply_rise_order for a corpse that was tagged to a group.
func _join_control_group(unit: Node, group_number: int) -> void:
	var g: Array = control_groups.get(group_number, [])
	if unit not in g:
		g.append(unit)
		control_groups[group_number] = g
	unit.set_control_group_number(group_number)


## Formation math lives in formation_planner.gd since the Tier-7 splits — this
## just hands out the per-order DetHash salt (successive orders jitter
## differently while staying deterministic, §10).
func _next_order_salt() -> int:
	_move_order_counter += 1
	return _move_order_counter - 1


## Clears all selections and control groups
## Used when resetting the game to avoid invalid references
func cleanup_all() -> void:
	clear_selection()
	
	# Clear all control groups
	for i in range(1, 10):
		control_groups[i] = []
