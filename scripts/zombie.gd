extends Unit
class_name Zombie

## Zombie unit — player-controlled undead (V2 skeleton).
##
## Phase 1.2 demolition: the v1 stealth-era combat is GONE (V2_DIRECTION_SPEC
## §11) — leap-as-speed-boost, melee + the 2-attacker gate, the post-kill
## continuation scan, and stuck detection are all deleted. The lunge is REFRAMED
## as the Pounce (kill delivery) and rebuilt fresh in Phase 2.2; FERAL states,
## retargeting, and the hunt pool follow in 2.2–2.3. This skeleton is just: stand
## (IDLE), move where the player commands (MOVING), die (DEAD). Movement is
## Unit-base-driven via set_move_target — zombie.gd no longer pursues anything.

enum State {
	IDLE,
	MOVING,
	DEAD
}

## Emitted on a kill. Nothing emits it in this skeleton — the Pounce re-emits it
## in Phase 2.2. Kept wired so GameManager's listener survives the demolition.
signal zombie_killed_human(human: Unit, zombie: Zombie)

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null

var current_state: State = State.IDLE
var facing_direction: Vector2 = Vector2.RIGHT

## Special zombies (FatZombie/CostumeZombie) set this true in their _ready().
## Read by end_game_overlay.gd. Specials are excluded from the PoC — this only
## keeps them parsing; full re-audit is post-validation.
var is_special: bool = false

## VESTIGIAL — read by unit.gd:390 (BOID alignment) until the HP/combat strip
## (step 1.3). Carries no behavior here. Remove with that step.
var is_melee_attacker: bool = false


func _ready() -> void:
	team = Team.ZOMBIES
	super._ready()


## Whether this zombie can receive a new player command. Calm zombies always can
## now — the committed leap/melee states that used to block commands are gone.
## (Released ferals stop being selectable at all once Phase 2.4 lands.)
func can_receive_command() -> bool:
	return true


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		velocity = Vector2.ZERO
		return

	update_zombie_state()

	# BOID tuning per movement state (cohesion is a no-op — disabled in unit.gd —
	# but kept for parity; separation/alignment are the live forces).
	match current_state:
		State.IDLE:
			self.cohesion_strength = 15.0
			self.alignment_rate = 0.5
			self.separation_radius = 30.0
			self.separation_strength = 100.0
		State.MOVING:
			self.cohesion_strength = 0.0
			self.alignment_rate = 0.8
			self.separation_radius = 35.0
			self.separation_strength = 120.0
		State.DEAD:
			self.cohesion_strength = 0.0
			self.alignment_rate = 0.0
			self.separation_radius = 25.0
			self.separation_strength = 80.0

	# Face the direction of travel.
	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()

	# Base Unit physics (movement toward target, BOID separation).
	super._physics_process(delta)


## MOVING while heading to a commanded position, else IDLE.
func update_zombie_state() -> void:
	if has_target:
		current_state = State.MOVING
	else:
		current_state = State.IDLE


## Death: enter DEAD, stop, recolor, linger briefly as a corpse, then free.
## (Zombies become killable by gunfire in Phase 3.1; GameManager tracks the free
## for the lose condition.)
func die() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	modulate = Color(0.4, 0.0, 0.0)
	# Living zombies stop being pushed by this corpse via the BOID separation skip
	# (dead units excluded by current_health <= 0 in apply_separation_force), not
	# via collision layers — units don't collide with each other anyway.
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		queue_free()


## Receives damage. The 2-arg signature is retained because fat_zombie.gd calls
## super.take_damage(amount, knockback). HP plumbing (current_health,
## update_health_bar) lives on Unit and is removed in step 1.3 — revisit then.
func take_damage(amount: float, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	current_health -= amount
	update_health_bar()
	if current_health <= 0:
		die()
		if knockback_direction != Vector2.ZERO and is_instance_valid(self):
			var tween := create_tween()
			tween.tween_property(self, "position", position + knockback_direction * 8.0, 0.15)
