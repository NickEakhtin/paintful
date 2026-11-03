shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, depth_draw_never, shadows_disabled;

stencil_mode read, compare_not_equal, 1;

uniform vec4 outline_color : source_color = vec4(1.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 outward = (PROJECTION_MATRIX * vec4(MODELVIEW_NORMAL_MATRIX * NORMAL, 0.0)).xy * VIEWPORT_SIZE;
	clip.xy += outward / max(length(outward), 0.0001) * (3.6 / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}
void fragment() { ALBEDO = outline_color.rgb; ALPHA = 1.0; }
