shader_type spatial;
// The forearm skin. The mesh is a flat grid whose UV are skin coordinates; the vertex shader puts every
// vertex on the arm (a tapered cylinder) or on the pulled skin flap, with the same formulas as ArmShape
// (keep them in sync). World units are screen pixels: x right, y up, z toward the orthographic camera.
// The stencil and ink come from the ink layer, a 2D viewport drawn in the same skin coordinates.
render_mode cull_disabled;

uniform float radius = 210.0;
uniform float taper_top = 1.1;
uniform float taper_bottom = 0.84;
uniform float arm_length = 1000.0;
// The mesh runs this many times `arm_length`, so a pull dragging the skin up or down never shows its ends.
const float MESH_REACH = 1.8;
uniform float grip_angle = 2.007;
uniform float max_pull = 220.0;
uniform float hold_depth = 0.25;
uniform float grip_bulge = 0.35;
uniform float bulge_spread = 300.0;
uniform float grip_v = 0.0;
uniform float pull_side = 0.0;
uniform float pull_amount = 0.0;
uniform float pull_shear = 0.0;

// The ink layer covers theta -wrap..wrap and v -stencil_height/2..stencil_height/2.
uniform sampler2D ink_layer : source_color, filter_linear, repeat_disable;
uniform float wrap_angle = 2.094;
uniform float stencil_height = 700.0;

uniform vec4 skin_color : source_color = vec4(0.74, 0.5, 0.38, 1.0);
uniform vec4 skin_shadow_color : source_color = vec4(0.5, 0.27, 0.21, 1.0);
// Where the skin is stretched it turns paler and shinier; where it bunches up it folds.
uniform vec4 stretched_color : source_color = vec4(0.92, 0.74, 0.64, 1.0);
uniform float stretch_tint = 1.6;
uniform float fold_strength = 0.35;

// "Show what's left" ping: the silhouette glows on a side that still hides unfinished stencil.
uniform float hint_left = 0.0;
uniform float hint_right = 0.0;
uniform vec4 hint_color : source_color = vec4(1.0, 0.72, 0.2, 1.0);

varying vec2 skin_uv;
varying float skin_theta;
varying float stretch;

float radius_at(float v) {
	return radius * mix(taper_top, taper_bottom, clamp(v / arm_length + 0.5, 0.0, 1.0));
}

float bulge_at(float v) {
	float d = (v - grip_v) / bulge_spread;
	return 1.0 - grip_bulge * (1.0 - exp(-0.5 * d * d));
}

vec2 grip_point(float v) {
	float r = radius_at(v);
	vec2 rest = vec2(sin(grip_angle), cos(grip_angle)) * r;
	vec2 full = vec2(r + max_pull, hold_depth * r);
	return mix(rest, full, pull_amount * bulge_at(v));
}

float tangent_angle(float v) {
	if (pull_side == 0.0 || pull_amount <= 0.0) {
		return grip_angle;
	}
	float r = radius_at(v);
	vec2 q = grip_point(v);
	float distance = length(q);
	if (distance <= r) {
		return grip_angle;
	}
	return min(grip_angle, atan(q.x, q.y) - acos(r / distance));
}

// Screen-space point (x right, y down, z toward the camera) of skin point (theta, v).
vec3 place(float theta, float v) {
	float r = radius_at(v);
	float s = pull_side < 0.0 ? -1.0 : 1.0;
	float local = theta * s;
	float t_angle = tangent_angle(v);
	if (pull_side == 0.0 || local <= t_angle || local > grip_angle) {
		return vec3(sin(theta) * r, v, cos(theta) * r);
	}
	vec2 tangent = vec2(sin(t_angle), cos(t_angle)) * r;
	vec2 grip = grip_point(v);
	// Unstretched at T, more toward the fingers (ArmShape._ease_out).
	float k = clamp(r * (grip_angle - t_angle) / max(length(grip - tangent), 0.0001), 0.2, 2.0);
	float share = (local - t_angle) / (grip_angle - t_angle);
	float t = k * share + (1.0 - k) * share * share;
	vec2 on_flap = mix(tangent, grip, t);
	return vec3(on_flap.x * s, v + pull_shear * bulge_at(v) * t * t, on_flap.y);
}

vec3 to_world(vec3 p) {
	return vec3(p.x, -p.y, p.z);
}

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

void vertex() {
	float theta = (UV.x * 2.0 - 1.0) * PI;
	float v = (UV.y - 0.5) * arm_length * MESH_REACH;
	vec3 here = to_world(place(theta, v));
	float e = 0.004;
	vec3 along_theta = to_world(place(theta + e, v)) - to_world(place(theta - e, v));
	vec3 along_v = to_world(place(theta, v + 1.0)) - to_world(place(theta, v - 1.0));
	VERTEX = here;
	NORMAL = normalize(cross(along_v, along_theta));
	stretch = length(along_theta) / (2.0 * e * radius_at(v));
	skin_uv = vec2((theta + wrap_angle) / (2.0 * wrap_angle), v / stencil_height + 0.5);
	skin_theta = theta;
}

void fragment() {
	// Skin: a warm tone, soft blotches, fine pores.
	vec2 p = skin_uv * vec2(wrap_angle * radius * 2.0, stencil_height);
	float blotch = noise(p * 0.012) * 0.6 + noise(p * 0.04) * 0.4;
	float pores = noise(p * 0.9);
	vec3 skin = mix(skin_shadow_color.rgb, skin_color.rgb, 0.75 + 0.25 * blotch);
	skin *= 0.94 + 0.06 * pores;
	// Stretched skin pales; bunched-up skin shows fine folds across the pull.
	float stretched = clamp((stretch - 1.0) * stretch_tint, 0.0, 1.0);
	skin = mix(skin, stretched_color.rgb, stretched * 0.5);
	float bunched = clamp(1.0 - stretch, 0.0, 1.0);
	float folds = 0.5 + 0.5 * sin(p.x * 0.35 + noise(p * 0.05) * 3.0);
	skin *= 1.0 - fold_strength * bunched * folds;

	vec4 ink = vec4(0.0);
	if (skin_uv.x >= 0.0 && skin_uv.x <= 1.0 && skin_uv.y >= 0.0 && skin_uv.y <= 1.0) {
		ink = texture(ink_layer, skin_uv);
	}
	// The arm darkens and reddens toward its silhouette, like skin turning away from the lamp.
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	skin = mix(skin, skin_shadow_color.rgb * 0.8, edge * edge * 0.6);
	ALBEDO = mix(skin, ink.rgb, ink.a);
	ROUGHNESS = mix(0.62 - 0.2 * stretched, 0.45, ink.a);
	SPECULAR = 0.35;
	float hint = skin_theta < 0.0 ? hint_left : hint_right;
	EMISSION = hint_color.rgb * hint * smoothstep(0.6, 0.98, edge) * 1.2;
	RIM = 0.2;
	RIM_TINT = 0.7;
}
