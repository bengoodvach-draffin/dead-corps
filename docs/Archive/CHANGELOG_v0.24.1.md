# Dead Corps — Changelog v0.24.1

**Release Date:** March 19, 2026
**Focus:** Costume Zombie

---

## Added

### `CostumeZombie` — `scripts/costume_zombie.gd` + `scenes/costume_zombie.tscn`
- Extends `Zombie`, sets `is_special = true`
- `is_costumed: bool = true` — while true, this zombie is invisible to all human detection systems
- **Disguise break trigger:** permanently breaks when the zombie pins a human (target transitions to `GRAPPLED` state). Not on chase start, not on first attack — only on the pin.
- After break: full human detection resumes, zombie behaves identically to a regular zombie
- **Visual:** pink `Color(1.0, 0.4, 0.8)` while costumed; reverts to standard zombie green `Color(0.4, 0.6, 0.3)` on break
- Standard stats: health 50, move speed 90, attack damage 15, attack range 25

---

## Changed

### `human.gd` — detection suppression (three touch points)
All three use `zombie.get("is_costumed") == true` — property check, no class name dependency, avoids GDScript load order issues.

- **`find_nearest_visible_zombie()`** — flee detection skips costumed zombies entirely. Human will not flee from a costumed zombie regardless of proximity.
- **`check_for_nearby_zombies()` drain/vision count loop** — costumed zombies excluded from both `new_drain_count` and `new_vision_count`. This means: no morale sighting drain, and no contribution to `_zombies_in_vision_count` which drives the 5-second alert cone timer.
- **`_acquire_shoot_target()`** — costumed zombies cannot be acquired as shoot targets. Aim timer never starts.

Net effect: while costumed, this zombie is completely transparent to all human systems — flee, morale, shooting, alerting, and gunshot response.

---

## Design Notes

- Human reaction to a costumed zombie biting a nearby ally may need strengthening. The `grappled_drain` morale event fires normally when the pin happens, but the dramatic surprise of a disguised zombie suddenly attacking may warrant a larger hit or a dedicated "betrayal" event. Flagged for post-validation tuning.
- The disguise breaking on pin (not on attack start) is intentional — the human doesn't know something is wrong until it's too late. This creates clean assassination plays.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/costume_zombie.gd` | **NEW** — CostumeZombie class |
| `scripts/human.gd` | Costumed zombie skipped in flee detection, morale drain, aim acquisition |
| `scenes/costume_zombie.tscn` | **NEW** — Costume Zombie scene |
| `docs/PROJECT_CONTEXT.md` | Updated to v0.24.1 |
| `docs/CHANGELOG_v0.24.1.md` | **NEW** — this file |
