shader_type spatial;
render_mode world_vertex_coords;
// DRAWN MASONRY, PLANKS AND SHINGLES -- the shader that makes a surface look painted by a person
// rather than photographed onto a polygon.
//
// WHY A PBR TEXTURE IS NOT ENOUGH, WHICH IS THE WHOLE REASON THIS FILE EXISTS.
// Zoom into the reference art and every stone in the chapel wall is a separate object: a dark
// mortar line all the way round it, a flat fill inside, a lighter band along its top edge, and a
// tone slightly different from the stone next to it. Nothing about that is a photograph. A tiling
// PBR set -- which is what pixel_surface.gdshader uses, and what got this scene most of the way --
// gives the opposite: continuous grain, soft boundaries, and no two adjacent blocks distinguishable
// because the mortar is just another dark smudge among many. At 640-960 px wide, soft boundaries
// read as mud. Hard ones read as masonry.
//
// So the STRUCTURE is drawn here procedurally -- courses, mortar, bevel, per-block tone -- and the
// PBR maps are demoted to what they are actually good at, which is grain INSIDE a block. That is
// the "we already have materials as a starting point" split: the textures still carry the roughness
// of stone and the grain of oak, they just stop being asked to carry the shapes.
//
// THE EDGES ARE HARD ON PURPOSE. Every boundary below is a step(), not a smoothstep(). A pixel
// artist draws a one-pixel line; an antialiased line at this resolution is a two-pixel grey smear,
// and grey smears are what make a render look like a render. The widths are given in METRES and
// chosen so a mortar line lands on about one screen pixel at this scene's framing.
//
// THREE PATTERNS, ONE SHADER, because a wall, a plank stack and a roof differ only in how the grid
// is laid out and the rest -- bevel, tone jitter, grain, the whole lighting model -- is identical.
// Splitting them into three shaders would triple the places a lighting change has to be made.

group_uniforms Pattern;
// 0 = ASHLAR: running-bond courses, every other row offset. Walls, wells, arches.
// 1 = PLANK: long boards, offset along their length, with a groove between each. Doors, counters.
// 2 = SHINGLE: overlapping courses, each row lit along its exposed bottom lip. Roofs.
uniform int pattern : hint_range(0, 2) = 0;
// Block size in METRES: (along the surface, up the surface). A chapel ashlar is about 0.5 x 0.3.
uniform vec2 block_size = vec2(0.52, 0.3);
// Fraction of a block that each course is shifted by. 0.5 is running bond; 0 is a stack bond.
uniform float row_offset : hint_range(0.0, 1.0, 0.05) = 0.5;
// Jitters the offset per course so the wall is not a perfect lattice. 0 for cut ashlar.
uniform float row_jitter : hint_range(0.0, 1.0, 0.01) = 0.15;
group_uniforms;

group_uniforms Ink;
// Mortar/groove half-width in metres. About one screen pixel at this framing.
uniform float mortar : hint_range(0.0, 0.1, 0.002) = 0.022;
uniform vec4 mortar_color : source_color = vec4(0.16, 0.13, 0.11, 1.0);
uniform float mortar_strength : hint_range(0.0, 1.0, 0.01) = 0.85;
// The drawn bevel: a lighter band along the top edge of every block and a darker one along the
// bottom. This is what gives a flat fill the read of a solid object, and it is the single biggest
// difference between this and a photograph.
uniform float bevel : hint_range(0.0, 0.2, 0.002) = 0.03;
uniform float bevel_light : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float bevel_dark : hint_range(0.0, 1.0, 0.01) = 0.28;
group_uniforms;

group_uniforms Irregularity;
// THE GRID HAS TO STOP BEING A GRID, and this is the difference between drawn masonry and the
// mathematical lattice that makes flat-shaded 3D read as late-90s pre-rendered CG.
//
// A perfect running bond gives every course the same height, every block the same width and every
// mortar line the same weight. Nothing built by hand does that, and the eye finds the repeat
// instantly -- it is the same failure as an untreated tiling texture, just drawn instead of
// photographed. Three cheap breaks fix it:
//
//   warp     bends the whole coordinate on a low-frequency noise, so courses are not dead straight
//   width    varies the block length course by course
//   ragged   varies the mortar width per block, so no two joints weigh the same
uniform float grid_warp : hint_range(0.0, 0.3, 0.005) = 0.05;
uniform float grid_warp_metres : hint_range(0.2, 12.0, 0.1) = 3.0;
uniform float width_jitter : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float ragged : hint_range(0.0, 1.0, 0.01) = 0.4;
// A few blocks in every wall are darker than their neighbours -- damp, soot, a different stone.
// Without this a wall is one colour with lines on it, however irregular the lines are.
uniform float dark_block_chance : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float dark_block_amount : hint_range(0.0, 1.0, 0.01) = 0.3;
group_uniforms;

