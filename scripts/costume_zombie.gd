extends Zombie
class_name CostumeZombie

## Costume Zombie — special zombie intended to be undetectable while costumed.
##
## NON-FUNCTIONAL on the v2-poc branch (specials excluded from the PoC, §11).
## The v1 detection-evasion and the "disguise breaks when it pins a human"
## trigger both relied on systems the pivot deleted (vision/morale/alerts and
## grapple/GRAPPLED), so the disguise no longer breaks. Kept only so the project
## parses; full re-audit post-validation (spec Parked Register).
##
## is_special = true (set in _ready) — carried over; specials aren't wired into
## any v2 system yet.

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


## Updates the body color to reflect costumed/broken state
func _apply_costume_visual() -> void:
	if _body:
		_body.color = COSTUMED_COLOR if is_costumed else BROKEN_COLOR
	# Also update modulate in case die() has changed it
	if is_costumed:
		modulate = Color(1, 1, 1, 1)
