shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// PLASTER OVER STONE, WITH A REAL STEP BETWEEN THEM.
//
// BASE: the shader Godot 4.6 writes for a StandardMaterial3D with an albedo texture, a normal
// map, a roughness texture, ambient occlusion and deep parallax (scene/resources/material.cpp,
// BaseMaterial3D::_update_shader — the same text the Inspector's "Convert to ShaderMaterial"
// hands you). Uniform names, the vertex UV line, the whole parallax block and the output
// assignments are that code. Everything added is inside a block or on a line marked LAYERED.
//
// WHAT WAS ADDED. A second texture set (the stone UNDER the plaster) and a break mask. The mask
// is three things summed: a painted image per wall (a PNG you edit in Krita; the addon writes
// the blank at 32 px/m), a seamless NoiseTexture2D for procedural weathering, and the vertex
// colour's red channel for Blender vertex paint. The plaster's own height map roughens the edge.
//
// THE RECESS IS THE ENGINE'S OWN PARALLAX READING A REAL DISCONTINUITY: where the parallax loop
// sampled `texture(texture_heightmap, ofs).r`, it now samples `height_at(ofs)` = the plaster
// height where plaster stands, the stone height MINUS the plaster thickness where it has gone.
// Nothing else in the loop is touched, so the step at a break edge is exactly what deep
// parallax does with any cliff in a height map — the stone sits behind the plaster edge.
//
// UV CONVENTION: the mesh's UVs are METRES (the Floorplan addon's metric UVs). `uv1_scale` is
// the plaster's tiles per metre as in any StandardMaterial3D; the stone has its own
// `under_uv_scale`; the mask and the noise are addressed in metres directly.
//
// THE MATERIAL IS THE CLASS, THE MESH IS THE INSTANCE. A Material is a shared resource: edit
// the .tres and every wall follows. Per-wall differences go through Godot's own per-instance
// mechanism, `instance uniform` (Inspector: GeometryInstance3D → Instance Shader Parameters;
// script: set_instance_shader_parameter). The docs allow scalars and vectors only — no
// samplers, "use a texture array and an index" — and about 16 per shader. So every Breaks knob
// has a per-instance OFFSET (0 = inherit the material's value) and the painted masks live in
// ONE sheet imported as a Texture2DArray, each wall pointing at its slice by `mask_slot`.
//
// RELIEF SHADOWS. Parallax offsets texels; it casts no shadow, and nothing built in does. The
// documented per-light hook is light(): there the same combined height is marched toward the
// light from the parallax-corrected point, and whatever rises above the ray shadows the pixel —
// stones shadow their neighbours, the plaster edge shadows the stone in a break. Writing
// light() replaces the engine's lighting for this material (docs), so the diffuse line is the
// docs' own Lambert example, times the shadow, plus a small Blinn-Phong specular. Cost: it runs
// once per light per pixel, `relief_shadow_layers` height samples each.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_roughness : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform sampler2D texture_ambient_occlusion : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ao_light_affect : hint_range(0.0, 1.0, 0.01) = 0.0;
// LAYERED: default WHITE, not black — an unassigned plaster height is a flat surface at full
// height, so the stone can sit below it.
uniform sampler2D texture_heightmap : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float heightmap_scale : hint_range(-16.0, 16.0, 0.001) = 8.0;
uniform int heightmap_min_layers : hint_range(1, 64) = 8;
uniform int heightmap_max_layers : hint_range(1, 64) = 32;
uniform vec2 heightmap_flip = vec2(1.0, 1.0);
uniform vec3 uv1_scale = vec3(0.4, 0.4, 0.4);
uniform vec3 uv1_offset = vec3(0.0);

// LAYERED: the layer under the plaster.
group_uniforms Under;
uniform sampler2D under_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D under_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float under_normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform sampler2D under_roughness : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D under_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D under_heightmap : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 under_uv_scale = vec2(0.4, 0.4);
group_uniforms;

