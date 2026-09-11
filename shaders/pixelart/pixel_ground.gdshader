shader_type spatial;
render_mode world_vertex_coords;
// THE CAMP FLOOR. Half the frame, and the surface the whole scene is judged on -- everything else
// sits on it. Separate from pixel_surface.gdshader because the ground needs three things a prop
// never does, and bolting them onto the shared shader would make every barrel pay for them.
//
//   1. TWO MUD SETS, BLENDED. One tiling texture over 44 metres reads as one tiling texture,
//      however good it is and however hard the de-tiler works: the eye finds the repeat because
//      every part of the ground has the same STATISTICS. Cross-fading a churned leafy mud against a
//      dry trodden one on a low-frequency mask gives the ground regions -- a wet corner, a dry
//      path -- and regions are what stop it reading as wallpaper.
//
//   2. ONE HEIGHT FIELD FOR BOTH THE SHAPE AND THE WATER. In pixel_surface the puddles are found by
//      sampling the tiling height map, which means they appear wherever the TEXTURE is dark -- at
//      texture frequency, every couple of metres, in a regular grid. Water does not do that. Here
//      the ground is displaced by a procedural fbm and the puddles are the low ground OF THAT SAME
//      FIELD, so the water is in the hollows the mesh actually has. The field is also differentiated
//      analytically for the normal, so the rolling ground is lit as the shape it is rather than as a
//      flat plane wearing a picture.
//
//   3. WEEDS AS TINT, NOT AS GEOMETRY. The reference's mud is broken up by patches of dry
//      yellow-green scrub. Most of those are too small to be worth a mesh at 640x360, so a third
//      noise tints the albedo toward dry grass and the scattered cards handle only the tufts big
//      enough to have a silhouette.
//
// The lighting half is deliberately identical to pixel_surface.gdshader, banding and coloured
// shadows included -- the ground must plate the same way as everything standing on it.

group_uniforms Layers;
uniform sampler2D mud_color : source_color, hint_default_white;
uniform sampler2D mud_normal : hint_normal;
uniform sampler2D mud_ao : hint_default_white;
uniform sampler2D dry_color : source_color, hint_default_white;
uniform sampler2D dry_normal : hint_normal;
uniform sampler2D dry_ao : hint_default_white;
uniform vec4 mud_tint : source_color = vec4(1.0);
uniform vec4 dry_tint : source_color = vec4(1.0);
// Metres per texture repeat. Big enough that a leaf is several pixels on screen: at 640x360 and
// this camera height anything finer stops being detail and becomes noise the outline pass inks.
uniform float texture_metres : hint_range(0.5, 20.0, 0.1) = 6.0;
uniform float normal_strength : hint_range(0.0, 3.0, 0.05) = 0.7;
// PULL THE MUD TOWARD ITS OWN LUMINANCE BEFORE TINTING, the same knob pixel_surface carries and for
// a sharper reason here. brown_mud_leaves_01 measures linear (0.396, 0.330, 0.201) -- a strongly
// warm brown. The palette gives the ground a DESATURATED ramp on purpose, so that timber lying on it
// can be the warm thing; but a warm photograph ignores that and lands on the wood ramp anyway, which
// is measurable: 60 percent of one frame came out of the wood ramp and only 16 percent out of mud,
// on a scene that is mostly ground. Desaturating the texture hands the hue back to mud_tint.
uniform float texture_desaturate : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float ao_strength : hint_range(0.0, 2.0, 0.05) = 0.55;
group_uniforms;

group_uniforms Pixelation;
// THE ART TEXEL, in metres -- see the same uniform in pixel_surface.gdshader for the full reasoning.
// The short version: the pixel-art character is produced by snapping every surface lookup to a grid
// fixed to the WORLD, not by rendering the frame small. That keeps the render high resolution (so
// the reference's density of detail survives) and keeps the grid from crawling when the camera
// moves. The displacement in vertex() stays smooth -- that is real shape, not texture.
uniform float texel_metres : hint_range(0.0, 0.5, 0.005) = 0.05;
group_uniforms;

