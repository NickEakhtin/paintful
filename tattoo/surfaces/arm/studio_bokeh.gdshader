shader_type canvas_item;
// A dark studio far out of focus behind the arm: a warm gradient and a few soft, slowly breathing lights.

uniform vec4 top_color : source_color = vec4(0.16, 0.13, 0.12, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.05, 0.045, 0.05, 1.0);
uniform vec2 size = vec2(1280.0, 720.0);

float blob(vec2 p, vec2 center, float radius) {
	return 1.0 - smoothstep(radius * 0.55, radius, length(p - center));
}

void fragment() {
	vec2 p = UV * size;
	vec3 color = mix(top_color.rgb, bottom_color.rgb, UV.y);
	// Lights in the background, placed by fractions of the screen so they stay put on any aspect.
	float t = TIME * 0.2;
	color += vec3(0.55, 0.42, 0.25) * 0.10 * blob(p, size * vec2(0.08, 0.22), 120.0 + 6.0 * sin(t));
	color += vec3(0.75, 0.62, 0.35) * 0.18 * blob(p, size * vec2(0.92, 0.78), 90.0);
	color += vec3(0.85, 0.8, 0.7) * 0.10 * blob(p, size * vec2(0.86, 0.12), 60.0 + 4.0 * sin(t * 1.3));
	color += vec3(0.4, 0.35, 0.5) * 0.08 * blob(p, size * vec2(0.18, 0.75), 150.0);
	color += vec3(0.6, 0.5, 0.3) * 0.06 * blob(p, size * vec2(0.62, 0.05), 80.0);
	COLOR = vec4(color, 1.0);
}
