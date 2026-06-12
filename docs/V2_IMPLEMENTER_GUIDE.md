# Dead Corps — V2 Implementer Guide (delegated execution on `v2-poc`)

**What this is:** the companion to `V2_POC_BUILD_PLAN.md` for executing build-plan
steps with a lower-capability model (or a future session without the whole design
paged in). It contains the things the build plan deliberately leaves out: the
cross-cutting invariants any implementer must preserve, which steps are safe to
delegate at all, the per-step ticket discipline, and how to verify work.

**What this is NOT:** `docs/IMPLEMENTER_GUIDE.md` (the v1 scaling guide). That
document's specs target v1 code and its invariants checklist describes systems
the pivot deletes (melee gate, corpse linger, morale, health bars). It survives
only as the post-PoC reference for upgrading the Phase-0 registry internals
(its Spec 0 benchmark + Spec 1 spatial index). **Never hand it to a model
working against v2 code.**

Process rules (propose-first, one-feature-at-a-time, parse gate, version
discipline) live in `CLAUDE.md` and are not repeated here. Architecture rules
for any new or rebuilt script live in `docs/ARCHITECTURE_GUIDELINES.md`.

---

## 1. Delegation map — who may execute what

Per the division-of-labour analysis in `CODEBASE_REVIEW.md`: design,
ticket-writing, and review stay with Ben + a high-capability model; cheaper
models execute only well-specified, low-judgement tickets. Applied to the
build plan:

| Build-plan step | Delegable to a cheaper model? |
|---|---|
| 0.1 `level_config.gd` | **Yes** — mechanical, fully specified by spec §9, clear pattern to copy (`level_bounds.gd`). |
| 0.2 unit registry | **Yes, with a written ticket** — small API, exact signatures specifiable, determinism rules below apply. |
| 0.3 determinism utilities | **Yes** — pure functions plus a grep audit. |
| 1.1–1.7 demolition | **Borderline — per-file tickets required.** Deleting subsystems from a god class needs judgement about shared helpers; the ticket must name exactly which functions/blocks die and which survive, per file. Do not give a cheap model "strip morale from human.gd" without that list. |
| 2.1 idle shamble | **Yes, with a ticket.** |
| 2.2–2.3 feral core, pounce, retarget/pool | **No.** This is the heart of the pivot. |
| 2.4–2.6 release seeding, contagion, risers | **No** for first implementation; follow-up fixes with tickets OK. |
| 3.1–3.4 fill front, fear break, rout/herding | **No.** Same reason as 2.2. |
| 3.5 cower detector | **Yes, with a ticket** — a self-contained detector with explicit thresholds and a named pattern to copy. |
| 4.1–4.2 win/lose, combo | **Borderline** — the combo math is exactly specified (delegable); the win/lose wiring touches GameManager (ticket required). |
| 5.1 rendering pass | **Yes, with a ticket** — visual, low-coupling, easy to verify by eye. |
| 6.x, 7.x level + Mark + playtests | **No** (level design + the Mark's scope rule are judgement work; playtests are Ben). |

The "No" rows are not about code difficulty — they're where subtle wrongness
(a retarget that prefers wrong, a fill that decays when it shouldn't) silently
corrupts the *validation verdict on the pivot*, which is the entire point of
this branch. Faithfulness to the spec there is worth the more capable model.

---

## 2. Invariants checklist (any model, any step — keep in view while editing)

### Determinism (spec §10 — hard constraint, per-step acceptance criterion)
- **No live RNG.** No `randf`/`randi`/`shuffle`/`randomize`, no random timer
  offsets. Organic variation comes from `hash(unit_uid, anchor)` (Phase 0.3).
- **Neighbour/unit lists come only from the GameManager registry**, never from
  `get_tree().get_nodes_in_group()` in per-frame code. Registry results are
  stable-ordered by `unit_uid`; preserve that ordering — never re-sort by
  anything non-deterministic, never iterate a Dictionary where order matters.
- **Stagger by identity, not chance:** any bucketed/throttled check uses
  `unit_uid % bucket_count`.
- **All timing in seconds** (accumulated `delta`), never frame counts.

### Core-loop rules that look like bugs but are the design
- **Released is released.** There is no recall path for FERAL zombies. Do not
  add one, ever — not as a debug convenience, not as an edge-case fix.
- **Kill registers at pounce landing.** A zombie dying mid-flight does NOT
  complete the kill; once landed, the human is dead regardless of what happens
  to the zombie afterwards.
- **Pounce exclusion:** a human targeted by an in-flight pounce is invisible to
  all other ferals' retargeting. This is the only anti-pile-up rule; do not add
  attacker caps.
- **Cowering humans are local-scan only** — never in the global hunt pool.
- **The break is committed the instant the fear threshold trips:** fill cancels
  immediately, line vanishes, no shot can land during the reaction beat.
- **The fill front holds (no reset, no decay) during rotation-to-face**, and
  decays only when NO zombie is in range/LOS. Firing is the only reset.
- **Escape zones are a hard boundary for ALL zombies** (calm and feral) — nobody
  dies, nobody enters; pursuers halt at the rim with target lost.
- **Risers count toward the zombie total for the lose condition**, and
  `rise_time` is measured from the pounce landing — not from when the killer
  moves away.
- **The Mark never interrupts an active pursuit and never moves a zombie
  anywhere prey isn't.** It affects feral retargeting only.
- **Specials never go feral** — but they are excluded from the PoC entirely;
  do not wire them into any new system. They only need to keep parsing.
- **No timers in the frenzy** other than the no-progress failsafe (40px / 2.0s
  rolling window). Do not "fix" a stuck feral with a wind-down timer.

### Engineering rules
- **Every §9 tunable reads from `level_config`** — never hardcode a number that
  appears in the spec's knob table.
- **`global_position` for all cross-unit math** (nested scenes break local
  `position`).
- **`@tool` scripts guard game logic** with `Engine.is_editor_hint()`.
- **Cross-script type checks use duck typing** (`unit.get("property")`), never
  `class_name` checks (load-order parse errors).
- **Run `tools/check.ps1` after every `.gd` edit** — it is the only automated
  safety net. Watch the partial-comment / empty-block parse trap when removing
  code in bulk.
- **One owner per mechanic** — see `ARCHITECTURE_GUIDELINES.md` before creating
  or extending any script.

---

## 3. Ticket discipline (just-in-time, never pre-written)

Tickets are written against *current* code immediately before execution — line
numbers and even file shapes drift fast on this branch (especially across the
Phase-1 demolition). A ticket contains:

- **Scope** — one build-plan step (or one file of a demolition step), nothing else.
- **Exact files + functions** with their current signatures (re-grepped, not recalled).
- **Approach** — data structures, pseudocode where the logic is non-obvious.
- **Invariants touched** — named from the checklist above.
- **Step-by-step edits.**
- **Acceptance criteria + manual test steps** (there is no automated suite).
- **Rollback note** — what to revert if the test fails.

Ben (or a high-capability session) writes and reviews the ticket; the cheaper
model executes it; review happens on the diff.

---

## 4. Verification recipe

1. **Parse gate:** `tools/check.ps1` green.
2. **Manual test steps from the ticket** — run in the sandbox/PoC scene, exact
   setup described (unit positions, what to click, what must happen).
3. **Determinism spot-check** (for any step touching feral logic, targeting,
   fills, or movement): run the same scripted scenario twice from a fresh boot
   and diff the debug-print log of kill order / target choices / break timings.
   Identical inputs must produce identical logs. A cheap scripted scenario via
   the Initializer is sufficient — this check is the practical meaning of §10.
