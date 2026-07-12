extends Node
class_name GameManager

## Main game manager that coordinates all gameplay systems
## Handles zombie conversion, spawning, escape tracking, and game state

signal human_escaped()
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

## Pending risers (spec §3.6, build-plan 2.6): killed humans waiting to stand back
## up as CALM zombies. Each entry = { "corpse": Human, "pos": Vector2, "time_left":
## float }. Filled on a kill (clock starts at the pounce landing), counted down in
## _physics_process (fixed timestep → deterministic, §10), and raised at zero.
var _pending_risers: Array[Dictionary] = []

## Monotonic source for unit_uid. Assigned in registration order and never
## reused — this is what makes the registry's query results stable-ordered (§10).
var _next_unit_uid: int = 0

## Counter for humans that successfully escaped to the safe zone
var escaped_humans: int = 0

## Number of zombies at game start (usually 6)
var starting_zombie_count: int = 0

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
	
	# Scoring (4.2): the combo system + its runtime HUD. Combo first so the HUD finds it.
	combo = ComboSystem.new()
	combo.name = "ComboSystem"
	add_child(combo)
	var hud := ComboHUD.new()
	hud.name = "ComboHUD"
	add_child(hud)

	# CRITICAL FIX: Register manually placed units
	# When users manually place zombies/humans in the editor, they need to be tracked
	await get_tree().process_frame  # Wait for all nodes to be ready
	register_manually_placed_units()


func _process(delta: float) -> void:
	# Track game time (only while game is running)
	if not game_ended:
		game_time += delta


func _physics_process(delta: float) -> void:
	# Riser countdowns tick on the physics step (fixed timestep → deterministic).
	if not game_ended:
		_tick_risers(delta)

func spawn_zombie(pos: Vector2) -> Zombie:
	if not zombie_scene:
		push_error("Zombie scene not set in GameManager!")
		return null
	
	var zombie: Zombie = zombie_scene.instantiate()
	zombie.position = pos
	units_parent.add_child(zombie)
	_register_zombie(zombie)
	return zombie

func spawn_human(pos: Vector2) -> Human:
	if not human_scene:
		push_error("Human scene not set in GameManager!")
		return null
	
	var human: Human = human_scene.instantiate()
	human.position = pos
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

func _on_zombie_killed_human(human: Human, zombie: Zombie) -> void:
	# Violence contagion (spec §3.3, build-plan 2.5): a kill ignites idle zombies
	# near the kill site.
	# (The gunfire-death half of the trigger waits for Phase 3.)
	_apply_contagion(human.global_position, zombie)

	# Risers (spec §3.6, build-plan 2.6): the corpse stands back up CALM after
	# rise_time, measured from this instant (= the pounce landing, where the kill
	# signal fires). Position captured now so a freed corpse can't strand the rise.
	_pending_risers.append({
		"corpse": human,
		"pos": human.global_position,
		"time_left": GameConfig.rise_time,
	})

	# Scoring (spec §6.1, build-plan 4.2): a pounce kill feeds the combo (gunfire deaths
	# don't reach here — they're the player's losses, not scored).
	if combo != null:
		combo.register_kill(human)


## Counts down pending risers each physics frame and raises any whose clock hit zero
## (spec §3.6). Fixed timestep keeps timing deterministic (§10). A risen corpse is
## freed and replaced by a fresh CALM zombie at the death spot — governed by normal
## rules from then on (a later nearby kill's contagion may grab it; no auto-rally).
func _tick_risers(delta: float) -> void:
	if _pending_risers.is_empty():
		return
	# Iterate back-to-front so removals don't skip entries.
	for i in range(_pending_risers.size() - 1, -1, -1):
		var entry: Dictionary = _pending_risers[i]
		entry.time_left -= delta
		if entry.time_left <= 0.0:
			_pending_risers.remove_at(i)
			_raise(entry)


## Raises one corpse: frees the dead human (if still valid) and spawns a CALM zombie
## where it fell. The new zombie idle-shambles from its spawn anchor like any calm
## unit and is fully subject to normal rules (contagion, release) from this moment.
func _raise(entry: Dictionary) -> void:
	# UNTYPED read: entry.corpse may be a previously-freed instance (e.g. a human freed by
	# an escape-zone entry the same frame its pounce landed, or a scene reset). A TYPED
	# local (`var corpse: Human = ...`) validates the object on assignment and crashes on a
	# freed instance BEFORE the is_instance_valid guard below can run — that was the captured
	# crash (game_manager.gd:175). Read untyped, then guard.
	var corpse = entry.corpse
	if is_instance_valid(corpse):
		corpse.queue_free()
	else:
		# Diagnostic (rule 2 — confirm the trigger on replication): a corpse freed before it
		# could rise. Log the spot so we can tell an escape-rim race (pos AT an exit) from a
		# benign scene reset. The rise still proceeds from the captured pos (§3.6 intent).
		push_warning("⚠️ _raise: corpse already freed before rise at %s (escape-rim race?)" % entry.pos)
	spawn_zombie(entry.pos)


