shader_type spatial;
render_mode cull_back;
// The crypt's stone. Same painted lighting as shaders/painted_env.gdshader, plus the three things
// a MODULAR dungeon needs that an open landscape does not.
//
// THE PROBLEM THIS SOLVES. The brick kit is thirteen .glb files, each dropped dozens of times per
// dungeon on a 4 m grid. Every copy of wall_brick_a is byte-identical, so any detail baked into the
// mesh — a stain, a crack, a patch of moss — appears in the same place on all forty of them, and
// the eye finds the grid instantly. Meanwhile the meshes carry NO UVs at all (COLOR_0 + NORMAL +
// POSITION; the tangents Godot's importer synthesised have no UV layout behind them and mean
// nothing), so there is no texture space to paint into even if that were the right answer.
//
// Both problems have the same fix: sample in WORLD space, triplanar. wall_brick_a at x=8 and the
// same mesh at x=12 land on different noise because they are in different places. Nothing is
// per-module, so nothing can restart at a module seam, and the kit needs no UVs to get grain.
//
// WHAT IS DELIBERATELY NOT HERE:
//
//   * PARALLAX / DISPLACEMENT. The bricks are real geometry — 18,600 verts per 4x3 m wall, every
//     brick a modelled box with a real silhouette that really self-shadows. The relief exists. What
//     follows is grain ON stone, not the stone; heightmapping it would be paying twice.
//   * A SATURATION KNOB on the palette remap. Taking COLOR_0's luminance IS the desaturation — the
//     blue lives entirely in the chroma being discarded. `chroma_keep` is the escape hatch.
//   * SPECULAR AND RIM, for the reason painted_env gives: both were measured, on this project, to
//     be the source of the "plastic" look.

group_uniforms Stone;
// THE PALETTE REMAP. COLOR_0 is treated as a per-brick VARIATION signal rather than as a colour:
// take its luminance, normalise it across the range the kit actually occupies, and remap that onto
// three warm stone stops. Re-skinning to an ice vault is three colours in a sibling .tres.
// THESE ARE ALBEDO, NOT RENDERED BRIGHTNESS, and the first pass got that wrong by a factor of two.
// It set dark/mid/light to 0.055/0.20/0.38, which sounds like reasonable dark stone — but the kit's
// FLOOR tiles occupy the bottom of the measured COLOR_0 range (0.22-0.42 against the walls' 0.29-
// 0.70), so they landed near `stone_dark` and rendered at 0.08 albedo. That is fresh asphalt. In a
// room lit only by torches there is no headroom to recover it, and no amount of light_energy helps:
// the light was never the bottleneck. Real weathered limestone is 0.25-0.45.
uniform vec3 stone_dark : source_color = vec3(0.100, 0.088, 0.078);
uniform vec3 stone_mid : source_color = vec3(0.300, 0.270, 0.235);
uniform vec3 stone_light : source_color = vec3(0.520, 0.480, 0.420);
// THE KIT'S COLOUR RANGE, AND THESE ARE MEASURED, NOT GUESSED. p5/p95 over all 148,608 coloured
// vertices, from scripts/dungeon/tests/probe_crypt_paint.gd. Authoring the ramp over 0..1 instead
// would leave three quarters of it unreachable and land every brick on the same mid grey — which
// looks exactly like the shader doing nothing at all.
//
// These are the POST-BAKE numbers. Folding Cycles AO into COLOR_0 (tools/export_dungeon_kit.py)
// pulled p5 from 0.287 down to 0.168 while p95 barely moved, because what darkened was the mortar
// and the undersides — exactly the signal `cav` below reads to push moss into the joints.
// RE-MEASURE AND UPDATE THESE ANY TIME THE BAKE STRENGTH CHANGES.
uniform float var_black : hint_range(0.0, 1.0, 0.005) = 0.168;
uniform float var_white : hint_range(0.0, 1.0, 0.005) = 0.575;
// 1.0 = the ramp is linear in measured luminance. Above 1 it pushes the mid-range DOWN, which on a
// kit whose floors already sit low just buries them.
uniform float var_contrast : hint_range(0.2, 3.0, 0.05) = 1.0;
// 0 = the remap is the desaturation, which is the point. Only raise this if a future kit encodes
// something meaningful in hue rather than in value.
uniform float chroma_keep : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float stone_rough : hint_range(0.0, 1.0, 0.01) = 0.92;
group_uniforms;

