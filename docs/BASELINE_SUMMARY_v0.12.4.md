# Dead Corps v0.12.4 - CURRENT STABLE VERSION

**Date:** February 25, 2026  
**Status:** Stable - Core Mechanics Working  
**Purpose:** Foundation for tactical puzzle gameplay development

---

## 🎮 PROJECT OVERVIEW

**Dead Corps** is a tactical puzzle game where you command zombie hordes to hunt down fleeing humans. Combining RTS-style unit control with puzzle mechanics similar to Commandos or Shadow Tactics, featuring an isometric 2D perspective.

**Primary Goal:** Portfolio piece and learning experience for game development, covering design, technical implementation, and the full development pipeline.

---

## ✅ WORKING FEATURES (v0.12.4)

### **Core Zombie Mechanics**

#### 1. **Vision-Based Pursuit System**
- **Location:** `zombie.gd::check_auto_pursuit()` (line 411)
- **Behavior:** Zombies automatically pursue visible humans
- **Vision Modes:**
  - IDLE: 100px circular (360°)
  - PURSUING: 200px forward arc (90°)
- **Smart Switching:** Won't abandon combat for distant targets
- **Combat Lock:** Vision checks SKIPPED when grappling/in melee (prevents mid-combat target abandonment)

#### 2. **Leap Attack System**
- **Location:** `zombie.gd::try_leap_attack()` (line 324)
- **Trigger:** When within 150px of targeted human
- **Mechanics:**
  - Leap speed: 3x normal (450 units/s)
  - Landing: Automatically grapples target
  - Pinning: Human frozen until killed/converted
- **Cooldown:** 3 seconds between leaps
- **Flags:** Sets `is_leaping` and `has_leap_grappled` for combat state tracking

#### 3. **Melee Combat System**
- **Location:** `zombie.gd::manage_melee_attacker_status()` (line 526)
- **Range:** 30px attack range
- **Limit:** Maximum 3 zombies can attack one human simultaneously
- **Overflow:** 4th+ zombie finds different target
- **Commitment:** Once in melee range, zombie commits to target (no switching)

#### 4. **Target Commitment System**
- **Prevents:** Mid-combat target switching
- **Flags:** `is_committed_to_target`, `is_melee_attacker`, `has_leap_grappled`
- **Priority:** Combat engagement > vision checks > auto-pursuit
- **Duration:** Maintains commitment until target killed or lost

#### 5. **Stuck Detection & Recovery**
- **Location:** `zombie.gd::check_if_stuck()` (line 564)
- **Timeout:** 2 seconds of minimal movement
- **Exemption:** Stuck timer ignored during combat (fighting = standing still is normal)
- **Recovery:** Finds new target or goes idle

---

### **Core Human Mechanics**

#### 1. **Weighted Threat Flee System**
- **Location:** `human.gd::calculate_flee_direction()` (line 509)
- **Behavior:** Flees away from ALL visible zombies
- **Weighting:** Closer zombies have stronger influence
- **Formula:** `weight = 1.0 - (distance / max_range)`
- **Vision Range:**
  - IDLE: 120px circular (360°)
  - FLEEING: 100px forward arc (90°)

#### 2. **Escape Zone Attraction**
- **Location:** `human.gd::calculate_flee_direction()` (line 550)
- **Behavior:** Pulls toward escape zone when within 200px
- **Strength:** 20% at max range → 80% at close range
- **Smart Pathing:** Won't pull if zombie blocking path (60° cone check)
- **Desperation:** Always seeks escape if within 100px

#### 3. **Grapple System (Fixed v0.12.4)**
- **Location:** `human.gd::is_being_attacked()` (line 905)
- **Trigger:** Zombie within 50px AND in combat (leaping OR melee)
- **Critical Fix:** No longer grapples from proximity alone - requires active combat engagement
- **Effect:** Human frozen (velocity = 0) until killed/converted
- **No Escape:** Once grappled, stays grappled (rescue mechanics deferred)

