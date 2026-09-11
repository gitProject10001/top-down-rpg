shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painting : source_color,filter_nearest_mipmap;
uniform vec2 quadrant=vec2(0);
uniform vec4 tint : source_color=vec4(1);
uniform vec4 solid : source_color=vec4(0);
void fragment(){
 vec2 uv=fract(UV)*.497+quadrant+.0015;
 ALBEDO=solid.a>.5?solid.rgb:textureLod(painting,uv,1.0).rgb*tint.rgb;
 ROUGHNESS=.94;SPECULAR=.025;
}
