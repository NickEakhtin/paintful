class_name Door
extends Node3D
## A 1 m hinged door. The player opens and closes it with `interact` unless it's locked;
## code (clients walking in) can still open() a locked door.

@export var locked: bool = false
@export var locked_prompt: String = "Заперто"
## Swing in degrees; negative swings the other way.
@export var open_angle: float = 100.0
@export var swing_time: float = 0.35

var is_open: bool = false

var _tween: Tween

@onready var _hinge: Node3D = $Hinge
@onready var _interactable: Interactable = $Hinge/Panel/Interactable


func _ready() -> void:
	_interactable.interacted.connect(func(_player: Player) -> void: toggle())
	_update_prompt()


func open() -> void:
	_swing(true)


func close() -> void:
	_swing(false)


func toggle() -> void:
	_swing(not is_open)


func set_locked(value: bool) -> void:
	locked = value
	_update_prompt()


func _swing(to_open: bool) -> void:
	is_open = to_open
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	var angle: float = deg_to_rad(open_angle) if to_open else 0.0
	_tween.tween_property(_hinge, "rotation:y", angle, swing_time).set_trans(Tween.TRANS_SINE)
	_update_prompt()


func _update_prompt() -> void:
	_interactable.enabled = not locked
	if locked:
		_interactable.prompt = locked_prompt
	else:
		_interactable.prompt = "Закрыть дверь" if is_open else "Открыть дверь"
