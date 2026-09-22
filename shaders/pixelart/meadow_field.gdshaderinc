// Shared unlit pigments and broad wind field; no screen-space colour sampling.
uniform vec4 meadow_region = vec4(0.0);
uniform float meadow_patch_scale = 8.0;
uniform float meadow_ground_influence = 0.65;
uniform float meadow_normal_mix = 0.75;
uniform float meadow_wind_strength = 1.0;
uniform vec3 meadow_cool = vec3(.09,.16,.055);
uniform vec3 meadow_warm = vec3(.17,.22,.07);
float meadow_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float meadow_noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(meadow_hash(i),meadow_hash(i+vec2(1,0)),f.x),mix(meadow_hash(i+vec2(0,1)),meadow_hash(i+vec2(1,1)),f.x),f.y);
}
float meadow_weight(vec2 p) { return meadow_region.z>0.0 ? 1.0-smoothstep(meadow_region.z*.65,meadow_region.z,distance(p,meadow_region.xy)) : 0.0; }
vec3 meadow_pigment(vec2 p,float authored) {
 float large=meadow_noise(p/max(meadow_patch_scale,1.0));
 float medium=meadow_noise(p/max(meadow_patch_scale*.28,.4)+31.0);
 float stroke=meadow_noise(p*3.1+medium);
 float t=clamp(.55*large+.3*medium+.15*authored,0.0,1.0);
 return mix(meadow_cool,meadow_warm,smoothstep(.23,.77,t))*mix(.93,1.07,stroke);
}
float meadow_gust(vec2 p,float time) { return smoothstep(.28,.78,meadow_noise(p*.16-vec2(time*.19,time*.08))); }
