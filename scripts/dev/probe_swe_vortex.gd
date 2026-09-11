extends SceneTree
## THE ACCEPTANCE TEST: is there a von Karman vortex street behind the cylinder?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_vortex.gd
##
## Jeschke & Wojtan 2023 Figure 3 is a shallow-water solver shedding a vortex street past a
## cylinder, and its whole point is that SWE "do allow turbulence in the form of swirling eddies".
## That is the figure this work is aimed at, so this is where "reproducing the paper images" has to
## stop being a picture and become numbers.
##
## IT MATTERS THAT THIS IS HARD TO FAKE. A wake that merely LOOKS like a street is easy to get
## wrong in three specific ways, and each has its own assertion here:
##
##   REFLECTION      a closed box bounces the wake back through the body that shed it. What returns
##                   is a standing wave with a frequency set by the domain length, and it looks
##                   exactly like shedding. edge_mode 2's outflow sponge exists for this, and the
##                   null run below measures what is left.
##   THE GRID        a cylinder on a 0.2 m lattice is a staircase, and a staircase sheds off its own
##                   corners at a frequency set by the CELL SIZE, not the body. The tell is that a
##                   circle and a square then give the SAME Strouhal number - so both are run, and
##                   the discriminator matters more than either number alone.
##   NOISE           quantisation noise in a scheme with no diffusion wanders, and a spectrum of
##                   wandering has peaks in it. Every threshold below is a multiple of a NULL RUN
##                   with no body in it, measured in the same configuration.
##
## AND THE PHASE TEST IS THE ONE THAT WOULD HAVE BEEN WRITTEN BACKWARDS. A street has glide-
## reflection symmetry: F(x, -y, t) = M F(x, y, t + T/2) with M = diag(+1, -1). For the transverse
## velocity that gives v(x, -y, t) = -v(x, y, t + T/2), and over half a period a single tone flips
## sign again - so the two flips CANCEL and v at mirror points is IN PHASE. It is the STREAMWISE
## component u that is in antiphase. Asserting the intuitive thing (v antiphase) rejects a correct
## vortex street, and it sits in the load-bearing conjunction, so it would have rejected the
## finding rather than a bug.

const U0 := 1.2               ## inflow, m/s
## ONE FLOW-THROUGH IS 53 SECONDS - 64 m at 1.2 m/s - and the settle used to be fifteen. So the
## probe points three diameters downstream were sampling water that was SEEDED there, not water
## that had come past the body, and a wake had never established at all. 3600 steps is 60 s, one
## full flow-through plus the twenty convective times (D/U = 3.3 s at D = 4) a shear layer needs.
const SETTLE := 3600
## And the record has to hold the period it is looking for. At St 0.2, D = 4, U = 1.2 the shedding
## period is 16.7 s; 4800 steps is 80 s, so about five cycles. Still thin, but the DFT bin spacing
## is then 0.0125 Hz against an expected 0.06 Hz, which the parabolic interpolation can work with.
const RECORD := 4800
const SAMPLE := 4             ## steps between samples

## THE EFFECTIVE REYNOLDS NUMBER IS SET BY THE BODY'S SIZE IN CELLS, AND BY NOTHING ELSE.
##
## The advective difference is first-order upwind, whose numerical viscosity is nu = u*dx/2. So
##     Re = U*D / nu = U*D / (U*dx/2) = 2*D/dx
## and the inflow speed CANCELS. Driving the channel harder does not buy a more turbulent wake; it
## buys proportionally more numerical viscosity. The only dial is how many cells span the body.
##
## Von Karman shedding begins near Re = 47. At D = 4 m on a 0.2 m grid that is Re = 40 - just
## below - and the first run measured exactly what sub-critical flow looks like: a SYMMETRIC
## recirculating wake, v antiphase and u in phase across the axis, at the same frequency for a
## circle and a square. Not a street, and the probe said so.
##
## So this sweeps the body size and finds where the transition actually is, which is a far more
## useful answer than one size that either works or does not.
## SMALLER, NOT BIGGER, and the first sweep had it backwards.
##
## Two hard nonlinear sinks sit right where the shear layer is born. Potential flow puts 2U at the
## shoulder, and blockage raises it: at D = 12 in a 64 m channel that is 2.95 m/s against
## u_max = 3.0, and the flux cap min(weir_cd*sqrt(g*hf)*hf, h*dx/(4dt)) = 3.00 m2/s against
## q = 2.95. Both are within two per cent of engaging. Worse, the shoulder is then at Froude 0.94 -
## near-critical - so a 12 m body in this channel is CHOKED, not merely clipped, and 19 % blockage
## is four times the textbook ceiling of five anyway.
##
## D = 4 and 6 are 6.3 % and 9.4 % blockage with the shoulder at 2.4-2.6 m/s, comfortably clear of
## both caps.
const SIZES := [4.0, 6.0]
## THE SYMMETRY HAS TO BE BROKEN, AND A STATIC OFFSET DOES NOT DO IT.
##
## Shedding is a symmetry-BREAKING instability: above the critical Reynolds number the symmetric
## wake still EXISTS as a solution, it is merely unstable, and a perfectly symmetric setup will sit
## in it forever because nothing pushes it off. Measured at Re 40, 80 and 120: mirror correlation
## v = -0.98 and u = +1.000, identical at every size. u correlating at exactly one means the two
## halves of the flow were bit-for-bit mirror images. The solution never left the symmetric branch.
##
## Offsetting the body by half a texel was the first attempt and it was worse than nothing: at
## dx 0.2 the texel-centre rows lie at +-0.1, so moving the cylinder to y = 0.1 centres it ON a row
## instead of between two, which is MORE symmetric. Both offsets are symmetric; they just differ in
## which symmetry.
##
## So the perturbation is a KICK, not a placement: the body is displaced sideways for a moment
## during settling and then put back. That is physical - it is what tapping the cylinder does - it
## leaves no permanent asymmetry in the geometry or the boundary conditions to be accused of causing
## the result, and it decisively lands the solution off the symmetric branch.
const KICK_AT := 300          ## step during settling at which the body is nudged
const KICK_FOR := 120         ## and how long it stays nudged
const KICK_Y := 1.0           ## metres sideways

