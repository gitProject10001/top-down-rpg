shader_type canvas_item;
// THE CLOUD. Reads MapGrid's discovery bytes (FORMAT_R8, bilinear) and turns them into weather.
//
// THE FOG IS NOT BLACK. Black over parchment reads as a hole burnt in the paper; warm grey-cream
// reads as cloud lying on a map, which is the thing being asked for. The only saturated colour in
// here is the rim: a thin band of ACCENT gold exactly on the boundary of the known world, so the
// frontier looks lit rather than cut.
//
// THE DOMAIN WARP IS WHAT HIDES THE GRID. At 1 m cells over a ~1000 px map the discovery texture is
// ~4.7 screen px per texel; bilinear alone would still read as soft squares. Displacing the lookup
// by a couple of texels of noise turns every cell boundary into a wandering line, which is why the
// grid can stay coarse enough to stamp cheaply.

uniform sampler2D discovery : filter_linear, repeat_disable, hint_default_black;
/// What was SEEN rather than walked (MapData's coarse vista grid). It never clears the fog, only
/// thins it — enough for the muted relief underneath to read as distant terrain through haze, never
/// enough to compete with the ground you have actually crossed. Black default = a zone with no
/// vista (every dungeon) behaves exactly as it did before this existed.
uniform sampler2D vista : filter_linear, repeat_disable, hint_default_black;
uniform float vista_thin = 0.62;      // how much of the fog a fully-seen vista cell removes
uniform vec2 map_uv_origin = vec2(0.0);
uniform vec2 map_uv_size = vec2(1.0);
// COOLER AND DARKER THAN THE PAPER, and that is the whole requirement. The first pass used
// (0.80,0.74,0.64) over (0.62,0.56,0.47) — the second of which is almost exactly PARCH_DEEP, so the
// unexplored world rendered as a slightly different shade of parchment and the map did not read as
// clouded at all. Fog has to be a DIFFERENT MATERIAL from the sheet, not a tint of it.
uniform vec3 fog_light : source_color = vec3(0.66, 0.625, 0.575);
uniform vec3 fog_dark : source_color = vec3(0.395, 0.368, 0.342);
uniform vec3 rim_color : source_color = vec3(1.0, 0.82, 0.5);
uniform float drift = 0.008;
uniform float warp = 0.014;
/// Viewport width / height. The noise is sampled in UV, which is not square — without this the
/// cloud blobs come out stretched into horizontal rectangles on a 16:10 screen.
uniform float aspect = 1.6;

// Hash-without-sine. The obvious fract(sin(dot(...))) hash has visible axis-aligned structure, and
// the hard smoothstep this shader applies to the result AMPLIFIES it into vertical banding across
// the fog — which is exactly what the first render showed.
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 guv = (UV - map_uv_origin) / max(map_uv_size, vec2(0.0001));

	// Anything off the grid is unexplored by definition, and must stay fully clouded — otherwise
	// the sheet's margins read as "discovered empty ground".
	float seen = 0.0;
	float far_seen = 0.0;
	if (guv.x >= 0.0 && guv.x <= 1.0 && guv.y >= 0.0 && guv.y <= 1.0) {
		vec2 w = guv + (vec2(fbm(guv * 7.0), fbm(guv * 7.0 + 31.4)) - 0.5) * warp;
		vec2 cw = clamp(w, vec2(0.0), vec2(1.0));
		seen = texture(discovery, cw).r;
		far_seen = texture(vista, cw).r;      // same rect, so the same UV addresses both
	}

	// Two scales drifting in OPPOSITE directions at different rates, so the cloud churns instead of
	// sliding — one layer moving alone reads as a texture being scrolled, which is a screen effect.
	// Sampled in screen UV, not sheet UV: weather belongs to the viewer, not to the paper.
	vec2 auv = UV * vec2(aspect, 1.0);
	float cl = fbm(auv * 3.2 + vec2(TIME * drift, TIME * drift * 0.6));
	float cl2 = fbm(auv * 7.4 - vec2(TIME * drift * 0.7, TIME * drift * 0.3));
	float cloud = smoothstep(0.18, 0.82, clamp(cl * 0.70 + cl2 * 0.44, 0.0, 1.0));

	float a = 1.0 - smoothstep(0.32, 0.72, seen + (cloud - 0.5) * 0.22);
	// MULTIPLIED, not maxed: walked ground must still clear completely (a is already 0 there), and
	// merely-seen ground lifts to a haze rather than opening up.
	a *= 1.0 - smoothstep(0.10, 0.55, far_seen) * vista_thin;
	float rim = smoothstep(0.28, 0.46, seen) * (1.0 - smoothstep(0.54, 0.80, seen));

	COLOR = vec4(mix(fog_dark, fog_light, cloud) + rim_color * rim * 0.45, a);
}
