shader_type spatial;
render_mode blend_add, ambient_light_disabled, fog_disabled;

uniform float particle_size = 3.0;

void vertex() {
	float depth = max(0.8, -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z);
	POINT_SIZE = clamp(8.0 * (particle_size / 3.0) / depth, 1.5, 4.0 * (particle_size / 3.0));
}

void fragment() {
	float radius = length(POINT_COORD * 2.0 - 1.0);
	ALBEDO = COLOR.rgb * 0.85;
	ALPHA = (1.0 - smoothstep(0.18, 1.0, radius)) * COLOR.a * 0.78;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO / PI;
}
