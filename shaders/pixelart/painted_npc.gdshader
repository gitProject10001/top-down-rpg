shader_type spatial;
uniform vec4 boots : source_color = vec4(.26,.20,.15,1);
uniform vec4 mail : source_color = vec4(.38,.39,.40,1);
uniform vec4 helmet : source_color = vec4(.52,.51,.49,1);
uniform vec4 cloth_a : source_color = vec4(.50,.25,.20,1);
uniform vec4 cloth_b : source_color = vec4(.34,.38,.43,1);
uniform vec4 cloth_c : source_color = vec4(.44,.39,.28,1);
varying float height;
varying float variant;
void vertex(){height=clamp(VERTEX.y+.5,0.0,1.0);variant=fract(sin(dot(MODEL_MATRIX[3].xz,vec2(37.2,11.7)))*435.1);}
void fragment(){
 vec3 cloth=variant<.4?cloth_a.rgb:(variant<.75?cloth_b.rgb:cloth_c.rgb);
 vec3 c=boots.rgb;
 if(height>.3)c=cloth;
 if(height>.62)c=mail.rgb;
 if(height>.79)c=helmet.rgb;
 ALBEDO=c;ROUGHNESS=1.0;SPECULAR=0.0;
}
