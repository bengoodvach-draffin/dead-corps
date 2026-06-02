# Dead Corps - v0.16.0: Panic Spreading Fix

**Release Date:** February 27, 2026  
**Focus:** Sentry Panic Spreading - Reacting to Nearby Attacks

---

## 🎯 The Problem

**Issue:** Sentries with directional vision arcs (90°) would not react when zombies attacked from behind. The entire group would be killed one-by-one without fleeing.

**Example Scenario:**
```
[Sentry] [Sentry] [Sentry] [Sentry] [Sentry]
   ↓        ↓        ↓        ↓        ↓
 (all facing north)

                            Zombie attacks from SOUTH ↑
```

**What Happened:**
1. Zombie approaches from behind (south)
2. All sentries facing north - can't see zombie
3. Zombie grapples rear sentry
4. Rear sentry transitions: SENTRY → GRAPPLED (skips FLEEING)
5. Other sentries still can't see zombie - don't react
6. Zombie kills grappled human, moves to next one
7. Repeat until all dead

**Root Cause:** Sentries only reacted to zombies they could SEE in their vision arc. If attacked from behind, they had no way to know danger was present.

---

## ✅ The Solution: Panic Spreading

**New Behavior:** Humans now panic when they notice nearby allies being attacked, **even if they can't see the zombie**.

### **How It Works:**

Every detection cycle, humans check:
1. **Can I see a zombie?** ← Original check
2. **Is a nearby human being attacked?** ← NEW check
3. If EITHER is true → FLEE!

### **Panic Trigger Conditions:**

A human panics if a nearby ally (within 120px) is:
- **Being grappled** (current_state == GRAPPLED)
- **Being chased** (attacker_count > 0)

### **Panic Behavior:**

When panic is triggered:
```gdscript
print("Human at ", position, " panicking - ally under attack nearby!")
current_state = State.FLEEING

// Flee AWAY from the ally's position (danger is there)
var flee_away := (position - ally.position).normalized()
start_fleeing_in_direction(flee_away)
```

**Result:** Creates realistic "oh crap, they got Jim!" group panic behavior!

---

## 🎮 Gameplay Impact

### **Before v0.16.0:**

Sentry group facing north, zombie from south:
```
Zombie kills Sentry #5 (rear)
Zombie kills Sentry #4
Zombie kills Sentry #3
Zombie kills Sentry #2
Zombie kills Sentry #1
All dead - zero fled
```

### **After v0.16.0:**

Sentry group facing north, zombie from south:
```
Zombie grapples Sentry #5 (rear)
Sentry #4 notices: "My friend is under attack!" → FLEES
Sentry #3 notices: "People are fleeing!" → FLEES
Sentry #2 notices: "People are fleeing!" → FLEES  
Sentry #1 notices: "People are fleeing!" → FLEES
Chain reaction creates natural panic wave!
```

---

## 🔧 Technical Implementation

### **Added to check_for_nearby_zombies():**

```gdscript
// PANIC SPREADING: Check before vision system
var panic_radius: float = 120.0  // Slightly larger than idle vision

for ally in nearby_humans:
    var distance_to_ally := position.distance_to(ally.position)
    
    if distance_to_ally <= panic_radius:
        // Check if ally is in distress
        if ally.current_state == State.GRAPPLED or ally.attacker_count > 0:
            // PANIC! Friend under attack!
            current_state = State.FLEEING
            
            // Flee away from danger zone
            var flee_away := (position - ally.position).normalized()
            start_fleeing_in_direction(flee_away)
            return  // Flee immediately
```

### **New Helper Function:**

```gdscript
func start_fleeing_in_direction(direction: Vector2) -> void:
    velocity = Vector2.ZERO
    has_target = false
    attack_target = null
    
    var safe_direction := avoid_obstacles(direction)
    var flee_target := position + safe_direction * flee_distance
    
    last_flee_direction = safe_direction.normalized()
    last_threat_time = Time.get_ticks_msec() / 1000.0
    set_move_target(flee_target)
```

**Purpose:** Allows fleeing in a direction without needing a visible zombie target.

---

## 📏 Parameters

### **Panic Radius: 120px**

**Why 120px?**
- Larger than idle vision (100px) - notices slightly more
- Smaller than flee vision (200px) - not too sensitive
- Matches realistic "hearing a scuffle" distance
- Prevents entire map from panicking at once

**Tuning Options:**
- **Smaller (80px):** More realistic, requires tighter formations
- **Larger (150px):** More sensitive, easier group survival
- **Current (120px):** Balanced middle ground

---

## 🧪 Testing Scenarios

### **Test 1: Sentry Line - Rear Attack**

**Setup:**
1. Place 5 sentries in a line, all facing north
2. Send zombie from south to attack rear sentry
3. Observe panic propagation

**Expected:**
- Zombie grapples rear sentry ✓
- Adjacent sentry notices and flees ✓
- Panic wave spreads forward through line ✓
- Most/all sentries escape ✓

---

### **Test 2: Sentry Circle - Central Attack**

**Setup:**
1. Place sentries in circle, all facing outward
2. Send zombie to center, attack one sentry
3. Observe radial panic spread

**Expected:**
- Zombie grapples one sentry ✓
- Adjacent sentries panic and flee outward ✓
- Creates natural scatter pattern ✓

---

### **Test 3: Mixed Idle/Sentry**

**Setup:**
1. Mix of idle (360° vision) and sentry (90° arc) humans
2. Zombie attacks from sentry blind spot

**Expected:**
- Either idle sees zombie OR sentry notices ally panic ✓
- Group reacts appropriately ✓
- Panic still spreads if needed ✓

---

## 📦 Files Modified

**scripts/human.gd:**
- Added panic spreading check in `check_for_nearby_zombies()`
- Added `start_fleeing_in_direction()` helper function
- Panic check runs BEFORE vision system

---

## 🎓 Design Philosophy

### **Humans Are Social Creatures**

Real people don't need to see a threat to know it's there. They notice:
- Friends yelling
- People running
- Sounds of struggle
- Body language panic

**In-game:** Checking `attacker_count > 0` and `GRAPPLED` state simulates this social awareness.

### **Panic Spreads Organically**

The cascade effect:
1. First victim gets attacked
2. Nearest ally notices → flees
3. Their movement alerts others → flee
4. Creates natural wave pattern

**Not a global alarm** - panic spreads through proximity, creating realistic group dynamics.

### **Vision Arc Tradeoff**

Sentries gain:
- ✅ Focused surveillance
- ✅ Directional watching
- ✅ Tactical positioning

Sentries lose:
- ❌ 360° awareness
- ❌ Can be flanked

**Panic spreading balances this** - sentries aren't helpless, but also aren't omniscient.

---

## 🚀 Future Enhancements

**Possible Improvements:**
- Different panic radii for different human types
- Police/military don't panic, they investigate
- Panic intensity based on how many allies in distress
- Sound-based alerts (hearing distance > seeing distance)
- False alarms (panicking at nothing occasionally)

---

## 🎮 Gameplay Tips

**For Players:**
- Flanking sentry groups is now less effective
- Spread out zombies to avoid triggering mass panic
- Target isolated sentries to prevent chain reactions

**For Level Designers:**
- Sentry formations now viable even with gaps
- Can place sentries back-to-back for coverage
- 120px spacing = max distance for panic chain

---

**Version:** v0.16.0  
**Status:** Panic spreading implemented and ready for testing  
**Breaking Changes:** None - additive feature only
