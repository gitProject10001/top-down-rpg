shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo_color : source_color=vec4(.4,.3,.2,1);
uniform float mail=0.0;
varying vec3 p;
void vertex(){p=VERTEX;}
void fragment(){
 vec2 cell=floor(p.xy*125.0);
 float link=mod(cell.x+cell.y,2.0);
 ALBEDO=albedo_color.rgb*mix(1.0,.82+link*.18,mail);
 ROUGHNESS=.91;SPECULAR=.08;
}
