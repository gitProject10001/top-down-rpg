extends SceneTree
## GOLDEN DUMP — the refactor's oracle. Writes every placement GladeKit makes, for every scene
## that uses it, as one plain-text file you can `git diff --no-index` against a later run.
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/golden_gladekit.gd \
##       -- --out=docs/refactor-evidence/golden_before.txt
##
## WHY THIS EXISTS ALONGSIDE verify_gladekit.gd. The suite proves INVARIANTS — that a wall is
## deterministic, that a junction deletes the right stones, that nothing floats. It cannot prove
## that a refactor changed nothing, because it never compares against yesterday's output. This does
## exactly that and nothing else: it asserts no property at all, it just states, exhaustively, what
## the kit built. Any difference is a diff line.
##
## WHY IT DOES NOT SORT. `verify_gladekit._bricks()` sorts before comparing, which is right for the
## question it asks (are these the same stones?) and blind to the question this asks (did the
## pipeline run its stages in the same ORDER?). Splitting a monolith into stages is precisely the
## change that reorders `snap_transforms` while leaving every value alone, so this dump keeps the
## emission order and lets the diff catch it.
##
## FULL PRECISION, via `var_to_str`. A structural refactor must not move a float by one ulp; %.2f
## would hide it. If the arithmetic genuinely had to change, the diff shows exactly which pieces.

const SCENES := [
	"res://scenes/dev/gladekit/glade_demo.tscn",
	"res://scenes/dev/gladekit/adobe.tscn",
	"res://scenes/dev/gladekit/whinbek.tscn",
	"res://scenes/dev/gladekit/lookdev.tscn",
]

const WARMUP := 30                             ## frames to let deferred rebuilds settle
const DEFAULT_OUT := "user://glade_golden.txt"

var _out := PackedStringArray()
var _timings := PackedStringArray()


func _initialize() -> void:
	_run()


func _run() -> void:
	var path := DEFAULT_OUT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(6)

	for s: String in SCENES:
		await _dump_scene(s)
	await _dump_house()

	# The perf column goes in its OWN file. Wall-clock milliseconds differ run to run, so putting
	# them in the golden would make every diff dirty and the oracle worthless.
	var body := "\n".join(_out) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[GOLDEN] FAILED to open %s (%d)" % [path, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(body)
	f.close()

	var tpath := path.get_basename() + "_timings.txt"
	var tf := FileAccess.open(tpath, FileAccess.WRITE)
	if tf:
		tf.store_string("\n".join(_timings) + "\n")
		tf.close()

	print("[GOLDEN] %s  (%d lines, %d nodes)" % [path, _out.size(), _timings.size()])
	quit(0)


# ---------------------------------------------------------------- the fixtures --------------


func _dump_scene(scene_path: String) -> void:
	_out.append("")
	_out.append("################################################################ %s" % scene_path)
	var packed := load(scene_path)
	if packed == null:
		_out.append("!! could not load")
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for i in WARMUP:
		await process_frame
	await physics_frame
	_walk(scene, scene)
	scene.free()


## The code-built half-timbered house from shot_house.gd. A scene file cannot exercise the House
## preset's storey stack, and that stack is the deepest path through the wall pipeline.
func _dump_house() -> void:
	_out.append("")
	_out.append("################################################################ (code) alsace house")
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(_house(Vector3.ZERO, 7.0, 5.5, 3))
	world.add_child(_house(Vector3(9.5, 0, 0.6), 5.5, 5.0, 5))
	# A tower driven into the first house: the ONLY fixture here that exercises junction claims,
	# the buried pass and tee quoins, which are the rules most easily broken by a stage split.
	world.add_child(_tower(Vector3(2.4, 0, 1.8), 2.2, 9))
	# No shipped scene paints one, and the golden should not have a blind spot the size of a whole
	# node type. Stroke data is set directly rather than brushed, because the brush is editor-only.
	world.add_child(_scatter())
	for i in WARMUP:
		await process_frame
	await physics_frame
	_walk(world, world)
	world.free()


