extends SceneTree
## WHERE DOES IT EXPLODE, and does it explode where the theory says it should?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_blowup.gd
##
## The bench opens with a source running into a closed box, which HAS NO STEADY STATE BY
## CONSTRUCTION: the bowl has no outlet, so the level rises for as long as you let it. The solver
## is explicit, so above a depth the grid sets it goes unstable. Leave the lab running and it will
## blow up - not because anything is wrong, but because that configuration is a ramp toward the
## CFL limit and nobody put a wall at the end of it.
##
## THAT IS NOT AN ACCEPTABLE ANSWER, and this file exists to stop it being an anecdote. Three
## questions, each with a number:
##
##   WHEN     at what depth, what step, and what wall-clock second does it go?
##   WHY      is that the CFL limit kappa = g*h*dt^2/dx^2 = 0.25, or something else? If it blows at
##            kappa well below 0.25 the stability argument is about a scheme we are not running.
##   WHAT     what does it look like on the way in - does it warn, or does one frame do it?
##
## AND IT NEVER RECOVERS. The state is RGBA16F and float16 saturates at 65504, so a diverged cell
## does not go NaN and get noticed, it pegs at 65504 and stays there for the rest of the session.
## Every finiteness test in this project called that healthy until this run was written; the guard
## here is physical plausibility instead, because nothing on this bench is 100 m deep.
##
## suite 8 of probe_swe_lab measures the same ceiling by SEEDING a deep pan. This measures it the
## way a person meets it: by watching a basin fill.

