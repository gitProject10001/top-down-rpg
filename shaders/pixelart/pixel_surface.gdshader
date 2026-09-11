shader_type spatial;
render_mode world_vertex_coords;
// ENVIRONMENT SURFACES for the pixel-art camp. A copy of shaders/painted_env.gdshader -- its
// wrapped lambert, banding, coloured shadows, parallax occlusion and stochastic de-tiling are all
// still here and still correct -- with the four things this scene needs that the original
// deliberately does not have. painted_env is NOT edited; the reasoning below says where the two
// part company and why.
//
//   1. A SEPARATE AO MAP. painted_env's header explains that cavity darkening is multiplied into
//      the albedo in the .blend, so a second sampler would double it. That is true of assets that
//      came from that pipeline. It is not true of assets/textures/whinbek/*, which ship a real
//      _ao.png next to the colour and whose colour map has no cavity baked in -- so here the map
//      is the only source of that darkening and has to be sampled.
//
//   2. VERTEX DISPLACEMENT. painted_env has parallax, which is the SHADING of depth; it moves
//      texels, never the silhouette. Cart ruts read as ruts only if the ground's edge against a
//      barrel actually bends. Godot has no tessellation stage, so displacement here means a mesh
//      subdivided at author time and moved in vertex() -- the ground plane carries 384x384
//      subdivisions for exactly this. Where a surface has no vertices to move, leave displace at 0
//      and let parallax do the cheaper job.
//
//   3. TRIPLANAR. tools/blender/propkit.py exports no UVs -- every prop in assets/models/camp is
//      flat-coloured geometry. Triplanar world-space projection is what lets those props take the
//      same tiling PBR sets as the hand-UV'd surfaces without anyone unwrapping anything. The
//      blend follows shaders/dungeon_stone.gdshader, which solved this first.
//
//   4. WETNESS. painted_env pins SPECULAR to 0 and ROUGHNESS to 1 on purpose -- its header records
//      that specular was measured to be the source of the plastic look on matte surfaces. Mud
//      holding water is not a matte surface, and the reference is full of puddles. So the sheen is
//      here, but it is GATED BY THE HEIGHT MAP: only the low spots get it, which is where water
//      actually collects. A surface with wet_amount at 0 behaves exactly like painted_env.

group_uniforms Albedo;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool use_vertex_color = false;
// PULL THE TEXTURE TOWARD ITS OWN LUMINANCE BEFORE TINTING, so albedo_color decides the hue and the
// texture only supplies the PATTERN.
//
// This exists because of fabric_pattern_07, whose mean is linear (0.606, 0.350, 0.333) -- a strong
// pink. Cancelling a cast like that with a tint means solving three channels simultaneously by eye,
// and every attempt overshoots in a different direction: the camp canvas went scarlet, then cold
// grey, then orange, across three renders. At 1.0 the texture becomes a grey weave, its mean drops
// to its luminance (0.403 for this set), and albedo_color is then simply the colour of the cloth --
// which can be reasoned about instead of guessed.
uniform float texture_desaturate : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float alpha_cut : hint_range(0.0, 1.0, 0.01) = 0.0;
group_uniforms;

group_uniforms Tiling;
// UV path only. The triplanar path uses triplanar_scale instead, because a world-space projection
// has no UV to transform.
uniform vec2 uv1_scale = vec2(1.0);
uniform vec2 uv1_offset = vec2(0.0);
// WORLD-SPACE PROJECTION for meshes with no UVs (everything propkit builds). Off by default so a
// properly unwrapped mesh is unaffected.
uniform bool triplanar = false;
uniform float triplanar_scale : hint_range(0.02, 8.0, 0.01) = 0.5;
// How sharply the three projections cut over. Low is a soft three-way blend (good on rounded
// forms); high is nearly a hard pick per face (good on boxes, and cheaper to read).
uniform float triplanar_sharpness : hint_range(1.0, 16.0, 0.5) = 6.0;
group_uniforms;