## Lifted verbatim from shot_house.gd, on purpose: the picture that suite renders and the numbers
## this one records must describe the SAME building, or a diff here would not correspond to
## anything you can look at.
func _house(at: Vector3, span: float, deep: float, seed_v: int) -> GladeWall:
	var w := GladeWall.new()
	w.name = "House%d" % seed_v
	var c := Curve3D.new()
	for p in [Vector3.ZERO, Vector3(span, 0, 0), Vector3(span, 0, deep), Vector3(0, 0, deep),
			Vector3.ZERO]:
		c.add_point(p)
	w.curve = c
	w.position = at
	w.rng_seed = seed_v
	w.style = load("res://addons/gladekit/styles/alsace_stone.tres")

	var g := GladeStorey.new()
	g.height = 2.5
	g.style = load("res://addons/gladekit/styles/alsace_stone.tres")
	var up := GladeStorey.new()
	up.height = 2.4
	up.jetty = 0.3
	up.style = load("res://addons/gladekit/styles/alsace_timber.tres")
	var attic := GladeStorey.new()
	attic.height = 2.2
	attic.jetty = 0.22
	attic.style = load("res://addons/gladekit/styles/alsace_timber.tres")
	w.storeys = [g, up, attic]

	_hole(w, Vector3(span * 0.42, 0.0, deep), 1.15, 2.05)          # street door
	for i in 3:
		_hole(w, Vector3(span * (0.2 + i * 0.3), 0.95, deep), 0.9, 1.1)     # shop floor
		_hole(w, Vector3(span * (0.2 + i * 0.3), 3.35, deep), 1.0, 1.15)    # first floor
		_hole(w, Vector3(span * (0.2 + i * 0.3), 5.75, deep), 0.9, 1.05)    # attic
	for i in 2:
		_hole(w, Vector3(0.0, 3.35, deep * (0.3 + i * 0.36)), 1.0, 1.15)    # gable end
		_hole(w, Vector3(0.0, 5.75, deep * (0.3 + i * 0.36)), 0.9, 1.0)

	var roof := GladeRoof.new()
	roof.name = "Roof"                         # named, so the dump's node paths never depend on
	roof.pitch_degrees = 52.0                  # Godot's auto-name counter
	roof.overhang = 0.55
	roof.rng_seed = seed_v
	roof.dormer_count = 2
	roof.dormer_up_slope = 0.2
	roof.style = load("res://addons/gladekit/styles/alsace_timber.tres")
	w.add_child(roof)

	var ch := GladeChimney.new()
	ch.position = Vector3(span * 0.25, 0, deep * 0.42)
	ch.clearance = 0.9
	roof.add_child(ch)
	return w


## A higher-ranked round tower standing in the house. Its rank is what makes the house give up the
## stones inside it, and `buried_style` is what fills the face the house keeps on the inside.
func _tower(at: Vector3, radius: float, seed_v: int) -> GladeWall:
	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := GladeWall.new()
	w.name = "Tower"
	w.position = at
	w.rng_seed = seed_v
	w.style = stone
	w.wall_height = 9.0
	w.junction_rank = 3
	w.plan_mode = GladeWall.PlanMode.CYLINDER
	w.make_cylinder(radius)
	return w


## A painted patch of grass. `points`/`normals`/`amounts` ARE the serialised stroke, so writing
## them is exactly what loading a painted .tscn does.
func _scatter() -> GladeScatter:
	var s := GladeScatter.new()
	s.name = "Meadow"
	s.rng_seed = 4
	s.position = Vector3(-6.0, 0, -6.0)
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var amt := PackedFloat32Array()
	for ix in 8:
		for iz in 8:
			pts.append(Vector3(ix * 0.35, 0.0, iz * 0.35))
			nrm.append(Vector3.UP)
			amt.append(0.4 + 0.075 * float((ix * 7 + iz * 3) % 8))
	s.normals = nrm
	s.amounts = amt
	s.points = pts                             # setter last: it is the one that marks dirty
	return s