## Ignites every CALM zombie within contagion_radius of the kill site into the frenzy
## (spec §3.3). The killer is excluded; already-feral neighbours are skipped by the CALM
## guard (a reserve hit by sequential kills ignites once per zombie). Deterministic:
## neighbours_within returns unit_uid order, no RNG (§10).
## `seed_target`, when given, is the human each woken zombie pursues (the gunfire shooter
## — see report_gunfire_kill); null means wake targetless and let FeralBrain retarget the
## nearest prey (the human-kill case, where prey is right there at the kill). Either way,
## after igniting, normal §3.4 feral rules + peel-off govern.
func _apply_contagion(kill_pos: Vector2, killer: Zombie, seed_target: Human = null) -> void:
	for u in neighbours_within(kill_pos, GameConfig.contagion_radius, &"zombies", killer):
		var z := u as Zombie
		if z != null and z.current_state == Zombie.State.CALM:
			z.ignite_feral(seed_target)


## A defender's fill front shot a zombie (build-plan 3.1). Delivers the binary kill,
## then fires the gunfire-death half of violence contagion (spec §3.3 — the trigger
## deferred from 2.5), SEEDING the woken zombies at the shooter. Without the seed they
## wake targetless and instantly calm, since the ranged shooter is usually outside the
## scan radius — so a gunshot draws the nearby horde onto the gunman. The killed zombie
## is marked dead before the query (registry excludes it); no riser (gunfire kills a
## zombie, not a human).
func report_gunfire_kill(zombie: Zombie, shooter: Human) -> void:
	if not is_instance_valid(zombie) or not zombie.is_alive:
		return
	var death_pos := zombie.global_position
	zombie.take_damage(1.0)
	_apply_contagion(death_pos, null, shooter)

func _on_human_died(human: Human) -> void:
	# Remove from tracking array
	all_humans.erase(human)
	
	# Check win condition
	check_win_condition()


## Called when a zombie is removed from the scene tree (died)
## Triggers lose condition check
func _on_zombie_removed(zombie: Zombie) -> void:
	# Remove from tracking array
	all_zombies.erase(zombie)

	# A still-alive zombie leaving the tree means a scene teardown/reload (e.g. the
	# debug Reset button), not a death — don't judge the game during teardown or the
	# draining registry spuriously reads as "all zombies eliminated". Real deaths go
	# through die() (is_alive=false before queue_free), so they still reach the check.
	if is_instance_valid(zombie) and zombie.is_alive:
		return

	# Check lose condition
	check_lose_condition()


## Called when a human successfully escapes to the safe zone
## Increments the escaped counter and removes the human from tracking
func on_human_escaped(human: Human) -> void:
	escaped_humans += 1
	all_humans.erase(human)
	# A fleeing human can be mid-pursuit when it reaches the exit (3.2+) — drop its
	# hunt-pool entry so the freed instance doesn't linger as a stale pursuit key.
	_pursuit_counts.erase(human)
	human_escaped.emit()
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
	
	# Record starting zombie count for scoring
	starting_zombie_count = get_all_zombies().size()
	
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
	
	# Assign first 6 zombies to groups 1-6
	for i in range(min(6, zombies.size())):
		var zombie := zombies[i]
		var group_number := i + 1  # Groups are 1-indexed
		
		# Manually assign to control group (simulating Ctrl+1 through Ctrl+6)
		selection_manager.control_groups[group_number] = [zombie]
		zombie.set_control_group_number(group_number)
		print("Auto-assigned zombie to control group ", group_number)

func get_all_zombies() -> Array[Zombie]:
	# Clean up invalid references
	all_zombies = all_zombies.filter(func(z): return is_instance_valid(z))
	return all_zombies

func get_all_humans() -> Array[Human]:
	# Clean up invalid references
	all_humans = all_humans.filter(func(h): return is_instance_valid(h))
	return all_humans


