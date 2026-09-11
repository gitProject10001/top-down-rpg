shader_type canvas_item;
// THE PAPER. Procedural, so there is no texture to import, no resolution to outgrow, and no
// seam to hide when the sheet is 224 m wide at one zoom and 20 m wide at another.
//
// Fibre and stains are sampled in SHEET space, not screen space, so the grain is glued to the map
// and slides with it when you pan — paper that stays put while the map moves under it reads as a
// screen effect, which is exactly the wrong impression. The vignette is the one thing sampled in
// screen space, because it belongs to the viewer's light, not to the sheet.

uniform vec3 paper : source_color = vec3(0.86, 0.78, 0.62);
uniform vec3 paper_deep : source_color = vec3(0.74, 0.64, 0.47);
uniform float grain = 0.055;
uniform float vignette = 0.55;
uniform vec2 sheet_uv_origin = vec2(0.0);
uniform vec2 sheet_uv_size = vec2(1.0);

// Hash-without-sine, same as map_fog.gdshader: the sine-fract hash has axis-aligned structure that
// shows up as banding once anything downstream raises the contrast.
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
	vec2 suv = (UV - sheet_uv_origin) / max(sheet_uv_size, vec2(0.0001));

	// Two stretched noise fields crossed at right angles: laid paper, not sandpaper.
	float fibre = vnoise(suv * vec2(430.0, 62.0)) * 0.5 + vnoise(suv * vec2(62.0, 430.0)) * 0.5;
	float stain = fbm(suv * 3.0 + 11.0);

	vec3 col = mix(paper, paper_deep, smoothstep(0.44, 0.86, stain) * 0.55);
	col += (fibre - 0.5) * grain;

	vec2 d = (UV - 0.5) * 2.0;
	col *= 1.0 - vignette * dot(d, d) * 0.42;

	COLOR = vec4(col, 1.0);
}
