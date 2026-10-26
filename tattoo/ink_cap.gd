class_name InkCap
extends Control
## The ink cap on the side table: a small 3D cup with ink inside, rendered by the `Model`
## SubViewport onto `Picture`. The session hit-tests this control's rect and calls
## set_dipping() while the needle is in the ink, which makes the surface wobble.

## Height of the ink surface inside the cup, in the model's units.
const INK_LEVEL: float = 0.45

var _dipping: bool = false
var _time: float = 0.0

@onready var _ink: MeshInstance3D = $Model/Ink


func set_dipping(dipping: bool) -> void:
	_dipping = dipping


func _process(delta: float) -> void:
	var wobble: float = 0.0
	if _dipping:
		_time += delta
		wobble = sin(_time * 24.0)
	_ink.position.y = INK_LEVEL + wobble * 0.008
	_ink.rotation.x = wobble * 0.06
	_ink.rotation.z = cos(_time * 19.0) * 0.05 if _dipping else 0.0
