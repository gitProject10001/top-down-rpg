shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
 vec2 uv=(floor(UV*vec2(22,32))+.5)/vec2(22,32);
 float h=1.0-uv.y;
 float center=.5+sin(h*8.0-TIME*6.0)*.045;
 float width=(1.0-h)*.32+sin(h*18.0+TIME*8.0)*.03;
 float tongue=abs(uv.x-center)/max(width,.01);
 if(tongue>1.0||h<.04)discard;
 vec3 c=vec3(1.0,.24,.025);
 if(tongue<.65)c=vec3(1.0,.64,.09);
 if(tongue<.32&&h<.55)c=vec3(1.0,.91,.45);
 ALBEDO=c;EMISSION=c*1.4;
}
