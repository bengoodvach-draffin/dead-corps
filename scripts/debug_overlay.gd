extends CanvasLayer

## Debug overlay showing game state, controls, and reset button
##
## Displays real-time information about:
## - Zombie and human counts
## - Selected units count
## - Escaped humans count
## - Control group assignments
##
## Provides a reset button to restart the level without closing the game

@onready var info_label: Label = $InfoPanel/VBoxContainer/InfoLabel
@onready var controls_label: Label = $InfoPanel/VBoxContainer/ControlsLabel
@onready var reset_button: Button = $InfoPanel/VBoxContainer/ResetButton

var game_manager: GameManager


## Called when the node enters the scene tree
func _ready() -> void:
	# Find game manager
	await get_tree().process_frame
	game_manager = get_tree().get_first_node_in_group("game_manager")
	
	# Controls + scoring + unit legend. Small font + word-wrap, pinned to ~the WASD-line
	# width so long items wrap onto new lines instead of widening the panel.
	controls_label.add_theme_font_size_override("font_size", 12)
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.custom_minimum_size = Vector2(230.0, 0.0)
	controls_label.text = """CONTROLS
- LMB / drag: select calm zombies
- Shift+LMB: add to selection
- RMB ground: move selected
- RMB on human: RELEASE (go feral)
- Ctrl+1-9 assign group, 1-9 select
- WASD pan, wheel zoom, Reset restarts

SCORING (combo)
- Pounce kills build a pot; longer chains pay more per kill
- Burst + terror kills raise the x multiplier
- Window lapses: bank pot x mult into SCORE

UNITS
- Zombie: white calm, orange feral, red dead
- Human: M militia, P police, G GI, blank civilian
- Cowering pale-blue, corpse red, line = filling"""
	
	# Connect reset button
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)


## Called every frame to update the display
func _process(_delta: float) -> void:
	update_info()


## Updates the info label with current game state
func update_info() -> void:
	if not game_manager:
		return
	
	var zombie_count := game_manager.get_all_zombies().size()
	var human_count := game_manager.get_all_humans().size()
	var escaped_count := game_manager.escaped_humans
	
	var selection_manager: SelectionManager = get_tree().get_first_node_in_group("selection_manager")
	var selected_count := 0
	if selection_manager:
		selected_count = selection_manager.get_selected_units().size()
	
	info_label.text = """GAME STATE:
Zombies: %d
Humans: %d
Escaped: %d
Selected: %d
""" % [zombie_count, human_count, escaped_count, selected_count]


## Called when reset button is pressed
## Reloads the current scene to restart the game
## Cleans up references first to avoid errors with dead units
func _on_reset_pressed() -> void:
	# Clean up all selection and control group references before reload
	var selection_manager: SelectionManager = get_tree().get_first_node_in_group("selection_manager")
	if selection_manager:
		selection_manager.cleanup_all()
	
	# Reload the current scene
	get_tree().reload_current_scene()
