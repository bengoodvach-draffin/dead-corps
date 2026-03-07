# Dead Corps - Changelog v0.21.2

**Release Date:** March 7, 2026
**Focus:** Panic propagation depth cap + distance-based reaction delays

---

## Changed

### Depth-capped panic propagation

`propagate_flee_to_group()` now accepts a `depth: int` parameter (default 0).
Propagation stops when `depth >= panic_propagation_depth`.

New export property on Human (Flee group):
**`panic_propagation_depth: int = 2`** — How many hops panic spreads from original sighting.
- `0` = only the direct detector flees
- `1` = detector + immediate neighbours (one ring)
- `2` = detector + two rings outward (default, recommended)
- `99` = unlimited (old behaviour)

Chain behaviour at default depth 2:
```
Depth 0: Human A sees zombie → flees → propagates to B, C, D
Depth 1: B, C, D flee → propagate to E, F, G
Depth 2: E, F, G flee → propagation STOPS
```

### Distance-based reaction delays

Replaced index-based delay (`i * 0.05s`) with distance-based delay:
```
delay = (distance_to_ally / 80px) * 0.4s
```
- Ally 5px away → ~0.025s delay (near-instant)
- Ally 40px away → 0.2s delay
- Ally 80px away → 0.4s delay (max)

Tight formations and squads now react near-simultaneously since everyone
is close together. Loose groups get a realistic outward ripple.
