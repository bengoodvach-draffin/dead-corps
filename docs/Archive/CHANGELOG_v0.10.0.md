# v0.10.0 - Smart Flee System (No More Random!)

**Date:** February 13, 2026  
**Status:** Major upgrade - Intelligent flee behavior  
**Previous version:** v0.9.5 (extended vision)

---

## 🎯 MAJOR CHANGE: NO MORE RANDOM MOVEMENT

**Old behavior:**
- Humans lost sight of zombie → returned RANDOM direction
- Unpredictable, erratic movement
- Humans wandered aimlessly

**New behavior:**
- Humans lost sight → intelligent priority-based decisions
- Predictable, purposeful movement
- **No random vectors!** (except extreme edge case: zombies perfectly cancel out)

---

## ✅ WHAT'S NEW

### **1. Priority-Based Flee System**

When no zombies are visible, humans now follow this decision tree:

```
No visible threats detected:
  ↓
PRIORITY 1: Am I being actively pursued?
  YES → Keep fleeing in last direction (being hunted!)
  NO  → Continue ↓

PRIORITY 2: Is escape zone within 200px with line-of-sight?
  (Only if currently FLEEING state)
  YES → Flee toward escape zone (safety nearby!)
  NO  → Continue ↓

PRIORITY 3: How long since I last saw a threat?
  < 5 seconds → Keep fleeing in last direction (momentum)
  ≥ 5 seconds → Continue ↓

PRIORITY 4: Truly safe - STOP FLEEING
  Return Vector2.ZERO (stand still)
```

---

### **2. Pursuit Detection**

**New function:** `is_being_pursued()`

```gdscript
func is_being_pursued() -> bool:
    # Checks if any zombie has locked onto this human as attack_target
    # Returns true if being actively hunted
```

