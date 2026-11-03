# Frames of hand-drawn rain (grey streaks on white) -> transparent PNGs for a frame-by-frame rain sheet:
# the white background becomes transparent, the streaks become pale rain-coloured with alpha from their darkness.
# Usage: Godot --headless --path . --script tools/props/make_rain_frames.gd -- out_dir in1.jpg in2.jpg ... [--gain=3]
extends SceneTree

const RAIN := Color(0.78, 0.84, 0.95)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var gain := 3.0
	var inputs: Array[String] = []
	for arg in a.slice(1):
		if arg.begins_with("--gain="):
			gain = float(arg.get_slice("=", 1))
		else:
			inputs.append(arg)
	DirAccess.make_dir_recursive_absolute(a[0])
	for i in inputs.size():
		var src := Image.load_from_file(inputs[i])
		src.convert(Image.FORMAT_RGB8)
		var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
		for y in src.get_height():
			for x in src.get_width():
				var alpha := clampf((1.0 - src.get_pixel(x, y).get_luminance()) * gain, 0.0, 1.0)
				out.set_pixel(x, y, Color(RAIN.r, RAIN.g, RAIN.b, alpha))
		var path := a[0].path_join("rain_%d.png" % (i + 1))
		out.save_png(path)
		print("rain frame -> ", path)
	quit()
