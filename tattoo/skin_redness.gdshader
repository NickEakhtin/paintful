shader_type canvas_item;
// Redness over the skin where the needle has worked too long in one place.
// Heat comes from a coarse grid (SkinHeat), blurred here into soft blotches,
// and is cut to the rounded skin panel.

uniform sampler2D heat : filter_linear, repeat_disable, hint_default_black;
uniform float pink_from = 0.25;
uniform float warn_heat = 0.5;
uniform float danger_heat = 0.8;
uniform vec4 pink_color : source_color = vec4(1.0, 0.5, 0.5, 1.0);
uniform vec4 red_color : source_color = vec4(0.92, 0.1, 0.08, 1.0);
uniform vec4 deep_color : source_color = vec4(0.5, 0.0, 0.06, 1.0);
uniform float max_alpha = 0.75;
// Throb of the red spots, 0..1; the session drives it.
uniform float pulse = 0.0;
// The skin panel: size and corner radius in pixels.
uniform vec2 size = vec2(760.0, 680.0);
uniform float corner_radius = 280.0;

// Centre plus two rings of eight taps: the grid's blocky circles become soft blotches.
float blurred_heat(vec2 uv) {
	vec2 texel = 1.0 / vec2(textureSize(heat, 0));
	float sum = texture(heat, uv).r * 6.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * TAU / 8.0 + 0.4;
		vec2 direction = vec2(cos(angle), sin(angle)) * texel;
		sum += texture(heat, uv + direction * 1.2).r * 2.0;
		sum += texture(heat, uv + direction * 2.6).r;
	}
	return sum / 30.0;
}

float inside_skin(vec2 uv) {
	vec2 p = (uv - 0.5) * size;
	vec2 q = abs(p) - (size * 0.5 - corner_radius);
	float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
	return clamp(0.5 - distance, 0.0, 1.0);
}

void fragment() {
	float h = blurred_heat(UV);
	float red = smoothstep(pink_from, warn_heat, h);
	vec3 color = mix(pink_color.rgb, red_color.rgb, red);
	color = mix(color, deep_color.rgb, smoothstep(danger_heat - 0.1, 1.0, h));
	float alpha = smoothstep(pink_from * 0.5, warn_heat, h) * max_alpha;
	// Red spots throb: brighter and more opaque on the beat.
	float throb = pulse * smoothstep(warn_heat - 0.1, warn_heat, h);
	color = mix(color, vec3(1.0, 0.25, 0.2), throb * 0.35);
	alpha = min(1.0, alpha + throb * 0.2);
	COLOR = vec4(color, alpha * inside_skin(UV));
}
