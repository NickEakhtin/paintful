extends StaticBody3D

signal violet_stage_changed(active: bool)
## The skull changes the basement palette between its original lighting and violet.
const VIOLET := Color(0.68, 0.22, 1.0)
const ALTAR_MATERIAL := preload("res://art/materials/altar_green.tres")
const RING_MATERIAL := preload("res://art/materials/circle_relic_green.tres")
const ALTAR_MASK := preload("res://art/materials/altar_emission_mask.png")
const RING_MASK := preload("res://art/materials/circle_relic_emission_mask.png")
const RESET_DISTANCE := 5.0

var activated := false

var palette_lights: Array[Light3D] = []
var palette_fogs: Array[FogVolume] = []
var palette_flames: Array[MeshInstance3D] = []
var ritual_candles: Array[Node3D] = []
var candle_rest_transforms: Array[Transform3D] = []
var palette_meshes: Array[MeshInstance3D] = []
var violet_materials := {}

var restore_palette: Array[Callable] = []
var eyes := Node3D.new()
var flash := ColorRect.new()
var gaze_target: Node3D
@onready var skull_root := get_parent_node_3d()
@onready var resting_position := skull_root.position
@onready var resting_rotation := skull_root.rotation
var hover_blend := 0.0
var hover_phase := 0.0

func _ready() -> void:
	var skull := get_parent().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var target := CollisionShape3D.new()
	set_meta("outline_mesh", skull)
	target.shape = skull.mesh.create_trimesh_shape()
	target.transform = global_transform.affine_inverse() * skull.global_transform
	add_child(target)

	_collect_palette_targets.call_deferred()
	_build_eyes()
	var overlay := CanvasLayer.new()
	overlay.layer = 110
	add_child(overlay)
	overlay.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.hide()
	set_process(false)
	set_physics_process(false)

func _build_eyes() -> void:
	eyes.name = "SocketEyes"
	add_child(eyes)
	eyes.hide()
	var orb := _glowing_sphere(0.0085, Color(0.72, 0.16, 1.0), 2.0)
	var iris := _glowing_sphere(0.0038, Color(0.94, 0.80, 1.0), 3.0)
	for socket_x in [-0.034, 0.034]:
		var eye := MeshInstance3D.new()
		eye.mesh = orb
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = Vector3(socket_x, 0.087, 0.055)
		eyes.add_child(eye)
		var glint := MeshInstance3D.new()
		glint.mesh = iris
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glint.position.z = -0.0079
		eye.add_child(glint)

func _glowing_sphere(radius: float, color: Color, energy: float) -> SphereMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = material
	return sphere

func _physics_process(delta: float) -> void:
	hover_blend = move_toward(hover_blend, 1.0 if activated else 0.0, delta / 1.25)
	if hover_blend == 0.0:
		skull_root.position = resting_position
		skull_root.rotation = resting_rotation
		for i in ritual_candles.size():
			ritual_candles[i].transform = candle_rest_transforms[i]
		hover_phase = 0.0
		set_physics_process(false)
		return
	hover_phase += delta
	var sway := 0.045 * sin(TAU * hover_phase / 4.6)
	var height := 0.22 + 0.025 * sin(TAU * hover_phase / 3.1)
	skull_root.position = resting_position + Vector3(sway, height, 0.0) * smoothstep(0.0, 1.0, hover_blend)
	var desired_yaw := resting_rotation.y
	if activated and is_instance_valid(gaze_target):
		var toward_player := gaze_target.global_position - skull_root.global_position
		toward_player.y = 0.0
		if toward_player.length_squared() > 0.0001:
			desired_yaw = atan2(toward_player.x, toward_player.z)
	skull_root.rotation.y = lerp_angle(skull_root.rotation.y, desired_yaw, minf(1.0, delta * 3.5))
	var blend := smoothstep(0.0, 1.0, hover_blend)
	for i in ritual_candles.size():
		var candle := ritual_candles[i]
		var base := candle_rest_transforms[i]
		var phase := hover_phase * 1.35 + float(i) * 1.71
		var target := base
		target.origin += Vector3(0.018 * sin(phase), 0.09 + 0.025 * sin(phase * 0.73), 0.018 * cos(phase * 0.81))
		target.basis = base.basis * Basis.from_euler(Vector3(0.035 * sin(phase * 0.63), 0.0, 0.035 * cos(phase * 0.77)))
		candle.transform = base.interpolate_with(target, blend)

