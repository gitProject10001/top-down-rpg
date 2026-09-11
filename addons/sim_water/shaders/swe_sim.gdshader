shader_type canvas_item;
// blend_disabled, and it is NOT cosmetic. A canvas_item shader's alpha is the BLEND FACTOR,
// and this is the first sim in the project to carry real data there (foam). With blending on,
// COLOR.a silently decides whether each texel is written at all: the dry branch writes
// vec4(0.0), alpha 0, so dry texels were never cleared, and foam bootstrapped itself to 1.0
// everywhere because only saturated texels could write. The two solvers this replaces both
// wrote alpha 1.0 unconditionally, which is why neither ever met this.
render_mode blend_disabled;
// THE SHALLOW WATER EQUATIONS, on a camera-following grid. This replaces BOTH previous
// solvers, and that is the point: ripple_sim evolved a height with no velocity, flow_sim
// evolved a velocity with no height, and everything that was missing from the water — a bore,
// the drawdown at a lip, a standing wave, foam that gathers where it should — is exactly the
// coupling between the two. SWE's state IS (height, velocity), so one RGBA texture and one
// pass do the work of both.
//
//   R   = eta   surface deviation from the LOCAL region's rest level, metres
//   G,B = u'    velocity DEVIATION from the terrain-baked current u0, m/s
//   A   = foam
//
// WHY u' AND NOT u. The baked current's div(u0) is NOT zero — it sums slope, drop and bank
// terms and only its eddy part is divergence-free; measured convergence p90 is about 0.4 1/s.
// Feeding that into continuity gives d(eta)/dt = -H*div(u) ~ 0.22 m/s and every pond in the
// world drains or overflows inside two seconds. Integrating the DEVIATION keeps u0 as pure
// kinematic transport — it advects momentum and foam, it never moves mass — and buys two
// things besides: u0's 3.9 m/s drops out of the CFL condition entirely, and G/B stay
// zero-centred, which is the same float16 precision argument the old ripple field already
// paid for once.
//
// WHY THE ODD-LOOKING CONTINUITY LINE. Forward-Euler on both eta and u is unconditionally
// unstable; the pair must be forward-BACKWARD (update u from grad(eta), then eta from the NEW
// u). One pass cannot read a neighbour's new u, but folding g*dt^2*lap(eta) into eta is
// algebraically the same thing. It is also a Rhie-Chow momentum-interpolation correction,
// which kills the collocated grid's checkerboard mode for free: half-life 0.048 s at 2dx, and
// 1.6%/s at 2 m, so nothing visible is touched.
//
// STABILITY: kappa = g*H*dt^2/dx^2 must stay under 0.25. At g 9.81, H 0.55, dt 1/60,
// dx 0.125 that is 0.0959 — a 2.6x margin, ceiling 1.43 m of depth against this world's 0.55.
// Exceeded, it fails as a grid-scale checkerboard doubling every few frames and then NaN, so
// the harness probes max|eta| rather than waiting to see it.

uniform sampler2D prev : hint_default_black, filter_linear, repeat_disable;
// THE SAME TEXTURE, BOUND TWICE, and this is not a nicety. `field` reads u0 and H0, which are
// genuinely low-frequency and want interpolation. `field_n` reads the region rest level Y,
// which MUST be nearest: at 1 m texels a linear fetch smears a 1.2 m tier step into a ramp,
// adjacent sim texels then differ by only 0.15 m — under any sane step threshold — so no step
// is detected, the gravity term IS applied across it, and g*(0.15/0.125) = 11.8 m/s^2 is
// exactly the delta-function explosion the weir exists to prevent.
uniform sampler2D field : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D field_n : hint_default_black, filter_nearest, repeat_disable;
// THE BED, in world Y, on its own texture, sampled NEAREST - and the alternative was tried and
// measured, so this is a decision rather than an inheritance.
//
// NEAREST COSTS A STAIRCASE. The field is half-metre treads with centimetre risers, so a waterline
// steps at half a metre and, worse, the shallows become a flight of sills a wave cannot climb.
//
// LINEAR REMOVES THE STAIRCASE AND BREAKS A LAKE AT REST. The seeded rest depth is Y - b, and Y is
// a per-region constant carrying a DRY SENTINEL over ground with no water. A sentinel cannot be
// interpolated: it steps at the field texel while a linear b slides between them, so the two stop
// cancelling and the seeded surface comes out ragged at every bank. Measured: a 73 mm cell moving
// in a valley that was supposed to be still, against a 2 mm tolerance.
//
// Taking the rest depth from the field's own linear H0 channel instead does not rescue it: H0 is
// CLAMPED to zero off water while the bed there is a 1000 m wall sentinel, and a linear fetch ramps
// that wall across a texel - a surface 26 m in the air on the first frame, float16 saturated in a
// few hundred steps.
//
// So the staircase stays until the BAKE changes: what this wants is a rest surface defined
// everywhere and smooth, with the wet test coming from `bed > rest` rather than from a sentinel.
// Then b and the rest surface can both be linear and cancel exactly. That is a field-format change,
// not a sampler flag, and it is the next thing this needs.
uniform sampler2D bed : hint_default_black, filter_nearest, repeat_disable;

uniform int res = 512;
// The bed/terrain texture's own resolution, so the bed can be addressed by integer texel rather
// than by a uv that two neighbouring cells compute slightly differently. See bed_at().
uniform int field_res = 128;
// Reconstruct the bed bilinearly between terrain texels instead of taking the nearest. On by
// default; the knob exists so the staircase can be put back for one run and the difference read
// off, which is the only honest way to claim a smooth bed is what let a front climb.
uniform bool bed_smooth = true;
// Above this the bed is Water.BED_WALL, the off-map sentinel, and must never be interpolated.
uniform float bed_wall_min = 500.0;
uniform float dx = 0.125;
uniform float dt = 0.0166667;
uniform float window_m = 64.0;
uniform vec2 scroll_uv = vec2(0.0);

uniform float gravity = 9.81;
// 1/s on u'. A linear drag damps AMPLITUDE at drag/2, so the half-life is 1.386/drag = 1.07 s
// — matching the old field's measured 0.96 s.
uniform float drag = 1.3;
uniform float manning = 0.03;
// Per step, on the zero-wavevector mode; also the bleed that drains the positivity clamp.
uniform float eta_keep = 0.999;
uniform float u_max = 3.0;
uniform float advect_gain = 0.0;   // momentum self-advection; 0 == parity with the old field
uniform float weir_cd = 1.0;       // multiples of critical discharge; 1.0 IS Froude 1
uniform float tier_eps = 0.5;      // |dY| above this is a STEP; a tier is 1.2 m
uniform bool weirs_on = true;
uniform float h_dry = 0.002;
uniform float h_wet = 0.02;
uniform float h_min = 0.01;
// THE DEPTH THE BED-FRICTION TERM IS ALLOWED TO SEE, and it is deliberately far below h_min.
// Manning goes as |u|/h^(4/3), so a vanishing column is already overwhelmingly damped BY THE
// PHYSICS - which is what actually stops a runup tongue in nature. Sharing h_min = 1 cm with the
// rest of the solver capped that friction at a hundredth of its proper value, so the physics could
// not do the job and wet_ramp was bolted on to do it instead. Half a millimetre keeps the division
// finite at h = 0 and nothing else.
uniform float h_fric = 0.0005;
uniform float poke_frac = 0.5;     // an impulse may displace at most this much of the column
uniform float dry_y = -1000.0;
uniform float spring_rate = 0.06;
uniform float spring_mark = 10000.0;
// How far the surface may draw down, as a fraction of rest depth. Below ~0.7 the cell is
// nearly dry and cannot be refilled; see the floor below.
uniform float draw_max : hint_range(0.1, 1.0, 0.05) = 0.55;

uniform float foam_decay = 1.2;
uniform float foam_jump = 2.5;
uniform float foam_crest = 1.5;
uniform float foam_plunge = 4.0;

uniform int impulse_count = 0;
uniform vec4 impulses[16];         // xy = uv, z = radius_uv, w = metres of downward poke
uniform bool reset = false;
// Reset to an EMPTY basin (eta = -H0) rather than a full one. The model's zero IS water at
// rest, so "empty" is a full-amplitude displacement away from it, not the absence of one.
uniform bool reset_empty = false;
// Bench tap: show the TERRAIN INPUT instead of the state, so a field that is not arriving is
// visible immediately rather than after an hour of chasing the solver.
uniform bool diag = false;

// ---------------------------------------------------------------- DEPTH MODE ---------------
// The state variable becomes h (water depth, >= 0) over the bed, so the surface is w = b + h.
// Everything the eta encoding cannot express follows from that one change: water can be ABSENT
// (h = 0, and it costs nothing), it can be ANYWHERE (not only where a map painted it), and the
// surface can sit at any height rather than a fixed per-region level.
uniform bool depth_mode = false;
// A face is open when there is hydrostatic depth across it. ZERO by default, because any positive
// value makes the gate a switch rather than a limit - see the note at the face loop. Kept as a
// knob only so a bisect can put it back.
uniform float hf_min = 0.0;
// THE CFL GUARD. On, because the alternative is a solver that dies silently and permanently
// while somebody watches a basin fill; off in every probe that measures the stability limit,
// because a guard set to kappa_max would otherwise report kappa_max back as the answer.
// STAGE 2: the staggered layout. A SEPARATE flag from depth_mode, because the two say different
// things and different consumers care. depth_mode says what R MEANS (an absolute depth, not a
// deviation); this says where G and B LIVE (on the cell's left and bottom faces, not at its
// centre). A viewer that draws depth cares about the first and not the second; anything that
// reads a velocity cares about the second and not the first.
uniform bool staggered = false;
// SECOND-ORDER SLOPE-LIMITED UPWIND on the advective terms. With it off the scheme is exactly the
// first-order upwind it replaces, which is what makes this a clean A/B rather than two solvers.
uniform bool muscl = true;
// NO-SLIP AT A SOLID'S WALL, as a quadratic tangential drag on the faces running alongside it.
//
// An obstacle here raises the bed, so hf goes to zero across its boundary and the face closes. That
// is a perfect FREE-SLIP wall: no mass crosses it and NO TANGENTIAL STRESS IS TRANSMITTED EITHER.
// And a free-slip cylinder does not shed a von Karman street - shedding needs a boundary layer, and
// a boundary layer is made of the vorticity a NO-SLIP wall generates. Without one the flow slides
// past the body and closes behind it symmetrically, which is exactly what was measured: transverse
// velocity in ANTIPHASE across the wake axis and streamwise in phase, at every body size and every
// Reynolds number tried. That is the potential-flow dipole signature, not a wake that failed to
// shed.
//
// So the wall has to take tangential momentum. Quadratic rather than linear because that is what a
// rough wall does, and it keeps the sink proportional to the thing it is meant to remove.
uniform float obs_wall_cd = 1.0;

