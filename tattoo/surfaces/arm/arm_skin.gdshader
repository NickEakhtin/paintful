shader_type spatial;
// The forearm skin. The mesh is a flat grid whose UV are skin coordinates; the vertex shader puts every
// vertex on the arm (a tapered cylinder) or on the pulled skin flap, with the same formulas as ArmShape
// (keep them in sync). World units are screen pixels: x right, y up, z toward the orthographic camera.
// The stencil and ink come from the ink layer, a 2D viewport drawn in the same skin coordinates.
render_mode cull_disabled;

uniform float radius = 210.0;
// The shoulder's top (`fade_top_from`, the profile's first row; ArmShape sets it) dissolves into the background over
// `fade_top_length` px instead of showing a hard edge: more and more of its pixels dropped in a fine noise and the
// rest darkening a little. No transparency: the transparent pipeline lit the arm in blocks. The hand ends by itself.
uniform float fade_top_from = -1948.0;
uniform float fade_top_length = 120.0;
uniform float arm_length = 2300.0;
// The arm's outline, shoulder to fingertips (ArmShape.PROFILE, measured off the side-view photo): R its half width,
// G its centre line across, both in radii, one texel every `profile_step` px from `profile_top`; read with the same
// linear step as ArmShape.radius_at() / center_at(), so the two agree exactly.
uniform sampler2D profile_tex : filter_nearest, repeat_disable;
uniform float profile_top = -1948.0;
uniform float profile_step = 5.0;
uniform int profile_count = 2;
// The photo's own shading over the arm (ArmProfile.shading): R the detail / 2 (the muscles, the elbow, the knuckles),
// G skin (0 between the fingers, cut out below `hand_from`, the wrist). Columns run across the arm (sin of the angle
// round it, -1 .. 1), rows as the profile's. It stays with the arm, not the skin: the skin slides over the muscles.
// `photo_strength` scales how much it darkens and lightens, `photo_relief` how much it bends the light (px of height
// per unit of detail).
uniform sampler2D photo_shading : filter_linear, repeat_disable;
uniform float photo_strength = 1.0;
uniform float photo_relief = 60.0;
uniform float hand_from = 660.0;
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
// The slide (ArmShape.slide()): skin around drag_from (theta, v) moves by drag (arc px at `radius`, px along).
uniform vec2 drag_from = vec2(0.0);
uniform vec2 drag = vec2(0.0);
uniform float drag_radius = 160.0;
// Two short folds (ArmShape.folds): (theta of the middle, middle row, half length in radians, skin px tucked in),
// bunched up and tucked in by their amounts (1 closed, 0 smooth).
uniform vec4 fold_0 = vec4(0.0, 0.0, 0.0001, 1.0);
uniform vec4 fold_1 = vec4(0.0, 0.0, 0.0001, 1.0);
uniform float fold_amount_0 = 0.0;
uniform float fold_amount_1 = 0.0;
uniform float fold_closed_width = 8.0;
uniform float fold_spread = 70.0;
// The fat bump (ArmShape.bump): (theta, top row, half width in radians, height), the skin it sags over, how full.
uniform vec4 bump = vec4(0.0);
uniform float bump_overhang = 45.0;
uniform float bump_amount = 0.0;
// How uneven the bump is, and how ragged the folds' creases are (px): ArmShape.bump_uneven, fold_ragged.
uniform float bump_uneven = 0.5;
uniform bool bump_up = false;
uniform float fold_ragged = 9.0;
// How much the bump bends the light, and how dark the shadow it casts on the skin below.
uniform float bump_relief = 0.45;
uniform float bump_shadow = 0.45;
// How dark the crease is, and how much the bunched lips either side of it catch the light.
uniform float fold_shade = 0.6;
uniform float fold_lip = 0.03;

