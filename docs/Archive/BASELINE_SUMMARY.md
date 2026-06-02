# Dead Corps v0.9.0 - BASELINE VERSION

**Date:** February 12, 2026  
**Status:** Known Issues - Humans not fleeing properly  
**Purpose:** Clean starting point for next debugging session

---

## 📋 WHAT'S IN THIS VERSION

### ✅ ACTIVE FEATURES

#### **1. Weighted Zombie Threat**
- **Location:** `human.gd::calculate_flee_direction()` (line 509)
- **What it does:** Humans flee away from ALL visible zombies
- **Weighting:** Closer zombies = stronger influence
- **Formula:** `weight = 1.0 - (distance / max_range)`
- **Vision range:** 
  - IDLE: 120px (circular, 360°)
  - FLEEING: 100px (forward arc, 90°) ⚠️ **BUG: This shrinks vision!**

#### **2. Escape Zone Pull**
- **Location:** `human.gd::calculate_flee_direction()` (line 550)
- **What it does:** Pulls humans toward escape zone when within 200px
- **Strength:** 20% at max range (200px) → 80% at close range (50px)
- **Context-aware:** Won't pull if zombie blocking path (60° cone check)
- **Desperation mode:** Always seeks if within 100px

#### **3. Obstacle Avoidance (Walls)**
- **Location:** `human.gd::avoid_obstacles()` (line 447)
- **What it does:** Raycasts 80px ahead, tries alternative angles if blocked
- **Angles tested:** ±22.5°, ±45°, ±67.5°, ±90° (8 directions total)
- **Returns:** Direction with most clearance

#### **4. Cascading Panic Delays**
- **Location:** `human.gd::propagate_flee_to_group()` (line 835)
- **What it does:** When 1 human detects zombie, nearby allies flee with delays
- **Delay:** 0.05s per human (creates wave effect)
- **Trigger radius:** 80px
- **Minimum group size:** 4 humans
- **Note:** Uses normal `start_fleeing()`, NOT direction inheritance

#### **5. Group Vision Merging**
- **Location:** `vision_renderer.gd::draw_vision_groups()`
- **What it does:** 4+ units in same state = merged vision arc with badge
- **Visual:** Thick lines (3.5px), count badge ("×5")

#### **6. Vision Range Detection Fix**
- **Location:** `human.gd::can_see_unit()` (line 262)
- **What it does:** Accounts for unit radius (12px) so vision triggers at edge
- **Formula:** `effective_distance = distance - UNIT_RADIUS`

---

### ❌ DISABLED FEATURES (Commented Out)

#### **7. Human Separation Forces**
- **Location:** `human.gd::calculate_flee_direction()` (line 538-548) - COMMENTED
- **What it would do:** Repulsion from nearby humans (50px personal space)
- **Strength:** 40% of zombie threat weight

#### **8. Direction Inheritance**
- **Location:** `human.gd::start_fleeing_with_direction()` (line 635) - EXISTS BUT NOT CALLED
- **What it would do:** 70% inherited direction + 30% own calculation
- **Purpose:** Wave spreading in unified direction
- **Note:** Function exists but `propagate_flee_to_group()` uses normal `start_fleeing()` instead

#### **9. Danger Zone Check**
- **Location:** Not present in this version
- **What it would do:** Rotate 90° if zombie near flee target

#### **10. Human Blocking Check**
- **Location:** Not present in `avoid_obstacles()` human-specific check
- **What it would do:** Rotate 90° if human in path

---

## 🐛 KNOWN BUGS

### **Critical Bug #1: Vision Range Shrinks When Fleeing**
**Location:** `human.gd::calculate_flee_direction()` line 521
```gdscript
var max_range := flee_vision_range if current_state == State.FLEEING else idle_vision_radius
// IDLE: 120px → can see zombie
// Switches to FLEEING
// FLEEING: 100px → LOSES sight of zombie!
// Returns (0, 0) direction → sets target to current position → JITTER
```

**Impact:** Humans detect zombie, switch to fleeing, immediately lose sight, stop moving

**Fix needed:** Use 200px range when FLEEING (hyper-aware panic state)

---

### **Bug #2: Random Direction Fallback**
**Location:** `human.gd::calculate_flee_direction()` line 606-608
```gdscript
if total_threat.length() < 0.01:
    return Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
```

**Impact:** If no zombies visible, returns random direction instead of (0, 0)

**Fix needed:** Return `Vector2.ZERO` instead of random

