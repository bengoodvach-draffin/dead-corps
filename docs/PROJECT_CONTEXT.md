# Dead Corps - Project Context Document

**Last Updated:** March 15, 2026  
**Current Version:** v0.22.6  
**Purpose:** Complete context for starting fresh Claude conversations

---

## 🎮 **Project Overview**

**Dead Corps** is a tactical puzzle game where players command zombie hordes through levels. It's a creative career transition project from software development into game development, reviving a 15-year-old concept with a unique twist on the zombie genre.

**Core Gameplay:**
- Players control zombies (not defend against them)
- RTS-style unit control with tactical puzzle mechanics
- Similar to Commandos or Shadow Tactics
- Eleven distinct zombie types with specialized abilities
- Sandbox-style levels with environmental challenges

**Development Philosophy:**
- Portfolio project and creative exploration (not commercial)
- Learning opportunity for game development
- Community-generated content through level editor (planned)

---

## 📊 **Current Build Status: v0.22.6**

### **What's Implemented & Working:**

✅ **Core Systems (v0.1.0 - v0.12.0):**
- Basic zombie and human units (2D isometric)
- Unit selection and command system
- Formation-based movement (BOID flocking)
- Vision systems (circular and arc-based)
- Combat and grappling mechanics
- Zombie conversion on kill
- Escape zones for humans
- Camera controls

✅ **Phase A: Sentry System (v0.14.0):**
- Degree-based sentry facing (0° = North, 90° = East, etc.)
- Visual arrow in editor showing facing direction
- Swing arc system for sentries
  - Smooth sin/cos oscillation
  - Configurable range, speed, pause duration
  - Visual arc indicator in editor (green)

✅ **Panic Spreading (v0.16.0 - v0.17.0):**
- 40px panic radius (immediate neighbors only)
- Triggers only on GRAPPLED state (not being chased)
- Realistic panic waves through sentry groups
- Fixed global_position calculations for escape zones
- Line-of-sight requirement for escape zone selection

✅ **Zombie Navigation (v0.17.0 - v0.17.3):**
- Optional NavigationAgent2D support
- Pathfinding around obstacles
- Smooth corner navigation
- Falls back to direct movement if not configured
- Works for both combat and normal movement
- Agent radius: 30px for wide clearance

✅ **Patrol System Phase B1 (v0.18.0):**
- Manual waypoint patrol (typed coordinates)
- LOOP mode (circular: 0→1→2→3→0)
- PING_PONG mode (back-and-forth: 0→1→2→3→2→1→0)
- Visual waypoint path in editor (yellow dots/lines)
- Configurable patrol speed
- Stops patrolling when zombie detected

✅ **Patrol System Phase B2 (v0.19.0 - v0.19.4):**
- Visual waypoint placement via child Node2D nodes
- Natural string sorting (handles Waypoint1-10+ correctly)
- Drag-and-drop waypoint positioning
- Backwards compatible with manual waypoints
- Swing disabled while patrolling (clean movement)
- Faces movement direction while walking

✅ **Patrol System Phase C (v0.20.0):**
- Per-waypoint pause durations (`patrol_pause_durations: Array[float]`)
- Per-waypoint swing during pause (`patrol_waypoint_swing: Array[bool]`)
- Per-waypoint facing overrides (`patrol_waypoint_facing: Array[float]`, -1.0 = no override)
- Swing during pause works even if `sentry_has_swing` is globally false
- Fully backwards compatible — empty arrays = behaviour identical to v0.19.5

✅ **Formation Squad Patrols (v0.21.0):**
- Leader-follower pattern: one human leads, others hold a NodePath reference to leader
- Five formation shapes: LINE_ABREAST, COLUMN, WEDGE, ECHELON, DIAMOND
- Configurable spacing (`formation_spacing`) and regroup timeout (`formation_regroup_timeout`)
- Leader waits at each waypoint (with timeout) for followers to regroup before advancing
- Followers go IDLE if leader dies (with `is_instance_valid` guard)
- Fully backwards compatible — empty `patrol_leader` = standalone sentry behaviour unchanged

✅ **Vision System Fixes (v0.18.0):**
- Zombies show forward arc when moving (not idle circle)
- Proper state detection for right-click movement

