class_name SkullRitual
extends Node3D
## Put under the skull model on the offering table. activate() turns the basement violet: every light and fog volume
## under `palette_root`, the altar and ring materials, the stair draft, the offering's flames; the skull rises a
## little, sways, turns to `gaze_target` and its sockets glow; the table's candles float. restore() puts it all back.
## A white frame flashes on every change.

signal violet_stage_changed(active: bool)

const VIOLET: Color = Color(0.68, 0.22, 1.0)
const ALTAR_MATERIAL: Material = preload("res://art/materials/altar_green.tres")
const RING_MATERIAL: Material = preload("res://art/materials/circle_relic_green.tres")
const ALTAR_MASK: Texture2D = preload("res://art/materials/altar_emission_mask.png")
const RING_MASK: Texture2D = preload("res://art/materials/circle_relic_emission_mask.png")

## Everything under this takes the violet light (the basement).
@export var palette_root: Node3D
## The table with candles and coins: its flames turn violet, its candles float.
@export var offering: Node3D
## Particles whose colour ramps turn violet (the stair draft).
@export var tinted_particles: Array[GPUParticles3D] = []

var activated: bool = false

var _palette_lights: Array[Light3D] = []
var _palette_fogs: Array[FogVolume] = []
var _palette_flames: Array[MeshInstance3D] = []
var _ritual_candles: Array[Node3D] = []
var _candle_rest_transforms: Array[Transform3D] = []
var _palette_meshes: Array[MeshInstance3D] = []
var _violet_materials: Dictionary = {}
var _restore_palette: Array[Callable] = []
var _eyes: Node3D = Node3D.new()
var _flash: ColorRect = ColorRect.new()
var _gaze_target: Node3D
var _hover_blend: float = 0.0
var _hover_phase: float = 0.0

@onready var _skull_root: Node3D = get_parent_node_3d()
@onready var _resting_position: Vector3 = _skull_root.position
@onready var _resting_rotation: Vector3 = _skull_root.rotation


func _ready() -> void:
	_collect_palette_targets.call_deferred()
	_build_eyes()
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.layer = 110
	add_child(overlay)
	overlay.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.hide()
	set_process(false)
	set_physics_process(false)


func is_violet_active() -> bool:
	return activated


## Violet, and the skull watches `gaze` (the player's camera).
func activate(gaze: Node3D) -> void:
	if activated:
		return
	_flash_once()
	activated = true
	_gaze_target = gaze
	_apply_violet()
	violet_stage_changed.emit(true)
	_eyes.visible = true
	set_process(true)
	set_physics_process(true)


func restore() -> void:
	if not activated:
		return
	_flash_once()
	activated = false
	violet_stage_changed.emit(false)
	for restore_call: Callable in _restore_palette:
		restore_call.call()
	_restore_palette.clear()
	_eyes.hide()
	set_process(false)
	set_physics_process(true)


func _build_eyes() -> void:
	_eyes.name = "SocketEyes"
	add_child(_eyes)
	_eyes.hide()
	var orb: SphereMesh = _glowing_sphere(0.0085, Color(0.72, 0.16, 1.0), 2.0)
	var iris: SphereMesh = _glowing_sphere(0.0038, Color(0.94, 0.80, 1.0), 3.0)
	for socket_x: float in [-0.034, 0.034]:
		var eye: MeshInstance3D = MeshInstance3D.new()
		eye.mesh = orb
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(socket_x, 0.087, 0.055)
		_eyes.add_child(eye)
		var glint: MeshInstance3D = MeshInstance3D.new()
		glint.mesh = iris
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glint.position.z = -0.0079
		eye.add_child(glint)


func _glowing_sphere(radius: float, color: Color, energy: float) -> SphereMesh:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = material
	return sphere


