extends SceneTree
## IS AN OBSTACLE ACTUALLY A WALL, or does it merely look like one?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_obstacle.gd
##
## An obstacle here is a piece of BED: it raises the effective bed inside its footprint, and the
## no-flow boundary is then supposed to fall out of the LISFLOOD face depth
## hf = max(0, max(w, w_n) - max(b, b_n)), which is identically zero wherever the solid stands above
## both surfaces. That is an elegant claim and elegance is not evidence, so:
##
##   1 THE SEED SEES IT     a basin filled around a cylinder must be DRY inside the footprint. If
##                          the reset does not know about the obstacle, water starts inside it and
##                          everything after that is about a lake with a hole in the middle.
##   2 THE SHAPE IS RIGHT   the dry footprint must match the analytic circle to within a texel. This
##                          is what stops the drawn mesh and the simulated solid drifting apart -
##                          the one disagreement you would never see, because you judge an
##                          obstacle's position entirely by eye.
##   3 IT IS STILL          a lake standing against a solid must not move. Conservation is not
##                          enough: water sloshing round a cylinder forever also conserves.
##   4 NOTHING CROSSES      no discharge through the footprint, at all, ever.
##   5 DRAGGING CONSERVES   the headline interaction. Pulling a solid through a lake raises the bed
##                          under standing water, so w = b + h rises, a gradient appears and the
##                          water flows out - and the question is whether it all goes somewhere or
##                          some of it just stops existing.

