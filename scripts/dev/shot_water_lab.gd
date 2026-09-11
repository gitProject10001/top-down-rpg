extends SceneTree
## PHOTOGRAPH THE WATER LAB, and count what is in the picture.
##
##   Godot_console.exe --path . --resolution 1600x900 \
##       --script res://scripts/dev/shot_water_lab.gd -- --out=C:/some/folder
##
## The swe bench runs the solver over an ANALYTIC bed - a bowl, a ramp, a valley written as
## arithmetic. This one runs it over terrain the WILDS ADDON GENERATED: the same painted map, the
## same tiers, the same shoreline the game builds, through the same SweTerrain seam. That is the
## difference between "the solver works" and "the solver works on our water", and only one of them
## is a statement about the game.
##
## It also reports what the wilds actually handed the solver - the lake's bed, its surface and the
## column between them - because a lake that renders beautifully at 0.55 m deep is a puddle, and
## the picture alone will not say so.

var _out := "user://"
var _rip: Node = null
var _fail := 0


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

	# WHICH SOLVER IS ACTUALLY RUNNING. The bench asks for the staggered depth solver in _ready;
	# if something reset it the picture below would still look like water and would be the old
	# encoding, which is exactly the class of thing that went unnoticed for a week on the swe bench.
	print("[WLAB] depth_mode %s   staggered %s   advect %s   edge_mode %d"
			% [_rip.get("depth_mode"), _rip.get("staggered"), _rip.get("advect"),
			int(_rip.get("edge_mode"))])
	if not bool(_rip.get("depth_mode")) or not bool(_rip.get("staggered")):
		print("[WLAB] FAIL: the water lab is not running the solver it says it runs")
		_fail += 1

	# WHAT THE WILDS HANDED THE SOLVER. Straight off the terrain contract through the seam, at the
	# middle of the painted lake.
	var zone := get_first_node_in_group("zone") as Node3D
	var terr := zone.get_node_or_null("Terrain") as Node3D if zone != null else null
	var m: Object = zone.get("built_map") if zone != null else null
	if terr != null and m != null:
		# MAP CELLS TIMES cell_size ARE ALREADY THE TERRAIN'S LOCAL FRAME. Building a world
		# position out of them and then calling to_local applies the transform twice, which walked
		# the sample off the map and got back BED_WALL and a NAN surface - the honest answer to a
		# question about a place that does not exist.
		var mid := Vector2(35.0, 33.5) * float(m.cell_size)
		var surf: float = terr.water_surface_y(mid)
		var bed: float = terr.water_bed_y(mid)
		var dep: float = terr.water_depth_at(mid)
		print("[WLAB] lake mid-water: surface %.3f m, bed %.3f m, column %.3f m "
				% [surf, bed, dep] + "(map.lake_depth %.2f)" % float(m.lake_depth))
		if dep < 0.8:
			print("[WLAB] FAIL: the painted lake is %.2f m deep - that is a puddle, not a lake"
					% dep)
			_fail += 1
		# AND IT HAS TO STAY WADEABLE. There is no swim state in this game, so a lake deeper than a
		# person is not a deeper lake, it is a drowned player - which is exactly what happened when
		# this was set to a 2.25 m column. The bound is the character, not the solver, and it binds
		# a long way before the solver's 7.34 m does.
		if dep > 1.20:
			print("[WLAB] FAIL: the lake is %.2f m deep and this world has NO SWIMMING - the "
					% dep + "player walks in and goes under. Lower WildsMap.lake_depth.")
			_fail += 1
		# The solver's own ceiling. Painting deeper than it can hold does not look wrong, it
		# saturates float16 and stops being water.
		var dx: float = float(_rip.get("SIZE_M")) / float(_rip.get("RES"))
		var ceiling: float = 0.5 * dx * dx / (9.81 * pow(1.0 / 60.0, 2.0))
		print("[WLAB] solver ceiling %.2f m, lake uses %.0f%% of it" % [ceiling,
				dep / maxf(ceiling, 1e-6) * 100.0])
		if dep > ceiling:
			print("[WLAB] FAIL: the lake is deeper than the solver can hold")
			_fail += 1
	else:
		print("[WLAB] FAIL: no zone or built map - the wilds terrain did not come up")
		_fail += 1

	var cam := _camera()
	if cam != null:
		cam.global_position = Vector3(56.0, 14.0, 78.0)
		cam.look_at(Vector3(70.0, -1.0, 67.0), Vector3.UP)
	await _shot("lake")
	for _i in 600:
		_rip.call("step_once")
		await process_frame
	await _shot("lake_settled")

	print("[WLAB] %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)


func _camera() -> Camera3D:
	for n in root.find_children("*", "Camera3D", true, false):
		var c := n as Camera3D
		if c != null and c.current:
			return c
	return null


func _shot(tag: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := _out + "water_lab_%s.png" % tag
	var ok := img.save_png(path) == OK
	# Blue against red, the same crude classifier the swe bench uses: the terrain is earth-toned
	# and the water is not, and a subtle test would be measuring its own thresholds.
	var water := 0
	var n := 0
	for y in range(int(float(img.get_height()) * 0.12), img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b < 0.25:
				continue
			n += 1
			if c.b > c.r + 0.06:
				water += 1
	print("[WLAB] %-12s water %5.1f%%   (%s)"
			% [tag, float(water) / maxf(float(n), 1.0) * 100.0, path if ok else "SAVE FAILED"])
