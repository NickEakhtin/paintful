// Wet asphalt with puddles, for any mesh (wet_asphalt_box.tscn is a ready ground block).
// The texture is laid in world space, so a mesh can be moved and stretched without the asphalt stretching.
// Puddles fill the low parts of the height map (art/materials/wet_asphalt/height.png) on upward faces:
// glassy, dark, with rain rings when `rain_time` runs (set by wet_asphalt_box.gd in the game only,
// so the editor does not redraw nonstop). Made by tools/props/make_wet_asphalt.gd.
// The projection is worked out here, not with the material's triplanar option: that one crashed the 4.7.2 editor.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile_size = 3.0;                                // metres one copy of the texture covers
uniform float puddles : hint_range(0.0, 1.0) = 0.36;         // water level: how much of the ground is under water
uniform float puddle_edge : hint_range(0.005, 0.2) = 0.035;  // how soft the shore is
uniform float wetness : hint_range(0.0, 1.0) = 0.85;         // the dry parts: 0 = dusty, 1 = soaked and glossy
uniform vec3 puddle_tint : source_color = vec3(0.025, 0.022, 0.02);
uniform float bump : hint_range(0.0, 3.0) = 1.0;
uniform float rain_time = 0.0;
uniform float ripple_density = 2.2;                           // drop rings per metre
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.6;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// slope of the rain rings at p (in drop cells), one drop per cell, each on its own beat
vec2 ripple_slope(vec2 p) {
	vec2 cell = floor(p);
	vec2 slope = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 r = hash2(c);
			float t = fract(rain_time * (0.6 + r.x * 0.5) + r.y);
			vec2 d = p - (c + r);
			float dist = length(d);
			float front = t * 1.1;                                   // ring radius, in cells
			float ring = sin((dist - front) * 42.0) * smoothstep(0.12, 0.0, abs(dist - front)) * (1.0 - t);
			slope += d / max(dist, 1e-4) * ring;
		}
	}
	return slope;
}

void fragment() {
	vec3 n = normalize(world_normal);
	// planar projection by the face's main axis; t/b = world directions of the texture's u/v
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, 1.0);
	vec2 uv = world_pos.xz;
	if (abs(n.y) < 0.5) {
		b = vec3(0.0, 1.0, 0.0);
		if (abs(n.x) > abs(n.z)) {
			t = vec3(0.0, 0.0, 1.0);
			uv = world_pos.zy;
		} else {
			uv = world_pos.xy;
		}
	}
	uv /= tile_size;

	float h = texture(height_tex, uv).r;
	vec2 texel = 1.0 / vec2(textureSize(height_tex, 0));
	vec2 slope = vec2(
		texture(height_tex, uv + vec2(texel.x, 0.0)).r - texture(height_tex, uv - vec2(texel.x, 0.0)).r,
		texture(height_tex, uv + vec2(0.0, texel.y)).r - texture(height_tex, uv - vec2(0.0, texel.y)).r);
	slope *= bump * 9.0;

	float up = smoothstep(0.6, 0.95, n.y);
	float water = (1.0 - smoothstep(puddles - puddle_edge, puddles, h)) * up;

	vec3 albedo = texture(albedo_tex, uv).rgb * mix(1.0, 0.55, wetness);   // wet things look darker
	albedo = mix(albedo, puddle_tint, water * 0.9);

	slope *= 1.0 - water;                                                  // the water surface is flat...
	if (water > 0.01 && ripple_strength > 0.0) {                           // ...apart from the rain rings
		slope += ripple_slope(world_pos.xz * ripple_density) * ripple_strength * 0.35 * water;
	}
	vec3 wn = normalize(n - t * slope.x - b * slope.y);

	ALBEDO = albedo;
	// grit stays a little rougher than the smooth tops; soaked asphalt is glossy, puddles are glass
	float dry_rough = mix(0.9, 0.5, wetness) + (1.0 - h) * 0.15;
	ROUGHNESS = mix(dry_rough, 0.02, water);
	SPECULAR = mix(0.5, 0.6, water);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
