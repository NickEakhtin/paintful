shader_type canvas_item;
// Grimy low-fi look over the whole game screen (scenes/retro_post.tscn): chunky pixels, few colours with ordered
// dithering, film grain, a dark vignette and a hair of colour fringing. Only shows in the game, not in the 3D editor.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float pixel_size = 4.0;                          // screen pixels per game pixel
uniform float color_levels = 6.0;                        // shades per colour channel
uniform float dither_strength : hint_range(0.0, 1.0) = 0.85;
uniform float contrast = 1.15;
uniform float saturation = 0.85;
uniform float grain : hint_range(0.0, 0.3) = 0.09;
uniform float vignette : hint_range(0.0, 2.0) = 0.9;
uniform float fringe = 0.6;                              // colour fringing towards the edges, in game pixels
// lifts the dark tones before the colours are cut down: with only `color_levels` shades the near-black of a dim room
// otherwise all lands on black, and the dithering shows only on the few lit spots. 1 = off, lower = brighter shadows
uniform float shadow_gamma : hint_range(0.3, 1.0) = 1.0;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(FRAGCOORD.xy / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size / res;
	vec2 from_center = uv - 0.5;
	vec2 shift = from_center * fringe * pixel_size / res * 2.0;
	vec3 col = vec3(texture(screen, uv + shift).r, texture(screen, uv).g, texture(screen, uv - shift).b);

	col = pow(max(col, vec3(0.0)), vec3(shadow_gamma));
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col += (rand(cell + fract(TIME * 7.0) * 100.0) - 0.5) * grain;   // grain changes every frame, per game pixel
	col *= 1.0 - dot(from_center, from_center) * vignette;

	int bx = int(mod(cell.x, 4.0));
	int by = int(mod(cell.y, 4.0));
	float threshold = (BAYER[by * 4 + bx] + 0.5) / 16.0 - 0.5;
	col = floor(clamp(col, 0.0, 1.0) * (color_levels - 1.0) + 0.5 + threshold * dither_strength) / (color_levels - 1.0);
	COLOR = vec4(col, 1.0);
}
