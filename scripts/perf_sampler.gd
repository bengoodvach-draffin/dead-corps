extends Node

## PERF SAMPLER (WORK_QUEUE Tier 3.6, built 2026-08-02) — the instrument that
## replaced profiler-screenshot archaeology. Every SAMPLE_INTERVAL it appends one
## compact line to the console (and thus godot.log, file logging being enabled),
## so a whole session's performance curve can be read back from the log file:
## frame-time avg/max since the last line, physics time, node count, and the
## unit census by state. Claude reads the log directly; no screenshots.
##
## Deliberately NOT gated on GameConfig.debug_logs — this is the perf
## instrument, and one line per 5s is noise-free. Gate: GameConfig.perf_log.
## Created at runtime by GameManager (no class_name — loaded by path, so no
## editor class-cache regen is needed; the ComboHUD pattern).
##
## Read-only observer: it samples and prints, touches nothing, so it cannot
## affect determinism (§10).

const SAMPLE_INTERVAL := 5.0

var _gm: Node = null

## Render-frame accumulation since the last report.
var _elapsed: float = 0.0
var _frames: int = 0
var _worst_frame: float = 0.0
## Wall-clock seconds since boot, for the t= stamp (display only, not sim time).
var _uptime: float = 0.0


func setup(gm: Node) -> void:
	_gm = gm


func _process(delta: float) -> void:
	if not GameConfig.perf_log:
		return
	_uptime += delta
	_elapsed += delta
	_frames += 1
	_worst_frame = maxf(_worst_frame, delta)
	if _elapsed < SAMPLE_INTERVAL:
		return

	var avg_ms := _elapsed / _frames * 1000.0
	var worst_ms := _worst_frame * 1000.0
	# Engine monitors: physics step time and total node count — the two numbers
	# the hand-profiling sessions kept needing alongside script time.
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	print("⏱️ PERF t=%ds | frame avg %.1fms worst %.1fms (%d frames) | physics %.1fms | nodes %d | %s" % [
		int(_uptime), avg_ms, worst_ms, _frames, phys_ms, nodes, _census()])

	_elapsed = 0.0
	_frames = 0
	_worst_frame = 0.0


## One-line unit census by state — the context that makes a frame-time spike
## readable ("300 ferals" vs "quiet map") without a screenshot.
func _census() -> String:
	if _gm == null or not is_instance_valid(_gm):
		return "no GM"
	var z_calm := 0
	var z_feral := 0
	for z in _gm.living_zombies():
		if z.current_state == Zombie.State.FERAL:
			z_feral += 1
		else:
			z_calm += 1
	var h_flee := 0
	var h_shelter := 0
	var h_cower := 0
	var h_idle := 0
	for h in _gm.living_humans():
		match h.current_state:
			Human.State.FLEEING:
				h_flee += 1
			Human.State.SHELTERED:
				h_shelter += 1
			Human.State.COWER:
				h_cower += 1
			_:
				h_idle += 1
	return "Z %d calm %d feral | H %d idle %d flee %d shelter %d cower" % [
		z_calm, z_feral, h_idle, h_flee, h_shelter, h_cower]
