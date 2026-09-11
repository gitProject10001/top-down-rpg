extends SceneTree
## TEMPORARY: look at the rocks. Builds rows of variants in code — no scene file — and saves a PNG.
## Run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1500x900 \
##       --script res://scripts/gladekit_tests/probe_rock_shot.gd -- --out=C:/some/folder

const WARMUP := 20

## name, displace, strata, facet, erosion, facets, subdiv
const ROWS := [
	["bare d0 s0", 0.00, 0.0, 0.0, 0.00, 13, 0],
	["d08 s0", 0.08, 0.0, 0.5, 0.25, 13, 0],
	["d14 s1", 0.14, 0.0, 0.5, 0.25, 13, 1],
	["d22 s1", 0.22, 0.0, 0.5, 0.35, 13, 1],
	["strata.7 s1", 0.16, 0.7, 0.5, 0.30, 11, 1],
	["blocky f9 s0", 0.10, 0.0, 0.9, 0.20, 9, 0],
]

var _out := "user://"


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

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.20, 0.22, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.72)
	e.ambient_light_energy = 0.45
	env.environment = e
	world.add_child(env)

	# RAKING light. Facets are only visible if something crosses them at a shallow angle; lit from
	# the camera every rock in the world looks like a smooth lump.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-22, 38, 0)
	sun.shadow_enabled = true
	world.add_child(sun)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.60, 0.57)
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true

	# ONE ROW PER FAMILY. The composition can only be judged once the primitive is known good, and
	# guessing at the fill while the meshes were wrong cost two renders.
	var f := GladeRockField.new(3)
	f.displace = 0.10
	f.facet = 0.6
	f.erosion = 0.30
	f._apply()
	var fams := [GladeRockMesh.Family.COLUMN, GladeRockMesh.Family.SHARD,
			GladeRockMesh.Family.BLOCK, GladeRockMesh.Family.SLAB,
			GladeRockMesh.Family.PLATE, GladeRockMesh.Family.BOULDER]
	var names := ["COLUMN", "SHARD", "BLOCK", "SLAB", "PLATE", "BOULDER"]
	for r in fams.size():
		var d: Dictionary = GladeRockMesh.FAMILIES[fams[r]]
		for i in 6:
			var mi := MeshInstance3D.new()
			mi.mesh = GladeRockMesh.build(i + 1, f, int(d.f), d.r, 0.26, float(d.cut), 0, false, float(d.top))
			mi.material_override = mat
			# scaled UNIFORMLY, exactly as the fill mode does, so what is on screen is what a
			# formation will actually be built out of
			mi.scale = Vector3.ONE * 0.9
			mi.position = Vector3(float(i) * 1.6 - 4.0, 0.0, float(r) * 1.7 - 4.2)
			world.add_child(mi)
		var sz := GladeRockMesh.size_of(1, f, int(d.f), d.r, 0.26, float(d.cut), 0, false, float(d.top))
		print("  %-8s footprint %.2f x %.2f   height %.2f   (h/foot %.2f)"
				% [names[r], sz.x, sz.z, sz.y, sz.y / maxf(maxf(sz.x, sz.z), 0.01)])

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.34, 0.36, 0.33)
	fmat.roughness = 1.0
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0, -0.01, 0)
	world.add_child(floor_mi)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 32.0
	cam.current = true
	cam.look_at_from_position(Vector3(-3.2, 5.6, 8.4), Vector3(-0.3, 0.25, 0.0), Vector3.UP)

	for i in WARMUP:
		await process_frame
	await _shot("grid")

	# and one from two metres, because the wide shot flatters everything
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(-2.6, 1.1, -1.2), Vector3(-0.6, 0.28, -2.1), Vector3.UP)
	for i in 6:
		await process_frame
	await _shot("close")
	quit(0)


func _shot(name: String) -> void:
	for i in 4:
		await process_frame
	var path := "%srockprobe_%s.png" % [_out, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("[ROCK] %s %s (%d x %d)" % ["ok  " if err == OK else "FAIL", path,
			img.get_width(), img.get_height()])
