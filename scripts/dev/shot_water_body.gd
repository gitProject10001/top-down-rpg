extends SceneTree
## PHOTOGRAPH THE WATER CLOSE UP, where the artifacts live.
##
##   Godot_console.exe --path . --resolution 1200x1200 \
##       --script res://scripts/dev/shot_water_body.gd -- --out=C:/Users/jonny/Desktop/shots
##
## shot_water_lab.gd frames the whole lake from twenty metres up, which is the right picture for
## "is there water and is it the right depth" and the wrong one for every question actually being
## asked now. The reported artifacts are all at the scale of a body: a black wedge along an
## obstacle wall, a sawtooth ring around a cylinder, a blocky checker on open water. None of them
## survives being photographed from far enough away to see the shoreline.
##
## So this stands the camera in the water and takes the same three framings the report did, and
## prints the numbers beside each one - because "it looks better" is the claim that has been wrong
## most often on this branch, and a picture with no measurement beside it is exactly that claim.

var _out := "user://"
var _rip: Node = null
var _terr: Node3D = null
var _mid := Vector3.ZERO
var _surf := 0.0
var _bed := 0.0
var _cam: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var lab := (load("res://scenes/dev/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 90:
		await process_frame
	_rip = root.get_node("/root/Ripples")

	var zone := get_first_node_in_group("zone") as Node3D
	_terr = zone.get_node_or_null("Terrain") as Node3D if zone != null else null
	var m: Object = zone.get("built_map") if zone != null else null
	if _terr == null or m == null:
		print("[BODY] FAIL: no wilds terrain")
		quit(1)
		return
	var mid_local := Vector2(35.0, 33.5) * float(m.cell_size)
	_mid = _terr.to_global(Vector3(mid_local.x, 0.0, mid_local.y))
	_surf = float(_terr.water_surface_y(mid_local))
	_bed = float(_terr.water_bed_y(mid_local))
	# THE MIDDLE OF THE LAKE IS AT THE WATERLINE, not at the terrain node's origin. to_global of a
	# map cell answers the terrain's own Y, which here is a metre below the surface - so every
	# camera placed relative to it was UNDERWATER, and the first close-up came back looking up
	# through the underside of the lake at an upside-down world.
	_mid.y = _surf
	print("[BODY] lake mid %.1f,%.1f  surface %.3f  bed %.3f  column %.3f"
			% [_mid.x, _mid.z, _surf, _bed, _surf - _bed])

	# PIN THE SIM WINDOW TO THE LAKE. The window follows the player, and the player is standing on
	# the shore where water_lab puts it - so without this the close-ups would be photographing the
	# rim fade instead of the water.
	var anchor := Node3D.new()
	lab.add_child(anchor)
	anchor.global_position = _mid
	_rip.set("focus_override", anchor)
	_rip.set("paused", true)

	# TAKE THE CAMERA OFF WHATEVER IS DRIVING IT. The first run of this probe placed the camera
	# exactly where it was asked to and photographed the whole lake from twenty metres up anyway,
	# because CameraRig follows the player every frame and puts it back. A shot probe that politely
	# asks for a viewpoint gets the scene's viewpoint.
	for n in root.find_children("*", "Node3D", true, false):
		if n.name == "CameraRig":
			(n as Node3D).set_process(false)
			(n as Node3D).set_physics_process(false)
	_cam = root.find_children("FlyCam", "Camera3D", true, false).front() as Camera3D
	if _cam == null:
		print("[BODY] FAIL: no FlyCam to borrow")
		quit(1)
		return
	_cam.set_process(false)
	_cam.set_physics_process(false)
	_cam.current = true
	_cam.fov = 55.0
	# The HUD is not the subject. Hidden rather than deleted, so nothing else notices.
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false

	# AND LET THE BASIN SETTLE. A freshly seeded wilds lake rings for tens of seconds; 240 steps in
	# it was still swinging by most of a metre, which would have been photographed as "the water".
	await _run_steps(1800)

	# ---- THE QUIET LAKE. No body, no solid, nothing moving: whatever texture is visible here is
	# the surface's own, and it is the control every other picture is read against.
	await _frame("quiet", _mid + Vector3(-3.5, 1.1, 3.5), _mid + Vector3(0.0, -0.2, 0.0))
	_report("quiet")

	# ---- A CYLINDER, the shape the report called perfect, and the one with the sawtooth ring.
	var cyl: int = _rip.call("obstacle_add", 0, Vector2(_mid.x, _mid.z), Vector2(0.6, 0.6),
			_surf + 0.35)
	await _run_steps(90)
	await _frame("cylinder", _mid + Vector3(-2.6, 0.85, 2.6), _mid + Vector3(0.0, -0.15, 0.0))
	_report("cylinder")

	# ---- A BOX WALL, which is where the black wedge was photographed. A tall box so the wall runs
	# well above the surface, exactly as in the report.
	_rip.call("obstacle_remove", cyl)
	var box: int = _rip.call("obstacle_add", 1, Vector2(_mid.x, _mid.z), Vector2(1.6, 1.6),
			_surf + 2.5)
	await _run_steps(90)
	await _frame("box_wall", _mid + Vector3(-4.2, 1.0, 0.6), _mid + Vector3(-1.4, 0.0, 0.0))
	_report("box_wall")
	_rip.call("obstacle_remove", box)

	# ---- A BODY WALKING, which is the thing this is all for. Same solid the wader registers:
	# a 0.45 m cylinder whose top face sits just proud of the surface.
	# TOP BELOW THE WATERLINE, exactly as water_wader registers it. Above it the solid is emergent,
	# the solver keeps its cells dry and the surface is cut at its outline - a player standing in a
	# crater. This is the shipped geometry, so the picture is of the shipped thing.
	var body: int = _rip.call("obstacle_add", 0, Vector2(_mid.x - 7.0, _mid.z),
			Vector2(0.45, 0.45), _surf - 0.08)
	var x := -7.0
	while x < 0.0:
		x += 5.0 / 60.0
		_rip.call("obstacle_move", body, Vector2(_mid.x + x, _mid.z))
		await _run_steps(1)
	await _frame("body_wake", _mid + Vector3(-3.0, 1.3, 4.0), _mid + Vector3(-1.5, -0.2, 0.0))
	_report("body_wake")
	# CLOSE ENOUGH TO SEE WHETHER THE WATER TOUCHES IT. The crater was only obvious from a couple of
	# metres away, so a frame from twenty is not evidence that it has gone.
	await _frame("body_close", _mid + Vector3(0.6, 0.45, 1.3), _mid + Vector3(0.0, -0.1, 0.0))
	# And from above, where a wake reads as a wake rather than as a slope.
	await _frame("body_wake_top", _mid + Vector3(-3.0, 7.0, 0.4), _mid + Vector3(-2.5, 0.0, 0.0))
	_report("body_wake_top")

	quit(0)


## Surface statistics for the picture just taken: the wave the body made, and the grid-scale
## roughness underneath it. One is the point of the exercise and the other is the complaint.
func _report(tag: String) -> void:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	var bd: Image = (_rip.call("bed_texture") as Texture2D).get_image()
	if img == null or bd == null:
		return
	var res := img.get_width()
	var fres := bd.get_width()
	var org: Vector2 = _rip.call("window_origin")
	var t: float = float(_rip.get("SIZE_M")) / float(res)
	var lo := 1e9
	var hi := -1e9
	var rough := 0.0
	var n := 0
	for z in range(2, res - 2):
		for x in range(2, res - 2):
			var w := org + Vector2(float(x) + 0.5, float(z) + 0.5) * t
			# Open water within 10 m of the middle: near enough to hold the wake, far enough from
			# the shore that the shoreline's own structure is not being reported as roughness.
			if (w - Vector2(_mid.x, _mid.z)).length() > 10.0:
				continue
			var c := _surf_at(img, bd, x, z, res, fres)
			if c <= -1e8:
				continue
			var s := 0.0
			var k := 0
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var v := _surf_at(img, bd, x + o.x, z + o.y, res, fres)
				if v > -1e8:
					s += v
					k += 1
			if k < 4:
				continue
			lo = minf(lo, c)
			hi = maxf(hi, c)
			rough += absf(c - s / float(k))
			n += 1
	if n == 0:
		return
	var ulp: float = pow(2.0, floor(log(maxf(_surf - _bed, 1e-3)) / log(2.0)) - 10.0)
	print("[BODY] %-14s wave %6.1f mm p-p   grid roughness %5.2f mm (%.2f ulp)   over %d texels"
			% [tag, (hi - lo) * 1000.0, rough / float(n) * 1000.0, rough / float(n) / ulp, n])


func _surf_at(img: Image, bd: Image, x: int, z: int, res: int, fres: int) -> float:
	var h: float = img.get_pixel(clampi(x, 0, res - 1), clampi(z, 0, res - 1)).r
	if h <= 0.002:
		return -1e9
	var b := _bed_bilinear(bd, clampi(x, 0, res - 1), clampi(z, 0, res - 1), res, fres)
	if b > 500.0:
		return -1e9
	return b + h


## The solver's own bilinear bed. Reading it NEAREST here would measure this probe's reconstruction
## error instead of the water, which on a steep shore is centimetres - the size of the answer.
func _bed_bilinear(bd: Image, cx: int, cz: int, res: int, fres: int) -> float:
	var t := Vector2((float(cx) + 0.5) / float(res) * float(fres) - 0.5,
			(float(cz) + 0.5) / float(res) * float(fres) - 0.5)
	var i0 := Vector2i(floori(t.x), floori(t.y))
	var fr := t - Vector2(i0)
	var q := PackedFloat32Array([0, 0, 0, 0])
	var top := -1e9
	for k in 4:
		var p := Vector2i(clampi(i0.x + (k & 1), 0, fres - 1), clampi(i0.y + (k >> 1), 0, fres - 1))
		q[k] = bd.get_pixel(p.x, p.y).r
		top = maxf(top, q[k])
	if top > 500.0:
		return bd.get_pixel(clampi(cx * fres / res, 0, fres - 1),
				clampi(cz * fres / res, 0, fres - 1)).r
	return lerpf(lerpf(q[0], q[1], fr.x), lerpf(q[2], q[3], fr.x), fr.y)


func _frame(tag: String, eye: Vector3, look: Vector3) -> void:
	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := _out + "body_%s.png" % tag
	print("[BODY] %-14s -> %s" % [tag, path if img.save_png(path) == OK else "SAVE FAILED"])


func _run_steps(steps: int) -> void:
	for _i in steps:
		_rip.call("step_once")
		await process_frame
