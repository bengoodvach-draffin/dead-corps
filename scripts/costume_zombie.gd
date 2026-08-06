extends Zombie
class_name CostumeZombie

## Costume Zombie v2 (specials spec §3) — the Trojan in disguise: undetectable
## while costumed, opens doors like a human, armed with a player-ordered kill.
## REWRITTEN IN PLACE from the dead v1 special (Ben's explicit OK, 2026-08-06):
## the v1 ability text targeted systems the pivot deleted.
##
## SLICE 1 SCOPE (framework): the latch, the identity flags, the pink read.
## While costumed it is CALM-ONLY — never feral, never releasable, immune to
## contagion. That is enforced by `is_special` (the release collectors and the
## contagion guard skip specials) plus the ignite_feral guards in zombie.gd,
## with no code here: this class is deliberately thin.
##
## STILL TO BUILD (later slices — the spec's §3 surface):
##   slice 2 — perception exemptions (§3.2): fill / civilian clock / fear /
##             herding repel / exit filter / door-watch all skip it.
##   slice 3 — door transit (§3.3): passes doors under human admission rules;
##             no burst, no CalmBreach, locked doors bar it.
##   slice 4 — the ordered kill + THE BREAK (§3.4/§3.6): pounce launch drops
##             is_costumed AND is_special permanently — after it, this unit is
##             a mechanically ordinary zombie that happens to be in the room.
##   slice 5 — the compromised rule (§3.5).

## The one latch (§3.1): starts true, breaks permanently at pounce launch
## (slice 4 — the only trigger; nothing else can end it). Checked by other
## systems via duck-typing: `unit.get("is_costumed") == true` (the standing
## special-zombie convention — avoids load-order parse issues).
var is_costumed: bool = true

## Bright pink (§5, carried from v1): unmistakably not zombie green, unmissable
## in a horde — the player-side read is never hidden, only the humans' is.
const COSTUMED_COLOR := Color(1.0, 0.4, 0.8)
## Standard zombie green from the launch frame (§5 — the broken read).
const BROKEN_COLOR := Color(0.4, 0.6, 0.3)

var _body: ColorRect = null


## DOOR TRANSIT (§3.3, built slice 3) — "doors open for it and close behind
## it", mechanically:
##   - collision_mask 9 → 41 while costumed: keeps Environment (1) and the
##     shared barrier bit (8 — escape zones and fences STILL block it), adds
##     the DoorLock bit (32) so an ENGAGED door bars it exactly as it bars a
##     human: no walking the infiltrator through a doorway the frenzy is
##     pounding on.
##   - a per-body collision exception with each door's ZombieBarrier —
##     exceptions override the mask, so intact unlocked doors admit THIS body
##     while every other zombie still slides off. Personal and stateless: the
##     door's state never changes and nothing can tailgate.
## Granted lazily on the first physics tick (doors deeper in the tree may
## ready after a hand-placed costume); revoked at the break (slice 4).
const COSTUMED_COLLISION_MASK := 41   # Environment | EscapeBarrier | DoorLock
var _door_passage_granted: bool = false


func _ready() -> void:
	# Before super._ready (the standing subclass pattern): every is_special
	# guard must already see it during base setup.
	is_special = true
	super._ready()
	collision_mask = COSTUMED_COLLISION_MASK
	_body = get_node_or_null("Sprite/Body")
	_apply_costume_visual()
	if GameConfig.debug_logs:
		print("🎭 COSTUME: %s rises costumed" % name)


## THE ORDERED KILL (§3.4, built slice 4) — the costume's only violence: a
## player-ordered, controlled, CANCELABLE pounce on one named human. It stays
## CALM, selected, and commandable throughout the pursuit; any new order
## cancels instantly (set_move_target / queue_move overrides below). No
## failsafe timer — the player is the failsafe. Within pounce_range it breaks
## the costume (§3.6 — at LAUNCH) and fires a completely normal Pounce: same
## flight, kill-at-landing, mid-flight-death-means-no-kill, same recovery.
## The kill then scores, fires contagion, and rises the victim exactly like
## any pounce kill — all existing machinery.
var _kill_target: Human = null


func order_kill(target: Human) -> void:
	if not is_costumed or target == null or not is_instance_valid(target) or not target.is_alive:
		return
	_clear_kill()
	# A plain command replaces any route, exactly like a move order does.
	has_target = false
	move_queue.clear()
	queued_attack = null
	_kill_target = target
	# The pursuit claim doubles as the telegraph (the target wears the hunted
	# ring) and keeps the prey off other ferals' menus while the scalpel works.
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null:
		gm.add_pursuit(target)
	if GameConfig.debug_logs:
		print("🎭 ORDERED KILL: %s stalks %s" % [name, target.name])


