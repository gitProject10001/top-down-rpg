shader_type spatial;
// Hand-painted surface shader for ENVIRONMENT art. Characters keep shaders/toon_lit.gdshader —
// the hard cel terminator reads as drawn linework on a face, which is exactly what you want on a
// character and exactly what you do not want on a hillside or a roof.
//
// WHAT MAKES A SURFACE LOOK PAINTED RATHER THAN CEL-SHADED
//
//   1. WRAP. A painter does not stop light dead at N·L = 0; light bleeds around the terminator.
//      `(N·L + wrap) / (1 + wrap)` remaps the whole range instead of clamping it, which softens
//      the terminator AND lifts the dark side. This one uniform does most of the work.
//
//   2. THE SHADOW IS A COLOUR, NOT AN ABSENCE. Darkening toward black is the single most common
//      "3D render" tell. Here the shadow side keeps the surface's own albedo and shifts it toward
//      shade_tint, so a coral wall goes to a dusty violet-coral rather than to grey.
//
//   3. SHADOWS GET MORE SATURATED, NOT LESS. Painters push chroma into shadow; renderers wash it
//      out. shade_saturation > 1 restores that.
//
//   4. NO SPECULAR, NO RIM. Both were measured, on this project, to be the source of the "plastic"
//      look. There is no uniform to turn them back on, deliberately.
//
//      THE ONE EXCEPTION, so the next reader finds it here rather than discovering a contradiction:
//      shaders/glass_stylized.gdshader does have a fresnel rim. It is a separate `unshaded` shader
//      with no light() at all, applied per SURFACE to window panes only, so it cannot reach the
//      environment shading model. The measurement above was taken on matte opaque surfaces, which
//      have no physical reason for a grazing highlight; glass is the material that does.
//
// Bands default to 0 = fully smooth. Raise `bands` only if a scene wants a graphic, poster-like
// read; the painted look does not need them.

group_uniforms Albedo;
uniform vec4 albedo_color : source_color = vec4(1.0);
// Environment meshes here are TEXTURELESS: assets/models/house.glb carries one flat colour per
// shingle, per stone, per plank in COLOR_0. Meshes with no colour attribute get COLOR = 1.0.
uniform bool use_vertex_color = true;
uniform sampler2D albedo_texture : source_color, hint_default_white;

// LEAF CUTOUT. Above 0, a texel whose alpha falls under this is discarded, which is how a canopy
// made of leaf cards gets its holes. Discard rather than ALPHA for the same reason the see-through
// stipple below discards: blending would push the surface into the sorted pass, and a MultiMesh of
// three hundred bushes has no meaningful sort order. A cut-out stays opaque, sorts by depth like
// any solid, and costs nothing per instance. 0 disables the sample entirely, which is what every
// non-foliage surface wants.
uniform float alpha_cut : hint_range(0.0, 1.0, 0.01) = 0.0;
// AND THE REASON ALPHA-TESTED FOLIAGE NEEDS A SECOND KNOB. Mipmapping averages the leaf mask toward
// its own mean — about 0.4 for a cluster that is mostly gaps — so past a certain distance EVERY
// texel reads under the cutoff and a canopy that was solid at three metres dissolves to nothing at
// eighty. It is not a fade; it is the silhouette falling apart, and it is worst at exactly the
// framing the terrace vista uses.
//
// Relaxing the threshold as the surface recedes hands the coverage back. Metres at which the cut
// has fallen to its floor; 0 disables the whole ramp.
uniform float alpha_cut_falloff : hint_range(0.0, 300.0, 1.0) = 0.0;
group_uniforms;

// UV1 TRANSFORM, and it is not a nicety — without it every tiled surface in the game is wrong.
//
// Blender states tiling with a Mapping node, which exports as glTF KHR_texture_transform, which
// Godot's importer puts into StandardMaterial3D.uv1_scale. A ShaderMaterial has no such property,
// so painted_skin had nothing to copy it into and this shader sampled raw UV — meaning a wall
// authored to tile every 1.5 m and a roof authored to tile every 3.5 m BOTH arrived tiling once
// per metre. The source of truth for texel density lived in the .blend and stopped at the border.
group_uniforms Tiling;
uniform vec2 uv1_scale = vec2(1.0);
uniform vec2 uv1_offset = vec2(0.0);
group_uniforms;

