# Phase B2: Visual Waypoint Placement

**Version:** v0.19.0  
**Feature:** Drag-and-drop waypoint placement with child nodes

---

## 🎯 **What's New**

**Instead of typing coordinates:**
```
❌ OLD WAY:
Patrol Waypoints:
  [0]: (100, 100)  ← Type numbers
  [1]: (200, 100)
  [2]: (200, 200)
```

**Now you can drag nodes in the editor:**
```
✅ NEW WAY:
Human (Sentry)
├─ Waypoint1 (Node2D) ← Drag this around!
├─ Waypoint2 (Node2D)
└─ Waypoint3 (Node2D)
```

**Much easier for level designers!**

---

## 📋 **Step-by-Step Setup**

### **Step 1: Create Your Sentry**

1. **Add a Human** to your scene (or select existing one)
2. **In Inspector:**
   - Initial State: **SENTRY**
   - Patrol Enabled: **ON** (check the box)
   - Patrol Mode: **LOOP** (or PING_PONG)
   - Patrol Speed: **50** (adjust as needed)
3. **Leave Patrol Waypoints EMPTY** (don't add any manual coordinates!)

---

### **Step 2: Add Waypoint Child Nodes**

1. **Right-click the Human sentry** in scene tree
2. **Add Child Node** → Search: **"Node2D"**
3. **Add it**
4. **Rename it:** "Waypoint1" (EXACTLY this spelling, capital W)
5. **Repeat** to add more waypoints: "Waypoint2", "Waypoint3", etc.

**Important naming:**
- Must start with "Waypoint"
- Followed by a number: Waypoint1, Waypoint2, Waypoint3...
- Numbers determine patrol order
- Case-sensitive: "Waypoint" not "waypoint"

---

### **Step 3: Position Waypoints Visually**

**Now the fun part - drag them around!**

1. **Select "Waypoint1"** in scene tree
2. **In 2D viewport**, you'll see the waypoint (small dot/cross)
3. **Click and drag** to move it where you want
4. **Repeat for Waypoint2, Waypoint3**, etc.

**Tips:**
- Use arrow keys for fine positioning
- Check position in Inspector if you need exact placement
- Waypoints are positioned in world space (absolute positions)

---

### **Step 4: Test Your Patrol**

1. **Save the scene** (Ctrl+S)
2. **Run the game** (F5)
3. **Watch console** for:
   ```
   Loaded waypoint: Waypoint1 at (100, 100)
   Loaded waypoint: Waypoint2 at (200, 100)
   Loaded waypoint: Waypoint3 at (200, 200)
   Patrol initialized for Human1 with 3 waypoints
   ```
4. **Watch sentry walk** the patrol route!

---

## 🎨 **Visual Editor Benefits**

### **See the Path Immediately:**

When you select the sentry in editor:
- Yellow dots show waypoint positions
- Yellow lines connect them
- You can see exactly where the guard will walk

### **Easy Adjustments:**

Want to change the path?
1. Select a waypoint node
2. Drag it to new position
3. Save and re-run
4. Done!

No more guessing coordinates!

---

## 📊 **Example Setups**

### **Square Perimeter Patrol**

```
Human (Sentry)
├─ Waypoint1 (Node2D)  ← Position: Top-left corner
├─ Waypoint2 (Node2D)  ← Position: Top-right corner
├─ Waypoint3 (Node2D)  ← Position: Bottom-right corner
└─ Waypoint4 (Node2D)  ← Position: Bottom-left corner

Patrol Mode: LOOP
Result: Guard walks square continuously
```

---

### **Hallway Back-and-Forth**

```
Human (Sentry)
├─ Waypoint1 (Node2D)  ← Position: Left end of hallway
└─ Waypoint2 (Node2D)  ← Position: Right end of hallway

Patrol Mode: PING_PONG
Result: Guard walks back and forth
```

---

### **Complex Route**

```
Human (Sentry)
├─ Waypoint1 (Node2D)  ← Entrance
├─ Waypoint2 (Node2D)  ← First room
├─ Waypoint3 (Node2D)  ← Hallway junction
├─ Waypoint4 (Node2D)  ← Second room
├─ Waypoint5 (Node2D)  ← Storage area
└─ Waypoint6 (Node2D)  ← Back to entrance

Patrol Mode: LOOP
Result: Complete facility patrol
```

---

## 🔄 **Backwards Compatibility**

**Both methods work:**

**Manual waypoints (Phase B1):**
- Fill in Patrol Waypoints array in Inspector
- Type coordinates manually
- Waypoint children are ignored

**Visual waypoints (Phase B2):**
- Leave Patrol Waypoints array EMPTY
- Add Waypoint child nodes
- Positions auto-loaded from children

**System automatically chooses:**
- If Patrol Waypoints has entries → use those
- If Patrol Waypoints is empty → load from children
- Can't mix both methods (manual overrides children)

---

## 🐛 **Troubleshooting**

### **Sentry Not Moving**

**Check:**
- [ ] Patrol Enabled is ON
- [ ] Waypoint children exist (Waypoint1, Waypoint2, etc.)
- [ ] Waypoints are Node2D type (not other node types)
- [ ] Names spelled correctly: "Waypoint" not "waypoint"
- [ ] Initial State is SENTRY

---

### **Console Shows "0 waypoints"**

**Likely causes:**

**Wrong naming:**
```
❌ Wrong:
├─ waypoint1  (lowercase 'w')
├─ WayPoint1  (capital 'P')
├─ Waypoint_1 (underscore)

✅ Correct:
├─ Waypoint1  (capital W, no underscore)
├─ Waypoint2
└─ Waypoint3
```

**Or manual waypoints set:**
- Check Inspector → Patrol Waypoints
- If it has entries, clear them (set size to 0)
- System prioritizes manual over children

---

### **Waypoints Out of Order**

**Waypoints patrol in alphabetical order by name:**

```
Correct order:
Waypoint1 → Waypoint2 → Waypoint3 → ... → Waypoint10

Wrong order (if you have 10+ waypoints):
Waypoint1 → Waypoint10 → Waypoint2 → ...
          ↑ Alphabetically "10" comes before "2"
```

**Fix for 10+ waypoints:**
Use leading zeros:
```
Waypoint01, Waypoint02, ..., Waypoint10, Waypoint11
```

---

### **Can't See Waypoint Nodes in Viewport**

**Waypoints are Node2D - they're invisible by default!**

**To see them:**
1. **Select a waypoint** in scene tree
2. **Look for the transform gizmo** (arrows/circle)
3. **That's where the waypoint is**

**Or add a visual marker (optional):**
1. Select waypoint
2. Add child → Sprite2D or ColorRect
3. Make it small (10x10 pixels)
4. Set bright color
5. Now you can see it even when not selected!

---

### **Patrol Path Looks Wrong in Editor**

**The yellow path only shows when SENTRY is selected, not waypoints!**

**To see the path:**
1. Select the SENTRY (parent human)
2. Yellow dots and lines appear
3. Shows the patrol route

**If no yellow path appears:**
- Patrol Enabled might be OFF
- Or waypoints not loading (check console)

---

## 💡 **Pro Tips**

### **Tip 1: Use Snap to Grid**

1. **View menu → Grid Snap** (or press G)
2. **Adjust grid size** (default 10 pixels)
3. **Drag waypoints** - they snap to grid
4. **Result:** Clean, aligned patrol paths

---

### **Tip 2: Group Waypoints in Editor**

**For better organization:**
```
Human (Sentry)
├─ Waypoints (Node)        ← Empty container node
│  ├─ Waypoint1 (Node2D)
│  ├─ Waypoint2 (Node2D)
│  └─ Waypoint3 (Node2D)
```

**Still works!** System finds Waypoint children recursively.

---

### **Tip 3: Color-Code Waypoints**

**Add ColorRect children for visibility:**

1. Select Waypoint1
2. Add child → ColorRect
3. Size: 8x8, Color: Yellow
4. Offset: -4, -4 (centers it)
5. Now waypoint has visible marker!

---

### **Tip 4: Copy/Paste Waypoints**

**To duplicate a patrol pattern:**
1. Select all waypoint nodes (Ctrl+click)
2. Ctrl+C (copy)
3. Select target sentry
4. Ctrl+V (paste)
5. Rename to Waypoint1, Waypoint2, etc.
6. Adjust positions as needed

---

## 🎮 **Common Patrol Patterns**

### **1. Room Guard**

**4 waypoints at room corners**
- LOOP mode
- Speed: 40 (slow patrol)
- Checks entire perimeter

### **2. Hallway Guard**

**2 waypoints at hall ends**
- PING_PONG mode
- Speed: 50
- Walks back and forth

### **3. Multi-Room Patrol**

**8+ waypoints through facility**
- LOOP mode
- Speed: 60
- Covers large area

### **4. Figure-8 Pattern**

**6 waypoints in figure-8 shape**
- LOOP mode
- Speed: 45
- Interesting, unpredictable route

---

## 📋 **Quick Reference**

**Naming Rules:**
- ✓ Waypoint1, Waypoint2, Waypoint3...
- ✓ Capital W
- ✓ No spaces, underscores, or hyphens
- ✓ Numbers determine order

**Setup Steps:**
1. Sentry: Patrol Enabled = ON
2. Add Node2D children named Waypoint1, Waypoint2, etc.
3. Drag them to positions in viewport
4. Save and run!

**Debugging:**
- Check console for "Loaded waypoint..." messages
- Yellow path shows when sentry selected
- Patrol Waypoints array should be EMPTY (for visual mode)

---

## 🚀 **What's Next: Phase C**

**Coming soon:**
- Per-waypoint pause durations
- Per-waypoint swing arcs
- Per-waypoint facing direction overrides

**For now:** Basic patrol with visual placement is complete! 🎉

---

**Happy patrolling!** 🎯
