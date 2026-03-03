# Dead Corps - Changelog v0.17.0

**Release Date:** February 27, 2026  
**Focus:** Panic Tuning & Zombie Navigation

---

## 🎯 Panic Spreading Adjustments

### Fix 1: Reduced Panic Radius (40px)

**Changed:** Panic radius reduced from 120px → 40px

**Why:** 120px was too sensitive - entire groups would panic when one human was just being chased (not actually in danger).

**New Behavior:**
- Only **immediate neighbors** (40px away) panic
- Creates tighter, more realistic panic waves
- Prevents cascade from single chase

**Effect:**
- Sentries in loose formation won't all flee at once
- Panic spreads more gradually
- Player has more time to capitalize on flanking

---

### Fix 2: Panic Only on Grapple

**Changed:** Panic triggers only when ally is `GRAPPLED`, not just `attacker_count > 0`

**Why:** Humans were panicking when allies were merely being chased, not actually in combat.

**Old Trigger:**
```gdscript
if ally.current_state == GRAPPLED or ally.attacker_count > 0:
    panic()  // Too sensitive!
```

**New Trigger:**
```gdscript
if ally.current_state == GRAPPLED:
    panic()  // Only when actually pinned/in melee
```

**Result:**
- Panic only when ally is in **serious danger** (being attacked in melee)
- Being chased ≠ panic (humans can still escape)
- Being grappled = panic (ally is doomed, run!)

---

## 🧭 Zombie Navigation System (Optional Feature)

### New: NavigationAgent2D Support

**Added optional pathfinding** for zombies to navigate around obstacles.

**How It Works:**

Zombies now check for NavigationAgent2D component:
- **If present:** Use navigation mesh for pathfinding
- **If not present:** Use direct movement (original behavior)

**Code:**
```gdscript
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null

func handle_combat():
    if nav_agent and nav_agent.is_inside_tree():
        # Use navigation pathfinding
        nav_agent.target_position = attack_target.position
        var next_position = nav_agent.get_next_path_position()
        # Move toward next waypoint
    else:
        # Use direct movement (current behavior)
        velocity = (target.position - position).normalized() * speed
```

**Backwards Compatible:**
- Existing zombies without NavigationAgent2D work exactly as before
- Level designers can opt-in to navigation on per-level basis

---

## 📋 Navigation Setup (For Level Designers)

### Quick Setup:

1. **Add NavigationRegion2D** to level scene
2. **Bake navigation mesh** from buildings
3. **Add NavigationAgent2D** as child of zombie instances
4. **Done!** Zombies now pathfind

**See:** `docs/NAVIGATION_SETUP_GUIDE.md` for complete instructions

---

### Benefits:

**Without Navigation:**
```
Zombie → Wall → [STUCK, pushing uselessly]
```

**With Navigation:**
```
Zombie → Around corner → Around wall → Target reached!
```

**Impact:**
- ✅ Zombies navigate building corners
- ✅ No more stuck-on-walls
- ✅ More challenging gameplay (zombies actually reach humans)
- ✅ Optional - only use in levels where it matters

---

## 🎮 Gameplay Impact

### Panic Spreading (After Tuning):

**Before v0.17.0:**
- Panic radius: 120px
- Trigger: Being chased OR grappled
- **Result:** Entire groups flee from single pursuit

**After v0.17.0:**
- Panic radius: 40px
- Trigger: Only when grappled
- **Result:** Only immediate neighbors panic when ally is in serious danger

**Example:**
```
[S] [S] [S] [S] [S]  (Sentries 40px apart)
         ↑
      GRAPPLED

Before: ALL 5 panic
After: Middle + 2 adjacent panic (3 total)
```

---

### Zombie Navigation (After Setup):

**Before:**
- Zombies stuck on building corners
- Push against walls ineffectively
- Easy to kite around obstacles

**After (with Navigation):**
- Zombies path around buildings
- Navigate corners smoothly
- Must genuinely escape, not just loop around walls

