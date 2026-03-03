# Dead Corps - Export Guide

## How to Export Your Game with a Specific Level

### Step 1: Set Your Main Scene

1. **Open Godot** and load your Dead Corps project
2. **In the FileSystem dock** (bottom-left), navigate to your test level:
   - `scenes/test_level_1.tscn`
3. **Right-click** on `test_level_1.tscn`
4. **Select** "Set as Main Scene"
   - OR -
5. **Menu Bar:** Project → Project Settings → Application → Run
6. **Set "Main Scene"** to `res://scenes/test_level_1.tscn`

**You'll know it worked when:**
- A small "play" icon appears next to your scene in the FileSystem
- Pressing F5 now runs your test level instead of main.tscn

---

### Step 2: Export Your Game

#### First-Time Export Setup:

1. **Menu Bar:** Project → Export...
2. **Click** "Add..." button
3. **Select your platform:**
   - Windows Desktop
   - macOS
   - Linux/X11
   - etc.
4. **Configure Export Template:**
   - If prompted, download export templates
   - Godot → Manage Export Templates → Download and Install

#### Export Settings:

**Windows Export Example:**
- **Name:** "Dead Corps - Test Level 1"
- **Runnable:** ✅ (checked)
- **Export Path:** Browse to where you want the .exe
  - Example: `C:/Games/DeadCorps/DeadCorps.exe`
- **Resources Tab:**
  - Embed PCK: ✅ (everything in one file)
  - Export Mode: "Export all resources in the project"

#### Export the Game:

1. **Select your export preset** (Windows Desktop, etc.)
2. **Click** "Export Project" button (bottom-right)
3. **Choose filename and location**
4. **Click** "Save"

**Result:** 
- You'll get a `.exe` file (Windows) or equivalent for your platform
- Double-click to run - it will launch `test_level_1.tscn`!

---

### Step 3: Testing Your Export

**Before distributing:**
1. **Run the exported .exe** on your machine
2. **Check:**
   - ✅ Correct level loads (test_level_1, not main)
   - ✅ All units spawn correctly
   - ✅ Escape zones work
   - ✅ No missing assets/graphics
   - ✅ Game ends properly when humans escape/die

---

## Common Export Issues

### Issue: Wrong Level Loads
**Solution:** Make sure you set test_level_1 as Main Scene BEFORE exporting

### Issue: Units Don't Spawn
**Cause:** Initializer might be disabled
**Solution:** 
- If using manual placement: Ensure GameManager.register_manually_placed_units() is working
- If using auto-spawn: Enable Initializer in your test_level_1 scene

### Issue: Missing Graphics/Assets
**Cause:** Godot didn't include all resources
**Solution:** 
- Export Settings → Resources → "Export all resources in the project"
- Or manually add resources to "Filters to export non-resource files"

### Issue: Export Template Missing
**Solution:** 
- Godot → Manage Export Templates
- Download the templates matching your Godot version

---

## Export Platforms

### Windows (.exe)
- **Platform:** Windows Desktop
- **File Extension:** .exe
- **Can run on:** Windows 7/8/10/11

### macOS (.app)
- **Platform:** macOS
- **File Extension:** .app bundle
- **Can run on:** macOS 10.12+
- **Note:** May need to sign/notarize for distribution

### Linux (.x86_64)
- **Platform:** Linux/X11
- **File Extension:** .x86_64 (or no extension)
- **Can run on:** Most Linux distributions

### Web (HTML5)
- **Platform:** Web
- **Output:** index.html + .wasm files
- **Can run:** In web browsers
- **Note:** Upload to itch.io or host yourself

---

## Multiple Export Presets

**You can have multiple export configurations:**

1. **"Dead Corps - Main Level"**
   - Main Scene: `scenes/main.tscn`
   - For testing original level

2. **"Dead Corps - Test Level 1"**
   - Main Scene: `scenes/test_level_1.tscn`
   - For showcasing your new level

**To switch:**
- Change "Main Scene" in Project Settings
- Re-export

---

## Distribution Checklist

Before sharing your game:
- [ ] Test exported .exe thoroughly
- [ ] Correct level loads
- [ ] All gameplay works
- [ ] Create README.txt with controls
- [ ] Include credits (Godot, your name)
- [ ] Zip the .exe (or bundle .app for macOS)
- [ ] Test on another computer (if possible)

---

## Quick Reference

**Set Main Scene:**
1. Right-click scene in FileSystem
2. "Set as Main Scene"

**Export Game:**
1. Project → Export...
2. Select platform preset
3. Click "Export Project"
4. Choose location
5. Save

**Test Export:**
1. Run the .exe
2. Verify correct level loads
3. Test all gameplay

---

## Troubleshooting

**Q: Game crashes on launch**
A: Check console for errors, ensure all scenes referenced exist

**Q: Performance issues in export**
A: Disable debug features (F1 overlay), optimize scene complexity

**Q: File size too large**
A: Compress textures, remove unused assets, enable PCK embedding

**Q: Game won't run on other computers**
A: Include Visual C++ redistributables (Windows), check architecture (32 vs 64-bit)

---

**Version:** v0.12.5
**Last Updated:** February 25, 2026
