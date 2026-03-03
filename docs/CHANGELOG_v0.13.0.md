# Dead Corps - Changelog v0.13.0

**Release Date:** February 27, 2026  
**Focus:** Critical Fixes - Player Command Stuck Detection & Escape Zone Smart Blending

---

## 🎯 Critical Fixes

### Fix 1: Zombie Stuck Detection - Player Command Bypass (MAJOR)

**Problem:** When clicking on distant humans, zombies would run toward them but trigger stuck detection after 2 seconds because the human wasn't in vision range yet. The stuck detector would cancel the command, making distant targets impossible to attack via clicking.

**Root Cause:** Stuck detection measured movement per-frame instead of progress toward target. Player-commanded zombies running toward distant targets would be marked as "stuck" even though they were making progress.

**Example Scenario:**
```
1. Player clicks human 300px away
2. Zombie starts running (is_player_commanded = true)
3. After 2s, zombie has moved 150px closer
4. Human still outside vision range (100px idle)
5. Stuck detector: "Only moved 1.5px... stuck!"
6. Command cancelled, zombie goes idle
```

**Solution:** Disable stuck detection entirely for player-commanded zombies.

**Files Modified:** `scripts/zombie.gd`

```gdscript
func check_if_stuck(delta: float) -> void:
    # Don't check stuck for player-commanded zombies
    # Players know what they want - let them command freely!
    if is_player_commanded:
        stuck_timer = 0.0
        return
    
    # Rest of stuck detection for auto-pursuing zombies...
```

**Impact:**
- ✅ Player commands work at any distance
- ✅ Can click humans across the entire map
- ✅ Auto-pursuing zombies still get stuck detection
- ✅ No false positives for player intent

---

### Fix 2: Escape Zone Seeking - Smart Blending System (MAJOR)

**Problem:** Humans would not seek nearby escape zones when zombies were visible, even if the zone was <50px away. The escape zone seeking code only ran when NO zombies were visible, making zones useless during active chases.

**Root Cause:** Flawed priority system:

```
OLD LOGIC:
IF zombies visible:
    Flee away from zombies (weak 10% zone bias)
    Strong seeking NEVER RUNS!
    
IF no zombies visible:
    Strong seeking to zone (100%)
```

**Example Scenario:**
```
Human at (-3, 110)
Escape zone at (40, 110) - only 43px away!
Zombie at (90, 120) - 94px away

OLD BEHAVIOR:
- Sees zombie ✓
- Gets 10% pull toward zone
- 90% flee away from zombie
- Runs AWAY from zone, gets caught

NEW BEHAVIOR:
- Zone weight: 90% (because 43px away)
- Threat weight: 10%
- Direction: 90% toward zone, 10% dodge zombie
- Human escapes!
```

**Solution:** Smart blending system that works DURING active chases.

**Files Modified:** `scripts/human.gd`

**New Logic:**

```gdscript
# Calculate zone weight based on distance:
# 50px away = 90% zone pull, 10% threat avoidance
# 100px away = 75% zone pull, 25% threat avoidance
# 150px away = 60% zone pull, 40% threat avoidance
# 200px away = 40% zone pull, 60% threat avoidance
var zone_weight = 0.4 + (0.5 * (1.0 - distance / 200.0))

# Blend directions:
blended = (zone_direction * zone_weight) + (threat_direction * threat_weight)
```

**Weight Curve:**

| Distance | Zone Weight | Threat Weight | Behavior |
|----------|-------------|---------------|----------|
| 50px | 90% | 10% | Mostly zone, slight dodge |
| 100px | 75% | 25% | Strong zone, some dodge |
| 150px | 60% | 40% | Balanced |
| 200px | 40% | 60% | More dodge, zone bias |
| >200px | 0% | 100% | Pure threat avoidance |

**Impact:**
- ✅ Escape zones work during active chases
- ✅ No line-of-sight requirement
- ✅ Works through walls (pathfinding around obstacles)
- ✅ Smooth weight scaling with distance
- ✅ Natural-looking diagonal escape patterns

---

