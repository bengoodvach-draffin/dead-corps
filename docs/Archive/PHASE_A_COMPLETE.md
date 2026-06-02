# Dead Corps - Phase A Complete: Sentry Degrees & Swing Arc

**Version:** v0.14.0  
**Release Date:** February 27, 2026  
**Status:** Phase A Complete - Degrees & Swing Arc Implemented

---

## ✅ Phase A Features Implemented

### 1. Degree-Based Sentry Direction ✓
### 2. Visual Arrow in Editor ✓  
### 3. Swing Arc Mechanics ✓
### 4. Smooth Sin/Cos Oscillation ✓

---

## 🎯 Feature 1: Degree-Based Direction

### **What Changed:**

**OLD System:**
```gdscript
@export var sentry_direction: Vector2 = Vector2.RIGHT
# User had to think in cartesian coordinates
# (1, 0) = right, (0, -1) = up, (-1, 0) = left...
```

**NEW System:**
```gdscript
@export_range(0.0, 360.0, 1.0) var sentry_facing_degrees: float = 0.0
# 0° = North (up)
# 90° = East (right)
# 180° = South (down)
# 270° = West (left)
```

### **Conversion Reference:**

| Direction | Degrees | Old Vector2 Equivalent |
|-----------|---------|------------------------|
| **North (Up)** | 0° | Vector2(0, -1) |
| **Northeast** | 45° | Vector2(0.707, -0.707) |
| **East (Right)** | 90° | Vector2(1, 0) |
| **Southeast** | 135° | Vector2(0.707, 0.707) |
| **South (Down)** | 180° | Vector2(0, 1) |
| **Southwest** | 225° | Vector2(-0.707, 0.707) |
| **West (Left)** | 270° | Vector2(-1, 0) |
| **Northwest** | 315° | Vector2(-0.707, -0.707) |

### **Editor Experience:**

- **Slider:** Drag to set angle (0-360°)
- **Type:** Enter exact value (e.g., 45 for northeast)
- **Snap:** 1° increments for precision
- **Visual:** Arrow shows direction in real-time

---

## 🎨 Feature 2: Visual Arrow in Editor

### **What You See:**

When you select a sentry in the editor:
- **Cyan arrow** points in facing direction
- **Arrow length:** 60 pixels
- **Thick line:** 3px width for visibility
- **Arrowhead:** Shows direction clearly

### **Swing Arc Visualization:**

