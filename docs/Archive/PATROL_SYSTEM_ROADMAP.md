# Dead Corps - Sentry/Patrol System Roadmap

**Current Status:** Phase A Complete (Degrees + Swing Arc)  
**Next Steps:** Phase B & C (Patrol System)

---

## ✅ **Phase A - COMPLETE**

- ✅ Degree-based sentry direction (0° = North)
- ✅ Visual arrow in editor showing facing
- ✅ Swing arc mechanics (sin/cos smooth motion)
- ✅ Parameters: swing_range, swing_speed, swing_pause

**Result:** Static sentries work perfectly with swinging vision arcs!

---

## 🎯 **Phase B1 - Basic Patrol System** (NEXT)

### **Goal:** Get sentries moving along waypoints

### **Features to Implement:**

**1. Waypoint Array System**
```gdscript
@export var patrol_waypoints: Array[Vector2] = []
@export var patrol_mode: PatrolMode = PatrolMode.LOOP
@export var patrol_speed: float = 50.0  # Slower than flee speed

enum PatrolMode {
    LOOP,        # 0→1→2→3→0→1... (circular)
    PING_PONG    # 0→1→2→3→2→1→0 (back-and-forth)
}
```

**2. Patrol State Management**
```gdscript
var current_waypoint_index: int = 0
var is_patrolling: bool = false
var patrol_direction: int = 1  # 1 = forward, -1 = backward (for PING_PONG)
```

**3. Movement Logic**
- Move toward `waypoints[current_waypoint_index]`
- When reached (within ~10px), advance to next waypoint
- LOOP mode: wraps around (0→1→2→0)
- PING_PONG mode: reverses at ends (0→1→2→1→0)

**4. Facing Direction**
- While moving: face movement direction
- While at waypoint: maintain last movement direction (or use swing if enabled)

**5. Debug Visualization**
- Draw lines connecting waypoints in editor (@tool)
- Show current waypoint with highlight
- Number each waypoint

---

### **Implementation Steps:**

**Step 1: Add Export Properties**
- waypoints array
- patrol_mode enum
- patrol_speed

**Step 2: Add Patrol Logic**
- `update_patrol()` function called in `_physics_process()`
- Check distance to current waypoint
- Advance when reached
- Handle LOOP vs PING_PONG

**Step 3: Movement Integration**
- Use existing `set_move_target()` from Unit
- Set velocity based on patrol_speed
- Face movement direction

**Step 4: Editor Visualization**
- In `_draw()`, connect waypoint dots with lines
- Draw numbers at each waypoint
- Show patrol path preview

---

### **Manual Waypoint Entry (Phase B1):**

Level designers type waypoints in Inspector:
```
Patrol Waypoints:
  [0]: (100, 100)
  [1]: (200, 100)
  [2]: (200, 200)
  [3]: (100, 200)
```

**Not pretty, but functional!**

---

### **Expected Result:**

```
Sentry walks: (100,100) → (200,100) → (200,200) → (100,200) → [LOOP]
```

With visual path shown in editor!

---

## 🎨 **Phase B2 - Visual Waypoint Editor** (LATER)

### **Goal:** Make waypoint placement easy and visual

### **Approach: Child Node Method**

Instead of typing coordinates, use Node2D children:

**Setup:**
1. Add Node2D children to sentry named "Waypoint1", "Waypoint2", etc.
2. Drag them around in editor to position
3. Script automatically reads child positions in `_ready()`

**Example Hierarchy:**
```
Human (Sentry)
├─ NavigationAgent2D (optional)
├─ Waypoint1 (Node2D at 100,100)
├─ Waypoint2 (Node2D at 200,100)
├─ Waypoint3 (Node2D at 200,200)
└─ Waypoint4 (Node2D at 100,200)
```

**Auto-Loading Code:**
```gdscript
func _ready():
    # Auto-load waypoints from child nodes
    for child in get_children():
        if child.name.begins_with("Waypoint"):
            patrol_waypoints.append(child.global_position)
    
    # Sort by name to maintain order
    # Waypoint1, Waypoint2, Waypoint3...
```

**Benefits:**
- Visual placement (drag nodes around)
- No typing coordinates
- See path in editor instantly
- Simple to implement (no custom editor plugin needed)

**Instructions Document:**
- Create step-by-step guide for level designers
- Screenshots showing waypoint placement
- Common patterns (square patrol, figure-8, etc.)

---

## 🔄 **Phase C - Advanced Patrol Features**

### **Features to Add:**

**1. Per-Waypoint Pauses**
```gdscript
@export var waypoint_pause_durations: Array[float] = []

# At waypoint 2, pause for 3 seconds before continuing
waypoint_pause_durations = [0.0, 0.0, 3.0, 0.0]
```

