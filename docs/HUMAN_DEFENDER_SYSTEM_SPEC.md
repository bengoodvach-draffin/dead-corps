# Dead Corps — Human Defender System Spec
**Date:** March 15, 2026
**Status:** Designed, not yet implemented
**Target version:** v0.22.0
**Replaces:** Binary flee trigger, depth-capped propagation chain

---

## Table of Contents
1. [Overview](#1-overview)
2. [Defender Classes](#2-defender-classes)
3. [Combat System](#3-combat-system)
4. [Morale System](#4-morale-system)
5. [Human States](#5-human-states)
6. [Zombie Death State](#6-zombie-death-state)
7. [Vision System Updates](#7-vision-system-updates)
8. [Camera & Scale](#8-camera--scale)
9. [Deprecations](#9-deprecations)
10. [Secondary Responses (Deferred)](#10-secondary-responses-deferred)
11. [GDD Updates](#11-gdd-updates)
12. [PROJECT_CONTEXT Updates](#12-project_context-updates)
13. [Development Plan](#13-development-plan)

---

## 1. Overview

This spec introduces five differentiated human defender classes, a unified morale bar system replacing the existing binary flee/panic architecture, a full shooting system, and visual/scale updates to align with Shadow Tactics-style zoom level.

**Core design principle:** The morale bar does all the interesting work. Class differentiation emerges from morale max values and drain rates rather than hardcoded thresholds. Randomness in *when* panic spreads is interesting; randomness in *what happens* is kept minimal.

---

## 2. Defender Classes

### 2.1 Combat Table

| Unit | Weapon | Range | Aim Time | Kills (frontal) | Primary Response |
|------|--------|-------|----------|-----------------|------------------|
| Civilian | Unarmed | — | — | 0 | Flee |
| Militia | Shotgun | ~150px | 0.7s | 1 | Flee |
| Police | Pistol | ~150px | 0.55s | 2 | Flee |
| GI | Assault Rifle | ~250px | 0.525s | 4 | Tunnel Vision |
| Spec Ops | Assault Rifle | ~250px | 0.26s | 8 | Tunnel Vision |

### 2.2 Class Notes
- **Civilian** — panics on any sighting, collapses almost immediately, cannot fight back
- **Militia** — same range as police but slower aim; holds nerve against 1-3 zombies, morale collapses against 4+ before they can shoot
- **Police** — ignores sightings, breaks under sustained social pressure; reliably kills 2 zombies before being overwhelmed
- **GI** — nearly unbreakable except when allies are grappled; requires panic, stealth, or overwhelming numbers
- **Spec Ops** — effectively immune under normal conditions; tunnel vision means even when morale empties they keep fighting but become flanakble

### 2.3 Shared Stats (All Classes)
- Health: 75
- Move speed: 90px/sec
- Vision cone angle: 90°
- No shooting while fleeing
- One-shot kills: 50 damage (humans have 75hp)

---

## 3. Combat System

### 3.1 Shooting Rules
- Armed units only shoot within their vision cone
- Units actively track acquired targets (turn to face them)
- Buildings block shots (reusing existing LOS raycast)
- Other units do not block shots
- Closest zombie targeted first
- No friendly fire
- Grappling zombies can be shot; grappled human survives
- No shooting while in FLEEING state

### 3.2 Aim Time
- Starts when a zombie enters the unit's vision cone (target acquisition)
- When timer reaches zero the shot fires
- After firing, new target acquired and timer resets
- **Mid-aim loss of sight:** timer pauses until target reacquired; if new target acquired instead, timer resets fully

### 3.3 Gun Visual — Tracer Line
- On firing: instant line drawn from unit barrel position to target
- Line fades over ~0.1s
- Communicates range, direction, and which unit fired
- No audio required for readability (placeholder until audio added)

### 3.4 Engagement Timing Reference
With 350px vision and zombie speed 105px/s:

| Unit | Free aim time (vision→weapon range) | Time in weapon range | Kills before melee |
|------|--------------------------------------|---------------------|--------------------|
| Militia | 1.9s | 1.1s | 1 |
| Police | 1.9s | 1.1s | 2 |
| GI | 0.95s | 2.1s | 4 |
| Spec Ops | 0.95s | 2.1s | 8 |

---

## 4. Morale System

### 4.1 Architecture
Every defender has a `morale` value starting at `morale_max`. Stress events drain it continuously or in flat hits. When it reaches zero the unit executes its primary response.

**This replaces:**
- Binary direct-sighting flee trigger
- `propagate_flee_to_group()` depth-capped cascade
- `panic_propagation_depth` export

### 4.2 Morale Drain Table

| Unit | Morale Max | Sighting (/sec) | Ally grappled (flat) | Ally fleeing (flat) | Ally killed (flat) |
|------|-----------|----------------|---------------------|--------------------|--------------------|
| Civilian | 65 | 30 | 100 | 50 | 150 |
| Militia | 150 | 35 | 100 | 40 | 150 |
| Police | 200 | 0 | 100 | 40 | 150 |
| GI | 400 | 0 | 275 | 20 | 150 |
| Spec Ops | 1000 | 0 | 100 | 0 | 150 |

### 4.3 Drain Event Definitions

**Sighting (continuous /sec):**
- **Armed units (Militia, Police, GI, Spec Ops):** drain activates only when zombie is within weapon range. Seeing a zombie beyond weapon range starts the aim timer but does NOT drain morale. Only when the zombie closes to firing range does morale begin draining.
- **Civilians:** drain activates at full vision range (350px) since they have no weapon threshold.
- Multiple zombies within range stack: 3 in weapon range = 3× drain rate.

**Ally grappled (flat one-time hit):**
- Triggers once when a nearby ally transitions to GRAPPLED
- Radius: 80px
- One hit per grapple event

**Ally fleeing (flat one-time hit):**
- Triggers when a fleeing ally moves through vicinity
- Requires movement — stationary fleeing unit doesn't trigger
- Radius: 80px

**Ally killed (flat one-time hit):**
- Triggers on nearby ally death (not conversion — death is the traumatic moment)
- Radius: 80px

### 4.4 Key Scenario Validation

**Single zombie approaching (3.0s total approach from 350px):**
- Civilian: drains from 350px, empties at ~2.2s, flees well before contact ✅
- Militia: drain starts at 150px, holds nerve, shoots at t=2.6s ✅
- Police/GI/Spec Ops: hold nerve, shoot comfortably ✅

**Two zombies approaching:**
- Civilian: flees in 1.1s ✅
- Militia: holds for one kill, grappled by second ✅
- Police: kills both ✅

**Five zombies approaching:**
- Militia: 175/sec drain (35 × 5) once all in weapon range, morale empties in under 1s, flees before shooting ✅
- Police: kills 2, grappled by third ✅
- GI: kills 4, grappled by fifth ✅
- Spec Ops: kills all 5 ✅

**Squad cascade (grapple chain):**
- Civilian: instant on first grapple ✅
- Militia/Police/GI: second grapple breaks them ✅
- Spec Ops: holds firm ✅

### 4.5 Visual Representation
- Color tint shifts as morale drains (green → yellow → red)
- Morale bar appears below unit when morale drops below a threshold (invisible when healthy)

---

## 5. Human States

### 5.1 Existing States (Unchanged)
IDLE, SENTRY, FLEEING, GRAPPLED, DEAD

### 5.2 New States

**TUNNEL VISION** — GI and Spec Ops primary response when morale empties

*Mechanic:*
- Duration: 10 seconds
- Unit rotation locks in the direction of current target at moment of trigger
- Vision cone narrows from 90° to 45°
- Unit keeps shooting at whatever enters the narrowed cone
- Zombies approaching from outside the 45° cone are completely undetected
- Immune to all morale drain events while active
- After 10 seconds: reverts to SENTRY, rotation unlocks, cone returns to 90°

*Tactical implication:*
- Player must deliberately provoke tunnel vision (e.g. using Costume Zombie to approach safely)
- Once triggered, flanking zombies can approach freely from outside the cone
- Creates a sustained 10-second exploitable blind spot

**FREEZE** — Civilian only (deferred — see Section 10)
- 5-second paralysis before fleeing
- Defined as full state for future implementation

**MELEE CHARGE** — Militia only (deferred — see Section 10)
- Moves toward target at normal speed
- While cooldown inactive: invulnerable, unpinnable, first zombie contacted dies instantly
- After swing: 5-second cooldown, now vulnerable and pinnable
- If pinned during cooldown: cannot fight back
- No targets after cooldown → revert to SENTRY after 10 seconds

### 5.3 State Transitions
```
IDLE → SENTRY
SENTRY → FLEEING (morale empties, flee classes)
SENTRY → TUNNEL VISION (morale empties, GI/Spec Ops)
SENTRY → GRAPPLED
FLEEING → GRAPPLED
TUNNEL VISION → SENTRY (after 10 seconds)
GRAPPLED → DEAD
```

---

## 6. Zombie Death State

### 6.1 Existing State
Zombies already have a DEAD state triggered on melee kill. This handles death by shooting without a new state.

### 6.2 Visual Representation
- On death (any cause): zombie sprite changes to **dark red** (Color(0.4, 0.0, 0.0))
- Darker than dead human to clearly distinguish the two
- Dead human color: medium red (Color(0.7, 0.1, 0.1))
- On death by shooting: small knockback impulse in direction of shot before fade
- Body remains briefly then fades — match existing melee death timing
- Dead body: non-interactive, no collision, no targeting

---

## 7. Vision System Updates

### 7.1 Range Changes

| State | Current | Updated |
|-------|---------|---------|
| Idle circle (all classes) | 100px | 100px (unchanged) |
| Sentry arc | 180px | 350px |
| Fleeing arc | 180px | 350px |
| Tunnel Vision arc | N/A | 45° cone, locked rotation, 10s |

### 7.2 Dual-Zone Vision Arc (New)

**Zone 1 — Detection zone (350px, outer):**
- Light/transparent fill
- Zombies here trigger aim timer
- Armed units: morale drain does NOT activate here
- Civilians: morale drain activates here

**Zone 2 — Shooting zone (weapon range, inner):**
- Solid/brighter fill
- Militia/Police: 150px
- GI/Spec Ops: 250px
- Civilian: no inner zone (single zone only)
- Zombies here trigger both aim timer and morale drain

**Implementation:** Extend VisionRenderer to draw two concentric arcs with different alphas per unit type. Weapon range exported per class, passed to renderer.

---

## 8. Camera & Scale

### 8.1 Target Zoom
- Reference: Shadow Tactics (~2.5×)
- At 2.5× on 1080p: ~768 × 432 game units visible
- Units appear ~60px on screen

### 8.2 On-Screen Size Reference

| Value | Game units | On screen at 2.5× |
|-------|-----------|-------------------|
| Unit diameter | 24px | 60px |
| Vision arc | 350px | 875px |
| Weapon range GI | 250px | 625px |
| Weapon range Militia/Police | 150px | 375px |
| World bounds | ±1000px | ~38% visible at once |

### 8.3 Implementation Note
Camera zoom already functional. Set default starting zoom to ~2.5×. No new camera code required.

---

## 9. Deprecations

| Item | Location | Replacement |
|------|----------|-------------|
| `propagate_flee_to_group()` | human.gd | Morale drain system |
| `panic_propagation_depth` export | human.gd | No longer needed |
| Binary direct-sighting flee trigger | human.gd | Sighting drain within weapon range |
| Hardcoded morale threshold logic | human.gd | Emergent from morale values |

---

## 10. Secondary Responses (Deferred — Design Record Only)

Removed from scope to reduce complexity. Documented here for future implementation.

| Unit | Secondary Response | Chance | Notes |
|------|-------------------|--------|-------|
| Civilian | Freeze | 10% | 5s paralysis before fleeing |
| Militia | Melee charge | 15% | Rush first zombie, one-shot, then vulnerable |
| Police | Ranged fight | 10% | Suppresses flee, keeps shooting |

If re-implemented: add accessibility setting to disable secondary responses.

---

## 11. GDD Updates

**Section 2.1 — Add to Not Yet Implemented:**
Five defender classes, morale bar system, shooting system with tracer lines, dual-zone vision arcs, tunnel vision state, zombie death visuals.

**Section 3.4 — Replace Panic Spreading with Morale System:**
Use Section 4 of this spec.

**Section 6.1 — Replace sentry-only defender description:**
Use the five-class combat table from Section 2.

**Section 3.6 — Update Vision System:**
- Human SENTRY and FLEEING arcs: 350px (was 180px)
- Idle circle: 100px (unchanged)
- Dual-zone arcs: detection zone (350px) + shooting zone (weapon range)
- Morale drain activates in shooting zone for armed units, full range for civilians
- Tunnel Vision: 45° cone, locked rotation, 10s duration

**Section 4 — Update Human Stats:**
```
Vision (Sentry/Fleeing): 350px arc, 90° (was 180px)
Vision (Idle): 100px circle (unchanged)
Vision (Tunnel Vision): 45° cone, locked, 10s
Morale drain radius: 80px
```

---

## 12. PROJECT_CONTEXT Updates

**What's Implemented — add:**
```
❌ Human Defender Classes (v0.22.0 — designed, not implemented):
- Five classes: Civilian, Militia, Police, GI, Spec Ops
- Morale bar replacing binary flee trigger and propagate_flee_to_group()
- Shooting system with aim time and tracer lines
- Dual-zone vision arcs (detection + shooting range)
- Tunnel Vision state for GI/Spec Ops
- Zombie death visual (dark red color + shot knockback)
- See HUMAN_DEFENDER_SYSTEM_SPEC.md
```

**Known Issues — add:**
```
⚠️ Vision range (pre-v0.22.0):
- Human SENTRY/FLEEING arcs currently 180px, increasing to 350px in v0.22.0
```

**Default Values — update:**
```
Human vision (SENTRY/FLEEING): 350px (was 180px)
Human vision (IDLE): 100px (unchanged)
Morale drain radius: 80px
Weapon range Militia/Police: 150px
Weapon range GI/Spec Ops: 250px
Tunnel Vision duration: 10s
Tunnel Vision cone: 45°
Dead zombie color: Color(0.4, 0.0, 0.0)
Dead human color: Color(0.7, 0.1, 0.1)
```

**Scripts Inventory:** No new files required. All additions go into human.gd and vision_renderer.gd. Check inventory before creating any new resource or enum files.

---

## 13. Development Plan

### Phase 1 — Defender Class Scaffolding (v0.22.0)
No behaviour changes. Add class system and exports.

- Add `DefenderClass` enum: CIVILIAN, MILITIA, POLICE, GI, SPEC_OPS
- Add `@export var defender_class: DefenderClass`
- Add morale exports: morale_max, sighting_drain, grappled_drain, fleeing_drain, killed_drain
- Add weapon exports: weapon_range, aim_time
- Populate default values per class from spec tables
- Update Scripts Inventory

Validation: Existing behaviour unchanged. Exports visible and correct in Inspector.

---

### Phase 2 — Vision Range + Dual-Zone Arc (v0.22.1)

- Update SENTRY and FLEEING arc range to 350px
- Extend VisionRenderer for two radii: detection_range + weapon_range
- Outer zone: transparent fill (detection)
- Inner zone: solid fill (shooting range)
- Civilian: single zone only
- Set camera default zoom to ~2.5×

Validation: 350px cones on all humans. Armed units show inner shooting zone. Civilian shows single zone. Camera at correct zoom.

---

### Phase 3 — Morale Bar (v0.22.2)

- Add `morale` and `morale_max` to human.gd
- Sighting drain in `_physics_process()`:
  - Armed: count visible zombies within weapon_range, drain × count × delta
  - Civilian: count visible zombies within full vision range, drain × count × delta
- Ally event hooks (80px radius):
  - Ally → GRAPPLED: apply grappled_drain
  - Fleeing ally moves through radius: apply fleeing_drain
  - Ally dies: apply killed_drain
- Morale reaches 0 → execute primary response per class
- Morale visual: color tint + bar below threshold
- Remove `propagate_flee_to_group()`, `panic_propagation_depth`, binary flee trigger
- Debug: 📉 [Name] morale draining, 💀 [Name] morale empty → [response]

Validation: Civilians flee from single zombie at distance. Armed units hold until weapon range. Militia flees from 5 zombies. GI breaks on 2 grapples.

---

### Phase 4 — Shooting System (v0.22.3)

- Add `aim_timer` and `current_target` to human.gd
- Target acquisition starts aim_timer
- Timer reaches 0: fire (50 damage), acquire new target, reset timer
- Target lost: pause timer; new target: reset timer
- LOS check before firing
- No shooting in FLEEING state
- Tracer line on fire: draw line unit→target, fade 0.1s
- Debug: 🎯 [Name] acquired target, ⚡ [Name] fired

Validation: Each class kills correct number frontally. Timer pauses on LOS loss. Tracer visible. No shooting while fleeing.

---

### Phase 5 — Tunnel Vision State (v0.22.4)

- Add TUNNEL_VISION to state enum
- GI/Spec Ops: transition to TUNNEL_VISION when morale reaches 0
- On entry: lock rotation, narrow cone 90°→45°, start 10s timer
- Suppress all morale drain events while active
- Peripheral zombies outside 45° cone undetected
- Timer expires: revert to SENTRY, unlock rotation, restore 90° cone
- Update VisionRenderer to render 45° cone in TUNNEL_VISION
- Debug: 🔍 [Name] tunnel vision triggered, 🔓 [Name] tunnel vision ended

Validation: Cone visibly narrows. Flanking zombies approach unseen. Reverts after 10s.

---

### Phase 6 — Zombie Death Visual (v0.22.5)

- On zombie death: sprite → dark red Color(0.4, 0.0, 0.0)
- On death by shooting: small knockback impulse in shot direction
- Confirm dead human color: Color(0.7, 0.1, 0.1)
- Body fade: match existing melee death timing

Validation: Dead zombies visually distinct from dead humans. Shot knockback readable at 2.5× zoom.

---

### Phase 7 — Integration Testing (v0.22.6)

- Build test level with all five defender classes
- Validate all scenarios from Section 4.4
- Tune morale values if needed
- Validate dual-zone arcs, tunnel vision cone, tracer lines, death visuals
- Confirm all deprecations complete, no regressions

---

### Out of Scope
FREEZE state, MELEE CHARGE, Police ranged fight, morale regeneration tuning, audio.

---

**END OF SPEC**

*Next session: Phase 1 — defender class scaffolding. Ben to provide ZIP or confirm GitHub up to date.*
