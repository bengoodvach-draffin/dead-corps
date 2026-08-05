extends Node
class_name GameManager

## Main game manager that coordinates all gameplay systems
## Handles zombie conversion, spawning, escape tracking, and game state

signal game_won()
signal game_lost()

@export var zombie_scene: PackedScene
@export var human_scene: PackedScene

var units_parent: Node2D
var all_zombies: Array[Zombie] = []
var all_humans: Array[Human] = []

## Combo / pot scoring (build-plan 4.2). Created in _ready; fed pounce kills from
## _on_zombie_killed_human; finalized at game end. The ComboHUD + end screen read it.
var combo: ComboSystem = null

## Component children (Tier-7 manager splits): the hunt pool (§3.4 pursuit
## claims + pool queries) and the violence pipeline (§3.3 contagion + gunfire,
## §3.6 risers + corpse commands). GameManager keeps one-line delegates for
## their public APIs, so callers never changed. The Mark system (Phase 7) lands
## as a third sibling.
var _hunt: HuntPool = null
var _violence: ViolencePipeline = null
var _mark: MarkSystem = null
var _hazard_field: HazardField = null

## Monotonic source for unit_uid. Assigned in registration order and never
## reused — this is what makes the registry's query results stable-ordered (§10).
var _next_unit_uid: int = 0

## Counter for humans that successfully escaped to the safe zone
var escaped_humans: int = 0

## Timer tracking how long the game has been running (in seconds)
var game_time: float = 0.0

## Whether the game has ended (prevents multiple end screens)
var game_ended: bool = false


func _ready() -> void:
	# Find or create units parent
	units_parent = get_tree().get_first_node_in_group("units_parent")
	if not units_parent:
		units_parent = Node2D.new()
		units_parent.name = "Units"
		add_child(units_parent)
	
	# Component children (Tier-7 splits): hunt pool + violence pipeline.
	_hunt = HuntPool.new()
	_hunt.name = "HuntPool"
	add_child(_hunt)
	_hunt.setup(self)
	_violence = ViolencePipeline.new()
	_violence.name = "ViolencePipeline"
	add_child(_violence)
	_violence.setup(self)
	_mark = MarkSystem.new()
	_mark.name = "MarkSystem"
	add_child(_mark)
	_mark.setup(self)
	_hazard_field = HazardField.new()
	_hazard_field.name = "HazardField"
	add_child(_hazard_field)
	_hazard_field.setup(self)

	# Scoring (4.2): the combo system + its runtime HUD. Combo first so the HUD finds it.
	combo = ComboSystem.new()
	combo.name = "ComboSystem"
	add_child(combo)
	var hud := ComboHUD.new()
	hud.name = "ComboHUD"
	add_child(hud)

	# The perf sampler (Tier 3.6) — loaded by path (no class_name, no editor
	# class-cache dependency), gated at runtime by GameConfig.perf_log.
	var sampler: Node = load("res://scripts/perf_sampler.gd").new()
	sampler.name = "PerfSampler"
	add_child(sampler)
	sampler.setup(self)

	# Since F4 the units carry no presentation of their own — a level without a
	# VisionRenderer node would have no selection boxes at all. Spawn one if the
	# scene didn't (deferred: scene-authored renderers register in their _ready).
	_ensure_vision_renderer.call_deferred()

	# CRITICAL FIX: Register manually placed units
	# When users manually place zombies/humans in the editor, they need to be tracked.
	# PHYSICS frame, not process frame: a render frame holds time_scale-many physics
	# ticks, so waiting on it made the registration tick (= when units first perceive
	# each other) depend on the fast-forward state — a boot-time divergence that
	# flipped level outcomes under held-F. One physics tick is one physics tick.
	await get_tree().physics_frame
	register_manually_placed_units()
	_adopt_shelter_residents()


func _process(delta: float) -> void:
	# Track game time (only while game is running)
	if not game_ended:
		game_time += delta


