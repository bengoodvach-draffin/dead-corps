# Dead Corps - Changelog v0.20.0

**Release Date:** March 7, 2026  
**Focus:** Phase C - Per-Waypoint Observation Behaviour

---

## Added

### Three new export properties on `Human` (in Inspector under patrol section):

**`patrol_pause_durations: Array[float]`**  
- Pause duration in seconds at each waypoint. Index matches waypoint index.
- `0.0` or missing index = no pause (immediate advance, same as before).
- Empty array = no pauses anywhere (fully backwards compatible).
- Example: `[2.0, 0.0, 3.0]` — pause 2s at waypoint 0, skip waypoint 1, pause 3s at waypoint 2.

**`patrol_waypoint_swing: Array[bool]`**  
- Whether to swing the vision cone during the pause at each waypoint.
- Only has effect when the corresponding `patrol_pause_durations` entry is > 0.
- Uses existing `sentry_swing_range` / `sentry_swing_speed` / `sentry_swing_pause` settings.
- Works even if `sentry_has_swing` is false globally.
- Example: `[true, false, true]` — swing at waypoints 0 and 2, stand still at 1.

**`patrol_waypoint_facing: Array[float]`**  
- Facing direction override on arrival at each waypoint (degrees, same system as `sentry_facing_degrees`).
- `-1.0` = no override (keep facing the arrival direction).
- `0.0–360.0` = face this direction (0°=North, 90°=East, 180°=South, 270°=West).
- Applied before swing starts, so swing sweeps from the overridden direction.
- Example: `[90.0, -1.0, 270.0]` — face East at waypoint 0, no override at waypoint 1, face West at waypoint 2.

---

## Changed

- `update_patrol()` — fully reworked to support Phase C pause/swing/facing logic. Backwards compatible: sentries with no Phase C arrays configured behave identically to v0.19.5.
- `update_swing_arc()` — added optional `force: bool = false` parameter. Allows per-waypoint swing to run even when `sentry_has_swing` is globally false.

---

## Technical Details

- During a waypoint pause, `has_target = false` and `velocity = Vector2.ZERO` — sentry stops completely.
- Swing during pause is driven from within `update_patrol()`, not `_physics_process()`, to avoid double-calling.
- Facing override sets `swing_center_angle` so subsequent swing sweeps from the correct direction.
- `is_patrol_paused` and `is_waypoint_swinging` are the two new runtime state flags.
- Array length mismatches handled gracefully — short arrays simply mean "no configuration" for higher-indexed waypoints.

---

## Backwards Compatibility

All three new arrays default to empty (`[]`). Existing sentries with no Phase C properties set will behave exactly as they did in v0.19.5. No scene files need updating.

---

## Testing

**Basic pause test:**
1. Add sentry with 3 waypoints
2. Set `patrol_pause_durations = [2.0, 0.0, 3.0]`
3. Run — sentry should pause 2s at waypoint 0, pass through waypoint 1, pause 3s at waypoint 2
4. Console should show `⏸️ PATROL PAUSED` and `▶️ PATROL RESUMING` messages

**Facing override test:**
1. Add sentry with waypoints
2. Set `patrol_waypoint_facing = [90.0, -1.0]`
3. Run — sentry should snap to face East (90°) when arriving at waypoint 0
4. Console should show `🧭 FACING OVERRIDE at waypoint 0: 90.0°`

**Swing during pause test:**
1. Add sentry with waypoints
2. Set `patrol_pause_durations = [4.0]`, `patrol_waypoint_swing = [true]`
3. Run — sentry should stop at waypoint 0 and swing its vision cone for 4 seconds
4. Works regardless of whether `sentry_has_swing` is enabled globally

**Full observation behaviour test:**
1. Set `patrol_pause_durations = [3.0]`, `patrol_waypoint_swing = [true]`, `patrol_waypoint_facing = [180.0]`
2. Run — sentry arrives at waypoint 0, turns to face South (180°), swings vision cone for 3s, then continues
