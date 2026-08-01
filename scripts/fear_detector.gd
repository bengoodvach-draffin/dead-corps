class_name FearDetector
extends Node

## Fear-radius break (build-plan 3.3, spec §4.2). A behavior component (child of the
## Human shell), ticked by the dispatcher while the human is defending — independent
## of the fill.
##
## Each frame it counts living zombies within fear_radius (NO line of sight) — ANY
## state counts: calm, feral, or risen. If the count exceeds the class threshold N
## (fear_threshold, indexed by defender_class), the break COMMITS instantly and
## irreversibly: the fill is canceled (no shot can land), a fear_reaction beat is held
## (animation time — the human is frozen, not a last-stand window), then it routs.
##
## Civilians (N=0): any zombie inside the radius breaks them — their second flee path
## (the up-close ambush), complementing the distance-sighting reaction clock (3.2).

var _owner: Human = null
var _gm: Node = null

## Once the threshold trips, the break is committed (spec §4.2 — irreversible, even if
## the zombies scatter during the beat). _beat counts the reaction down to the rout.
var _committed: bool = false
var _beat: float = 0.0

## Scan cadence (perf, 2026-07-30). The count below casts an LOS ray per zombie
## in radius; running it every frame for every defending human made the physics
## queries scale as humans × zombies. Now it runs every fear_scan_interval, with
## the PHASE staggered per unit so the crowd doesn't all scan on the same tick.
##
## The stagger is primed on the first tick rather than in setup(): components are
## built in _ready, but unit_uid isn't assigned until registration, so seeding it
## early would hand every human the same offset. DetHash, not RNG (§10).
const SCAN_SALT := 8117
var _scan_timer: float = 0.0
var _scan_primed: bool = false


func setup(owner_human: Human) -> void:
	_owner = owner_human


## True from the instant a break commits through the reaction beat (and the frame it
## transitions to FLEEING). The dispatcher freezes movement + skips the fill while true.
func is_breaking() -> bool:
	return _committed


func tick(delta: float) -> void:
	if _committed:
		_beat -= delta
		if _beat <= 0.0:
			# The beat is over — the break RESOLVES into the rout. Clearing the
			# flag matters: it used to latch true forever, which was harmless
			# while only the defending branch read it, but the step-6 SHELTERED
			# branch also freezes on is_breaking() — a stale flag froze every
			# entrant on the threshold ("humans can't enter the building").
			_committed = false
			_owner.start_fleeing()
		return

	if not _scan_primed:
		# Spread the crowd's first scan across one interval, then hold cadence.
		_scan_primed = true
		_scan_timer = DetHash.hash01(_owner.unit_uid, SCAN_SALT) * GameConfig.fear_scan_interval
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer += GameConfig.fear_scan_interval

	var gm := _game_manager()
	if gm == null:
		return

	# Count living zombies (any state) within the fear radius, BUILDING-LOS gated (a
	# solid building blocks dread; friendly humans don't — fear isn't a shot). A zombie
	# behind a wall doesn't count; one in the open or emerging from cover does (§4.2 ambush).
	#
	# BREACHED-SHELTER exception (Ben's ruling 2026-07-26, sharpens §8.2): inside a
	# breached building the DISTANCE cap drops — panic propagates by SIGHT alone,
	# so everyone who can see the breach-point ferals (or the horde through the
	# hole) breaks the moment the door falls. Interior walls still stage the sweep
	# room by room; outdoor fear keeps its 250px tuning; armed sheltered humans
	# never tick fear at all (the last stand, §7.2).
	var count := 0
	var pool: Array
	if _owner.is_sheltered() and not _owner.is_safely_sheltered():
		pool = gm.living_zombies()
	else:
		# Unsorted: this is a count — order can't matter.
		pool = gm.neighbours_within(_owner.global_position, GameConfig.fear_radius, &"zombies", null, false)
	for u in pool:
		if _has_los(u):
			count += 1
	if count > _threshold():
		# Break commits this instant: cancel the fill so no shot lands during the beat.
		_committed = true
		_beat = GameConfig.fear_reaction
		_owner.cancel_fill()


func _threshold() -> int:
	return GameConfig.fear_threshold[_owner.defender_class]


## True if no building or intact door blocks the line from this human to `zombie`
## (environment + DoorLOS — humans do NOT block fear; a sheltered human stays calm
## while ferals pound the door, buildings spec §5.3). global_position-based;
## excludes self and the target.
func _has_los(zombie: Unit) -> bool:
	var space := _owner.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_owner.global_position, zombie.global_position)
	query.collision_mask = 17   # Environment (1) + intact-door "DoorLOS" blockers (16)
	query.exclude = [_owner, zombie]
	return space.intersect_ray(query).is_empty()


## Lazily resolves the GameManager (the unit registry). Cached after first use.
func _game_manager() -> Node:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
	return _gm
