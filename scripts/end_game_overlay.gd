extends CanvasLayer

## End game overlay showing final score and game result
##
## Displays when the game ends (win or lose)
## Shows:
## - Result message (win/lose)
## - Score breakdown
## - Keeps debug overlay visible for reset button

@onready var backdrop: ColorRect = $Backdrop
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_label: Label = $ResultPanel/VBoxContainer/ResultLabel
@onready var score_label: Label = $ResultPanel/VBoxContainer/ScoreLabel
@onready var breakdown_label: Label = $ResultPanel/VBoxContainer/BreakdownLabel

var game_manager: GameManager


## Called when the node enters the scene tree
func _ready() -> void:
	# Hide by default
	visible = false
	
	# Find game manager
	await get_tree().process_frame
	game_manager = get_tree().get_first_node_in_group("game_manager")
	
	if game_manager:
		# Connect to game end signals
		game_manager.game_won.connect(_on_game_won)
		game_manager.game_lost.connect(_on_game_lost)


## Called when player wins
func _on_game_won() -> void:
	show_end_screen("GAME OVER", false)


## Called when player loses
func _on_game_lost() -> void:
	show_end_screen("YOU LOSE\nAll your zombies died", true)


## Shows the end game screen with score
## @param message: The result message to display
## @param is_loss: Whether this is a loss (affects scoring)
func show_end_screen(message: String, is_loss: bool) -> void:
	if not game_manager:
		return
	
	# Calculate score
	var score_data := calculate_score(is_loss)
	
	# Set result message
	result_label.text = message
	
	# Set score
	if is_loss:
		score_label.text = "SCORE: 0"
	else:
		score_label.text = "SCORE: %d" % score_data.total
	
	# Set breakdown
	breakdown_label.text = format_score_breakdown(score_data, is_loss)
	
	# Show the overlay
	visible = true


## Calculates the final score
## Returns dictionary with score components
func calculate_score(is_loss: bool) -> Dictionary:
	var result := {
		"zombie_score": 0,
		"zombie_count": 0,
		"time_bonus": 0,
		"escaped": 0,
		"game_time": 0.0,
		"total": 0
	}
	
	# If player lost, score is 0
	if is_loss:
		return result
	
	# Get game data
	result.escaped = game_manager.escaped_humans
	result.game_time = game_manager.game_time
	
	# 25 points per regular zombie, 100 points per special zombie
	# Uses is_special flag on Zombie base class — no subclass name dependency
	var regular_count := 0
	var special_count := 0
	for z in game_manager.get_all_zombies():
		if z.is_special:
			special_count += 1
		else:
			regular_count += 1
	# Also count incubating corpses (dead humans converting) as regular zombies
	var dead_human_count := 0
	for human in game_manager.get_all_humans():
		if human.is_dead:
			dead_human_count += 1
	regular_count += dead_human_count
	result.zombie_count = regular_count + special_count
	result.zombie_score = (regular_count * 25) + (special_count * 100)
	
	# Time bonuses
	var time_minutes: float = result.game_time / 60.0
	if time_minutes <= 1.0:
		result.time_bonus = 200
	elif time_minutes <= 2.0:
		result.time_bonus = 150
	elif time_minutes <= 3.0:
		result.time_bonus = 100
	elif time_minutes <= 4.0:
		result.time_bonus = 50
	else:
		result.time_bonus = 0
	
	# Total score
	result.total = result.zombie_score + result.time_bonus
	
	return result


## Formats the score breakdown text
func format_score_breakdown(score_data: Dictionary, is_loss: bool) -> String:
	if is_loss:
		return "\nAt least one human survived or escaped.\nBetter luck next time!"
	
	var minutes := int(score_data.game_time / 60.0)
	var seconds := int(score_data.game_time) % 60
	var time_str := "%d:%02d" % [minutes, seconds]
	
	var breakdown := ""
	breakdown += "\nZombies Survived: %d (+%d)\n" % [score_data.zombie_count, score_data.zombie_score]
	breakdown += "Time: %s (+%d)\n" % [time_str, score_data.time_bonus]
	breakdown += "Humans Escaped: %d (+0)" % score_data.escaped
	
	return breakdown
