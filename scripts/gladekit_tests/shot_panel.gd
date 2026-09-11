extends SceneTree
## PANEL MODE, looked at — the proof of concept for "the detail lives in the material".
##
## Three things this has to show, and only a render can:
##
##   1. THE SHEETS FACE OUT. The first cut wound them counter-clockwise about the outward normal,
##      which is the BACK face in Godot, so the wall rendered inside out — the exact mistake
##      `glade_brick_mesh.gd`'s header says the adobe cycle lost a render to. If this frame is lit
##      and solid rather than black and see-through, the winding is right.
##   2. THE TEXTURE TILES CONTINUOUSLY across a bend, because UVs run in metres of wall rather than
##      0..1 per quad. A seam at every arc split would be obvious on a curved wall and invisible on
##      a straight one, so the wall here BENDS.
##   3. IT COSTS ALMOST NOTHING. The masonry wall beside it is the same shape in stone; compare the
##      piece counts printed on the way past.
##
## THE TEXTURE IS PROCEDURAL, deliberately: this proves the plumbing (albedo + normal map + tangents
## + tiling) with no asset in the repo. Drop a real stone set into `assets/textures/`, point a
## StandardMaterial3D at it, put that on the style's `material`, and nothing else changes.
##
## Needs a real rendering context, so run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1500x760 --script res://scripts/gladekit_tests/shot_panel.gd -- --out=C:/some/folder

const WARMUP := 90                             ## noise textures generate on a thread; give them time
const STONE := "res://addons/gladekit/styles/crypt_stone.tres"

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
	e.background_color = Color(0.55, 0.63, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.66, 0.76)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)

	# Raking light, because a normal map that is not working looks exactly like one that is until
	# the light comes in from the side.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -142, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(80, 80)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.26)
	pl.material = gm
	ground.mesh = pl
	world.add_child(ground)

	# --- the panel style ---------------------------------------------------------------------
	var panel_style: GladeStyle = load(STONE).duplicate()
	panel_style.wall_mode = GladeStyle.WallMode.PANEL
	panel_style.panel_uv_scale = 1.6
	panel_style.material = _stone_material()

	var pw := _bent_wall(Vector3(-4.5, 0, 0), panel_style)
	world.add_child(pw)

	# ...and the same wall in stone, for the count.
	var masonry: GladeStyle = load(STONE)
	var mw := _bent_wall(Vector3(5.5, 0, 0), masonry)
	world.add_child(mw)

	# A MASS in panel mode too — the point being that a fill mode does not know which node it is
	# working for, so this needed no code at all.
	var m := GladeMass.new()
	m.name = "PanelMass"
	m.size = Vector3(3.0, 2.8, 3.0)
	m.style = panel_style
	m.position = Vector3(0.5, 0, 6.5)
	world.add_child(m)

	await process_frame
	print("[PANEL] panel wall pieces: %d   masonry wall pieces: %d"
			% [pw.snap_transforms.size(), mw.snap_transforms.size()])
	print("[PANEL] panel wall stats: %s" % [pw.stats])

	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.current = true

	_look(Vector3(0.0, 5.0, 15.0), Vector3(0.5, 1.6, 1.0), 52.0)
	await _shoot("panel_overview")

	# Close, and across the BEND, which is where a per-quad UV would show a seam.
	_look(Vector3(-7.0, 1.8, 6.0), Vector3(-3.4, 1.5, 1.2), 40.0)
	await _shoot("panel_close")

	# --- THE SOLIDS, from high enough to see their tops ---------------------------------------
	# The whole point of the skin work: a panel solid must read SOLID, its top must exist, and an
	# untextured one must be visible at all. Four cases, left to right.
	for n: Node in world.get_children():
		if n is GladeMass or n is GladeWall:
			n.queue_free()
	await process_frame

	var plain: GladeStyle = load(STONE).duplicate()
	plain.wall_mode = GladeStyle.WallMode.PANEL    # no material at all: palette vertex colours only
	var thick: GladeStyle = panel_style.duplicate()
	thick.depth = 0.7
	var thin: GladeStyle = panel_style.duplicate()
	thin.depth = 0.15

	# 1. textured solid   2. untextured solid   3. hollow, two wall thicknesses   4. no style
	var solid := _solid(panel_style, Vector3(-6.0, 0, 0))
	world.add_child(solid)
	world.add_child(_solid(plain, Vector3(-1.5, 0, 0)))
	var room := _solid(panel_style, Vector3(3.0, 0, 0))
	room.hollow = true
	room.style_left = thick
	room.style_front = thin
	world.add_child(room)
	var blank := GladeMass.new()
	blank.name = "NoStyle"
	blank.size = Vector3(2.6, 2.4, 2.6)
	blank.position = Vector3(7.5, 0, 0)
	world.add_child(blank)

	await process_frame
	print("[PANEL] solid=%s  hollow=%s  styleless children=%d"
			% [solid.stats, room.stats, blank.get_child_count(true)])

	_look(Vector3(0.4, 6.4, 10.5), Vector3(0.4, 1.0, 0.0), 52.0)
	await _shoot("panel_solids")

	# Down into the hollow one, because "there is a room in there and its walls are different
	# thicknesses" is the one claim the wide shot cannot support.
	_look(Vector3(3.0, 5.6, 3.4), Vector3(3.0, 1.2, 0.0), 46.0)
	await _shoot("panel_hollow")
	quit(0)


func _solid(st: GladeStyle, at: Vector3) -> GladeMass:
	var m := GladeMass.new()
	m.name = "Solid"
	m.size = Vector3(2.6, 2.4, 2.6)
	m.rng_seed = 3
	m.style = st
	m.position = at
	return m


## A wall that BENDS, so the panel has to follow it and the texture has to survive the splits.
func _bent_wall(at: Vector3, st: GladeStyle) -> GladeWall:
	var w := GladeWall.new()
	w.name = "Panel" if st.wall_mode == GladeStyle.WallMode.PANEL else "Masonry"
	var c := Curve3D.new()
	c.add_point(Vector3(-3.0, 0, 2.0))
	c.add_point(Vector3(0.0, 0, 0.0))
	c.add_point(Vector3(3.2, 0, 1.4))
	w.curve = c
	w.position = at
	w.wall_height = 3.2
	w.rng_seed = 6
	w.style = st

	var door := GladeOpening.new()
	door.name = "Door"
	door.position = Vector3(0.0, 0.0, 0.0)
	door.width = 1.1
	door.height = 2.0
	door.arched = false
	w.add_child(door)
	return w


## A stand-in stone material: cellular noise for the albedo, the same field as a normal map. Enough
## to prove albedo + normal + tangents + tiling all arrive; not a substitute for a real texture set.
func _stone_material() -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.022
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	n.cellular_jitter = 1.0

	var albedo := NoiseTexture2D.new()
	albedo.noise = n
	albedo.seamless = true                     # or every tile boundary is a visible line
	albedo.width = 512
	albedo.height = 512

	var normal := NoiseTexture2D.new()
	normal.noise = n
	normal.seamless = true
	normal.width = 512
	normal.height = 512
	normal.as_normal_map = true
	normal.bump_strength = 12.0

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo
	mat.albedo_color = Color(0.72, 0.66, 0.56)
	mat.normal_enabled = true
	mat.normal_texture = normal
	mat.normal_scale = 1.4
	mat.roughness = 0.92
	# The panel emits both faces as separate sheets with opposed normals, so back-face culling is
	# correct and wanted: it is what makes the inside-out failure visible instead of hidden.
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


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
