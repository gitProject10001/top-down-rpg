uniform int art_edit_count = 0;
uniform vec4 art_edit_rows_x[32];
uniform vec4 art_edit_rows_y[32];
uniform vec4 art_edit_rows_z[32];
uniform vec4 art_edit_values[32];
float art_layer(int layer, vec3 world, float base) {
    float value=base;
    for(int i=0;i<art_edit_count;i++) {
        if(int(art_edit_values[i].y)!=layer) continue;
        vec4 p=vec4(world,1.0);
        vec3 q=vec3(dot(art_edit_rows_x[i],p),dot(art_edit_rows_y[i],p),dot(art_edit_rows_z[i],p));
        float weight=(1.0-smoothstep(.55,1.0,length(q.xz)))*(1.0-smoothstep(.55,1.0,abs(q.y)));
        value+=weight*art_edit_values[i].x;
    }
    return clamp(value,0.0,1.0);
}
