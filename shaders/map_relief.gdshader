shader_type canvas_item;
// THE WORLD YOU CANNOT WALK ON. MapRelief's flat unshaded capture, reduced to a few tonal bands and
// tinted into the sheet's palette so it reads as drawn terrain rather than as a screenshot lying
// under the map.
//
// DELIBERATELY QUIET. This layer exists to give the walkable plan somewhere to BE — without it the
// hub reads as a sock floating in cloud. It must never compete with the ink: low contrast, low
// alpha, and posterised hard enough that no individual prop is legible. If you can tell what a
// bush is, this is turned up too far.

uniform sampler2D relief : filter_linear, repeat_disable, hint_default_transparent;
/// Terrain is only drawn where it was SEEN. Without this the whole level would be sitting under the
/// fog from the first frame, and a keen eye could read the map's shape straight through the cloud.
uniform sampler2D vista : filter_linear, repeat_disable, hint_default_black;
uniform vec2 map_uv_origin = vec2(0.0);
uniform vec2 map_uv_size = vec2(1.0);
uniform vec3 tint_low : source_color = vec3(0.60, 0.53, 0.40);
uniform vec3 tint_high : source_color = vec3(0.80, 0.73, 0.59);
uniform float bands = 4.0;
uniform float strength = 0.55;

void fragment() {
	vec2 guv = (UV - map_uv_origin) / max(map_uv_size, vec2(0.0001));
	if (guv.x < 0.0 || guv.x > 1.0 || guv.y < 0.0 || guv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec4 s = texture(relief, guv);
		// Luminance, not hue: the capture carries the level's real albedo, and letting green grass
		// and red brick through would make the sheet look like a screenshot with a filter on it.
		float lum = dot(s.rgb, vec3(0.299, 0.587, 0.114));
		lum = floor(lum * bands + 0.5) / bands;
		float known = smoothstep(0.08, 0.5, texture(vista, guv).r);
		COLOR = vec4(mix(tint_low, tint_high, lum), s.a * strength * known);
	}
}
