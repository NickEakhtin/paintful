class_name Door
extends Node3D
## A hinged door; the node sits on the hinge and the leaf runs from it along local -X.
## The player opens and closes it with `interact` unless it's locked; it swings away from them and shuts by itself
## once they walk farther than `auto_close_distance` from the hinge. Code (clients walking in) can still open() a
## locked door; it then swings by `open_angle` and stays open until close().

@export var locked: bool = false
@export var locked_prompt: String = "Заперто"
## Swing in degrees when code opens it; a positive turn swings the leaf to the front (+Z) side.
@export var open_angle: float = 95.0
@export var swing_time: float = 0.7
## Metres (horizontal) from the hinge; 0 = a door the player opened stays open.
@export var auto_close_distance: float = 2.5

var is_open: bool = false

var _tween: Tween
var _opener: Player = null
var _close_beyond: float = 0.0

@onready var _hinge: Node3D = $Hinge
@onready var _interactable: Interactable = $Hinge/Panel/Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	_update_prompt()


func _physics_process(_delta: float) -> void:
	if _opener == null or not is_open or auto_close_distance <= 0.0 or (_tween and _tween.is_running()):
		return
	var offset: Vector3 = _opener.global_position - global_position
	if Vector2(offset.x, offset.z).length() > _close_beyond:
		close()


func open() -> void:
	_opener = null
	_swing(open_angle)


func close() -> void:
	_opener = null
	_swing(0.0)


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func set_locked(value: bool) -> void:
	locked = value
	_update_prompt()


## The player swings it away from themselves; it remembers them to shut once they walk off.
func _on_interacted(player: Player) -> void:
	if is_open:
		close()
		return
	var player_in_front: bool = global_basis.z.dot(player.global_position - global_position) > 0.0
	_swing(absf(open_angle) * (-1.0 if player_in_front else 1.0))
	_opener = player
	var from: Vector3 = player.global_position - global_position
	_close_beyond = maxf(auto_close_distance, Vector2(from.x, from.z).length() + 0.5)


func _swing(angle_degrees: float) -> void:
	is_open = angle_degrees != 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_hinge, "rotation:y", deg_to_rad(angle_degrees), swing_time)
	_update_prompt()


func _update_prompt() -> void:
	_interactable.enabled = not locked
	if locked:
		_interactable.prompt = locked_prompt
	else:
		_interactable.prompt = "Закрыть дверь" if is_open else "Открыть дверь"
