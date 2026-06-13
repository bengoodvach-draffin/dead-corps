class_name DetHash

## DetHash - Deterministic per-unit jitter (spec §10)
##
## Static, pure helpers (no node — ARCHITECTURE_GUIDELINES rule 2). The v2 design
## bans live RNG: organic variation must come from a unit's stable identity, not
## chance, so identical inputs produce identical runs. Any system wanting
## "random-looking" per-unit variation (idle shamble wander, move-order jitter)
## seeds it through these from (unit_uid, salt).
##
## Determinism scope: Godot's hash() is stable for a given build/platform — which
## is exactly what §10 promises (identical *runs on the same machine*), not
## cross-platform replays. Do not swap in randf/randi anywhere.

## Core: deterministic float in [0, 1) from arbitrary integer seed components.
## Masks to a non-negative 31-bit value so the sign of hash() can't leak in.
static func _hash01(seed_parts: Array) -> float:
	return float(hash(seed_parts) & 0x7FFFFFFF) / 2147483648.0  # / 2^31 → [0, 1)


## Deterministic value in [0, 1) for a unit + salt. Vary `salt` to get a
## different-but-stable value from the same unit (e.g. per move order).
static func hash01(uid: int, salt: int) -> float:
	return _hash01([uid, salt])


## Deterministic angle in [0, TAU) for a unit + salt.
static func angle(uid: int, salt: int) -> float:
	return hash01(uid, salt) * TAU


## Deterministic point inside the disc of the given radius, uniformly
## distributed. Angle and radius use distinct sub-seeds so they don't correlate;
## the sqrt gives an even areal spread rather than clustering at the centre.
static func offset(uid: int, salt: int, max_radius: float) -> Vector2:
	var a: float = _hash01([uid, salt, 0]) * TAU
	var r: float = sqrt(_hash01([uid, salt, 1])) * max_radius
	return Vector2(cos(a), sin(a)) * r
