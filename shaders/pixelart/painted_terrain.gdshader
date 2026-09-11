shader_type spatial;
render_mode world_vertex_coords;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
varying vec3 p;
float hash(vec2 v){return fract(sin(dot(v,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 v){vec2 i=floor(v),f=fract(v); f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);}
void vertex(){p=VERTEX;}
void fragment(){
 vec2 q=vec2((p.x+p.z)*0.707107,(p.z-p.x)*0.707107);
 q=floor(q*75.0)/75.0;
 vec2 uv=fract(q/2.5)*0.497+0.0015;
 vec3 grass_tex=textureLod(atlas,uv,1.0).rgb;
 vec3 dirt_tex=textureLod(atlas,uv+vec2(0.5,0),1.0).rgb;
 float bend=sin(q.y*.24)*1.2;
 float lane=abs(q.x-bend-1.0);
 float square=length((q-vec2(0,3.8))/vec2(1.3,1.0));
 float edge=n(q*1.3)*0.8+n(q*6.0)*0.25;
 float grass_mask=smoothstep(3.3,4.2,lane+edge)*smoothstep(6.8,8.0,square+edge);
 float broad=n(q*.8)*.7+n(q*2.5)*.3;
 vec3 dirt=mix(vec3(.245,.183,.119),vec3(.355,.28,.185),broad);
 dirt=mix(pow(vec3(.37,.29,.20),vec3(2.2)),dirt_tex*vec3(.76,.78,.80),.58)*(.80+broad*.40);
 vec3 grass=mix(vec3(.125,.175,.083),vec3(.255,.29,.135),broad);
 grass=grass_tex*vec3(.75,.90,.80)*(.8+broad*.4);
 vec2 cell=floor(q*9.0),f=fract(q*9.0);
 float seed=hash(cell);
 float stroke=step(.50,seed)*step(abs(f.x-f.y*.34-.28),.19)*step(.26,f.y);
 grass+=vec3(.005,.007,.003)*stroke;
 grass*=1.0-step(.85,seed)*.18;
 float scuff=step(.75,hash(floor(q*vec2(5,12))))*step(fract(q.y*12.0),.22);
 dirt*=1.0-scuff*.04;
 vec3 color=mix(dirt,grass,grass_mask);
 // Long paired wheel marks follow the lane and are broken by patches of loose soil.
 float r1=abs(abs(q.x-bend-1.0)-.82);
 float r2=abs(abs(q.y-4.0-sin(q.x*.23)*1.4)-.75);
 float rut=1.0-smoothstep(.028,.07,min(r1,r2));
 rut*=step(.35,n(vec2(q.y*2.0,4.0)))*(1.0-grass_mask);
 color*=1.0-rut*.30;
 ALBEDO=color; ROUGHNESS=1.0; SPECULAR=0.0;
}
