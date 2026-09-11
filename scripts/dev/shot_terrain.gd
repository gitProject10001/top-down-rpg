extends SceneTree
## Photograph sculpted ground, from the game's own camera pitch.
##
##   Godot_console.exe --path . --resolution 1280x720 --script res://scripts/dev/shot_terrain.gd -- \
##       --out=C:/some/folder
##
## Four subjects, each answering a question a still of a flat plane cannot:
##
##   rolling   — noise ground with grass painted over it. Does the foliage sit ON the hill, and does
##               the hill read as ground rather than as a crumpled sheet? Shot as a 4-FRAME STRIP at
##               0.25 s, because wind phase and TAA smear are invisible in one frame and this is the
##               shot where grass on a slope either settles or crawls.
##   cliff     — a deliberate blocking face, with the slope overlay ON. The red band is the whole
##               point: it is where an enemy would stick, and it should be exactly where you meant.
##   lake      — a carved basin at the waterline.
##   contact   — two metres from where grass meets a slope, which is where a plant that is merely
##               near the ground stops looking like a plant standing on it.
##
## Loading the bench scene is also, deliberately, the smoke test for it: the panel, the terrain node
## and every brush construct here, so a parse error or a missing method fails this run.

const PITCH := 53.0
const TerrainField := preload("res://scripts/terrain_field.gd")

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var lab := (load("res://scenes/dev/foliage_lab.tscn") as PackedScene).instantiate()
	# BEFORE add_child, so the bench never writes anything back. This script sculpts and paints for
	# real; letting it autosave would mean taking a photograph destroyed the terrain being examined.
	lab.autosave = false
	root.add_child(lab)
	current_scene = lab
	for _i in 40:
		await process_frame

	var ground := lab.get_node("Ground")
	# The bench's own specimens and reference patch would fill the frame; the ground is the subject.
	for c in lab.get_children():
		if c is CanvasLayer:
			c.visible = false
	for n: String in ["Grass", "PaintedLayers"]:
		var x := lab.get_node_or_null(n)
		if x is Node3D:
			(x as Node3D).visible = false
	for c in lab.get_children():
		if c.get_class() == "Node3D" and c.name != "PaintedLayers":
			(c as Node3D).visible = false

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 40.0

	# --- rolling: noise ground, grass over it -------------------------------------------------
	ground.max_slope_deg = 30.0
	ground.noise_fill(5, 0.018, 2, 3.2)
	var g := _paint_grass(lab, ground, Vector2(-16.0, -16.0), Vector2(16.0, 16.0))
	for _i in 20:
		await process_frame
	# FAR ENOUGH BACK TO SEE THE GROUND. The first pass framed this at 34 m with grass at 26 tufts/m2
	# and the result was a photograph of grass: not one metre of terrain was visible anywhere in it,
	# in a shot whose whole subject is the shape of the hill. The arena ships at about 10 tufts/m2.
	_aim(cam, Vector3(0.0, 0.0, 0.0), 52.0)
	# FOUR FRAMES, not one. A still cannot show wind phase, TAA smear on a swaying instance, or
	# whether grass on a slope is settling or crawling — and those are the three ways this fails.
	for f in 4:
		await _settle(15)
		_save("terrain_rolling_%d" % f)

	# --- cliff: a blocking face, with the diagnostic on ---------------------------------------
	ground.reset_flat()
	ground.begin_stroke(Vector2.ZERO, TerrainField.Mode.CLIFF, 1.6)
	for _i in 7:
		ground.sculpt(Vector2(0.0, -4.0), 7.0, TerrainField.Mode.CLIFF, 1.3)
	# NO GRASS on the cliff shots. The subject is the face and the band on it, and a canopy over the
	# top of it hides both — the same mistake as framing the rolling shot too close.
	g.visible = false
	ground.material().set_shader_parameter("overlay", true)
	# CLOSER THAN THE WIDE SHOT. main.tscn's fog is tuned for the hub's 234 m spread, and the bench
	# lifts that environment deliberately so it cannot drift from the shipping look — but inside a
	# 64 m field it washes a distant subject almost white. Frame the detail shots near.
	_aim(cam, Vector3(0.0, 2.0, -2.0), 22.0)
	await _settle(20)
	_save("terrain_cliff_overlay")
	ground.material().set_shader_parameter("overlay", false)
	await _settle(10)
	_save("terrain_cliff_plain")
	g.visible = true

	# --- lake ---------------------------------------------------------------------------------
	ground.reset_flat()
	ground.noise_fill(11, 0.02, 2, 1.4)
	ground.begin_stroke(Vector2(0.0, 0.0), TerrainField.Mode.LAKE, 2.0)
	for _i in 10:
		ground.sculpt(Vector2.ZERO, 9.0, TerrainField.Mode.LAKE, 0.55)
	g.visible = false
	_aim(cam, Vector3(0.0, 0.0, 0.0), 24.0)
	await _settle(20)
	_save("terrain_lake")
	g.visible = true
	g.rebuild()

	# --- contact: two metres from where grass meets a slope -----------------------------------
	ground.reset_flat()
	ground.begin_stroke(Vector2.ZERO, TerrainField.Mode.RAISE, 1.6)
	for _i in 5:
		ground.sculpt(Vector2(0.0, -3.0), 8.0, TerrainField.Mode.RAISE, 0.7)
	g.rebuild()
	var eye := Vector3(2.2, 1.4, 4.0)
	cam.global_position = eye
	cam.look_at(Vector3(0.0, 0.9, 0.0))
	cam.fov = 44.0
	await _settle(20)
	_save("terrain_contact")

	quit(0)


## A grass field covering the given local rectangle, seeded on the terrain so it follows the ground.
func _paint_grass(lab: Node, ground: Node, from: Vector2, to: Vector2) -> GrassPatch:
	var g := GrassPatch.new()
	g.name = "ShotGrass"
	g.density = 7.0
	g.rng_seed = 12
	g.tuft_height = 0.5
	g.blades = 5
	g.clump_size = 2.0
	g.sink = 0.05
	g.paint_only = true
	g.brush_radius = 2.2
	lab.add_child(g)
	g.terrain = g.get_path_to(ground)
	var pts := PackedVector2Array()
	var step := 3.0
	var x := from.x
	while x <= to.x:
		var z := from.y
		while z <= to.y:
			pts.append(Vector2(x, z))
			z += step
		x += step
	g.brush_points = pts
	g.rebuild()
	return g


func _aim(cam: Camera3D, at: Vector3, dist: float) -> void:
	cam.global_position = at + Vector3(0.0, sin(deg_to_rad(PITCH)) * dist,
			cos(deg_to_rad(PITCH)) * dist)
	cam.look_at(at)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _save(stem: String) -> void:
	var path := _out + stem + ".png"
	print("[TERRAIN SHOT] %s (%s)" % [path,
			"ok" if root.get_texture().get_image().save_png(path) == OK else "FAILED"])
