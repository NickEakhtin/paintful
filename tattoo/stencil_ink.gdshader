shader_type canvas_item;
// Draws one stencil part: the faint transfer turns into ink where coverage grows.
// Edges come from the full-resolution part texture and the ink's shape from `paint` (InkPaint: the same stamps
// drawn at the screen's resolution), so strokes stay crisp on any monitor; the low-resolution logic grid
// (`coverage`) only masks it, so ink shows only where the logic laid some.
// Fresh ink is wet: deep black with a glossy sheen (a window reflection plus a bright rim
// where it beads at the edges); over `dry_time` it dries to flat, slightly grey matte.

uniform sampler2D coverage : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D paint : filter_linear, repeat_disable, hint_default_black;
// One texel of `paint`, in UV.
uniform float paint_texel = 0.00390625;
// How dark the first touch of the needle shows: ink appears with a crisp edge at once and darkens with every
// pass until the spot is full (the logic still counts only full ink).
uniform float first_pass = 0.35;
// When each cell last took ink, in the same clock as `now` (InkCanvas.inked_at_texture).
uniform sampler2D inked_at : filter_linear, repeat_disable, hint_default_black;
uniform float now = 0.0;
uniform float dry_time = 6.0;
uniform vec4 stencil_color : source_color = vec4(0.55, 0.3, 0.75, 0.5);
// Dried ink.
uniform vec4 ink_color : source_color = vec4(0.11, 0.1, 0.14, 1.0);
uniform vec4 wet_ink_color : source_color = vec4(0.02, 0.015, 0.04, 1.0);
uniform vec4 gloss_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float gloss_strength = 1.0;
// How much the ink surface bulges at its edges and ripples, for the highlights.
uniform float bump = 0.9;
// Wet ink stands this much above dry ink, so a fresh stroke over old ink shows a glossy rim.
uniform float wet_height = 0.6;
uniform vec4 highlight_color : source_color = vec4(1.0, 0.72, 0.2, 1.0);
// 1 once the part is complete: covers soft coverage at the edges.
uniform float done = 0.0;
// Glow right after the part completes (white) or loses its ink, fades 1 -> 0.
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
// "Show what's left" ping, 0..1; only lights up cells without ink.
uniform float highlight = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Ink at `uv`: the screen-resolution dabs, where the logic grid has any ink at all.
float ink_amount(vec2 uv) {
	float gate = smoothstep(0.0, 0.01, texture(coverage, uv).r);   // wider than the stroke: never cuts its rim
	float laid = texture(paint, uv).r;
	float presence = smoothstep(0.0, 0.015, laid);                   // the dab's rim: a pixel wide
	return max(presence * mix(first_pass, 1.0, smoothstep(0.0, 1.0, min(laid, 1.0))) * gate, done);
}

// Ink times the part's shape at `uv`; `shape` is the part texture's alpha there
// (TEXTURE can't be passed into a function in canvas shaders).
float wetness(vec2 uv) {
	return 1.0 - smoothstep(0.0, dry_time, now - texture(inked_at, uv).r);
}

// Height of the ink surface: wet ink sits on top of dry ink as its own layer.
float ink_at(float shape, vec2 uv) {
	return ink_amount(uv) * shape * (1.0 + wet_height * wetness(uv));
}

void fragment() {
	float shape = texture(TEXTURE, UV).a;
	float ink = ink_amount(UV);
	float wet = wetness(UV) * smoothstep(0.3, 1.0, ink);

	// Surface: ink beads up where it ends, plus a slow ripple of the liquid.
	float step_uv = 1.5 * paint_texel;
	vec2 dx = vec2(step_uv, 0.0);
	vec2 dy = vec2(0.0, step_uv);
	vec2 slope = vec2(ink_at(texture(TEXTURE, UV + dx).a, UV + dx) - ink_at(texture(TEXTURE, UV - dx).a, UV - dx),
			ink_at(texture(TEXTURE, UV + dy).a, UV + dy) - ink_at(texture(TEXTURE, UV - dy).a, UV - dy));
	vec2 ripple = vec2(noise(UV * 14.0 + now * 0.07), noise(UV * 14.0 + 17.0 - now * 0.05)) - 0.5;
	vec3 normal = normalize(vec3(-(slope + ripple * 0.12) * bump, 1.0));

	// Bright pin highlight from a lamp up and to the left.
	vec3 to_light = normalize(vec3(-0.5, -0.7, 1.0));
	vec3 half_way = normalize(to_light + vec3(0.0, 0.0, 1.0));
	float specular = pow(max(dot(normal, half_way), 0.0), 160.0) * 1.5;
	// The studio window reflected in the wet ink: two soft diagonal bands that the surface bends.
	vec2 mirror = SCREEN_UV + normal.xy * 0.12;
	float across = dot(mirror, vec2(0.7071, 0.7071));
	float window = smoothstep(0.52, 0.56, across) * (1.0 - smoothstep(0.62, 0.66, across))
			+ 0.6 * smoothstep(0.69, 0.71, across) * (1.0 - smoothstep(0.73, 0.75, across));
	float sheen = (specular + window * 0.4) * wet * gloss_strength;

	// Dry ink is flat and a little grainy; wet ink is deeper.
	vec3 dry = ink_color.rgb * (0.9 + 0.2 * noise(UV * 180.0));
	vec3 inked = mix(dry, wet_ink_color.rgb, wet) + gloss_color.rgb * sheen;

	vec4 color = mix(stencil_color, vec4(inked, ink_color.a), ink);
	color = mix(color, highlight_color, highlight * (1.0 - ink));
	color.rgb = mix(color.rgb, flash_color.rgb, flash);
	COLOR = vec4(color.rgb, color.a * shape);
}
