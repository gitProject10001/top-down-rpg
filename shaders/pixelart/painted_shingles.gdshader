shader_type spatial;
render_mode cull_disabled;
varying vec3 p;
float h(vec2 a){return fract(sin(dot(a,vec2(127.1,311.7)))*43758.5453);}
void vertex(){p=VERTEX;}
void fragment(){
 vec2 q=vec2(p.x,p.y*1.35+p.z*.1);
 q=floor(q*95.0)/95.0;
 float row=floor(q.y/.26);
 vec2 tile=vec2(q.x/.27+mod(row,2.0)*.5,q.y/.26);
 vec2 id=floor(tile),f=fract(tile);
 float seed=h(id);
 vec3 c=mix(vec3(.17,.105,.065),vec3(.35,.245,.155),seed);
 float grain=h(vec2(floor(f.x*17.0),id.x+id.y*9.0));
 c*=.88+grain*.22;
 c*=mix(.46,1.0,smoothstep(.015,.07,f.x));
 c*=mix(.43,1.0,smoothstep(.02,.16,f.y));
 c+=vec3(.055,.045,.028)*step(.88,f.y);
 float split=step(.96,h(vec2(floor(f.x*21.0),seed*60.0)))*smoothstep(.35,.95,f.y);
 c*=1.0-split*.43;
 ALBEDO=c;ROUGHNESS=1.0;SPECULAR=0.0;
}
