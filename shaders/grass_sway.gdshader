shader_type spatial;
// Painterly grass-tuft material: flat matte color from vertex colors (× per-instance
// MultiMesh tint), with a gentle wind sway on the blade TIPS only.
//
// UV.y encodes normalized blade height (0 = root, 1 = tip), so the sway weight keeps
// roots planted. The phase is driven by world position, so neighbouring tufts move
// slightly out of step — reads as wind, not as a single rigid wobble.
render_mode cull_disabled, specular_disabled;

uniform float sway_strength = 0.05;
uniform float sway_speed = 1.4;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * sway_speed + wp.x * 0.9 + wp.z * 0.7;
	VERTEX.x += sin(phase) * sway_strength * UV.y;
	VERTEX.z += cos(phase * 0.8) * sway_strength * 0.6 * UV.y;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
