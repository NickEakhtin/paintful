extends Control
## Start screen placeholder. Becomes the main menu in step 9.

const FIRST_SCENE: String = "res://world/level/level.tscn"


func _unhandled_input(event: InputEvent) -> void:
	if Transition.is_busy:
		return
	var is_press: bool = (event is InputEventKey or event is InputEventMouseButton) \
		and event.is_pressed() and not event.is_echo()
	if is_press:
		Transition.change_scene(FIRST_SCENE)
