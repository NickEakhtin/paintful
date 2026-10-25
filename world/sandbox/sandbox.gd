extends Node3D
## Test ground for trying out features.
## Debug: `interact` starts a new day and shows its title card.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not Transition.is_busy:
		_show_next_day()


func _show_next_day() -> void:
	GameState.start_new_day()
	await Transition.show_title("День %d" % GameState.day)
	await Transition.fade_in()
