class_name DoorBreach
extends RefCounted

## Shared door-breaking mechanics — the pieces the FERAL siege (FeralBrain) and
## the CALM auto-breach (CalmBreach) both need, owned in one place.
##
## A static utility rather than a component, deliberately: behavior components
## never call each other (ARCHITECTURE_GUIDELINES rule 2 — the shell mediates),
## so shared mechanics live here, following the FeralTargeting / DetHash pattern.
##
## Two things are shared: the WEDGE test (am I getting nowhere, and is a door the
## reason?) and the POUND stagger (so a crowd never strikes in unison, §4.3).


## The intact door whose engagement arc contains `zombie`, or null — the wedge
## test both breach paths key on. Scene order (stable) resolves overlapping arcs,
## per §10. Called on the wedge cadence, never per frame, so the group lookup is
## not hot; a live lookup (no cache) is also immune to scene reloads (R restart).
##
## `starts_open` portals report is_intact() false, so an open doorway is never
## mistaken for an obstacle by a crowd queuing through it.
static func door_in_arc(zombie: Node2D) -> Node2D:
	for door in zombie.get_tree().get_nodes_in_group("shelter_doors"):
		if not is_instance_valid(door) or not door.is_intact():
			continue
		if door.in_engagement_arc(zombie.global_position):
			return door
	return null


## DetHash-staggered delay before a besieger's FIRST pound (§4.3). Shared salt —
## calm and feral pounders keep the identical cadence, so a mixed crowd on one
## door reads as one rhythm. No RNG (§10).
static func first_pound_delay(unit_uid: int) -> float:
	return DetHash.hash01(unit_uid, 4501) * GameConfig.pound_interval


## A no-progress bucket, owned one-per-breach-path. Feed it the distance to the
## goal each frame; it reports "wedged" on the frame a door_wedge_window closes
## having gained less than door_wedge_min_progress of ground.
##
## Deliberately much shorter than the §3.4.4 give-up failsafe: that clock has to
## tolerate a slow or queued chase before abandoning a hunt, whereas hitting a
## door should convert to pounding almost immediately (Ben's ruling 2026-07-29).
class Wedge extends RefCounted:
	var _ref_dist: float = INF
	var _timer: float = 0.0

	## Re-baseline the window. INF is the safe "no idea yet" value — the next
	## window closes with apparent infinite progress and simply re-baselines.
	func reset(dist: float) -> void:
		_ref_dist = dist
		_timer = GameConfig.door_wedge_window

	## True on the frame a window closes with no meaningful progress made.
	func check(dist: float, delta: float) -> bool:
		_timer -= delta
		if _timer > 0.0:
			return false
		var progressed := _ref_dist - dist
		_ref_dist = dist
		_timer = GameConfig.door_wedge_window
		return progressed < GameConfig.door_wedge_min_progress
