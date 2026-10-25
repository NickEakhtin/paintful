extends RayCast3D
## Finds the Interactable the player looks at, shows its hint and triggers it on `interact`.
## Walls block the ray because it also collides with the "world" layer.

var _target: Interactable = null
var _shown_prompt: String = ""

@onready var _player: Player = owner as Player


func _physics_process(_delta: float) -> void:
	_target = null
	if not _player.is_locked() and is_colliding():
		_target = get_collider() as Interactable
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _target != null and _target.can_interact(_player):
		_target.interact(_player)
		get_viewport().set_input_as_handled()


func _update_prompt() -> void:
	var text: String = ""
	if _target != null:
		text = _target.get_prompt(_player)
		if text != "" and _target.can_interact(_player):
			text = "E — %s" % text
	if text != _shown_prompt:
		_shown_prompt = text
		Events.interaction_prompt_changed.emit(text)
