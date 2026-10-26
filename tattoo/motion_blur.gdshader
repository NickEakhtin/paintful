shader_type canvas_item;
// Horizontal smear of whatever is on screen, for the quick turn to the side table.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 0 = sharp, 1 = full smear.
uniform float strength = 0.0;

void fragment() {
	float spread = strength * 0.05;
	vec4 sum = vec4(0.0);
	for (int i = -6; i <= 6; i++) {
		sum += texture(screen_texture, SCREEN_UV + vec2(float(i) / 6.0 * spread, 0.0));
	}
	COLOR = sum / 13.0;
}