group_uniforms Triplanar;
// How hard the three planes cut over. Low = a wide smeary blend band on every chamfer; high = a
// visible hard edge. 4 is the usual compromise and the kit is nearly all axis-aligned boxes anyway.
uniform float tri_sharpness : hint_range(1.0, 16.0, 0.5) = 4.0;
// Per-stone tone break-up. Cellular CELL_VALUE: flat values per cell, so each stone gets its own
// tone rather than a gradient across it.
uniform sampler2D mottle_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
// NOT an exact divisor of the kit's 4 m module pitch, on purpose: at 0.25 every module would sample
// the same phase of the noise and the pass would rebuild the very grid it exists to hide.
uniform float mottle_scale : hint_range(0.01, 2.0, 0.01) = 0.23;
uniform float mottle_amount : hint_range(0.0, 1.0, 0.01) = 0.16;
// Broad grime. Deliberately a LONGER repeat than a room is wide, so no two walls in one room get
// the same dirt.
uniform sampler2D grunge_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float grunge_scale : hint_range(0.01, 2.0, 0.01) = 0.08;
uniform vec3 grime_color : source_color = vec3(0.35, 0.33, 0.28);
uniform float grime_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
// Metres up the piece that grime pools within. See v_local_y.
uniform float grime_height : hint_range(0.1, 5.0, 0.1) = 1.6;
group_uniforms;

group_uniforms Grain;
uniform sampler2D bump_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_normal;
uniform float bump_scale : hint_range(0.01, 4.0, 0.01) = 0.5;
uniform float bump_amount : hint_range(0.0, 2.0, 0.01) = 0.6;
// NoiseTexture2D(as_normal_map) writes an OpenGL-convention map, and Godot's built-in NORMAL_MAP
// path flips green on the way in — a hand-rolled decode like the one below does not. If the mortar
// reads as RAISED rather than recessed under a grazing torch, this is the knob, not the bake.
uniform float bump_green_sign : hint_range(-1.0, 1.0, 2.0) = -1.0;
group_uniforms;

