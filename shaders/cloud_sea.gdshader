shader_type spatial;
render_mode unshaded, blend_mix;
// Infinite sea of clouds under the world — port of "Above the clouds" by Duke
// (https://www.shadertoy.com/view/ll2SWd), which itself credits: iq's "Clouds" (lighting),
// Shane's "Fiery Spikeball" (raymarcher), otaviogood's "Alien Beacon" (spiral noise).
// License of the original: CC BY-NC-SA 3.0 (NON-COMMERCIAL — replace before any commercial release).
//
// Integration: drawn on a large horizontal quad that follows the player (the deck is sampled in
// world-anchored "cloud space", so the quad recentring never moves the clouds). The camera is
// always ABOVE the deck (player never enters it), rays march downward from the quad surface.
// The Shadertoy camera rotations are dropped; wind = slow world-space drift instead.

uniform sampler2D noise_tex : repeat_enable, filter_linear;   // 256^2 RANDOM-texel RGBA (iq 3D-noise trick)
uniform float world_scale = 0.25;     // world metres -> cloud units (original constants stay valid)
uniform float sea_level = -45.0;      // world y of the deck's mean surface
uniform vec3 wind = vec3(1.0, 0.0, 0.6);
uniform float wind_speed = 0.25;      // cloud units/sec — "lightly moving"
uniform float fuzz_speed = 0.8;       // fine-detail boil (original was 5.0 — too frantic here)
uniform int steps = 64;
uniform vec3 sun_dir = vec3(-0.5, 0.5, 0.7);      // TOWARD the sun; fed by cloud_sea.gd
uniform vec3 horizon_color : source_color = vec3(0.62, 0.61, 0.55);  // match env fog
uniform float fuzz_freq = 9.0;        // original 50 -> subpixel at world scale; ~9 = visible boil
uniform float fuzz_amp = 1.6;         // cauliflower granularity on the tops
uniform float aerial = 0.00012;       // original 4e-4 washed the deck white at our distances
uniform float brightness = 0.82;      // keep tops out of bloom blow-out
// Our camera looks steeply DOWN (never grazing like the Shadertoy) — the deck must read through
// RELIEF SHADING: sample the sun-derivative farther away and sharpen it, so billow tops light up
// and the valleys between them shade, like an aerial photo of a cumulus field.
uniform float light_offset = 1.0;     // original 0.3
uniform float light_sharp = 0.3;      // original 0.6 (smaller = punchier)
uniform float max_march = 200.0;      // original 120 read as a hard horizon from low angles
uniform float relief = 1.6;           // vertical exaggeration: billows tower instead of swell

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ---- iq's texture-based 3D value noise (needs RANDOM texels + bilinear filtering) ----
float pn(in vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 uv = (p.xy + vec2(37.0, 17.0) * p.z) + f.xy;
	vec2 rg = textureLod(noise_tex, (uv + 0.5) / 256.0, 0.0).yx;
	return -1.0 + 2.4 * mix(rg.x, rg.y, f.z);
}

float fpn(vec3 p) {
	return pn(p * 0.06125) * 0.5 + pn(p * 0.125) * 0.25 + pn(p * 0.25) * 0.125;
}

float rand(vec2 co) {
	return fract(sin(dot(co * 0.123, vec2(12.9898, 78.233))) * 43758.5453);
}

// ---- otaviogood's spiral noise (hash-free; THE cauliflower shapes) ----
const float nudge = 0.739513;
const float normalizer = 0.80405254;   // 1/sqrt(1+nudge^2)

float SpiralNoiseC(vec3 p) {
	float n = 0.0;
	float iter = 1.0;
	for (int i = 0; i < 8; i++) {
		n += -abs(sin(p.y * iter) + cos(p.x * iter)) / iter;   // abs -> ridged
		p.xy += vec2(p.y, -p.x) * nudge;
		p.xy *= normalizer;
		p.xz += vec2(p.z, -p.x) * nudge;
		p.xz *= normalizer;
		iter *= 1.733733;
	}
	return n;
}

