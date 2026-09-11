shader_type canvas_item;
render_mode unshaded;
// THE SOLVER, MADE LEGIBLE. The state texture is RGBA16F carrying (eta, u'x, u'y, foam) and
// looking at it raw — which is what the water lab's F key has always done — shows a dim purple
// haze. Every quantity the solver actually reasons about is a COMBINATION of that texture and
// the terrain field, and none of them is a channel:
//
//   depth   H  = H0 + eta         the thing continuity conserves
//   speed   |u0 + u'|             the thing the CFL condition bounds
//   Froude  |u| / sqrt(g H)       the thing foam is derived from
//   steps   |dY| > tier_eps       the thing the weirs are for
//
// So this shader recomputes them from the same two inputs the sim shader reads, using the same
// constants, and false-colours ONE at a time. It is a viewer, never a solver: nothing here
// feeds back, and if a number looks wrong here it is wrong in the sim too.
//
// SHARED CONSTANTS ARE PASSED IN, not copied. gravity, dry_y, spring_mark and tier_eps all
// arrive as uniforms set from the same GDScript constants that configure the sim material, so
// a view that disagrees with the solver is impossible by construction rather than by care.

uniform sampler2D field : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D field_n : hint_default_black, filter_nearest, repeat_disable;
// THE BED, on its own texture and read NEAREST for the same reason field_n is: it is the
// channel a solver differences, and a smeared step is a delta-function acceleration.
uniform sampler2D bed : hint_default_black, filter_nearest, repeat_disable;
uniform int mode = 0;
uniform float gravity = 9.81;
uniform float dry_y = -1000.0;
uniform float spring_mark = 10000.0;
uniform float tier_eps = 0.5;
uniform float res = 512.0;
uniform float field_res = 64.0;
// Metres per state texel. Passed in for the same reason gravity and tier_eps are: the vorticity
// view divides by it, and a viewer that guesses its own dx reports curl in units of nothing.
uniform float dx = 0.125;
// Full-scale of the colour ramp, in the unit of whatever `mode` is showing. Exposed because a
// 1 cm ripple and a 40 cm drawdown are the same picture at the wrong scale.
uniform float ramp = 0.30;
uniform vec2 pick_uv = vec2(-1.0);
uniform bool show_grid = false;
// Which encoding the state texture is in. The two mean OPPOSITE things by the same channel: R is a
// deviation from a flat rest surface in one and an absolute water depth in the other, so a viewer
// that guesses draws a full basin over an empty one and calls it depth.
uniform bool depth_mode = false;
// WHERE the velocity lives, which is a different question from what R means - see the sim shader.
// Staggered, G is the LEFT face and B is the BOTTOM face, so "the velocity at this cell" is the
// mean of the two faces either side. Drawing a face value as though it were a cell value shifts
// every speed and Froude reading half a texel and quietly halves a shear layer.
uniform bool staggered = false;

// The cell-centred velocity at a texel, in whichever layout is live.
//
// The state sampler is PASSED IN rather than read as TEXTURE: in a canvas_item shader TEXTURE is a
// built-in of fragment(), not a global, so a helper cannot see it.
vec2 vel_at(sampler2D tex, vec2 uv, float t) {
	vec4 c = texture(tex, uv);
	if (!staggered) {
		return c.gb;
	}
	return vec2(0.5 * (c.g + texture(tex, uv + vec2(t, 0.0)).g),
			0.5 * (c.b + texture(tex, uv + vec2(0.0, t)).b));
}

// Blue-grey-red, symmetric, with EXACTLY mid-grey at zero. A diverging ramp is the only honest
// choice for a signed quantity: on a sequential ramp "no displacement" is a colour somewhere in
// the middle that the eye cannot find, and the whole point of the quiescence tests is to see at
// a glance whether the field is at rest.
vec3 diverging(float v) {
	float t = clamp(v, -1.0, 1.0);
	vec3 lo = vec3(0.20, 0.42, 0.85);
	vec3 hi = vec3(0.92, 0.35, 0.24);
	vec3 mid = vec3(0.46, 0.46, 0.48);
	return t < 0.0 ? mix(mid, lo, -t) : mix(mid, hi, t);
}

