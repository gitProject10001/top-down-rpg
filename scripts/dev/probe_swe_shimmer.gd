extends SceneTree
## WHERE DOES THE GRID-SCALE SHIMMER COME FROM, and what actually sets its amplitude?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_shimmer.gd
##
## probe_swe_settle says a flat pan at 2.25 m is bit-exact at rest on both schemes - roughness
## 0.00 ulp for 1200 steps. It says that because it sets seep = 0 first. The LAB does not: seep is
## 0.001 m/s by default, which is 1.67e-5 m a step against a 1.95e-3 m ulp at 2.25 m. That is 8.5
## ulp-thousandths, and round_store's rest guard fires only under one ulp-thousandth - so in the
## lab the guard NEVER fires and the store dithers every wet cell every step.
##
## Four questions, one sweep:
##   1. does seep alone turn a bit-exact pan into a vibrating one?
##   2. is it the DITHER or is it float16 TRUNCATION underneath it? (dither_gain 0 vs 1)
##   3. is the noise WHITE or is it the checkerboard? (lag-1 neighbour correlation of the
##      high-passed surface: -1.0 is a pure k*dx = pi mode, -0.4 is spatial white noise)
##   4. does the amplitude scale as 1/sqrt(drag), which is what "injection balanced by drag alone,
##      with no diffusion anywhere" predicts?

var _rip: Node = null
var _lab: Node = null
var _prev := PackedFloat32Array()


func _initialize() -> void:
	_lab = (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 30:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	_lab.set("_live", false)
	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_rip.call("sim_set", &"cfl_guard", false)
	_rip.set("depth_mode", true)
	_rip.set("edge_mode", 1)
	_lab.get_node("Bed").set("bed_depth", 2.25)

	var ulp: float = pow(2.0, floor(log(2.25) / log(2.0)) - 10.0)
	print("[SHIMMER] flat pan / bowl at 2.25 m. one float16 ulp = %.4f mm. dx 0.2, dt 1/60."
			% (ulp * 1000.0))
	print("[SHIMMER] theory: sigma_d = 0.41 ulp/step, eta_rms = sigma_d/sqrt(2*drag*dt)")
	print("[SHIMMER] %-46s %8s %8s %8s %8s %8s"
			% ["case", "rough", "corr1", "|dh|", "guard%", "flip%"])
	print("[SHIMMER] %-46s %8s %8s %8s %8s %8s"
			% ["", "ulp", "-1=chk", "ulp/stp", "exact", "signflip"])

	_lab.get_node("Bed").set("profile", 0)             # FLAT_PAN
	_lab.call("_rebuild")
	for staggered in [true, false]:
		for seep: float in [0.0, 0.001]:
			for dith: float in [1.0, 0.0]:
				await _case("pan  %s seep %.4f dither %.0f"
						% ["stag" if staggered else "coll", seep, dith],
						staggered, seep, dith, 0.7, ulp)
	# THE DRAG SCALING. Injection is per step and the only sink is drag on u, so the equilibrium
	# height variance goes as 1/drag: four times the drag must halve the roughness.
	for drag: float in [0.175, 0.7, 2.8, 11.2]:
		await _case("pan  stag seep 0.0010 dither 1 drag %.3f" % drag,
				true, 0.001, 1.0, drag, ulp)
	_lab.get_node("Bed").set("profile", 3)             # BOWL: a real shore
	_lab.call("_rebuild")
	for seep: float in [0.0, 0.001]:
		for dith: float in [1.0, 0.0]:
			await _case("bowl stag seep %.4f dither %.0f" % [seep, dith],
					true, seep, dith, 0.7, ulp)
	quit(0)


func _case(tag: String, staggered: bool, seep: float, dith: float, drag: float,
		ulp: float) -> void:
	_rip.set("staggered", staggered)
	_rip.call("sim_set", &"seep", seep)
	_rip.call("sim_set", &"dither_gain", dith)
	_rip.call("sim_set", &"drag", drag)
	await _lab.call("_reset", false)
	for _i in 600:
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
	var res := int(_rip.get("RES"))
	var a := _sample(res)
	_rip.call("step_once")
	await process_frame
	_lab.call("_read_back")
	var b := _sample(res)
	var m := _metrics(a, b, res, ulp)
	print("[SHIMMER] %-46s %8.2f %8.2f %8.2f %8.1f %8.1f" % [tag, m[0], m[1], m[2], m[3], m[4]])


## The water SURFACE (bed + h) and the raw h, over the interior, as two flat arrays.
func _sample(res: int) -> Array:
	var img: Image = _lab.get("_state_img")
	var w := PackedFloat32Array()
	var h := PackedFloat32Array()
	w.resize(res * res)
	h.resize(res * res)
	for i in res * res:
		w[i] = -1e9
	# Only the quarter the metrics look at, plus a ring: _bed_at is GDScript and the full 320^2
	# costs more than the 600 steps that produced the state.
	for z in range(res / 4 - 2, res * 3 / 4 + 2):
		for x in range(res / 4 - 2, res * 3 / 4 + 2):
			var d: float = img.get_pixel(x, z).r
			h[z * res + x] = d
			w[z * res + x] = (float(_lab.call("_bed_at", Vector2i(x, z), res)) + d
					if d > 0.0 else -1e9)
	return [w, h]


func _metrics(a: Array, b: Array, res: int, ulp: float) -> Array:
	var wa: PackedFloat32Array = a[0]
	var ha: PackedFloat32Array = a[1]
	var hb: PackedFloat32Array = b[1]
	var wb: PackedFloat32Array = b[0]
	var lo := res / 4
	var hi := res * 3 / 4
	var rough := 0.0
	var e2 := 0.0
	var e_next := 0.0
	var dsum := 0.0
	var guard := 0.0
	var flip := 0.0
	var n := 0.0
	var e := PackedFloat32Array()
	e.resize(res * res)
	var eb := PackedFloat32Array()
	eb.resize(res * res)
	for z in range(lo, hi):
		for x in range(lo, hi):
			e[z * res + x] = _dev(wa, x, z, res)
			eb[z * res + x] = _dev(wb, x, z, res)
	for z in range(lo + 1, hi - 2):
		for x in range(lo + 1, hi - 2):
			var i := z * res + x
			if wa[i] < -1e8:
				continue
			var ev := e[i]
			rough += absf(ev)
			e2 += ev * ev
			e_next += ev * e[i + 1]
			dsum += absf(hb[i] - ha[i])
			if hb[i] == ha[i]:
				guard += 1.0
			if ev * eb[i] < 0.0:
				flip += 1.0
			n += 1.0
	n = maxf(n, 1.0)
	return [rough / n / ulp, e_next / maxf(e2, 1e-30), dsum / n / ulp,
			guard / n * 100.0, flip / n * 100.0]


## The high-passed surface at a texel: its own value less the mean of the four neighbours.
func _dev(w: PackedFloat32Array, x: int, z: int, res: int) -> float:
	var i := z * res + x
	if w[i] < -1e8:
		return 0.0
	var s := 0.0
	var k := 0
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var j := (z + o.y) * res + (x + o.x)
		if j < 0 or j >= w.size() or w[j] < -1e8:
			continue
		s += w[j]
		k += 1
	if k == 0:
		return 0.0
	return w[i] - s / float(k)