group_uniforms Pixelation;
// THE ART TEXEL, and this is where the pixel-art character of a surface comes from now.
//
// Screen-space pixelation -- rendering small and scaling up -- puts the whole image on one lattice,
// which is faithful to how pixel art is MADE, but it pays for that with every pixel of geometric
// detail. The reference is high-resolution pixel art: it is a dense image, with plank ends and
// straw and single-pixel highlights that a 640x360 buffer simply cannot hold. Rendering coarse
// enough to look chunky threw all of that away.
//
// Quantising in SURFACE space instead keeps both. The render stays high resolution, so silhouettes,
// outlines and small props stay sharp; but every texture lookup is snapped to a fixed grid measured
// in METRES, so a wall is built out of square blocks of colour of a consistent real-world size, the
// way a pixel artist paints one. Because the grid is fixed to the surface rather than to the screen,
// it also cannot crawl when the camera moves -- which is the failure mode screen-space pixelation
// spends a camera-snapping routine trying to avoid.
//
// MEASURED RESULT: THIS IS OFF IN EVERY CAMP MATERIAL, AND THE REASON IS WORTH KEEPING.
//
// It was tried at 0.05 m across the whole scene. It does produce chunky painted blocks -- and it
// destroys exactly what this shader exists to carry. Snapping the sampling coordinate snaps the
// NORMAL and AO lookups with it, so each block becomes one flat colour with no relief inside it:
// the normal map, the ambient occlusion and the parallax all stop varying below the texel, which is
// where nearly all of their detail lives. Up close it is worse still, because the texel is a fixed
// size in METRES rather than in pixels, so approaching a wall grows the blocks without bound.
//
// The pixel character of this scene comes from the render resolution instead -- one screen pixel is
// one art pixel, and every one of them is free to differ from its neighbour by whatever the normal
// map says. The detail loss that first prompted this uniform was the 640x360 buffer, not the place
// the quantisation happened; raising the buffer fixed it without costing any relief.
//
// Left in because it is the right tool for a surface deliberately meant to read as chunky at a
// fixed camera distance. One texel should land on two to four screen pixels; at this framing that
// is about 0.05 m. 0 disables it, and 0 is the default for good reason.
uniform float texel_metres : hint_range(0.0, 0.5, 0.005) = 0.0;
// The same idea for the UV path, in UV units, because a UV-mapped surface has no world scale to
// measure against. Canvas is the only thing in the camp that uses it.
uniform float texel_uv : hint_range(0.0, 0.2, 0.002) = 0.0;
group_uniforms;

group_uniforms Relief;
uniform bool use_normal_map = false;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_strength : hint_range(0.0, 4.0, 0.05) = 1.0;

uniform sampler2D height_texture : hint_default_black;
// PARALLAX: shading of depth, no vertices needed, angle-dependent.
uniform bool use_parallax = false;
uniform float parallax_depth : hint_range(0.0, 0.2, 0.001) = 0.03;
uniform int parallax_steps : hint_range(4, 48) = 20;
// DISPLACEMENT: real depth, needs a subdivided mesh. Metres. 0 disables it and costs nothing.
uniform float displace : hint_range(0.0, 2.0, 0.005) = 0.0;
// Where the height map's "sea level" sits, so a surface can be pushed both in and out rather than
// only outward from its authored plane.
uniform float displace_mid : hint_range(0.0, 1.0, 0.01) = 0.5;
// DISPLACEMENT TILES COARSER THAN ALBEDO, and this is the knob that makes displacement usable at
// all. The ground tiles its colour every ~2 m; its mesh carries a vertex every ~11 cm. Sampling
// height at the albedo's rate asks the mesh to reproduce detail four times finer than its own
// spacing, which does not come out as detail -- it comes out as noise that swims when the camera
// moves. Multiplying the UV DOWN for the vertex lookup puts the displaced wavelength safely above
// the vertex spacing and leaves the fine grain to the normal map, which can actually carry it.
uniform float displace_tiling : hint_range(0.01, 4.0, 0.01) = 1.0;

uniform bool use_ao_map = false;
uniform sampler2D ao_texture : hint_default_white;
uniform float ao_strength : hint_range(0.0, 2.0, 0.05) = 1.0;

uniform float detile : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float detile_scale : hint_range(0.01, 1.0, 0.01) = 0.12;
group_uniforms;

group_uniforms Wetness;
// 0 keeps painted_env's matte contract exactly. Above 0, the low ground gets damp.
uniform float wet_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
// Height below which the surface counts as a hollow. Compared against the same height map the
// displacement uses, so puddles land in the dips the geometry actually has.
uniform float wet_level : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float wet_softness : hint_range(0.01, 0.5, 0.01) = 0.12;
uniform vec4 wet_tint : source_color = vec4(0.36, 0.38, 0.34, 1.0);
uniform float wet_darken : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float wet_specular : hint_range(0.0, 1.0, 0.01) = 0.5;
group_uniforms;

group_uniforms Light;
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.35;
// Above 1 the light is posterised into that many steps. This scene WANTS them -- the pixel-art
// read comes from flat tonal plates carrying detailed texture, which is the opposite of the
// painterly default of 0.
uniform float bands : hint_range(0.0, 8.0, 1.0) = 4.0;
uniform float band_softness : hint_range(0.01, 1.0, 0.01) = 0.06;
group_uniforms;

