shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_schlick_ggx;
// Stylized multimesh grass by @_Malido (CC0) — https://godotshaders.com/shader/stylized-multimesh-grass-shader/
// Convention: UV.y = 0 at blade TIP, 1 at ROOT (our tuft mesh is built to match).
// Local adaptation (marked below): ALBEDO multiplied by COLOR for per-instance tint variation.
// Local adaptation (marked below): stippled distance fade, mirrored from painted_env.gdshader.

// LOCAL ADAPTATION. Mirrored from painted_env.gdshader rather than shared through a .gdshaderinc,
// which is the standing call in this project (dungeon_stone.gdshader: "one syntax error in a shared
// include takes every one of them down at once"). Same dither, same reason: a MultiMesh cannot be
// sorted, so the fade discards instead of blending.
uniform float fade_start : hint_range(0.0, 200.0, 1.0) = 0.0;
uniform float fade_end : hint_range(0.0, 200.0, 1.0) = 1.0;

float dither_threshold(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

// LOCAL ADAPTATION: petals. UV.x is the flower mask -- 0 on foliage, 1 on a flower head. It is
// the only per-vertex channel free here, because a MultiMesh with use_colors overwrites COLOR with
// the per-INSTANCE tint, so vertex colour cannot carry anything of its own.
uniform vec3 flower_color: source_color = vec3(0.92, 0.90, 0.86);
// INSTANCE_CUSTOM is a VERTEX-stage built-in in Godot, so the per-instance flowering flag has to be
// carried across to the fragment by hand.
varying float v_flower;

uniform vec3 top_color: source_color;
uniform vec3 bottom_color: source_color;
uniform float ambient_occlusion_factor: hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float specular_strength: hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float player_displacement_strength: hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float player_displacement_size: hint_range(0.0, 2.0, 0.01) = 1.0;

uniform vec3 wind_direction;
uniform float wind_strength: hint_range(0.0, 1.0, 0.01) = 0.3;
uniform sampler2D wind_noise;
uniform float wind_noise_size: hint_range(0.0, 1.0, 0.001) = 0.05;
uniform float wind_noise_speed: hint_range(0.0, 1.0, 0.001) = 0.1;

instance uniform vec3 player_position;

void vertex() {
	v_flower = INSTANCE_CUSTOM.r;
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 wind_texture = texture(wind_noise, world_position.xz * wind_noise_size + normalize(-wind_direction.xz) * (TIME + UV.y / 2.5) * wind_noise_speed).rgb;
	vec3 wind_vector = (vec4(wind_texture * normalize(wind_direction) * wind_strength, 0.0) * MODEL_MATRIX).xyz;

	float player_height = smoothstep(1.0, 0.0, length(player_position.y - world_position.y + 0.3));
	vec3 push_direction = vec3(world_position - player_position) * vec3(1, -0.3, 1);
	float player_position_factor = smoothstep(player_displacement_size, 0.0, length(push_direction));

	vec3 player_push_vector = (vec4(normalize(push_direction), 0.0) * MODEL_MATRIX).xyz;

	VERTEX += player_push_vector * (1.0 - UV.y) * player_position_factor * player_displacement_strength * player_height;
	VERTEX += wind_vector * (1.0 - UV.y) * (1.0 - player_position_factor * 0.7);

	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// LOCAL ADAPTATION: stippled distance fade. VERTEX is view space here, so its length is the
	// distance to the camera.
	if (fade_start > 0.0) {
		if (smoothstep(fade_start, fade_end, length(VERTEX)) > dither_threshold(FRAGCOORD.xy)) {
			discard;
		}
	}

	vec3 color = mix(bottom_color, top_color, 1.0 - UV.y);

	float ao_fallof = pow(UV.y, 5.0);
	vec3 ao_color = bottom_color * (1.0 - ambient_occlusion_factor);

	// LOCAL ADAPTATION: petals belong only to the instances flagged as flowering. The tuft mesh is
	// shared by every instance in the MultiMesh, so the head has to be built into all of them and
	// then thrown away per instance — INSTANCE_CUSTOM.r is the flag GrassPatch writes.
	if (UV.x > 0.5 && v_flower < 0.5) {
		discard;
	}

	ALBEDO = mix(color, ao_color, ao_fallof) * COLOR.rgb;
	// LOCAL ADAPTATION: a petal ignores the root-to-tip ramp and the root AO entirely.
	ALBEDO = mix(ALBEDO, flower_color * COLOR.rgb, step(0.5, UV.x));   // * COLOR.rgb = per-instance tint (local adaptation)
	ROUGHNESS = 0.4;

	SPECULAR *= (1.0 - UV.y) * specular_strength;

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
