// Rectangular world-space section, aligned with the owning architectural volume.
instance uniform vec3 reveal_focus = vec3(0.0);
instance uniform vec3 reveal_camera = vec3(0.0, 10.0, 10.0);
instance uniform float reveal_radius = 0.0;
instance uniform vec3 reveal_box_center = vec3(0.0);
instance uniform vec3 reveal_box_right = vec3(1.0,0.0,0.0);
instance uniform vec3 reveal_box_forward = vec3(0.0,0.0,1.0);
varying vec3 reveal_world;
void architecture_reveal(vec2 fragcoord) {
 if (reveal_radius <= 0.01 || reveal_world.y < reveal_focus.y + 0.35) return;
 vec3 direction = normalize(reveal_camera-reveal_focus);
 if(dot(reveal_world-reveal_focus,direction)<=0.2) return;
 vec3 delta=reveal_world-reveal_box_center;
 if(abs(dot(delta,reveal_box_right))<reveal_radius && abs(dot(delta,reveal_box_forward))<reveal_radius) discard;
}
