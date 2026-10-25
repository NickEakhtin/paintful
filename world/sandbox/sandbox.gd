extends Node3D
## Test ground for trying out features.

@onready var _player: Player = $Player


func _ready() -> void:
	Events.objective_changed.emit("Положи иглу на стол")


func _on_needle_placed(_item: Item) -> void:
	Events.objective_changed.emit("Игла на месте")


func _on_day_sign_interacted(_by: Player) -> void:
	_player.lock_controls(&"title")
	GameState.start_new_day()
	await Transition.show_title("День %d" % GameState.day)
	await Transition.fade_in()
	_player.unlock_controls(&"title")
