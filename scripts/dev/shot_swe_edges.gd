extends SceneTree
## THE BORDER ARTIFACTS, ON A BED WITH NOTHING ELSE ON IT.
##
##   Godot_console.exe --path . --resolution 1200x1200 \
##       --script res://scripts/dev/shot_swe_edges.gd -- --out=C:/Users/jonny/Desktop/shots
##
## shot_water_body.gd photographs the wilds lake, which is the right place to ask whether the game
## looks right and the wrong place to ask WHY it does not: a waterfall, a raft, a shoreline and a
## staircase of tiers are all in frame, and any of them could be making the marks. This puts a
## cylinder and a box on a FLAT PAN with a drawn mesh for each, so anything left in the picture is
## the renderer's, and the bench draws the solids so the eye can see where the water should stop.
##
## The framings are the reported ones: down the wall of a box, and low across a cylinder.

const DEPTH := 1.04

var _out := "user://"
var _rip: Node = null
var _lab: Node = null
var _cam: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	_lab = (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(_lab)
	current_scene = _lab
	for _i in 60:
		await process_frame
	_rip = root.get_node("/root/Ripples")

	_lab.set("_live", false)
	_lab.set("_source_on", false)
	_lab.set("_sink_on", false)
	_lab.get_node("Bed").set("profile", 0)              # FLAT_PAN: no shore, no slope, no steps
	_lab.get_node("Bed").set("bed_depth", DEPTH)
	_lab.get_node("Bed").set("extent", float(_rip.get("SIZE_M")))
	_lab.call("_rebuild")
	_rip.set("depth_mode", true)
	_rip.set("staggered", true)
	_rip.set("edge_mode", 1)
	_rip.set("reset_empty", false)
	_rip.set("paused", true)
	_rip.call("sim_set", &"wave_scale", 0.35)
	_rip.call("sim_set", &"smooth_grid", 0.30)
	_rip.call("sim_set", &"ripple_kill", 0.008)
	_rip.call("reset_now")

	var anchor := Node3D.new()
	_lab.add_child(anchor)
	anchor.global_position = Vector3.ZERO
	_rip.set("focus_override", anchor)
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	_cam = root.find_children("*", "Camera3D", true, false).front() as Camera3D
	_cam.set_process(false)
	_cam.set_physics_process(false)
	_cam.current = true
	_cam.fov = 50.0
	await _step(240)

	print("[EDGE] flat pan %.2f m, dx %.2f m - anything in these pictures is the renderer's"
			% [DEPTH, float(_rip.get("SIZE_M")) / float(_rip.get("RES"))])

	# A CYLINDER STANDING PROUD, low camera - the framing the sawtooth ring was reported in.
	var cyl: int = _rip.call("obstacle_add", 0, Vector2(0.0, 0.0), Vector2(0.6, 0.6), 0.35)
	await _step(120)
	await _frame("cyl_low", Vector3(-2.2, 0.55, 2.2), Vector3(0.0, -0.1, 0.0))
	# WITH THE WATER TAKEN AWAY. Two large translucent panes hang below the surface beside the
	# cylinder, and turning dry_skirt to zero did not move them - so before theorising about which
	# vertex rule puts them there, establish whether they are the water surface at all.
	_veil(false)
	await _frame("cyl_nowater", Vector3(-2.2, 0.55, 2.2), Vector3(0.0, -0.1, 0.0))
	_veil(true)
	await _frame("cyl_top", Vector3(-0.6, 4.5, 0.6), Vector3(0.0, 0.0, 0.0))
	_rip.call("obstacle_remove", cyl)

	# A BOX WALL, the framing the black wedge was reported in: a tall face meeting the water.
	var box: int = _rip.call("obstacle_add", 1, Vector2(0.0, 0.0), Vector2(1.2, 1.2), 2.5, 0.4)
	await _step(120)
	await _frame("box_wall", Vector3(-3.4, 0.65, 1.2), Vector3(-1.0, 0.05, 0.2))
	_rip.call("obstacle_remove", box)

	# A SUBMERGED SOLID - a hull's draft. There must be water OVER this, not a hole in the lake.
	var reef: int = _rip.call("obstacle_add", 1, Vector2(0.0, 0.0), Vector2(0.5, 1.1),
			-DEPTH + 0.12, 0.3)
	await _step(120)
	await _frame("submerged", Vector3(-2.6, 1.0, 2.6), Vector3(0.0, -0.2, 0.0))
	print("[EDGE] submerged: %s" % _over_solid())
	_rip.call("obstacle_remove", reef)

	# A MOVING BODY, the wader's own solid, mid-stride.
	# TOP BELOW THE WATERLINE, as water_wader registers it. Above it the solid is emergent: the
	# solver keeps its cells dry and the surface is cut at its outline, which is a player standing
	# in a crater with the lake held off at arm's length.
	var body: int = _rip.call("obstacle_add", 0, Vector2(-6.0, 0.0), Vector2(0.25, 0.25), -0.08)
	var x := -6.0
	while x < 0.0:
		x += 5.0 / 60.0
		_rip.call("obstacle_move", body, Vector2(x, 0.0))
		await _step(1)
	# WHAT IS ACTUALLY AT THE BOW. The ring of dark teeth there survived both submergence depths and
	# survived bridging the dry film, which rules out both explanations - so measure it instead of
	# proposing a third. If nothing inside the disc is dry, the teeth are not a hole.
	_bow_report(0.0, 0.45)
	await _frame("body_low", Vector3(-3.2, 0.7, 2.8), Vector3(0.4, -0.1, 0.0))
	# EYE-LEVEL WITH THE WATERLINE, a metre off. The crater was only obvious this close, so a frame
	# from four metres is not evidence that it has gone.
	await _frame("body_close", Vector3(-1.0, 0.22, 0.9), Vector3(0.05, -0.02, 0.0))
	await _frame("body_top", Vector3(-1.5, 6.0, 0.4), Vector3(-1.0, 0.0, 0.0))
	_rip.call("obstacle_remove", body)

	# THE SAME BODY AT WALKING PACE, and this is the test of the explanation rather than a prettier
	# picture. The ring at the bow is claimed to be a SUPERCRITICAL shock: at wave_scale 0.35 the
	# celerity in a 1.04 m lake is 1.89 m/s, so a 5 m/s jog is Froude 2.6 and a 1.5 m/s walk is 0.8.
	# If the claim is right the ring must be absent here. If it is still there, it is not a shock.
	_rip.call("reset_now")
	await _step(240)
	var slow: int = _rip.call("obstacle_add", 0, Vector2(-4.0, 0.0), Vector2(0.25, 0.25), -0.08)
	x = -4.0
	while x < 0.0:
		x += 1.5 / 60.0
		_rip.call("obstacle_move", slow, Vector2(x, 0.0))
		await _step(1)
	_bow_report(0.0, 0.45)
	await _frame("body_walk_top", Vector3(-1.5, 6.0, 0.4), Vector3(-1.0, 0.0, 0.0))

	# ---- THE LOOK ROUTE, and this is its whole acceptance test: assigning a resource must change
	# the water, without touching a shader file or a solver dial. Before this existed the surface's
	# appearance uniforms were written by nothing in the project and ran on compiled-in defaults.
	var win: Node3D = _lab.get("_window")
	if win == null:
		print("[EDGE] FAIL: no WaterWindow to hand a look to")
	else:
		var look := WaterLook.new()
		# A lagoon: clear enough to read the bed through a metre of it, and a saturated ramp.
		look.shallow_color = Color(0.55, 0.86, 0.80, 1.0)
		look.deep_color = Color(0.02, 0.42, 0.55, 1.0)
		look.absorb = 2.6
		look.shallow_alpha = 0.04
		look.max_alpha = 0.80
		win.set("look", look)
		await _step(2)
		await _frame("look_lagoon", Vector3(-2.2, 0.55, 2.2), Vector3(0.0, -0.1, 0.0))
		win.set("look", null)

	quit(0)


## What the field holds inside and just around a body's footprint: how many cells are dry, and how
## far the surface swings. A hole and a steep bow wave look identical from a camera and want
## opposite fixes.
func _bow_report(cx: float, r: float) -> void:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	var res := img.get_width()
	var org: Vector2 = _rip.call("window_origin")
	var t: float = float(_rip.get("SIZE_M")) / float(res)
	var dry := 0
	var inside := 0
	var lo := 1e9
	var hi := -1e9
	var ring_lo := 1e9
	var ring_hi := -1e9
	for z in res:
		for x in res:
			var w := org + Vector2(float(x) + 0.5, float(z) + 0.5) * t
			var d := (w - Vector2(cx, 0.0)).length()
			var h: float = img.get_pixel(x, z).r
			if d <= r:
				inside += 1
				if h <= 0.002:
					dry += 1
				lo = minf(lo, h)
				hi = maxf(hi, h)
			elif d <= r + 3.0 * t:
				ring_lo = minf(ring_lo, h)
				ring_hi = maxf(ring_hi, h)
	print("[EDGE] bow: %d texels inside the body, %d of them DRY;  h inside [%.3f, %.3f], "
			% [inside, dry, lo, hi] + "h in the ring just outside [%.3f, %.3f]"
			% [ring_lo, ring_hi])


## Is there water standing on the submerged solid, or a hole where the lake should be? Read off the
## state texture rather than off the picture, because "I think I can see water there" is not a test.
func _over_solid() -> String:
	var img: Image = (_rip.call("debug_texture") as Texture2D).get_image()
	var res := img.get_width()
	var org: Vector2 = _rip.call("window_origin")
	var t: float = float(_rip.get("SIZE_M")) / float(res)
	var lo := 1e9
	var n := 0
	for z in res:
		for x in res:
			var w := org + Vector2(float(x) + 0.5, float(z) + 0.5) * t
			if absf(w.x) > 0.35 or absf(w.y) > 0.8:
				continue
			lo = minf(lo, float(img.get_pixel(x, z).r))
			n += 1
	if n == 0:
		return "no texels over the solid - the geometry is wrong"
	return "%.3f m of water over a solid drawing 0.12 m of a %.2f m column (want ~%.2f)" \
			% [lo, DEPTH, DEPTH - 0.12]


## Show or hide every mesh drawn with the water-surface shader, and report how many there are -
## because "the water" being two overlapping surfaces would itself explain a great deal.
func _veil(on: bool) -> void:
	var n := 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat == null and mi.mesh != null:
			mat = mi.mesh.surface_get_material(0) as ShaderMaterial if mi.mesh.get_surface_count() > 0 else null
		if mat != null and mat.shader != null and mat.shader.resource_path.contains("water_surface"):
			mi.visible = on
			n += 1
	print("[EDGE] water-surface meshes: %d (%s)" % [n, "shown" if on else "hidden"])


func _frame(tag: String, eye: Vector3, look: Vector3) -> void:
	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := _out + "edge_%s.png" % tag
	print("[EDGE] %-12s -> %s" % [tag, path if img.save_png(path) == OK else "SAVE FAILED"])


func _step(n: int) -> void:
	for _i in n:
		_rip.call("step_once")
		await process_frame
