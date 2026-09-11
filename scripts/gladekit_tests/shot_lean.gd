extends SceneTree
## THE WALL OFF PLUMB — the three ways a wall can stop being a box, side by side, and the claim
## behind each of them.
##
## Cycle A gave the kit two new things to say and corrected a third, and none of them can be judged
## from a number:
##
##   lean     a SHEAR. One direction for the whole wall, no centre needed, so it is the only one of
##            the three that means anything on an OPEN wall — the case `profile` documents itself as
##            refusing.
##   setback  a negative `GladeStorey.jetty`. Each floor steps IN, which is what stone does when it
##            cannot lean, and what the old clamp at zero forbade outright.
##   profile  a scale about the plan centre. Not new — but until this cycle it leaned the STONE and
##            never the CLAIM, so the blockout drew a cylinder where the fill drew a dome.
##
## Two passes on one camera, and the second is the point: `blockout` draws the claim and nothing
## else, so the pair answers "does the mass the junction system reasons about match the mass you can
## see". Before this cycle the two pictures disagreed on every wall here.
##
## Needs a real rendering context, so run it WITHOUT --headless (a small window opens and closes):
##   Godot_console.exe --path . --resolution 1400x760 --script res://scripts/gladekit_tests/shot_lean.gd -- --out=C:/some/folder

const WARMUP := 30                             # frames to let deferred rebuilds settle

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.71, 0.80)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.72, 0.82)
	e.ambient_light_energy = 0.65
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -128, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(80, 80)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.46, 0.28)
	pl.material = gm
	ground.mesh = pl
	world.add_child(ground)

	# THE CONTROL, and it stands first so the eye has a plumb edge to judge the rest against. Same
	# curve, same seed, same style as the leaning wall beside it; `lean` is the only difference.
	# ACROSS the run, not along it: a wall leaning towards the camera is a wall you cannot see
	# leaning. The curve runs on Z, so the lean is on X and shows in silhouette.
	world.add_child(_run_wall(Vector3(-13.0, 0, 0), Vector2.ZERO, 11))
	world.add_child(_run_wall(Vector3(-6.5, 0, 0), Vector2(0.17, 0.0), 11))
	world.add_child(_setback_tower(Vector3(1.5, 0, 0)))
	world.add_child(_domed_tower(Vector3(10.5, 0, 0)))

	var cam := Camera3D.new()
	cam.position = Vector3(-3.0, 7.6, 21.0)
	cam.look_at_from_position(cam.position, Vector3(-1.0, 3.2, 0.0), Vector3.UP)
	cam.fov = 44.0
	world.add_child(cam)
	cam.current = true

	await _shoot("lean_geometry")

	# ...and the same frame with nothing but the claim in it.
	GladeDebug.blockout = true
	for n in world.get_children():
		if n is GladeWall:
			(n as GladeWall).rebuild()
	await _shoot("lean_massing")
	GladeDebug.blockout = false
	quit(0)


func _shoot(name: String) -> void:
	for i in WARMUP:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %s   %s (%d x %d)" % ["ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])


## An OPEN wall — two points, no loop. `profile` scales about the footprint's centre and so has
## nothing to work with here and quietly does nothing; a shear needs no centre. This is the case that
## separates the two, which is why the shot uses it rather than a tidy box.
func _run_wall(at: Vector3, lean: Vector2, seed_v: int) -> GladeWall:
	var w := GladeWall.new()
	w.name = "Run%s" % ("Plumb" if lean == Vector2.ZERO else "Leaning")
	var c := Curve3D.new()
	c.add_point(Vector3(0, 0, -2.6))
	c.add_point(Vector3(0, 0, 2.6))
	w.curve = c
	w.position = at
	w.rng_seed = seed_v
	w.wall_height = 5.2
	w.lean = lean
	w.style = load("res://addons/gladekit/styles/alsace_stone.tres")
	return w


## FOUR FLOORS THAT EACH STEP IN. A battered tower with a stepped face, which is what a negative
## jetty is for and what the clamp at zero used to make unsayable. Note there are no corbels on it:
## `GladeStageFill` only hangs beam-ends under a jetty that is actually positive, so a setback grows
## nothing to carry an overhang that is not there.
func _setback_tower(at: Vector3) -> GladeWall:
	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := GladeWall.new()
	w.name = "Setback"
	w.position = at
	w.rng_seed = 4
	w.style = stone
	w.plan_mode = GladeWall.PlanMode.BOX
	w.set_box_plan(Vector3(-2.2, 0, -2.2), Vector3.RIGHT, Vector3.BACK, 4.4, 4.4)
	var arr: Array[GladeStorey] = []
	for i in 4:
		var s := GladeStorey.new()
		s.height = 1.7
		s.jetty = 0.0 if i == 0 else -0.16
		s.style = stone
		arr.append(s)
	w.storeys = arr
	return w


## A DOME, for the half of the fix that has no new knob at all: `profile` could always lean the
## stone, and until this cycle the claim it published was the straight cylinder the wall would have
## been. In the massing pass this one used to be a can; now it is the shape it looks like.
func _domed_tower(at: Vector3) -> GladeWall:
	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := GladeWall.new()
	w.name = "Domed"
	w.position = at
	w.rng_seed = 9
	w.style = stone
	root.add_child(w)                          # make_cylinder wants a live node
	w.make_cylinder(2.9, 20)
	root.remove_child(w)
	var dome := Curve.new()
	dome.add_point(Vector2(0.0, 1.0))
	dome.add_point(Vector2(0.55, 0.86))
	dome.add_point(Vector2(1.0, 0.30))
	w.profile = dome
	var arr: Array[GladeStorey] = []
	for i in 4:
		var s := GladeStorey.new()
		s.height = 1.7
		s.style = stone
		arr.append(s)
	w.storeys = arr
	return w