**Why it matters:**
- Zombie behind wall → human can't see it
- But zombie locked on as target → still chasing
- Human keeps fleeing (knows it's in danger)
- **No random movement when being hunted**

---

### **3. Momentum System with 5-Second Timeout**

**New variable:** `last_threat_time`

**How it works:**
1. Human sees zombie → flees, updates `last_threat_time`
2. Zombie goes out of sight (200px+ away)
3. Human checks: time since last threat?
   - < 5 seconds → **Keep fleeing** (momentum)
   - ≥ 5 seconds → **Stop** (timeout, truly safe)

**Example:**
```
t=0s:  See zombie, start fleeing, last_threat_time = 0
t=2s:  Zombie at 210px (out of sight), elapsed = 2s
       → Momentum: Keep fleeing
t=5s:  Still no zombie, elapsed = 5s
       → Momentum: Keep fleeing
t=7s:  Still no zombie, elapsed = 7s
       → TIMEOUT: Stop fleeing ✅
```

---

### **4. Smart Escape Zone Seeking**

**Only triggers when:**
- Human is currently in FLEEING state (not idle)
- Escape zone within 200px
- Line-of-sight to escape zone
- No visible threats and not being pursued

**Benefits:**
- Humans flee TO safety, not just AWAY from danger
- Purposeful movement even without visible threats
- Gameplay objective-oriented

---

### **5. Vision Range Reduced Back to 200px**

**Changed from:** 300px (v0.9.5)  
**Changed to:** 200px (original)

**Why this works now:**
- Momentum system covers the 5-second gap after losing sight
- Being-pursued detection catches locked-on zombies
- More realistic vision range
- Better chase tension gameplay

**Vision ranges:**
- IDLE: 120px, 360°
- SENTRY: 180px, 90°
- FLEEING: 200px, 360°

---

## 📊 BEHAVIOR EXAMPLES

### **Example A: Lost Sight Mid-Flee**
```
t=0s:  Human at (100, 50), zombie at (50, 50), distance: 50px
       → Sees zombie, flees EAST, last_threat_time = 0

t=2s:  Human at (180, 50), zombie at (80, 50), distance: 100px
       → Still sees zombie, flees EAST, last_threat_time = 2

t=4s:  Human at (260, 50), zombie at (110, 50), distance: 150px
       → Still sees zombie, flees EAST, last_threat_time = 4

t=6s:  Human at (340, 50), zombie at (140, 50), distance: 200px
       → Still sees zombie, flees EAST, last_threat_time = 6

t=8s:  Human at (420, 50), zombie at (170, 50), distance: 250px
       → LOST SIGHT (> 200px)
       → Priority 3: Momentum (elapsed: 2s < 5s)
       → Keeps fleeing EAST ✅

t=10s: Human at (500, 50), zombie at (200, 50), distance: 300px
       → Still no sight
       → Priority 3: Momentum (elapsed: 4s < 5s)
       → Keeps fleeing EAST ✅

t=14s: Human at (660, 50), zombie at (260, 50), distance: 400px
       → Still no sight
       → Momentum timeout (elapsed: 8s ≥ 5s)
       → Priority 4: STOP ✅
```

### **Example B: Zombie Locked On (Behind Wall)**
```
t=0s:  Human sees zombie, starts fleeing
t=2s:  Human turns corner, zombie now behind wall
       → Can't see zombie (LOS blocked)
       → But zombie.attack_target == this human
       → Priority 1: BEING PURSUED!
       → Keeps fleeing ✅ (never stops while hunted)
```

### **Example C: Escape Zone Nearby**
```
Human at (100, 50), lost sight of zombie
Escape zone at (180, 60), distance: 80px
  → Priority 2: Within 200px with LOS
  → Flees toward escape zone ✅
  → Reaches safety!
```

---

## 🐛 BUGS FIXED

### **Bug #1: Random Direction on Loss of Sight**
**Before:** Lost sight → random direction → erratic movement  
**After:** Lost sight → momentum/pursuit/escape zone → **purposeful movement** ✅

### **Bug #2: Stopping While Being Hunted**
**Before:** Lost sight of pursuing zombie → eventually stopped → got caught  
**After:** Checks if zombie locked on → keeps fleeing even if can't see ✅

### **Bug #3: Ignoring Nearby Escape Zone**
**Before:** Lost sight → random → might flee AWAY from escape  
**After:** Seeks escape zone when close → **intelligent goal-seeking** ✅

---

## 📝 TECHNICAL CHANGES

### **New Functions:**
```gdscript
func is_being_pursued() -> bool:
    # Checks if any zombie has this human as attack_target
    # Returns true if being actively hunted
```

### **New Variables:**
```gdscript
var last_threat_time: float = 0.0
# Timestamp (in seconds) when human last saw a threat
# Used for 5-second momentum timeout
```

### **Modified Functions:**
```gdscript
func calculate_flee_direction() -> Vector2:
    # Now implements 4-priority fallback system
    # Updates last_threat_time when threats visible
    # Returns Vector2.ZERO when truly safe (no more random!)
```

---

## 🎯 EDGE CASES

### **The Only Remaining Random Case:**
**Zombies perfectly cancel out (extremely rare):**
```
Human at (100, 100)
Zombie A at (50, 100)  → flee direction: (1, 0)
Zombie B at (150, 100) → flee direction: (-1, 0)
Total: (0, 0) → would use momentum or stop
```

**This is so rare it's negligible** - requires perfect symmetry.

---

## ✅ FILES CHANGED

- `scripts/human.gd`:
  - Added `last_threat_time` variable
  - Added `is_being_pursued()` function
  - Modified `calculate_flee_direction()` with priority system
  - Reduced vision from 300px → 200px (2 locations)

---

## 📊 FEATURES STATUS

| Feature | Status | Notes |
|---------|--------|-------|
| **Weighted zombie threat** | ✅ ACTIVE | Core flee logic |
| **Priority flee system** | ✅ NEW! | 4-tier intelligent fallback |
| **Pursuit detection** | ✅ NEW! | Keeps fleeing when hunted |
| **Momentum timeout** | ✅ NEW! | 5-second grace period |
| **Escape zone seeking** | ✅ NEW! | Seek safety when close |
| **Vision: 200px, 360°** | ✅ ACTIVE | Reduced from 300px |
| **Cascading panic** | ✅ ACTIVE | 0.05s delays |
| **Debug logging** | ✅ ACTIVE | First human only |
| Obstacle avoidance | ❌ DISABLED | Still commented out |
| Escape zone pull | ❌ DISABLED | Still commented out |

---

## 🧪 WHAT TO TEST

**Smooth flee behavior:**
- Single zombie → humans flee directly away
- Lose sight → humans keep fleeing for 5 seconds
- Timeout → humans stop (safe)
- **NO random turns or erratic movement** ✅

**Pursuit detection:**
- Zombie locks on, human goes behind wall
- Human should keep fleeing (knows it's hunted)

**Escape zone seeking:**
- Human near escape zone without visible threats
- Should flee toward safety

**Group behavior:**
- Multiple humans detect same zombie
- Should flee in coordinated direction (cascading delays)

---

## 🔮 NEXT STEPS

**If flee behavior is now smooth and intelligent:**

1. **Re-enable obstacle avoidance**
   - Test if humans avoid walls smoothly
   - May need tuning with new priority system

2. **Re-enable escape zone pull**
   - Now redundant with Priority 2?
   - Or keep as additional force when threats visible?

3. **Fine-tune timeout**
   - 5 seconds too long/short?
   - Different timeout for being pursued?

4. **Consider cohesion forces**
   - Groups stay together while fleeing?

---

## 📂 VERSION HISTORY

- v0.9.0 - Baseline (vision bugs, erratic flee)
- v0.9.1 - Vision range fix (120/100 → 200px)
- v0.9.2 - Minimal flee (disabled features)
- v0.9.3 - Debug logging
- v0.9.4 - Vision arc fix (90° → 360°)
- v0.9.5 - Extended vision (200px → 300px)
- **v0.10.0 - Smart flee system (NO MORE RANDOM!)** ← YOU ARE HERE

---

**This is a major milestone!** Humans now think intelligently instead of moving randomly. 🧠✨

**END OF CHANGELOG**
