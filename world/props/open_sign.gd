class_name OpenSign
extends Node3D
## The studio's OPEN switch: its Interactable sits by the window, and the neon TATTOO sign outside burns while the
## studio is open. Opening starts the working day (Events.studio_opened).
## Closing is only allowed once the day's clients are done: the day flow sets `can_close`.

@export var neon: NeonSign

var is_open: bool = false
var can_close: bool = false:
	set(value):
		can_close = value
		if is_node_ready():
			_update()

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	_update()


func set_open(value: bool) -> void:
	if value == is_open:
		return
	is_open = value
	_update()
	if is_open:
		Events.studio_opened.emit()
	else:
		Events.studio_closed.emit()


func _on_interacted(_player: Player) -> void:
	set_open(not is_open)


func _update() -> void:
	if neon != null:
		neon.powered = is_open
	if not is_open:
		_interactable.prompt = "Включить вывеску: открыть студию"
		_interactable.enabled = true
	elif can_close:
		_interactable.prompt = "Выключить вывеску: закрыть студию"
		_interactable.enabled = true
	else:
		_interactable.prompt = "Студия открыта"
		_interactable.enabled = false
