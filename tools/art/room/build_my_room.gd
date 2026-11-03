# Generates scenes/CULTIC_ROOM_MAIN_SCENE.tscn step by step: a tattoo parlour assembled from the project's models at real-world scale.
# Models are real-size (Scale 1); only wall / floor modules get stretched to fit the room. Re-running overwrites scenes/CULTIC_ROOM_MAIN_SCENE.tscn.
# Usage: Godot --headless --script tools/room/build_my_room.gd -- [step]
#        (1 floor, 2 walls, 3 ceiling, 4 furniture, 5 lights, 6 decor; default = all)
extends SceneTree

const W := 10.32; const D := 5.0; const H := 3.2   # interior: x -5.16..5.16, z 0.15..5.15 (north wall = door/window wall at z=0)
const XL := -W / 2; const XR := W / 2; const ZN := 0.15; const ZS := 0.15 + D
const T := 0.3                                     # wall thickness
const M := "res://art/models/"
# North wall openings (from tools/pipeline/door_window_wall.py): door x -3.43..-2.23, window x 0.23..3.69

var res := {}                                      # path -> id
var nodes: Array[String] = []
var placed := {}                                   # node path -> Transform3D, to put lights at world positions

func xf(yaw := 0.0, scale := Vector3.ONE, pos := Vector3.ZERO, flip_x := false) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	if flip_x: b = b * Basis(Vector3.RIGHT, PI)
	return Transform3D(b * Basis.from_scale(scale), pos)

func num(a: float) -> String:                      # like Python's %.5g
	if absf(a) < 1e-6: return "0"
	var s := String.num(a, maxi(0, 4 - int(floor(log(absf(a)) / log(10.0)))))
	return s.trim_suffix(".0")

func tf(t: Transform3D) -> String:
	var b := t.basis
	var v := [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z]
	return "Transform3D(" + ", ".join(v.map(num)) + ")"

func ext(path: String) -> String:
	if not res.has(path): res[path] = "%d_%s" % [res.size() + 1, path.get_file().get_basename()]
	return res[path]

func inst(parent: String, name: String, path: String, pos: Vector3, yaw := 0.0, s = 1.0, flip_x := false) -> void:
	var t := xf(yaw, s if s is Vector3 else Vector3.ONE * s, pos, flip_x)
	placed[parent + "/" + name] = t
	nodes.append('[node name="%s" parent="%s" instance=ExtResource("%s")]\ntransform = %s\n' % [name, parent, ext(path), tf(t)])

func light(owner: String, name: String, local: Vector3, energy: float, rng: float, color := Color(1, 0.66, 0.32), shadow := false) -> void:
	# Light at a point given in the owner model's own (unscaled) coordinates; lights live unscaled under Lights.
	var p: Vector3 = placed[owner] * local
	nodes.append('[node name="%s" type="OmniLight3D" parent="Lights"]\ntransform = %s\nlight_color = Color(%s, %s, %s, 1)\nlight_energy = %s\n%somni_range = %s\nomni_attenuation = 1.4\n'
		% [name, tf(Transform3D(Basis(), p)), num(color.r), num(color.g), num(color.b), num(energy), "shadow_enabled = true\n" if shadow else "", num(rng)])

