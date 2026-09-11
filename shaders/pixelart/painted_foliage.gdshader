shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
uniform sampler2D leaves : source_color, filter_nearest_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
void fragment(){
 vec4 c=textureLod(leaves,UV,2.0);
 if(c.a<0.5) discard;
 float value=dot(c.rgb,vec3(.299,.587,.114));
 ALBEDO=mix(vec3(value),c.rgb,.65)*tint.rgb*vec3(.80,.95,.82);
 ROUGHNESS=1.0; SPECULAR=0.0;
}
void light(){
 float wrap=clamp(dot(NORMAL,LIGHT)*.6+.4,0.0,1.0);
 DIFFUSE_LIGHT+=LIGHT_COLOR*(.12+wrap*.85)*mix(.35,1.0,ATTENUATION)/3.14159;
}
