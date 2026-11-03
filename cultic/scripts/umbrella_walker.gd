extends Node3D
## A man with an umbrella walking in the rain, as a frame-by-frame silhouette (art/characters/umbrella_walker/,
## 4 frames cut from art/concepts/characters/umbrella_walk_sheet.png by tools/characters/walk_sheet.gd). Each frame
## has a normal map, so the flat figure catches the street lights. He walks from `path_from` to `path_to` (in this
## node's own space), waits a moment, turns and walks back, for ever. The quad always faces the camera (Y-billboard);
## when, on screen, he walks to the left the mirrored frames (frame_N_left, with their own normal maps) are shown.

const FRAMES := "res://art/characters/umbrella_walker/frame_%d%s.png"
const COUNT := 4

@export var path_from := Vector3(-5.25, 0, 0)
@export var path_to := Vector3(5.25, 0, 0)
@export var speed := 0.9                     # metres per second
@export var stride := 0.75                   # metres per 4-frame cycle: sets the frame rate to match the speed
@export var pause_at_ends := Vector2(1.0, 3.0)   # seconds he stands before turning back (random in this range)
@export var animate := true                  # off: he just stands in the middle of the path, no walking, no frames

@onready var _body: MeshInstance3D = $Body
@onready var _material: StandardMaterial3D = (_body.mesh as QuadMesh).material.duplicate()

var _right: Array[Texture2D] = []
var _right_normal: Array[Texture2D] = []
var _left: Array[Texture2D] = []
var _left_normal: Array[Texture2D] = []
var _t := 0.0                                # 0 at path_from, 1 at path_to
var _dir := 1.0
var _wait := 0.0
var _phase := 0.0                            # frames walked, fractional
var _frame := -1
var _facing_left := false


func _ready() -> void:
	for i in COUNT:
		_right.append(load(FRAMES % [i, ""]))
		_right_normal.append(load(FRAMES % [i, "_normal"]))
		_left.append(load(FRAMES % [i, "_left"]))
		_left_normal.append(load(FRAMES % [i, "_left_normal"]))
	_body.material_override = _material
	if not animate:
		_body.position = path_from.lerp(path_to, 0.5)
		_show(0, false)
		set_process(false)
		return
	_t = randf()
	_dir = 1.0 if randf() < 0.5 else -1.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var left := _facing_left
	# frames face right: mirror when, on screen, he is walking to the left
	var camera := get_viewport().get_camera_3d()
	if camera:
		var walk := global_basis * (path_to - path_from).normalized() * _dir
		left = walk.dot(camera.global_basis.x) < 0.0
	if _wait > 0.0:
		_wait -= delta
		_show(0, left)                       # standing: feet apart
		return
	var length := path_from.distance_to(path_to)
	_t += _dir * speed * delta / maxf(length, 0.01)
	if _t >= 1.0 or _t <= 0.0:
		_t = clampf(_t, 0.0, 1.0)
		_dir = -_dir
		_wait = randf_range(pause_at_ends.x, pause_at_ends.y)
	_body.position = path_from.lerp(path_to, _t)
	_phase = fmod(_phase + speed * delta / stride * COUNT, COUNT)
	_show(int(_phase), left)


func _show(frame: int, left: bool) -> void:
	if frame == _frame and left == _facing_left:
		return
	_frame = frame
	_facing_left = left
	_material.albedo_texture = (_left if left else _right)[frame]
	_material.normal_texture = (_left_normal if left else _right_normal)[frame]