group_uniforms Moss;
uniform sampler2D moss_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
// Dark and desaturated — bright green moss in a near-black crypt is the fastest way to make a scene
// read as placeholder art. But not DARKER THAN THE STONE, which the first value was: at 0.165
// luminance against stone_mid's 0.30 it mixed in as a dim patch with no hue, invisible under warm
// torchlight. Moss has to differ from stone in HUE, not in value, or the mix reads as dirt.
uniform vec3 moss_color : source_color = vec3(0.170, 0.245, 0.100);
uniform float moss_scale : hint_range(0.01, 2.0, 0.01) = 0.12;
uniform float moss_amount : hint_range(0.0, 1.0, 0.01) = 0.70;
// WORK THIS OUT, DO NOT EYEBALL IT. The mask is a product of four terms, so it lands far lower than
// the individual factors suggest: a floor tile runs up=1.0, gravity=1.0, cavity~0.70, clump~0.5, and
// multiplies out to ~0.38. At the first value of 0.42 the smoothstep clipped every one of them to
// zero and the crypt grew no moss anywhere, which reads as "the moss code does nothing".
uniform float moss_threshold : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float moss_soft : hint_range(0.01, 1.0, 0.01) = 0.22;
// How strongly moss prefers up-facing surfaces. The mask is REMAPPED rather than clamped, so a
// vertical wall still gets some and only downward faces get none.
// BELOW 1.0 ON PURPOSE. This is an exponent on a mask that is 0.5 for a vertical face, so 1.6 scored
// walls at 0.33 and — multiplied by the cavity and clump terms — put them under the threshold
// everywhere. The crypt grew moss on nothing but floor it was too dark to see. At 0.8 a wall scores
// 0.57 and moss reaches the lower mortar courses, which is where the reference photo has it.
uniform float moss_up_power : hint_range(0.1, 8.0, 0.1) = 0.8;
// Moss climbs from the floor. Metres, measured up the piece's own base.
uniform float moss_height : hint_range(0.1, 5.0, 0.1) = 1.3;
uniform float moss_gravity : hint_range(0.0, 1.0, 0.05) = 0.7;
// How much moss seeks the CREVICES. In the reference photo the moss is in the mortar, not on the
// faces — and after the Blender cavity bake, (1 - remapped COLOR_0) is exactly a crevice mask.
uniform float moss_in_mortar : hint_range(0.0, 1.0, 0.05) = 0.8;
uniform float moss_bump : hint_range(0.0, 1.0, 0.05) = 0.35;
// How much the per-piece seed pushes moss coverage around, so one wall is mossier than its neighbour.
uniform float moss_piece_spread : hint_range(0.0, 2.0, 0.05) = 0.5;
// WATER RUNS DOWN. The moss mask was one isotropic triplanar sample, so a wall grew the same round
// blobs the floor does -- and moss on a wall is not lichen, it is what grows where water has been
// running. Compressing Y in the SAMPLE POSITION stretches the noise vertically, which costs one
// extra fetch and no new texture.
//
// It leaves the floor exactly as it was, for free and by construction: the XZ triplanar plane
// samples (x, z), so scaling Y cannot reach it. Only the XY and ZY planes -- the wall-facing ones --
// see the change, and the blend below is weighted by verticality on top of that.
//
// 1 = isotropic (the old behaviour). Past ~6 the streaks stop varying down their own length and
// read as a curtain rather than as separate runs.
uniform float moss_streak : hint_range(1.0, 12.0, 0.5) = 7.0;
// WATER ENTERS AT THE TOP. The first version put the wall's moss allowance at the SKIRTING and
// faded it upward, which is where standing water would leave it -- but on a wall the eye reads that
// as growth CLIMBING, and what it should read as is a stain hanging from above. So the source is the
// head of the wall and the run falls from it.
//
// Height the water gets in at: just under the cornice, where a roof would fail.
uniform float moss_drip_top : hint_range(0.0, 8.0, 0.1) = 6.5;
// How far a run reaches before it has dried out.
uniform float moss_drip_len : hint_range(0.5, 8.0, 0.1) = 6.6;
// WIDE AT THE TOP, NARROW AT THE BOTTOM, which is the whole shape. The noise has to clear a bar that
// RISES the further it falls, so a run starts as a broad wet patch and only its strongest cores
// survive to the bottom. 0 = a parallel-sided stripe, which reads as a painted line.
uniform float moss_drip_taper : hint_range(0.0, 1.0, 0.05) = 0.62;
// HOW SPARSE THE RUNS ARE at the head, before the taper starts eating them. Without this the bar at
// depth 0 is zero, every rise in the noise qualifies, and the whole top of the wall goes green as
// one curtain — which reads as a painted band, not as water finding a few weak points.
uniform float moss_drip_bite : hint_range(0.0, 1.0, 0.02) = 0.36;
uniform float moss_wall_amount : hint_range(0.0, 1.5, 0.05) = 0.6;
group_uniforms;

