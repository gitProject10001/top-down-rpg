shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
// Inverted-hull ink outline — the classic anime object line. Used as the next_pass of toon_lit:
// render the BACK faces (cull_front) pushed OUT along the normal, in a dark flat colour. From the
// front they peek out just past the silhouette as a clean outline.
//
// The push is done in VIEW space so its thickness is a world-space amount independent of the model's
// scale (our characters are imported at very different scales: player Model ~1.28, enemy ~2.2). With
// the fixed-distance camera this also reads as a near-constant on-screen line width.

uniform float outline_width : hint_range(0.0, 0.1) = 0.02;   // view-space metres
uniform vec4 outline_color : source_color = vec4(0.05, 0.04, 0.06, 1.0);

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	view.xyz += view_n * outline_width;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
