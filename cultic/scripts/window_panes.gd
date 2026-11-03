@tool
extends Node3D
## Glazing for a window opening: a sheet of glass split into even panes by a dark frame with mullions.
## Put the node in the middle of the opening, facing the room (+Z); `size` is the opening's width and height.
## The glass and bars are rebuilt on load and not saved into the scene; clicking them selects this node.

@export var size := Vector2(1.78, 2.06)
@export var columns := 2
@export var rows := 3
@export var frame_width := 0.07         # outer frame bars
@export var bar_width := 0.045          # bars between the panes
@export var bar_depth := 0.06
@export var frame_color := Color(0.07, 0.055, 0.05)
@export var glass_color := Color(0.55, 0.62, 0.68, 0.18)
# box the room's reflection is captured in, centred at `reflection_offset` from the window; zero size = no reflections
@export var reflection_box := Vector3.ZERO           # e.g. (10.3, 3.4, 5.3) for my_room; off by default
@export var reflection_offset := Vector3(0.0, -0.44, 2.65)


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = frame_color
	wood.roughness = 0.55
	wood.metallic = 0.2
	var glass := StandardMaterial3D.new()
	glass.albedo_color = glass_color
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA   # reflections stay bright on see-through glass
	glass.roughness = 0.0
	glass.metallic = 0.6           # shiny: mirrors the room on top of the view outside
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

	var pane := QuadMesh.new()
	pane.size = size
	pane.material = glass
	_add(pane, Vector3.ZERO)
	var shine := QuadMesh.new()          # glare streaks just in front of the glass
	shine.size = size
	var shine_material := ShaderMaterial.new()
	shine_material.shader = load("res://cultic/scripts/glass_shine.gdshader")
	shine.material = shine_material
	_add(shine, Vector3(0, 0, 0.004))
	if reflection_box != Vector3.ZERO:
		var probe := ReflectionProbe.new()   # captures the room once, for the glass to reflect
		probe.size = reflection_box
		probe.position = reflection_offset
		probe.box_projection = true
		probe.interior = true
		add_child(probe)
		probe.owner = self

	var half := size / 2.0
	# outer frame: top, bottom, left, right
	_bar(Vector2(size.x, frame_width), Vector2(0, half.y - frame_width / 2), wood)
	_bar(Vector2(size.x, frame_width), Vector2(0, -half.y + frame_width / 2), wood)
	_bar(Vector2(frame_width, size.y), Vector2(-half.x + frame_width / 2, 0), wood)
	_bar(Vector2(frame_width, size.y), Vector2(half.x - frame_width / 2, 0), wood)
	# even panes: the bars split the space inside the outer frame into equal parts
	var inner := size - Vector2(frame_width, frame_width) * 2.0
	for c in range(1, columns):
		var x := -inner.x / 2 + inner.x * c / columns
		_bar(Vector2(bar_width, inner.y), Vector2(x, 0), wood)
	for r in range(1, rows):
		var y := -inner.y / 2 + inner.y * r / rows
		_bar(Vector2(inner.x, bar_width), Vector2(0, y), wood)


func _bar(bar_size: Vector2, at: Vector2, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(bar_size.x, bar_size.y, bar_depth)
	box.material = material
	_add(box, Vector3(at.x, at.y, 0))


func _add(mesh: Mesh, at: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	add_child(part)
	part.owner = self   # clicking the glass or a bar in the editor then selects this node (it is still not saved)
