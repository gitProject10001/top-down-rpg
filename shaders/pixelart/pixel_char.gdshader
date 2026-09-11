shader_type spatial;
// THE STANDING FIGURES, PAINTED BY BODY ZONE RATHER THAN TEXTURED.
//
// WHY THE BAKED TEXTURE HAD TO GO. char_a.glb carries a texture page, and using it is the obvious
// thing to do -- it is also why the figures came out looking like someone spilled coffee on the
// canvas. A figure in this frame is about thirty pixels tall. Its whole texture page therefore
// arrives averaged down into roughly three hundred pixels, and averaging a muddy low-contrast page
// gives a muddy low-contrast blob. Then the palette snap sends that blob to the mud ramp, where it
// is standing on mud, and the figure disappears.
//
// A pixel artist does not draw a thirty-pixel soldier by shrinking a photograph. They draw four
// flat colours stacked up the body -- dark boots, a coloured surcoat, mail at the shoulders, a
// helmet -- with a hard black outline round the lot. At this size the ZONES are the character;
// there is no room for anything else, and anything else is noise.
//
// So this shader ignores the page entirely and paints by height in MODEL space. Four bands, hard
// edges, two lighting steps. It is cruder than the texture and it reads enormously better.
//
// THE SURCOAT COLOUR VARIES PER FIGURE, hashed from the instance origin. The reference has red and
// blue among its soldiers and that colour is what the eye uses to tell one from another and to find
// them against the ground. Hashing the world position means six copies of one mesh come out as six
// distinguishable people with no per-instance setup in the scene file.

group_uniforms Zones;
// Boundaries as a fraction of the model height, bottom to top. char_a is authored one unit tall
// with its origin at the CENTRE, so height is remapped from [-0.5, 0.5] before these are applied.
uniform float hem : hint_range(0.0, 1.0, 0.01) = 0.30;      // boots -> surcoat
uniform float chest : hint_range(0.0, 1.0, 0.01) = 0.62;    // surcoat -> mail
uniform float collar : hint_range(0.0, 1.0, 0.01) = 0.79;   // mail -> helmet
uniform vec4 boots : source_color = vec4(0.16, 0.12, 0.09, 1.0);
uniform vec4 mail : source_color = vec4(0.34, 0.34, 0.38, 1.0);
uniform vec4 helmet : source_color = vec4(0.46, 0.46, 0.5, 1.0);
group_uniforms;

group_uniforms Surcoat;
// Three cloths, chosen per instance. Keep them far apart in hue -- their whole job is to be
// findable against a brown field.
uniform vec4 cloth_a : source_color = vec4(0.55, 0.15, 0.11, 1.0);
uniform vec4 cloth_b : source_color = vec4(0.17, 0.22, 0.42, 1.0);
uniform vec4 cloth_c : source_color = vec4(0.36, 0.30, 0.18, 1.0);
group_uniforms;

group_uniforms Light;
// TWO STEPS, not the environment four. A fourth tonal plate on a thirty-pixel figure lands on one
// or two pixels, which reads as dirt on the silhouette rather than as form.
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float bands : hint_range(1.0, 6.0, 1.0) = 2.0;
uniform float band_softness : hint_range(0.01, 0.5, 0.01) = 0.04;
uniform vec4 shade_tint : source_color = vec4(0.42, 0.38, 0.52, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.46;
uniform float shade_saturation : hint_range(0.0, 2.0, 0.05) = 1.3;
uniform vec4 light_tint : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float light_tint_amount : hint_range(0.0, 1.0, 0.05) = 0.4;
group_uniforms;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying float body_h;
varying float variant;

vec3 saturate_rgb(vec3 c, float amount) {
	return mix(vec3(dot(c, LUMA)), c, amount);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Model space, so the zones stay put whatever the figure is standing on or scaled to.
	body_h = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	// MODEL_MATRIX[3] is the instance origin in world space: one hash per figure, stable across
	// frames because the figures do not move.
	variant = hash21(MODEL_MATRIX[3].xz * 3.17);
}

void fragment() {
	vec3 cloth = variant < 0.4 ? cloth_a.rgb : (variant < 0.75 ? cloth_b.rgb : cloth_c.rgb);

	// step(), not smoothstep(): a blended boundary between a surcoat and mail is a grey band, and a
	// grey band at this scale is the whole of the surcoat.
	vec3 col = boots.rgb;
	col = mix(col, cloth, step(hem, body_h));
	col = mix(col, mail.rgb, step(chest, body_h));
	col = mix(col, helmet.rgb, step(collar, body_h));

	ALBEDO = col;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float l = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	float m = l * bands;
	float b = floor(m);
	l = (b + smoothstep(0.5 - band_softness, 0.5 + band_softness, m - b)) / bands;
	vec3 shadow_side = saturate_rgb(ALBEDO * shade_tint.rgb, shade_saturation) * shade_strength;
	shadow_side *= ATTENUATION;
	vec3 lit_side = mix(ALBEDO, ALBEDO * light_tint.rgb, light_tint_amount);
	DIFFUSE_LIGHT += mix(shadow_side, lit_side, l) * (LIGHT_COLOR / PI);
}
