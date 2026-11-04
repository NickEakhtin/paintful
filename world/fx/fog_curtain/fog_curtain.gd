@tool
extends Node3D
## "Thick fog" behind an opening: a volumetric FogVolume fills the box, so everything in it fades out the farther
## it is (and lamps glow through it), plus optional unshaded see-through `layers`; the box is closed by an opaque
## fog-coloured wall at `depth` metres, so nothing farther than `depth` is visible through the opening.
## The volumetric part needs Volumetric Fog enabled in the scene's Environment (density can stay 0 there).
## The node sits on the outer face of the wall at the middle of the opening; fog extends along -Z (away from the room).

@export var width: float = 5.0:
	set(v):
		width = v
		_rebuild()
@export var height: float = 4.5:
	set(v):
		height = v
		_rebuild()
## Visibility limit in metres from the wall.
@export var depth: float = 1.5:
	set(v):
		depth = v
		_rebuild()
@export var layers: int = 7:
	set(v):
		layers = v
		_rebuild()
@export var color: Color = Color(0.17, 0.16, 0.21):
	set(v):
		color = v
		_rebuild()
## Side walls of the opaque box; turn one off where two fog curtains meet.
@export var left_side: bool = true:
	set(v):
		left_side = v
		_rebuild()
@export var right_side: bool = true:
	set(v):
		right_side = v
		_rebuild()
## Opacity of the first layer; later layers get denser.
@export var near_density: float = 0.12:
	set(v):
		near_density = v
		_rebuild()


## Real volumetric fog inside the box: things fade out gradually with distance.
@export var volumetric: bool = true:
	set(v):
		volumetric = v
		_rebuild()
## How thick the fog gets by the far wall: 3 leaves ~5% of what is there visible, 4 ~2%, 2 ~14%.
@export_range(0.5, 8.0, 0.1) var fog_strength: float = 3.5:
	set(v):
		fog_strength = v
		_rebuild()
## Glow of the fog itself (its colour is `color`), so it reads as fog even where no lamp lights it.
@export_range(0.0, 4.0, 0.05) var fog_glow: float = 1.0:
	set(v):
		fog_glow = v
		_rebuild()
## Soft edges of the fog box, in metres-ish (FogMaterial.edge_fade).
@export_range(0.0, 2.0, 0.05) var fog_edge_fade: float = 0.3:
	set(v):
		fog_edge_fade = v
		_rebuild()

var _fog: FogVolume


## Hide the fog while the camera is outside the wall (e.g. a street view of the facade); the opaque box
## would otherwise cover the facade.
@export var only_from_inside: bool = true


func _ready() -> void:
	set_notify_transform(true)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_place_fog()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not only_from_inside:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		var inside: bool = to_local(camera.global_position).z > 0.0
		for child in get_children():
			if child.has_meta("fog_part"):
				child.visible = inside


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("fog_part"):
			child.queue_free()
	_fog = null
	if volumetric and depth > 0.0:
		_add_fog_volume()
	for i in layers:
		var t: float = float(i + 1) / float(layers + 1)
		var alpha: float = lerpf(near_density, 0.6, t * t)
		_quad(Vector2(width, height), Vector3(0, height * 0.5, -depth * t), Vector3.ZERO, alpha)
	# opaque box at the visibility limit: back, sides, top and bottom
	_quad(Vector2(width, height), Vector3(0, height * 0.5, -depth), Vector3.ZERO, 1.0)
	if left_side:
		_quad(Vector2(depth, height), Vector3(-width * 0.5, height * 0.5, -depth * 0.5), Vector3(0, PI * 0.5, 0), 1.0)
	if right_side:
		_quad(Vector2(depth, height), Vector3(width * 0.5, height * 0.5, -depth * 0.5), Vector3(0, -PI * 0.5, 0), 1.0)
	_quad(Vector2(width, depth), Vector3(0, height, -depth * 0.5), Vector3(PI * 0.5, 0, 0), 1.0)
	_quad(Vector2(width, depth), Vector3(0, 0, -depth * 0.5), Vector3(-PI * 0.5, 0, 0), 1.0)


## Tint the existing volume and its backing panels for the duration of a lightning pulse.
func apply_lightning(amount: float, flash_color: Color) -> void:
	var tint: Color = color.lerp(flash_color, clampf(amount, 0.0, 1.0))
	if is_instance_valid(_fog):
		var volume_material: FogMaterial = _fog.material as FogMaterial
		volume_material.albedo = tint
		volume_material.emission = Color(tint.r, tint.g, tint.b) * fog_glow
	for part in get_children():
		if part is MeshInstance3D and part.has_meta("fog_part"):
			var panel: StandardMaterial3D = part.mesh.surface_get_material(0) as StandardMaterial3D
			panel.albedo_color = Color(tint, panel.albedo_color.a)


func _quad(size: Vector2, pos: Vector3, rot: Vector3, alpha: float) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	mesh.material = material
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.rotation = rot
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.set_meta("fog_part", true)
	add_child(part)


## The volume is top-level and unscaled (FogVolume wants a plain box), sized from this node's global scale.
func _add_fog_volume() -> void:
	var material: FogMaterial = FogMaterial.new()
	material.albedo = color
	material.emission = Color(color.r, color.g, color.b) * fog_glow
	material.edge_fade = fog_edge_fade
	var fog: FogVolume = FogVolume.new()
	fog.material = material
	fog.top_level = true
	fog.set_meta("fog_part", true)
	_fog = fog
	add_child(fog)
	_place_fog()


func _place_fog() -> void:
	if _fog == null or not is_instance_valid(_fog) or not is_inside_tree():
		return
	var scale_g: Vector3 = global_basis.get_scale().abs()
	var size: Vector3 = Vector3(width * scale_g.x, height * scale_g.y, depth * scale_g.z)
	_fog.size = size
	_fog.global_transform = Transform3D(global_basis.orthonormalized(), global_transform * Vector3(0, height * 0.5, -depth * 0.5))
	(_fog.material as FogMaterial).density = fog_strength / maxf(size.z, 0.01)
