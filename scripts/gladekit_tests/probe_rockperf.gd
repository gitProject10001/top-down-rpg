extends SceneTree
## TEMPORARY: what does a big rock field actually cost to rebuild?
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/probe_rockperf.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(_ground())

	var scree: GladeStyle = load("res://addons/gladekit/styles/scree_stone.tres")
	# a big field, the case the framerate complaint came from
	var f := GladeRocks.new()
	f.region_mode = GladeRocks.RegionMode.BOX
	f.style = scree
	f.conform_to_ground = true
	f.density = 1.2
	f.size = 0.5
	world.add_child(f)
	f.make_box(30.0, 30.0)

	for i in 20:
		await process_frame

	# first build is cold; the interesting number is a REBUILD, which is what a gizmo drag costs
	for label in ["cold", "warm", "warm", "density nudge"]:
		if label == "density nudge":
			f.density = 1.25
		var t := Time.get_ticks_usec()
		f.rebuild()
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		print("  %-14s %7.1f ms   rocks %d   cells %d   colliders %d"
				% [label, ms, int(f.stats.get("rocks", 0)), int(f.stats.get("cells", 0)),
						int(f.stats.get("colliders", 0))])
	quit(0)


func _ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	return body
