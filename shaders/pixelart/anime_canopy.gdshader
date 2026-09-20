shader_type spatial;
// Coverage AA smooths the painted cutout, while crown AO replaces noisy
// rectangular self-shadows. Sprays still cast their silhouettes onto the world.
render_mode cull_disabled, shadows_disabled, alpha_to_coverage;
uniform sampler2D leaf_painting : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind_strength : hint_range(0.0, .2) = .055;
uniform vec3 shade_pigment : source_color = vec3(.27, .40, .28);
uniform vec3 light_pigment : source_color = vec3(.55, .66, .34);
varying float cavity;
varying float tint;
varying vec3 crown_normal_world;
void vertex() {
    cavity = COLOR.r;
    tint = COLOR.g;
    crown_normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float phase = world.x * .21 + world.z * .33;
    float tip = COLOR.b;
    VERTEX.x += sin(TIME * 1.1 + phase) * wind_strength * tip;
    VERTEX.z += cos(TIME * .85 + phase * 1.3) * wind_strength * .4 * tip;
    VERTEX.y += sin(TIME * 2.1 + phase * 2.0) * wind_strength * .16 * tip;
}
void fragment() {
    vec4 paint = texture(leaf_painting, UV);
    ALPHA = paint.a;
    ALPHA_SCISSOR_THRESHOLD = .32;
    ALPHA_ANTIALIASING_EDGE = .20;
    ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_painting, 0));
    float pigment = smoothstep(.025, .25, dot(paint.rgb, vec3(.299, .587, .114)));
    vec3 base = mix(shade_pigment, light_pigment, pigment);
    base *= mix(.90, 1.08, tint);
    base = mix(base * vec3(.88, 1.0, 1.12), base, smoothstep(.25, .8, cavity));
    ALBEDO = base;
    NORMAL = normalize(mat3(VIEW_MATRIX) * crown_normal_world);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    AO = cavity;
    AO_LIGHT_AFFECT = .65;
}
void light() {
    float wrap = smoothstep(-.35, .95, dot(NORMAL, LIGHT));
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap / 3.14159265;
}
