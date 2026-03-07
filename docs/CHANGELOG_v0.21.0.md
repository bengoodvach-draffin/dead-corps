# Dead Corps - Changelog v0.21.0

**Release Date:** March 7, 2026
**Focus:** Formation Squad Patrols

---

## Added

### Formation Patrol System

Allows multiple humans to follow the same waypoint path while maintaining tactical formation spacing. One human is the **leader** (has waypoints configured as normal); others are **followers** who hold a NodePath reference to the leader and occupy a numbered slot in the formation.

---

### New enum: `FormationShape`

Set on the leader only. Determines how follower slots are arranged relative to the leader's facing direction:

| Shape | Description | Best for |
|---|---|---|
| `LINE_ABREAST` | Side by side perpendicular to travel | Open areas, wide coverage |
| `COLUMN` | Single file behind leader | Corridors, narrow paths |
| `WEDGE` | V-shape, leader at point | General purpose |
| `ECHELON` | Diagonal line right and behind | Flanking coverage |
| `DIAMOND` | Right, left, behind (3 followers) | Compact 4-unit squads |

---

### New Inspector properties — Leader subgroup (Patrol group):

**`formation_shape: FormationShape`** — Formation shape (default: WEDGE)
**`formation_spacing: float`** — Pixels between formation slots (default: 40.0)
**`formation_regroup_timeout: float`** — Seconds to wait at waypoints for followers before advancing (default: 10.0)

### New Inspector properties — Follower subgroup (Patrol group):

**`patrol_leader: NodePath`** — NodePath to the leader Human node. Set this to make this human a follower. Leave empty for leaders and standalone sentries.
**`formation_slot: int`** — Which slot in the formation (1-based, 1–7)

---

## Changed

- `update_patrol()` — Added regroup waiting logic. Leader holds at each waypoint (after any Phase C pause) until all SENTRY-state followers are within `formation_spacing × 2` of their slots, or `formation_regroup_timeout` expires.
- `_ready()` — Followers (non-empty `patrol_leader`) no longer initialise their own patrol or load child waypoints.
- `_physics_process()` — Routes followers to `update_formation_follow()` instead of `update_patrol()`.
- Swing gate updated — followers don't run swing arc (they face leader's direction instead).
- Facing direction update — followers face their movement direction while catching up, then mirror leader's facing when in position.

---

## New Functions

**`update_formation_follow(delta)`** — Per-frame follower update. Lazily resolves leader NodePath, checks leader validity, calculates formation slot target, and moves toward it. If leader is gone and follower is in SENTRY state, follower goes IDLE.

**`get_formation_offset(slot)`** — Pure math function. Returns the Vector2 offset for a given slot based on `formation_shape`, `formation_spacing`, and current `facing_direction`.

**`all_followers_in_formation()`** — Returns true if all SENTRY-state followers are within threshold of their slots. Ignores fleeing/grappled followers.

**`_has_followers()`** — Returns true if any human in the scene has a `patrol_leader` NodePath pointing to this node.

**`is_follower()`** — Returns true if this human has a `patrol_leader` set (public helper).

---

## Backwards Compatibility

All new properties default to empty/zero values. Existing sentries and patrols with no formation configuration behave identically to v0.20.0.

---

## Setup Instructions

**Squad of 4 (Leader + 3 followers):**

1. Create your leader human as normal — set waypoints, patrol mode, Phase C config etc.
2. For each follower:
   - Set `Initial State` = SENTRY
   - Set `Patrol Leader` = NodePath to the leader (drag the leader node into this field)
   - Set `Formation Slot` = 1, 2, or 3
   - Leave `Patrol Waypoints` empty
3. On the leader, set `Formation Shape` and `Formation Spacing` as desired.

**When the leader detects a zombie and flees**, followers detect independently via their own `check_for_nearby_zombies()`. Since `propagate_flee_to_group()` fires within 80px, the whole squad should react together in practice.

**When the leader dies**, all followers in SENTRY state automatically go IDLE.

---

## Testing

1. Create leader with 3 waypoints, LOOP mode
2. Create 2–3 followers with `patrol_leader` pointing to the leader, slots 1, 2, 3
3. Run — squad should walk together maintaining formation
4. Console: `⏳ WAITING TO REGROUP` when leader arrives at waypoint
5. Console: `✅ SQUAD REGROUPED` or `⏱️ REGROUP TIMEOUT` before advancing
6. Console: `⚠️ [name]: leader gone — going idle` if leader is killed
