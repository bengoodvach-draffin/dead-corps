# v0.9.2 - MINIMAL FLEE (Diagnostic Version)

**Date:** February 13, 2026  
**Status:** Diagnostic - Stripped to bare minimum  
**Previous version:** v0.9.1 (vision range fixes)

---

## 🎯 PURPOSE

This version strips flee mechanics to **absolute bare minimum** to diagnose erratic behavior.

**Only active:** Weighted zombie threat (flee away from visible zombies)  
**Everything else:** Commented out (not deleted)

---

## ✅ WHAT'S ACTIVE

### **Core Flee Behavior ONLY:**

```gdscript
func calculate_flee_direction() -> Vector2:
    // For each visible zombie:
    //   - Calculate direction away
    //   - Weight by inverse distance (closer = stronger)
    //   - Add to total_threat vector
    // Return normalized total_threat
```

**That's it!** Nothing else affecting flee direction.

---

## ❌ WHAT'S DISABLED (Commented Out)

### **1. Escape Zone Pull**
- **Location:** `calculate_flee_direction()` lines 552-606
- **Status:** Fully commented out
- **Why:** Could be pulling humans in unexpected directions

### **2. Obstacle Avoidance**
- **Location:** `update_flee_direction()` line 682
- **Status:** Commented out
- **Why:** Could be rotating flee direction unexpectedly

### **3. Human Separation Forces**
- **Location:** `calculate_flee_direction()` lines 538-550
- **Status:** Already disabled (from v0.9.0)

### **4. Direction Inheritance**
- **Location:** `start_fleeing_with_direction()` 
- **Status:** Already disabled (from v0.9.0)

### **5. Danger Zone Check**
- **Location:** `update_flee_direction()` lines 687-698
- **Status:** Already disabled (from v0.9.0)

### **6. Human Blocking Check**
- **Location:** `avoid_obstacles()`
- **Status:** Already disabled (from v0.9.0)

---

## 🧪 EXPECTED BEHAVIOR

**With ONLY weighted zombie threat:**

**Single zombie approaching:**
```
- Human detects zombie from west
- Calculates direction: EAST (directly opposite)
- Flees EAST in straight line
- Should be very predictable!
```

**Multiple zombies:**
```
- Human sees 2 zombies (north and west)
- Calculates weighted average
- Flees toward southeast (away from both)
- May adjust as zombies move, but should be smooth
```

**Group of humans:**
```
- All humans see same zombie
- All calculate same flee direction
- All flee in same direction (with 0.05s cascade delays)
- Should move as coordinated group
```

---

## 🎯 WHAT THIS TESTS

**If flee behavior is NOW consistent and predictable:**
- ✅ Core zombie threat calculation works correctly
- ✅ Vision range fix (200px) is working
- ✅ Problem was in one of the disabled features
- → Start re-enabling features one by one to find culprit

**If flee behavior is STILL erratic:**
- ❌ Problem is in core weighted threat calculation itself
- ❌ OR vision system still has issues
- ❌ OR movement system has problems
- → Need deeper debugging of core systems

---

## 🔧 RE-ENABLING FEATURES (If Core Works)

**Step 1:** Re-enable obstacle avoidance
```gdscript
// Uncomment in update_flee_direction():
flee_direction = avoid_obstacles(flee_direction)
```
- Test: Does behavior stay consistent or become erratic?

**Step 2:** Re-enable escape zone pull
```gdscript
// Uncomment entire escape zone section in calculate_flee_direction()
```
- Test: Does behavior stay consistent?

**Step 3:** Consider re-enabling separation forces
```gdscript
// Uncomment human separation in calculate_flee_direction()
```
- Test: Does this help or hurt?

---

## 🐛 IF STILL ERRATIC - DEEP DEBUG

Add logging to see exactly what's happening:

```gdscript
func calculate_flee_direction() -> Vector2:
    print("=== FLEE DIRECTION CALC ===")
    print("Position: ", position)
    
    var total_threat := Vector2.ZERO
    var visible_zombie_count = 0
    
    for zombie in zombies:
        if can_see_unit(zombie):
            visible_zombie_count += 1
            var away = (position - zombie.position).normalized()
            var distance = position.distance_to(zombie.position)
            var weight = 1.0 - (distance / 200.0)
            
            print("  Zombie ", visible_zombie_count, " at ", zombie.position)
            print("    Distance: ", distance)
            print("    Away direction: ", away)
            print("    Weight: ", weight)
            print("    Contribution: ", away * weight)
            
            total_threat += away * weight
    
    print("Total visible zombies: ", visible_zombie_count)
    print("Total threat vector: ", total_threat)
    print("Normalized flee direction: ", total_threat.normalized())
    print("================")
    
    return total_threat.normalized()
```

This will show:
- How many zombies are visible
- Direction away from each zombie
- How they're weighted
- Final flee direction

---

## 📊 FEATURES STATUS SUMMARY

| Feature | Status | Location |
|---------|--------|----------|
| **Weighted zombie threat** | ✅ ACTIVE | calculate_flee_direction() |
| **Vision range (200px)** | ✅ ACTIVE | v0.9.1 fix |
| **Cascading panic delays** | ✅ ACTIVE | propagate_flee_to_group() |
| Escape zone pull | ❌ DISABLED | Commented out |
| Obstacle avoidance | ❌ DISABLED | Commented out |
| Human separation | ❌ DISABLED | Commented out |
| Direction inheritance | ❌ DISABLED | Not called |
| Danger zone check | ❌ DISABLED | Commented out |
| Human blocking | ❌ DISABLED | Commented out |

---

## 📝 FILES CHANGED

- `scripts/human.gd` - Commented out escape zone and obstacle avoidance

---

## 🎯 SUCCESS CRITERIA

**This version succeeds if:**
- Humans flee directly away from zombies
- Single zombie → straight line flee
- Multiple zombies → flee toward averaged "safe" direction
- Groups flee together in coordinated way
- NO erratic movement, NO random turns

**If successful:**
- Re-enable features one at a time
- Identify which feature causes erratic behavior
- Fix or tune that specific feature

**If still erratic:**
- Problem is in core systems
- Need to debug weighted threat calculation
- Or investigate movement/physics layer

---

**This is the diagnostic turning point!** 🔬
