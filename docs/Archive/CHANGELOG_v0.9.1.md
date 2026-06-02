# v0.9.1 - Vision Range Fixes Only

**Date:** February 13, 2026  
**Status:** Bug fixes - Vision range corrected  
**Previous version:** v0.9.0 (baseline)

---

## 🐛 BUGS FIXED

### **Bug #1: Vision Shrinks When Fleeing**
**Location:** `human.gd::calculate_flee_direction()` line 521  
**Problem:** Vision range decreased from 120px (idle) to 100px (fleeing), causing humans to lose sight of zombies immediately after detecting them  
**Fix:** Changed to use 200px range consistently when calculating flee direction  

**Before:**
```gdscript
var max_range := flee_vision_range if current_state == State.FLEEING else idle_vision_radius
//                100px when fleeing    120px when idle
```

**After:**
```gdscript
var max_range: float = 200.0  # Always use wide range (hyper-aware panic)
```

---

### **Bug #2: Inconsistent Vision in can_see_unit()**
**Location:** `human.gd::can_see_unit()` line 296  
**Problem:** FLEEING state still used 100px range for visibility check, inconsistent with calculate_flee_direction()  
**Fix:** Changed to use 200px range for FLEEING state  

**Before:**
```gdscript
State.FLEEING:
    in_range = effective_distance <= flee_vision_range  # 100px
```

**After:**
```gdscript
State.FLEEING:
    in_range = effective_distance <= 200.0  # Hyper-aware panic state
```

---

## ⚠️ NOT FIXED (Yet)

### **Random Direction Fallback**
**Location:** `human.gd::calculate_flee_direction()` line 608-609  
**Status:** LEFT AS-IS (returns random direction when no threats)  
**Reason:** Changing to Vector2.ZERO may be causing movement to break - need to investigate further

This will be addressed in v0.9.2 after vision fixes are confirmed working.

---

## 💡 REASONING

**Why 200px for fleeing?**
1. **Psychologically accurate:** Scared people are MORE aware, not less (adrenaline)
2. **Matches vision display:** Vision arcs show at 200px proximity threshold
3. **Prevents sight loss:** Humans detect at 120px idle, switching to flee shouldn't lose sight
4. **Gameplay clarity:** No confusing gap between "vision arc appears" and "flee triggers"

**Vision Range Progression:**
- IDLE: 120px circle (relaxed awareness)
- SENTRY: 180px arc (focused watching)
- FLEEING: 200px arc (hyper-aware panic) ← WIDER than idle!

---

## 📊 EXPECTED BEHAVIOR AFTER FIXES

### **Scenario: Zombie Approaches Group**

**Before (broken):**
```
1. Zombie at 190px → Vision arc appears
2. Zombie at 115px → Human detects (120px idle vision)
3. Human switches to FLEEING
4. Vision shrinks to 100px → LOSES SIGHT
5. calculate_flee_direction() may return wrong direction
6. Human moves erratically
```

**After (fixed):**
```
1. Zombie at 190px → Vision arc appears
2. Zombie at 115px → Human detects (120px idle vision)
3. Human switches to FLEEING
4. Vision EXPANDS to 200px → MAINTAINS SIGHT ✅
5. calculate_flee_direction() sees zombie consistently
6. Human should flee more reliably
```

---

## ✅ FILES CHANGED

- `scripts/human.gd` - Vision range fixes (2 locations only)

---

## 📝 CHANGES IN THIS VERSION

**APPLIED:**
- ✅ Vision range 120/100 → 200 in calculate_flee_direction()
- ✅ Vision range 100 → 200 in can_see_unit() for FLEEING state

**NOT APPLIED (reverted):**
- ❌ Random direction → Vector2.ZERO (caused movement to break)

---

## 🎯 NEXT STEPS

**If humans flee more consistently:**
- Great! Vision range was the main issue
- Can revisit Vector2.ZERO change carefully later

**If still random/broken:**
- Disable obstacle avoidance
- Disable escape zone pull
- Add debug logging to see what's happening

**Date:** February 13, 2026  
**Status:** Bug fixes - Vision range corrected  
**Previous version:** v0.9.0 (baseline)

---

## 🐛 BUGS FIXED

### **Bug #1: Vision Shrinks When Fleeing**
**Location:** `human.gd::calculate_flee_direction()` line 521  
**Problem:** Vision range decreased from 120px (idle) to 100px (fleeing), causing humans to lose sight of zombies immediately after detecting them  
**Fix:** Changed to use 200px range consistently when calculating flee direction  

