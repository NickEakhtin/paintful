shader_type canvas_item;
// The skin under the working needle: the picture is pulled in toward the tip like a small dent shaped like the
// brush (an ellipse `radius` long along `axis`, `thickness` of that across, turning with it),
// lit from the same lamp as the wet ink (up and to the right), with a pink halo around it.
// The whole skin also trembles by `shake` pixels while the machine buzzes.
// Reads the screen (a BackBufferCopy right before it), so it bends skin, stencil, ink and redness,
// but nothing drawn after it (tasks, machine). Cut to the rounded skin panel.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Needle tip in this rect's layout pixels (all lengths here are layout pixels, not screen pixels).
uniform vec2 tip = vec2(0.0);
// How hard the needle presses, 0..1; the session eases it in and out.
uniform float press = 0.0;
// Picture offset this frame, in pixels.
uniform vec2 shake = vec2(0.0);
uniform float radius = 18.0;
// The brush's direction on screen (unit) and its half thickness as a share of `radius` (1: a round dent).
uniform vec2 axis = vec2(1.0, 0.0);
uniform float thickness = 1.0;
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
	// a screen pixel of soft edge on any monitor (`size` is in layout pixels, 2-3 screen pixels on 1440p/4K)
	return clamp(0.5 - distance / max(fwidth(distance), 1e-4), 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * size;
	vec2 offset = p - tip;
	// in the brush's ellipse: x along it, y across, 1 on its rim
	vec2 across_dir = vec2(-axis.y, axis.x);
	float thick = max(thickness, 0.05);
	vec2 local = vec2(dot(offset, axis), dot(offset, across_dir)) / (radius * vec2(1.0, thick));
	float r = length(local);
	vec2 local_dir = r > 0.0001 ? local / r : vec2(0.0);
	// outward in the ellipse, back on the skin: the pull keeps the brush's shape (shorter across it)
	vec2 out_vec = axis * local_dir.x + across_dir * local_dir.y * thick;
	// the ellipse's normal, for the light on its walls
	vec2 normal = axis * local_dir.x * thick + across_dir * local_dir.y;
	vec2 out_dir = length(normal) > 0.0001 ? normalize(normal) : vec2(0.0);

	// Sample farther out than we draw: what's around the tip looks pulled into the dent.
	float pull = r < 1.0 ? 4.0 * r * (1.0 - r) : 0.0;
	vec2 source = p + out_vec * depth * pull * press - shake;
	// `size`, `tip`, `shake` are layout pixels (the 1280x720 base), the screen is real pixels (x2 on 1440p, x3 on 4K):
	// step through this rect's UV, so the dent is the same on every monitor
	vec2 uv_to_screen = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	vec3 color = texture(screen_texture, SCREEN_UV + (source - p) / size * uv_to_screen).rgb;

	// Walls of the dent: the one facing the lamp is lighter, the other darker.
	float wall = r < 1.0 ? r * (1.0 - r * r) / 0.385 : 0.0;
	vec2 to_light = normalize(vec2(0.5, -0.7));
	color *= 1.0 + shade * wall * dot(-out_dir, to_light) * press;

	float halo = exp(-pow(r / (0.7 * tint_spread), 2.0)) * tint.a * press;
	color = mix(color, tint.rgb, halo);
	COLOR = vec4(color, inside_skin(UV));
}
