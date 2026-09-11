extends SceneTree
## WHAT THE SCHEME CAN AND CANNOT HOLD, measured against the scheme we have.
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_scheme.gd
##
## probe_swe_lab asks whether the solver is CORRECT: does a lake stay level, is mass conserved,
## where is the stability ceiling. Everything in it is green. probe_swe_long asks whether it stays
## correct for a hundred seconds. Also green, except one number.
##
## Neither of them asks whether it is the RIGHT SCHEME, and that is the open question. The
## references both discretise the shallow water equations on a STAGGERED grid with an advective
## momentum flux; this solver is collocated with no advective term at all. Those two differences
## have consequences that are provable rather than arguable, and this file measures them - so that
## when the scheme changes there is a before to compare the after against.
##
## IT MOSTLY DOES NOT ASSERT. A baseline that fails is not a regression, it is the starting point.
## Only the seeds themselves are checked, because a probe whose stimulus silently did not happen
## reports the absence of an effect and looks like a result.
##
## FOUR QUESTIONS:
##
##   CIRCULATION   can the solver hold a vortex? The real equations conserve circulation in the
##                 absence of friction. This one has no advective term, so the curl of its momentum
##                 update is the curl of a gradient, which is identically zero: vorticity can only
##                 decay. Expected result - decay at exactly the drag rate and no slower.
##   CHECKERBOARD  the k*dx = pi mode. A 3-point (i+1)-(i-1) gradient has an eigenvalue of exactly
##                 zero there, so on a collocated grid this mode has no restoring force. Whether it
##                 decays at all is down to the compact Laplacian, which is also the term that
##                 diffuses the centimetre-scale signal a shoaling wave is made of.
##   MOMENTUM      sum(h*u) in a closed box with the friction off. Never measured. It is the
##                 quantity the staggered rewrite is FOR, so its present value is worth writing
##                 down before anything moves.
##   ENERGY        kinetic plus potential, same run. A scheme that loses energy with drag off is
##                 diffusive; one that gains it is on its way to blowing up. This is the number
##                 that says which of the two the Laplacian is doing.

const CENTRE := Vector2(0.5, 0.5)

var _rip: Node = null
var _lab: Node = null
var _fail := 0


