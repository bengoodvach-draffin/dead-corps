# Navigation Setup - Final Steps

**Version:** v0.17.3  
**Status:** Code ready, needs final configuration in Godot

---

## ✅ **What's Already Done:**

- ✓ NavigationAgent2D added to zombie.tscn
- ✓ All navigation code in zombie.gd
- ✓ Debug logging in place
- ✓ Both combat and normal movement supported

---

## 🔧 **What YOU Need to Do in Godot:**

### **Step 1: Configure NavigationRegion2D** (5 minutes)

**In your level scene:**

1. **Select NavigationRegion2D**
2. **In Inspector**, expand "Navigation Polygon"
3. **Find "Agents" section** (might be under a dropdown)
4. **Set Agent Radius: 30.0** (was 15.0)
   - This gives zombies wider clearance around corners
5. **Menu:** NavigationRegion2D → **Bake NavigationPolygon**
6. **Confirm:** Blue navigation area should pull away from walls more

---

### **Step 2: Verify Zombie Has NavigationAgent2D** (1 minute)

**Check the zombie scene:**

1. **Scene → Open Scene** → Find **zombie.tscn**
2. **Expand Zombie node** in scene tree
3. **Confirm you see:** NavigationAgent2D as a child
4. **If missing:** It should be there in this zip, but if not:
   - Right-click Zombie → Add Child Node
   - Search: NavigationAgent2D
   - Add it
   - Set Radius: 30.0

---

### **Step 3: Test Navigation** (2 minutes)

1. **Run your game (F5)**
2. **Check console for:**
   ```
   === ZOMBIE NAVIGATION DEBUG ===
   Zombie: Zombie1
   ✓ HAS NavigationAgent2D
   ===============================
   ```
3. **Right-click to move zombie** around a building corner
4. **Should:** Take smooth, wide turns
5. **Should NOT:** Cut sharp corners

---

## 🎯 **Expected Behavior:**

### **Normal Movement (Right-Click):**
- Zombie uses navigation to path around obstacles
- Takes smooth corners
- Doesn't get stuck on walls

### **Combat Movement (Attacking Humans):**
- Same navigation behavior
- Paths around buildings to reach target
- No more wall-pushing

---

## 🐛 **Troubleshooting:**

### **"✗ NO NavigationAgent2D" in console**

**Fix:**
1. Open zombie.tscn
2. Check if NavigationAgent2D child exists
3. If missing, add it manually (see Step 2 above)

---

### **Zombie still cuts corners too sharp**

**Fix:**
1. Select NavigationRegion2D
2. Navigation Polygon → Agent Radius → **Increase to 35 or 40**
3. Re-bake navigation mesh
4. Also set zombie's NavigationAgent2D → Radius to same value

---

### **Zombie ignores navigation mesh**

**Check navigation layers match:**
1. NavigationRegion2D → Navigation Layers: Layer 1 checked
2. Zombie → NavigationAgent2D → Navigation Layers: Layer 1 checked
3. They must match!

---

### **Navigation works but zombie moves weird**

**Tune these values on NavigationAgent2D:**
- **Path Desired Distance: 15.0** (lower = tighter following)
- **Target Desired Distance: 20.0** (how close to final target)
- **Radius: 30.0** (clearance from walls)

---

## 📊 **Recommended Settings:**

### **For Tight Levels (corridors, mazes):**
```
NavigationPolygon:
  Agent Radius: 25.0
  Cell Size: 8.0

NavigationAgent2D:
  Radius: 25.0
  Path Desired Distance: 12.0
  Target Desired Distance: 15.0
```

### **For Open Levels (arenas, fields):**
```
NavigationPolygon:
  Agent Radius: 35.0
  Cell Size: 15.0

NavigationAgent2D:
  Radius: 35.0
  Path Desired Distance: 20.0
  Target Desired Distance: 25.0
```

### **Balanced (recommended starting point):**
```
NavigationPolygon:
  Agent Radius: 30.0
  Cell Size: 10.0

NavigationAgent2D:
  Radius: 30.0
  Path Desired Distance: 15.0
  Target Desired Distance: 20.0
```

---

## 🎮 **Testing Checklist:**

- [ ] Console shows "✓ HAS NavigationAgent2D" on startup
- [ ] Right-click movement paths around buildings
- [ ] Attack-move paths around buildings
- [ ] Zombies take smooth, wide corners
- [ ] No getting stuck on walls
- [ ] Navigation mesh visible as blue area in editor

---

## 🚀 **You're Done When:**

✅ Zombie console shows navigation is active  
✅ Right-click movement uses navigation  
✅ Zombies navigate around corners smoothly  
✅ No sharp corner cutting or wall-hugging  

---

**Everything else is already set up in the code!** Just do those 3 steps above in Godot. 🎯