✅ **World Bounds System (v0.19.5):**
- WorldBounds autoload singleton — single source of truth for level size
- Units and camera both read from WorldBounds automatically
- Change `world_bounds_min` / `world_bounds_max` in world_bounds.gd to resize level
- Default bounds: ±1000 (expanded from old hardcoded ±500)

---

✅ **Human Defender System (v0.22.0 - v0.22.6):**
- Five defender classes: Civilian, Militia, Police, GI, Spec Ops — set via `defender_class` Inspector export
- `DefenderClass` enum with per-class morale and weapon defaults auto-applied in `_ready()`
- Morale bar system replacing binary flee trigger and `propagate_flee_to_group()` cascade
- Dual-zone vision arcs: outer detection zone (350px) + inner shooting zone (weapon range)
- Shooting system: aim timer starts on target acquisition in vision cone, fires on entering weapon range
- Tracer line on firing (bright yellow, 0.1s fade) from bottom-center of sprite
- TUNNEL_VISION state for GI/Spec Ops: 22.5° locked orange cone, 10s, locks toward threat zombie
- Morale recovers to 50% on flee recovery and tunnel vision expiry
- Zombie death visual: dark red Color(0.4, 0.0, 0.0), 0.3s delay, shot knockback tween (8px)
- Navigation debug logging silenced in zombie.gd
- Camera default zoom 1.0×, max zoom 2.5×, windowed 1920×1080
- Vision range increased: SENTRY/FLEEING arcs 180px → 350px

**Key spec amendments made during implementation:**
- Ally event radius changed from 80px → 150px (more realistic spread)
- Tunnel vision cone narrowed from 45° → 22.5° (tighter, more dramatic)
- Tunnel vision locks toward threat zombie position (not current facing)
- Morale bar shows only in IDLE/SENTRY states (hides on FLEEING, GRAPPLED, DEAD)
- No color tint on morale drain — bar only
- `propagate_flee_to_group()` and `panic_propagation_depth` deprecated (commented out, not deleted)

---

### **Known Issues & Limitations:**

⚠️ **Navigation Mesh Baking (Godot 4.6):**
- Auto-bake can fail for some setups
- Workaround: Use Groups method (add buildings to "buildings" group)
- Manual polygon drawing works but tedious
- Navigation layers must match (Region and Agent both on Layer 1)

⚠️ **Patrol Resume After Threat:**
- Patrol stops permanently when a zombie is detected (by design for now)
- Sentries do not resume their route after the threat passes
- Evaluate during playtesting whether auto-resume is needed

⚠️ **Morale/shooting tuning:**
- Kill counts per class are higher than spec due to aim timer starting at vision range
- Intentionally left for playtesting tuning — fundamentally working correctly

---

## 🗂️ **File Structure**

### **Key Scripts:**

**scripts/zombie.gd:**
- Zombie unit class (extends Unit)
- States: IDLE, MOVING, PURSUING, LEAPING, MELEE, DEAD
- Vision: Circular (idle) or Arc (moving/pursuing)
- Navigation support via optional NavigationAgent2D
- Leap attack mechanics
- Conversion signal when killing humans
- `take_damage(amount, knockback_direction)` override — optional knockback tween on death
- Death: dark red color, 0.3s delay, movement stops immediately on DEAD state

**scripts/human.gd:**
- Human unit class (extends Unit)
- States: IDLE, SENTRY, FLEEING, GRAPPLED, DEAD, TUNNEL_VISION
- FREEZE and MELEE_CHARGE states designed but deferred
- `DefenderClass` enum: CIVILIAN, MILITIA, POLICE, GI, SPEC_OPS
- Morale system: continuous sighting drain, ally event hooks (150px radius), flee/tunnel vision response
- Shooting system: aim timer, tracer line, LOS pause, weapon range gating
- TUNNEL_VISION: 22.5° locked cone, threat-facing, 10s duration, immune to drain
- Patrol modes: LOOP, PING_PONG
- Phase C: per-waypoint pause, swing, and facing overrides
- Formation squad system: leader/follower with 5 shapes
- `propagate_flee_to_group()` deprecated (commented out)
- Sentry features: degrees, swing arcs, visual editor
- Escape zone seeking with line-of-sight
- Waypoint loading from child nodes

