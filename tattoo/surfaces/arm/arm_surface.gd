class_name ArmSurface
extends SkinSurface
## The forearm, seen straight on and filling the screen top to bottom. The stencil is the unwrapped skin
## (`theta` -wrap..wrap around the arm, `stencil_height` px along it), so its sides hide behind the
## silhouettes. WASD (`hand_*`) is the artist's left hand: A / D grip the skin behind the left / right
## silhouette and pull it out into a flat flap facing the camera, W / S tilt the pull.
## The math is `ArmShape` (and its copy in `arm_skin.gdshader`), the hand logic `SkinPull`.

@export_group("Shape")
@export var radius: float = 210.0
@export var taper_top: float = 1.1
@export var taper_bottom: float = 0.84
@export var arm_length: float = 1000.0

@export_group("Stencil")
## How far around the arm the stencil reaches on each side of the front line, in degrees.
@export var wrap_angle: float = 120.0
## How much of the arm's length the stencil covers, in pixels, centred.
@export var stencil_height: float = 700.0

@export_group("Ink")
## Ink starts thinning where the skin turns this far from the camera, in degrees...
@export var ink_soft_angle: float = 50.0
## ...and stops landing here.
@export var ink_max_angle: float = 62.0

@export_group("Pull")
## Where the fingers hold the skin, in degrees from the front line (behind the silhouette).
@export var grip_angle: float = 115.0
## How far past the silhouette a full pull drags the skin, in pixels.
@export var max_pull: float = 220.0
## How far toward the camera a full pull brings the grip, in radii (more = flatter flap).
@export var hold_depth: float = 0.25
## Share of the pull lost at the top and bottom of the screen.
@export_range(0.0, 1.0) var grip_bulge: float = 0.35
@export var bulge_spread: float = 300.0
## Steepest pull, in degrees from horizontal.
@export var max_pull_angle: float = 60.0
@export var pull_rate: float = 4.5
@export var return_rate: float = 10.0
## How fast W / S tilt the pull, degrees per second.
@export var tilt_speed: float = 80.0

## Grid of the arm mesh (around, along).
const MESH_STEPS: Vector2i = Vector2i(288, 96)

var shape: ArmShape = ArmShape.new()
var pull: SkinPull = SkinPull.new()

var _material: ShaderMaterial
var _wrap: float = 0.0
var _highlight: float = 0.0
## Which sides hide unfinished stencil, found when a ping starts: (left, right), 0 or 1.
var _hidden_left_right: Vector2 = Vector2.ZERO

@onready var _background: ColorRect = $Background
@onready var _view_viewport: SubViewport = $View3D/Viewport
@onready var _camera: Camera3D = $View3D/Viewport/Camera
@onready var _arm: MeshInstance3D = $View3D/Viewport/Arm
@onready var _ink_layer: SubViewport = $InkLayer
@onready var _stencil: Control = $InkLayer/Stencil
@onready var _hand: Node2D = $Hand
@onready var _key_light: DirectionalLight3D = $View3D/Viewport/Key
@onready var _fill_light: DirectionalLight3D = $View3D/Viewport/Fill
@onready var _stretch_sound: AudioStreamPlayer = $StretchSound
@onready var _release_sound: AudioStreamPlayer = $ReleaseSound


func _ready() -> void:
	_apply_exports()
	# The lamp up and to the left, as for the wet ink's highlight; a warm fill from the lower right.
	_key_light.look_at_from_position(Vector3(-600.0, 700.0, 900.0), Vector3.ZERO)
	_fill_light.look_at_from_position(Vector3(900.0, -250.0, 500.0), Vector3.ZERO)
	_arm.mesh = _build_mesh()
	_material = _arm.material_override
	_material.set_shader_parameter("ink_layer", _ink_layer.get_texture())
	_material.set_shader_parameter("wrap_angle", _wrap)
	_material.set_shader_parameter("stencil_height", stencil_height)
	shape.apply_to(_material)
	_hand.visible = false