## Monotonic physics-tick counter since scene start. The deterministic time base
## for per-unit cadence staggering ((sim_tick + unit_uid) % N) — NOT
## Engine.get_physics_frames(), which counts from app launch and so would give
## every R-restart a different phase (§10: a restart must reproduce the run).
var sim_tick: int = 0

## Next sim_tick the repeating perf auto-frenzy fires at (see _physics_process).
var _next_auto_frenzy_tick: int = 0


## True only on the dedicated test level — the auto-frenzy's hard gate.
func _is_perf_test_level() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path.ends_with("level_testing.tscn")


## TRUE per-tick wall time (the 133ms-lock hunt): consecutive GM tick stamps.
## Within a catch-up bundle the gap between two GM ticks is one COMPLETE tick's
## wall cost — scripts, physics server, nav server, everything, including work
## invisible to TIME_PHYSICS_PROCESS. The MIN gap in a window is the purest
## sample (no render between bundle ticks); read+reset by the sampler.
var tick_gap_min_us: int = 0
var tick_gap_sum_us: int = 0
var tick_gap_samples: int = 0
var _last_tick_us: int = 0


func _physics_process(delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	if _last_tick_us > 0:
		var gap := now_us - _last_tick_us
		if tick_gap_min_us == 0 or gap < tick_gap_min_us:
			tick_gap_min_us = gap
		tick_gap_sum_us += gap
		tick_gap_samples += 1
	_last_tick_us = now_us
	sim_tick += 1
	# Roster compaction, once per tick — it used to run inside every registry
	# query (see _compact_registry). Same tree-order guarantee as the nav sync
	# below: this lands before any unit ticks, so queries see a clean roster.
	_compact_registry()
	_rebuild_grids()
	# AUTONOMOUS LOAD TEST (Tier 3.6): at the configured tick, ignite every calm
	# zombie — a full frenzy with nobody at the keyboard. Specials excluded as
	# everywhere. sim_tick-based so two runs of the same scenario ignite on the
	# identical tick (§10 — this is also what the boot-twice determinism diff runs on).
	# REPEATING since 2026-08-03: re-fires every interval rather than once, so a
	# load test sustains a mass-feral frenzy (Ben's captured chug had 325
	# simultaneous ferals — a single ignite wave resolves back to calm and never
	# reproduces that census headlessly).
	# HARD-GATED to level_testing (Ben's ruling 2026-08-05): the flag leaked into
	# a live docks session once (zombies "going feral for no reason") — whatever
	# the config or env vars say, the auto-frenzy can only ever fire on the
	# dedicated perf/mechanics test level.
	if GameConfig.perf_auto_frenzy_delay > 0.0 \
			and _is_perf_test_level() \
			and sim_tick >= _next_auto_frenzy_tick \
			and sim_tick >= int(GameConfig.perf_auto_frenzy_delay * 60.0):
		_next_auto_frenzy_tick = sim_tick + int(GameConfig.perf_auto_frenzy_delay * 60.0)
		# SEEDED like a release, not contagion-style: a targetless ignite retargets
		# from the local scan radius, and a quiet-boot layout (zombies deliberately
		# out of awareness range) means no candidates → every feral calms the same
		# tick it ignited (the first baseline run's silent no-op). Each zombie
		# instead targets its nearest living unsheltered human MAP-WIDE.
		# Deterministic: zombies and humans iterate in uid order, strict nearest.
		var humans := living_humans()
		var ignited := 0
		for z in living_zombies():
			if z.is_special or z.current_state != Zombie.State.CALM:
				continue
			var best: Human = null
			var best_sq := INF
			for h in humans:
				if h.is_safely_sheltered():
					continue
				var d_sq := z.global_position.distance_squared_to(h.global_position)
				if d_sq < best_sq:
					best_sq = d_sq
					best = h
			z.ignite_feral(best)   # null-safe: no prey at all → calms, as designed
			ignited += 1
		print("⏱️ PERF AUTO-FRENZY: ignited %d zombies at tick %d" % [ignited, sim_tick])
	# Nav-map sync per PHYSICS TICK. Godot syncs the NavigationServer once per
	# RENDER frame by default, so under fast-forward (3 ticks/frame) agents path
	# against maps up to 3 ticks stale — enough micro-divergence to flip a level's
	# outcome (found via a held-F playtest). Forcing the sync here couples pathing
	# to the tick stream: the sim is identical at any time_scale or render rate
	# (§10). GameManager ticks before the units (tree order), so every agent
	# queries a fresh map.
	NavigationServer2D.map_force_update(get_viewport().find_world_2d().navigation_map)
	# Riser countdowns tick on the physics step (fixed timestep → deterministic).
	if not game_ended:
		_violence.tick(delta)
		_hazard_field.tick(delta)   # hazard sweep (mines etc.) — after risers, same gate

func spawn_zombie(pos: Vector2) -> Zombie:
	if not zombie_scene:
		push_error("Zombie scene not set in GameManager!")
		return null
	
	var zombie: Zombie = zombie_scene.instantiate()
	# Convert the world-space spawn point into the parent's frame BEFORE add_child,
	# so _ready (anchors, bounds clamp) already sees the final position — and an
	# offset Units parent can't shift the spawn (Tier-4 cluster fix).
	zombie.position = units_parent.to_local(pos)
	units_parent.add_child(zombie)
	_register_zombie(zombie)
	return zombie

func spawn_human(pos: Vector2) -> Human:
	if not human_scene:
		push_error("Human scene not set in GameManager!")
		return null
	
	var human: Human = human_scene.instantiate()
	human.position = units_parent.to_local(pos)   # world→parent frame; see spawn_zombie
	units_parent.add_child(human)
	_register_human(human)
	return human


## === UNIT REGISTRY (V2) ===
## Single owner of unit tracking: assigns the stable unit_uid, appends to the
## tracking array, and wires the unit's signals. Both spawn_*() and
## register_manually_placed_units() route through these so the wiring lives in
## exactly one place (ARCHITECTURE_GUIDELINES rule 1).
##
## Idempotent: a unit already tracked is skipped (the manual-placement path may
## re-encounter an already-spawned unit). uid is assigned in registration order
## and never reused — successive registrations strictly increase it. That, plus
## order-preserving appends and validity filtering, is the ordering contract the
## query helpers below rely on.

func _register_zombie(zombie: Zombie) -> void:
	if all_zombies.has(zombie):
		return
	zombie.unit_uid = _next_unit_uid
	_next_unit_uid += 1
	all_zombies.append(zombie)
	# Guarded so a re-encountered or pre-connected instance can't double-connect.
	if not zombie.zombie_killed_human.is_connected(_on_zombie_killed_human):
		zombie.zombie_killed_human.connect(_on_zombie_killed_human)
	if not zombie.tree_exiting.is_connected(_on_zombie_removed):
		zombie.tree_exiting.connect(_on_zombie_removed.bind(zombie))


func _register_human(human: Human) -> void:
	if all_humans.has(human):
		return
	human.unit_uid = _next_unit_uid
	_next_unit_uid += 1
	all_humans.append(human)
	if not human.human_died.is_connected(_on_human_died):
		human.human_died.connect(_on_human_died)

## Pounce-kill signal handler: the violence pipeline handles contagion + the
## riser; the combo (GM's child) scores it here — gunfire deaths never reach
## this (the player's losses, unscored).
func _on_zombie_killed_human(human: Human, zombie: Zombie) -> void:
	_violence.register_pounce_kill(human, zombie)
	if combo != null:
		combo.register_kill(human)


# === VIOLENCE PIPELINE DELEGATES (owner: violence_pipeline.gd) ===

func report_gunfire_kill(zombie: Zombie, shooter: Human) -> void:
	_violence.report_gunfire_kill(zombie, shooter)


func report_hazard_kill(zombie: Zombie, hazard: Node) -> void:
	_violence.report_hazard_kill(zombie, hazard)


func rising_corpses() -> Array:
	return _violence.rising_corpses()


func set_rise_route(corpse: Human, point: Vector2) -> void:
	_violence.set_rise_route(corpse, point)


func queue_rise_waypoint(corpse: Human, point: Vector2) -> void:
	_violence.queue_rise_waypoint(corpse, point)


func queue_rise_group(corpse: Human, group_number: int) -> void:
	_violence.queue_rise_group(corpse, group_number)


# === MARK DELEGATES (owner: mark_system.gd) ===

func mark_prey_for(feral: Zombie) -> Node:
	return _mark.prey_for(feral)


func place_mark(pos: Vector2, human: Human, building: Node2D) -> void:
	_mark.place(pos, human, building)


func clear_mark() -> void:
	_mark.clear()


func mark_active() -> bool:
	return _mark.is_active()


func mark_position() -> Vector2:
	return _mark.centre()

func _on_human_died(human: Human) -> void:
	# Remove from tracking array
	all_humans.erase(human)
	
	# Check win condition
	check_win_condition()


## Called when a zombie leaves the scene tree — registry bookkeeping ONLY. The
## lose verdict is judged at the death instant (report_gunfire_kill), never here:
## tree exits also happen during scene-reset teardowns, where a draining registry
## spuriously read as "all zombies eliminated" (A4).
func _on_zombie_removed(zombie: Zombie) -> void:
	all_zombies.erase(zombie)


## Called when a human successfully escapes to the safe zone
## Increments the escaped counter and removes the human from tracking
func on_human_escaped(human: Human) -> void:
	escaped_humans += 1
	all_humans.erase(human)
	# A fleeing human can be mid-pursuit when it reaches the exit (3.2+) — drop its
	# hunt-pool entry so the freed instance doesn't linger as a stale pursuit key.
	_hunt.drop(human)
	if GameConfig.debug_logs:
		print("Human escaped! Total escaped: ", escaped_humans)
	
	# Check win condition (all humans either dead or escaped)
	check_win_condition()


## Win (spec §8): no humans remain on the map — all dead/converted or fled. A live
## human is one that's still valid and not a corpse; cowering humans are alive, so they
## count here and must be pounced to end the level (no special case — it just falls out).
func check_win_condition() -> void:
	if game_ended:
		return

	var remaining_humans := 0
	for human in all_humans:
		if is_instance_valid(human) and not human.is_dead:
			remaining_humans += 1

	if remaining_humans == 0:
		game_ended = true
		if combo != null:
			combo.finalize()   # bank any in-progress chain before the end screen reads it
		print("Victory! All humans dealt with! (%d zombies, %d escaped)" % [get_total_zombie_count(), escaped_humans])
		game_won.emit()


## Lose (spec §8): the zombie total reaches zero, with risers counting (get_total_zombie_count).
func check_lose_condition() -> void:
	if game_ended:
		return

	if get_total_zombie_count() == 0:
		game_ended = true
		if combo != null:
			combo.finalize()   # bank any in-progress chain before the end screen reads it
		print("Defeat! All zombies eliminated!")
		game_lost.emit()

func setup_test_scenario() -> void:
	"""Spawn a simple test scenario with a few zombies and humans"""
	# Spawn starting zombies (6 total)
	spawn_zombie(Vector2(-100, 0))
	spawn_zombie(Vector2(-120, 20))
	spawn_zombie(Vector2(-80, -20))
	spawn_zombie(Vector2(-140, 0))
	spawn_zombie(Vector2(-90, 40))
	spawn_zombie(Vector2(-110, -40))

	# Auto-assign control groups to starting zombies (for testing convenience)
	await get_tree().process_frame  # Wait for zombies to be fully initialized
	auto_assign_starting_control_groups()
	
	# Spawn humans (5 total)
	spawn_human(Vector2(100, 50))
	spawn_human(Vector2(120, -30))
	spawn_human(Vector2(150, 0))
	spawn_human(Vector2(80, 80))
	spawn_human(Vector2(140, 60))


## Auto-assigns the first 6 zombies to control groups 1-6
## Called after initial zombie spawn for testing convenience
func auto_assign_starting_control_groups() -> void:
	var zombies := get_all_zombies()
	var selection_manager := get_tree().get_first_node_in_group("selection_manager")
	
	if not selection_manager:
		push_warning("SelectionManager not found - cannot auto-assign control groups")
		return
	
	# Assign first 6 zombies to groups 1-6, through the SelectionManager's own
	# method (single owner of the groups dict — no cross-owner writes).
	for i in range(min(6, zombies.size())):
		var group_number := i + 1  # Groups are 1-indexed
		selection_manager.set_control_group(group_number, [zombies[i]])
		if GameConfig.debug_logs:
			print("Auto-assigned zombie to control group ", group_number)

## The registered rosters. Compaction is NOT done here (see _compact_registry):
## these getters sat underneath every registry query, so the filter() ran — and
## allocated a fresh array — hundreds of times per physics tick. Freed entries
## are dropped once per tick instead, and every consumer validity-checks inline.
func get_all_zombies() -> Array[Zombie]:
	return all_zombies

func get_all_humans() -> Array[Human]:
	return all_humans


## Spawns the readability layer if the scene didn't author one (F4 fallback).
func _ensure_vision_renderer() -> void:
	if get_tree().get_first_node_in_group("vision_renderer") == null:
		var vr := VisionRenderer.new()
		vr.name = "VisionRenderer"
		add_child(vr)


## Drops freed references from both rosters. Called once per physics tick from
## _physics_process, before any unit ticks (GameManager sits above the units in
## tree order — the same ordering guarantee the nav sync relies on).
func _compact_registry() -> void:
	all_zombies = all_zombies.filter(func(z): return is_instance_valid(z))
	all_humans = all_humans.filter(func(h): return is_instance_valid(h))


## === REGISTRY QUERIES (V2) ===
## Living-unit and neighbour lookups for v2 systems (contagion, fear count,
## local scan, awareness, seeding, mark/shamble radii — all radius queries).
##
## ORDERING CONTRACT: results are in unit_uid order. uid is assigned in
## registration order, the tracking arrays only ever append, and the validity
## filtering preserves relative order. All v2 systems iterate these results —
## NEVER re-sort them by anything non-deterministic (spec §10).
##
## The spatial hash promised by the old note landed 2026-07-30 (see below); the
## API and the ordering contract are unchanged.


# === SPATIAL HASH (perf, 2026-07-30) ===
##
## Profiled on level_docks at 16 zombies / 134 humans: neighbours_within was
## 10.13 ms of an 18.46 ms frame — 55% of frametime across 280 calls per tick,
## every one of them a full linear scan of the roster. Most of those calls are
## BOID separation and alignment with radii of 30–45px, i.e. scanning 134 humans
## to find the two standing next to you.
##
## A uniform grid, rebuilt once per tick alongside the roster compaction, so a
## query only visits the cells its circle overlaps. Sized for the DENSE-CROWD
## case (2026-07-30's 447-human blob): the whole point of the grid is that a 30px
## separation query in a packed crowd touches ~its own cell, not the crowd. At
## 256px cells that blob sat in a handful of buckets and every query iterated
## basically everyone — worse than the linear scan it replaced (measured: 1.6ms
## per boid call). Small cells fix density; the HYBRID fallback below covers the
## opposite end (wide queries fall back to a roster scan), so big cells are no
## longer needed for anything.
const GRID_CELL := 64.0

## Snapshot slack: the grid is built at the top of the tick and units move during
## it (~2–3px at current speeds). Queries widen their radius by this instead of
## padding by whole cells — the old ±1-cell pad turned a 30px query's 2×2 cells
## into 4×4, quadrupling the buckets visited for the game's most frequent query.
const GRID_MOVE_SLOP := 8.0

var _grid_zombies: Dictionary = {}
var _grid_humans: Dictionary = {}

## Built once, not per call: the sort below runs on every query, and allocating a
## fresh lambda 280 times a tick was the exact kind of churn this change removes.
var _uid_sorter: Callable = func(a: Unit, b: Unit) -> bool: return a.unit_uid < b.unit_uid


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / GRID_CELL), floori(pos.y / GRID_CELL))


