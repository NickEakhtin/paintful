extends Node3D
## Static props (ruined walls, ground patches): in the game each mesh gets an exact (trimesh) collision, made
## here at start like the basement hatch's, so no physics body is saved in the scene (that crashed the 4.7.2 editor).

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.create_trimesh_collision()
