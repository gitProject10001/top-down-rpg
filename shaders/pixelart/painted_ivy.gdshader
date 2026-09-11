shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(1);
void fragment(){
	// Large painted leaf blocks; no high-frequency atlas noise at gameplay distance.
	vec2 cell=floor(UV*vec2(3.0,4.0));
	float band=mod(cell.x+cell.y,3.0);
	vec3 base=tint.rgb*mix(vec3(.72,.78,.54),vec3(1.0,.96,.72),band/3.0);
	ALBEDO=base;
	ROUGHNESS=1.0; SPECULAR=0.0;
}
void light(){
	float d=clamp(dot(NORMAL,LIGHT)*.65+.35,0.0,1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR*d*ATTENUATION/3.14159;
}