#### 4. **Cascading Panic Propagation**
- **Location:** `human.gd::propagate_flee_to_group()` (line 835)
- **Behavior:** When one human detects zombie, nearby allies flee with delays
- **Delay:** 0.05s per human (creates panic wave effect)
- **Radius:** 80px trigger range
- **Minimum:** Requires 4+ humans in group
- **Method:** Uses standard `start_fleeing()` - each calculates own direction

#### 5. **Flee Momentum System**
- **Timeout:** 5 seconds after last visible threat
- **Behavior:** Continues fleeing in last direction after losing sight
- **Safety Check:** Only stops when truly safe (no threats for full timeout)

---

### **World & Obstacles**

#### 1. **Building System**
- **Location:** `building.gd`
- **Collision:** Static bodies block movement and vision
- **Resizing:** Inspector-editable width/height properties (20-1000px, 10px increments)
- **Fixed (v0.12.4):** Width and height changes now save properly
- **Duplication:** Each building has independent collision shape (fixed shared resource bug)

#### 2. **Escape Zones**
- **Location:** `escape_zone.gd`
- **Function:** Human "win condition" - reach zone to escape level
- **Detection:** Area2D trigger with collision layer/mask filtering
- **Visual:** Distinct color/marker for player visibility

---

### **Visual Systems**

#### 1. **Group Vision Merging**
- **Location:** `vision_renderer.gd::draw_vision_groups()`
- **Threshold:** 4+ units in same state
- **Visual:** Merged vision arc with count badge (e.g., "×5")
- **Line Width:** 3.5px for groups vs 1.5px for individuals

#### 2. **Selection System**
- **Location:** `selection_manager.gd`
- **Box Select:** Drag rectangle to select multiple zombies
- **Click Select:** Single click selects/deselects
- **Visual:** Green outline for player-controlled, red for auto-pursuing

#### 3. **Debug Overlay** (Toggle F1)
- FPS counter
- Unit counts (zombies, humans, escaped)
- Active vision cones
- Attack ranges

---

## 🐛 KNOWN ISSUES (v0.12.4)

### **Resolved in This Version:**
- ✅ Vision bug (zombies releasing grappled targets) - FIXED
- ✅ Collateral grappling (nearby humans freezing) - FIXED
- ✅ Building resize not saving - FIXED

### **Minor Issues:**
- Human group formations can clump when fleeing
- No formation-based movement yet (RTS-style unit spreading)
- Zombie pathfinding basic (no A* or navigation mesh)