group_uniforms Grime;
// DIRT COLLECTS AT THE BOTTOM OF WALLS. A flat plane meeting flat ground with no transition is the
// "cardboard cutout pasted on a box" read; a metre of grime at the foot of every wall is most of
// what removes it, and it is free because the height above the ground is already in world_pos.
uniform vec4 grime_color : source_color = vec4(0.22, 0.18, 0.14, 1.0);
uniform float grime_height : hint_range(0.0, 5.0, 0.05) = 1.1;
uniform float grime_amount : hint_range(0.0, 1.0, 0.01) = 0.42;
// Blotchy weathering over the whole surface, at a scale unrelated to the block grid so the two
// never line up.
uniform float weather_amount : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float weather_metres : hint_range(0.2, 10.0, 0.1) = 2.4;
group_uniforms;

group_uniforms Surface;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
// How much of the photograph survives INSIDE a block. Low: it is grain, not structure.
uniform float grain : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float grain_metres : hint_range(0.1, 8.0, 0.05) = 1.2;
// Per-block tone jitter. The reference varies every stone; without this a wall is one flat colour
// with lines ruled on it.
uniform float tone_jitter : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform sampler2D normal_texture : hint_normal;
uniform bool use_normal_map = true;
uniform float normal_strength : hint_range(0.0, 3.0, 0.05) = 0.7;
uniform sampler2D ao_texture : hint_default_white;
uniform bool use_ao_map = false;
uniform float ao_strength : hint_range(0.0, 2.0, 0.05) = 0.7;
group_uniforms;

group_uniforms Light;
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform float bands : hint_range(0.0, 8.0, 1.0) = 4.0;
uniform float band_softness : hint_range(0.01, 1.0, 0.01) = 0.05;
uniform vec4 shade_tint : source_color = vec4(0.52, 0.46, 0.5, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float shade_saturation : hint_range(0.0, 2.0, 0.05) = 1.25;
uniform float shade_occlusion : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform vec4 light_tint : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float light_tint_amount : hint_range(0.0, 1.0, 0.05) = 0.4;
group_uniforms;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec3 world_pos;
varying vec3 world_nrm;
varying float ao_term;

vec3 saturate_rgb(vec3 c, float amount) {
	return mix(vec3(dot(c, LUMA)), c, amount);
}

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

float fbm(vec2 p) {
	return value_noise(p) * 0.6 + value_noise(p * 2.17) * 0.28 + value_noise(p * 4.39) * 0.12;
}

// THE DOMINANT-AXIS PROJECTION, rather than a three-way triplanar blend.
//
// A blended triplanar pattern is wrong here even though it is what pixel_surface uses for its
// textures: cross-fading two brick grids produces a region where BOTH are half-visible, which reads
// as a mesh of broken stones rather than as a corner. Every surface this shader lands on is a face
// of a box -- a wall, a roof slope, a plank -- so picking the one axis the face actually points
// along gives a clean grid per face and a hard change at the corner, which is exactly how a drawn
// building behaves.
vec2 surface_coords(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x >= a.y && a.x >= a.z) {
		return vec2(p.z, p.y);      // a wall facing along X: courses run in Z, stack up in Y
	}
	if (a.z >= a.y) {
		return vec2(p.x, p.y);      // a wall facing along Z
	}
	return vec2(p.x, p.z);          // a floor or a roof, seen from above
}

void vertex() {
	world_pos = VERTEX;
	world_nrm = NORMAL;
}

