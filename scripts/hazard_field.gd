class_name HazardField
extends Node

## HazardField — the single referee for all hazard terrain (fences/hazards spec
## §B7). A child system of GameManager alongside HuntPool / ViolencePipeline /
## MarkSystem, reached by one-line delegates and ticked from GM's
## _physics_process.
##
## Why a system and not per-node ticking (which is what Door does): overlapping
## hazards touching one unit need a single deterministic resolution — kills in
## one order, (later) slowest speed factor winning — and per-node ticking would
## make that depend on scene order side effects. Mines and HazardZones are dumb
## geometry and data: they draw themselves and answer questions; only this node
## ticks.
##
## Determinism (§B8): hazards iterate in hazard_uid order (tree order at
## registration, stable per §10); victims resolve nearest-first with the
## registry's unit_uid order breaking distance ties; the sweep cadence is a
## fixed-timestep accumulator. A given field always eats the same zombies in
## the same order.
##
## SLICE SCOPE: mines only. HazardZone handling (SLOW / IMPALE speed factors +
## stake kills) lands with the stakes/wire step — the sweep loop below is the
## seam it plugs into.

var _gm: Node = null

## All hazard nodes in hazard_uid order. Collected ONCE, lazily on the first
## tick rather than in _ready: GameManager (and so this child) readies before
## hand-placed hazard nodes deeper in the tree have joined the group.
var _hazards: Array = []
var _registered: bool = false

## Fixed-timestep sweep accumulator (§B8). The remainder carries over, so the
## cadence never drifts with frame count.
var _accum: float = 0.0


func setup(gm: Node) -> void:
	_gm = gm


## One physics frame (ticked by GameManager, after the registry compaction and
## before the riser pipeline). Accumulates to hazard_scan_interval, then sweeps.
func tick(delta: float) -> void:
	if not _registered:
		_register()
	if _hazards.is_empty():
		return
	_accum += delta
	if _accum < GameConfig.hazard_scan_interval:
		return
	_accum -= GameConfig.hazard_scan_interval
	_sweep()


## First-tick registration: the whole scene tree is ready by now, so group
## membership is complete. Tree order IS hazard_uid order (§10 — stable).
func _register() -> void:
	_registered = true
	_hazards = get_tree().get_nodes_in_group("hazards")
	if not _hazards.is_empty():
		print("✅ HazardField: registered %d hazard(s)" % _hazards.size())


## Units this field slowed last sweep (unit → factor). The single-writer set:
## anyone in it who isn't re-slowed this sweep gets 1.0 restored.
var _slowed: Dictionary = {}


## One sweep, three passes in spec order (§B7): mine kills, IMPALE kills, then
## speed factors. Hazards always in hazard_uid order, victims in unit_uid order.
func _sweep() -> void:
	for h in _hazards:
		if is_instance_valid(h) and h is Mine:
			_tick_mine(h)
	for h in _hazards:
		if is_instance_valid(h) and h is HazardZone and h.is_active() \
				and h.toll_mode == HazardZone.TollMode.IMPALE:
			_impale_kills(h)
	_apply_speed_factors()


## IMPALE (§B6.2): every qualifying zombie dies this sweep — no 1:1 here, the
## bed has as many points as it needs. The directional rule, as amended (Ben
## 2026-08-03): die when the velocity component AGAINST the points exceeds
## impale_min_speed — immune to BOID-jitter phantom kills on safe crossings.
## Mid-pounce zombies are exempt (§B6.4 — a lunge is ballistic and leaps the
## bed clean; contrast mines, which a lunge DOES trigger: pressure vs points).
## Humans never die here — their toll is the weave (speed pass below).
func _impale_kills(zone: HazardZone) -> void:
	var facing := zone.points_direction()
	for u in _gm.neighbours_within(zone.query_centre(), zone.bounding_reach(), &"zombies"):
		var z := u as Zombie
		if z == null or not z.is_alive or z.is_mid_pounce():
			continue
		if z.velocity.dot(facing) >= -zone.impale_min_speed:
			continue   # stationary, brushing, or moving WITH the points — safe
		if not zone.contains(z.global_position):
			continue
		if GameConfig.debug_logs:
			print("💥 STAKES: %s impaled on %s" % [z.name, zone.name])
		_gm.report_hazard_kill(z, zone)