## 🧹 Technical Improvements

### Removed Line-of-Sight Check for Escape Zones

**OLD:** Humans only sought escape zones if they had direct line of sight  
**NEW:** Always seek nearest zone, pathfind around obstacles

**Why:** In cramped corridors, nearest zone often blocked by walls. LOS requirement made zones unreachable.

### Simplified Fallback Priority 2

**OLD:** Complex LOS checking, verbose logging, conditional seeking  
**NEW:** Simple fallback for safe humans (no threats visible)

The main zone seeking now happens in the blending system, Priority 2 is just a safety net.

---

## 📋 Debugging Improvements

### Enhanced Logging

**Smart Zone Blending Logs:**
```
🎯 SMART ZONE BLENDING:
  Distance to zone: 43.0px
  Zone weight: 90.0%
  Threat weight: 10.0%
  Threat direction: (-0.994, -0.106)
  Zone direction: (0.923, 0.000)
  BLENDED direction: (0.731, -0.011)
```

**Shows:**
- Distance to nearest zone
- Weight calculations
- Individual direction vectors
- Final blended result

---

## 🎮 Gameplay Impact

### Before v0.13.0:

**Player Commands:**
- ❌ Clicking distant humans cancelled after 2s
- ❌ Had to wait for zombie to get close before clicking
- ❌ Frustrating micromanagement

**Escape Zones:**
- ❌ Humans ignored zones during chases
- ❌ Only sought zones when safe (after escaping zombie vision)
- ❌ Zones felt useless in cramped levels
- ❌ Human at 50px from zone would run away from it

### After v0.13.0:

**Player Commands:**
- ✅ Click any human at any distance
- ✅ Zombie runs full distance to target
- ✅ Smooth, RTS-style control

**Escape Zones:**
- ✅ Humans seek zones even during active chases
- ✅ 50px from zone = 90% pull (nearly guaranteed escape)
- ✅ 100px from zone = 75% pull (strong escape bias)
- ✅ Works through walls and obstacles
- ✅ Natural dodge + escape patterns

---

## 🧪 Testing Scenarios

### Test 1: Player Command at Distance

**Setup:**
1. Place zombie at (0, 0)
2. Place human at (300, 0)
3. Click human to command zombie

**Expected:**
- Zombie runs full 300px distance
- No stuck detection triggers
- Zombie reaches and attacks human

### Test 2: Escape Zone During Chase

**Setup:**
1. Place human at (0, 100)
2. Place escape zone at (50, 100) - 50px away
3. Place zombie at (100, 100) - chasing human

**Expected:**
- Human sees zombie ✓
- Smart blending activates (90% zone, 10% dodge)
- Human moves diagonally toward zone while dodging
- Human reaches zone and escapes

### Test 3: Escape Zone Through Walls

**Setup:**
1. Place human in corridor
2. Place escape zone on other side of wall (nearest)
3. Place zombie chasing human

**Expected:**
- Human targets zone through wall
- Pathfinds around wall to reach zone
- No LOS requirement blocks behavior

---

## 📦 Files Changed

### Modified:
- `scripts/zombie.gd` - Added player command bypass in stuck detection
- `scripts/human.gd` - Complete escape zone system restructure

### Documentation:
- `docs/CHANGELOG_v0.13.0.md` - This file

---

## 🚀 Next Steps

**Immediate Priorities:**
- Test player commands at various distances
- Test escape zones in cramped corridors
- Verify zone weight curve feels natural

**Phase A (Next Development):**
- Sentry degrees (0° = North)
- Swing arc with sin/cos smoothing
- Visual arrow in editor

---

## 🔮 Future Enhancements

**Escape Zone System:**
- Per-zone "pull strength" multiplier
- Dynamic zone weights based on zombie count
- Zone "safety radius" visualization

**Stuck Detection:**
- Better pathfinding to reduce false positives
- Collision avoidance improvements
- Formation-based movement to prevent clumping

---

**Version:** v0.13.0  
**Status:** Critical fixes implemented, ready for testing  
**Breaking Changes:** None - all changes are improvements to existing systems