// ============================== POLICY, NOT PHYSICS =========================================
//
// Everything below this line is an ARTISTIC CAP. It is here because the picture wants it, not
// because the equations do, and every probe that measures the scheme turns it off - a solver
// measured with its governor on reports the governor.
//
// WAVE SPEED. Scales g in the pressure term only, so c = sqrt(g*h) falls with it. A lake with
// slower waves reads as bigger: the eye judges scale from how fast a disturbance crosses a
// surface, and real water at these depths crosses a 20 m pond in six seconds, which on a screen
// looks like a puddle twitching. It cannot disturb a lake at rest, because g multiplies a gradient
// that is identically zero there - the same argument the CFL guard rests on - and it BUYS CFL
// headroom rather than spending it, since kappa is linear in g.
uniform float wave_scale = 1.0;
// GRID-SCALE SMOOTHING, and the selectivity is the point. Applied to the SURFACE as a discrete
// Laplacian, so it is exactly zero on a flat lake however the bed varies underneath, and its
// damping goes as k^2: at the two-texel mode the neighbours' mean differs from the centre by the
// whole amplitude, and at twenty texels it differs by about one per cent of it. So the grid-scale
// shimmer goes and the waves you can see do not.
//
// THE STAGGERED SCHEME DELIBERATELY HAS NO DIFFUSION - that was the whole point of moving velocity
// to the faces, because the collocated scheme's compact Laplacian cost 16.9 % of the energy in ten
// seconds and ate the centimetre-scale signal a shoaling wave is made of. This is not that term
// coming back: that one was load-bearing for STABILITY and ran at full strength always. This is a
// small optional filter with a dial on it, and the dial reads zero in every physics test.
uniform float smooth_grid = 0.0;
// AND AN AMPLITUDE GATE ON TOP OF THE SCALE ONE, which is what lets the gain be large.
//
// k^2 selectivity alone is a compromise: strong enough to kill the shimmer quickly and it starts
// eating long waves too, because k^2 falls off but never reaches zero. CURVATURE separates them
// far more sharply than wavelength does. The quantity smoothed here is w minus the mean of its
// neighbours, and for a two-texel shimmer of amplitude A that is 2A - about 2 mm - while for a
// wave one metre tall and four metres long it is k^2*A*dx^2, about 100 mm. A factor of fifty,
// against the factor of a hundred k^2 alone gives across the same range but with a long tail.
//
// So: full gain below `ripple_kill` of curvature, tapering to nothing above it. The shimmer is
// deep inside the band and dies in a step or two; anything with a shape is outside it and is not
// touched at all. That is "kill the low vibrations, leave the big waves" stated as arithmetic.
uniform float ripple_kill = 0.008;

// ---- OBSTACLES: solids standing in the water, in WINDOW UV, converted driver-side.
//   a = (centre.x, centre.y, half_x, half_y)   window fractions
//   b = (top_y, kind, cos(rot), sin(rot))      kind 0 = cylinder, 1 = box
// ---- edge_mode 2, THE CHANNEL: uniform inflow at -x, free-slip walls top and bottom, and an
// outflow at +x that must not reflect. A closed box would bounce a wake straight back through the
// body that shed it and produce a picture that looks exactly like shedding and is standing waves.
uniform float inflow_u = 0.0;      // m/s injected across the whole left rim
uniform float sponge_uv = 0.10;    // width of the outflow sponge, in window fractions
// ---- edge_mode 3, THE OCEAN: a wave-maker at -x and a beach at +x.
//
// The maker drives the inflow FACE VELOCITY sinusoidally rather than displacing the surface,
// because a velocity boundary is what a paddle is and it does not fight the water coming back at
// it. For a shallow-water wave of amplitude A on depth h, the two are related by u = A*sqrt(g/h),
// which is what wave_amp means here: metres of surface amplitude, converted at the boundary.
//
// WHAT IS ACTUALLY RESOLVABLE. At dx 0.2 m a wave needs about 20 cells to keep its shape, so
// lambda >= 4 m; on 0.55 m of water c = sqrt(g*h) = 2.3 m/s, so the period floor is about 1.7 s.
// Anything faster than that is not a wave on this grid, it is a column of cells taking turns.
uniform float wave_amp = 0.0;      // metres of surface amplitude at the maker
uniform float wave_period = 4.0;   // seconds
uniform float wave_time = 0.0;     // seconds, driven by the host so the phase survives a reseed
uniform int obs_count = 0;
uniform vec4 obs_a[8];
uniform vec4 obs_b[8];
uniform bool cfl_guard = true;
// ---- THE LAKE MUST BE THE SAME LAKE TOMORROW, and this is the term that promises it.
//
// A rate, per second, at which the water is drawn back toward the depth the terrain says it should
// have. Zero is off and the solver is untouched, which is the right default for a general solver -
// a dam break has no rest level to return to. The GAME sets it, because "the environment does not
// change on its own" is a gameplay requirement and not a fluid one.
//
// WHY IT IS NEEDED, measured rather than assumed. Two large non-conservative terms already fight
// each other in the shipped configuration, and the lake's size is wherever they happen to balance:
//
//   SEEP takes a flat rate off every wet cell - about 120 m3 a minute out of the game's lake.
//   THE HORIZON RIM (edge_mode 0) forces the outer 6 % of the window back to the rest depth every
//   step, which is a ~900 m2 reservoir creating or destroying whatever that takes - about the same
//   again, the other way.
//
// Neither is a bug on its own: seep is what lets a spring-fed chain self-balance, and the rim is
// what lets a window follow the camera without reflecting off its own edge. But the lake's extent
// was an accident of their ratio, and removing EITHER one alone made the drift worse rather than
// better - as shipped it lost 7.95 % of itself in a minute, and with seep floored it gained 16 %.
//
// A restoring force is the honest fix because it is bounded by construction: it can only move water
// TOWARD the authored level, so no accumulation of numerical error, no impulse and no boundary can
// walk the lake away and stay there. At 1/30 per second a wave lives and dies long before it is
// touched, and a lake pushed off its level returns over about half a minute.
uniform float level_keep = 0.0;
// Held a little under the true 0.25 limit, so the guard engages BEFORE the scheme is marginal
// rather than exactly at the cliff edge.
uniform float cfl_max = 0.20;
// SEEPAGE as a fixed rate, m/s. It cannot be eta_keep's proportional relaxation: h *= 0.999 is
// 6 %/s, which empties a half-metre pond in a minute. (And eta_keep was never really a sink -
// relaxing toward the rest surface is a sink above it and a SOURCE below it.)
uniform float seep = 0.001;
// 0 = HORIZON: fade to the rest depth at the window rim, for a window that follows a camera.
// 1 = WALL: leave the rim alone and let the off-map sentinel bed reflect - the lab's box.
uniform int edge_mode = 0;
// A per-step seed for the dither below. Any value that changes every step will do; the driver
// feeds it the step counter.
uniform float jitter = 0.0;
// BISECT KNOB for the store's dither. 1.0 is the shipped behaviour; 0.0 makes round_store a plain
// truncating store, so a probe can separate "float16 quantisation" from "the dither on top of it".
uniform float dither_gain = 1.0;

// ---- BENCH SEEDS, and they exist because two of the questions this solver has to answer cannot be
// asked with the API it has. splash() only ever pushes h DOWN, and reset only ever writes still
// water, so there is no way to hand the solver an initial VELOCITY field - which means no way to
// ask whether it can hold a vortex, and no way to hand it the one mode a collocated grid cannot
// restore. Both are seeds on the reset path; neither is reachable from a step.
//   0  as before: still water, full or empty per reset_empty
//   1  VORTEX      - a Gaussian-cored swirl on top of a full basin. Circulation is conserved by
//                    the real equations and can only decay here, because the term that would
//                    sustain it is the advective one this solver does not have.
//   2  CHECKERBOARD - h alternating by +-amplitude every texel. This is the k*dx = pi mode, and it
//                    sits in the null space of a 3-point (i+1)-(i-1) gradient: no restoring force
//                    and no damping, forever, unless something else supplies them.
uniform int seed_kind = 0;
uniform vec4 seed_p = vec4(0.5, 0.5, 0.1, 0.5);   // xy centre uv, z radius uv, w amplitude

const ivec2 OFF[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));

ivec2 cl(ivec2 p) { return clamp(p, ivec2(0), ivec2(res - 1)); }

// texelFetch, not texture(prev, UV +- texel): a weir conserves mass only if a fragment and its
// neighbour read the SAME number, and this makes that structural rather than a coincidence of
// bilinear sampling landing on texel centres. The clamp doubles as the window-edge wall.
vec4 st(ivec2 p) { return texelFetch(prev, cl(p), 0); }

// THE BED, ADDRESSED BY THE STATE TEXEL THAT STANDS ON IT, and integer all the way down.
//
// It used to be texture(bed, uv) here and texture(bed, uv + 1.0/res) for the neighbour, which is
// the SAME texel the neighbour fetches for itself - to within a float rounding of one addition.
// Under filter_nearest an ulp at a texel boundary is a DIFFERENT TEXEL, and the number it decides
// is hf, which decides whether the face between two cells exists at all. Two cells disagreeing by
// an ulp about a continuous quantity is noise; two cells disagreeing about whether they are
// connected is a hole in the conservation argument.
//
// Taking the neighbour's index as an INTEGER makes the agreement structural: cell i computing the
// face to i+1 and cell i+1 computing the face to i evaluate bed_at() on the same ivec2 and get the
// same bits, with no appeal to how floor() rounded.
//
// The argument is in WINDOW texels, never the scrolled state index. The bed texture is baked for
// the window and does not scroll with the state; mixing the two frames is a one-texel error that
// only appears when the camera moves, which is to say never on the bench and always in the game.
// AND Y COMES THROUGH THE SAME DOOR, which is not optional and cost a bug to learn.
//
// Y (the rest surface) and b (the bed) are baked at the SAME terrain texel and are only meaningful
// together: the rest depth is max(Y - b, 0). Read Y through the GPU's filter_nearest at a uv while
// reading b by integer index and they agree everywhere except exactly on a texel boundary, where
// the two roundings can land one texel apart. At RES 320 over FIELD_RES 128 the state texel centre
// (i + 0.5) * 0.4 is an exact integer for i = 2, 7, 12, ... - EVERY FIFTH COLUMN AND ROW.
//
// Measured: 153 texels of the valley bank seeded DRY when the terrain says they hold up to 0.10 m,
// because Y came from one texel and b from its neighbour across a bank that climbs 0.12 m per
// texel. The solver then spent six hundred steps correctly filling the holes, which every
// instrument reported as a lake that would not stay at rest.
ivec2 fld(ivec2 w) {
	return clamp(ivec2(floor((vec2(cl(w)) + 0.5) / float(res) * float(field_res))),
			ivec2(0), ivec2(field_res - 1));
}

float bed_texel(ivec2 p) {
	return texelFetch(bed, clamp(p, ivec2(0), ivec2(field_res - 1)), 0).r;
}

// THE BED, SMOOTHED - because a nearest bed is a flight of stairs and water cannot climb stairs.
//
// The terrain is baked at 0.5 m while the solver runs at 0.2 m, so a nearest bed gives every state
// cell one of a few discrete elevations and the boundaries between them are RISERS. On a 3 % beach
// that is 1.5 cm every half metre. Measured at the waterline after wet_ramp was deleted: the front
// needed to gain 1.29 cm to open the next face, against a wave arriving half a centimetre high. It
// is not being slowed on the slope, it is standing at the foot of a step.
//
// Reconstructed bilinearly the same ramp is exact - a linear function sampled and linearly
// interpolated is itself - so the riser becomes 0.6 cm per state texel and, more importantly,
// CONTINUOUS. hf then throttles the front instead of switching it off.
//
// THE C-PROPERTY IS UNAFFECTED, whatever filter this uses. w = b + max(Y - b, 0) = max(Y, b), which
// is exactly Y on any wet cell however b was reconstructed - provided the SAME b seeds the state
// and differences it, which is what routing everything through this one function guarantees.
//
// THE SENTINEL IS NEVER INTERPOLATED. Off-map the bed is Water.BED_WALL, a kilometre, and smearing
// that into its neighbours would ramp a wall across the map edge and put the surface in the sky -
// the failure this shader's header already records once. Any stencil touching the wall falls back
// to nearest, which keeps the wall one texel wide and vertical.
// THE TOP OF ANY SOLID COVERING THIS TEXEL, or a very negative number if none does.
//
// Tested at the TEXEL CENTRE from the INTEGER index, which is what makes two cells sharing a face
// agree about whether the solid is between them. Testing it from a uv would reintroduce exactly the
// bug fld() exists to remove, one layer up: an ulp of disagreement at a boundary becomes a
// full-magnitude disagreement about whether a wall is there.
//
// A hard in/out test, deliberately. A solid boundary IS a step, and softening it would put a ramp
// where the wall is - which is a leak, not a nicety.
// A SOFT RIM TAPERS TO THE BED, and it has to be the REAL bed rather than a fixed drop.
//
// The first attempt dropped the top by a flat 4 m across the rim. On a 1.04 m lake the bed is only
// 0.96 m under the body, so the taper went below it after a quarter of the way out and the dome
// collapsed to a nub: measured, a full-rimmed 0.25 m body made 6.8 mm of wake against a 5.9 mm
// noise floor. It displaced essentially nothing.
//
// bed_at() already has the terrain height in hand when it calls this, so pass it in and mix toward
// it. The dome then meets the ground exactly at its rim at ANY depth, with no constant to tune and
// nothing to get wrong on a shallower lake.
float obstacle_top(ivec2 w, float terrain_bed) {
	float top = -1.0e9;
	if (obs_count == 0) {
		return top;
	}
	vec2 c = (vec2(cl(w)) + 0.5) / float(res);
	for (int i = 0; i < obs_count; i++) {
		vec2 d = c - obs_a[i].xy;
		bool inside;
		// A CYLINDER MAY HAVE A SOFT RIM, and if it does its top RAMPS to nothing at the edge
		// rather than stepping. A stepped edge means the footprint is a whole number of cells that
		// changes as the body walks, and every change displaces a cell of water in one step - a
		// train of pulses at the bow, which is what the one-cell spikes were. obs_a.w is the inner
		// radius; equal to .z (the old packing) is a hard edge and behaves exactly as before.
		float soft_top = obs_b[i].x;
		if (obs_b[i].y < 0.5) {
			float ro = obs_a[i].z;
			float d2 = dot(d, d);
			inside = d2 <= ro * ro;
			float ri = obs_a[i].w;
			if (inside && ri < ro) {
				float t = clamp((ro - sqrt(d2)) / max(ro - ri, 1.0e-6), 0.0, 1.0);
				// Smoothstep, so the dome meets the bed with zero gradient and the volume it
				// displaces is a smooth function of where its centre sits.
				t = t * t * (3.0 - 2.0 * t);
				// Falling well below any bed at the rim: bed_at takes the max with the terrain, so
				// the solid simply stops existing there rather than leaving a lip.
				soft_top = mix(terrain_bed, obs_b[i].x, t);
			}
		} else {
			// Rotate into the box's own frame. cos and sin arrive precomputed so the shader never
			// has to agree with GDScript about an angle.
			vec2 r = vec2(obs_b[i].z * d.x + obs_b[i].w * d.y,
					-obs_b[i].w * d.x + obs_b[i].z * d.y);
			inside = abs(r.x) <= obs_a[i].z && abs(r.y) <= obs_a[i].w;
		}
		if (inside) {
			top = max(top, soft_top);
		}
	}
	return top;
}

