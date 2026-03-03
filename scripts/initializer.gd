extends Node

## Scene initializer - sets up the test scenario when the game starts
## 
## This simple script runs when the main scene loads and triggers the
## GameManager to spawn the initial test units. It's a separate node
## to keep initialization logic cleanly separated from game logic.
##
## The script waits one frame before initializing to ensure all other
## nodes (especially GameManager) are fully ready. This prevents race
## conditions where we might try to access systems that haven't finished
## their _ready() calls yet.
##
## In a full game, this would be replaced with level loading logic,
## but for prototyping it just sets up a simple test scenario.
##
## To disable auto-spawning: Uncheck "Enabled" in the Inspector

## Whether to automatically spawn units on start
@export var enabled: bool = true


## Called when the node enters the scene tree
## Waits one frame, then tells GameManager to spawn test units
func _ready() -> void:
	# Check if spawning is enabled
	if not enabled:
		print("Initializer disabled - no units will spawn automatically")
		return
	
	# Wait for one frame to ensure all nodes are ready
	# This is important because nodes' _ready() functions are called
	# in tree order, and we need GameManager to be fully initialized
	await get_tree().process_frame
	
	# Find the GameManager via group system
	# Using groups allows flexible scene structure
	var game_manager: GameManager = get_tree().get_first_node_in_group("game_manager")
	
	# If we found GameManager, set up the test scenario
	if game_manager:
		# This spawns 3 zombies and 4 humans in pre-defined positions
		game_manager.setup_test_scenario()
		print("Test scenario loaded!")
	else:
		# If GameManager not found, something is wrong with scene setup
		push_error("Could not find GameManager!")
