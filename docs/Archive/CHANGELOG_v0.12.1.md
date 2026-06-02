# v0.12.1 - Editor Removed, Building Improvements, Debug Logging

## What Changed

### 1. ❌ Level Editor Removed
All level editor files have been removed:
- `scenes/level_editor.tscn`
- `scripts/level_editor.gd`
- `scripts/level_loader.gd`
- `scripts/main_with_level_loading.gd`
- All documentation files

**Why:** Taking too much time to debug, focus should be on core gameplay.

---

### 2. ✅ Building Resizing Improved

**Before:**
- Buildings had "Scale" property (confusing)
- Had to drag orange handles in viewport

**Now:**
- Buildings have **Building Width** and **Building Height** properties in pixels
- Just type the dimensions you want directly in the Inspector!
- Range: 20-1000 pixels in 10-pixel increments
- Visual and collision update automatically

**How to use:**
1. Select a Building in the scene tree
2. In Inspector, find "Building Width" and "Building Height"
3. Type your desired pixel dimensions
4. Done!

---

### 3. 🐛 Debug Logging for Zombie Target Switching

Added comprehensive logging whenever a zombie switches targets mid-combat.

**What gets logged:**
```
🔄 ZOMBIE TARGET SWITCH
  Position: (x, y)
  FROM: Human@12345 at (x, y)
  TO: Human@67890 at (x, y)
  Combat State:
    is_melee_attacker: true/false
    is_committed_to_target: true/false
    has_leap_grappled: true/false
    is_leaping: true/false
  Control State:
    is_player_commanded: true/false
    is_locked_in_pursuit: true/false
  Call stack:
    [function call trace]
```

**Why:** To debug the issue where zombies abandon targets mid-combat and jump to new humans.

**What to look for:**
- Check the logs when you see a zombie abandon a grappled/melee target
- The call stack will show WHICH CODE PATH triggered the switch
- Combat state shows if zombie SHOULD have stayed locked to target

---

## Files Modified

**scripts/building.gd:**
- Added `@export building_width` and `@export building_height` properties
- Added `update_size_from_properties()` function
- Updated `_ready()` to initialize width/height from collision shape

**scripts/zombie.gd:**
- Added debug logging block in `set_attack_target()`
- Logs position, old/new target, combat state, control state, and call stack

---

## Next Steps

1. **Test building resizing** - much easier now with pixel dimensions
2. **Reproduce zombie bouncing** - watch the logs when it happens
3. **Analyze call stack** - see what's calling `set_attack_target()` during combat
4. **Fix root cause** - based on what the logs reveal

The logs will tell us exactly WHY zombies are switching - is it stuck detection? Melee management? Auto-pursuit? Something else?
