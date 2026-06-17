class_name ComboSystem
extends Node

## Combo / pot scoring (build-plan 4.2, spec §6.1). A standalone system node (child of
## GameManager), fed pounce kills via register_kill(). Gunfire deaths are the player's
## OWN losses, not scored. Ticks the combo window on _physics_process; banks on expiry.
##
## Model (spec §6.1, V2 tiered base — locked 2026-06-17):
##   - Each kill adds a TIERED base to the pot: kill_base × ceil(chain_pos / tier_size)
##     (10/5 → kills 1–5 worth 10, 6–10 worth 20, 11–15 worth 30…). Rewards chain LENGTH,
##     so the window now drives score, not just keeps the chain alive.
##   - Multiplier (per chain, starts 1, kept rare): +1 within burst_window of the last
##     kill (simultaneity), +1 on a terror kill (victim was COWERING); stacks.
##   - Window (combo_window) refreshes each kill; on expiry: total += pot × mult, reset.
##   - The held multiplier applies to the whole pot — late bursts inflate the chain.

## Emitted when a chain banks (amount = pot × multiplier). The HUD pops on this.
signal banked(amount: int, pot: int, multiplier: int)

## Running level score (sum of all banked combos).
var total: int = 0

# Active-chain state.
var _pot: int = 0
var _mult: int = 1
var _chain: int = 0        ## kills so far in the current chain — drives the base tier
var _window: float = 0.0   ## seconds left before the chain banks
var _active: bool = false


## Registers a pounce kill (spec §6.1). `human` is the victim, read for the terror bonus.
## Called by GameManager's kill handler — gunfire (zombie) deaths never reach here.
func register_kill(human: Human) -> void:
	if _active:
		# Continuing chain: a burst (within burst_window of the last kill) bumps the mult.
		var since_last := GameConfig.combo_window - _window
		if since_last <= GameConfig.burst_window:
			_mult += 1
	else:
		# Fresh chain.
		_pot = 0
		_mult = 1
		_chain = 0
		_active = true

	_chain += 1
	var tier := ceili(float(_chain) / float(GameConfig.combo_tier_size))
	_pot += GameConfig.kill_base * tier

	# Terror kill — victim was cowering (was_cowering persists into death). Stacks.
	if human != null and human.was_cowering:
		_mult += 1

	_window = GameConfig.combo_window   # refresh the forgiveness window


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_window -= delta
	if _window <= 0.0:
		_bank()


## Banks any active chain immediately — called at game end so a winning final kill (or
## any chain still in progress) still scores before the end screen reads the total.
func finalize() -> void:
	if _active:
		_bank()


## Live combo state for the HUD. window_fraction is the draining-bar value (1→0).
func snapshot() -> Dictionary:
	var frac := 0.0
	if _active and GameConfig.combo_window > 0.0:
		frac = clampf(_window / GameConfig.combo_window, 0.0, 1.0)
	return {
		"active": _active,
		"pot": _pot,
		"multiplier": _mult,
		"window_fraction": frac,
	}


func _bank() -> void:
	var amount := _pot * _mult
	total += amount
	banked.emit(amount, _pot, _mult)
	_active = false
	_pot = 0
	_mult = 1
	_chain = 0
	_window = 0.0
