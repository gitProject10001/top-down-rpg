shader_type spatial;
render_mode world_vertex_coords;
uniform sampler2D painting : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 painting_center = vec2(0.0, 3.0);
uniform float painting_size : hint_range(1.0, 128.0) = 32.0;
uniform float border_blend : hint_range(0.01, 0.4) = 0.16;
uniform vec3 grass_dark : source_color = vec3(0.19, 0.22, 0.10);
uniform vec3 grass_light : source_color = vec3(0.34, 0.35, 0.17);
uniform vec3 earth_color : source_color = vec3(0.32, 0.27, 0.16);
uniform float patch_metres : hint_range(1.0, 100.0) = 12.0;
uniform float detail_metres : hint_range(0.5, 12.0) = 3.0;
uniform sampler2D road_mask : filter_linear, repeat_disable;
uniform bool use_road_mask = false;
uniform vec2 road_mask_center = vec2(0.0);
uniform vec2 road_mask_size = vec2(100.0);
uniform float road_edge_noise : hint_range(0.0, 0.3) = 0.08;
varying vec3 world_position;

float hash_ground(vec2 cell) {
 vec3 h = fract(vec3(cell.xyx) * 0.1031);
 h += dot(h, h.yzx + 33.33);
 return fract((h.x + h.y) * h.z);
}

float ground_noise(vec2 pos) {
 vec2 cell = floor(pos);
 vec2 f = fract(pos);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(hash_ground(cell), hash_ground(cell + vec2(1, 0)), f.x), mix(hash_ground(cell + vec2(0, 1)), hash_ground(cell + vec2(1, 1)), f.x), f.y);
}

void vertex() { world_position = VERTEX; }

void fragment() {
 vec2 pos = world_position.xz;
 float patches = ground_noise(pos / patch_metres);
 float broad = ground_noise(pos / (patch_metres * 5.0) + vec2(41.3, 9.7));
 float detail = ground_noise(pos / max(detail_metres, 0.1) * 3.0);
 float detail_visibility = 1.0 - smoothstep(0.15, 0.8, length(fwidth(pos)));
 vec3 tint = mix(grass_dark, grass_light, patches * 0.7 + broad * 0.3);
 vec3 ground = tint * mix(vec3(0.94), vec3(1.06), broad);
 ground = mix(ground, earth_color, smoothstep(0.76, 0.95, patches) * 0.18);
 ground *= 1.0 + (detail - 0.5) * 0.12 * detail_visibility;

 vec2 q = vec2((pos.x + pos.y) * 0.707107, (pos.y - pos.x) * 0.707107);
 vec2 uv = (q - painting_center) / painting_size + 0.5;
 float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
 float stamp = smoothstep(0.0, border_blend, edge);
 vec3 painted = texture(painting, clamp(uv, vec2(0.0), vec2(1.0))).rgb * vec3(0.62, 0.59, 0.55);
 ALBEDO = mix(ground, painted, stamp);

 if (use_road_mask) {
  vec2 mask_uv = (pos - road_mask_center) / max(road_mask_size, vec2(0.01)) + 0.5;
  float inside = step(0.0, mask_uv.x) * step(0.0, mask_uv.y) * step(mask_uv.x, 1.0) * step(mask_uv.y, 1.0);
  vec2 mask = texture(road_mask, mask_uv).rg * inside;
  mask += (ground_noise(pos * 1.7) - 0.5) * road_edge_noise * 4.0 * mask * (1.0 - mask);
  vec3 road = mix(earth_color * 0.95, earth_color * 1.08, ground_noise(pos * 0.7));
  ALBEDO = mix(ALBEDO, road, smoothstep(0.05, 0.95, mask.r));
  ALBEDO = mix(ALBEDO, road * 0.88, smoothstep(0.05, 0.95, mask.g));
 }
 ROUGHNESS = 1.0;
 SPECULAR = 0.0;
}
