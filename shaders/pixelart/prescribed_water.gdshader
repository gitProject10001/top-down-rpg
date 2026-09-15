shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec2 boundary[32];
uniform int edge_count = 0;
uniform vec2 flow_path[16];
uniform int path_count = 0;
uniform float flow_speed = .55;
uniform float basin_depth = .4;
uniform bool debug_flow = false;
uniform vec2 vortex_center = vec2(-3,-2);
uniform float vortex_strength = 0.0;
uniform vec4 rings[8];
uniform float clock = 0.0;

float shore(vec2 p) {
    float d = 10000.0;
    for(int i=0;i<edge_count;i++) {
        vec2 a=boundary[i]; vec2 b=boundary[(i+1)%edge_count];
        vec2 ab=b-a;
        float t=clamp(dot(p-a,ab)/max(dot(ab,ab),.00001),0.0,1.0);
        d=min(d,length(p-a-ab*t));
    }
    return d;
}
vec2 current(vec2 p) {
    float best=10000.0; vec2 flow=vec2(0.0);
    for(int i=0;i<path_count-1;i++) {
        vec2 a=flow_path[i]; vec2 ab=flow_path[i+1]-a;
        float t=clamp(dot(p-a,ab)/max(dot(ab,ab),.00001),0.0,1.0);
        float d=length(p-a-ab*t);
        if(d<best) { best=d; flow=ab/max(length(ab),.001); }
    }
    flow*=flow_speed*smoothstep(-1.0,6.0,p.x);
    vec2 offset=p-vortex_center;
    flow+=vec2(-offset.y,offset.x)*vortex_strength*exp(-dot(offset,offset)*.5);
    return flow;
}
void fragment() {
    vec2 p=UV;
    float bank=shore(p);
    vec2 flow=current(p);
    // Two cross-faded phases avoid stretching a variable vector field forever.
    float phase=fract(clock*.12);
    vec2 q=p-flow*phase*2.0;
    vec2 q2=p-flow*fract(phase+.5)*2.0;
    float waves=sin(q.x*6.0+sin(q.y*3.7))*sin(q.y*5.2+cos(q.x*2.8));
    float waves2=sin(q2.x*6.0+sin(q2.y*3.7))*sin(q2.y*5.2+cos(q2.x*2.8));
    float caustic=mix(pow(1.0-abs(waves),24.0),pow(1.0-abs(waves2),24.0),abs(phase*2.0-1.0));
    float ring=0.0;
    for(int i=0;i<8;i++) {
        float age=clock-rings[i].z;
        if(age>=0.0 && age<2.0) {
            float r=length(p-rings[i].xy);
            ring+=exp(-pow((r-age*1.4)/.075,2.0))*(1.0-age*.5)*rings[i].w;
        }
    }
    float depth=basin_depth*smoothstep(0.0,1.5,bank);
    vec3 color=mix(vec3(.025,.16,.12),vec3(.004,.035,.045),clamp(depth/.5,0.0,1.0));
    float foam=(1.0-smoothstep(.035,.20,bank))*(.35+.2*sin(p.x*12.0+p.y*9.0+clock));
    ALBEDO=color+vec3(.035,.09,.07)*caustic*.35+vec3(.2,.35,.3)*(ring*.45+foam*.5);
    if(debug_flow) ALBEDO=vec3(flow.x*.35+.5,.15,flow.y*.35+.5);
    NORMAL=normalize(NORMAL+vec3(sin(q.x*5.0+q.y)*.08,0.0,cos(q.y*5.0-q.x)*.08));
    ROUGHNESS=.23;
    SPECULAR=.65;
    ALPHA=mix(.45,.82,clamp(depth/.5,0.0,1.0));
    EMISSION=vec3(.025,.05,.04)*caustic*.15+vec3(.15,.23,.2)*ring*.2;
}
