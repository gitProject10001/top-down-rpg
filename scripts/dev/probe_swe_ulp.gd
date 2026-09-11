extends SceneTree
## IS THE SHIMMER'S AMPLITUDE THE ULP, and is the SEED any part of it?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_ulp.gd
##
## Section 1 - THE ULP LAW. Same pan, same drag, same seep, four depths. If the roughness in
## MILLIMETRES quadruples from 0.55 m to 2.25 m while the roughness in ULPS does not move, then the
## amplitude is set by the store's resolution and by nothing else - and anything that shrinks the
## ulp shrinks the vibration in proportion.
##
## Section 2 - SEED OR STORE. A one-off perturbation left over from the fill decays at the drag
## rate: ten seconds is seven half-lives, a factor of 130. A per-step injection reaches a floor and
## stays there. Run a bowl - a bed with a real shore, where the seed is genuinely rough because
## every cell has a different depth and therefore a different lattice - and watch the shape.

var _rip: Node = null
var _lab: Node = null


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
	_rip.call("sim_set", &"drag", 0.7)
	_rip.set("depth_mode", true)
	_rip.set("staggered", true)
	_rip.set("edge_mode", 1)

	print("[ULP] ---- section 1: flat pan, seep 0.001, dither on, 600 steps ----")
	print("[ULP] %6s %10s %10s %10s" % ["depth", "ulp mm", "rough mm", "rough ulp"])
	_lab.get_node("Bed").set("profile", 0)
	_rip.call("sim_set", &"seep", 0.001)
	_rip.call("sim_set", &"dither_gain", 1.0)
	for d: float in [0.55, 1.1, 2.25, 4.5]:
		_lab.get_node("Bed").set("bed_depth", d)
		_lab.call("_rebuild")
		var ulp: float = pow(2.0, floor(log(d) / log(2.0)) - 10.0)
		await _reset_run(600)
		var r := _rough(int(_rip.get("RES")))
		print("[ULP] %6.2f %10.4f %10.4f %10.2f" % [d, ulp * 1000.0, r * 1000.0, r / ulp])

	print("[ULP] ---- section 2: bowl 2.25 m, roughness (ulp) at step 0,15,60,150,300,600,1200 ----")
	_lab.get_node("Bed").set("profile", 3)
	_lab.get_node("Bed").set("bed_depth", 2.25)
	_lab.call("_rebuild")
	var ulp2: float = pow(2.0, floor(log(2.25) / log(2.0)) - 10.0)
	for cfg: Array in [[0.001, 1.0], [0.0, 1.0], [0.001, 0.0], [0.0, 0.0]]:
		_rip.call("sim_set", &"seep", cfg[0])
		_rip.call("sim_set", &"dither_gain", cfg[1])
		await _lab.call("_reset", false)
		var line := "[ULP] seep %.4f dither %.0f:" % [cfg[0], cfg[1]]
		var at := 0
		for n: int in [0, 15, 60, 150, 300, 600, 1200]:
			await _run(n - at)
			at = n
			line += " %6.2f" % (_rough(int(_rip.get("RES"))) / ulp2)
		print(line)
	quit(0)


func _reset_run(n: int) -> void:
	await _lab.call("_reset", false)
	await _run(n)


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")


## Mean |w - mean of the four neighbours| over the interior, in metres.
func _rough(res: int) -> float:
	_lab.call("_read_back")
	var img: Image = _lab.get("_state_img")
	if img == null:
		return 0.0
	var lo := res / 4
	var hi := res * 3 / 4
	var w := PackedFloat32Array()
	w.resize(res * res)
	for i in res * res:
		w[i] = -1e9
	for z in range(lo - 1, hi + 1):
		for x in range(lo - 1, hi + 1):
			var d: float = img.get_pixel(x, z).r
			if d > 0.0:
				w[z * res + x] = float(_lab.call("_bed_at", Vector2i(x, z), res)) + d
	var total := 0.0
	var n := 0.0
	for z in range(lo, hi):
		for x in range(lo, hi):
			var i := z * res + x
			if w[i] < -1e8:
				continue
			var s := 0.0
			var k := 0
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var j := (z + o.y) * res + (x + o.x)
				if w[j] < -1e8:
					continue
				s += w[j]
				k += 1
			if k == 0:
				continue
			total += absf(w[i] - s / float(k))
			n += 1.0
	return total / maxf(n, 1.0)
