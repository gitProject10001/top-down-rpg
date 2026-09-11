extends SceneTree
## HOW BIG IS THE WAKE A BOAT AND A WADER ACTUALLY LEAVE, in millimetres.
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_wake.gd
##
## The report is that the boat and the player should make bigger waves. That is a claim about a
## number nobody has ever measured, so the first job is to measure it and the second is to change
## one dial at a time and measure again IN THE SAME PROCESS - "it looks bigger now" against a
## remembered picture has been wrong repeatedly on this branch.
##
## THERE ARE TWO DIALS AND THE OBVIOUS ONE IS THE WORSE ONE.
##
##   STRENGTH is how deep the poke is. Raising it raises the wake, and also the CFL load and the
##   risk of poking a hole clean through a one-metre lake, so it cannot simply be multiplied.
##
##   RADIUS is what WAVELENGTH the poke deposits its energy at, and it is nearly free. The wader's
##   footfall ring is 0.35 m on a 0.2 m grid - under two texels, the grid scale, which is exactly
##   the wavelength first-order upwinding and the curvature-gated smoother dissipate fastest.
##   Energy put in there is gone in a few steps however much of it there is.
##
## THIS RUNS ON THE BENCH'S FLAT PAN, NOT ON THE WILDS LAKE, and that is a correction. The first
## three drafts measured on water_lab's painted basin and reported 372 mm of "wake" from a null
## case with NO SOURCE AT ALL, because a freshly seeded basin rings and its 120 % shoreline swings
## by its whole local depth while it does. A wake is a solver property; measure it where the solver
## is the only thing happening. The pan is set to the same 1.04 m column and the same policy dials
## the game runs, so the numbers transfer.

const DT := 1.0 / 60.0
const DEPTH := 1.04           ## the game's lake, so the millimetres below are the game's millimetres
const SETTLE := 240           ## a flat pan is bit-exact still, so this only has to flush the seed
const TRACK := 16.0           ## metres the source travels through the middle of the pan
## The shallow fringe, where an uncapped wake would punch through. Roughly what the wilds put at a
## lake's edge and what the game's older waters are throughout.
const SHALLOW := 0.30
## Water.WAKE_BITE, mirrored so the rows below say what the game actually asks for. Read from the
## autoload rather than copied would be better, but `Water` is not resolvable from a --script entry
## point, and a probe that silently tests a different cap than the game ships is worse than one
## that has to be kept in step by hand and says so.
const WAKE_BITE := 0.25

var _rip: Node = null
var _lab: Node = null
var _res := 0
var _org := Vector2.ZERO
var _t := 0.0
var _rest := PackedFloat32Array()
var _fail := 0
var _null := 0.0
var _base_raft := 0.0
var _base_wade := 0.0
var _ship_raft := 0.0
var _ship_wade := 0.0


