shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;
// STYLIZED WATER for the lakes carved in the foliage bench. The project's first water of any kind —
// the prior art was a bare PlaneMesh standing in for a sea, which has no shoreline at all.
//
// UNSHADED, like shaders/glass_stylized.gdshader and for the same reason: painted_env.gdshader:19
// records that specular and rim were measured to be the source of this project's "plastic" look and
// says there is deliberately no uniform to switch them back on. A surface that composes its own
// colour and never calls light() cannot reach the environment shading model at all, so the rule
// stays intact rather than being argued with. Water, like glass, is one of the few materials with a
// physical reason to have a highlight.
//
// THE SHAPE OF THE LAKE COMES FROM A TEXTURE, NOT FROM GEOMETRY.
//
// This is one flat quad covering the WHOLE terrain, and the only thing that makes it look like a
// lake is `depth`: a small R-channel image baked by scripts/terrain_field.gd from the height array
// it already owns, holding metres of water at each grid vertex and exactly zero everywhere the
// player did not paint one. Alpha comes off that, so the quad is invisible except where there is
// water, and the waterline lands precisely on the contour where terrain height meets water level.
// No shoreline mesh, no outline extraction, no second collision shape.
//
// It also means the foam is FREE and, more importantly, correct: the shallows are where `depth` is
// small, so a band keyed on depth is the shore by construction, at any lake shape, without a
// DEPTH_TEXTURE read. Sampling the depth buffer would have meant a screen-space fetch and dragging
// this into the sorted transparent pass properly — the same argument painted_env.gdshader:107 makes
// about why foliage stipples instead of blending.

group_uniforms Shape;
// Metres across the terrain, so the vertex stage can turn a position into a depth-map lookup
// without depending on how PlaneMesh happens to lay out its UVs.
uniform float extent = 64.0;
uniform sampler2D depth_map : hint_default_black, filter_linear;
// What one unit of the depth map means in metres. Must match TerrainField.depth_image()'s `scale`.
uniform float depth_scale = 2.0;

group_uniforms Color;
uniform vec4 shallow_color : source_color = vec4(0.42, 0.68, 0.66, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.28, 0.40, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 0.97, 1.0);
// How far up the beach the foam reaches, in metres of depth.
uniform float foam_depth : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float max_alpha : hint_range(0.0, 1.0, 0.01) = 0.88;

group_uniforms Ripples;
// Two crossing wave trains rather than a noise texture: at this scale the eye reads the MOVEMENT,
// not the pattern, and two sines cost nothing and need no asset.
uniform float ripple_scale : hint_range(0.5, 20.0, 0.5) = 6.0;
uniform float ripple_speed : hint_range(0.0, 3.0, 0.05) = 0.55;
uniform float ripple_strength : hint_range(0.0, 1.0, 0.01) = 0.18;

group_uniforms Flow;
// THE CURRENT, baked per region by whatever produced the terrain — RG is the flow vector
// on the world XZ plane, B is convergence (where the field crowds into itself, which is where
// real foam collects). Shares the depth map's square exactly, so v_uv addresses both.
//
// The detail below travels ALONG this field using the two-phase cross-blend: two copies of
// the pattern half a period out of step, each displaced by flow * elapsed, cross-faded so
// whichever one is resetting is the one being hidden. UVs never accumulate, so nothing
// stretches or tears — the cheap stylized cousin of Wave Profile Buffers, six lines instead
// of a subsystem. With flow at zero the two copies coincide and this is EXACTLY the pair of
// crossing sines it replaces, which is what keeps still ponds and old screenshots unchanged.
uniform sampler2D flow_map : hint_default_black, filter_linear;
uniform float flow_speed = 1.0;                  // metres/second per unit of baked flow
uniform float flow_drag : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float flow_period : hint_range(0.5, 8.0, 0.1) = 3.0;   // seconds per phase reset
// Flow speed at which water foams on its own. Rapids go white; a pond never does. Set from
// the measured distribution over a bench river (median 0.49, p90 2.33, max 3.89), not by
// eye: at 1.1 this threshold whitened 37% of the water, which is a river made of foam. Near
// p90 it catches the spill edges and leaves the reaches alone.
uniform float foam_speed : hint_range(0.1, 6.0, 0.05) = 2.6;
// Convergence at which foam starts to gather. Like foam_speed this is a THRESHOLD, not a
// multiplier: the baked field's raw divergence (median 0.00, p90 0.83) saturates instantly
// if used directly, which turned the first river solid white.
uniform float foam_gather : hint_range(0.05, 3.0, 0.05) = 1.1;