// Black -> colour, for a quantity that has a floor at zero.
vec3 ramp_to(float v, vec3 c) {
	return c * clamp(v, 0.0, 1.0);
}

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	vec4 f = texture(field, UV);
	float Yraw = texture(field_n, UV).a;
	float spring = Yraw > spring_mark * 0.5 ? 1.0 : 0.0;
	float Y = Yraw - spring * spring_mark;
	float wet_region = Y > dry_y + 1.0 ? 1.0 : 0.0;
	float H0 = max(f.b, 0.0);
	vec2 u0 = f.rg;
	vec2 ud = vel_at(TEXTURE, UV, 1.0 / res);
	// DEPTH MODE stores h outright; the deviation is then h - h0 rather than the channel itself.
	float H = max(depth_mode ? s.r : H0 + s.r, 0.0);
	float e = depth_mode ? s.r - H0 : s.r;

	vec3 col;
	if (mode == 0) {
		col = diverging(e / max(ramp, 1e-4));
	} else if (mode == 1) {
		// DEPTH, and the one that shows a basin filling. Dry cells inside the basin read
		// black, which is what "the bed is exposed" should look like.
		col = ramp_to(H / max(ramp, 1e-4), vec3(0.35, 0.80, 0.95));
	} else if (mode == 2) {
		col = ramp_to(length(u0 + ud) / max(ramp, 1e-4), vec3(0.98, 0.84, 0.30));
	} else if (mode == 3) {
		col = ramp_to(s.a, vec3(1.0));
	} else if (mode == 4) {
		// FROUDE, with a hard line at 1. Supercritical is the region the whole foam model is
		// built on, and a smooth ramp hides exactly the boundary you came to look at.
		float Fr = length(u0 + ud) * inversesqrt(gravity * max(H, 0.05));
		col = Fr < 1.0 ? mix(vec3(0.06, 0.16, 0.30), vec3(0.30, 0.62, 0.90), Fr)
				: mix(vec3(1.0, 0.85, 0.30), vec3(0.95, 0.20, 0.15),
						clamp((Fr - 1.0) / 2.0, 0.0, 1.0));
	} else if (mode == 5) {
		// THE TERRAIN INPUT. Rest depth as blue, the baked current as a red/green vector, and
		// the springs as pure green — the same picture the field bake writes.
		col = vec3(0.5 + u0.x * 0.15, 0.5 + u0.y * 0.15, 0.0);
		col.b = clamp(H0 / 1.5, 0.0, 1.0);
		col = mix(col, vec3(0.2, 1.0, 0.3), spring);
	} else if (mode == 7) {
		// THE BED itself, which is the whole point of the depth rewrite: the floor the water sits
		// on, present everywhere including ground that was never painted as water.
		col = diverging(texture(bed, UV).r / max(ramp, 1e-4));
	} else if (mode == 9) {
		// VORTICITY, curl(u) about the vertical, in 1/s. There is no other way to answer "does the
		// solver hold an eddy" - speed shows a swirl and a straight current identically, and a
		// scalar circulation says a number without saying where it went.
		//
		// It should be EMPTY except where something is spinning, and on this solver it is empty
		// almost everywhere by construction: with no advective momentum flux the update is the
		// curl of a gradient, which is identically zero, so vorticity is only ever destroyed.
		// That is the point of having the view - the emptiness is the finding.
		float t = 1.0 / res;
		float curl;
		if (staggered) {
			// THE C-GRID'S NATURAL VORTICITY, at the CORNER (i+1/2, j+1/2), as a compact difference
			// of the four face values that surround it:
			//     w = (v[i+1,j+1/2] - v[i,j+1/2] - u[i+1/2,j+1] + u[i+1/2,j]) / dx
			//
			// The centred 2*dx form below is wrong twice over on face data. It is half a cell out
			// of place, because it treats a face value as though it sat at the cell centre. And its
			// symbol vanishes at theta = pi, so it is blind to exactly the grid-scale structure a
			// vorticity view is looked at to find - it would smooth the cores AND hide the noise,
			// which is the worst pair of errors a diagnostic can have.
			float vr = texture(TEXTURE, UV + vec2(t, t)).b;
			float vl = texture(TEXTURE, UV + vec2(0.0, t)).b;
			float ut = texture(TEXTURE, UV + vec2(t, t)).g;
			float ub = texture(TEXTURE, UV + vec2(t, 0.0)).g;
			curl = ((vr - vl) - (ut - ub)) / max(dx, 1e-4);
		} else {
			vec2 ur = vel_at(TEXTURE, UV + vec2(t, 0.0), t) + texture(field, UV + vec2(t, 0.0)).rg;
			vec2 ul = vel_at(TEXTURE, UV - vec2(t, 0.0), t) + texture(field, UV - vec2(t, 0.0)).rg;
			vec2 uu = vel_at(TEXTURE, UV + vec2(0.0, t), t) + texture(field, UV + vec2(0.0, t)).rg;
			vec2 ud2 = vel_at(TEXTURE, UV - vec2(0.0, t), t) + texture(field, UV - vec2(0.0, t)).rg;
			curl = ((ur.y - ul.y) - (uu.x - ud2.x)) / (2.0 * max(dx, 1e-4));
		}
		col = diverging(curl / max(ramp, 1e-4));
	} else if (mode == 8) {
		// THE AGREEMENT CHECK, an assertion drawn rather than asserted: the rest depth H0 must be
		// exactly what the bed and the rest surface say it is. NOT `b + H0 - Y`, which is false
		// all along the WET BEACH, where the bed stands proud of its own surface and the column
		// clamps to zero -- the naive form lights up precisely where the shore is and reads as a
		// bug. Mid-grey is agreement; any colour means two consumers of the same arithmetic have
		// drifted apart.
		float err = H0 - max(Y - texture(bed, UV).r, 0.0);
		col = wet_region > 0.5 ? diverging(err / max(ramp, 1e-4))
				: vec3(0.11, 0.10, 0.09);
	} else {
		// WET / DRY and the STEPS. This is the weir's own view of the world: which faces are
		// open, and where the staircase is. A weir that misfires is nearly always a step the
		// solver does not see, and that is invisible in every other mode.
		col = wet_region > 0.5 ? vec3(0.10, 0.22, 0.38) : vec3(0.10, 0.09, 0.08);
		col = mix(col, vec3(0.16, 0.42, 0.62), clamp(H / 0.6, 0.0, 1.0) * wet_region);
		float t = 1.0 / res;
		for (int i = 0; i < 4; i++) {
			vec2 o = i < 2 ? vec2(i == 0 ? t : -t, 0.0) : vec2(0.0, i == 2 ? t : -t);
			float Ynr = texture(field_n, UV + o).a;
			float Yn = Ynr - (Ynr > spring_mark * 0.5 ? spring_mark : 0.0);
			if (Yn > dry_y + 1.0 && wet_region > 0.5 && abs(Yn - Y) > tier_eps) {
				col = vec3(0.95, 0.55, 0.15);
			}
		}
		col = mix(col, vec3(0.2, 1.0, 0.3), spring * 0.7);
	}

	// Everything outside a water region is bed, in every mode — otherwise a solver that is
	// quietly writing into dry cells looks identical to one that is not.
	if (mode != 5 && mode != 6) {
		col = mix(vec3(0.11, 0.10, 0.09), col, wet_region);
	}

	// The terrain lattice the bed and the rest surface are baked on - half a metre at the shipped
	// FIELD_RES, two field texels to the metre. When a step reads as a ramp instead of a wall,
	// this is the grid it should be square to; it is also the staircase a shoreline is quantised
	// by, which is why it is worth being able to see under the water.
	if (show_grid) {
		vec2 g = fract(UV * field_res);
		if (min(g.x, g.y) < field_res / res) {
			col = mix(col, vec3(0.0), 0.35);
		}
	}

	// The inspected cell, drawn as a box rather than a dot so it survives being one texel of
	// five hundred and twelve.
	if (pick_uv.x >= 0.0) {
		vec2 d = abs(UV - pick_uv) * res;
		float m = max(d.x, d.y);
		if (m > 3.0 && m < 5.0) {
			col = vec3(1.0, 0.95, 0.2);
		}
	}
	COLOR = vec4(col, 1.0);
}