void fragment() {
	vec3 geo_n = normalize(world_nrm);
	vec2 p = surface_coords(world_pos, geo_n);

	// Bend the coordinate before it is gridded: every course, joint and bevel below inherits the
	// wobble, so the wall is irregular as a STRUCTURE rather than having noise added on top of a
	// regular one.
	if (grid_warp > 0.0) {
		vec2 w = vec2(fbm(p / max(grid_warp_metres, 0.01)),
				fbm(p / max(grid_warp_metres, 0.01) + 19.3)) - 0.5;
		p += w * grid_warp * 2.0;
	}

	vec2 size = max(block_size, vec2(0.02));
	// SHINGLES OVERLAP, so their courses are half the height they appear and each row is drawn from
	// the row below. Scaling the vertical period here is the whole difference between a roof and a
	// wall as far as the grid is concerned.
	if (pattern == 2) {
		size.y *= 0.62;
	}

	float row = floor(p.y / size.y);
	// Block length varies course by course. Applied AFTER the row is chosen, so a course keeps a
	// single consistent block size -- which is how a mason works -- rather than every stone in a
	// course being a different length, which reads as rubble.
	float row_width = size.x * (1.0 + (hash21(vec2(row, 2.71)) - 0.5) * width_jitter);
	// Planks run long and offset along their length; ashlar and shingle offset per course.
	float shift = row_offset * row;
	if (row_jitter > 0.0) {
		shift += (hash21(vec2(row, 7.13)) - 0.5) * row_jitter;
	}
	vec2 cell = vec2(floor(p.x / row_width + shift), row);
	vec2 local = vec2(fract(p.x / row_width + shift), fract(p.y / size.y));
	size.x = row_width;

	// Distance to the block edge, in METRES, so mortar and bevel widths mean the same thing on a
	// tall thin plank as on a square ashlar.
	vec2 to_edge = min(local, 1.0 - local) * size;
	float edge = min(to_edge.x, to_edge.y);

	// A plank has no cross joint worth drawing every course -- its grooves run along its length.
	if (pattern == 1) {
		edge = min(to_edge.y, to_edge.x * 3.0);
	}

	// ---- THE DRAWN FILL -----------------------------------------------------------------------
	float tone = (hash21(cell + 3.7) - 0.5) * 2.0;
	vec3 base = albedo_color.rgb * (1.0 + tone * tone_jitter);
	// A minority of blocks are simply darker. Threshold rather than blend: a stone is either the
	// odd one out or it is not.
	float odd = hash21(cell + 11.9);
	base *= 1.0 - step(1.0 - dark_block_chance, odd) * dark_block_amount;

	// Grain from the PBR map, at block-independent scale: this is the only job the photograph has.
	vec3 tex = texture(albedo_texture, p / max(grain_metres, 0.01)).rgb;
	base = mix(base, base * tex * 2.0, grain);

	// ---- THE DRAWN EDGES ----------------------------------------------------------------------
	// step(), not smoothstep(): see the header. A hard line is the point.
	// Per-block mortar weight, so no two joints are drawn with the same pen.
	float joint = mortar * (1.0 + (hash21(cell + 5.3) - 0.5) * ragged * 2.0);
	float is_mortar = 1.0 - step(joint, edge);
	// Top edge lit, bottom edge shadowed. A shingle gets the opposite emphasis -- its exposed lip is
	// at the BOTTOM of the course, which is the edge the sun actually catches on a roof.
	float top = step(1.0 - (bevel / size.y), local.y);
	float bottom = 1.0 - step(bevel / size.y, local.y);
	if (pattern == 2) {
		float t = top;
		top = bottom;
		bottom = t;
	}
	base *= 1.0 + top * bevel_light * (1.0 - is_mortar);
	base *= 1.0 - bottom * bevel_dark * (1.0 - is_mortar);
	base = mix(base, mortar_color.rgb, is_mortar * mortar_strength);

	// ---- GRIME ----------------------------------------------------------------------------------
	if (weather_amount > 0.0) {
		float blotch = fbm(p / max(weather_metres, 0.01) + 47.1);
		base *= 1.0 - smoothstep(0.45, 0.85, blotch) * weather_amount;
	}
	if (grime_amount > 0.0 && grime_height > 0.0) {
		// world_pos.y, not the surface coordinate: dirt is a function of height above the GROUND,
		// and it has to run round a corner without a seam.
		float low = 1.0 - smoothstep(0.0, grime_height, world_pos.y);
		base = mix(base, grime_color.rgb, low * grime_amount);
	}

	float ao = 1.0;
	if (use_ao_map) {
		ao = mix(1.0, texture(ao_texture, p / max(grain_metres, 0.01)).r, ao_strength);
	}
	// The mortar course is a recess, so it occludes whether or not a map says so.
	ao *= 1.0 - is_mortar * 0.35;
	ao_term = ao;

	ALBEDO = base * ao;

	// The grain map still tilts the lighting inside a block; the mortar tilts it at the joint, so a
	// wall lit from the side shows its courses in relief and not only in colour.
	vec3 n = geo_n;
	if (use_normal_map) {
		vec3 tn = texture(normal_texture, p / max(grain_metres, 0.01)).rgb * 2.0 - 1.0;
		vec3 up = abs(geo_n.y) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec3 tangent = normalize(cross(up, geo_n));
		vec3 bitangent = cross(geo_n, tangent);
		n = normalize(geo_n + (tangent * tn.x + bitangent * tn.y) * normal_strength);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
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
