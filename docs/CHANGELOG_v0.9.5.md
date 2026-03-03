# v0.9.5 - Extended Flee Vision Range

**Date:** February 13, 2026  
**Status:** Bug fix - Extended vision range  
**Previous version:** v0.9.4 (vision arc fix)

---

## 🐛 BUG FIXED

### **Humans Losing Sight Mid-Flee**

**Problem:**
- Humans fled away from zombies successfully (v0.9.4 fix worked!)
- But after fleeing ~170-200px, they'd lose sight of the zombie
- Next update: `calculate_flee_direction()` returned RANDOM direction
- Result: Sudden, erratic direction changes mid-flee

**Evidence from logs:**
```
Position 1: distance: 113px  ✓ Can see zombie, flee correctly
Position 2: distance: 115px  ✓ Still see zombie, flee correctly
Position 3: distance: 170px  ✓ Still see zombie, flee correctly
Position 4: distance: 205px  ✗ LOST SIGHT (>200px limit)
  → Returns random direction
  → Sudden direction change!

Later:
"Human at (287.94, -24.20) stopped fleeing - no zombies visible"
```

---

## ✅ THE FIX

**Increased flee vision range: 200px → 300px**

**Changes made:**

### **1. calculate_flee_direction() - Line 540**
```gdscript
// BEFORE:
var max_range: float = 200.0

// AFTER:
var max_range: float = 300.0  // Extended to maintain sight while fleeing
```

### **2. can_see_unit() FLEEING case - Line 302**
```gdscript
// BEFORE:
in_range = effective_distance <= 200.0

// AFTER:
in_range = effective_distance <= 300.0  // Extended range
```

---

## 💡 REASONING

**Why 300px?**

1. **Humans are faster than zombies:**
   - Human speed: 90 px/s
   - Zombie speed: 85 px/s
   - 5 px/s advantage means humans pull away

2. **Detection interval: 0.3 seconds:**
   - In 0.3s, human moves: 90 * 0.3 = 27px
   - In 0.3s, zombie moves: 85 * 0.3 = 25.5px
   - Net separation: 1.5px per update

3. **Distance accumulation:**
   - Human detects at 120px (idle vision)
   - Flees for several updates
   - Distance grows: 120 → 150 → 180 → 210px
   - At 200px: loses sight → random direction!

4. **300px buffer:**
   - Gives ~80px buffer before losing sight
   - ~50 updates (15 seconds) of fleeing before loss
   - Plenty of time to reach safety or escape zone

---

## 📊 VISION RANGES SUMMARY

| State | Range | Arc | Purpose |
|-------|-------|-----|---------|
| **IDLE** | 120px | 360° | Casual awareness |
| **SENTRY** | 180px | 90° | Focused watching |
| **FLEEING** | 300px | 360° | **Hyper-aware panic + maintain sight while fleeing** ✅ |

---

## 🎯 EXPECTED BEHAVIOR NOW

**Zombie approaches from west:**
1. Human detects at 120px (IDLE)
2. Switches to FLEEING (300px, 360°)
3. Flees EAST consistently
4. Zombie chases but human is faster
5. Distance grows: 120 → 150 → 180 → 210 → 240 → 270px
6. **Human STILL sees zombie** (within 300px) ✅
7. Continues fleeing smoothly until safe or escaped
8. **No random direction changes** ✅

---

## 🧪 TESTING NOTES

**What to observe:**
- Humans should flee in smooth, consistent directions
- No sudden 90° or random turns mid-flee
- Humans should maintain flight until reaching escape zone or very far away
- Group should flee together without individuals veering off

**If you still see erratic behavior:**
- Check if obstacle avoidance is re-enabled (should still be disabled)
- Check if escape zone pull is re-enabled (should still be disabled)
- Send new debug logs

---

## 📝 FILES CHANGED

- `scripts/human.gd` - Vision range 200px → 300px (2 locations)

---

## 🎯 FEATURES STATUS

| Feature | Status | Notes |
|---------|--------|-------|
| **Weighted zombie threat** | ✅ ACTIVE | Core flee logic |
| **Vision: 300px, 360°** | ✅ ACTIVE | Extended range + no arc |
| **Cascading panic** | ✅ ACTIVE | 0.05s delays |
| Escape zone pull | ❌ DISABLED | Still commented out |
| Obstacle avoidance | ❌ DISABLED | Still commented out |

---

## 📂 VERSION HISTORY

- v0.9.0 - Baseline (vision bugs, erratic flee)
- v0.9.1 - Vision range fix (120/100 → 200px)
- v0.9.2 - Minimal flee (disabled features for testing)
- v0.9.3 - Debug logging added
- v0.9.4 - Vision arc fix (90° → 360° for FLEEING)
- **v0.9.5 - Extended vision (200px → 300px)** ← YOU ARE HERE

---

## 🔮 NEXT STEPS

**If flee behavior is now smooth and consistent:**

1. **Re-enable obstacle avoidance** (one at a time)
   - Test if it stays smooth
   - May need tuning

2. **Re-enable escape zone pull**
   - Test if it creates good gameplay
   - May need tuning

3. **Consider separation forces**
   - Might prevent unit clumping
   - Test carefully

4. **Tune detection_interval**
   - Currently 0.3s
   - Could increase to 0.5s for less frequent updates
   - Trade-off: responsiveness vs stability

---

**END OF CHANGELOG**
