extends SceneTree
## REBUILD COST, repeatably. What the editor's frame rate is made of.
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/bench_gladekit.gd
##   ... -- --reps=40 --only=masonry
##
## WHY A SEPARATE HARNESS. `golden_gladekit.gd` writes a timings file, but it rebuilds each node
## ONCE inside a scene load, so its numbers carry the scene's warm-up, the physics tick and whatever
## the neighbours were doing. That is fine as a smoke signal and useless for deciding whether a
## change made anything faster.
##
## This rebuilds ONE node in isolation, `reps` times, and reports the MEDIAN — not the mean, because
## a single GC pause or a Windows scheduler hiccup moves a mean and not a median. The fixtures are
## the shapes a user actually drags: a plain run of wall, a closed house, a house with storeys and a
## roof, and a mud wall (which is its own performance story).
##
## DRAGGING A PEARL IS THE CASE THAT MATTERS. The editor calls `rebuild()` on every mouse-move
## frame, so a wall that takes 16 ms to grow cannot exceed 60 fps while you are shaping it, and one
## that takes 300 ms is unusable. That is the number to watch here, not the total.

const DEFAULT_REPS := 25


func _initialize() -> void:
	_run()


## One frame first: in `_initialize()` the SceneTree root is not yet live, so a node added there
## never enters the tree and `rebuild()` quietly does nothing. That cost an afternoon once already.
func _run() -> void:
	await process_frame
	var reps := DEFAULT_REPS
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reps="):
			reps = int(a.substr(7))
		elif a.begins_with("--only="):
			only = a.substr(7)

	print("\n%-22s %9s %9s %9s   %s" % ["fixture", "median", "min", "max", "pieces"])
	print("-".repeat(70))
	var total := 0.0
	for f in _fixtures():
		if only != "" and not (f.name as String).contains(only):
			continue
		total += _bench(f, reps)
	print("-".repeat(70))
	print("%-22s %9.2f ms  (sum of medians)\n" % ["TOTAL", total])
	quit(0)


func _bench(f: Dictionary, reps: int) -> float:
	var node: GladeWall = (f.make as Callable).call()
	root.add_child(node)                       # _ready rebuilds once; that one is the warm-up
	assert(node.is_inside_tree(), "fixture never entered the tree — nothing would be measured")
	var samples: Array[float] = []
	for i in reps:
		var t0 := Time.get_ticks_usec()
		node.rebuild()
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	var med: float = samples[samples.size() / 2]
	var pieces: int = node.snap_transforms.size() + int(node.stats.get("adobe_quads", 0))
	print("%-22s %8.2f  %8.2f  %8.2f   %d" % [f.name, med, samples[0],
			samples[samples.size() - 1], pieces])
	node.free()
	return med


# ---------------------------------------------------------------- the fixtures --------------


func _fixtures() -> Array:
	return [
		{"name": "masonry_run", "make": _masonry_run},
		{"name": "masonry_house", "make": _masonry_house},
		{"name": "masonry_storeys", "make": _storeyed},
		{"name": "timber_house", "make": _timber_house},
		{"name": "adobe_block", "make": _adobe_block},
	]


func _wall(points: Array, height := 2.4, seed_v := 7) -> GladeWall:
	var w := GladeWall.new()
	var c := Curve3D.new()
	for p: Vector3 in points:
		c.add_point(p)
	w.curve = c
	w.rng_seed = seed_v
	w.wall_height = height
	w.generate_collision = false               # physics bodies are not what we are measuring
	return w


## A plain 12 m run — the thing you get from Place > Wall and then drag longer.
func _masonry_run() -> GladeWall:
	var w := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 2.4)
	w.style = load("res://addons/gladekit/styles/alsace_stone.tres")
	return w


func _masonry_house() -> GladeWall:
	var w := _wall([Vector3.ZERO, Vector3(8, 0, 0), Vector3(8, 0, 6), Vector3(0, 0, 6),
			Vector3.ZERO], 3.0)
	w.style = load("res://addons/gladekit/styles/alsace_stone.tres")
	return w


func _storeyed() -> GladeWall:
	var w := _masonry_house()
	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	for h: float in [2.5, 2.4, 2.2]:
		var s := GladeStorey.new()
		s.height = h
		s.style = stone
		w.storeys.append(s)
	return w


func _timber_house() -> GladeWall:
	var w := _masonry_house()
	w.style = load("res://addons/gladekit/styles/alsace_timber.tres")
	return w


## The one that is measured in hundreds of milliseconds. See the note in glade_fill_adobe.gd.
func _adobe_block() -> GladeWall:
	var w := _wall([Vector3.ZERO, Vector3(8, 0, 0), Vector3(8, 0, 6), Vector3(0, 0, 6),
			Vector3.ZERO], 3.0)
	w.style = load("res://addons/gladekit/styles/adobe_clay.tres")
	return w