func look_at_xf(eye: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - eye), eye)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var step := int(args[0]) if args.size() > 0 else 99
	nodes.append('[node name="MyRoom" type="Node3D"]\n')
	nodes.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")\n')
	nodes.append('[node name="Sun" type="DirectionalLight3D" parent="."]\ntransform = %s\nlight_energy = 0.8\nshadow_enabled = true\n'
		% tf(look_at_xf(Vector3(1.5, 8, -6), Vector3(1.5, 8, -6) + Vector3(-4, -9, 14.5))))
	nodes.append('[node name="Camera3D" type="Camera3D" parent="."]\ntransform = %s\nfov = 70.0\ncurrent = true\n'
		% tf(look_at_xf(Vector3(4.3, 1.8, 4.7), Vector3(-1.6, 0.9, 1.4))))

	# --- step 1: floor -----------------------------------------------------------------------------------------
	nodes.append('[node name="Shell" type="Node3D" parent="."]\n')
	var nx := 8; var nz := 4
	var tile := Vector3(W / nx / 1.292, 0.07 / 0.0952, D / nz / 1.292)
	for i in nx:
		for j in nz:
			inst("Shell", "Floor_%d_%d" % [i, j], M + "floor_tile.glb", Vector3(XL + W * (i + 0.5) / nx, -0.07, ZN + D * (j + 0.5) / nz), 0, tile)

	# --- step 2: walls -----------------------------------------------------------------------------------------
	if step >= 2:
		inst("Shell", "NorthWall", M + "wall_door_window.glb", Vector3.ZERO)
		var side_len := D + 2 * T                      # side walls also close the corners
		for i in 2:                                    # west: bare brick; modules overlap a little to hide their ragged ends
			inst("Shell", "WestWall%d" % (i + 1), M + "brick_wall.glb", Vector3(XL - T / 2 + (0.01 if i else 0.0), 0, -T + side_len * (i + 0.5) / 2), 90,
				Vector3(side_len / 2 / 4.39 * 1.06, H / 3.2, T / 0.3))
		for i in 2:                                    # east: wallpaper + wainscot (0.95 m, as on the door wall)
			inst("Shell", "EastWall%d" % (i + 1), M + "wall_wallpaper.glb", Vector3(XR + T / 2, 0, -T + side_len * (i + 0.5) / 2), -90,
				Vector3(side_len / 2 / 4.38, H / 3.2, T / 0.2))
			inst("Shell", "EastWainscot%d" % (i + 1), M + "wall_panel.glb", Vector3(XR, 0, ZN + D * (i + 0.5) / 2), -90, Vector3(D / 2 / 2.1, 0.953 / 0.954, 1.0))
		var south_len := W + 2 * T
		for i in 3:                                    # south: wallpaper + wainscot
			inst("Shell", "SouthWall%d" % (i + 1), M + "wall_wallpaper.glb", Vector3(-south_len / 2 + south_len * (i + 0.5) / 3, 0, ZS + T / 2), 180,
				Vector3(south_len / 3 / 4.38, H / 3.2, T / 0.2))
		for i in 4:
			inst("Shell", "SouthWainscot%d" % (i + 1), M + "wall_panel.glb", Vector3(XL + W * (i + 0.5) / 4, 0, ZS), 180, Vector3(W / 4 / 2.1, 0.953 / 0.954, 1.0))

	# --- step 3: ceiling ---------------------------------------------------------------------------------------
	if step >= 3:
		for i in nx:
			for j in nz:
				inst("Shell", "Ceiling_%d_%d" % [i, j], M + "floor_tile.glb", Vector3(XL + W * (i + 0.5) / nx, H + 0.07, ZN + D * (j + 0.5) / nz), 0, tile, true)

	# --- step 4: furniture -------------------------------------------------------------------------------------
	var F := "Furniture"
	if step >= 4:
		nodes.append('[node name="Furniture" type="Node3D" parent="."]\n')
		# waiting corner (west half, by the south wall)
		inst(F, "Rug", M + "rug.glb", Vector3(-2.6, 0.005, 3.6))
		inst(F, "Sofa", M + "sofa.glb", Vector3(-2.6, 0, ZS - 0.5), 180)        # back against the wainscot
		inst(F, "CoffeeTable", M + "coffee_table.glb", Vector3(-2.6, 0, 3.6))
		inst(F, "Armchair", M + "armchair.glb", Vector3(-4.4, 0, 3.6), 90)
		inst(F, "CoatRack", M + "coat_rack.glb", Vector3(-4.5, 0, 0.7))          # left of the door
		# work zone (east half, in the window light)
		inst(F, "TattooChair", M + "recliner.glb", Vector3(2.4, 0, 2.6), -90)
		inst(F, "Cabinet", "res://world/props/cabinet/cabinet.tscn", Vector3(XR - 0.1, 0, 3.6), -90)   # in front of the wainscot
		inst(F, "Plant", M + "plant.glb", Vector3(4.55, 0, 0.85), -30)

	# --- step 5: lamps and lights ------------------------------------------------------------------------------
	if step >= 5:
		nodes.append('[node name="Lights" type="Node3D" parent="."]\n')
		inst(F, "FloorLamp", M + "lamp.glb", Vector3(1.4, 0, 2.0))               # artist's lamp at the chair head
		light(F + "/FloorLamp", "FloorLamp", Vector3(0, 1.51, 0), 1.4, 4.5, Color(1, 0.66, 0.32), true)
		inst(F, "TableLamp", M + "table_lamp.glb", Vector3(XR - 0.37, 2.0, 3.6), -90)
		light(F + "/TableLamp", "TableLamp", Vector3(0, 0.42, 0), 0.8, 3.5, Color(1, 0.5, 0.35))
		inst(F, "Chandelier", M + "chandelier.glb", Vector3(-0.4, H, 2.65))
		var lanterns := [Vector3(0.435, -0.603, 0.023), Vector3(-0.068, -0.607, 0.443), Vector3(-0.43, -0.601, -0.004), Vector3(0.066, -0.607, -0.449)]
		for i in lanterns.size():
			light(F + "/Chandelier", "Chandelier%d" % (i + 1), lanterns[i], 1.3, 5.5, Color(1, 0.66, 0.32), i == 0)
		nodes.append('[node name="Decor" type="Node3D" parent="."]\n')
		inst("Decor", "WallLamp", M + "wall_lamp.glb", Vector3(XL + 0.17, 1.6, 3.6), 90)   # brick wall, above the armchair
		light("Decor/WallLamp", "WallLamp", Vector3(0, 0.206, 0.078), 1.6, 5.0, Color(1, 0.66, 0.32), true)

	# --- step 6: table top and wall decor ----------------------------------------------------------------------
	if step >= 6:
		var top := 0.384                               # coffee table top height
		inst(F, "CandleTall", M + "candle_tall.glb", Vector3(-2.98, top, 3.48))
		inst(F, "CandleBig", M + "candle_big.glb", Vector3(-2.75, top, 3.72))
		inst(F, "CandleSmall", M + "candle_small.glb", Vector3(-3.05, top, 3.76))
		light(F + "/CandleBig", "Candles", Vector3(0, 0.18, 0), 0.6, 2.5, Color(1, 0.6, 0.3))
		inst(F, "Book", M + "book.glb", Vector3(-2.3, top, 3.72), 20)
		inst(F, "Mug", M + "coffee_mug.glb", Vector3(-2.28, top, 3.42), 150)
		inst("Decor", "FrameArched", M + "frame_arched.glb", Vector3(-3.1, 1.35, ZS), 180)  # gallery above the sofa
		inst("Decor", "FrameOval", M + "frame_oval.glb", Vector3(-2.1, 1.4, ZS), 180)
		inst("Decor", "FrameSquare", M + "frame_square.glb", Vector3(XR, 1.3, 1.9), -90)   # beside the tattoo chair
		inst("Decor", "TattooSign", M + "tattoo_sign.glb", Vector3(XL + 0.13, 1.3, 1.5), 0)  # brick wall, seen from the door

	var head: Array[String] = ["[gd_scene load_steps=%d format=3]\n" % (res.size() + 4)]
	for path in res:
		head.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % [path, res[path]])
	head.append("""
[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 2
ambient_light_color = Color(0.45, 0.38, 0.5, 1)
ambient_light_energy = 0.35
tonemap_mode = 2
glow_enabled = true
glow_intensity = 0.9
glow_bloom = 0.05
glow_hdr_threshold = 0.9
ssr_enabled = true
ssr_max_steps = 96
ssao_enabled = true
""")
	var out := ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../scenes/CULTIC_ROOM_MAIN_SCENE.tscn").simplify_path()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(head) + "\n" + "\n".join(nodes))
	f.close()
	print("step %d nodes %d resources %d -> %s" % [mini(step, 6), nodes.size(), res.size(), out])
	quit()