**scripts/unit.gd:**
- Base class for all units
- Movement and combat systems
- Health and damage
- BOID flocking (separation, cohesion, alignment)
- Team system (ZOMBIES vs HUMANS)

**scripts/vision_renderer.gd:**
- Draws vision arcs/circles
- Handles all unit vision visualization

---

### **Scene Files:**

**scenes/zombie.tscn:**
- Zombie unit scene
- Includes NavigationAgent2D child (radius: 30.0)
- CollisionShape2D (radius: 12.0)
- Visual sprite

**scenes/human.tscn:**
- Human unit scene
- Similar structure to zombie

**scenes/test_level_1.tscn:**
- Main test level
- Should include NavigationRegion2D
- Buildings on collision layer 1

---

## 🗃️ **Scripts & Files Inventory**

> **Purpose:** Prevent naming conflicts and wasted effort. Before creating any new file, check this list first.
> **Last Updated:** v0.21.3

---

### **GDScript Files (`scripts/`)**

| File | Class Name | Extends | Purpose |
|------|-----------|---------|---------|
| `unit.gd` | `Unit` | `CharacterBody2D` | Base class for all units. Handles movement, combat, health, selection, BOID flocking, and world boundary clamping. Inherited by Zombie and Human. |
| `zombie.gd` | `Zombie` | `Unit` | Player-controlled zombie units. Handles states (IDLE/MOVING/PURSUING/LEAPING/MELEE/DEAD), vision detection, leap attacks, and human conversion signal. Optional NavigationAgent2D support. |
| `human.gd` | `Human` | `Unit` | AI-controlled human enemies. Handles states (IDLE/SENTRY/FLEEING/GRAPPLED/DEAD), sentry facing/swing arc, patrol system (LOOP/PING_PONG) with Phase C per-waypoint pause/swing/facing, formation squad system (leader/follower, 5 shapes), depth-capped panic spreading with distance-based delays, and escape zone seeking. Uses @tool for editor visuals. |
| `game_manager.gd` | `GameManager` | `Node` | **Core gameplay coordinator. Do NOT rename or replace.** Tracks all_zombies and all_humans arrays, handles spawning, zombie conversion after incubation, escape counting, win/loss conditions, and game time. Found in scene via group `"game_manager"`. |
| `selection_manager.gd` | `SelectionManager` | `Node2D` | RTS unit selection. Handles click selection, drag box selection, Shift+click multi-select, and Ctrl+1-9 control group assignment/recall. Found in scene via group `"selection_manager"`. |
| `camera_controller.gd` | `CameraController` | `Camera2D` | RTS camera. WASD pan, mouse wheel zoom with smoothing, edge scrolling, and configurable bounds. Syncs bounds from WorldBounds autoload on ready. Found in scene via group `"camera"`. |
| `vision_renderer.gd` | `VisionRenderer` | `Node2D` | Draws all unit vision cones and circles each frame. Handles Tab key cycling between vision modes (none/all/selected only/hidden). Merges vision of nearby grouped units. |
| `building.gd` | `Building` | `StaticBody2D` | Static obstacle. Blocks unit movement and line-of-sight. Configurable width/height and color via @export. Uses @tool for real-time editor preview. Added to `"buildings"` group for navigation mesh baking. |
| `escape_zone.gd` | `EscapeZone` | `Area2D` | Safe zone for humans. Humans entering are counted as escaped; zombies entering are killed. Configurable size and color. Uses @tool for editor preview. References GameManager via group. |
| `initializer.gd` | *(none)* | `Node` | Scene bootstrap. Waits one frame then calls `game_manager.setup_test_scenario()`. Can be disabled via @export flag. For prototyping only — will be replaced by level loading. |
| `debug_overlay.gd` | *(none)* | `CanvasLayer` | In-game HUD showing live zombie/human/escaped counts, selected unit count, control group assignments, and a reset button. References GameManager and SelectionManager via groups. |
| `end_game_overlay.gd` | *(none)* | `CanvasLayer` | Win/loss screen shown when game ends. Displays result message and score breakdown. Hidden by default, shown when GameManager emits `game_won` or `game_lost` signals. |
| `world_bounds.gd` | *(none, Autoload)* | `Node` | **Added v0.19.5.** Autoload singleton registered as `WorldBounds`. Single source of truth for world bounds (`world_bounds_min`, `world_bounds_max`). Read by unit.gd and camera_controller.gd. Change bounds here and everything updates automatically. |
| `level_bounds.gd` | *(none)* | `Node2D` | **Added v0.21.3.** @tool Node placed in each level scene. Exports `bounds_min` / `bounds_max` (Vector2). On `_ready()` writes values into WorldBounds autoload so all unit clamping and camera update automatically. Draws orange boundary rectangle in editor and at runtime. Replace the old approach of editing world_bounds.gd directly. |

