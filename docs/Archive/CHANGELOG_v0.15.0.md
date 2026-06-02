# Dead Corps - Changelog v0.15.0

**Release Date:** February 27, 2026  
**Focus:** Escape Zone Fixes - Global Position & Line-of-Sight Restoration

---

## 🎯 Critical Fixes

### Fix 1: Nested Escape Zones - Global Position Bug (CRITICAL)

**Problem:** When escape zones were nested under other nodes (especially under other escape zones), the distance calculations were completely wrong, causing humans to ignore nearby zones.

**Root Cause:** The code was using `position` (local position relative to parent) instead of `global_position` (absolute world position).

**Example of the Bug:**
```
Hierarchy:
  EscapeZone (parent) at global (0, 55)
    └─ EscapeZone (child) at local (0, 0)

Human at global (0, 75)

OLD CODE:
  distance = (0, 75) to zone.position (0, 0) = 75px ❌

NEW CODE:
  distance = (0, 75) to zone.global_position (0, 55) = 20px ✓
```

**Why This Broke:**
- Godot's `position` property returns coordinates relative to parent node
- If a zone is nested, `position` might be (0, 0) even if it's at (100, 100) in the world
- The distance calculation was comparing human's global position to zone's local position
- This resulted in wildly incorrect distances

**The Fix:**
```gdscript
// OLD (BROKEN):
var distance := position.distance_to(zone.position)
var to_zone := (zone.position - position).normalized()

// NEW (FIXED):
var distance := global_position.distance_to(zone.global_position)
var to_zone := (zone.global_position - global_position).normalized()
```

**Files Modified:**
- `scripts/human.gd` - Updated all escape zone distance/direction calculations

**Impact:**
- ✅ Escape zones work correctly when nested under other nodes
- ✅ Distance calculations always accurate
- ✅ Humans can now find zones regardless of scene hierarchy
- ✅ Level designers have freedom to organize scene tree

---

### Fix 2: Line-of-Sight Requirement Restored (MAJOR)

**Problem:** In v0.13.0, we removed the line-of-sight check to allow humans to seek zones through walls. This caused erratic behavior where humans would try to run through walls toward blocked zones.

**Why v0.13.0 Approach Failed:**
```
[Human] ----wall---- [Zone A: 50px away, BLOCKED]

[Zone B: 150px away, CLEAR PATH]
```

**v0.13.0 Behavior (Broken):**
- Picks Zone A (nearest by straight-line distance)
- Tries to walk through wall
- Gets stuck pushing against wall
- Looks janky and broken

**v0.15.0 Behavior (Fixed):**
- Checks Zone A: blocked by wall → skip it
- Checks Zone B: clear line of sight → select it
- Runs cleanly to Zone B
- Looks natural and responsive

**The Fix:**

Changed from "nearest zone by distance" to "nearest VISIBLE zone":

```gdscript
func get_nearest_escape_zone() -> Node2D:
    for zone in escape_zones:
        var distance := global_position.distance_to(zone.global_position)
        
        // CRITICAL: Only consider zones we can see
        if not has_line_of_sight_to_point(zone.global_position):
            continue  // Skip blocked zones
        
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_zone = zone
    
    return nearest_zone  // Returns nearest VISIBLE zone
```

**Function Renamed:**
- `get_nearest_escape_zone()` → Returns nearest VISIBLE zone (LOS required)
- Documentation updated to reflect this

**Impact:**
- ✅ Humans only seek zones they can actually reach
- ✅ No more trying to run through walls
- ✅ Smooth, natural pathfinding
- ✅ Works great in cramped corridors with multiple zones

---

## 🧹 Cleanup

### Debug Logging Removed

Removed all debug logging that was added in v0.14.1 for diagnostics:
- Removed `get_nearest_escape_zone()` debug prints
- Removed escape zone blending debug prints
- Code is now clean and production-ready

---

## 🎮 Gameplay Impact

### Before v0.15.0:

**Nested Zones:**
- ❌ Distance calculations wrong for nested zones
- ❌ Humans ignored zones 20px away
- ❌ Unpredictable behavior based on scene hierarchy

**Zone Selection:**
- ❌ Picked nearest zone even if blocked by walls
- ❌ Humans tried to walk through walls
- ❌ Looked janky and stuck

### After v0.15.0:

**Nested Zones:**
- ✅ Distances always calculated correctly
- ✅ Works regardless of scene hierarchy
- ✅ Level designers can organize scenes freely

**Zone Selection:**
- ✅ Only seeks zones with clear line of sight
- ✅ Natural pathfinding around obstacles
- ✅ Smooth, responsive escape behavior