func _initialize() -> void:
	_lab = (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 60:
		await process_frame
	_rip = root.get_node("/root/Ripples")

	_lab.set("_live", false)
	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_lab.get_node("Bed").set("profile", 0)              # FLAT_PAN
	_lab.get_node("Bed").set("bed_depth", DEPTH)
	# The bed must be the whole window: it defaults to 48 m inside 64 m, and the 8 m ring outside it
	# is the off-map sentinel, which is a wall standing in the measurement band.
	_lab.get_node("Bed").set("extent", float(_rip.get("SIZE_M")))
	# AND THE BED HAS TO BE PUSHED. Setting the profile marks the bed node dirty; it does not bake
	# it into the field the solver reads. Without this the pan was never a pan, and the null control
	# duly reported 420 mm of wake and a dry cell on a flat 1.04 m basin.
	_lab.call("_rebuild")
	_rip.set("depth_mode", true)
	_rip.set("staggered", true)
	_rip.set("edge_mode", 1)                            # walls, 32 m away: 17 s to echo, we run 4
	_rip.set("paused", true)
	# PIN THE WINDOW TO THE PAN. The 64 m window is centred on whatever _focus() returns - the
	# bench's player, or failing that the current camera - and the track this probe sails runs
	# through the world origin. Left alone the two need not overlap at all, which is how the field
	# came back with zero wet texels while the seam correctly reported 1.04 m of water underfoot.
	var anchor := Node3D.new()
	_lab.add_child(anchor)
	anchor.global_position = Vector3.ZERO
	_rip.set("focus_override", anchor)
	# THE GAME'S POLICY, not the bench's defaults. wave_scale slows the celerity and smooth_grid
	# eats grid-scale curvature, and both change how big a splash looks - so a wake measured without
	# them would be a number about a solver nobody runs.
	_rip.call("sim_set", &"wave_scale", 0.35)
	_rip.call("sim_set", &"smooth_grid", 0.30)
	_rip.call("sim_set", &"ripple_kill", 0.008)
	# AND SEED IT FULL. The bench boots EMPTY on purpose - its headline profile is a bowl that
	# fills and then overflows, which wants an empty basin - and _rebuild's reset inherits that
	# flag. A wake probe wants a lake, not a bowl waiting for rain, and the empty pan is why the
	# seam correctly reported 1.04 m of water while the field held none.
	_rip.set("reset_empty", false)
	_rip.call("reset_now")
	await _run(4)

	_res = int(_rip.get("RES"))
	_t = float(_rip.get("SIZE_M")) / float(_res)
	_org = _rip.call("window_origin")
	print("[WAKE] window origin %.1f,%.1f - the pan is centred on the world origin"
			% [_org.x, _org.y])
	print("[WAKE] flat pan %.2f m, dx %.2f m, wave_scale %.2f, smooth_grid %.2f, drag %.2f"
			% [DEPTH, _t, float(_rip.call("sim_get", &"wave_scale")),
			float(_rip.call("sim_get", &"smooth_grid")), float(_rip.get("DRAG"))])
	print("[WAKE] wake = peak-to-peak departure from rest in a band 3-8 m beside a %.0f m track, "
			% TRACK + "0.5 s after the source has passed. A 0.35 m radius is %.1f texels."
			% (0.35 / _t))
	# IS THE PAN A PAN. A flat basin has one depth everywhere inside its extent, so if the spread
	# across the field is not a fraction of a millimetre the bench is not in the state this probe
	# thinks it set - which is exactly how the first four runs produced confident wrong numbers.
	await _run(SETTLE)
	var span := _field_span()
	# AND ASK THE SEAM WHAT IT THINKS, because "no water" has two completely different causes: the
	# solver drained it, or the terrain never offered any. Only one of them is about the solver.
	var terr: Object = _rip.get("terrain")
	for probe: Vector3 in [Vector3.ZERO, Vector3(8, 0, 0), Vector3(0, 0, 6)]:
		print("[WAKE] seam @%.0f,%.0f: bed %.3f  level %.3f  present %s"
				% [probe.x, probe.z, float(terr.bed_y(probe)), float(terr.level_y(probe)),
				terr.present()])
	print("[WAKE] pan check: h in [%.3f, %.3f] m over %d wet texels" % [span.x, span.y, int(span.z)])
	if span.y - span.x > 0.02 or absf(span.y - DEPTH) > 0.05:
		print("[WAKE] FAIL: that is not a flat %.2f m pan - the bench did not take the profile"
				% DEPTH)
		_fail += 1
	print("[WAKE] %-32s %8s %8s %8s %8s" % ["source", "wake mm", "radius", "strength", "min h"])

	# THE NULL CASE FIRST, AND EVERY ROW IS READ AGAINST IT. Comparing the rest field to itself is a
	# tautology that reports zero whatever the solver is doing.
	_null = await _case("no source (null control)", 4.5, 1e9, 0.6, 0.0)

	# THE BOAT at top speed: BOW_EVERY 0.35 m of travel per ring, TOP_SPEED 4.5 m/s.
	_base_raft = await _case("raft bow  WAS", 4.5, 0.35, 0.6, 0.04 + 0.03 * 4.5)
	await _case("raft bow  wider only", 4.5, 0.35, 1.4, 0.04 + 0.03 * 4.5)
	await _case("raft bow  stronger only", 4.5, 0.35, 0.6, 0.12 + 0.09 * 4.5)
	await _case("raft bow  wider + stronger", 4.5, 0.35, 1.4, 0.12 + 0.09 * 4.5)
	# WHAT ACTUALLY SHIPPED, cap included. raft.gd asks Water.wake for 0.06 + 0.08*speed at 1.4 m;
	# at top speed that is 0.42 m, which WAKE_BITE clamps to a quarter of a 1.04 m column.
	_ship_raft = await _case("raft bow  SHIPPING NOW", 4.5, 0.35, 1.4,
			minf(0.06 + 0.08 * 4.5, DEPTH * WAKE_BITE))

	# THE PLAYER jogging: RIPPLE_EVERY 0.9 m of travel per ring.
	_base_wade = await _case("wader step  WAS", 5.0, 0.9, 0.35, 0.05 + 0.01 * 5.0)
	await _case("wader step  wider only", 5.0, 0.9, 1.0, 0.05 + 0.01 * 5.0)
	await _case("wader step  wider + stronger", 5.0, 0.9, 1.0, 0.15 + 0.03 * 5.0)
	_ship_wade = await _case("wader step  SHIPPING NOW", 5.0, 0.9, 1.0,
			minf(0.14 + 0.035 * 5.0, DEPTH * WAKE_BITE))

	# THE POINT OF THE EXERCISE, asserted rather than admired. A wake that is not several times the
	# noise floor is not a wake, and the wader's shipped footfall was 1.15x it.
	print("[WAKE] raft  %.1f -> %.1f mm (%.1fx),  wader %.1f -> %.1f mm (%.1fx),  null %.1f mm"
			% [_base_raft * 1000.0, _ship_raft * 1000.0, _ship_raft / maxf(_base_raft, 1e-6),
			_base_wade * 1000.0, _ship_wade * 1000.0, _ship_wade / maxf(_base_wade, 1e-6),
			_null * 1000.0])
	if _ship_raft < _base_raft * 2.0 or _ship_wade < _base_wade * 2.0:
		print("[WAKE] FAIL: the new settings are not meaningfully bigger than the old ones")
		_fail += 1
	if _ship_wade < _null * 4.0:
		print("[WAKE] FAIL: the wader's wake is still within sight of the noise floor")
		_fail += 1

	# ---- A SOLID INSTEAD OF A POKE.
	#
	# An impulse is a hole punched in the surface that radiates and dies. A moving SOLID shoulders
	# water aside for as long as it moves: bow wave in front, the displaced water closing behind it,
	# and nothing at all when it stops - out of the same conservation law as everything else, with
	# no amplitude to tune. The question this answers is whether that is actually BIGGER, or merely
	# better-shaped, because the wader is going to be one and the footfall rings can then go.
	print("[WAKE] ---- a moving SOLID (bed_at = max(terrain, top)), not an impulse ----")
	var solid_body := await _solid_case("body  r 0.45 (the wader)", 5.0, 0.45)
	await _solid_case("body  r 0.60", 5.0, 0.60)
	await _solid_case("body  r 0.45, walking pace", 2.0, 0.45)
	# SUBMERGED BODIES. A top face ABOVE the waterline is EMERGENT: the solver keeps those cells dry
	# and the surface is cut at the body's outline, so a wading player stands in a crater instead of
	# in water. Sinking the top a little leaves water standing over it, which the renderer draws
	# continuously - the question is what that costs in wake, since the body then blocks less of the
	# column. The pan's rest surface is y = 0, so a top of -0.08 leaves 8 cm over a 1.04 m column.
	await _solid_case("body  r 0.45, top -0.08", 5.0, 0.45, 0, Vector2.ZERO, -0.08)
	await _solid_case("body  r 0.45, top -0.12", 5.0, 0.45, 0, Vector2.ZERO, -0.12)
	await _solid_case("body  r 0.45, top -0.25", 5.0, 0.45, 0, Vector2.ZERO, -0.25)
	# ---- HOW BIG SHOULD THE BODY BE. The player currently out-waves the boat, which is backwards:
	# 261 mm against the raft's 204. The chosen lever is a smaller cylinder, and the player's own
	# collision capsule is radius 0.3125 (player4.tscn:26) - so the shipped 0.45 was 44 % oversized
	# for no reason beyond wanting a wide footprint on a coarser grid.
	#
	# TWO NUMBERS PER CANDIDATE, because a radius buys a wake and costs a footprint. The wake is
	# measured here; the footprint swing is arithmetic and is printed first, below.
	print("[WAKE] ---- how big should the body be (target: well under the raft's %.0f mm) ----"
			% (_ship_raft * 1000.0))
	_footprint_table()
	for r: float in [0.3125, 0.28, 0.25, 0.20]:
		await _solid_case("body  r %.4f, shipped sink" % r, 5.0, r, 0, Vector2.ZERO, -0.08)
	# ---- A SOFT RIM, against the one-cell spikes at the bow. A stepped footprint adds a whole cell
	# of displacement at once and a body at 5 m/s crosses a cell 35 times a second; a ramped rim adds
	# each cell gradually. It also displaces LESS, so radius and softness trade against each other
	# and the pair has to be swept together rather than either alone.
	for pair: Vector2 in [Vector2(0.25, 0.10), Vector2(0.25, 0.25), Vector2(0.30, 0.30),
			Vector2(0.35, 0.35), Vector2(0.40, 0.40)]:
		await _solid_case("body  r %.2f soft %.2f" % [pair.x, pair.y], 5.0, pair.x, 0,
				Vector2.ZERO, -0.08, pair.y)

	# AND THE OTHER LEVER, for comparison: the same body sunk further so it blocks less column. The
	# hull rows below show this is by far the stronger of the two - 12 % of the column makes 30 mm
	# and 34 % makes 110, against a radius that only moves the wake as about r^0.63.
	await _solid_case("body  r 0.3125, sunk 0.30", 5.0, 0.3125, 0, Vector2.ZERO, -0.30)
	await _solid_case("body  r 0.3125, sunk 0.45", 5.0, 0.3125, 0, Vector2.ZERO, -0.45)

	# THE HULL, which is a different animal: DRAFT 0.12 on a 1.04 m column blocks only 12 % of it,
	# so the boat displaces the right VOLUME and shoulders far less water than a body that blocks
	# the lot. Whether that leaves the bow and stern rings any work to do is the question.
	await _solid_case("hull  0.5x1.1 box, draft 0.12", 4.5, 0.0, 1,
			Vector2(0.5, 1.1), -DEPTH + 0.12)
	await _solid_case("hull  same, draft 0.35", 4.5, 0.0, 1,
			Vector2(0.5, 1.1), -DEPTH + 0.35)
	print("[WAKE] solid body %.1f mm vs the wader's best impulse %.1f mm, null %.1f mm"
			% [solid_body * 1000.0, _ship_wade * 1000.0, _null * 1000.0])
	if solid_body < _null * 4.0:
		print("[WAKE] FAIL: a body walking through the lake barely disturbs it")
		_fail += 1

	# ---- AND THE SAME BOAT IN THE SHALLOWS, THROUGH THE REAL CALL PATH.
	#
	# This is the claim that licenses every number above. A 0.42 m displacement is a dent in a
	# metre of water and a hole clean through the 0.2 m fringe at its edge, and the fringe is where
	# a boat is beached and a player wades. Water.wake clamps to a third of the LOCAL column, so
	# the same call site is supposed to be safe in both - which is an assertion, not a hope.
	print("[WAKE] ---- the same raft, through Water.wake, over a %.2f m shallow pan ----" % SHALLOW)
	_lab.get_node("Bed").set("bed_depth", SHALLOW)
	_lab.call("_rebuild")
	await _run(4)
	var shallow := await _case("raft bow  shallow, via Water.wake", 4.5, 0.35, 1.4,
			0.06 + 0.08 * 4.5, true, SHALLOW)
	var lo := _min_depth()
	print("[WAKE] shallow pan: wake %.1f mm, column held at %.3f m of %.2f" % [shallow * 1000.0, lo,
			SHALLOW])
	if lo < SHALLOW * 0.40:
		print("[WAKE] FAIL: the cap did not hold - a %.2f m pan was drawn to %.3f m" % [SHALLOW, lo])
		_fail += 1

	print("[WAKE] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## Sail a source straight through the pan and measure what it leaves behind.
func _case(tag: String, speed: float, every: float, radius: float, strength: float,
		via_policy := false, pan := DEPTH) -> float:
	_rip.set("reset_empty", false)
	_rip.call("reset_now")
	await _run(SETTLE)
	_snap_rest()

	var travel := 0.0
	var x := -TRACK * 0.5
	while x < TRACK * 0.5:
		x += speed * DT
		travel += speed * DT
		if travel >= every:
			travel = 0.0
			if via_policy:
				# THE REAL CALL PATH, cap and all - not the solver primitive underneath it. The
				# rows above prove the numbers; this proves the numbers are what the game asks for.
				root.get_node(^"/root/Water").call("wake", Vector3(x, 0.0, 0.0), radius, strength)
			else:
				_rip.call("splash", Vector3(x, 0.0, 0.0), radius, strength)
		await _run(1)
	# LET THE SOURCE LEAVE: what is wanted is the wave it radiates, not the hole under the hull.
	await _run(30)

	var pk := _band_p2p()
	var lo := _min_depth()
	print("[WAKE] %-32s %8.1f %8.2f %8.3f %8.3f" % [tag, pk * 1000.0, radius, strength, lo])
	# A POKE DEEPER THAN THE LAKE IS NOT A BIGGER WAVE, it is a dry cell and a shock front.
	# AGAINST THE PAN ACTUALLY UNDER IT, not against the constant. Hardcoding DEPTH here failed the
	# shallow-water case for holding 0.134 m of a 0.30 m pan - which is the cap working.
	if strength > 0.0 and lo < pan * 0.25:
		print("[WAKE]    ^ that drew the column down to %.2f m of %.2f - too strong to ship"
				% [lo, pan])
		_fail += 1
	return pk


## Min, max and count of the wet field - the bench's own state, before any claim is made about it.
func _field_span() -> Vector3:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	var lo := 1e9
	var hi := -1e9
	var n := 0
	for z in _res:
		for x in _res:
			var h := float(img.get_pixel(x, z).r)
			if h <= 0.002:
				continue
			lo = minf(lo, h)
			hi = maxf(hi, h)
			n += 1
	return Vector3.ZERO if n == 0 else Vector3(lo, hi, float(n))


## THE COST OF A SMALL DISC, and it is arithmetic rather than simulation so it needs no GPU.
##
## obstacle_top() (swe_sim.gdshader:341-363) tests the texel CENTRE against the analytic shape, so a
## body covers a whole number of cells and that number CHANGES as it walks. A footprint that changes
## area is a displacement that changes with it - the body breathes once per texel crossed. Smaller
## discs swing harder in relative terms, which is the price of shrinking one, and it should be a
## number before it is a decision.
##
## Counted over a 5x5 grid of sub-texel positions: the cells covered at each, and the spread.
func _footprint_table() -> void:
	print("[WAKE] %-10s %8s %8s %8s %8s" % ["radius", "across", "cells", "swing", "of mean"])
	for r: float in [0.45, 0.3125, 0.28, 0.25, 0.20]:
		var lo := 1e9
		var hi := -1e9
		var sum := 0.0
		var n := 0
		var span := int(ceil(r / _t)) + 2
		for a in 5:
			for b in 5:
				var ox := float(a) / 5.0 * _t
				var oy := float(b) / 5.0 * _t
				var count := 0
				for j in range(-span, span + 1):
					for i in range(-span, span + 1):
						var px := (float(i) + 0.5) * _t - ox
						var py := (float(j) + 0.5) * _t - oy
						if px * px + py * py <= r * r:
							count += 1
				lo = minf(lo, float(count))
				hi = maxf(hi, float(count))
				sum += float(count)
				n += 1
		var mean := sum / float(n)
		print("[WAKE] %-10.4f %8.1f %8.1f %8.0f %7.0f%%"
				% [r, 2.0 * r / _t, mean, hi - lo, (hi - lo) / maxf(mean, 1.0) * 100.0])


## Walk a SOLID through the pan on the same track the impulse cases use, and measure the same band.
func _solid_case(tag: String, speed: float, radius: float, kind := 0, size := Vector2.ZERO,
		top := 0.06, soft := 0.0) -> float:
	_rip.set("reset_empty", false)
	_rip.call("obstacle_clear")
	_rip.call("reset_now")
	# PARKED OFF THE TRACK WHILE IT SETTLES. Registering the solid at the start line and then
	# seeding would seed the pan around it, and the first step would be the body appearing - a
	# transient far bigger than the wake, sitting in the measurement band.
	await _run(SETTLE)
	_snap_rest()
	# Top face just proud of the rest surface (y = 0 on this pan), so it blocks the whole column.
	var sz := Vector2(radius, radius) if size == Vector2.ZERO else size
	var id: int = _rip.call("obstacle_add", kind, Vector2(-TRACK * 0.5, 0.0), sz, top, 0.0, soft)
	var x := -TRACK * 0.5
	while x < TRACK * 0.5:
		x += speed * DT
		_rip.call("obstacle_move", id, Vector2(x, 0.0))
		await _run(1)
	# THE SOLID LEAVES THE WATER, not just the band. Left standing at the finish line it would go on
	# blocking the column while the wake was being read, and the hole around it is not a wave.
	_rip.call("obstacle_remove", id)
	await _run(30)

	var pk := _band_p2p()
	print("[WAKE] %-32s %8.1f %8.2f %8s %8.3f" % [tag, pk * 1000.0, radius, "solid", _min_depth()])
	return pk


## The pan at rest, per texel. The wake is a departure from THIS, so nothing static can enter it.
func _snap_rest() -> void:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	_rest.resize(_res * _res)
	for z in _res:
		for x in _res:
			_rest[z * _res + x] = img.get_pixel(x, z).r


## Peak-to-peak departure from rest in a band beside the track: the radiated wake. On a flat pan the
## bed is constant, so depth and surface differ by a constant and this needs no bed reconstruction -
## which is one fewer thing that can turn out to be the answer.
func _band_p2p() -> float:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	if img == null or _rest.is_empty():
		return 0.0
	var lo := 1e9
	var hi := -1e9
	var n := 0
	for z in _res:
		for x in _res:
			if not _in_band(x, z):
				continue
			var d := float(img.get_pixel(x, z).r) - _rest[z * _res + x]
			lo = minf(lo, d)
			hi = maxf(hi, d)
			n += 1
	if n < 200:
		print("[WAKE] FAIL: the band is only %d texels - the geometry is wrong" % n)
		_fail += 1
	return 0.0 if hi < lo else hi - lo


func _min_depth() -> float:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	if img == null:
		return 0.0
	var lo := 1e9
	for z in _res:
		for x in _res:
			var w := _texel_world(x, z)
			if absf(w.x) > TRACK * 0.5 + 2.0 or absf(w.y) > 3.0:
				continue
			lo = minf(lo, float(img.get_pixel(x, z).r))
	return 0.0 if lo > 1e8 else lo


func _in_band(x: int, z: int) -> bool:
	var w := _texel_world(x, z)
	return absf(w.x) <= TRACK * 0.5 and absf(w.y) >= 3.0 and absf(w.y) <= 8.0


func _texel_world(x: int, z: int) -> Vector2:
	return _org + Vector2(float(x) + 0.5, float(z) + 0.5) * _t


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