func setup(stencil: StencilData) -> void:
	super(stencil)
	if not stencil.parts.is_empty():
		_ink_layer.size = Vector2i(stencil.parts[0].texture.get_size())


func stencil_layer() -> Control:
	return _stencil


func to_cell(screen_point: Vector2) -> Vector2:
	var skin: Vector2 = shape.screen_to_skin(screen_point - _center())
	if not skin.is_finite():
		return Vector2.INF
	return _skin_to_cell(skin)


func project(cell: Vector2) -> Vector3:
	var skin: Vector2 = _cell_to_skin(cell)
	var placed: Vector3 = shape.project(skin.x, skin.y)
	var center: Vector2 = _center()
	return Vector3(placed.x + center.x, placed.y + center.y, placed.z)


func pixels_per_cell() -> float:
	return 2.0 * _wrap * radius / grid.x


## The preimage of a screen circle is a sheared ellipse on stretched skin: bound it with the local Jacobian.
func cells_within(cell: Vector2, radius_px: float) -> Vector2:
	var here: Vector3 = project(cell)
	var du: Vector3 = project(cell + Vector2(1.0, 0.0)) - here
	var dv: Vector3 = project(cell + Vector2(0.0, 1.0)) - here
	var det: float = du.x * dv.y - dv.x * du.y
	var limit: Vector2 = Vector2.ONE * 3.0 * radius_px / pixels_per_cell()
	if absf(det) < 0.0001:
		return limit
	# Rows of the inverse Jacobian: how much u and v change per screen pixel.
	var u_row: Vector2 = Vector2(dv.y, -dv.x) / det
	var v_row: Vector2 = Vector2(-du.y, du.x) / det
	return (Vector2(u_row.length(), v_row.length()) * radius_px + Vector2.ONE).min(limit)


## The brush's screen circle on the skin, through the local Jacobian (shear ignored).
func ink_reach(cell: Vector2, radius_px: float) -> Vector2:
	var here: Vector3 = project(cell)
	var du: Vector3 = project(cell + Vector2(1.0, 0.0)) - here
	var dv: Vector3 = project(cell + Vector2(0.0, 1.0)) - here
	var det: float = du.x * dv.y - dv.x * du.y
	var limit: Vector2 = Vector2.ONE * 3.0 * radius_px / pixels_per_cell()
	if absf(det) < 0.0001:
		return limit
	var u_row: Vector2 = Vector2(dv.y, -dv.x) / det
	var v_row: Vector2 = Vector2(-du.y, du.x) / det
	return (Vector2(u_row.length(), v_row.length()) * radius_px).min(limit)


## The ink is drawn into the skin's own layer, as big as the stencil image.
func ink_pixels() -> Vector2:
	return Vector2(_ink_layer.size)


func supports_tasks() -> bool:
	return false


func hint() -> String:
	return "A / D — оттянуть кожу, W / S — наклон"


func update_surface(delta: float, active: bool) -> void:
	var was_side: int = pull.side
	var was_holding: bool = pull.holding
	if active and not Transition.is_busy:
		pull.update(delta, Input.is_action_pressed("hand_left"), Input.is_action_pressed("hand_right"),
				Input.is_action_pressed("hand_up"), Input.is_action_pressed("hand_down"))
	else:
		pull.update(delta, false, false, false, false)
	if was_side == 0 and pull.side != 0:
		_stretch_sound.play()
	elif was_holding and not pull.holding and pull.amount > 0.3:
		_release_sound.play()
	_sync_pull()


## A ping also lights up the silhouette on each side that still hides unfinished stencil, so it's
## clear which way to pull.
func set_highlight(value: float, canvas: InkCanvas) -> void:
	if value > 0.0 and _highlight <= 0.0:
		_hidden_left_right = _find_hidden(canvas)
	_highlight = value
	_material.set_shader_parameter("hint_left", _hidden_left_right.x * value)
	_material.set_shader_parameter("hint_right", _hidden_left_right.y * value)


