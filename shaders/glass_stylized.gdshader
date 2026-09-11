shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled;
// Stylized glass for windows and lantern panes.
//
// THIS SHADER HAS A FRESNEL RIM, AND painted_env.gdshader SAYS NOT TO. That comment is right and is
// not being overturned — it is being scoped. Read in full, it says specular and rim "were measured,
// on this project, to be the source of the plastic look", and everything it was measured on was a
// matte opaque surface: plaster, slate, hillside, stone. A limewashed wall has no physical reason
// for a grazing-angle highlight, so giving it one reads as cheap plastic.
//
// Glass is the one material in the arena whose entire identity IS that highlight. A pane with no
// edge response does not read as understated; it reads as a hole punched in the wall, which is
// exactly what the flat dark boxes it replaces looked like.
//
// THE GUARD, so this cannot leak back into the environment:
//   * separate file, and `unshaded` — there is no light() here, so the painted lighting model is
//     untouched and cannot acquire a rim by accident;
//   * painted_env still has no uniform to turn its own rim on, and gains none;
//   * this material is only ever a PER-SURFACE override on a surface named bo_glass or a lantern
//     pane. Never a material_override on a node.
// And `fresnel_strength` ships with a hint_range so the exception stays measurable rather than
// asserted — set it to 0 in the tuner, shoot the arena, and let the picture settle it.
//
// REFLECTION IS A SKY GRADIENT, NOT A MATCAP AND NOT A CUBEMAP. The camera rig YAWS — CameraZone
// sets yaw_degrees per zone (warehouse 22.5, path 5, terrace -25) and CameraRig lerps through it.
// A matcap is locked to view space, so its highlight would swim across every pane as the rig swung,
// which is the classic matcap tell and unusually visible on a camera that turns on its own. The
// gradient is evaluated on the WORLD-space reflect vector instead, so the top of a pane stays
// sky-blue and the bottom stays ground-green wherever the camera goes. It also needs no asset, and
// its three defaults are lifted straight from main.tscn's ProceduralSkyMaterial so it agrees with
// the actual sky by construction rather than by eye.

group_uniforms Tint;
uniform vec4 glass_color : source_color = vec4(0.055, 0.085, 0.105, 1.0);
uniform float glass_alpha : hint_range(0.0, 1.0, 0.01) = 0.82;
group_uniforms;

group_uniforms Reflection;
uniform vec3 sky_color : source_color = vec3(0.25, 0.50, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.70, 0.83, 0.95);
uniform vec3 ground_color : source_color = vec3(0.50, 0.58, 0.52);
uniform float reflection_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float horizon_sharpness : hint_range(0.5, 8.0, 0.1) = 2.0;
group_uniforms;

group_uniforms Rim;
uniform float fresnel_power : hint_range(0.5, 8.0, 0.1) = 3.2;
uniform float fresnel_strength : hint_range(0.0, 2.0, 0.01) = 0.85;
// Matches painted_env's light_tint, so the pane's edge agrees with the sun the rest of the scene
// is lit by instead of introducing a second light colour.
uniform vec4 fresnel_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
group_uniforms;

group_uniforms Distortion;
// Old hand-blown glass is not flat. Object space, so the ripple belongs to the pane and does not
// swim when the camera moves, and procedural, so it costs no texture.
uniform float distort_scale : hint_range(0.1, 20.0, 0.1) = 4.0;
uniform float distort_amount : hint_range(0.0, 0.4, 0.005) = 0.06;
group_uniforms;

group_uniforms Glow;
// HOW BLOOM IS EARNED. main.tscn runs glow at hdr_threshold 1.1, so a rim pushed past 1.1 blooms
// with no change to any global glow setting. Raising glow_bloom instead would bleed from every
// pixel in the frame and fight the crisp read, which is what got the colour grade switched off.
uniform float emission_boost : hint_range(0.0, 4.0, 0.05) = 0.0;
group_uniforms;

group_uniforms Matcap;
// A DOOR LEFT OPEN, SHUT. Ships at 0 so no asset is needed and no highlight can swim; an artist who
// wants a painted streak later has a slot for it without a second shader.
uniform sampler2D matcap : source_color, hint_default_white;
uniform float matcap_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
group_uniforms;

varying vec3 v_obj;

// Lifted verbatim from shaders/toon_lit.gdshader (the project's only Fresnel) rather than written
// a second time, so the two cannot drift into subtly different curves.
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void vertex() {
	// Object space kept for the ripple. Computing it in fragment() would mean inverting
	// MODEL_MATRIX per pixel.
	v_obj = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	n.xy += vec2(sin(v_obj.y * distort_scale), cos(v_obj.x * distort_scale)) * distort_amount;
	n = normalize(n);

	// World-space reflect against a three-stop sky. NORMAL and VERTEX are view space here.
	vec3 nw = normalize(mat3(INV_VIEW_MATRIX) * n);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vw = normalize(world - CAMERA_POSITION_WORLD);
	vec3 r = reflect(vw, nw);
	float up = clamp(r.y, -1.0, 1.0);
	vec3 refl = up >= 0.0
		? mix(horizon_color, sky_color, pow(up, 1.0 / horizon_sharpness))
		: mix(horizon_color, ground_color, pow(-up, 1.0 / horizon_sharpness));

	if (matcap_strength > 0.0) {
		vec2 mc = n.xy * 0.5 + 0.5;
		refl = mix(refl, texture(matcap, mc).rgb, matcap_strength);
	}

	float f = fresnel(fresnel_power, n, VIEW);

	vec3 col = mix(glass_color.rgb, refl, reflection_strength * f);
	col += fresnel_color.rgb * f * fresnel_strength;

	ALBEDO = col;
	// Real glass is more opaque at a grazing angle than face-on, so the edge firms up as it lights.
	ALPHA = clamp(glass_alpha + f * 0.4, 0.0, 1.0);
	EMISSION = fresnel_color.rgb * f * emission_boost;
}