---

### **Scene Files (`docs/` — stored alongside docs)**

| File | Purpose |
|------|---------|
| `zombie.tscn` | Zombie unit scene. Includes NavigationAgent2D (radius 30), CollisionShape2D (radius 12), Sprite2D. |
| `human.tscn` | Human unit scene. Mirrors zombie structure. Add Waypoint1, Waypoint2... child Node2D nodes here for patrol routes. |
| `building.tscn` | Reusable building obstacle. Drag into levels and resize via CollisionShape2D orange handles. |
| `escape_zone.tscn` | Escape zone scene. Place at level exit points. |
| `debug_overlay.tscn` | Debug HUD overlay. Add to main scene as CanvasLayer. |
| `end_game_overlay.tscn` | End game screen overlay. Add to main scene as CanvasLayer. |
| `main.tscn` | Main test level scene. Contains Camera2D, SelectionManager, VisionRenderer, GameManager, Initializer, buildings, escape zones, and overlay UIs. |

---

### **Documentation Files (`docs/`)**

| File | Purpose |
|------|---------|
| `GAME_DESIGN_DOCUMENT.md` | Full game design doc v3.0. Core gameplay loop, zombie types, level design philosophy, tactical systems. |
| `PATROL_SYSTEM_ROADMAP.md` | Phase A/B/C roadmap for the sentry/patrol system. Current status and planned features. |
| `PHASE_A_COMPLETE.md` | Phase A completion notes — sentry degrees and swing arc system (v0.14.0). |
| `PATROL_QUICKSTART_PHASE_B1.md` | How to use the manual waypoint patrol system (Phase B1, v0.18.0). |
| `PATROL_PHASE_B2_VISUAL_WAYPOINTS.md` | How to use drag-and-drop visual waypoints via child Node2D (Phase B2, v0.19.0). |
| `NAVIGATION_SETUP_GUIDE.md` | How to set up NavigationRegion2D and bake a nav mesh for zombie pathfinding (v0.17.0). |
| `NAVIGATION_FINAL_SETUP.md` | Final configuration steps for navigation — layers, groups, agent radius (v0.17.3). |
| `NAVIGATION_TROUBLESHOOTING.md` | Common nav mesh issues and fixes. Covers Groups method, layer mismatches, manual polygon approach. |
| `DEBUG_LOGGING_GUIDE.md` | Reference for debug print statements in the codebase (v0.12.6). |
| `EXPORT_GUIDE.md` | How to export the game with a specific level as the main scene. |
| `2.5D_CONVERSION_PLAN.md` | Future consideration only — plan for converting to 2.5D with height gameplay. Not being implemented. |
| `BASELINE_SUMMARY.md` | Snapshot of v0.9.0 state. Historical reference only. |
| `BASELINE_SUMMARY_v0.12.4.md` | Snapshot of v0.12.4 stable baseline. Historical reference only. |
| `CHANGELOG_v0.9.1.md` through `CHANGELOG_v0.21.2.md` | Per-version change logs. Useful for understanding why decisions were made. |


---

## 🎯 **Key Systems Explained**

### **1. Navigation System (Optional)**

**How It Works:**
- NavigationAgent2D on zombies (optional)
- NavigationRegion2D in level with baked mesh
- If agent exists: use pathfinding
- If not: use direct movement

