shader_type spatial;
render_mode diffuse_burley, specular_disabled;
#include "res://shaders/pixelart/architecture_reveal.gdshaderinc"
#include "res://shaders/pixelart/stone_pigment.gdshaderinc"
#include "res://addons/house_builder/masonry_finish.gdshaderinc"
uniform int surface_kind = 0;
uniform bool window_surface = false;
uniform float night_strength = 0.0;
uniform bool weathered = true;
uniform float pattern_seed = 0.0;
uniform bool cutaway_enabled = false;
uniform float cutaway_height = 1.05;
varying vec3 detail_position;
varying vec3 detail_normal;
float detail_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)) + pattern_seed*.07)*43758.5453); }
float detail_noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(detail_hash(i),detail_hash(i+vec2(1,0)),f.x),mix(detail_hash(i+vec2(0,1)),detail_hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 detail_position=VERTEX; detail_normal=NORMAL;
 reveal_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
 if(cutaway_enabled && detail_position.y > cutaway_height) discard;
 architecture_reveal(FRAGCOORD.xy);
 vec3 n=abs(detail_normal);
 vec2 uv=n.y>max(n.x,n.z)?detail_position.xz:(n.x>n.z?detail_position.zy:detail_position.xy);
 float cloud=detail_noise(uv*3.7);
 vec2 grain_scale=surface_kind==0?vec2(23.0,2.0):vec2(15.0,19.0);
 float stroke=detail_noise(uv*grain_scale+cloud*.65);
 vec3 pigment=mix(COLOR.rgb*vec3(.88,.94,1.02),COLOR.rgb*vec3(1.09,1.04,.93),cloud);
 pigment*=mix(.92,1.08,smoothstep(.36,.65,stroke));
 if(weathered && (surface_kind==0 || surface_kind==1)) {
  float damp=(1.0-smoothstep(.03,.37,detail_position.y))*smoothstep(.32,.76,cloud);
  pigment=mix(pigment,pigment*vec3(.65,.76,.67),damp*.46);
 }
 ALBEDO=pigment;
 ROUGHNESS=1.0; SPECULAR=0.0;
 AO=mix(.77,1.0,smoothstep(.02,.22,detail_position.y));
 AO_LIGHT_AFFECT=.6;
 if(masonry_finish_enabled) {
  vec3 wear=vec3(masonry_weathering);
  if(anime_painted) wear*=vec3(art_layer(2,reveal_world,moss_amount),art_layer(3,reveal_world,damp_amount),art_layer(4,reveal_world,damage_amount))/vec3(.35,.25,.20);
  vec4 finish=masonry_finish(COLOR.rgb,detail_position,detail_normal,AO,clamp(wear,vec3(0),vec3(1)));
  ALBEDO=finish.rgb; AO=finish.a;
  if(masonry_courses) NORMAL=masonry_relief_normal(VERTEX,NORMAL,finish.a*.016);
 }
 if(window_surface) EMISSION=vec3(.80,.36,.08)*night_strength*(.7+.3*cloud);
}
