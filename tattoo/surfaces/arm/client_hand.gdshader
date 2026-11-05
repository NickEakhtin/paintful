shader_type spatial;
// The client's hand below the wrist: a flat picture (art/characters/client_hand/, made by tools/make_client_hand.gd)
// on a quad behind the arm's front, lit through its normal map, with the arm's own skin lines on it. It's out of
// focus, the more so toward the wrist; its top dissolves in the arm's grain the other way round, so where the arm
// fades out the hand fades in.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear, repeat_disable;
// The arm's skin lines (the same noise textures), tiled every `detail_tile` px of the quad.
uniform sampler2D skin_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_tile = 160.0;
uniform float detail_strength = 0.1;
uniform float normal_strength = 0.8;
// The quad's size in px (for the skin lines and the blur).
uniform vec2 quad_size = vec2(920.0, 1226.0);
// Out of focus: blur radius in px at the wrist (top) and at the fingertips, easing over `blur_span` of the height.
uniform float blur_near = 18.0;
uniform float blur_far = 5.0;
uniform float blur_span = 0.65;
// The top `top_fade` px dissolve in, against the arm dissolving out there.
uniform float top_fade = 300.0;
// The picture's tone against the arm's (it has no blotches or shadow mix): below 1 darkens it.
uniform float brightness = 0.86;

const int TAPS = 16;

float grain(vec2 frag) {
	return fract(52.9829189 * fract(dot(floor(frag), vec2(0.06711056, 0.00583715))));
}

void fragment() {
	float radius = mix(blur_near, blur_far, smoothstep(0.0, blur_span, UV.y));
	vec2 texel = radius / quad_size;
	vec4 colour = vec4(0.0);
	vec3 bent = vec3(0.0);
	// a disc of taps (a golden-angle spiral), all weighted alike: a soft out-of-focus blur
	for (int i = 0; i < TAPS; i++) {
		float r = sqrt((float(i) + 0.5) / float(TAPS));
		float a = float(i) * 2.39996;
		vec2 offset = vec2(cos(a), sin(a)) * r * texel;
		colour += texture(albedo_tex, UV + offset);
		bent += texture(normal_tex, UV + offset).rgb;
	}
	colour /= float(TAPS);
	bent /= float(TAPS);
	// the soft edge and the top's fade-in, as dropped pixels (no transparency, like the arm)
	float fade_in = smoothstep(0.0, top_fade / quad_size.y, UV.y);
	if (colour.a * fade_in < 1.0 - grain(FRAGCOORD.xy)) {
		discard;
	}
	vec3 skin = colour.rgb / max(colour.a, 0.001);
	// the skin's fine lines, fading where it's blurrier
	vec2 detail_uv = UV * quad_size / detail_tile;
	float sharp = 1.0 - smoothstep(4.0, 16.0, radius);
	float lines = 1.0 - texture(skin_detail, detail_uv).r;
	skin *= 1.0 - detail_strength * lines * sharp;
	ALBEDO = skin * brightness;
	ROUGHNESS = 0.62;
	SPECULAR = 0.3;
	vec3 fine = texture(skin_normal, detail_uv).rgb;
	NORMAL_MAP = normalize(mix(bent, fine, 0.25 * sharp));
	NORMAL_MAP_DEPTH = normal_strength;
	RIM = 0.2;
	RIM_TINT = 0.7;
}
