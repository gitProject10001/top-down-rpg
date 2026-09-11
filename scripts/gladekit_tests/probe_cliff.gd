extends SceneTree
## TEMPORARY: look at a ROCK-mode wall. Builds cliffs in code, no scene file.
##   Godot_console.exe --path . --resolution 1500x900 \
##       --script res://scripts/gladekit_tests/probe_cliff.gd -- --out=C:/some/folder

const STYLE := "res://addons/gladekit/styles/cliff_granite.tres"
const WARMUP := 24

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
	e.background_color = Color(0.44, 0.56, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.78)
	e.ambient_light_energy = 0.40
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.45
	sun.rotation_degrees = Vector3(-30, 42, 0)
	sun.shadow_enabled = true
	world.add_child(sun)

	# REAL TERRAIN, with collision — a rolling surface built from a displaced grid. A flat plane
	# proves nothing about `conform_to_ground`, and "the rocks float" is only visible over ground
	# that actually moves.
	world.add_child(_terrain())

	var st: GladeStyle = load(STYLE)
	# WELD the aggregate into one surface for this run.
	st = st.duplicate()
	st.rock_weld = 0.10
	st.rock_weld_cell = 0.40

	# 1. THE BARRIER — a 13 m face that delimits an area. The requirement, at full scale.
	var barrier := _wall(world, [Vector3(-16, 0, -6), Vector3(-6, 0, -9), Vector3(4, 0, -7),
			Vector3(13, 0, -2)], st, 13.0, 11)

	# 2. an arch worn through it, to prove openings cut a cliff
	var arch := GladeOpening.new()
	arch.width = 3.4
	arch.height = 4.2
	arch.arched = true
	barrier.add_child(arch)
	arch.position = barrier.to_local(Vector3(-4.0, 0, -8.4))
	arch.position.y = 0.0

	# 3. a low outcrop, closed plan — the freestanding case
	_wall(world, [Vector3(-13, 0, 9), Vector3(-8, 0, 11), Vector3(-5, 0, 8),
			Vector3(-9, 0, 5.5), Vector3(-13, 0, 9)], st, 3.4, 23)

	# 4. a tall spire, to see the taper work
	_wall(world, [Vector3(9, 0, 8), Vector3(12, 0, 9.5), Vector3(13.5, 0, 6.5),
			Vector3(10, 0, 5.5), Vector3(9, 0, 8)], st, 9.0, 41)

	# --- the scatter node, all three region modes
	var scree: GladeStyle = load("res://addons/gladekit/styles/scree_stone.tres")

	var field := GladeRocks.new()
	field.name = "RockField"
	field.region_mode = GladeRocks.RegionMode.BOX
	field.style = scree
	field.conform_to_ground = true
	field.density = 0.7
	field.size = 0.5
	field.position = Vector3(-4, 0, 6)
	world.add_child(field)
	field.make_box(9.0, 6.0)

	var line := GladeRocks.new()
	line.name = "RockLine"
	line.region_mode = GladeRocks.RegionMode.PATH
	line.style = scree
	line.conform_to_ground = true
	line.path_width = 2.6
	line.density = 1.1
	line.size = 0.36
	line.big_chance = 0.06
	var lc := Curve3D.new()
	for p in [Vector3(2, 0, 2), Vector3(6, 0, 4), Vector3(9, 0, 1), Vector3(13, 0, 2)]:
		lc.add_point(p)
	line.curve = lc
	world.add_child(line)

	var painted := GladeRocks.new()
	painted.name = "Painted"
	painted.style = scree
	painted.conform_to_ground = true
	painted.density = 1.4
	painted.size = 0.42
	painted.position = Vector3(-14, 0, 2)
	world.add_child(painted)
	for i in 26:
		var a := float(i) * 0.44
		painted.paint_at(painted.to_global(Vector3(cos(a) * a * 0.24, 0, sin(a) * a * 0.24)),
				Vector3.UP, 1.3, 1.0)

	for i in WARMUP:
		await process_frame
	_report(world)
	for n in [field, line, painted]:
		print("  %-10s %s" % [n.name, n.stats])

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40.0
	cam.far = 400.0
	cam.current = true

	# the top-down-ish three-quarter the game is actually played at
	cam.look_at_from_position(Vector3(-4, 34, 48), Vector3(-1, 4.0, -2), Vector3.UP)
	await _shot("wide")

	cam.fov = 36.0
	cam.look_at_from_position(Vector3(-4, 9, 20), Vector3(-2, 0.5, 4), Vector3.UP)
	await _shot("scatter")

	cam.fov = 34.0
	cam.look_at_from_position(Vector3(-5.5, 3.0, 3.5), Vector3(-4.2, 2.6, -6.5), Vector3.UP)
	await _shot("arch")

	cam.fov = 38.0
	cam.look_at_from_position(Vector3(-9.5, 2.4, 14.5), Vector3(-9.0, 1.4, 8.5), Vector3.UP)
	await _shot("outcrop")

	# TWO METRES from where a block meets the ground and where two blocks meet each other
	cam.fov = 44.0
	cam.look_at_from_position(Vector3(6.5, 1.6, 12.0), Vector3(10.5, 2.6, 8.0), Vector3.UP)
	await _shot("close")
	quit(0)