**2. Per-Waypoint Swing Arc**
```gdscript
@export var waypoint_has_swing: Array[bool] = []

# Swing at waypoints 1 and 3, not at 0 and 2
waypoint_has_swing = [false, true, false, true]
```

**3. Per-Waypoint Facing Override**
```gdscript
@export var waypoint_face_direction: Array[float] = []

# At waypoint 2, face 90° (east) regardless of movement
waypoint_face_direction = [-1, -1, 90.0, -1]  # -1 = no override
```

**Use Case:** Guard patrols hallway, stops at intersection, looks down perpendicular corridor for 2 seconds, continues.

---

### **State Machine for Patrol:**

```
SENTRY_PATROL (base state)
  └─ MOVING_TO_WAYPOINT
       └─ Reached waypoint
            └─ AT_WAYPOINT (paused)
                 ├─ Has swing? → SWINGING
                 ├─ Has pause? → PAUSING (timer countdown)
                 └─ Neither? → MOVING_TO_WAYPOINT (next)
```

---

## 📋 **Implementation Order (Recommended)**

**Session 1 (Next):**
- Phase B1: Basic LOOP patrol with manual waypoints
- Get movement working
- Basic debug visualization

**Session 2:**
- Phase B2: Child-node waypoint system
- Instructions document for designers
- Test with complex paths

**Session 3:**
- Phase C: Per-waypoint pauses
- Per-waypoint swing arcs
- Face direction override

**Session 4:**
- Polish and testing
- Edge case handling
- Performance optimization

---

## 🎮 **Example Use Cases**

### **1. Hallway Guard (Simple LOOP)**
```
Waypoints: Start → End → Start (loop)
Pause: None
Swing: None
Speed: Slow (30)
```

### **2. Watchtower Guard (PING_PONG with swing)**
```
Waypoints: Corner1 → Corner2 → Corner3 → Corner4
Mode: PING_PONG
Pause: 2s at each corner
Swing: Yes (60° range at each corner)
```

### **3. Intersection Guard (Complex)**
```
Waypoints: A → B (intersection) → C
Pause: [0s, 3s, 0s]
Face: [auto, 90°, auto]  # At B, face east down corridor
Swing: [no, yes, no]     # Only swing at intersection
```

---

## 🤔 **Design Questions to Consider**

**Q: What happens when zombie detected during patrol?**

**Options:**
1. **Interrupt immediately** - stop patrol, flee/alert
2. **Finish waypoint** - complete path to next waypoint, then react
3. **Flexible** - depends on sentry type (guard vs coward)

**Recommendation:** Interrupt immediately (more realistic, better gameplay)

---

**Q: Resume patrol after threat gone?**

**Options:**
1. **Yes** - return to patrol path
2. **No** - stay idle/sentry at current position
3. **Return to start** - go back to waypoint 0

**Recommendation:** Return to nearest waypoint on path (practical)

---

**Q: Patrol while swinging?**

**Answer:** No - only swing AT waypoints (paused), not while moving
- Matches our earlier decision
- More realistic (hard to walk while turning head constantly)
- Simpler to implement

---

## 📊 **Complexity Estimates**

| Phase | Features | Complexity | Time Est. |
|-------|----------|-----------|-----------|
| **B1** | Basic patrol, LOOP, manual waypoints | Medium | 1-2 hrs |
| **B2** | Child-node waypoints, instructions | Low | 1 hr |
| **C** | Pauses, swing, face override | Medium-High | 2-3 hrs |
| **Polish** | Edge cases, testing | Medium | 1-2 hrs |

**Total:** ~5-8 hours of development

---

## 🎯 **Success Criteria**

**Phase B1 Complete When:**
- ✅ Sentry moves through waypoints in order
- ✅ LOOP mode wraps around correctly
- ✅ PING_PONG mode reverses at ends
- ✅ Path visible in editor
- ✅ Faces movement direction

**Phase B2 Complete When:**
- ✅ Waypoints placed by dragging Node2D children
- ✅ Instructions document created
- ✅ Level designers can use without coding

**Phase C Complete When:**
- ✅ Can pause at specific waypoints
- ✅ Can swing at specific waypoints
- ✅ Can override facing at waypoints
- ✅ Complex patrol patterns work (intersection guard)

---

## 🚀 **Ready for Next Session**

**We'll start with Phase B1:**
1. Add waypoint array export
2. Implement LOOP patrol logic
3. Add basic movement
4. Draw waypoint paths in editor

**Should take ~1-2 hours to get basic patrol working!**

Let me know when you're ready to start! 🎮

---

**Current Version:** v0.17.0 (Panic + Navigation)  
**Next Version:** v0.18.0 (Basic Patrol - Phase B1)  
**Future Version:** v0.19.0 (Visual Waypoints - Phase B2)  
**Final Version:** v0.20.0 (Advanced Patrol - Phase C)
