shader_type spatial;
render_mode cull_disabled;

uniform vec3 pattern_offset = vec3(0.0);
uniform bool weathered = true;
uniform vec4 plaster_color : source_color = vec4(0.68, 0.49, 0.29, 1.0);
uniform vec4 worn_color : source_color = vec4(0.47, 0.29, 0.19, 1.0);
varying vec3 local_position;

float hash(vec3 p) {
 p = fract(p * 0.1031);
 p += dot(p, p.yzx + 33.33);
 return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
 vec3 i = floor(p);
 vec3 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
                mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
            mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { local_position = VERTEX; }
void fragment() {
 // Continuous object-space field: no tiled patch, seams or stretching on resize.
 vec3 p = local_position + pattern_offset;
 float wear = noise(p * 1.13) * 0.58 + noise(p * 3.17) * 0.27 + noise(p * 9.31) * 0.15;
 float mask = weathered ? smoothstep(0.55, 0.60, wear) : 0.0;
 float pigment = (noise(p * 5.7) - 0.5) * 0.09 + (noise(p * 37.1) - 0.5) * 0.035;
 ALBEDO = mix(plaster_color.rgb, worn_color.rgb, mask) * (1.0 + pigment);
 ROUGHNESS = 0.94;
 SPECULAR = 0.16;
}
