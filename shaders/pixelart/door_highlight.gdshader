shader_type spatial;
render_mode unshaded, cull_front;
void vertex() { VERTEX += NORMAL*0.055; }
void fragment() { ALBEDO=vec3(0.9,0.6,0.18); }