float bed_terrain(ivec2 w) {
	ivec2 n = fld(w);
	if (!bed_smooth) {
		return bed_texel(n);
	}
	vec2 t = (vec2(cl(w)) + 0.5) / float(res) * float(field_res) - 0.5;
	ivec2 i0 = ivec2(floor(t));
	vec2 fr = t - vec2(i0);
	float b00 = bed_texel(i0);
	float b10 = bed_texel(i0 + ivec2(1, 0));
	float b01 = bed_texel(i0 + ivec2(0, 1));
	float b11 = bed_texel(i0 + ivec2(1, 1));
	if (max(max(b00, b10), max(b01, b11)) > bed_wall_min) {
		return bed_texel(n);
	}
	return mix(mix(b00, b10, fr.x), mix(b01, b11, fr.x), fr.y);
}


// The bed, INCLUDING anything standing on it. Everything downstream - the seed, the face depths,
// the surface, the equation mirror - goes through here, so a solid cannot be visible to one of
// them and invisible to another.
float bed_at(ivec2 w) {
	float bt = bed_terrain(w);
	return max(bt, obstacle_top(w, bt));
}

// THE SPRING FLAG IS NEAREST AND STAYS NEAREST. It is a flag, and an interpolated flag is a wrong
// answer in a band around every source - the same argument that gave the tier level its own
// sampler. It rides the Y channel offset by spring_mark, so it must be stripped before Y is used
// for anything and must never be carried into a max().
float spring_at(ivec2 w) {
	float yr = texelFetch(field_n, fld(w), 0).a;
	return yr > spring_mark * 0.5 ? 1.0 : 0.0;
}

// THE REST SURFACE, over the same stencil the bed is reconstructed on - the HIGHEST real one, dry
// only when all four are dry.
//
// Nearest Y against a SMOOTH bed is the Y/b split all over again, one level down. Y is a per-texel
// binary (a region's flat rest surface, or the -1000 dry sentinel) while b now varies continuously
// inside that texel, so at a waterline there is a band of cells whose terrain texel says DRY while
// their own bed sits below the lake. The seed leaves them empty, the solver's neighbours see an
// open face into them, and water flows in - measured as a lake at rest moving 6.7 cm and running
// at a quarter of a metre a second. Y follows the stencil and the waterline lands where b crosses
// the rest surface, at sub-texel resolution, which is the whole point of smoothing the bed.
//
// max(), not an average: a rest surface is not a quantity to interpolate, it is a LEVEL, and the
// question a cell is asking is "is any lake next to me standing above my bed". (In a world with
// two adjacent regions at different levels this takes the higher, which is a decision the wilds
// never reaches - the game runs the eta encoding.)
float rest_y_at(ivec2 w) {
	if (!bed_smooth) {
		float yr = texelFetch(field_n, fld(w), 0).a;
		return yr - (yr > spring_mark * 0.5 ? spring_mark : 0.0);
	}
	vec2 t = (vec2(cl(w)) + 0.5) / float(res) * float(field_res) - 0.5;
	ivec2 i0 = ivec2(floor(t));
	float best = dry_y;
	for (int k = 0; k < 4; k++) {
		float yr = texelFetch(field_n,
				clamp(i0 + ivec2(k & 1, k >> 1), ivec2(0), ivec2(field_res - 1)), 0).a;
		best = max(best, yr - (yr > spring_mark * 0.5 ? spring_mark : 0.0));
	}
	return best;
}

// The hydrostatic rest depth at a state texel: what a reset must seed and what "at rest" means.
// One function so the seed and the solver can never disagree about it.
float seed_rest(ivec2 w) { return max(rest_y_at(w) - bed_at(w), 0.0); }

// --------------------------------------------------------------- the depth solver ----------
//
// h over a bed, and the three things that make it correct rather than merely different:
//
// 1. THE PRESSURE TERM DIFFERENCES THE SURFACE, w = b + h, never the depth. The eta encoding got
//    this right for free, because eta IS the surface measured from a flat datum; the naive
//    h-substitution gets it catastrophically wrong. Over a sloping bed at rest, h varies while w
//    does not, so lap(h) is non-zero and the stabiliser becomes a DEPTH GENERATOR. Same trap for
//    the gradient. Every difference below is of w.
//
// 2. THE FACE DEPTH is LISFLOOD-FP's, and it replaces the whole apparatus the eta encoding needed
//    for a terraced world - the tier test, the wet test, the weir block:
//        hf = max(0, max(w, w_n) - max(b, b_n))
//    At rest w_n - w = 0, so no flux crosses a wet face however deep it is: the C-property, exact.
//    Where the neighbour bed stands above this surface, hf = 0 and the face closes with no branch.
//    And over a FREE OVERFALL onto dry lower ground, hf = h > 0, so the face OPENS - which is the
//    waterfall, and which the tempting min(w, w_n) form gets exactly backwards.
//
// 3. THE FLUX IS FACE-SYMMETRIC, built from OLD velocities on both sides. The eta solver reads
//    the neighbour's old velocity against its own NEW one, so two cells compute different numbers
//    for the same face and mass is quietly not conserved. Invisible while eta_keep bleeds
//    everything toward rest; fatal the moment "how much did the lake fill" is the headline. Old
//    velocities on both sides make q antisymmetric under swap, so the donor's loss IS the
//    receiver's gain, bit for bit.
//
//    Nothing is lost by it. g*dt^2*lap(w) is ALGEBRAICALLY the difference between fluxing with the
//    old velocity and fluxing with the new one, so old-velocity flux PLUS that term is still the
//    forward-backward scheme - conservative and symplectic at once.
//
// The weir is not deleted here, it is promoted: weir_cd*sqrt(g)*hf^1.5 stops being "the only way
// mass crosses a step" and becomes the universal critical-flow ceiling on every face, which is
// what keeps a metre of head across an overfall from producing a delta-function acceleration.
// ROUNDING THE STORE, and it is load-bearing rather than a polish item.
//
// THE RGBA16F WRITE TRUNCATES; it does not round to nearest. Measured: a lake seeded at rest over
// a sloping bed had a surface strictly inside [-1 ulp, 0] across all 36864 wet texels, never once
// above. On a CONSERVED quantity a truncating store is not noise, it is a systematic drain of half
// an ulp per cell per step - at h ~ 0.7 m, 2.4e-4 m/step, and a submerged ramp lost 10 % of itself
// in five seconds.
//
// ROUND-HALF-UP WAS TRIED AND IS WRONG, in a way that ten-second tests cannot see. Adding half an
// ulp before a truncating store IS round-to-nearest, and round-to-nearest is unbiased for a value
// that is MEASURED but ruinous for one that is ACCUMULATED: an increment smaller than half an ulp
// rounds back to where it started, so a cell gaining 1e-5 m per step against a 2.4e-4 ulp gains
// nothing, every step, forever. The error is invisible while water is deep and concentrated and
// arrives in big lumps; it becomes total once the water spreads thin, because the increments
// shrink while the ulp does not. Measured: a source delivering 26 m3/s was accounted for exactly
// for fifty seconds and then decayed to 12, with nothing lost anywhere - the water simply never
// arrived. The same threshold is why a runup tongue never wetted: its leading edge gains sub-ulp
// amounts, so the shoreline could not move at all, at ANY wet-gate setting.
//
// STOCHASTIC ROUNDING is the tool for an accumulator. Dithering by a uniform sub-ulp amount before
// the truncating store accepts an increment of f ulps with probability f, so the expectation is
// exact at any size, however small. It costs about an ulp of noise per cell - a millimetre at
// bench depths - and that is the right trade against not being able to add up.
float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}


float round_store(float v, float v_prev, vec2 uv) {
	if (v <= 0.0) {
		return v;
	}
	float ulp = exp2(floor(log2(v)) - 10.0);   // float16 carries a 10-bit mantissa
	// THE DITHER MUST NOT MOVE WHAT THE SOLVER DID NOT MOVE, and until this line it could.
	//
	// Stochastic rounding exists so that an increment SMALLER than an ulp still accumulates: dither
	// by uniform[0, 1) ulp before a truncating store and an increment of f ulps is accepted with
	// probability f, so the expectation is exact at any size. All of that is about an INCREMENT.
	// A cell at rest has none - h_new is h, bit for bit - and dithering it is not stochastic
	// rounding, it is just noise applied to a fixed point.
	//
	// It should still have been harmless, because v + ulp*hash with hash < 1 truncates back to v.
	// It is not, because the addition happens in FLOAT32: at h ~ 0.55 the float32 ulp is 6e-8 while
	// hash near 1 differs from 1 by less than that, so v + ulp*hash rounds UP to exactly v + ulp
	// and the truncating store keeps it. Rare per cell per step, certain across 36864 cells and 600
	// steps - and with no diffusion in the staggered scheme to sweep it up, those events accumulate
	// as a random walk. Measured: a flat pan at rest, which is a fixed point bit-for-bit through
	// five steps, wandering 5.4 mm by step 600, with the worst cells 44 to 128 texels from any wall
	// - far too deep for the boundary to have reached them.
	//
	// The guard is exact rather than a threshold on purpose. Anything that moved by even a
	// thousandth of an ulp still gets dithered, so accumulation is untouched: the source injects
	// about 0.02 ulp a step and is twenty times over this line.
	if (abs(v - v_prev) < ulp * 1e-3) {
		return v_prev;
	}
	return v + dither_gain * ulp * hash12(uv * 1024.0 + jitter);
}


