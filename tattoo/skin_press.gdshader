shader_type canvas_item;
// The skin under the working needle: the picture is pulled in toward the tip like a small dent,
// lit from the same lamp as the wet ink (up and to the left), with a pink halo around it.
// The whole skin also trembles by `shake` pixels while the machine buzzes.
// Reads the screen (a BackBufferCopy right before it), so it bends skin, stencil, ink and redness,
// but nothing drawn after it (tasks, machine). Cut to the rounded skin panel.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Needle tip in this rect's pixels.
uniform vec2 tip = vec2(0.0);
// How hard the needle presses, 0..1; the session eases it in and out.
uniform float press = 0.0;
// Picture offset this frame, in pixels.
uniform vec2 shake = vec2(0.0);
uniform float radius = 18.0;
// Farthest the picture moves toward the tip, in pixels (halfway out the dent).
uniform float depth = 2.1;
// Light and shade on the dent's walls.
uniform float shade = 0.14;
uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.45, 0.28);
// Halo size relative to `radius`.
uniform float tint_spread = 1.4;
// The skin panel: size and corner radius in pixels.
uniform vec2 size = vec2(760.0, 680.0);
uniform float corner_radius = 280.0;

float inside_skin(vec2 uv) {
	vec2 p = (uv - 0.5) * size;
	vec2 q = abs(p) - (size * 0.5 - corner_radius);
	float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
	return clamp(0.5 - distance, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * size;
	vec2 offset = p - tip;
	float r = length(offset) / radius;
	vec2 out_dir = r > 0.0001 ? normalize(offset) : vec2(0.0);

	// Sample farther out than we draw: what's around the tip looks pulled into the dent.
	float pull = r < 1.0 ? 4.0 * r * (1.0 - r) : 0.0;
	vec2 source = p + out_dir * depth * pull * press - shake;
	vec3 color = texture(screen_texture, SCREEN_UV + (source - p) * SCREEN_PIXEL_SIZE).rgb;

	// Walls of the dent: the one facing the lamp is lighter, the other darker.
	float wall = r < 1.0 ? r * (1.0 - r * r) / 0.385 : 0.0;
	vec2 to_light = normalize(vec2(-0.5, -0.7));
	color *= 1.0 + shade * wall * dot(-out_dir, to_light) * press;

	float halo = exp(-pow(r / (0.7 * tint_spread), 2.0)) * tint.a * press;
	color = mix(color, tint.rgb, halo);
	COLOR = vec4(color, inside_skin(UV));
}
