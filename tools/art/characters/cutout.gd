# Cuts a character drawn on a plain white background out into a transparent PNG for a billboard (Sprite3D).
# The background is flood-filled from the border; closed white holes (between an arm and the body) bigger than
# HOLE_PX are removed too, small white details (cuffs, collar) stay. The edge is softened and the image cropped.
# Usage: Godot --headless --path . --script tools/characters/cutout.gd -- in.png out.png [white_threshold]
extends SceneTree

const HOLE_PX := 600
const PAD := 4


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var threshold := float(a[2]) if a.size() > 2 else 0.9
	var img := Image.load_from_file(a[0])
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width(); var h := img.get_height()
	var white := PackedByteArray(); white.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			white[y * w + x] = 1 if minf(c.r, minf(c.g, c.b)) > threshold and c.s < 0.12 else 0
	# label the white regions; those touching the border or large enough are background
	var bg := PackedByteArray(); bg.resize(w * h)
	var seen := PackedByteArray(); seen.resize(w * h)
	for start in w * h:
		if not white[start] or seen[start]:
			continue
		var region := PackedInt32Array(); var stack := PackedInt32Array([start]); seen[start] = 1
		var border := false
		while not stack.is_empty():
			var i := stack[stack.size() - 1]; stack.resize(stack.size() - 1)
			region.append(i)
			var x := i % w; var y := i / w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				border = true
			for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if n >= 0 and white[n] and not seen[n]:
					seen[n] = 1; stack.append(n)
		if border or region.size() > HOLE_PX:
			for i in region:
				bg[i] = 1
	# alpha: background 0; a pixel next to the background fades with its whiteness (soft, no white halo)
	var lo := Vector2i(w, h); var hi := Vector2i(-1, -1)
	for y in h:
		for x in w:
			var i := y * w + x
			var c := img.get_pixel(x, y)
			if bg[i]:
				c.a = 0.0
			else:
				var edge := (x > 0 and bg[i - 1]) or (x < w - 1 and bg[i + 1]) or (y > 0 and bg[i - w]) or (y < h - 1 and bg[i + w])
				if edge:
					var lum := minf(c.r, minf(c.g, c.b))
					c.a = clampf((1.0 - lum) / (1.0 - 0.55), 0.0, 1.0)
					if c.a > 0.0:   # un-blend the white so the edge keeps the line colour
						c = Color((c.r - (1.0 - c.a)) / c.a, (c.g - (1.0 - c.a)) / c.a, (c.b - (1.0 - c.a)) / c.a, c.a).clamp()
				lo = lo.min(Vector2i(x, y)); hi = hi.max(Vector2i(x, y))
			img.set_pixel(x, y, c)
	var rect := Rect2i(lo - Vector2i(PAD, PAD), hi - lo + Vector2i(PAD, PAD) * 2 + Vector2i.ONE).intersection(Rect2i(0, 0, w, h))
	var out := img.get_region(rect)
	out.save_png(a[1])
	print("%s: %dx%d, figure from y %d to %d" % [a[1], out.get_width(), out.get_height(), lo.y, hi.y])
	quit()
