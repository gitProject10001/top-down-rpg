shader_type canvas_item;
// Painterly screen grade: split-toning + vignette.
//
// WHY: painters don't shade with black — shadow and light differ in COLOR (cool shadows, warm
// lights), and a canvas darkens gently toward its edges. This pass nudges the rendered frame
// that way: dark regions drift teal, bright regions drift cream, and a soft vignette frames the
// view. Strengths are deliberately low — it should read as "hand-painted", not "instagram filter".

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float split_strength : hint_range(0.0, 1.0) = 0.14;   // how hard shadows/highlights are tinted
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.2; // corner darkening
// THE SAME SHADOW COLOUR THE SURFACE SHADER USES. This was teal (0.55, 0.73, 0.8), hue ~0.53, while
// painted_env.gdshader's shade_tint is blue-violet at hue ~0.63 — so wherever both passes applied,
// the grade was pulling the shadows back out of the colour the surface shader had just put them in.
// Measured off docs/images/references/whinbek-conceptart.jpg, the reference's own dark quartile
// sits at hue 0.64, which settles the argument in the surface shader's favour.
uniform vec3 shadow_tint : source_color = vec3(0.58, 0.62, 0.82);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.94, 0.82); // warm cream for the lights

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	// Split-tone by luminance: darks multiply toward teal, lights toward warm cream.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 toned = col * mix(shadow_tint, highlight_tint, smoothstep(0.0, 0.9, lum));
	col = mix(col, toned, split_strength);

	// Soft vignette — full brightness in the middle ~2/3, easing down toward the corners.
	float d = length(SCREEN_UV - 0.5) * 1.4142;
	float vig = smoothstep(0.95, 0.4, d);
	col *= mix(1.0 - vignette_strength, 1.0, vig);

	COLOR = vec4(col, 1.0);
}
