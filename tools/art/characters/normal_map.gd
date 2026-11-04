# Normal map for a cut-out character (transparent PNG), so a flat billboard catches light as if it had volume.
# Height = a rounded "pillow" (distance from the silhouette edge, eased) + fine relief from the drawing's shading
# (dark lines and folds sit lower). Normals come from the height slopes, OpenGL convention (green = up), as Godot wants.
# Usage: Godot --headless --path . --script tools/characters/normal_map.gd -- in.png out_normal.png [strength]
extends SceneTree

const PILLOW_PX := 60.0     # how far in from the edge the body keeps rounding
const PILLOW := 1.0         # weight of the rounded volume
const DETAIL := 0.35        # weight of the drawn shading / lines
const BLUR := 5             # smoothing passes on the height


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var strength := float(a[2]) if a.size() > 2 else 3.0
	var img := Image.load_from_file(a[0])
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width(); var h := img.get_height()
	var n := w * h

	# distance to the nearest transparent pixel (two-pass chamfer)
	var dist := PackedFloat32Array(); dist.resize(n)
	for i in n:
		dist[i] = 0.0 if img.get_pixel(i % w, i / w).a < 0.5 else 1e6
	for y in h:
		for x in w:
			var i := y * w + x
			if x > 0: dist[i] = minf(dist[i], dist[i - 1] + 1.0)
			if y > 0: dist[i] = minf(dist[i], dist[i - w] + 1.0)
			if x > 0 and y > 0: dist[i] = minf(dist[i], dist[i - w - 1] + 1.414)
			if x < w - 1 and y > 0: dist[i] = minf(dist[i], dist[i - w + 1] + 1.414)
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if x < w - 1: dist[i] = minf(dist[i], dist[i + 1] + 1.0)
			if y < h - 1: dist[i] = minf(dist[i], dist[i + w] + 1.0)
			if x < w - 1 and y < h - 1: dist[i] = minf(dist[i], dist[i + w + 1] + 1.414)
			if x > 0 and y < h - 1: dist[i] = minf(dist[i], dist[i + w - 1] + 1.414)

	var height := PackedFloat32Array(); height.resize(n)
	for i in n:
		var c := img.get_pixel(i % w, i / w)
		if c.a < 0.5:
			continue
		var t := minf(dist[i] / PILLOW_PX, 1.0)
		var pillow := sqrt(1.0 - (1.0 - t) * (1.0 - t))   # quarter circle: steep at the edge, flat inside
		height[i] = pillow * PILLOW + c.get_luminance() * DETAIL
	for _p in BLUR:
		var out := height.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var i := y * w + x
				out[i] = (height[i] * 4.0 + height[i - 1] + height[i + 1] + height[i - w] + height[i + w]) / 8.0
		height = out

	var normal := Image.create(w, h, false, Image.FORMAT_RGB8)
	var k := strength * 8.0
	for y in h:
		for x in w:
			var i := y * w + x
			var dx := (height[mini(i + 1, y * w + w - 1)] - height[maxi(i - 1, y * w)]) * 0.5
			var dy := (height[mini(i + w, n - 1 - (w - 1 - x))] - height[maxi(i - w, x)]) * 0.5   # image y goes down
			var nv := Vector3(-dx * k, dy * k, 1.0).normalized()
			normal.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
	normal.save_png(a[1])
	print("%s: %dx%d, strength %.1f" % [a[1], w, h, strength])
	quit()