// The ink layer covers theta -wrap..wrap and v -stencil_height/2..stencil_height/2.
uniform sampler2D ink_layer : source_color, filter_linear, repeat_disable;
// The ink look's wetness (InkPaint.wetness, over the same area as ink_layer): where a wet paper towel went, the skin
// glistens and a little darker, drying as the ink does. Its ink looks fresh by itself (stencil_ink.gdshader).
uniform sampler2D wet_map : filter_linear, repeat_disable, hint_default_black;
uniform float wet_darken = 0.2;
uniform float wet_roughness = 0.08;
uniform float wet_specular = 1.0;
uniform float wrap_angle = 2.094;
uniform float stencil_height = 700.0;

uniform vec4 skin_color : source_color = vec4(0.74, 0.5, 0.38, 1.0);
uniform vec4 skin_shadow_color : source_color = vec4(0.5, 0.27, 0.21, 1.0);
// Where the skin is stretched it turns paler and shinier; where it bunches up it folds.
uniform vec4 stretched_color : source_color = vec4(0.92, 0.74, 0.64, 1.0);
uniform float stretch_tint = 1.6;
uniform float fold_strength = 0.35;
// Skin texture: a tiling cell pattern (the fine criss-cross lines of skin) as colour and as a normal map.
uniform sampler2D skin_detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// One tile of the texture, in skin pixels.
uniform float detail_tile = 160.0;
// How much the lines darken the skin, and how deep they look in the light.
uniform float detail_strength = 0.1;
uniform float normal_strength = 0.5;

// "Show what's left" ping: the silhouette glows on a side that still hides unfinished stencil.
uniform float hint_left = 0.0;
uniform float hint_right = 0.0;
uniform vec4 hint_color : source_color = vec4(1.0, 0.72, 0.2, 1.0);

varying vec2 skin_uv;
varying float skin_theta;
varying float skin_v;
varying float stretch;
// Where the skin point sits on the arm after the slide (theta, row): the photo's shading belongs there.
varying vec2 arm_at;

// (half width, centre) at row v, px (ArmShape.radius_at(), center_at()).
vec2 profile_at(float v) {
	float at = clamp((v - profile_top) / profile_step, 0.0, float(profile_count) - 1.001);
	int i = int(at);
	vec2 a = texelFetch(profile_tex, ivec2(i, 0), 0).rg;
	vec2 b = texelFetch(profile_tex, ivec2(i + 1, 0), 0).rg;
	return radius * mix(a, b, at - float(i));
}