float SpiralNoise3D(vec3 p) {
	float n = 0.0;
	float iter = 1.0;
	for (int i = 0; i < 5; i++) {
		n += (sin(p.y * iter) + cos(p.x * iter)) / iter;
		p.xz += vec2(p.z, -p.x) * nudge;
		p.xz *= normalizer;
		iter *= 1.33733;
	}
	return n;
}

float Clouds(vec3 p) {
	float final = p.y + 4.5;
	final += SpiralNoiseC(p.zxy * 0.123 + 100.0) * 3.0;   // large terrain-like features
	final -= SpiralNoise3D(p);                            // large 3D features
	return final;
}

float map(vec3 p) {
	// (rotations from the original dropped — they were the Shadertoy camera; wind drifts instead)
	p += wind * (TIME * wind_speed);
	return Clouds(p) + fpn(p * fuzz_freq + TIME * fuzz_speed) * fuzz_amp;
}

// world -> cloud space: y anchored to sea_level (deck mean at cloud y = -4.5). The y axis is
// sampled at world_scale/relief — vertical exaggeration that turns swells into cumulus towers.
vec3 to_cloud(vec3 pw) {
	return vec3(pw.x * world_scale,
				(pw.y - sea_level) * world_scale / relief - 4.5,
				pw.z * world_scale);
}

void fragment() {
	vec3 ro = to_cloud(v_world);                       // start at the quad surface — no empty march
	vec3 rdw = normalize(v_world - CAMERA_POSITION_WORLD);
	vec3 rd = normalize(vec3(rdw.x, rdw.y / relief, rdw.z));  // direction bent by the anisotropy

	float ld = 0.0;
	float td = 0.0;
	float w = 0.0;
	float d = 1.0;
	float t = 0.0;

	vec2 seed = SCREEN_UV + fract(TIME);
	t = (1.0 + 0.2 * rand(seed));                      // dither the start (kills banding)

	vec4 sum = vec4(0.0);

	for (int i = 0; i < 128; i++) {
		if (i >= steps) { break; }
		vec3 pos = ro + t * rd;

		if (td > (1.0 - 1.0 / 80.0) || d < 0.0006 * t || t > max_march
				|| pos.y < -5.0 || pos.y > 30.0 || sum.a > 0.99) { break; }

		d = map(pos) * 0.326;
		d = max(d, -0.4);                              // fix holes deep inside clouds

		if (d < 0.4) {
			ld = 0.1 - d;
			// iq directional-derivative lighting: sample density toward the sun
			float shade = clamp((ld - map(pos + light_offset * sun_dir)) / light_sharp, 0.0, 1.0);
			ld *= shade;
			w = (1.0 - td) * ld;
			td += w;

			// (local adaptation) top-down relief: the ambient itself follows the sun-derivative
			// shading, drifting COOL in the billow valleys — otherwise an aerial view is a flat
			// bright sheet (the original's contrast came from grazing silhouettes we never see).
			vec3 amb = mix(vec3(0.42, 0.46, 0.60), vec3(0.65, 0.68, 0.7) * 1.3, shade);
			vec3 lin = amb + 0.5 * vec3(0.7, 0.5, 0.3) * ld;
			vec4 col = vec4(mix(1.15 * vec3(1.0, 0.95, 0.8), vec3(0.765), d), max(0.6, d));
			col.xyz *= lin;
			col.xyz = mix(col.xyz, horizon_color, 1.0 - exp(-aerial * t * t));  // aerial perspective
			col.a *= 0.4;
			col.rgb *= col.a;
			sum = sum + col * (1.0 - sum.a);           // front-to-back blend
		}

		td += 1.0 / 70.0;
		d = max(d, 0.04);
		d = abs(d) * (1.0 + 0.28 * rand(seed * vec2(float(i))));   // fuzz + de-band
		t += d * 0.5;
	}

	sum = clamp(sum, 0.0, 1.0);
	ALBEDO = brightness * sum.rgb / max(sum.a, 1e-3);  // un-premultiply for Godot's blend_mix
	ALPHA = sum.a;
}
