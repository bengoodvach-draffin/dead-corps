extends StaticBody2D
class_name FatZombieCorpse

## Fat Zombie Corpse — permanent blocking obstacle spawned when a Fat Zombie dies
##
## Treated as a building for all purposes:
## - Blocks unit movement (StaticBody2D collision on layer 1)
## - Blocks line-of-sight (raycasts hit it because it's on collision layer 1)
## - Added to "buildings" group (picked up by human LOS raycasts)
##
## NOTE: NavigationObstacle2D is intentionally omitted in this prototype slice.
## The NavigationAgent2D on zombie.tscn has avoidance_enabled = false, which means
## runtime obstacles have no effect. Zombies will be physically blocked by the
## StaticBody2D collision and won't path through it, but they won't route around it
## cleanly either. Enable avoidance and add NavigationObstacle2D in a future pass.

## Visual color of the corpse (darker than live Fat Zombie)
const CORPSE_COLOR := Color(0.25, 0.38, 0.25)

## Collision rectangle size in pixels
## Set to 60x60 — roughly 2.5x the regular zombie footprint (24px diameter)
## Tune this during playtesting
const CORPSE_SIZE := Vector2(60.0, 60.0)


func _ready() -> void:
	# Must be on collision layer 1 (buildings) to block movement and LOS raycasts
	collision_layer = 1
	collision_mask = 0  # Corpse doesn't need to detect anything
	
	# Add to buildings group so LOS raycasts in human.gd pick it up
	add_to_group("buildings")
	
	# Set up collision shape
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = CORPSE_SIZE
	col.shape = shape
	add_child(col)
	
	# Set up visual
	var visual := ColorRect.new()
	visual.color = CORPSE_COLOR
	visual.offset_left = -CORPSE_SIZE.x / 2
	visual.offset_top = -CORPSE_SIZE.y / 2
	visual.offset_right = CORPSE_SIZE.x / 2
	visual.offset_bottom = CORPSE_SIZE.y / 2
	add_child(visual)
	
	print("🪨 FAT ZOMBIE CORPSE placed at: ", global_position)
