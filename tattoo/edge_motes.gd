class_name EdgeMotes
extends GPUParticles2D
## Tiny spirit-purple specks that come off every edge of the screen and float up, swirling, while the edge frame
## burns (like the dust out of the basement hatch). The session sets `level` (0..1): how many fly.

## Specks alive at a full level.
@export var count: int = 420
@export var color: Color = Color(0.72, 0.32, 1.0)
## Seconds a speck lives.
@export var life: float = 3.0
## How fast they rise (pixels per second, at the end of the climb) and how much they swirl.
@export var rise: float = 90.0
@export var swirl: float = 0.9
## Speck size in pixels.
@export var size_min: float = 2.5
@export var size_max: float = 5.0
## How many points along the screen's edges they come from.
const POINTS: int = 512

## 0..1: share of `count` emitted.
var level: float = 0.0:
	set(value):
		level = clampf(value, 0.0, 1.0)
		amount_ratio = level
		emitting = level > 0.01

var _built_for: Vector2 = Vector2.ZERO


func _ready() -> void:
	amount = count
	lifetime = life
	local_coords = false
	emitting = false
	texture = _dot_texture()
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	process_material = _process_material()
	_fit_points()
	get_viewport().size_changed.connect(_fit_points)


func _process_material() -> ParticleProcessMaterial:
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	m.particle_flag_disable_z = true
	m.direction = Vector3(1, 0, 0)   # turned to each point's normal: away from its edge, into the screen
	m.spread = 40.0
	m.initial_velocity_min = 60.0
	m.initial_velocity_max = 170.0
	m.gravity = Vector3(0, -rise, 0)   # screen y is down: they drift up
	m.damping_min = 20.0
	m.damping_max = 45.0
	m.scale_min = size_min / 8.0
	m.scale_max = size_max / 8.0
	m.turbulence_enabled = true
	m.turbulence_noise_strength = swirl
	m.turbulence_noise_scale = 3.0
	m.turbulence_noise_speed_random = 0.4
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.12
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color.BLACK, color * 2.6, color * 1.6, Color.BLACK])
	var ramp_texture: GradientTexture1D = GradientTexture1D.new()
	ramp_texture.gradient = ramp
	m.color_ramp = ramp_texture
	return m


## A soft round speck, 8 px across (additive: black is invisible).
func _dot_texture() -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(0.8, 0.8, 0.8), Color.BLACK])
	var dot: GradientTexture2D = GradientTexture2D.new()
	dot.gradient = gradient
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 8
	dot.height = 8
	return dot


## Spawn points spread evenly along the four edges of the screen (a little inside them).
func _fit_points() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	if screen == _built_for or screen == Vector2.ZERO:
		return
	_built_for = screen
	var perimeter: float = 2.0 * (screen.x + screen.y)
	var image: Image = Image.create(POINTS, 1, false, Image.FORMAT_RGF)
	var normals: Image = Image.create(POINTS, 1, false, Image.FORMAT_RGF)
	for i in POINTS:
		var at: float = (i + randf()) / POINTS * perimeter
		var inset: float = randf_range(2.0, 18.0)
		var point: Vector2
		var inward: Vector2
		if at < screen.x:
			point = Vector2(at, inset)
			inward = Vector2.DOWN
		elif at < screen.x + screen.y:
			point = Vector2(screen.x - inset, at - screen.x)
			inward = Vector2.LEFT
		elif at < 2.0 * screen.x + screen.y:
			point = Vector2(at - screen.x - screen.y, screen.y - inset)
			inward = Vector2.UP
		else:
			point = Vector2(inset, at - 2.0 * screen.x - screen.y)
			inward = Vector2.RIGHT
		image.set_pixel(i, 0, Color(point.x, point.y, 0.0))
		normals.set_pixel(i, 0, Color(inward.x, inward.y, 0.0))
	var m: ParticleProcessMaterial = process_material
	m.emission_point_texture = ImageTexture.create_from_image(image)
	m.emission_normal_texture = ImageTexture.create_from_image(normals)
	m.emission_point_count = POINTS
	visibility_rect = Rect2(Vector2(-100, -400), screen + Vector2(200, 500))