vec4 step_depth(vec2 uv) {
	vec4 f = texture(field, uv);
	ivec2 W = ivec2(floor(uv * float(res)));
	// Y AND b OVER THE SAME STENCIL. See fld() and rest_y_at() - reading one through the sampler
	// and the other by index puts them a texel apart on every fifth column of the grid, and
	// smoothing one without the other puts a band of unseeded cells along every waterline.
	float spring = spring_at(W);
	float Y = rest_y_at(W);
	float b = bed_at(W);
	// THE REST DEPTH, RECONSTRUCTED FROM THE BED THIS SOLVER ACTUALLY READS - never the field's
	// own H0 channel, however tempting. H0 is sampled filter_LINEAR (a shoreline wants a smooth
	// depth) while the bed must be sampled NEAREST (it is the channel being differenced). Seeding
	// h from one and building the surface from the other gives w = b + h a sawtooth of up to the
	// whole depth per metre at the shoreline, which is a 43 m/s^2 pressure gradient out of a lake
	// at rest. Measured: the state saturated float16 within 600 steps.
	//
	// Reconstructed this way, w = b + max(Y - b, 0) is EXACTLY Y wherever the cell is wet, so the
	// C-property holds by construction rather than by tolerance. Off water Y is the dry sentinel,
	// so h0 is 0 - which is the right answer there too.
	// THE REST DEPTH, reconstructed as Y - b and NOT taken from the field's own H0 channel, even
	// though that channel exists and is linear and the algebra says they should cancel. They do
	// not, at the map edge: H0 is CLAMPED to zero off water while the bed there is a 1000 m wall
	// sentinel, and a linear fetch ramps that wall across a texel. Pairing a near-zero depth with
	// a half-interpolated kilometre gives a surface 26 m in the air on the first frame, and float16
	// saturates within a few hundred steps. `Y - b` clamps to zero over the same ground, because Y
	// is the dry sentinel there and max() eats the whole thing.
	float h0 = max(Y - b, 0.0);
	vec2 u0 = f.rg;

	ivec2 P = ivec2(floor((uv + scroll_uv) * float(res)));
	vec4 s = st(P);
	float h = max(s.r, 0.0);
	vec2 ud = s.gb;
	float foam = s.a;

	// IMPULSES FIRST, because they decide whether this texel is allowed to do nothing.
	float poke = 0.0;
	for (int i = 0; i < impulse_count; i++) {
		vec2 d = (uv - impulses[i].xy) / max(impulses[i].z, 1e-5);
		// A DISPLACEMENT, NOT A DELETION. The bare Gaussian subtracts water and never puts it back,
		// so every splash and every wake ring the raft leaves is water gone from the world - a boat
		// drained the lake it sailed on. Subtracting a second Gaussian of TWICE the radius and a
		// QUARTER the amplitude makes the pair exactly volume-neutral (a 2-D Gaussian's integral
		// goes as amplitude times radius squared), and it is the better shape anyway: a dip inside
		// a raised rim is what displacing water actually looks like.
		float r2 = dot(d, d);
		poke += impulses[i].w * (exp(-4.0 * r2) - 0.25 * exp(-r2));
	}

	vec4 sn[4];
	for (int i = 0; i < 4; i++) {
		sn[i] = st(P + OFF[i]);
	}
	// THE FAST PATH IS GONE. It returned early wherever this cell and its wettest neighbour were
	// both under h_dry, which sounds like "nothing to do here" and is in fact "do not let the
	// waterline move". Every texel the front is about to reach is exactly a texel whose neighbours
	// are nearly dry. An optimisation that decides the answer in the one place the answer is
	// interesting is not an optimisation, and a hundred thousand texels of arithmetic is not the
	// cost anybody was worried about.

	float w = b + h;

	// ---- the four faces
	float hf[4];
	float open[4];
	float wn[4];
	float hn[4];
	for (int i = 0; i < 4; i++) {
		float bn = bed_at(W + OFF[i]);
		float hnb = max(sn[i].r, 0.0);
		float wnb = bn + hnb;
		hf[i] = max(0.0, max(w, wnb) - max(b, bn));
		// THE GATE IS AT ZERO, not at hf_min, and that is what makes it continuous rather than a
		// switch. At hf -> 0 the two descriptions of the neighbour agree: hf reaches zero exactly
		// when max(w, w_n) meets max(b, b_n), and for a wet cell against a higher dry bank that is
		// the moment w = b_n = w_n. So the mirror below and the true value coincide there, and
		// nothing jumps.
		//
		// With hf_min at half a millimetre they did NOT coincide. A face flickered between mirrored
		// and centred as hf crossed the threshold, which changes grad_w by a factor of two,
		// discontinuously, every step, at every waterline - a noise source sitting exactly where
		// the centimetre-scale shoaling signal is. hf_min survives as a knob for bisecting; it is
		// no longer a floor anything relies on.
		open[i] = hf[i] > hf_min ? 1.0 : 0.0;
		// A closed face mirrors self, so its gradient and its flux fall to zero with no branch.
		// This IS the standard reflecting ghost cell and it is not a halving: the wall condition
		// is dw/dn = 0, and mirroring gives exactly the centred difference of the mirrored field.
		wn[i] = mix(w, wnb, open[i]);
		hn[i] = mix(h, hnb, open[i]);
	}

	// ---- momentum, on the SURFACE gradient
	vec2 grad_w = vec2(wn[0] - wn[1], wn[2] - wn[3]) / (2.0 * dx);

	// THE CFL GUARD, and the thing it prevents is not a wobble - it is death.
	//
	// This scheme is explicit, so it is stable only while kappa = g*h*dt^2/dx^2 stays under 0.25.
	// Past that the grid-scale mode doubles every few steps, and because the state lives in
	// RGBA16F the runaway ends at float16's largest finite value and STOPS THERE. 65504 is not
	// NaN and not Inf; it passes every finiteness test, it never recovers, and the session is over.
	// Measured on the configuration the bench opens in - a source into a closed box, which has no
	// steady state by construction - it arrives after about four minutes of watching a basin fill,
	// with no warning of any kind.
	//
	// So: cap the WAVE SPEED rather than let the scheme die. g_eff = g * min(1, kappa_max/kappa)
	// holds the local kappa at kappa_max however deep the water gets. What that costs is honest and
	// bounded: waves in water deeper than the ceiling travel at the ceiling's speed
	// (sqrt(kappa_max)*dx/dt, about 5.4 m/s here) instead of sqrt(g*h). Nothing else changes.
	//
	// WHAT IT DOES NOT COST is the C-property. g multiplies a gradient that is exactly zero on a
	// lake at rest, so scaling it per-cell cannot disturb a lake at rest no matter how it varies -
	// and the same g_eff goes into the Laplacian below, because that term is the other half of the
	// same forward-backward pair and halving one without the other would break the very stability
	// this is protecting.
	//
	// It is a KNOB and the probes turn it off. A guard that is on while the ceiling is being
	// measured would make suite 8 report the guard's constant back to itself.
	float g_eff = gravity;
	if (cfl_guard) {
		float hf_top = max(max(hf[0], hf[1]), max(hf[2], hf[3]));
		float kap = gravity * hf_top * dt * dt / (dx * dx);
		g_eff = gravity * min(1.0, cfl_max / max(kap, 1e-9));
	}
	vec2 acc = -g_eff * grad_w;

	// Advection, one filtered fetch, carrying foam. The backtrace is CLAMPED: off the edge the
	// sampler answers black, and in this encoding black is DRY, not rest - an unclamped fetch
	// imports dryness into the window every step.
	vec2 utot = u0 + ud;
	vec2 back = clamp((uv + scroll_uv) - utot * (dt / max(window_m, 0.001)),
			vec2(0.0), vec2(1.0));
	vec4 sb = texture(prev, back);
	vec2 u0b = texture(field, clamp(back - scroll_uv, vec2(0.0), vec2(1.0))).rg;
	ud = mix(ud, sb.gb + (u0b - u0), advect_gain);
	foam = sb.a;

	ud += acc * dt;
	ud *= exp(-drag * dt);
	float hs = max(h, h_min);
	// MANNING SEES THE REAL DEPTH, on its own floor rather than sharing h_min with everything else.
	//
	// This is the whole of what wet_ramp was standing in for. Bed friction goes as |u|/h^(4/3), so
	// a vanishing column is ALREADY overwhelmingly damped by the physics - that is what stops a
	// runup tongue in nature. Capping the depth this term sees at h_min = 1 cm capped the friction
	// too, so the physics could not do its job and a hand-made ramp was bolted on to do it instead.
	// At 2.5 mm the honest term divides by about 1.4 at 1 m/s; the ramp divided by five hundred.
	float hf_fric = max(h, h_fric);
	ud /= (1.0 + dt * gravity * manning * manning * length(u0 + ud) / pow(hf_fric, 1.3333333));
	// THE WET RAMP IS GONE, and it was the answer to "why is runup exactly zero".
	//
	//     wet_ramp = smoothstep(h_dry, h_wet, h);  ud *= wet_ramp;
	//
	// measured at the waterline of a 3 % beach: h = 0.00250 m, so wet_ramp = 0.002. The cell the
	// front has to advance THROUGH had its velocity multiplied by one five-hundredth. The tongue
	// was born stopped. Everything else was innocent, and each was measured: the face was OPEN
	// (hf 0.0025 against hf_min 0.0005), the riser was NEGATIVE (both cells in one bed texel, so
	// there was no step to climb), the flux ceiling never bound, and drag at four settings spanning
	// an order of magnitude moved the waterline by 0.000 m every time.
	float sp = length(ud);
	if (sp > u_max) {
		ud *= u_max / sp;
	}

	// ---- continuity
	float divq = 0.0;
	float lapW = 0.0;
	for (int i = 0; i < 4; i++) {
		float sgn = (i == 0 || i == 2) ? 1.0 : -1.0;
		// OLD velocities, BOTH sides. See note 3 in the header.
		float axu = (i < 2) ? 0.5 * (s.g + sn[i].g) : 0.5 * (s.b + sn[i].b);
		float uf = axu * sgn;
		// Upwind depth, capped by the face depth: a cell can export neither water it does not
		// have nor water standing above the sill between them.
		float hdon = (uf > 0.0) ? h : hn[i];
		float q = min(hf[i], hdon) * uf;
		// POSITIVITY IS STRUCTURAL, not a clamp afterwards. Four faces, so a quarter of the
		// column each, and h >= 0 becomes a theorem rather than a hope.
		//
		// THE OTHER CEILING IS CRITICAL FLOW, and the coefficient matters. Critical discharge at
		// depth h is h*sqrt(g*h) - that is Froude 1, the fastest water can cross a section. The
		// weir formula it was borrowed from carries Cd = (2/3)^1.5 = 0.544, which is right for
		// discharge over a crest given the UPSTREAM HEAD and wrong as a cap on face flux: it caps
		// at 0.54 of critical, so it throttles ordinary SUBCRITICAL flow. Measured: a wave crossing
		// water 5 cm deep needs 0.021 m2/s and was being held to 0.019, so it could not shoal at
		// all - waves died on the way in and the waterline never moved, at any wet-gate setting.
		// weir_cd stays a knob and defaults to 1.0, which is exactly Froude 1.
		float qcap = min(weir_cd * sqrt(gravity * hf[i]) * hf[i],
				hdon * dx / (4.0 * dt));
		q = clamp(q, -qcap, qcap);
		divq += open[i] * q / dx;
		lapW += open[i] * hf[i] * (wn[i] - w) / (dx * dx);
	}
	// g_eff, NOT gravity: this term and the pressure gradient above are the two halves of one
	// forward-backward step, and scaling one without the other is not a weaker guard, it is a
	// DIFFERENT SCHEME - and an unstable one, since the Laplacian is the only restoring force at
	// the grid scale.
	float h_new = h - dt * divq + g_eff * dt * dt * lapW;

	// ---- impulses: a displacement, and poke_frac is now a RATE limit rather than a positivity
	// guard. h - poke can no longer go negative, but a full-depth poke digs a hole with a
	// metre-high wall round it, which is an instant CFL violation.
	h_new -= min(poke, poke_frac * h);
	// ---- source, then seepage as a fixed rate
	h_new += spring * spring_rate * dt;
	// SEEPAGE TAKES THE EXCESS, NEVER THE LAKE.
	//
	// This used to be an unconditional `max(h_new - seep*dt, 0)`: a flat rate off EVERY wet cell,
	// which at the shipped 0.001 m/s is 3.6 metres of water an hour. Measured on the game's own
	// lake it removed 7.95 % of it in ONE MINUTE of play - the lake receded visibly and would have
	// been gone in about twelve. An environment that changes on its own is a gameplay bug whatever
	// the number is, and this one was not small.
	//
	// The term is still wanted: it is what lets a spring-fed chain self-balance, each pool rising
	// until seepage matches its inflow, and it is what drains flooded ground back off a hillside.
	// Both of those are about water ABOVE where the terrain says water belongs. Below that line it
	// is not seepage, it is a hole in the bottom of the lake.
	//
	// So it removes at most the excess over the authored rest depth: never below it, and - the
	// other half, easy to get wrong - never ADDING, which a plain max() against the floor would do
	// to any basin that happened to be filling.
	float rest_h = max(Y - b, 0.0);
	h_new -= min(seep * dt, max(h_new - rest_h, 0.0));
	h_new = max(h_new, 0.0);
	// ---- POLICY: back toward the level the terrain authored. See the uniform. Off at zero, and
	// it only ever moves water toward rest_h, so it cannot itself become a source of drift.
	// Applied ONLY where the terrain says there is water to keep: on ground that is merely flooded
	// rest_h is zero and this would fight the drainage that is supposed to happen there.
	if (level_keep > 0.0 && rest_h > 0.0) {
		h_new = mix(h_new, rest_h, clamp(level_keep * dt, 0.0, 1.0));
	}

	// ---- foam, from the Froude number.
	float Fr = length(u0 + ud) * inversesqrt(gravity * max(h_new, 0.05));
	vec2 nx1 = mix(ud, sn[0].gb, open[0]);
	vec2 nx0 = mix(ud, sn[1].gb, open[1]);
	vec2 nz1 = mix(ud, sn[2].gb, open[2]);
	vec2 nz0 = mix(ud, sn[3].gb, open[3]);
	float divu = ((nx1.x - nx0.x) + (nz1.y - nz0.y)) / (2.0 * dx);
	float jump = smoothstep(0.90, 1.30, Fr)
			* (0.30 + 0.70 * smoothstep(0.5, 3.0, max(-divu, 0.0)));
	// A CREST IS A SURFACE STANDING ABOVE ITS NEIGHBOURS, and it has to be measured that way
	// rather than against a baked rest depth.
	//
	// It used to be smoothstep(0.35, 0.60, (h_new - h0) / hs), and h0 = max(Y - b, 0) is exactly
	// ZERO everywhere no map painted water - which is all the ground a filling basin is supposed
	// to spill onto. So every flooded cell read (h - 0)/h = 1, saturated the smoothstep, and
	// accumulated foam at foam_crest against foam_decay to an equilibrium above 1. Overflow came
	// out as a solid white sheet, permanently, and no amount of tightening the SHORE foam could
	// touch it because this is the other term. The bug needed water somewhere the terrain has no
	// rest surface, so the lab's own painted basin never showed it.
	//
	// Against the neighbour mean it is well-balanced by construction: at rest the SURFACE is flat
	// whatever the bed does underneath, so the difference is zero on a lake, zero on a beach, zero
	// on flooded ground, and positive only where the water is actually heaped. Open faces only -
	// a closed face mirrors w and would drag the mean toward self, reading a wall as a crest.
	float wsum = 0.0;
	float wcnt = 0.0;
	for (int i = 0; i < 4; i++) {
		wsum += open[i] * wn[i];
		wcnt += open[i];
	}
	float w_new = b + h_new;
	float wbar = wcnt > 0.5 ? wsum / wcnt : w_new;
	float crest = smoothstep(0.35, 0.60, (w_new - wbar) / max(hs, h_min));
	// A FOAM-ONLY DEPTH WEIGHT, which is what wet_ramp's second job always was. Keeping a film of
	// water from reading as whitewater is a rendering decision and belongs here; multiplying the
	// VELOCITY by the same number was the physics bug. h_wet keeps its meaning and loses its teeth.
	foam += (jump * foam_jump + crest * foam_crest) * smoothstep(0.0, h_wet, h_new) * dt;
	foam -= foam * clamp(foam_decay * dt, 0.0, 1.0);

	// ---- the window edge, and this is NOT today's rim fade wearing a new name.
	// A texel that has just scrolled into view has no history: st() clamps, so it inherits the
	// edge value, and the rim has already damped that toward zero. In the eta encoding zero is
	// REST and nobody noticed. Here zero is DRY, so without this the window drags a permanent dry
	// crescent behind the camera - a four-metre ring of exposed bed following the player
	// everywhere. Both the rim and the newly-arrived band must fall back to the REST DEPTH.
	vec2 src = uv + scroll_uv;
	float newly = (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) ? 1.0 : 0.0;
	if (edge_mode == 0) {
		vec2 bnd = min(uv, vec2(1.0) - uv);
		float rim = smoothstep(0.0, 0.06, min(bnd.x, bnd.y));
		h_new = mix(h0, h_new, rim);
		ud *= rim;
		foam *= rim;
	}
	h_new = mix(h_new, h0, newly);
	ud = mix(ud, vec2(0.0), newly);
	foam = mix(foam, 0.0, newly);

	return vec4(round_store(max(h_new, 0.0), h, uv), ud, clamp(foam, 0.0, 1.0));
}



