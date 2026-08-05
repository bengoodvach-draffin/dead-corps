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
## sim_tick at the last report, for the ticks-per-window delta.
var _last_sim_tick: int = 0


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
	# Engine monitors. TIME_* are last-frame times: physics includes the bundled
	# catch-up ticks (divide by ticks-per-frame for per-tick cost), process is
	# the _process scripts, nav is the NavigationServer sync. draw_calls tells
	# the render side's story — frame minus the three TIME_* is render+engine.
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var nav_ms := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# True per-tick wall cost from the GM tick stamps (133ms-lock hunt): ticks
	# actually run this window, and the min/avg gap between consecutive ticks.
	var ticks := 0
	var tick_min := 0.0
	var tick_avg := 0.0
	if _gm != null and is_instance_valid(_gm):
		ticks = int(_gm.sim_tick) - _last_sim_tick
		_last_sim_tick = int(_gm.sim_tick)
		tick_min = _gm.tick_gap_min_us / 1000.0
		if int(_gm.tick_gap_samples) > 0:
			tick_avg = _gm.tick_gap_sum_us / 1000.0 / _gm.tick_gap_samples
		_gm.tick_gap_min_us = 0
		_gm.tick_gap_sum_us = 0
		_gm.tick_gap_samples = 0

	print("⏱️ PERF t=%ds | frame avg %.1fms worst %.1fms (%d frames) | physics %.1fms proc %.1fms nav %.1fms | ticks %d wall min %.1f avg %.1fms | draws %d | nodes %d | %s" % [
		int(_uptime), avg_ms, worst_ms, _frames, phys_ms, proc_ms, nav_ms, ticks, tick_min, tick_avg, draws, nodes, _census()])

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