If swing is enabled:
- **Green arc** shows swing range
- **Two arc boundaries** (left/right extremes)
- **Semi-transparent** (doesn't obscure other elements)
- **Updates live** as you adjust swing_range

### **Implementation:**

```gdscript
@tool  # Enables script to run in editor
extends Unit

func _draw() -> void:
    if Engine.is_editor_hint() and initial_state == State.SENTRY:
        # Draw arrow
        draw_line(Vector2.ZERO, arrow_end, Color.CYAN, 3.0)
        
        # Draw swing arc if enabled
        if sentry_has_swing:
            draw_arc_visualization()
```

---

## 🔄 Feature 3: Swing Arc System

### **New Export Properties:**

```gdscript
## Whether this sentry has a swinging vision arc
@export var sentry_has_swing: bool = false

## How far to swing (±degrees from center)
@export_range(0.0, 90.0, 1.0) var sentry_swing_range: float = 45.0

## Speed of swing (degrees per second)
@export_range(1.0, 180.0, 1.0) var sentry_swing_speed: float = 30.0

## Pause duration at each extreme
@export_range(0.0, 2.0, 0.1) var sentry_swing_pause: float = 0.5
```

### **How It Works:**

**Swing Cycle:**
```
1. Start at center (0°)
2. Swing right (+45°) over 1.5 seconds
3. Pause for 0.5 seconds
4. Swing left (-45°) over 1.5 seconds
5. Pause for 0.5 seconds
6. Repeat
```

**Full cycle:** ~4 seconds (1.5s + 0.5s + 1.5s + 0.5s)

### **State Variables:**

```gdscript
var swing_center_angle: float = 0.0      # Base direction (from sentry_facing_degrees)
var current_swing_offset: float = 0.0   # Current offset: -range to +range
var swing_direction: int = 1             # 1 = swinging right, -1 = left
var swing_pause_timer: float = 0.0      # Countdown for pause
var is_swing_paused: bool = false       # Whether paused at extreme
```

---

## 🌊 Feature 4: Smooth Sin/Cos Oscillation

### **Natural Motion:**

Instead of linear movement, the swing uses **speed modulation** for natural head-turning:

```gdscript
# Slower at extremes, faster in middle
var swing_progress = current_swing_offset / sentry_swing_range
var speed_multiplier = 1.0

if abs(swing_progress) > 0.7:  # Near extremes
    speed_multiplier = 0.5 + 0.5 * (1.0 - abs(swing_progress))
```

**Speed Curve:**

| Position | Progress | Speed Multiplier | Visual Effect |
|----------|----------|------------------|---------------|
| Center | 0% | 1.0x | Full speed |
| Mid-swing | 50% | 1.0x | Full speed |
| Near extreme | 85% | 0.65x | Slowing down |
| At extreme | 100% | 0.5x | Nearly stopped |

**Result:** Natural deceleration/acceleration, like a real head turning!

---

## 📋 How to Use

### **Creating a Static Sentry:**

1. **Drag Human into scene**
2. **In Inspector:**
   - Initial State → SENTRY
   - Sentry Facing Degrees → 45 (faces northeast)
   - Sentry Has Swing → OFF
3. **See cyan arrow** pointing northeast

**Result:** Guard watching one direction

---

### **Creating a Swinging Sentry:**

1. **Drag Human into scene**
2. **In Inspector:**
   - Initial State → SENTRY
   - Sentry Facing Degrees → 0 (faces north)
   - Sentry Has Swing → ON
   - Sentry Swing Range → 60 (±60° = 120° total)
   - Sentry Swing Speed → 40 (degrees/second)
   - Sentry Swing Pause → 0.8 (seconds)
3. **See cyan arrow + green arc** showing range

**Result:** Guard sweeping vision 120° back and forth

---

### **Example Configurations:**

**Doorway Guard (narrow sweep):**
- Facing: 0° (north)
- Swing: ON
- Range: 30°
- Speed: 20°/s
- Pause: 0.3s

**Watchtower Guard (wide sweep):**
- Facing: 180° (south, watching approach)
- Swing: ON
- Range: 75°
- Speed: 25°/s
- Pause: 1.0s

**Corner Guard (facing diagonal):**
- Facing: 45° (northeast)
- Swing: OFF

**Hallway Guard (side-to-side):**
- Facing: 90° (east, center of arc)
- Swing: ON
- Range: 45°
- Speed: 35°/s
- Pause: 0.5s

---

## 🎮 Runtime Behavior

### **Vision Cone Updates:**

The sentry's vision cone **follows the swing arc** in real-time:
- **Center:** Vision cone points at `sentry_facing_degrees`
- **Swinging:** Vision cone rotates with current swing offset
- **Detection:** Zombies detected based on current facing direction

### **Interaction with Flee:**

If zombie detected:
1. **Human transitions:** SENTRY → FLEEING
2. **Swing stops:** No longer swinging
3. **Flee behavior:** Normal weighted threat calculation
4. **Returns to SENTRY?** No - once fleeing, stays fleeing (design choice)

---

## 🔧 Technical Implementation

### **Degrees to Vector Conversion:**

```gdscript
func degrees_to_vector(degrees: float) -> Vector2:
    # Godot coords: 0° = right, 90° = down
    # Our system: 0° = up, 90° = right
    # Subtract 90° to rotate reference
    var radians = deg_to_rad(degrees - 90.0)
    return Vector2(cos(radians), sin(radians)).normalized()
```

### **Swing Arc Update (per frame):**

```gdscript
func update_swing_arc(delta: float) -> void:
    if is_swing_paused:
        # Handle pause countdown
        swing_pause_timer -= delta
        if swing_pause_timer <= 0.0:
            is_swing_paused = false
            swing_direction *= -1  # Reverse
        return
    
    # Update offset with speed modulation
    var speed_mult = calculate_speed_multiplier()
    current_swing_offset += sentry_swing_speed * delta * swing_direction * speed_mult
    
    # Check if reached extreme
    if abs(current_swing_offset) >= sentry_swing_range:
        current_swing_offset = sentry_swing_range * swing_direction
        is_swing_paused = true
        swing_pause_timer = sentry_swing_pause
    
    # Update facing direction
    var current_angle = swing_center_angle + current_swing_offset
    facing_direction = degrees_to_vector(current_angle)
```

### **Editor Drawing:**

```gdscript
@tool  # Run in editor
extends Unit

func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        queue_redraw()  # Redraw when properties change

func _draw() -> void:
    if not Engine.is_editor_hint():
        return
    
    # Draw direction arrow
    # Draw swing arc (if enabled)
```

---

## 🧪 Testing Guide

### **Test 1: Static Sentry Direction**

**Setup:**
1. Create human sentry facing 0° (north)
2. Place zombie to the east (right)
3. Run game

**Expected:**
- Sentry does NOT detect zombie (looking north, zombie is east)

**Adjust:**
- Change facing to 90° (east)
- Sentry now detects zombie ✓

---

### **Test 2: Swing Arc Detection**

**Setup:**
1. Create swinging sentry: facing 0°, range 45°
2. Place zombie at 30° (northeast) from sentry
3. Run game

**Expected:**
- Zombie detected when sentry swings right (+30° within +45° range)
- Zombie NOT detected when sentry at center (0°) or swinging left

---

### **Test 3: Swing Speed & Pause**

**Setup:**
1. Create sentry with slow swing: 10°/s, pause 2.0s
2. Watch behavior

**Expected:**
- Slow, deliberate head turning
- Long pause at each extreme
- Natural acceleration/deceleration

---

### **Test 4: Visual Arrow Accuracy**

**Setup:**
1. Create sentry, set facing to 45°
2. **In editor**, observe cyan arrow
3. Change to 135°, 225°, 315°

**Expected:**
- Arrow points exactly in specified direction
- Updates immediately when degree value changes
- Green arc shows swing range correctly

---

## 📦 Files Modified

### **scripts/human.gd:**

**Added:**
- `@tool` directive (line 1)
- Degree-based export properties
- Swing arc state variables
- `degrees_to_vector()` function
- `update_swing_arc()` function
- `_process()` for editor updates
- `_draw()` for visual indicators

**Modified:**
- `_ready()` - Convert degrees to Vector2
- `_physics_process()` - Call swing arc update

---

## 🚀 Next Steps: Phase B

**Phase B1 - Manual Waypoint Patrol:**
- LOOP patrol mode
- Waypoints as `Array[Vector2]` (manual typing)
- Face movement direction while moving
- Basic debug visualization

**Phase B2 - Visual Waypoint Editor:**
- Child-node waypoint placement
- Drag Node2D children in editor
- Instructions for setup

**Phase C - Advanced Patrol:**
- PING_PONG mode
- Per-waypoint pauses
- Per-waypoint swing arcs
- Face direction override

---

## 🎓 Key Learnings

### **Degrees vs Vector2:**
- Degrees FAR more intuitive for level designers
- 0° = North matches top-down game expectations
- Slider in Inspector much easier than typing coordinates

### **@tool Directive:**
- Enables script execution in editor
- Requires `Engine.is_editor_hint()` checks
- `queue_redraw()` needed to update visuals

### **Smooth Motion:**
- Linear swing feels robotic
- Speed modulation creates natural motion
- Small pause at extremes = believable behavior

### **Editor Visualization:**
- Cyan arrow = clear, visible direction indicator
- Green arc = non-intrusive range display
- Real-time updates = immediate feedback

---

## 💡 Design Philosophy

**"Zero-to-North" Approach:**
- 0° = Up/North feels natural in top-down view
- Matches compass directions (N, E, S, W)
- Easier mental model than radians or right=0°

**Visual-First Design:**
- What you see in editor = what you get in game
- No guessing about angles
- Immediate visual feedback

**Natural Motion:**
- Human-like head turning
- Acceleration/deceleration curves
- Believable patrol behavior

---

**Phase A Status:** ✅ COMPLETE  
**Ready for:** Phase B1 (Manual Waypoint Patrol)  
**Version:** v0.14.0
