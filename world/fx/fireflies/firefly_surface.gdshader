shader_type spatial;
render_mode blend_add, ambient_light_disabled;
uniform float point_pixels = 3.0;

void vertex() {
	POINT_SIZE = point_pixels;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = COLOR.a * (1.0 - smoothstep(0.55, 1.0, length(POINT_COORD * 2.0 - 1.0)));
}

void light() {
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR / PI;
}
