shader_type particles;
// Fireflies circling a lamp post (scripts/fireflies.gd): every particle keeps its own orbit radius, height and
// speed, drifts up and down, wanders a little and blinks on its own rhythm. Positions are computed outright each
// frame (no physics), in the emitter's local space, around the emitter (the lantern).

uniform vec2 radius = vec2(0.3, 0.8);          // metres from the lantern
uniform vec2 height = vec2(-0.4, 0.4);         // metres below/above the emitter (the lantern)
uniform vec2 speed = vec2(2.2, 5.4);           // radians per second, either direction
uniform float bob = 0.12;                      // up/down drift, metres
uniform float wander = 0.1;                    // in/out drift, metres
uniform float blink_rate = 0.5;                // blinks per second, on average

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	uint seed = INDEX * 7919u + RANDOM_SEED;
	CUSTOM.x = mix(radius.x, radius.y, sqrt(hash(seed + 1u)));      // radius (sqrt: not all crowded at the post)
	CUSTOM.y = mix(height.x, height.y, hash(seed + 2u));            // height
	CUSTOM.z = mix(speed.x, speed.y, hash(seed + 3u)) * (hash(seed + 4u) < 0.5 ? -1.0 : 1.0);   // angular speed
	CUSTOM.w = 0.0;                                                 // age
	VELOCITY = vec3(0.0);
}

void process() {
	CUSTOM.w += DELTA;
	uint seed = INDEX * 7919u + 17u;                               // the same for this particle every life
	float phase = hash(seed) * 6.2832;
	float t = TIME;
	float angle = phase + CUSTOM.z * t;
	float r = CUSTOM.x + sin(t * 1.6 + phase * 3.0) * wander;
	float y = CUSTOM.y + sin(t * (1.2 + hash(seed + 5u) * 1.2) + phase) * bob;
	vec3 pos = vec3(cos(angle) * r, y, sin(angle) * r);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = pos;

	// a blink: a short soft pulse now and then, each firefly on its own clock
	float rate = blink_rate * (0.6 + hash(seed + 6u) * 0.8);
	float cycle = fract(t * rate + hash(seed + 7u));
	float pulse = smoothstep(0.0, 0.08, cycle) * (1.0 - smoothstep(0.08, 0.35, cycle));
	// fade in after (re)spawning and out before the end of a life, so restarts are never seen
	float life_fade = smoothstep(0.0, 1.0, CUSTOM.w) * (1.0 - smoothstep(LIFETIME - 1.0, LIFETIME, CUSTOM.w));
	COLOR = vec4(1.0, 1.0, 1.0, mix(0.32, 1.0, pulse) * life_fade);
}