**Before:**
```gdscript
var max_range := flee_vision_range if current_state == State.FLEEING else idle_vision_radius
//                100px when fleeing    120px when idle
```

**After:**
```gdscript
var max_range: float = 200.0  # Always use wide range (hyper-aware panic)
```

---

### **Bug #2: Random Direction Fallback**
**Location:** `human.gd::calculate_flee_direction()` line 608-609  
**Problem:** When no zombies visible, returned random direction instead of staying put  
**Fix:** Return `Vector2.ZERO` instead of random direction  

**Before:**
```gdscript
if total_threat.length() < 0.01:
    return Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
```

**After:**
```gdscript
if total_threat.length() < 0.01:
    return Vector2.ZERO  # Don't move if no threats
```

---

### **Bug #3: Inconsistent Vision in can_see_unit()**
**Location:** `human.gd::can_see_unit()` line 296  
**Problem:** FLEEING state still used 100px range for visibility check, inconsistent with calculate_flee_direction()  
**Fix:** Changed to use 200px range for FLEEING state  

**Before:**
```gdscript
State.FLEEING:
    in_range = effective_distance <= flee_vision_range  # 100px
```

**After:**
```gdscript
State.FLEEING:
    in_range = effective_distance <= 200.0  # Hyper-aware panic state
```

---

## 💡 REASONING

**Why 200px for fleeing?**
1. **Psychologically accurate:** Scared people are MORE aware, not less (adrenaline)
2. **Matches vision display:** Vision arcs show at 200px proximity threshold
3. **Prevents sight loss:** Humans detect at 120px, switching to flee shouldn't lose sight
4. **Gameplay clarity:** No confusing gap between "vision arc appears" and "flee triggers"

**Why Vector2.ZERO instead of random?**
1. **Predictable behavior:** Humans shouldn't wander randomly
2. **Better debugging:** Clear signal when no threats detected
3. **Realistic:** People don't run randomly when no danger visible

---

## 📊 EXPECTED BEHAVIOR AFTER FIXES

### **Scenario: Zombie Approaches Group**

**Before (broken):**
```
1. Zombie at 190px → Vision arc appears
2. Zombie at 115px → Human detects (120px idle vision)
3. Human switches to FLEEING
4. Vision shrinks to 100px → LOSES SIGHT
5. calculate_flee_direction() returns (0,0) or random
6. Human jitters or moves randomly
```

**After (fixed):**
```
1. Zombie at 190px → Vision arc appears
2. Zombie at 115px → Human detects (120px idle vision)
3. Human switches to FLEEING
4. Vision STAYS at 200px → MAINTAINS SIGHT ✅
5. calculate_flee_direction() returns direction away from zombie
6. Human flees smoothly 200px in that direction ✅
7. Group cascades (0.05s delays), all flee same direction ✅
```

---

## 🎯 NEXT STEPS IF STILL BROKEN

If humans still flee in random/weird directions after these fixes:

**Test 1: Disable Obstacle Avoidance**
```gdscript
// In update_flee_direction():
flee_direction = avoid_obstacles(flee_direction)  // COMMENT OUT
```
- Tests if obstacle avoidance is causing erratic direction changes

**Test 2: Disable Escape Zone Pull**
```gdscript
// In calculate_flee_direction():
// Comment out entire "Check for escape zone attraction" section
```
- Tests if escape zone is pulling humans in unexpected directions

**Test 3: Add Debug Logging**
```gdscript
func calculate_flee_direction() -> Vector2:
    print("=== FLEE CALC ===")
    print("Position: ", position)
    
    var total_threat := Vector2.ZERO
    for zombie in zombies:
        if can_see_unit(zombie):
            var away = (position - zombie.position).normalized()
            print("  Fleeing from zombie at ", zombie.position, " direction: ", away)
            total_threat += away * weight
    
    print("Total flee direction: ", total_threat.normalized())
    return total_threat.normalized()
```
- Shows exactly which zombies are influencing flee direction

---

## ✅ FILES CHANGED

- `scripts/human.gd` - Vision range fixes (3 locations)

---

## 📝 VERSION HISTORY

- v0.9.0 - Baseline (humans flee in random directions, vision bugs)
- v0.9.1 - Vision range & random direction fixes (this version)
- v0.9.2 - (Next) TBD based on testing results
