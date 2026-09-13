shader_type spatial;
render_mode unshaded, cull_disabled;
uniform bool hollow = false;
uniform float floor_height = 0.0;
uniform vec3 focus;
uniform vec3 view_direction;
varying vec3 world;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz; }
void fragment() {
 if(world.y < floor_height || dot(world-focus,view_direction)<=0.2) discard;
 // Irregular stone cells in the exposed core, independent of the outside atlas.
 vec3 p=world*2.8;
 vec3 cell=floor(p);
 float first=10.0; float second=10.0; float pigment=0.0;
 for(int x=-1;x<=1;x++) for(int y=-1;y<=1;y++) for(int z=-1;z<=1;z++) {
  vec3 c=cell+vec3(float(x),float(y),float(z));
  vec3 seed=c+vec3(hash(c),hash(c+17.0),hash(c+37.0));
  float d=length(p-seed);
  if(d<first) { second=first; first=d; pigment=hash(c+5.0); }
  else if(d<second) second=d;
 }
 float joint=smoothstep(0.025,0.09,second-first);
 vec3 stone=mix(vec3(0.055,0.035,0.018),vec3(0.16,0.105,0.052),pigment);
 ALBEDO=hollow?vec3(0.0):mix(vec3(0.009,0.005,0.002),stone,joint);
}
