extends CanvasLayer

## End-game overlay (build-plan 4.2, spec §8). Shows the combo-accumulated score, the
## level timer (display-only), and the escaped stat (zero points) — on win AND loss.
## The v1 scoring (25/zombie + time bonuses) is gone; the score is whatever the
## ComboSystem banked (GameManager runs combo.finalize() before emitting the end signal).

@onready var backdrop: ColorRect = $Backdrop
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_label: Label = $ResultPanel/VBoxContainer/ResultLabel
@onready var score_label: Label = $ResultPanel/VBoxContainer/ScoreLabel
@onready var breakdown_label: Label = $ResultPanel/VBoxContainer/BreakdownLabel

var game_manager: GameManager


func _ready() -> void:
	visible = false
	await get_tree().process_frame
	game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		game_manager.game_won.connect(_on_game_won)
		game_manager.game_lost.connect(_on_game_lost)


func _on_game_won() -> void:
	_show("YOU WIN")


func _on_game_lost() -> void:
	_show("DEFEAT\nYour horde was wiped out")


## Renders the end screen. Score = the banked combo total (shown on win AND loss, spec
## §8); breakdown = level timer (display-only) + escaped count (a stat, zero points).
func _show(message: String) -> void:
	if game_manager == null:
		return
	result_label.text = message

	var total := 0
	if game_manager.combo != null:
		total = game_manager.combo.total
	score_label.text = "SCORE: %d" % total

	breakdown_label.text = _breakdown()
	visible = true


func _breakdown() -> String:
	var t: float = game_manager.game_time
	var minutes := int(t / 60.0)
	var seconds := int(t) % 60
	var escaped_line := "Escaped: %d  (+0)" % game_manager.escaped_humans
	# A lost special stings by name (specials spec §2.4 — the denial callout).
	if not game_manager.lost_specials.is_empty():
		escaped_line += "  — including the %s" % ", ".join(game_manager.lost_specials)
	return "\nTime: %d:%02d\n%s" % [minutes, seconds, escaped_line]
