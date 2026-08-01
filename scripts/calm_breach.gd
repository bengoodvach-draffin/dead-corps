class_name CalmBreach
extends Node

## CALM AUTO-BREACH (Ben's ruling 2026-07-29) — a behavior component of the
## Zombie shell, ticked from _tick_calm.
##
## A CALM zombie whose ordered move is BLOCKED by an intact door pounds it down
## and carries on. The player expresses "break this" by where the horde is sent,
## not by clicking the door: no pixel-hunting a specific node to open a wall.
##
## This is NOT a siege. There is no prey, no hunt pool, no peel-off, and no state
## change — the zombie stays CALM, selected, and fully commandable; a new order
## cancels the pound instantly (uncommitted, unlike release-on-door, which stays
## as the FERAL variant: ferals peel to live prey and answer the Mark, calm
## breachers ignore humans entirely).
##
## TWO WAYS IN, one loop:
##   - INCIDENTAL: the ordered move makes no ground for a door_wedge_window WHILE
##     the zombie sits in an intact door's engagement arc. Walking PAST a door
##     never fires it (that route is progressing), and a route that detours
##     around the wall through another opening never fires it either — only a
##     door genuinely in the way gets hit.
##   - ORDERED (Ben's ruling 2026-07-30, supersedes release-on-door): the player
##     RMB'd the door itself. No move goal — the door IS the destination, and the
##     zombie stops there once it falls rather than walking on through.
##
## The grammar this completes: RELEASE IS FOR PREY, ORDERS ARE FOR TERRAIN. A
## human or an occupied building ignites the horde; a door is terrain, so it's
## commanded. Breaking one deliberately no longer costs you control of the crew.

var _owner: Zombie = null

## The door being pounded, or null. Doubles as the "am I breaching" state.
var _door: Node2D = null
## True when the door was ordered directly (rather than found in the way): no
## goal to compare against, and it persists until the door falls.
var _ordered: bool = false
## The move goal an INCIDENTAL breach serves. A different destination voids it —
## the old door says nothing about whether the new route is blocked.
var _goal: Vector2 = Vector2.ZERO
## Countdown to the next pound, DetHash-staggered on begin (§4.3).
var _pound_timer: float = 0.0
## No-progress bucket toward the goal; a fired window at a door starts the pound.
var _wedge := DoorBreach.Wedge.new()


func setup(owner_zombie: Zombie) -> void:
	_owner = owner_zombie


## True while pounding a door (readability / debug; Phase 5 draws off this).
func is_breaching() -> bool:
	return _door != null


func current_door() -> Node2D:
	return _door


## Abandon any breach and restart the wedge clock. Called on a new order, on
## going idle, and on ignite/death — nothing about a calm breach is committed,
## ordered ones included.
func cancel() -> void:
	_door = null
	_ordered = false
	_wedge.reset(INF)


## ORDERED BREACH: go break this specific door. A plain calm order — the caller
## has already cleared any move route. Invalid or already-open doors no-op, so
## the click simply does nothing rather than stranding the crew.
func order(door: Node2D) -> void:
	if door == null or not is_instance_valid(door) or not door.is_intact():
		return
	_door = door
	_ordered = true
	_goal = Vector2.ZERO
	_pound_timer = DoorBreach.first_pound_delay(_owner.unit_uid)
	_wedge.reset(INF)


## One frame of calm behaviour. `has_goal`/`goal` are the shell's commanded move
## (if any). Returns TRUE if this component drove movement this frame, meaning
## the shell must NOT also run its own nav move.
func tick(has_goal: bool, goal: Vector2, delta: float) -> bool:
	# ORDERED: the door IS the order. No goal to measure against, no wedge wait —
	# walk to it and pound until it falls (or the player says otherwise).
	if _ordered:
		return _tick_pounding(delta)

	if not has_goal:
		cancel()   # nothing ordered — no route left to unblock
		return false

	if not _goal.is_equal_approx(goal):
		# A new destination (or the first frame of this one): drop any breach and
		# baseline the progress window against the new route.
		cancel()
		_goal = goal
		_wedge.reset(_owner.global_position.distance_to(goal))
		return false

	if _door != null:
		return _tick_pounding(delta)

	if not _wedge.check(_owner.global_position.distance_to(goal), delta):
		return false
	# Going nowhere. If a door is the reason, break it; otherwise this is an
	# ordinary jam (crowd, terrain corner) and the normal move keeps trying.
	var door := DoorBreach.door_in_arc(_owner)
	if door == null:
		return false
	_door = door
	_pound_timer = DoorBreach.first_pound_delay(_owner.unit_uid)
	print("🔨 CALM BREACH: %s pounds %s (blocking its move)" % [_owner.name, door.name])
	return _tick_pounding(delta)


## Press the door and pound on the cadence (§4.3) — identical damage and stagger
## to a feral siege; a door does not care what mood broke it. An incidental
## breach leaves the move order untouched, so when the door falls the shell's nav
## move resumes straight through the hole that very frame; an ordered one has no
## route to resume, so the crew simply stops at the opening it just made.
func _tick_pounding(delta: float) -> bool:
	if not is_instance_valid(_door) or not _door.is_intact():
		cancel()
		return false   # the way is open — hand movement back to the shell now
	_owner.nav_move_toward(_door.global_position, GameConfig.zombie_speed)
	if _door.in_engagement_arc(_owner.global_position):
		_pound_timer -= delta
		if _pound_timer <= 0.0:
			_pound_timer += GameConfig.pound_interval
			_door.apply_pound(GameConfig.pound_damage)
	return true
