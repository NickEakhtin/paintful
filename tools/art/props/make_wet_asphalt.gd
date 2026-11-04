# Tileable wet asphalt textures for scripts/wet_asphalt.gdshader, made from noise only:
#   art/materials/wet_asphalt/albedo.png  dark worn asphalt: aggregate grit, lighter stones, cracked slabs, dirt in the dips
#   art/materials/wet_asphalt/height.png  0 = low (cracks, dips where the puddles collect) .. 1 = high
# Usage: Godot --headless --path . --script tools/props/make_wet_asphalt.gd -- [size_px] [seed]
extends SceneTree

const OUT := "res://art/materials/wet_asphalt/"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var px := int(a[0]) if a.size() > 0 else 1024
	var seed := int(a[1]) if a.size() > 1 else 7

	var basins := _seamless(px, _noise(seed, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2.5, 3))        # wide dips: puddles
	var swell := _seamless(px, _noise(seed + 1, FastNoiseLite.TYPE_SIMPLEX, 9.0, 3))            # medium unevenness
	var grit := _seamless(px, _noise(seed + 2, FastNoiseLite.TYPE_VALUE, 160.0, 2))             # aggregate
	var stones := _seamless(px, _noise(seed + 3, FastNoiseLite.TYPE_CELLULAR, 70.0, 1))         # lighter pebbles
	var slabs := _noise(seed + 4, FastNoiseLite.TYPE_CELLULAR, 3.2, 1)                          # cracked slabs
	slabs.domain_warp_enabled = true
	slabs.domain_warp_amplitude = 18.0
	slabs.domain_warp_frequency = 0.012
	slabs.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var edges := _seamless(px, slabs)
	slabs.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var slab_tone := _seamless(px, slabs)
	var hair := _noise(seed + 5, FastNoiseLite.TYPE_CELLULAR, 9.0, 1)                           # fine hairline cracks
	hair.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	hair.domain_warp_enabled = true
	hair.domain_warp_amplitude = 6.0
	var hairline := _seamless(px, hair)

	var height := Image.create(px, px, false, Image.FORMAT_L8)
	var albedo := Image.create(px, px, false, Image.FORMAT_RGB8)
	for y in px:
		for x in px:
			var b := basins.get_pixel(x, y).r
			var s := swell.get_pixel(x, y).r
			var g := grit.get_pixel(x, y).r
			var st := stones.get_pixel(x, y).r
			var tone := slab_tone.get_pixel(x, y).r
			var crack := 1.0 - smoothstep(0.0, 0.045, edges.get_pixel(x, y).r)
			var fine := (1.0 - smoothstep(0.0, 0.02, hairline.get_pixel(x, y).r)) * smoothstep(0.55, 0.75, s)
			var pebble := smoothstep(0.82, 0.9, st) * smoothstep(0.35, 0.7, g)
			var h := b * 0.62 + s * 0.16 + g * 0.1 + tone * 0.08 + pebble * 0.05 - crack * 0.3 - fine * 0.08
			height.set_pixel(x, y, Color(clampf(h, 0.0, 1.0), 0, 0))
			# colour: near-black brown, slabs a shade apart, grit and stones lighter, dirt settled low
			var c := Color(0.1, 0.088, 0.078).lerp(Color(0.19, 0.165, 0.145), tone * 0.45 + smoothstep(0.3, 0.8, g) * 0.75)
			c = c.lerp(Color(0.32, 0.29, 0.26), pebble * 0.85)
			c = c.lerp(Color(0.06, 0.047, 0.038), (1.0 - smoothstep(0.25, 0.5, b)) * 0.6)    # dirt in the dips
			c = c.lerp(Color(0.015, 0.012, 0.01), maxf(crack, fine * 0.7))
			albedo.set_pixel(x, y, c)
	height.save_png(ProjectSettings.globalize_path(OUT + "height.png"))
	albedo.save_png(ProjectSettings.globalize_path(OUT + "albedo.png"))
	print("wet asphalt textures: %dpx, seed %d -> %s" % [px, seed, OUT])
	quit()


func _noise(seed: int, type: FastNoiseLite.NoiseType, repeats: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = type
	n.frequency = repeats / 1024.0
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	return n


func _seamless(px: int, n: FastNoiseLite) -> Image:
	n.frequency *= 1024.0 / px
	var img := n.get_seamless_image(px, px, false, false, 0.1, true)
	img.convert(Image.FORMAT_RF)
	return img