**Setup:**
1. Add NavigationRegion2D to level
2. Configure: Source Geometry Mode = "Groups"
3. Add buildings to "buildings" group
4. Set Agent Radius: 30.0
5. Bake NavigationPolygon
6. NavigationAgent2D already on zombie.tscn

**Common Issues:**
- Layers must match (both on Layer 1)
- Buildings need StaticBody2D with collision shapes
- Groups method most reliable in Godot 4.6

---

### **2. Patrol System**

**Two Methods:**

**Manual (Phase B1):**
```gdscript
// In Inspector:
Patrol Waypoints: [(100,100), (200,100), (200,200)]
```

**Visual (Phase B2 - Recommended):**
```
Human (Sentry)
├─ Waypoint1 (Node2D) ← Drag to position
├─ Waypoint2 (Node2D)
└─ Waypoint3 (Node2D)
```

**Naming Rules:**
- Must be exactly "Waypoint1", "Waypoint2", etc.
- Capital W, no underscores/spaces
- Numbers determine order (natural sort)

**Patrol Modes:**
- **LOOP:** Circular patrol (0→1→2→3→0)
- **PING_PONG:** Back-and-forth (0→1→2→3→2→1→0)

**Phase C — Per-Waypoint Behaviour:**
- `patrol_pause_durations: Array[float]` — seconds to pause at each waypoint (0.0 = no pause)
- `patrol_waypoint_swing: Array[bool]` — whether to swing the vision cone during the pause
- `patrol_waypoint_facing: Array[float]` — facing override on arrival (-1.0 = no override, 0–360°)
- Swing during pause works even if `sentry_has_swing` is globally false

**Example Phase C setup:**
```
patrol_pause_durations  = [0.0, 3.0, 0.0, 2.0]
patrol_waypoint_swing   = [false, true, false, false]
patrol_waypoint_facing  = [-1.0, -1.0, -1.0, 90.0]
→ Waypoint 1: walk through
→ Waypoint 2: pause 3s, swing vision cone
→ Waypoint 3: walk through
→ Waypoint 4: pause 2s, face East (90°)
```

**Formation Squads (v0.21.0):**
```
Leader (Human — has waypoints)
├─ Follower A  patrol_leader = Leader, formation_slot = 1
├─ Follower B  patrol_leader = Leader, formation_slot = 2
└─ Follower C  patrol_leader = Leader, formation_slot = 3
```
- Leader patrols normally; waits at each waypoint for followers to regroup
- Formation shapes: LINE_ABREAST, COLUMN, WEDGE, ECHELON, DIAMOND
- Followers go IDLE if leader dies
- Followers use ramped catch-up speed when out of position

---

### **3. Sentry System**

**Configuration:**
```gdscript
@export var sentry_facing_degrees: float = 0.0  // 0=North, 90=East
@export var sentry_has_swing: bool = false
@export var sentry_swing_range: float = 45.0    // ±45° sweep
@export var sentry_swing_speed: float = 30.0    // deg/sec
@export var sentry_swing_pause: float = 0.5     // pause at extremes
```

**Visual Indicators (Editor):**
- Cyan arrow: facing direction
- Green arc: swing range (if enabled)
- Yellow path: patrol waypoints (if patrol enabled)

**Swing Behavior:**
- Only active when stationary (not patrolling)
- Smooth sin/cos oscillation
- Pauses at extremes
- Speed modulation (faster in middle, slower at edges)

---

### **4. Panic / Morale System**

**Current implementation (to be replaced in v0.22.0):**
```gdscript
// Check nearby humans (40px radius)
if ally.current_state == GRAPPLED:
    panic()  // Only when actually pinned!
```

**Planned morale system (v0.22.0):**
- Every defender has a morale bar (morale_max varies by class)
- Stress events drain it: sighting (within weapon range for armed units), ally grappled, ally fleeing, ally killed
- Bar reaches 0 → primary response (flee or tunnel vision depending on class)
- Replaces propagate_flee_to_group() and panic_propagation_depth entirely
- See HUMAN_DEFENDER_SYSTEM_SPEC.md for full design and drain values

