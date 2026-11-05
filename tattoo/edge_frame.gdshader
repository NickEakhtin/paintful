shader_type canvas_item;
// A red frame around the whole screen while the needle works past the stencil's edge: soft, thickest in the
// corners, pulsing a little. The session sets `strength` (0..1).

uniform float strength = 0.0;
uniform vec4 color : source_color = vec4(0.9, 0.05, 0.05, 1.0);
// How far in the frame reaches, as a share of the screen's shorter side.
uniform float width = 0.09;

void fragment() {
	vec2 aspect = vec2(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
	float short_side = min(aspect.x, aspect.y);
	vec2 from_edge = min(UV, 1.0 - UV) * aspect / short_side;   // distance to the nearest edge, in short sides
	float d = min(from_edge.x, from_edge.y);
	float frame = 1.0 - smoothstep(0.0, width, d);
	float pulse = 0.85 + 0.15 * sin(TIME * 18.0);
	COLOR = vec4(color.rgb, color.a * frame * frame * strength * pulse);
}
