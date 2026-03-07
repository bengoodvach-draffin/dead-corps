# Dead Corps - Changelog v0.21.1

**Release Date:** March 7, 2026
**Focus:** Formation follower movement polish

---

## Fixed

### Followers pushing each other off their paths

Formation followers were applying full BOID separation forces while converging on their slots, causing them to shove each other sideways. Fixed by detecting when a follower is still converging (`distance_to_slot > formation_slot * 5px`) and reducing separation to near-zero during that phase:

- Converging: `separation_radius = 8px`, `separation_strength = 20` — soft nudge only, lets them pass through each other's space
- In position: `separation_radius = 20px`, `separation_strength = 80` — light separation to avoid stacking

### Followers not catching up after falling behind

Followers were always moving at the leader's `patrol_speed` regardless of how far behind they were. Fixed with a smoothly ramped speed multiplier:

- In slot: 1× patrol speed
- 1× `formation_spacing` behind: ~1× patrol speed
- 2× `formation_spacing` behind: ~2× patrol speed  
- Maximum: 2.5× patrol speed (hard cap)

Speed ramps smoothly via `lerp(current, target, 0.1)` each physics frame — no sudden jumps when falling behind or snapping back into position.