**Propagation Chain (current, v0.21.2 — being deprecated):**
- `panic_propagation_depth` export (default: 2) controls how many hops panic spreads
- Depth 0 = only direct detector flees
- Depth 1 = detector + immediate neighbours
- Depth 2 = two rings outward (default — recommended)
- Delay per ally is distance-based: ally 80px away = 0.4s delay, 5px away = ~0.025s

**Example (default depth 2, 80px propagation radius):**
```
Depth 0: Human A sees zombie → flees + propagates
Depth 1: B, C, D (within 80px of A) flee + propagate
Depth 2: E, F, G (within 80px of B/C/D) flee — CHAIN STOPS
Humans further than ~160px from contact: unaffected ✅
```

**Console debug output:**
- `PANIC MOB (depth 0): 4 humans fleeing together!`
- `🛑 PANIC CHAIN stopped at depth 2 for Human5`

---

## 🛠️ **Development Environment**

**Engine:** Godot 4.6 (latest version)  
**Platform:** 2D (isometric perspective)  
**Language:** GDScript  
**Location:** Amsterdam, North Holland, NL  

**Tools Used:**
- Claude.ai for development assistance
- Claude Code (occasionally)
- Git for version control (recommended)

---

## 📝 **Important Design Decisions**

### **Degrees vs Vectors:**
- Use degrees for sentry facing (more intuitive for designers)
- 0° = North/Up, 90° = East/Right, 180° = South, 270° = West
- Internally converts to Vector2 for calculations

### **Global vs Local Positions:**
- Always use `global_position` for calculations
- Avoids bugs with nested scene hierarchies
- Particularly important for escape zones

### **Formation-Based Movement:**
- BOID flocking prevents unit clumping
- Separation, cohesion, alignment forces
- Different strengths for different states (idle vs fleeing)

### **Vision System:**
- State-dependent (circle for idle, arc for moving)
- Line-of-sight raycasting to detect obstacles
- Group vision sharing for sentries

### **Optional Navigation:**
- Not required - direct movement works
- Opt-in per level via NavigationAgent2D
- Backwards compatible

---

## 🚀 **Next Steps / Roadmap**

### **Immediate (Integration Testing + First Validation Slice):**
- Complete integration testing of v0.22.x human defender system
- Tune morale/weapon values (kill counts currently higher than spec)
- Costume Zombie + Fat Zombie (first special zombie types)
- A handcrafted test level with Civilian, Militia, Police, GI, Spec Ops and both zombie types
- Validate core tactical puzzle loop is fun

### **Near-Term:**
- Building transformation system (zombies enter buildings to change type)
- More zombie types (11 planned total)
- More test levels

### **Long-Term:**
- Community level sharing
- Campaign mode
- Advanced puzzle mechanics

---

## 🐛 **Debugging Tips**

### **Navigation Not Working:**
```
1. Check console: "✓ HAS NavigationAgent2D" or "✗ NO"
2. Verify navigation layers match (both Layer 1)
3. Check buildings in "buildings" group
4. Verify StaticBody2D on buildings
5. Enable nav debug: nav_agent.debug_enabled = true
```

### **Patrol Not Working:**
```
1. Check: Patrol Enabled = ON
2. Verify waypoint names (Waypoint1, Waypoint2...)
3. Check console: "Loaded X waypoints"
4. Initial State must be SENTRY
```

### **Panic Not Spreading:**
```
1. Check spacing: <80px for propagation to work (propagation_radius = 80px)
2. Verify state: Must be GRAPPLED (not just chased)
3. Check panic_propagation_depth — default 2, set higher to test wider spread
4. Console: "PANIC MOB (depth X)" confirms chain is firing
5. Console: "🛑 PANIC CHAIN stopped at depth X" shows where it was cut off
```

### **Swing Arc Erratic:**
```
1. Should be disabled while patrolling (v0.19.4)
2. Only swings when stationary
3. Check: is_patrolling should be false for swing
```

---

## 📦 **Version History (Recent)**

