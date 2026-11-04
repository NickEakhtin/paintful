@tool
extends Node
## Puts a painting into every picture frame (models/frame_*.glb) of the scene this node sits in, also in the editor.
## Frames of one size share a painting: art/paintings/canvas/<size>.png, made by tools/paintings/frame_paintings.gd
## from your art/paintings/<size>.png (white until you add one). Frames added later get a canvas too.
## The canvases live inside the frame instances and are not saved into the scene.

# frame model -> [opening quad centre, quad size] in model space (printed by tools/paintings/frame_paintings.gd)
const QUADS: Dictionary = {
	"frame_arched": [Vector2(0.0006, 0.4063), Vector2(0.4661, 0.7361)],
	"frame_oval": [Vector2(-0.0011, 0.3961), Vector2(0.3892, 0.5695)],
	"frame_square": [Vector2(-0.0011, 0.3993), Vector2(0.5216, 0.6792)],
}
# size name -> [model, instance scale]; a frame gets the size of its model with the nearest scale
const SIZES: Dictionary = {
	"arched": ["frame_arched", 1.2],
	"oval": ["frame_oval", 1.2],
	"square_small": ["frame_square", 0.448],
	"square_medium": ["frame_square", 0.64],
	"square_large": ["frame_square", 1.29],
	"square_xl": ["frame_square", 1.675],
}
const GAP: float = 0.005   # canvas stands this far in front of the wall behind the frame

var _room_centre: Vector3 = Vector3.ZERO
var _walls: Array[MeshInstance3D] = []

var _materials: Dictionary = {}


func _ready() -> void:
	var scene_root: Node = owner if owner else get_parent()
	var shell: Node3D = scene_root.get_node_or_null("Shell") as Node3D
	if shell:
		_walls.assign(shell.find_children("*", "MeshInstance3D", true, false))
		var parts: Array[Node] = shell.find_children("*", "Node3D", false, false)
		for part: Node3D in parts:
			_room_centre += part.global_position / parts.size()
	for frame: Node3D in scene_root.find_children("*", "Node3D", true, false):
		var model: String = frame.scene_file_path.get_file().get_basename()
		if QUADS.has(model) and not frame.has_node("Painting"):
			_add_canvas(frame, model)


func _add_canvas(frame: Node3D, model: String) -> void:
	var scale_y: float = frame.transform.basis.y.length()
	var size_name: String = ""
	for s in SIZES:
		if SIZES[s][0] == model and (size_name == "" or absf(SIZES[s][1] - scale_y) < absf(SIZES[size_name][1] - scale_y)):
			size_name = s
	var quad: QuadMesh = QuadMesh.new()
	quad.size = QUADS[model][1]
	quad.material = _material(size_name)
	var canvas: MeshInstance3D = MeshInstance3D.new()
	canvas.name = "Painting"
	canvas.mesh = quad
	# frames hang at different depths, some back to front: put the canvas on the room side, just off the wall
	var faces_room: bool = frame.global_basis.z.dot(_room_centre - frame.global_position) > 0.0
	var centre: Vector3 = frame.global_transform * Vector3(QUADS[model][0].x, QUADS[model][0].y, 0.0)
	var normal: Vector3 = frame.global_basis.z.normalized() * (1.0 if faces_room else -1.0)
	var wall: float = _wall_distance(centre + normal * 0.5, -normal)
	var plane: Vector3 = centre + normal * ((0.5 - wall if wall >= 0.0 else 0.0) + GAP)
	frame.add_child(canvas)
	canvas.owner = frame   # clicking the canvas in the editor selects its frame (and it is still not saved)
	var facing: Basis = Basis.looking_at(-normal, frame.global_basis.y.normalized())   # quad front towards the room
	canvas.global_transform = Transform3D(facing.scaled_local(Vector3(frame.global_basis.x.length(), frame.global_basis.y.length(), 1.0)), plane)


func _material(size_name: String) -> StandardMaterial3D:
	if not _materials.has(size_name):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		var path: String = "res://art/paintings/canvas/%s.png" % size_name
		if ResourceLoader.exists(path):
			mat.albedo_texture = load(path)
		else:   # a fresh painting Godot has not imported yet: read the file directly
			mat.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.roughness = 0.85
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[size_name] = mat
	return _materials[size_name]


## Distance along `dir` from `from` to the nearest face of the room shell, or -1 if there is none within a metre.
func _wall_distance(from: Vector3, dir: Vector3) -> float:
	var best: float = -1.0
	var probe: AABB = AABB(from, Vector3.ZERO).expand(from + dir)
	for wall in _walls:
		if wall.mesh == null or not (wall.global_transform * wall.get_aabb()).intersects(probe):
			continue
		var inv: Transform3D = wall.global_transform.affine_inverse()
		var o: Vector3 = inv * from
		var d: Vector3 = (inv.basis * dir)
		var faces: PackedVector3Array = wall.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(o, d, faces[i], faces[i + 1], faces[i + 2])
			if hit != null:
				var dist: float = from.distance_to(wall.global_transform * hit)
				if dist <= 1.0 and (best < 0.0 or dist < best):
					best = dist
	return best
