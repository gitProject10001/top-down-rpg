shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painting : source_color,filter_nearest_mipmap;
void fragment(){
 vec3 c=textureLod(painting,UV*.497+vec2(.0015,.5015),2.0).rgb;
 ALBEDO=c*.60;ROUGHNESS=1.0;SPECULAR=0.0;
}
