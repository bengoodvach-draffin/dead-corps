# Dead Corps - Tactical Zombie Puzzle Game

**Current Version:** v0.12.4  
**Status:** Stable - Core Mechanics Working  
**Engine:** Godot 4.x  
**Date:** February 25, 2026

---

## 🎮 Quick Start

### Play the Game
1. Open `scenes/main.tscn` in Godot 4.x
2. Press F5 to run
3. **Controls:**
   - **Left Click:** Select zombie
   - **Box Drag:** Select multiple zombies
   - **Right Click:** Command zombies to attack target
   - **Arrow Keys / WASD:** Pan camera
   - **Scroll Wheel:** Zoom
   - **F1:** Toggle debug overlay

### Create Levels
1. Duplicate `scenes/main.tscn` or create new scene
2. **Disable Auto-Spawning:** 
   - Select **Initializer** node in scene tree
   - In Inspector, **uncheck "Enabled"** checkbox
3. Manually place zombies and humans from `scenes/`
4. Add buildings for obstacles
5. Place escape zone(s)

---

## 📚 Documentation

### **Quick Reference**
- **[BASELINE_SUMMARY_v0.12.4.md](docs/BASELINE_SUMMARY_v0.12.4.md)** - Complete feature overview, architecture, development status

### **Recent Changes**
- **[CHANGELOG_v0.12.4.md](docs/CHANGELOG_v0.12.4.md)** - Vision bug fix, collateral grappling fix, building resize fix

### **Design Documents**
- **[GAME_DESIGN_DOCUMENT.md](docs/GAME_DESIGN_DOCUMENT.md)** - Full game concept, mechanics, design philosophy

### **Version History**
- [CHANGELOG_v0.12.0.md](docs/CHANGELOG_v0.12.0.md) - Selection system, combat commitment
- [CHANGELOG_v0.11.0.md](docs/CHANGELOG_v0.11.0.md) - Leap attacks, grappling
- [CHANGELOG_v0.10.0.md](docs/CHANGELOG_v0.10.0.md) - Vision system, obstacles
- [CHANGELOG_v0.9.x.md](docs/) - Flee behavior, basic pursuit

---

## ✅ What's Working (v0.12.4)

### Core Gameplay
- ✅ **Zombie AI:** Vision-based pursuit, leap attacks, melee combat
- ✅ **Human Behavior:** Weighted threat fleeing, escape seeking, panic propagation
- ✅ **Grappling:** Zombies pin humans with leap or melee attacks
- ✅ **Selection & Control:** Box select, right-click commands
- ✅ **Obstacles:** Buildings block movement and line-of-sight
- ✅ **Vision System:** Arc-based detection with grouping

### Recent Fixes
- ✅ **Vision Bug Fixed:** Zombies no longer abandon grappled targets mid-combat
- ✅ **Collateral Grappling Fixed:** Only combat-engaged zombies grapple humans (not proximity alone)
- ✅ **Building Resize Fixed:** Width and height changes now save properly

---

## 🎯 Project Goals

**Primary:** Portfolio piece demonstrating:
- Game design (tactical puzzle mechanics)
- Technical implementation (AI, vision systems, unit control)
- Full development pipeline (concept → playable prototype)

**Secondary:** Learning experience covering:
- Godot 4.x engine
- GDScript programming
- 2D isometric game development
- State management & AI behaviors

---

## 🏗️ Project Structure

```
/Dead Corps/
├── scenes/          # Game scenes (.tscn files)
│   ├── main.tscn    # Main game scene
│   ├── zombie.tscn
│   ├── human.tscn
│   ├── building.tscn
│   └── escape_zone.tscn
├── scripts/         # GDScript files
│   ├── zombie.gd    # Zombie AI & combat
│   ├── human.gd     # Human flee behavior
│   ├── building.gd
│   └── [managers]   # Game, selection, vision systems
└── docs/            # Documentation & changelogs
    ├── BASELINE_SUMMARY_v0.12.4.md
    ├── CHANGELOG_v0.12.4.md
    └── GAME_DESIGN_DOCUMENT.md
```

---

## 🎨 Game Concept

**Dead Corps** is a tactical puzzle game where you **command zombie hordes** to hunt down fleeing humans. Instead of defending against zombies, you ARE the zombie horde.

**Inspiration:** Commandos, Shadow Tactics, RTS movement mechanics  
**Perspective:** Isometric 2D (top-down angled)  
**Genre:** Tactical puzzle + RTS-style unit control

### Core Loop
1. Command zombies to pursue humans
2. Humans flee toward escape zones
3. Use buildings for cover/tactics
4. Grapple humans before they escape
5. Find optimal solution (puzzle element)

---

## 🔧 Development Status

### Completed
- Core zombie AI (pursuit, leap, melee)
- Human flee behavior (weighted threats)
- Vision & line-of-sight system
- Selection & command system
- Grappling mechanics
- Building obstacles

### In Progress
- Formation-based movement (prevent clumping)
- RTS-style movement polish
- Combat refinement (damage, conversion)

### Planned
- Human rescue mechanics
- Multiple zombie types
- Puzzle level design
- Animations & polish

---

## 🐛 Reporting Issues

When reporting bugs, please include:
1. **Version:** v0.12.4 (check logs or README)
2. **Steps to reproduce:** What actions trigger the bug?
3. **Expected behavior:** What should happen?
4. **Actual behavior:** What actually happens?
5. **Logs:** Copy relevant console output (if applicable)

---

## 📝 Development Notes

### Disable Auto-Spawning
To create custom levels without automatic zombie/human spawning:
- **Select:** Initializer node in scene tree
- **Uncheck:** "Enabled" in Inspector panel
- **Alternative:** Delete the Initializer node entirely

### Common Debugging
- **F1:** Toggle debug overlay (FPS, unit counts, vision cones)
- **Console logs:** Watch for grapple messages, combat state changes
- **Combat flags:** `is_melee_attacker`, `has_leap_grappled`, `is_committed_to_target`

### Performance Tips
- Group vision rendering (4+ units) saves draw calls
- Detection checks run every 0.1s (not every frame)
- Vision raycasts cached per frame

---

## 🎓 Learning Resources

This project demonstrates:
- **AI State Machines:** Zombie/human behavior states
- **Vision Systems:** Raycast-based line-of-sight with arc filtering
- **Unit Selection:** Box select, command system
- **Weighted Decision Making:** Multi-threat flee calculations
- **Priority Systems:** Combat engagement > player commands > auto-pursuit
- **Debug Visualization:** Real-time overlay system

---

## 📄 License

[Add license information here]

---

## 🙏 Credits

**Developer:** Ben  
**Engine:** Godot 4.x  
**Concept:** Original tactical zombie puzzle game  
**Inspiration:** Commandos, Shadow Tactics, classic RTS games

---

**Last Updated:** February 25, 2026  
**Version:** v0.12.4