func _hole(w: GladeWall, at: Vector3, width: float, height: float) -> void:
	var o := GladeOpening.new()
	o.position = at
	o.width = width
	o.height = height
	o.arched = false
	w.add_child(o)


# ---------------------------------------------------------------- the dump -------------------


func _walk(n: Node, from: Node) -> void:
	if n is GladeWall or n is GladeRoof or n is GladePath or n is GladeScatter:
		_dump_node(n as Node3D, from)
	for c in n.get_children():
		_walk(c, from)


func _dump_node(n: Node3D, from: Node) -> void:
	var t0 := Time.get_ticks_usec()
	if n.has_method("rebuild"):
		n.call("rebuild")                      # synchronous, so the timing is the node's own
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0

	var path := str(from.get_path_to(n))
	_out.append("")
	_out.append("======== %s [%s]" % [path, n.get_class() if n.get_script() == null
			else (n.get_script() as Script).get_global_name()])

	# --- stats, keys sorted so a Dictionary's insertion order never shows up as a diff
	var st: Dictionary = n.get("stats") if n.get("stats") != null else {}
	var keys := st.keys()
	keys.sort()
	for k in keys:
		_out.append("stat %s = %s" % [k, var_to_str(st[k])])

	# --- every placement, IN ORDER
	var xf: Array = n.get("snap_transforms") if n.get("snap_transforms") != null else []
	var col: Array = n.get("snap_colors") if n.get("snap_colors") != null else []
	_out.append("placements %d" % xf.size())
	for i in xf.size():
		var c := var_to_str(col[i]) if i < col.size() else "-"
		_out.append("  %d %s %s" % [i, var_to_str(xf[i]), c])

	# --- the adobe surface, if this node grew one
	_dump_meshes(n)
	# --- the collision it laid under the art
	_dump_collision(n)

	_timings.append("%-52s %8.2f ms  %6d placements" % [path, ms, xf.size()])


## Every ArrayMesh a node committed directly (the clay), vertex by vertex. Skips MultiMeshInstance3D
## — those are the placements already dumped above, and the headless renderer does not retain their
## buffers anyway.
func _dump_meshes(n: Node3D) -> void:
	# Identified BY POSITION, never by name. Generated children get Godot's auto-names
	# (`@MeshInstance3D@152`), whose counter depends on how many objects the engine happened to
	# allocate before this one — which a refactor changes without changing a single vertex. Naming
	# them here would make every diff dirty and the oracle worthless.
	var idx := 0
	for c in n.get_children(true):
		if not (c is MeshInstance3D) or c is MultiMeshInstance3D:
			continue
		var m: Mesh = (c as MeshInstance3D).mesh
		if m == null:
			continue
		idx += 1
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] \
					!= null else PackedVector3Array()
			var cl: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] \
					!= null else PackedColorArray()
			_out.append("mesh %d surface %d verts %d" % [idx, s, v.size()])
			for i in v.size():
				_out.append("  v %d %s %s %s" % [i, var_to_str(v[i]),
						var_to_str(nm[i]) if i < nm.size() else "-",
						var_to_str(cl[i]) if i < cl.size() else "-"])


func _dump_collision(n: Node3D) -> void:
	var shapes := 0
	for body in n.get_children(true):
		if not (body is StaticBody3D):
			continue
		for s in body.get_children():
			if not (s is CollisionShape3D):
				continue
			var cs := s as CollisionShape3D
			var size := (cs.shape as BoxShape3D).size if cs.shape is BoxShape3D else Vector3.ZERO
			_out.append("  collider %s %s" % [var_to_str(cs.transform), var_to_str(size)])
			shapes += 1
	if shapes > 0:
		_out.append("colliders %d" % shapes)
