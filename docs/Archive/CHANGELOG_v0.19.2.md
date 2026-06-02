# Dead Corps - Changelog v0.19.2

**Release Date:** March 2, 2026  
**Focus:** Phase B2 Fixes - Waypoint Ordering, Visual Markers, Swing Behavior

---

## 🔧 **Bug Fixes**

### **Fix 1: Waypoint Order Reversed**

**Problem:** Visual waypoints loaded in reverse order (Waypoint3 → Waypoint2 → Waypoint1)

**Root Cause:** String comparison `a.name < b.name` wasn't handling numbers correctly

**Solution:** Changed to natural string comparison:
```gdscript
// OLD:
waypoint_nodes.sort_custom(func(a, b): return a.name < b.name)

// NEW:
waypoint_nodes.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
```

**Result:**
- ✅ Waypoints now load in correct order: 1 → 2 → 3 → ...
- ✅ Handles numbers correctly (Waypoint1 < Waypoint10, not Waypoint1 > Waypoint10)
- ✅ Added debug output to console showing sort order

**Console Output:**
```
Waypoint sort order for Human1:
  [0] Waypoint1
  [1] Waypoint2
  [2] Waypoint3
```

---

### **Fix 2: Visual Waypoint Markers**

**Problem:** Waypoints (Node2D) invisible in editor - hard to position

**Solution:** Auto-generate colored visual markers when waypoints load

**Implementation:**
```gdscript
func add_waypoint_visual_marker(waypoint: Node2D, index: int):
    # Create 12x12 ColorRect
    # Color based on human's instance ID (unique per human)
    # Add number label (1, 2, 3...)
    # Set owner so it saves with scene
```

**Features:**
- ✅ 12x12 pixel colored square at each waypoint
- ✅ Unique color per human (based on instance ID)
- ✅ Number label showing waypoint order (1, 2, 3...)
- ✅ Automatically created when waypoints load
- ✅ Saved with scene (persists in editor)

**Colors:**
- Generated using HSV with unique hue per human
- Bright (90% value), saturated (80%), semi-transparent (80% alpha)
- Each human's waypoints share same color
- Different humans have different colors

**Example:**
```
Human1 waypoints: Orange markers (1, 2, 3)
Human2 waypoints: Blue markers (1, 2, 3)
Human3 waypoints: Green markers (1, 2, 3)
```

---

### **Fix 3: Swing Arc During Patrol**

**Problem:** Sentries with swing enabled showed erratic behavior while patrolling

**Root Cause:**
- Swing arc centered on `sentry_facing_degrees` (initial direction)
- While patrolling, human faces movement direction
- Swing tried to oscillate around wrong center point
- Result: Jerky, unnatural head movements

**Solution:** Disable swing while actively patrolling

**Implementation:**
```gdscript
// Only swing when stationary (not patrolling)
if current_state == State.SENTRY and sentry_has_swing and not is_patrolling:
    update_swing_arc(delta)

// While patrolling, face movement direction
if is_patrolling:
    facing_direction = velocity.normalized()
```

**Behavior Changes:**

**Before:**
- Sentry walks waypoint path
- Tries to swing head while walking
- Center point is static initial direction
- Looks janky and unnatural

**After:**
- Sentry walks waypoint path
- Faces direction of movement (no swing)
- Clean, natural movement
- Swing only when stationary

**Future Enhancement (Phase C):**
- Pause at waypoints
- Swing while paused (look around)
- Resume walking (face movement direction)

---

## 📊 **Technical Details**

### **Natural String Comparison**

**Why it matters:**
```
Standard sort: "Waypoint1", "Waypoint10", "Waypoint2"
Natural sort:  "Waypoint1", "Waypoint2", "Waypoint10"
                           ↑ Correct numerical order
```

**GDScript method:**
```gdscript
String.naturalnocasecmp_to(other: String) -> int
Returns: -1 if this < other, 0 if equal, 1 if this > other
```

---

### **Visual Marker Generation**

**Color Algorithm:**
```gdscript
var hue = float(get_instance_id() % 360) / 360.0
var color = Color.from_hsv(hue, 0.8, 0.9, 0.8)
```

**Properties:**
- Instance ID is unique per node instance
- Modulo 360 gives hue (0-360 degrees on color wheel)
- Divide by 360 to normalize (0.0-1.0)
- HSV ensures visually distinct colors

**Marker Structure:**
```
Waypoint1 (Node2D)
└─ WaypointMarker (ColorRect)
   └─ WaypointNumber (Label)
```

---

### **Swing State Management**

**State Conditions:**

**Swing Enabled (stationary sentry):**
```
current_state == SENTRY
sentry_has_swing == true
is_patrolling == false
```

**Swing Disabled (patrolling):**
```
is_patrolling == true
→ Face movement direction instead
```

**Swing Disabled (fleeing):**
```
current_state == FLEEING
→ Face flee direction
```

---

## 🧪 **Testing Scenarios**

### **Test 1: Waypoint Order**

**Setup:**
- Create Human with 3 visual waypoints
- Name them: Waypoint1, Waypoint2, Waypoint3
- Position them in triangle pattern