// ================================ THE STAGGERED SOLVER ======================================
//
// Stage 2. Same RGBA16F texture, different MEANING for two of its channels:
//
//   R = h      water depth at the CELL CENTRE          (unchanged)
//   G = u->    x velocity on the cell's LEFT face      (i-1/2, j)
//   B = v^     y velocity on the cell's BOTTOM face    (i, j-1/2)
//   A = foam                                            (unchanged)
//
// The degrees of freedom come out exact - one depth and two faces per cell, and every face in the
// domain is owned by exactly one cell. It is scroll-safe because the window origin snaps to whole
// metres, which is five state texels at dx 0.2, so h and both faces shift by the same integer and
// nothing lands on a half texel.
//
// WHY BOTHER. The collocated pressure gradient is (w[i+1] - w[i-1]) / 2dx, whose Fourier symbol
// sin(theta)/dx is exactly ZERO at theta = k*dx = pi. The checkerboard is invisible to it. So a
// collocated grid needs a separate restoring force at the grid scale, and ours is the compact
// Laplacian g*dt^2*div(h grad w) - which is a DIFFUSION OF THE FREE SURFACE, and a diffusion does
// not know which wavelength you meant it for. Measured with drag and Manning switched off: 16.1 %
// of the energy in a closed box, gone in ten seconds, to nothing but the scheme.
//
// A staggered face gradient is (w[i] - w[i-1]) / dx, symbol 2i*sin(theta/2)/dx, which is MAXIMAL
// at theta = pi. The mode the other scheme could not see is the one this one restores hardest, so
// no stabiliser is needed anywhere and the diffusion goes with it.
//
// AND IT IS SYMPLECTIC, which doubles the depth ceiling for free. Update the face velocity from
// the old surfaces, then flux with the NEW velocity:
//     U' = U - i*g*dt*A*W,        W' = W - i*H*dt*A*U',       A = 2 sin(theta/2)/dx
// gives det(M) = 1 exactly, against the collocated 1 - 4*kappa*sin^4(theta/2). Stability is then
// |tr| <= 2, i.e. 4*kappa*sin^2(theta/2) <= 4, so kappa <= 1 in 1D and kappa <= 0.5 in 2D - twice
// the collocated 0.25. Predicted ceiling 3.67 m -> 7.34 m, and suite 8 is the falsifiable test.
//
// ONE PASS, BY REDUNDANT RECOMPUTE. Continuity needs the NEW velocity on all four faces of a cell
// and two of them belong to neighbours, but the driver allows exactly one viewport render per
// frame. So every fragment computes its neighbours' faces as well as its own. Momentum on a face
// is a local stencil over OLD data, so the two cells that share a face call the same function with
// the same ivec2 and read the same texels in the same order - the numbers are identical by
// construction rather than by tolerance, and the donor's loss IS the receiver's gain.
//
// THE DISCIPLINE THAT KEEPS THAT TRUE, and it lapses silently:
//   - every face function takes an ivec2 and NOTHING ELSE. No uv, no float position, no
//     pre-fetched stencil handed in by the caller.
//   - no caching across faces. Recomputing hf_x twice inside one fragment is correct; hoisting it
//     into a variable shared between two different faces is not.
//   - the scroll enters in ONE place, inside stw(), so a window index can never mix with a state
//     index.
// The failure if it lapses is a slow direction-dependent mass drift that passes at 600 steps and
// fails at 6000, which is what probe_swe_long exists to catch.

// The integer texel scroll. scroll_uv * res is a whole number by construction (the window origin
// snaps to metres, which is 5 texels at dx 0.2), so this is exact and a window index plus this IS
// the state index.
ivec2 scr() { return ivec2(round(scroll_uv * float(res))); }

// The state at a WINDOW texel. Everything below works in window indices; this is the one place the
// scroll enters, so the two frames cannot be confused anywhere else.
vec4 stw(ivec2 w) { return st(w + scr()); }

float depth_at(ivec2 w) { return max(stw(w).r, 0.0); }

// The free surface at a cell: water where there is water, bare bed where there is not - which is
// what lets hf below close a face against dry ground with no branch.
float surf_at(ivec2 w) { return bed_at(w) + depth_at(w); }

// LISFLOOD-FP's face depth on the x-face at (i-1/2, j) - the face OWNED by cell w, between w-ex
// and w. The depth over the HIGHER of the two beds: zero when that bed stands above both surfaces,
// which is a closed face; equal to the upstream depth over a free overfall, which is a waterfall.
float hf_x(ivec2 w) {
	ivec2 a = w - ivec2(1, 0);
	float ba = bed_at(a);
	float bb = bed_at(w);
	return max(0.0, max(ba + depth_at(a), bb + depth_at(w)) - max(ba, bb));
}

float hf_y(ivec2 w) {
	ivec2 a = w - ivec2(0, 1);
	float ba = bed_at(a);
	float bb = bed_at(w);
	return max(0.0, max(ba + depth_at(a), bb + depth_at(w)) - max(ba, bb));
}

// The CFL guard's effective gravity for a face carrying depth hfc. Same argument as the collocated
// branch: g multiplies a gradient that is identically zero on a lake at rest, so scaling it per
// face cannot disturb one however it varies.
float g_at(float hfc) {
	// wave_scale first: it is a policy dial on the wave speed, and the guard below then measures
	// the kappa the solver will ACTUALLY run at rather than the one it would have without it.
	float g = gravity * wave_scale;
	if (!cfl_guard) {
		return g;
	}
	float kap = g * hfc * dt * dt / (dx * dx);
	return g * min(1.0, cfl_max / max(kap, 1e-9));
}

// ---- MUSCL: A SLOPE-LIMITED SECOND-ORDER UPWIND FOR THE ADVECTIVE TERMS.
//
// First-order upwind carries numerical viscosity nu = u*dx/2. On this grid that makes the effective
// Reynolds number Re = U*D/nu = 2*D/dx - and THE INFLOW SPEED CANCELS, so driving the channel
// harder buys proportionally more viscosity and nothing else. The only dial is how many cells span
// the body, and a sweep to Re 120 still produced a stable symmetric wake with no shedding at all.
// That is the measurement this exists to move.
//
// THE VAN LEER LIMITER, in its harmonic-mean form: for two consecutive differences a and b it
// returns 2ab/(a+b) when they agree in sign and ZERO when they do not. Zero at an extremum is the
// whole point - it is what makes the scheme TVD, so a second-order stencil cannot manufacture a new
// maximum out of a shock, which is how an unlimited second-order scheme turns a bore into ringing
// and then into a NaN.
float vanleer(float a, float b) {
	float ab = a * b;
	return ab > 0.0 ? 2.0 * ab / (a + b) : 0.0;
}

// The limited slope of u about the x-face owned by cell w. Three fetches, all old state, indexed
// only by ivec2 - so two cells asking about the same face still get the same bits.
float slope_ux(ivec2 w) {
	float um = stw(w - ivec2(1, 0)).g;
	float u0 = stw(w).g;
	float up = stw(w + ivec2(1, 0)).g;
	return vanleer(u0 - um, up - u0);
}

