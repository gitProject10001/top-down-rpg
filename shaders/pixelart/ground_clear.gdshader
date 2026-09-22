shader_type spatial;
#include "res://shaders/pixelart/meadow_field.gdshaderinc"
uniform sampler2D art_coverage : filter_linear, repeat_disable;
uniform vec2 art_coverage_center = vec2(0.0);
uniform vec2 art_coverage_size = vec2(152.0,144.0);
uniform bool use_art_coverage = false;
render_mode world_vertex_coords;
// Opt-in art study. The original material is preserved when disabled.
uniform bool anime_painted = false;
uniform sampler2D meadow_painting : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D path_painting : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D brush_normal : filter_linear_mipmap, repeat_enable;

// THE GROUND, AND WHY IT IS NOT JUST A TILED TEXTURE.
//
// The village sits on one hand-painted image (ground_painting.png): a crossroads, worn dirt, tufts
// of grass. That painting is the quality bar, and it covers 32 metres. Everything past it used to
// be procedural colour noise, which at any distance read as a checkerboard of olive squares.
//
// So the ground outside the painting is now the SAME KIND OF MATERIAL, drawn from a painted layer
// atlas, tiled by the Heitz-Neyret histogram-preserving scheme rather than by repetition:
//
//   1. World XZ is skewed onto a triangular lattice. Every point falls inside one triangle.
//   2. Each of the triangle's three vertices carries its own random offset AND rotation into the
//      source image, so no two triangles read the same patch.
//   3. The three samples are blended by barycentric weight, but VARIANCE-PRESERVING: subtract the
//      texture mean, divide by sqrt(sum of squared weights), add the mean back. A plain weighted
//      average would wash the brushwork into mush exactly where the triangles meet, which is the
//      whole reason naive stochastic tiling looks soft.
//   4. textureGrad, not texture. fract() on the UV makes the implicit derivative explode at every
//      wrap, and the mip selector turns that into a visible grid of blurred seams.
//
// The lattice has no preferred axis, so there is nothing for the eye to lock onto — which is the
// failure mode of the square-grid value noise this replaced.
//
// GROWING THE WORLD. Everything here is in world space, so the material does not care how big the
// ground is, and scripts/village/terrain.gd keeps the mesh and its collider the same size. Nothing
// below is tied to the current extent.

// --- the painted crossroads, stamped where the village stands -------------------------------
uniform sampler2D painting : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 painting_center = vec2(0.0, 3.0);
uniform float painting_size : hint_range(1.0, 128.0) = 32.0;
uniform float border_blend : hint_range(0.01, 0.4) = 0.16;

// --- the painted layer atlas: one row, three columns (grass | dirt | gravel) -----------------
uniform sampler2D layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// World size of one tile of grass, and of one tile of road surface.
uniform float grass_metres : hint_range(1.0, 40.0) = 2.5;
uniform float road_metres : hint_range(1.0, 40.0) = 6.0;
// THE ATLAS IS NOT THE PAINTING, and left raw it reads brighter and yellower than the village it
// has to sit next to. Each grade maps one atlas column onto the mean of the matching part of the
// painting — grass onto its green-dominant pixels, dirt onto its paths, both measured after the
// 0.62/0.59/0.55 grade the stamp itself gets. That is what makes the join at the border
// invisible. Gravel keeps its own grey and is only matched in brightness.
//
// NO source_color HINT ON THESE. They are multipliers, not colours: the hint would have Godot read
// them as sRGB and convert, which cubes a 0.35 into a 0.1 and drops the whole field into shadow
// while the stamp stays lit. That is exactly what it looked like.
uniform vec3 grass_grade = vec3(0.62, 0.59, 0.55);
uniform vec3 dirt_grade = vec3(0.50, 0.70, 0.88);
uniform vec3 gravel_grade = vec3(0.62, 0.74, 0.90);

// MEANS OF THE ATLAS COLUMNS, in LINEAR space, measured off the file. Not art direction: the
// variance-preserving blend needs the true mean or it pushes the result off-colour. Re-measure
// these if terrain_layers.png is ever repainted.
const vec3 GRASS_MEAN = vec3(0.1304, 0.1090, 0.0288);
const vec3 DIRT_MEAN = vec3(0.2749, 0.1439, 0.0474);
const vec3 GRAVEL_MEAN = vec3(0.1817, 0.1324, 0.0881);
const float COLUMNS = 3.0;
// Each column is three times taller than it is wide, so a SQUARE patch of world is a third of the
// column's height. Getting this wrong stretches every blade of grass by 3:1.
const float COLUMN_ASPECT = 3.0;
// Keeps a mip tap from bleeding into the neighbouring column.
const float COLUMN_INSET = 0.002;
const vec3 LUMA = vec3(0.299, 0.587, 0.114);

