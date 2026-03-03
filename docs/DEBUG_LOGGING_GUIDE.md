# Debug Logging Guide - v0.12.6

## What's Been Added

This version includes comprehensive logging to diagnose two issues:
1. **Zombies losing targets** in cramped corridors
2. **Humans not seeking nearest escape zone**

---

## 🔍 Zombie Target Loss Logging

### What You'll See:

```
🔍 ZOMBIE LOST TARGET:
  Zombie: Zombie2 at (150.5, 200.3)
  Lost: Human at (180.2, 195.7)
  Distance: 35.4px
  State: PURSUING
  Combat: melee=false committed=false grappled=false
  Reason: Vision lost (line of sight blocked or out of arc)
```

### What This Means:

**Why zombies lose targets:**

1. **Vision blocked by walls** - Common in corridors
   - Zombie can see around corner initially
   - Human turns corner, breaks line of sight
   - Zombie loses target and goes IDLE

2. **Out of vision arc** - Vision cone limitations
   - Pursuing state: 90° forward arc, 200px range
   - If human escapes to sides, zombie can't see
   - Target lost

3. **False stuck detection** - Zombie thinks it's stuck
   - See "🚧 ZOMBIE STUCK" logs below

### Solutions:

**Option A: Increase vision arc when pursuing**
- Currently 90°, could increase to 120° or 180°
- Helps in tight turns

**Option B: Add "last known position" tracking**
- Zombie goes to last seen position when vision lost
- More realistic pursuit behavior

**Option C: Increase vision range**
- Currently 200px when pursuing
- Could increase to 250-300px for longer corridors

---

## 🚧 Zombie Stuck Detection Logging

### What You'll See:

```
🚧 ZOMBIE STUCK - FINDING NEW TARGET:
  Zombie: Zombie at (100, 100)
  Current target: Human
  Distance moved: 0.8px
  Stuck duration: 2.0s
```

### What This Means:

Zombie hasn't moved more than 2px in 2 seconds, assumed stuck.

**Common Causes:**

1. **Tight corridors** - Zombie can't navigate narrow spaces
2. **Corners** - Basic pathfinding struggles with sharp turns  
3. **Collision clusters** - Multiple zombies blocking each other
4. **Target behind wall** - Zombie sees target but can't reach it

### Solutions:

**Option A: Increase stuck threshold**
- Change from 2px to 5-10px
- Allows slight movement to count as "not stuck"

**Option B: Increase stuck timeout**
- Change from 2.0s to 3-4s
- Gives more time to navigate obstacles

**Option C: Better pathfinding**
- Implement A* or navigation mesh
- Zombies path around obstacles smartly

---

## 🎯 Escape Zone Seeking Logging

### What You'll See:

```
🎯 ESCAPE ZONE CHECK:
  Human: Human at (150, 100)
  Nearest zone at: (200, 150)
  Distance: 70.7px
  Has line of sight: false
  ✗ BLOCKED - Cannot see zone, not seeking
  (Will use other flee priorities instead)
```

### What This Means:

**The Issue:**
- Human finds nearest escape zone ✓
- But won't seek it if blocked by walls ✗
- Must have direct line of sight to actively pursue

**Two Escape Zone Behaviors:**

1. **Weak bias (10-20% influence):**
   - Works through walls
   - Applied when fleeing from zombies
   - Subtle pull toward nearest zone

2. **Active seeking (100% influence):**
   - Only when within 200px AND visible
   - Requires line of sight
   - Strong pull toward zone

**In tight corridors:**
- Nearest zone often blocked
- Weak bias provides gentle guidance
- But might not be enough to reach zone before caught

### Solutions:

**Option A: Remove line-of-sight requirement**
```gdscript
// OLD:
if has_line_of_sight_to_point(escape_zone.position):
    return to_zone

// NEW:
return to_zone  // Always seek nearest, regardless of LOS
```
**Pros:** Humans always path toward nearest zone  
**Cons:** Might look weird (seeking through walls)

**Option B: Find nearest zone WITH line of sight**
```gdscript
func get_nearest_visible_escape_zone() -> Node2D:
    var zones = get_tree().get_nodes_in_group("escape_zone")
    var nearest_visible = null
    var nearest_distance = INF
    
    for zone in zones:
        if has_line_of_sight_to_point(zone.position):
            var dist = position.distance_to(zone.position)
            if dist < nearest_distance:
                nearest_distance = dist
                nearest_visible = zone
    
    return nearest_visible
```
**Pros:** Only seeks zones they can see  
**Cons:** Might not find ANY visible zone in tight corridors

**Option C: Increase weak bias strength**
- Change from 10-20% to 30-50%
- Makes the "through walls" guidance stronger
- Easier to implement

**Option D: Increase seek range**
- Change from 200px to 300-400px
- More likely to have LOS at longer distances
- Simple parameter change

---

## 🧪 Testing Recommendations

### For Zombie Target Loss:

1. **Place zombie and human in corridor**
2. **Make human flee around corner**
3. **Watch console for "🔍 ZOMBIE LOST TARGET" logs**
4. **Check distance when lost** - if <50px, probably vision arc issue
5. **Check if walls involved** - if yes, LOS blocking

### For Escape Zone Seeking:

1. **Place human between two zones**
2. **Put wall blocking nearest zone**
3. **Watch for "🎯 ESCAPE ZONE CHECK" logs**
4. **See if "Has line of sight: false" appears**
5. **Observe human behavior** - random fleeing or gentle drift toward zone?

---

## 📊 Quick Fixes to Try

### If zombies lose targets too easily:

**In zombie.gd, line ~170:**
```gdscript
// Increase pursuing vision range
const PURSUING_VISION_RANGE: float = 300.0  // Was 200.0
```

**In zombie.gd, line ~172:**
```gdscript
// Increase pursuing vision arc
const PURSUING_VISION_ARC: float = 120.0  // Was 90.0
```

### If zombies get stuck too often:

**In zombie.gd, line ~156:**
```gdscript
// Increase stuck timeout
@export var stuck_timeout: float = 4.0  // Was 2.0
```

**Or increase stuck threshold:**
```gdscript
@export var stuck_threshold: float = 5.0  // Was 2.0
```

### If humans don't seek escape zones:

**In human.gd, line 724 - Remove LOS check:**
```gdscript
// OLD:
if has_line_of_sight_to_point(escape_zone.position):
    return to_zone

// NEW:
return to_zone  // Always seek, pathfind around obstacles
```

**Or increase seek range (line 722):**
```gdscript
if distance_to_zone < 400.0:  // Was 200.0
```

**Or increase weak bias (line 683):**
```gdscript
var zone_influence := 0.3 + (0.3 * (1.0 - (distance_to_zone / 300.0)))
// Was: 0.1 + (0.1 * ...)
// Now: 30-60% influence instead of 10-20%
```

---

## 🎮 Expected Logging Volume

**Light gameplay:** 5-10 messages per second  
**Intense gameplay:** 20-50 messages per second

If logging gets too spammy, you can:
1. Comment out specific logs you don't need
2. Add a cooldown timer
3. Only log every Nth occurrence

---

## 🚀 Next Steps

1. **Run your cramped corridor level**
2. **Watch the console** as zombies chase humans
3. **Note which logs appear most often**
4. **Try the quick fixes** above
5. **Report back:** Which issue is most common?

Then we can implement the best permanent solution!

---

**Version:** v0.12.6  
**Focus:** Diagnostic logging for corridor gameplay issues