group_uniforms SolvedWater;
// THE SOLVER (scripts/ripple_field.gd + shaders/swe_sim.gdshader), over a 64 m window that
// follows the camera. ONE texture now, where there used to be two: Shallow Water's state is
// (height, velocity), so the wave field and the current field turned out to be the same
// fluid described twice.
//
//   R = eta, the surface deviation from this region's rest level
//   G,B = u', the velocity DEVIATION from the terrain-baked current (it ADDS to it)
//   A = foam the solver made and carried here
//
// rect.xy is the window's world-XZ min corner, .z its side in metres, .w the master gain AND
// the kill switch. At the project default of w = 0 every term below is exactly zero and this
// shader is bit-identical to its pre-solver self — which is what keeps terrain_field's fenced
// decorative water, and every old screenshot, untouched.
global uniform sampler2D water_swe_tex;
global uniform vec4 water_swe_rect;
// Metres of simulated crest -> units of colour. The sines deliver +-ripple_strength from a
// +-1 wave; the solver delivers ~+-0.05 m, so it needs its own scale to land in the same
// visual register.
uniform float ripple_field_gain : hint_range(0.0, 8.0, 0.1) = 3.0;
// A crest taller than this reads as foam — the accent that sells a wake in flat colour.
uniform float ripple_foam_crest : hint_range(0.01, 0.3, 0.01) = 0.05;
// How much of the visible foam comes from the solver rather than the baked thresholds. This
// is the dial that turns "a river with foam painted on it" into "a river carrying foam".
uniform float live_foam : hint_range(0.0, 2.0, 0.05) = 1.0;

group_uniforms Displacement;
// THE SURFACE MOVES NOW, and this AMENDS a decision recorded a few lines up. The field used
// to be "a signed brightness band, never a normal or a highlight". That was the right call
// while the mesh was two triangles: a normal with no geometry under it is a lie. With the
// plane subdivided and eta displacing vertices, the surface has real relief, and refusing to
// shade it would mean tessellating the mesh and then hiding the result — at 53 degrees down
// a 15 cm crest is about 8 px of silhouette, while a band across its face is tens of pixels.
//
// SCOPED exactly the way glass_stylized.gdshader scoped its fresnel, so this cannot leak:
//   * still `unshaded`, still no light() anywhere — the painted lighting model is untouched
//     and cannot acquire a highlight by accident;
//   * `look_dir` is a LOOK vector, not a light: nothing samples the sun, and the term is
//     composed straight into ALBEDO like every other term in this file;
//   * `shade` is built as dot(n, L) - L.y, which is EXACTLY zero on flat water, so still
//     ponds, terrain_field's fenced water and every old screenshot are unchanged;
//   * slope_shade ships with a hint_range so the exception stays measurable, not asserted.
//
// Displacement is SHAPED and asymmetric, not raw: +0.15 m is where a crest would reach
// BED_SHALLOW (the wet beach) and +0.35 the terrace top, so a tanh soft-limit caps the
// excursion while barely touching an ordinary ripple.
uniform float disp_gain : hint_range(0.0, 8.0, 0.1) = 3.5;
uniform float disp_up : hint_range(0.02, 0.5, 0.01) = 0.15;
uniform float slope_shade : hint_range(0.0, 2.0, 0.05) = 0.55;
uniform float normal_extra : hint_range(0.0, 4.0, 0.1) = 1.8;
uniform vec3 look_dir = vec3(-0.40, 0.80, -0.45);