// --- macro variation, so 400 metres of grass is not 400 metres of one colour ------------------
uniform float macro_metres : hint_range(10.0, 400.0) = 90.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec3 dry_tint : source_color = vec3(0.78, 0.74, 0.46);
uniform vec3 lush_tint : source_color = vec3(0.46, 0.60, 0.30);
// How much bare earth wears through the grass, and over how many metres it varies.
uniform float wear_amount : hint_range(0.0, 1.0) = 0.85;
uniform float wear_metres : hint_range(5.0, 200.0) = 22.0;
uniform float gravel_amount : hint_range(0.0, 1.0) = 0.55;

// --- the control map: where roads and lusher grass go ----------------------------------------
// R = dirt road, G = gravel, B = lush grass. Linear data, never albedo.
uniform sampler2D road_mask : filter_linear, repeat_disable;
uniform bool use_road_mask = false;
uniform bool builder_layout = false;
uniform mat4 builder_inverse;
uniform vec2 road_mask_center = vec2(0.0);
uniform vec2 road_mask_size = vec2(100.0);
uniform float road_edge_noise : hint_range(0.0, 0.3) = 0.08;

varying vec3 world_position;
uniform vec2 exploration_points[32];
uniform int exploration_count = 0;
uniform vec3 exploration_clearing = vec3(0.0);


// --- noise ------------------------------------------------------------------------------------

float hash_ground(vec2 cell) {
	vec3 h = fract(vec3(cell.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float ground_noise(vec2 pos) {
	vec2 cell = floor(pos);
	vec2 f = fract(pos);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_ground(cell), hash_ground(cell + vec2(1, 0)), f.x),
			mix(hash_ground(cell + vec2(0, 1)), hash_ground(cell + vec2(1, 1)), f.x), f.y);
}

// Four octaves, each ROTATED against the last. Without the rotation the octaves share the value
// noise's axes and the sum keeps the square grid the old material was made of.
float fbm(vec2 pos) {
	const mat2 turn = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float sum = 0.0;
	float gain = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += ground_noise(pos) * gain;
		pos = turn * pos * 2.03;
		gain *= 0.5;
	}
	return sum / 0.9375;
}


// --- stochastic tiling -------------------------------------------------------------------------

// Two independent randoms per lattice vertex: where to look in the image, and how to turn it.
vec3 vertex_random(vec2 cell) {
	return vec3(hash_ground(cell + vec2(17.3, 5.1)),
			hash_ground(cell + vec2(3.7, 29.9)),
			hash_ground(cell + vec2(43.1, 11.2)));
}

// The triangular lattice of Heitz & Neyret 2018: skew world space so each cell splits into two
// triangles, then report which three vertices bound this point and how much each one weighs.
void triangle_grid(vec2 uv, out vec3 w, out vec2 v1, out vec2 v2, out vec2 v3) {
	const mat2 skew = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054));
	vec2 skewed = skew * uv;
	vec2 base = floor(skewed);
	vec3 temp = vec3(fract(skewed), 0.0);
	temp.z = 1.0 - temp.x - temp.y;
	if (temp.z > 0.0) {
		w = vec3(temp.z, temp.y, temp.x);
		v1 = base;
		v2 = base + vec2(0.0, 1.0);
		v3 = base + vec2(1.0, 0.0);
	} else {
		w = vec3(-temp.z, 1.0 - temp.y, 1.0 - temp.x);
		v1 = base + vec2(1.0, 1.0);
		v2 = base + vec2(1.0, 0.0);
		v3 = base + vec2(0.0, 1.0);
	}
}

// One column of the atlas. u wraps across the column's width, v across its height, and because the
// column is COLUMN_ASPECT taller than wide, a unit step in v covers that many square patches.
vec2 column_uv(vec2 uv, float column) {
	float u = mix(COLUMN_INSET, 1.0 - COLUMN_INSET, fract(uv.x));
	float v = fract(uv.y / COLUMN_ASPECT);
	return vec2((column + u) / COLUMNS, v);
}

