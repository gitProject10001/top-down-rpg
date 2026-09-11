extends SceneTree
## THE CUBE TEST, looked at. One `GladeMass`, two styles, and the only question that matters:
## DOES THE EDGE BLEND?
##
## The `mass_arris` suite proves the numbers — nothing passes through anything, every course carries
## a corner stone, the beds line up, the quoin alternates. None of that answers whether the arris
## READS as a corner, and the adobe cycle is the standing reminder: a style that passed at plate
## framing gave up five defects the moment the camera came in to two metres. So this frames the same
## solid three ways and the third one is a close-up of the edge itself.
##
##   wide    the whole cube, both dressed faces visible, so the two styles read as two materials
##   four    all four sides dressed and alternating — every arris cut, no bare corner
##   close   the arris at about two metres, which is where a quoin is judged
##
## Needs a real rendering context, so run it WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1400x760 --script res://scripts/gladekit_tests/shot_mass.gd -- --out=C:/some/folder

const WARMUP := 30
const STONE := "res://addons/gladekit/styles/crypt_stone.tres"
const SIZE := Vector3(4.0, 3.0, 4.0)

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

	# Raking light across the arris on purpose. A corner is read by the shadow line down it, so a
	# sun square to one face would hide precisely the thing being judged.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -155, 0)
	sun.light_energy = 1.25
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

	var crypt: GladeStyle = load(STONE)
	var pale: GladeStyle = crypt.duplicate()
	# Compatible geometry, different colour — the case "two styles that meet at an edge" means. A
	# palette this much lighter is deliberate: if the arris is wrong, a subtle pair would hide it.
	var pale_palette: Array[Color] = [Color(0.82, 0.78, 0.65), Color(0.74, 0.70, 0.57),
			Color(0.88, 0.84, 0.72)]
	pale.palette = pale_palette
	pale.palette_weights = PackedFloat32Array([3, 2, 2])

	var two := _mass(crypt, pale, false)
	two.position = Vector3(-3.2, 0, 0)
	world.add_child(two)

	var four := _mass(crypt, pale, true)
	four.position = Vector3(3.2, 0, 0)
	world.add_child(four)

	# THE CONTROL, and the reason this shot has four frames rather than three. A rendering shows
	# everything at once and says nothing about which part is new: the first close-up of the arris
	# showed pronounced horizontal shelving across both faces, and there was no way to tell from the
	# picture alone whether the mass had introduced it or `crypt_stone` simply looks like that. So an
	# ORDINARY `GladeWall` box, same style, same size, same seed, stands beside the cubes. Whatever
	# both do is the style. Whatever only the mass does is mine.
	var ctrl := GladeWall.new()
	ctrl.name = "ControlWall"
	var c := Curve3D.new()
	for p in [Vector3.ZERO, Vector3(SIZE.x, 0, 0), Vector3(SIZE.x, 0, SIZE.z),
			Vector3(0, 0, SIZE.z), Vector3.ZERO]:
		c.add_point(p)
	ctrl.curve = c
	ctrl.plan_mode = GladeWall.PlanMode.BOX
	ctrl.wall_height = SIZE.y
	ctrl.rng_seed = 9
	ctrl.style = crypt
	ctrl.position = Vector3(-3.2 - SIZE.x * 0.5, 0, -8.0)
	world.add_child(ctrl)

	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.current = true

	# The shared arris of the LEFT cube is its -X/-Z corner, at world (-5.2, *, -2.0). Both dressed
	# faces are visible from outside that corner.
	_look(Vector3(-11.5, 4.6, -9.4), Vector3(-3.6, 1.5, -1.6), 46.0)
	await _shoot("mass_two_faces")

	_look(Vector3(10.6, 5.2, -9.8), Vector3(3.2, 1.5, -1.2), 46.0)
	await _shoot("mass_four_faces")

	# ...and the edge itself, at two metres. If the mitre or the quoin is wrong, this is where it is
	# obvious and nowhere else is.
	_look(Vector3(-7.6, 1.9, -5.4), Vector3(-5.2, 1.5, -2.0), 34.0)
	await _shoot("mass_arris_close")

	# The control wall's -X/-Z corner sits at world (-5.2, *, -8.0) — the same corner geometry as the
	# mass's, framed identically, so the two close-ups can be laid side by side.
	_look(Vector3(-7.6, 1.9, -11.4), Vector3(-5.2, 1.5, -8.0), 34.0)
	await _shoot("mass_control_wall_close")

	# EVERY BASIC FORM in a row, because `sides` is one number that decides three things at once —
	# the prism, how many arrises it has, and whether those arrises are corners at all. The 20-sided
	# one must read ROUND: its 18-degree joints are under `corner_angle_deg`, so they are left smooth
	# rather than growing twenty pilasters.
	for n: Node in world.get_children():
		if n is GladeMass or n is GladeWall:
			n.queue_free()
	await process_frame
	var x := -9.0
	for n in [3, 4, 6, 8, 20]:
		var pm := GladeMass.new()
		pm.name = "Prism%d" % n
		pm.shape = GladeMass.Shape.PRISM
		pm.sides = n
		pm.size = Vector3(3.2, 3.4, 3.2)
		pm.rng_seed = 4
		pm.style = crypt
		pm.position = Vector3(x, 0, 0)
		world.add_child(pm)
		x += 4.6
	_look(Vector3(0.5, 7.0, 15.0), Vector3(0.5, 1.5, 0.0), 46.0)
	await _shoot("mass_shapes")
	quit(0)


func _mass(a: GladeStyle, b: GladeStyle, all_four: bool) -> GladeMass:
	var m := GladeMass.new()
	m.name = "MassFour" if all_four else "MassTwo"
	m.size = SIZE
	m.rng_seed = 9
	if all_four:
		m.style_left = a
		m.style_right = b
		m.style_front = b
		m.style_back = a
	else:
		m.style_left = a                       # -X
		m.style_front = b                      # -Z
	return m


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
