extends SceneTree
## LOOK AT THE TWO SEAM RULES. The suite proves a valley is laid and a tee is quoined; only a
## picture says whether either reads as a building.
##
## Built rather than loaded, because neither junction exists in scenes/dev/whinbek.tscn: its wing
## roof passes UNDER the main eave (so the two roofs never fold into each other) and its tees are
## the ones this renders. A crossing pair of equal roofs is the case the valley rule was written
## for, and it takes six lines to stand one up.
##
## Run WITHOUT --headless (a window opens and closes):
##   Godot_console.exe --path . --resolution 1280x800 --script res://scripts/gladekit_tests/shot_seams.gd -- --out=C:/some/folder

const WHINBEK := "res://scenes/dev/gladekit/whinbek.tscn"
const STONE := "res://addons/gladekit/styles/alsace_stone.tres"
const SLATE := "res://addons/gladekit/styles/alsace_slate.tres"
const WARMUP := 24

const VIEWS := [
	{"name": "valley", "from": Vector3(11.5, 7.5, 11.0), "at": Vector3(1.6, 3.6, 1.0),
		"fov": 40.0},
	{"name": "valley_top", "from": Vector3(6.0, 12.0, 8.0), "at": Vector3(1.2, 4.2, 0.6),
		"fov": 42.0},
	{"name": "tee", "from": Vector3(-9.5, 3.6, 7.0), "at": Vector3(-3.4, 2.4, 1.2),
		"fov": 38.0},
]

var _out := "user://"
var _roofs: Array[GladeRoof] = []
var _walls: Array[GladeWall] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if not _out.ends_with("/"):
		_out += "/"

	var world := Node3D.new()
	root.add_child(world)
	_lighting(world)

	# TWO WINGS AT THE SAME HEIGHT, crossing at right angles: the commonest valley there is, and
	# equal ranks on purpose — neither wing cuts the other, they simply meet.
	world.add_child(_block(Vector3(-4.0, 0, 0), 9.0, 5.0, 3.2, 44.0, 3, 0))
	world.add_child(_block(Vector3(1.4, 0, -4.6), 4.6, 9.5, 3.2, 44.0, 8, 0))
	# ...and a tower driven into the first one, which is the tee.
	world.add_child(_tower(Vector3(-3.4, 0, 1.2), 1.7, 6.4, 5))

	for i in WARMUP:
		await process_frame

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true

	for on in [false, true]:
		for r in _roofs:
			r.valley_tiles = on
			r.rebuild()
		for w in _walls:
			w.tee_quoins = on
			w.rebuild()
		for i in 8:
			await process_frame
		var valleys := 0
		var tees := 0
		for r in _roofs:
			valleys += int(r.stats.get("valleys", 0))
		for w in _walls:
			tees += int(w.stats.get("tees", 0))
		print("[SHOT] rules %-3s -> %d valley pieces, %d tee quoins" % ["on" if on else "off",
				valleys, tees])

		for v in VIEWS:
			cam.fov = v["fov"]
			cam.look_at_from_position(v["from"], v["at"], Vector3.UP)
			for i in 4:
				await process_frame
			var path: String = "%s%s_%s.png" % [_out, v["name"], "on" if on else "off"]
			var err := root.get_texture().get_image().save_png(path)
			print("[SHOT] %s %s" % ["ok  " if err == OK else "FAIL", path])

	world.queue_free()
	await _whinbek()
	quit(0)


## ...and the same rule in the acceptance scene, where the tower is driven through the main block's
## gable end and leaves two plumb joints six metres tall.
func _whinbek() -> void:
	var scene: Node = load(WHINBEK).instantiate()
	root.add_child(scene)
	var walls: Array[GladeWall] = []
	_collect(scene, walls)
	for i in WARMUP:
		await process_frame
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	for on in [false, true]:
		for w in walls:
			w.tee_quoins = on
			w.rebuild()
		for i in 8:
			await process_frame
		var tees := 0
		for w in walls:
			tees += int(w.stats.get("tees", 0))
		print("[SHOT] whinbek tees %-3s -> %d quoins" % ["on" if on else "off", tees])
		cam.fov = 34.0
		cam.look_at_from_position(Vector3(-3.6, 3.4, -9.4), Vector3(1.4, 2.6, -3.4), Vector3.UP)
		for i in 4:
			await process_frame
		var path: String = "%swhinbek_tee_%s.png" % [_out, "on" if on else "off"]
		var err := root.get_texture().get_image().save_png(path)
		print("[SHOT] %s %s" % ["ok  " if err == OK else "FAIL", path])


func _collect(n: Node, out: Array[GladeWall]) -> void:
	if n is GladeWall:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _block(at: Vector3, span: float, deep: float, height: float, pitch: float, seed_v: int,
		rank: int) -> GladeWall:
	var w := GladeWall.new()
	var c := Curve3D.new()
	for p in [Vector3.ZERO, Vector3(span, 0, 0), Vector3(span, 0, deep), Vector3(0, 0, deep),
			Vector3.ZERO]:
		c.add_point(p)
	w.curve = c
	w.position = at
	w.rng_seed = seed_v
	w.junction_rank = rank
	w.wall_height = height
	w.style = load(STONE)
	_walls.append(w)

	var roof := GladeRoof.new()
	roof.style = load(SLATE)
	roof.pitch_degrees = pitch
	roof.overhang = 0.45
	roof.rng_seed = seed_v
	roof.junction_rank = rank
	w.add_child(roof)
	_roofs.append(roof)
	return w


func _tower(at: Vector3, radius: float, height: float, rank: int) -> GladeWall:
	var w := GladeWall.new()
	w.position = at
	w.rng_seed = 21
	w.junction_rank = rank
	w.wall_height = height
	w.style = load(STONE)
	w.make_cylinder(radius, 12)
	w.plan_mode = GladeWall.PlanMode.CYLINDER
	_walls.append(w)
	return w


func _lighting(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.71, 0.80)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.72, 0.82)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -128, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(60, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.46, 0.28)
	pl.material = gm
	ground.mesh = pl
	world.add_child(ground)
