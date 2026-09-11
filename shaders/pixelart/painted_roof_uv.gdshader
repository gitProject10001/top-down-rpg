shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painting : source_color,filter_nearest_mipmap;
uniform vec2 repeats=vec2(3,1.5);
void fragment(){
 vec2 uv=fract(UV*repeats)*.497+.0015;
 vec3 c=textureLod(painting,uv,1.5).rgb;
 ALBEDO=c*vec3(.64,.59,.55);
 ROUGHNESS=1.0;SPECULAR=0.0;
}
