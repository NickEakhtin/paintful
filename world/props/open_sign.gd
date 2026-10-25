class_name OpenSign
extends Node3D
## OPEN/CLOSED sign by the entrance. Opening it starts the working day (Events.studio_opened).
## Closing is only allowed once the day's clients are done: the day flow sets `can_close`.

@export var open_color: Color = Color(0.4, 1.0, 0.5)
@export var closed_color: Color = Color(1.0, 0.35, 0.3)

var is_open: bool = false
var can_close: bool = false:
	set(value):
		can_close = value
		if is_node_ready():
			_update()

@onready var _label: Label3D = $Board/Label
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
	_label.text = "ОТКРЫТО" if is_open else "ЗАКРЫТО"
	_label.modulate = open_color if is_open else closed_color
	if not is_open:
		_interactable.prompt = "Открыть студию"
		_interactable.enabled = true
	elif can_close:
		_interactable.prompt = "Закрыть студию"
		_interactable.enabled = true
	else:
		_interactable.prompt = "Студия открыта"
		_interactable.enabled = false