// LAYERED: where the plaster has gone.
group_uniforms Breaks;
// The painted masks, one sheet for the whole project (assets/masks/floorplan_masks.png,
// imported as a 2D texture array of 8 × 8 slices). A wall reads its own slice.
uniform sampler2DArray mask_sheet : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D mask_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float noise_scale_m : hint_range(0.1, 20.0) = 3.0;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.6;
uniform float break_edge : hint_range(0.0, 1.0) = 0.62;
uniform float break_soft : hint_range(0.001, 0.5) = 0.06;
uniform float use_vertex_color : hint_range(0.0, 1.0) = 0.0;
uniform float plaster_thickness : hint_range(0.0, 0.2) = 0.03;
uniform float edge_relief : hint_range(0.0, 1.0) = 0.3;
uniform float rim_ao : hint_range(0.0, 1.0) = 0.6;
// LAYERED: PARALLAX CANNOT CROSS A HARD EDGE — on a box the relief stops at the corner and the
// offset texels slide past the face onto nothing. The mesh carries each face's UV box (CUSTOM1 =
// min, CUSTOM0 = max + a flag, written by the Floorplan metric-UV pass — UV2 stays the
// lightmap's, so a plastered wall bakes like any other); within this many
// metres of the face's edge the parallax depth and the plaster step fade to zero, so two faces
// meet flat at their corner. A mesh without the channels never fades.
uniform float edge_fade_m : hint_range(0.0, 1.0) = 0.15;
group_uniforms;

// LAYERED: relief self-shadowing, in light().
group_uniforms Relief_shadows;
uniform float relief_shadow : hint_range(0.0, 1.0) = 0.7;
uniform int relief_shadow_layers : hint_range(1, 32) = 8;
uniform float relief_shadow_soft : hint_range(0.001, 0.5) = 0.05;
group_uniforms;

// LAYERED: PER-INSTANCE SETTINGS (GeometryInstance3D → Instance Shader Parameters). The mask
// slice this mesh paints on (-1 = none) and the metres its slice spans; then one offset per
// Breaks knob, added to the material's value and clamped — 0 inherits.
instance uniform int mask_slot : hint_range(-1, 63) = -1;
instance uniform vec2 mask_origin = vec2(0.0, 0.0);
instance uniform vec2 mask_size = vec2(8.0, 8.0);
instance uniform float break_edge_ofs : hint_range(-1.0, 1.0) = 0.0;
instance uniform float break_soft_ofs : hint_range(-0.5, 0.5) = 0.0;
instance uniform float noise_amount_ofs : hint_range(-1.0, 1.0) = 0.0;
instance uniform float noise_scale_ofs : hint_range(-20.0, 20.0) = 0.0;
instance uniform float plaster_thickness_ofs : hint_range(-0.2, 0.2) = 0.0;
instance uniform float edge_relief_ofs : hint_range(-1.0, 1.0) = 0.0;
instance uniform float rim_ao_ofs : hint_range(-1.0, 1.0) = 0.0;
instance uniform float edge_fade_ofs : hint_range(-1.0, 1.0) = 0.0;
instance uniform float relief_shadow_ofs : hint_range(-1.0, 1.0) = 0.0;

varying vec2 uv_m;
varying vec4 face_box;   // LAYERED: the face's UV box in metres (min.xy, max.xy)
varying float face_valid; // LAYERED: 1 when the mesh carries face boxes
// LAYERED: written in fragment(), read in light() — the parallax-corrected tile UV, the vertex
// colour, the edge fade and the tangent frame the parallax used (view space).
varying vec2 pom_uv;
varying float pom_vcol;
varying float pom_edge;
varying vec3 pom_t;
varying vec3 pom_b;
varying vec3 pom_n;

// LAYERED: the effective (material + instance offset) values.
float e_break_edge() { return clamp(break_edge + break_edge_ofs, 0.0, 1.0); }
float e_break_soft() { return clamp(break_soft + break_soft_ofs, 0.001, 0.5); }
float e_noise_amount() { return clamp(noise_amount + noise_amount_ofs, 0.0, 1.0); }
float e_noise_scale() { return clamp(noise_scale_m + noise_scale_ofs, 0.1, 40.0); }
float e_plaster_thickness() { return clamp(plaster_thickness + plaster_thickness_ofs, 0.0, 0.4); }
float e_edge_relief() { return clamp(edge_relief + edge_relief_ofs, 0.0, 1.0); }
float e_rim_ao() { return clamp(rim_ao + rim_ao_ofs, 0.0, 1.0); }
float e_edge_fade() { return clamp(edge_fade_m + edge_fade_ofs, 0.0, 2.0); }
float e_relief_shadow() { return clamp(relief_shadow + relief_shadow_ofs, 0.0, 1.0); }