func has_kill_order() -> bool:
	return _kill_target != null


func _clear_kill() -> void:
	if _kill_target != null and is_instance_valid(_kill_target):
		var gm := get_tree().get_first_node_in_group("game_manager")
		if gm != null:
			gm.remove_pursuit(_kill_target)
	_kill_target = null


## Any new order cancels the kill instantly (§3.4 — the CalmBreach
## cancellation pattern; agency is never taken).
func set_move_target(target: Vector2) -> void:
	_clear_kill()
	super.set_move_target(target)


func queue_move(point: Vector2) -> void:
	_clear_kill()
	super.queue_move(point)


func _physics_process(delta: float) -> void:
	if not _door_passage_granted:
		_door_passage_granted = true
		_grant_door_passage()
	# The launched pounce owns the frame (flight → landing → recovery), exactly
	# as _tick_feral gives it the frame for a feral. The unit stays CALM.
	if current_state == State.CALM and _pounce != null and _pounce.is_active():
		_pounce.tick(delta)
		return
	if current_state == State.CALM and _kill_target != null:
		_tick_ordered_kill()
		return
	super._physics_process(delta)


func _tick_ordered_kill() -> void:
	# Target loss (§3.4): death (someone else got there) or escape (freed +
	# queue_freed) cancels on the spot; the special stands calm where it is.
	if not is_instance_valid(_kill_target) or not _kill_target.is_alive:
		_clear_kill()
		return
	_apply_boid_tuning()
	apply_boid_forces()
	var dist := global_position.distance_to(_kill_target.global_position)
	if dist <= GameConfig.pounce_range and not _kill_target.is_pounce_claimed():
		# THE BREAK IS AT LAUNCH (§3.6): from the instant it leaves the ground
		# it is a visible, valid, ordinary zombie — shootable mid-flight.
		var victim := _kill_target
		_clear_kill()
		_break_costume()
		_pounce.start(victim)
		return
	# Nav-pathed CALM pursuit at zombie speed — through any door that admits it
	# (§3.3), chasing if the target moves. Claimed targets are simply waited
	# out (keep pursuing; the claim clears at that pounce's resolution).
	nav_move_toward(_kill_target.global_position, GameConfig.zombie_speed)
	clamp_position_to_bounds()
	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()


## THE BREAK (§3.6): permanent, and the end of being special entirely —
## is_special drops WITH the costume. From here it is contagion-eligible,
## releasable, feral-capable, herd-repellent, fear-countable, fill-targetable,
## burst-capable, CalmBreach-subject, and present in every "zombies" query. It
## keeps its identity (selection, control group, unit_uid) — still your unit,
## just no longer a special one. Nothing remembers but the colour.
func _break_costume() -> void:
	if not is_costumed:
		return
	is_costumed = false
	is_special = false
	_revoke_door_passage()
	_apply_costume_visual()
	_break_pop()
	if GameConfig.debug_logs:
		print("🎭 BREAK: %s drops the disguise!" % name)


## The reveal pop (§5): a readable beat at horde scale — scale spike easing
## back (the sombrero flying off). Presentation only, never simulation.
func _break_pop() -> void:
	scale = Vector2(1.7, 1.7)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)


## One-time wiring (rule 8): doors are static per level. Breached doors free
## their barriers — a stale exception with a freed body is inert.
func _grant_door_passage() -> void:
	for door in get_tree().get_nodes_in_group("shelter_doors"):
		if not is_instance_valid(door):
			continue
		var barrier: StaticBody2D = door.zombie_barrier()
		if barrier != null:
			add_collision_exception_with(barrier)


## THE BREAK will call this (slice 4): the ordinary zombie slides off doors
## like everyone else from the launch frame.
func _revoke_door_passage() -> void:
	collision_mask = 9   # back to the standard zombie mask
	for door in get_tree().get_nodes_in_group("shelter_doors"):
		if not is_instance_valid(door):
			continue
		var barrier: StaticBody2D = door.zombie_barrier()
		if barrier != null:
			remove_collision_exception_with(barrier)


func _apply_costume_visual() -> void:
	if _body:
		_body.color = COSTUMED_COLOR if is_costumed else BROKEN_COLOR
	if is_costumed:
		modulate = Color(1, 1, 1, 1)