vec3 tap(vec2 uv, vec2 ddx, vec2 ddy, vec3 rnd, float column) {
	float angle = rnd.z * 6.2831853;
	float cs = cos(angle);
	float sn = sin(angle);
	mat2 turn = mat2(vec2(cs, sn), vec2(-sn, cs));
	vec2 t = turn * uv + rnd.xy;
	vec2 dx = turn * ddx;
	vec2 dy = turn * ddy;
	if (column < 0.5) {
		// Sample a grass-only region of the village painting. Mirrored coordinates
		// stay continuous at wrapping boundaries; this crop excludes the crossroads.
		vec2 mirrored = 1.0 - abs(mod(t, 2.0) - 1.0);
		vec2 crop_size = vec2(0.22, 0.22);
		vec2 sign_uv = mix(vec2(1.0), vec2(-1.0), step(vec2(1.0), mod(t, 2.0)));
		return textureGrad(painting, vec2(0.025, 0.025) + mirrored * crop_size,
				dx * sign_uv * crop_size, dy * sign_uv * crop_size).rgb;
	}
	// The derivatives have to be squeezed exactly the way the coordinates were, or the mip
	// selector picks a level for a texture the size of the whole atlas.
	const vec2 squeeze = vec2(1.0 / COLUMNS, 1.0 / COLUMN_ASPECT);
	return textureGrad(layers, column_uv(t, column), dx * squeeze, dy * squeeze).rgb;
}

// The whole point of the file: paint a surface out of one image, forever, with no repeat and no
// loss of contrast.
vec3 stochastic_layer(vec2 pos, vec2 ddx, vec2 ddy, float metres, float column, vec3 mean) {
	vec2 uv = pos / metres;
	vec2 dx = ddx / metres;
	vec2 dy = ddy / metres;
	vec3 w;
	vec2 v1;
	vec2 v2;
	vec2 v3;
	triangle_grid(uv, w, v1, v2, v3);
	if (column < 0.5 || anime_painted) {
		// Each vertex samples a bounded patch, with no wrapping or mirroring.
		// Four independent meadow regions provide different painted features.
		vec3 result = vec3(0.0);
		vec3 weights = pow(w, vec3(anime_painted ? 1.4 : 3.0));
		weights /= max(dot(weights, vec3(1.0)), 0.0001);
		for (int i = 0; i < 3; i++) {
			vec2 vertex = i == 0 ? v1 : (i == 1 ? v2 : v3);
			vec3 rnd = vertex_random(vertex);
			vec2 anchor = vec2(vertex.x + vertex.y * 0.5, vertex.y * 0.8660254);
			float angle = rnd.z * 6.2831853;
			mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
			vec2 corner = step(vec2(0.5), rnd.xy) * 0.75;
			vec2 sample_uv = corner + vec2(0.125) + (rnd.xy - 0.5) * 0.04 + rotation * (uv - anchor) * 0.045;
			if (anime_painted) {
				// Bounded overlapping crops avoid requiring perfectly seamless source edges.
				vec2 brush_uv = vec2(0.5) + (rnd.xy - 0.5) * 0.25 + rotation * (uv - anchor) * 0.22;
				vec3 brush_color;
				if (column < 0.5) {
					brush_color = textureGrad(meadow_painting, brush_uv, rotation * dx * 0.22, rotation * dy * 0.22).rgb;
				} else {
					brush_color = textureGrad(path_painting, brush_uv, rotation * dx * 0.22, rotation * dy * 0.22).rgb;
				}
				result += brush_color * weights[i];
			} else {
				result += textureGrad(painting, sample_uv, rotation * dx * 0.045, rotation * dy * 0.045).rgb * weights[i];
			}
		}
		return result;
	}
	vec3 c1 = tap(uv, dx, dy, vertex_random(v1), column);
	vec3 c2 = tap(uv, dx, dy, vertex_random(v2), column);
	vec3 c3 = tap(uv, dx, dy, vertex_random(v3), column);
	if (column < 0.5) {
		// Prefer one painted sample locally, with smooth overlap at joins.
		// No variance boost: the original brushwork already has the target contrast.
		vec3 weights = pow(w, vec3(4.0));
		weights /= max(weights.x + weights.y + weights.z, 0.0001);
		return c1 * weights.x + c2 * weights.y + c3 * weights.z;
	}
	// Variance preserving: without the divide, the three-way blend halves the standard deviation
	// and every triangle centre turns to flat colour.
	//
	// BUT ONLY WHILE THERE IS DETAIL LEFT TO PRESERVE. Far enough away every tap resolves to a
	// high mip, which IS the texture's mean, so the divide has nothing to rescue and instead
	// amplifies the last scraps of difference by a factor that swings between 1 at a lattice
	// vertex and sqrt(3) at a triangle's centre. That modulation is visible as a faint web of
	// triangles across the whole field. So the correction fades out with the footprint and the
	// distant blend becomes a plain average, which at that range is indistinguishable anyway.
	float footprint = max(length(dx), length(dy));
	float detail = 1.0 - smoothstep(0.05, 0.35, footprint);
	vec3 blended = w.x * (c1 - mean) + w.y * (c2 - mean) + w.z * (c3 - mean);
	blended /= max(mix(1.0, sqrt(dot(w, w)), detail), 0.0001);
	return clamp(blended + mean, vec3(0.0), vec3(1.0));
}

