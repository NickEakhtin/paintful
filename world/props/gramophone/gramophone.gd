extends Node3D
## Desktop gramophone: its Interactable winds it up or stops it; while it plays the horn bobs gently.

const OUTLINE_COLOR: Color = Color(0.95, 0.66, 0.24, 1.0)
const BOB_AMPLITUDE: float = 0.03
const BOB_FREQUENCY: float = 1.25

@onready var horn_pivot: Node3D = $Visual/HornPivot
@onready var outline_mesh: MeshInstance3D = $Visual/OutlineMesh
@onready var _interactable: Interactable = $Interactable

var _playing: bool = false
var _phase: float = 0.0
var _horn_rest_position: Vector3 = Vector3.ZERO
var _return_tween: Tween

func _ready() -> void:
	_horn_rest_position = horn_pivot.position
	_interactable.set_meta("outline_mesh", outline_mesh)
	_interactable.interacted.connect(_on_interacted)

func interaction_outline_color() -> Color:
	return OUTLINE_COLOR

func _on_interacted(_player: Player) -> void:
	_playing = not _playing
	_interactable.prompt = "Остановить граммофон" if _playing else "Завести граммофон"
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