float radius_at(float v) {
	return profile_at(v).x;
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

// Screen-space point (x right, y down, z toward the camera) of arm point (theta, v): round the row's own middle.
vec3 place(float theta, float v) {
	vec2 profile = profile_at(v);
	float r = profile.x;
	float s = pull_side < 0.0 ? -1.0 : 1.0;
	float local = theta * s;
	float t_angle = tangent_angle(v);
	if (pull_side == 0.0 || local <= t_angle || local > grip_angle) {
		return vec3(profile.y + sin(theta) * r, v, cos(theta) * r);
	}
	vec2 tangent = vec2(sin(t_angle), cos(t_angle)) * r;
	vec2 grip = grip_point(v);
	// Unstretched at T, more toward the fingers (ArmShape._ease_out).
	float k = clamp(r * (grip_angle - t_angle) / max(length(grip - tangent), 0.0001), 0.2, 2.0);
	float share = (local - t_angle) / (grip_angle - t_angle);
	float t = k * share + (1.0 - k) * share * share;
	vec2 on_flap = mix(tangent, grip, t);
	return vec3(on_flap.x * s + profile.y, v + pull_shear * bulge_at(v) * t * t, on_flap.y);
}

// A fold as it is at `theta` (ArmShape._fold_local()): a scar — its middle wanders, its band widens and narrows.
vec4 fold_local(vec4 f, float seed, float theta) {
	float a = theta - f.x;
	float middle = f.y + fold_ragged * (0.6 * sin(a * 9.0 + seed) + 0.3 * sin(a * 23.0 + 2.0 * seed)
			+ 0.15 * sin(a * 53.0 + 3.0 * seed));
	return vec4(f.x, middle, f.z, f.w * (1.0 + 0.3 * sin(a * 13.0 + 1.7 * seed)));
}

// The fold at `theta` (ArmShape._fold_at()), as it is there: its vec4 in `f`, its amount returned (0: none).
float fold_at(float theta, out vec4 f) {
	if (fold_amount_0 > 0.0 && abs(theta - fold_0.x) < fold_0.z) {
		f = fold_local(fold_0, 0.7, theta);
		return fold_amount_0;
	}
	if (fold_amount_1 > 0.0 && abs(theta - fold_1.x) < fold_1.z) {
		f = fold_local(fold_1, 3.0, theta);
		return fold_amount_1;
	}
	f = vec4(0.0, 0.0, 1.0, 1.0);
	return 0.0;
}

float fold_reach(vec4 f, float theta) {
	return 1.0 - smoothstep(0.5, 1.0, abs(theta - f.x) / f.z);
}

// Skin point -> its row on the arm with the fold there bunched up (ArmShape.fold_place()).
float fold_place(float theta, float v) {
	vec4 f;
	float amount = fold_at(theta, f);
	if (amount <= 0.0) {
		return v;
	}
	float slack = max(0.0, f.w - fold_closed_width) * clamp(amount, 0.0, 1.0) * fold_reach(f, theta);
	float start = f.y - f.w * 0.5;
	float end = start + f.w;
	if (v < start) {
		return v + slack * 0.5 * (1.0 - smoothstep(0.0, fold_spread, start - v));
	}
	if (v > end) {
		return v - slack * 0.5 * (1.0 - smoothstep(0.0, fold_spread, v - end));
	}
	return v + slack * 0.5 - slack * (v - start) / f.w;
}

// How deep skin point is tucked into a fold (ArmShape.fold_hidden()); `lips` gets the bunched rims' light.
float fold_hidden(float theta, float v, out float lips) {
	vec4 f;
	float amount = fold_at(theta, f);
	lips = 0.0;
	if (amount <= 0.0) {
		return 0.0;
	}
	float reach = fold_reach(f, theta);
	float start = f.y - f.w * 0.5;
	float t = (v - start) / f.w;
	float lip_width = f.w * 0.1;
	lips = (exp(-pow((v - start) / lip_width, 2.0)) + exp(-pow((v - start - f.w) / lip_width, 2.0))) * amount * reach;
	return amount * reach * smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.8, 1.0, t));
}

float bump_reach(float theta) {
	if (bump.z <= 0.0) {
		return 0.0;
	}
	float x = clamp(abs(theta - bump.x) / bump.z, 0.0, 1.0);
	float r = 1.0 - x * x;
	return r * r;   // round, easing to nothing at the sides (no hard edge)
}

// The bump's lumpiness at `theta` (ArmShape._bump_lumps()).
float bump_lumps(float theta) {
	float a = theta - bump.x;
	return 1.0 + bump_uneven * (0.55 * sin(a * 8.0 + 0.6) + 0.3 * sin(a * 19.0 + 2.1));
}

// The bump's top row and height at `theta` (ArmShape._bump_local()).
vec2 bump_local(float theta) {
	float a = theta - bump.x;
	float edge = bump_up ? -(bump.y + bump.w) : bump.y;
	return vec2(edge + bump_uneven * 14.0 * sin(a * 11.0 + 1.3), bump.w * (0.75 + 0.25 * bump_lumps(theta)));
}

float bump_slip(float theta) {
	return min(bump_overhang * 0.92 * clamp(bump_amount, 0.0, 1.0) * bump_reach(theta) * bump_lumps(theta),
			bump_overhang * 0.95);
}

// A row (after the folds) -> its row with the bump sagging (ArmShape.bump_place()); rows mirrored for an upward one.
float bump_place(float theta, float row_in) {
	float row = bump_up ? -row_in : row_in;
	float slip = bump_slip(theta);
	vec2 local = bump_local(theta);
	float top = local.x;
	float lip = top + local.y;
	float bottom = lip + bump_overhang;
	if (slip <= 0.0 || row <= top || row >= bottom) {
		return row_in;
	}
	if (row <= lip) {
		float placed = top + (row - top) * (local.y + slip) / local.y;
		return bump_up ? -placed : placed;
	}
	float placed = lip + slip + (row - lip) * (bump_overhang - slip) / bump_overhang;
	return bump_up ? -placed : placed;
}

