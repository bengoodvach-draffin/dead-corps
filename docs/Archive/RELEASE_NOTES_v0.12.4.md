# Dead Corps v0.12.4 - STABLE RELEASE

**Release Date:** February 25, 2026  
**Status:** Stable - All Critical Bugs Fixed  

---

## 🎯 CRITICAL FIXES IN THIS RELEASE

### 1. Vision System Bug - FIXED ✅
**The Problem:** Zombies were vibrating/bouncing on grappled humans, repeatedly grabbing and releasing them.

**The Fix:** Added combat state check before vision checks. Zombies in combat now ignore vision system and maintain their grapple.

**Impact:** Zombies now properly hold humans until killed - smooth, reliable combat.

---

### 2. Collateral Grappling Bug - FIXED ✅
**The Problem:** When one zombie leaped at a human, nearby humans would also freeze.

**The Fix:** Grappling now requires active combat engagement (leaping OR in melee), not just proximity.

**Impact:** Only the targeted human freezes - clean, predictable combat behavior.

---

### 3. Building Resize Bug - FIXED ✅
**The Problem:** Building width changes wouldn't save in duplicated levels.

**The Fix:** Reversed property application logic - exported properties now set collision shape size.

**Impact:** Building editing works perfectly - both width and height save properly.

---

## 📦 WHAT'S INCLUDED

### Documentation (NEW!)
- **README.md** - Quick start guide, project overview
- **docs/BASELINE_SUMMARY_v0.12.4.md** - Complete feature reference
- **docs/CHANGELOG_v0.12.4.md** - Detailed technical changes
- **docs/GAME_DESIGN_DOCUMENT.md** - Full game concept

### Game Files
- All scenes (main, zombie, human, building, escape_zone)
- All scripts (complete AI, vision, combat systems)
- Manager systems (selection, game, vision rendering)

---

## 🎮 HOW TO USE

### Quick Start
1. **Extract** the zip file
2. **Open** `scenes/main.tscn` in Godot 4.x
3. **Press F5** to play

### Create Custom Levels
1. **Duplicate** main.tscn
2. **Select** Initializer node in scene tree
3. **Uncheck** "Enabled" checkbox in Inspector (disables auto-spawning)
4. **Manually place** zombies and humans
5. **Add buildings** for obstacles
6. **Place escape zones**

---

## ✅ WHAT'S WORKING

### Core Mechanics
- ✅ Zombie pursuit AI with vision-based detection
- ✅ Leap attacks that pin humans
- ✅ Melee combat with 3-attacker limit
- ✅ Human flee behavior (weighted threat calculation)
- ✅ Escape zone seeking
- ✅ Building obstacles (block movement + vision)
- ✅ Selection system (box select, commands)

### Combat System
- ✅ Zombies maintain grapples until kill (no more vibrating)
- ✅ Only targeted humans get grappled (no collateral)
- ✅ Combat engagement properly tracked
- ✅ Vision checks skip during active combat

---

## 🎯 NEXT STEPS

### Immediate Priorities
- Formation-based movement (prevent unit clumping)
- RTS-style movement polish
- Combat completion (damage, conversion mechanics)

### Future Features
- Human rescue mechanics
- Multiple zombie types
- Puzzle level design
- Animations and polish

---

## 🐛 KNOWN MINOR ISSUES

- Humans can clump when fleeing in groups (formation system planned)
- Basic pathfinding (no A* yet - simple direct movement)
- No damage/conversion yet (grapples don't kill/convert)

**None of these affect core gameplay loop.**

---

## 🔧 CONTROLS

### Gameplay
- **Left Click:** Select zombie
- **Box Drag:** Select multiple zombies
- **Right Click:** Command selected zombies to attack target
- **Arrow Keys / WASD:** Pan camera
- **Scroll Wheel:** Zoom in/out
- **F1:** Toggle debug overlay

### Debug Overlay Shows
- FPS counter
- Unit counts (zombies, humans, escaped)
- Vision cones (when enabled)
- Attack ranges

---

## 📋 DEVELOPMENT CONTEXT

This is a **portfolio project** demonstrating:
- Game AI (state machines, vision systems, weighted decisions)
- Unit control systems (selection, commands, targeting)
- Combat mechanics (grappling, leap attacks, melee)
- Debug visualization
- Full development pipeline (design → implementation → debugging)

**Tech Stack:**
- Engine: Godot 4.x
- Language: GDScript
- Perspective: Isometric 2D
- Genre: Tactical puzzle + RTS control

---

## 📚 DOCUMENTATION GUIDE

### Start Here
1. **README.md** - Quick overview and controls
2. **docs/BASELINE_SUMMARY_v0.12.4.md** - All features explained
3. **docs/CHANGELOG_v0.12.4.md** - Technical implementation details

### For Developers
- **GAME_DESIGN_DOCUMENT.md** - Original concept and philosophy
- **Older changelogs** - Version history and development progression

---

## 🎓 WHAT YOU CAN LEARN

This project demonstrates:
- **AI State Machines:** Clean state transitions for zombie/human behavior
- **Vision Systems:** Raycast-based line-of-sight with arc filtering
- **Weighted Decision Making:** Multi-threat flee calculations
- **Combat Priority Systems:** Combat > player commands > auto-pursuit
- **Debug Visualization:** Real-time overlay with grouped rendering
- **Unit Selection:** Box select with multi-select support

---

## ✨ STABILITY NOTES

**This is the most stable version to date:**
- All critical bugs from v0.12.0-0.12.3 have been fixed
- Combat mechanics work reliably
- No game-breaking issues
- Clean, organized codebase with comprehensive documentation

**Use this as your baseline for future development.**

---

## 🙏 CREDITS

**Developer:** Ben  
**Engine:** Godot 4.x  
**Inspiration:** Commandos, Shadow Tactics, RTS classics  

---

**Questions? Issues? Check the documentation or review the code comments - they're comprehensive!**

**Version:** v0.12.4  
**Status:** STABLE  
**Date:** February 25, 2026