## Rebuilds both grids from the live rosters. Called once per physics tick, right
## after compaction and before any unit ticks.
func _rebuild_grids() -> void:
	_grid_zombies.clear()
	_grid_humans.clear()
	for z in all_zombies:
		if is_instance_valid(z) and z.is_alive:
			_grid_insert(_grid_zombies, z)
	for h in all_humans:
		if is_instance_valid(h) and h.is_alive:
			_grid_insert(_grid_humans, h)


func _grid_insert(grid: Dictionary, u: Unit) -> void:
	var cell := _cell_of(u.global_position)
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append(u)

## Living zombies (valid + alive). Dead units are excluded — the corpse-linger
## invariant carried from v1. Liveness is the is_alive flag (HP was removed in
## demolition step 1.3); the "dead excluded" contract holds.
func living_zombies() -> Array[Zombie]:
	var result: Array[Zombie] = []
	for z in all_zombies:
		if is_instance_valid(z) and z.is_alive:
			result.append(z)
	return result


## Living humans (valid + alive). Same dead-exclusion contract as living_zombies().
func living_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in all_humans:
		if is_instance_valid(h) and h.is_alive:
			result.append(h)
	return result


## Living units of `team` (&"zombies" or &"humans") within `radius` of `pos`,
## excluding `exclude` if given. Result is in unit_uid order (inherits the
## living_*() ordering). global_position for all distance math — nested scenes
## break local position (CLAUDE.md invariant).
## PERF (2026-07-30): this is THE hot path — every unit's BOID separation and
## alignment, every human's fear and fill scan, and two per door, all per physics
## tick, so it runs hundreds of times a frame. It used to build the living roster
## first (`living_zombies()`), which itself called a getter that ran a filter():
## THREE array allocations and three full passes per call. At ~170 units that was
## well over a thousand allocations per tick, which is why adding humans fell off
## a cliff rather than degrading gently.
##
## Now: iterate the roster in place, check validity and liveness inline, and
## compare SQUARED distances (no sqrt per unit). One allocation — the result —
## and one pass. Identical results and identical ordering.
## `sorted = false` skips the uid re-sort (perf): results then follow GRID
## CONSTRUCTION order — buckets are filled in uid order and cells walked in a
## fixed order, so it is still fully deterministic run-to-run, just not globally
## uid-ascending. ONLY order-insensitive aggregations (force sums, counts) may
## pass false; anything that picks "first/nearest wins on tie" needs the sort.
##
## `max_results > 0` stops after that many hits — a deterministic SAMPLE in grid
## order, for statistical consumers (e.g. alignment's average facing). This is
## the answer to the packed-mega-horde case (2026-08-01): when 300 zombies stand
## inside one radius, the query legitimately returns all of them and no spatial
## structure can help — the only fix is not needing all of them. Sample callers
## pass sorted = false; a "sorted sample" would be first-N-found sorted after
## the fact, which no current caller wants.
func neighbours_within(pos: Vector2, radius: float, team: StringName, exclude: Unit = null, sorted: bool = true, max_results: int = 0) -> Array[Unit]:
	var result: Array[Unit] = []
	var grid: Dictionary
	if team == &"zombies":
		grid = _grid_zombies
	else:
		grid = _grid_humans

	var radius_sq := radius * radius
	# Radius + slop covers snapshot staleness (see GRID_MOVE_SLOP) far cheaper
	# than whole-cell padding did.
	var pad := radius + GRID_MOVE_SLOP
	var lo := _cell_of(pos - Vector2(pad, pad))
	var hi := _cell_of(pos + Vector2(pad, pad))

	# HYBRID: a wide query can span more cells than the roster has units, at which
	# point walking the grid costs more than simply scanning everyone. Compare the
	# two up front and take the cheaper — so this is never worse than the linear
	# scan it replaced, whatever radius a caller asks for.
	var pool: Array
	if team == &"zombies":
		pool = all_zombies
	else:
		pool = all_humans
	var cell_count := (hi.x - lo.x + 1) * (hi.y - lo.y + 1)

	if cell_count > pool.size():
		for u in pool:
			if u == exclude or not is_instance_valid(u) or not u.is_alive:
				continue
			if u.global_position.distance_squared_to(pos) <= radius_sq:
				result.append(u)
				if max_results > 0 and result.size() >= max_results:
					return result
		return result   # roster order IS unit_uid order — no sort needed

	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			# One lookup, not has() + [] — this is the innermost loop.
			var bucket = grid.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			for u in bucket:
				if u == exclude or not is_instance_valid(u) or not u.is_alive:
					continue
				if u.global_position.distance_squared_to(pos) <= radius_sq:
					result.append(u)
					if max_results > 0 and result.size() >= max_results:
						return result

	# THE ORDERING CONTRACT (§10): cells are walked in a fixed order, but that
	# isn't unit_uid order, and consumers rely on uid ordering to break ties
	# deterministically. Restore it — but only when there's something to reorder,
	# since most separation queries return one or two units.
	if sorted and result.size() > 1:
		result.sort_custom(_uid_sorter)
	return result


