shader_type spatial;
render_mode world_vertex_coords;
uniform sampler2D painting : source_color,filter_nearest,repeat_disable;
varying vec3 p;
void vertex(){p=VERTEX;}
void fragment(){
 vec2 q=vec2((p.x+p.z)*.707107,(p.z-p.x)*.707107);
 vec2 uv=(q-vec2(0,3.0))/32.0+.5;
 uv=(floor(uv*1100.0)+.5)/1100.0;
 ALBEDO=texture(painting,uv).rgb*vec3(.62,.59,.55);
 ROUGHNESS=1.0;SPECULAR=0.0;
}
