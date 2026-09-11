shader_type canvas_item;
// Kuwahara filter — the classic "oil painting" post-process.
// Source: https://godotshaders.com/shader/kuwahara-shader-godot-4/ (adapted).
//
// For each pixel, four overlapping quadrant windows are averaged; the pixel takes the MEAN of
// the window with the LOWEST VARIANCE. Uniform regions flatten into paint daubs while real
// edges (where variance is high on one side) stay crisp — brush strokes without any stroke
// texture. Cost: 4*(radius+1)^2 texture reads per pixel — keep radius modest (2-4).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int radius : hint_range(1, 20) = 3;
// Blend back toward the unfiltered image. At full strength the filter eats small detail — grass
// tips, window mullions, the shingle grid — so being able to sit at 0.5 matters more than it
// sounds. NOTE radius is in PIXELS: the effect gets stronger at low resolution and weaker at high,
// unlike a surface shader which scales with the world.
uniform float strength : hint_range(0.0, 1.0, 0.05) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 m0 = vec3(0.0); vec3 m1 = vec3(0.0); vec3 m2 = vec3(0.0); vec3 m3 = vec3(0.0);
	vec3 s0 = vec3(0.0); vec3 s1 = vec3(0.0); vec3 s2 = vec3(0.0); vec3 s3 = vec3(0.0);
	float n0 = 0.0; float n1 = 0.0; float n2 = 0.0; float n3 = 0.0;
	vec3 c;

	for (int j = -radius; j <= 0; ++j) {
		for (int i = -radius; i <= 0; ++i) {
			c = texture(screen_tex, uv + vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE).rgb;
			float w = 1.0 / (1.0 + length(vec2(float(i), float(j))));
			m0 += c * w; s0 += c * c * w; n0 += w;
		}
	}
	for (int j = -radius; j <= 0; ++j) {
		for (int i = 0; i <= radius; ++i) {
			c = texture(screen_tex, uv + vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE).rgb;
			float w = 1.0 / (1.0 + length(vec2(float(i), float(j))));
			m1 += c * w; s1 += c * c * w; n1 += w;
		}
	}
	for (int j = 0; j <= radius; ++j) {
		for (int i = 0; i <= radius; ++i) {
			c = texture(screen_tex, uv + vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE).rgb;
			float w = 1.0 / (1.0 + length(vec2(float(i), float(j))));
			m2 += c * w; s2 += c * c * w; n2 += w;
		}
	}
	for (int j = 0; j <= radius; ++j) {
		for (int i = -radius; i <= 0; ++i) {
			c = texture(screen_tex, uv + vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE).rgb;
			float w = 1.0 / (1.0 + length(vec2(float(i), float(j))));
			m3 += c * w; s3 += c * c * w; n3 += w;
		}
	}

	float min_sigma2 = 1e+20;
	vec3 best_color = texture(screen_tex, uv).rgb;
	m0 /= n0; s0 = abs(s0 / n0 - m0 * m0);
	float sig = s0.r + s0.g + s0.b;
	if (sig < min_sigma2) { min_sigma2 = sig; best_color = m0; }
	m1 /= n1; s1 = abs(s1 / n1 - m1 * m1);
	sig = s1.r + s1.g + s1.b;
	if (sig < min_sigma2) { min_sigma2 = sig; best_color = m1; }
	m2 /= n2; s2 = abs(s2 / n2 - m2 * m2);
	sig = s2.r + s2.g + s2.b;
	if (sig < min_sigma2) { min_sigma2 = sig; best_color = m2; }
	m3 /= n3; s3 = abs(s3 / n3 - m3 * m3);
	sig = s3.r + s3.g + s3.b;
	if (sig < min_sigma2) { min_sigma2 = sig; best_color = m3; }

	COLOR = vec4(mix(texture(screen_tex, uv).rgb, best_color, strength), 1.0);
}
