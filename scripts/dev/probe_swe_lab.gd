extends SceneTree
## THE SWE LAB'S ACCEPTANCE, and the record of what the lab found the day it was built.
##
## Every earlier water probe started from a FULL pond, where "it fills" and "it fails to drain"
## are the same picture. This one starts DRY and watches the volume, which is the only reading
## that can tell them apart — and the first thing it measured was that a dry basin does not stay
## dry. The diagnosis is section 2, and it is carried here rather than in a note because it is a
## property of the model that somebody will otherwise rediscover from scratch:
##
##   THE SOLVER CANNOT REPRESENT A DRY BASIN AT REST. Its state is (eta, u') where eta is the
##   deviation from a FLAT rest surface, and there is no bed-elevation channel — so "empty" is
##   only expressible as eta = -H0, a full-amplitude displacement. At the shoreline H0 falls to
##   zero across one metre of the bilinear terrain field, so eta acquires a real, steep gradient
##   there, and the solver reads a dry beach as a metre-high wall of water leaning inward.
##   Gravity then collapses it into the basin, correctly, at about a millimetre of head per step.
##
##   Every measurement below agrees with that and nothing else does. The INTERIOR of a flat pan
##   is an exact fixed point — all four faces equal, div(q) and lap(H) both identically zero, the
##   GPU writing back the same bits (section 2c). gravity = 0 stops the leak dead while switching
##   off drag, the weirs and the positivity floor changes nothing (2b). The growth is LINEAR in
##   time, which is a front advancing, not an instability compounding. And it did not scale with
##   float16's ulp, which rules out a rounding ratchet.
##
##   The fix is a design decision, not a patch: make depth h the primary variable over a separate
##   bed elevation, so "dry" is h = 0 and costs no displacement at all. That is a rewrite of the
##   state, and it is the honest price of a solver that can dry out. Until then the game is
##   unaffected — ponds there start and stay near rest, which is the one regime this encoding is
##   exact in — and the lab exists to keep the limit visible instead of surprising.
##
## 2 and 2a CHARACTERISE — they print the leak and its shape and never fail, because failing on a
## known limit is how a suite gets ignored. Everything else ASSERTS: 1 that an empty reset really
## empties, 2b that gravity is still the whole of it, 2c that the interior is still exact, 3 that
## a spring still reaches the field, 4 and 5 that source and sink still move mass in the right
## direction, 6 that the cell inspector still agrees with the shader.


var _rip: Node = null
var _fail := 0


