shader_type spatial;
render_mode cull_disabled;

uniform sampler2D spray : filter_linear_mipmap, repeat_disable;
uniform vec3 shade_color : source_color = vec3(0.065, 0.23, 0.16);
uniform vec3 middle_color : source_color = vec3(0.25, 0.48, 0.19);
uniform vec3 sun_color : source_color = vec3(0.66, 0.79, 0.31);
uniform float wind_strength : hint_range(0.0, 0.3) = 0.055;
varying float cavity;

void vertex() {
    cavity = COLOR.r;
    float weight = clamp(VERTEX.y / 5.0, 0.0, 1.0);
    float phase = VERTEX.x * 0.8 + VERTEX.z * 1.1;
    VERTEX.x += sin(TIME * 1.1 + phase * 0.3) * wind_strength * weight;
    VERTEX.z += sin(TIME * 2.7 + phase * 3.0) * wind_strength * 0.25 * weight;
}

void fragment() {
    ALPHA = texture(spray, UV).a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ALBEDO = vec3(1.0);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    // Low ambient floor; transferred normals drive directional palette bands.
    EMISSION = shade_color * cavity * 0.22;
    AO = cavity;
    AO_LIGHT_AFFECT = 0.65;
}

void light() {
    float n = dot(NORMAL, LIGHT) * 0.5 + 0.5;
    vec3 palette = mix(shade_color, middle_color, smoothstep(0.30, 0.46, n));
    palette = mix(palette, sun_color, smoothstep(0.67, 0.79, n));
    DIFFUSE_LIGHT += palette * LIGHT_COLOR * ATTENUATION * cavity / 3.14159265;
}
