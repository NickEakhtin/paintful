@tool
class_name NeonSign
extends Node3D
## Neon TATTOO sign (put on a tattoo_sign.glb instance): the letters glow hot pink and each one now and then
## shorts out on its own schedule: a quick sputter, sometimes a short blackout, then it lights up again.
## `powered` off: dark tubes and no light (the studio is closed).
## Runs in the editor too; everything it changes lives inside the instance, so nothing is written into the scene.

@export var neon_color: Color = Color(1.0, 0.1, 0.6)
@export var glow_energy: float = 6.0
@export var mean_interval: float = 7.0          # seconds between glitches of one letter (each letter waits 0.6–2× this)
@export var wall_light_energy: float = 0.8      # pink light the sign casts around itself
@export var preview_in_editor: bool = true     # off: the sign stays as modelled in the editor and only glows in the game
@export var powered: bool = true:
	set(value):
		powered = value
		for i in _mats.size():
			_set_lit(i, _lit[i])

const LETTERS: Array[String] = ["root_9", "root_8", "root_5", "root_6", "root_7"]  # T, A, TT (one mesh, split below), O, O
var _mats: Array[StandardMaterial3D] = []
var _lit: Array[bool] = []
var _light: OmniLight3D


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	var letters: Array[MeshInstance3D] = []
	for letter_name in LETTERS:
		var mesh: MeshInstance3D = find_child(letter_name, true, false) as MeshInstance3D
		if mesh == null:
			continue
		if letter_name == "root_5":
			letters.append_array(_split_vertically(mesh))
		else:
			letters.append(mesh)
	if letters.is_empty():
		return
	var center: Vector3 = Vector3.ZERO
	for mesh in letters:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = neon_color
		mat.roughness = 0.3
		mesh.material_override = mat
		_mats.append(mat)
		_lit.append(true)
		center += mesh.global_transform * mesh.get_aabb().get_center()
	center /= letters.size()
	_light = OmniLight3D.new()
	_light.light_color = neon_color
	_light.omni_range = 1.6
	_light.omni_attenuation = 1.6
	add_child(_light)
	_light.global_position = center + letters[0].global_basis.z.normalized() * 0.12   # just in front of the tubes
	for i in _mats.size():
		_set_lit(i, true)
		_glitch_loop(i)


## The two T's in the middle are one mesh: cut it into an upper and a lower letter so each can flicker alone.
func _split_vertically(mesh: MeshInstance3D) -> Array[MeshInstance3D]:
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		index = PackedInt32Array(range(verts.size()))
	var aabb: AABB = mesh.get_aabb()
	var mid: float = aabb.position.y + aabb.size.y / 2
	var parts: Array[MeshInstance3D] = []
	for upper in [true, false]:
		var part_index: PackedInt32Array = PackedInt32Array()
		for t in range(0, index.size(), 3):
			var cy: float = (verts[index[t]].y + verts[index[t + 1]].y + verts[index[t + 2]].y) / 3.0
			if (cy > mid) == upper:
				part_index.append_array([index[t], index[t + 1], index[t + 2]])
		var part_arrays: Array = arrays.duplicate()
		part_arrays[Mesh.ARRAY_INDEX] = part_index
		var part_mesh: ArrayMesh = ArrayMesh.new()
		part_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part_arrays)
		var part: MeshInstance3D = MeshInstance3D.new()
		part.mesh = part_mesh
		part.transform = mesh.transform
		mesh.get_parent().add_child(part)
		parts.append(part)
	mesh.visible = false
	return parts


func _set_lit(i: int, lit: bool) -> void:
	_lit[i] = lit
	var glowing: bool = lit and powered
	_mats[i].emission_energy_multiplier = glow_energy if glowing else 0.04
	_mats[i].albedo_color = neon_color.lerp(Color.WHITE, 0.35) if glowing else neon_color.darkened(0.75)
	_light.light_energy = wall_light_energy * _lit.count(true) / _lit.size() if powered else 0.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _glitch_loop(i: int) -> void:
	while is_inside_tree():
		await _wait(mean_interval * randf_range(0.6, 2.0))
		if not is_inside_tree():
			return
		for k in randi_range(2, 6):                      # short-circuit sputter
			_set_lit(i, false)
			await _wait(randf_range(0.03, 0.12))
			_set_lit(i, true)
			await _wait(randf_range(0.02, 0.15))
		if randf() < 0.35:                               # sometimes the tube drops out for a moment and stutters back
			_set_lit(i, false)
			await _wait(randf_range(0.4, 1.5))
			for k in randi_range(1, 3):
				_set_lit(i, true)
				await _wait(randf_range(0.03, 0.08))
				_set_lit(i, false)
				await _wait(randf_range(0.05, 0.2))
			_set_lit(i, true)
