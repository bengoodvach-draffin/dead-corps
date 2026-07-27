class_name FormationPlanner

## Formation-slot math for group move orders — extracted from SelectionManager
## (Tier-7 manager splits, pre-Mark). Pure and static (the FeralTargeting
## pattern): the caller owns the per-level order counter and passes it as the
## salt. Deterministic (§10): grid by index, jitter by DetHash(unit_uid, salt).

## Spreads `units` in a rough grid around `target_pos` with per-unit DetHash
## jitter so a commanded horde reads as a shamble, not a parade. One position
## per unit, same order as `units`. Positions are world-bounds clamped.
static func plan(target_pos: Vector2, units: Array[Unit], order_salt: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var unit_count := units.size()

	if unit_count == 0:
		return positions

	if unit_count == 1:
		# Single unit — exactly the ordered point (the cursor-precision contract).
		positions.append(target_pos)
		return positions

	var spacing := 40.0
	var units_per_row := int(ceil(sqrt(unit_count)))
	var grid_width: float = (units_per_row - 1) * spacing
	var grid_height: float = (ceil(float(unit_count) / units_per_row) - 1) * spacing
	var start_x: float = target_pos.x - grid_width / 2.0
	var start_y: float = target_pos.y - grid_height / 2.0

	for i in range(unit_count):
		var row := i / units_per_row
		var col := i % units_per_row
		# Keyed off unit_uid + order_salt → identical every run, different per
		# unit and per order (spec §10 — no RNG).
		var jitter := DetHash.offset(units[i].unit_uid, order_salt, 15.0)
		var pos := Vector2(
			start_x + col * spacing + jitter.x,
			start_y + row * spacing + jitter.y
		)
		var bounds_min := WorldBounds.world_bounds_min
		var bounds_max := WorldBounds.world_bounds_max
		pos.x = clamp(pos.x, bounds_min.x, bounds_max.x)
		pos.y = clamp(pos.y, bounds_min.y, bounds_max.y)
		positions.append(pos)

	return positions
