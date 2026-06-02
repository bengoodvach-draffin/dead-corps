# Dead Corps v0.19.5 - WorldBounds World Bounds

## Summary
Replaced hardcoded boundary constants with a centralized `WorldBounds` autoload singleton. World bounds are now defined in one place and automatically applied to all units and the camera.

---

## What Changed

### Added
- `scripts/world_bounds.gd` — New autoload singleton, single source of truth for world bounds

### Changed
- `scripts/unit.gd` — Removed `GAME_BOUNDS_MIN/MAX` constants; now reads from `WorldBounds`
- `scripts/camera_controller.gd` — Camera bounds now default to `WorldBounds` values on `_ready()`

---

## Setup Required (One-time)

You must register WorldBounds as an Autoload:

1. **Project → Project Settings → Autoload**
2. Click the folder icon and select `res://scripts/world_bounds.gd`
3. Set Name to `WorldBounds`
4. Click **Add**

---

## How to Change World Size

Open `world_bounds.gd` (or select the WorldBounds node if it's in your scene) and change:

```gdscript
@export var world_bounds_min: Vector2 = Vector2(-1000, -1000)
@export var world_bounds_max: Vector2 = Vector2(1000, 1000)
```

That's it — all units and the camera update automatically.

### Common Sizes
| Level Size  | bounds_min       | bounds_max      | World Size  |
|-------------|-----------------|-----------------|-------------|
| Small       | (-500, -500)    | (500, 500)      | 1000×1000   |
| Medium      | (-1000, -1000)  | (1000, 1000)    | 2000×2000   |
| Large       | (-2000, -1500)  | (2000, 1500)    | 4000×3000   |
| Rectangular | (-800, -400)    | (800, 400)      | 1600×800    |

---

## Camera Override (Optional)

The camera will auto-sync to WorldBounds bounds on startup. If you need different bounds per scene, simply set `bounds_min` / `bounds_max` directly on the Camera2D node in the Inspector — it won't be overridden as long as the values differ from the old ±500 defaults.

---

## No Breaking Changes
- All existing gameplay behavior is identical
- Unit clamping and target clamping work the same way
- Default bounds expanded from ±500 to ±1000 (gives you more room by default)
