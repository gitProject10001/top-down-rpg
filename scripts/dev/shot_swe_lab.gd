extends SceneTree
## PHOTOGRAPH THE BENCH, and count what is in the picture.
##
##   Godot_console.exe --path . --resolution 1600x900 \
##       --script res://scripts/dev/shot_swe_lab.gd -- --out=C:/some/folder
##
## Everything else about the depth solver is verified by numbers that never leave the GPU. This is
## the one check that the numbers reach the screen, and it exists because the complaint that
## started this work - "the lab is a plane, there is no terrain lakebed" - was invisible to every
## probe in the project. The solver was fine. The picture was a flat blue sheet at a fixed height
## with the bed hidden underneath it, and no assertion anywhere was looking at the picture.
##
## SO IT COUNTS PIXELS, in three states that must differ:
##
##   EMPTY    the bed is bare. Mostly terrain, almost no water.
##   PART     a source has run a while. Water in the low ground, terrain still visible on the high.
##   FULL     seeded at rest. Water over most of the basin.
##
## The classifier is deliberately crude - blue channel against red - because a subtle one would be
## measuring its own thresholds. Terrain is a grey checker (r == b) and water is blue (b > r), and
## nothing in the scene is otherwise.

var _out := "user://"
var _rip: Node = null
var _fail := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var lab := (load("res://scenes/dev/swe_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 30:
		await process_frame
	_rip = root.get_node("/root/Ripples")
	lab.set("_live", false)
	# DELIBERATELY SETS NOTHING ABOUT THE SOLVER. This probe is the one that opens the scene the way
	# a person does, and the bug it exists to catch was exactly a default: the bench started in the
	# encoding it was built to replace, the surface shader read that encoding's channel as a depth,
	# and it discarded itself entirely. The solver ran, the overlay filled, the volume climbed, and
	# the 3D view was empty. Asserting the defaults here is the point.
	if not bool(_rip.get("depth_mode")):
		print("[SHOT] FAIL: the bench does not open in depth mode - the surface will draw nothing")
		_fail += 1
	if int(_rip.get("edge_mode")) != 1:
		print("[SHOT] FAIL: the bench does not open as a closed box")
		_fail += 1
	lab.set("_source_on", false)
	lab.call("_rebuild")

	# What is actually in the 3D scene, before anything is photographed.
	var cam: Camera3D = lab.get_node("FlyCam")
	print("[SHOT] camera at %s looking %s, fov %.0f, current %s"
			% [cam.global_position, -cam.global_transform.basis.z, cam.fov, cam.current])
	for ch in lab.get_node("Bed").get_children():
		var mi := ch as MeshInstance3D
		print("[SHOT] Bed child %-12s %-16s visible=%s%s"
				% [ch.name, ch.get_class(), ch.get("visible"),
				"  surfaces=%d aabb=%s" % [mi.mesh.get_surface_count(), mi.get_aabb()]
				if mi != null and mi.mesh != null else ""])
	for ch in lab.get_children():
		if ch is Node3D:
			print("[SHOT] lab child %-14s %s at %s" % [ch.name, ch.get_class(),
					(ch as Node3D).global_position])

	await _reset(lab, true)
	var empty: Array = await _classify("empty")

	# Fill it. A strong source at the centre of the bowl, which is where the bench should have had
	# one all along - the shipped placement straddled the upstream waterline.
	lab.set("_source_on", true)
	lab.call("_rebuild")
	await _reset(lab, true)
	await _run_steps(lab, 900)
	var part: Array = await _classify("partly filled")

	lab.set("_source_on", false)
	lab.call("_rebuild")
	await _reset(lab, false)
	var full: Array = await _classify("full")

	# THE SHORELINE, close and low. The wide shot cannot show what a waterline is DOING - the
	# vertical curtains at every bed step were invisible from 42 m and obvious from four, which is
	# where the report came from. A bench that only ever photographs itself from the establishing
	# shot will keep missing that class of thing.
	# Outside the basin, looking down on the waterline at a shallow angle - the angle a vertical
	# artifact shows at and an overhead shot hides.
	cam.global_position = Vector3(0.0, 2.0, 25.0)
	cam.look_at(Vector3(0.0, -0.4, 19.5), Vector3.UP)
	await _classify("shore")
	cam.global_position = Vector3(0.0, 24.0, 34.56)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	# THE ASSERTIONS, and they are about the PICTURE rather than the state.
	if empty[0] < 0.20:
		print("[SHOT] FAIL: an empty basin shows almost no terrain (%.1f%%) - the bed is hidden"
				% (empty[0] * 100.0))
		_fail += 1
	if empty[1] > 0.03:
		print("[SHOT] FAIL: an empty basin is %.1f%% water - the surface is drawing where there "
				% (empty[1] * 100.0) + "is none")
		_fail += 1
	if full[1] <= empty[1] + 0.10:
		print("[SHOT] FAIL: full and empty look the same (%.1f%% vs %.1f%% water). This is the "
				% [full[1] * 100.0, empty[1] * 100.0]
				+ "original complaint, and it is back")
		_fail += 1
	if part[1] <= empty[1] + 0.01 or part[1] >= full[1] + 0.05:
		print("[SHOT] FAIL: filling does not read as between empty and full "
				+ "(%.1f%% vs %.1f%% vs %.1f%%)" % [empty[1] * 100.0, part[1] * 100.0,
				full[1] * 100.0])
		_fail += 1

	print("[SHOT] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


## Save the frame and report what fraction of it is terrain and what fraction is water. Returns
## [terrain, water] as fractions of the whole image.
func _classify(tag: String) -> Array:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := _out + "swe_lab_%s.png" % tag.replace(" ", "_")
	var saved := img.save_png(path) == OK
	var terrain := 0
	var water := 0
	var n := 0
	# SKIP THE SKY, by geometry rather than by colour. The procedural sky is the same HUE as water
	# - blue channel above red - so no honest colour test separates them, and the camera here is
	# fixed, so the horizon is a fixed row. Everything above it is sky by construction.
	var horizon := int(float(img.get_height()) * 0.12)
	for y in range(horizon, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y)
			# Skip the UI panels, which are near-black, and the sky, which is bright and blue but
			# sits in the top band only. Counting them would swamp the thing being measured.
			if c.r + c.g + c.b < 0.25:
				continue
			n += 1
			if c.b > c.r + 0.06:
				water += 1
			elif absf(c.b - c.r) <= 0.06:
				terrain += 1
	var tf := float(terrain) / maxf(float(n), 1.0)
	var wf := float(water) / maxf(float(n), 1.0)
	print("[SHOT] %-14s terrain %5.1f%%   water %5.1f%%   (%s)"
			% [tag, tf * 100.0, wf * 100.0, path if saved else "SAVE FAILED"])
	return [tf, wf]


func _reset(lab: Node, empty: bool) -> void:
	await lab.call("_reset", empty)
	await _run_steps(lab, 2)


func _run_steps(lab: Node, steps: int) -> void:
	for _i in steps:
		lab.call("_feed_sink", 1)
		_rip.call("step_once")
		await process_frame
