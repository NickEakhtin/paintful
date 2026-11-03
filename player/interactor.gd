extends RayCast3D
## Finds the Interactable the player looks at, outlines it, shows its hint and triggers it on `interact` (LMB, the
## colleague's way; E works too). Walls block the ray because it also collides with the "world" layer.

const OUTLINE: Script = preload("res://player/outline/interaction_outline.gd")

var _target: Interactable = null
var _shown_prompt: String = ""
var _outline: MeshInstance3D = OUTLINE.new()

@onready var _player: Player = owner as Player


func _ready() -> void:
	add_child(_outline)


func _physics_process(_delta: float) -> void:
	_target = null
	if not _player.is_locked() and is_colliding():
		_target = get_collider() as Interactable
	_outline.call(&"track", _target if _target != null and _target.can_interact(_player) else null)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _target != null and _target.can_interact(_player):
		_player.tap()
		_target.interact(_player)
		get_viewport().set_input_as_handled()


func _update_prompt() -> void:
	var text: String = ""
	if _target != null:
		text = _target.get_prompt(_player)
		if text != "" and _target.can_interact(_player):
			text = "ЛКМ — %s" % text
	if text != _shown_prompt:
		_shown_prompt = text
		Events.interaction_prompt_changed.emit(text)
