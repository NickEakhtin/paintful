class_name EdgeMotes
extends GPUParticles2D
## Spirit-purple specks that burst out where the brush touches the stencil's edge, then float up, swirling, and
## vanish fast (like the dust out of the basement hatch). The session moves this node to the touch and sets
## `level` (0..1): how many fly. Specks already out stay where they are (global coordinates).

## Specks alive at a full level.
@export var count: int = 12000
@export var color: Color = Color(0.72, 0.32, 1.0)
## Seconds a speck lives.
@export var life: float = 1.8
## How hard they burst out of the touch (pixels per second) and how quickly that dies down.
@export var burst_min: float = 150.0
@export var burst_max: float = 420.0
@export var brake: float = 420.0
## How fast they rise once the burst is spent (pixels per second per second) and how much they swirl.
@export var rise: float = 350.0
@export var swirl: float = 0.9
## Speck size in pixels, and how wide the spot they come from is.
@export var size_min: float = 2.0
@export var size_max: float = 4.0
@export var spot_radius: float = 25.0

## 0..1: share of `count` emitted.
var level: float = 0.0:
	set(value):
		level = clampf(value, 0.0, 1.0)
		amount_ratio = level
		emitting = level > 0.01


func _ready() -> void:
	amount = count
	lifetime = life
	local_coords = false
	emitting = false
	texture = _dot_texture()
	# plain blending, unshaded: their own purple whatever is under them (added up, they went white over the skin)
	var flat: CanvasItemMaterial = CanvasItemMaterial.new()
	flat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = flat
	process_material = _process_material()
	visibility_rect = Rect2(-4000, -4000, 8000, 8000)   # global specks: never culled by where the node is


func _process_material() -> ParticleProcessMaterial:
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = spot_radius
	m.particle_flag_disable_z = true
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0   # every way out of the touch
	m.initial_velocity_min = burst_min
	m.initial_velocity_max = burst_max
	m.gravity = Vector3(0, -rise, 0)   # screen y is down: they drift up
	m.damping_min = brake * 0.8
	m.damping_max = brake * 1.2
	m.scale_min = size_min / 8.0
	m.scale_max = size_max / 8.0
	m.turbulence_enabled = true
	m.turbulence_noise_strength = swirl
	m.turbulence_noise_scale = 3.0
	m.turbulence_noise_speed_random = 0.4
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.12
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
	var clear: Color = Color(color, 0.0)
	ramp.colors = PackedColorArray([clear, color, color, clear])
	var ramp_texture: GradientTexture1D = GradientTexture1D.new()
	ramp_texture.gradient = ramp
	m.color_ramp = ramp_texture
	return m


## A soft round speck, 8 px across.
func _dot_texture() -> Texture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	var dot: GradientTexture2D = GradientTexture2D.new()
	dot.gradient = gradient
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 8
	dot.height = 8
	return dot
