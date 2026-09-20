shader_type spatial;
#include "res://shaders/pixelart/architecture_reveal.gdshaderinc"
#include "res://shaders/pixelart/stone_pigment.gdshaderinc"
uniform bool use_vertex_color=true;
uniform vec3 base_color=vec3(0.18,0.17,0.15);
uniform float stone_normal_flatten : hint_range(0.0,1.0) = 0.0;
uniform float stone_chip_strength : hint_range(0.0,1.0) = 1.0;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local_position;
varying vec3 face_normal;
void vertex() {
 local_position=VERTEX; face_normal=NORMAL;
 reveal_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 if(anime_painted) VERTEX+=stone_chip_offset(VERTEX,reveal_world)*stone_chip_strength;
}
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
void fragment() {
 architecture_reveal(FRAGCOORD.xy);
 vec3 geological_plane=normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));
 if(dot(geological_plane,NORMAL)<0.0) geological_plane=-geological_plane;
 NORMAL=normalize(mix(NORMAL,geological_plane,stone_normal_flatten));
 vec3 stone_color=use_vertex_color?COLOR.rgb:base_color;
 float grain=hash(floor(local_position*85.0));
 float mottling=sin(local_position.x*11.0+sin(local_position.y*17.0))*sin(local_position.z*9.0+local_position.y*13.0);
 // Shared deposits cross the joints and unite adjacent stones visually.
 float cloud=0.5+0.5*sin(local_position.x*0.72+sin(local_position.y*1.1))*sin(local_position.y*0.81+0.7);
 float damp=(1.0-smoothstep(0.0,0.85,local_position.y))*(0.5+0.5*cloud);
 vec3 pigment=mix(stone_color,stone_color*vec3(0.74,0.79,0.70),damp*0.55);
 ALBEDO=pigment*(0.84+0.22*cloud+0.04*grain+0.035*mottling);
 ROUGHNESS=0.9; SPECULAR=0.06;
 AO=use_vertex_color?COLOR.a:0.48; AO_LIGHT_AFFECT=0.65;
 if(anime_painted) {
  ALBEDO=painted_stone(pigment*(.92+.12*cloud),local_position,face_normal);
  ALBEDO=stone_weather(ALBEDO,local_position,face_normal,reveal_world,use_vertex_color?COLOR.a:0.5);
  ROUGHNESS=1.0; SPECULAR=0.0;
 }
}
