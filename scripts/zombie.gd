extends Unit
class_name Zombie

## Zombie unit - player-controlled undead unit
## 
## Engagement model (v0.25.0):
## - Zombies NEVER auto-pursue. Only a player right-click starts an engagement.
## - Once commanded, zombies chase freely until leaping/grappled/in melee.
## - Leaping, grappled, and melee states are committed — cannot be redirected.
## - On kill, zombie auto-scans for nearest human within continuation_range (250px)
##   with clear LOS — if found, re-engages without player input.
## - Special zombies skip post-kill continuation.

enum State {
	IDLE,
	MOVING,
	PURSUING,
	LEAPING,
	MELEE,
	DEAD
}

signal zombie_killed_human(human: Unit, zombie: Zombie)

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null

@export var leap_range: float = 40.0
@export var leap_speed_multiplier: float = 2.0
## Range to scan for next target after a kill
@export var continuation_range: float = 250.0

var current_state: State = State.IDLE
var facing_direction: Vector2 = Vector2.RIGHT
var is_leaping: bool = false
var normal_speed: float = 0.0
var is_melee_attacker: bool = false
var has_leap_grappled: bool = false
var leap_grappled_target: Human = null
## When true, zombie cannot receive new commands until current target dies
var is_committed_to_target: bool = false
## Special zombies (FatZombie, CostumeZombie): no leap, no continuation, full player control
var is_special: bool = false
var melee_enter_time: float = 0.0
const MELEE_VISION_DELAY: float = 0.5

@onready var selection_circle: Line2D = $SelectionIndicator/SelectionCircle

var stuck_check_interval: float = 0.5
var stuck_check_timer: float = 0.0
var stuck_sample_position: Vector2 = Vector2.ZERO
var stuck_max_count: int = 3
var stuck_count: int = 0
var stuck_distance_threshold: float = 15.0


func _ready() -> void:
	team = Team.ZOMBIES
	normal_speed = move_speed
	stuck_sample_position = position
	stuck_check_timer = stuck_check_interval
	super._ready()


## Returns true if this zombie can receive a new player command right now.
## Committed zombies (leaping, grappled, in melee) must finish their engagement first.
func can_receive_command() -> bool:
	return not (is_leaping or is_committed_to_target)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		velocity = Vector2.ZERO
		return
	
	update_zombie_state()
	
	match current_state:
		State.IDLE:
			self.cohesion_strength = 15.0
			self.alignment_rate = 0.5
			self.separation_radius = 30.0
			self.separation_strength = 100.0
		State.PURSUING, State.LEAPING:
			self.cohesion_strength = 0.0
			self.alignment_rate = 1.5
			self.separation_radius = 45.0
			self.separation_strength = 150.0
		State.MOVING:
			self.cohesion_strength = 0.0
			self.alignment_rate = 0.8
			self.separation_radius = 35.0
			self.separation_strength = 120.0
		State.MELEE, State.DEAD:
			self.cohesion_strength = 0.0
			self.alignment_rate = 0.0
			self.separation_radius = 25.0
			self.separation_strength = 80.0
	
	if velocity.length() > 0.1:
		facing_direction = velocity.normalized()
	elif attack_target and is_instance_valid(attack_target):
		facing_direction = (attack_target.position - position).normalized()
	
	# Check if target has died or become invalid
	if attack_target:
		var target_dead := false
		if attack_target is Human and attack_target.is_dead:
			target_dead = true
		if not is_instance_valid(attack_target) or target_dead:
			if target_dead and not is_special:
				print("Zombie's target died - running post-kill continuation check")
				_check_post_kill_continuation()
			clear_attack_target()
			return
	
	# Stuck detection (only when chasing a target)
	if attack_target and is_instance_valid(attack_target):
		check_if_stuck(delta)
	else:
		stuck_count = 0
		stuck_check_timer = stuck_check_interval
	
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		manage_melee_attacker_status()
	
	update_leap_state()
	super._physics_process(delta)


