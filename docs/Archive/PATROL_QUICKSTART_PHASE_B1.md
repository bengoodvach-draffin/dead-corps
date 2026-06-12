# Patrol System Quick Start - Phase B1

**Version:** v0.18.0  
**Status:** Basic patrol system complete!

---

## ✅ What's Included

### **Vision Arc Fix:**
- ✓ Zombies now show forward arc (triangle) when moving via right-click
- ✓ Was stuck on idle circle, now properly transitions to MOVING state

### **Patrol System (Phase B1):**
- ✓ Waypoint array for manual coordinate entry
- ✓ LOOP mode (circular patrol: 0→1→2→3→0)
- ✓ PING_PONG mode (back-and-forth: 0→1→2→3→2→1→0)
- ✓ Visual waypoint path in editor (yellow/orange lines and dots)
- ✓ Sentries face movement direction while patrolling
- ✓ Patrol stops when zombie detected (switches to fleeing)

---

## 🎮 How to Use Patrol

### **Step 1: Enable Patrol on a Sentry**

1. **Select a Human** in your scene
2. **In Inspector**, set:
   - **Initial State:** SENTRY
   - **Patrol Enabled:** ON (check the box)

---

### **Step 2: Add Waypoints (Manual Entry)**

**In Inspector → Patrol Waypoints:**

1. **Click the dropdown** next to "Patrol Waypoints"
2. **Set Array Size:** 4 (or however many points you want)
3. **Enter coordinates** for each waypoint:

```
Patrol Waypoints:
  [0]: (100, 100)
  [1]: (200, 100)
  [2]: (200, 200)
  [3]: (100, 200)
```

**Result:** Square patrol pattern

---

### **Step 3: Choose Patrol Mode**

**In Inspector → Patrol Mode:**

**LOOP (default):**
- Patrols in a circle: 0→1→2→3→0→1...
- Never reverses direction
- Good for: perimeter patrols, guard rounds

**PING_PONG:**
- Goes forward then backward: 0→1→2→3→2→1→0→1...
- Reverses at ends
- Good for: hallway patrols, back-and-forth routes

---

### **Step 4: Adjust Patrol Speed (Optional)**

**In Inspector → Patrol Speed:**
- Default: 50 (pixels/second)
- Range: 10-100
- **Slower (30):** Casual stroll
- **Medium (50):** Normal walk
- **Faster (70):** Brisk pace

---

## 📊 Visual Editor Guide

### **What You'll See in Editor:**

When you select a sentry with patrol enabled:

**Yellow/Orange Waypoints:**
- Dots show waypoint positions
- Lines connect waypoints in order
- Path shows the patrol route

**Cyan Arrow:**
- Shows initial facing direction (if not patrolling)
- Overridden by movement direction while patrolling

---

## 🎯 Example Configurations

### **Square Perimeter Guard (LOOP)**

```
Patrol Enabled: ON
Patrol Waypoints:
  [0]: (100, 100)   # Top-left
  [1]: (300, 100)   # Top-right
  [2]: (300, 300)   # Bottom-right
  [3]: (100, 300)   # Bottom-left
Patrol Mode: LOOP
Patrol Speed: 50
```

**Behavior:** Guard walks square perimeter continuously

---

### **Hallway Patrol (PING_PONG)**

```
Patrol Enabled: ON
Patrol Waypoints:
  [0]: (100, 200)   # Left end
  [1]: (300, 200)   # Right end
Patrol Mode: PING_PONG
Patrol Speed: 40
```

**Behavior:** Guard walks back and forth down hallway

---

### **Figure-8 Pattern (LOOP)**

```
Patrol Enabled: ON
Patrol Waypoints:
  [0]: (150, 100)
  [1]: (250, 150)
  [2]: (250, 250)
  [3]: (150, 200)
  [4]: (50, 250)
  [5]: (50, 150)
Patrol Mode: LOOP
Patrol Speed: 60
```

**Behavior:** Guard traces figure-8 pattern

---

## 🐛 Troubleshooting

### **Sentry Not Moving**

**Check:**
- [ ] Patrol Enabled is checked (ON)
- [ ] Patrol Waypoints has at least 1 waypoint
- [ ] Waypoints are valid coordinates (not 0,0 unless intended)
- [ ] Initial State is SENTRY (not IDLE)

---

### **Can't See Waypoint Path**

**Fix:**
- Make sure sentry is **selected** in editor
- Waypoint visualization only shows when selected
- Path drawn in yellow/orange color

---

### **Sentry Stops Patrolling Mid-Route**

**This is normal if:**
- Zombie detected (sentry switches to FLEEING)
- Sentry was grappled
- After fleeing, sentry won't resume patrol (current behavior)

---

### **Waypoint Path Looks Wrong**

**Common issues:**
- **Coordinates relative to world, not sentry**
- If sentry at (50, 50), waypoint (100, 100) is 50px away
- Use global positions, not offsets

---

## 🎓 Tips & Tricks

### **Quick Way to Get Coordinates:**

1. **Place a Node2D** where you want waypoint
2. **Check its Position** in Inspector
3. **Copy those coordinates** to Patrol Waypoints array
4. **Delete the Node2D**

---

### **Test Patrol Quickly:**

1. **Run game (F5)**
2. **Watch sentry walk the path**
3. **Adjust waypoints if path looks wrong**
4. **Re-run to test**

---

### **Combining with Swing Arc:**

Patrol + Swing Arc = Guard that:
- Walks patrol route (moving between points)
- Stops and looks around at each waypoint (future Phase C feature)
- **Currently:** Swing only works when stationary, not while moving

---

## 🚀 What's Next: Phase B2

**Visual Waypoint Placement:**
- Drag Node2D children to set waypoints (no typing!)
- See waypoints in editor instantly
- Easier for level designers

**Phase C:**
- Per-waypoint pauses
- Per-waypoint swing arcs  
- Per-waypoint facing overrides

---

## 📋 Testing Checklist

- [ ] Sentry with 4-waypoint LOOP patrol walks continuously
- [ ] PING_PONG mode reverses at ends correctly
- [ ] Waypoint path visible in editor (yellow dots/lines)
- [ ] Sentry faces movement direction while walking
- [ ] Patrol stops when zombie detected
- [ ] Can adjust patrol speed and see difference

---

## 🎮 Try These Patterns

**2-point back-and-forth:**
- Simplest patrol
- Good for doorways

**4-point square:**
- Classic perimeter patrol
- Good for rooms

**6+ point complex route:**
- Guards check multiple areas
- More realistic patrol

---

**Patrol system ready to use!** Just add waypoints and go! 🎯
