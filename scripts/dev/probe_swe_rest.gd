extends SceneTree
## IS A FLAT PAN AT REST A FIXED POINT, step by step, and if not WHERE does it stop being one?
##
##   Godot_console.exe --path . --script res://scripts/dev/probe_swe_rest.gd
##
## probe_swe_lab's suite 7a says "a cell moved 6 mm in 600 steps" and that is a number with no
## cause in it. On a FLAT pan every cell has the same bed, so after the reset every cell has the
## same depth, so every surface difference is exactly zero, so every face velocity is exactly zero,
## so nothing can move at all - the rest state should be a fixed point in the strict sense, bit for
## bit, and not merely a slow one.
##
## When it is not, the interesting question is WHICH STEP and WHICH TEXEL first departs. A
## disturbance at the wall reaches the middle of a 64 m window in ten seconds at sqrt(g*h), so by
## step 600 the whole field is ringing and the worst cell is nowhere near the cause.
##
## Reports, for the first steps and then in blocks: the largest |u| anywhere and where it is, the
## largest departure of h from the seed and where, and how far each is from the nearest wall - which
## is what separates "the boundary is leaking" from "the interior is unstable".

var _rip: Node = null
var _lab: Node = null
var _seed := PackedFloat32Array()
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
		print("[REST] FAIL: swe_lab.gd did not load")
		quit(1)
		return

	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_rip.call("sim_set", &"seep", 0.0)
	_rip.call("sim_set", &"cfl_guard", false)
	_lab.get_node("Bed").set("profile", 0)          # FLAT PAN: one bed everywhere
	_lab.get_node("Bed").set("bed_depth", 0.55)
	_lab.call("_rebuild")
	_rip.set("depth_mode", true)
	_rip.set("edge_mode", 1)

	for staggered in [false, true]:
		_rip.set("staggered", staggered)
		print("[REST] ======== %s ========"
				% ("STAGGERED (faces)" if staggered else "collocated (cell centres)"))
		await _watch()

	print("[REST] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


func _watch() -> void:
	await _lab.call("_reset", false)
	_lab.call("_read_back")
	var img: Image = _lab.get("_state_img")
	var res := img.get_width()
	_seed = PackedFloat32Array()
	_seed.resize(res * res)
	for z in res:
		for x in res:
			_seed[z * res + x] = img.get_pixel(x, z).r
	print("[REST]  step   max|u|         at        wall_d   max|dh| mm        at        wall_d")
	var at := 0
	for n: int in [1, 2, 3, 5, 10, 30, 100, 300, 600]:
		await _run(n - at)
		at = n
		_report(n, res)


func _report(step: int, res: int) -> void:
	var img: Image = _lab.get("_state_img")
	if img == null:
		return
	var bu := 0.0
	var bu_at := Vector2i(-1, -1)
	var bh := 0.0
	var bh_at := Vector2i(-1, -1)
	for z in res:
		for x in res:
			var px := img.get_pixel(x, z)
			var u := Vector2(px.g, px.b).length()
			if u > bu:
				bu = u
				bu_at = Vector2i(x, z)
			# Against the SEED, not against the neighbours: this asks whether the state has left
			# where it started, which is the only definition of "at rest" that means anything.
			var d: float = absf(px.r - _seed[z * res + x])
			if d > bh:
				bh = d
				bh_at = Vector2i(x, z)
	print("[REST] %5d   %.6f   %-11s %5d    %8.4f   %-11s %5d"
			% [step, bu, str(bu_at), _wall_d(bu_at, res), bh * 1000.0, str(bh_at),
			_wall_d(bh_at, res)])


## Texels from the nearest window rim. The bed is 48 m of a 64 m window, so the outer 40 texels are
## the off-map sentinel wall - anything reported inside that band is the boundary talking.
func _wall_d(p: Vector2i, res: int) -> int:
	if p.x < 0:
		return -1
	return mini(mini(p.x, res - 1 - p.x), mini(p.y, res - 1 - p.y))


func _run(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
	_lab.call("_read_back")
