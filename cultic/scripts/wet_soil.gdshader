shader_type spatial;
// Wet brown soil for the ground patches (scenes/props/ground/): two dark browns blended by a broad, soft noise plus a
// fine speckle, a crumbly normal map, and wetness: the whole patch is damp (`dampness`) and the hollows (vertex
// alpha = 1) are soaked: darker, glossy and smoother, as if water stands there.
// The volcano crater (scripts/volcano.gd) cuts a round hole through every patch: nothing is drawn inside the
// vertical cylinder `hole` (x, z, radius; radius 0 = no hole; the volcano sets it), except on the volcano itself
// (`ignore_hole`).

uniform sampler2D pattern : filter_linear_mipmap, repeat_enable;         // grey noise
uniform sampler2D grain : hint_normal, filter_linear_mipmap, repeat_enable; // crumbs and clods
uniform vec3 dark_soil : source_color = vec3(0.085, 0.058, 0.04);
uniform vec3 light_soil : source_color = vec3(0.17, 0.115, 0.075);
uniform float uv_scale = 0.8;              // texture repeats per metre
uniform float dampness = 0.35;             // wetness everywhere, 0..1
uniform float wet_darken = 0.55;           // how much darker fully soaked soil is
uniform float wet_roughness = 0.45;        // a soft sheen where it is soaked (lower = more mirror-like)
uniform float dry_roughness = 0.85;
uniform float grain_depth = 1.0;
uniform bool ignore_hole = false;
uniform vec3 hole = vec3(0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!ignore_hole && hole.z > 0.0 && distance(world_pos.xz, hole.xy) < hole.z) {
		discard;
	}
	vec2 uv = UV * uv_scale;
	float broad = texture(pattern, uv * 0.3).r;
	float fine = texture(pattern, uv * 3.0 + 0.37).r;
	vec3 soil = mix(dark_soil, light_soil, smoothstep(0.2, 0.8, broad)) * (0.85 + 0.3 * fine) * COLOR.rgb;
	float wet = clamp(dampness + COLOR.a + (texture(pattern, uv * 0.6 + 0.5).r - 0.5) * 0.5, 0.0, 1.0);
	ALBEDO = soil * mix(1.0, wet_darken, wet);
	ROUGHNESS = mix(dry_roughness, wet_roughness, wet);
	SPECULAR = 0.3;
	NORMAL_MAP = texture(grain, uv * 2.0).rgb;
	NORMAL_MAP_DEPTH = grain_depth * mix(1.0, 0.25, wet * wet);   // standing water smooths the surface
}
