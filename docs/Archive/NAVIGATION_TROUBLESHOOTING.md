# Navigation Mesh Troubleshooting - Godot 4.6

**Issue:** Buildings not being avoided by navigation mesh

---

## 🔧 **Solution 1: Verify Manual Polygon Excludes Buildings**

### **How Manual Polygons Work:**

**You draw the WALKABLE area** - buildings should be OUTSIDE your polygon.

**Correct:**
```
┌─────────┐
│ Walkable│
├────┐    │  
│Bld │    │  ← Building OUTSIDE polygon
├────┘    │
│ Walkable│
└─────────┘
```

**Incorrect:**
```
┌─────────────┐
│ Walkable    │
│   ┌────┐    │  ← Building INSIDE polygon
│   │Bld │    │
│   └────┘    │
│ Walkable    │
└─────────────┘
```

---

## 🎯 **Solution 2: Use Geometry Parsing (Recommended)**

**Instead of fully manual, let Godot detect buildings:**

### **Step 1: Create Outer Boundary Manually**

Draw ONE big polygon around your entire playable area:

```
┌─────────────────────┐
│                     │
│  [Building]  [Bld]  │
│                     │
│      [Building]     │
│                     │
└─────────────────────┘
```

Just draw the outer rectangle - don't worry about buildings inside.

---

### **Step 2: Enable Geometry Parsing**

1. **Select NavigationRegion2D**
2. **Inspector → Navigation Polygon → Geometry**
3. **Set these:**
   - **Source Geometry Mode:** "Groups"
   - **Source Geometry Group Name:** "buildings"
   - **Parsed Geometry Type:** "Static Colliders"
   - **Parsed Collision Mask:** 1 (layer 1)

---

### **Step 3: Add Buildings to Group**

1. **Select ALL buildings** (shift-click)
2. **Node tab** (top-right)
3. **Groups section**
4. **Add group:** "buildings"

---

### **Step 4: Bake**

1. **Menu → Bake NavigationPolygon**
2. **Result:** Outer polygon minus building collision shapes

**Should see:**
- Blue everywhere EXCEPT where buildings are
- Gaps/holes around each building

---

## 🐛 **Solution 3: Debug - Check What Zombies See**

Enable navigation debug to see the actual paths:

**In zombie.gd `_ready()`:**

```gdscript
if nav_agent:
    nav_agent.debug_enabled = true
    nav_agent.debug_use_custom = true
    nav_agent.debug_path_custom_color = Color.GREEN
```

**Run game:**
- Green lines should show zombie's planned path
- If path goes through buildings, navigation isn't working
- If path goes around, navigation IS working but zombie movement is broken

---

## 🔍 **Solution 4: Check Navigation Layers**

**Most common Godot 4.6 issue:**

Navigation layers must match between region and agent.

### **Check NavigationRegion2D:**

1. **Select NavigationRegion2D**
2. **Inspector → find "Navigation Layers"** (might be under dropdown)
3. **Ensure Layer 1 is checked**

### **Check NavigationAgent2D:**

1. **Select zombie → NavigationAgent2D**
2. **Inspector → Navigation Layers**
3. **Ensure Layer 1 is checked**

**If they don't match:**
- Agent can't see the navigation mesh
- Will ignore it completely

---

## 📊 **Visual Debug Checklist**

**In Editor (game not running):**
- [ ] Blue areas visible where zombies should walk
- [ ] Gaps/holes around buildings (no blue there)
- [ ] Navigation Polygon property not empty

**In Running Game:**
- [ ] Console shows "✓ HAS NavigationAgent2D"
- [ ] Green path lines visible (if debug enabled)
- [ ] Zombies actually follow paths around corners

**If blue areas look wrong:**
- Manual polygon might be covering buildings
- Redraw to exclude building areas

**If blue areas look correct but zombies ignore them:**
- Check navigation layers match
- Check NavigationAgent2D radius matches Agent Radius

---

## 🎯 **Quick Test:**

**Create a simple test:**

1. **Delete complex navigation mesh**
2. **Draw a simple square** avoiding ONE building
3. **Place zombie outside square**
4. **Place human inside square** (on other side of building)
5. **Run game** - does zombie path around to enter square?

**If YES:** Navigation works, your complex polygon is wrong  
**If NO:** Navigation layers or agent settings wrong

---

## 🛠️ **Nuclear Option: Start Fresh**

If nothing works, try this:

1. **Delete NavigationRegion2D** entirely
2. **Create new NavigationRegion2D**
3. **Add new NavigationPolygon**
4. **Draw simple outer boundary** (just a rectangle)
5. **Don't manually exclude buildings yet**
6. **Set Geometry Mode:** "Groups"
7. **Add buildings to group:** "buildings"
8. **Bake** - let Godot handle it

**This often fixes weird Godot 4.6 issues.**

---

## 📋 **Settings Summary**

**For Godot 4.6 + Manual Polygons:**

```
NavigationRegion2D:
  Navigation Polygon:
    Geometry:
      Source Geometry Mode: Groups
      Source Geometry Group Name: buildings
      Parsed Geometry Type: Static Colliders
      Parsed Collision Mask: 1
    Agents:
      Agent Radius: 30.0
      Cell Size: 10.0
  Navigation Layers: [✓][ ][ ]... (Layer 1 checked)

Buildings (StaticBody2D):
  Groups: buildings
  Collision Layer: 1

Zombie → NavigationAgent2D:
  Navigation Layers: [✓][ ][ ]... (Layer 1 checked)
  Radius: 30.0
  Path Desired Distance: 15.0
  Target Desired Distance: 20.0
```

---

**Try the Groups approach - it's the most reliable for Godot 4.6!**
