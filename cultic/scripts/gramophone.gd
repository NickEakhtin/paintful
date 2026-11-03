extends StaticBody3D
## Interactable desktop gramophone with a subtle looping horn motion.

const OUTLINE_COLOR := Color(0.95, 0.66, 0.24, 1.0)
const BOB_AMPLITUDE := 0.03
const BOB_FREQUENCY := 1.25

@onready var horn_pivot: Node3D = $Visual/HornPivot
@onready var outline_mesh: MeshInstance3D = $Visual/OutlineMesh

var _playing := false
var _phase := 0.0
var _horn_rest_position := Vector3.ZERO
var _return_tween: Tween

func _ready() -> void:
	_horn_rest_position = horn_pivot.position
	set_meta("outline_mesh", outline_mesh)

func can_interact() -> bool:
	return true

func interaction_outline_color() -> Color:
	return OUTLINE_COLOR

func interact(_player: Node3D) -> void:
	_playing = not _playing
	if _return_tween and _return_tween.is_running():
		_return_tween.kill()
	if _playing:
		_phase = 0.0
	else:
		_return_tween = create_tween()
		_return_tween.tween_property(horn_pivot, "position", _horn_rest_position, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if not _playing:
		return
	_phase += delta * TAU * BOB_FREQUENCY
	horn_pivot.position = _horn_rest_position + Vector3.UP * (sin(_phase) * BOB_AMPLITUDE)
