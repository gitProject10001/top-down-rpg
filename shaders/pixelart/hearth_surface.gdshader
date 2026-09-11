shader_type spatial;
render_mode cull_disabled;
uniform vec4 paint : source_color = vec4(0.5,0.35,0.25,1.0);
varying vec3 p;
float h(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
void vertex(){p=VERTEX;}
void fragment(){
 vec3 q=floor(p*24.0)/24.0;
 float grain=h(floor(q.xy*23.0)+floor(q.z*17.0));
 float patches=h(floor(q.xy*2.0)+floor(q.z*2.0));
 ALBEDO=paint.rgb*(0.80+floor(grain*3.0)*0.045+patches*.20);
 ROUGHNESS=1.0;SPECULAR=0.0;
}
void light(){
 float n=clamp(dot(NORMAL,LIGHT)*0.7+0.3,0.0,1.0);
 float stepped=floor(n*5.0)/5.0;
 DIFFUSE_LIGHT+=LIGHT_COLOR*(0.12+stepped*ATTENUATION*.70)/3.14159;
}
