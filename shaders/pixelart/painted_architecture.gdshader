shader_type spatial;
#include "res://shaders/pixelart/architecture_reveal.gdshaderinc"
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
uniform vec2 quadrant=vec2(0,0.5);
uniform vec4 tint : source_color=vec4(1);
uniform float metres=2.5;
uniform float detail_lod=1.0;
uniform bool masonry_relief = true;
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
  vec4 stone=stone_field(stone_uv);
  // Broad atlas colour preserves the established palette without duplicating joints.
  vec3 pigment=vec3(0.32,0.33,0.31)*tint.rgb;
  float aa=max(fwidth(stone.w),0.002);
  float mortar=smoothstep(0.008-aa,0.030+aa,stone.w);
  ALBEDO=pigment*mix(0.40,0.72+0.48*stone.z,mortar)*(0.97+0.06*stone_hash(floor(stone_uv*48.0)));
  float height=stone.x*masonry_depth;
  vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
  vec3 r1=cross(dy,NORMAL),r2=cross(NORMAL,dx);
  float det=dot(dx,r1);
  NORMAL=normalize(abs(det)*NORMAL-sign(det)*(dFdx(height)*r1+dFdy(height)*r2));
  AO=mix(0.38,1.0,stone.y); AO_LIGHT_AFFECT=0.55;
  ROUGHNESS=mix(0.98,0.83,stone.y); SPECULAR=0.18;
 }
}
