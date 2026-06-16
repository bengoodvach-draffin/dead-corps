class_name ReleaseSeeder
extends RefCounted

## Release seeding — assigns released ferals to a cluster of humans (build-plan 2.4,
## spec §5.2). Pure static logic (no state, no nodes, like DetHash): given the ferals
## to release and the candidate humans near the click, it returns which human each
## feral is seeded at. The selection_manager owns the input + igniting; this owns only
## the assignment math (rule 1 — one owner per mechanic), keeping that shell focused.
##
## Algorithm: first pass assigns one feral per human via greedy nearest-pairs; any
## remaining ferals distribute evenly (least-loaded human, nearest tiebreak). No
## per-human cap — pounce-exclusion (§3.5) prevents real pile-ups. Fully deterministic
## (§10): every ordering breaks on unit_uid, no RNG. Callers pass ferals pre-sorted by
## unit_uid so the remaining-distribution pass is order-stable.


## Maps each feral → the human it's seeded at. `ferals` and `candidates` must both be
## non-empty (caller guards) and `ferals` unit_uid-sorted. `click_pos` is the release
## point — each feral's "movement path" is the line from it toward the click, and
## humans along that path are preferred over off-axis ones so the horde drives in like
## a bullet rather than splaying across the front rank (§2.4).
static func assign(ferals: Array[Zombie], candidates: Array[Human], click_pos: Vector2) -> Dictionary:
	var assigned := {}        # Zombie → Human
	var human_load := {}      # Human → int (ferals assigned so far)
	for h in candidates:
		human_load[h] = 0

	# Per-feral heading: from the feral toward the click (the swarm's intended push).
	var headings := {}
	for f in ferals:
		headings[f] = (click_pos - f.global_position).normalized()

	# Build all (feral, human, path-score) pairs, best-first with unit_uid ties.
	var pairs: Array = []
	for f in ferals:
		for h in candidates:
			pairs.append({"f": f, "h": h, "s": FeralTargeting.path_score(f.global_position, headings[f], h.global_position)})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.s != b.s:
			return a.s < b.s
		if a.f.unit_uid != b.f.unit_uid:
			return a.f.unit_uid < b.f.unit_uid
		return a.h.unit_uid < b.h.unit_uid
	)

	# First pass: one feral per human, best path-score greedy.
	for p in pairs:
		if assigned.has(p.f) or human_load[p.h] > 0:
			continue
		assigned[p.f] = p.h
		human_load[p.h] = 1

	# Remaining ferals: distribute evenly (least-loaded, best-score tiebreak, unit_uid).
	for f in ferals:
		if assigned.has(f):
			continue
		var best: Human = null
		for h in candidates:
			if best == null or _prefer_least_loaded(h, best, human_load, f, headings[f]):
				best = h
		assigned[f] = best
		human_load[best] += 1

	return assigned


## True if human `h` is a better least-loaded seed for feral `f` than the current best
## `cur`: fewer ferals assigned, else better path-score, else lower unit_uid (§10 ties).
static func _prefer_least_loaded(h: Human, cur: Human, human_load: Dictionary, f: Zombie, heading: Vector2) -> bool:
	if human_load[h] != human_load[cur]:
		return human_load[h] < human_load[cur]
	var sh := FeralTargeting.path_score(f.global_position, heading, h.global_position)
	var sc := FeralTargeting.path_score(f.global_position, heading, cur.global_position)
	if sh != sc:
		return sh < sc
	return h.unit_uid < cur.unit_uid