**v0.22.6 (planned — integration testing)** - Full human defender system validation
**v0.22.5** - Zombie death visual: dark red color, 0.3s delay, shot knockback tween
**v0.22.4** - Tunnel Vision state: 22.5° locked cone, threat-facing, 10s, immune to drain
**v0.22.3** - Shooting system: aim timer, tracer line, LOS pause, weapon range gating
**v0.22.2** - Morale bar: sighting drain, ally event hooks, flee/tunnel vision response
**v0.22.1** - Vision range 350px, dual-zone arcs, camera zoom 1.0×/2.5× max
**v0.22.0** - Defender class scaffolding: DefenderClass enum, morale/weapon exports
**v0.21.3** - Bug fixes: flee fallback dead code, level_bounds.gd, boundary edge clamping, false stuck detection, formation bounds hardcode, patrol speed persisting into flee
**v0.21.2** - Depth-capped, distance-based panic propagation
**v0.21.1** - Formation follower polish: ramped catch-up speed, reduced separation while converging
**v0.21.0** - Formation squad patrols — leader/follower system with 5 formation shapes and regroup waiting
**v0.20.0** - Phase C patrol: per-waypoint pause durations, swing, and facing overrides  
**v0.19.5** - WorldBounds autoload singleton — centralised world bounds for units and camera  
**v0.19.4** - Removed visual waypoint markers (caused gameplay visibility issues)  
**v0.19.2** - Fixed waypoint order, swing during patrol  
**v0.19.0** - Phase B2: Visual waypoint placement  
**v0.18.0** - Phase B1: Basic patrol system  
**v0.17.3** - Navigation system complete  
**v0.17.0** - Panic spreading fixes  
**v0.16.0** - Panic spreading initial implementation  
**v0.15.0** - Escape zone global_position fix  
**v0.14.0** - Phase A: Sentry degrees and swing arcs  

---

## 📚 **Documentation Files**

**Available in /docs:**
- HUMAN_DEFENDER_SYSTEM_SPEC.md (new — v0.22.0 design)
- PATROL_PHASE_B2_VISUAL_WAYPOINTS.md
- PATROL_QUICKSTART_PHASE_B1.md
- PATROL_SYSTEM_ROADMAP.md
- NAVIGATION_SETUP_GUIDE.md
- NAVIGATION_TROUBLESHOOTING.md
- NAVIGATION_FINAL_SETUP.md
- CHANGELOG_v0.19.2.md (and others)
- PHASE_A_COMPLETE.md

---

## 🎯 **Starting a New Chat**

**Required Context (add all three to Project Knowledge):**
- `PROJECT_CONTEXT.md` — technical state, scripts inventory, known issues
- `CLAUDE_INSTRUCTIONS.md` — rules for working with Claude
- `GAME_DESIGN_DOCUMENT.md` — design intent, zombie types, level design rules

If using Project Knowledge these load automatically.
If starting a fresh project or new Claude account, attach all three manually.

**What to say:**
"I'm working on Dead Corps v0.21.2.
Ready to [specific task or question]"

**Claude will have:**
- Full technical context from PROJECT_CONTEXT.md
- Design intent from the GDD
- Workflow rules to follow
- Scripts inventory to prevent naming conflicts

**What Claude Won't Have Without Prompting:**
- Exact code from previous sessions (paste if needed)
- Specific bug details from old conversations
- Your current level/scene setup details

---

## 💡 **Key Terminology**

**Sentry:** Human guard with directional vision and optional swing arc  
**Waypoint:** Position marker for patrol routes  
**BOID:** Flocking algorithm (separation, cohesion, alignment)  
**Grappled:** Human pinned by zombie (being attacked)  
**Panic Spreading:** Current system — nearby humans flee when ally grappled (being replaced by morale system)  
**Morale Bar:** Planned v0.22.0 system — continuous drain from stress events, replaces panic spreading  
**Navigation Mesh:** Pathfinding data structure (blue areas in editor)  
**Phase A/B/C:** Development phases for patrol system  
**LOOP/PING_PONG:** Patrol modes (circular vs back-and-forth)  
**Tunnel Vision:** Planned v0.22.0 GI/Spec Ops response — locked rotation, narrowed 45° cone, 10s duration

---

## 🔧 **Common Commands**

**Test Navigation:**
```
Debug → Visible Collision Shapes
Debug → Visible Navigation
```

