# Dark stained planks (albedo) for simple wooden props built from boxes, in the palette of the room's models.
# Planks run along the texture's V axis; iron nails near both ends. Make the normal map with
# tools/characters/normal_map.gd afterwards.
# Usage: Godot --headless --path . --script tools/props/make_plank_texture.gd -- out.png [planks] [size_px]
extends SceneTree

const DARK := Color(0.11, 0.065, 0.04)
const MID := Color(0.2, 0.12, 0.07)
const LIGHT := Color(0.3, 0.19, 0.11)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var planks := int(a[1]) if a.size() > 1 else 4
	var px := int(a[2]) if a.size() > 2 else 512
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.02
	grain.fractal_octaves = 4
	var blotch := FastNoiseLite.new()
	blotch.frequency = 0.008
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var w := float(px) / planks
	for y in px:
		for x in px:
			var p := int(x / w)                       # which plank
			var u := fmod(x, w) / w                   # across the plank, 0..1
			grain.seed = p * 17 + 3
			# grain: noise stretched along the plank, with growth rings bending around
			var g := grain.get_noise_2d(x * 6.0, y * 0.35 + p * 400.0)
			var rings := 0.5 + 0.5 * sin((u * 9.0 + g * 3.0) * PI)
			var c := MID.lerp(LIGHT, rings * 0.55 + g * 0.25).lerp(DARK, clampf(0.35 - blotch.get_noise_2d(x, y + p * 300) * 0.8, 0.0, 0.6))
			c = c * (0.85 + 0.15 * float(p % 2))      # neighbouring planks differ a little
			var edge := minf(u, 1.0 - u) * w          # px to the seam
			if edge < 2.5:
				c = c.lerp(Color(0.03, 0.02, 0.015), 1.0 - edge / 2.5)
			for ny in [px * 0.08, px * 0.92]:         # two nails at each end of the plank
				for nx in [w * 0.28, w * 0.72]:
					var d := Vector2(fmod(x, w) - nx, y - ny).length()
					if d < 5.0:
						c = Color(0.07, 0.07, 0.075).lerp(Color(0.22, 0.2, 0.18), clampf(1.0 - d / 5.0, 0.0, 1.0) * 0.6)
			img.set_pixel(x, y, c.clamp())
	img.save_png(a[0])
	print("%s: %d planks, %dpx" % [a[0], planks, px])
	quit()
