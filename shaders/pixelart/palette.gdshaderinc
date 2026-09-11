// PALETTE SNAPPING, in Oklab, with ordered dithering — the thing that makes a 3D render read as
// pixel art rather than as a small screenshot.
//
// WHY OKLAB AND NOT RGB. "Nearest colour" in RGB is nearest by voltage, not by appearance: RGB
// distance is dominated by green and treats a lightness step and a hue step as the same size. On
// this project's palette that shows up as mud picking a green out of the foliage ramp because the
// two happen to sit close in the blue channel. Oklab is perceptually uniform, so "nearest" means
// what a person means by it, and the L axis can be weighted separately from chroma — which matters
// here because pixel artists ramp lightness much more finely than hue.
//
// WHY ORDERED DITHER BEFORE THE SEARCH, NOT AFTER. The alternative is to find the two nearest
// entries and blend between them by a threshold, which needs a second search and still snaps to
// whichever pair happens to straddle the pixel. Perturbing the INPUT by the Bayer value and then
// snapping once is the classic ordered-palette dither: it costs one search, and a smooth gradient
// crossing the gap between two palette entries automatically breaks into the checker-to-solid
// progression a pixel artist draws by hand.
//
// The palette is a 1-pixel-tall texture; PALETTE_MAX bounds the loop because GLSL wants a constant
// trip count and a texture's size is not one. Unused slots are the last real colour repeated, so
// they can never win the search.

const int PALETTE_MAX = 64;

// sRGB -> linear Oklab. The palette texture is imported as source_color, so both sides of the
// comparison are already linear when they reach here.
vec3 linear_to_oklab(vec3 c) {
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	l = sign(l) * pow(abs(l), 1.0 / 3.0);
	m = sign(m) * pow(abs(m), 1.0 / 3.0);
	s = sign(s) * pow(abs(s), 1.0 / 3.0);
	return vec3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

// 8x8 Bayer, evaluated rather than sampled. A texture fetch here would need its own import
// settings (nearest, no mips, no sRGB) and one more file to get wrong; this recursive construction
// is exact — verified to emit each of the 64 levels once, in the canonical order — and free.
//
// bayer2 is the 2x2 matrix [[0,2],[3,1]]/4 written as arithmetic: y*y*0.75 is 0 for even rows and
// 0.75 for odd ones, which is the row swap; x/2 is the column. Each further level adds the
// previous one at quarter weight, which is exactly how the matrix is defined.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

// Returns [0, 1) in 1/64 steps.
float bayer8(vec2 a) {
	return bayer4(a * 0.5) * 0.25 + bayer2(a);
}

// `count` is the real number of entries; `weights` scales (L, a, b) before the distance, so a
// scene can be told to care more about lightness than hue (or the reverse) without a new palette.
vec3 palette_snap(sampler2D pal, int count, vec3 col, vec3 weights) {
	vec3 want = linear_to_oklab(col) * weights;
	vec3 best = col;
	float best_d = 1e9;
	float inv = 1.0 / float(max(count, 1));
	for (int i = 0; i < PALETTE_MAX; i++) {
		if (i >= count) {
			break;
		}
		vec3 entry = texture(pal, vec2((float(i) + 0.5) * inv, 0.5)).rgb;
		vec3 d = linear_to_oklab(entry) * weights - want;
		float dist = dot(d, d);
		if (dist < best_d) {
			best_d = dist;
			best = entry;
		}
	}
	return best;
}
