shader_type canvas_item;
// The spirit's flame on top of the tattoo machine. Its base sits at (0.5, BASE) in the rect.
// `size` shrinks it toward the base; at 0 only the coal shows (`coal` = how bright it glows).

uniform float size : hint_range(0.0, 1.0) = 1.0;
// 1 = healthy yellow-white core, 0 = dying, deep red.
uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float coal : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_speed = 5.0;
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.65, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.4, 0.06, 1.0);
uniform vec4 dying_color : source_color = vec4(0.75, 0.08, 0.04, 1.0);

const float BASE = 0.88;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// x -1..1 across the rect, y 0 at the base and 1 at the top of the rect.
	vec2 p = vec2((UV.x - 0.5) * 2.0, (BASE - UV.y) / BASE);
	float t = TIME * flicker_speed;

	vec4 flame = vec4(0.0);
	if (size > 0.01) {
		float y = p.y / size;
		float sway = (noise(vec2(p.y * 3.0 - t, 1.7)) - 0.5) * 0.45 * clamp(y, 0.0, 1.0);
		float x = (p.x + sway * size) / size;
		// Teardrop: a round bulb near the base narrowing to a tip.
		float width = 0.5 * pow(clamp(1.0 - y, 0.0, 1.0), 0.75) * smoothstep(-0.25, 0.25, y);
		float d = abs(x) / max(width, 0.001);
		float lick = noise(vec2(x * 4.0, y * 5.0 - t * 1.6));
		float shape = (1.0 - smoothstep(0.7, 1.0, d)) * (1.0 - smoothstep(0.6, 1.0, y + (lick - 0.5) * 0.4));
		float core = (1.0 - smoothstep(0.0, 0.65, d)) * clamp(1.0 - y * 1.3, 0.0, 1.0);
		vec3 edge = mix(dying_color.rgb, edge_color.rgb, heat);
		vec3 color = mix(edge, core_color.rgb, core * mix(0.3, 1.0, heat));
		// A soft glow around it.
		float glow = exp(-length(vec2(p.x, p.y - 0.3 * size) / size) * 3.5) * 0.35;
		flame = vec4(color, max(shape, glow * (1.0 - shape)));
	}

	// The coal at the base: dull red, flaring orange as it's about to catch.
	float coal_shape = 1.0 - smoothstep(0.05, 0.16, length(vec2(p.x, p.y * 1.6)));
	float pulse = 0.85 + 0.15 * noise(vec2(t * 0.7, 3.1));
	vec3 coal_color = mix(dying_color.rgb * 0.6, edge_color.rgb, coal);
	float coal_alpha = coal_shape * coal * pulse * step(0.001, coal);

	vec3 rgb = mix(coal_color, flame.rgb, flame.a);
	COLOR = vec4(rgb, max(flame.a, coal_alpha));
}
