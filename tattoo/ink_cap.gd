class_name InkCap
extends Control
## The ink cap on the side table: a small 3D cup with ink inside, rendered by the `Model`
## SubViewport onto `Picture`, at as many pixels as the cup takes on the screen (sharp on any monitor). The session hit-tests this control's rect and calls dip()
## on every click in the ink, which makes the surface wobble for a moment.

## Height of the ink surface inside the cup, in the model's units.
const INK_LEVEL: float = 0.45
## Seconds a dip keeps the ink wobbling.
const WOBBLE_TIME: float = 0.45

var _wobble: float = 0.0
var _time: float = 0.0

@onready var _ink: MeshInstance3D = $Model/Ink
@onready var _view: SubViewport = $Model


func dip() -> void:
	_wobble = 1.0


func _process(delta: float) -> void:
	var pixels: Vector2i = Vector2i((size * get_global_transform_with_canvas().get_scale() * get_viewport().get_final_transform().get_scale()).round())
	if pixels.x > 0 and pixels != _view.size:
		_view.size = pixels
	_wobble = maxf(0.0, _wobble - delta / WOBBLE_TIME)
	_time = _time + delta if _wobble > 0.0 else 0.0
	var wave: float = sin(_time * 24.0) * _wobble
	_ink.position.y = INK_LEVEL + wave * 0.01
	_ink.rotation.x = wave * 0.08
	_ink.rotation.z = cos(_time * 19.0) * 0.06 * _wobble
