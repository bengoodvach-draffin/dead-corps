# Dead Corps — Changelog v0.24.0

**Release Date:** March 19, 2026
**Focus:** Special Zombie Foundation + Fat Zombie

---

## Added

### `is_special` flag — `zombie.gd`
- New `var is_special: bool = false` on the `Zombie` base class
- When `true`, three systems are disabled:
  - `check_auto_pursuit()` returns immediately — zombie never auto-locks onto humans
  - `update_leap_state()` returns immediately — no speed boost, no guaranteed pin
  - Pack recruitment in `propagate_pursuit_to_group()` skips this zombie
- Player maintains full command of special zombies at all times
- **Architecture note:** subclasses set `is_special = true` in their own `_ready()` before calling `super._ready()`. Do NOT redeclare `is_special` as a variable in subclasses — this would create a shadowed copy that the parent checks wouldn't see.
- This is the shared foundation for all 11 planned special zombie types.

### `FatZombie` — `scripts/fat_zombie.gd` + `scenes/fat_zombie.tscn`
- Extends `Zombie`, sets `is_special = true`
- **Cannot attack:** `attack_damage` and `attack_range` both set to 0.0
- **Gunshot-only death:** `take_damage()` is overridden — damage is ignored unless `knockback_direction != Vector2.ZERO` (the signal of a gunshot). Melee, environmental, and other damage sources do nothing.
- **Corpse spawning:** on gunshot death, spawns a `FatZombieCorpse` node at its `global_position` then removes itself after 0.3s death flash
- `spawn_corpse_on_death: bool = true` — set to `false` by `escape_zone.gd` before calling `die()` to suppress corpse on clean escape-zone removal
- **Visual:** light green body `Color(0.6, 0.85, 0.6)`, sprite scaled 1.5×
- **Collision:** `CircleShape2D` radius 18px (vs regular 12px), selection ring scaled to 22px
- **Speed:** 90px/sec (matches regular zombie — flagged for tuning)

### `FatZombieCorpse` — `scripts/fat_zombie_corpse.gd` + `scenes/fat_zombie_corpse.tscn`
- `StaticBody2D` on collision layer 1 — physically blocks all unit movement
- Added to `"buildings"` group on `_ready()` — picked up by LOS raycasts in `human.gd` automatically
- **Visual:** 60×60px rectangle, dark green `Color(0.25, 0.38, 0.25)`
- Collision shape and visual both built in `_ready()` (no child nodes in scene — all procedural)
- **NavigationObstacle2D intentionally omitted:** `zombie.tscn` has `avoidance_enabled = false` on its `NavigationAgent2D`, so runtime obstacles have no navigation effect. Zombies will be physically blocked by the collision but won't route around the corpse cleanly. Enable avoidance and add `NavigationObstacle2D` in a future pass when nav avoidance is turned on.

---

## Changed

### `escape_zone.gd`
- Added `FatZombie` check in `_on_body_entered()`: if the entering zombie is a `FatZombie`, sets `spawn_corpse_on_death = false` before calling `die()`, so no permanent obstacle is left behind when the fat zombie walks off the level edge.

### `end_game_overlay.gd`
- Scoring now separates regular and special zombies:
  - Regular zombies (including incubating dead humans): **25 points each**
  - Special zombies (`FatZombie`, `CostumeZombie`): **100 points each**
- `CostumeZombie` included in the scoring check in preparation for v0.24.1

---

## Technical Notes

- `fat_zombie_corpse.tscn` has no child nodes — collision and visual are built procedurally in `_ready()`. This keeps the scene file minimal and avoids resource duplication.
- `FatZombie.die()` has a `_is_dying` guard to prevent double-trigger (e.g. if both escape zone and damage fire simultaneously).
- `FatZombie` inherits the full `register_manually_placed_units()` path in `game_manager.gd` because it extends `Zombie` — no changes needed to GameManager for tracking.

---

## How to Test

1. **Add a Fat Zombie to the scene:** Instance `scenes/fat_zombie.tscn`, place it in the level.
2. **Verify no auto-pursuit:** Run the game — Fat Zombie should stand still even when humans are nearby.
3. **Verify player control:** Right-click to move — Fat Zombie should respond normally.
4. **Verify no attack:** Walk Fat Zombie into a human — it should bump into them without dealing damage.
5. **Verify gunshot death + corpse:** Let a GI or Police shoot it. A dark green 60×60 rectangle should appear at its position. Regular zombies should be physically blocked by it.
6. **Verify LOS blocking:** Place a human on the far side of the corpse — a zombie on the near side should not be able to see it (no auto-pursuit triggered even for regular zombies).
7. **Verify escape zone:** Walk Fat Zombie into the escape zone — it should disappear with no corpse spawned.
8. **Verify scoring:** Let a Fat Zombie survive to the end screen — it should contribute 100pts, not 25pts.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/zombie.gd` | Added `is_special` flag; gated auto-pursuit, leap, pack recruitment |
| `scripts/fat_zombie.gd` | **NEW** — FatZombie class |
| `scripts/fat_zombie_corpse.gd` | **NEW** — FatZombieCorpse obstacle class |
| `scripts/escape_zone.gd` | Suppress Fat Zombie corpse on escape zone entry |
| `scripts/end_game_overlay.gd` | Separate scoring for regular vs special zombies |
| `scenes/fat_zombie.tscn` | **NEW** — Fat Zombie scene |
| `scenes/fat_zombie_corpse.tscn` | **NEW** — Fat Zombie Corpse scene |
| `docs/PROJECT_CONTEXT.md` | Updated to v0.24.0 |
| `docs/CHANGELOG_v0.24.0.md` | **NEW** — this file |
