shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;
// THE SIMULATED SURFACE: one camera-following grid whose every vertex sits at w = b + h, the bed
// plus the water actually standing on it.
//
// WHY THIS IS NOT water_stylized.gdshader WITH A NEW UNIFORM. That shader draws one flat plane per
// painted water region at a FIXED height, decides where water is from a BAKED depth texture, and
// treats the solver as a small displacement on top - tanh-limited to 0.15 m, which renders a 0.55 m
// drawdown as 1.5 pixels. Every one of those is load-bearing for the water it draws, and every one
// is wrong for water that has to fill a basin, climb past its banks and leave a bed dry behind it.
// So this is a second shader rather than a mutilated first one; the far planes keep theirs.
//
// THREE THINGS IT DOES THAT THE FLAT PLANE CANNOT:
//
//   1. THE HEIGHT IS THE SIMULATION'S. VERTEX.y = b + h, no cap and no soft limit. A basin that has
//      filled to two metres is drawn two metres deep.
//   2. WATER IS ONLY WHERE WATER IS. The discard is on the LIVE depth, so dry bed is bare ground
//      rather than a plane pretending. This is the whole of "the lab is a plane, there is no
//      terrain lakebed" - the terrain was always there, under an opaque sheet that never left.
//   3. DEPTH IS VISIBLE. Beer-Lambert absorption: shallow water is nearly clear and you read the
//      ground through it, deep water is not. That is what makes a basin FILLING legible as
//      something other than a colour change, and it is how the reference reads depth too.

// Published by the Ripples autoload: the solver state (R = h, GB = u', A = foam) and the window
// rect it covers (xy = world min corner, z = side in metres, w = master gain / kill switch).
global uniform sampler2D water_swe_tex;
global uniform vec4 water_swe_rect;

// The bed over the same window, in world Y. Set by water_window.gd rather than published as a
// global: only this shader needs it, and a global costs a project setting and a plugin self-heal.
// LINEAR, matching the solver exactly. Whatever filtering the physics uses, the surface must use
// the same one, or the drawn waterline sits a texel from the simulated one.
uniform sampler2D bed_tex : hint_default_black, filter_nearest, repeat_disable;
// The terrain field, for the OTHER encoding. See depth_mode.
uniform sampler2D field_tex : hint_default_black, filter_linear, repeat_disable;
// WHICH ENCODING THE STATE TEXTURE IS IN, and it is not optional. The two mean opposite things by
// the same channel: R is an absolute water DEPTH in one and a DEVIATION from a flat rest surface
// in the other. A surface that assumes depth and is handed a deviation reads "negative depth"
// everywhere an empty basin is empty, discards itself entirely, and draws nothing at all - while
// the solver runs correctly and every probe stays green, because the probes set the flag and a
// person opening the scene does not.
uniform bool depth_mode = true;

// THE SAME NUMBER THE SOLVER USES. If the mesh drops water at a different depth than the physics
// calls dry, the visible edge and the simulated edge disagree by a texel and the shoreline crawls.
uniform float h_dry : hint_range(0.0, 0.05, 0.0005) = 0.002;
// THE BED OFF THE MAP IS A SENTINEL 1000 m WALL (Water.BED_WALL) - the right number for a solver
// that only ever compares it, and a catastrophic one for geometry: those vertices would be flung a
// kilometre into the sky and drag triangles up with them from the last wet cell at the boundary.
// They are discarded in the fragment stage regardless, so this only has to keep them finite.
uniform float bed_clamp = 96.0;
// ABOVE THIS, THE BED IS NOT GROUND, it is Water.BED_WALL - the 1000 m sentinel that says "no map
// here". Tested BEFORE the clamp above, because the clamp is what turns an unmistakable kilometre
// into a plausible 96 m.
uniform float bed_wall_min = 500.0;

// ---- OBSTACLES, THE SAME ARRAYS THE SOLVER READS, and the surface has to read them or it draws
// water through solid objects.
//
// bed_tex is the TERRAIN bed. A solid raises the EFFECTIVE bed inside its footprint, and it does
// that as a shader uniform in the sim - so nothing about it reaches this texture. The surface then
// believed the terrain was still down at its own level inside a cube, found the footprint dry,
// took the "dry vertex sits at its highest wet neighbour's surface" rule, and drew the lake
// straight across the cube at water level - up its vertical faces and out the other side, colouring
// them. The geometry was right; the shader simply did not know the object was there.
//   a = (centre.x, centre.y, half_x, half_y)  window fractions
//   b = (top_y, kind, cos(rot), sin(rot))     kind 0 = cylinder, 1 = box
uniform int obs_count = 0;
uniform vec4 obs_a[8];
uniform vec4 obs_b[8];

