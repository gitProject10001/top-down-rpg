shader_type spatial;
render_mode cull_back;
// The wilds terraces — painted_env FAMILY, not terrain_slope's bench hack: ambient stays ON
// (ambient_light_disabled was the reference-floor trade, its own header says so), no specular,
// no rim. W1 keeps this deliberately small: flat grass tops broken by a world-space value
// noise, cliffs banded by WORLD-Y strata (the GladeRockField sawtooth idea, so beds run level
// across separate faces). Vertex COLOR carries (tier fraction, moisture[W3], course parity).

uniform bool is_cliff = false;
uniform vec3 grass_color: source_color = vec3(0.34, 0.44, 0.26);
uniform vec3 grass_dark: source_color = vec3(0.24, 0.33, 0.19);
uniform vec3 dirt_color: source_color = vec3(0.42, 0.34, 0.24);
uniform vec3 cliff_color: source_color = vec3(0.38, 0.33, 0.30);
uniform vec3 cliff_dark: source_color = vec3(0.26, 0.22, 0.21);
uniform float strata_height = 0.6;
uniform float breakup_scale = 0.11;    // world-space noise frequency, 1/m
uniform float breakup_amount = 0.35;
// The dock's walkability overlay (debug only, never shipped on): green flat, red cliff.
uniform bool slope_overlay = false;

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec4 v_col;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

// Tiny world-space value noise — enough breakup for W1 without a texture dependency.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 col;
	if (is_cliff) {
		// Strata by world Y: a sawtooth over strata_height, hardened into two-tone beds, plus
		// the course parity the mesh already carries for a subtle per-course shift.
		float band = fract(v_world.y / strata_height);
		float bed = step(0.5, band);
		float n = vnoise(v_world.xz * breakup_scale * 3.0 + v_world.y);
		col = mix(cliff_color, cliff_dark, bed * 0.6 + v_col.b * 0.15 + n * 0.2);
	} else {
		float n = vnoise(v_world.xz * breakup_scale);
		float n2 = vnoise(v_world.xz * breakup_scale * 4.7 + 13.0);
		vec3 grass = mix(grass_color, grass_dark, n * breakup_amount + n2 * 0.18);
		// Higher tiers dry toward dirt a little (tier fraction in COLOR.r).
		col = mix(grass, dirt_color, v_col.r * 0.25);
		// Water beds (COLOR.g) are wet earth, not lawn.
		col = mix(col, dirt_color * 0.8, v_col.g * 0.85);
	}
	if (slope_overlay) {
		float flat_f = smoothstep(0.7, 0.9, v_world_normal.y);
		col = mix(vec3(0.8, 0.2, 0.2), vec3(0.2, 0.8, 0.3), flat_f);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