group_uniforms Shadow;
uniform vec4 shade_tint : source_color = vec4(0.58, 0.47, 0.42, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float shade_saturation : hint_range(0.0, 2.0, 0.05) = 1.25;
uniform float shade_occlusion : hint_range(0.0, 1.0, 0.05) = 1.0;
group_uniforms;

group_uniforms Sunlight;
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

vec2 quantize2(vec2 v, float step_size) {
	return step_size > 0.0 ? (floor(v / step_size) + 0.5) * step_size : v;
}

vec3 quantize3(vec3 v, float step_size) {
	return step_size > 0.0 ? (floor(v / step_size) + 0.5) * step_size : v;
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec4 tri_sample(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

// Whiteout blend: the three tangent-space samples are re-based onto the geometric normal before
// they are mixed, so a triplanar normal map does not flatten where two projections meet.
vec3 tri_normal(sampler2D tex, vec3 p, vec3 w, vec3 n, float strength) {
	vec3 nx = texture(tex, p.zy).rgb * 2.0 - 1.0;
	vec3 ny = texture(tex, p.xz).rgb * 2.0 - 1.0;
	vec3 nz = texture(tex, p.xy).rgb * 2.0 - 1.0;
	nx.xy *= strength;
	ny.xy *= strength;
	nz.xy *= strength;
	nx = vec3(nx.xy + n.zy, abs(nx.z) * n.x);
	ny = vec3(ny.xy + n.xz, abs(ny.z) * n.y);
	nz = vec3(nz.xy + n.xy, abs(nz.z) * n.z);
	return normalize(nx.zyx * w.x + ny.xzy * w.y + nz.xyz * w.z);
}

float height_at(vec2 uv, vec3 p, vec3 w) {
	return triplanar ? tri_sample(height_texture, p, w).r : texture(height_texture, uv).r;
}

// textureLod, because vertex() has no derivatives to pick a mip with and plain texture() there is
// undefined. Level 0 is also what you want: displacing from a blurred mip loses the ruts.
float height_at_lod(vec2 uv, vec3 p, vec3 w) {
	if (triplanar) {
		return textureLod(height_texture, p.zy, 0.0).r * w.x
			+ textureLod(height_texture, p.xz, 0.0).r * w.y
			+ textureLod(height_texture, p.xy, 0.0).r * w.z;
	}
	return textureLod(height_texture, uv, 0.0).r;
}

void vertex() {
	// world_vertex_coords: VERTEX and NORMAL are already world space here, which is what the
	// triplanar projection needs and saves reconstructing it from MODEL_MATRIX.
	world_pos = VERTEX;
	world_nrm = NORMAL;

	if (displace > 0.0) {
		vec2 uv = UV * uv1_scale * displace_tiling + uv1_offset;
		vec3 p = VERTEX * triplanar_scale * displace_tiling;
		vec3 w = tri_weights(normalize(NORMAL));
		float h = height_at_lod(uv, p, w) - displace_mid;
		VERTEX += NORMAL * h * displace;
		world_pos = VERTEX;
	}
}

void fragment() {
	vec3 geo_n = normalize(world_nrm);
	vec3 tri_w = tri_weights(geo_n);
	// SNAP THE SAMPLING COORDINATE, NOT THE GEOMETRY. Quantising here means every texture read
	// below -- albedo, normal, ao, the height the wetness test uses -- lands on the same art texel,
	// so a block of colour and its lighting normal change together and the surface reads as one
	// painted pixel rather than as a smooth normal wearing a blocky colour. The vertex displacement
	// in vertex() is deliberately left smooth: that is real shape, and stair-stepping it would put
	// facets on the silhouette.
	vec3 tri_p = quantize3(world_pos, texel_metres) * triplanar_scale;
	vec2 uv = quantize2(UV * uv1_scale + uv1_offset, texel_uv);

	// PARALLAX first, so albedo and normal stay on the same texel and agree about where the
	// surface is. UV path only -- a triplanar surface has three of them and no single tangent
	// frame to march along, and the props that use triplanar are the ones seen from above anyway.
	if (use_parallax && !triplanar) {
		uv = UV * uv1_scale + uv1_offset;
		vec3 vdir = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL)));
		float lean = clamp(1.0 - abs(vdir.z), 0.0, 1.0);
		int steps = int(mix(4.0, float(parallax_steps), lean));
		float layer = 1.0 / float(steps);
		vec2 step_uv = (vdir.xy / max(abs(vdir.z), 0.15)) * parallax_depth * layer;
		float depth = 0.0;
		vec2 cur = uv;
		float h = texture(height_texture, cur).r;
		for (int i = 0; i < steps; i++) {
			if (depth >= 1.0 - h) {
				break;
			}
			cur -= step_uv;
			h = texture(height_texture, cur).r;
			depth += layer;
		}
		vec2 prev = cur + step_uv;
		float after = (1.0 - h) - depth;
		float before = (1.0 - texture(height_texture, prev).r) - depth + layer;
		uv = quantize2(mix(cur, prev, clamp(after / max(after - before, 0.0001), 0.0, 1.0)), texel_uv);
	}

	vec4 tex = triplanar ? tri_sample(albedo_texture, tri_p, tri_w) : texture(albedo_texture, uv);

	// DE-TILING: a second tap at a different scale and offset, cross-faded by a low-frequency mask
	// built from the same coordinate. The two copies never align, so the repeat stops being a grid.
	if (detile > 0.0) {
		vec2 c = (triplanar ? tri_p.xz : uv) * detile_scale;
		float m = sin(c.x * 1.7 + c.y * 2.3) + sin(c.x * -2.9 + c.y * 1.1) + sin(c.x * 0.6 - c.y * 3.7);
		m = smoothstep(-0.6, 0.6, m * 0.5) * detile;
		vec4 other = triplanar
			? tri_sample(albedo_texture, tri_p * 0.77 + vec3(0.37, 0.61, 0.23), tri_w)
			: texture(albedo_texture, uv * 0.77 + vec2(0.37, 0.61));
		tex = mix(tex, other, m);
	}

	if (alpha_cut > 0.0 && tex.a < alpha_cut) {
		discard;
	}

	if (texture_desaturate > 0.0) {
		tex.rgb = mix(tex.rgb, vec3(dot(tex.rgb, LUMA)), texture_desaturate);
	}
	vec3 base = (tex * albedo_color).rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}

	// AMBIENT OCCLUSION. Multiplied into albedo AND carried into light() -- see the header for why
	// this shader samples a map painted_env does not. AO is a linear mask, so the sampler carries
	// no source_color hint and the red channel is read directly.
	float ao = 1.0;
	if (use_ao_map) {
		ao = triplanar ? tri_sample(ao_texture, tri_p, tri_w).r : texture(ao_texture, uv).r;
		ao = mix(1.0, ao, ao_strength);
	}
	ao_term = ao;
	base *= ao;

	// WETNESS, gated by the same height field the displacement moved: water sits in the hollows.
	float wet = 0.0;
	if (wet_amount > 0.0) {
		float h = height_at(uv, tri_p, tri_w);
		wet = (1.0 - smoothstep(wet_level - wet_softness, wet_level + wet_softness, h)) * wet_amount;
	}
	base = mix(base, mix(base * (1.0 - wet_darken), wet_tint.rgb, 0.35), wet);

	ALBEDO = base;

	if (use_normal_map) {
		if (triplanar) {
			// A triplanar normal comes out in WORLD space, which NORMAL_MAP (tangent space) cannot
			// take -- so it is converted to view space and written to NORMAL directly. Flattened
			// toward the geometric normal inside a puddle: still water has no grain.
			vec3 wn = tri_normal(normal_texture, tri_p, tri_w, geo_n, normal_strength);
			wn = normalize(mix(wn, geo_n, wet));
			NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		} else {
			NORMAL_MAP = texture(normal_texture, uv).rgb;
			NORMAL_MAP_DEPTH = normal_strength * (1.0 - wet);
		}
	}

	// painted_env's matte contract, restored exactly wherever the surface is dry.
	SPECULAR = wet_specular * wet;
	ROUGHNESS = mix(1.0, 0.12, wet);
}

void light() {
	// (1) wrapped lambert -- remapped, not clamped, so light carries past the terminator
	float l = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;

	if (bands >= 1.0) {
		float m = l * bands;
		float b = floor(m);
		l = (b + smoothstep(0.5 - band_softness, 0.5 + band_softness, m - b)) / bands;
	}

	// (2)+(3) the shadow keeps the surface colour, shifted and saturated rather than darkened...
	vec3 shadow_side = saturate_rgb(ALBEDO * shade_tint.rgb, shade_saturation) * shade_strength;
	// ...but gated by the shadow map, or it becomes a light source that walls cannot stop.
	shadow_side *= mix(1.0, ATTENUATION, shade_occlusion);
	// (4) the lit side warms toward the sun's own colour
	vec3 lit_side = mix(ALBEDO, ALBEDO * light_tint.rgb, light_tint_amount);

	// AO belongs on the DIRECT term too, not only in the albedo: a cavity that is merely painted
	// dark still catches a full lambert response and reads as a dark surface facing the sun rather
	// than as a recess. Softened, because a baked map is an ambient estimate, not a shadow.
	DIFFUSE_LIGHT += mix(shadow_side, lit_side, l) * (LIGHT_COLOR / PI) * mix(1.0, ao_term, 0.6);
}