func _physics_process(delta: float) -> void:
	_hover_blend = move_toward(_hover_blend, 1.0 if activated else 0.0, delta / 1.25)
	if _hover_blend == 0.0:
		_skull_root.position = _resting_position
		_skull_root.rotation = _resting_rotation
		for i in _ritual_candles.size():
			_ritual_candles[i].transform = _candle_rest_transforms[i]
		_hover_phase = 0.0
		set_physics_process(false)
		return
	_hover_phase += delta
	var sway: float = 0.045 * sin(TAU * _hover_phase / 4.6)
	var height: float = 0.22 + 0.025 * sin(TAU * _hover_phase / 3.1)
	_skull_root.position = _resting_position + Vector3(sway, height, 0.0) * smoothstep(0.0, 1.0, _hover_blend)
	var desired_yaw: float = _resting_rotation.y
	if activated and is_instance_valid(_gaze_target):
		var toward_player: Vector3 = _gaze_target.global_position - _skull_root.global_position
		toward_player.y = 0.0
		if toward_player.length_squared() > 0.0001:
			desired_yaw = atan2(toward_player.x, toward_player.z)
	_skull_root.rotation.y = lerp_angle(_skull_root.rotation.y, desired_yaw, minf(1.0, delta * 3.5))
	var blend: float = smoothstep(0.0, 1.0, _hover_blend)
	for i in _ritual_candles.size():
		var candle: Node3D = _ritual_candles[i]
		var base: Transform3D = _candle_rest_transforms[i]
		var phase: float = _hover_phase * 1.35 + float(i) * 1.71
		var target: Transform3D = base
		target.origin += Vector3(0.018 * sin(phase), 0.09 + 0.025 * sin(phase * 0.73), 0.018 * cos(phase * 0.81))
		target.basis = base.basis * Basis.from_euler(Vector3(0.035 * sin(phase * 0.63), 0.0, 0.035 * cos(phase * 0.77)))
		candle.transform = base.interpolate_with(target, blend)


func _process(_delta: float) -> void:
	if is_instance_valid(_gaze_target):
		for eye: Node3D in _eyes.get_children():
			eye.look_at(_gaze_target.global_position, Vector3.UP)


func _flash_once() -> void:
	_flash.show()
	RenderingServer.frame_post_draw.connect(_flash.hide, CONNECT_ONE_SHOT)


## Lights, fog and the altar and ring meshes, once every instance has built its parts.
func _collect_palette_targets() -> void:
	_palette_lights.assign(palette_root.find_children("*", "Light3D", true, false))
	_palette_fogs.assign(palette_root.find_children("*", "FogVolume", true, false))
	if offering != null:
		_palette_flames.assign(offering.find_children("Flame", "MeshInstance3D", true, false))
		for candle: Node3D in offering.get_node("Candles").get_children():
			_ritual_candles.append(candle)
			_candle_rest_transforms.append(candle.transform)
	for mesh: MeshInstance3D in palette_root.find_children("*", "MeshInstance3D", true, false):
		var material: Material = mesh.material_override
		if material != ALTAR_MATERIAL and material != RING_MATERIAL:
			continue
		_palette_meshes.append(mesh)
		if not _violet_materials.has(material):
			var tinted: StandardMaterial3D = material.duplicate() as StandardMaterial3D
			tinted.emission_texture = ALTAR_MASK if material == ALTAR_MATERIAL else RING_MASK
			tinted.emission = VIOLET
			_violet_materials[material] = tinted


func _apply_violet() -> void:
	for light: Light3D in _palette_lights:
		_restore_palette.append(light.set.bind("light_color", light.light_color))
		light.light_color = VIOLET * light.light_color.v
	for fog: FogVolume in _palette_fogs:
		var mist: FogMaterial = fog.material as FogMaterial
		if mist:
			_restore_palette.append(fog.set.bind("material", mist))
			mist = mist.duplicate()
			mist.albedo = VIOLET * mist.albedo.v
			mist.emission = VIOLET * mist.emission.v
			fog.material = mist
	# room dust already scatters real light; only self-lit particles use ramps
	var targets: Array[Node] = []
	for particles: GPUParticles3D in tinted_particles:
		targets.append(particles)
		targets.append_array(particles.find_children("*", "GPUParticles3D", true, false))
	for particles: GPUParticles3D in targets:
		var process: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
		if process and process.color_ramp is GradientTexture1D:
			var gradient: Gradient = (process.color_ramp as GradientTexture1D).gradient
			_restore_palette.append(gradient.set.bind("colors", gradient.colors))
			for i in gradient.get_point_count():
				var prior: Color = gradient.get_color(i)
				var tint: Color = VIOLET * prior.v
				tint.a = prior.a
				gradient.set_color(i, tint)
	for flame: MeshInstance3D in _palette_flames:
		_restore_palette.append(flame.set_instance_shader_parameter.bind("violet_flame", false))
		flame.set_instance_shader_parameter("violet_flame", true)
	for mesh: MeshInstance3D in _palette_meshes:
		var original: Material = mesh.material_override
		if _violet_materials.has(original):
			_restore_palette.append(mesh.set.bind("material_override", original))
			mesh.material_override = _violet_materials[original]
