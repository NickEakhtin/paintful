@tool
extends Node3D
## Fireflies around the street lamps: on start it finds every lamp post whose name starts with `lamp_prefix`
## (StreetLamp, StreetLamp2, ...) anywhere in the scene and puts a small swarm of glowing points around its lantern
## (the lamp's highest light; the top of the post if it has none).
## The points are particles drawn as plain screen pixels (PointMesh), no geometry; scripts/fireflies.gdshader moves
## and blinks them. Put one node anywhere in the scene; it shows in the editor too.

const SHADER := preload("res://cultic/scripts/fireflies.gdshader")

@export var lamp_prefix := "StreetLamp"
@export var per_lamp := 20:                     # fireflies around each lantern
	set(v):
		per_lamp = v
		_rebuild()
@export var point_size := 3.5:                  # pixels of the 3D view; under the retro filter 3 = exactly one game pixel, smaller ones vanish
	set(v):
		point_size = v
		_rebuild()
@export var orbit_radius := Vector2(0.2, 0.45):  # metres from the lantern, min..max
	set(v):
		orbit_radius = v
		_rebuild()
@export var orbit_height := Vector2(-0.25, 0.25): # metres below/above the lantern, min..max
	set(v):
		orbit_height = v
		_rebuild()


func _ready() -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta("firefly_swarm"):
			child.queue_free()
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if root == null:
		root = get_parent()
	for lamp in root.find_children(lamp_prefix + "*", "Node3D", true, false):
		if lamp.get_parent() and String(lamp.get_parent().name).begins_with(lamp_prefix):
			continue                                    # a part of a lamp, not a lamp
		_add_swarm(lamp)


func _add_swarm(lamp: Node3D) -> void:
	var process := ShaderMaterial.new()
	process.shader = SHADER
	process.set_shader_parameter("radius", orbit_radius)
	process.set_shader_parameter("height", orbit_height)

	var material := ShaderMaterial.new()
	material.shader = preload("res://cultic/scripts/firefly_surface.gdshader")
	material.set_shader_parameter("point_pixels", point_size)
	var points := PointMesh.new()
	points.material = material

	var swarm := GPUParticles3D.new()
	swarm.name = "Fireflies_" + String(lamp.name)
	swarm.set_meta("firefly_swarm", true)
	swarm.amount = per_lamp
	swarm.lifetime = 24.0
	swarm.randomness = 1.0
	swarm.preprocess = 24.0                                  # already flying when the scene starts
	swarm.local_coords = true
	swarm.process_material = process
	swarm.draw_pass_1 = points
	swarm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach := orbit_radius.y + 0.5
	swarm.visibility_aabb = AABB(Vector3(-reach, orbit_height.x - 0.6, -reach), Vector3(reach * 2.0, orbit_height.y - orbit_height.x + 1.2, reach * 2.0))
	add_child(swarm)
	swarm.top_level = true
	# upright around the lantern, whatever the lamp's own rotation or scale
	swarm.global_transform = Transform3D(Basis.IDENTITY, _lantern_position(lamp))


## Where the lantern is: the lamp's highest light, or else the top centre of its meshes.
func _lantern_position(lamp: Node3D) -> Vector3:
	var lights := lamp.find_children("*", "Light3D", true, false)
	if not lights.is_empty():
		var lantern: Node3D = lights[0]
		for light: Light3D in lights:
			if light.global_position.y > lantern.global_position.y:
				lantern = light
		return lantern.global_position
	var top := lamp.global_position
	for mesh: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		top.y = maxf(top.y, box.end.y)
	return top