// SURFACE RELIEF. Everything below perturbs how light lands; none of it adds specular, because
// this shader has none by design (see the header) and a roughness map would therefore be a
// uniform that does nothing.
group_uniforms Relief;
// GATED BY A FLAG rather than by a default texture. There is no "flat normal" default hint, and
// the fallback for an unset sampler is WHITE — which decodes to a tilted normal, not a flat one,
// and would silently re-light every untextured surface in the game the moment this uniform
// existed. Off unless something supplies a map.
uniform bool use_normal_map = false;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_strength : hint_range(0.0, 4.0, 0.05) = 1.0;

// PARALLAX OCCLUSION. Marches the view ray through the height field and samples where it first
// goes under the surface, so texels slide against each other as the camera moves and near edges
// occlude far ones. This is the only thing here that produces depth rather than the shading of
// depth.
//
// It is angle-dependent by nature — offset scales with how far the view vector leans across the
// surface — so it earns its cost on walls and gives back least on a roof seen from nearly
// overhead. Steps are spent where the lean is greatest and skipped where it is not.
uniform bool use_parallax = false;
uniform sampler2D height_texture : hint_default_black;
uniform float parallax_depth : hint_range(0.0, 0.2, 0.001) = 0.03;
uniform int parallax_steps : hint_range(4, 48) = 20;

// STOCHASTIC DE-TILING (Heitz & Neyret's texture bombing, in its cheap two-tap form).
//
// Repetition cannot be fixed by UV mapping — UVs set scale and orientation, and a lattice repeated
// across 3,000 m2 of wall reads as a lattice however it is scaled. Two taps of the SAME texture at
// a different scale and offset, cross-faded by a low-frequency mask, breaks the grid because the
// two copies never line up. Costs one extra fetch of whatever it is applied to.
uniform float detile : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float detile_scale : hint_range(0.01, 1.0, 0.01) = 0.12;
group_uniforms;

// WHERE THE CAVITY WENT, since a reader will look for it here.
//
// Recesses being darker than faces is the other half of making a tiled surface stop reading as a
// photograph on a polygon — a normal map only tilts the shading normal, so a mortar line ends up
// exactly as bright as the brick beside it. That darkening IS present, multiplied into the albedo
// in the .blend, so it costs nothing here and arrives through the one channel that already
// crosses the border.
//
// It is deliberately not a second uniform sampling a height map. That would double the effect on
// every surface already carrying it, need eight more textures imported for maps glTF cannot
// transport, and buy only the ability to retune something the source file states more clearly.
//
// PARALLAX IS ALSO NOT HERE, and that is a measurement rather than an omission: it scales with
// viewing angle, and the roof planes this work was prompted by sit 20 degrees off flat under a
// fixed camera. It would cost a ray-march per pixel to do almost nothing exactly where the
// complaint was. It becomes worth having if the camera ever gets close to a WALL at a grazing
// angle, which is the case it is actually good at.

group_uniforms Light;
// 0 = hard terminator (cel-like); 1 = fully wrapped, very soft. ~0.5 is the painterly zone.
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.55;
// 0 = smooth. Above 1 the light is posterised into that many steps.
uniform float bands : hint_range(0.0, 8.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.01, 1.0, 0.01) = 0.35;
group_uniforms;

