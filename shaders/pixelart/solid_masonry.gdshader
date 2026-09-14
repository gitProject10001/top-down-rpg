shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local_position;
void vertex() { local_position=VERTEX; }
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
void fragment() {
 float grain=hash(floor(local_position*85.0));
 float mottling=sin(local_position.x*11.0+sin(local_position.y*17.0))*sin(local_position.z*9.0+local_position.y*13.0);
 // Shared deposits cross the joints and unite adjacent stones visually.
 float cloud=0.5+0.5*sin(local_position.x*0.72+sin(local_position.y*1.1))*sin(local_position.y*0.81+0.7);
 float damp=(1.0-smoothstep(0.0,0.85,local_position.y))*(0.5+0.5*cloud);
 vec3 pigment=mix(COLOR.rgb,COLOR.rgb*vec3(0.74,0.79,0.70),damp*0.55);
 ALBEDO=pigment*(0.84+0.22*cloud+0.04*grain+0.035*mottling);
 ROUGHNESS=0.9; SPECULAR=0.06;
 AO=COLOR.a; AO_LIGHT_AFFECT=0.35;
}