// A tint normalised to carry no brightness of its own, so the macro field changes the season
// rather than the exposure.
vec3 balance(vec3 tint) {
	return tint / max(dot(tint, LUMA), 0.001);
}


void vertex() {
	world_position = VERTEX;
}


void fragment() {
	float brush_surface = 1.0;
	vec2 pos = builder_layout ? (builder_inverse * vec4(world_position, 1.0)).xz : world_position.xz;
	vec2 ddx = dFdx(pos);
	vec2 ddy = dFdy(pos);

	// 1. Painted grass, everywhere, at village quality.
	vec3 ground = stochastic_layer(pos, ddx, ddy, grass_metres, 0.0, GRASS_MEAN) * grass_grade;

	// 2. Macro variation. One low-frequency field decides how dry the grass reads, a second and
	//    slower one decides where the earth has worn through. Both are rotated fbm, so neither
	//    has an axis for the eye to find.
	//
	//    The shift is measured AGAINST THE MIDPOINT of the two tints, not against white. Tinting
	//    toward mix(lush, dry, 0.5) everywhere is not a variation, it is a constant yellow cast
	//    over the whole world, which is what the first pass of this did.
	float dryness = fbm(pos / macro_metres);
	vec3 season = mix(lush_tint, dry_tint, dryness);
	vec3 neutral = mix(lush_tint, dry_tint, 0.5);
	ground *= mix(vec3(1.0), balance(season) / balance(neutral), macro_strength);
	ground *= 1.0 + (dryness - 0.5) * macro_strength * 0.35;

	vec2 domain = pos + vec2(fbm(pos / 17.0), fbm(pos / 19.0 + 37.0)) * 12.0;
	float edge_detail = (fbm(pos * 1.5) - 0.5) * 0.16;
	float wear = smoothstep(0.43, 0.65, fbm(domain / wear_metres + vec2(19.4, 7.7)) + edge_detail) * wear_amount;
	if (wear > 0.002) {
		vec3 earth = stochastic_layer(pos, ddx, ddy, road_metres * 1.6, 1.0, DIRT_MEAN) * dirt_grade;
		ground = mix(ground, earth, wear);
	}
	float stones = smoothstep(0.56, 0.73, fbm(domain / 13.0 + 81.0) + edge_detail) * gravel_amount;
	if (stones > 0.002) {
		vec3 stone = stochastic_layer(pos, ddx, ddy, road_metres * 0.5, 2.0, GRAVEL_MEAN) * gravel_grade;
		ground = mix(ground, stone, stones);
	}

	// 3. The village painting, stamped in its own 45-degree frame. It is the art the rest of the
	//    material is trying to live up to, and it carries the crossroads.
	vec2 q = vec2((pos.x + pos.y) * 0.707107, (pos.y - pos.x) * 0.707107);
	vec2 uv = (q - painting_center) / painting_size + 0.5;
	float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
	// The border wobbles, so the stamp does not end on four straight lines.
	float wobble = (fbm(pos * 0.35) - 0.5) * 0.06;
	float stamp = builder_layout ? 0.0 : smoothstep(0.0, border_blend, edge + wobble);
	vec3 painted = texture(painting, clamp(uv, vec2(0.0), vec2(1.0))).rgb * vec3(0.62, 0.59, 0.55);
	ALBEDO = mix(ground, painted, stamp);
	// Match world_stream.gd: the same corridors exclude vegetation.
	float trail_x = 18.0*sin(pos.y/95.0) + 9.0*sin(pos.y/37.0);
	float distance_to_trail = min(abs(pos.x-trail_x), abs(pos.y-0.35*pos.x-90.0));
	float trail = (1.0-smoothstep(1.7,3.5,distance_to_trail+(fbm(pos*1.3)-0.5)*1.2)) * (1.0-stamp);
	if (!builder_layout && trail > 0.002) {
		vec3 soil = stochastic_layer(pos, ddx, ddy, road_metres, 1.0, DIRT_MEAN)*dirt_grade;
		ALBEDO = mix(ALBEDO,soil,trail);
	}

	// 4. The control map. Roads and lusher grass are painted from the same atlas, so a road is a
	//    painted surface and not a flat brown decal sitting on one.
	if (use_road_mask) {
		vec2 mask_uv = (pos - road_mask_center) / max(road_mask_size, vec2(0.01)) + 0.5;
		float inside = step(0.0, mask_uv.x) * step(0.0, mask_uv.y)
				* step(mask_uv.x, 1.0) * step(mask_uv.y, 1.0);
		vec3 mask = texture(road_mask, mask_uv).rgb * inside;
		// Break the edges so a drawn curve does not read as a drawn curve.
		vec3 ragged = (ground_noise(pos * 1.7) - 0.5) * road_edge_noise * 4.0 * mask * (1.0 - mask);
		mask = clamp(mask + ragged, vec3(0.0), vec3(1.0));

		float dirt = anime_painted ? smoothstep(0.12, 0.82, mask.r + (ground_noise(pos * 4.0) - .5) * .28) : smoothstep(0.05, 0.95, mask.r);
		if (anime_painted && use_art_coverage) {
			vec2 art_uv=(world_position.xz-art_coverage_center)/art_coverage_size+vec2(.5);
			vec4 authored=texture(art_coverage,art_uv);
			dirt=authored.r*inside;
			ALBEDO*=mix(vec3(.91,.98,1.06),vec3(1.05,1.02,.93),authored.b);
            ALBEDO=mix(ALBEDO,meadow_pigment(pos,authored.b),meadow_weight(pos)*meadow_ground_influence*(1.0-authored.r));
		}
		float gravel = smoothstep(0.05, 0.95, mask.g);
		brush_surface *= (1.0-dirt)*(1.0-gravel);
		float lush = smoothstep(0.05, 0.95, mask.b);

		if (lush > 0.002) {
			ALBEDO = mix(ALBEDO, ALBEDO * balance(lush_tint) * 1.02, lush * 0.5);
		}
		if (dirt > 0.002) {
			ALBEDO = mix(ALBEDO,
					stochastic_layer(pos, ddx, ddy, road_metres, 1.0, DIRT_MEAN) * dirt_grade, dirt);
		}
		if (gravel > 0.002) {
			ALBEDO = mix(ALBEDO,
					stochastic_layer(pos, ddx, ddy, road_metres, 2.0, GRAVEL_MEAN) * gravel_grade,
					gravel);
		}
	}

	// Same authored polyline used by decoration exclusion. No second road layout.
	float route_distance = 100000.0;
	for (int i = 0; i < 31; i++) {
		if (i + 1 >= exploration_count) { break; }
		vec2 a = exploration_points[i];
		vec2 ab = exploration_points[i+1] - a;
		float t = clamp(dot(pos-a,ab)/max(dot(ab,ab),0.001),0.0,1.0);
		route_distance = min(route_distance,length(pos-a-ab*t));
	}
	float route_wear = 1.0-smoothstep(1.0,2.6,route_distance+(ground_noise(pos*2.0)-0.5)*0.6);
	float clearing_wear = (1.0-smoothstep(5.0,max(6.0,exploration_clearing.z),length(pos-exploration_clearing.xy)))*0.65;
	if (exploration_count > 1) {
		float amount = max(route_wear,clearing_wear)*(1.0-stamp);
		if (amount > 0.002) {
			vec3 path_soil = stochastic_layer(pos,ddx,ddy,road_metres,1.0,DIRT_MEAN)*dirt_grade;
			ALBEDO = mix(ALBEDO,path_soil,amount);
		}
	}
	if (anime_painted) {
		// Existing submerged vertices receive sandy bed paint, not meadow grass.
		float submerged = 1.0 - smoothstep(-0.08, 0.25, world_position.y + (ground_noise(pos*5.0)-.5)*.09);
		vec3 bed = stochastic_layer(pos, ddx, ddy, road_metres, 1.0, DIRT_MEAN) * vec3(.55,.65,.66);
		ALBEDO = mix(ALBEDO, bed, submerged);
		vec3 painted_normal = texture(brush_normal,world_position.xz/4.581).rgb*2.0-1.0;
		vec3 world_normal = normalize(vec3(painted_normal.x,painted_normal.z,-painted_normal.y));
		NORMAL = normalize(mix(NORMAL, mat3(VIEW_MATRIX)*world_normal, .35*brush_surface*(1.0-submerged)));
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
