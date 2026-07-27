class_name MarkSystem
extends Node2D

## THE MARK (spec §5.4, amended by Ben's field ruling 2026-07-26) — the player's
## in-storm influence verb, owned here as a GameManager child (Tier-7 sibling of
## HuntPool / ViolencePipeline).
##
## THE FIELD MODEL: one Mark, one circle (GameConfig.mark_radius, v0 400px),
## centred on the marked human / building / ground point. The rule compresses to
## one sentence: FERALS INSIDE THE CIRCLE PREFER PREY INSIDE THE CIRCLE.
## Ferals outside never notice it — two separated packs stay independently
## manageable (the conscious trade-off: no cross-map recall; walk the mark to
## the pack instead). FeralBrain consults prey_for() at retarget; the per-feral
## "strictly closer AND within the 250px scan" override lives there, not here.
##
## Placement (SelectionManager, RMB with NOTHING selected): on a human = the
## mark rides them; on an occupied building's footprint = aggro the building
## (bullseye only — a building merely overlapped by the ring is ignored, Ben's
## ruling); on ground = a coordinate mark. RMB on the mark clears it.
##
## Fiction: the pack instinct's attention — a pointed hunger, not an order.
## Bias, not command: it reorders menus, never moves a feral where prey isn't.

enum Mode { NONE, HUMAN, BUILDING, POINT }

const PURPLE := Color(0.65, 0.35, 0.9)

var _gm: Node = null
var _mode: Mode = Mode.NONE
var _human: Human = null
var _building: Node2D = null
var _point: Vector2 = Vector2.ZERO


func setup(gm: Node) -> void:
	_gm = gm
	z_index = 2   # above ground + units, below the HUD


## Places (or moves) the one Mark. Resolution is the caller's (SelectionManager
## reuses its click rules): human beats building beats ground.
func place(pos: Vector2, human: Human, building: Node2D) -> void:
	if human != null:
		_mode = Mode.HUMAN
		_human = human
		print("🟣 MARK: on %s" % human.name)
	elif building != null:
		_mode = Mode.BUILDING
		_building = building
		print("🟣 MARK: aggro %s" % building.name)
	else:
		_mode = Mode.POINT
		_point = pos
		print("🟣 MARK: at %s" % pos.round())
	queue_redraw()


func clear() -> void:
	if _mode == Mode.NONE:
		return
	_mode = Mode.NONE
	_human = null
	_building = null
	print("🟣 MARK: cleared")
	queue_redraw()


func is_active() -> bool:
	return _mode != Mode.NONE


## The field's centre right now (a human mark rides its human).
func centre() -> Vector2:
	match _mode:
		Mode.HUMAN:
			return _human.global_position if is_instance_valid(_human) else global_position
		Mode.BUILDING:
			return _building.centre() if is_instance_valid(_building) else global_position
		Mode.POINT:
			return _point
	return global_position


## THE QUERY (called by FeralBrain at retarget / siege-pull): what does the
## field designate for this feral? Returns a Human (prefer-this-prey), a
## building Node2D (aggro — the brain sieges it), or null (feral outside the
## field, or nothing valid inside it). Deterministic: registry order, strict <.
func prey_for(feral: Zombie) -> Node:
	if _mode == Mode.NONE:
		return null
	var c := centre()
	if feral.global_position.distance_to(c) > GameConfig.mark_radius:
		return null
	match _mode:
		Mode.HUMAN:
			if is_instance_valid(_human) and _human.is_alive and not _human.is_safely_sheltered():
				return _human
			clear()   # prey died / got safe — the attention dissolves
			return null
		Mode.BUILDING:
			if is_instance_valid(_building) and _building.is_occupied():
				return _building
			clear()
			return null
		Mode.POINT:
			# Nearest valid human to the CENTRE, inside the circle (prey-in rule).
			var best: Human = null
			var best_d := INF
			for h in _gm.living_humans():
				if h.is_safely_sheltered():
					continue
				var d: float = c.distance_to(h.global_position)
				if d <= GameConfig.mark_radius and d < best_d:
					best_d = d
					best = h
			return best
	return null


## Presentation only: ride the marked human / keep the ring fresh.
func _process(_delta: float) -> void:
	if _mode == Mode.NONE:
		return
	global_position = centre()
	queue_redraw()


func _draw() -> void:
	if _mode == Mode.NONE:
		return
	# The field ring (Ben's readability set): a very transparent purple disc
	# edge + a firmer rim so the reach reads at a glance.
	draw_arc(Vector2.ZERO, GameConfig.mark_radius, 0.0, TAU, 96, Color(PURPLE, 0.14), 6.0, true)
	draw_arc(Vector2.ZERO, GameConfig.mark_radius, 0.0, TAU, 96, Color(PURPLE, 0.35), 1.5, true)
	# The mark itself: decal dot on ground/building, riding circle on a human.
	if _mode == Mode.HUMAN:
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 48, PURPLE, 2.5, true)
	else:
		draw_circle(Vector2.ZERO, 7.0, PURPLE)
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 32, Color(PURPLE, 0.7), 2.0, true)
