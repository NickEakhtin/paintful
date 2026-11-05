shader_type canvas_item;
// Out of focus toward the wrist and over the client's hand: blurs what's drawn under it (the arm's 3D view and the
// background) by a radius growing down the screen, from nothing at `from_y` to `max_radius` at `full_y` and on,
// and darkens smoothly from `from_y` down to `dark_y` (`darken` at the bottom and on). ArmSurface sets the rows every
// frame from the scroll.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Screen rows in the window's own pixels: where the blur starts and where it's full.
uniform float from_y = 100000.0;
uniform float full_y = 100001.0;
uniform float max_radius = 26.0;
uniform float darken = 0.6;
uniform float dark_y = 100002.0;

void fragment() {
	float amount = smoothstep(from_y, full_y, FRAGCOORD.y);
	float shade = darken * smoothstep(from_y, dark_y, FRAGCOORD.y);
	if (amount <= 0.001 && shade <= 0.001) {
		discard;   // above the wrist: nothing to do
	}
	float radius = max_radius * amount;
	float lod = log2(max(radius * 0.5, 1.0));
	vec3 colour = vec3(0.0);
	// a disc of taps at a blurrier mip, all alike: soft and even
	for (int i = 0; i < 12; i++) {
		float r = sqrt((float(i) + 0.5) / 12.0);
		float a = float(i) * 2.39996;
		vec2 offset = vec2(cos(a), sin(a)) * r * radius * SCREEN_PIXEL_SIZE;
		colour += textureLod(screen_tex, SCREEN_UV + offset, lod).rgb;
	}
	colour /= 12.0;
	colour *= 1.0 - shade;
	COLOR = vec4(colour, 1.0);
}
