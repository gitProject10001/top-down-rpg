shader_type spatial;
// BILLBOARD grass card (A/B experiment vs the geometry tufts in grass_sway.gdshader).
//
// CYLINDRICAL billboarding: each card rotates around Y to face the camera but stays upright —
// full spherical billboarding would tip the cards toward our steep top-down camera and they'd
// read as stickers lying on the lawn. The card's look comes from a texture with alpha; we use
// ALPHA_SCISSOR (cutout) so the pass stays depth-writing and cheap-ish, but overlapping cards
// still cost overdraw — that's the billboard trade.
render_mode cull_disabled, specular_disabled;

uniform sampler2D grass_tex : source_color, filter_linear;
uniform float sway_strength = 0.06;
uniform float sway_speed = 1.4;

void vertex() {
	// preserve per-instance scale, replace rotation with camera-facing yaw
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 fwd = INV_VIEW_MATRIX[2].xyz;
	fwd.y = 0.0;
	fwd = normalize(fwd);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	mat4 bb = mat4(vec4(right * sx, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	// wind: sway the TOP of the card (UV.y = 0 at top for QuadMesh), phased by world position
	float tip = 1.0 - UV.y;
	float phase = TIME * sway_speed + MODEL_MATRIX[3][0] * 0.9 + MODEL_MATRIX[3][2] * 0.7;
	VERTEX.x += sin(phase) * sway_strength * tip;
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(grass_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;                 // texture × per-instance tint
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // shade like the lawn
	ROUGHNESS = 1.0;
}
