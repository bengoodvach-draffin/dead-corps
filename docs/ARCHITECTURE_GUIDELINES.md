# Dead Corps — Architecture Guidelines (v2 rebuild and onward)

**Why this exists:** v1's `human.gd` grew to **2,854 lines holding nine
subsystems**, with a 295-line `_physics_process`, a melee protocol split across
three files with no owner, cross-file reads of underscore-"private" fields, and
runtime coupling through `get_tree()` group scans (full autopsy:
`CODEBASE_REVIEW.md` Findings §1). The v2 demolition deletes most of that code.
These rules exist so the rebuild doesn't grow the same shape back. They apply to
**every new or rebuilt script** on `v2-poc` and after.

These are working defaults, not dogma — violating one is allowed, but it's a
*propose-first* decision with a stated reason, never a drift.

---

## The rules

### 1. One owner per mechanic
Every mechanic (fill, fear, retargeting, pounce, contagion, combo, cower) lives
in exactly one script that owns its state and its rules. Other scripts interact
through its methods and signals — never by reimplementing a piece of its logic
locally and never by reading its private fields. *(The v1 anti-pattern: the
2-attacker melee protocol smeared across `zombie.gd`, `selection_manager.gd`,
and `human.gd`.)*

### 2. Behaviors are component child nodes, not base-class bulk
`CODEBASE_REVIEW` Stage F planned to decompose `human.gd` into components as a
refactor; v2 builds it that way from birth. The intended component map:

- **Human** (thin shell: state enum, movement, identity)
  - `FillComponent` — awareness, the radial front, rotation gate, firing
  - `FearComponent` — fear-radius count, threshold, the committed break
  - `FleeBehavior` — rout pathing, zombie-avoiding flee vectors (herding)
  - `CowerDetector` — net-displacement detector
  - `PatrolBehavior` — surviving waypoint movement (ported, not rewritten)
- **Zombie** (thin shell: state enum, movement, selectability)
  - `ShambleBehavior` — calm idle wander
  - `FeralBrain` — pursuit, local scan + hunt pool retargeting, the failsafe
  - `PounceBehavior` — lunge, kill-at-landing, recovery
- **Unit** stays what it is: movement, selection, BOID separation/alignment,
  bounds — and never knows about its subclasses (the `self as Zombie` smell
  from v1 stays dead).

A component gets its own scene-tree child node when it has per-frame behavior
or editor presence; a plain `RefCounted`/inner helper is fine for pure logic.
Components talk to their shell, not to sibling components directly.

### 3. Size tripwires
**A script crossing ~400 lines or a function crossing ~40 lines is a stop
sign:** pause and propose a split before adding more. These are tripwires, not
hard caps — but crossing one silently is how 2,854 lines happen.
*(Proposed, not yet implemented: an advisory line-count warning in
`tools/check.ps1` — needs Ben's go-ahead before touching the gate.)*

### 4. `_physics_process` is a dispatcher
Per-state handler methods (`_tick_calm(delta)`, `_tick_feral(delta)`, …) with a
thin `match` on the state enum. No state's logic inlined in the process
function; no early-return ladders mixing subsystems. *(v1's 295-line
`_physics_process` is the cautionary tale.)*

### 5. Signals up, calls down
Parents/managers call methods on their children; children report upward via
signals. No reaching across the tree into another unit's internals, and **no
reads of another script's underscore-prefixed fields** — if something outside
needs it, it gets a method or a signal, which makes the dependency visible.

### 6. Simulation state is independent of presentation
Renderers and HUD read simulation state (fill front radius, feral flag, combo
pot); simulation never reads from or waits on a renderer. This is the
3D-migration insurance from `CODEBASE_REVIEW` — if the pivot validates, the
view layer is rewritten and everything behind it should survive untouched.

### 7. Data over branches
Per-class numbers live in the `level_config` table — code reads
`config.fill_speed[defender_class]`, it does not scatter
`if defender_class == DefenderClass.GI:` branches. A new class should be a new
table row, not a new code path. *(v1's `human.gd` partly bloated through
per-class branching.)*

### 8. The registry is the only per-frame discovery mechanism
No `get_tree().get_nodes_in_group()` in per-frame code — units and neighbours
come from the GameManager registry (`neighbours_within()` etc.). Group lookups
are for one-time wiring at `_ready()`. This is both the performance posture
(`CODEBASE_REVIEW` Fix A) and the determinism posture (stable ordering) in one
rule.

---

## How this is enforced

- **At propose time:** every implementation proposal answers "which component
  owns this?" before code is written. If the answer is "the shell" or "two
  places", the proposal isn't ready.
- **At review time:** Ben reviews diffs against the tripwires (rule 3) and the
  ownership question (rule 1).
- **In session memory:** `CLAUDE.md` points here; read this file before
  creating or substantially extending any script.
