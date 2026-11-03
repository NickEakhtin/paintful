extends Node3D

const LIGHT_PARTICLE_SHADER := preload("res://cultic/scripts/light_reactive_particles.gdshader")
## A floor hatch the player opens with LMB (player.gd calls interact()): it sinks a little, then slides back
## under the floor. LMB again brings it back. An open hatch also closes by itself once the player, standing on the
## floor above, walks farther than `auto_close_distance` from it (never while the player is down in the basement).
## With a level switch in the scene (scripts/level_switch.gd), LMB on the open hatch takes the player down to the
## basement instead of closing it.

@export var drop := 0.08                        # how far it sinks first
@export var slide := Vector3(0, 0, 1.35)        # then where it slides, in its own axes ("back" = +Z)
@export var duration := 1.2
@export var size := Vector3(1.3, 0.06, 1.5)    # collision box; its top is flush with the hatch's origin
@export var auto_close_distance := 2.5          # metres (horizontal) from the opening; 0 = stays open
@export_group("Dust")
## Glowing dust (points, no geometry): when the hatch opens a burst of it shoots up out of the opening and scatters,
## and for as long as the hatch is open more dust keeps swirling in the shaft and the start of the basement, some of
## it floating up and out. When the hatch closes no new dust is born and what is left fades out.
@export var dust := true
@export var dust_color := Color(0.12, 1.0, 0.22)    # keep red/blue low: bright pure green, not white
@export var dust_brightness := 1.4               # above 1 glows; lower = darker
@export var dust_amount := 440                  # particles flying in the basement at once
@export var dust_burst_amount := 520            # particles in the burst when the hatch opens
@export var dust_burst_boost := 0.6             # brightness of the burst relative to the basement dust: below 1 = darker
@export var dust_area := Vector3(1.0, 1.1, 1.4)  # half-size of the box the dust is born in, metres
@export var dust_offset := Vector3(0.0, -1.3, 0.9)  # centre of that box from the hatch (down into the basement)
@export var dust_lifetime := 3.0               # seconds a dust speck lives before it has faded out
@export var dust_point_size := 3.0               # pixels of the 3D view; under the retro filter 3 = exactly one game pixel, smaller ones vanish

var _closed: Vector3
var _open := false
var _tween: Tween
var _opener: Node3D
var _close_beyond := 0.0
var _dust: GPUParticles3D               # keeps flying in the basement while open
var _dust_burst: GPUParticles3D         # the burst out of the hatch when it opens


func _ready() -> void:
	add_to_group("hatch")
	_closed = position
	# made here, in the game only: a physics body saved inside this scene crashed the Godot 4.7.2 editor
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	shape.position.y = 0.02 - size.y / 2.0
	body.add_child(shape)
	add_child(body)
	# a click target that stays over the opening (layer 3: LMB sees it, the player walks through it),
	# so the hatch can be closed again after it has slid away under the floor
	var target := StaticBody3D.new()
	target.collision_layer = 4
	target.collision_mask = 0
	target.top_level = true
	target.add_child(shape.duplicate())
	add_child(target)
	target.global_transform = global_transform
	if dust:
		_make_dust()


func can_interact() -> bool:
	return not (_tween and _tween.is_running())

func interact(player: Node3D) -> void:
	if _tween and _tween.is_running():
		return
	var switch := get_tree().get_first_node_in_group("level_switch")
	if _open and switch:
		switch.go_down(player)
		return
	_toggle(player)


## Shut at once, no animation (the level switch does it behind the black screen).
func close_now() -> void:
	if _tween:
		_tween.kill()
	position = _closed
	_open = false
	if _dust:
		_dust.emitting = false


func _toggle(player: Node3D) -> void:
	if not _open and player:
		_opener = player
		_close_beyond = maxf(auto_close_distance, _horizontal_distance(player) + 0.5)   # clicked from afar: no snap shut
	var down := _closed + Vector3.DOWN * drop
	var away := down + basis.orthonormalized() * slide
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _open:
		if _dust:
			_dust.emitting = false                      # closing: no new dust, the rest fades out
		_tween.tween_property(self, "position", down, duration * 0.65)
		_tween.tween_property(self, "position", _closed, duration * 0.35)
	else:
		_tween.tween_property(self, "position", down, duration * 0.35)
		if _dust:
			_tween.tween_callback(func() -> void:          # the lid starts to slide: dust bursts out and keeps flowing
				_dust_burst.restart()
				_dust.emitting = true)
		_tween.tween_property(self, "position", away, duration * 0.65)
	_open = not _open


func _physics_process(_delta: float) -> void:
	if not _open or auto_close_distance <= 0.0 or (_tween and _tween.is_running()):
		return
	var player := _opener if is_instance_valid(_opener) else get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var floor_y: Vector3 = get_parent_node_3d().global_transform * _closed if get_parent_node_3d() else _closed
	if player.global_position.y < floor_y.y - 0.5:
		return                                      # down in the basement: keep the way out open
	if _horizontal_distance(player) > _close_beyond:
		_toggle(player)                             # the hatch is open, so this slides it shut


