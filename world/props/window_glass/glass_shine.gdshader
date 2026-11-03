shader_type spatial;
// Glare on window glass (window_glass.tscn): a couple of soft diagonal streaks plus a brighter rim at grazing
// angles, added on top of whatever is behind. Cheap, and reads as "shiny" even in a dark room.
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec3 shine_color : source_color = vec3(0.75, 0.8, 0.9);
uniform float strength = 0.2;
uniform float angle = 0.9;          // tilt of the streaks
uniform float rim = 0.25;           // extra glare when looking along the glass

float streak(float x, float centre, float width) {
	return smoothstep(width, 0.0, abs(x - centre));
}

void fragment() {
	float d = UV.x + (1.0 - UV.y) * angle;   // runs across the diagonal
	float s = streak(d, 0.55, 0.12) * 0.8 + streak(d, 0.78, 0.05) + streak(d, 1.25, 0.08) * 0.5;
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	ALBEDO = shine_color * (s * strength + fresnel * rim);
}
