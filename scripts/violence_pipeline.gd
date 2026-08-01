class_name ViolencePipeline
extends Node

## The violence pipeline — contagion (spec §3.3), gunfire kills, and the riser
## pipeline (§3.6) including corpse commands (6a/6b) — extracted from
## GameManager (Tier-7 manager splits, pre-Mark). GameManager keeps one-line
## delegates for the public API, so all callers are unchanged; the pounce-kill
## SIGNAL handler also stays on GameManager (it feeds the combo there).

var _gm: Node = null

## Cached SelectionManager (corpse commands, 6a) — auto-select + rise-order handoff.
var _selection_mgr: Node = null

## Pending risers: corpses counting down to their CALM rise (spec §3.6).
var _pending_risers: Array = []


func setup(gm: Node) -> void:
	_gm = gm


func pending_count() -> int:
	return _pending_risers.size()


## A pounce kill landed: contagion + queue the riser (called from GameManager's
## zombie_killed_human handler; scoring stays with the combo there).
func register_pounce_kill(human: Human, zombie: Zombie) -> void:
	# Violence contagion (spec §3.3): a kill ignites idle zombies near the kill site.
	apply_contagion(human.global_position, zombie)

	# Risers (spec §3.6): the corpse stands back up CALM after rise_time, measured
	# from this instant (= the pounce landing). Position captured now so a freed
	# corpse can't strand the rise.
	_pending_risers.append({
		"corpse": human,
		"pos": human.global_position,
		"time_left": GameConfig.rise_time,
		# Corpse commands (6a/#8): a queued ROUTE, re-resolved (release-or-move on
		# the FIRST waypoint) when it rises; [] = no order.
		"queued_route": [],
		# Corpse commands (6b): a queued control group (-1 = none) joined on rise.
		"queued_group": -1,
	})
	# The corpse is now a selectable, commandable body until it stands (6a).
	human.mark_pending_rise()


## Ignites every CALM zombie within contagion_radius of the kill site (spec §3.3).
## The killer is excluded; already-feral neighbours are skipped by the CALM guard.
## Deterministic: neighbours_within returns unit_uid order, no RNG (§10).
## `seed_target`, when given, is the human each woken zombie pursues (the gunfire
## shooter); null wakes them targetless (the pounce-kill case — prey is right there).
func apply_contagion(kill_pos: Vector2, killer: Zombie, seed_target: Human = null) -> void:
	for u in _gm.neighbours_within(kill_pos, GameConfig.contagion_radius, &"zombies", killer):
		var z := u as Zombie
		# is_special guard (spec §3.7 insurance): specials never go feral.
		if z != null and z.current_state == Zombie.State.CALM and not z.is_special:
			z.ignite_feral(seed_target)


## A defender's fill front shot a zombie (spec §3.3 gunfire half): binary kill,
## contagion SEEDED at the shooter ("you shot us — we're coming for you"), and
## the lose verdict judged at this death instant (A4/A5 — gunfire is the only
## way a zombie dies in v2, so this is frame-exact and teardown-immune).
func report_gunfire_kill(zombie: Zombie, shooter: Human) -> void:
	if not is_instance_valid(zombie) or not zombie.is_alive:
		return
	var death_pos := zombie.global_position
	zombie.take_damage(1.0)
	apply_contagion(death_pos, null, shooter)
	_gm.check_lose_condition()


## Counts down pending risers each physics frame (ticked by GameManager) and
## raises any whose clock hit zero. Fixed timestep keeps timing deterministic (§10).
func tick(delta: float) -> void:
	if _pending_risers.is_empty():
		return
	# Iterate back-to-front so removals don't skip entries.
	for i in range(_pending_risers.size() - 1, -1, -1):
		var entry: Dictionary = _pending_risers[i]
		entry.time_left -= delta
		if entry.time_left <= 0.0:
			_pending_risers.remove_at(i)
			_raise(entry)


## Raises one corpse: frees the dead human (if still valid) and spawns a CALM
## zombie where it fell, subject to normal rules from that moment.
func _raise(entry: Dictionary) -> void:
	# UNTYPED read: entry.corpse may be a previously-freed instance (e.g. a human
	# freed by an escape-zone entry the same frame its pounce landed, or a scene
	# reset). A TYPED local validates on assignment and crashes on a freed
	# instance BEFORE the guard below can run — that was the captured crash.
	var corpse = entry.corpse
	var sel := _selection_manager()
	# Auto-select (6a): if the corpse was still selected, the risen zombie
	# inherits the selection. Note it BEFORE freeing; drop the stale corpse ref.
	var was_selected := false
	if is_instance_valid(corpse):
		if sel != null:
			was_selected = sel.is_selected(corpse)
			if was_selected:
				sel.remove_unit_from_selection(corpse)
		corpse.queue_free()
	else:
		# Diagnostic (rule 2): a corpse freed before it could rise — log the spot
		# to tell an escape-rim race (pos AT an exit) from a benign scene reset.
		push_warning("⚠️ _raise: corpse already freed before rise at %s (escape-rim race?)" % entry.pos)
	var zombie: Zombie = _gm.spawn_zombie(entry.pos)
	# 6a: replay the queued click (release-or-move) on the fresh zombie.
	if zombie != null and sel != null:
		sel.apply_rise_order(zombie, entry, was_selected)


## The selectable corpses (6a): valid pending-rise humans, unit_uid-ordered (§10).
func rising_corpses() -> Array:
	var out: Array = []
	for entry in _pending_risers:
		var c = entry.corpse
		if is_instance_valid(c) and (c as Human).is_selectable_corpse():
			out.append(c)
	out.sort_custom(func(a, b): return a.unit_uid < b.unit_uid)
	return out


## Replaces the corpse's rise route with a single waypoint (plain RMB, 6a/#8).
## The route lives on the ENTRY so a freed corpse can't strand it.
func set_rise_route(corpse: Human, point: Vector2) -> void:
	for entry in _pending_risers:
		if entry.corpse == corpse:
			entry["queued_route"] = [point]
			if is_instance_valid(corpse):
				corpse.set_queued_route(entry["queued_route"])
			return


## Appends a waypoint to the corpse's rise route (shift+RMB, #8), respecting the cap.
func queue_rise_waypoint(corpse: Human, point: Vector2) -> void:
	for entry in _pending_risers:
		if entry.corpse == corpse:
			var route: Array = entry["queued_route"]
			if route.size() < Unit.MAX_WAYPOINTS:
				route.append(point)   # Array is by-ref → the entry updates in place
				if is_instance_valid(corpse):
					corpse.set_queued_route(route)
			return


## Records a control group on the riser entry (6b) — joined on rise.
func queue_rise_group(corpse: Human, group_number: int) -> void:
	for entry in _pending_risers:
		if entry.corpse == corpse:
			entry["queued_group"] = group_number
			return


## Lazily resolves the SelectionManager (corpse commands, 6a). Cached.
func _selection_manager() -> Node:
	if _selection_mgr == null or not is_instance_valid(_selection_mgr):
		_selection_mgr = get_tree().get_first_node_in_group("selection_manager")
	return _selection_mgr