float slope_vy(ivec2 w) {
	float vm = stw(w - ivec2(0, 1)).b;
	float v0 = stw(w).b;
	float vp = stw(w + ivec2(0, 1)).b;
	return vanleer(v0 - vm, vp - v0);
}

// du/dx at the x-face owned by w, second-order and upwind-biased.
//
// MUSCL reconstructs the advected quantity at the two ends of the control volume from the UPWIND
// side, each corrected by half its limited slope, and differences those instead of the raw values:
//     du/dx = (u_k - u_{k-1} + 0.5*(sigma_k - sigma_{k-1})) / dx      for a > 0
// With sigma identically zero this is exactly the first-order upwind it replaces, which is what
// makes `muscl` a clean A/B rather than a different solver.
float dudx_at(ivec2 w, float a) {
	if (a > 0.0) {
		float um = stw(w - ivec2(1, 0)).g;
		float u0 = stw(w).g;
		float corr = muscl ? 0.5 * (slope_ux(w) - slope_ux(w - ivec2(1, 0))) : 0.0;
		return (u0 - um + corr) / dx;
	}
	float u0 = stw(w).g;
	float up = stw(w + ivec2(1, 0)).g;
	float corr = muscl ? 0.5 * (slope_ux(w + ivec2(1, 0)) - slope_ux(w)) : 0.0;
	return (up - u0 - corr) / dx;
}

// du/dy at the x-face owned by w - the TRANSVERSE difference, limited the same way. The slope here
// is of u across y, so it is its own stencil rather than slope_ux.
float dudy_at(ivec2 w, float a) {
	float u0 = stw(w).g;
	if (a > 0.0) {
		float um = stw(w - ivec2(0, 1)).g;
		float corr = 0.0;
		if (muscl) {
			float s0 = vanleer(u0 - um, stw(w + ivec2(0, 1)).g - u0);
			float sm = vanleer(um - stw(w - ivec2(0, 2)).g, u0 - um);
			corr = 0.5 * (s0 - sm);
		}
		return (u0 - um + corr) / dx;
	}
	float up = stw(w + ivec2(0, 1)).g;
	float corr = 0.0;
	if (muscl) {
		float s0 = vanleer(u0 - stw(w - ivec2(0, 1)).g, up - u0);
		float sp = vanleer(up - u0, stw(w + ivec2(0, 2)).g - up);
		corr = 0.5 * (sp - s0);
	}
	return (up - u0 - corr) / dx;
}

float dvdy_at(ivec2 w, float a) {
	if (a > 0.0) {
		float vm = stw(w - ivec2(0, 1)).b;
		float v0 = stw(w).b;
		float corr = muscl ? 0.5 * (slope_vy(w) - slope_vy(w - ivec2(0, 1))) : 0.0;
		return (v0 - vm + corr) / dx;
	}
	float v0 = stw(w).b;
	float vp = stw(w + ivec2(0, 1)).b;
	float corr = muscl ? 0.5 * (slope_vy(w + ivec2(0, 1)) - slope_vy(w)) : 0.0;
	return (vp - v0 - corr) / dx;
}

float dvdx_at(ivec2 w, float a) {
	float v0 = stw(w).b;
	if (a > 0.0) {
		float vm = stw(w - ivec2(1, 0)).b;
		float corr = 0.0;
		if (muscl) {
			float s0 = vanleer(v0 - vm, stw(w + ivec2(1, 0)).b - v0);
			float sm = vanleer(vm - stw(w - ivec2(2, 0)).b, v0 - vm);
			corr = 0.5 * (s0 - sm);
		}
		return (v0 - vm + corr) / dx;
	}
	float vp = stw(w + ivec2(1, 0)).b;
	float corr = 0.0;
	if (muscl) {
		float s0 = vanleer(v0 - stw(w - ivec2(1, 0)).b, vp - v0);
		float sp = vanleer(vp - v0, stw(w + ivec2(2, 0)).b - vp);
		corr = 0.5 * (sp - s0);
	}
	return (vp - v0 - corr) / dx;
}

// THE NEW x VELOCITY on the face owned by cell w. Reads only OLD state; takes only an ivec2.
//
// The pressure term differences the two cells the face separates, over ONE dx. There is no
// mirroring and no factor of two: on a staggered grid a wall is a face that does not exist, not a
// ghost cell carrying a reflected surface.
float mom_x(ivec2 w) {
	// THE RIM MASK, and it is load-bearing rather than tidy. Faces exist for i in [0, res] but
	// only i in [0, res-1] have a cell to live in. Face 0 is the left domain wall and face res is
	// the right one - and the right one is the dangerous case, because st()'s clamp would hand
	// back cell res-1's OWN face as though it were the wall's: a different number, for a different
	// place, with nothing to say it is wrong.
	if (w.x <= 0 || w.x >= res) {
		// THE INFLOW is the one rim face that is not a wall. Under edge_mode 2 the left edge is
		// driven at inflow_u and the right is left to the sponge below; every other rim face is
		// still a wall, including under the channel.
		if ((edge_mode == 2 || edge_mode == 3) && w.x <= 0) {
			// THE WAVE-MAKER, on the inflow face. A velocity paddle rather than a surface
			// displacement: a displacement boundary holds the surface at a value, which also holds
			// down whatever comes BACK from the beach, so the maker doubles as a perfect mirror and
			// the basin fills with standing waves. Driving the velocity leaves the returning wave
			// free to pass through.
			float w_u = inflow_u;
			if (edge_mode == 3 && wave_amp > 0.0) {
				// u = A * sqrt(g/h) is the shallow-water relation between surface amplitude and
				// particle velocity. h from the rest depth at the maker, which is the deep end.
				float h_maker = max(seed_rest(ivec2(0, w.y)), h_min);
				w_u += wave_amp * sqrt(gravity / h_maker)
						* sin(6.2831853 * wave_time / max(wave_period, 0.05));
			}
			return w_u;
		}
		return 0.0;
	}
	float hfc = hf_x(w);
	if (hfc <= 0.0) {
		return 0.0;
	}
	float u = stw(w).g;
	// ---- ADVECTION, u du/dx + v du/dy. THIS IS THE EDDIES, and without it there are provably
	// none: with no advective term the momentum update is the curl of a gradient, whose curl is
	// identically zero, so vorticity can only ever decay. Measured before this line existed - a
	// seeded vortex lost circulation 10 % FASTER than pure drag, and switching the old
	// semi-Lagrangian path on changed the answer by nothing at all, to four decimals.
	//
	// FIRST-ORDER UPWIND on the advective difference specifically. It is the only term here that
	// can put energy INTO a mode, and centred it is unstable at every dt.
	//
	// v AT AN x-FACE IS THE CORNER MEAN of the four y-faces around it, and that is a deliberate
	// departure from Jeschke & Wojtan Eq 19, which writes a single transverse face. Taken
	// literally, Eq 19 and Eq 20 are biased the same way round in x and in y, so a vortex would
	// acquire a preferred sense of rotation - which is exactly the quantity this term exists to
	// produce, so the bias would be indistinguishable from the result.
	if (advect_gain > 0.0) {
		float vbar = 0.25 * (stw(w).b + stw(w - ivec2(1, 0)).b
				+ stw(w + ivec2(0, 1)).b + stw(w + ivec2(-1, 1)).b);
		u -= advect_gain * dt * (u * dudx_at(w, u) + vbar * dudy_at(w, vbar));
	}
	u += -g_at(hfc) * (surf_at(w) - surf_at(w - ivec2(1, 0))) / dx * dt;
	u *= exp(-drag * dt);
	// Manning over the FACE depth on its own floor. A vanishing column is overwhelmingly damped by
	// |u|/h^(4/3), and that is the physics that stops a runup tongue - see h_fric.
	u /= (1.0 + dt * gravity * manning * manning * abs(u) / pow(max(hfc, h_fric), 1.3333333));
	// THE SOLID'S WALL. This face runs alongside a solid if the cell above or below it is inside
	// one; the drag is then on the velocity ALONG that wall, which is the momentum a no-slip
	// boundary removes and the vorticity it therefore generates.
	if (obs_wall_cd > 0.0 && obs_count > 0
			&& (obstacle_top(w + ivec2(0, 1), bed_terrain(w + ivec2(0, 1))) > -1.0e8
			|| obstacle_top(w - ivec2(0, 1), bed_terrain(w - ivec2(0, 1))) > -1.0e8)) {
		u /= (1.0 + obs_wall_cd * abs(u) * dt / dx);
	}
	return clamp(u, -u_max, u_max);
}

float mom_y(ivec2 w) {
	if (w.y <= 0 || w.y >= res) {
		return 0.0;
	}
	float hfc = hf_y(w);
	if (hfc <= 0.0) {
		return 0.0;
	}
	float v = stw(w).b;
	// The mirror image of mom_x's advection, corner mean and all. Written out rather than shared,
	// because sharing it would need the axis as a parameter and every face function here takes an
	// ivec2 and nothing else - that discipline is what makes two cells agree about a face.
	if (advect_gain > 0.0) {
		float ubar = 0.25 * (stw(w).g + stw(w - ivec2(0, 1)).g
				+ stw(w + ivec2(1, 0)).g + stw(w + ivec2(1, -1)).g);
		v -= advect_gain * dt * (v * dvdy_at(w, v) + ubar * dvdx_at(w, ubar));
	}
	v += -g_at(hfc) * (surf_at(w) - surf_at(w - ivec2(0, 1))) / dx * dt;
	v *= exp(-drag * dt);
	v /= (1.0 + dt * gravity * manning * manning * abs(v) / pow(max(hfc, h_fric), 1.3333333));
	if (obs_wall_cd > 0.0 && obs_count > 0
			&& (obstacle_top(w + ivec2(1, 0), bed_terrain(w + ivec2(1, 0))) > -1.0e8
			|| obstacle_top(w - ivec2(1, 0), bed_terrain(w - ivec2(1, 0))) > -1.0e8)) {
		v /= (1.0 + obs_wall_cd * abs(v) * dt / dx);
	}
	return clamp(v, -u_max, u_max);
}

// THE DISCHARGE across a face, m2/s, positive toward +x, RETURNED WITH THE VELOCITY THAT MADE IT.
//
// One function, because continuity and (from stage 3) the advective flux must carry the same
// number - if the two ever fluxed different discharges an eddy would spin up or decay on its own,
// which is exactly the quantity being added.
//
// It returns (q, u) as a pair rather than calling mom_x() again, and that is an OPTIMISATION THAT
// DOES NOT BREAK THE BIT-IDENTITY DISCIPLINE - which most optimisations here would. The rule is
// that a face's value must depend on nothing but its integer index, so that the two cells sharing
// it compute the same bits; caching inside ONE evaluation of ONE face is invisible to that. What
// is forbidden is hoisting a face's value out to a caller that then hands it to a different face,
// which is how a cell ends up using its neighbour's arithmetic instead of its own.
//
// Worth doing: without it a fragment evaluates about 52 bed lookups, each of which is a bilinear
// four-fetch, for something over two hundred texture reads per texel per step.
vec2 flux_x(ivec2 w) {
	float u = mom_x(w);
	float hfc = hf_x(w);
	// Upwind donor: u > 0 carries water from the cell BEHIND the face.
	float hdon = (u > 0.0) ? depth_at(w - ivec2(1, 0)) : depth_at(w);
	// Positivity is structural - four faces, a quarter of the column each, so h >= 0 is a theorem
	// rather than a clamp. The other ceiling is critical flow: h*sqrt(g*h) is Froude 1, the fastest
	// water can cross a section.
	float cap = min(weir_cd * sqrt(gravity * hfc) * hfc, hdon * dx / (4.0 * dt));
	return vec2(clamp(min(hfc, hdon) * u, -cap, cap), u);
}

vec2 flux_y(ivec2 w) {
	float v = mom_y(w);
	float hfc = hf_y(w);
	float hdon = (v > 0.0) ? depth_at(w - ivec2(0, 1)) : depth_at(w);
	float cap = min(weir_cd * sqrt(gravity * hfc) * hfc, hdon * dx / (4.0 * dt));
	return vec2(clamp(min(hfc, hdon) * v, -cap, cap), v);
}

