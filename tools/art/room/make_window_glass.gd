# Bakes scripts/window_panes.gd into a plain scene, scenes/window_glass.tscn: glass plus frame bars as real nodes, so
# in the editor a click on any part selects the whole window instance.
# Usage: Godot --headless --path . --script tools/room/make_window_glass.gd -- [width height columns rows]
extends SceneTree


var window: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	window = Node3D.new()
	window.name = "WindowGlass"
	window.set_script(load("res://cultic/scripts/window_panes.gd"))
	if args.size() == 4:
		window.size = Vector2(float(args[0]), float(args[1]))
		window.columns = int(args[2])
		window.rows = int(args[3])
	get_root().add_child(window)   # _ready builds the parts, owned by the window


func _process(_delta: float) -> bool:
	var parts := window.get_children()
	var bars := 0
	for part in parts:
		if part is ReflectionProbe:
			part.name = "RoomReflection"
		elif part.mesh is QuadMesh:
			part.name = "Shine" if part.mesh.material is ShaderMaterial else "Glass"
		else:
			bars += 1
			part.name = "Bar%d" % bars
	window.set_script(null)
	var scene := PackedScene.new()
	scene.pack(window)
	print("saved: ", ResourceSaver.save(scene, "res://world/props/window_glass/window_glass.tscn"), ", parts: ", parts.size())
	return true
