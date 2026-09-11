shader_type spatial;
render_mode cull_disabled;
void fragment(){ ALBEDO=vec3(.20,.225,.095)*mix(.85,1.18,COLOR.r); ROUGHNESS=1.0; SPECULAR=0.0; }
void light(){
 float d=clamp((dot(NORMAL,LIGHT)+.22)/1.22,0.0,1.0);
 DIFFUSE_LIGHT+=LIGHT_COLOR*mix(d,floor(d*4.0+.3)/4.0,.35)*ATTENUATION/3.14159;
}
