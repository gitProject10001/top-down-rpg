// Disabled in authored scenes; Play sets these per mesh without changing materials.
instance uniform vec3 reveal_focus = vec3(0.0);
instance uniform vec3 reveal_camera = vec3(0.0, 10.0, 10.0);
instance uniform float reveal_radius = 0.0;
varying vec3 reveal_world;
void architecture_reveal(vec2 fragcoord) {
	if (reveal_radius <= 0.01 || reveal_world.y < reveal_focus.y + 0.35) { return; }
	vec3 direction = normalize(reveal_camera - reveal_focus);
	vec3 delta = reveal_world - reveal_focus;
	float along = dot(delta, direction);
	if (along <= 0.2) { return; }
	float distance_to_ray = length(delta - direction * along);
	float coverage = 1.0 - smoothstep(reveal_radius - 0.35, reveal_radius, distance_to_ray);
	coverage *= smoothstep(0.2, 0.65, along);
	float pixel = fract(sin(dot(floor(fragcoord), vec2(12.9898, 78.233))) * 43758.5453);
	if (coverage > pixel) { discard; }
}