// Metres of geometric lift for a given eta, soft-limited. Shared by the vertex stage (which
// moves the mesh) and the fragment stage (which differences it for the normal), so the
// shading always describes the surface that is actually there.
float swe_lift(float e, float depth_m) {
	float t = e * disp_gain;
	float lim = (t >= 0.0) ? disp_up : min(disp_up, depth_m * 0.6);
	return sign(t) * lim * tanh(abs(t) / max(lim, 1e-4));
}

varying vec2 v_uv;
varying vec2 v_world;
varying vec2 v_wpos;
varying float v_amp;

void vertex() {
	v_uv = VERTEX.xz / extent + 0.5;
	v_world = VERTEX.xz;
	// TRUE world XZ, for the field lookup. v_world above is object-local — fine for the sines
	// (space-agnostic pattern), wrong for sampling a world-anchored texture: the planes sit at
	// region centres under a terrain that is itself parked off-origin.
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;

	// DISPLACE. textureLod is mandatory in the vertex stage (there are no derivatives here);
	// the addon GPUTrail already ships that form on this project's hardware.
	vec2 suv = (v_wpos - water_swe_rect.xy) / max(water_swe_rect.z, 0.001);
	float inw = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
	float srim = 1.0 - smoothstep(0.85, 1.0, max(abs(suv.x - 0.5), abs(suv.y - 0.5)) * 2.0);
	float dep = textureLod(depth_map, v_uv, 0.0).r * depth_scale;
	float eta = textureLod(water_swe_tex, clamp(suv, vec2(0.0), vec2(1.0)), 0.0).r;
	// Fade the lift out as the water shallows, so the mesh never lifts off its own shoreline.
	v_amp = water_swe_rect.w * inw * srim * smoothstep(0.0, 0.25, dep);
	VERTEX.y += swe_lift(eta, dep) * v_amp;
}

// The ambient pattern, evaluated at an arbitrary point so the flow can displace it. Two
// crossing wave trains rather than a noise texture: at this scale the eye reads the MOVEMENT,
// not the pattern, and two sines cost nothing and need no asset.
float detail_at(vec2 p, float t) {
	return sin(p.x / ripple_scale + t * ripple_speed)
			* sin(p.y / ripple_scale * 1.37 - t * ripple_speed * 0.8);
}