func _process(_delta: float) -> void:
	var player := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if activated and is_instance_valid(player):
		var away := player.global_position - skull_root.global_position
		away.y = 0.0
		if away.length() >= RESET_DISTANCE:
			_flash_once()
			_restore_green()
			return
	if is_instance_valid(gaze_target):
		for eye: Node3D in eyes.get_children():
			eye.look_at(gaze_target.global_position, Vector3.UP)

func _flash_once() -> void:
	flash.show()
	RenderingServer.frame_post_draw.connect(flash.hide, CONNECT_ONE_SHOT)

func _restore_green() -> void:
	var was_violet := activated
	activated = false
	if was_violet:
		violet_stage_changed.emit(false)
	for restore in restore_palette:
		restore.call()
	restore_palette.clear()
	eyes.hide()
	set_process(false)
	set_physics_process(true)
	var altar_control := owner.get_node_or_null("GreenRoomDecor/Volcano/PitAltarLift")
	if altar_control and altar_control.has_method("lower"):
		altar_control.lower()

func interaction_outline_color() -> Color:
	return Color("#e7b548").lerp(Color("#8642b1"), smoothstep(0.0, 1.0, hover_blend))

func is_violet_active() -> bool:
	return activated

func can_interact() -> bool:
	return not flash.visible

func interact(player: Node3D) -> void:
	if flash.visible:
		return
	_flash_once()
	if not activated:
		activated = true
		gaze_target = player.get_node("Head/Camera3D")
		_apply_violet()
		violet_stage_changed.emit(true)
		_process(0)
	else:
		_restore_green()
	eyes.visible = activated
	set_process(activated)
	set_physics_process(true)

# Collect fixed room geometry and lights after all scene instances have entered the tree.
func _collect_palette_targets() -> void:
	var scene := owner
	var basement: AABB = scene.get_node("LevelSwitch").basement_box
	for light: Light3D in scene.find_children("*", "Light3D", true, false):
		if basement.has_point(light.global_position) or light.is_in_group("basement_stairs"):
			palette_lights.append(light)
	for fog: FogVolume in scene.find_children("*", "FogVolume", true, false):
		if basement.has_point(fog.global_position) or fog.is_in_group("basement_stairs"):
			palette_fogs.append(fog)
	var decor := scene.get_node("GreenRoomDecor")
	var offering := decor.get_node("SkullTableOffering")
	palette_flames.assign(offering.find_children("Flame", "MeshInstance3D", true, false))
	for candle: Node3D in offering.get_node("Candles").get_children():
		ritual_candles.append(candle)
		candle_rest_transforms.append(candle.transform)
	for mesh: MeshInstance3D in decor.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.material_override
		if material != ALTAR_MATERIAL and material != RING_MATERIAL:
			continue
		palette_meshes.append(mesh)
		if not violet_materials.has(material):
			var tinted := material.duplicate() as StandardMaterial3D
			tinted.emission_texture = ALTAR_MASK if material == ALTAR_MATERIAL else RING_MASK
			tinted.emission = VIOLET
			violet_materials[material] = tinted

func _apply_violet() -> void:
	var scene := get_tree().current_scene
	for light in palette_lights:
		restore_palette.append(light.set.bind("light_color", light.light_color))
		light.light_color = VIOLET * light.light_color.v
	for fog in palette_fogs:
		var mist := fog.material as FogMaterial
		if mist:
			restore_palette.append(fog.set.bind("material", mist))
			mist = mist.duplicate()
			mist.albedo = VIOLET * mist.albedo.v
			mist.emission = VIOLET * mist.emission.v
			fog.material = mist

	# Room dust already scatters real light. Only the self-lit staircase and hatch use ramps.
	var draft := scene.get_node("StairDraft")
	var targets := draft.find_children("*", "GPUParticles3D", true, false)
	targets.append(draft)
	targets.append_array(scene.get_node("BasementHatch").find_children("*", "GPUParticles3D", true, false))
	for particles: GPUParticles3D in targets:
		var process := particles.process_material as ParticleProcessMaterial
		if process and process.color_ramp is GradientTexture1D:
			var gradient: Gradient = process.color_ramp.gradient
			restore_palette.append(gradient.set.bind("colors", gradient.colors))
			for i in gradient.get_point_count():
				var prior := gradient.get_color(i)
				var tint := VIOLET * prior.v
				tint.a = prior.a
				gradient.set_color(i, tint)

	for flame in palette_flames:
		restore_palette.append(flame.set_instance_shader_parameter.bind("violet_flame", false))
		flame.set_instance_shader_parameter("violet_flame", true)
	for mesh in palette_meshes:
		var original := mesh.material_override
		if violet_materials.has(original):
			restore_palette.append(mesh.set.bind("material_override", original))
			mesh.material_override = violet_materials[original]