group_uniforms Regions;
// Metres per blend feature. This is the size of a "dry patch", and it wants to be big -- a couple
// of building widths -- or the two mud sets average into a third texture instead of reading as two.
uniform float region_metres : hint_range(2.0, 60.0, 0.5) = 17.0;
uniform float dry_bias : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float region_contrast : hint_range(0.5, 8.0, 0.1) = 2.2;
group_uniforms;

group_uniforms Weeds;
uniform vec4 weed_color : source_color = vec4(0.42, 0.44, 0.20, 1.0);
uniform float weed_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float weed_metres : hint_range(1.0, 30.0, 0.5) = 7.0;
// Above this the weed mask is 1. Raising it shrinks the patches without softening their edges,
// which is what a trodden camp looks like: bare mud with islands of scrub, not a gradient.
uniform float weed_threshold : hint_range(0.0, 1.0, 0.01) = 0.62;
group_uniforms;

group_uniforms Shape;
// Metres of relief between the high ground and the hollows. The mesh carries a vertex every ~11 cm,
// so keep the wavelength (shape_metres) far above that or the displacement turns into noise.
uniform float relief : hint_range(0.0, 3.0, 0.01) = 0.55;
uniform float shape_metres : hint_range(3.0, 60.0, 0.5) = 13.0;
// How much of the relief sits BELOW the plane. At 0.8 the ground mostly dips away from y = 0, which
// is what lets the scene use a flat collider without the player being buried by a mound.
uniform float sink : hint_range(0.0, 1.0, 0.01) = 0.8;
group_uniforms;

group_uniforms Water;
uniform vec4 water_tint : source_color = vec4(0.24, 0.27, 0.24, 1.0);
uniform float water_level : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float water_softness : hint_range(0.01, 0.4, 0.01) = 0.06;
uniform float water_darken : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float water_specular : hint_range(0.0, 1.0, 0.01) = 0.55;
group_uniforms;

group_uniforms Light;
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float bands : hint_range(0.0, 8.0, 1.0) = 4.0;
uniform float band_softness : hint_range(0.01, 1.0, 0.01) = 0.07;
uniform vec4 shade_tint : source_color = vec4(0.6, 0.46, 0.4, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float shade_saturation : hint_range(0.0, 2.0, 0.05) = 1.3;
uniform float shade_occlusion : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform vec4 light_tint : source_color = vec4(1.0, 0.92, 0.74, 1.0);
uniform float light_tint_amount : hint_range(0.0, 1.0, 0.05) = 0.45;
group_uniforms;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec3 world_pos;
varying float ao_term;
varying float wet_term;

vec2 quantize2(vec2 v, float step_size) {
	return step_size > 0.0 ? (floor(v / step_size) + 0.5) * step_size : v;
}

vec3 saturate_rgb(vec3 c, float amount) {
	return mix(vec3(dot(c, LUMA)), c, amount);
}

// Value noise on a hashed lattice. A texture fetch would be one more file to import correctly and
// this is called at four different scales; the arithmetic is cheaper than the bookkeeping.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Three octaves. Four is not visibly better at this camera height and this one runs per vertex on
// a 147,000-quad plane as well as per fragment.
float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.13) * 0.3 + value_noise(p * 4.31) * 0.15;
}

// The ground's shape, in [0, 1]. Everything -- displacement, the normal, and where the water sits --
// reads this one function, which is what keeps the puddles in the hollows.
float shape(vec2 xz) {
	return fbm(xz / max(shape_metres, 0.01));
}

void vertex() {
	VERTEX.y += (shape(VERTEX.xz) - sink) * relief;
	world_pos = VERTEX;
}