## Distance from the middle of the opening (where the closed hatch lies), ignoring height.
func _horizontal_distance(node: Node3D) -> float:
	var parent := get_parent_node_3d()
	var centre: Vector3 = (parent.global_transform * _closed) if parent else _closed
	var offset := node.global_position - centre
	return Vector2(offset.x, offset.z).length()


## The dust stays over the opening (top-level), whatever the lid does.
func _make_dust() -> void:
	var opening: Vector3 = get_parent_node_3d().global_transform * _closed if get_parent_node_3d() else global_position
	# 1) the burst when the lid slides away: shoots up and out, slows down but never stops, swirls and fades
	var burst := ParticleProcessMaterial.new()
	burst.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	burst.emission_box_extents = Vector3(size.x * 0.45, 0.15, size.z * 0.45)
	burst.direction = Vector3.UP
	burst.spread = 55.0
	burst.initial_velocity_min = 2.2
	burst.initial_velocity_max = 4.8
	burst.gravity = Vector3(0, 0.08, 0)                # floats up a little: never settles down onto the floor
	burst.damping_min = 0.5                            # soft braking: it spreads wide, then keeps drifting
	burst.damping_max = 1.0
	_swirl(burst, 1.4, 2.0, 0.25, 0.5)
	# turbulence steers a particle by replacing its own speed, so in the burst it starts weak (the dust really flies
	# out) and grows over the particle's life (then it swirls)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.05))
	grow.add_point(Vector2(0.35, 0.6))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	burst.turbulence_influence_over_life = grow_tex
	burst.color_ramp = _ramp(dust_brightness * dust_burst_boost, 0.02)
	_dust_burst = _particles("BasementDustBurst", burst, dust_burst_amount, dust_lifetime, true, 0.8)
	_dust_burst.global_transform = Transform3D(Basis.IDENTITY, opening + Vector3(0, -0.2, 0))

	# 2) the dust that keeps flying in the basement for as long as the hatch is open
	var drift := ParticleProcessMaterial.new()
	drift.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	drift.emission_box_extents = dust_area
	drift.direction = Vector3.UP
	drift.spread = 180.0                               # every way
	drift.initial_velocity_min = 0.4
	drift.initial_velocity_max = 1.3
	drift.gravity = Vector3(0, 0.2, 0)                 # a slow rise, so it floats up out of the hatch, never settles
	# no damping: damping stopped the dust dead in mid-air, where it looked like lying on an invisible floor
	_swirl(drift, 2.0, 1.4, 0.15, 0.35)                # gentle enough that the rise still shows
	drift.color_ramp = _ramp(dust_brightness, 0.15)
	_dust = _particles("BasementDust", drift, dust_amount, dust_lifetime, false, 0.0)
	_dust.global_transform = Transform3D(Basis.IDENTITY, opening + basis.orthonormalized() * dust_offset)


func _swirl(m: ParticleProcessMaterial, strength: float, scale: float, influence_min: float, influence_max: float) -> void:
	m.turbulence_enabled = true
	m.turbulence_noise_strength = strength
	m.turbulence_noise_scale = scale
	m.turbulence_noise_speed = Vector3(0.3, 0.5, 0.3)  # the swirls themselves move: never a still pattern
	m.turbulence_noise_speed_random = 0.8
	m.turbulence_influence_min = influence_min
	m.turbulence_influence_max = influence_max


## Colour over a particle's life: fades in, glows, fades out (additive: black is invisible).
func _ramp(brightness: float, fade_in: float) -> GradientTexture1D:
	var bright := Color(dust_color.r, dust_color.g, dust_color.b) * brightness
	var ramp := Gradient.new()
	ramp.set_color(0, Color.BLACK if fade_in > 0.05 else bright)
	ramp.set_color(1, Color.BLACK)
	ramp.add_point(fade_in, bright)
	ramp.add_point(0.7, bright * 0.7)
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	return tex


func _particles(node_name: String, process: ParticleProcessMaterial, count: int, life: float, once: bool, explosive: float) -> GPUParticles3D:
	var material := ShaderMaterial.new()
	material.shader = LIGHT_PARTICLE_SHADER
	material.set_shader_parameter("particle_size", dust_point_size)
	var points := PointMesh.new()
	points.material = material
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = count
	p.lifetime = life
	p.one_shot = once
	p.explosiveness = explosive
	p.randomness = 0.5
	p.emitting = false
	p.local_coords = false
	p.process_material = process
	p.draw_pass_1 = points
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-5, -3, -5), Vector3(10, 9, 10))
	add_child(p)
	p.top_level = true
	return p