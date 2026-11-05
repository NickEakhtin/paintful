extends SceneTree
## Turns the hand reference (a grey sculpt render on a dark gradient, fingers up, back of the hand to us) into the
## client's hand sprite for the arm surface: cut from its background, flipped upside down (fingers down, the wrist
## on top, where the arm ends), tinted to skin, plus a normal map from its shading.
## Run: Godot --headless --path . --script res://tools/make_client_hand.gd
## Writes art/characters/client_hand/hand_albedo.png and hand_normal.png.

const SOURCE: String = "res://docs/art/client_hand_reference.jpg"
const OUT_DIR: String = "res://art/characters/client_hand/"
## How close (luminance) to its row's background colour a pixel must be to count as background.
const BACKGROUND_TOLERANCE: float = 0.07
## The skin tone the grey shading is tinted with (light and shadow).
const SKIN_LIGHT: Color = Color(0.93, 0.7, 0.58)
const SKIN_SHADOW: Color = Color(0.45, 0.26, 0.2)
## How strongly the shading's slopes bend the normals.
const NORMAL_STRENGTH: float = 3.0
## The cut is opened by this many px: anything thinner than twice it is dropped.
const OPEN: int = 4


func _init() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null or source.is_empty():
		push_error("can't read " + SOURCE)
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	var w: int = source.get_width()
	var h: int = source.get_height()
	var lum: PackedFloat32Array = PackedFloat32Array()
	lum.resize(w * h)
	for y in h:
		for x in w:
			lum[y * w + x] = source.get_pixel(x, y).get_luminance()
	# the background's luminance in each row, from the left and right edges (a vertical gradient)
	var row_background: PackedFloat32Array = PackedFloat32Array()
	row_background.resize(h)
	for y in h:
		var total: float = 0.0
		for x in 6:
			total += lum[y * w + x] + lum[y * w + w - 1 - x]
		row_background[y] = total / 12.0
	# flood fill the background from every border pixel that looks like it (the gaps between the fingers included)
	var background: PackedByteArray = PackedByteArray()
	background.resize(w * h)
	var stack: PackedInt32Array = PackedInt32Array()
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if background[i] == 1:
			continue
		var y: int = i / w
		if absf(lum[i] - row_background[y]) > BACKGROUND_TOLERANCE:
			continue
		background[i] = 1
		var x: int = i % w
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - w)
		if y < h - 1:
			stack.append(i + w)
	# clean the cut: thin slivers of background left along the wrist go (an opening: shrink the hand by OPEN px, keep
	# its biggest piece, grow it back inside the first cut)
	var hand: PackedByteArray = PackedByteArray()
	hand.resize(w * h)
	for i in w * h:
		hand[i] = 1 - background[i]
	var shrunk: PackedByteArray = _morph(hand, w, h, OPEN, true)
	var piece: PackedByteArray = _largest_piece(shrunk, w, h)
	var grown: PackedByteArray = _morph(piece, w, h, OPEN + 1, false)
	for i in w * h:
		background[i] = 0 if (grown[i] == 1 and hand[i] == 1) else 1
	# alpha, softened over a pixel at the cut
	var albedo: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var normal: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i: int = y * w + x
			var cover: float = 0.0
			var count: float = 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = clampi(x + dx, 0, w - 1)
					var ny: int = clampi(y + dy, 0, h - 1)
					cover += 0.0 if background[ny * w + nx] == 1 else 1.0
					count += 1.0
			var alpha: float = cover / count
			var shade: float = clampf((lum[i] - 0.2) / 0.7, 0.0, 1.0)
			var skin: Color = SKIN_SHADOW.lerp(SKIN_LIGHT, shade)
			# flipped upside down: fingers down
			albedo.set_pixel(x, h - 1 - y, Color(skin, alpha))
	# a height from the shading (smoothed), its slopes as normals; computed on the flipped picture
	var height: PackedFloat32Array = PackedFloat32Array()
	height.resize(w * h)
	for y in h:
		for x in w:
			var total: float = 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx: int = clampi(x + dx, 0, w - 1)
					var ny: int = clampi(y + dy, 0, h - 1)
					total += lum[(h - 1 - ny) * w + nx]
			height[y * w + x] = total / 25.0
	for y in h:
		for x in w:
			var left: float = height[y * w + maxi(x - 1, 0)]
			var right: float = height[y * w + mini(x + 1, w - 1)]
			var up: float = height[maxi(y - 1, 0) * w + x]
			var down: float = height[mini(y + 1, h - 1) * w + x]
			var n: Vector3 = Vector3((left - right) * NORMAL_STRENGTH, (down - up) * NORMAL_STRENGTH, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	albedo.save_png(ProjectSettings.globalize_path(OUT_DIR + "hand_albedo.png"))
	normal.save_png(ProjectSettings.globalize_path(OUT_DIR + "hand_normal.png"))
	print("hand sprite %dx%d written to %s" % [w, h, OUT_DIR])
	quit()


## Shrinks (`erode`) or grows a 0/1 mask by `radius` px (a square neighbourhood, done as two 1D passes).
static func _morph(mask: PackedByteArray, w: int, h: int, radius: int, erode: bool) -> PackedByteArray:
	var pass_x: PackedByteArray = PackedByteArray()
	pass_x.resize(w * h)
	for y in h:
		for x in w:
			var value: int = 1 if erode else 0
			for d in range(-radius, radius + 1):
				var m: int = mask[y * w + clampi(x + d, 0, w - 1)]
				if erode and m == 0:
					value = 0
					break
				if not erode and m == 1:
					value = 1
					break
			pass_x[y * w + x] = value
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var value: int = 1 if erode else 0
			for d in range(-radius, radius + 1):
				var m: int = pass_x[clampi(y + d, 0, h - 1) * w + x]
				if erode and m == 0:
					value = 0
					break
				if not erode and m == 1:
					value = 1
					break
			out[y * w + x] = value
	return out


## Only the biggest connected piece of a 0/1 mask.
static func _largest_piece(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var label: PackedInt32Array = PackedInt32Array()
	label.resize(w * h)
	var best_label: int = 0
	var best_size: int = 0
	var next: int = 0
	for start in w * h:
		if mask[start] == 0 or label[start] != 0:
			continue
		next += 1
		var size: int = 0
		var stack: PackedInt32Array = PackedInt32Array([start])
		label[start] = next
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			var x: int = i % w
			var y: int = i / w
			for n in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if n >= 0 and mask[n] == 1 and label[n] == 0:
					label[n] = next
					stack.append(n)
		if size > best_size:
			best_size = size
			best_label = next
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if label[i] == best_label else 0
	return out