// LAYERED: 1 where the stone shows, 0 where the plaster stands; `m` in metres.
float break_w(vec2 m, float vcol, float h_top) {
	float painted = 0.0;
	if (mask_slot >= 0) {
		painted = texture(mask_sheet, vec3((m - mask_origin) / mask_size, float(mask_slot))).r;
	}
	float n = texture(mask_noise, m / e_noise_scale()).r;
	float x = painted + n * e_noise_amount() + vcol * use_vertex_color + (h_top - 0.5) * e_edge_relief();
	return smoothstep(e_break_edge() - e_break_soft(), e_break_edge() + e_break_soft(), x);
}

// LAYERED: the combined height the parallax walks. `uv_tile` is the plaster's tiled UV the
// engine's loop works in; the metric point is recovered from the tile offset.
float height_at(vec2 uv_tile, vec2 uv_tile0, vec2 m0, float vcol, float edge) {
	vec2 m = m0 + (uv_tile - uv_tile0) / uv1_scale.xy;
	float h_top = texture(texture_heightmap, uv_tile).r;
	float h_under = texture(under_heightmap, m * under_uv_scale).r;
	float w = break_w(m, vcol, h_top);
	// Thickness in height units: the loop's full range is heightmap_scale * 0.01 tile units,
	// i.e. that many metres divided by uv1_scale — so a thickness in metres converts back.
	// Faded by `edge`: the recess closes toward a hard edge and meets the corner flat.
	float t = e_plaster_thickness() * uv1_scale.x / max(heightmap_scale * 0.01, 0.0001) * edge;
	return clamp(mix(h_top, h_under - t, w), 0.0, 1.0);
}

// LAYERED: 0 on a face's hard edge, 1 from edge_fade_m inward; 1 everywhere on meshes without
// face boxes.
float edge_fade(vec2 m) {
	if (face_valid < 0.5) {
		return 1.0;
	}
	float d = min(min(m.x - face_box.x, m.y - face_box.y), min(face_box.z - m.x, face_box.w - m.y));
	return smoothstep(0.0, max(e_edge_fade(), 0.0001), d);
}

