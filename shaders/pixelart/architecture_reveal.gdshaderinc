// Shared by the reveal and the real cross-section geometry.
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
 vec3 right = normalize(cross(direction, vec3(0,1,0)));
 vec3 up = cross(right, direction);
 float angle = atan(dot(delta,up),dot(delta,right));
 float radius = reveal_radius + along*0.16 + 0.065*sin(angle*13.0) + 0.035*sin(angle*29.0+1.2);
 if (length(delta-direction*along) < radius) { discard; }
}