### **Missing Features (Deferred):**
- Human rescue mechanics (waiting for combat system completion)
- Damage/conversion system (zombies grapple but don't convert yet)
- Multiple zombie types
- Puzzle level design tools

---

## 🏗️ ARCHITECTURE OVERVIEW

### **Class Hierarchy**
```
Node2D
├── Unit (base class)
│   ├── Zombie
│   └── Human
├── Building (StaticBody2D)
├── EscapeZone (Area2D)
└── Managers
    ├── GameManager
    ├── SelectionManager
    ├── VisionRenderer
    └── Initializer (spawner)
```

### **Key Design Patterns**

#### State Management
- Zombies: IDLE, MOVING, PURSUING, ATTACKING, LEAPING
- Humans: IDLE, FLEEING, GRAPPLED, DEAD
- Combat flags separate from movement state (is_melee_attacker, is_committed_to_target, has_leap_grappled)

#### Vision System
- Raycast-based line-of-sight
- Obstacle blocking (buildings)
- State-dependent range/arc
- Grouped rendering for performance

#### Combat Priority
```
1. Combat engagement (melee/leap) - highest priority, locks target
2. Player commands - overrides auto-pursuit
3. Auto-pursuit - lowest priority, can be interrupted
```

---

## 📁 PROJECT STRUCTURE

```
/Dead Corps/
├── scenes/
│   ├── main.tscn (main game scene)
│   ├── zombie.tscn
│   ├── human.tscn
│   ├── building.tscn
│   ├── escape_zone.tscn
│   └── debug_overlay.tscn
├── scripts/
│   ├── unit.gd (base class)
│   ├── zombie.gd
│   ├── human.gd
│   ├── building.gd
│   ├── escape_zone.gd
│   ├── game_manager.gd
│   ├── selection_manager.gd
│   ├── vision_renderer.gd
│   ├── camera_controller.gd
│   └── initializer.gd
└── docs/
    ├── GAME_DESIGN_DOCUMENT.md
    ├── CHANGELOG_v0.12.4.md
    └── [version history]
```

---

## 🎯 DEVELOPMENT STATUS

### **Completed Systems:**
- ✅ Core zombie AI (pursuit, leap, melee)
- ✅ Human flee behavior (weighted threats, escape seeking)
- ✅ Vision system (line-of-sight, arc-based)
- ✅ Grappling mechanics (combat engagement)
- ✅ Selection & control (box select, commands)
- ✅ Building obstacles (collision, LOS blocking)
- ✅ Debug visualization

### **In Development:**
- 🔄 Formation-based movement (prevent clumping)
- 🔄 RTS-style movement feel (smooth unit spreading)
- 🔄 Combat refinement (damage, conversion)

### **Planned Features:**
- ⏳ Human rescue mechanics
- ⏳ Multiple zombie types (fast, tank, ranged)
- ⏳ Puzzle level design
- ⏳ Level editor (deferred - using Godot's built-in tools)

---

## 🔧 DEVELOPMENT SETUP

### **Engine:** Godot 4.x
### **Language:** GDScript
### **Perspective:** Isometric 2D (top-down angled view)

### **Testing Tips:**
- **Disable Auto-Spawn:** Uncheck "Enabled" on Initializer node in main.tscn
- **Manual Unit Placement:** Drag zombie.tscn and human.tscn into scene
- **Toggle Debug Overlay:** Press F1 during gameplay
- **Camera Controls:** Arrow keys or WASD to pan, scroll to zoom

---

## 📊 VERSION PROGRESSION

- **v0.9.x** - Core flee behavior, basic zombie pursuit
- **v0.10.0** - Vision system, obstacle avoidance
- **v0.11.0** - Leap attacks, grappling mechanics
- **v0.12.0** - Selection system, combat commitment
- **v0.12.1-0.12.3** - Bug investigation (debug logging)
- **v0.12.4** - Vision & grappling bugs FIXED (current stable)

---

## 🎮 GAMEPLAY PHILOSOPHY

**Core Loop:** Command zombies → Hunt humans → Humans flee/escape → Tactical puzzle emerges

**Inspiration:** 
- Commandos/Shadow Tactics (tactical unit control)
- RTS movement feel (Starcraft, Warcraft III)
- Puzzle design (limited resources, optimal solutions)

**Unique Twist:** You control the monsters, not the heroes. Humans are autonomous prey, not player units.

---

## 📝 NOTES FOR DEVELOPERS

### **Common Workflows:**

**Creating New Levels:**
1. Duplicate main.tscn or create new scene
2. Add buildings for obstacles/cover
3. Place escape zone(s)
4. **Disable Initializer:** Select Initializer node, uncheck "Enabled" in Inspector
5. Manually place zombies/humans for specific puzzle setup

**Debugging Combat:**
- Watch for "Zombie entered melee" messages
- Check grapple state changes (is_grappled flag)
- Verify combat flags (is_melee_attacker, has_leap_grappled)
- Use debug overlay (F1) for visual confirmation

**Performance:**
- Group vision rendering saves draw calls
- Detection checks limited by timer (0.1s intervals)
- Raycasts cached per frame for vision/LOS

---

## 🚀 NEXT MILESTONES

1. **Movement Polish:** Formation-based positioning to prevent clumping
2. **Combat Completion:** Damage dealing, human → zombie conversion
3. **Level Design:** Create 3-5 puzzle levels demonstrating mechanics
4. **Polish:** Animations, sound effects, visual feedback
5. **Portfolio Package:** Screenshots, gameplay video, design doc
