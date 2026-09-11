shader_type spatial;
uniform vec4 albedo_color : source_color = vec4(1);
varying vec3 rest_position;
void vertex(){rest_position=VERTEX;}
void fragment(){
 vec3 p=rest_position;
 vec3 steel=vec3(.23,.25,.26),leather=vec3(.075,.043,.025),cloth=vec3(.19,.035,.027);
 vec3 c=steel;
 if(p.y<.55)c=leather;
 if(p.y>.70 && p.y<1.39 && abs(p.x)<.19)c=cloth;
 if(p.y>.86 && p.y<.94)c=leather;
 float chain=mod(floor(p.x*110.0)+floor(p.y*85.0),2.0);
 c*=.86+chain*.14;
 ALBEDO=c*albedo_color.rgb;ROUGHNESS=.93;SPECULAR=.06;
}