## Scans for nearest valid human within continuation_range after a kill.
## LOS check only — no vision arc. Zombie knows where the fight is.
func _check_post_kill_continuation() -> void:
	var nearest := _find_nearest_human_simple(continuation_range)
	if nearest:
		print("⚡ POST-KILL CONTINUATION: ", name, " -> ", nearest.name)
		set_attack_target(nearest)


## Finds nearest living, attackable human within range using LOS check only.
## Used for post-kill continuation and stuck detection recovery.
func _find_nearest_human_simple(range: float) -> Unit:
	var humans := get_tree().get_nodes_in_group("humans")
	var best: Unit = null
	var best_dist := range
	
	for human in humans:
		if not human is Human:
			continue
		if human.is_dead:
			continue
		if human.attacker_count >= 2:
			continue
		
		var dist := position.distance_to(human.position)
		if dist >= best_dist:
			continue
		
		if not has_line_of_sight_to(human):
			continue
		
		best_dist = dist
		best = human
	
	return best


func handle_combat(_delta: float) -> void:
	if not is_instance_valid(attack_target):
		attack_target = null
		return
	
	var distance := position.distance_to(attack_target.position)
	
	if distance > attack_range:
		if nav_agent and nav_agent.is_inside_tree():
			nav_agent.target_position = attack_target.position
			if not nav_agent.is_navigation_finished():
				var next_position = nav_agent.get_next_path_position()
				var direction = (next_position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
			else:
				var direction := (attack_target.position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
		else:
			var direction := (attack_target.position - position).normalized()
			velocity = direction * move_speed
			move_and_slide()
	else:
		velocity = Vector2.ZERO
		if attack_timer <= 0:
			perform_attack()
			attack_timer = attack_cooldown


func move_to_target(_delta: float) -> void:
	var distance := position.distance_to(target_position)
	
	if distance > 5.0:
		if nav_agent and nav_agent.is_inside_tree():
			nav_agent.target_position = target_position
			if not nav_agent.is_navigation_finished():
				var next_position = nav_agent.get_next_path_position()
				var direction = (next_position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
			else:
				var direction := (target_position - position).normalized()
				velocity = direction * move_speed
				move_and_slide()
		else:
			var direction := (target_position - position).normalized()
			velocity = direction * move_speed
			move_and_slide()
	else:
		velocity = Vector2.ZERO
		has_target = false


func update_zombie_state() -> void:
	var old_state := current_state
	
	# Melee (committed — highest priority)
	if is_melee_attacker and attack_target and is_instance_valid(attack_target):
		var distance_to_target := position.distance_to(attack_target.position)
		if distance_to_target <= attack_range:
			if old_state != State.MELEE:
				melee_enter_time = Time.get_ticks_msec() / 1000.0
			current_state = State.MELEE
			return
	
	if is_leaping:
		current_state = State.LEAPING
		return
	
	if attack_target:
		current_state = State.PURSUING
		return
	
	if has_target:
		current_state = State.MOVING
		return
	
	current_state = State.IDLE


## LOS check between this zombie and a target unit
func has_line_of_sight_to(target: Unit) -> bool:
	var query := PhysicsRayQueryParameters2D.create(position, target.position)
	query.collision_mask = 1
	var space_state := get_world_2d().direct_space_state
	var result := space_state.intersect_ray(query)
	return result.is_empty()


func update_leap_state() -> void:
	if is_special:
		return
	
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		var distance := position.distance_to(attack_target.position)
		
		if distance <= leap_range and not is_leaping:
			start_leap()
		
		# Guaranteed pin at 40px
		if is_leaping and distance <= 40.0 and not has_leap_grappled:
			attack_target.is_grappled = true
			attack_target.grapple_timer = attack_target.grapple_duration
			has_leap_grappled = true
			leap_grappled_target = attack_target
			is_committed_to_target = true
			print("Zombie landed leap - target PINNED!")
		
		if distance > leap_range and is_leaping:
			stop_leap()
	else:
		if is_leaping:
			stop_leap()


func start_leap() -> void:
	is_leaping = true
	move_speed = normal_speed * leap_speed_multiplier
	print("Zombie leaping toward human!")


func stop_leap() -> void:
	is_leaping = false
	move_speed = normal_speed


## Manages melee attacker slot on target. Max 2 per human (v0.25.0).
func manage_melee_attacker_status() -> void:
	var distance_to_target := position.distance_to(attack_target.position)
	
	if distance_to_target <= attack_range:
		if not is_melee_attacker:
			if attack_target.attacker_count < 2:
				is_melee_attacker = true
				is_committed_to_target = true
				print("Zombie entered melee with human (", attack_target.attacker_count, "/2 attackers)")
			else:
				if not is_committed_to_target:
					print("Human already has 2 melee attackers - finding different target")
					var new_target := _find_nearest_human_simple(continuation_range)
					if new_target and new_target != attack_target:
						set_attack_target(new_target)
	else:
		if is_melee_attacker:
			is_melee_attacker = false
			print("Zombie left melee range (", attack_target.attacker_count, "/2 attackers)")


func check_if_stuck(delta: float) -> void:
	stuck_check_timer -= delta
	if stuck_check_timer > 0.0:
		return
	
	stuck_check_timer = stuck_check_interval
	var distance_moved := position.distance_to(stuck_sample_position)
	stuck_sample_position = position
	
	if distance_moved >= stuck_distance_threshold:
		stuck_count = 0
		return
	
	if is_committed_to_target or is_melee_attacker or has_leap_grappled:
		print("⏸️ Zombie barely moved but in combat - staying engaged")
		stuck_count = 0
		return
	
	stuck_count += 1
	print("⚠️ ZOMBIE STUCK CHECK: ", name, " moved only ", snappedf(distance_moved, 0.1),
		  "px (count: ", stuck_count, "/", stuck_max_count, ")")
	
	if stuck_count < stuck_max_count:
		return
	
	stuck_count = 0
	print("🚧 ZOMBIE STUCK CONFIRMED - finding new target or going idle")
	
	var new_target := _find_nearest_human_simple(continuation_range)
	if new_target and new_target != attack_target:
		set_attack_target(new_target)
		print("  ✅ Switched to new target: ", new_target.name)
	else:
		clear_attack_target()
		print("  ❌ No other targets — going idle")


## Sets attack target. player_commanded param kept for API compatibility but no longer used.
func set_attack_target(target: Unit, _player_commanded: bool = true) -> void:
	if attack_target == target and is_instance_valid(target):
		return
	
	# Clean up old target's attacker slot
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		attack_target.remove_attacker()
	
	if is_melee_attacker:
		is_melee_attacker = false
	
	has_leap_grappled = false
	leap_grappled_target = null
	is_committed_to_target = false
	
	super.set_attack_target(target)
	
	if target and is_instance_valid(target) and target.is_human():
		target.add_attacker()


func clear_attack_target() -> void:
	if attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		attack_target.remove_attacker()
	
	if is_melee_attacker:
		is_melee_attacker = false
	
	has_leap_grappled = false
	leap_grappled_target = null
	is_committed_to_target = false
	attack_target = null


func die() -> void:
	if is_melee_attacker and attack_target and is_instance_valid(attack_target) and attack_target.is_human():
		attack_target.remove_attacker()
		is_melee_attacker = false
	
	current_state = State.DEAD
	velocity = Vector2.ZERO
	modulate = Color(0.4, 0.0, 0.0)
	
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		queue_free()


func take_damage(amount: float, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	current_health -= amount
	update_health_bar()
	
	if current_health <= 0:
		die()
		if knockback_direction != Vector2.ZERO and is_instance_valid(self):
			var tween := create_tween()
			tween.tween_property(self, "position", position + knockback_direction * 8.0, 0.15)


func perform_attack() -> void:
	if is_instance_valid(attack_target) and attack_target.is_human():
		var was_alive := attack_target.current_health > 0
		attack_target.take_damage(attack_damage)
		if was_alive and attack_target.current_health <= 0:
			zombie_killed_human.emit(attack_target, self)