**Expected:**
- Console shows: [0] Waypoint1, [1] Waypoint2, [2] Waypoint3
- Sentry walks: 1 → 2 → 3 → 1 (LOOP mode)

**Verify:**
- Check console output on game start
- Watch patrol path - should go in order

---

### **Test 2: Visual Markers**

**Setup:**
- Create Human with 4 visual waypoints
- Enable patrol
- Run game once (to generate markers)
- Stop game, check in editor

**Expected:**
- Each waypoint has colored square marker
- Numbers 1, 2, 3, 4 visible on markers
- All markers same color for this human
- Markers saved with scene (persist in editor)

**Verify:**
- Expand waypoint nodes in scene tree
- Should see WaypointMarker child
- Markers visible without selecting waypoint

---

### **Test 3: Swing Behavior**

**Setup:**
- Create sentry with patrol + swing enabled
- Waypoints: 2 points (simple back-and-forth)
- Patrol Mode: PING_PONG
- Sentry Has Swing: ON
- Swing Range: 45°

**Expected While Patrolling:**
- Sentry faces movement direction
- No swing oscillation while walking
- Clean, natural movement

**Expected If Stationary:**
- Sentry swings head left/right
- Oscillates around facing direction
- Pauses at extremes

**Verify:**
- Watch sentry vision arc while walking
- Should point forward (movement direction)
- Should NOT swing side-to-side

---

### **Test 4: Multiple Humans, Different Colors**

**Setup:**
- Create 3 sentries with visual waypoints
- Each has 3-4 waypoints
- All have patrol enabled

**Expected:**
- Human1 waypoints: One color (e.g., orange)
- Human2 waypoints: Different color (e.g., blue)
- Human3 waypoints: Different color (e.g., green)
- Each human's waypoints all share same color

**Verify:**
- Run game once to generate markers
- Stop and check in editor
- Each human's waypoint group has unique color

---

## 🎯 **Design Notes**

### **Why Disable Swing While Patrolling?**

**Realism:**
- Walking guard looks forward (where they're going)
- Not swinging head side-to-side while walking
- Save swing for stationary observation

**Gameplay:**
- Clear visual: Walking guard has predictable vision
- Forward arc follows movement direction
- Player can predict guard's sight lines

**Future (Phase C):**
- Guard walks to waypoint
- **Pauses** at waypoint (stops moving)
- **Swings** to look around (observation point)
- Resumes walking to next waypoint

---

### **Why Unique Colors Per Human?**

**Organizational:**
- Quickly identify which waypoints belong to which guard
- Useful for complex levels with many patrols
- Visual grouping without selecting

**Alternatives Considered:**
```
Single color:      All waypoints same color (harder to distinguish)
Random per marker: Each waypoint different (no grouping)
Manual per human:  Designer sets color (more work)
Instance ID:       Automatic, unique, no setup ✓
```

---

### **Why Natural Sort?**

**Problem with Standard Sort:**
```
Waypoint1
Waypoint10   ← Alphabetically before Waypoint2!
Waypoint2
Waypoint3
```

**Natural Sort Solution:**
```
Waypoint1
Waypoint2    ← Correct numerical order
Waypoint3
Waypoint10
```

**Handles:**
- Single digit: Waypoint1-9
- Double digit: Waypoint10-99
- Triple digit: Waypoint100+
- Mixed: Waypoint1, Waypoint001 (sorts correctly)

---

## 📋 **Files Modified**

### **scripts/human.gd**

**load_waypoints_from_children():**
- Changed sort to use `naturalnocasecmp_to()`
- Added debug output showing sort order
- Added call to `add_waypoint_visual_marker()`

**add_waypoint_visual_marker():** (NEW)
- Creates ColorRect marker
- Generates unique color per human
- Adds number label
- Sets owner for scene persistence

**_physics_process():**
- Added `and not is_patrolling` condition to swing update
- Updated facing direction logic for patrol
- Patrol movement overrides swing behavior

**update_patrol():**
- Removed redundant `facing_direction = direction` line
- Now handled in `_physics_process()` based on velocity

---

## 🚀 **What's Working**

✅ Visual waypoints load in correct order (1→2→3)  
✅ Colored markers auto-generated for visibility  
✅ Unique color per human for organization  
✅ Number labels show waypoint order  
✅ Swing disabled while patrolling (clean movement)  
✅ Face movement direction while walking  
✅ Markers persist in editor (saved with scene)  
✅ Natural sort handles 10+ waypoints correctly  

---

## 🔜 **Next: Phase C**

**Per-Waypoint Features:**
- Pause duration at each waypoint
- Swing arc at specific waypoints (observation points)
- Facing direction override at waypoints
- Different behaviors per waypoint in patrol

**Example Phase C Behavior:**
```
Waypoint1: Walk to corner
Waypoint2: PAUSE 3s, SWING 60°, look around
Waypoint3: Walk to hallway
Waypoint4: PAUSE 2s, FACE 90° (look down corridor)
Waypoint5: Return to start
```

---

**Version:** v0.19.2  
**Status:** Phase B2 complete and polished  
**Breaking Changes:** None - backwards compatible with manual waypoints