## A rolling ground with a collider, so drop-to-ground and conform have something to find.
func _terrain() -> StaticBody3D:
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.018
	n.fractal_octaves = 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size := 120.0
	var step := 2.0
	var cells := int(size / step)
	var h := func(ix: int, iz: int) -> Vector3:
		var x := -size * 0.5 + ix * step
		var z := -size * 0.5 + iz * step
		return Vector3(x, n.get_noise_2d(x, z) * 3.2, z)
	for ix in cells:
		for iz in cells:
			var a: Vector3 = h.call(ix, iz)
			var b: Vector3 = h.call(ix + 1, iz)
			var c: Vector3 = h.call(ix + 1, iz + 1)
			var d: Vector3 = h.call(ix, iz + 1)
			for tri: Array in [[a, d, c], [a, c, b]]:
				# WIND IT, do not just name the normal. Godot's front face is CLOCKWISE about the
				# outward normal, so the right-hand normal of the emitted order must OPPOSE it —
				# the same rule GladeRockMesh._commit() states. Setting the normal alone leaves the
				# winding wrong and the whole ground is backface-culled: invisible, with everything
				# apparently floating in the sky.
				var gn: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
				if gn.y > 0.0:
					tri = [tri[0], tri[2], tri[1]]
					gn = -gn
				st.set_normal(-gn.normalized())
				for v: Vector3 in tri:
					st.add_vertex(v)
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.name = "Terrain"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.46, 0.34)
	gm.roughness = 1.0
	mi.material_override = gm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	return body


func _wall(parent: Node3D, pts: Array, st: GladeStyle, h: float, seed_v: int) -> GladeWall:
	var w := GladeWall.new()
	var c := Curve3D.new()
	for p: Vector3 in pts:
		c.add_point(p)
	w.curve = c
	w.style = st
	w.wall_height = h
	w.rng_seed = seed_v
	var prof := Curve.new()
	prof.add_point(Vector2(0.0, 1.0))
	prof.add_point(Vector2(0.55, 0.86))
	prof.add_point(Vector2(1.0, 0.62))
	w.profile = prof
	w.conform_to_ground = true
	parent.add_child(w)
	w.call_deferred("drop_to_ground")
	return w


func _shot(name: String) -> void:
	for i in 8:
		await process_frame
	var path := "%scliff_%s.png" % [_out, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("[CLIFF] %s %s" % ["ok  " if err == OK else "FAIL", path])


func _report(n: Node) -> void:
	for c in n.get_children():
		if c is GladeWall:
			var s: Dictionary = (c as GladeWall).stats
			var fams := ""
			for k in ["COLUMN", "SHARD", "BLOCK", "SLAB", "PLATE", "BOULDER"]:
				fams += " %s=%d" % [k.substr(0, 3), int(s.get("fam_%d" % ["COLUMN", "SHARD",
						"BLOCK", "SLAB", "PLATE", "BOULDER"].find(k), 0))]
			print("  wall h=%.1f  blocks %d  WELD %d ms  %d tris"
					% [(c as GladeWall).wall_height, int(s.get("rock_blocks", 0)),
							int(s.get("weld_ms", -1)), int(s.get("weld_tris", 0))])
			print("       normals pointing OUT: %.1f%%"
					% [float(s.get("weld_outward", 0.0)) * 100.0])
			var tris := 0
			var inst := 0
			var draws := 0
			for ch in c.get_children(true):
				if ch is MultiMeshInstance3D:
					var mm := (ch as MultiMeshInstance3D).multimesh
					if mm == null or mm.mesh == null:
						continue
					draws += 1
					inst += mm.instance_count
					var t := 0
					for si in mm.mesh.get_surface_count():
						t += (mm.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
								as PackedVector3Array).size() / 3
					tris += t * mm.instance_count
			var shapes := 0
			for ch in c.get_children(true):
				if ch is StaticBody3D:
					shapes += ch.get_child_count()
			print("     draws %d  instances %d  TRIANGLES %d  collision shapes %d"
					% [draws, inst, tris, shapes])