// The face depth CONNECTING cell w to its neighbour i, for the foam terms. Neighbour +x and +y are
// reached across the NEIGHBOUR's face; -x and -y across this cell's own.
float hf_link(ivec2 w, int i) {
	if (i == 0) { return hf_x(w + ivec2(1, 0)); }
	if (i == 1) { return hf_x(w); }
	if (i == 2) { return hf_y(w + ivec2(0, 1)); }
	return hf_y(w);
}


vec4 step_staggered(vec2 uv) {
	ivec2 W = ivec2(floor(uv * float(res)));
	float spring = spring_at(W);
	float Y = rest_y_at(W);
	float b = bed_at(W);
	float h0 = max(Y - b, 0.0);

	vec4 s = stw(W);
	float h = max(s.r, 0.0);
	float foam = s.a;

	float poke = 0.0;
	for (int i = 0; i < impulse_count; i++) {
		vec2 d = (uv - impulses[i].xy) / max(impulses[i].z, 1e-5);
		// A DISPLACEMENT, NOT A DELETION. The bare Gaussian subtracts water and never puts it back,
		// so every splash and every wake ring the raft leaves is water gone from the world - a boat
		// drained the lake it sailed on. Subtracting a second Gaussian of TWICE the radius and a
		// QUARTER the amplitude makes the pair exactly volume-neutral (a 2-D Gaussian's integral
		// goes as amplitude times radius squared), and it is the better shape anyway: a dip inside
		// a raised rim is what displacing water actually looks like.
		float r2 = dot(d, d);
		poke += impulses[i].w * (exp(-4.0 * r2) - 0.25 * exp(-r2));
	}

	// ---- continuity, from the four face discharges. NO LAPLACIAN: the velocity being fluxed is
	// already the new one, which is the thing g*dt^2*lap(w) was standing in for on a grid that
	// could not read a neighbour's updated velocity.
	vec2 fxl = flux_x(W);
	vec2 fxr = flux_x(W + ivec2(1, 0));
	vec2 fyb = flux_y(W);
	vec2 fyt = flux_y(W + ivec2(0, 1));
	float divq = ((fxr.x - fxl.x) + (fyt.x - fyb.x)) / dx;
	float h_new = h - dt * divq;

	h_new -= min(poke, poke_frac * h);
	h_new += spring * spring_rate * dt;
	// SEEPAGE TAKES THE EXCESS, NEVER THE LAKE.
	//
	// This used to be an unconditional `max(h_new - seep*dt, 0)`: a flat rate off EVERY wet cell,
	// which at the shipped 0.001 m/s is 3.6 metres of water an hour. Measured on the game's own
	// lake it removed 7.95 % of it in ONE MINUTE of play - the lake receded visibly and would have
	// been gone in about twelve. An environment that changes on its own is a gameplay bug whatever
	// the number is, and this one was not small.
	//
	// The term is still wanted: it is what lets a spring-fed chain self-balance, each pool rising
	// until seepage matches its inflow, and it is what drains flooded ground back off a hillside.
	// Both of those are about water ABOVE where the terrain says water belongs. Below that line it
	// is not seepage, it is a hole in the bottom of the lake.
	//
	// So it removes at most the excess over the authored rest depth: never below it, and - the
	// other half, easy to get wrong - never ADDING, which a plain max() against the floor would do
	// to any basin that happened to be filling.
	float rest_h = max(Y - b, 0.0);
	h_new -= min(seep * dt, max(h_new - rest_h, 0.0));
	h_new = max(h_new, 0.0);
	// ---- POLICY: back toward the level the terrain authored. See the uniform. Off at zero, and
	// it only ever moves water toward rest_h, so it cannot itself become a source of drift.
	// Applied ONLY where the terrain says there is water to keep: on ground that is merely flooded
	// rest_h is zero and this would fight the drainage that is supposed to happen there.
	if (level_keep > 0.0 && rest_h > 0.0) {
		h_new = mix(h_new, rest_h, clamp(level_keep * dt, 0.0, 1.0));
	}

	// ---- POLICY: grid-scale smoothing of the SURFACE. See the uniform. Zero on a flat lake
	// whatever the bed does, because it differences w and not h; k^2-selective, so it takes the
	// two-texel shimmer and leaves anything you would call a wave.
	//
	// CONNECTED neighbours only. A closed face is a wall, and averaging across one would pull the
	// waterline toward dry ground - which is a shoreline that creeps, the exact failure this
	// project spent a week removing.
	if (smooth_grid > 0.0) {
		float ssum = 0.0;
		float scnt = 0.0;
		for (int i = 0; i < 4; i++) {
			if (hf_link(W, i) > 0.0) {
				ssum += surf_at(W + OFF[i]);
				scnt += 1.0;
			}
		}
		if (scnt > 0.5) {
			float lap = ssum / scnt - (b + h_new);
			// The gate. Below ripple_kill of curvature this is 1 and the full gain applies; by
			// four times it it is 0 and the wave passes untouched.
			float gate = 1.0 - smoothstep(ripple_kill, ripple_kill * 4.0, abs(lap));
			h_new = max(h_new + smooth_grid * gate * lap, 0.0);
		}
	}

	// ---- this cell's own two faces, which is what the state carries forward. Taken from the
	// fluxes already computed, so the velocity stored and the velocity fluxed cannot differ.
	float u_new = fxl.y;
	float v_new = fyb.y;

	// ---- foam. "The velocity here" on a staggered grid is the mean of the two faces either side.
	vec2 ucen = vec2(0.5 * (u_new + fxr.y), 0.5 * (v_new + fyt.y));
	float Fr = length(ucen) * inversesqrt(gravity * max(h_new, 0.05));
	// The divergence is already computed above. Reuse it rather than differencing velocities a
	// second time over 2dx, which is what the collocated branch had to do and is both coarser and
	// a different number from the one continuity actually used.
	float jump = smoothstep(0.90, 1.30, Fr)
			* (0.30 + 0.70 * smoothstep(0.5, 3.0, max(-divq, 0.0)));
	// A crest is a surface standing above its CONNECTED neighbours - connected, because a wall is
	// not a crest and averaging one in would read every shoreline as breaking.
	float wsum = 0.0;
	float wcnt = 0.0;
	for (int i = 0; i < 4; i++) {
		if (hf_link(W, i) > 0.0) {
			wsum += surf_at(W + OFF[i]);
			wcnt += 1.0;
		}
	}
	float w_new = b + h_new;
	float wbar = wcnt > 0.5 ? wsum / wcnt : w_new;
	float crest = smoothstep(0.35, 0.60, (w_new - wbar) / max(h_new, h_min));
	foam += (jump * foam_jump + crest * foam_crest) * smoothstep(0.0, h_wet, h_new) * dt;
	foam -= foam * clamp(foam_decay * dt, 0.0, 1.0);

	// ---- the window edge.
	vec2 src = uv + scroll_uv;
	float newly = (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) ? 1.0 : 0.0;
	if (edge_mode == 2 || edge_mode == 3) {
		// THE CHANNEL'S OUTFLOW SPONGE. A wake has to leave, and a closed box will not let it: it
		// reflects, the reflection reaches the body that shed it, and what comes back is a standing
		// wave that looks like a vortex street and has a frequency set by the domain length rather
		// than by the body. That is the single most likely way to "reproduce the paper figure" and
		// be wrong.
		//
		// A sponge, not a characteristic condition. Sommerfeld radiation needs one wave speed and
		// there are two here (the gravity wave sqrt(gh) and the advected vorticity, which travels
		// at about 0.8 U) - a condition tuned to one reflects the other. A layer that relaxes the
		// state toward the undisturbed inflow absorbs both, at the cost of some domain. It ramps in
		// as the CUBE of the depth into the layer, because a sponge with a hard edge is itself an
		// impedance step and reflects off its own start.
		float into = (uv.x - (1.0 - sponge_uv)) / max(sponge_uv, 1e-4);
		if (into > 0.0) {
			float k = into * into * into;
			h_new = mix(h_new, h0, k);
			u_new = mix(u_new, inflow_u, k);
			v_new = mix(v_new, 0.0, k);
			foam = mix(foam, 0.0, k);
		}
		// The inflow END is held at the undisturbed state over a thin band, so the body cannot
		// change the flow that is arriving at it.
		// The inflow END is held at the undisturbed state over a thin band, so the body cannot
		// change the flow that is arriving at it. NOT under the ocean mode: there the whole point
		// is that waves LEAVE the maker and return to it, and clamping the first band would absorb
		// every reflection and hide whatever the beach did with them.
		float inb = edge_mode == 3 ? -1.0 : (0.02 - uv.x) / 0.02;
		if (inb > 0.0) {
			float k2 = clamp(inb, 0.0, 1.0);
			h_new = mix(h_new, h0, k2);
			u_new = mix(u_new, inflow_u, k2);
			v_new = mix(v_new, 0.0, k2);
		}
	}
	if (edge_mode == 0) {
		vec2 bnd = min(uv, vec2(1.0) - uv);
		float rim = smoothstep(0.0, 0.06, min(bnd.x, bnd.y));
		h_new = mix(h0, h_new, rim);
		u_new *= rim;
		v_new *= rim;
		foam *= rim;
	}
	h_new = mix(h_new, h0, newly);
	u_new = mix(u_new, 0.0, newly);
	v_new = mix(v_new, 0.0, newly);
	foam = mix(foam, 0.0, newly);

	return vec4(round_store(max(h_new, 0.0), h, uv), u_new, v_new, clamp(foam, 0.0, 1.0));
}




