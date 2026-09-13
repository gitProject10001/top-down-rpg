shader_type spatial;
#include "res://shaders/pixelart/architecture_reveal.gdshaderinc"
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_nearest_mipmap;
uniform vec2 quadrant=vec2(0,0.5);
uniform vec4 tint : source_color=vec4(1);
uniform float metres=2.5;
uniform float detail_lod=1.0;
varying vec3 p;
varying vec3 norm;
void vertex(){ reveal_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;p=VERTEX;norm=NORMAL;}
void fragment(){ architecture_reveal(FRAGCOORD.xy);
 vec3 a=abs(norm);
 vec2 uv=a.y>max(a.x,a.z)?p.xz:(a.x>a.z?p.zy:p.xy);
 uv=fract(uv*vec2(1,-1)/metres)*.497+quadrant+.0015;
 ALBEDO=textureLod(atlas,uv,detail_lod).rgb*tint.rgb;
 ROUGHNESS=1.0;SPECULAR=0.0;
}
