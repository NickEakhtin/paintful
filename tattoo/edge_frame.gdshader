shader_type canvas_item;
// A spirit-purple frame around the whole screen while the needle works past the stencil's edge: soft, pulsing a
// little (the purple specks rising off it are `EdgeMotes`). The session sets `strength` (0..1).

uniform float strength = 0.0;
uniform vec4 color : source_color = vec4(0.62, 0.18, 0.95, 1.0);
// How far in the frame reaches, as a share of the screen's shorter side.
uniform float width = 0.12;
// Overall boost of the frame's opacity.
uniform float boost = 1.7;
void fragment() {
	vec2 aspect = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
	float short_side = min(aspect.x, aspect.y);
	vec2 from_edge = min(UV, 1.0 - UV) * aspect / short_side;   // distance to the nearest edge, in short sides
	float d = min(from_edge.x, from_edge.y);
	if (d > width || strength <= 0.0) {
		discard;   // the middle of the screen: nothing to draw, no noise to sample
	}
	float frame = 1.0 - smoothstep(0.0, width, d);
	float pulse = 0.85 + 0.15 * sin(TIME * 18.0);
	float frame_alpha = clamp(color.a * pow(frame, 1.6) * pulse * boost, 0.0, 1.0);
	COLOR = vec4(color.rgb, frame_alpha * strength);
}