func _initialize() -> void:
	var lab := (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 30:
		await process_frame
	# AFTER the frames, never in _initialize: at that point the autoloads have not been added yet
	# and an absolute get_node from `root` fails outright.
	_rip = root.get_node("/root/Ripples")
	# The panel re-reads the GPU on a timer for the human watching it. A probe does its own
	# readbacks at the exact steps it cares about, so leaving the timer on doubles the cost of the
	# slowest thing in the run for readings nobody looks at.
	lab.set("_live", false)
	# A scene whose script failed to parse still instantiates — as a bare Node3D, whose every
	# get() answers null and whose every call() is a no-op. That reads as a clean pass.
	if not lab.has_method("_read_back"):
		print("[LAB] FAIL: swe_lab.gd did not load — see the parse errors above")
		quit(1)
		return

	# SUITES 0-6 CHARACTERISE THE DEVIATION SOLVER, and the bench now opens in the depth one - so
	# they have to ask for the old encoding rather than inherit whatever the scene defaults to.
	# Stated here because the numbers below (the 60 cubic metre shoreline leak, the eta mirror) are
	# only true of eta, and silently running them against h would replace a known characterisation
	# with a meaningless one.
	_rip.set("depth_mode", false)
	_rip.set("edge_mode", 0)

	await _bed_agrees(lab)
	await _empty_start(lab)
	await _shoreline_leak(lab)
	await _which_term(lab)
	await _interior_is_exact(lab)
	await _source(lab)
	await _sink(lab)
	await _mirror(lab)
	await _depth_suite(lab)
	await _depth_ceiling(lab)
	# THE SAME SUITE AGAIN, STAGGERED. Two schemes live in the one shader behind `staggered`, and
	# the only honest way to claim the new one is better is to run the identical assertions against
	# both in the same process and print the pair. A rewrite that is measured against a REMEMBERED
	# baseline is a rewrite measured against a story about a baseline.
	_rip.set("staggered", true)
	print("[LAB] ================ STAGGERED (velocity on the faces) ================")
	await _depth_suite(lab)
	await _depth_ceiling(lab)
	_rip.set("staggered", false)

	print("[LAB] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## 0. THE BED AGREES WITH THE DEPTH MAP, texel by texel over the whole window. Three things now
## read the same arithmetic - the baked depth texture, the gameplay depth query, and the solver
## bed channel - and they agree only because they come out of one function. This is the assertion
## that keeps that true, and it is checked HERE rather than only in verify_wilds because the bake
## is a separate path: it resamples the oracle on a 1 m lattice, and a bake can be wrong about a
## contract the contract itself honours.
##
## The invariant is `H0 == max(Y - b, 0)`, NOT `b + H0 == Y`. The naive form is false along the
## whole wet beach, where the bed stands above its own surface and the column clamps to zero.
func _bed_agrees(lab: Node) -> void:
	await _reset(lab, false)
	var f: Image = (_rip.call("field_texture") as Texture2D).get_image()
	var b: Image = (_rip.call("bed_texture") as Texture2D).get_image()
	if f == null or b == null:
		print("[LAB] 0. FAIL: no bed texture - the bake never ran")
		_fail += 1
		return
	var mark := float(_rip.get("SPRING_MARK")) * 0.5
	var dry := float(_rip.get("DRY_Y")) + 1.0
	var worst := 0.0
	var at := Vector2i(-1, -1)
	var wet := 0
	for z in f.get_height():
		for x in f.get_width():
			var px := f.get_pixel(x, z)
			var yy: float = px.a - (float(_rip.get("SPRING_MARK")) if px.a > mark else 0.0)
			if yy <= dry:
				continue
			wet += 1
			var d: float = absf(px.b - maxf(yy - b.get_pixel(x, z).r, 0.0))
			if d > worst:
				worst = d
				at = Vector2i(x, z)
	print("[LAB] 0. bed vs depth map over %d wet texels: worst disagreement %.6f m at %s"
			% [wet, worst, at])
	if wet == 0:
		print("[LAB]    FAIL: no wet texels in the window - the bench bed is not reaching the bake")
		_fail += 1
	if worst > 1e-3:
		print("[LAB]    FAIL: the bed channel and the depth map disagree about the same world")
		_fail += 1


## 1. EMPTY MEANS EMPTY. Guards two traps at once: draw_max floors eta at -H0 * draw_max, so at
## the shipped 0.55 an "empty" basin is 45% full on the first step; and the reset step has to bind
## the terrain field, because eta = -H0 needs an H0 to negate.
func _empty_start(lab: Node) -> void:
	lab.set("_source_on", false)
	lab.set("_sink_on", false)
	lab.call("_rebuild")
	await _reset(lab, true)
	var v := _vol(lab)
	print("[LAB] 1. reset EMPTY -> volume %.3f m3" % v)
	if v > 5.0:
		print("[LAB]    FAIL: an empty basin is holding water (draw_max floor, or an unbound field)")
		_fail += 1


## 2. THE SHORELINE LEAK, watched rather than sampled: a constant leak and a compounding
## instability both end at "there is water in a dry basin", and only the SHAPE tells them apart.
## Linear is a front advancing. Exponential would be a solver coming apart.
func _shoreline_leak(lab: Node) -> void:
	await _reset(lab, true)
	var at := 0
	for n: int in [1, 10, 60, 300]:
		await _run(lab, n - at)
		at = n
		print("[LAB] 2. quiescent from empty, step %3d -> volume %8.3f m3" % [n, _vol(lab)])
	# Per bed shape. All three square footprints leak alike and the inscribed bowl leaks less in
	# proportion to its smaller area — consistent with a shoreline front, and inconsistent with
	# anything that depends on slope or curvature, since the flat pan has neither and leaks most.
	for case: Array in [[0, 0.0, "flat pan"], [1, 0.0, "valley, level"],
			[1, 0.03, "valley, 3% grade"], [3, 0.0, "bowl"]]:
		lab.get_node("Bed").set("profile", case[0])
		lab.get_node("Bed").set("grade", case[1])
		lab.call("_rebuild")
		await _reset(lab, true)
		var e0 := _vol(lab)
		await _run(lab, 60)
		print("[LAB] 2a. %-18s 60 quiescent steps -> %+.3f m3" % [case[2], _vol(lab) - e0])


## 2b. WHICH TERM. Every knob switched off in turn through the bench's own controls, on the flat
## pan, which is the control case: uniform H0, uniform eta, no gradient, no curvature, no step.
## gravity is the only one that changes the answer, and it changes it to exactly zero.
func _which_term(lab: Node) -> void:
	lab.get_node("Bed").set("profile", 0)
	lab.call("_rebuild")
	var zero_at_no_gravity := false
	for case: Array in [
			["baseline", {}],
			["gravity 0", {&"gravity": 0.0}],
			["velocity gated off (h_wet 10)", {&"h_dry": 5.0, &"h_wet": 10.0}],
			["positivity floor lifted (draw_max 4)", {&"draw_max": 4.0}],
			["drag 0", {&"drag": 0.0}]]:
		var saved := {}
		for k: StringName in (case[1] as Dictionary):
			saved[k] = _rip.call("sim_get", k)
			_rip.call("sim_set", k, (case[1] as Dictionary)[k])
		await _reset(lab, true)
		var e0 := _vol(lab)
		await _run(lab, 60)
		var got := _vol(lab) - e0
		print("[LAB] 2b. flat pan, %-38s -> %+.3f m3" % [case[0], got])
		if case[0] == "gravity 0":
			zero_at_no_gravity = absf(got) < 0.01
		for k: StringName in saved:
			_rip.call("sim_set", k, saved[k])
	if not zero_at_no_gravity:
		print("[LAB]    FAIL: with gravity off the solver still moves mass — the diagnosis in this "
				+ "file's header no longer holds and needs redoing")
		_fail += 1


## 2c. THE INTERIOR IS AN EXACT FIXED POINT, and this is the assertion the whole diagnosis rests
## on. Far from any shoreline, on a flat bed, every term must be identically zero and the GPU must
## write back the same bits. If this ever stops holding, the leak is no longer a boundary effect
## and everything above is wrong.
func _interior_is_exact(lab: Node) -> void:
	lab.get_node("Bed").set("profile", 0)
	lab.call("_rebuild")
	await _reset(lab, true)
	var mid := Vector2i(_res(lab) / 2, _res(lab) / 2)
	lab.set("_pick", mid)
	lab.call("_read_back")
	var e0 := _eta_at(lab, mid)
	lab.call("_inspect")
	await _run(lab, 1)
	lab.call("_check_prediction")
	var e1 := _eta_at(lab, mid)
	print("[LAB] 2c. flat pan interior: eta %+.5f -> %+.5f  (%+.4f mm)  %s"
			% [e0, e1, (e1 - e0) * 1000.0, _plain(String(lab.get("_pred_line")))])
	if absf(e1 - e0) > 1e-5:
		print("[LAB]    FAIL: the interior of a flat empty pan is not a fixed point")
		_fail += 1
	lab.get_node("Bed").set("profile", 1)
	lab.get_node("Bed").set("grade", 0.03)
	lab.call("_rebuild")


## 3. THE SOURCE, against a rate derived from the field rather than guessed: the spring area is
## counted off the terrain texture, where one texel is exactly one square metre.
##
## The observed rate is far above the source and that is the section-2 leak, not a second defect —
## the same 60-odd cubic metres per five seconds arrives with the spring switched off. Reported,
## and only asserted to be POSITIVE, because a tighter assertion here would be re-measuring the
## leak under a name that hides it.
func _source(lab: Node) -> void:
	lab.set("_source_on", true)
	lab.call("_rebuild")
	await _reset(lab, true)
	var area := _spring_area()
	var rate := float(_rip.call("sim_get", &"spring_rate"))
	var a0 := _vol(lab)
	await _run(lab, 300)
	var got := (_vol(lab) - a0) / 5.0
	print("[LAB] 3. source: %.0f m2 of spring x %.4f m/s = %.3f m3/s expected, %.3f observed "
			% [area, rate, area * rate, got] + "(the rest is the shoreline leak)")
	if area <= 0.0:
		print("[LAB]    FAIL: no spring reached the terrain field at all")
		_fail += 1
	if got <= 0.0:
		print("[LAB]    FAIL: the source is not filling the basin")
		_fail += 1


## 4. eta_keep IS A SOURCE BELOW REST. Relaxation toward eta = 0 is a sink only ABOVE the rest
## surface; below it, it pulls upward. Invisible in a game where ponds sit at rest, and the
## dominant term on a bench that starts dry — which is why the lab overrides it to 1.0 and says so.
func _sink(lab: Node) -> void:
	lab.set("_source_on", false)
	lab.call("_rebuild")
	_rip.call("sim_set", &"eta_keep", 0.999)
	await _reset(lab, true)
	var b0 := _vol(lab)
	await _run(lab, 240)
	var b1 := _vol(lab)
	print("[LAB] 4. no spring, eta_keep 0.999: %.3f -> %.3f m3 in 4 s" % [b0, b1])
	if b1 <= b0 + 0.5:
		print("[LAB]    NOTE: eta_keep no longer refills an empty basin — the headers are stale")
		_fail += 1
	_rip.call("sim_set", &"eta_keep", 1.0)

	# 5. THE DRAIN, from full so there is something to remove. It is expressed with the shipped
	# impulse API rather than new shader code: a drain is a continuous downward displacement, and
	# splash() clamps a poke to a fraction of the local column, so it weakens as the cell empties
	# and can never pull the depth negative.
	await _reset(lab, false)
	lab.set("_sink_on", true)
	lab.set("_sink_rate", 1.5)
	lab.set("_sink_radius", 6.0)
	var c0 := _vol(lab)
	await _run(lab, 240)
	var c1 := _vol(lab)
	print("[LAB] 5. sink on, 4 s: %.3f -> %.3f m3" % [c0, c1])
	if c1 >= c0 - 0.5:
		print("[LAB]    FAIL: the sink is not removing water")
		_fail += 1
	lab.set("_sink_on", false)


## 6. THE MIRROR AGAINST THE SHADER. The cell inspector re-implements the sim shader in GDScript,
## which is a liability taken on deliberately — there is no other way to show a single term of an
## update the GPU emits only the sum of. This is what keeps it from becoming confident fiction.
func _mirror(lab: Node) -> void:
	lab.set("_source_on", true)
	lab.call("_rebuild")
	await _reset(lab, true)
	await _run(lab, 90)
	var drift := 0
	var checked := 0
	var r := _res(lab)
	# Fractions of the window, not absolute texels: RES is a tuning decision and these picks must
	# keep pointing at the same piece of world when it changes.
	for f in [Vector2(0.50, 0.50), Vector2(0.39, 0.50), Vector2(0.50, 0.59), Vector2(0.35, 0.43)]:
		var p := Vector2i(int(f.x * float(r)), int(f.y * float(r)))
		lab.set("_pick", p)
		lab.call("_read_back")
		lab.call("_inspect")                      # predicts eta for the NEXT step
		await _run(lab, 1)
		lab.call("_check_prediction")
		var line := String(lab.get("_pred_line"))
		if line == "":
			continue
		checked += 1
		print("[LAB] 6. cell %s: %s" % [p, _plain(line)])
		if line.contains("DRIFT"):
			drift += 1
	if checked == 0:
		print("[LAB]    FAIL: the mirror never produced a prediction")
		_fail += 1
	elif drift > 0:
		print("[LAB]    FAIL: the cell inspector disagrees with the shader in %d of %d cells"
				% [drift, checked])
		_fail += 1


## 7. THE DEPTH ENCODING, and this is the stage's whole acceptance. Everything above runs against
## eta; everything here runs the same bench against h over a bed.
##
## TOLERANCES ARE SET BY THE STORE, not by taste. The state is RGBA16F, so one ulp at h ~ 0.5 m is
## 4.9e-4 m and at 1.3 m is 9.8e-4. The write is dithered (see swe_sim.gdshader) which makes the
## quantiser unbiased but leaves a floor of about an ulp of noise per cell per step. A cell
## tolerance below that would be asserting something the hardware cannot deliver, and a volume
## tolerance in absolute cubic metres would mean different things on a pond and a lake - so cells
## are checked against ulps and volume against a FRACTION of itself.
##
## seep is zeroed throughout and the spring is off: these are conservation tests, and a sink doing
## its job would hide exactly the error they look for.
## SET BY THE STORE, and by the fact that the store must be DITHERED. RGBA16F truncates, so a
## conserved quantity needs a rounding policy, and the only correct one is stochastic: round-to-
## nearest is noiseless but cannot accumulate an increment smaller than half an ulp, which silently
## deletes a spreading sheet and freezes a runup front. Stochastic rounding is unbiased at any
## increment size and costs a few ulps of wander per cell instead. Six ulps at bench depths.
const CELL_TOL := 6.0e-3
const VOL_TOL := 0.001          ## 0.1 % of the lake, over 600 steps


func _depth_suite(lab: Node) -> void:
	print("[LAB] --- depth mode ---")
	lab.set("_source_on", false)
	lab.set("_sink_on", false)
	var seep_was: Variant = _rip.call("sim_get", &"seep")
	_rip.call("sim_set", &"seep", 0.0)
	# THE CFL GUARD IS OFF FOR EVERY PHYSICS TEST. It caps g so the local kappa cannot exceed
	# cfl_max, which is exactly the right thing for somebody watching a basin fill and exactly the
	# wrong thing for a suite that measures what the scheme does: a guarded solver would report the
	# guard's own constant back as its stability limit, and every correctness figure below would be
	# about a scheme with a governor on it rather than the one that ships in the equations.
	_rip.call("sim_set", &"cfl_guard", false)
	# WALL, not HORIZON. The horizon rim fades toward the REST depth, which is right for a window
	# following a camera through a world that is already full, and wrong on a bench asking whether
	# an empty basin stays empty - it would refill its own edge every step.
	_rip.set("edge_mode", 1)
	_rip.set("depth_mode", true)

	# 7a-c. LAKE AT REST, over three beds that differ in exactly one feature each.
	#   flat    no slope, no step        - satisfied by almost any scheme
	#   ramp    slope, no step, no shore - THE test. Over a slope h varies while the surface does
	#           not, so a solver that differences DEPTH instead of SURFACE sees a gradient that is
	#           not there and drains the lake. This is the case the eta encoding cannot even
	#           express and the naive h-substitution fails outright.
	#   valley  slope, a V, and a 0.9 m vertical bank wall
	var failed_rest := false
	for case: Array in [[0, 0.0, "7a. flat pan       "], [4, 0.03, "7b. ramp, 3% grade "],
			[1, 0.03, "7c. valley + banks "]]:
		lab.get_node("Bed").set("profile", case[0])
		lab.get_node("Bed").set("grade", case[1])
		lab.call("_rebuild")
		await _reset(lab, false)
		# WHAT THE RESET ACTUALLY SEEDED, before asking whether it stays. "A cell moved 0.15 m"
		# has two completely different causes - the solver drifted, or the seed was not a lake at
		# rest and the solver correctly fixed it - and they want opposite fixes. The surface spread
		# tells them apart in one line: a correct seed is FLAT over every wet texel whatever the
		# bed does underneath.
		print("[LAB] %s seeded: %s  %s" % [case[2], _surface_spread(lab), _seed_holes(lab)])
		var v0 := _vol(lab)
		var s0 := _snapshot(lab)
		await _run(lab, 600)
		var moved := _max_abs_delta(lab, s0)
		var dv := _vol(lab) - v0
		print("[LAB] %s 600 steps at rest: volume %+.4f m3 (%+.4f%%)  worst cell %+.6f m  "
				% [case[2], dv, dv / maxf(v0, 1e-6) * 100.0, moved]
				+ "max |u| %.4f m/s" % _max_speed(lab))
		if absf(dv) > VOL_TOL * v0:
			print("[LAB]    FAIL: a lake at rest lost or gained volume")
			_fail += 1
			failed_rest = true
		# THE BAR DEPENDS ON THE SCHEME, and pretending otherwise would be scoring a conservative
		# solver against a diffusive one's habits.
		#
		# On a FLAT pan both are now bit-exact - 0.000000 m over 600 steps - because the bed is
		# uniform, so the seed is uniform, so there is no perturbation to evolve. On a SLOPING or
		# STEPPED bed the seed is not exact and cannot be: h is stored in float16, so
		# w = b + fl16(Y - b) misses Y by up to half an ulp, differently in every cell, and the
		# seeded surface carries about 2 mm of real structure before a single step runs.
		#
		# That structure is an initial condition with energy in it. The collocated scheme DIFFUSES
		# it away - which is exactly the 16 % of energy per ten seconds the compact Laplacian costs,
		# and exactly the diffusion that was also eating the centimetre-scale shoaling signal. The
		# staggered scheme conserves it instead, so it sloshes and superposes, and local excursions
		# reach several times the seed spread. Measured: seed spread 1.9 mm, worst cell 9.8 mm.
		#
		# Holding the conservative scheme to the diffusive one's number would be marking it down for
		# not throwing energy away. The real question - is the scheme adding energy that was never
		# there - is asked properly by probe_swe_scheme's budget, which is where it belongs.
		var cell_tol := CELL_TOL * (2.5 if bool(_rip.get("staggered")) else 1.0)
		if moved > cell_tol:
			print("[LAB]    FAIL: a cell moved %.6f m at %s, past %.4f m"
					% [moved, _worst_at, cell_tol])
			_explain_worst(lab, s0)
			_fail += 1
			failed_rest = true
		_assert_stable(lab, case[2])

	# 7d. IS THE SURFACE FLAT, and does it STAY flat? The single most informative reading on this
	# bench: depth varies over a sloping bed by design, and the surface must not. A submerged ramp
	# has no shoreline, no step and no dry cell, so nothing else can be blamed.
	#
	# Watch its SIGN as well as its size. A one-signed spread means the quantiser is one-signed,
	# which is how the truncating float16 store was found: before the dither this read
	# "[-0.000957, 0.000000]" across 36864 texels, never once above zero, and the lake sank at
	# half an ulp per step for as long as you let it run.
	lab.get_node("Bed").set("profile", 4)
	lab.get_node("Bed").set("bed_depth", 0.700)
	lab.get_node("Bed").set("grade", 0.010)
	lab.call("_rebuild")
	await _reset(lab, false)
	print("[LAB] 7d. seeded submerged ramp: %s" % _surface_spread(lab))
	var p0 := _vol(lab)
	await _run(lab, 1)
	print("[LAB] 7d. after 1 step:    volume %+.6f m3   %s"
			% [_vol(lab) - p0, _surface_spread(lab)])
	await _run(lab, 299)
	var d300 := _vol(lab) - p0
	_assert_stable(lab, "7d. submerged ramp")
	print("[LAB] 7d. after 300 steps: volume %+.6f m3 (%+.4f%%)   %s"
			% [d300, d300 / maxf(p0, 1e-6) * 100.0, _surface_spread(lab)])
	if absf(d300) > VOL_TOL * p0:
		print("[LAB]    FAIL: a submerged ramp does not hold its water")
		_fail += 1
		failed_rest = true
	lab.get_node("Bed").set("bed_depth", 0.55)
	lab.get_node("Bed").set("grade", 0.03)
	lab.call("_rebuild")

	# 7e. EMPTY STAYS EMPTY. The headline. What cost 60 cubic metres in five seconds under eta now
	# costs nothing at all, because "empty" is a state this encoding can hold rather than a
	# full-amplitude displacement it has to fight.
	await _reset(lab, true)
	await _run(lab, 600)
	var ve := _vol(lab)
	# Against suite 2 above rather than a quoted constant: that number depends on the bed, and the
	# default bed is a knob. Suite 2 measures the same thing on the same bed in the same run.
	print("[LAB] 7e. empty, 600 quiescent steps -> volume %.6f m3   (eta, same bed: see suite 2)"
			% ve)
	if ve > 0.001:
		print("[LAB]    FAIL: a dry basin is filling itself")
		_fail += 1

	# 7f. POSITIVITY, structural rather than clamped: the per-face quarter-column ceiling makes
	# h >= 0 a theorem. If the floor is ever load-bearing, 7g is what shows it.
	await _reset(lab, false)
	lab.set("_source_on", true)
	lab.call("_rebuild")
	await _run(lab, 300)
	var lo := _min_h(lab)
	_assert_stable(lab, "7f. driven")
	print("[LAB] 7f. after 300 driven steps, min h = %.6f m" % lo)
	if lo < 0.0:
		print("[LAB]    FAIL: negative depth")
		_fail += 1
	lab.set("_source_on", false)
	lab.call("_rebuild")

	# 7g. CONSERVATION. One big splash into a closed box, nothing entering or leaving. This asserts
	# the face-symmetric flux really is antisymmetric: the eta solver builds each face from its own
	# NEW velocity against the neighbour's OLD one, so two cells disagree about the same face and
	# mass quietly leaks. Nothing else in this file would notice.
	await _reset(lab, false)
	var before := _vol(lab)
	var centre: Vector3 = lab.get_node("Bed").to_global(Vector3.ZERO)
	_rip.call("splash", centre, 3.0, 0.25)
	# THE BASELINE IS TAKEN AFTER THE IMPULSE HAS LANDED, and reading it before was this probe
	# reporting its own stimulus as a leak. A splash in the depth encoding is not a wave added to a
	# conserved column, it is a DISPLACEMENT: `h_new -= min(poke, poke_frac * h)` removes water and
	# nothing puts it back. 0.25 m over a Gaussian of radius 3 m is about 1.8 m3, and against a
	# 1268 m3 box that is 0.14% - which is to say, essentially the entire "drift" this suite
	# reported for as long as it has existed. Conservation is what happens AFTER the stimulus.
	await _run(lab, 1)
	var c0 := _vol(lab)
	await _run(lab, 599)
	var err := absf(_vol(lab) - c0) / maxf(c0, 1e-6) * 100.0
	_assert_stable(lab, "7g. closed box")
	print("[LAB] 7g. closed box, one splash: %.3f -> %.3f m3 on impact, %.3f after 600 steps  "
			% [before, c0, _vol(lab)] + "(%.4f%% drift)" % err)
	if err > 0.5:
		print("[LAB]    FAIL: mass is not conserved across a face")
		_fail += 1
		failed_rest = true

	# 7i. THE DEPTH MIRROR AGAINST THE SHADER, the same contract suite 6 holds the eta mirror to.
	# Until now this branch had no mirror at all - the inspector printed "the mirror models the eta
	# solver only" and refused - so every failure in the encoding the work is actually about
	# arrived as a whole-field mystery with no way to interrogate one cell. Four picks across the
	# bowl: the middle, the flank, and two on the way out toward the rim where the faces close.
	lab.set("_source_on", true)
	lab.call("_rebuild")
	await _reset(lab, true)
	await _run(lab, 120)
	var m_drift := 0
	var m_checked := 0
	# FOUND, NOT GUESSED. Fixed fractions of the window put two of the four picks on dry ground,
	# where the fast path returns h unchanged and the mirror is trivially right about nothing. The
	# cells worth checking are the deep one, one halfway out, and the two either side of the
	# waterline - which is where every open question in this work lives.
	for p in _mirror_picks(lab):
		lab.set("_pick", p)
		lab.call("_read_back")
		lab.call("_inspect")                      # predicts h for the NEXT step
		await _run(lab, 1)
		lab.call("_check_prediction")
		var ml := String(lab.get("_pred_line"))
		if ml == "":
			continue
		m_checked += 1
		print("[LAB] 7i. cell %s: %s" % [lab.get("_pick"), _plain(ml)])
		if ml.contains("DRIFT"):
			m_drift += 1
	if m_checked == 0:
		print("[LAB]    FAIL: the depth mirror never produced a prediction")
		_fail += 1
	elif m_drift > 0:
		print("[LAB]    FAIL: the depth mirror disagrees with the shader in %d of %d cells"
				% [m_drift, m_checked])
		_fail += 1
	lab.set("_source_on", false)
	lab.call("_rebuild")

	# 7h. ONLY WHEN SOMETHING IS WRONG. A bisect costs a thousand steps and answers a question
	# nobody asks while the suite is green - but a probe that reports WHETHER without WHERE is how
	# a real failure turns into a week. gravity gates both the pressure flux and the Laplacian, so
	# it only proves one of the two is guilty; weir_cd zeroes the per-face discharge ceiling and
	# nothing else, which is the line that separates them.
	if failed_rest:
		print("[LAB] 7h. something moved that should not have. Bisecting:")
		lab.get_node("Bed").set("profile", 4)
		lab.call("_rebuild")
		for case: Array in [
				["baseline", {}],
				["gravity 0 (flux AND Laplacian off)", {&"gravity": 0.0}],
				["weir_cd 0 (flux off, Laplacian on)", {&"weir_cd": 0.0}],
				["u_max 0.01 (motion pinned off)", {&"u_max": 0.01}]]:
			var saved := {}
			for k: StringName in (case[1] as Dictionary):
				saved[k] = _rip.call("sim_get", k)
				_rip.call("sim_set", k, (case[1] as Dictionary)[k])
			await _reset(lab, false)
			var e0 := _vol(lab)
			await _run(lab, 300)
			print("[LAB] 7h.   ramp, %-36s -> %+.4f m3" % [case[0], _vol(lab) - e0])
			for k: StringName in saved:
				_rip.call("sim_set", k, saved[k])

	_rip.call("sim_set", &"seep", seep_was)
	_rip.call("sim_set", &"cfl_guard", true)
	_rip.set("depth_mode", false)
	_rip.set("edge_mode", 0)



## 8. THE DEPTH CEILING, measured rather than quoted.
##
## The scheme is explicit, so it has a stability limit: kappa = g*H*dt^2/dx^2 < 0.25, which
## rearranges to H_max = 0.25*dx^2/(g*dt^2). At dx 0.125 and dt 1/60 that is 1.43 m - and the
## whole point of the depth encoding is to let a basin fill past its banks, which over this world's
## deep bed wants about 1.75 m. So the requirement as asked for does not fit the grid as built, and
## this suite is what turns that from an argument into a number.
##
## A FLAT PAN, because its rest state is bit-exact: anything that grows afterwards is the
## perturbation, not the seed. One splash, then the deviation from rest sampled three times. A
## stable solver decays monotonically; an unstable one doubles between samples and then NaNs.
func _depth_ceiling(lab: Node) -> void:
	print("[LAB] --- depth ceiling ---")
	var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
	var dt := 1.0 / 60.0
	# THE CONSTANT FOLLOWS THE SCHEME. Collocated, stability needs kappa <= 0.25 in 2D; the
	# staggered forward-backward update is symplectic (det = 1 exactly) and its face gradient is
	# maximal at theta = pi rather than zero, which lifts it to kappa <= 0.5. Leaving 0.25 here
	# would let the assertion below pass against the wrong scheme's number - and its tolerance is a
	# factor of two either way, which is exactly the size of the difference.
	var kap_max: float = 0.5 if bool(_rip.get("staggered")) else 0.25
	var predicted: float = kap_max * dx * dx / (9.81 * dt * dt)
	print("[LAB] 8. dx %.4f m, dt %.5f s, kappa_max %.2f -> theory says H_max = %.3f m"
			% [dx, dt, kap_max, predicted])
	_rip.set("depth_mode", true)
	_rip.set("edge_mode", 1)
	var seep_was: Variant = _rip.call("sim_get", &"seep")
	_rip.call("sim_set", &"seep", 0.0)
	# OFF, and this is the suite where it matters most: the guard exists precisely to stop what
	# this measures. Leave it on and the answer is "stable at every depth we tried", which is the
	# guard describing itself.
	_rip.call("sim_set", &"cfl_guard", false)
	lab.set("_source_on", false)
	lab.set("_sink_on", false)
	lab.get_node("Bed").set("profile", 0)
	var last_stable := 0.0
	var first_unstable := 0.0
	# THE SWEEP HAS TO BRACKET THE CEILING IT IS LOOKING FOR, and it stopped at 6 m. The collocated
	# scheme fails at 4, so 6 was one step past the answer and the list was the right length. A
	# staggered forward-backward update is genuinely symplectic (det = 1 rather than
	# 1 - 4*kappa*sin^4(theta/2)) and its face gradient carries symbol 2i*sin(theta/2)/dx, which is
	# MAXIMAL at theta = pi where the 3-point gradient's sin(theta)/dx vanishes. That moves the
	# limit from kappa <= 0.25 to kappa <= 0.5 in 2D: H_max 3.67 m -> 7.34 m. A sweep ending at 6
	# would report "stable everywhere" and no ceiling at all, which reads as a pass and is a probe
	# that has stopped measuring.
	for depth: float in [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 10.0]:
		lab.get_node("Bed").set("bed_depth", depth)
		lab.call("_rebuild")
		await _reset(lab, false)
		var rest := _snapshot(lab)
		var centre: Vector3 = lab.get_node("Bed").to_global(Vector3.ZERO)
		# Sized to the pan so the test is the same shape at every depth: a tenth of the column.
		_rip.call("splash", centre, 2.0, depth * 0.1)
		var a := PackedFloat32Array()
		for _k in 3:
			await _run(lab, 60)
			a.append(_max_abs_delta(lab, rest))
		var nan_free := _finite(lab)
		# Growth between the second and third window. Below 1 the wave is dying, which is what a
		# stable explicit scheme does; well above it the grid-scale mode is doubling.
		var growth: float = a[2] / maxf(a[1], 1e-9)
		# STABLE MEANS THE DISTURBANCE DID NOT GROW PAST THE ONE THAT WAS PUT IN, and the ratio
		# between two consecutive samples is not that test.
		#
		# It used to be `growth < 1.05`, which reads a sloshing wave as an instability. A closed box
		# with no diffusion does not decay monotonically - the splash crosses, reflects and returns,
		# so consecutive samples wander up and down by tens of per cent while the amplitude is
		# plainly falling. Measured on the staggered scheme at 4 m: 0.043 -> 0.027 -> 0.031, growth
		# 1.14, flagged GROWING, against a splash of 0.40 m. It had decayed by a factor of thirteen.
		# The collocated scheme passed the same test only because its Laplacian was damping the
		# ringing, so the criterion was quietly measuring the diffusion rather than the stability.
		#
		# The honest test is against the STIMULUS: an explicit scheme past its limit does not wander
		# a few per cent, it doubles every few steps and ends orders of magnitude above whatever was
		# poked in. At 8 m the same run reads 10.8 m against a 0.80 m splash.
		var amp := depth * 0.1
		var stable := nan_free and a[2] < amp and a[2] < depth and growth < 2.0
		print("[LAB] 8. depth %.1f m (kappa %.3f): deviation %.4f -> %.4f -> %.4f, growth %.2f  %s"
				% [depth, 9.81 * depth * dt * dt / (dx * dx), a[0], a[1], a[2], growth,
				"stable" if stable else ("NaN" if not nan_free else "GROWING")])
		if stable:
			last_stable = depth
		elif first_unstable == 0.0:
			first_unstable = depth
	print("[LAB] 8. measured: stable to %.1f m, first failure at %.1f m (theory %.2f m)"
			% [last_stable, first_unstable, predicted])
	# The theory is only useful if it predicts the measurement. A ceiling that sits a whole
	# doubling away from 0.25*dx^2/(g*dt^2) means the stability argument is about a scheme we are
	# not running, and every RES decision made from it is guesswork.
	#
	# WHEN THE SCHEME GOES STAGGERED, `predicted` must change to 0.5*dx^2/(g*dt^2) WITH it. The
	# tolerance below is a factor of two either way, so it would quietly pass against the wrong
	# constant - which is the failure mode this assertion exists to prevent, applied to itself.
	if first_unstable > 0.0 and (first_unstable < predicted * 0.5
			or last_stable > predicted * 2.0):
		print("[LAB]    FAIL: the measured ceiling does not match the CFL formula")
		_fail += 1
	lab.get_node("Bed").set("bed_depth", 0.55)
	lab.call("_rebuild")
	_rip.call("sim_set", &"seep", seep_was)
	_rip.call("sim_set", &"cfl_guard", true)
	_rip.set("depth_mode", false)
	_rip.set("edge_mode", 0)


## No NaN anywhere in the state. An unstable explicit scheme reaches it within a few hundred steps,
## and once it does every other reading is meaningless.
## HAS THE SOLVER BLOWN UP? Returns "" if not, or a description of the worst offender.
##
## THIS USED TO TEST is_nan AND is_inf, AND THIS SOLVER NEVER PRODUCES EITHER. The state lives in
## an RGBA16F texture, and float16 SATURATES: its largest finite value is 65504, so a diverging
## cell climbs to 65504 and stays there forever. It is not NaN, it is not Inf, it passes every
## finiteness test ever written, and it is dead. Suite 8's own output has printed
## "deviation 65500.0000 -> 65504.0000" for as long as it has existed and _finite() called that
## field healthy every time; only a separate `a[2] < depth` clause noticed. A divergence detector
## that cannot detect this solver's divergence is worse than none, because it is trusted.
##
## So the test is PHYSICAL PLAUSIBILITY, not IEEE classification. Nothing on this bench is 100 m
## deep or moving at 100 m/s, and the float16 ceiling is 655 times the first of those - there is no
## overlap between "a wave we care about" and "the state has died", so the bound needs no tuning.
const DIVERGE_H := 100.0
const DIVERGE_U := 100.0


## Fail loudly the moment the state stops being water. Called after every depth-mode section
## EXCEPT suite 8, where blowing up is the measurement rather than the fault.
func _assert_stable(lab: Node, tag: String) -> void:
	var why := _diverged(lab)
	if why == "":
		return
	print("[LAB]    FAIL: %s DIVERGED - %s" % [tag.strip_edges(), why])
	_fail += 1


func _diverged(lab: Node) -> String:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return "no state image"
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, z)
			if is_nan(px.r) or is_nan(px.g) or is_nan(px.b):
				return "NaN at (%d, %d)" % [x, z]
			if is_inf(px.r) or absf(px.r) > DIVERGE_H:
				return "h = %.1f at (%d, %d)%s" % [px.r, x, z,
						"  (float16 saturated)" if px.r >= 65504.0 else ""]
			if absf(px.g) > DIVERGE_U or absf(px.b) > DIVERGE_U:
				return "u = (%.1f, %.1f) at (%d, %d)" % [px.g, px.b, x, z]
	return ""


func _finite(lab: Node) -> bool:
	return _diverged(lab) == ""



## The R channel over the whole window, flat, so a later readback can be differenced against it.
func _snapshot(lab: Node) -> PackedFloat32Array:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	var out := PackedFloat32Array()
	if img == null:
		return out
	out.resize(img.get_width() * img.get_height())
	for z in img.get_height():
		for x in img.get_width():
			out[z * img.get_width() + x] = img.get_pixel(x, z).r
	return out


## The largest absolute change in the R channel since `before` - the "did anything move" figure
## that a volume total cannot give, because equal and opposite cell errors sum to zero.
func _max_abs_delta(lab: Node, before: PackedFloat32Array) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null or before.is_empty():
		return 0.0
	var w := img.get_width()
	var worst := 0.0
	_worst_at = Vector2i(-1, -1)
	for z in img.get_height():
		for x in w:
			var d := absf(img.get_pixel(x, z).r - before[z * w + x])
			if d > worst:
				worst = d
				_worst_at = Vector2i(x, z)
	return worst


## WHERE the worst cell was, so a failure can say more than how big it is.
var _worst_at := Vector2i(-1, -1)


## THE FULL TERM LIST FOR THE CELL THAT MOVED, printed only on failure. The whole reason the depth
## mirror exists: "a cell moved 0.15 m" is a number with no cause in it, and bisecting global knobs
## over six hundred steps to find one is how a week goes. This asks the cell.
func _explain_worst(lab: Node, before: PackedFloat32Array) -> void:
	if _worst_at.x < 0:
		return
	lab.set("_pick", _worst_at)
	lab.call("_read_back")
	lab.call("_inspect")
	var txt := String((lab.get("_report") as RichTextLabel).text)
	# WHERE IT STARTED, and it is the first thing to look at. A cell that ends AT its rest depth
	# after moving a long way did not drift - it was seeded wrong and the solver corrected it,
	# which is a different bug in a different file.
	var img: Image = lab.get("_state_img")
	if img != null and not before.is_empty():
		print("[LAB]    cell %s: h was %.6f at the reset, %.6f now"
				% [_worst_at, before[_worst_at.y * img.get_width() + _worst_at.x],
				img.get_pixel(_worst_at.x, _worst_at.y).r])
	print("[LAB]    the cell that moved, in full:")
	for ln in _plain(txt).split("\n"):
		print("[LAB]      " + ln)
## CELLS THE RESET LEFT DRY THAT THE TERRAIN SAYS ARE UNDER WATER, which _surface_spread cannot
## report by construction: it averages over WET texels, so a basin cell seeded at zero is not in
## its sample at all. A hole is a lake with a bite out of it, and the solver then spends the run
## filling it - which reads as drift in every instrument that watches how much a cell moved.
##
## The test is the solver's own seed formula, max(Y - b, 0), against what the state actually holds.
## THROUGH THE LAB'S OWN BED AND Y, never a copy. Every instrument that reconstructs the terrain
## for itself is a second implementation that can drift from the shader, and the drift shows up as
## a failure in the thing being measured rather than in the ruler. swe_lab's _bed_at and _rest_y_at
## are the mirror's, and suite 7i holds THOSE to the GPU every run.
func _seed_holes(lab: Node) -> String:
	lab.call("_read_back")
	var st: Image = lab.get("_state_img")
	if st == null or lab.get("_bed_img") == null:
		return ""
	var res := st.get_width()
	var h_dry := float(_rip.call("sim_get", &"h_dry"))
	var holes := 0
	var worst := 0.0
	var at := Vector2i(-1, -1)
	for z in res:
		for x in res:
			var w := Vector2i(x, z)
			# _rest_y_at already strips the spring mark, exactly as the shader does.
			var want: float = maxf(float(lab.call("_rest_y_at", w, res))
					- float(lab.call("_bed_at", w, res)), 0.0)
			if want <= h_dry:
				continue
			var got: float = maxf(st.get_pixel(x, z).r, 0.0)
			if got > h_dry:
				continue
			holes += 1
			if want > worst:
				worst = want
				at = Vector2i(x, z)
	if holes == 0:
		return "no seed holes"
	return "SEED HOLES %d texels, deepest %.4f m at %s" % [holes, worst, at]


## The spread of the water SURFACE over every wet texel, which is the only number that says
## whether a lake is at rest. Depth varies over a sloping bed by design; the surface must not.
func _surface_spread(lab: Node) -> String:
	lab.call("_read_back")
	var st: Image = lab.get("_state_img")
	if st == null or lab.get("_bed_img") == null:
		return "no data"
	var res := st.get_width()
	var lo := 1e9
	var hi := -1e9
	var n := 0
	for z in range(0, res, 2):
		for x in range(0, res, 2):
			var h: float = st.get_pixel(x, z).r
			if h <= 0.01:
				continue
			# The lab's bed, not a copy of it - see _seed_holes.
			var w: float = float(lab.call("_bed_at", Vector2i(x, z), res)) + h
			lo = minf(lo, w)
			hi = maxf(hi, w)
			n += 1
	if n == 0:
		return "no wet texels"
	return "surface w in [%.6f, %.6f], spread %.6f m over %d texels" % [lo, hi, hi - lo, n]
## The fastest cell in the window. A lake at rest must have none.
func _max_speed(lab: Node) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	var top := 0.0
	var res := img.get_width()
	for z in range(0, img.get_height(), 2):
		for x in range(0, res, 2):
			# Through the lab's own face-to-centre helper: staggered, G and B are FACE values and
			# reading them straight reports a velocity half a texel from where it is.
			top = maxf(top, (lab.call("_vel_at", Vector2i(x, z), res) as Vector2).length())
	return top


func _min_h(lab: Node) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	var lo := 1e9
	for z in img.get_height():
		for x in img.get_width():
			lo = minf(lo, img.get_pixel(x, z).r)
	return lo


# ------------------------------------------------------------------------------ instruments ---

## The state texture side, read off the live image rather than assumed.
func _res(lab: Node) -> int:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	return img.get_width() if img != null else 512


func _eta_at(lab: Node, at: Vector2i) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	return img.get_pixel(at.x, at.y).r


## Square metres carrying the spring mark, straight off the terrain field. Each field texel is
## exactly one metre square — that is why the window origin snaps to whole metres — so a count IS
## an area: no calibration, and it follows the source if the source moves.
func _spring_area() -> float:
	var img: Image = (_rip.call("field_texture") as Texture2D).get_image()
	var mark := float(_rip.get("SPRING_MARK")) * 0.5
	var n := 0
	for z in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, z).a > mark:
				n += 1
	return float(n)


