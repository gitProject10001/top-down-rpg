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
uniform vec4 wakes[16];
uniform vec2 wake_directions[16];
uniform float clock = 0.0;

vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
float cells(vec2 p) {
    p+=vec2(sin(p.y*2.5+sin(p.x*1.6)+clock*.3),cos(p.x*2.3+sin(p.y*1.9)-clock*.22))*.35;
    vec2 base=floor(p); vec2 f=fract(p);
    float first=10.0; float second=10.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 cell=vec2(float(x),float(y));
        vec2 h=hash2(base+cell);
        vec2 point=.5+.38*sin(6.2831*h+clock*.24);
        float d=length(cell+point-f);
        if(d<first) { second=first; first=d; }
        else second=min(second,d);
    }
    float patches=smoothstep(.2,.75,.5+.5*sin(p.x*.8+p.y*1.3+sin(p.x*1.7)+clock*.15));
    return (1.0-smoothstep(.012,.075,second-first))*(.3+.7*smoothstep(.15,.6,first))*patches;
}

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
    float caustic=mix(cells(q*1.9),cells(q2*1.9),abs(phase*2.0-1.0));
    float ring=0.0;
    for(int i=0;i<8;i++) {
        float age=clock-rings[i].z;
        if(age>=0.0 && age<2.0) {
            vec2 offset=p-rings[i].xy;
            float r=length(offset);
            float a=atan(offset.y,offset.x);
            float uneven=sin(a*5.0+float(i)*1.7)*.07+sin(a*9.0-clock)*.03;
            ring+=exp(-pow((r-age*1.4+uneven)/.06,2.0))*(1.0-age*.5)*rings[i].w*.3;
        }
    }
    float wake=0.0;
    vec2 disturbance=vec2(0.0);
    for(int i=0;i<16;i++) {
        float age=clock-wakes[i].z;
        if(age>=0.0 && age<2.4) {
            vec2 offset=p-wakes[i].xy;
            vec2 direction=wake_directions[i];
            float behind=-dot(offset,direction);
            float across=dot(offset,vec2(-direction.y,direction.x));
            float fade=pow(1.0-age/2.4,2.0)*wakes[i].w;
            float envelope=smoothstep(-.2,.1,behind)*(1.0-smoothstep(.4+age*.7,1.2+age,behind));
            float turbulence=sin(behind*14.0+float(i)*2.1+clock*2.0)*.055;
            float arm=exp(-pow((abs(across+turbulence)-(.16+behind*.45+age*.1))/.10,2.0))*envelope;
            arm*=.6+.4*sin(behind*19.0+across*11.0+float(i));
            float churn=exp(-dot(offset,offset)/( .1+age*.22))*(.5+.5*sin(across*31.0+behind*23.0-age*12.0));
            wake+=(arm*.45+churn*.32)*fade;
            disturbance+=offset*(arm+churn)*fade*.12;
        }
    }
    wake=min(wake,1.0);
    float depth=basin_depth*smoothstep(0.0,1.5,bank);
    vec3 color=mix(vec3(.025,.16,.12),vec3(.004,.035,.045),clamp(depth/.5,0.0,1.0));
    float foam=(1.0-smoothstep(.035,.20,bank))*(.35+.2*sin(p.x*12.0+p.y*9.0+clock));
    ALBEDO=color+vec3(.035,.09,.07)*caustic*.35+vec3(.2,.35,.3)*(ring*.45+foam*.5+wake);
    if(debug_flow) ALBEDO=vec3(flow.x*.35+.5,.15,flow.y*.35+.5);
    vec3 local_slope=vec3(sin(q.x*5.0+q.y)*.06+disturbance.x,0.0,cos(q.y*5.0-q.x)*.06+disturbance.y);
    NORMAL=normalize(NORMAL+mat3(VIEW_MATRIX)*mat3(MODEL_MATRIX)*local_slope);
    ROUGHNESS=.23;
    SPECULAR=.65;
    ALPHA=mix(.45,.82,clamp(depth/.5,0.0,1.0));
    EMISSION=vec3(.025,.05,.04)*caustic*.15+vec3(.15,.23,.2)*ring*.2;
}