void fragment() {
	// One snapped coordinate for everything the fragment reads: the mud, the region mask, the weeds
	// and the water all change on the same grid, so a puddle edge lands on a texel boundary instead
	// of cutting diagonally across one.
	vec2 art = quantize2(world_pos.xz, texel_metres);
	vec2 uv = art / max(texture_metres, 0.01);

	// THE GEOMETRIC NORMAL, REBUILT. The mesh was displaced in vertex() but its NORMAL attribute
	// still points straight up, so without this the rolling ground would be lit as a flat plane.
	// Central differences on the same field, at roughly one vertex spacing.
	float e = 0.12;
	float hx = shape(world_pos.xz + vec2(e, 0.0)) - shape(world_pos.xz - vec2(e, 0.0));
	float hz = shape(world_pos.xz + vec2(0.0, e)) - shape(world_pos.xz - vec2(0.0, e));
	vec3 ground_n = normalize(vec3(-hx * relief, 2.0 * e, -hz * relief));

	// Which mud is here.
	float region = fbm(art / max(region_metres, 0.01));
	region = clamp((region - 0.5 + dry_bias) * region_contrast + 0.5, 0.0, 1.0);

	vec4 wet_tex = texture(mud_color, uv) * mud_tint;
	vec4 dry_tex = texture(dry_color, uv * 1.37 + vec2(0.31, 0.17)) * dry_tint;
	vec3 base = mix(wet_tex.rgb, dry_tex.rgb, region);
	if (texture_desaturate > 0.0) {
		base = mix(base, vec3(dot(base, LUMA)), texture_desaturate);
	}

	float ao = mix(texture(mud_ao, uv).r, texture(dry_ao, uv * 1.37 + vec2(0.31, 0.17)).r, region);
	ao = mix(1.0, ao, ao_strength);

	// Weeds: a hard-edged mask, not a gradient -- see weed_threshold.
	// Rotated off the world axes: value noise sits on an axis-aligned lattice, and a hard threshold
	// across it produces patches with visibly straight, square edges -- they read as spilled paint
	// rather than as scrub. A 31 degree turn costs two multiplies and hides the grid.
	vec2 wrot = mat2(vec2(0.857, 0.515), vec2(-0.515, 0.857)) * art;
	float weeds = smoothstep(weed_threshold, weed_threshold + 0.2,
			fbm(wrot / max(weed_metres, 0.01) + 31.7));
	// Kept off the steepest ground and out of the water, both of which is where it will not grow.
	weeds *= smoothstep(0.55, 0.9, ground_n.y) * weed_amount;
	base = mix(base, base * 0.6 + weed_color.rgb * 0.9, weeds);

	// Water, in the hollows of the same field the mesh was displaced by.
	float h = shape(art);
	float wet = 1.0 - smoothstep(water_level - water_softness, water_level + water_softness, h);
	wet *= 1.0 - weeds;
	wet_term = wet;
	base = mix(base, mix(base * (1.0 - water_darken), water_tint.rgb, 0.4), wet);

	ao_term = ao;
	ALBEDO = base * ao;

	// The surface normal is the ground's shape plus the mud's own grain, flattened under water.
	vec3 tex_n = mix(texture(mud_normal, uv).rgb,
			texture(dry_normal, uv * 1.37 + vec2(0.31, 0.17)).rgb, region) * 2.0 - 1.0;
	tex_n.xy *= normal_strength * (1.0 - wet);
	// The plane's tangent frame is the world axes, so the grain can be added to the ground normal
	// directly rather than through a tangent-space transform that would be the identity anyway.
	vec3 n = normalize(ground_n + vec3(tex_n.x, 0.0, tex_n.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	SPECULAR = water_specular * wet;
	ROUGHNESS = mix(1.0, 0.1, wet);
}

void light() {
	float l = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	if (bands >= 1.0) {
		float m = l * bands;
		float b = floor(m);
		l = (b + smoothstep(0.5 - band_softness, 0.5 + band_softness, m - b)) / bands;
	}
	vec3 shadow_side = saturate_rgb(ALBEDO * shade_tint.rgb, shade_saturation) * shade_strength;
	shadow_side *= mix(1.0, ATTENUATION, shade_occlusion);
	vec3 lit_side = mix(ALBEDO, ALBEDO * light_tint.rgb, light_tint_amount);
	DIFFUSE_LIGHT += mix(shadow_side, lit_side, l) * (LIGHT_COLOR / PI) * mix(1.0, ao_term, 0.6);
}
