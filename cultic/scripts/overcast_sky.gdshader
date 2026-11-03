shader_type spatial;
// Stormy sky for the inside of a big sphere (scenes/sky_sphere.tscn): heavy dark blue-grey clouds piled in billows,
// their lower edges catching a cold light, a paler band and rain shafts at the horizon. Slowly drifts.
// Ragged low scud races under the main deck, and lightning (driven by sky_sphere.gd) lights the clouds from inside.
// Unshaded, so the room's lamps do not light it.
render_mode unshaded, shadows_disabled, fog_disabled, depth_draw_never;

uniform vec3 cloud_dark : source_color = vec3(0.016, 0.019, 0.028);
uniform vec3 cloud_mid : source_color = vec3(0.07, 0.08, 0.1);
uniform vec3 cloud_light : source_color = vec3(0.26, 0.285, 0.33);
uniform vec3 horizon_color : source_color = vec3(0.17, 0.19, 0.22);
uniform float cloud_scale = 1.6;
uniform float darkness : hint_range(0.0, 1.0) = 0.72;   // how much of the sky is the darkest cloud
uniform float rain = 0.6;                               // strength of the rain shafts at the horizon
uniform float drift_speed = 0.015;
uniform vec3 wind = vec3(1.0, 0.0, 0.35);
uniform vec3 fog_color : source_color = vec3(0.17, 0.185, 0.205);
uniform float fog_height : hint_range(0.0, 1.0) = 0.1;    // how high up the sky the fog bank reaches (0 = horizon, 1 = overhead)
uniform float fog_density : hint_range(0.0, 1.0) = 0.85;
uniform float sky_time = 0.0;                           // advanced by sky_sphere.gd in the game only: a TIME-driven shader would keep the editor redrawing nonstop
uniform float scud_speed = 0.06;                        // low torn clouds racing under the main deck
uniform float scud_amount : hint_range(0.0, 1.0) = 0.6;
uniform float flash = 0.0;                              // lightning, 0..1, set by sky_sphere.gd
uniform vec3 flash_dir = vec3(0.0, 0.3, -1.0);          // where the strike is
uniform float bolt = 0.0;                               // 1 while the bolt itself is visible
uniform float bolt_seed = 0.0;
uniform vec3 flash_color : source_color = vec3(0.75, 0.8, 1.0);
uniform vec3 light_dir = vec3(0.35, 0.07, -1.0);         // a pale light low behind the clouds, on the window side
uniform vec3 light_color : source_color = vec3(0.36, 0.355, 0.34);


varying vec3 dir;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic: no grid creases in the clouds
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < octaves; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// puffy noise: creases where the noise crosses its middle, rounded lumps in between
float billow(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < octaves; k++) {
		v += a * abs(noise(p) * 2.0 - 1.0);
		p = p * 2.07 + vec3(4.1, 2.3, 7.7);
		a *= 0.5;
	}
	return v;
}

// heavy cloud masses: a broad deck, with big soft lumps rolled into it
float density(vec3 q, int octaves) {
	return fbm(q, octaves) * 0.85 + (1.0 - billow(q * 0.8, 2)) * 0.2;
}