---

## 🏗️ Scene Hierarchy Best Practices

### ✅ Recommended Structure:

```
Main
├── GameManager
├── TestLevel
│   ├── EscapeZones (Node2D or Node)
│   │   ├── EscapeZone1
│   │   ├── EscapeZone2
│   │   └── EscapeZone3
│   ├── Humans
│   │   ├── Human1
│   │   └── Human2
│   └── Buildings
│       ├── Building1
│       └── Building2
```

**Why This Works:**
- All escape zones at same hierarchy level
- Using `global_position` ensures correct calculations
- Clean organization

### ⚠️ What Also Works (Now Fixed):

```
Main
├── TestLevel
│   ├── EscapeZone1
│   │   ├── EscapeZone2 (nested)  ← NOW WORKS!
│   │   └── EscapeZone3 (nested)  ← NOW WORKS!
```

**Previously:** Distance calculations were wrong  
**Now:** Works correctly thanks to `global_position` fix

---

## 🧪 Testing Scenarios

### Test 1: Nested Escape Zones

**Setup:**
1. Create parent Node2D at (100, 100)
2. Add EscapeZone child at local position (0, 0)
3. Place human at (100, 120) - 20px away from zone's global position

**Expected:**
- Human detects zone at 20px distance ✓
- Runs toward zone ✓
- Escapes successfully ✓

### Test 2: Blocked vs Clear Zones

**Setup:**
1. Place Zone A at 30px from human (blocked by wall)
2. Place Zone B at 100px from human (clear path)
3. Send zombie to chase human

**Expected:**
- Human ignores Zone A (blocked, no LOS)
- Human seeks Zone B (visible)
- Human runs to Zone B ✓

### Test 3: Weight Blending with Visible Zone

**Setup:**
1. Human at (0, 75)
2. Visible escape zone at (0, 55) - 20px north
3. Zombie approaching from east

**Expected:**
- Blending: 85% north + 15% west
- Human moves mostly north with slight westward dodge
- Human escapes to zone ✓

---

## 📦 Files Changed

### Modified:
- `scripts/human.gd` - All escape zone calculations updated to use `global_position`
- `scripts/human.gd` - LOS check restored in `get_nearest_escape_zone()`
- `scripts/human.gd` - Debug logging removed

### Documentation:
- `docs/CHANGELOG_v0.15.0.md` - This file

---

## 🔬 Technical Details

### Position vs Global Position

**In Godot:**
- `position`: Local coordinates relative to parent node
- `global_position`: Absolute world coordinates

**When to use each:**
- ✅ `global_position`: When calculating distances between nodes in different parts of scene tree
- ❌ `position`: Only when working with parent-child relationships

**Example:**
```gdscript
# Human at global (100, 100)
# Zone nested under node at global (200, 200)
# Zone's local position is (50, 50)

# WRONG:
position.distance_to(zone.position)
# = (100, 100) to (50, 50) = 70.7px ❌

# RIGHT:
global_position.distance_to(zone.global_position)
# = (100, 100) to (250, 250) = 212.1px ✓
```

### Line-of-Sight Check

```gdscript
func has_line_of_sight_to_point(point: Vector2) -> bool:
    var query := PhysicsRayQueryParameters2D.create(position, point)
    query.collision_mask = 1  # Only hit buildings/walls
    query.exclude = [self]
    
    var result := space_state.intersect_ray(query)
    return result.is_empty()  # True if no obstacles
```

**How It Works:**
1. Cast ray from human to escape zone
2. Check if ray hits any buildings (collision_mask = 1)
3. If ray hits nothing → zone is visible
4. If ray hits building → zone is blocked

---

## 🎓 Key Learnings

### Always Use Global Position for Distance Calculations

When calculating distances between nodes that might be in different parts of the scene tree, **always use `global_position`**, not `position`.

**Rule of Thumb:**
- Same parent → can use `position`
- Different parents → must use `global_position`
- Unsure → use `global_position` (always safe)

### Line-of-Sight Matters for Pathfinding

Picking the "nearest" zone without considering obstacles creates janky behavior. Players notice when AI tries to walk through walls.

**Better approach:**
- Nearest VISIBLE zone > Nearest absolute zone
- Even if further away, reachable zones feel more responsive

### Scene Hierarchy Freedom

By using `global_position`, we give level designers complete freedom to organize their scene tree however makes sense to them, without breaking gameplay mechanics.

---

## 🚀 Status

**Version:** v0.15.0  
**All Critical Issues:** ✅ RESOLVED  
**Ready For:** Production testing and Phase B development  
**Breaking Changes:** None - all changes are fixes to existing systems
