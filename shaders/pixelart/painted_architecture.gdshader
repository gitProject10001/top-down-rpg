shader_type spatial;
#include "res://shaders/pixelart/architecture_reveal.gdshaderinc"
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
uniform vec2 quadrant=vec2(0,0.5);
uniform vec4 tint : source_color=vec4(1);
uniform float metres=2.5;
uniform float detail_lod=1.0;
uniform bool masonry_relief = true;
uniform bool plain_vertical_stone = false;
uniform float masonry_depth : hint_range(0.0,0.09) = 0.07;
float stone_hash(vec2 v) { return fract(sin(dot(v,vec2(127.1,311.7)))*43758.5453); }
// Metre-scale joints and bevels; no directional lighting baked into pigment.
vec4 stone_field(vec2 uv) {
 float y=uv.y+0.025*sin(uv.x*1.8)+0.012*sin(uv.x*5.1);
 float row=floor(y/0.43);
 float offset=stone_hash(vec2(row,7.0))*0.82;
 float x=uv.x+offset;
 float column=floor(x/0.85);
 float left=column*0.85+0.20*(stone_hash(vec2(column,row))-0.5);
 if(x<left) column-=1.0;
 float right=(column+1.0)*0.85+0.20*(stone_hash(vec2(column+1.0,row))-0.5);
 if(x>right) column+=1.0;
 left=column*0.85+0.20*(stone_hash(vec2(column,row))-0.5);
 right=(column+1.0)*0.85+0.20*(stone_hash(vec2(column+1.0,row))-0.5);
 float width=right-left;
 vec2 cell=vec2(column,row);
 vec2 local=vec2(x-left,fract(y/0.43)*0.43);
 float seed=stone_hash(cell);
 float chip=0.008*sin(uv.x*43.0+seed*20.0)*sin(uv.y*51.0)+0.004*sin(uv.x*97.0+uv.y*73.0);
 vec2 d=vec2(min(local.x,width-local.x),min(local.y,0.43-local.y));
 float corner=0.025+0.025*seed;
 float edge=min(min(d.x,d.y),(d.x+d.y-corner)*0.707)+chip;
 float bevel=smoothstep(0.018,0.11,edge);
 float face=0.82+0.18*seed+0.055*sin(uv.x*8.0+seed*13.0)*sin(uv.y*11.0);
 return vec4(bevel*face,bevel,seed,edge);
}
// Mixed flagstones on horizontal masonry, rather than the vertical brick courses.
vec4 paving_field(vec2 uv) {
 float row=floor(uv.y/1.35);
 vec2 q=vec2(uv.x+stone_hash(vec2(row,31.0))*1.8,uv.y);
 vec2 cell=floor(q/vec2(1.85,1.35));
 vec2 local=mod(q,vec2(1.85,1.35));
 vec2 size=vec2(1.85,1.35);
 float choice=stone_hash(cell+13.0);
 float part=0.0;
 if(choice<0.65) {
  float split=0.64+0.55*stone_hash(cell+7.0);
  if(local.x>split) { local.x-=split; size.x-=split; part=1.0; }
  else size.x=split;
  if(choice<0.30 && part>0.5) {
   float split_y=0.49+0.30*stone_hash(cell+23.0);
   if(local.y>split_y) { local.y-=split_y; size.y-=split_y; part=3.0; }
   else { size.y=split_y; part=2.0; }
  }
 }
 float seed=stone_hash(cell+vec2(part*19.0,part*7.0));
 vec2 d=min(local,size-local);
 float edge=min(min(d.x,d.y),(d.x+d.y-0.022-seed*0.025)*0.707);
 edge+=0.004*sin(uv.x*53.0+uv.y*37.0+seed*13.0);
 float bevel=smoothstep(0.008,0.045,edge);
 return vec4(bevel*(0.85+0.15*seed),bevel,seed,edge);
}
varying vec3 p;
varying vec3 norm;
void vertex(){ reveal_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;p=VERTEX;norm=NORMAL;}
void fragment(){ architecture_reveal(FRAGCOORD.xy);
 vec3 a=abs(norm);
 vec2 uv=a.y>max(a.x,a.z)?p.xz:(a.x>a.z?p.zy:p.xy);
 uv=fract(uv*vec2(1,-1)/metres)*.497+quadrant+.0015;
 ALBEDO=textureLod(atlas,uv,detail_lod).rgb*tint.rgb;
 ROUGHNESS=1.0;SPECULAR=0.0;
 if(masonry_relief && quadrant.x<0.1 && quadrant.y>0.4) {
  vec2 stone_uv=a.y>max(a.x,a.z)?p.xz:(a.x>a.z?p.zy:p.xy);
  bool horizontal=a.y>max(a.x,a.z);
  vec4 stone=horizontal?paving_field(stone_uv):stone_field(stone_uv);
  // Broad atlas colour preserves the established palette without duplicating joints.
  vec3 pigment=vec3(0.32,0.33,0.31)*tint.rgb;
  float aa=max(fwidth(stone.w),0.002);
  float mortar=smoothstep(0.008-aa,0.030+aa,stone.w);
  ALBEDO=pigment*mix(0.40,0.72+0.48*stone.z,mortar)*(0.97+0.06*stone_hash(floor(stone_uv*48.0)));
  vec3 surface_normal=NORMAL;
  float height=stone.x*(horizontal?0.022:masonry_depth);
  vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
  vec3 r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
  float det=dot(dx,r1);
  NORMAL=normalize(abs(det)*NORMAL-sign(det)*(dFdx(height)*r1+dFdy(height)*r2));
  AO=mix(0.24,1.0,stone.y); AO_LIGHT_AFFECT=0.65;
  ROUGHNESS=mix(0.98,0.83,stone.y); SPECULAR=0.18;
  if(plain_vertical_stone && !horizontal) {
   ALBEDO=vec3(0.16,0.155,0.14)*(0.97+0.04*stone_hash(floor(stone_uv*48.0)));
   NORMAL=surface_normal; AO=0.62; ROUGHNESS=0.96; SPECULAR=0.06;
  }
 }
}
