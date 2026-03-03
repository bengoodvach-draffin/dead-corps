# Zombie Navigation Setup Guide

**Version:** v0.17.0  
**Purpose:** Enable zombies to pathfind around obstacles instead of getting stuck on walls

---

## 🎯 What This Does

**Without Navigation:**
- Zombies walk straight toward targets
- Get stuck on walls and building corners
- Push against obstacles ineffectively

**With Navigation:**
- Zombies pathfind around obstacles
- Navigate around building corners
- Find efficient routes to targets

---

## 📋 Setup Steps

### Step 1: Add NavigationRegion2D to Level

1. **Open your level scene** (e.g., `main.tscn` or `test_level_1.tscn`)
2. **Add NavigationRegion2D** node:
   - Right-click your level root node
   - Add Child Node → Search "NavigationRegion2D"
   - Name it "NavigationRegion"

### Step 2: Create Navigation Mesh

1. **Select NavigationRegion2D** in scene tree
2. **In Inspector**, find "Navigation Polygon" property
3. **Click** "[empty]" next to Navigation Polygon
4. **Select** "New NavigationPolygon"
5. **Click the new polygon** to open it

**Navigation Polygon Settings:**
- Cell Size: 10.0 (smaller = more precise, slower)
- Cell Height: 10.0
- Agent Radius: 15.0 (slightly larger than zombie radius to prevent wall-hugging)

### Step 3: Draw Walkable Area

**Two Methods:**

**Method A: Bake from Scene (Recommended)**

1. **With NavigationRegion2D selected:**
   - In top toolbar, click "NavigationRegion2D" menu
   - Select "Bake NavigationPolygon"
2. **Godot automatically:**
   - Scans your level for collision shapes
   - Creates walkable areas around obstacles
   - Updates when you modify buildings

**Result:** Entire level is walkable except where buildings/walls exist

---

**Method B: Manual Drawing**

1. **With NavigationRegion2D selected:**
   - Click polygon outline in 2D view
   - Click to add points creating walkable area
   - Avoid placing points inside buildings
2. **Close the polygon** by clicking first point again

**Use when:** Baking doesn't work or you want precise control

---

### Step 4: Add NavigationAgent2D to Zombies

**For existing zombies in scenes:**

1. **Open zombie.tscn** (or your zombie scene file)
2. **Add NavigationAgent2D** as child of root Zombie node:
   - Right-click Zombie root
   - Add Child Node → "NavigationAgent2D"
   - Leave at default settings

**NavigationAgent2D Settings (Inspector):**
- Path Desired Distance: 10.0 (how close to waypoints before moving to next)
- Target Desired Distance: 15.0 (how close to final target)
- Path Max Distance: 50.0 (maximum deviation before recalculating)
- Avoidance Enabled: false (we handle this in code)

**Important:** Save the zombie.tscn scene after adding NavigationAgent2D

---

**For manually placed zombies:**

1. **In your level**, select each zombie instance
2. **Right-click** zombie in scene tree
3. **Add Child Node** → "NavigationAgent2D"
4. **Repeat** for all zombies in level

---

### Step 5: Test Navigation

1. **Run the scene** (F5)
2. **Command zombie** to attack human on other side of building
3. **Observe:**
   - ✅ Zombie should path around building
   - ✅ Smooth corner navigation
   - ✅ No getting stuck on walls

---

## 🔧 Troubleshooting

### Issue: Zombies Still Walk Through Walls

**Cause:** Navigation mesh not set up or buildings not in collision layer

**Fix:**
1. Check NavigationRegion2D has a polygon assigned
2. Verify buildings have CollisionShape2D on layer 1
3. Try "Bake NavigationPolygon" again

---

### Issue: Zombies Take Weird Routes

**Cause:** Navigation mesh has gaps or islands

**Fix:**
1. **Select NavigationRegion2D**
2. **View the navigation mesh** (should show blue overlay)
3. **Check for:**
   - Gaps between walkable areas
   - Disconnected islands
   - Too-narrow passages
4. **Rebake** or manually fix polygon

---

### Issue: Performance Drops

**Cause:** Navigation mesh too detailed (Cell Size too small)

**Fix:**
1. **Select NavigationRegion2D** → Navigation Polygon
2. **Increase Cell Size** from 10 to 20 or 30
3. **Rebake** navigation mesh

---

### Issue: Zombies Don't Use Navigation

**Cause:** NavigationAgent2D not properly added

**Fix:**
1. **Select a zombie** in running game
2. **Check Remote tab** (top-right, next to Scene)
3. **Expand zombie node** - should see NavigationAgent2D child
4. **If missing:** Add it following Step 4 above

---

## 📐 Recommended Settings

### Small/Tight Levels:
```
NavigationPolygon:
  Cell Size: 8.0
  Agent Radius: 12.0

NavigationAgent2D:
  Path Desired Distance: 8.0
  Target Desired Distance: 12.0
```

### Large/Open Levels:
```
NavigationPolygon:
  Cell Size: 15.0
  Agent Radius: 15.0

NavigationAgent2D:
  Path Desired Distance: 15.0
  Target Desired Distance: 20.0
```

### Complex/Many Obstacles:
```
NavigationPolygon:
  Cell Size: 10.0
  Agent Radius: 18.0  # Wider berth around obstacles

NavigationAgent2D:
  Path Max Distance: 100.0  # More flexible pathing
```

---

## 🎮 Optional: Per-Level Navigation

You can have different navigation setups for different levels:

**Level 1 (Simple):**
- Large cell size (20.0)
- Simple navigation mesh
- Fast performance

**Level 5 (Complex):**
- Small cell size (8.0)
- Detailed navigation mesh
- Precise pathing

Just set up NavigationRegion2D differently in each level scene!

---

## 🔄 Updating Navigation

**When you add/move buildings:**

1. **Select NavigationRegion2D**
2. **Menu:** NavigationRegion2D → Bake NavigationPolygon
3. **Navigation updates** automatically

**For manual polygons:**
- Edit polygon points in 2D view
- Adjust to avoid new obstacles

---

## 📊 Before & After

### Before Navigation:

```
Zombie → Building → [STUCK]
         (pushes uselessly)
```

### After Navigation:

```
Zombie → Around → Around → Target
         Corner1   Corner2   Reached!
```

---

## 💡 Advanced: Debugging Navigation

**View Navigation Mesh:**
1. **Debug menu** (while running): Debug → Visible Collision Shapes
2. **Blue overlay** shows where zombies can walk
3. **Check for gaps** or unexpected blockages

**Enable Navigation Debug:**
```gdscript
# In zombie.gd _ready():
if nav_agent:
    nav_agent.debug_enabled = true
    nav_agent.debug_use_custom = true
    nav_agent.debug_path_custom_color = Color.GREEN
```

**Result:** Green lines show zombie's planned path in real-time

---

## 🚀 Summary

**Minimum Setup (5 minutes):**
1. Add NavigationRegion2D to level
2. Bake navigation mesh
3. Add NavigationAgent2D to zombie.tscn
4. Done!

**Result:** Zombies navigate around obstacles instead of getting stuck! ✅

---

**Questions?** Check that:
- [ ] NavigationRegion2D exists in level
- [ ] Navigation polygon baked successfully
- [ ] NavigationAgent2D is child of each zombie
- [ ] Buildings have collision shapes on layer 1

If zombies work but don't use navigation, that's okay - they fall back to direct movement automatically.