// The top of any solid covering a window uv, or very negative if none does. Same test as the sim's
// obstacle_top(), so the drawn waterline and the simulated one cannot disagree about where a solid
// begins.
// THE SAME RAMP THE SOLVER USES. Kept byte-for-byte in step with swe_sim's obstacle_top: a
// renderer that draws a hard disc where the solver simulates a dome puts the waterline a cell from
// where the water is, which is the exact class of bug that produced every border artifact on this
// branch.
float surf_obstacle_top(vec2 c, float terrain_bed) {
	float top = -1.0e9;
	for (int i = 0; i < obs_count; i++) {
		vec2 d = c - obs_a[i].xy;
		bool inside;
		float soft_top = obs_b[i].x;
		if (obs_b[i].y < 0.5) {
			float ro = obs_a[i].z;
			float d2 = dot(d, d);
			inside = d2 <= ro * ro;
			float ri = obs_a[i].w;
			if (inside && ri < ro) {
				float t = clamp((ro - sqrt(d2)) / max(ro - ri, 1.0e-6), 0.0, 1.0);
				t = t * t * (3.0 - 2.0 * t);
				soft_top = mix(terrain_bed, obs_b[i].x, t);
			}
		} else {
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
// How far a vertex with no water and no wet neighbour sinks below its bed, so the triangle that
// crosses the waterline ends up UNDER the terrain instead of standing on it.
uniform float dry_skirt : hint_range(0.0, 2.0, 0.05) = 0.4;

// ---- EVERYTHING BELOW THIS LINE IS APPEARANCE, and nothing above it is.
//
// The split is already real and worth keeping visible: water_window.gd sets exactly seven shader
// parameters and every one of them is solver state (bed_tex, field_tex, depth_mode, obs_*, h_dry).
// Not one of the knobs in these three groups is written by any script in the project - they run on
// the defaults below. That is a missing route in, not a missing separation, and the route must not
// be opened by letting art into _follow(), which runs every frame and carries physics.
//
// Grouped because this shader was the only one in the project with more than a handful of uniforms
// and no groups at all; water_stylized has six blocks, painted_env seven.
group_uniforms Color;
// LIFTED WHEN THIS SHADER STOPPED BEING LIT, and the amount is not a taste change - it is the
// sun that used to be multiplying them. These were authored against diffuse_lambert, so the engine
// scaled them by the directional light before anything reached the screen; unshaded, ALBEDO is the
// final colour and the same numbers came out muddy. Raised to land near where the lit version
// looked, and pushed toward the saturated cyan the reference asks for while they were being moved.
uniform vec4 shallow_color : source_color = vec4(0.62, 0.87, 0.86, 1.0);
uniform vec4 deep_color : source_color = vec4(0.09, 0.36, 0.52, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.99, 1.0);
// METRES OF WATER PER E-FOLD OF OPACITY, and the single highest-value knob in the file. At 0.85 a
// metre of lake is most of the way to opaque; both of the references this is aimed at are legible
// straight to the bed. Small numbers make a puddle look like ink.
uniform float absorb : hint_range(0.05, 4.0, 0.05) = 0.85;
uniform float max_alpha : hint_range(0.0, 1.0, 0.01) = 0.94;
// OPACITY AT THE WATERLINE, where `opt` is zero. This was a hard-coded 0.16 inside the ALPHA
// expression, which made it the one clarity control nobody could reach - and clarity is most of
// what separates a bright lagoon you can read the sand through from a deep still ruin.
uniform float shallow_alpha : hint_range(0.0, 1.0, 0.01) = 0.16;
group_uniforms;

group_uniforms Foam;
// THE WATERLINE, in metres of depth - but gated on the depth GRADIENT, which is the whole point.
// Keyed on depth alone this paints every shallow lake white, and a basin that is FILLING is
// nothing but shallow water: the entire surface came out one flat sheet of foam, with the waves
// and the slope shading buried under it. A shore is not where water is thin, it is where water
// STOPS - so it wants the place depth falls to zero, not the place depth is small.
uniform float shore_foam : hint_range(0.0, 0.4, 0.005) = 0.03;
// Depth change per metre at which the edge is fully drawn. A spreading sheet a few centimetres
// deep has a gradient near zero across its middle and a steep one at its rim.
uniform float shore_edge : hint_range(0.05, 4.0, 0.05) = 1.2;
uniform float live_foam : hint_range(0.0, 2.0, 0.05) = 1.0;
// How far foam carries the albedo toward foam_color, and how much opacity it adds. Both were
// hard-coded (0.85 and 0.30) in the composition below; a lacy shoreline and a solid one differ
// mostly in these two.
uniform float foam_mix : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float foam_alpha : hint_range(0.0, 1.0, 0.01) = 0.30;
group_uniforms;

group_uniforms Shading;
// Relief from the surface slope. Same amendment water_stylized records: no light() call, the
// surface still composes its own colour, and the term vanishes identically on flat water.
uniform float slope_shade : hint_range(0.0, 3.0, 0.05) = 0.9;
// A HYDRAULIC JUMP IS WHITE WATER, and until now it was drawn as a black gash.
//
// A body wading faster than the wave speed makes a bow shock - real physics, not an artifact:
// measured inside a 0.9 m body's footprint, ZERO of 32 cells dry, the surface swinging from 0.53 m
// to 1.18 m inside and to 1.65 m in the ring just outside. That is a metre of water standing up
// across three cells. wave_scale 0.35 puts the celerity in a 1.04 m lake at 1.89 m/s, so a 5 m/s
// jog is Froude 2.6 and a 1.5 m/s walk is 0.8 - and the ring is duly ABSENT at walking pace, which
// is the test that made it a shock rather than a hole.
//
// So it is drawn as what it is. Above `jump_slope` the surface is foaming, which is both the
// prettier picture and the more honest one; below it nothing changes at all, and on flat water the
// term is identically zero.
uniform float jump_slope : hint_range(0.2, 6.0, 0.05) = 2.5;
uniform float jump_foam : hint_range(0.0, 1.0, 0.05) = 1.0;
// Metres a cell stands off its neighbours' plane before it counts as broken water. A 0.28 m wave
// spread over several cells curves by centimetres; the shock's tips stand off by most of a metre.
uniform float jump_curv : hint_range(0.02, 1.0, 0.01) = 0.18;
uniform vec3 look_dir = vec3(-0.40, 0.80, -0.45);
// THE HIGHLIGHT, RE-EARNED HONESTLY after this shader stopped being lit.
//
// It used to write SPECULAR = 0.5 and never write NORMAL at all, so the engine shaded every wave
// with the PlaneMesh's constant up-vector: a flat sheet of highlight that could not see a single
// wave, and that any nearby light blew out to white. A hero light on the player did exactly that.
//
// This is composed straight into ALBEDO from the SAME normal the shade term uses - built from
// v_slope - so it sits on the wave relief instead of on the mesh, and no light in the scene can
// touch it. Same argument water_stylized and glass_stylized make: look_dir is a look vector, not a
// light, and there is no light() function anywhere near water in this project.
//
// Kept modest on purpose: scenes/main.tscn runs glow at hdr_threshold 1.1, so a glint pushed much
// past 1 blooms project-wide.
uniform float glint_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float glint_sharp : hint_range(1.0, 128.0, 1.0) = 24.0;
group_uniforms;

varying vec2 v_suv;
varying float v_h;
varying vec3 v_wpos;
// THE SURFACE SLOPE, CARRIED FROM THE VERTICES so the rasteriser interpolates it.
//
// It used to be differenced in the FRAGMENT stage, and the comment there gave the reason: the mesh
// was coarser than the texture (VERTS_M 0.25 against TEXEL_M 0.2) and therefore faceted. That
// stopped being true when VERTS_M was derived from TEXEL_M to kill the moire - they are now
// exactly equal, one vertex per texel.
//
// And the fragment version had a defect the reason never covered. snap_state() floors to the texel
// centre, so all four neighbour reads return the SAME VALUES for every pixel inside a texel: the
// slope, hence the shading, was constant across each 0.2 m cell. That is the hard-edged square
// checker over the whole surface - not noise in the water, a piecewise-constant normal drawn over
// perfectly smooth water. Interpolating from the vertices makes the normal continuous, and costs
// LESS: eight texture reads move off every pixel and onto every vertex, of which there are far
// fewer.
varying vec2 v_slope;
varying float v_dhdx;
// SURFACE CURVATURE, and it is here because a slope cannot see a spike.
//
// v_slope is a CENTRAL difference, so at the apex of a one-cell spike the two neighbours are
// symmetric about it and the slope comes out near ZERO - the steepest thing in the picture reads as
// flat. That is why foaming on slope alone whitened the flanks of the shock and left its tips dark:
// the tips are exactly where the central difference is blind. The Laplacian is maximal there
// instead, which is the complementary measurement.
varying float v_curv;

// The window UV for a world XZ, and whether it is inside at all.
vec2 win_uv(vec2 wxz) {
	return (wxz - water_swe_rect.xy) / max(water_swe_rect.z, 0.001);
}

// THE STATE TEXTURE, READ NEAREST - by snapping to the texel centre, because the sampler itself
// cannot be told. water_swe_tex is a GLOBAL uniform published by the Ripples autoload, so it
// carries the default filter_linear and no hint of this shader's can change that.
//
// THIS IS THE 96 m SLAB. The bed is filter_nearest and the state was filter_linear on a finer
// grid, so a vertex standing on the off-map sentinel bed could pick up a bilinear SMEAR of h from
// a wet texel up to a texel away - h > h_dry, the WET branch, VERTEX.y = 96 + h - and a wall of
// water the height of the bed clamp stood at the map edge. The discard is no defence: v_h
// interpolates from a genuinely wet vertex, so the overwhelming majority of the triangle survives
// it. Read the same texel the solver wrote and the wall reads its own zero.
vec2 snap_state(vec2 c) {
	float n = max(float(textureSize(water_swe_tex, 0).x), 1.0);
	return (floor(c * n) + 0.5) / n;
}

// THE FIELD, READ NEAREST, and for a sharper reason than the state texture's.
//
// field_tex is filter_linear and its A channel is not a quantity - it is a rest water LEVEL with
// two sentinels riding it: DRY_Y = -1000 where there is no water and SPRING_MARK = +10000 added
// where a spring is. Interpolating that is meaningless everywhere and catastrophic at a shoreline,
// where the hardware would happily blend 2.05 m of lake with -1000 and hand back a rest level
// several hundred metres underground - which is a test for "is this solid standing proud" that
// answers yes for every solid within one field texel of any shore.
vec2 snap_field(vec2 c) {
	float n = max(float(textureSize(field_tex, 0).x), 1.0);
	return (floor(c * n) + 0.5) / n;
}

// Depth at a window UV, in whichever encoding is live, and ZERO over the sentinel bed. Also
// reports the bed it stood on, clamped to something geometry can survive, and whether that bed
// was the sentinel - which the caller needs, because after the clamp it is unrecoverable.
// THE BED, RECONSTRUCTED THE WAY THE SOLVER RECONSTRUCTS IT - bilinear over the terrain texels,
// with the off-map sentinel never interpolated.
//
// THIS IS A DISAGREEMENT, NOT A REFINEMENT. swe_sim.gdshader's bed_terrain() has read the bed
// bilinearly since Stage 1, because a sampled linear ramp interpolates back to itself exactly and a
// NEAREST bed is a staircase - 1.29 cm risers on a 3 % beach, which is what used to stop a runup
// tongue at the foot of a step. The surface shader kept reading it nearest. So the geometry was
// built on a staircase while the water standing on it was computed on a ramp, and the difference is
// exactly HALF THE BED SLOPE, per texel, everywhere the bed is not flat: 0.9 cm on a 1.7 % bed,
// 1.5 cm on a 3 %. That is a hard step at every 0.5 m field texel, which is the blocky terracing on
// any sloped bed - and it is identically zero on a flat one, which is why the bench's pan never
// showed it and the wilds lake always did.
//
// FIELD_M is 0.5 m against the state's 0.2 m, so this is a bed FOUR TIMES coarser than the water on
// it; getting the interpolation to match matters more here than it does in the solver.
float bed_smooth_at(vec2 c) {
	float fres = max(float(textureSize(bed_tex, 0).x), 1.0);
	vec2 t = c * fres - 0.5;
	vec2 i0 = floor(t);
	vec2 fr = t - i0;
	vec2 inv = vec2(1.0 / fres);
	vec2 u00 = (i0 + 0.5) * inv;
	float b00 = textureLod(bed_tex, clamp(u00, vec2(0.0), vec2(1.0)), 0.0).r;
	float b10 = textureLod(bed_tex, clamp(u00 + vec2(inv.x, 0.0), vec2(0.0), vec2(1.0)), 0.0).r;
	float b01 = textureLod(bed_tex, clamp(u00 + vec2(0.0, inv.y), vec2(0.0), vec2(1.0)), 0.0).r;
	float b11 = textureLod(bed_tex, clamp(u00 + inv, vec2(0.0), vec2(1.0)), 0.0).r;
	// THE SENTINEL IS NEVER INTERPOLATED. Blending 1000 m of off-map rock with half a metre of lake
	// gives a bed halfway up a mountain and a ring of geometry round the whole map edge.
	if (max(max(b00, b10), max(b01, b11)) > bed_wall_min) {
		return textureLod(bed_tex, c, 0.0).r;
	}
	return mix(mix(b00, b10, fr.x), mix(b01, b11, fr.x), fr.y);
}

vec4 sample_column(vec2 c) {
	float b_raw = bed_smooth_at(c);
	// A SOLID RAISES THE BED - exactly what it does in the solver, where bed_at() is
	// max(terrain, obstacle_top) and nothing else in the scheme knows solids exist.
	//
	// IT IS NOT AUTOMATICALLY A WALL, and reporting it as one unconditionally was wrong for
	// anything that does not break the surface. A raft's hull draws 0.12 m of a 1.04 m column, so
	// there are 0.92 m of water ON TOP of it - and the surface drew a raft-shaped HOLE with bare
	// bed at the bottom of it instead. Whether a solid is a wall is a question about whether water
	// stands on it; the block below settles that, and NOT from the depth, which cannot say.
	float ob = surf_obstacle_top(c, b_raw);
	float solid = step(-1.0e8, ob);
	b_raw = mix(b_raw, max(b_raw, ob), solid);
	float wall = step(bed_wall_min, b_raw);
	float r = textureLod(water_swe_tex, snap_state(c), 0.0).r;
	// In the deviation encoding the depth is the region's rest depth plus the deviation, and the
	// bed to stand it on is that rest surface minus that rest depth.
	float h0 = max(textureLod(field_tex, c, 0.0).b, 0.0);
	float h = max(depth_mode ? r : max(h0 + r, 0.0), 0.0) * (1.0 - wall);
	// IS THIS SOLID STANDING PROUD OF THE WATER, OR UNDER IT? Everything about how it should be
	// drawn turns on that, and the state texture will not say. When a solid rises above the water
	// the LISFLOOD face depth closes every face around it, so the water that was there is TRAPPED
	// at whatever depth it had rather than drained. Read at face value, b + h over a tower standing
	// 0.35 m proud of a 1.04 m lake is a surface at 1.39 m: a metre of water balanced on top of the
	// tower, drawn as a vertical pane climbing out of the lake.
	//
	// ASKED OF THE FIELD, NOT OF THE NEIGHBOURS. The first attempt compared the solid's top to the
	// highest open water beside it, which is correct and which fails in the one place it must not:
	// the INTERIOR of a solid has no open neighbour at all. A raft's hull is 5 by 11 texels, so
	// every texel in the middle of it answered "no open water, therefore proud", and the boat sailed
	// in a hull-shaped hole with curtains at its corners - a worse version of the artifact the test
	// was written to remove.
	//
	// field_tex.a is the REST WATER LEVEL this place belongs to, straight off the terrain seam
	// (ripple_field.gd:652), with DRY_Y = -1000 where there is none and SPRING_MARK = 10000 added
	// where a spring rides the same channel. It is a per-texel answer that owes nothing to
	// neighbours, so it is right in the middle of a hull and at the edge of a tower alike.
	float rest = textureLod(field_tex, snap_field(c), 0.0).a;
	rest -= step(5000.0, rest) * 10000.0;
	float has_rest = step(-500.0, rest);
	float proud = solid * has_rest * step(rest + h_dry, ob);
	h *= 1.0 - proud;
	// A solid standing proud is a wall for the same reason the map edge is: it is what stops the
	// "highest wet neighbour" rule reaching over the top of a cube and drawing the lake across it.
	wall = max(wall, proud);
	return vec4(clamp(b_raw, -bed_clamp, bed_clamp), h, wall, solid);
}

// The neighbour's water SURFACE, with the sentinel bed MIRRORED to self. Every consumer here
// differences this against its own surface, and 96 m minus half a metre of lake, divided by a
// 0.2 m texel, is a slope of five hundred - which is a normal pointing sideways and a black ring
// of shading round the whole map edge. Mirroring makes the map edge read as flat, which is the
// same thing the solver does with a closed face.
// IS THIS NEIGHBOUR SOMETHING WATER CANNOT CROSS: the off-map sentinel, or a solid whose top
// stands above our own surface. A SUBMERGED solid is not blocked - there is water over it, and
// pretending otherwise is what drew a hole in the lake under a raft.
float nb_blocked(vec4 n, float w_self) {
	return max(n.z, n.w * step(w_self + h_dry, n.x));
}

// The neighbour's water SURFACE, with anything blocked MIRRORED to self. Every consumer differences
// this against its own surface, and 96 m minus half a metre of lake over a 0.2 m texel is a slope
// of five hundred - a normal pointing sideways and a black ring round the whole map edge.
float nb_level(vec4 n, float w_self) {
	return mix(n.x + n.y, w_self, nb_blocked(n, w_self));
}

// And the neighbour's DEPTH, mirrored the same way, for the shore-foam term.
float nb_depth(vec4 n, float h_self, float w_self) {
	return mix(n.y, h_self, nb_blocked(n, w_self));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_suv = win_uv(wp.xz);
	vec2 c = clamp(v_suv, vec2(0.0), vec2(1.0));
	float bt = 1.0 / max(float(textureSize(water_swe_tex, 0).x), 1.0);
	// textureLod is mandatory in the vertex stage - there are no derivatives here.
	vec4 bh = sample_column(c);
	float b = bh.x;
	float h = bh.y;

	// WHERE A DRY VERTEX SITS, and getting this wrong is what puts a vertical curtain of water at
	// every shoreline. A dry vertex has no water surface of its own, so the obvious b + h places
	// it on the BANK - above the water, sometimes well above, because the bed steps. The triangle
	// joining it to its wet neighbour then spans that whole drop, and the part of it that survives
	// the depth discard is a wall standing where a waterline should be.
	//
	// A dry vertex belongs at the level of the water it is next to. Take the highest wet
	// neighbour's surface; failing that - properly dry, nothing near - sink it below its own bed,
	// where the opaque terrain hides it.
	// THE FOUR NEIGHBOURS, FETCHED ONCE AND USED TWICE - by the dry-vertex rule just below and by
	// the slope just after it. They were two separate sets of reads in two different stages.
	vec4 nr = sample_column(clamp(c + vec2(bt, 0.0), vec2(0.0), vec2(1.0)));
	vec4 nl = sample_column(clamp(c - vec2(bt, 0.0), vec2(0.0), vec2(1.0)));
	vec4 nu = sample_column(clamp(c + vec2(0.0, bt), vec2(0.0), vec2(1.0)));
	vec4 nd = sample_column(clamp(c - vec2(0.0, bt), vec2(0.0), vec2(1.0)));

	// THE WATER THIS VERTEX CAN BORROW A LEVEL FROM: the highest wet neighbour that is not blocked
	// off. sample_column has already settled which solids are proud, so a submerged hull counts as
	// water here and a tower does not.
	float open_w = -1e9;
	if (nr.z < 0.5 && nr.y > h_dry) { open_w = max(open_w, nr.x + nr.y); }
	if (nl.z < 0.5 && nl.y > h_dry) { open_w = max(open_w, nl.x + nl.y); }
	if (nu.z < 0.5 && nu.y > h_dry) { open_w = max(open_w, nu.x + nu.y); }
	if (nd.z < 0.5 && nd.y > h_dry) { open_w = max(open_w, nd.x + nd.y); }

	float w = b + h;
	if (h <= h_dry) {
		float best = open_w;
		// ALL EIGHT NEIGHBOURS, and the four diagonals are not a refinement - they are the whole
		// bug. A vertex's triangle-mates on this grid are its EIGHT neighbours, so a dry vertex
		// with a wet DIAGONAL and four dry edge-neighbours failed the rescue above and fell
		// through to b - dry_skirt while still sharing a triangle with water.
		//
		// And b is the EFFECTIVE bed, which a solid raises. Inside a tower standing 2.5 m proud of
		// the lake, b - dry_skirt is two metres ABOVE the surface: the triangle joining that vertex
		// to its wet diagonal is a near-vertical pane of water climbing the wall, lit edge-on, so
		// it reads as a black wedge or a translucent curtain. That is the "border pattern at a
		// height change" - it needs no obstacle at all, only a bed step taller than dry_skirt, so
		// a tier riser or a steep bank does it too.
		//
		// With all eight covered, a dry vertex that touches water is always AT the waterline, and
		// one that touches none shares no triangle with any wet vertex, so where it sinks to
		// stops mattering.
		for (int i = 0; i < 4; i++) {
			vec2 o = vec2(i == 0 || i == 3 ? bt : -bt, i < 2 ? bt : -bt);
			vec4 dg = sample_column(clamp(c + o, vec2(0.0), vec2(1.0)));
			if (dg.z < 0.5 && dg.y > h_dry) { best = max(best, dg.x + dg.y); }
		}
		w = best > -1.0e8 ? best : b - dry_skirt;
	}

	// SLOPE AND COLUMN-THINNING, mirrored against the level this vertex is actually DRAWN at.
	// Mirroring against b + h instead would hand a dry vertex sitting on the bank a slope measured
	// from the bank, and that slope would then be interpolated into the wet pixels beside it - a
	// dark rim exactly along every waterline.
	float dxm = water_swe_rect.z * bt;
	v_slope = vec2(nb_level(nr, w) - nb_level(nl, w),
			nb_level(nu, w) - nb_level(nd, w)) / (2.0 * max(dxm, 0.001));
	// MIRRORED AT A WALL, and this is the hard white collar drawn round every solid and round the
	// map edge. shore foam is (thin water) * (column thinning fast), and it exists to draw the
	// waterline where a lake runs out onto a beach. A wall neighbour reports depth 0, so the raw
	// difference across it is the WHOLE COLUMN over one texel - 2.6 per metre against a threshold
	// of 1.2 - and the term saturated along every vertical face in the scene. A cliff is not a
	// beach: mirror the depth the same way the surface is mirrored and the collar goes, while a
	// genuine shore, whose dry neighbour is not a wall, keeps its foam.
	float hr = nb_depth(nr, h, w);
	float hl = nb_depth(nl, h, w);
	float hu = nb_depth(nu, h, w);
	float hd = nb_depth(nd, h, w);
	v_dhdx = length(vec2(hr - hl, hu - hd)) / (2.0 * max(dxm, 0.001));
	// In metres of surface, not per metre: how far this vertex stands off the plane its four
	// neighbours describe. Zero on anything flat OR uniformly sloping, whatever the tilt, and equal
	// to the spike height on a spike - which is the one thing v_slope cannot report.
	v_curv = abs((nb_level(nr, w) + nb_level(nl, w)
			+ nb_level(nu, w) + nb_level(nd, w)) * 0.25 - w);
	// GATED ON THE KILL SWITCH. With the solver asleep the rect publishes w = 0, and this must
	// collapse to nothing rather than draw a 64 m sheet of water at whatever the bed happens to be.
	float live = step(0.0001, water_swe_rect.w);
	v_h = h * live;
	// The node sits at Y = 0 and the bed is baked in world Y, so local Y IS world Y here.
	VERTEX.y = w * live;
	v_wpos = vec3(wp.x, VERTEX.y, wp.z);
}

void fragment() {
	// OUTSIDE THE WINDOW, or dry. discard rather than a zero alpha, so the grid never writes depth
	// over bare ground and never costs a blend for the part of itself that is not water.
	if (v_suv.x < 0.0 || v_suv.x > 1.0 || v_suv.y < 0.0 || v_suv.y > 1.0 || v_h <= h_dry) {
		discard;
	}
	vec2 c = clamp(v_suv, vec2(0.0), vec2(1.0));

	// CUT AT THE SOLID'S OWN OUTLINE, per pixel, and this is the sawtooth.
	//
	// The wet/dry decision is made per VERTEX on a 0.2 m lattice, and v_h then interpolates from a
	// wet vertex to a dry one - so nearly the whole of the boundary triangle survives the depth
	// discard and the water is drawn about a texel INTO the solid, in a staircase. Round a cylinder
	// that reads as a ring of triangular teeth.
	//
	// But the shape is ANALYTIC here: surf_obstacle_top tests the same uniforms the solver does, at
	// whatever position it is asked about. Asking at the PIXEL gives a silhouette limited by the
	// screen rather than by the simulation grid - a circle comes out round.
	float ob_here = surf_obstacle_top(c, bed_smooth_at(c));
	float rest_here = textureLod(field_tex, snap_field(c), 0.0).a;
	rest_here -= step(5000.0, rest_here) * 10000.0;
	if (ob_here > -1.0e8 && ob_here > rest_here + h_dry && rest_here > -500.0) {
		discard;
	}
	vec4 swe = texture(water_swe_tex, c);

	// BEER-LAMBERT. One expression carries both the tint and the transparency, which is why they
	// can never disagree about how deep the water is.
	float opt = 1.0 - exp(-v_h / max(absorb, 0.01));
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, opt);

	// SLOPE AND COLUMN-THINNING, interpolated from the vertices rather than re-differenced here.
	// See the varying declarations: differencing here read the same texel for every pixel in a
	// cell, so the normal was piecewise constant and the surface wore a 0.2 m checker.
	vec2 slope = v_slope;
	// How fast the WATER COLUMN is thinning. Near zero across a calm sheet however thin it is;
	// large only where the sheet is running out.
	float dhdx = v_dhdx;
	// THE SLOPE THE LIGHTING SEES IS LIMITED, keeping its direction. Past about 45 degrees the shade
	// term pins its own clamp, so every steep face - a shock front, a bore, a wake trough - shades
	// to the same flat dark whatever its real angle, which is what turns a gradient into a hard
	// edge. Bounding the slope instead lets a steep face read as steep rather than as saturated.
	float steep = length(slope);
	vec2 slope_lit = steep > jump_slope ? slope * (jump_slope / steep) : slope;
	vec3 n = normalize(vec3(-slope_lit.x, 1.0, -slope_lit.y));
	vec3 L = normalize(look_dir);
	// EXACTLY ZERO on flat water, which is what keeps still ponds looking exactly as they did.
	float shade = dot(n, L) - L.y;
	// SCALED, NOT SUBTRACTED, and that is what stops steep water going BLACK. deep_color is
	// (0.06, 0.22, 0.38); subtracting a flat 0.35 from it drives red and green below zero and
	// clips, so any slope steep enough to saturate the clamp - a wake trough, a bore, the face of
	// a bow wave - came out as a black gash rather than as dark water. Multiplying preserves the
	// hue and cannot cross zero, and it is still EXACTLY identity on flat water, where shade is
	// identically zero, so a still pond looks precisely as it did.
	col *= 1.0 + clamp(shade * slope_shade, -0.55, 0.55);
	// The sun's own reflection, on the water's own normal. Zero where the surface faces away, so a
	// flat pond gets an even sheen rather than a hotspot.
	col += foam_color.rgb * pow(max(dot(n, L), 0.0), glint_sharp) * glint_strength;

	// FOAM: what the solver made (hydraulic jumps, crests, the plunge below a fall) plus the
	// shoreline, where shallow water breaks on the bed. The second also does the useful work of
	// drawing the waterline as a line rather than a fade.
	float shore = (1.0 - smoothstep(0.0, max(shore_foam, 0.001), v_h))
			* smoothstep(0.15, max(shore_edge, 0.2), dhdx);
	// THE JUMP, foamed by its own steepness. Ordinary waves are gentle - a 0.2 m wave on a metre of
	// water is a slope of 0.2 - and the shock measures about 2.8, so the two do not overlap and the
	// threshold does not have to be delicate. Zero on flat water by construction.
	float jump = max(smoothstep(jump_slope, jump_slope * 2.0, steep),
			smoothstep(jump_curv, jump_curv * 2.0, v_curv)) * jump_foam;
	float foam = clamp(swe.a * live_foam + shore + jump, 0.0, 1.0);
	col = mix(col, foam_color.rgb, foam * foam_mix);

	ALBEDO = col;
	// The very edge fades out so the waterline is a meeting rather than a cut, and depth does the
	// rest: a puddle is nearly clear, a lake is not.
	// Depth carries the opacity, and the floor is low on purpose: a centimetre of water should let
	// you read the ground through it, which is what makes a basin FILLING legible rather than a
	// sheet appearing all at once.
	ALPHA = clamp(smoothstep(h_dry, h_dry + 0.02, v_h) * mix(shallow_alpha, max_alpha, opt)
			+ foam * foam_alpha, 0.0, 1.0);
}