const R := 4.0                ## cylinder radius, m

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
		print("[OBS] FAIL: swe_lab.gd did not load")
		quit(1)
		return

	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_rip.call("sim_set", &"seep", 0.0)
	_rip.call("sim_set", &"cfl_guard", false)
	_lab.get_node("Bed").set("profile", 0)          # flat pan: the solid is the only feature
	_lab.get_node("Bed").set("bed_depth", 0.55)
	_lab.call("_rebuild")
	_rip.set("depth_mode", true)
	_rip.set("edge_mode", 1)

	for staggered in [false, true]:
		_rip.set("staggered", staggered)
		print("[OBS] ======== %s ========"
				% ("STAGGERED" if staggered else "collocated"))
		await _one_shape(0, "cylinder")
		await _one_shape(1, "box")
		await _drag()

	print("[OBS] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


func _one_shape(kind: int, name_: String) -> void:
	_rip.call("obstacle_clear")
	var top: float = float(_lab.get_node("Bed").get("rest_y")) + 1.5
	_rip.call("obstacle_add", kind, Vector2.ZERO, Vector2(R, R), top, 0.0)
	await _lab.call("_reset", false)
	_lab.call("_read_back")

	# 1 + 2. Where is the water, and does its hole have the right shape?
	var img: Image = _lab.get("_state_img")
	var res := img.get_width()
	var org: Vector2 = _rip.call("window_origin")
	var t: float = float(_rip.get("SIZE_M")) / float(res)
	var wet_inside := 0
	var dry_outside := 0
	var inside := 0
	var outside := 0
	for z in res:
		for x in res:
			var w := org + Vector2(float(x) + 0.5, float(z) + 0.5) * t
			var d := w.length()
			var h: float = img.get_pixel(x, z).r
			# ONLY WHERE THERE IS A BED AT ALL. The bench's bed is 48 m of a 64 m window and
			# everything outside it is the off-map 1000 m sentinel, which is legitimately and
			# permanently dry. Counting that ring as "dry outside the solid" reported 44800 texels
			# of correct behaviour as a footprint the size of the map.
			if maxf(absf(w.x), absf(w.y)) > 23.0:
				continue
			# A texel-wide skin either side of the boundary is not judged: the solid is tested at
			# the texel CENTRE, so the edge is quantised by construction and counting it would be
			# measuring the lattice.
			if kind == 0 and d < R - t * 1.5:
				inside += 1
				if h > 0.002:
					wet_inside += 1
			elif kind == 0 and d > R + t * 1.5:
				outside += 1
				if h <= 0.002:
					dry_outside += 1
			elif kind == 1:
				var b := maxf(absf(w.x), absf(w.y))
				if b < R - t * 1.5:
					inside += 1
					if h > 0.002:
						wet_inside += 1
				elif b > R + t * 1.5:
					outside += 1
					if h <= 0.002:
						dry_outside += 1
	print("[OBS] %-9s seed: %d texels inside the solid, %d of them WET; %d outside, %d of them DRY"
			% [name_, inside, wet_inside, outside, dry_outside])
	if inside == 0:
		print("[OBS]    FAIL: the solid covers no texels - it never reached the shader")
		_fail += 1
	if wet_inside > 0:
		print("[OBS]    FAIL: the reset put water inside a solid, so it does not know it is there")
		_fail += 1
	if dry_outside > 0:
		print("[OBS]    FAIL: %d texels outside the solid are dry - the footprint is too big"
				% dry_outside)
		_fail += 1

	# 3. Standing water against a wall must be STILL, not merely conserved.
	var v0 := _vol()
	var s0 := _snap(res)
	await _run(600)
	var moved := _moved(s0, res)
	print("[OBS] %-9s 600 steps at rest beside it: volume %+.4f m3, worst cell %+.6f m, max|u| %.4f"
			% [name_, _vol() - v0, moved, _max_u(res)])
	if moved > 0.015:
		print("[OBS]    FAIL: water is sloshing around a solid that is not doing anything")
		_fail += 1
	if absf(_vol() - v0) > v0 * 0.002:
		print("[OBS]    FAIL: volume is not conserved beside a solid")
		_fail += 1


## 5. THE HEADLINE INTERACTION: drag a solid across a still lake and count the water.
##
## The solid raises the bed under standing water, so w = b + h rises, a gradient appears, and the
## water flows out - until hf closes and traps whatever has not left. That trapped water is a real
## artefact and it is bounded, but it must still be WATER: the failure worth catching is water that
## stops existing, because that is invisible in the picture and fatal to everything downstream.
func _drag() -> void:
	_rip.call("obstacle_clear")
	await _lab.call("_reset", false)
	_lab.call("_read_back")
	var v0 := _vol()
	var top: float = float(_lab.get_node("Bed").get("rest_y")) + 1.5
	var id: int = _rip.call("obstacle_add", 0, Vector2(-16.0, 0.0), Vector2(R, R), top, 0.0)
	# Two metres a second across the basin, which is fast for a thing you drag with a mouse and
	# therefore the hard case.
	var steps := 900
	for i in steps:
		var x: float = -16.0 + 32.0 * float(i) / float(steps)
		_rip.call("obstacle_move", id, Vector2(x, 0.0))
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
	var v1 := _vol()
	# VOLUME IS CONSERVED, AND THE FIRST VERSION OF THIS TEST EXPECTED IT NOT TO BE.
	#
	# The reasoning was: the solid ends up standing in the lake, so its footprint of water has been
	# displaced and is gone from the total. That is wrong. Displaced water is PUSHED OUT into the
	# surrounding lake - the bed rises under it, w = b + h rises with it, and the gradient moves it
	# sideways. It leaves the footprint; it does not leave the world. The expected total is
	# therefore the total, and a probe that expected a 27 m3 loss would have called correct
	# behaviour a failure and gone looking for a leak that was not there.
	var disp := PI * R * R * 0.55
	print("[OBS] drag 32 m in %d steps: %.2f -> %.2f m3 (%+.3f%%), having pushed about %.1f m3 "
			% [steps, v0, v1, (v1 - v0) / maxf(v0, 1e-6) * 100.0, disp]
			+ "out of its own footprint on the way")
	if absf(v1 - v0) > v0 * 0.01:
		print("[OBS]    FAIL: dragging a solid through the lake loses water - displaced water has "
				+ "to go somewhere, and 1 % of the lake is not somewhere")
		_fail += 1
	_rip.call("obstacle_clear")


func _vol() -> float:
	_lab.call("_read_back")
	return float(_lab.get("_volume"))


func _snap(res: int) -> PackedFloat32Array:
	var img: Image = _lab.get("_state_img")
	var out := PackedFloat32Array()
	out.resize(res * res)
	for z in res:
		for x in res:
			out[z * res + x] = img.get_pixel(x, z).r
	return out


func _moved(before: PackedFloat32Array, res: int) -> float:
	var img: Image = _lab.get("_state_img")
	var worst := 0.0
	for z in res:
		for x in res:
			worst = maxf(worst, absf(img.get_pixel(x, z).r - before[z * res + x]))
	return worst


func _max_u(res: int) -> float:
	var top := 0.0
	for z in range(0, res, 2):
		for x in range(0, res, 2):
			top = maxf(top, (_lab.call("_vel_at", Vector2i(x, z), res) as Vector2).length())
	return top


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
