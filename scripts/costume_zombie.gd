extends Zombie
class_name CostumeZombie

## Costume Zombie — special zombie that is undetectable while costumed
##
## Humans cannot detect this zombie in any way while is_costumed is true:
## - No flee reaction
## - No morale drain
## - No aim timer acquisition
## - No alert trigger
## - No gunshot response (nothing to react to)
##
## The disguise breaks permanently when this zombie pins a human (GRAPPLED state).
## After that it behaves identically to a regular zombie.
##
## is_special = true (set in _ready): disables auto-pursuit, leap, and pursuit lock.
## Player maintains full control at all times.

## Whether the disguise is currently active
var is_costumed: bool = true

## Color while disguised — bright pink
const COSTUMED_COLOR := Color(1.0, 0.4, 0.8)

## Color after disguise breaks — standard zombie green
const BROKEN_COLOR := Color(0.4, 0.6, 0.3)

## Reference to the body ColorRect for visual updates
var _body: ColorRect = null


func _ready() -> void:
	# Mark as special — disables auto-pursuit, leap, and pursuit lock in zombie.gd
	is_special = true
	
	# Call parent _ready
	super._ready()
	
	# Cache body node and apply costumed visual
	_body = get_node_or_null("Sprite/Body")
	_apply_costume_visual()
	
	print("🎭 COSTUME ZOMBIE ready: ", name, " — disguise ACTIVE")


## Override perform_attack to detect the pin moment and break the disguise.
## The disguise breaks when this zombie successfully pins a human (GRAPPLED),
## not when it starts chasing — the human doesn't notice until it's too late.
func perform_attack() -> void:
	# Check if we're about to pin a human — if so, break disguise first
	if is_costumed and is_instance_valid(attack_target) and attack_target.is_human():
		var human := attack_target as Human
		# Pin happens at leap range (40px) — detect when human enters grapple state
		if human.current_state == Human.State.GRAPPLED:
			_break_disguise()
	
	# Perform the actual attack (inherited)
	super.perform_attack()


## Breaks the disguise permanently.
## Called when the zombie successfully pins a human.
func _break_disguise() -> void:
	if not is_costumed:
		return  # Already broken
	
	is_costumed = false
	is_special = false  # Restore full zombie behaviour — auto-pursuit, leap, pack recruitment
	_apply_costume_visual()
	print("🎭 COSTUME ZOMBIE: disguise BROKEN — ", name, " now behaves like a regular zombie!")


## Updates the body color to reflect costumed/broken state
func _apply_costume_visual() -> void:
	if _body:
		_body.color = COSTUMED_COLOR if is_costumed else BROKEN_COLOR
	# Also update modulate in case die() has changed it
	if is_costumed:
		modulate = Color(1, 1, 1, 1)
