uniform bool masonry_finish_enabled=false;
uniform vec3 masonry_tint=vec3(.32,.305,.27);
uniform vec2 masonry_block_size=vec2(.72,.37);
uniform float masonry_weathering=.5;
uniform float masonry_source_value=.205;
uniform bool masonry_courses=false;
uniform float masonry_height_offset=0.0;
uniform vec4 masonry_ledge_heights=vec4(-100.0);
float mason_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float mason_noise(vec2 p) {
 vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mason_hash(i),mason_hash(i+vec2(1,0)),f.x),mix(mason_hash(i+vec2(0,1)),mason_hash(i+vec2(1,1)),f.x),f.y);
}
// Returns painted pigment and contact occlusion. Joints belong only to broad
// masonry panels; carved frames keep their actual geometric seams.
vec4 masonry_finish(vec3 base,vec3 p,vec3 face,float cavity,vec3 wear) {
 p.y+=masonry_height_offset;
 vec3 a=abs(face);
 vec2 uv=a.y>max(a.x,a.z)?p.xz:(a.x>a.z?p.zy:p.xy);
 float row=floor(uv.y/masonry_block_size.y);
 float shifted=uv.x+(mod(row,2.0)*.5+.10*mason_hash(vec2(row,13.0)))*masonry_block_size.x;
 vec2 cell=vec2(shifted,uv.y)/masonry_block_size;
 vec2 edge=min(fract(cell),1.0-fract(cell))*masonry_block_size;
 float joint_width=.009;
 float aa=max(fwidth(uv.x),fwidth(uv.y))*.65;
 float seam=1.0-smoothstep(joint_width-aa,joint_width+aa,min(edge.x,edge.y));
 seam*=float(masonry_courses && a.y<.75);
 float variance=masonry_courses?mix(.91,1.08,mason_hash(floor(cell))):1.0;
 float value=clamp(dot(base,vec3(.333333))/max(.01,masonry_source_value),.72,1.18);
 float broad=mason_noise(uv*1.8);
 float stroke=mason_noise(uv*vec2(12,19)+broad*.5);
 vec3 pigment=masonry_tint*value*variance;
 pigment*=mix(vec3(.91,.98,1.06),vec3(1.08,1.025,.92),broad);
 pigment*=mix(.96,1.045,smoothstep(.42,.65,stroke));
 pigment*=1.0-seam*.26;
 float basal=1.0-smoothstep(.12,1.4,p.y);
 float recess=max(1.0-cavity,seam*.60);
 float shelf=max(face.y,0.0)*.4;
 float under_ledge=0.0;
 for(int i=0;i<4;i++) {
  float below=masonry_ledge_heights[i]-p.y;
  under_ledge=max(under_ledge,step(0.0,below)*(1.0-smoothstep(.03,.65,below)));
 }
 float habitat=clamp(basal*.72+recess*.6+shelf+under_ledge*.55,0,1);
 float islands=smoothstep(.48,.72,mason_noise(uv*4.7+broad));
 float moss=habitat*islands*wear.x;
 pigment=mix(pigment,vec3(.105,.145,.078),moss*.65);
 float drip=smoothstep(.55,.76,mason_noise(uv*vec2(14,.85)));
 pigment*=1.0-drip*habitat*wear.y*.25;
 // Sparse broken hairline cracks concentrated at joints and the wall base.
 float wave=sin(uv.x*19.0+uv.y*3.0+mason_noise(uv*3.0)*5.0);
 float crack=(1.0-smoothstep(.025,.10,abs(wave)))*smoothstep(.70,.85,mason_noise(uv*1.2+17.0));
 pigment*=1.0-crack*habitat*wear.z*.35;
 return vec4(pigment,clamp(cavity*(1.0-seam*.2),.48,1.0));
}
vec3 masonry_relief_normal(vec3 position,vec3 normal,float height) {
 vec3 dx=dFdx(position),dy=dFdy(position);
 vec3 r1=cross(dy,normal),r2=cross(normal,dx);
 float determinant=dot(dx,r1);
 vec3 gradient=sign(determinant)*(dFdx(height)*r1+dFdy(height)*r2);
 return normalize(abs(determinant)*normal-gradient);
}
