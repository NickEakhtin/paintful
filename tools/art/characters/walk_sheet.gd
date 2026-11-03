# Cuts a walk-cycle sheet (black silhouettes on white, `cols` x `rows` cells) into aligned transparent frames:
# alpha from how dark a pixel is (and its own alpha, if the sheet already has one), colour a flat near-black, every frame on the same canvas with the umbrella tip
# (the topmost point) on one vertical line and the feet (the lowest point) on one baseline, so the figure does not
# jump between frames. Picks frames by index (row-major), in the order given.
# Usage: Godot --headless --path . --script tools/characters/walk_sheet.gd -- sheet.png out_dir cols rows 0,1,2,...
extends SceneTree

const INK := Color(0.07, 0.07, 0.08)   # silhouette colour (lit in the game, so not pure black)
const PAD := 4


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var sheet := Image.load_from_file(a[0])
	sheet.convert(Image.FORMAT_RGBA8)
	var cols := int(a[2]); var rows := int(a[3])
	var cw := sheet.get_width() / cols; var ch := sheet.get_height() / rows
	var picks := Array(a[4].split(",")).map(func(s): return int(s))
	var cells := []
	for idx in picks:
		var cell := sheet.get_region(Rect2i((idx % cols) * cw, (idx / cols) * ch, cw, ch))
		var top := Vector2i(-1, -1); var bottom := -1; var left := cw; var right := -1
		for y in ch:
			for x in cw:
				var c := cell.get_pixel(x, y)
				var alpha := clampf((0.85 - c.get_luminance()) / 0.5, 0.0, 1.0) * c.a   # white or transparent = background
				cell.set_pixel(x, y, Color(INK.r, INK.g, INK.b, alpha))
				if alpha > 0.5:
					if top.y < 0: top = Vector2i(x, y)
					bottom = y; left = mini(left, x); right = maxi(right, x)
		cells.append({"img": cell, "tip": top.x, "top": top.y, "bottom": bottom, "left": left, "right": right})
	# common canvas: widest reach left/right of the tip, tallest reach above the feet
	var l := 0; var r := 0; var up := 0
	for c in cells:
		l = maxi(l, c.tip - c.left); r = maxi(r, c.right - c.tip); up = maxi(up, c.bottom - c.top)
	var w := l + r + 1 + PAD * 2; var h := up + 1 + PAD * 2
	DirAccess.make_dir_recursive_absolute(a[1])
	for i in cells.size():
		var c: Dictionary = cells[i]
		var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var src := Rect2i(c.left, c.top, c.right - c.left + 1, c.bottom - c.top + 1)
		out.blit_rect(c.img, src, Vector2i(PAD + l - (c.tip - c.left), PAD + up - (c.bottom - c.top)))
		out.save_png("%s/frame_%d.png" % [a[1], i])
	print("%d frames, %dx%d" % [cells.size(), w, h])
	quit()
