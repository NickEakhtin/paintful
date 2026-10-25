shader_type canvas_item;
// Draws one stencil part: the faint transfer turns into ink where coverage grows.
// Edges come from the full-resolution part texture, so they stay crisp
// while the low-resolution coverage grid fills in softly.

uniform sampler2D coverage : filter_linear, repeat_disable, hint_default_black;
uniform vec4 stencil_color : source_color = vec4(0.55, 0.3, 0.75, 0.5);
uniform vec4 ink_color : source_color = vec4(0.08, 0.06, 0.12, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.72, 0.2, 1.0);
// 1 once the part is complete: covers soft coverage at the edges.
uniform float done = 0.0;
// White glow right after the part completes, fades 1 -> 0.
uniform float flash = 0.0;
// "Show what's left" ping, 0..1; only lights up cells without ink.
uniform float highlight = 0.0;

void fragment() {
	float shape = texture(TEXTURE, UV).a;
	float ink = max(texture(coverage, UV).r, done);
	vec4 color = mix(stencil_color, ink_color, smoothstep(0.0, 1.0, ink));
	color = mix(color, highlight_color, highlight * (1.0 - ink));
	color.rgb = mix(color.rgb, vec3(1.0), flash);
	COLOR = vec4(color.rgb, color.a * shape);
}
