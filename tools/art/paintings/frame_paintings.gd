# Paintings for the picture frames (models/frame_*.glb). Each frame model's through-opening is traced from its mesh
# (front view, flood fill from the centre), so the sheets and canvases match the real arch / oval / rectangle.
# Usage: Godot --headless --path . --script res://tools/art/paintings/frame_paintings.gd
#   art/paintings/templates/<size>_<W>x<H>cm.png  blank sheet to paint on, one per frame size: white = visible,
#                                                 light grey rim = bleed hidden behind the frame, grey = cut away
#   art/paintings/canvas/<size>.png               what the frames show: art/paintings/<size>.png (your painting,
#                                                 any size, cropped to fill) cut to the frame's shape, or plain white
# The canvas quads in world/studio/studio.tscn are sized from the numbers this prints ("quad").
extends SceneTree

# frame size name -> [model, scale of the frame instances in the scene (x, y)]
const SIZES := {
	"arched": ["frame_arched", Vector2(1.2, 1.2)],
	"oval": ["frame_oval", Vector2(1.2, 1.2)],
	"square_small": ["frame_square", Vector2(0.448, 0.448)],
	"square_medium": ["frame_square", Vector2(0.64, 0.64)],
	"square_large": ["frame_square", Vector2(1.296, 1.28)],
	"square_xl": ["frame_square", Vector2(1.685, 1.664)],
}
const MARGIN := 0.04        # quad = opening grown by this share of its size on each side
const BLEED := 0.012        # metres (model space) the painting reaches under the frame past the visible edge
const TRACE_CELLS := 500    # tracing grid, longest side
const TEMPLATE_PX := 1600
const CANVAS_PX := 1024
const OUT := "res://art/paintings/"

var _traced := {}           # model -> {"quad": Rect2, "hole": Rect2, "mask": Image (L8: 255 visible, 160 bleed, 0 out)}


func _initialize() -> void:
	for size_name in SIZES:
		var model: String = SIZES[size_name][0]
		var scale: Vector2 = SIZES[size_name][1]
		var t: Dictionary = _trace(model)
		var quad: Rect2 = t.quad
		var aspect := quad.size.x * scale.x / (quad.size.y * scale.y)
		var visible_cm := (t.hole as Rect2).size * scale * 100.0
		var template_name := "%s_%dx%dcm.png" % [size_name, roundi(visible_cm.x), roundi(visible_cm.y)]
		_save(_template(t.mask, _px(TEMPLATE_PX, aspect)), "templates/" + template_name)
		_save(_canvas(t.mask, _px(CANVAS_PX, aspect), size_name), "canvas/%s.png" % size_name)
		print("%s: %s, visible %dx%d cm, quad centre (%.4f, %.4f) size (%.4f, %.4f)" % [size_name, template_name,
				roundi(visible_cm.x), roundi(visible_cm.y), quad.get_center().x, quad.get_center().y, quad.size.x, quad.size.y])
	quit()


func _px(longest: int, aspect: float) -> Vector2i:
	return Vector2i(longest, roundi(longest / aspect)) if aspect >= 1.0 else Vector2i(roundi(longest * aspect), longest)


func _trace(model: String) -> Dictionary:
	if _traced.has(model):
		return _traced[model]
	var inst: Node3D = load("res://art/models/_shared/%s.glb" % model).instantiate()
	var tris := PackedVector2Array()
	var bounds := Rect2(); var first := true
	for m: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()                               # mesh -> model space (the scene is not in the tree here)
		var n: Node = m
		while n != inst:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				var p := xf * verts[i]
				tris.append(Vector2(p.x, p.y))
				bounds = Rect2(Vector2(p.x, p.y), Vector2.ZERO) if first else bounds.expand(Vector2(p.x, p.y))
				first = false
	inst.free()

	# 1) coarse pass over the whole frame to find the opening
	var hole: Rect2 = _flood(tris, bounds, 300).rect
	# 2) fine pass over the opening plus margin
	var quad: Rect2 = hole.grow_individual(hole.size.x * MARGIN, hole.size.y * MARGIN, hole.size.x * MARGIN, hole.size.y * MARGIN)
	var fine: Dictionary = _flood(tris, quad, TRACE_CELLS)
	var w: int = fine.w; var h: int = fine.h
	var inside: PackedByteArray = fine.inside
	var reach := ceili(BLEED / fine.cell)
	var mask := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			var v := 0
			if inside[y * w + x]:
				v = 255
			else:
				for dy in range(-reach, reach + 1):           # within BLEED of the opening: bleed
					var yy := y + dy
					if yy < 0 or yy >= h:
						continue
					var dx := int(sqrt(reach * reach - dy * dy))
					for xx in range(maxi(0, x - dx), mini(w, x + dx + 1)):
						if inside[yy * w + xx]:
							v = 160
							break
					if v:
						break
			mask.set_pixel(x, h - 1 - y, Color8(v, v, v))   # image rows go down, model y goes up
	_traced[model] = {"quad": quad, "hole": fine.rect, "mask": mask}
	return _traced[model]


