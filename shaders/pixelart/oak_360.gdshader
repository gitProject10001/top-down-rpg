shader_type spatial;
render_mode cull_disabled;
uniform sampler2D painting : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind_strength : hint_range(0.0, 0.3) = 0.07;
void vertex() {
	float phase = VERTEX.x*1.4+VERTEX.z*1.9;
	VERTEX.x += sin(TIME*1.3+phase)*wind_strength;
	VERTEX.z += sin(TIME*0.9+phase*0.7)*wind_strength*0.5;
}
void fragment() {
	vec4 ink = texture(painting, UV);
	ALPHA = ink.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = ink.rgb * vec3(0.85, 0.92, 0.88);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
void light() {
	float diffuse = clamp(dot(NORMAL,LIGHT)*0.65+0.35,0.0,1.0);
	float bands = mix(diffuse,floor(diffuse*5.0)/5.0,0.25);
	DIFFUSE_LIGHT += LIGHT_COLOR*bands*ATTENUATION/3.14159265;
}