// How deep a row is hidden under the bump (ArmShape.bump_hidden()).
float bump_hidden(float theta, float row) {
	vec2 local = bump_local(theta);
	float t = ((bump_up ? -row : row) - local.x - local.y) / bump_overhang;
	return bump_amount * bump_reach(theta) * smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.8, 1.0, t));
}

// The bump's height over the skin at (theta, row after the folds), 0..1: a lumpy dome over its rows.
float bump_height(float theta, float row) {
	vec2 local = bump_local(theta);
	float t = clamp(((bump_up ? -row : row) - local.x) / local.y, 0.0, 1.0);
	return bump_amount * bump_reach(theta) * bump_lumps(theta) * sin(t * PI);
}

// Where arm point (theta, row) is in the photo's shading (ArmProfile.shading).
vec2 photo_uv(float theta, float row) {
	return vec2(sin(theta) * 0.5 + 0.5, ((row - profile_top) / profile_step + 0.5) / float(profile_count));
}

// The photo's shading detail at arm point (theta, row): 1 = as the average across the arm there.
float photo_detail(float theta, float row) {
	return texture(photo_shading, photo_uv(theta, row)).r * 2.0;
}

// Where skin point (theta, v) sits after the fold and the slide.
vec2 slide(float theta, float v) {
	vec2 d = vec2((theta - drag_from.x) * radius, v - drag_from.y);
	float k = exp(-dot(d, d) / (drag_radius * drag_radius));
	return vec2(theta + drag.x / radius * k, bump_place(theta, fold_place(theta, v)) + drag.y * k);
}

// The skin point's place on screen, slid first.
vec3 place_slid(float theta, float v) {
	vec2 at = slide(theta, v);
	return place(at.x, at.y);
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
	vec3 here = to_world(place_slid(theta, v));
	float e = 0.004;
	vec3 along_theta = to_world(place_slid(theta + e, v)) - to_world(place_slid(theta - e, v));
	vec3 along_v = to_world(place_slid(theta, v + 1.0)) - to_world(place_slid(theta, v - 1.0));
	VERTEX = here;
	NORMAL = normalize(cross(along_v, along_theta));
	TANGENT = normalize(along_theta);
	BINORMAL = normalize(along_v);
	// round the arm only: folds and the bump move rows up and down, which isn't stretch (it lit pale streaks)
	stretch = length(along_theta.xz) / (2.0 * e * radius_at(v));
	skin_uv = vec2((theta + wrap_angle) / (2.0 * wrap_angle), v / stencil_height + 0.5);
	skin_theta = theta;
	skin_v = v;
	arm_at = slide(theta, v);
}