group_uniforms Variation;
// Per-piece VALUE offset. Real masonry steps in brightness where two batches of stone meet, which
// is the "these two modules are different" cue wanted here — without touching the pattern.
//
// KEPT SMALL, because it cuts both ways. On a wall the step lands on a vertical joint and reads as
// masonry; on a FLOOR of 4 m squares the same step outlines every tile and hands the eye the exact
// grid the rest of this shader is hiding. At 0.07 the floor was a visible checkerboard.
uniform float tint_jitter : hint_range(0.0, 0.5, 0.01) = 0.03;
// Offsets the MOSS CLUMP layer only, and defaults to 0. Offsetting the low-frequency layers per
// piece would put a hard noise discontinuity at every module joint — rebuilding the visible tile
// grid this whole shader exists to remove. Raise it only if the clumps visibly repeat.
uniform float seed_spread : hint_range(0.0, 20.0, 0.1) = 0.0;
group_uniforms;

// PER-PIECE CONSTANTS, written by Kit.paint() from the same stable ctx.variant_roll that picks the
// variant — so it is keyed to WHERE a piece is, never to when it was built, and the determinism
// suites are unaffected by construction.
//   x = seed   y = seed2   z = value jitter [-1,1]   w = moss bias [0,1)
// The -1 default means "nobody plumbed me": a template mesh or a hand-placed prop wearing this
// material falls back to hashing its own origin rather than going uniformly grey. The socket
// degrades, which is the rule for every socket in this dungeon.
instance uniform vec4 piece_params = vec4(-1.0);

// METRES THIS PIECE'S ORIGIN SITS ABOVE ITS ROOM'S FLOOR.
//
// v_local_y below is "metres up this piece", and the comment there argues that is what gravity
// wants because every kit piece has its origin at the bottom centre. That was true only while every
// piece stood ON THE FLOOR. A stacked wall course sits at 3.3 m and restarts its own local Y at
// zero, so grime pools and moss climbs from 3.3 m upward — a floating tide mark landing exactly on
// the string course the banding exists to hide, on every wall in the dungeon. The cornice is worse:
// all 0.5 m of it is inside grime_height.
//
// Written by Kit.dress() from the slot's own Y. It also fixes stair rooms, which have had this bug
// since walls started riding climb_height.
instance uniform float piece_base = 0.0;

// PAINT ON THE STONE. rgb is the colour, w is how much of it to take; w = 0 is untinted, which is
// the default and therefore what every piece nobody has an opinion about renders as.
//
// WHY THIS EXISTS. The palette remap above takes COLOR_0's LUMINANCE and lands it on three warm
// stops, so the crypt is monochrome BY CONSTRUCTION -- the chroma is discarded on purpose and
// `chroma_keep` is the escape hatch for a kit that encodes something in hue. This is the other
// escape hatch, for the case the reference art actually wants: architecture that was PAINTED. Blue
// columns against an ochre panel field is most of what a Titan Quest interior is doing, and none of
// it can come from COLOR_0, because the meshes do not carry it and should not -- a tint that lived
// in the vertex colour would be the same on all forty copies of a wall and could not be re-skinned.
//
// Written per instance by Kit.dress() from DungeonTheme.piece_tints, so the one shared material is
// preserved. That is not a nicety: per-instance uniforms only work with a shared material, and
// Forward+ auto-instancing collapses forty identical mesh+material pairs into one draw. A material
// per colour would cost both.
instance uniform vec4 piece_tint = vec4(1.0, 1.0, 1.0, 0.0);

// ---- the painted look. THE TWIN OF THIS BLOCK LIVES IN shaders/painted_env.gdshader. ----------
// Deliberately duplicated rather than extracted to a .gdshaderinc: painted_env is worn by the
// ground, the whole village and all the foliage, and one syntax error in a shared include takes
// every one of them down at once. The two also WANT to diverge — a torch pool needs a harder
// terminator and a warm shade tint where a sunlit village wants soft and blue. Names and semantics
// are kept identical so a fix found in one transplants verbatim. If they still agree in three
// months, extract them.
group_uniforms Light;
uniform float wrap : hint_range(0.0, 1.0, 0.01) = 0.30;
uniform float bands : hint_range(0.0, 8.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.01, 1.0, 0.01) = 0.35;
group_uniforms;

