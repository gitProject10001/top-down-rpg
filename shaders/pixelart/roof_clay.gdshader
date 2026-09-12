shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Unlit pigment only: no painted light direction, crevice outline or highlights.
// Tile colour is stored per vertex; actual overlapping geometry casts the shadows.
varying vec3 clay_position;
uniform float cavity_strength : hint_range(0.0,1.0) = 0.78;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex(){ clay_position=VERTEX; }
void fragment(){
 vec2 p=clay_position.xz;
 float cloud=noise(p*7.0)*0.65+noise(p*23.0)*0.35;
 float grain=noise(p*95.0);
 float streak=noise(p*vec2(32.0,140.0));
 ALBEDO=COLOR.rgb*(0.62+0.38*cloud+0.035*(grain-0.5));
 // UV2 is tile-local: a narrow side joint and the tucked upper overlap.
 // Derivative antialiasing keeps the joint stable at gameplay distance.
 float edge_distance=min(UV2.x,1.0-UV2.x);
 float aa=max(fwidth(UV2.x)*0.65,0.005);
 float side_joint=1.0-smoothstep(0.025-aa,0.075+aa,edge_distance);
 float overlap=smoothstep(0.49,0.63,UV2.y);
 float cavity=max(side_joint*0.62,overlap*0.72);
 AO=mix(1.0,min(COLOR.a,1.0-cavity),cavity_strength);
 AO_LIGHT_AFFECT=0.35;
 ROUGHNESS=clamp(0.79+0.17*cloud,0.0,1.0);
 METALLIC=0.0;
 SPECULAR=0.24;
 // Fracture backings use zero vertex pigment: no reflective glints in black holes.
 if (max(COLOR.r,max(COLOR.g,COLOR.b))<0.0001) { ALBEDO=vec3(0.0); SPECULAR=0.0; AO=0.0; }
 // Restrained clay grain, tangent-space; large relief belongs to the mesh.
 NORMAL_MAP=normalize(vec3((grain-0.5)*0.12,(streak-0.5)*0.10,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH=0.32;
}