func _initialize() -> void:
	_lab = (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 30:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	_lab.set("_live", false)
	if not _lab.has_method("_read_back"):
		print("[SCHEME] FAIL: swe_lab.gd did not load")
		quit(1)
		return
	# A FLAT PAN throughout. Every question here is about the SCHEME, and a sloping or stepped bed
	# adds a second cause to every answer. The bed is the subject of a different stage.
	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_rip.call("sim_set", &"seep", 0.0)
	_lab.get_node("Bed").set("profile", 0)
	_lab.call("_rebuild")
	var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
	print("[SCHEME] grid %d, dx %.3f m, dt %.5f s, flat pan"
			% [int(_rip.get("RES")), dx, 1.0 / 60.0])

	# BOTH SCHEMES, IN ONE PROCESS. The whole case for the staggered rewrite is that the collocated
	# grid needs a compact Laplacian at the grid scale and that the Laplacian is a diffusion of the
	# free surface - so the number that decides whether the rewrite was worth doing is the ENERGY
	# these two lose with the friction switched off. Measured against each other in the same run,
	# not against a remembered figure.
	for staggered in [false, true]:
		_rip.set("staggered", staggered)
		print("[SCHEME] ======== %s ========"
				% ("STAGGERED (faces, no stabiliser)" if staggered
				else "collocated (cell centres, compact Laplacian)"))
		await _circulation()
		await _checkerboard()
		await _budget()
	_rip.set("staggered", false)

	print("[SCHEME] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## CAN IT HOLD A VORTEX? Seed a Gaussian-cored swirl and measure the circulation on a fixed ring
## around it. Twice: with the semi-Lagrangian advection path off, which is how the solver ships,
## and with it on, which is the only transport it currently has.
##
## The ring is FIXED IN SPACE and larger than the core, so it measures the vortex's total strength
## rather than following the part of it that happens to survive.
func _circulation() -> void:
	var drag := float(_rip.call("sim_get", &"drag"))
	print("[SCHEME] --- circulation, drag %.3f (half-life %.2f s) ---" % [drag, log(2.0) / drag])
	for advect in [false, true]:
		_rip.set("advect", advect)
		await _seed(1, Vector4(CENTRE.x, CENTRE.y, 0.08, 0.60))
		var g0 := _gamma(0.12)
		if absf(g0) < 1e-3:
			print("[SCHEME]    FAIL: the vortex seed produced no circulation - the stimulus did "
					+ "not happen, so nothing below means anything")
			_fail += 1
			return
		var line := "[SCHEME] C. advect %-3s  Gamma m2/s at t=0,1,2,5 s: %+.4f" \
				% ["on" if advect else "off", g0]
		var prev := 0
		for t in [60, 120, 300]:
			await _run(t - prev)
			prev = t
			line += "  %+.4f" % _gamma(0.12)
		# The number to compare against: pure drag would leave exp(-drag*t) of it.
		line += "   (pure drag at 5 s would leave %+.4f)" % (g0 * exp(-drag * 5.0))
		print(line)
	_rip.set("advect", false)


## THE MODE A COLLOCATED GRID CANNOT SEE. Seed h alternating every texel and watch the amplitude.
## If it decays, something is restoring it and that something is the compact Laplacian; if it sits
## there, the scheme has a null space and the shoreline signal is competing with a mode that never
## goes away.
func _checkerboard() -> void:
	print("[SCHEME] --- checkerboard, the k*dx = pi mode ---")
	# The seed is QUANTISED BY THE STORE on the way in: at h ~ 0.86 m one float16 ulp is 0.49 mm,
	# so a 1 mm request lands as 2 ulp. That is fine - it is the mode that matters, not the size -
	# but the number printed at step 0 is the seed the solver got, not the seed asked for.
	await _seed(2, Vector4(CENTRE.x, CENTRE.y, 0.1, 0.001))
	var a0 := _checker_amp()
	if a0 < 1e-5:
		print("[SCHEME]    FAIL: the checkerboard seed produced no alternation")
		_fail += 1
		return
	var line := "[SCHEME] K. amplitude mm at step 0,2,5,15,30,60: %.4f" % (a0 * 1000.0)
	var prev := 0
	for t in [2, 5, 15, 30, 60]:
		await _run(t - prev)
		prev = t
		line += "  %.4f" % (_checker_amp() * 1000.0)
	print(line)
	# With the Laplacian off there is nothing left to restore this mode at all, which is what
	# turns a claim about a null space into a measurement.
	var g_was: Variant = _rip.call("sim_get", &"gravity")
	_rip.call("sim_set", &"gravity", 0.0)
	await _seed(2, Vector4(CENTRE.x, CENTRE.y, 0.1, 0.001))
	var b0 := _checker_amp()
	await _run(60)
	print("[SCHEME] K. gravity 0 (no Laplacian, no pressure): %.4f -> %.4f mm in 60 steps"
			% [b0 * 1000.0, _checker_amp() * 1000.0])
	_rip.call("sim_set", &"gravity", g_was)


## MOMENTUM AND ENERGY over one splash in a closed box, with drag and Manning switched off so the
## only losses left are the scheme's own.
func _budget() -> void:
	var drag_was: Variant = _rip.call("sim_get", &"drag")
	var mann_was: Variant = _rip.call("sim_get", &"manning")
	_rip.call("sim_set", &"drag", 0.0)
	_rip.call("sim_set", &"manning", 0.0)
	print("[SCHEME] --- momentum and energy, drag 0, Manning 0, closed box ---")
	await _seed(0, Vector4(CENTRE.x, CENTRE.y, 0.1, 0.0))
	var centre: Vector3 = _lab.get_node("Bed").to_global(Vector3.ZERO)
	_rip.call("splash", centre, 3.0, 0.20)
	await _run(1)
	var b := _budget_now()
	print("[SCHEME] M. on impact:      |sum h*u| %.5f m3/s   E %.4f J/rho   volume %.3f m3"
			% [b.x, b.y, b.z])
	var prev := 1
	for t in [60, 180, 600]:
		await _run(t - prev)
		prev = t
		var n := _budget_now()
		print("[SCHEME] M. step %4d:      |sum h*u| %.5f m3/s   E %.4f (%+.2f%%)   volume %.3f"
				% [t, n.x, n.y, (n.y - b.y) / maxf(b.y, 1e-9) * 100.0, n.z])
	_rip.call("sim_set", &"drag", drag_was)
	_rip.call("sim_set", &"manning", mann_was)


# ------------------------------------------------------------------------ instruments ----------

## Circulation on a ring of radius r (in window fractions) about CENTRE: Gamma = closed integral of
## u . dl. Sampled at 256 points, bilinearly, which is finer than the texel the field is stored on.
func _gamma(r_uv: float) -> float:
	var img: Image = _state(true)
	if img == null:
		return 0.0
	var size: float = float(_rip.get("SIZE_M"))
	var r_m := r_uv * size
	var n := 256
	var total := 0.0
	for i in n:
		var a := TAU * float(i) / float(n)
		var uv := CENTRE + Vector2(cos(a), sin(a)) * r_uv
		var u := _u_at(img, uv)
		total += (u.x * -sin(a) + u.y * cos(a))
	return total * TAU * r_m / float(n)


## The amplitude of the alternating component of h over the middle of the window: the mean of
## |h - (mean of the four neighbours)| / 2, which is exactly the checkerboard's amplitude when the
## field IS a checkerboard and near zero for anything smooth.
func _checker_amp() -> float:
	var img: Image = _state(true)
	if img == null:
		return 0.0
	var res := img.get_width()
	var total := 0.0
	var n := 0
	for z in range(res / 4, res * 3 / 4, 2):
		for x in range(res / 4, res * 3 / 4, 2):
			var c := img.get_pixel(x, z).r
			var nb := (img.get_pixel(x + 1, z).r + img.get_pixel(x - 1, z).r
					+ img.get_pixel(x, z + 1).r + img.get_pixel(x, z - 1).r) * 0.25
			total += absf(c - nb) * 0.5
			n += 1
	return total / maxf(float(n), 1.0)


## (|sum h*u| in m3/s, energy per unit density in J/rho, volume in m3) over the whole window.
##
## ENERGY is kinetic plus potential: 0.5*h*|u|^2 + 0.5*g*(w - w_rest)^2, integrated. The potential
## term is measured against the REST SURFACE rather than the bed, because a lake at rest has to
## come out at zero or the number is dominated by a constant nobody cares about.
func _budget_now() -> Vector3:
	var img: Image = _state(true)
	var bed: Image = _lab.get("_bed_img")
	if img == null or bed == null:
		return Vector3.ZERO
	var res := img.get_width()
	var fres := bed.get_width()
	var size: float = float(_rip.get("SIZE_M"))
	var area := (size / float(res)) * (size / float(res))
	var g: float = _rip.get("GRAVITY")
	# The rest surface of a flat pan is flat, so the mean surface is the right datum and needs no
	# terrain query - and using the field's own mean keeps this honest if the pan is ever tilted.
	var mom := Vector2.ZERO
	var ke := 0.0
	var vol := 0.0
	var wsum := 0.0
	var wn := 0
	for z in range(0, res, 2):
		for x in range(0, res, 2):
			var h: float = maxf(img.get_pixel(x, z).r, 0.0)
			if h <= 0.0:
				continue
			var fx := clampi(int((float(x) + 0.5) / float(res) * float(fres)), 0, fres - 1)
			var fz := clampi(int((float(z) + 0.5) / float(res) * float(fres)), 0, fres - 1)
			wsum += bed.get_pixel(fx, fz).r + h
			wn += 1
	var w_rest := wsum / maxf(float(wn), 1.0)
	for z in range(0, res, 2):
		for x in range(0, res, 2):
			var px := img.get_pixel(x, z)
			var h: float = maxf(px.r, 0.0)
			if h <= 0.0:
				continue
			var u: Vector2 = _lab.call("_vel_at", Vector2i(x, z), res)
			var a4 := area * 4.0
			mom += h * u * a4
			ke += 0.5 * h * u.length_squared() * a4
			vol += h * a4
			var fx := clampi(int((float(x) + 0.5) / float(res) * float(fres)), 0, fres - 1)
			var fz := clampi(int((float(z) + 0.5) / float(res) * float(fres)), 0, fres - 1)
			var d := bed.get_pixel(fx, fz).r + h - w_rest
			ke += 0.5 * g * d * d * a4
	return Vector3(mom.length(), ke, vol)


## u at a window uv, bilinearly from the state's G and B channels.
## u at a window uv, bilinearly, from CELL-CENTRED velocities - which under the staggered layout
## have to be reconstructed from the faces first. Reading G and B straight there is a half-texel
## error in each direction, and on a circulation integral that is not noise: it rotates the sampled
## field slightly against the ring it is integrated on, so Gamma comes out systematically low and
## the answer to "can this scheme hold a vortex" is biased by the instrument.
func _u_at(img: Image, uv: Vector2) -> Vector2:
	var n := img.get_width()
	var t := uv * float(n) - Vector2(0.5, 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var fr := t - Vector2(i0)
	var acc := Vector2.ZERO
	for dz in 2:
		for dx in 2:
			var p := Vector2i(clampi(i0.x + dx, 0, n - 1), clampi(i0.y + dz, 0, n - 1))
			var w := (fr.x if dx == 1 else 1.0 - fr.x) * (fr.y if dz == 1 else 1.0 - fr.y)
			acc += (_lab.call("_vel_at", p, n) as Vector2) * w
	return acc


# -------------------------------------------------------------------------- harness ------------

## Reset with one of the bench seeds, then put the seed back to plain still water so nothing later
## re-seeds by accident. The seed uniform is consumed by the reset steps inside _reset.
func _seed(kind: int, p: Vector4) -> void:
	_rip.call("sim_set", &"seed_kind", kind)
	_rip.call("sim_set", &"seed_p", p)
	await _reset()
	_rip.call("sim_set", &"seed_kind", 0)


## NO EXTRA STEPS. swe_lab's own _reset already runs the two that consume the reset and write both
## halves of the ping-pong; adding two more here made every "step 0" reading two solver steps late.
## It mattered: the checkerboard halves about every two steps, so the seed read 0.48 mm when the
## solver had actually been handed 0.98, and the decay looked half as fast as it is.
func _reset() -> void:
	await _lab.call("_reset", false)
	_lab.call("_read_back")


## EVERY RUN CHECKS THE STATE IS STILL WATER. This file had no divergence guard at all, which is
## the worst place to have none: it drives the solver with stimuli nothing else uses - a seeded
## vortex, a checkerboard at the grid scale, drag and Manning switched OFF - and then prints
## circulation and energy figures computed from whatever came back. A diverged field yields a
## perfectly plausible-looking table of numbers and a PASS.
##
## And the obvious guard does not work here. The state is RGBA16F, float16 SATURATES at 65504, so a
## dead cell is neither NaN nor Inf and every finiteness test in the project called it healthy.
## The test is physical plausibility instead: nothing on a flat pan is 100 m deep or moving at
## 100 m/s, and there is no overlap between that and a live simulation.
func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
	var why := _diverged()
	if why != "":
		print("[SCHEME]    FAIL: the solver diverged - %s" % why)
		print("[SCHEME]    everything printed after this line is arithmetic on a dead field")
		_fail += 1


func _diverged() -> String:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return "no state image"
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, z)
			if is_nan(px.r) or is_nan(px.g) or is_nan(px.b):
				return "NaN at (%d, %d)" % [x, z]
			if is_inf(px.r) or absf(px.r) > 100.0:
				return "h = %.1f at (%d, %d)%s" % [px.r, x, z,
						"  (float16 saturated)" if px.r >= 65504.0 else ""]
			if absf(px.g) > 100.0 or absf(px.b) > 100.0:
				return "u = (%.1f, %.1f) at (%d, %d)" % [px.g, px.b, x, z]
	return ""


func _state(fresh: bool) -> Image:
	if fresh:
		_lab.call("_read_back")
	return _lab.get("_state_img")
