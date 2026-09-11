extends SceneTree
## Builds an Alsatian half-timbered house entirely from GladeKit rules and saves a PNG of it.
## The suite proves the invariants; this answers the only question the suite cannot — does it
## LOOK like the reference photo.
##
## Needs a real rendering context, so run it WITHOUT --headless (a small window opens and closes):
##   Godot_console.exe --path . --resolution 1280x800 --script res://scripts/gladekit_tests/shot_house.gd

const OUT := "user://glade_house.png"
const WARMUP := 30                             # frames to let deferred rebuilds settle


func _initialize() -> void:
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
	sun.rotation_degrees = Vector3(-48, -132, 0)
	sun.light_energy = 1.15
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

	world.add_child(_house(Vector3.ZERO, 7.0, 5.5, 3))
	world.add_child(_house(Vector3(9.5, 0, 0.6), 5.5, 5.0, 5))

	var cam := Camera3D.new()
	cam.position = Vector3(-10.5, 8.4, 17.0)
	cam.look_at_from_position(cam.position, Vector3(7.5, 3.4, 1.5), Vector3.UP)
	cam.fov = 46.0
	world.add_child(cam)
	cam.current = true

	for i in WARMUP:
		await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT)
	print("[SHOT] %s -> %s (%dx%d)" % ["ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(OUT), img.get_width(), img.get_height()])
	quit(0 if err == OK else 1)


## A whole house out of the rules: stone footing, jettied timber floor, roof with dormers, a
## chimney, a door and a row of windows. Nothing here is placed by hand except the intent.
func _house(at: Vector3, span: float, deep: float, seed_v: int) -> GladeWall:
	var w := GladeWall.new()
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

	# An opening's node position is projected onto the curve, so a point ON a face puts it there.
	# Camera-facing faces here are z = deep and x = 0.
	_hole(w, Vector3(span * 0.42, 0.0, deep), 1.15, 2.05)          # street door
	for i in 3:
		_hole(w, Vector3(span * (0.2 + i * 0.3), 0.95, deep), 0.9, 1.1)     # shop floor
		_hole(w, Vector3(span * (0.2 + i * 0.3), 3.35, deep), 1.0, 1.15)    # first floor
		_hole(w, Vector3(span * (0.2 + i * 0.3), 5.75, deep), 0.9, 1.05)    # attic
	for i in 2:
		_hole(w, Vector3(0.0, 3.35, deep * (0.3 + i * 0.36)), 1.0, 1.15)    # gable end
		_hole(w, Vector3(0.0, 5.75, deep * (0.3 + i * 0.36)), 0.9, 1.0)

	var roof := GladeRoof.new()
	roof.pitch_degrees = 52.0
	roof.overhang = 0.55
	roof.rng_seed = seed_v
	roof.dormer_count = 2
	roof.dormer_up_slope = 0.2
	roof.style = load("res://addons/gladekit/styles/alsace_timber.tres")
	w.add_child(roof)

	_chimney(w, span, deep)
	return w


func _hole(w: GladeWall, at: Vector3, width: float, height: float) -> void:
	var o := GladeOpening.new()
	o.position = at
	o.width = width
	o.height = height
	o.arched = false
	w.add_child(o)


func _chimney(w: GladeWall, span: float, deep: float) -> void:
	var roof: GladeRoof = null
	for c in w.get_children():
		if c is GladeRoof:
			roof = c
	if roof == null:
		return
	var ch := GladeChimney.new()
	ch.position = Vector3(span * 0.25, 0, deep * 0.42)
	ch.clearance = 0.9
	roof.add_child(ch)