## === HUNT POOL (V2, spec §3.4) ===
## Delegates to hunt_pool.gd (the single owner since the Tier-7 splits). Ferals
## report up here (rule 5) instead of peeking into each other's FeralBrain.


func add_pursuit(human: Human) -> void:
	_hunt.add_pursuit(human)


func remove_pursuit(human: Human) -> void:
	_hunt.remove_pursuit(human)


func pursued_humans() -> Array[Human]:
	return _hunt.pursued_humans()


func is_pursued(human: Human) -> bool:
	return _hunt.is_pursued(human)


func fleeing_humans() -> Array[Human]:
	return _hunt.fleeing_humans()


## Total zombies for the lose condition (spec §8): LIVING zombies + corpses about
## to rise. Living, not registered (A5) — dead zombies linger in all_zombies for
## their corpse-linger frames, which coupled the verdict's timing to framerate.
func get_total_zombie_count() -> int:
	return living_zombies().size() + _violence.pending_count()


## Shelter adoption (Ben's ruling 2026-07-26): humans PLACED inside an intact
## shelter at level start become SHELTERED as if they'd fled in — the occupants
## list is what every siege / flush / pour-in / win system keys off, and
## hand-placed units weren't on it (besiegers calmed at the breach; the building
## read unoccupied). Eligibility: intact `is_shelter` buildings only (dumb boxes
## and ruins keep their bystanders); patrol-enabled humans keep their authored
## routes. Deterministic: buildings in tree order, humans in unit_uid order.
##
## Adoptees HOLD THEIR PLACED POSITION (2026-07-30) — no spot claim, so there's
## no notional entry door to work out either. See Human.adopt_into_shelter.
func _adopt_shelter_residents() -> void:
	for b in get_tree().get_nodes_in_group("shelter_buildings"):
		if not b.is_shelter or b.is_breached():
			continue
		for h in living_humans():
			if h.patrol_enabled or h.is_sheltered():
				continue
			if not b.contains_point(h.global_position):
				continue
			h.adopt_into_shelter(b)


## Registers manually placed units in the scene
## Called during _ready() to track units placed via the editor
## Without this, manually placed units won't trigger win/loss conditions
func register_manually_placed_units() -> void:
	print("Registering manually placed units...")
	
	# Find all zombies in the scene. get_nodes_in_group returns scene-tree order
	# (deterministic), so manually-placed uids are assigned in a stable order.
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Zombie and not all_zombies.has(zombie):
			_register_zombie(zombie)
			if GameConfig.debug_logs:
				print("  Registered manually placed zombie: ", zombie.name)

	# Find all humans in the scene
	for human in get_tree().get_nodes_in_group("humans"):
		if human is Human and not all_humans.has(human):
			_register_human(human)
			if GameConfig.debug_logs:
				print("  Registered manually placed human: ", human.name)
	
	print("Registration complete: %d zombies, %d humans" % [all_zombies.size(), all_humans.size()])