void fragment() {
	// Skin: a warm tone, soft blotches, fine pores.
	vec2 p = skin_uv * vec2(wrap_angle * radius * 2.0, stencil_height);
	float blotch = noise(p * 0.012) * 0.6 + noise(p * 0.04) * 0.4;
	float pores = noise(p * 0.9);
	vec3 skin = mix(skin_shadow_color.rgb, skin_color.rgb, 0.75 + 0.25 * blotch);
	skin *= 0.94 + 0.06 * pores;
	// the skin's fine lines; stretched skin smooths them out
	vec2 detail_uv = p / detail_tile;
	float lines = 1.0 - texture(skin_detail, detail_uv).r;
	float smooth_out = clamp((stretch - 1.0) * 2.0, 0.0, 0.7);
	skin *= 1.0 - detail_strength * lines * (1.0 - smooth_out);
	// Stretched skin pales; bunched-up skin shows fine folds across the pull.
	float stretched = clamp((stretch - 1.0) * stretch_tint, 0.0, 1.0);
	skin = mix(skin, stretched_color.rgb, stretched * 0.5);
	float bunched = clamp(1.0 - stretch, 0.0, 1.0);
	float folds = 0.5 + 0.5 * sin(p.x * 0.35 + noise(p * 0.05) * 3.0);
	skin *= 1.0 - fold_strength * bunched * folds;

	vec4 ink = vec4(0.0);
	float wet = 0.0;
	if (skin_uv.x >= 0.0 && skin_uv.x <= 1.0 && skin_uv.y >= 0.0 && skin_uv.y <= 1.0) {
		ink = texture(ink_layer, skin_uv);
		wet = clamp(texture(wet_map, skin_uv).r, 0.0, 1.0);
	}
	skin *= 1.0 - wet_darken * wet;
	// the fold: the tucked band goes dark, the bunched lips either side catch the light
	float lips;
	float hidden = fold_hidden(skin_theta, skin_v, lips);
	// the bump: the skin it sags over lies in its shadow; the dome itself bends the light (below)
	float bump_row = fold_place(skin_theta, skin_v);
	float under = bump_hidden(skin_theta, bump_row);
	hidden = max(hidden, under);
	// the shadow darkens skin and ink alike, after the ink is laid on (fading the ink there left brown skin showing)
	float shade = (1.0 - bump_shadow * under) * (1.0 - fold_shade * hidden);
	// The arm darkens and reddens toward its silhouette, like skin turning away from the lamp.
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	skin = mix(skin, skin_shadow_color.rgb * 0.8, edge * edge * 0.6);
	// the photo's shading where this skin lies on the arm: its muscles, elbow and knuckles, skin and ink alike; the
	// gaps between the fingers are cut out
	vec4 photo = texture(photo_shading, photo_uv(arm_at.x, arm_at.y));
	if (arm_at.y > hand_from && photo.g < 0.4) {
		discard;
	}
	shade *= mix(1.0, photo.r * 2.0, photo_strength);
	ALBEDO = mix(skin, ink.rgb, ink.a) * shade + vec3(fold_lip) * lips * (1.0 - ink.a);
	ROUGHNESS = mix(mix(0.62 - 0.2 * stretched, wet_roughness, wet), 0.45, ink.a);
	// the photo's muscles bend the light too: brighter counts as higher, the normal tilts by the slope
	{
		float e = 4.0;
		float d_v = photo_detail(arm_at.x, arm_at.y + e) - photo_detail(arm_at.x, arm_at.y - e);
		float d_t = photo_detail(arm_at.x + e / radius, arm_at.y) - photo_detail(arm_at.x - e / radius, arm_at.y);
		float k = photo_relief / (2.0 * e);
		NORMAL = normalize(NORMAL - normalize(TANGENT) * d_t * k - normalize(BINORMAL) * d_v * k);
	}
	// the shoulder's top dissolves: pixels dropped by a fine noise (interleaved gradient noise, steady on screen)
	float fade = smoothstep(fade_top_from, fade_top_from + fade_top_length, skin_v);
	float grain = fract(52.9829189 * fract(dot(floor(FRAGCOORD.xy), vec2(0.06711056, 0.00583715))));
	if (fade < grain) {
		discard;
	}
	ALBEDO *= mix(0.6, 1.0, fade);
	// the bump's dome: tilt the normal by the height's slope along the arm and round it
	if (bump_amount > 0.0) {
		float e = 2.0;
		float h_v = bump_height(skin_theta, bump_row + e) - bump_height(skin_theta, bump_row - e);
		float h_t = bump_height(skin_theta + e / radius, bump_row) - bump_height(skin_theta - e / radius, bump_row);
		float slope = bump_relief * bump.w * 0.02;
		NORMAL = normalize(NORMAL - normalize(TANGENT) * h_t * slope / (2.0 * e) * 30.0 - normalize(BINORMAL) * h_v * slope / (2.0 * e) * 30.0);
	}
	NORMAL_MAP = texture(skin_normal, detail_uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - smooth_out) * (1.0 - 0.5 * ink.a);
	SPECULAR = mix(0.35, wet_specular, wet * (1.0 - ink.a));
	NORMAL_MAP_DEPTH *= 1.0 - 0.6 * wet;   // a film of water smooths the skin's fine lines
	float hint = skin_theta < 0.0 ? hint_left : hint_right;
	EMISSION = hint_color.rgb * hint * smoothstep(0.6, 0.98, edge) * 1.2;
	RIM = 0.2;
	RIM_TINT = 0.7;
}
