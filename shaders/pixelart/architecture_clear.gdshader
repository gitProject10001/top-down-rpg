shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painting:source_color,filter_linear_mipmap_anisotropic;
uniform vec2 quadrant=vec2(0);
uniform vec2 uv_scale=vec2(1);
uniform vec4 tint:source_color=vec4(1);
uniform vec4 solid:source_color=vec4(0);
void fragment(){
 vec2 uv=fract(UV*uv_scale)*.486+quadrant+.007;
 ALBEDO=solid.a>.5?solid.rgb:textureGrad(painting,uv,dFdx(UV*uv_scale)*.486,dFdy(UV*uv_scale)*.486).rgb*tint.rgb;
 ROUGHNESS=1.0;SPECULAR=0.0;
}
