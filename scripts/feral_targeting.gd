class_name FeralTargeting
extends RefCounted

## Movement-vector-aware target scoring — the single owner of the "drive along the
## path" rule, shared by release seeding (ReleaseSeeder) and feral peel/retarget
## (FeralBrain), §2.4. Pure static, no state (like DetHash).
##
## Lower score = better target. Humans ALONG the mover's heading (its movement path)
## score lowest; off-axis ones are penalised by feral_offaxis_penalty × perpendicular
## offset; humans BEHIND the heading get a large but FINITE penalty so they're picked
## only as a last resort (never INF — nothing is left unassignable). With no heading
## (a stationary mover) it degrades to plain distance.
##
## This is what makes the horde punch in like a bullet and KEEP driving up the centre,
## instead of splaying onto whatever human happens to be nearest.

const BEHIND_PENALTY := 100000.0


## path_score with the THREAT WEIGHT applied (Ben, 2026-08-06): armed humans
## (M/P/G) score × feral_threat_weight, so shooters out-bid civilians at equal
## geometry and the horde stops filing past a firing GI. For the feral's
## AUTONOMOUS choices only (FeralBrain peel/retarget/off-door) — release seeding
## keeps calling path_score raw, because the player's aim is not up for bias.
static func threat_score(origin: Vector2, heading: Vector2, h: Human) -> float:
	var s := path_score(origin, heading, h.global_position)
	if h.is_armed():
		s *= GameConfig.feral_threat_weight
	return s


static func path_score(origin: Vector2, heading: Vector2, point: Vector2) -> float:
	var to_point := point - origin
	if heading == Vector2.ZERO:
		return to_point.length()
	var forward := to_point.dot(heading)
	var perp := (to_point - heading * forward).length()
	if forward < 0.0:
		return to_point.length() + BEHIND_PENALTY
	return forward + perp * GameConfig.feral_offaxis_penalty