func _find_hidden(canvas: InkCanvas) -> Vector2:
	var found: Vector2 = Vector2.ZERO
	var out_of_reach: float = shape.ink_soft_angle
	for part in canvas.part_count():
		if canvas.is_part_done(part):
			continue
		for cell in canvas.part_cells(part):
			if canvas.cell_ink(cell) >= 1.0:
				continue
			var theta: float = _cell_to_skin(Vector2(cell % grid.x + 0.5, 0.0)).x
			if theta < -out_of_reach:
				found.x = 1.0
			elif theta > out_of_reach:
				found.y = 1.0
	return found


func release() -> void:
	pull.release()
	_sync_pull()


func _process(_delta: float) -> void:
	var view_size: Vector2 = size
	if view_size.y > 0.0:
		_camera.size = view_size.y
	(_background.material as ShaderMaterial).set_shader_parameter("size", view_size)


func _sync_pull() -> void:
	shape.side = pull.side
	shape.amount = pull.amount
	shape.shear = pull.shear(max_pull)
	shape.apply_to(_material)
	_place_hand()


## The placeholder hand sits outside the arm with its fingertips on the flap's edge, fingers toward the arm.
func _place_hand() -> void:
	_hand.visible = pull.side != 0 and pull.amount > 0.02
	if not _hand.visible:
		return
	var grip: Vector2 = shape.grip_screen() + size * 0.5
	var inward: Vector2 = Vector2(-pull.side, 0.0).rotated(-pull.angle * pull.side)
	_hand.position = grip - inward * 78.0
	_hand.rotation = inward.angle() + PI * 0.5
	_hand.modulate.a = smoothstep(0.02, 0.3, pull.amount)


func _center() -> Vector2:
	return get_global_rect().get_center()


func _skin_to_cell(skin: Vector2) -> Vector2:
	return Vector2((skin.x / _wrap + 1.0) * 0.5 * grid.x, (skin.y / stencil_height + 0.5) * grid.y)


func _cell_to_skin(cell: Vector2) -> Vector2:
	return Vector2((cell.x / grid.x * 2.0 - 1.0) * _wrap, (cell.y / grid.y - 0.5) * stencil_height)


func _apply_exports() -> void:
	_wrap = deg_to_rad(wrap_angle)
	shape.radius = radius
	shape.taper_top = taper_top
	shape.taper_bottom = taper_bottom
	shape.length = arm_length
	shape.grip_angle = deg_to_rad(grip_angle)
	shape.max_pull = max_pull
	shape.hold_depth = hold_depth
	shape.grip_bulge = grip_bulge
	shape.bulge_spread = bulge_spread
	shape.ink_soft_angle = deg_to_rad(ink_soft_angle)
	shape.ink_max_angle = deg_to_rad(ink_max_angle)
	pull.max_angle = deg_to_rad(max_pull_angle)
	pull.pull_rate = pull_rate
	pull.return_rate = return_rate
	pull.tilt_speed = deg_to_rad(tilt_speed)


## A flat grid; UV = skin coordinates (theta -PI..PI, v along `arm_length` × the shader's MESH_REACH).
## The shader places the vertices.
func _build_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for j in MESH_STEPS.y + 1:
		for i in MESH_STEPS.x + 1:
			var uv: Vector2 = Vector2(float(i) / MESH_STEPS.x, float(j) / MESH_STEPS.y)
			uvs.append(uv)
			vertices.append(Vector3(uv.x, uv.y, 0.0))
	var row: int = MESH_STEPS.x + 1
	for j in MESH_STEPS.y:
		for i in MESH_STEPS.x:
			var a: int = j * row + i
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var reach: float = radius * 3.0 + max_pull
	mesh.custom_aabb = AABB(Vector3(-reach, -arm_length * 2.0, -reach), Vector3(reach * 2.0, arm_length * 4.0, reach * 2.0))
	return mesh