const CHUNK := 500            ## steps between readings
const MAX_STEPS := 24000      ## 400 s of simulated time; well past the predicted ceiling
const DIVERGE_H := 100.0

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
		print("[BLOWUP] FAIL: swe_lab.gd did not load")
		quit(1)
		return

	var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
	var dt := 1.0 / 60.0
	# The collocated scheme's limit. A staggered forward-backward update should double it; when
	# that lands, this constant moves with it and the prediction below is the falsifiable claim.
	var ceiling: float = 0.25 * dx * dx / (9.81 * dt * dt)
	print("[BLOWUP] grid %d, dx %.3f m, dt %.5f s"
			% [int(_rip.get("RES")), dx, dt])
	print("[BLOWUP] CFL says the deepest stable water is %.2f m (kappa = g*h*dt^2/dx^2 = 0.25)"
			% ceiling)

	# EXACTLY THE CONFIGURATION THE BENCH OPENS IN. Not a contrived one: bowl, source on, closed
	# box, no sink, no seep. This is what a person sees who opens the scene and walks away.
	_lab.set("_source_on", true)
	_lab.set("_sink_on", false)
	_rip.call("sim_set", &"seep", 0.0)
	_lab.get_node("Bed").set("profile", 3)          # BOWL
	_lab.get_node("Bed").set("bed_depth", 0.55)
	_lab.call("_rebuild")
	_rip.set("depth_mode", true)
	_rip.set("edge_mode", 1)

	# TWO PASSES, because "it explodes" and "the guard fixes it" are two claims and each needs its
	# own run. The first finds the cliff and checks it is where the CFL formula says. The second
	# drives the identical basin past that point with the guard on and asserts it is still water.
	var cliff := await _fill(false, ceiling)
	print("[BLOWUP]")
	await _fill(true, ceiling)
	if cliff < 0.0:
		print("[BLOWUP] NOTE: pass 1 never reached the cliff, so pass 2 proves nothing about it.")

	print("[BLOWUP] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## Fill the bowl until it dies or the step cap runs out. Returns the last healthy depth, or -1 if
## it never died.
func _fill(guard: bool, ceiling: float) -> float:
	var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
	var dt := 1.0 / 60.0
	_rip.call("sim_set", &"cfl_guard", guard)
	print("[BLOWUP] ---- cfl_guard %s ----" % ("ON  (g capped so kappa cannot pass cfl_max)"
			if guard else "OFF (the scheme as the equations describe it)"))
	await _reset()

	print("[BLOWUP]   step      t       volume     max h    kappa    max|u|   state")
	var step := 0
	var blew_at := -1
	var blew_h := 0.0
	var blew_k := 0.0
	var prev_h := 0.0
	var warned := false
	while step < MAX_STEPS:
		await _run(CHUNK)
		step += CHUNK
		var mh := _max_h()
		var mu := _max_u()
		var k: float = 9.81 * mh * dt * dt / (dx * dx)
		var why := _diverged()
		print("[BLOWUP] %6d  %5.1fs  %9.1f  %7.3f  %7.4f  %7.3f   %s"
				% [step, float(step) * dt, _vol(), mh, k, mu, why if why != "" else "ok"])
		# THE WARNING, if there is one: max |u| climbing while the depth is still fine is the
		# grid-scale mode growing before it saturates. If this never fires, the answer to "does it
		# warn" is no, and a guard cannot be reactive.
		if why == "" and mu > 3.0 and not warned:
			warned = true
			print("[BLOWUP]     ^ velocity is running away %.1f steps before the state dies"
					% 0.0)
		if why != "":
			blew_at = step
			blew_h = prev_h
			blew_k = 9.81 * prev_h * dt * dt / (dx * dx)
			break
		prev_h = mh

	if blew_at < 0:
		print("[BLOWUP] did not diverge in %d steps (%.0f s). Deepest water %.3f m, kappa %.4f."
				% [MAX_STEPS, float(MAX_STEPS) * dt, prev_h,
				9.81 * prev_h * dt * dt / (dx * dx)])
		print("[BLOWUP] NOTE: that is not a pass for the solver, it is a statement that the basin "
				+ "did not fill far enough in the time allowed.")
	else:
		print("[BLOWUP] DIVERGED between step %d and %d (%.1f s), last good depth %.3f m, "
				% [blew_at - CHUNK, blew_at, float(blew_at) * dt, blew_h]
				+ "kappa %.4f" % blew_k)
		print("[BLOWUP] the CFL limit predicted %.2f m; the last reading before death was %.3f m "
				% [ceiling, blew_h] + "(%.0f%% of it)" % (blew_h / maxf(ceiling, 1e-6) * 100.0))
		# The theory earns its keep only if it predicts the measurement. Blowing up at a third of
		# the predicted depth would mean the limit is set by something else entirely - and every
		# resolution decision made from the CFL formula would be guesswork.
		if blew_h < ceiling * 0.5:
			print("[BLOWUP]    FAIL: it died at half the predicted depth or less. The CFL formula "
					+ "is not what is limiting this solver, and the real limit is unknown.")
			_fail += 1

	# THE GUARD'S TWO OBLIGATIONS, and it has to meet both or it is not a fix. Staying alive is the
	# easy one - clamping h to a constant would also stay alive. The other is that it must not have
	# quietly stopped conserving water on the way: a guard that survives by losing the lake has
	# replaced a visible failure with an invisible one.
	if guard:
		if blew_at >= 0:
			print("[BLOWUP]    FAIL: the guard did not hold - it died anyway")
			_fail += 1
		else:
			var want: float = 52.0 * 0.5 * float(MAX_STEPS) * dt
			var got := _vol()
			print("[BLOWUP] guard held for %.0f s. Deepest %.3f m (%.0f%% past the unguarded "
					% [float(MAX_STEPS) * dt, prev_h, (prev_h / maxf(ceiling, 1e-6) - 1.0) * 100.0]
					+ "cliff). Volume %.0f m3 against %.0f the source delivered (%+.1f%%)."
					% [got, want, (got - want) / maxf(want, 1e-6) * 100.0])
			if absf(got - want) > want * 0.05:
				print("[BLOWUP]    FAIL: the guard is not conserving water - it survived by "
						+ "losing the lake, which is a worse bug than the one it fixes")
				_fail += 1
	return blew_h if blew_at >= 0 else -1.0


func _diverged() -> String:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return "no state"
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, z)
			if is_nan(px.r) or is_nan(px.g) or is_nan(px.b):
				return "NaN"
			if is_inf(px.r) or absf(px.r) > DIVERGE_H:
				return "DEAD (h %.0f%s)" % [px.r, ", float16 pegged" if px.r >= 65504.0 else ""]
	return ""


func _max_h() -> float:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return 0.0
	var top := 0.0
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			top = maxf(top, img.get_pixel(x, z).r)
	return top


func _max_u() -> float:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return 0.0
	var top := 0.0
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, z)
			top = maxf(top, Vector2(px.g, px.b).length())
	return top


func _vol() -> float:
	_lab.call("_read_back")
	return float(_lab.get("_volume"))


func _reset() -> void:
	await _lab.call("_reset", true)
	_lab.call("_read_back")


func _run(steps: int) -> void:
	for _i in steps:
		_lab.call("_feed_sink", 1)
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