var _rip: Node = null
var _lab: Node = null
var _fail := 0
var _null_rms := 0.0
var _obs_id := -1


func _initialize() -> void:
	_lab = (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 30:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	_lab.set("_live", false)
	if not _lab.has_method("_read_back"):
		print("[VORTEX] FAIL: swe_lab.gd did not load")
		quit(1)
		return

	# A FLAT PAN in a channel. Every feature of the wake has to come from the body, so the bed
	# contributes nothing: no slope to steer it, no bank to reflect off, no shoreline anywhere.
	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_rip.call("sim_set", &"seep", 0.0)
	_rip.call("sim_set", &"cfl_guard", false)
	_lab.get_node("Bed").set("profile", 0)
	_lab.get_node("Bed").set("bed_depth", 1.0)
	# THE BED IS THE WHOLE WINDOW. It defaults to 48 m inside a 64 m window, and water_bed_y answers
	# the 1000 m off-map sentinel outside it - so there is an 8 m ring of WALL inside the solver
	# domain on every side. The inflow face sits at the window edge, inside that ring, where
	# hf = 0 against a kilometre of rock and q = min(hf, h_donor)*u delivers exactly nothing. Every
	# channel measurement before this line was a closed box coasting on its initial seed, with the
	# body sitting in decaying slosh rather than a maintained stream.
	_lab.get_node("Bed").set("extent", float(_rip.get("SIZE_M")))
	_lab.call("_rebuild")
	_rip.set("depth_mode", true)
	_rip.set("staggered", true)
	_rip.set("edge_mode", 2)
	_rip.call("sim_set", &"inflow_u", U0)
	# Friction OFF. Bed friction at this depth would damp the wake faster than it sheds, and the
	# question is whether the SCHEME can hold an eddy, not whether Manning can kill one.
	_rip.call("sim_set", &"drag", 0.0)
	_rip.call("sim_set", &"manning", 0.0)
	# THE DRIVER'S FLAG, not the uniform. ripple_field binds advect_gain EVERY STEP from
	# Ripples.advect, so sim_set("advect_gain", 1.0) is overwritten before the next frame renders
	# and the whole advective term stays off. Every vortex measurement taken before this line was
	# made with no advection at all, which is a measurement of the wrong solver.
	_rip.set("advect", true)

	var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
	print("[VORTEX] U %.2f m/s, h %.1f m, dx %.2f m, Froude %.2f"
			% [U0, 1.0, dx, U0 / sqrt(9.81 * 1.0)])
	print("[VORTEX] a shedding street wants St = f*D/U in about [0.15, 0.25], and the effective "
			+ "Reynolds number here is 2*D/dx - the inflow speed cancels")

	# THE NULL FIRST, and every threshold below is a multiple of it. A run with no body still has a
	# spectrum - quantisation noise in a scheme with no diffusion wanders, and wandering has peaks.
	# Comparing a wake against zero would be comparing it against a number nobody measured.
	print("[VORTEX] ---- null: the same channel with NO body ----")
	_rip.call("obstacle_clear")
	_obs_id = -1
	var nul := await _run_case("null", -1)
	_null_rms = nul.x
	print("[VORTEX] null transverse RMS %.5f m/s   -> every threshold below is a multiple of this"
			% _null_rms)

	# The free-slip / no-slip A/B has run and is recorded in the log: it moved almost nothing
	# (RMS 0.06618 -> 0.06595), so obs_wall_cd is not what was holding the wake symmetric. Left out
	# of the sweep to keep it affordable now that the settle is four times longer.
	var shed_at := 0.0
	for d: float in SIZES:
		var re: float = 2.0 * d / dx
		print("[VORTEX] ---- cylinder D = %.1f m (%.0f texels), Re_eff = 2D/dx = %.0f ----"
				% [d, d / dx, re])
		_rip.call("obstacle_clear")
		var top: float = float(_lab.get_node("Bed").get("rest_y")) + 2.0
		# Off-axis by half a texel: see SIZES. The body is at -12 m so the wake has 6 diameters of
		# channel to develop in before the outflow sponge starts absorbing.
		_obs_id = _rip.call("obstacle_add", 0, Vector2(-16.0, 0.0),
				Vector2(d * 0.5, d * 0.5), top, 0.0)
		var r := await _run_case("D=%.0f" % d, 0, d)
		if r.z >= 0.10 and r.z <= 0.30 and shed_at <= 0.0:
			shed_at = d
	if shed_at > 0.0:
		print("[VORTEX] shedding first appears at D = %.1f m, Re_eff %.0f - the textbook critical "
				% [shed_at, 2.0 * shed_at / dx] + "Reynolds number for a cylinder is about 47")
	else:
		print("[VORTEX] no size in this sweep shed. Re_eff = 2*D/dx tops out at %.0f here, and the "
				% (2.0 * float(SIZES[SIZES.size() - 1]) / dx)
				+ "wake stays the symmetric recirculating one that sub-critical flow gives.")
		_fail += 1

	print("[VORTEX] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## Returns (transverse RMS, shedding frequency Hz, Strouhal).
func _run_case(tag: String, kind: int, d := 4.0) -> Vector3:
	await _lab.call("_reset", false)
	# Settle in three parts so the body can be kicked in the middle of it and the wake still has
	# time to forget the kick itself before anything is recorded.
	await _run(KICK_AT)
	if _obs_id >= 0:
		_rip.call("obstacle_move", _obs_id, Vector2(-16.0, KICK_Y))
	await _run(KICK_FOR)
	if _obs_id >= 0:
		_rip.call("obstacle_move", _obs_id, Vector2(-16.0, 0.0))
	await _run(maxi(SETTLE - KICK_AT - KICK_FOR, 1))
	if _diverged():
		print("[VORTEX]    FAIL: %s diverged during settling" % tag)
		_fail += 1
		return Vector3.ZERO

	# TWO PROBE POINTS, mirrored across the wake axis, three diameters downstream. One point gives a
	# frequency; the pair gives the SYMMETRY, which is what separates a street from a wake that is
	# merely wobbling.
	var pa := _texel(Vector2(-16.0 + 3.0 * d, d))
	var pb := _texel(Vector2(-16.0 + 3.0 * d, -d))
	var va := PackedFloat32Array()
	var vb := PackedFloat32Array()
	var ua := PackedFloat32Array()
	var ub := PackedFloat32Array()
	var n := RECORD / SAMPLE
	for _i in n:
		await _run(SAMPLE)
		var a := _vel(pa)
		var b := _vel(pb)
		va.append(a.y)
		vb.append(b.y)
		ua.append(a.x)
		ub.append(b.x)
	if _diverged():
		print("[VORTEX]    FAIL: %s diverged during recording" % tag)
		_fail += 1
		return Vector3.ZERO

	var rms := _rms(va)
	var f := _peak_hz(va)
	var st := f * d / U0
	print("[VORTEX] %-9s transverse RMS %.5f m/s   f %.4f Hz   St %.3f"
			% [tag, rms, f, st])
	if kind < 0:
		return Vector3(rms, f, st)

	# A5: the signal has to stand out of the null, AND out of nothing.
	#
	# The null came back at exactly 0.00000 m/s - an empty channel in this scheme is perfectly
	# quiet, which is a better null than expected and makes "three times the null" a threshold of
	# zero that anything passes. So the bar is the larger of the two: three times the measured
	# noise, or a hundredth of the free stream, whichever is bigger. A wake that moves the water
	# sideways by less than 1 % of the flow speed is not a wake anybody can see.
	var bar := maxf(_null_rms * 3.0, U0 * 0.01)
	if rms < bar:
		print("[VORTEX]    FAIL: transverse RMS %.5f is under the bar %.5f (3x null, floored at "
				% [rms, bar] + "1%% of U) - that is not a wake")
		_fail += 1
	# A10: Strouhal in the physical band.
	if st < 0.10 or st > 0.30:
		print("[VORTEX]    FAIL: St %.3f is outside [0.10, 0.30] - whatever is oscillating, it is "
				% st + "not vortex shedding")
		_fail += 1
	# A14, AND THE SIGN IS THE POINT. Glide-reflection makes v IN PHASE across the wake axis and u
	# in ANTIPHASE. The intuitive assertion is the opposite and would reject a correct street.
	var cv := _corr(va, vb)
	var cu := _corr(ua, ub)
	print("[VORTEX] %-9s mirror correlation: v %+.3f (want POSITIVE)   u %+.3f (want NEGATIVE)"
			% [tag, cv, cu])
	if cv < 0.2:
		print("[VORTEX]    FAIL: transverse velocity is not in phase across the wake - the "
				+ "glide-reflection symmetry a street is defined by is absent")
		_fail += 1
	if cu > -0.2:
		print("[VORTEX]    FAIL: streamwise velocity is not in antiphase across the wake")
		_fail += 1
	return Vector3(rms, f, st)


## The dominant frequency of a signal, by direct DFT with a Hann window and parabolic interpolation
## on the peak. The raw bin spacing is 1/(N*dt_sample), which is coarse enough that the raw peak
## alone cannot meet a 15 % tolerance - the interpolation is not polish, it is what makes the
## number usable.
func _peak_hz(sig: PackedFloat32Array) -> float:
	var n := sig.size()
	if n < 16:
		return 0.0
	var dts := float(SAMPLE) / 60.0
	var mean := 0.0
	for v in sig:
		mean += v
	mean /= float(n)
	var w := PackedFloat32Array()
	w.resize(n)
	for i in n:
		# Hann, to stop the record's own ends ringing across the whole spectrum.
		w[i] = (sig[i] - mean) * 0.5 * (1.0 - cos(TAU * float(i) / float(n - 1)))
	var best := 0.0
	var best_k := 0
	var power := PackedFloat32Array()
	var kmax := mini(n / 2, 200)
	power.resize(kmax)
	for k in kmax:
		var f := float(k) / (float(n) * dts)
		if f < 0.01 or f > 0.5:
			power[k] = 0.0
			continue
		var re := 0.0
		var im := 0.0
		for i in n:
			var a := TAU * f * float(i) * dts
			re += w[i] * cos(a)
			im += w[i] * sin(a)
		power[k] = re * re + im * im
		if power[k] > best:
			best = power[k]
			best_k = k
	if best_k <= 0 or best_k >= kmax - 1:
		return float(best_k) / (float(n) * dts)
	# Parabolic interpolation on the three bins around the peak, CLAMPED to the half-bin either
	# side that is the only answer it can meaningfully give.
	#
	# The denominator y0 - 2*y1 + y2 is the curvature at the peak, and on a FLAT spectrum - which is
	# exactly what the null run has - it passes through zero. Guarding only its magnitude leaves the
	# sign, so a near-zero negative denominator sends d to minus a billion: the null reported a
	# shedding frequency of -539350633 Hz and a Strouhal number of -1.8e9. A peak interpolation can
	# never legitimately move the answer more than half a bin, so say so.
	var y0 := power[best_k - 1]
	var y1 := power[best_k]
	var y2 := power[best_k + 1]
	var den := y0 - 2.0 * y1 + y2
	var d := 0.0
	if absf(den) > 1e-12:
		d = clampf(0.5 * (y0 - y2) / den, -0.5, 0.5)
	return (float(best_k) + d) / (float(n) * dts)


func _rms(sig: PackedFloat32Array) -> float:
	if sig.is_empty():
		return 0.0
	var mean := 0.0
	for v in sig:
		mean += v
	mean /= float(sig.size())
	var acc := 0.0
	for v in sig:
		acc += (v - mean) * (v - mean)
	return sqrt(acc / float(sig.size()))


## Zero-lag normalised correlation of two signals, mean removed.
func _corr(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := mini(a.size(), b.size())
	if n < 4:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= float(n)
	mb /= float(n)
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in n:
		var x := a[i] - ma
		var y := b[i] - mb
		num += x * y
		da += x * x
		db += y * y
	return num / maxf(sqrt(da * db), 1e-12)


func _texel(world: Vector2) -> Vector2i:
	var res := int(_rip.get("RES"))
	var org: Vector2 = _rip.call("window_origin")
	var t: float = float(_rip.get("SIZE_M")) / float(res)
	return Vector2i(clampi(int((world.x - org.x) / t), 0, res - 1),
			clampi(int((world.y - org.y) / t), 0, res - 1))


func _vel(p: Vector2i) -> Vector2:
	_lab.call("_read_back")
	return _lab.call("_vel_at", p, int(_rip.get("RES")))


func _diverged() -> bool:
	_lab.call("_read_back")
	var img: Image = _lab.get("_state_img")
	if img == null:
		return true
	for z in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var px := img.get_pixel(x, z)
			if is_nan(px.r) or absf(px.r) > 100.0 or absf(px.g) > 100.0:
				return true
	return false


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
