shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled, shadows_disabled;

uniform float particle_size = 3.0;

void vertex() {
	float depth = max(0.8, -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z);
	POINT_SIZE = clamp(8.0 * (particle_size / 3.0) / depth, 1.5, 4.0 * (particle_size / 3.0));
}

void fragment() {
	float radius = length(POINT_COORD * 2.0 - 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = (1.0 - smoothstep(0.18, 1.0, radius)) * COLOR.a;
}
