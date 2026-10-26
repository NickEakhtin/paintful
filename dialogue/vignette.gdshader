shader_type canvas_item;
// Darkens the screen edges with a violet tint while the spirit speaks.

uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(0.08, 0.0, 0.12, 1.0);

void fragment() {
	float edge = smoothstep(0.35, 0.85, distance(UV, vec2(0.5)) * 1.3);
	COLOR = vec4(tint.rgb, edge * strength * 0.85);
}