void fragment() {
	float d = texture(depth_map, v_uv).r * depth_scale;

	// OUT OF THE LAKE ENTIRELY. discard rather than a zero alpha, so the quad never writes depth
	// over dry ground and never costs a blend for the 90% of itself that is not water.
	if (d <= 0.001) {
		discard;
	}

	float t = clamp(d / max(depth_scale, 0.001), 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);

	// THE CURRENT. Two phases half a cycle apart, each carried downstream by the flow and
	// reset every flow_period; the triangle weight hides whichever is mid-reset.
	vec3 fl = texture(flow_map, v_uv).rgb;
	vec2 flow = fl.rg * flow_speed;
	// ONE sample of the solver, for everything it knows. Its velocity is a DEVIATION from the
	// baked field, so it ADDS rather than replaces — inside the window the current is the
	// terrain's answer plus whatever the water is actually doing about it.
	vec2 suv = (v_wpos - water_swe_rect.xy) / max(water_swe_rect.z, 0.001);
	float s_in = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
	float s_rim = 1.0 - smoothstep(0.85, 1.0, max(abs(suv.x - 0.5), abs(suv.y - 0.5)) * 2.0);
	vec4 swe = texture(water_swe_tex, clamp(suv, vec2(0.0), vec2(1.0)));
	float s_amp = water_swe_rect.w * s_in * s_rim;
	flow += swe.gb * s_amp;
	float carried_foam = swe.a * s_amp * live_foam;
	float speed = length(flow);
	float ph = TIME / max(flow_period, 0.001);
	float p0 = fract(ph);
	vec2 drift = flow * flow_drag * flow_period;
	float waves = mix(detail_at(v_world - drift * p0, TIME),
			detail_at(v_world - drift * fract(ph + 0.5), TIME),
			abs(p0 * 2.0 - 1.0));
	col += waves * ripple_strength * (1.0 - t);

	// ETA as a signed brightness band, the same composition as the sines above. Faded by the
	// baked depth so waves die at the waterline.
	float f_amp = s_amp * smoothstep(0.0, 0.04, d);
	col += clamp(swe.r * ripple_field_gain, -0.18, 0.18) * f_amp;
	col = mix(col, foam_color.rgb,
			smoothstep(ripple_foam_crest, ripple_foam_crest * 2.0, swe.r) * f_amp * 0.85);

	// SLOPE SHADING, from the TEXTURE rather than the mesh: the sim is 0.125 m and the mesh is
	// 0.5 m, so a mesh-derived normal would be four times coarser and visibly faceted. This is
	// what actually makes the displacement read; without it, subdividing the plane buys almost
	// nothing at a top-down camera.
	vec2 ts = 1.0 / vec2(textureSize(water_swe_tex, 0));
	float sdx = water_swe_rect.z * ts.x;
	float eR = texture(water_swe_tex, suv + vec2(ts.x, 0.0)).r;
	float eL = texture(water_swe_tex, suv - vec2(ts.x, 0.0)).r;
	float eU = texture(water_swe_tex, suv + vec2(0.0, ts.y)).r;
	float eD = texture(water_swe_tex, suv - vec2(0.0, ts.y)).r;
	vec2 slope = vec2(swe_lift(eR, d) - swe_lift(eL, d),
			swe_lift(eU, d) - swe_lift(eD, d)) * (normal_extra / (2.0 * sdx));
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 L = normalize(look_dir);
	// dot(n, L) - L.y is identically 0.0 on flat water, which is what keeps a still pond and
	// every pre-displacement screenshot bit-identical.
	float shade = dot(n, L) - L.y;
	col += clamp(shade * slope_shade, -0.20, 0.28) * s_amp;
	col = mix(col, foam_color.rgb, smoothstep(0.10, 0.28, shade) * s_amp * 0.6);

	// FOAM, from three sources that never fight: the shallows (which the depth map has
	// already located for us), the rapids, and the places the current crowds into itself.
	float foam = 1.0 - smoothstep(0.0, max(foam_depth, 0.001), d);
	// Fast water goes white, in travelling streaks rather than an even wash — `waves` is
	// already being carried downstream, so riding it costs nothing.
	float rapids = smoothstep(foam_speed * 0.55, foam_speed, speed) * (0.55 + 0.45 * waves);
	// Convergence: baked -divergence. Where flow crowds together, foam gathers and stays —
	// the eddy corners and the outside of a bend, exactly where a river collects its scum.
	float gather = smoothstep(foam_gather * 0.5, foam_gather, fl.b) * (0.6 + 0.4 * waves);
	// The shore band keeps its full weight; the two flow terms are accents ON water, not a
	// second coat of white over it. Summed unweighted, a narrow stream saturates instantly —
	// most of a 3-cell channel is "shore" by the corner rule before flow says anything.
	// Foam the SOLVER put there — born in shear and convergence, then carried downstream and
	// wound around the eddies. This is the term that reads as moving water rather than as a
	// pattern painted on still water, so it carries most of the weight where it exists.
	foam = clamp(foam + rapids * 0.55 + gather * 0.45 + carried_foam * 0.6, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam * 0.85);

	ALBEDO = col;
	// Shallow water is nearly clear and deep water is not, and the very edge fades out entirely so
	// the waterline is a soft meeting rather than a cut.
	ALPHA = smoothstep(0.0, 0.06, d) * mix(0.55, max_alpha, t);
}