## Speed factors (§B7 step 3) — the ONE writer of Unit.terrain_speed_factor.
## For every living unit inside any armed zone: the SLOWEST applicable factor
## wins (min across zones — order-independent, so overlap is deterministic by
## construction). Units that left every zone get 1.0 restored. SLOW tolls both
## teams; IMPALE tolls humans only (the weave) — zombies crossing with the
## points move at full speed, and the ones moving against are already dead.
func _apply_speed_factors() -> void:
	var factors: Dictionary = {}
	for h in _hazards:
		if not is_instance_valid(h) or not (h is HazardZone) or not h.is_active():
			continue
		var zone: HazardZone = h
		var zf: float = zone.zombie_speed_factor if zone.toll_mode == HazardZone.TollMode.SLOW else 1.0
		var hf: float = zone.human_speed_factor
		if zf < 1.0:
			for u in _gm.neighbours_within(zone.query_centre(), zone.bounding_reach(), &"zombies"):
				if u.is_alive and zone.contains(u.global_position):
					factors[u] = minf(factors.get(u, 1.0), zf)
		if hf < 1.0:
			for u in _gm.neighbours_within(zone.query_centre(), zone.bounding_reach(), &"humans"):
				if u.is_alive and zone.contains(u.global_position):
					factors[u] = minf(factors.get(u, 1.0), hf)
	for u in _slowed:
		if is_instance_valid(u) and not factors.has(u):
			u.terrain_speed_factor = 1.0
	for u in factors:
		u.terrain_speed_factor = factors[u]
	_slowed = factors


## One mine: find the victim, spend the mine, land the kill (§B5).
##
## Victim choice (Ben's ruling 2026-08-03): the NEAREST qualifying body to the
## mine centre, unit_uid breaking distance ties — the registry returns uid
## order, so strict < keeps the lowest uid on equal distance. Zombies always
## qualify (calm, feral, risers-once-alive, specials, and MID-POUNCE — a lunge
## is a low tackle, not a vault; presence is presence); humans only when the
## mine opts in. Corpses and pending-rise bodies are not living units and never
## qualify — though a riser that stands up inside the circle is eaten on the
## next sweep, accepted as-is (visible, rare, thematically right).
func _tick_mine(mine: Mine) -> void:
	if not mine.is_live():
		return
	var centre := mine.global_position
	var victim: Unit = null
	var best_d := INF
	for u in _gm.neighbours_within(centre, mine.trigger_radius, &"zombies"):
		if u.is_alive:
			var d: float = centre.distance_to(u.global_position)
			if d < best_d:
				best_d = d
				victim = u
	if mine.affects_humans:
		for u in _gm.neighbours_within(centre, mine.trigger_radius, &"humans"):
			if u.is_alive:
				var d: float = centre.distance_to(u.global_position)
				if d < best_d:
					best_d = d
					victim = u
	if victim == null:
		return
	# EXACTLY ONE body dies — 1:1 is the mine's whole identity (ruling 4), and
	# the self-consuming mine is what makes the corpse road free (ruling 5).
	# Shaped as best-first selection so a future area-of-effect variant (Ben,
	# 2026-08-03 — testing option) is a kill-cap change, not a rewrite; note
	# ruling 5 (area kill-zones do NOT pave) would need re-judging with it.
	mine.spend()   # before the kill: nothing a death cascades into may re-trigger this mine
	if victim is Zombie:
		_gm.report_hazard_kill(victim, mine)
	else:
		# Human (affects_humans, §B5.2): unscored, NO riser — the death never
		# enters register_pounce_kill, so kill-context riser denial is free.
		# Herding prey across your own minefield throws the body away. The
		# human_died signal carries the win check from here.
		victim.take_damage(1.0)
	if GameConfig.debug_logs:
		print("💥 MINE: %s detonates under %s" % [mine.name, victim.name])