void vertex() {
	dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	float t = sky_time * drift_speed;
	float dither = (hash(vec3(FRAGCOORD.xy, 0.0)) - 0.5) / 255.0;   // breaks up banding in dark gradients
	// lightning: the clouds around the strike light up from inside, the whole sky a little
	vec3 fd = normalize(flash_dir);
	float glow = flash * (pow(max(dot(d, fd), 0.0), 6.0) * 1.4 + 0.12);
	// the bolt: a jagged line from the cloud base at the strike down to the horizon
	float strike = 0.0;
	if (bolt > 0.0 && d.y > 0.0 && d.y < fd.y) {
		float side = atan(d.x * fd.z - d.z * fd.x, dot(d.xz, fd.xz));   // angle left/right of the strike
		float jag = (fbm(vec3(d.y * 18.0, bolt_seed, 0.0), 4) - 0.5) * 0.12 + (fbm(vec3(d.y * 70.0, bolt_seed, 3.0), 2) - 0.5) * 0.02;
		strike = bolt * smoothstep(0.006, 0.0, abs(side - jag)) * (0.6 + 0.4 * d.y / fd.y);
	}
	// thick fog bank near the horizon, thinning upwards in slow-rolling wisps
	float wisps = fbm(vec3(d.x * 3.0 + t * 4.0, d.y * 8.0 - t * 2.0, d.z * 3.0), 4);
	float fog = clamp(1.0 - smoothstep(0.0, fog_height, d.y + (wisps - 0.5) * fog_height * 0.8), 0.0, 1.0) * fog_density;
	if (fog > 0.985) {
		ALBEDO = fog_color + flash_color * (glow * 0.6 + strike) + dither;   // solid fog: no need to work out the clouds behind it
	} else {
		// project onto a flat cloud layer, so the clouds flatten and pile up towards the horizon
		vec2 uv = d.xz / (max(d.y, 0.0) + 0.18) * cloud_scale * 0.4;   // big shapes still near the horizon, where the window looks
		vec3 p = vec3(uv, t * 0.3);
		vec3 warp = vec3(fbm(p * 0.7 + vec3(0.0, 0.0, t), 3), fbm(p * 0.7 + vec3(5.2, 1.3, t), 3), 0.0);
		vec3 q = p * 1.3 + warp * 0.55 + wind * t;
		float dens = density(q, 6);
		dens += (fbm(q * 4.0 + warp, 3) - 0.5) * 0.14;               // crisp torn detail on the edges
		// a pale light sits low behind the clouds: masses are lit on the side facing it, with silver rims and
		// bright gaps around it, and stay heavy and dark away from it
		vec3 ld = normalize(light_dir);
		vec2 light_uv = ld.xz / (ld.y + 0.18) * cloud_scale * 0.4;
		vec2 towards = normalize(light_uv - uv + vec2(0.0001)) * 0.1;
		float lit = clamp((dens - density(q + vec3(towards, 0.0), 4)) * 8.0 + 0.4, 0.0, 1.0);
		float near = pow(max(dot(d, ld), 0.0), 6.0);
		float mass = smoothstep(0.44, 0.58, dens);                 // 0 in the thinner gaps, 1 inside a cloud mass
		vec3 gap = mix(cloud_mid, light_color, 0.25 + near * 0.6);
		vec3 body = mix(cloud_mid, cloud_dark, smoothstep(0.55 - darkness * 0.15, 0.85, dens));
		body = mix(body, mix(cloud_light, light_color, near), lit * lit * (0.55 + 0.45 * near));
		vec3 col = mix(gap, body, mass);
		col += light_color * mass * (1.0 - mass) * (0.5 + 2.2 * near);   // silver lining, brightest near the light
		col += light_color * pow(max(dot(d, ld), 0.0), 60.0) * (1.0 - mass) * 0.9;   // the light itself through gaps
		col = mix(col, cloud_dark, smoothstep(0.35, 1.0, up) * 0.45);   // heavier overhead
		// paler band low on the horizon with grey rain shafts falling into it
		float band = 1.0 - smoothstep(0.0, 0.1, up);
		float shafts = smoothstep(0.45, 0.8, fbm(vec3(normalize(d.xz + vec2(0.0001)) * 6.0, t * 2.0), 3)) * (1.0 - smoothstep(0.0, 0.14, up));
		col = mix(col, horizon_color, band * 0.7);
		col = mix(col, mix(cloud_mid, horizon_color, 0.5), shafts * rain);
		// scud: ragged dark wisps low in the sky, moving much faster than the deck above them
		float scud = fbm(vec3(uv * 2.2 + wind.xz * sky_time * scud_speed, sky_time * 0.02), 4);
		col = mix(col, cloud_dark * 1.3, smoothstep(0.5, 0.75, scud) * scud_amount * (1.0 - smoothstep(0.05, 0.45, up)));
		col = mix(col, horizon_color * 0.7, 1.0 - smoothstep(-0.06, 0.01, d.y));          // below the horizon: flat grey
		col += flash_color * glow * (0.35 + dens) + flash_color * strike;
		ALBEDO = mix(col, fog_color, fog) + dither;
	}
}
