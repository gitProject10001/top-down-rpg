extends SceneTree
## THE LONG RUN, because ten seconds is not an answer.
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_long.gd
##
## probe_swe_lab settles everything in 600 steps, and 600 steps is ten seconds. A scheme can be
## perfectly behaved for ten seconds and wrong at two minutes in three different ways, none of
## which a short run can distinguish:
##
##   a DRIFT that is linear    - 0.02 % in 600 steps is 0.2 % in 6000, and boring
##   a DRIFT that compounds    - the same 0.02 % becoming 20 %, which is not
##   a CEILING that is reached - a closed box with a source in it fills forever, and this solver
##                               goes unstable above a depth the grid sets. Nothing about the
##                               first minute says when.
##
## So: six thousand steps, sampled every thousand, at rest and driven. The rest run asks whether
## anything moves on its own. The driven run asks what happens when it does not stop.

var _rip: Node = null
var _fail := 0


func _initialize() -> void:
	var lab := (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 30:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	lab.set("_live", false)
	if not lab.has_method("_read_back"):
		print("[LONG] FAIL: swe_lab.gd did not load")
		quit(1)
		return

	var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
	var ceiling: float = 0.25 * dx * dx / (9.81 * pow(1.0 / 60.0, 2.0))
	print("[LONG] grid %d, dx %.3f m, depth ceiling %.2f m" % [int(_rip.get("RES")), dx, ceiling])

	await _runup(lab)
	await _at_rest(lab)
	await _driven(lab, ceiling)

	_check_sampling(lab)
	print("[LONG] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## C. DOES A WAVE RUN UP A BEACH, or does the waterline stay where it is?
##
## The complaint is that water clings to the edge like glue instead of breaking against it, and
## there is a term with exactly that effect: wet_ramp multiplies velocity by
## smoothstep(h_dry, h_wet, h), so water thinner than h_wet has NO velocity at all. A runup tongue
## is a thin sheet by definition, so the wave arrives, the sheet it should push up the slope is
## born already stopped, and the shoreline advances only by diffusion.
##
## MEASURED AS EXCURSION: the wetted area is the waterline's position. Poke a lake on a sloping
## beach and watch how far it climbs, at several gate settings. A shoreline that cannot run up
## reports nothing however hard it is hit.
func _runup(lab: Node) -> void:
	lab.set("_source_on", false)
	lab.set("_sink_on", false)
	_rip.call("sim_set", &"seep", 0.0)
	lab.get_node("Bed").set("profile", 4)          # ramp: a plain beach, nothing else on it
	lab.get_node("Bed").set("bed_depth", 0.55)
	lab.get_node("Bed").set("grade", 0.03)
	lab.call("_rebuild")
	# BY DRAG, not by the wet gate. The gate made no difference at four settings spanning an order
	# of magnitude, and the wave turned out to die before it ever reached thin water - so the gate
	# was never what stopped it. What kills a shoaling wave is TIME: as depth falls the wave slows
	# (c = sqrt(gh)), so a linear drag gets proportionally longer to work on it. Crossing the last
	# four metres of this beach takes five seconds at 0.8 m/s, and at drag 0.7 that is a factor of
	# six of decay against a factor of 1.5 of shoaling gain. The drag was tuned for how a ripple
	# should fade in a pond, and nobody asked it what it did to a shore.
	var drag_was: Variant = _rip.call("sim_get", &"drag")
	print("[LONG] C. runup on a 3%% beach, by DRAG:")
	for case: Array in [[0.70, 0.0, "shipped   "], [0.02, 0.0, "0.02      "]]:
		_rip.call("sim_set", &"drag", case[0])
		await _reset(lab, false)
		# CLOSE TO THE SHORE, and watched long enough for the wave to get there. The waterline on
		# this beach sits at x = -18.3; a shallow-water wave travels at sqrt(g*H), about 3 m/s
		# here, so a shove from the deep end needs eleven seconds to arrive and the first version
		# of this test watched five. It measured a wave that had not turned up yet.
		var deep: Vector3 = lab.get_node("Bed").to_global(Vector3(-8.0, 0.0, 0.0))
		# A DOME, NOT A HOLE, and this test spent its whole life measuring the wrong sign.
		#
		# splash() applies a DOWNWARD displacement - it is the drain's primitive - so a positive
		# strength digs a crater. What then travels to the shore is a TROUGH with the crest behind
		# it, and the profile printed exactly that: -1.3 cm across the whole approach. A trough
		# pulls the waterline back before it can push it forward, which is the opposite of the
		# thing being measured, so "runup 0.000" was partly a statement about the stimulus.
		#
		# A negative strength raises instead: h -= min(poke, poke_frac * h) with poke < 0 is
		# h += |poke|, and poke_frac (a positivity guard on the downward case) does not bind. That
		# is a dome of water collapsing into a surge, which is what a beach is meant to receive.
		_rip.call("splash", deep, 4.0, -0.25)
		var line0 := _waterline(lab)
		var peak := line0
		var trace := PackedFloat32Array()
		for _k in 24:
			await _run(lab, 30)
			var now := _waterline(lab)
			peak = minf(peak, now)          # up the beach is -x
			# THE ADVANCE ITSELF, sampled over time. This used to trace _dry_beach - the most water
			# standing on a band starting one texel ABOVE the waterline - which is an instrument
			# with a 0.2 m dead zone in front of it, so it printed 0.00000 through a 0.214 m runup
			# and made the run look like a failure sitting next to its own success. The waterline is
			# interpolated and has no dead zone; trace that.
			trace.append(line0 - now)
		var shape := ""
		for k in range(0, trace.size(), 3):
			shape += "%+.3f " % trace[k]
		# WHERE DOES THE WAVE DIE? A profile of the surface from the shore into the lake says it
		# outright, where every scalar so far has only said "not here".
		_profile(lab, line0)
		_shore_terms(lab)
		print("[LONG] C.  drag %.2f (%s): waterline %.2f -> %.2f m, runup %+.3f m"
				% [case[0], case[2], line0, peak, line0 - peak]
				+ "   advance every 1.5 s " + shape)
		if not _finite(lab):
			print("[LONG]    NOTE: unstable at this gate - the ramp is load-bearing below here")
			break
	_rip.call("sim_set", &"drag", drag_was)
	lab.get_node("Bed").set("grade", 0.03)
	lab.call("_rebuild")


## A. NOTHING DRIVING IT, for a hundred seconds. A lake at rest that is still at rest after 6000
## steps is a lake at rest; one that is merely SLOW to go wrong looks identical at 600.
func _at_rest(lab: Node) -> void:
	_rip.call("sim_set", &"seep", 0.0)
	lab.set("_source_on", false)
	lab.set("_sink_on", false)
	lab.get_node("Bed").set("profile", 1)          # valley: slope, banks, the hard case
	lab.call("_rebuild")
	await _reset(lab, false)
	var v0 := _vol(lab)
	print("[LONG] A. valley at rest, %.1f m3" % v0)
	var prev := 0.0
	for k in 6:
		await _run(lab, 1000)
		var d := (_vol(lab) - v0) / maxf(v0, 1e-6) * 100.0
		print("[LONG] A.  step %5d: volume %+8.4f %%   max |u| %.4f m/s   %s"
				% [(k + 1) * 1000, d, _max_speed(lab), _surface(lab)])
		# COMPOUNDING is the thing to catch. A drift that doubles between equal windows is not a
		# tolerance question, it is a different answer arriving slowly.
		if k >= 2 and absf(d) > maxf(absf(prev) * 1.8, 0.05):
			print("[LONG]    FAIL: the drift is growing faster than linearly (%+.4f -> %+.4f %%)"
					% [prev, d])
			_fail += 1
		prev = d
		if not _finite(lab):
			print("[LONG]    FAIL: NaN")
			_fail += 1
			return
	if absf(prev) > 1.0:
		print("[LONG]    FAIL: %+.3f %% of the lake moved with nothing driving it" % prev)
		_fail += 1


## B. A SOURCE THAT DOES NOT STOP, in a closed box. This is the configuration the bench opens in,
## and it has no steady state by construction: the box has no outlet, so depth rises until the grid
## cannot integrate it. The question is not whether that happens but WHEN, and whether the solver
## says so or simply starts lying.
func _driven(lab: Node, ceiling: float) -> void:
	lab.set("_source_on", true)
	lab.get_node("Bed").set("profile", 3)          # bowl: fills, then overflows its rim
	lab.call("_rebuild")
	await _reset(lab, true)
	var area := _spring_area()
	var rate := float(_rip.call("sim_get", &"spring_rate"))
	print("[LONG] B. bowl, source %.0f m2 x %.3f m/s = %.2f m3/s into a closed box"
			% [area, rate, area * rate])
	var v0 := _vol(lab)
	for k in 6:
		await _run(lab, 1000)
		var t := float((k + 1) * 1000) / 60.0
		var want := area * rate * t
		var got := _vol(lab) - v0
		print("[LONG] B.  %5.1f s: volume %8.1f m3 (source says %8.1f, %+.1f %%)   max h %.3f m"
				% [t, got, want, (got - want) / maxf(want, 1e-6) * 100.0, _max_h(lab)]
				+ "   wet %.0f m2" % _wet(lab))
		if not _finite(lab):
			print("[LONG]    FAIL: NaN at %.1f s, max h was heading for the %.2f m ceiling"
					% [t, ceiling])
			_fail += 1
			return
		# MASS IN A CLOSED BOX IS THE SOURCE, EXACTLY. Nothing leaves; there is no outlet and seep
		# is off. Any gap is the solver inventing or losing water, and over a hundred seconds a
		# small per-step error has had time to become a visible one.
		if absf(got - want) > maxf(want * 0.05, 1.0):
			print("[LONG]    FAIL: %+.1f m3 unaccounted for" % (got - want))
			_fail += 1
			# WHICH IS IT: water being destroyed, or water never arriving? A shortfall reads the
			# same either way in a total, and the two want opposite fixes. Split the change into
			# the cells that GAINED and the cells that LOST, and check the source is still there.
			await _where_the_mass_went(lab)
		if _max_h(lab) > ceiling:
			print("[LONG]    NOTE: past the %.2f m stability ceiling - anything after this is "
					% ceiling + "arithmetic, not water")
			return


## Total gained and total lost over one window, separately, plus whether the spring still exists.
## Sum(gain) - Sum(loss) is the net the volume total reports; seeing the two apart says whether the
## solver is eating water or simply not being given any.
func _where_the_mass_went(lab: Node) -> void:
	var before := _snap(lab)
	await _run(lab, 300)
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null or before.is_empty():
		return
	var res := img.get_width()
	var area: float = pow(float(_rip.get("SIZE_M")) / float(res), 2.0)
	var up := 0.0
	var down := 0.0
	var worst := 0.0
	var at := Vector2i(-1, -1)
	for z in res:
		for x in res:
			var d: float = img.get_pixel(x, z).r - before[z * res + x]
			if d > 0.0:
				up += d * area
			else:
				down += -d * area
				if -d > worst:
					worst = -d
					at = Vector2i(x, z)
	var expect: float = _spring_area() * float(_rip.call("sim_get", &"spring_rate")) * 5.0
	print("[LONG]      over 5 s: gained %.1f m3, lost %.1f m3, net %+.1f (source should give %.1f)"
			% [up, down, up - down, expect])
	print("[LONG]      spring still %.0f m2; biggest single loss %.4f m at %s"
			% [_spring_area(), worst, at])


func _snap(lab: Node) -> PackedFloat32Array:
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


## The volume total samples every fourth texel. That is fine for a smooth deep lake and a lie in
## the presence of texel-scale structure, which is exactly what a thin sheet spreading over rough
## ground is. Compare against every texel, once, at the end - when the sheet is at its thinnest.
func _check_sampling(lab: Node) -> void:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return
	var res := img.get_width()
	var area: float = pow(float(_rip.get("SIZE_M")) / float(res), 2.0)
	var full := 0.0
	for z in res:
		for x in res:
			full += maxf(img.get_pixel(x, z).r, 0.0) * area
	var sampled := float(lab.get("_volume"))
	print("[LONG] D. volume sampled every 4th texel %.1f m3 vs every texel %.1f (%+.2f %%)"
			% [sampled, full, (sampled - full) / maxf(full, 1e-6) * 100.0])
	if absf(sampled - full) > full * 0.02:
		print("[LONG]    NOTE: the sampled total is not the total - every figure above is off by "
				+ "this much")


func _surface(lab: Node) -> String:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return ""
	var lo := 1e9
	var hi := -1e9
	for z in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var h: float = img.get_pixel(x, z).r
			if h > 0.05:
				lo = minf(lo, h)
				hi = maxf(hi, h)
	return "h in [%.3f, %.3f]" % [lo, hi] if hi > -1e8 else "dry"


## WHERE THE WATERLINE IS, in metres of world X along the middle of the beach, at FULL texture
## resolution. Wetted area is the wrong instrument for this: it samples every fourth texel, so its
## granularity is 0.8 m and a wave climbing a 3 %% beach moves the line by centimetres. An
## instrument coarser than the effect reports zero and looks like a result.
func _waterline(lab: Node) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	var res := img.get_width()
	var texel: float = float(_rip.get("SIZE_M")) / float(res)
	var org: Vector2 = _rip.call("window_origin")
	# THE THRESHOLD IS NOT h_dry, and using it was measuring the solver's own gate rather than the
	# water. h_dry is 2 mm and the front now creeps at 1.75 mm, so a waterline thresholded there
	# reports "did not move" about a front that moved. A tenth of it puts the cut below anything
	# the physics treats as special and above the store's noise.
	#
	# AND IT INTERPOLATES. The texel is 0.2 m and the effect being measured is centimetres, so
	# reporting the first wet texel's centre quantises the answer to a bin forty times the size of
	# the signal - which is the same mistake as thresholding, one layer down. Crossing the eps
	# contour between two cells gives the position to a fraction of a texel.
	var eps := float(_rip.call("sim_get", &"h_dry")) * 0.1
	var z := res / 2
	# The beach falls along +x, so the waterline is the LOWEST x that still holds water. Averaged
	# over a few rows, because a single row is one texel of noise.
	var total := 0.0
	var rows := 0
	for dz in [-6, -2, 2, 6]:
		var zz := clampi(z + dz, 0, res - 1)
		for x in res:
			var h: float = img.get_pixel(x, zz).r
			if h <= eps:
				continue
			var fx := float(x)
			if x > 0:
				var hp: float = img.get_pixel(x - 1, zz).r
				# h rises from hp (below eps) to h (above): where does it cross?
				fx -= clampf((h - eps) / maxf(h - hp, 1e-9), 0.0, 1.0)
			total += org.x + (fx + 0.5) * texel
			rows += 1
			break
	return total / maxf(float(rows), 1.0)


## The highest water SURFACE in the four metres of lake nearest the waterline. Zero at rest; a
## wave arriving reads as its own amplitude. This is what separates "the shore cannot be climbed"
## from "nothing ever got there".
## The most water standing anywhere on the two metres of DRY beach above the rest waterline, in
## metres. Threshold-free on purpose: every instrument so far has asked "is this cell wet", which
## is a question with a cutoff in it, and a cutoff can hide a millimetre of runup as a zero.
## The water SURFACE along the beach, from the waterline out into the lake, in centimetres. At
## rest it is zero everywhere. A wave shows as a bump, and where the bump stops is the answer to
## why nothing ever climbs the shore.
func _profile(lab: Node, line_x: float) -> void:
	var out := ""
	for m in range(0, 17, 2):
		out += "%5.1f " % (_surface_at(lab, line_x + float(m)) * 100.0)
	print("[LONG]      surface cm at 0,2,..16 m out from the waterline: " + out)


## WHY THE WATERLINE DID NOT MOVE, in the solver's own terms rather than as a scalar.
##
## "runup 0.000 m" is a number with no cause in it, and this work has already spent six eliminations
## on it. Every step the front could take is gated by one of four quantities, all of them local to
## the two cells straddling the waterline, and all of them printable:
##
##   hf   = max(0, max(w, w_n) - max(b, b_n))   - the LISFLOOD sill. Zero means the next bed texel
##          stands above this surface and the face is shut: the wave is not being slowed, it is
##          being walled. On a 3 % beach at a 0.5 m bake, every riser is about 1.5 cm.
##   b_n - w, the height the water would have to gain before the face can open at all. THIS is the
##          gate that survives, now that wet_ramp is gone: measured +0.0129 m against a wave that
##          arrives half a centimetre high. The bed is a flight of stairs and the water is not
##          being slowed on it, it is standing at the foot of a step.
##   h on both cells, because a front that is thin is a different problem from a front that is
##          walled, and only one of them is fixed by resolution.
##
## Printed for the last wet cell along the beach and the dry one above it, so a zero has an author.
func _shore_terms(lab: Node) -> void:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	var bd: Image = lab.get("_bed_img")
	if img == null or bd == null:
		print("[LONG]      (no state or bed image - shore terms unavailable)")
		return
	var res := img.get_width()
	var fres := bd.get_width()
	var h_dry := float(_rip.call("sim_get", &"h_dry"))
	var hf_min := float(_rip.call("sim_get", &"hf_min"))
	var z := res / 2
	# The beach falls along +x: walk in from the wet end and stop at the last wet cell.
	var last := -1
	for x in res:
		if img.get_pixel(x, z).r > h_dry:
			last = x
			break
	if last < 0 or last == 0:
		print("[LONG]      (no waterline in this row)")
		return
	var bed_at := func(xx: int) -> float:
		var fx := clampi(int((float(xx) + 0.5) / float(res) * float(fres)), 0, fres - 1)
		var fz := clampi(int((float(z) + 0.5) / float(res) * float(fres)), 0, fres - 1)
		return bd.get_pixel(fx, fz).r
	# Up-beach is -x from the last wet cell.
	var up := last - 1
	var h: float = maxf(img.get_pixel(last, z).r, 0.0)
	var hn: float = maxf(img.get_pixel(up, z).r, 0.0)
	var b: float = bed_at.call(last)
	var bn: float = bed_at.call(up)
	var w := b + h
	var wn := bn + hn
	var hf := maxf(0.0, maxf(w, wn) - maxf(b, bn))
	print("[LONG]      shore face: wet cell h %.5f b %+.4f w %+.4f | dry cell h %.5f b %+.4f"
			% [h, b, w, hn, bn]
			+ "   riser b_n-w %+.4f m" % (bn - w))
	print("[LONG]      hf %.5f (%s, hf_min %.4f)   the front must gain %+.4f m to open it"
			% [hf, "OPEN" if hf > hf_min else "SHUT", hf_min, bn - w])


func _surface_at(lab: Node, wx: float) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	var bd: Image = (_rip.call("bed_texture") as Texture2D).get_image()
	if img == null or bd == null:
		return 0.0
	var res := img.get_width()
	var fres := bd.get_width()
	var texel: float = float(_rip.get("SIZE_M")) / float(res)
	var org: Vector2 = _rip.call("window_origin")
	var x := clampi(int((wx - org.x) / texel), 0, res - 1)
	var top := -1e9
	for z in range(res / 2 - 6, res / 2 + 6):
		var h: float = img.get_pixel(x, z).r
		if h <= 0.0:
			continue
		var fx := clampi(int((float(x) + 0.5) / float(res) * float(fres)), 0, fres - 1)
		var fz := clampi(int((float(z) + 0.5) / float(res) * float(fres)), 0, fres - 1)
		top = maxf(top, bd.get_pixel(fx, fz).r + h)
	return top if top > -1e8 else 0.0


func _dry_beach(lab: Node, line_x: float) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	var res := img.get_width()
	var texel: float = float(_rip.get("SIZE_M")) / float(res)
	var org: Vector2 = _rip.call("window_origin")
	var top := 0.0
	for z in range(res / 2 - 10, res / 2 + 10):
		for x in res:
			var wx: float = org.x + (float(x) + 0.5) * texel
			if wx > line_x - texel or wx < line_x - 2.0:
				continue
			top = maxf(top, img.get_pixel(x, z).r)
	return top


func _shore_wave(lab: Node, line_x: float) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	var bd: Image = (_rip.call("bed_texture") as Texture2D).get_image()
	if img == null or bd == null:
		return 0.0
	var res := img.get_width()
	var fres := bd.get_width()
	var texel: float = float(_rip.get("SIZE_M")) / float(res)
	var org: Vector2 = _rip.call("window_origin")
	var top := -1e9
	for z in range(res / 2 - 8, res / 2 + 8):
		for x in res:
			var wx: float = org.x + (float(x) + 0.5) * texel
			if wx < line_x:
				continue
			var h: float = img.get_pixel(x, z).r
			if h <= 0.0:
				continue
			var fx := clampi(int((float(x) + 0.5) / float(res) * float(fres)), 0, fres - 1)
			var fz := clampi(int((float(z) + 0.5) / float(res) * float(fres)), 0, fres - 1)
			top = maxf(top, absf(bd.get_pixel(fx, fz).r + h))
	return top if top > -1e8 else 0.0


func _max_h(lab: Node) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	var top := 0.0
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			top = maxf(top, img.get_pixel(x, z).r)
	return top


func _wet(lab: Node) -> float:
	lab.call("_read_back")
	return float(lab.get("_wet_area"))


func _max_speed(lab: Node) -> float:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return 0.0
	var top := 0.0
	for z in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			top = maxf(top, (lab.call("_vel_at", Vector2i(x, z), img.get_width()) as Vector2).length())
	return top


func _finite(lab: Node) -> bool:
	lab.call("_read_back")
	var img: Image = lab.get("_state_img")
	if img == null:
		return false
	for z in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var px := img.get_pixel(x, z)
			if is_nan(px.r) or is_nan(px.g) or is_nan(px.b) or is_inf(px.r) or absf(px.r) > 1000.0:
				return false
	return true


func _spring_area() -> float:
	var img: Image = (_rip.call("field_texture") as Texture2D).get_image()
	var mark := float(_rip.get("SPRING_MARK")) * 0.5
	var n := 0
	for z in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, z).a > mark:
				n += 1
	var texel: float = float(_rip.get("SIZE_M")) / float(img.get_width())
	return float(n) * texel * texel


func _vol(lab: Node) -> float:
	lab.call("_read_back")
	return float(lab.get("_volume"))


func _reset(lab: Node, empty: bool) -> void:
	await lab.call("_reset", empty)
	await _run(lab, 2)


func _run(lab: Node, steps: int) -> void:
	for _i in steps:
		lab.call("_feed_sink", 1)
		_rip.call("step_once")
		await process_frame
	lab.call("_read_back")
