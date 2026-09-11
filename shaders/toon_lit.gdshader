shader_type spatial;
// Cel / toon surface shader for characters.
//
// Structure adapted from a stylized toon shader supplied as a reference example. It replaces the
// "Flexible Toon Shader" we used before, which had two pathologies that made shading unreadable:
//   * N·L was never clamped, so it went negative and fell off the bottom of the ramp;
//   * ATTENUATION was folded in as an OFFSET (`+ (attenuation - 1.0)`) rather than a multiplier,
//     so shadow and form-shading fought each other instead of composing.
// Here: `clamp(dot(NORMAL, LIGHT), 0, 1) * ATTENUATION` — clamped, and shadow MULTIPLIES. The
// shadow side is then an explicit added tint rather than "whatever is left", which is what makes
// the dark tone actually reachable.
//
// Tune everything on assets/materials/toon_character.tres (Inspector); toon_skin.gd duplicates it
// per character, so that resource drives both the game and scenes/dev/shader_lab.tscn.

group_uniforms Albedo;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
// How much the surface colour tints the lighting. 1.0 = normal (textures show through);
// 0.0 = lighting only, ignoring albedo.
uniform float albedo_affect : hint_range(0.0, 1.0, 0.05) = 1.0;
// Vertex colour as albedo. Environment art here is TEXTURELESS: assets/models/house.glb carries
// all of its colour in COLOR_0 (one flat colour per shingle, per stone, per plank) with a white
// albedo, so without this the whole building renders white. Meshes with no colour attribute get
// COLOR = 1.0, so leaving this on costs characters nothing.
uniform bool use_vertex_color = true;
group_uniforms;

group_uniforms Light;
uniform bool use_stepped = true;
uniform float steps = 3.0;                                        // number of light bands
uniform float step_smoothness : hint_range(0.0, 1.0, 0.05) = 0.1; // 0 = razor-hard terminator
// The shadow side is ADDED as its own colour, so it is reachable no matter what the lit side does.
// Keep it a cool mid-dark; raise shadow_tint_amount for a deeper shadow.
uniform vec4 shadow_tint : source_color = vec4(0.24, 0.27, 0.38, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0, 0.05) = 0.4;
group_uniforms;

group_uniforms Specular;
// Toon specular is a tight highlight. On cloth/skin it reads as glass — hair only.
uniform float specular : hint_range(0.0, 1.0, 0.05) = 0.0;
group_uniforms;

group_uniforms Rim;
uniform bool use_rim = false;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount = 2.0;
uniform float rim_smoothness = 0.2;
// 1.0 = rim only appears where light reaches. A rim that ignores this glows on the shadow side and
// reads as latex, which is the single most common "plastic" tell.
uniform float rim_mask_shadow : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform float rim_blend : hint_range(0.0, 1.0, 0.05) = 1.0;
group_uniforms;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void fragment() {
	ALBEDO = (texture(albedo_texture, UV) * albedo_color).rgb;
	if (use_vertex_color) {
		ALBEDO *= COLOR.rgb;
	}
	SPECULAR = specular;
}

void light() {
	// Clamped lambert, with shadow/attenuation MULTIPLYING it.
	float light = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;

	// Quantise into flat bands with a controllable terminator width.
	if (use_stepped) {
		float light_mult = light * steps;
		float step_base = floor(light_mult);
		float light_factor = light_mult - step_base;
		light_factor = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, light_factor);
		light = (step_base + light_factor) / steps;
	}

	// Lit contribution, plus the shadow tint fading in as the light falls away.
	//
	// `light` IS APPLIED EXACTLY ONCE, and it used to be applied twice — the first line read
	// `(LIGHT_COLOR / PI) * light` and the second multiplied by `light` again, so the lit term was
	// LIGHT_COLOR * light^2. The tell is what that does to the bands this shader exists to make:
	// at steps = 3 the three flat tones should land on 0.33 / 0.67 / 1.00, and squaring puts them
	// on 0.11 / 0.44 / 1.00 instead. The two darker bands collapse toward black, so every character
	// in the game read as being in shadow everywhere — in the crypt, and out in the daylit hub too,
	// which is what made it obvious the cause could not be anything about the dungeon's lighting.
	// Measured under a single 1.0-energy directional light on a 0.55-albedo card: the card came
	// back at 0.80 and the character standing on it at 0.33.
	vec3 diffuse = LIGHT_COLOR / PI;
	diffuse = (shadow_tint.rgb * (1.0 - light) * shadow_tint_amount) + diffuse * light;

	if (use_rim) {
		float rim_value = fresnel(rim_amount, NORMAL, VIEW);
		rim_value = smoothstep(0.5 - (rim_smoothness / 2.0), 0.5 + (rim_smoothness / 2.0), rim_value);
		rim_value = mix(rim_value, rim_value * light, rim_mask_shadow);
		diffuse += rim_color.rgb * rim_value * rim_blend;
	}

	DIFFUSE_LIGHT += mix(diffuse, ALBEDO * diffuse, albedo_affect);
	SPECULAR_LIGHT += vec3(pow(light, 50.0)) * specular;
}
