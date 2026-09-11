shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painting : source_color,filter_nearest;
uniform vec4 tint : source_color = vec4(1);
void fragment(){
 vec2 uv=(floor(UV*256.0)+.5)/256.0;
 vec4 c=texture(painting,uv);
 ALPHA=c.a;
 ALPHA_SCISSOR_THRESHOLD=.5;
 float value=dot(c.rgb,vec3(.299,.587,.114));
 ALBEDO=mix(vec3(value),c.rgb,.72)*tint.rgb;
 ROUGHNESS=1.0;SPECULAR=0.0;
}
void light(){
 // Keep the painted albedo, but let the lobe normals and real shadows shape light.
 float diffuse=clamp((dot(NORMAL,LIGHT)+.12)/1.12,0.0,1.0);
 float bands=floor(diffuse*5.0)/5.0;
 float value=mix(diffuse,bands,.30);
 DIFFUSE_LIGHT+=LIGHT_COLOR*value*ATTENUATION/3.14159;
}
