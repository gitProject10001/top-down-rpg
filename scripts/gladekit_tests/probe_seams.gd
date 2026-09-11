extends SceneTree
## What the seam rules actually did to a scene: which junctions were found, which of them a rule
## claimed, and how many pieces it laid. The counterpart to probe_buried.gd — that one asks what a
## junction TAKES AWAY, this one asks what it PUTS BACK.
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/probe_seams.gd
##
## Optional: `-- --scene=res://path/to.tscn` for a scene other than whinbek.

const SCENE := "res://scenes/dev/gladekit/whinbek.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	var path := SCENE
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.substr(8)

	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	for i in 14:
		await process_frame
	await physics_frame

	var solids: Array[Node3D] = []
	_collect(scene, solids)

	print("\n=== what each building laid on its seams ===")
	for n in solids:
		var st: Dictionary = n.get("stats")
		if n is GladeWall:
			print("%-12s rank %d  bricks %5d  of which quoins %3d, TEES %3d"
					% [n.name, n.get("junction_rank"), int(st.get("bricks", 0)),
							int(st.get("quoins", 0)), int(st.get("tees", 0))])
		else:
			print("%-12s rank %d  shingles %5d  VALLEYS %3d  cut %3d"
					% [n.name, n.get("junction_rank"), int(st.get("shingles", 0)),
							int(st.get("valleys", 0)), int(st.get("cut", 0))])

	# How many the OVERLAY draws, which is the number that decides whether it is readable.
	var raw := 0
	var kept := 0
	for n in solids:
		var vols: Array = n.call("junction_volumes")
		if vols.is_empty():
			continue
		var found: Array = GladeSeam.between(vols[0], GladeJunction.gather_related(n))
		raw += found.size()
		kept += GladeSeam.significant(found).size()
	print("\n%d seams found in all, %d structural enough to draw" % [raw, kept])

	print("\n=== every seam a rule COULD have taken, and who was entitled to it ===")
	for n in solids:
		var mine: Array = n.call("junction_volumes")
		if mine.is_empty():
			continue
		var me: GladeVolume = mine[0]
		for other: GladeVolume in GladeJunction.gather_related(n):
			var them := instance_from_id(other.owner_id) as Node
			for s: GladeSeam in GladeSeam.significant(GladeSeam.between(me, [other])):
				var kind := ""
				if s.valley():
					kind = "VALLEY"
				elif s.tee():
					kind = "TEE"
				if kind == "":
					continue
				print("%-12s x %-12s %s  %.2f m  from %s to %s  (their rank %d)"
						% [n.name, them.name if them else "?", kind, s.measure(),
								_v(s.foot()), _v(s.head()), other.rank])

	quit(0)


func _collect(n: Node, out: Array[Node3D]) -> void:
	if n is GladeWall or n is GladeRoof:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
