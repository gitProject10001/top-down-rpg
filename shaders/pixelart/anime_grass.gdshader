shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/pixelart/meadow_field.gdshaderinc"
uniform sampler2D brush_painting : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D brush_normal : filter_linear_mipmap, repeat_enable;
uniform vec3 root_color = vec3(.060,.100,.045);
uniform vec3 cool_tip = vec3(.09,.16,.055);
uniform vec3 warm_tip = vec3(.17,.22,.07);
varying float blade_height;
varying float patch_tint;
varying float pigment_group;
varying float stroke_value;
varying float clump_density;
varying vec3 world_position;
void vertex() {
    blade_height = UV.y;
    // Vary footprint independently from height; preserve shared patch direction.
    VERTEX.x *= mix(.78,1.32,INSTANCE_CUSTOM.b);
    VERTEX.z *= mix(1.15,.86,INSTANCE_CUSTOM.b);
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    vec3 origin = MODEL_MATRIX[3].xyz;
    float gust = sin(TIME * 1.35 + origin.x * .65 + origin.z * .38);
    float sample_weight=meadow_weight(origin.xz);
    float field=meadow_gust(origin.xz,TIME)*2.0-1.0;
    gust=mix(gust,field*meadow_wind_strength,sample_weight);
    VERTEX.x += gust * .018 * blade_height * blade_height;
    VERTEX.z += mix(sin(TIME * 1.9 + origin.z),field*meadow_wind_strength,sample_weight) * .008 * blade_height;
    patch_tint = INSTANCE_CUSTOM.r;
    pigment_group = INSTANCE_CUSTOM.g;
    stroke_value = COLOR.r;
    clump_density = INSTANCE_CUSTOM.a;
    // Retain the blade's form while avoiding black backfaces on thin leaves.
    NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), .80));
}
void fragment() {
    vec3 root = root_color * mix(1.05,.76,clump_density);
    vec3 tip = mix(cool_tip,warm_tip,patch_tint);
    // Local cool/ochre strokes remain grouped, with modest per-ribbon values.
    tip = mix(tip * vec3(.68,.83,1.12), tip * vec3(1.24,1.06,.82), pigment_group);
    vec3 brush = texture(brush_painting, world_position.xz / 6.0).rgb;
    ALBEDO = mix(root, tip, smoothstep(0.0, .85, blade_height)) * (.9 + brush.g * .5) * stroke_value;
    float sample_weight=meadow_weight(world_position.xz);
    vec3 shared_pigment=meadow_pigment(world_position.xz,pigment_group);
    float root_shade=mix(.52,1.0,smoothstep(0.0,.85,blade_height));
    ALBEDO=mix(ALBEDO,shared_pigment*root_shade*stroke_value,sample_weight*meadow_ground_influence*mix(1.0,.55,blade_height));
    ALBEDO*=1.0+sample_weight*meadow_wind_strength*(meadow_gust(world_position.xz,TIME)-.5)*.08;
    vec3 geometric_normal=NORMAL;
    vec3 painted = texture(brush_normal, world_position.xz / 4.581).rgb * 2.0 - 1.0;
    vec3 world_normal = normalize(mix(vec3(0,1,0), vec3(painted.x,painted.z,-painted.y), .85));
    NORMAL = normalize(mix(mat3(VIEW_MATRIX)*world_normal,geometric_normal,sample_weight*(1.0-meadow_normal_mix)));
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    // Artistic root occlusion complements actual screen-space contact shading.
    // Concentrate it near the soil, strongest inside dense patches.
    AO = mix(mix(.70,.46,clump_density),1.0,smoothstep(.0,.65,blade_height));
    AO_LIGHT_AFFECT = .45;
}
void light() {
    // The tutorial uses a color ramp over painted world normals. Keep its
    // broad light grouping instead of sharp per-blade Lambert contrast.
    float brush_light = smoothstep(-.35,.85,dot(NORMAL,LIGHT));
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * mix(.45,1.15,brush_light) / 3.14159265;
}