void vertex() {
	uv_m = UV; // LAYERED: metres, for the under layer, the mask and the noise
	face_box = vec4(CUSTOM1.xy, CUSTOM0.xy); // LAYERED
	face_valid = CUSTOM0.z;           // LAYERED
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;
	vec2 uv_tile0 = UV;  // LAYERED
	vec2 m0 = uv_m;      // LAYERED
	float vcol = COLOR.r; // LAYERED
	float edge = edge_fade(uv_m); // LAYERED
	pom_t = TANGENT;      // LAYERED: for light()
	pom_b = BINORMAL;     // LAYERED
	pom_n = NORMAL;       // LAYERED
	pom_vcol = vcol;      // LAYERED
	pom_edge = edge;      // LAYERED

	{
		// Height: Enabled
		vec3 view_dir = normalize(normalize(-VERTEX + EYE_OFFSET) * mat3(TANGENT * heightmap_flip.x, -BINORMAL * heightmap_flip.y, NORMAL));

		// Height Deep Parallax: Enabled
		float num_layers = mix(float(heightmap_max_layers), float(heightmap_min_layers), abs(dot(vec3(0.0, 0.0, 1.0), view_dir)));
		float layer_depth = 1.0 / num_layers;
		float current_layer_depth = 0.0;
		vec2 p = view_dir.xy * heightmap_scale * 0.01 * edge; // LAYERED: * edge — no relief past a hard edge
		vec2 delta = p / num_layers;
		vec2 ofs = base_uv;
		float depth = 1.0 - height_at(ofs, uv_tile0, m0, vcol, edge); // LAYERED: was texture(texture_heightmap, ofs).r
		float current_depth = 0.0;
		while (current_depth < depth) {
			ofs -= delta;
			depth = 1.0 - height_at(ofs, uv_tile0, m0, vcol, edge); // LAYERED: same substitution
			current_depth += layer_depth;
		}

		vec2 prev_ofs = ofs + delta;
		float after_depth = depth - current_depth;
		float before_depth = (1.0 - height_at(prev_ofs, uv_tile0, m0, vcol, edge)) - current_depth + layer_depth; // LAYERED
		float weight = after_depth / (after_depth - before_depth);
		ofs = mix(ofs, prev_ofs, weight);
		base_uv = ofs;
	}
	pom_uv = base_uv; // LAYERED: the corrected point, where the shadow ray starts

	// LAYERED: everything below samples at the parallax-corrected point, in both layers, mixed
	// by the break weight there.
	vec2 m = m0 + (base_uv - uv_tile0) / uv1_scale.xy;
	float h_top = texture(texture_heightmap, base_uv).r;
	float w = break_w(m, vcol, h_top);
	vec2 uv_under = m * under_uv_scale;

	vec4 albedo_tex = texture(texture_albedo, base_uv);
	vec3 under_col = texture(under_albedo, uv_under).rgb; // LAYERED
	ALBEDO = mix(albedo.rgb * albedo_tex.rgb, under_col, w);

	METALLIC = metallic;
	SPECULAR = specular;

	vec4 roughness_texture_channel = vec4(0.333333, 0.333333, 0.333333, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	float under_rough = dot(texture(under_roughness, uv_under), roughness_texture_channel); // LAYERED
	ROUGHNESS = mix(roughness_tex * roughness, under_rough, w);

	// Normal Map: Enabled
	NORMAL_MAP = mix(texture(texture_normal, base_uv).rgb, texture(under_normal, uv_under).rgb, w);
	NORMAL_MAP_DEPTH = mix(normal_scale, under_normal_scale, w);

	// Ambient Occlusion: Enabled
	float ao_top = texture(texture_ambient_occlusion, base_uv).r;
	float ao_under = texture(under_ao, uv_under).r; // LAYERED
	float rim = w * (1.0 - w) * 4.0; // LAYERED: peaks on the break edge — the cavity under the plaster
	AO = mix(ao_top, ao_under, w) * (1.0 - e_rim_ao() * rim);
	AO_LIGHT_AFFECT = ao_light_affect;
}

// LAYERED: per light. The light vector goes into the same tangent frame the engine's parallax
// built its view vector in (`view_dir = V * mat3(T * flip.x, -B * flip.y, N)`), and the combined
// height is marched from the corrected point toward the light: the ray rises from the surface
// height to 1 in `relief_shadow_layers` steps, shifting in tile UV by `l.xy / l.z` × the
// parallax range per unit of height (the geometry the parallax already implies). The largest
// amount by which a sample overtops the ray is the occlusion; `relief_shadow_soft` softens it.
void light() {
	float shadow = 1.0;
	float strength = e_relief_shadow();
	vec3 l = vec3(dot(LIGHT, pom_t * heightmap_flip.x), dot(LIGHT, -pom_b * heightmap_flip.y), dot(LIGHT, pom_n));
	if (strength > 0.0 && l.z > 0.0 && pom_edge > 0.0) {
		float h0 = height_at(pom_uv, UV, uv_m, pom_vcol, pom_edge);
		float n = float(relief_shadow_layers);
		float layer = (1.0 - h0) / n;
		vec2 step_uv = l.xy / max(l.z, 0.1) * heightmap_scale * 0.01 * pom_edge * layer;
		vec2 uv = pom_uv;
		float h_ray = h0;
		float occ = 0.0;
		for (int i = 0; i < relief_shadow_layers; i++) {
			uv += step_uv;
			h_ray += layer;
			float hs = height_at(uv, UV, uv_m, pom_vcol, pom_edge);
			occ = max(occ, hs - h_ray);
		}
		shadow = 1.0 - strength * smoothstep(0.0, max(relief_shadow_soft, 0.001), occ);
	}
	// The docs' Lambert light() example, times the relief shadow.
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI * shadow;
	// Normalized Blinn-Phong with the StandardMaterial3D dielectric F0 (0.16 · specular²).
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float shininess = exp2(10.0 * (1.0 - ROUGHNESS) + 1.0);
	float d = pow(ndh, shininess) * (shininess + 8.0) / (8.0 * PI);
	float f0 = 0.16 * specular * specular;
	SPECULAR_LIGHT += d * f0 * ndl * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT / PI * shadow;
}
