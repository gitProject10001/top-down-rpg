shader_type spatial;
render_mode world_vertex_coords;
varying vec3 pos;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){pos=VERTEX;}
void fragment(){
 vec2 p=floor(pos.xz*22.0)/22.0;
 float broad=noise(p*0.65)*0.65+noise(p*2.4)*0.35;
 float flecks=noise(p*10.0);
 float path=1.0-smoothstep(2.1,4.8,abs(p.x-p.y*0.65+1.0));
 vec3 earth=mix(vec3(0.26,0.155,0.105),vec3(0.43,0.28,0.17),floor(broad*5.0)/4.0);
 earth=mix(earth,vec3(0.39,0.255,0.165),path*0.48);
 float moss=step(0.57,broad)*(1.0-path*0.85)*step(0.48,flecks);
 earth=mix(earth,vec3(0.36,0.32,0.16),moss*0.7);
 earth*=1.0+(step(0.68,flecks)-step(flecks,0.26))*0.13;
 ALBEDO=earth; ROUGHNESS=1.0; SPECULAR=0.0;
}
void light(){
 float shade=floor(clamp(dot(NORMAL,LIGHT)*0.65+0.35,0.0,1.0)*4.0)/4.0;
 DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*(0.08+shade*ATTENUATION*0.38)/3.14159;
}