## === REGISTRY QUERIES (V2) ===
## Living-unit and neighbour lookups for v2 systems (contagion, fear count,
## local scan, awareness, seeding, mark/shamble radii — all radius queries).
##
## ORDERING CONTRACT: results are in unit_uid order by construction. uid is
## assigned in registration order, the tracking arrays only ever append, and
## the validity filtering below preserves relative order. All v2 systems iterate
## these results — NEVER re-sort them by anything non-deterministic (spec §10).
## Internals are a naive O(n) scan: fine at PoC counts; a spatial hash can drop
## in behind this API later (it must still return unit_uid order).

## Living zombies (valid + alive). Dead units are excluded — the corpse-linger
## invariant carried from v1. Liveness is the is_alive flag (HP was removed in
## demolition step 1.3); the "dead excluded" contract holds.
func living_zombies() -> Array[Zombie]:
	var result: Array[Zombie] = []
	for z in get_all_zombies():
		if z.is_alive:
			result.append(z)
	return result


## Living humans (valid + alive). Same dead-exclusion contract as living_zombies().
func living_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in get_all_humans():
		if h.is_alive:
			result.append(h)
	return result


## Living units of `team` (&"zombies" or &"humans") within `radius` of `pos`,
## excluding `exclude` if given. Result is in unit_uid order (inherits the
## living_*() ordering). global_position for all distance math — nested scenes
## break local position (CLAUDE.md invariant).
func neighbours_within(pos: Vector2, radius: float, team: StringName, exclude: Unit = null) -> Array[Unit]:
	var result: Array[Unit] = []
	var pool: Array
	if team == &"zombies":
		pool = living_zombies()
	else:
		pool = living_humans()
	for u in pool:
		if u == exclude:
			continue
		if u.global_position.distance_to(pos) <= radius:
			result.append(u)
	return result


## === HUNT POOL (V2, spec §3.4) ===
## Which humans are being hunted, for feral retargeting. Ferals report up here
## (rule 5) instead of peeking into each other's FeralBrain (rule 8 — the registry
## is the discovery mechanism). A count per human (several ferals may pursue one).

var _pursuit_counts: Dictionary = {}   ## Human → number of ferals pursuing it


## A feral started pursuing this human.
func add_pursuit(human: Human) -> void:
	var was: int = _pursuit_counts.get(human, 0)
	_pursuit_counts[human] = was + 1
	# First pursuer → light the "targeted" readability ring (build-plan 2.4).
	if was == 0 and is_instance_valid(human):
		human.set_hunted(true)


## A feral stopped pursuing this human (retargeted away, calmed, or died).
func remove_pursuit(human: Human) -> void:
	if not _pursuit_counts.has(human):
		return
	var c: int = _pursuit_counts[human] - 1
	if c <= 0:
		_pursuit_counts.erase(human)
		# Last pursuer gone → clear the ring.
		if is_instance_valid(human):
			human.set_hunted(false)
	else:
		_pursuit_counts[human] = c


## Living humans currently pursued by at least one feral — the {pursued} half of
## the hunt pool. Built by filtering living_humans() so the result is unit_uid
## ordered (§10) and never includes dead/freed humans (stale count keys are ignored).
func pursued_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in living_humans():
		if _pursuit_counts.has(h):
			result.append(h)
	return result


## True if any feral is currently pursuing this human — the peel-off scan (2.4)
## skips already-pursued humans so each straggler draws exactly one peeler.
func is_pursued(human: Human) -> bool:
	return _pursuit_counts.has(human)


## The {FLEEING} half of the hunt pool (build-plan 3.2): living humans in the FLEEING
## rout. Filtering living_humans() keeps the result unit_uid ordered (§10) and free of
## dead/freed humans. Ferals retarget onto these with no LOS/distance gate, so a broken
## human draws the hunt across the map (the "overwhelm → produces a runner to chase").
func fleeing_humans() -> Array[Human]:
	var result: Array[Human] = []
	for h in living_humans():
		if h.current_state == Human.State.FLEEING:
			result.append(h)
	return result


## Total zombies for the lose condition (spec §8): living zombies + corpses about to
## rise. Risers count, so there's no false loss in the gap between a kill and the rise.
func get_total_zombie_count() -> int:
	return get_all_zombies().size() + _pending_risers.size()


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
			print("  Registered manually placed zombie: ", zombie.name)

	# Find all humans in the scene
	for human in get_tree().get_nodes_in_group("humans"):
		if human is Human and not all_humans.has(human):
			_register_human(human)
			print("  Registered manually placed human: ", human.name)
	
	print("Registration complete: %d zombies, %d humans" % [all_zombies.size(), all_humans.size()])
