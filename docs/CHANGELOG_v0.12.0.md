# v0.12.0 - Gameplay Tweaks & Vision Improvements

**Date:** February 14, 2026  
**Status:** Balance adjustments + visual polish  
**Previous version:** v0.11.0 (final features)

---

## 🎯 GAMEPLAY BALANCE CHANGES

### **1. Vision Range Adjustments**

**Human Vision:**
- Idle vision: 120px → **100px** (reduced)
- Humans detect zombies at closer range
- Creates more surprise encounters

**Zombie Vision:**
- Idle vision: 100px (unchanged)
- Active vision: 130px → **260px** (doubled!)
- Auto pursuit range: 100px → **260px**
- Zombies can now spot and chase humans from much farther away

**Result:** Zombies are more threatening, humans must be more careful

---

### **2. Speed Rebalance**

**New speeds:**
- Humans: 90 px/s → **85 px/s**
- Zombies: 85 px/s → **90 px/s**

**Critical Change:** **Zombies are now FASTER than humans!**
- Humans can no longer outrun zombies indefinitely
- Creates urgency and tension
- Escape zones and smart positioning become essential
- "Touch-and-go" moments are more dramatic

---

## ✨ NEW FEATURE: GROUP VISION

**How it works:**
- Humans within 50px form a detection group
- Group shares 100px vision radius (same as individual)
- When zombie enters group vision, the human CLOSEST to it detects first
- That human starts fleeing, triggering cascade to others

**Benefits:**
- ✅ Groups detect zombies earlier (collective awareness)
- ✅ Still maintains cascading panic effect (wave of fear)
- ✅ Realistic "edge person spots it first" behavior
- ✅ Creates dramatic group reactions

**Example:**
```
5 humans clustered together (within 50px)
Zombie approaches from north
Human on north edge is closest → detects first → flees
Others cascade-panic 0.05s apart → realistic wave effect
```

---

## 🎨 VISION DISPLAY IMPROVEMENTS

### **Building Occlusion**

Vision arcs and circles now properly clip at buildings!

**Implementation:**
- Raycasts every 10° (36 samples for full circle, fewer for arcs)
- Clips vision range at building collision points
- Vision "wraps around" buildings naturally
- No more vision passing through walls

**Visual result:**
```
Before: Vision circle passes straight through buildings
After: Vision stops at building edges, creates realistic "cut-out" effect
```

**Performance:**
- 36-64 raycasts per vision area (trivial for Godot)
- Only calculated when vision is being drawn
- Smooth performance even with many units

**Z-Index layering:**
- Vision renderer: z-index -1 (back)
- Buildings: z-index 0 (default, front)
- Vision now renders BEHIND buildings for proper occlusion

---

## 🎮 CAMERA CONTROLS

### **Edge Panning Disabled**

**Changed:**
- Mouse edge scrolling: **DISABLED** (commented out, not deleted)
- Reason: Too sensitive during testing

**Kept:**
- WASD panning: ✅ Still works
- **Arrow keys:** ✅ **Now supported!**

**New control scheme:**
- Pan with WASD **OR** arrow keys (↑↓←→)
- No accidental scrolling from mouse near edges
- Re-enable edge panning later if desired (code is commented)

---

## 📊 TECHNICAL CHANGES

### **Modified Files:**

**scripts/human.gd:**
- Reduced idle_vision_radius: 120 → 100
- Implemented group vision detection system
- Closest-human-reacts-first logic

**scripts/zombie.gd:**
- Increased active_vision_range: 130 → 260
- Increased auto_pursuit_range: 100 → 260

**scenes/human.tscn:**
- Reduced move_speed: 90.0 → 85.0

**scenes/zombie.tscn:**
- Increased move_speed: 85.0 → 90.0

**scripts/camera_controller.gd:**
- Disabled edge panning (commented out)
- Added arrow key support

**scripts/vision_renderer.gd:**
- Added building raycasting to draw_vision_arc()
- Added building raycasting to draw_vision_arc_merged()
- Added building raycasting to draw_merged_circle()
- Changed z_index: 1 → -1 (render behind buildings)

---

## 🎯 EXPECTED GAMEPLAY CHANGES

### **Chase Dynamics**

**Before:**
- Humans faster than zombies (90 vs 85)
- Humans could outrun forever
- Low tension

**After:**
- Zombies faster than humans (90 vs 85) ✅
- Humans CANNOT outrun indefinitely
- **Must use obstacles, buildings, and escape zones**
- High tension, dramatic chases

---

### **Detection Range**

**Before:**
- Humans detect at 120px
- Zombies detect at 130px
- Similar ranges

**After:**
- Humans detect at 100px
- Zombies detect at 260px
- **Zombies spot humans FIRST from far away** ✅
- Humans must be more careful about positioning

---

### **Group Behavior**

**Before:**
- Each human detects independently
- Sometimes edge humans miss zombies
- Inconsistent group reactions

**After:**
- Groups share collective awareness ✅
- Zombie detected earlier by group
- Realistic "front person sees it first" cascade ✅
- Consistent, natural-looking group panic

---

### **Visual Clarity**

**Before:**
- Vision passes through buildings
- Confusing what units can actually see
- Unrealistic

**After:**
- Vision clips at buildings ✅
- Clear visual of actual line-of-sight ✅
- Easier to understand detection ranges

---

## 🧪 TESTING PRIORITIES

1. **Speed balance:**
   - Can zombies actually catch humans?
   - Is it too easy/hard to escape?
   - Test with different building layouts

2. **Group vision:**
   - Do groups detect zombies naturally?
   - Does cascade effect still work?
   - Test with 3-5 human clusters

3. **Vision rendering:**
   - Do arcs/circles clip at buildings correctly?
   - Any performance issues with many units?
   - Check z-index layering is correct

4. **Camera controls:**
   - WASD still smooth?
   - Arrow keys work properly?
   - Miss edge panning or prefer without it?

---

## 📝 BALANCE CONSIDERATIONS

**If zombies catch humans too easily:**
- Reduce zombie speed back to 87-88 px/s
- Or increase human speed to 87-88 px/s
- Small changes make big difference!

**If groups react too slowly:**
- Increase group vision radius from 100px
- Or make group detection check more frequent

**If vision clipping causes performance issues:**
- Reduce raycast sampling (36 → 24 segments)
- Only render vision for selected/nearby units
- Add update throttling (every 0.1s instead of every frame)

---

## 🔮 FUTURE CONSIDERATIONS

**Post-testing tuning:**
- Fine-tune speed differential (currently 5 px/s)
- Adjust zombie vision ranges if too aggressive
- Consider variable speeds per zombie type
- Add stamina/fatigue system?

**Vision improvements:**
- Consider caching raycast results (0.1-0.2s)
- LOD for distant vision rendering
- Different vision colors for different states

**Camera:**
- Re-enable edge panning based on user feedback
- Add configurable edge panning sensitivity
- Zoom controls (mouse wheel already works)

---

## 📂 VERSION HISTORY

- v0.9.0 - Baseline
- v0.9.1 - Vision range fixes
- v0.9.2 - Minimal flee testing
- v0.9.3 - Debug logging
- v0.9.4 - Vision arc fix (360°)
- v0.9.5 - Extended vision (300px)
- v0.10.0 - Smart flee system
- v0.11.0 - Obstacle avoidance + escape bias
- **v0.12.0 - Balance tweaks + vision polish** ← YOU ARE HERE

---

**This version represents a major gameplay feel change with zombies being faster!** Test thoroughly to ensure it's balanced and fun. 🎮

**END OF CHANGELOG**
