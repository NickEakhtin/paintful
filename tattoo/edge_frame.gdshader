shader_type canvas_item;
// A spirit-purple frame around the whole screen while the needle works past the stencil's edge: soft, pulsing a
// little, with smoke curling off it toward the middle. The session sets `strength` (0..1).

uniform float strength = 0.0;
uniform vec4 color : source_color = vec4(0.62, 0.18, 0.95, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.75, 0.5, 1.0, 1.0);
// How far in the frame reaches, as a share of the screen's shorter side.
uniform float width = 0.12;
// Overall boost of the frame's opacity.
uniform float boost = 1.7;
// How far in the smoke drifts (share of the short side), how fast, how thick, how fine its wisps are.
uniform float smoke_reach = 0.3;
uniform float smoke_speed = 0.12;
uniform float smoke_amount = 1.0;
uniform float smoke_scale = 7.0;

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

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += noise(p) * amplitude;
		p = p * 2.03 + vec2(1.7, 9.2);
		amplitude *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 aspect = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
	float short_side = min(aspect.x, aspect.y);
	vec2 from_edge = min(UV, 1.0 - UV) * aspect / short_side;   // distance to the nearest edge, in short sides
	float d = min(from_edge.x, from_edge.y);
	if (d > max(smoke_reach, width) || strength <= 0.0) {
		discard;   // the middle of the screen: nothing to draw, no noise to sample
	}
	float frame = 1.0 - smoothstep(0.0, width, d);
	float pulse = 0.85 + 0.15 * sin(TIME * 18.0);
	// smoke from each side on its own (no seams in the corners): wisps drifting inward and swaying sideways,
	// thinning with the distance from that side
	vec2 pos = UV * aspect / short_side;
	vec2 far_edge = (1.0 - UV) * aspect / short_side;
	vec4 sides = vec4(pos.x, far_edge.x, pos.y, far_edge.y);   // left, right, top, bottom
	vec4 runs = vec4(pos.y, pos.y + 31.0, pos.x + 57.0, pos.x + 83.0);
	float smoke = 0.0;
	for (int i = 0; i < 4; i++) {
		if (sides[i] < smoke_reach) {
			float sway = sin(TIME * 0.7 + runs[i] * 3.0) * 0.04;
			vec2 q = vec2(runs[i] + sway, sides[i] - TIME * smoke_speed) * smoke_scale;
			float wisps = smoothstep(0.42, 0.8, fbm(q * vec2(1.0, 0.6)));
			smoke = max(smoke, wisps * (1.0 - smoothstep(0.0, smoke_reach, sides[i])));
		}
	}
	smoke *= smoke_amount;
	float frame_alpha = clamp(color.a * pow(frame, 1.6) * pulse * boost, 0.0, 1.0);
	float smoke_alpha = clamp(smoke, 0.0, 1.0) * (1.0 - frame_alpha);
	float alpha = (frame_alpha + smoke_alpha) * strength;
	vec3 rgb = (color.rgb * frame_alpha + smoke_color.rgb * smoke_alpha) / max(frame_alpha + smoke_alpha, 1e-4);
	COLOR = vec4(rgb, clamp(alpha, 0.0, 1.0));
}
