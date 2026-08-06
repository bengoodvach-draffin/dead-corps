class_name ComboHUD
extends CanvasLayer

## Combo + score HUD (build-plan 4.2, spec §7). Built entirely in code — no .tscn, so no
## scene edit / global-class-cache dance. GameManager instantiates it at runtime, so it
## works in any level.
##
## Layout: the running TOTAL score is always shown (top-right). While a chain is active,
## the combo readout — pot and current ×multiplier + a draining window bar — shows
## top-left, with a colour pop each time the multiplier bumps. Banking flies a "+amount"
## up and fades it. Minimal by design; the full readability/rendering pass is 5.1.

var _combo: ComboSystem = null
var _gm: GameManager = null

var _score_label: Label
var _time_label: Label
var _combo_box: VBoxContainer
var _combo_label: Label
var _window_bar: ProgressBar
var _bank_label: Label

var _last_mult: int = 1

## Elapsed GAME time (seconds) since the level loaded. Accumulates _process delta,
## so held-F fast-forward counts 3× (it's sim time, not wall clock); freezes when
## the game ends. Display-only — an R restart reloads the scene and rebuilds us,
## which resets it for free.
var _elapsed: float = 0.0


func _ready() -> void:
	layer = 100   # above gameplay
	_build_ui()
	_gm = get_tree().get_first_node_in_group("game_manager") as GameManager
	if _gm != null:
		_combo = _gm.combo
		if _combo != null:
			_combo.banked.connect(_on_banked)


func _process(delta: float) -> void:
	if _combo == null:
		return

	# Game timer: runs from level load, frozen once win/lose is judged.
	if _gm == null or not _gm.game_ended:
		_elapsed += delta

	# All HUD elements live top-right (re-positioned each frame so they survive resize),
	# clear of the top-left game/debug overlay.
	_score_label.text = "SCORE: %d" % _combo.total
	var view_w := get_viewport().get_visible_rect().size.x
	_score_label.position = Vector2(view_w - 240.0, 14.0)
	var minutes := int(_elapsed / 60.0)
	var seconds := int(_elapsed) % 60
	_time_label.text = "TIME %d:%02d" % [minutes, seconds]
	_time_label.position = Vector2(view_w - 420.0, 14.0)

	# Combo readout — pot + ×multiplier + draining window bar, just under SCORE while a
	# chain is live.
	var s := _combo.snapshot()
	if s.active:
		_combo_box.visible = true
		_combo_box.position = Vector2(view_w - 240.0, 48.0)
		_combo_label.text = "%d   ×%d" % [s.pot, s.multiplier]
		_window_bar.value = s.window_fraction * 100.0
		if s.multiplier > _last_mult:
			_pop(_combo_label)
		_last_mult = s.multiplier
	else:
		_combo_box.visible = false
		_last_mult = 1


# === INTERNAL ===

func _build_ui() -> void:
	_score_label = Label.new()
	_score_label.text = "SCORE: 0"
	_score_label.add_theme_font_size_override("font_size", 28)
	_score_label.position = Vector2(20.0, 14.0)
	add_child(_score_label)

	# Game timer, left of SCORE on the same top-right row.
	_time_label = Label.new()
	_time_label.text = "TIME 0:00"
	_time_label.add_theme_font_size_override("font_size", 28)
	_time_label.position = Vector2(20.0, 14.0)
	add_child(_time_label)

	# Combo readout, top-left.
	_combo_box = VBoxContainer.new()
	_combo_box.position = Vector2(20.0, 14.0)
	_combo_box.visible = false
	add_child(_combo_box)

	_combo_label = Label.new()
	_combo_label.text = "0   ×1"
	_combo_label.add_theme_font_size_override("font_size", 34)
	_combo_box.add_child(_combo_label)

	_window_bar = ProgressBar.new()
	_window_bar.min_value = 0.0
	_window_bar.max_value = 100.0
	_window_bar.value = 100.0
	_window_bar.show_percentage = false
	_window_bar.custom_minimum_size = Vector2(180.0, 10.0)
	_combo_box.add_child(_window_bar)

	# Bank "+amount" pop, near the combo readout.
	_bank_label = Label.new()
	_bank_label.add_theme_font_size_override("font_size", 48)   # big — the bank is the payoff
	_bank_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.15))   # gold
	_bank_label.position = Vector2(210.0, 14.0)
	_bank_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_bank_label)


## Quick colour flash on the combo readout when the multiplier bumps.
func _pop(label: Label) -> void:
	label.modulate = Color(1.0, 0.9, 0.2)   # flash yellow
	var t := create_tween()
	t.tween_property(label, "modulate", Color.WHITE, 0.25)


## A chain banked — fly "+amount" up into the total score (top-right, under SCORE), so
## the debug/game overlay (top-left) doesn't cover it.
func _on_banked(amount: int, _pot: int, _multiplier: int) -> void:
	var view_w := get_viewport().get_visible_rect().size.x
	_bank_label.text = "+%d" % amount
	_bank_label.position = Vector2(view_w - 260.0, 52.0)
	_bank_label.modulate = Color(1.0, 1.0, 1.0, 1.0)   # full opacity; gold comes from font_color
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_bank_label, "position:y", 18.0, 0.7)
	t.tween_property(_bank_label, "modulate:a", 0.0, 0.7)