group_uniforms Shadow;
uniform vec4 shade_tint : source_color = vec4(0.55, 0.45, 0.62, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float shade_saturation : hint_range(0.0, 2.0, 0.05) = 1.30;
// HOW MUCH OF THE SHADOW TINT SURVIVES INSIDE A CAST SHADOW. This is not a taste knob, it is a
// correctness one. A term added in light() is applied for every light REGARDLESS of occlusion, so
// at 0.0 the tint lights the inside of a sealed building: measured at 0.398 mean luminance in a
// closed house with ambient at zero and GI off. At 1.0 the tint is gated by ATTENUATION, cast
// shadows fall through to ambient/GI (which SDFGI and SSAO actually occlude), and interiors go
// properly dark. Leave it at 1.0 unless you want the leak on purpose.
uniform float shade_occlusion : hint_range(0.0, 1.0, 0.05) = 1.0;
group_uniforms;

group_uniforms Sunlight;
uniform vec4 light_tint : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float light_tint_amount : hint_range(0.0, 1.0, 0.05) = 0.35;
group_uniforms;

group_uniforms Distance;
// DISSOLVE FAR FOLIAGE, rather than draw it as noise. Nineteen thousand tufts at 30-40 m across a
// 76 m arena stop being grass and become green fuzz — and they are exactly what a pulled-back vista
// framing is trying to read past. 0 disables it, which is what every non-foliage surface wants.
//
// STIPPLED, NOT FADED, for the same reason the see-through cone below is stippled: alpha would push
// a MultiMesh into the sorted pass where it has no meaningful order. TAA then smooths the stipple
// into a dissolve, which is the behaviour the cone already depends on.
uniform float fade_start : hint_range(0.0, 200.0, 1.0) = 0.0;
uniform float fade_end : hint_range(0.0, 200.0, 1.0) = 1.0;
group_uniforms;

group_uniforms Wind;
// Metres of sway at the TOP of the plant. 0 disables the whole thing, which is how the house and
// the ground use this shader without paying for it.
uniform float wind_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
// The model's own height, so `strength` stays in metres regardless of plant size. A grass tuft and
// a tree cannot share one value here — that is why foliage gets its own materials.
uniform float wind_height = 1.0;
uniform float wind_speed : hint_range(0.0, 6.0, 0.05) = 1.6;
uniform vec2 wind_direction = vec2(1.0, 0.35);
// Spatial frequency of the gust travelling across the field. Small = long rolling waves.
uniform float wind_wavelength : hint_range(0.01, 1.0, 0.01) = 0.11;
group_uniforms;

// SEE THROUGH WHATEVER STANDS BETWEEN THE CAMERA AND THE PLAYER.
//
// scripts/roof_fade.gd already does this for the hand-modelled zones, by tweening a named mesh's
// `transparency` when the player trips an Area3D. That cannot work for a GladeKit building: a
// GladeWall batches every brick in the footprint into one MultiMeshInstance per brick VARIANT, so
// the node-level knob `transparency` can only fade a whole building at once — there is no node that
// means "the near wall". A fragment test has no such problem, because it asks the question per
// pixel: is this fragment inside the cone between the camera and the player?
//
// Driven by GLOBAL uniforms, not material ones, and deliberately: the alternative is writing the
// player's position into assets/materials/painted_glade.tres every frame, which the look-dev's
// "Save material" button would then bake into the file.
global uniform vec3 see_through_target;
global uniform float see_through_radius;   // 0 disables the whole thing, which is the default

// AND THE ROOM THE PLAYER IS STANDING IN, which is a different question from the one above.
//
// A cone around the player reveals the player. It does not reveal the ROOM — stand next to a wall
// and the hole is mostly wall. What a top-down game actually wants indoors is the doll's-house cut:
// take the lid off at the ceiling of the floor you are on and look down into the whole storey.
//
// So this is a half-space, not a cone: inside the building's footprint AND above that storey's
// ceiling is removed outright. Hard discard rather than stipple, because a stippled roof is a
// screenful of noise where a clean cut is simply the lid coming off. `interior_center.y` carries
// the ceiling height; xz and `interior_half` are the footprint box.
global uniform vec3 interior_center;
global uniform vec3 interior_half;
global uniform float interior_active;      // 0 = outdoors, and the default

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 saturate_rgb(vec3 c, float amount) {
	return mix(vec3(dot(c, LUMA)), c, amount);
}

// STIPPLE, NOT ALPHA. Going transparent would push these surfaces into the sorted pass, and a
// MultiMesh of ten thousand bricks has no meaningful sort order — they would swim through each
// other. Discarding on an ordered threshold keeps the material opaque and reads as a hand-drawn
// hatch, which suits the painted look better than a clean dissolve anyway.
// `frag` is passed in rather than read from FRAGCOORD: Godot's shading language only exposes
// built-ins inside the entry points, so a helper that reaches for one fails to compile.
float dither_threshold(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	if (wind_strength > 0.0) {
		// Phase from the INSTANCE ORIGIN, not the vertex. MODEL_MATRIX carries the per-instance
		// transform under MultiMesh, so every scattered tuft gets its own place in the gust
		// instead of all 11,000 of them swaying in lockstep.
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec2 dir = normalize(wind_direction);
		float phase = dot(origin.xz, dir) * (1.0 / max(wind_wavelength, 0.01)) * 0.05;
		float t = TIME * wind_speed + phase;
		// Two incommensurate frequencies so the loop never becomes obvious, same trick as the
		// hearth flicker.
		float sway = sin(t) + 0.35 * sin(t * 2.7);
		// Squared falloff from the base: the roots stay planted and the tip does the moving.
		// Linear makes the whole plant slide sideways, which reads as a bug.
		float h = clamp(VERTEX.y / max(wind_height, 0.01), 0.0, 1.0);
		VERTEX.xz += dir * sway * wind_strength * h * h;
	}
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// VERTEX is view space in fragment(), so its length IS the distance to the camera.
	if (fade_start > 0.0) {
		if (smoothstep(fade_start, fade_end, length(VERTEX)) > dither_threshold(FRAGCOORD.xy)) {
			discard;
		}
	}

	// THE LID OFF THE ROOM, first: everything over this storey's ceiling and inside its footprint.
	// Runs before the cone so a roof already removed here costs no further work.
	if (interior_active > 0.5) {
		vec2 d = abs(world.xz - interior_center.xz) - interior_half.xz;
		if (max(d.x, d.y) < 0.0 && world.y > interior_center.y) {
			discard;
		}
	}

	if (see_through_radius > 0.0) {
		// the cone from the eye to the player: anything inside it, and NEARER than the player, is
		// what is standing in the way
		vec3 to_target = see_through_target - CAMERA_POSITION_WORLD;
		float reach = length(to_target);
		vec3 dir = to_target / max(reach, 0.001);
		vec3 to_frag = world - CAMERA_POSITION_WORLD;
		float along = dot(to_frag, dir);
		// `along < reach` is the half that matters: the wall BEHIND the player must stay solid, or
		// the player is left standing in a hole with the landscape showing through the far side.
		if (along > 0.0 && along < reach) {
			float perp = length(to_frag - dir * along);
			float m = 1.0 - smoothstep(see_through_radius * 0.55, see_through_radius, perp);
			// fade the hole in as the occluder approaches the player, so a distant wall the cone
			// happens to clip does not flicker away
			m *= smoothstep(0.0, 0.35, 1.0 - along / max(reach, 0.001));
			if (m > dither_threshold(FRAGCOORD.xy)) {
				discard;
			}
		}
	}
	vec2 uv = UV * uv1_scale + uv1_offset;

	// PARALLAX, before anything is sampled: it displaces the coordinate every later fetch uses, so
	// albedo and normal stay on the same texel and agree about where the surface is.
	if (use_parallax) {
		// The view vector in TANGENT space. Its z is how square-on the surface is, and its xy is
		// the lean — which is exactly the quantity parallax offsets along.
		vec3 vdir = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL)));
		// Steps scale with the lean. Straight-on there is nothing to displace and the march is a
		// waste of a texture unit; at a grazing angle the offset is long and needs the samples.
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
		// One linear step back between the last two samples: without it the march quantises into
		// visible terraces at low step counts, which reads as worse than no parallax at all.
		vec2 prev = cur + step_uv;
		float after = (1.0 - h) - depth;
		float before = (1.0 - texture(height_texture, prev).r) - depth + layer;
		uv = mix(cur, prev, clamp(after / max(after - before, 0.0001), 0.0, 1.0));
	}

	vec4 tex = texture(albedo_texture, uv);
	// DE-TILING: a second tap at a different scale and offset, cross-faded by a low-frequency mask
	// built from the same coordinate. The two copies never align, so the repeat stops being a grid.
	if (detile > 0.0) {
		vec2 uv_b = uv * 0.77 + vec2(0.37, 0.61);
		vec2 c = uv * detile_scale;
		// Cheap value noise — three sines beat a texture fetch and there is no lattice to see at
		// this frequency.
		float m = sin(c.x * 1.7 + c.y * 2.3) + sin(c.x * -2.9 + c.y * 1.1) + sin(c.x * 0.6 - c.y * 3.7);
		m = smoothstep(-0.6, 0.6, m * 0.5);
		tex = mix(tex, texture(albedo_texture, uv_b), m * detile);
	}
	if (alpha_cut > 0.0) {
		float cut = alpha_cut;
		if (alpha_cut_falloff > 0.0) {
			cut *= clamp(1.0 - length(VERTEX) / alpha_cut_falloff, 0.12, 1.0);
		}
		if (tex.a < cut) {
			discard;
		}
	}
	vec3 base = (tex * albedo_color).rgb;
	if (use_vertex_color) {
		base *= COLOR.rgb;
	}

	ALBEDO = base;

	// NORMAL MAPPING. Godot builds NORMAL from this using the mesh's tangents, so it reaches
	// light()'s wrapped lambert without that function needing to know it exists. The .glb is
	// imported with ensure_tangents, so the tangents are there.
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}

	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	// (1) wrapped lambert — remapped, not clamped, so light carries past the terminator
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

	DIFFUSE_LIGHT += mix(shadow_side, lit_side, l) * (LIGHT_COLOR / PI);
}
