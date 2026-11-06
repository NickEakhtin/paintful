shader_type canvas_item;
// A wet paper towel (the stack, the towel in the hand, the crumpled ball): pale paper with fibres and an embossed
// dot pattern, soaked a little greyer in blotches (white, no blue), with glints of water, a darker soaked rim, and blood
// soaking in from a few spots as `stained` (0..1) grows. UV 0..1 over the sheet; COLOR tints it (alpha kept).

uniform float stained = 0.0;
// How soaked it is overall (0 dry .. 1 dripping).
uniform float wet = 0.85;
// Moves the blotches, so sheets of one stack don't look alike.
uniform vec2 seed = vec2(0.0);
uniform vec3 paper : source_color = vec3(0.95, 0.95, 0.94);
uniform vec3 soaked : source_color = vec3(0.78, 0.78, 0.77);
uniform vec3 blood : source_color = vec3(0.45, 0.03, 0.06);
// The emboss pattern's cells across the sheet.
uniform float emboss_cells = 11.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return 0.55 * noise(p) + 0.3 * noise(p * 2.1 + 3.7) + 0.15 * noise(p * 4.3 + 8.1);
}

void fragment() {
	vec2 uv = UV;
	// the water: blotches, more of them the wetter, darker toward the soaked rim
	float rim = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float blotch = fbm(uv * 3.2 + seed);
	float soak = clamp(wet * (0.45 + 0.9 * smoothstep(0.35, 0.7, blotch)) + 0.35 * (1.0 - smoothstep(0.0, 0.08, rim)), 0.0, 1.0);
	vec3 colour = mix(paper, soaked, soak * 0.8);
	// fibres: thin streaks both ways
	float fibres = noise(uv * vec2(70.0, 190.0) + seed) * 0.5 + noise(uv * vec2(190.0, 70.0) - seed) * 0.5;
	colour *= 0.93 + 0.1 * fibres;
	// the embossed dots, fainter where it's soaked flat
	vec2 cell = fract(uv * emboss_cells + vec2(0.5 * floor(uv.y * emboss_cells), 0.0)) - 0.5;
	float dot_mark = smoothstep(0.24, 0.12, length(cell));
	colour *= 1.0 - 0.07 * dot_mark * (1.0 - 0.6 * soak);
	// blood soaking in from a few spots, spreading as it takes more
	float spread = fbm(uv * 2.4 + seed * 1.7 + 11.0);
	float red = smoothstep(1.0 - stained * 0.85, 1.0 - stained * 0.85 + 0.12, spread) * step(0.001, stained);
	colour = mix(colour, blood * (0.75 + 0.35 * fibres), red * 0.9);
	// a few soft glints of water on the soaked blotches
	float glint = smoothstep(0.82, 0.97, fbm(uv * 9.0 + seed * 3.0)) * soak;
	colour += vec3(0.55) * glint;
	// a slightly darker edge so the sheet reads against the skin
	colour *= 0.82 + 0.18 * smoothstep(0.0, 0.025, rim);
	COLOR = vec4(colour * COLOR.rgb, COLOR.a);
}
