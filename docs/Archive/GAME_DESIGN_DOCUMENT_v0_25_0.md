# DEAD CORPS - DESIGN DOCUMENT

**Version:** 6.0 (Advanced Prototype Build)  
**Last Updated:** April 21, 2026  
**Status:** Prototype v0.25.0

---

## TABLE OF CONTENTS

1. [Game Overview](#1-game-overview)
2. [Current Prototype State (v0.21.2)](#2-current-prototype-state-v0212)
3. [Core Mechanics](#3-core-mechanics)
4. [Technical Specifications](#4-technical-specifications)
5. [Special Zombie Types (11 Total)](#5-special-zombie-types-11-total)
6. [Human Defenders](#6-human-defenders)
7. [Building System](#7-building-system)
8. [Level Design Philosophy](#8-level-design-philosophy)
9. [Future Features](#9-future-features)
10. [Original Ideas Not Yet Implemented](#10-original-ideas-not-yet-implemented)
11. [Design Philosophy & Decisions](#11-design-philosophy--decisions)
12. [Open Questions & Design Gaps](#12-open-questions--design-gaps)

---

## 1. GAME OVERVIEW

### 1.1 Core Concept

**Dead Corps** is a real-time tactical puzzle game where players command a growing zombie horde. The game inverts traditional zombie survival dynamics: instead of defending against zombies, you ARE the zombie apocalypse.

**Key Pillars:**
- **Growth Through Combat:** Defeated humans become zombies (snowball mechanic)
- **Tactical Puzzle Solving:** Use terrain, timing, and special zombie abilities to overcome defenders
- **Environmental Problem-Solving:** Different zombie types unlock new tactical options
- **Risk vs Reward:** Keep zombies alive for higher scores

### 1.2 Genre

Real-time strategy with strong tactical puzzle elements. Similar to:
- **Commandos / Shadow Tactics** - Tactical positioning and timing
- **Pikmin** - Unit conversion and growing army
- **Lemmings** - Environmental puzzle solving with limited control

### 1.3 Platform & Engine

- **Engine:** Godot 4.6 (updated from 4.3)
- **Platform:** PC (Windows/Linux/Mac)
- **Perspective:** 2D Isometric (top-down, 45-degree angle)
- **Target:** Single-player campaign (multiplayer post-launch consideration)

---

## 2. CURRENT PROTOTYPE STATE (v0.21.2)

### 2.1 Implemented Features ✅

**Core Systems:**
- ✅ RTS-style camera (WASD panning, edge scrolling, zoom)
- ✅ Unit selection (click, box-select, Shift/Ctrl modifiers)
- ✅ Formation movement (shambling horde with randomization)
- ✅ Control groups (Ctrl+1-9 to assign, 1-9 to recall)
- ✅ Zombie-human combat with conversion
- ✅ Game boundaries and collision
- ✅ WorldBounds autoload singleton (v0.19.5) — single source of truth for level size

**AI & Behavior:**
- ✅ Human flee mechanics (reaction time, threat vectors, obstacle avoidance)
- ✅ Player-controlled engagement (v0.25.0) — no auto-pursuit; right-click initiates attacks
- ✅ Group engagement resolver — greedy bipartite assignment, max 2 zombies per human, 150px group radius
- ✅ Post-kill continuation — zombie auto-finds next target within 250px LOS on kill
- ✅ Smart target selection (prioritizes unpinned humans)
- ✅ Stuck detection and retargeting
- ✅ Max 2 attackers per human (v0.25.0 — down from 3; enforced by group resolver and melee slot system)
- ✅ BOID separation (visual spacing without collision)

**Advanced Mechanics:**
- ✅ Hybrid leap system (speed boost + guaranteed pin at 40px)
- ✅ Line-of-sight blocking (buildings obstruct vision)
- ✅ Escape zone (humans run to safety, zombies die if entering)
- ✅ Pursuing zombies (LEAPING/MELEE states) cannot be redirected mid-commitment

**NEW: Vision System (v0.14.0+):**
- ✅ State-based vision shapes (circle for idle, arc for moving/pursuing)
- ✅ Zombie vision responds to movement commands
- ✅ Vision arc renderer with alpha gradient

**NEW: Sentry System (v0.14.0 - Phase A):**
- ✅ Degree-based sentry facing (0° = North, 90° = East, 180° = South, 270° = West)
- ✅ Visual facing arrow in editor (cyan)
- ✅ Swing arc system for sentries
  - Smooth sin/cos oscillation
  - Configurable swing range (±degrees from center)
  - Configurable swing speed (degrees per second)
  - Pause at extremes (configurable duration)
  - Visual swing arc indicator in editor (green)
- ✅ Arc vision during sentry state

**NEW: Panic Spreading (v0.16.0 - v0.21.2):**
- ✅ Proximity-based panic (40px grapple check)
- ✅ Triggers only on GRAPPLED state (not chase)
- ✅ Depth-capped propagation chain (default: 2 hops, configurable via `panic_propagation_depth`)
- ✅ Distance-based cascade delays (near allies react sooner than far ones)
- ✅ Global position fixes for escape zones
- ✅ Line-of-sight requirement for escape zone selection

**NEW: Zombie Navigation (v0.17.0 - v0.17.3):**
- ✅ Optional NavigationAgent2D support
- ✅ Pathfinding around obstacles
- ✅ Smooth corner navigation (30px agent radius)
- ✅ Falls back to direct movement if not configured
- ✅ Works for both combat and normal movement
- ✅ Backwards compatible (navigation is opt-in per level)

**NEW: Patrol System Phase B1 (v0.18.0):**
- ✅ Manual waypoint patrol (typed coordinates in Inspector)
- ✅ LOOP mode (circular: 0→1→2→3→0)
- ✅ PING_PONG mode (back-and-forth: 0→1→2→3→2→1→0)
- ✅ Visual waypoint path in editor (yellow dots/lines)
- ✅ Configurable patrol speed (independent of combat speed)
- ✅ Patrol stops when zombie detected (switches to fleeing)

**NEW: Patrol System Phase B2 (v0.19.0 - v0.19.4):**
- ✅ Visual waypoint placement via child Node2D nodes
- ✅ Natural string sorting (handles Waypoint1-10+ correctly)
- ✅ Drag-and-drop waypoint positioning in editor
- ✅ Backwards compatible with manual waypoint arrays
- ✅ Swing disabled while patrolling (clean movement)
- ✅ Sentries face movement direction while walking
- ✅ No editor movement (game logic disabled during editing)

**NEW: Patrol System Phase C (v0.20.0):**
- ✅ Per-waypoint pause durations (`patrol_pause_durations: Array[float]`)
- ✅ Per-waypoint swing during pause (`patrol_waypoint_swing: Array[bool]`)
- ✅ Per-waypoint facing overrides (`patrol_waypoint_facing: Array[float]`, -1.0 = no override)
- ✅ Swing during pause works even if `sentry_has_swing` globally false
- ✅ Fully backwards compatible — empty arrays = Phase B2 behaviour unchanged

**NEW: Formation Squad Patrols (v0.21.0 - v0.21.1):**
- ✅ Leader/follower system: followers hold NodePath to leader, take a numbered slot
- ✅ Five formation shapes: LINE_ABREAST, COLUMN, WEDGE, ECHELON, DIAMOND
- ✅ Configurable spacing (`formation_spacing`, default 40px) and regroup timeout (`formation_regroup_timeout`, default 10s)
- ✅ Leader waits at each waypoint for followers to regroup before advancing
- ✅ Followers ramp speed to catch up when out of position (1.0–1.5× multiplier)
- ✅ Reduced BOID separation while converging to prevent jostling
- ✅ Followers go IDLE if leader dies
- ✅ Fully backwards compatible — empty `patrol_leader` = standalone sentry, unchanged

**Polish & UI:**
- ✅ Inspector export groups on Human and Unit (cleaner Inspector layout)
- ✅ End game screen with score breakdown
- ✅ Scoring system (25pts regular zombie survived, 100pts special zombie survived + time bonuses)
- ✅ Reset button for rapid iteration
- ✅ Control group visual indicators
- ✅ Health bars and selection rings

**Human Defender System (v0.22.0–v0.22.5):**
- ✅ Five defender classes: Civilian, Militia, Police, GI, Spec Ops
- ✅ Morale bar replacing binary flee trigger and depth-capped propagation
- ✅ Shooting system: per-class weapons, aim time, tracer lines
- ✅ Dual-zone vision arcs (detection zone + shooting zone)
- ✅ Tunnel Vision state: 22.5° threat-facing cone, 10s, GI/Spec Ops
- ✅ Zombie death visual: dark red, 0.3s delay, shot knockback tween
- ✅ Vision range: SENTRY/FLEEING arcs 350px
- ⚠️ Kill count tuning deferred — values higher than spec, needs playtesting

**Alert System (v0.23.0–v0.23.1):**
- ✅ Low urgency detection alert: 5s cone timer, per-class side-aware offsets, smooth rotation
- ✅ High urgency unified system: ally grappled (75px), ally killed (75px), gunshot (150px)
- ✅ All high urgency: direct facing, 0.4s delay, 2s shared cooldown, 2s hold

**Special Zombies (v0.24.0–v0.24.1):**
- ✅ `is_special` flag on Zombie base class — disables leap, post-kill continuation, pack recruitment
- ✅ **Fat Zombie:** gunshot-only death, spawns permanent `FatZombieCorpse` obstacle (blocks movement + LOS like a building); no corpse on escape zone exit
- ✅ **Costume Zombie:** fully undetectable (`is_costumed = true`) across all human detection systems; disguise breaks permanently when zombie pins a human (GRAPPLED state); reverts to full regular zombie behaviour after break
- ✅ Scoring: special zombies worth 100pts, regular zombies 25pts
- ⚠️ Edge case: CostumeZombie sets `is_special = false` on disguise break — a broken-disguise Costume Zombie scores 25pts at end of game, not 100pts. Pending design decision on whether this is intended.

**Player-Controlled Engagement (v0.25.0):**
- ✅ Zombies never auto-pursue — all engagements are player-initiated via right-click
- ✅ Group engagement resolver: greedy bipartite assignment, max 2 per human, 150px group radius
- ✅ Post-kill continuation: 250px LOS scan, re-engages nearest available human
- ✅ Commitment model: PURSUING freely redirectable; LEAPING/MELEE locked until kill
- ✅ Zombie vision arcs removed — arcs are human-only visual language

### 2.2 Not Yet Implemented ❌

- ❌ Special zombie types (9 remaining — Fat Zombie and Costume Zombie implemented; 9 of 11 still planned)
- ❌ Building interaction system (transformation mechanic)
- ❌ Multiple level designs
- ❌ Campaign structure
- ❌ Environmental hazards (water, fire, spikes)
- ❌ Sound and music
- ❌ Final art style
- ❌ 3D migration (confirmed architectural direction — see Section 11)

### 2.3 Version History

**Foundation (v0.1-0.6):**
- Core systems (camera, selection, combat, conversion, flee AI)

**Polish Pass (v0.7-v0.8):**
- Hybrid leap, scoring, end game, control groups, escape zones
- Formation movement, AI improvements, smart targeting

**Vision & Sentry (v0.9-v0.14.0):**
- State-based vision system
- Degree-based sentry facing
- Swing arc mechanics
- Editor visual indicators

**Human AI Expansion (v0.15.0-v0.17.0):**
- Panic spreading system
- Escape zone improvements (global_position, LOS)
- Navigation system implementation

**Patrol System (v0.18.0-v0.19.5):**
- Phase B1: Manual waypoint patrol (typed arrays)
- Phase B2: Visual waypoints (child nodes)
- Swing/patrol integration fixes
- Editor behaviour fixes
- WorldBounds autoload singleton (v0.19.5)

**Patrol Phase C + Formations (v0.20.0-v0.21.2):**
- Phase C: Per-waypoint pause, swing, and facing overrides (v0.20.0)
- Inspector export groups on Human and Unit (v0.20.0)
- Formation squad patrols with leader/follower system and 5 shapes (v0.21.0)
- Formation follower polish: ramped catch-up speed, convergence BOID reduction (v0.21.1)
- Depth-capped, distance-based panic propagation (v0.21.2)

**Human Defender System (v0.22.0-v0.23.1):**
- Five defender classes with morale bar, shooting system, dual-zone vision arcs (v0.22.0–v0.22.5)
- Low urgency detection alert: 5s cone timer, per-class side-aware facing offsets (v0.23.0)
- High urgency unified alert: ally grappled/killed/gunshot, direct facing, 2s cooldown (v0.23.1)

**Special Zombies + Engagement Redesign (v0.24.0-v0.25.0):**
- Fat Zombie: gunshot-only death, permanent corpse obstacle (v0.24.0)
- Costume Zombie: full invisibility until pin, permanent disguise break (v0.24.1)
- Player-controlled engagement: no auto-pursuit, group resolver, post-kill continuation (v0.25.0)

---

## 3. CORE MECHANICS

### 3.1 Camera & Controls

**Camera**
- **Type:** 2D Isometric (fixed 45° angle)
- **Movement:** WASD keys OR mouse edge scrolling
- **Zoom:** Mouse wheel (currently disabled in prototype)
- **Bounds:** Camera clamped to level boundaries (±500 units)
- **Rotation:** Not implemented (may add 90° snapping later)

**Controls**
- **Select Units:** Left-click (single) OR drag-select (box)
- **Add to Selection:** Shift + left-click/drag
- **Remove from Selection:** Ctrl + left-click
- **Move Units:** Right-click on ground (formation spread with ±15px jitter)
- **Attack Enemy:** Right-click on human
- **Control Groups:** Ctrl+1-9 to assign, 1-9 to recall, Ctrl+0 to clear
- **Reset Level:** R key (debug feature)

### 3.2 Unit Selection

**Selection Feedback:**
- Green ring at unit's feet when selected
- Box-select draws green rectangle
- Control group number displayed in top-right of unit (1-9)

**Selection Rules:**
- Can select multiple units simultaneously
- Shift adds/removes from selection (toggle)
- Clicking empty space clears selection
- Control groups persist until reassigned or units die

### 3.3 Movement System

**Formation Movement**

When commanding multiple zombies:
1. Calculate grid formation centered on click point
2. Add random jitter (±15px) to each position
3. Each zombie gets individual target position
4. Result: Shambling horde (not regimented ranks)

**Example:** 9 zombies clicking at (100, 100) with 40px spacing:
```
[60+jitter, 60+jitter]  [100+jitter, 60+jitter]  [140+jitter, 60+jitter]
[60+jitter, 100+jitter] [100+jitter, 100+jitter] [140+jitter, 100+jitter]
[60+jitter, 140+jitter] [100+jitter, 140+jitter] [140+jitter, 140+jitter]
```

**Pursuit Lock**

**CRITICAL RULE:** Zombies in pursuit CANNOT be commanded!
- Idle zombie (no target) → Responds to player commands
- Pursuing zombie (has target) → **Ignores** player commands
- Only when target is killed/lost → Zombie becomes controllable again

This forces tactical positioning and prevents micromanagement during chases.

**Unit Speed**
- **Humans:** 90 units/second (fleeing)
- **Zombies:** 105 units/second (chasing)
- **Zombie Leap:** 210 units/second (2x multiplier at 40px range)
- **Patrol Speed:** 50 units/second (configurable, default for sentries)

Result: Zombies slowly catch humans, leap closes final distance.

### 3.4 Combat System

**Zombie Combat (v0.25.0)**

Zombies never auto-pursue. All engagements are player-initiated via right-click.

**Attack Command:**
- Right-click a human with zombies selected
- Group resolver finds all humans within 150px of the click target
- Zombies distributed via greedy bipartite assignment: nearest zombie to nearest human, max 2 per human
- Overflow zombies (beyond 2× human count) move to the clicked position

**Commitment States:**
- PURSUING (chasing) → player can redirect to a different target at any time
- LEAPING or MELEE (grappled/in contact) → committed until target dies, then control returns

**Post-Kill Continuation:**
1. Zombie's target dies
2. Zombie scans 250px radius for nearest living human with clear LOS (building check only, no vision arc)
3. If found: re-engages automatically
4. If not found: returns to IDLE, awaits player input

**Human Combat**

**Flee Behavior:**

When human detects zombie (150px range):
1. **Reaction delay:** 0.2 second freeze (fear/surprise)
2. **Calculate threat vector:** Away from ALL nearby zombies (weighted by distance)
3. **Obstacle avoidance:** Raycast ahead, veer around buildings
4. **Escape zone seeking:** If within 200px + line-of-sight → pull toward closest edge

**Flee Mechanics:**
- Detection radius: 150px
- Flee distance: Runs 200px away from threats
- Checks every 0.3 seconds (performance optimization)
- Only flees from visible zombies (line-of-sight matters)

**Grapple/Pin:**
- When zombie within 50px → human grappled (frozen for 0.5 seconds)
- Leap grapple (40px trigger) → immediate pin
- Timer-based: grapple_timer counts down, human escapes if zombie moves away

**Panic Spreading (v0.16.0 - v0.21.2) — being replaced in v0.22.0:**

Current implementation uses a depth-capped propagation chain (`propagate_flee_to_group()`, default 2 hops, 150px event radius). This is being deprecated and replaced by the morale system below.

**Morale System (v0.22.0 — designed, not yet implemented):**

Every defender has a morale bar (`morale_max` varies by class). Stress events drain it continuously or in flat hits. When it reaches zero the unit executes its primary response.

Drain events:
- **Sighting (continuous /sec):** Armed units drain only within weapon range. Civilians drain at full vision range (350px). Stacks per visible zombie.
- **Ally grappled (flat hit):** One-time drain when nearby ally transitions to GRAPPLED. Radius: 80px.
- **Ally fleeing (flat hit):** One-time drain when fleeing ally moves through vicinity. Radius: 80px.
- **Ally killed (flat hit):** One-time drain on nearby ally death. Radius: 80px.

Morale values by class:

| Unit | Morale Max | Sighting (/sec) | Ally grappled | Ally fleeing | Ally killed |
|------|-----------|----------------|---------------|--------------|-------------|
| Civilian | 65 | 30 | 100 | 50 | 150 |
| Militia | 150 | 35 | 100 | 40 | 150 |
| Police | 200 | 0 | 100 | 40 | 150 |
| GI | 400 | 0 | 275 | 20 | 150 |
| Spec Ops | 1000 | 0 | 100 | 0 | 150 |

Primary responses when morale empties:
- Civilian, Militia, Police → Flee
- GI, Spec Ops → Tunnel Vision (10s, threat-facing, 22.5° cone)

**Combat:**

Armed units shoot within their vision cone. See Section 6.1 for per-class weapon stats.
- One-shot kills (50 damage)
- Aim timer starts on target acquisition, fires when it reaches zero
- Buildings block shots (LOS raycast)
- No shooting while fleeing
- Tracer line drawn on firing, fades over 0.1s

### 3.5 Line of Sight System

**Buildings block vision:**
- Humans only flee from zombies they can see
- Raycasting checks for building obstruction
- Creates tactical sneaking opportunities

**Zombie Detection:**
- Zombies detect humans through buildings (simpler AI)
- Humans use LOS for flee decisions
- Escape zone seeking requires LOS to zone

### 3.6 Vision System (NEW - v0.14.0+)

**State-Based Vision Shapes:**

**Zombies:**
- IDLE state → Circle vision (360°, 100px radius)
- MOVING state → Forward arc vision (90°, 150px range)
- PURSUING state → Forward arc vision (90°, 150px range)
- Transitions automatically based on movement/targeting

**Humans (v0.22.0 — updated ranges):**
- IDLE state → Circle vision (360°, 100px radius)
- SENTRY state → Forward arc vision (90°, 350px range)
- FLEEING state → Forward arc vision (90°, 350px range)
- TUNNEL VISION state → Locked arc (22.5°, 350px range) — GI/Spec Ops only

**Dual-Zone Vision Arc (v0.22.0):**

Human arcs display two zones similar to Shadow Tactics viewcones:
- **Outer zone (detection, 350px):** Light/transparent fill. Aim timer activates here. Morale drain does NOT activate here for armed units.
- **Inner zone (shooting range):** Solid/brighter fill. Both aim timer and morale drain active here.
  - Militia/Police inner zone: 150px
  - GI/Spec Ops inner zone: 250px
  - Civilian: single zone only (morale drains across full 350px)

**Visual Rendering:**
- Vision areas drawn with alpha gradient (transparent to solid)
- Green for zombies, blue for humans (future: team colors)
- Arcs show facing direction clearly
- Dual-zone arcs communicate threat range vs detection range at a glance

### 3.7 Sentry System (NEW - v0.14.0)

**Degree-Based Facing:**
- 0° = North (up)
- 90° = East (right)
- 180° = South (down)
- 270° = West (left)
- Configurable in Inspector per sentry

**Swing Arc Mechanics:**
- **Purpose:** Sentry scans area by swinging head left/right
- **Configuration:**
  - `sentry_swing_range`: How far to look (±degrees, e.g., ±45° = 90° total sweep)
  - `sentry_swing_speed`: How fast to swing (degrees per second)
  - `sentry_swing_pause`: Pause duration at extremes (seconds)
- **Behavior:**
  - Smooth sin/cos oscillation (not linear)
  - Speed modulation (faster in middle, slower at edges)
  - Pauses at extremes before reversing
- **Integration with Patrol (v0.19.0+):**
  - Swing only when stationary (not while walking)
  - While patrolling, face movement direction
  - Phase C (v0.20.0) added per-waypoint swing: pause at a waypoint to swing and look around

**Editor Visualization:**
- Cyan arrow: Shows initial facing direction
- Green arc: Shows swing range (if enabled)
- Yellow path: Shows patrol waypoints (if patrol enabled)

### 3.8 Patrol System (NEW - v0.18.0+)

**Patrol Modes:**

**LOOP Mode:**
- Circular patrol: Waypoint 0 → 1 → 2 → 3 → 0 → ...
- Never reverses direction
- Good for: Perimeter patrols, guard rounds

**PING_PONG Mode:**
- Back-and-forth: 0 → 1 → 2 → 3 → 2 → 1 → 0 → ...
- Reverses at endpoints
- Good for: Hallway patrols, corridor routes

**Waypoint Configuration:**

**Method 1: Manual (Phase B1 - v0.18.0):**
```gdscript
// In Inspector:
@export var patrol_waypoints: Array[Vector2] = [(100,100), (200,100), (200,200)]
```

**Method 2: Visual (Phase B2 - v0.19.0 - Recommended):**
```
Human (Sentry)
├─ Waypoint1 (Node2D)  ← Drag to position in editor
├─ Waypoint2 (Node2D)
├─ Waypoint3 (Node2D)
└─ Waypoint4 (Node2D)
```

**Naming Rules:**
- Must be exactly "Waypoint1", "Waypoint2", etc.
- Capital W, numbers determine order
- Natural sort (handles Waypoint1-10+ correctly)

**Patrol Behavior:**
- Walks at `patrol_speed` (default 50 px/sec)
- Faces movement direction while walking
- Stops patrolling when zombie detected (switches to fleeing)
- Swing disabled while moving (only when stationary or paused at waypoint)
- Does not resume patrol after threat (by design — clear consequence)

**Editor Features:**
- Yellow dots show waypoint positions
- Yellow lines connect waypoints showing patrol path
- Visible when sentry selected

**Phase C — Per-Waypoint Behaviour (v0.20.0):**

Each waypoint can now have independent behaviour configured via three parallel arrays:

```gdscript
@export var patrol_pause_durations:  Array[float]  // seconds to pause (0.0 = pass through)
@export var patrol_waypoint_swing:   Array[bool]   // swing vision cone during pause?
@export var patrol_waypoint_facing:  Array[float]  // facing override on arrival (-1.0 = none)
```

Example:
```
Waypoint 0 → walk through (no pause)
Waypoint 1 → pause 3s, swing vision cone
Waypoint 2 → walk through
Waypoint 3 → pause 2s, face East (90°), no swing
```

- Swing during pause works even if `sentry_has_swing` is globally false
- Backwards compatible: empty arrays = Phase B2 behaviour unchanged

**Formation Squad Patrols (v0.21.0):**

One human leads a patrol route; others follow in formation.

```
Leader (has waypoints)
├─ Follower A  patrol_leader = Leader, formation_slot = 1
├─ Follower B  patrol_leader = Leader, formation_slot = 2
└─ Follower C  patrol_leader = Leader, formation_slot = 3
```

**Formation Shapes:** LINE_ABREAST, COLUMN, WEDGE, ECHELON, DIAMOND

**Behaviour:**
- Leader patrols normally, waiting at each waypoint (after Phase C pause) for followers to regroup
- Followers use ramped catch-up speed (1.0–1.5×) when out of position
- BOID separation reduced during convergence to prevent jostling
- Followers go IDLE if leader dies (`is_instance_valid` guard)
- Backwards compatible: `patrol_leader` empty = standalone sentry unchanged

**Tactical implications:**
- Formation shape affects how much of the map is visible at once
- Whole squad reacts together to zombie sightings (propagation within 80px)
- Killing the leader disrupts the formation without killing every follower

### 3.9 Navigation System (NEW - v0.17.0+)

**Optional Pathfinding:**
- NavigationAgent2D on zombies (optional)
- NavigationRegion2D in level with baked mesh
- If agent exists: use pathfinding
- If not: use direct movement

**How It Works:**
1. Add NavigationRegion2D to level
2. Add buildings to "buildings" group
3. Configure: Source Geometry Mode = "Groups"
4. Set Agent Radius: 30.0 (wide clearance)
5. Bake NavigationPolygon
6. NavigationAgent2D already on zombie.tscn

**Benefits:**
- Zombies path around buildings smoothly
- Smooth corner navigation
- No getting stuck on obstacles
- Backwards compatible (levels without navigation work fine)

**Technical Details:**
- Agent radius: 30px (wide clearance from walls)
- Cell size: 10px (grid precision)
- Navigation layers must match (both on Layer 1)
- Groups method most reliable in Godot 4.6

### 3.10 Conversion Mechanic

**Core Snowball Loop:**
1. Zombie kills human (health reaches 0)
2. Human enters DEAD state — 5-second incubation timer begins
3. After 5 seconds, GameManager spawns new zombie at the human's position
4. New zombie immediately under player control

**Incubation note:** Dead humans remain on the map for 5 seconds before converting. They are counted as part of the zombie total for scoring and lose condition checks during this period.

**Score Impact:**
- More zombies alive at end = higher score
- Encourages keeping zombies alive (tactical play)

### 3.11 Win/Lose Conditions

**Victory:**
- All humans killed OR escaped
- Shows "GAME OVER" screen

**Defeat:**
- All zombies dead + humans still alive
- Shows "YOU LOSE - All your zombies died"

**Scoring:**
- 25 points per regular zombie survived (including starting zombies)
- 100 points per special zombie survived (Fat Zombie, Costume Zombie)
- Note: CostumeZombie sets `is_special = false` on disguise break — a broken-disguise Costume Zombie scores 25pts, not 100pts
- Time bonuses:
  - ≤1 min: +200
  - ≤2 min: +150
  - ≤3 min: +100
  - ≤4 min: +50
  - >4 min: +0
- Humans escaped: 0 points (tracked for stats)
- Loss: 0 points total

---

## 4. TECHNICAL SPECIFICATIONS

### 4.1 Zombie Stats
```
Health: 50
Move Speed: 105 units/sec
Attack Damage: 15
Attack Range: 25 pixels
Attack Cooldown: 1.5 seconds
Auto-Pursuit Range: 100 pixels
Leap Range: 40 pixels
Leap Speed Multiplier: 2.0x (105 → 210)
Leap Pin Range: 40 pixels (guaranteed grapple)
Vision (Idle): 100px circle
Vision (Moving): 150px arc, 90° angle
```

### 4.2 Human Stats
```
Health: 75
Move Speed: 90 units/sec
Patrol Speed: 50 units/sec (default for sentries)
Flee Detection Radius: 150 pixels
Flee Distance: 200 pixels
Reaction Time: 0.2 seconds
Detection Check Interval: 0.3 seconds
Grapple Duration: 0.5 seconds
Grapple Proximity: 50 pixels (normal), 70 pixels (during leap)
Escape Zone Seek Range: 200 pixels
Morale Drain Radius: 80 pixels (v0.22.0 — replaces 40px panic radius)
Vision (Idle): 100px circle
Vision (Sentry): 350px arc, 90° angle (was 180px — updated v0.22.0)
Vision (Fleeing): 350px arc, 90° angle (was 100px — updated v0.22.0)
Vision (Tunnel Vision): 350px arc, 22.5° angle, threat-facing, 10s duration
```

**Weapon Stats (v0.22.0):**
```
Civilian: Unarmed
Militia: Shotgun, 150px range, 0.7s aim time, 50 damage (one-shot kill)
Police: Pistol, 150px range, 0.55s aim time, 50 damage (one-shot kill)
GI: Assault Rifle, 250px range, 0.525s aim time, 50 damage (one-shot kill)
Spec Ops: Assault Rifle, 250px range, 0.26s aim time, 50 damage (one-shot kill)
```

### 4.3 Sentry Configuration (NEW)
```
Facing: 0-360 degrees (0=North, 90=East, 180=South, 270=West)
Swing Range: 0-90 degrees (±from center, e.g., ±45° = 90° total sweep)
Swing Speed: 1-180 degrees/second (default: 30°/sec)
Swing Pause: 0-2 seconds (default: 0.5 sec)
```

### 4.4 Patrol Configuration (NEW)
```
Patrol Mode: LOOP or PING_PONG
Patrol Speed: 10-100 px/sec (default: 50)
Waypoint Proximity: 10 pixels (reached threshold)
Waypoint Count: Unlimited (practical max ~20)
```

### 4.5 Navigation Configuration (NEW)
```
Agent Radius: 30 pixels (zombie clearance from walls)
Cell Size: 10 pixels (grid precision)
Path Desired Distance: 15 pixels
Target Desired Distance: 20 pixels
Navigation Layers: Layer 1 (must match region and agent)
```

### 4.6 BOID Separation
```
Separation Radius: 30 pixels
Separation Strength: 100 (force magnitude)
Falloff: Squared (more aggressive when close)
Disabled For: Melee attackers (prevents bumping)
```

### 4.7 Formation Parameters
```
Base Spacing: 40 pixels
Jitter Range: ±15 pixels (X and Y)
Grid Layout: Square (sqrt of unit count)
Centering: Formation centered on click point
Bounds Clamping: Positions clamped to ±500 units
```

### 4.8 Collision Layers
```
Layer 1 (Buildings): Blocks movement, blocks LOS, used for navigation
Layer 2 (Zombies): No unit-unit collision, BOID separation only
Layer 3 (Humans): No unit-unit collision, BOID separation only
```

### 4.9 Game Boundaries
```
World Bounds: X: -500 to +500, Y: -500 to +500
Camera Bounds: Matches world bounds
Unit Clamping: Position clamped every physics frame
```

### 4.10 Performance Targets
```
Target Unit Count: 50-100 total units (zombies + humans)
Physics Updates: 60 FPS (fixed timestep)
Pathfinding: NavigationAgent2D (A* via Godot)
Detection Checks: Every 0.2-0.3 seconds (not every frame)
```

---

## 5. SPECIAL ZOMBIE TYPES (11 TOTAL)

All special zombies are created by entering specific buildings. Each type provides unique tactical abilities for environmental puzzle-solving.

### 5.1 Fat Zombie

**Source:** Fast food restaurant
**Appearance:** Grossly obese zombie

**Abilities:**
- Jump off cliff → creates permanent landing cushion (kills Fat Zombie)
- Jump into water → becomes permanent pontoon bridge (kills Fat Zombie)
- When killed → becomes permanent LOS-blocking obstacle

**Use Case:**
- Bridge hazards (gaps, spikes, water)
- Create cover for other zombies
- Tactical sacrifices

**Limitations:**
- Cannot attack humans
- Once ability used, zombie is dead (one-time use)

### 5.2 Fireman Zombie

**Source:** Fire station
**Appearance:** Zombie in firefighter gear, dragging fire hose

**Ability:**
- Spray water in cone (AOE damage/knockback)
- Damages and pushes back groups of defenders

**Use Case:**
- Clear clusters of defenders
- Create openings in defensive lines
- Push enemies into hazards

### 5.3 Traffic Controller Zombie

**Source:** Construction site / police station
**Appearance:** Zombie with traffic warden hat and glow sticks/stop sign

**Ability:**
- Set waypoint to redirect charging zombies
- Changes direction of zombie swarm mid-pursuit
- Becomes immobile once placed

**Use Case:**
- Navigate zombies around hazards
- Flank defensive positions
- Guide swarm through complex terrain

**Limitations:**
- Cannot attack humans
- Cannot move once placed

### 5.4 Marching Band Zombie

**Source:** School / theater / music hall
**Appearance:** Zombie with instrument (tuba, drum, massive drum set)

**Ability:**
- AOE buff to nearby zombies (radius effect)
- Increases speed and/or health of nearby units
- May enable formation control (future)

**Use Case:**
- Enhance horde for tough fights
- Support swarm in prolonged engagements
- Boost efficiency against strong defenders

### 5.5 Scuba Zombie

**Source:** Dive shop / aquarium
**Appearance:** Zombie in wetsuit with flippers and shark fin on head

**Ability:**
- Cross water hazards without dying
- Reduced land movement speed

**Use Case:**
- Access areas blocked by rivers/moats
- Flank positions across water
- Create alternate routes

**Trade-off:** Slower on land, vulnerable before reaching water

### 5.6 Headless Zombie

**Source:** Hardware store (guillotine/buzz saw)
**Appearance:** Zombie carrying its own severed head

**Abilities:**
- Throw head (one-time use) → reveals fog of war at landing spot
- No pathfinding (moves in straight line only)
- Doesn't charge civilians unless direct collision or fired upon
- Dies if hitting hard objects at speed

**Use Case:**
- Scout ahead, locate hidden defenders
- Reveal sniper positions
- Plan routes before committing forces

**Limitations:**
- Straight-line movement only (no turning)
- Fragile (collision deaths)
- Head throw is one-time ability

### 5.7 Costume Zombie

**Source:** Costume shop / theater  
**Appearance:** Zombie in silly disguise (sombrero, fake mustache, clown suit). Pink tint while costumed; reverts to standard zombie green on disguise break.

**Ability:**
- Fully undetectable while `is_costumed = true` — humans skip this zombie in all detection systems: flee detection, morale drain, aim timer acquisition, alert cone timer, and gunshot response
- Disguise breaks **permanently** when the zombie pins a human (target enters GRAPPLED state) — not on chase start, not on attack start
- After break: behaves identically to a regular zombie; all human detection systems apply normally

**Use Case:**
- Sneak past patrols entirely undetected
- Reach high-value targets (GI, Spec Ops) without triggering morale drain
- Set up ambushes — position the zombie before breaking disguise
- Break disguise deliberately to cause maximum morale shock at close range

### 5.8 Petrol Zombie

**Source:** Petrol station / gas station
**Appearance:** Zombie covered in black (doused in gasoline)

**Abilities:**
- If set on fire → explodes after short delay (damages friend and foe)
- If shot before ignition → leaks petrol on ground (creates hazard)
- Walking area denial bomb

**Use Case:**
- Tactical sacrifice for area clearing
- Deny chokepoints to defenders
- Clear clustered enemies

**Risk:** Damages your own zombies if they're nearby

### 5.9 Motorcycle Zombie

**Source:** Motorcycle dealership / car repair shop
**Appearance:** Zombie wheeling a motorcycle

**Abilities:**
- Moves slower than other zombies initially
- Activate: Rides motorcycle in straight line at high speed
- On collision (wall or enemy) → spectacular explosion
- Can be shot down mid-charge by high-caliber weapons

**Use Case:**
- Kamikaze attack on high-value targets
- Breach fortified positions
- Quickly eliminate priority threats

**Risk:** Vulnerable during charge, destroys zombie on use

### 5.10 Ordnance Zombie

**Source:** Military checkpoint / army surplus store
**Appearance:** Zombie with howitzer and bandolier of grenades

**Abilities:**
- Use mounted weapons (heavy machine guns)
  - Fixed direction, 45° arc
  - Shoots sporadically, hits friendlies and hostiles
- Fire howitzer once (50% chance to backfire!)
- Throw up to 2 grenades (50% chance to throw pin instead → self-destruct)

**Use Case:**
- High-risk, high-reward attacks
- Suppress fortified positions
- Comedic chaos (unreliable but powerful)

**Risk:** Extremely unreliable, likely to kill own zombies

### 5.11 Headcrab Zombie

**Source:** Aquarium
**Appearance:** Zombie with sea crab on head

**Abilities:**
- Survives one sniper shot (crab absorbs damage, then dies)
- Throw crab at rooftop enemies (distract/kill snipers)
- After crab thrown, zombie is vulnerable

**Use Case:**
- Counter snipers and elevated defenders
- Tank one high-damage shot
- Clear rooftop threats

---

## 6. HUMAN DEFENDERS

### 6.1 Defender Classes (v0.22.0 — designed, not yet implemented)

All five classes share: Health 75, Move speed 90px/sec, Vision cone 90°, no shooting while fleeing, one-shot kills (50 damage).

**Combat Table:**

| Unit | Weapon | Range | Aim Time | Kills (frontal) | Primary Response |
|------|--------|-------|----------|-----------------|------------------|
| Civilian | Unarmed | — | — | 0 | Flee |
| Militia | Shotgun | ~150px | 0.7s | 1 | Flee |
| Police | Pistol | ~150px | 0.55s | 2 | Flee |
| GI | Assault Rifle | ~250px | 0.525s | 4 | Tunnel Vision |
| Spec Ops | Assault Rifle | ~250px | 0.26s | 8 | Tunnel Vision |

**Morale Table:**

| Unit | Morale Max | Sighting (/sec) | Ally grappled | Ally fleeing | Ally killed |
|------|-----------|----------------|---------------|--------------|-------------|
| Civilian | 65 | 30 | 100 | 50 | 150 |
| Militia | 150 | 35 | 100 | 40 | 150 |
| Police | 200 | 0 | 100 | 40 | 150 |
| GI | 400 | 0 | 275 | 20 | 150 |
| Spec Ops | 1000 | 0 | 100 | 0 | 150 |

Note: Sighting drain activates within weapon range for armed units. Civilians drain at full vision range (350px).

**Class Notes:**
- **Civilian** — panics on any sighting, collapses almost immediately, cannot fight back
- **Militia** — same range as police but slower aim; holds against 1-3 zombies, collapses against 4+
- **Police** — ignores sightings entirely, breaks under social pressure (grapples, deaths); reliable 2-kill shooter
- **GI** — nearly unbreakable except when allies are grappled; requires panic, stealth, or overwhelming numbers
- **Spec Ops** — effectively immune; tunnel vision response means even morale collapse keeps them fighting but creates exploitable blind spot

### 6.2 Current Prototype (v0.23.0)

**Implemented States:**
- IDLE: Stationary, circle vision
- SENTRY: On patrol or watching, arc vision
- FLEEING: Running from zombies, forward arc vision
- GRAPPLED: Pinned by zombie, no vision
- DEAD: Converting to zombie
- TUNNEL_VISION: GI/Spec Ops — threat-facing, 22.5° orange cone, 10s, immune to drain
- FREEZE: Civilian only — 5s paralysis (designed, deferred)
- MELEE_CHARGE: Militia only — rush attack (designed, deferred)

**Alert System (v0.23.0–v0.23.1):**

**Low Urgency — Detection Alert (v0.23.0):**

When a zombie has been in a human's vision cone for 5 seconds, the human alerts nearby allies within 150px. Each ally rotates to a class-appropriate facing offset based on which side of the alerter they're on — right-side allies rotate right, left-side allies rotate left.

| Class | Response | Offsets |
|-------|----------|---------|
| Civilian | Flee only — no facing assignment | — |
| Militia | All face threat directly | 0° |
| Police | Fan out around threat | ±45°, ±90° |
| GI | Cover flanks and further | ±105°, ±165° |
| Spec Ops | Same as GI | ±105°, ±165° |

Alert cooldown: 30 seconds. Facing returns to original 30 seconds after cone clears.

**High Urgency — Ally Grappled, Ally Killed, Gunshot (v0.23.1):**

All three events use a unified system. All classes respond identically — direct facing toward the event, no class-based offsets. Civilians included.

| Event | Radius | Notes |
|-------|--------|-------|
| Ally grappled | 75px | Fires alongside morale drain |
| Ally killed | 75px | Fires alongside morale drain |
| Gunshot | 150px | Fires when any ally shoots |

Reaction delay: 0.4s. Shared cooldown: 2s across all high urgency types. Facing holds for 2s then returns to original (if no zombies now in sightline). If a zombie enters the new sightline, normal targeting takes over naturally.

All rotations smooth at 360°/sec (180° in 0.5s).

**Shared exclusion rules:**
- Unit already has shoot_target → ignore (already engaged)
- FLEEING, GRAPPLED, DEAD, TUNNEL_VISION → ignore

**Tactical implications:**
- Player cannot park zombies in vision cones indefinitely — 5s detection alert adapts the formation
- Militia alert creates a predictable blind spot — exploitable
- GI alert covers flanks — requires more careful approach
- Attacking a group is harder — nearby allies react immediately to grapples and kills
- Multiple simultaneous attacks can overwhelm the response — humans can only commit to one direction per 2s
- Deliberate sacrifice (sending one zombie to draw attention) opens flanking opportunities

### 6.3 Planned Defender Types (Future / Post-v0.22.0)

**Snipers:**
- Weapons: Long-range rifle
- Position: Rooftops, elevated positions
- Behavior: One-shot kills from extreme range
- Counter: Headcrab Zombie, Costume Zombie

**Militia arming civilians:**
- Police can arm civilians in some scenarios, turning them into Militia
- Deferred to post-validation slice

---

## 7. BUILDING SYSTEM

### 7.1 Planned Interaction (Not Yet Implemented)

**Transformation System:**
- Zombies enter specific buildings
- Building transforms zombie into special type
- Building remains (can be used multiple times)
- Process is instant (no animation in prototype)

### 7.2 Building-Zombie Mapping
```
Fast Food Restaurant → Fat Zombie
Fire Station → Fireman Zombie
Construction Site/Police Station → Traffic Controller Zombie
School/Theater/Music Hall → Marching Band Zombie
Dive Shop/Aquarium → Scuba Zombie (also Headcrab Zombie)
Hardware Store → Headless Zombie
Costume Shop/Theater → Costume Zombie
Petrol Station/Gas Station → Petrol Zombie
Motorcycle Dealership/Repair Shop → Motorcycle Zombie
Military Checkpoint/Army Surplus → Ordnance Zombie
Aquarium → Headcrab Zombie (also Scuba Zombie)
```

### 7.3 Building as Obstacles

**Current Implementation:**
- Buildings block movement (StaticBody2D collision)
- Buildings block line-of-sight (raycasting)
- Creates tactical positioning opportunities
- Humans use for cover, zombies path around
- **NEW:** Navigation system paths around buildings (v0.17.0+)

---

## 8. LEVEL DESIGN PHILOSOPHY

### 8.1 Design Principles

**Sandbox Puzzle Approach:**
- Levels are tactical puzzles with multiple solutions
- Player creativity encouraged (no "correct" path)
- Environmental storytelling over explicit objectives

**Three Design Levers:**
1. **Building Placement** - Which zombie types are available?
2. **Enemy Placement** - Where are defenders positioned?
3. **Terrain Variation** - What hazards/obstacles exist?

**NEW: Patrol Integration (v0.18.0+):**
- Sentry patrol routes add dynamic challenge
- Predictable patterns allow planning
- LOOP vs PING_PONG affects difficulty
- Tight vs loose formations affect panic spreading

**Replayability:**
- Different zombie type combinations = different strategies
- Speedrun potential (time bonuses incentivize optimization)
- Score-chasing (keep zombies alive for max points)
- Patrol route optimization (intercept at optimal points)

### 8.2 Prototype Level

**Current Test Scenario:**
- 3 buildings (obstacles only)
- 1 escape zone (right side of map)
- 4-5 humans with patrol routes
- 3 starting zombies
- Goal: Prevent humans from escaping
- NavigationRegion2D for pathfinding

### 8.3 Future Level Types

**Urban Streets:**
- Dense buildings, narrow alleys
- Rooftop snipers (requires Headcrab Zombie)
- Barricades and checkpoints
- Patrolling sentries with overlapping routes

**Suburban Neighborhoods:**
- Houses with civilians
- Police patrols
- Water hazards (pools, rivers)
- Interconnected patrol routes

**Industrial Zones:**
- Factories, warehouses
- Mounted guns, heavy defenses
- Environmental hazards (fire, machinery)
- Complex multi-level patrol patterns

**Special Scenarios:**
- VIP Assassination (kill specific target)
- Timed Escape (reach exit before reinforcements)
- Horde Survival (maximize zombie count)
- Stealth Missions (avoid detection until ready)

### 8.4 Progression Curve

**Early Levels:**
- Few defenders, simple layouts
- Tutorial special zombies
- Basic patrol patterns (LOOP, straight lines)
- Forgiving panic radius (spaced sentries)

**Mid Levels:**
- Complex terrain, mixed defender types
- Multi-stage objectives
- Overlapping patrol routes
- Tight formations (panic spreading matters)

**Late Levels:**
- Heavy defenses, requires all zombie types
- Precise execution
- Complex patrol coordination
- Multiple simultaneous threats

---

## 9. FUTURE FEATURES

### 9.1 First Validation Slice ⚠️ PARTIALLY COMPLETE

**Goal:** Validate that the core tactical puzzle loop is actually fun before building more infrastructure.

**Status:**
- ✅ Fat Zombie implemented (v0.24.0) — gunshot-only death, permanent corpse obstacle
- ✅ Costume Zombie implemented (v0.24.1) — full invisibility until pin
- ✅ Police Defender implemented (v0.22.x) — armed, morale bar, flees when bar empties
- ✅ GI Defender implemented (v0.22.x) — tunnel vision response, nearly unbreakable
- ✅ Player-controlled engagement redesigned (v0.25.0)
- ❌ Handcrafted test level combining all four — still outstanding
- ❌ Focused play sessions to validate fun — still outstanding

**Remaining work:** Build one handcrafted level using Costume Zombie + Fat Zombie against Police + barricaded GI. Run focused play sessions before designing further levels or adding more systems.

**Why this still matters:** Systems exist but haven't been meaningfully playtested together. Fun needs to be validated with a minimal puzzle loop before building more simulation complexity.

### 9.1a Patrol System Phase C ✅ COMPLETE (v0.20.0)

Phase C delivered full per-waypoint customisation:
- Pause durations, swing enable/disable, and facing overrides per waypoint
- Formation squad patrols with leader/follower system and 5 formation shapes (v0.21.0)
- Panic propagation depth cap and distance-based cascade delays (v0.21.2)

### 9.2 Campaign Structure (Post-Prototype)

**Narrative Arc:**
- Zombie outbreak spreads across city
- 10-20 levels telling progression of apocalypse
- Unlock new areas as infection spreads

**Level Progression:**
- Linear or branching paths (TBD)
- Difficulty scaling through defender quantity/quality
- Environmental variety (urban → suburban → industrial → military)

**Unlock System (Option 1):** Progressive zombie type unlocks
**Unlock System (Option 2):** All types available, level design determines usage

### 9.3 Audio System

**Music:**
- Dark but playful (horror-comedy tone)
- Dynamic intensity based on horde size
- Orchestral horror OR electronic/industrial (TBD)

**Sound Effects:**
- Unit footsteps, attacks, special abilities
- Conversion sound (human → zombie)
- Zombie groans, human screams
- Environmental ambience (city sounds, gunfire)
- Patrol alerts (sentry detection sounds)

**Voiceover (Optional):**
- Darkly comedic narrator commenting on player actions
- Unit barks (zombies groan, humans shout)

### 9.4 Art Style (TBD)

**Options Under Consideration:**
- Pixelated/Retro (low-res sprites, distinct style)
- Cartoonish (exaggerated proportions, humorous)
- Gritty/Realistic (detailed, dark atmosphere)
- Minimalist (simple shapes, clear silhouettes)

**Key Requirements:**
- Each zombie type instantly recognizable by silhouette
- Clear building identities (color-coding)
- Isometric clarity (no gameplay obscuration)
- Patrol routes visible and readable

### 9.5 Multiplayer (Future Consideration)

**Co-op Mode:**
- Two players control separate zombie hordes
- Shared objective (combine forces)
- Unique zombie types per player

**Versus Mode:**
- Asymmetric: One player zombies, one controls defenders
- Zombies must reach objective, defenders must stop them
- Different strategies for each side

**Current Decision:** Multiplayer NOT in initial scope. Evaluate after single-player is polished.

### 9.6 Accessibility Features

- Colorblind mode (UI color adjustments)
- Difficulty options (easier/harder AI)
- Control remapping (keyboard customization)
- Text size options
- Keyboard-only alternative to mouse controls
- Patrol speed indicators for timing-impaired players

---

## 10. ORIGINAL IDEAS NOT YET IMPLEMENTED

### 10.1 Advanced Unit Control

**Group Splitting (from original GDD):**
- Press numeral 1-4 to split selection into subgroups
- Each subgroup gets different shade of green
- Issue commands in rotation to each subgroup
- Allows simultaneous multi-pronged attacks

**Current Status:** Not implemented. Using standard RTS control groups instead (Ctrl+1-9).
**Evaluation:** May add later if players need more granular control.

### 10.2 Incubation Time

**Original Design:**
- 10-second delay before human becomes zombie
- Enemies can shoot incubating zombies (instant death)
- Players can't control zombie in melee until incubation starts

**Current Status:** **Implemented** — 5-second incubation timer (halved from original 10s). Dead humans remain on the map in DEAD state for 5 seconds, then convert. Dead humans are counted as part of the zombie total during incubation for scoring and lose condition checks. Shooting incubating zombies and melee restrictions from the original design are not implemented.
**Evaluation:** The 5-second delay adds a small conversion delay without dramatically slowing gameplay. Shooting incubating targets could be added as a future defender ability.

### 10.3 Attack Speed Multipliers

**Original Design:**
- 1 zombie on human = 1x kill speed
- 2 zombies = 1.5x multiplier
- 3 zombies = 1.75x multiplier
- Rewards coordinating attacks

**Current Status:** Fixed attack speed (1.5 sec cooldown, 15 damage, 75 health = ~8 seconds per kill with 1 zombie).
**Evaluation:** Could add multipliers to reward tactical coordination. Low priority.

### 10.4 Zombie Milling Behavior

**Original Design:**
- Idle zombies slowly wander randomly
- Forces player to constantly manage units
- Creates "mindless wandering" zombie feel

**Current Status:** Zombies stay perfectly still when idle.
**Evaluation:** Could add subtle idle movement for atmosphere. Risk: accidental detection. Low priority.

### 10.5 Unit Morale/Fleeing Mechanics

**Original Design (for future defender types):**
- Different morale thresholds per class
- Civilians flee easily, military never flees
- Flee when outnumbered by specific ratios

**Current Status:** All humans flee at 150px detection (sentries have patrol behavior).
**Evaluation:** Will implement when adding defender variety (police, military, etc.).

### 10.6 Delayed Command Execution

**Original Design:**
- Hold Alt while issuing commands to queue but not execute
- Allows setting up synchronized multi-unit maneuvers
- Execute all at once when Alt released

**Current Status:** Commands execute immediately.
**Evaluation:** Advanced feature for tactical depth. Post-launch consideration.

### 10.7 Building Entry/Exit

**Original Design:**
- Zombies can enter buildings through ground-floor doors
- Exit through doors OR upper-story windows
- Complex building navigation

**Current Status:** Buildings are solid obstacles.
**Evaluation:** Will implement with special zombie transformation system.

### 10.8 Sniper Threat to Incubating Zombies

**Original Design:**
- Snipers prioritize shooting incubating zombies
- Creates urgency to protect fresh converts
- Requires crowd control

**Current Status:** No incubation, no snipers yet.
**Evaluation:** Adds tension when both are implemented.

---

## 11. DESIGN PHILOSOPHY & DECISIONS

### 11.1 Why Tactical Puzzle Over Action RTS?

**Decision:** Emphasize planning and positioning over fast clicking.

**Reasoning:**
- Differentiation: Not another Starcraft clone
- Accessibility: Lower APM barrier to entry
- Depth: Thoughtful solutions more satisfying than brute force
- Zombie Theme: Shambling hordes fit methodical pacing

**Implementation:**
- Player-initiated engagements (right-click only) — no accidental auto-pursuit
- Pre-placed defenders (no dynamic spawning during play)
- Environmental puzzles require specific zombie types
- Score rewards efficiency over aggression
- **NEW:** Patrol patterns allow planning (predictable routes)

### 11.2 Why Guaranteed Leap Pin?

**Decision:** Hybrid system (continuous speed boost + discrete pin at 40px).

**Evolution:**
- v0.1-0.6: Pure speed boost, unreliable catches
- v0.7 attempt: Pin at leap start (felt wrong)
- v0.8: Pin at 40px (landing point)

**Reasoning:**
- **Frustration:** Players hated humans escaping mid-leap
- **Game Feel:** Guaranteed catch feels satisfying
- **Balance:** Human had enough escape time (60px → 40px)
- **Organic:** Speed boost feels natural, pin is reliable

### 11.3 Why BOID Separation Over Physics Collision?

**Decision:** Use BOID forces, disable unit-unit physics collision.

**Evolution:**
- v0.1-0.6: Physics collision → units pushed each other (janky)
- v0.7: Disabled collision → units stacked (ugly)
- v0.8: BOID separation → smooth spacing

**Reasoning:**
- Physics collision caused units to bump pinned zombies away
- Stacking looked bad (not like a horde)
- BOID gives organic spacing without pushing
- Disable separation for melee attackers (locked in combat)

### 11.4 Why Shambling Formation Over Perfect Grid?

**Decision:** Add ±15px jitter to formation positions.

**Reasoning:**
- Perfect grid looked like Roman legionnaires (wrong aesthetic)
- Zombies should be chaotic, not regimented
- Jitter creates "shambling horde" appearance
- Still maintains spacing (40px base + jitter)

### 11.5 Why Player-Controlled Engagement? (v0.25.0)

**Decision:** Zombies never auto-pursue. All engagements are explicitly player-initiated via right-click.

**Original design:** Auto-pursuit triggered when a zombie's vision arc swept across a human. A pursuit lock then prevented the player from redirecting the zombie.

**Problem found during testing:** Accidental engagements from a vision arc momentarily sweeping a human were anti-puzzle. The game was making decisions the player didn't make, and managing zombie orientation to avoid accidental triggering was friction with no tactical payoff.

**New model:** Right-click initiates attacks. PURSUING zombies (chasing) can be freely redirected. LEAPING and MELEE zombies are committed — control returns when the target dies. Post-kill continuation (250px LOS scan) means players don't micromanage every kill in a group fight.

**Why this fits the genre:** Commandos and Shadow Tactics give the player full control over when engagements begin. Tactical puzzles require the player to make the engagement decision, not the AI.

### 11.6 Why Smart Targeting (Unpinned First)?

**Decision:** Zombies prioritize unpinned humans over pinned ones.

**Problem:** All zombies dogpiled first target, others escaped.

**Solution:** Check if human is grappled, if so, find different target.

**Reasoning:**
- Spreads attacks naturally (no micromanagement needed)
- Prevents frustrating "tunnel vision" AI
- Still allows dogpiling if no other targets available
- Emergent: Creates dynamic chases across map

### 11.7 Why 25 Points Per Zombie (Not Per Created)?

**Decision:** Score for total zombies alive, not zombies created.

**Evolution:**
- Original design: Points for conversion (+1 per convert)
- v0.7: Points for zombies created (final - starting)
- v0.8: Points for all zombies alive (final count × 25)

**Reasoning:**
- Incentivizes keeping starting zombies alive (they're valuable too!)
- Rewards tactical play (minimize deaths)
- Simpler to explain (total × 25 vs created × 25)
- Creates risk/reward (use zombies aggressively vs preserve them)

### 11.8 Why Degrees Over Vectors for Sentry Facing? (NEW - v0.14.0)

**Decision:** Use 0-360 degree system instead of Vector2.

**Reasoning:**
- **Designer-Friendly:** "90 degrees" more intuitive than "Vector2(1, 0)"
- **Compass-Based:** 0°=North, 90°=East matches mental model
- **Editor UI:** Slider with degrees easier than vector input
- **Precision:** Exact angles easier (45°, 90°, 180°) than normalized vectors

**Implementation:**
- Internally converts to Vector2 for calculations
- Export property uses degrees for designer input
- Visual arrow in editor shows direction clearly

### 11.9 Why Swing Only When Stationary? (NEW - v0.19.0)

**Decision:** Disable swing arc while patrolling, only when standing still.

**Problem:** Swing while walking looked jerky and unnatural.

**Reasoning:**
- **Realism:** Walking guard looks forward (where they're going)
- **Clarity:** Forward arc follows movement direction (predictable)
- **Game Feel:** Clean movement more important than swing
- **Future:** Phase C will add pause-then-swing at waypoints

**Evolution:**
- v0.14.0: Swing works always (tried it)
- v0.19.0: Swing disabled while moving (better feel)
- v0.20.0+: Per-waypoint pause-and-swing (planned)

### 11.10 Why 40px Panic Radius? (NEW - v0.16.0)

**Decision:** Panic spreads to allies within 40px of grappled human.

**Testing:**
- 120px: Too large (entire groups panicked from single chase)
- 60px: Still too large (4-5 units affected)
- 40px: Just right (2-3 immediate neighbors)

**Reasoning:**
- **Realism:** Only those "standing right next to" victim panic
- **Tactical:** Formation spacing matters (tight vs loose)
- **Balance:** Allows isolated sentries without chain reaction
- **Emergent:** Creates formation decision (tight = risky, loose = safe)

**Example:**
```
Formation spacing 40px (tight):
[S] [S] [S] [S] [S]
     ↑
  GRAPPLED
Result: Middle + 2 adjacent panic (3 total)

Formation spacing 60px (loose):
[S]    [S]    [S]    [S]    [S]
            ↑
         GRAPPLED
Result: Only victim (1 total)
```

### 11.11 Why Visual Waypoints Over Typed Arrays? (NEW - v0.19.0)

**Decision:** Add child Node2D waypoint placement (Phase B2).

**Evolution:**
- v0.18.0: Manual typing `[(100,100), (200,100)]` (tedious)
- v0.19.0: Drag Waypoint1, Waypoint2 nodes (visual)

**Reasoning:**
- **Designer-Friendly:** See waypoints in editor, no coordinate math
- **Iteration Speed:** Drag to adjust, no typing/testing cycle
- **Visual Feedback:** Yellow path shows route immediately
- **Backwards Compatible:** Manual arrays still work

**Implementation:**
- Waypoint nodes are children of sentry
- Natural string sort handles Waypoint1-10+ correctly
- Loads positions on `_ready()`

### 11.12 Why Parallel Arrays for Phase C? (v0.20.0)

**Decision:** Three separate parallel arrays (`patrol_pause_durations`, `patrol_waypoint_swing`, `patrol_waypoint_facing`) rather than a custom resource or dictionary per waypoint.

**Reasoning:**
- **Inspector-Friendly:** Arrays work natively in Godot Inspector — no custom editor needed
- **Pattern Consistency:** Follows the same optional-per-waypoint pattern as waypoints themselves
- **Backwards Compatible:** Empty array = no behaviour, existing setups unaffected
- **Simple Indexing:** `array[waypoint_index]` — trivially maps to the waypoint system

**Trade-off acknowledged:** Not as legible as a dedicated WaypointData resource, but avoids over-engineering at this stage.

### 11.13 Why Leader/Follower Over Shared Waypoint Lists? (v0.21.0)

**Decision:** One human owns the waypoints (leader); others hold a NodePath reference to that human (followers).

**Alternatives considered:**
- Shared waypoint group (all sentries read from same node list)
- Duplicate waypoints on every sentry in the squad

**Reasoning:**
- **Single source of truth:** Change the leader's route and all followers automatically follow
- **Natural hierarchy:** Matches real patrol squad mental model (one leader, others follow)
- **Editor simplicity:** Followers need only two Inspector fields (`patrol_leader` + `formation_slot`)
- **Backwards compatible:** Leaders behave identically to standalone sentries when alone

### 11.14 Why Depth Cap Panic Propagation Instead of Unlimited? (v0.21.2)

**⚠️ Note: This system is being deprecated in v0.22.0 and replaced by the morale bar system. The reasoning below is preserved as historical record.**

**Decision:** `panic_propagation_depth` (default 2) limits the chain to ~2 rings from the contact point.

**Problem with unlimited:** Every human who panicked also propagated to their neighbours — a single zombie sighting could cascade across the entire map through daisy-chaining.

**Why depth 2 specifically:**
- 2 hops × 150px event radius = ~160px effective spread from contact
- Covers a realistic "everyone who could see or hear it" area
- Guards posts 200+ px apart are correctly isolated
- Whole blobs and squads within range react; distant sentries don't

**Tuning:** `panic_propagation_depth` is an export — level designers can set it per-sentry (0 = isolated, 99 = old unlimited behaviour).

**Replacement (v0.22.0):** The morale bar system makes explicit propagation chains unnecessary. Every unit drains independently based on proximity to events — runaway cascades are naturally prevented by morale_max values rather than a depth cap.

### 11.15 Why Full 3D Migration? (April 2026)

**Decision:** Migrate the entire project to 3D Godot — low-poly geometry, simple 3D character models, rotatable isometric camera.

**Drivers:**
- **Rooftop traversal** is a genuine planned gameplay mechanic (Headcrab Zombie, snipers, elevated defenders). Faking this in 2D requires separate NavigationRegion2Ds per floor, Z-sort layers, and collision filtering — scaffolding that gets discarded at migration anyway.
- **Urban density:** Dense buildings with camera freedom to avoid occlusion blind spots can't be cleanly solved in 2D without roof-opacity hacks.
- **Timing:** Migrating at v0.24.1 while game logic systems (morale, shooting, patrol, formations, state machines) are still portable is lower-cost than migrating later with more 2D-specific systems to rewrite.

**Systems requiring full rewrite:** Camera, vision renderer, all scene files.  
**Systems needing significant adaptation:** Unit movement, selection, navigation, building logic.  
**Systems surviving largely intact:** All game logic — state machines, morale, combat, patrol, formations.

**Reference aesthetic:** They Are Billions (horde density, colour palette), 28 Days Later (tone).  
**Art approach:** AI-generated assets via Midjourney for concepts; Synty-style low-poly for production.

---

## 12. OPEN QUESTIONS & DESIGN GAPS

### 12.1 Art Style

**Gap:** 3D migration confirmed; specific art direction to be finalised  
**Impact:** Can't produce final art until migration is complete  
**Decision made:** Low-poly 3D geometry, simple 3D character models, rotatable isometric camera. They Are Billions and 28 Days Later as primary aesthetic references. No pixel art.  
**Action:** Begin migration; develop style guide using Midjourney/Milanote alongside  
**Timeline:** Post-validation-slice

### 12.2 Audio Design

**Gap:** No audio/music style decided
**Impact:** Atmosphere and tone unclear
**Options:** Orchestral horror, electronic/industrial, comedic sound effects
**Action:** Add audio in post-prototype polish
**Timeline:** Post-prototype

### 12.3 Campaign Narrative

**Gap:** No story arc or level progression
**Impact:** Unknown how many levels, what order, what narrative
**Options:** Linear progression, branching paths, standalone scenarios
**Action:** Design after validating core loop
**Timeline:** Post-prototype

### 12.4 Special Zombie Implementation Priority

**Gap:** Which zombie types to implement first?
**Impact:** Development time allocation

**Suggested Priority:**
1. **Tier 1 (Simplest):** Fat, Scuba, Costume (passive abilities)
2. **Tier 2 (Moderate):** Fireman, Marching Band, Petrol (active abilities)
3. **Tier 3 (Complex):** Traffic Controller, Headless, Headcrab (special mechanics)
4. **Tier 4 (Advanced):** Motorcycle, Ordnance (physics/randomness)

### 12.5 Level Design Philosophy: Linear vs Sandbox

**Gap:** How open should levels be?
**Impact:** Puzzle design, replayability

**Options:**
- Puzzle box (one optimal solution)
- Sandbox (multiple valid approaches)
- Hybrid (optional objectives, ranked efficiency)

**Action:** Prototype one linear scenario, evaluate
**Current Lean:** Sandbox with score-based optimization

### 12.6 Multiplayer Scope

**Gap:** Is multiplayer core feature or bonus?
**Impact:** Architecture decisions (server/client, networking)
**Options:** Co-op, versus, both, neither
**Action:** Defer until single-player polished
**Current Lean:** Post-launch consideration

### 12.7 Accessibility Priority

**Gap:** Which accessibility features are must-have?
**Impact:** Development time, player base reach
**Options:** Colorblind mode, keyboard-only, difficulty options, text size
**Action:** Audit post-prototype
**Current Lean:** Colorblind mode and control remapping minimum

### 12.8 Exact Special Zombie Mechanics

**Gap:** Detailed implementation specs for each type

**Examples:**
- Fat Zombie: Does cushion disappear after one use or permanent?
- Traffic Controller: Radius of effect? Can redirect mid-air jumps?
- Headless: Exactly how far can head be thrown? Arc or straight line?

**Action:** Detail during implementation phase
**Priority:** Block out rough versions, refine through playtesting

### 12.9 Environmental Hazard Mechanics

**Gap:** How do hazards work exactly?

**Questions:**
- Water: Instant death or damage over time?
- Fire: Spread to adjacent units? Duration?
- Spikes: Damage or instant kill?
- Cliffs: Fall damage or death?

**Action:** Define alongside special zombies (they interact heavily)

### 12.10 Building Capacity Limits

**Gap:** Can one building transform unlimited zombies?

**Options:**
- Unlimited uses (player can spam special types)
- Limited uses (strategic resource management)
- Cooldown (time between uses)

**Action:** Playtest different approaches
**Current Lean:** Unlimited uses, level design controls availability

### 12.11 Phase C Patrol Customization ✅ RESOLVED (v0.20.0)

**Decision:** Implemented the "complex" option — pause duration + swing toggle + facing override per waypoint.

**Implementation:**
- `patrol_pause_durations: Array[float]` — seconds to pause at each waypoint
- `patrol_waypoint_swing: Array[bool]` — swing vision cone during pause
- `patrol_waypoint_facing: Array[float]` — facing override on arrival (-1.0 = none)
- Swing during pause works even if `sentry_has_swing` globally false
- All three arrays are optional and backwards compatible

**Followed by:** Formation squad patrols (v0.21.0) and panic propagation depth cap (v0.21.2).

### 12.12 Patrol Resume After Threat ✅ DECISION MADE

**Decision:** Patrol stops permanently when a zombie is detected. Sentries do not resume.

**Reasoning:** Clear, predictable consequence for detection. Avoids complexity of "safe again" detection. Sentries that have spotted zombies should stay alert and flee — resuming feels unrealistic. Evaluate during playtesting if players want different behaviour.

**Status:** Implemented and stable. No change planned.

---

## APPENDIX A: CONTROLS REFERENCE

**CAMERA**
```
WASD / Arrow Keys - Pan camera
Mouse Edge Scroll - Pan camera (when near screen edge)
Mouse Wheel - Zoom (disabled in prototype)
```

**SELECTION**
```
Left Click - Select unit
Left Drag - Box select multiple units
Shift + Left Click - Add/remove from selection
Ctrl + Left Click - Remove from selection
```

**COMMANDS**
```
Right Click (ground) - Move selected units (formation)
Right Click (enemy) - Attack target (idle zombies only)
```

**CONTROL GROUPS**
```
Ctrl + 1-9 - Assign selection to group
1-9 - Recall control group
Ctrl + 0 - Clear control group from selection
```

**DEBUG**
```
R - Reset level
```

---

## APPENDIX B: DEVELOPMENT TIMELINE

**Prototype Phase (v0.1-0.8 Complete):**
- ✅ Core systems (camera, selection, movement)
- ✅ Combat and conversion
- ✅ AI behaviors (flee, pursue, smart targeting)
- ✅ Polish (formations, control groups, scoring)

**Vision & Sentry Phase (v0.9-0.14.0 Complete):**
- ✅ State-based vision system
- ✅ Degree-based sentry facing
- ✅ Swing arc mechanics
- ✅ Editor visual indicators

**Human AI Phase (v0.15.0-0.17.0 Complete):**
- ✅ Panic spreading system
- ✅ Escape zone improvements
- ✅ Navigation system implementation

**Patrol System Phase B (v0.18.0-0.19.5 Complete):**
- ✅ Phase B1: Manual waypoint patrol
- ✅ Phase B2: Visual waypoint placement
- ✅ Integration fixes (swing, editor behaviour)
- ✅ WorldBounds autoload singleton

**Patrol Phase C + Formations (v0.20.0-0.21.2 Complete):**
- ✅ Phase C: Per-waypoint pause, swing, facing overrides
- ✅ Inspector export groups (Human, Unit)
- ✅ Formation squad patrols (leader/follower, 5 shapes)
- ✅ Formation follower polish (catch-up speed, BOID convergence)
- ✅ Depth-capped, distance-based panic propagation

**Human Defender System (v0.22.0-v0.22.5 Complete):**
- ✅ Five defender classes: Civilian, Militia, Police, GI, Spec Ops
- ✅ Morale bar system replacing binary flee trigger
- ✅ Shooting system: aim timer, tracer lines, one-shot kills
- ✅ Dual-zone vision arcs (detection + weapon range)
- ✅ Tunnel Vision: 22.5° threat-facing locked cone, 10s, GI/Spec Ops
- ✅ Zombie death visual: dark red, 0.3s delay, shot knockback tween

**Alert & Gunshot Response (v0.23.0 Complete):**
- ✅ Detection alert: 5s cone timer triggers side-aware formation response
- ✅ Per-class offsets: Militia (0°), Police (±45°/±90°), GI/Spec Ops (±105°/±165°)
- ✅ Gunshot response: 0.4s delayed facing snap to active target
- ✅ Smooth rotation at 360°/sec for all alert types

**High Urgency Alert System (v0.23.1 Complete):**
- ✅ Unified `_broadcast_high_urgency_alert()` replacing separate gunshot system
- ✅ Ally grappled → nearby units within 75px face event after 0.4s
- ✅ Ally killed → nearby units within 75px face event after 0.4s
- ✅ Gunshot → nearby units within 150px face target after 0.4s
- ✅ Shared 2s cooldown across all high urgency types
- ✅ 2s facing hold then return to original if no zombies in new sightline
- ✅ Civilians included in high urgency broadcasts

**Next Phase (First Validation Slice):**
- Integration testing of v0.22.x–v0.25.0 systems together
- One handcrafted test level with Civilian, Militia, Police, GI, Spec Ops, Costume Zombie, and Fat Zombie
- Validate core tactical puzzle loop is fun (Costume + Fat vs Police + barricaded GI is the target scenario)
- Tune morale/weapon values (kill counts currently higher than spec)

**Future Phases:**
- Building transformation system
- Remaining 9 special zombie types
- 3-5 complete levels with varied patrol patterns
- Refined art style selection
- Full campaign (10-20 levels)
- Audio implementation
- All defender varieties (civilian, police, military, spec ops, snipers)
- Playtesting and balance

---

## APPENDIX C: VERSION CHANGELOG (Recent)

**v0.25.0 (April 17, 2026):**
- Player-controlled engagement: zombies no longer auto-pursue; all engagements are player-initiated via right-click
- Group engagement resolver: right-click a human → finds all humans within 150px, distributes selected zombies via greedy bipartite assignment (max 2 per human, nearest-to-nearest)
- Overflow zombies (beyond 2× human count) move to the clicked position and join the fight
- Post-kill continuation: on target death, zombie scans 250px with LOS check; re-engages nearest available human automatically
- Commitment model: PURSUING state is freely redirectable; LEAPING and MELEE states are locked until target dies
- Attacker cap reduced 3→2 per human across zombie.gd, unit.gd, human.gd
- Zombie vision arcs removed entirely from vision_renderer.gd — arcs are now human-only visual language
- Tab key zombie vision cycling removed
- Removed: is_locked_in_pursuit, is_player_commanded, check_auto_pursuit(), propagate_pursuit_to_group(), can_see_unit(), is_in_vision_arc(), find_nearest_human_in_range()

**v0.23.1 (April 17, 2026):**
- High urgency alert system: unified `_broadcast_high_urgency_alert(event_pos, radius)` replacing separate gunshot system
- Ally grappled → nearby units within 75px face event directly after 0.4s (alongside existing morale drain)
- Ally killed → nearby units within 75px face event directly after 0.4s (alongside existing morale drain)
- Gunshot → nearby units within 150px face target after 0.4s
- All high urgency events: direct facing (0°, class-independent), shared 2s cooldown, 2s facing hold
- Civilians included in high urgency broadcasts (FLEEING state naturally excludes them once running)
- Low urgency facing return timer corrected: 120s → 30s

**v0.23.0 (March 19, 2026):**
- Detection alert: zombie in vision cone for 5s triggers alert to nearby allies (150px radius)
- Per-class side-aware facing offsets: allies on right get positive offset, left get negative
- Militia all face threat directly; Police ±45°/±90°; GI/Spec Ops ±105°/±165°
- Multiple same-side allies get increasing offsets (1st: 105°, 2nd: 165°)
- Alert cooldown 30s; facing returns to original after 30s of clear cone; patrol resumes after 30s
- All alert rotations smooth at 360°/sec (180° in 0.5s)
- FLEEING, GRAPPLED, DEAD, TUNNEL_VISION units immune to alert types

**v0.22.0–v0.22.5 (March 2026):**
- Five human defender classes: Civilian, Militia, Police, GI, Spec Ops
- Morale bar system replacing binary flee trigger and propagate_flee_to_group()
- Shooting system: per-class weapons, aim time, one-shot kills, tracer lines
- Dual-zone vision arcs: detection zone (350px) + shooting zone (weapon range)
- Tunnel Vision: 22.5° threat-facing locked cone, 10s, GI/Spec Ops
- Vision range: SENTRY/FLEEING arcs 180px → 350px
- Zombie death visual: dark red color, 0.3s delay, shot knockback tween (8px)
- Camera: 1.0× default zoom, 2.5× max, 1920×1080 windowed
- Navigation debug logging silenced
- Deprecations: propagate_flee_to_group(), panic_propagation_depth, binary flee trigger
- Spec amendments: ally radius 80px→150px, cone 45°→22.5°, threat-facing tunnel vision, bar-only morale visual
- Morale recovers to 50% on flee end and tunnel vision expiry

**v0.21.2 (March 7, 2026):**
- Depth-capped panic propagation (`panic_propagation_depth`, default 2)
- Distance-based cascade delays replace index-based delays

**v0.21.1 (March 7, 2026):**
- Formation follower polish: ramped catch-up speed (1.0–1.5×)
- Reduced BOID separation during convergence to prevent jostling

**v0.21.0 (March 7, 2026):**
- Formation squad patrols: leader/follower system
- Five formation shapes: LINE_ABREAST, COLUMN, WEDGE, ECHELON, DIAMOND
- Leader waits at waypoints for followers to regroup

**v0.20.0 (March 7, 2026):**
- Phase C: Per-waypoint pause durations, swing, and facing overrides
- Inspector export groups on Human and Unit

**v0.19.5 (March 3, 2026):**
- WorldBounds autoload singleton (centralised level bounds)

**v0.19.4 (March 2, 2026):**
- Removed waypoint visual markers (gameplay visibility issues)
- Editor movement fix (game logic disabled in editor)

**v0.19.2 (March 2, 2026):**
- Fixed waypoint order (natural string sort)
- Fixed swing behavior during patrol (disabled while moving)

**v0.19.0 (March 1, 2026):**
- Phase B2: Visual waypoint placement
- Child Node2D waypoint system

**v0.18.0 (February 28, 2026):**
- Phase B1: Manual waypoint patrol
- LOOP and PING_PONG modes

**v0.17.3 (February 27, 2026):**
- Navigation corner clearance optimization

**v0.17.0 (February 26, 2026):**
- Zombie navigation system (NavigationAgent2D)
- Panic spreading fixes (grapple-only trigger)

**v0.16.0 (February 25, 2026):**
- Panic spreading initial implementation

**v0.14.0 (February 20, 2026):**
- Phase A: Sentry degrees and swing arcs
- Editor visual indicators

---

**END OF DESIGN DOCUMENT**

---

**Document Maintenance:**
- Update this doc after each major milestone
- Track implemented features in Section 2
- Move resolved questions out of Section 12
- Archive old design decisions in change log

**Last Major Update:** v0.25.0 — special zombies (Fat + Costume), player-controlled engagement, 3D migration decision
**Next Planned Update:** First validation slice complete (handcrafted level + play sessions)
