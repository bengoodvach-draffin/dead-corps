# Dead Corps — Changelog v0.21.3

**Release Date:** March 7, 2026  
**Focus:** Bug fixes — flee system, patrol speed bleed, stuck detection, level bounds

---

## Fixed

### human.gd — Flee fallback dead code
`calculate_flee_direction()` had its entire fallback priority system (priorities 0.5–4) as
unreachable dead code. The `else:` branch was missing after the visible-threats early return,
so all five fallback priorities were trapped inside the `if` block. Humans stopped dead the
instant a zombie moved beyond vision range — no momentum, no pursuit awareness, no graceful
stop. Restructured as a proper `if/else`; deleted a duplicate dead block at the end. All five
priorities now fire correctly.

### human.gd — Patrol speed persisting into flee
`update_patrol()` wrote `move_speed = patrol_speed` (50) as a persistent mutation. When a
patrolling human transitioned to FLEEING, the value stuck — they fled at 50 px/s instead of
90 px/s, making them appear almost stationary compared to zombies. Added `_base_move_speed`
cached in `_ready()` after `super._ready()` sets the real value. All three `start_fleeing*`
entry points now restore it and explicitly set `is_patrolling = false`.

### zombie.gd — False stuck detection
`check_if_stuck()` compared position against `last_position` which updated every physics frame.
At 90 px/s and 60 fps, per-frame movement (~1.5 px) was always below the 5 px threshold, so
the stuck timer fired on every normally-moving zombie after ~2 seconds, calling
`clear_attack_target()` and dropping them to IDLE mid-chase. Replaced with an interval sampler:
checks every 0.5 s, requires 3 consecutive failures before triggering (movement threshold: 15 px
per interval vs ~45 px expected at normal speed).

### unit.gd — Boundary clamping from edge not centre
`clamp_position_to_bounds()` clamped the unit's centre point to `bounds_min/max`, so half the
sprite visually extended outside the level. Added `unit_radius` inset (matching the
CollisionShape2D radius) so the unit's edge stops at the boundary wall.

### selection_manager.gd — Formation positions clamped to hardcoded ±500
`calculate_formation_positions()` had `clamp(pos.x, -500, 500)` hardcoded. The single-zombie
path returned early and skipped the clamp — which is why one zombie in an expanded level worked
normally but two or more all marched toward the old boundary edge. Now reads from
`WorldBounds` autoload to stay in sync with actual level size.

---

## Added

### level_bounds.gd — Per-level bounds node
New `@tool` Node2D script. Place one in each level scene and set `bounds_min` / `bounds_max` in
the Inspector. On `_ready()` it writes those values into the `WorldBounds` autoload, so unit
clamping, camera, and formation positions all update automatically. Draws an orange rectangle in
both editor and at runtime so the level boundary is always visible. Replaces the old workflow of
editing `world_bounds.gd` directly.

**Usage:** Add Node2D to level → attach `level_bounds.gd` → rename `LevelBounds` → set bounds.

---

## No design changes
All fixes are infrastructure/behaviour corrections. No gameplay mechanics, stats, or design
decisions were altered. GDD not updated.
