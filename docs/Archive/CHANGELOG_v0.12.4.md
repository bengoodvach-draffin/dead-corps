# Dead Corps - Changelog v0.12.4

**Release Date:** February 25, 2026  
**Focus:** Critical Bug Fixes - Zombie Vision & Collateral Grappling

---

## 🎯 Critical Fixes

### Vision System Bug Fixed (Major)
**Problem:** Zombies were abandoning grappled humans mid-combat, creating a "vibrating" effect where they would repeatedly grapple and release targets.

**Root Cause:** The `check_auto_pursuit()` vision check was running even during active combat. When a human was grappled directly under/very close to a zombie, the vision cone couldn't see them, causing the zombie to clear its target despite ALL combat flags being true (melee_attacker, committed, leap_grappled).

**Solution:** Added combat state check BEFORE vision check. If zombie is in combat (melee_attacker OR committed OR leap_grappled), skip vision checks entirely and stay locked to target.

**Files Modified:** `scripts/zombie.gd`
```gdscript
// NEW: Check combat BEFORE vision
if attack_target and is_instance_valid(attack_target):
    var in_combat = is_melee_attacker or is_committed_to_target or has_leap_grappled
    if in_combat:
        return  // Stay locked, ignore vision

// Only check vision for non-combat pursuit
```

**Impact:** ✅ Zombies now maintain grapples until human is killed - no more mid-combat releases

---

### Collateral Grappling Bug Fixed (Major)
**Problem:** When a zombie leaped at one human, nearby humans would also freeze. Investigation revealed zombies could grapple humans just by walking within 50px proximity.

**Root Cause:** The `is_being_attacked()` function checked: "Is zombie within 50px AND targeting me?" without verifying the zombie was actually engaged in combat. Zombies approaching their target would inadvertently grapple nearby humans.

**Solution:** Added combat engagement verification - only grapple if zombie is actively leaping or in melee combat.

**Files Modified:** `scripts/human.gd`
```gdscript
// OLD: Grapple if zombie within 50px + targeting
if distance <= 50.0 and zombie.attack_target == self:
    # GRAPPLE!

// NEW: Verify zombie is combat-engaged
if distance <= 50.0 and zombie.attack_target == self:
    var is_combat_engaged = zombie.has_leap_grappled or zombie.is_melee_attacker
    if not is_combat_engaged:
        continue  // Skip - zombie just walking nearby
    # GRAPPLE!
```

**Impact:** ✅ Only targeted humans freeze when attacked - no more collateral freezing from proximity

---

### Building Resize Bug Fixed (Minor)
**Problem:** When duplicating levels, building width changes wouldn't save - only height changes persisted.

**Root Cause:** In `building.gd` `_ready()`, the code was reading FROM the collision shape and overwriting the exported properties, instead of applying the properties TO the shape.

**Solution:** Reversed the logic - now exported properties set the collision shape size.

**Files Modified:** `scripts/building.gd`
```gdscript
// OLD: Read from shape (overwrites user settings)
building_width = shape.size.x
building_height = shape.size.y

// NEW: Apply user settings to shape
shape.size = Vector2(building_width, building_height)
```

**Impact:** ✅ Both width and height changes now save properly

---

## 🧹 Technical Improvements

### Initializer Toggle Added
- Added `@export var enabled: bool = true` to Initializer script
- Can now disable auto-spawning via Inspector checkbox
- Makes custom level creation easier (no need to delete node)

### Debug Logging Cleanup
- Removed excessive combat state logging added during debugging
- Kept essential gameplay messages (grapples, leap announcements, melee entry)
- Removed all proximity check spam (was logging every zombie within 100px every frame)
- Fixed parse errors (GDScript string multiplication, invalid UID warnings)

### Code Quality
- Simplified grapple state transitions (removed duplicate logic)
- Improved code comments explaining vision/combat interaction
- Standardized logging format across human and zombie scripts

---

## 📋 Version History Context

**v0.12.0 → v0.12.4 Bug Fix Progression:**
- v0.12.1: Initial investigation - added comprehensive debug logging
- v0.12.2: Removed human escape mechanic, fixed building shared resources
- v0.12.3: Enhanced logging revealed vision bug, partial fixes
- v0.12.4: Final fixes for vision and collateral grappling bugs

---

## 🎮 Gameplay Impact

**Before v0.12.4:**
- Zombies would grapple humans, then immediately release them (vibrating effect)
- Nearby humans would freeze when zombies walked past
- Building editing frustrating (width changes didn't save)

**After v0.12.4:**
- ✅ Zombies maintain grapples until kill - proper predator behavior
- ✅ Only targeted humans get grappled - clean combat engagement
- ✅ Building editing works as expected

---

## 📦 Files Changed

### Modified
- `scripts/zombie.gd` - Added combat check before vision in check_auto_pursuit()
- `scripts/human.gd` - Added combat engagement check to is_being_attacked()
- `scripts/building.gd` - Fixed property application in _ready()
- `scenes/main.tscn` - Removed invalid script UIDs

### Testing Notes
- Test zombie grapple persistence: Zombie should hold human until conversion/death
- Test collateral freezing: Only leap/melee targets should freeze
- Test building resize: Both width and height should save in duplicated levels

---

## 🔮 Next Steps

**Immediate Priorities:**
- Formation-based movement to prevent unit clumping
- Professional RTS-style movement feel
- Combat refinement (damage dealing, conversion mechanics)

**Future Features:**
- Human rescue mechanics (when combat system allows)
- Multiple zombie types
- Tactical puzzle level design
