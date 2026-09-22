shader_type canvas_item;
render_mode unshaded;
// Final display-space pass: does not change 3D materials, lighting or tone mapping.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float palette_strength : hint_range(0.0,1.0) = 0.72;
uniform float soften_strength : hint_range(0.0,1.0) = 0.6;
uniform float radius : hint_range(0.0,3.0) = 1.25;
uniform float edge_preservation : hint_range(10.0,200.0) = 80.0;
uniform float warmth : hint_range(0.0,1.0) = 0.15;
const vec3 PALETTE[32] = vec3[32](
vec3(.09,.105,.12),vec3(.16,.19,.18),vec3(.23,.27,.24),vec3(.32,.35,.29),
vec3(.24,.31,.22),vec3(.34,.42,.27),vec3(.45,.51,.32),vec3(.58,.60,.39),
vec3(.17,.29,.26),vec3(.27,.40,.34),vec3(.39,.52,.41),vec3(.56,.65,.50),
vec3(.29,.24,.21),vec3(.40,.33,.27),vec3(.53,.43,.32),vec3(.67,.55,.39),
vec3(.42,.40,.34),vec3(.55,.53,.44),vec3(.69,.66,.54),vec3(.83,.79,.65),
vec3(.40,.23,.22),vec3(.58,.34,.25),vec3(.76,.49,.30),vec3(.90,.70,.43),
vec3(.24,.22,.29),vec3(.39,.33,.40),vec3(.56,.47,.52),vec3(.75,.65,.62),
vec3(.20,.33,.39),vec3(.32,.48,.54),vec3(.52,.67,.68),vec3(.94,.89,.75));
vec3 perceptual(vec3 c) {
    return vec3(dot(c,vec3(.2126,.7152,.0722)),(c.r-c.g)*.7,(c.b-c.g)*.7);
}
void fragment() {
    vec3 original=texture(screen_tex,SCREEN_UV).rgb;
    vec3 sum=original; float weights=1.0;
    // Small bilateral kernel removes speckle while keeping contrasting silhouettes.
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        if(x==0 && y==0) continue;
        vec3 tap=texture(screen_tex,SCREEN_UV+vec2(float(x),float(y))*SCREEN_PIXEL_SIZE*radius).rgb;
        vec3 delta=tap-original;
        float w=exp(-dot(delta,delta)*edge_preservation)*.7;
        sum+=tap*w; weights+=w;
    }
    vec3 col=mix(original,sum/weights,soften_strength);
    float l=dot(col,vec3(.2126,.7152,.0722));
    col+=warmth*mix(vec3(-.025,0.0,.025),vec3(.035,.012,-.025),smoothstep(.15,.8,l));
    vec3 target=perceptual(col), first=col, second=col;
    float d1=100.0, d2=100.0;
    for(int i=0;i<32;i++) {
        vec3 diff=perceptual(PALETTE[i])-target;
        float d=dot(diff,diff);
        if(d<d1) { d2=d1; second=first; d1=d; first=PALETTE[i]; }
        else if(d<d2) { d2=d; second=PALETTE[i]; }
    }
    // Soft transitions avoid binary palette flicker; deliberately no dither/noise.
    float blend=.5*smoothstep(.48,1.0,d1/max(d2,.000001));
    COLOR=vec4(mix(col,mix(first,second,blend),palette_strength),1.0);
}