## Rasterises the frame's triangles over `area` and flood-fills the empty space from its centre.
func _flood(tris: PackedVector2Array, area: Rect2, cells: int) -> Dictionary:
	var cell := maxf(area.size.x, area.size.y) / cells
	var w := ceili(area.size.x / cell); var h := ceili(area.size.y / cell)
	var solid := PackedByteArray(); solid.resize(w * h)
	for t in range(0, tris.size(), 3):
		var a := tris[t]; var b := tris[t + 1]; var c := tris[t + 2]
		var lo := ((a.min(b).min(c) - area.position) / cell).floor()
		var hi := ((a.max(b).max(c) - area.position) / cell).ceil()
		for gy in range(maxi(0, int(lo.y)), mini(h, int(hi.y) + 1)):
			for gx in range(maxi(0, int(lo.x)), mini(w, int(hi.x) + 1)):
				if Geometry2D.point_is_inside_triangle(area.position + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * cell, a, b, c):
					solid[gy * w + gx] = 1
	var inside := PackedByteArray(); inside.resize(w * h)
	var stack := PackedInt32Array([(h / 2) * w + w / 2])
	var lo := Vector2i(w, h); var hi := Vector2i(-1, -1)
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if inside[i] or solid[i]:
			continue
		inside[i] = 1
		var x := i % w; var y := i / w
		lo = lo.min(Vector2i(x, y)); hi = hi.max(Vector2i(x, y))
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	var rect := Rect2(area.position + Vector2(lo) * cell, Vector2(hi - lo + Vector2i.ONE) * cell)
	return {"rect": rect, "inside": inside, "w": w, "h": h, "cell": cell}


func _scaled(mask: Image, size: Vector2i) -> Image:
	var m := mask.duplicate() as Image
	m.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
	return m


func _template(mask: Image, size: Vector2i) -> Image:
	var m := _scaled(mask, size)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y in size.y:
		for x in size.x:
			var v := m.get_pixel(x, y).r8
			var c := Color8(150, 150, 150)                     # cut away
			if v > 222: c = Color.WHITE                        # visible
			elif v > 192: c = Color8(40, 40, 40)               # outline of the visible edge
			elif v > 80: c = Color8(222, 222, 222)             # bleed: hidden behind the frame
			img.set_pixel(x, y, c)
	return img


func _canvas(mask: Image, size: Vector2i, size_name: String) -> Image:
	var m := _scaled(mask, size)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var painting_path := ProjectSettings.globalize_path(OUT + size_name + ".png")
	if FileAccess.file_exists(painting_path):
		var p := Image.load_from_file(painting_path)
		p.convert(Image.FORMAT_RGBA8)
		var k := maxf(float(size.x) / p.get_width(), float(size.y) / p.get_height())   # cover, then crop the middle
		p.resize(maxi(size.x, roundi(p.get_width() * k)), maxi(size.y, roundi(p.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		img.blit_rect(p, Rect2i((p.get_size() - size) / 2, size), Vector2i.ZERO)
		print("  painting used: ", painting_path)
	for y in size.y:
		for x in size.x:
			var c := img.get_pixel(x, y)
			c.a = 1.0 if m.get_pixel(x, y).r8 > 80 else 0.0
			img.set_pixel(x, y, c)
	return img


func _save(img: Image, rel: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(OUT + rel))
	if err != OK:
		push_error("could not save %s: %s" % [rel, err])