---

### **Bug #3: Humans Not Moving (Primary Issue)**
**Status:** UNRESOLVED
**Symptoms:**
- Humans detect zombie ("Human detected zombie - fleeing!")
- Vision arc appears
- Humans jitter or don't move at all
- State changes to FLEEING but no actual movement

**Possible causes:**
1. Vision range shrinking (Bug #1) causing (0, 0) flee direction
2. Obstacle avoidance being too aggressive
3. Physics/movement system issue
4. Target setting issue

**Debugging strategy for next session:**
1. Fix Bug #1 (vision range)
2. Remove obstacle avoidance temporarily
3. Remove escape zone pull temporarily
4. Test pure weighted zombie threat
5. Add features back one by one

---

## 📊 GAME BALANCE

### **Unit Stats:**
- Zombie speed: 85 px/s
- Human speed: 90 px/s (5 px/s advantage)
- Zombie attack cooldown: 1.5s
- Human health: 40 HP
- Zombie damage: 15

### **Vision Ranges:**
- Human IDLE: 120px circle
- Human SENTRY: 180px 90° arc
- Human FLEEING: 100px 90° arc ⚠️ **TOO SHORT**
- Zombie auto-pursuit: 100px
- Vision display proximity threshold: 200px

---

## 🎮 EXPECTED BEHAVIOR (Not Working)

**Ideal scenario:**
1. Zombie approaches human group
2. Zombie at 190px: Vision arc appears (proximity threshold)
3. Zombie at 120px: First human detects (idle vision)
4. Human switches to FLEEING
5. Human STILL SEES zombie (should maintain sight)
6. `calculate_flee_direction()` returns direction AWAY
7. Human runs 200px in that direction
8. Group cascades (0.05s delays), all flee

**Actual behavior:**
1. Zombie approaches
2. Human detects: "Human detected zombie - fleeing!"
3. Switches to FLEEING
4. Vision shrinks to 100px
5. Loses sight of zombie
6. `calculate_flee_direction()` returns (0, 0)
7. Sets target to current position
8. Jitter/no movement

---

## 📁 FILE STRUCTURE

```
baseline-v0.9.0/
├── scenes/
│   ├── building.tscn
│   ├── debug_overlay.tscn
│   ├── end_game_overlay.tscn
│   ├── escape_zone.tscn
│   ├── human.tscn
│   ├── main.tscn
│   └── zombie.tscn
├── scripts/
│   ├── building.gd
│   ├── camera_controller.gd
│   ├── debug_overlay.gd
│   ├── end_game_overlay.gd
│   ├── escape_zone.gd
│   ├── game_manager.gd
│   ├── human.gd (32KB - main flee logic)
│   ├── initializer.gd
│   ├── selection_manager.gd
│   ├── unit.gd (18KB - base class)
│   ├── vision_renderer.gd (19KB - vision display)
│   └── zombie.gd (26KB - zombie AI)
└── BASELINE_SUMMARY.md (this file)
```

---

## 🔧 NEXT SESSION PRIORITIES

1. **Fix vision range bug** - Change fleeing vision from 100px to 200px
2. **Fix random direction bug** - Return Vector2.ZERO instead of random
3. **Test with minimal features:**
   - Start with JUST weighted zombie threat
   - No obstacle avoidance
   - No escape zone
   - No cascading
4. **Build back up incrementally:**
   - Add obstacle avoidance
   - Add escape zone
   - Add cascading
   - Consider re-enabling human separation

---

## 💡 DESIGN NOTES

### **Vision Philosophy:**
- **IDLE:** Relaxed awareness (120px circle)
- **SENTRY:** Focused watching (180px 90° arc)
- **FLEEING:** Should be HYPER-AWARE (200px 90° arc) - currently broken at 100px

### **Flee Direction Logic:**
The core algorithm:
```
For each visible zombie:
    Calculate direction away
    Weight by inverse distance (closer = stronger)
    Add to total_threat vector

If escape zone visible and clear path:
    Add pull toward zone (scaled by distance)

Return normalized total_threat
```

**The bug:** Vision shrinks mid-flee, breaking "visible zombie" check

---

## 📝 VERSION HISTORY

- **v0.8.x:** Previous working versions
- **v0.9.0:** THIS VERSION - Baseline with known bugs
- **v0.9.1:** (Next) Will have vision range fix
- **v0.10.0:** (Goal) Fully working flee mechanics

---

**END OF BASELINE SUMMARY**
