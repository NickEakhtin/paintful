extends GPUParticles3D
## Heavy rain: a box of GPU particle streaks (cheap: unshaded, no shadows, no collision). Drops fall fast, slanted by
## `wind` and scattered by `spread`. Either rides above the camera (`follow_camera`) or stays where it is placed and
## rains over `area` (metres, x by z) from its own height down to `fall_height` below it — e.g. outside a window.

@export var follow_camera := true
@export var height_above_camera := 12.0
## Size of the raining patch in metres (x, z).
@export var area := Vector2(20, 20)
## How far the drops fall before vanishing; sets the particle lifetime from the drop speed.
@export var fall_height := 20.0
## Horizontal push in m/s² (x, z); changes the slant of the whole downpour.
@export var wind := Vector2(2.0, 0.8):
	set(value):
		wind = value
		_apply_wind()


func _ready() -> void:
	# every rain patch gets its own process material so the areas do not overwrite each other
	process_material = process_material.duplicate()
	var material := process_material as ParticleProcessMaterial
	material.emission_box_extents = Vector3(area.x * 0.5, 0.2, area.y * 0.5)
	var speed := (material.initial_velocity_min + material.initial_velocity_max) * 0.5
	lifetime = maxf(fall_height / speed, 0.05)
	preprocess = lifetime
	_apply_wind()


func _process(_delta: float) -> void:
	if not follow_camera:
		return
	var camera := get_viewport().get_camera_3d()
	if camera:
		var p := camera.global_position
		global_position = Vector3(p.x, p.y + height_above_camera, p.z)


func _apply_wind() -> void:
	var material := process_material as ParticleProcessMaterial
	if material:
		material.gravity = Vector3(wind.x, -9.8, wind.y)
