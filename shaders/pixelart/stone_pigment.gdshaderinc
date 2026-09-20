uniform bool anime_painted = false;
#include "res://shaders/pixelart/art_surface_edits.gdshaderinc"
uniform float moss_amount = .38;
uniform float damp_amount = .25;
uniform float damage_amount = .22;
uniform vec3 moss_color = vec3(.10,.18,.075);
uniform vec3 damp_color = vec3(.20,.24,.25);
float pigment_hash(vec2 p) {
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float pigment_noise(vec2 p) {
    vec2 i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(pigment_hash(i),pigment_hash(i+vec2(1,0)),f.x),
               mix(pigment_hash(i+vec2(0,1)),pigment_hash(i+vec2(1,1)),f.x),f.y);
}
vec3 painted_stone(vec3 base, vec3 position, vec3 face_normal) {
    vec3 a=abs(face_normal);
    vec2 uv=a.y>max(a.x,a.z)?position.xz:(a.x>a.z?position.zy:position.xy);
    // Broken pigment islands, not tiny grain or extra fictitious brick joints.
    float broad=pigment_noise(uv*2.5);
    float stroke=pigment_noise(uv*vec2(13.0,22.0)+broad*.6);
    float dab=smoothstep(.48,.64,stroke);
    vec3 cool=base*vec3(.86,.95,1.08);
    vec3 warm=base*vec3(1.12,1.05,.91);
    vec3 pigment=mix(cool,warm,smoothstep(.25,.75,broad));
    return pigment*mix(.92,1.12,dab);
}

vec3 stone_chip_offset(vec3 p, vec3 world) {
    float amount=art_layer(4,world,damage_amount);
    // Continuous object-space deformation: coincident corners stay coincident.
    // Small chipped facets only; architectural openings and collision stay intact.
    float chip=smoothstep(.68,.88,pigment_noise(p.xz*5.0+p.y*3.1));
    float protected_base=smoothstep(.02,.18,p.y);
    return vec3(sin(p.y*19.0+p.z*13.0),-.65,cos(p.x*17.0+p.y*11.0))*chip*amount*.055*protected_base;
}

vec3 stone_weather(vec3 color,vec3 p,vec3 n,vec3 world,float cavity) {
    float moss=art_layer(2,world,moss_amount);
    float damp=art_layer(3,world,damp_amount);
    float damage=art_layer(4,world,damage_amount);
    vec3 a=abs(n);
    vec2 uv=a.y>max(a.x,a.z)?p.xz:(a.x>a.z?p.zy:p.xy);
    float breakup=pigment_noise(uv*6.0+pigment_noise(uv*1.8));
    float basal=1.0-smoothstep(.1,1.5,p.y);
    float recess=1.0-cavity;
    float shelf=max(0.0,n.y)*.32;
    float habitat=clamp(basal*.7+recess*.8+shelf,0.0,1.0);
    float deposits=smoothstep(.43,.69,breakup)*habitat*moss;
    color=mix(color,moss_color,deposits*.78);
    float drips=smoothstep(.57,.72,pigment_noise(uv*vec2(12.0,1.15)))*habitat*damp;
    color=mix(color,color*damp_color*2.4,drips*.33);
    float crack_wave=sin(uv.x*14.0+pigment_noise(uv*2.0)*5.0+uv.y*2.0);
    float crack=(1.0-smoothstep(.015,.085,abs(crack_wave)))*smoothstep(.62,.8,pigment_noise(uv*1.3+11.0));
    color*=1.0-crack*damage*.7;
    return color;
}