**Tuning Options:**
- Small levels: 8-10px cell size (precise)
- Large levels: 15-20px cell size (fast)
- Complex layouts: Smaller agent radius (tighter fits)

---

## 📦 Files Modified

### scripts/human.gd:
- Reduced panic_radius from 120.0 to 40.0
- Removed `attacker_count > 0` check
- Only panic when `ally.current_state == GRAPPLED`
- Updated panic message: "ally grappled" not "ally under attack"

### scripts/zombie.gd:
- Added `@onready var nav_agent` for optional NavigationAgent2D
- Added `handle_combat()` override with navigation support
- Falls back to direct movement if no navigation available

### Documentation:
- Created `docs/NAVIGATION_SETUP_GUIDE.md` - Complete navigation setup instructions
- Created `docs/CHANGELOG_v0.17.0.md` - This file

---

## 🧪 Testing Scenarios

### Test 1: Panic Spreading (Tight Formation)

**Setup:**
- Place 3 sentries in line, 40px apart, facing north
- Send zombie from south to grapple middle sentry

**Expected:**
- Middle sentry grappled ✓
- Left sentry (40px away) panics ✓
- Right sentry (40px away) panics ✓
- Total: 2 flee, 1 dies

---

### Test 2: Panic Spreading (Loose Formation)

**Setup:**
- Place 3 sentries in line, 60px apart, facing north
- Send zombie from south to grapple middle sentry

**Expected:**
- Middle sentry grappled ✓
- Left sentry (60px away) does NOT panic ✗
- Right sentry (60px away) does NOT panic ✗
- Total: 0 flee, 1 dies (others only react when zombie enters their vision)

---

### Test 3: Zombie Navigation

**Setup:**
- Add NavigationRegion2D to level with baked mesh
- Add NavigationAgent2D to zombie
- Place human behind building corner
- Command zombie to attack

**Expected:**
- Zombie paths around corner ✓
- No stuck-on-wall behavior ✓
- Smooth navigation ✓

---

### Test 4: Zombie Without Navigation

**Setup:**
- DON'T add NavigationAgent2D
- Place human behind building
- Command zombie to attack

**Expected:**
- Zombie uses direct movement (original behavior) ✓
- May get stuck on corner (expected without navigation) ✓
- Still functions, just not optimal ✓

---

## 🎓 Design Notes

### Why 40px Panic Radius?

**Tested values:**
- 20px: Too small, sentries die without panic spreading
- 40px: **Perfect** - immediate neighbors panic, formation matters
- 60px: Starts becoming too sensitive
- 120px (old): Way too sensitive, whole groups flee

**40px = ~3 unit radii** - feels like "standing right next to" in gameplay.

---

### Why Grapple-Only Panic?

**Being chased (attacker_count > 0):**
- Human might escape
- Zombie hasn't caught them yet
- Not worth panicking over

**Being grappled (State.GRAPPLED):**
- Human is pinned
- Actively taking damage
- Will die soon
- **Time to run!**

This creates better gameplay tension - you don't flee at first sight, but when real danger hits.

---

### Why Optional Navigation?

**Not all levels need it:**
- Open arenas: Direct movement fine
- Corridor levels: Minimal obstacles
- Simple layouts: Navigation overhead not worth it

**Use navigation for:**
- Complex building layouts
- Levels with many corners
- Mazes or tight spaces
- When zombie pathfinding matters to gameplay

**Optional = Best of both worlds**

---

## 🚀 Future Enhancements

**Panic System:**
- Configurable panic radius per human type
- Panic intensity (mild concern vs full flee)
- False alarms (panicking at nothing sometimes)

**Navigation:**
- Dynamic navigation mesh updates
- Zombie formation movement with navigation
- Avoidance between zombies
- Jump points for special zombie types

---

**Version:** v0.17.0  
**Status:** Panic tuned, navigation system ready for opt-in use  
**Breaking Changes:** None - all changes backwards compatible
