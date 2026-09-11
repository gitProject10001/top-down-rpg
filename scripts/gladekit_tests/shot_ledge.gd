extends SceneTree
## BALCONIES — the third axis, looked at from two metres.
##
## The suite proves a ledge adds without deleting, publishes its claim and follows the wall it hangs
## on. This answers what a suite cannot: is it a balcony, or is it a shelf with sticks on it.
##
## Three of them, on purpose:
##   left    a straight run — the plain case, and the one that shows the knees carrying the deck
##   middle  a wide balcony on a jettied timber house, where it has to sit UNDER an overhang
##   right   one on a round tower, where the deck is a flat rectangle on a curved wall and the two
##           had better agree about where the wall face is
##
## And a close-up pass, because the adobe cycle passed a whole style at plate framing and then found
## five defects the moment the camera moved in. Every defect this cycle found came from doing that.
##
## Needs a real rendering context, so run it WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1500x820 --script res://scripts/gladekit_tests/shot_ledge.gd -- --out=C:/some/folder

const WARMUP := 30
const STONE := "res://addons/gladekit/styles/alsace_stone.tres"
const TIMBER := "res://addons/gladekit/styles/alsace_timber.tres"

var _out := "user://"
var _cam: Camera3D


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
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -118, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(90, 90)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.46, 0.28)
	pl.material = gm
	ground.mesh = pl
	world.add_child(ground)

	world.add_child(_run_wall(Vector3(-11, 0, 0)))
	world.add_child(_house(Vector3(-3.5, 0, 0)))
	world.add_child(_tower(Vector3(9.0, 0, 0)))

	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.current = true

	_look(Vector3(-1.0, 7.4, 17.5), Vector3(-1.0, 3.4, 0.0), 50.0)
	await _shoot("ledge_three")

	# ...and from two metres, where the joints actually are. The house's balcony hangs off its +Z
	# face at world (-0.5, 2.95, 5); the camera stands off it and a little below, because the knees
	# under the deck are the part a plate framing never shows.
	_look(Vector3(1.4, 3.4, 10.2), Vector3(-0.5, 3.2, 5.4), 38.0)
	await _shoot("ledge_close")
	quit(0)


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = from
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.fov = fov


func _shoot(name: String) -> void:
	for i in WARMUP:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %s   %s (%d x %d)" % ["ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])


## THE PLAIN CASE. An open run of stone with a balcony on it — nothing to hide behind, so the knees
## either carry the deck or the deck floats.
func _run_wall(at: Vector3) -> GladeWall:
	var w := GladeWall.new()
	w.name = "Run"
	var c := Curve3D.new()
	c.add_point(Vector3(0, 0, -2.6))
	c.add_point(Vector3(0, 0, 2.6))
	w.curve = c
	w.position = at
	w.rng_seed = 12
	w.wall_height = 5.4
	w.style = load(STONE)
	_ledge(w, Vector3(0, 3.0, 0), 2.6, 1.15)
	return w


## A JETTIED TIMBER HOUSE. The balcony has to sit under an overhang, which is where a corbel and a
## deck would have grown through each other if the two emitters that project outward did not know
## about each other.
func _house(at: Vector3) -> GladeWall:
	var stone: GladeStyle = load(STONE)
	var timber: GladeStyle = load(TIMBER)
	var span := 6.0
	var deep := 5.0
	var w := GladeWall.new()
	w.name = "House"
	var c := Curve3D.new()
	for p in [Vector3.ZERO, Vector3(span, 0, 0), Vector3(span, 0, deep), Vector3(0, 0, deep),
			Vector3.ZERO]:
		c.add_point(p)
	w.curve = c
	w.plan_mode = GladeWall.PlanMode.BOX
	w.position = at
	w.rng_seed = 5
	w.style = stone
	w.storeys = [_storey(2.6, 0.0, stone), _storey(2.5, 0.3, timber)]

	var door := GladeOpening.new()
	door.position = Vector3(span * 0.5, 0.0, deep)
	door.width = 1.1
	door.height = 2.0
	door.arched = false
	w.add_child(door)
	# the door onto the balcony, which is what a balcony is FOR
	var up := GladeOpening.new()
	up.position = Vector3(span * 0.5, 3.05, deep)
	up.width = 1.0
	up.height = 1.9
	up.arched = false
	w.add_child(up)

	var roof := GladeRoof.new()
	roof.name = "Roof"
	roof.style = timber
	roof.pitch_degrees = 50.0
	roof.overhang = 0.5
	w.add_child(roof)

	_ledge(w, Vector3(span * 0.5, 2.95, deep), 3.2, 1.3)
	return w


## A ROUND TOWER. The deck is a flat rectangle and the wall is not, so this is where "the ledge
## starts where the stone stops" has to be true rather than nearly true.
func _tower(at: Vector3) -> GladeWall:
	var stone: GladeStyle = load(STONE)
	var w := GladeWall.new()
	w.name = "Tower"
	w.position = at
	w.rng_seed = 9
	w.style = stone
	root.add_child(w)                          # make_cylinder wants a live node
	w.make_cylinder(2.4, 20)
	root.remove_child(w)
	w.storeys = [_storey(2.7, 0.0, stone), _storey(2.6, 0.0, stone)]
	_ledge(w, Vector3(0, 2.9, 2.4), 2.2, 1.1)
	return w


func _ledge(w: GladeWall, at: Vector3, width: float, project: float) -> void:
	var L := GladeLedge.new()
	L.name = "Balcony"
	L.position = at
	L.width = width
	L.project = project
	w.add_child(L)


func _storey(h: float, jetty: float, st: GladeStyle) -> GladeStorey:
	var s := GladeStorey.new()
	s.height = h
	s.jetty = jetty
	s.style = st
	return s
