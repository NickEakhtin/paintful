extends MeshInstance3D
## Drives the sky sphere (overcast_sky.gdshader) in the game: drifts the clouds and now and then sends a
## lightning strike: the clouds light up, a jagged bolt drops to the horizon and a cold flash falls through the windows.
## No lightning while the player is in the basement (`Events.underground_changed`): the flash is a directional light
## and would light the basement through the ground.
## The shader is not left on TIME, because a material that animates by itself makes the editor redraw the whole
## scene every frame; in the editor the sky stays still.

@export var lightning_interval: Vector2 = Vector2(6.0, 18.0)   # seconds between strikes (random in this range)
@export var toward_window: Vector3 = Vector3(0, 0, -1)          # strikes mostly come from this side, so they show in the window
@export var room_flash_energy: float = 1.6
@export var fog_flash_color: Color = Color(0.76, 0.60, 0.98)
## Draw the cloudy sky sphere in the game. Off: the street fog hides it anyway, so only the lightning flashes
## through the windows are kept (the sphere is still shown in the editor).
@export var draw_clouds: bool = false

var _material: ShaderMaterial
var _time: float = 0.0
var _flash_light: DirectionalLight3D
var _underground: bool = false


func _ready() -> void:
	Events.underground_changed.connect(func(underground: bool) -> void: _underground = underground)
	_material = mesh.surface_get_material(0) as ShaderMaterial
	if not draw_clouds:
		mesh = null                         # nothing to draw; the flash light below still works
	_flash_light = DirectionalLight3D.new()
	_flash_light.light_color = Color(0.75, 0.82, 1.0)
	_flash_light.shadow_enabled = false     # shadows off for speed (the window bars no longer throw them)
	_flash_light.visible = false
	add_child(_flash_light)
	_lightning_loop()


func _process(delta: float) -> void:
	_time += delta
	if _material and draw_clouds:
		_material.set_shader_parameter("sky_time", _time)


func _lightning_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(lightning_interval.x, lightning_interval.y)).timeout
		if is_inside_tree() and not _underground:
			await _strike()


func _strike() -> void:
	var yaw: float = randf_range(-1.0, 1.0) if randf() < 0.7 else randf_range(-PI, PI)   # mostly in front of the window
	var flat: Vector2 = Vector2(toward_window.x, toward_window.z).normalized().rotated(yaw)
	var dir: Vector3 = Vector3(flat.x, randf_range(0.15, 0.35), flat.y).normalized()
	_material.set_shader_parameter("flash_dir", dir)
	_material.set_shader_parameter("bolt_seed", randf() * 100.0)
	_flash_light.look_at_from_position(Vector3.ZERO, -dir)   # light travels from the strike into the room
	var with_bolt: bool = randf() < 0.6
	# a real strike flickers: a few quick pulses, the last one fading out
	var pulses: int = randi_range(2, 4)
	for i in pulses:
		var last: bool = i == pulses - 1
		_set_flash(randf_range(0.6, 1.0), with_bolt)
		await get_tree().create_timer(randf_range(0.04, 0.09)).timeout
		if last:
			for k in 10:
				_set_flash(lerpf(0.8, 0.0, (k + 1) / 10.0), with_bolt and k < 4)
				await get_tree().create_timer(0.03).timeout
		else:
			_set_flash(0.1, false)
			await get_tree().create_timer(randf_range(0.05, 0.15)).timeout
	_set_flash(0.0, false)


func _set_flash(amount: float, bolt: bool) -> void:
	if _underground:
		amount = 0.0                        # went down mid-strike: put it out
	_material.set_shader_parameter("flash", amount)
	_material.set_shader_parameter("bolt", 1.0 if bolt and amount > 0.3 else 0.0)
	_flash_light.light_energy = amount * room_flash_energy
	_flash_light.visible = amount > 0.0
	get_tree().call_group("lightning_fog", "apply_lightning", amount, fog_flash_color)
