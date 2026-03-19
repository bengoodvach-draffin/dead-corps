extends Zombie
class_name FatZombie

## Fat Zombie — special zombie that creates a permanent blocking obstacle on death
##
## A pure utility/sacrifice unit. Cannot attack humans. When killed by gunshot,
## spawns a FatZombieCorpse at its position which acts as a permanent building —
## blocking movement, LOS, and navigation. If it enters an escape zone it simply
## disappears with no corpse spawned.
##
## is_special = true (set in _ready): disables auto-pursuit, leap, and pursuit lock.
## Player maintains full control at all times.

## Scene to spawn as the permanent obstacle when this zombie dies by gunshot
@export var corpse_scene: PackedScene

## When true, die() will spawn a corpse obstacle.
## Set to false by escape_zone.gd before calling die() so no corpse is left.
var spawn_corpse_on_death: bool = true

## Whether this zombie has died by gunshot (prevents re-triggering)
var _is_dying: bool = false


func _ready() -> void:
	# Mark as special — disables auto-pursuit, leap, and pursuit lock in zombie.gd
	is_special = true
	
	# Fat zombies cannot attack — clear attack stats
	attack_damage = 0.0
	attack_range = 0.0
	
	# Call parent _ready after setting is_special
	super._ready()
	
	print("🐷 FAT ZOMBIE ready: ", name)


## Override take_damage so Fat Zombie only dies from gunshot (damage with knockback direction).
## All other damage sources (melee, etc.) are ignored in this prototype slice.
## @param amount: Damage amount
## @param knockback_direction: Non-zero only when shot — this is the gunshot death trigger
func take_damage(amount: float, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	# Only die if this is a gunshot (knockback_direction is non-zero)
	if knockback_direction == Vector2.ZERO:
		print("🐷 FAT ZOMBIE: Ignored non-gunshot damage from ", name)
		return
	
	# Standard damage handling — will call die() if health reaches 0
	super.take_damage(amount, knockback_direction)


## Override die() to spawn the corpse obstacle before removing self.
## Escape zone sets spawn_corpse_on_death = false before calling die() so
## no corpse is left when the fat zombie walks off the level.
func die() -> void:
	# Guard against double-trigger
	if _is_dying:
		return
	_is_dying = true
	
	print("🐷 FAT ZOMBIE dying — spawn corpse: ", spawn_corpse_on_death)
	
	# Stop movement immediately
	current_state = State.DEAD
	velocity = Vector2.ZERO
	
	# Spawn corpse if death was by gunshot (not escape zone)
	if spawn_corpse_on_death and corpse_scene:
		var corpse = corpse_scene.instantiate()
		# Place corpse in the same parent so it stays in the level
		get_parent().add_child(corpse)
		corpse.global_position = global_position
		print("🐷 FAT ZOMBIE CORPSE spawned at: ", global_position)
	elif spawn_corpse_on_death and not corpse_scene:
		push_warning("FatZombie: corpse_scene not set — no obstacle will be spawned!")
	
	# Briefly show death color then remove
	modulate = Color(0.4, 0.0, 0.0)
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		queue_free()