group_uniforms Shadow;
uniform vec4 shade_tint : source_color = vec4(0.30, 0.26, 0.34, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0, 0.01) = 0.30;
uniform float shade_saturation : hint_range(0.0, 2.0, 0.05) = 1.15;
// LEAVE THIS AT 1.0. A sealed crypt is the literal case painted_env's comment warns about: the
// shade term is added for every light REGARDLESS of occlusion, so at 0.0 it lights the inside of a
// closed building from nowhere (measured there at 0.398 mean luminance with ambient off and GI
// off). Every wall would self-illuminate and the entire black-void pass would be wasted.
uniform float shade_occlusion : hint_range(0.0, 1.0, 0.05) = 1.0;
group_uniforms;

group_uniforms Torchlight;
uniform vec4 light_tint : source_color = vec4(1.0, 0.86, 0.66, 1.0);
// 0.45 plus the theme's amber light_color plus adjustment_saturation stacked into sodium orange —
// measured at 0.83 mean saturation, where the reference dioramas are nearly monochrome. The tint
// belongs on the LIGHT, not doubled onto the surface as well.
uniform float light_tint_amount : hint_range(0.0, 1.0, 0.05) = 0.28;
group_uniforms;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec3 v_wpos;
varying vec3 v_wnrm;
// METRES UP THIS PIECE. Every kit piece has its origin at the BOTTOM CENTRE — that is Kit's header
// contract, not a coincidence — so raw local Y is exactly what gravity-driven effects want. World Y
// cannot do this job: a stair room puts a floor at FLOOR_HEIGHT and every grime line would sit a
// storey too low.
varying float v_local_y;


vec3 saturate_rgb(vec3 c, float amount) {
	return mix(vec3(dot(c, LUMA)), c, amount);
}


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(tri_sharpness));
	return w / max(w.x + w.y + w.z, 1e-4);
}


// One scalar layer, world-space triplanar. Reads the red channel: every layer here is a NoiseTexture2D.
float tri_s(sampler2D t, vec3 p, vec3 w, float s, vec2 o) {
	return texture(t, p.zy * s + o).r * w.x
		+ texture(t, p.xz * s + o).r * w.y
		+ texture(t, p.xy * s + o).r * w.z;
}


// THE NORMAL, WITHOUT A TANGENT BASIS. Triplanar has no single tangent frame to build one from —
// each of the three planes has its own — so this is the whiteout blend (Golus): fold the geometric
// normal into each plane's XY, force Z positive by that axis's sign so the perturbation never
// inverts on the far side of a box, swizzle each plane's result into world orientation, then
// triblend. The geometry's own normal IS the third basis vector; the other two are implied by
// which plane is being sampled.
vec3 tri_normal(vec3 p, vec3 N, vec3 w, float s) {
	vec3 nx = texture(bump_tex, p.zy * s).xyz * 2.0 - 1.0;
	vec3 ny = texture(bump_tex, p.xz * s).xyz * 2.0 - 1.0;
	vec3 nz = texture(bump_tex, p.xy * s).xyz * 2.0 - 1.0;
	nx.y *= bump_green_sign;
	ny.y *= bump_green_sign;
	nz.y *= bump_green_sign;
	nx.xy *= bump_amount;
	ny.xy *= bump_amount;
	nz.xy *= bump_amount;
	nx = vec3(nx.xy + N.zy, abs(nx.z) * N.x);
	ny = vec3(ny.xy + N.xz, abs(ny.z) * N.y);
	nz = vec3(nz.xy + N.xy, abs(nz.z) * N.z);
	return normalize(nx.zyx * w.x + ny.xzy * w.y + nz.xyz * w.z);
}


