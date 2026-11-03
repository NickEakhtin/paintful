shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, shadows_disabled;
uniform bool circular = false;
void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	float edge = circular ? length(p) : max(p.x, p.y);
	if (edge > 1.0 || 1.0 - edge > 1.8 * fwidth(edge)) { discard; }
	ALBEDO = vec3(1.0);
}