**Check Zombie Has Navigation:**
```gdscript
// Console output on game start:
"✓ HAS NavigationAgent2D"
```

**Check Patrol Loaded:**
```gdscript
// Console output:
"Loaded 4 waypoints from child nodes for Human1"
"Patrol initialized for Human1 with 4 waypoints"
```

---

## 📞 **Quick Reference**

**Zombie States:**
- IDLE (circle vision)
- MOVING (forward arc)
- PURSUING (forward arc, locked)
- LEAPING (speed boost)
- MELEE (attacking)

**Human States:**
- IDLE (circle vision)
- SENTRY (arc vision, stationary or patrol)
- FLEEING (forward arc, running)
- GRAPPLED (no vision, pinned)
- DEAD (incubating zombie)
- TUNNEL_VISION (GI/Spec Ops — 22.5° locked orange cone, 10s, threat-facing)
- FREEZE (designed, deferred — Civilian only)
- MELEE_CHARGE (designed, deferred — Militia only)

**Collision Layers:**
- Layer 1: Buildings/Obstacles
- Layer 2: Zombies
- Layer 3: Humans (implied from team system)

**Default Values:**
- Zombie radius: 12px
- Human radius: 12px
- Morale event radius: 150px (ally grappled/fleeing/killed hooks)
- Navigation agent radius: 30px
- Patrol speed: 50 px/sec
- Swing range: 45°
- Swing speed: 30°/sec
- Formation spacing: 40px
- Formation regroup timeout: 10s
- Human vision (SENTRY/FLEEING): 350px arc, 90°
- Human vision (IDLE): 100px circle
- Tunnel Vision cone: 22.5°, duration: 10s
- Morale recovery on flee/tunnel vision end: 50% of morale_max
- Dead zombie color: Color(0.4, 0.0, 0.0)
- Dead human color: Color(0.8, 0.2, 0.2)
- Shot knockback: 8px tween over 0.15s
- Camera default zoom: 1.0× (debug), target game zoom: 2.5×
- Window: 1920×1080 windowed

**Planned values (tuning pass — post integration testing):**
- Kill counts per class (currently higher than spec — morale/aim values need tuning)

**Weapon Stats:**
- Civilian: unarmed
- Militia: shotgun, 150px range, 0.7s aim time
- Police: pistol, 150px range, 0.55s aim time
- GI: assault rifle, 250px range, 0.525s aim time
- Spec Ops: assault rifle, 250px range, 0.26s aim time

**Morale Stats:**

| Unit | Max | Sighting/sec | Grappled | Fleeing | Killed |
|------|-----|-------------|----------|---------|--------|
| Civilian | 65 | 30 | 100 | 50 | 150 |
| Militia | 150 | 35 | 100 | 40 | 150 |
| Police | 200 | 0 | 100 | 40 | 150 |
| GI | 400 | 0 | 275 | 20 | 150 |
| Spec Ops | 1000 | 0 | 100 | 0 | 150 |

---

## ⚙️ **Technical Notes**

**Engine Quirks (Godot 4.6):**
- Navigation baking changed significantly from 4.2
- Use "Groups" method for most reliable baking
- `Engine.is_editor_hint()` critical for @tool scripts
- `naturalnocasecmp_to()` for proper number sorting

**Performance:**
- Detection checks every 0.2s (not every frame)
- Vision raycasts cached and optimized
- BOID forces computed per unit per frame

**Code Style:**
- Type hints used: `var distance: float`
- Explicit nullability: `var target: Node2D = null`
- Comments explain "why" not "what"
- Functions document parameters and return values

---

## 🎨 **Asset Notes**

**Current Visuals:**
- Simple colored rectangles (placeholders)
- Zombies: Green-ish (Color 0.4, 0.6, 0.3)
- Humans: [default CharacterBody2D]
- Buildings: StaticBody2D with collision shapes
- All 2D isometric perspective

**Planned:**
- Proper sprite artwork
- Animations
- Particle effects
- UI polish

---

**END OF CONTEXT DOCUMENT**

*This document should be updated after major changes or new feature implementations.*
*Store in Google Drive for easy access across conversations.*
*Filename suggestion: `DeadCorps_Context_v0.21.2.md`*