void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// MODEL_MATRIX is good enough for the normal because kit pieces are unit-scaled — Kit.SIZES is
	// the gameplay contract and the collider assumes it. A non-uniformly scaled variant would need
	// the inverse transpose here instead.
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_local_y = VERTEX.y;
}


void fragment() {
	vec3 gn = normalize(v_wnrm);
	vec3 w = tri_weights(gn);

	// --- per-piece constants -------------------------------------------------------------------
	vec4 pp = piece_params;
	if (pp.x < 0.0) {
		// Quantise before hashing: the crypt is parked at world (500, 0, 500) and hashing raw
		// four-digit float32 coordinates correlates badly — neighbouring pieces come out the same.
		vec2 q = floor((MODEL_MATRIX[3].xz + 4096.0) / 0.5);
		pp = vec4(hash21(q), hash21(q + 17.0), hash21(q + 91.0) * 2.0 - 1.0, hash21(q + 313.0));
	}
	vec2 seed_off = vec2(pp.x, pp.y) * seed_spread;

	// --- palette remap of COLOR_0 --------------------------------------------------------------
	float lum = dot(COLOR.rgb, LUMA);
	float v = clamp((lum - var_black) / max(var_white - var_black, 1e-3), 0.0, 1.0);
	v = pow(v, var_contrast);
	vec3 stone = (v < 0.5)
		? mix(stone_dark, stone_mid, v * 2.0)
		: mix(stone_mid, stone_light, (v - 0.5) * 2.0);
	if (chroma_keep > 0.0) {
		stone = mix(stone, stone * (COLOR.rgb / max(lum, 1e-3)), chroma_keep);
	}

	// --- paint, if this piece was given any -----------------------------------------------------
	// VALUE-PRESERVING, and that is the whole trick. A straight mix() toward a colour flattens the
	// ramp the block above just built -- every brick's baked cavity, every mortar joint, the whole
	// reason the occlusion goes into COLOR_0 -- and a painted column comes out as a blue silhouette
	// with no masonry in it. So the tint is first renormalised to the luminance the stone already
	// has, and only then blended: the hue moves, the light and shade stay exactly where the bake
	// put them. Paint on stone behaves like this in life too; pigment does not fill the joints.
	//
	// Placed BEFORE mottle, grime and moss on purpose. Those are things that happen TO a surface,
	// and they must read on top of the paint rather than under it -- grime over a painted panel is
	// what makes it look painted a long time ago.
	if (piece_tint.a > 0.0) {
		float sv = dot(stone, LUMA);
		vec3 painted = piece_tint.rgb * (sv / max(dot(piece_tint.rgb, LUMA), 1e-3));
		stone = mix(stone, painted, piece_tint.a);
	}

	// --- mottle: each stone its own tone -------------------------------------------------------
	float mottle = tri_s(mottle_tex, v_wpos, w, mottle_scale, vec2(0.0));
	stone *= mix(1.0 - mottle_amount, 1.0 + mottle_amount, mottle);

	// --- grime, pooling low --------------------------------------------------------------------
	float grunge = tri_s(grunge_tex, v_wpos, w, grunge_scale, vec2(0.0));
	// Height above the ROOM's floor, not above this piece's own base — see piece_base.
	float h = v_local_y + piece_base;
	float low = 1.0 - smoothstep(0.0, grime_height, h);
	stone = mix(stone, stone * grime_color, grunge * grime_amount * mix(0.35, 1.0, low));

	// --- per-piece value step ------------------------------------------------------------------
	stone *= 1.0 + pp.z * tint_jitter;

	float rough = mix(stone_rough, 1.0, grunge * 0.4);
	vec3 world_n = tri_normal(v_wpos, gn, w, bump_scale);

	// --- moss ----------------------------------------------------------------------------------
	float up = pow(clamp(gn.y * 0.5 + 0.5, 0.0, 1.0), moss_up_power);
	float grav = 1.0 - smoothstep(moss_height * 0.5, moss_height, h);
	float clump = tri_s(moss_tex, v_wpos, w, moss_scale, seed_off);
	// How vertical this surface is: 1 on a wall, 0 on floor and ceiling. Everything below is gated
	// on it, so the floor keeps precisely the moss it had.
	float vert = clamp(1.0 - abs(gn.y), 0.0, 1.0);
	// The same noise with Y squashed, so its features run DOWN the wall. Blended in by verticality.
	float run = tri_s(moss_tex, v_wpos * vec3(1.0, 1.0 / max(moss_streak, 0.01), 1.0),
			w, moss_scale, seed_off);
	clump = mix(clump, run, vert);
	// HOW FAR THIS POINT HAS FALLEN from where the water got in: 0 at the source, 1 once dry.
	float depth = clamp((moss_drip_top - h) / max(moss_drip_len, 0.01), 0.0, 1.0);
	// The taper. The bar rises with depth, so a run is a broad patch at the head and a thin core by
	// the time it reaches the floor — which is the difference between a stain and a stripe.
	float bar = moss_drip_bite + moss_drip_taper * depth * (1.0 - moss_drip_bite);
	float taper = smoothstep(bar, bar + 0.22, run);
	float tide = vert * taper * (1.0 - 0.55 * depth) * moss_wall_amount;
	// (1 - v) is the crevice mask, for free: v is the normalised COLOR_0 luminance, which after the
	// Blender bake is per-brick lightness MULTIPLIED BY baked cavity. This is the whole reason the
	// occlusion goes into COLOR_0 rather than into a channel of its own.
	float cav = 1.0 - v;
	// The two contributions are kept apart, because they disagree about height. moss_gravity fades
	// growth out as it rises — right for growth that started on the ground, exactly backwards for a
	// stain that started at the ceiling — and the drip carries its own height profile in `depth`
	// anyway. Same for `clump`: the drip is already shaped by `run` and would only be eaten twice.
	float m = (up * mix(1.0, grav, moss_gravity) * clump + tide) * mix(1.0, cav, moss_in_mortar);
	m = clamp(smoothstep(moss_threshold, moss_threshold + moss_soft, m)
			* moss_amount * (1.0 + (pp.w - 0.5) * moss_piece_spread), 0.0, 1.0);

	stone = mix(stone, moss_color * (0.7 + 0.6 * clump), m);
	rough = mix(rough, 1.0, m);
	// Soften the grain under moss by pulling back toward the flat geometric normal, rather than
	// sampling a fourth map. Three more texture fetches to make lichen slightly fuzzier is not a
	// trade worth making.
	world_n = normalize(mix(world_n, gn, m * moss_bump));

	ALBEDO = stone;
	ROUGHNESS = rough;
	SPECULAR = 0.0;
	// Everything above is world space; Godot's fragment NORMAL is VIEW space.
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}


void light() {
	// (1) wrapped lambert — remapped, not clamped, so light carries past the terminator
	float l = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;

	if (bands >= 1.0) {
		float m = l * bands;
		float b = floor(m);
		l = (b + smoothstep(0.5 - band_softness, 0.5 + band_softness, m - b)) / bands;
	}

	// (2)+(3) the shadow keeps the surface colour, shifted and saturated rather than darkened...
	vec3 shadow_side = saturate_rgb(ALBEDO * shade_tint.rgb, shade_saturation) * shade_strength;
	// ...but gated by the shadow map, or it becomes a light source that walls cannot stop.
	shadow_side *= mix(1.0, ATTENUATION, shade_occlusion);
	// (4) the lit side warms toward the torch's own colour
	vec3 lit_side = mix(ALBEDO, ALBEDO * light_tint.rgb, light_tint_amount);

	DIFFUSE_LIGHT += mix(shadow_side, lit_side, l) * (LIGHT_COLOR / PI);
}
