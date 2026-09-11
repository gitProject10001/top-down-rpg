shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// THE MATERIAL CARRIES render_priority = 1 (water_ring.tscn), and it is load-bearing: the
// water surface is itself a transparent material, so both it and this ring sort in the
// transparent pass, where Godot orders equal priorities by distance-to-origin. A lake plane's
// origin is its region CENTRE, which can sit nearer the camera than a ring 3 cm above the
// water at the far end of that same lake — and the ring then draws UNDER the water it belongs
// on top of, flickering as the camera moves. Priority takes the ordering out of the
// geometry's hands. 3 cm of height alone cannot, because depth_draw_never writes no depth.
// THE SPLASH ACCENT (WA3): one crisp foam annulus expanding and fading on a flat quad laid in
// the water plane — the ripple FIELD carries the physical wave, this is the stylized white
// ring on top. Flat on the ground because the camera is fixed at 53 degrees down and only
// ground-plane FX read at that pitch (dash.gd:30 records the measurement); unshaded because
// water never touches the lighting model in this project (water_stylized.gdshader's header).

uniform vec4 ring_color : source_color = vec4(0.92, 0.97, 0.97, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring_r = mix(0.15, 0.92, progress);
	float w = mix(0.10, 0.035, progress);
	float a = (1.0 - smoothstep(w, w * 1.6, abs(r - ring_r))) * (1.0 - progress);
	ALBEDO = ring_color.rgb;
	ALPHA = a * ring_color.a * 0.9;
}