void fragment() {
	vec4 f = texture(field, UV);
	// The spring flag rides the Y channel, which is read NEAREST — a flag inside a
	// filter_linear channel is a flag that gets interpolated, and an interpolated flag is a
	// wrong answer in a band around every source.
	float Yraw = texture(field_n, UV).a;
	float spring = Yraw > spring_mark * 0.5 ? 1.0 : 0.0;
	float Y = Yraw - spring * spring_mark;
	if (diag) {
		COLOR = vec4(Y, f.b, f.r, 1.0);
	} else if (reset) {
		// The reset seeds the state the encoding actually uses: a depth (0 empty, rest depth full),
		// or the deviation from rest (a full-amplitude -H0 for empty, which is the very
		// cost the depth encoding exists to remove).
		// BOTH encodings seed from the same linear rest-depth channel, and both build their
		// surface from linearly-sampled terrain, so the reconstruction cancels exactly. Mixing
		// filters is what puts a sawtooth in the surface - see step_depth's note on h0.
		COLOR = depth_mode
				// BOTH by integer index, not through the samplers: the seed and the step must
				// reconstruct h from the same bed AND the same Y, or a lake starts life with
				// holes in it. See fld().
				? vec4(reset_empty ? 0.0 : max(seed_rest(ivec2(floor(UV * float(res)))), 0.0),
						0.0, 0.0, 0.0)
				: vec4(reset_empty ? -max(f.b, 0.0) : 0.0, 0.0, 0.0, 0.0);
		// A CHANNEL IS SEEDED MOVING. Starting it from rest and letting the inflow face fill the
		// domain does not work and is not a boundary problem: the inflow drives ONE column of
		// faces, so the current has to propagate 64 m by momentum transport alone, which at 1.2 m/s
		// is 53 seconds before the far end knows anything is happening. Measured with a settle of
		// 20 s: transverse velocity at the probe point was 0.00000, exactly, with a cylinder in the
		// flow - and every assertion downstream then reported the absence of a wake in water that
		// was not moving.
		//
		// The right initial condition for a channel is the undisturbed channel: a uniform stream
		// everywhere, which the body then disturbs. That is also what the outflow sponge relaxes
		// toward, so the seed and the boundary agree from step one.
		if (edge_mode == 2) {
			COLOR.g = inflow_u;
			COLOR.b = 0.0;
		}
		// ---- the bench seeds, laid over the still-water state above rather than replacing it, so
		// a vortex sits in a real basin over a real bed and a checkerboard perturbs a real lake.
		if (seed_kind == 1) {
			vec2 d = (UV - seed_p.xy) * window_m;             // metres from the core
			float r0 = max(seed_p.z * window_m, 1e-4);
			float env = exp(-dot(d, d) / (r0 * r0));
			// SOLID BODY inside the core, falling off outside: u = w x r, so |u| grows linearly
			// from the centre and the vorticity is uniform where the envelope is. A point vortex
			// (1/r) would put its whole circulation in one texel and measure the grid instead.
			COLOR.gb = seed_p.w * vec2(-d.y, d.x) / r0 * env;
		} else if (seed_kind == 2) {
			ivec2 P = ivec2(floor(UV * float(res)));
			float sgn = ((P.x + P.y) % 2 == 0) ? 1.0 : -1.0;
			COLOR.r = max(COLOR.r + sgn * seed_p.w, 0.0);
		}
	} else if (depth_mode) {
		COLOR = staggered ? step_staggered(UV) : step_depth(UV);
	} else if (Y <= dry_y + 1.0) {
		COLOR = vec4(0.0);          // never water here: still, still, dry
	} else {
		float H0 = max(f.b, 0.0);
		vec2 u0 = f.rg;

		ivec2 P = ivec2(floor((UV + scroll_uv) * float(res)));
		vec4 s = st(P);
		float e = s.r;
		vec2 ud = s.gb;
		float foam = s.a;
		float H = max(H0 + e, 0.0);

		// ---- the four faces. A WALL (dry) and a STEP (different tier) both CLOSE the face:
		// no pressure coupling and no flux across either. Mass crosses a step only through
		// the weir term below.
		float en[4];
		float Hn[4];
		float open[4];
		float dYn[4];
		float eraw[4];
		float wet[4];
		for (int i = 0; i < 4; i++) {
			vec2 nuv = UV + vec2(OFF[i]) / float(res);
			vec4 fn = texture(field, nuv);
			float Ynr = texture(field_n, nuv).a;
			float Yn = Ynr - (Ynr > spring_mark * 0.5 ? spring_mark : 0.0);
			vec4 sn = st(P + OFF[i]);
			float w = Yn > dry_y + 1.0 ? 1.0 : 0.0;
			float dY = Yn - Y;
			float stp = (w > 0.5 && abs(dY) > tier_eps) ? 1.0 : 0.0;
			wet[i] = w;
			dYn[i] = dY;
			eraw[i] = sn.r;
			open[i] = (w > 0.5 && stp < 0.5) ? 1.0 : 0.0;
			// A closed face MIRRORS self, so the gradient and the flux fall to zero with no
			// branch — a reflecting boundary, free.
			en[i] = mix(e, sn.r, open[i]);
			Hn[i] = mix(H, max(fn.b + sn.r, 0.0), open[i]);
		}

		// ---- gravity, on the deviation surface ----
		vec2 grad_e = vec2(en[0] - en[1], en[2] - en[3]) / (2.0 * dx);
		vec2 acc = -gravity * grad_e;

		// ---- advection: ONE filtered fetch, and it carries foam in .a for free ----
		vec2 utot = u0 + ud;
		vec2 back = (UV + scroll_uv) - utot * (dt / max(window_m, 0.001));
		vec4 sb = texture(prev, back);
		vec2 u0b = texture(field, back - scroll_uv).rg;
		// u_tot(back) - u0(here) carries the (u.grad)u0 term for free.
		ud = mix(ud, sb.gb + (u0b - u0), advect_gain);
		foam = sb.a;                // a passive scalar has no phase to lose: always advected

		// ---- momentum ----
		ud += acc * dt;
		ud *= exp(-drag * dt);
		float Hs = max(H, h_min);
		// Manning, semi-implicit: unconditionally stable and it can never reverse u. The
		// coefficient is 0.02 at 0.55 m (invisible) and 4.1 at 0.01 m (decisive) — friction
		// that exists only in the shallows, which is exactly where u = q/H wants to blow up.
		ud /= (1.0 + dt * gravity * manning * manning * length(utot) / pow(Hs, 1.3333333));
		float wet_ramp = smoothstep(h_dry, h_wet, H);
		ud *= wet_ramp;
		// CLAMP THE DEVIATION, never the total. Clamping |u0 + u'| looks more correct and is
		// a water pump: the baked current peaks at 3.89 m/s against u_max 3.0, so in every
		// fast cell the clamp solves for a NON-ZERO u' pointing against the flow — out of a
		// perfectly still field, every step, forever. Measured: a quiescent pond with no
		// impulses and no weirs held eta -0.15..+0.23 and never settled. u0's magnitude does
		// not threaten stability anyway (it is transport, not mass), which is the whole
		// reason this solver integrates the deviation.
		float sp = length(ud);
		if (sp > u_max) {
			ud *= u_max / sp;
		}

		// ---- continuity, forward-backward ----
		float divq = 0.0;
		float lapH = 0.0;
		for (int i = 0; i < 4; i++) {
			float sgn = (i == 0 || i == 2) ? 1.0 : -1.0;
			vec2 un = mix(ud, st(P + OFF[i]).gb, open[i]);
			float axu = (i < 2) ? 0.5 * (ud.x + un.x) : 0.5 * (ud.y + un.y);
			float uf = axu * sgn;
			// UPWIND depth in the transport flux: a cell can never export water it does not
			// have. SYMMETRIC depth in the Laplacian: that is the wave operator.
			float Hup = (uf > 0.0) ? H : Hn[i];
			float Hav = 0.5 * (H + Hn[i]);
			divq += open[i] * Hup * uf / dx;
			lapH += open[i] * Hav * (en[i] - e) / (dx * dx);
		}
		float e_new = e - dt * divq + gravity * dt * dt * lapH;

		// ---- weirs: how the terraced staircase is crossed ----
		// The crest is the REST SURFACE, not the tier top, so the head is max(eta, 0) and a
		// pond at rest is an exact fixed point rather than something that quietly drains.
		// The discharge is a pure function of the HIGHER cell, so both fragments compute
		// bit-identical numbers and the donor's loss is the receiver's gain with no second
		// pass. Submergence never applies: it would need 1.2 m of tailwater and eta never
		// exceeds ~0.3, which deletes a whole class of complexity.
		if (weirs_on) {
			for (int i = 0; i < 4; i++) {
				if (wet[i] < 0.5 || abs(dYn[i]) <= tier_eps) {
					continue;
				}
				float head = (dYn[i] > 0.0) ? max(eraw[i], 0.0) : max(e, 0.0);
				// Per-face quarter limiter: four faces can never take more than the head,
				// and it is reproducible from (head, dx, dt) alone.
				float q = min(weir_cd * sqrt(gravity) * head * sqrt(head),
						head * dx / (4.0 * dt));
				float dv = q * dt / dx;
				if (dYn[i] > 0.0) {
					e_new += dv;
					ud += vec2(-float(OFF[i].x), -float(OFF[i].y)) * (q / Hs) * 0.5;
					foam += smoothstep(0.0, 0.05, q) * foam_plunge * dt;
				} else {
					e_new -= dv;
				}
			}
		}

		// ---- impulses: a PURE DISPLACEMENT poke; u is untouched ----
		// With u' stored explicitly this is unambiguous. The old leapfrog stored two time
		// levels and had to poke both; poking one was read as a VELOCITY impulse re-applied
		// every step — the "black pit" bug. That whole class of error is gone.
		float poke = 0.0;
		for (int i = 0; i < impulse_count; i++) {
			vec2 d = (UV - impulses[i].xy) / max(impulses[i].z, 1e-5);
			// A DISPLACEMENT, NOT A DELETION. The bare Gaussian subtracts water and never puts it back,
			// so every splash and every wake ring the raft leaves is water gone from the world - a boat
			// drained the lake it sailed on. Subtracting a second Gaussian of TWICE the radius and a
			// QUARTER the amplitude makes the pair exactly volume-neutral (a 2-D Gaussian's integral
			// goes as amplitude times radius squared), and it is the better shape anyway: a dip inside
			// a raised rim is what displacing water actually looks like.
			float r2 = dot(d, d);
			poke += impulses[i].w * (exp(-4.0 * r2) - 0.25 * exp(-r2));
		}
		e_new -= min(poke, poke_frac * max(H, 0.0));  // cannot displace water that is not there

		// SOURCE AND SINK, the pair that makes a river a river rather than a standing pond
		// with a waterfall painted on it. Without them this solver has an exact fixed point
		// at rest, which is the correct answer to the wrong question: if there is a fall,
		// water is arriving from somewhere and leaving somewhere.
		//
		// The source is a painted spring (the catchment this map does not model). The sink is
		// eta_keep, which was already here: a universal relaxation toward the rest surface,
		// physically seepage and evaporation. Between them the chain self-balances with no
		// global bookkeeping — head rises at the spring until the weir passes what arrives,
		// each reach passes it on, and the terminal pool rises until seepage matches. Nothing
		// counts anything; every term is local, which is what keeps it inside the seam law.
		e_new += spring * spring_rate * dt;
		e_new *= eta_keep;
		// POSITIVITY, and nothing more. This must never be `h_min - H0`: that expression is
		// POSITIVE wherever H0 < h_min, i.e. all along the beach fringe, so it force-lifts eta
		// by a centimetre every step, the resulting shoreline gradient drives water inward,
		// and the whole lake settles into a permanent self-sustaining slosh. Measured: a
		// quiescent pond with no impulses and no weirs held eta -0.15..+0.23 forever. The
		// constraint that is actually wanted is just H >= 0.
		// POSITIVITY, and then some. H >= 0 is the true constraint, but leaving it there lets a
		// strongly-fed reach draw individual cells down to a few millimetres, and a nearly-dry
		// cell is a trap: the wet ramp zeroes its velocity, and velocity is what the flux term
		// needs to refill it. The result was a self-sustaining near-empty scar that appeared at
		// a source rate of 0.006 and looked identical at 0.02 — a threshold, not a response,
		// which is how you tell a numerical trap from an equilibrium. Holding the surface above
		// a fraction of the rest depth keeps every cell wet enough to recover.
		e_new = max(e_new, -H0 * draw_max);

		// ---- foam, from the FROUDE number ----
		// Whitewater belongs where the flow is supercritical, and Fr = 1 at H = 0.55 needs
		// 2.32 m/s — which is where the previous hand-tuned foam_speed of 2.6 had landed by
		// eye. The Froude form is that same threshold made DEPTH-AWARE, so a 15 cm riffle at
		// 1.2 m/s foams too, and in a terraced world that is most of the moving water.
		// FROUDE, floored well above h_min. Hs bottoms out at 1 cm, where sqrt(g*H) is only
		// 0.31 m/s, so a perfectly ordinary 0.5 m/s current reads as Fr 1.6 and every shallow
		// texel in the world turns white — measured, foam mean was 1.000 everywhere. Five
		// centimetres is the shallowest water that can meaningfully be said to have a Froude
		// number at all; below that the wet ramp is taking the velocity to zero anyway.
		float Fr = length(u0 + ud) * inversesqrt(gravity * max(H, 0.05));
		vec2 nx1 = mix(ud, st(P + OFF[0]).gb, open[0]);
		vec2 nx0 = mix(ud, st(P + OFF[1]).gb, open[1]);
		vec2 nz1 = mix(ud, st(P + OFF[2]).gb, open[2]);
		vec2 nz0 = mix(ud, st(P + OFF[3]).gb, open[3]);
		float divu = ((nx1.x - nx0.x) + (nz1.y - nz0.y)) / (2.0 * dx);
		float conv = max(-divu, 0.0);
		float jump = smoothstep(0.90, 1.30, Fr) * (0.30 + 0.70 * smoothstep(0.5, 3.0, conv));
		float crest = smoothstep(0.35, 0.60, e / Hs);
		foam += (jump * foam_jump + crest * foam_crest) * wet_ramp * dt;
		foam -= foam * clamp(foam_decay * dt, 0.0, 1.0);

		// The window edge is a horizon, not a wall: fade to nothing so the handover to the
		// static baked field outside it is invisible.
		vec2 b = min(UV, vec2(1.0) - UV);
		float rim = smoothstep(0.0, 0.06, min(b.x, b.y));
		COLOR = vec4(e_new * rim, ud * rim, clamp(foam, 0.0, 1.0) * rim);
	}
}