## Four cells worth putting the mirror on, scanning +x from the window centre: the deepest, one
## about half as deep, and the last wet cell and first dry cell at the waterline. Returns whatever
## it can find - a probe that skips a pick it could not locate is better than one that asserts
## against a cell that is not there.
func _mirror_picks(lab: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return out
	var res := img.get_width()
	var mid := res / 2
	var h_dry := 0.002
	var deepest := maxf(img.get_pixel(mid, mid).r, 0.0)
	out.append(Vector2i(mid, mid))
	var half := -1
	var last_wet := -1
	for x in range(mid, res):
		var hh := maxf(img.get_pixel(x, mid).r, 0.0)
		if half < 0 and hh <= deepest * 0.5:
			half = x
		if hh > h_dry:
			last_wet = x
		elif last_wet >= 0:
			break
	if half > mid:
		out.append(Vector2i(half, mid))
	if last_wet > mid:
		out.append(Vector2i(last_wet, mid))
		if last_wet + 1 < res:
			out.append(Vector2i(last_wet + 1, mid))
	return out


func _reset(lab: Node, empty: bool) -> void:
	await lab.call("_reset", empty)
	await _run(lab, 2)


## Step the solver by hand. The lab pauses itself, so nothing advances without being asked — which
## is exactly what makes a probe over it repeatable.
func _run(lab: Node, steps: int) -> void:
	for _i in steps:
		lab.call("_feed_sink", 1)
		_rip.call("step_once")
		await process_frame
	lab.call("_read_back")


func _vol(lab: Node) -> float:
	lab.call("_read_back")
	return float(lab.get("_volume"))


## Strip BBCode, so the panel's own coloured report reads as plain text in a console log.
func _plain(bb: String) -> String:
	var out := ""
	var depth := 0
	for ch in bb:
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth -= 1
		elif depth == 0:
			out += ch
	return out
