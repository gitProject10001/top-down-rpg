extends SceneTree
## THE ROUGH EXAMPLE: trace the sample plan, bake it, photograph it from the game's ~53° angle.
## NOT headless — the dummy renderer has no pixels:
##   Godot_console.exe --path . --resolution 1280x800 --script res://scripts/floorplan_tests/shot_floorplan.gd -- --out=C:/some/folder [--image=path.png --ppm=62]
## Writes <out>/floorplan_bake.png (the 3D blockout) and <out>/floorplan_plan.png (the traced
## input), and the baked scene next to them as floorplan_bake.tscn.

const Geo := preload("res://addons/floorplan/core/plan_geometry.gd")
const Tracer := preload("res://addons/floorplan/core/plan_tracer.gd")
const Baker := preload("res://addons/floorplan/core/plan_baker.gd")
const Fixture := preload("res://scripts/floorplan_tests/floorplan_fixture.gd")
const Kit := preload("res://addons/floorplan/data/blockout_kit.gd")
const Plugin := preload("res://addons/floorplan/plugin.gd")
const Refine := preload("res://addons/floorplan/core/plan_refine.gd")
const PlanStairScript := preload("res://addons/floorplan/nodes/plan_stair.gd")

var _out := "user://"
var _image := ""
var _ppm := Fixture.PPM


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a.begins_with("--image="):
			_image = a.substr(8)
		elif a.begins_with("--ppm="):
			_ppm = a.substr(6).to_float()
	_run()


func _run() -> void:
	var img: Image = Image.load_from_file(_image) if _image != "" else Fixture.build()
	img.save_png(_out + "floorplan_plan.png")
	var legend: Resource = Plugin.default_legend()
	var res: Dictionary = Tracer.trace(img, legend, _ppm, {})
	var data := {"ppm": Tracer.PLAN_PPM, "islands": Geo.compute(res.shapes), "doors": res.doors,
			"props": res.props}
	print("[SHOT] %d islands, %d doors, %d props" % [data.islands.size(), res.doors.size(), res.props.size()])
	var bake: Node3D = Baker.build(data, Kit.new(), legend, "FloorplanBake")
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(bake)
	Baker.save_to(bake, _out + "floorplan_bake.tscn")

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)

	for i in 6:
		await process_frame
	var bounds := AABB()
	var first := true
	for rm in _walk(bake):
		if rm is CSGCombiner3D and rm.has_meta("floorplan_room"):
			var m: Array = (rm as CSGCombiner3D).get_meshes()
			if m.size() == 2 and m[1] != null:
				var ab: AABB = (rm as Node3D).global_transform * (m[1] as Mesh).get_aabb()
				bounds = ab if first else bounds.merge(ab)
				first = false
	if first:
		bounds = AABB(Vector3.ZERO, Vector3(10, 3, 8))
	var centre := bounds.get_center()
	var radius := bounds.size.length() * 1.15
	var cam := Camera3D.new()
	# The game's ~53° pitch, swung a little toward the corridor side so both rooms read.
	var dir := Vector3(0.45, sin(deg_to_rad(53.0)), cos(deg_to_rad(53.0))).normalized()
	cam.fov = 45.0
	world.add_child(cam)                       # look_at needs the node in the tree
	cam.look_at_from_position(centre + dir * radius, centre, Vector3.UP)
	cam.make_current()
	for i in 12:
		await process_frame
	var shot := root.get_viewport().get_texture().get_image()
	shot.save_png(_out + "floorplan_bake.png")
	print("[SHOT] wrote %sfloorplan_bake.png (bounds %s)" % [_out, str(bounds)])

	# STEP 2 on the same scene: a material on every wall, then Finalize — proves the material
	# rides through CSG onto the baked meshes, and that the walls are plain meshes afterwards.
	var kit := Kit.new()
	var brick := StandardMaterial3D.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.35, 0.28))
	g.set_color(1, Color(0.8, 0.62, 0.5))
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_LINEAR
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0.25, 0.25)
	grad.repeat = GradientTexture2D.REPEAT
	grad.width = 64
	grad.height = 64
	brick.albedo_texture = grad
	# No triplanar (it would kill height/parallax); Finalize gives the meshes metric UVs, so
	# UV1 scale is tiles per metre — one 2 m tile everywhere, floor and walls alike.
	brick.uv1_triplanar = false
	brick.uv1_scale = Vector3(0.5, 0.5, 1)
	kit.wall_material = brick
	var ops: Array = Refine.apply_assets(bake, legend, kit)
	Refine.apply_ops(ops, bake)
	ops = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	for i in 8:
		await process_frame
	var csg_left := 0
	for n in _walk(bake):
		if n is CSGShape3D:
			csg_left += 1
	print("[SHOT] finalized: %s, CSG nodes left: %d" % [Refine.summary(ops), csg_left])
	Baker.save_to(bake, _out + "floorplan_final.tscn")
	root.get_viewport().get_texture().get_image().save_png(_out + "floorplan_final.png")
	print("[SHOT] wrote %sfloorplan_final.png" % _out)

	# ROOMS INSIDE ROOMS: a 10 × 8 m hall with a ROOM drawn in one corner (its outline becomes
	# interior walls, with a door), and a drawn wall from that room's side to the outline — a
	# T-junction at one end, flush at the other, with a door of its own. Kit greys, finalized,
	# from high up so the walls read as a plan.
	bake.get_parent().remove_child(bake)
	bake.free()
	var hall := Geo.compute([{"poly": Geo.rect(Vector2(500, 400), Vector2(1000, 800)), "op": 0}])
	var rooms := {"ppm": 100.0, "islands": hall, "props": [],
			"doors": [{"pos": Vector2(300, 405), "width_m": 1.0}, {"pos": Vector2(750, 255), "width_m": 1.2}],
			"walls": [{"points": Geo.rect(Vector2(300, 250), Vector2(400, 300)), "closed": true, "t": 0.0},
					{"points": PackedVector2Array([Vector2(500, 250), Vector2(1000, 250)]), "closed": false, "t": 0.0}]}
	var bake_r: Node3D = Baker.build(rooms, Kit.new(), legend, "FloorplanRooms")
	world.add_child(bake_r)
	ops = await Refine.finalize(bake_r, self)
	Refine.apply_ops(ops, bake_r)
	var parts := 0
	for n in _walk(bake_r):
		if n.name.begins_with("Partition_"):
			parts += 1
	var rc := Vector3(5.0, 0.0, 4.0)
	var rdir := Vector3(0.15, sin(deg_to_rad(62.0)), cos(deg_to_rad(62.0))).normalized()
	cam.look_at_from_position(rc + rdir * 14.5, rc, Vector3.UP)
	for i in 12:
		await process_frame
	Baker.save_to(bake_r, _out + "floorplan_rooms.tscn")
	root.get_viewport().get_texture().get_image().save_png(_out + "floorplan_rooms.png")
	print("[SHOT] wrote %sfloorplan_rooms.png (%d partitions)" % [_out, parts])
	bake_r.get_parent().remove_child(bake_r)
	bake_r.free()
	cam.look_at_from_position(centre + dir * radius, centre, Vector3.UP)

	# TWO FLOORS: the traced plan downstairs, a smaller room upstairs, a stair between them.
	# A 5.5 m run for the 4.7 m pitch (40°); its passage starts where the plan node says.
	var p0 := PlanStairScript.passage_start(4.7, 0.2, 5.5, 0) / 5.5
	var ground: Dictionary = {"index": 0, "islands": data.islands, "doors": res.doors, "props": res.props,
			"stairs": [{"pos": Vector2(120, 250), "rot": 0.0, "width_m": 1.2, "length_m": 5.5, "steps": 0,
			"footprint": Geo.rect(Vector2(120 + 550 * (p0 + 1.0) * 0.5, 250), Vector2(550 * (1.0 - p0), 120))}]}
	var up_room := Geo.compute([{"poly": Geo.rect(Vector2(400, 250), Vector2(700, 380)), "op": 0}])
	var upper: Dictionary = {"index": 1, "islands": up_room, "doors": [], "props": [], "stairs": []}
	var two := {"ppm": Tracer.PLAN_PPM, "pitch": 4.7, "levels": [ground, upper]}
	var bake2: Node3D = Baker.build(two, Kit.new(), legend, "FloorplanFloors")
	world.add_child(bake2)
	for i in 8:
		await process_frame
	cam.look_at_from_position(centre + Vector3(0.6, 1.1, 0.8).normalized() * radius * 1.35
			+ Vector3(0, 2.0, 0), centre + Vector3(0, 2.0, 0), Vector3.UP)
	for i in 8:
		await process_frame
	Baker.save_to(bake2, _out + "floorplan_floors.tscn")
	root.get_viewport().get_texture().get_image().save_png(_out + "floorplan_floors.png")
	print("[SHOT] wrote %sfloorplan_floors.png" % _out)

	# THE UPPER FLOOR FROM ABOVE, walls and all: the stairwell must read as an opening in the slab
	# with the top treads visible through it, and nothing standing around it.
	var up_c := Vector3(4.0, 4.7, 2.5)
	cam.look_at_from_position(up_c + Vector3(0.0, 12.0, 0.01), up_c, Vector3.UP)
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "floorplan_upper.png")
	print("[SHOT] wrote %sfloorplan_upper.png" % _out)

	# THE STAIR CLOSE-UP: the ramp collider shown translucent over the steps, the passage in the
	# floor above, seen from beside the run. The upper room's walls are hidden so the slab reads.
	var stair := bake2.get_node("Level_0/Stairs/Stair_1") as Node3D
	var ramp := stair.get_node("Ramp") as CSGPolygon3D
	ramp.visible = true
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.2, 0.9, 0.4, 0.35)
	ramp.material = glass
	# Cut-away: no walls on either floor, so the run, the ramp and the passage are in the open.
	for n in _walk(bake2):
		if n.name.begins_with("Wall_") or n.name.begins_with("Door_"):
			(n as Node3D).visible = false
	for i in 8:
		await process_frame
	var foot := stair.global_position
	var along := stair.global_transform.basis.x
	var side := stair.global_transform.basis.z
	var head := foot + along * 5.5 + Vector3(0, 4.7, 0)
	var look := (foot + head) * 0.5
	cam.look_at_from_position(look - along * 1.0 + side * 8.5 + Vector3(0, 2.5, 0), look, Vector3.UP)
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out + "floorplan_stair.png")
	print("[SHOT] wrote %sfloorplan_stair.png" % _out)

	# BREAKS: a finalized plaster wall with three break decals, lit low from the side so the rim
	# bevel and the cavity shadow read. Textures come straight from the PNGs (no importer here).
	for n in _walk(bake2):
		if n is Node3D:
			(n as Node3D).visible = true
	bake2.get_parent().remove_child(bake2)
	bake2.free()
	var wall_plan := {"ppm": 100.0, "islands": Geo.compute([{"poly": Geo.rect(Vector2(300, 200), Vector2(600, 400)), "op": 0}]),
			"doors": [], "props": []}
	var kit3 := Kit.new()
	kit3.wall_material = load("res://assets/materials/whinbek_plaster.tres")
	kit3.floor_material = load("res://assets/materials/whinbek_rubble.tres")
	var bake3: Node3D = Baker.build(wall_plan, kit3, legend, "BreakWall")
	world.add_child(bake3)
	var fops: Array = await Refine.finalize(bake3, self)
	Refine.apply_ops(fops, bake3)
	var pdir := ProjectSettings.globalize_path("res://assets/textures/breaks/")
	var at := [Vector3(1.6, 1.5, 0.01), Vector3(3.2, 1.2, 0.01), Vector3(4.6, 1.8, 0.01)]
	var i := 0
	for v in ["a", "b", "c"]:
		var dec := Decal.new()
		dec.texture_albedo = ImageTexture.create_from_image(Image.load_from_file(pdir + "break_%s_albedo.png" % v))
		dec.texture_normal = ImageTexture.create_from_image(Image.load_from_file(pdir + "break_%s_normal.png" % v))
		dec.texture_orm = ImageTexture.create_from_image(Image.load_from_file(pdir + "break_%s_orm.png" % v))
		dec.size = Vector3(1.1, 0.6, 1.0)
		dec.normal_fade = 0.3
		# +Y out of the top wall (z = 0) into the room (+Z): X along the wall, Y = +Z, Z = X × Y.
		dec.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.RIGHT.cross(Vector3.BACK)), at[i])
		i += 1
		bake3.add_child(dec)
	# The decals sit on the top wall's ROOM face (z = 0, facing +Z). Light travels toward −Z at a
	# low angle from the right (a DirectionalLight3D shines along its −Z; yaw 20° turns that to
	# (−0.34, −0.42, −0.94)), and the camera stands inside the room, 3.4 m back.
	sun.rotation_degrees = Vector3(-25, 20, 0)
	for k in 10:
		await process_frame
	var target := Vector3(3.0, 1.5, 0.0)
	cam.look_at_from_position(target + Vector3(0.6, 0.5, 3.4), target, Vector3.UP)
	for k in 8:
		await process_frame
	var img3 := root.get_viewport().get_texture().get_image()
	img3.save_png(_out + "floorplan_break.png")
	var magenta := 0
	for y in range(0, img3.get_height(), 4):
		for x in range(0, img3.get_width(), 4):
			var px := img3.get_pixel(x, y)
			if px.r > 0.9 and px.b > 0.9 and px.g < 0.1:
				magenta += 1
	print("[SHOT] wrote %sfloorplan_break.png (magenta pixels sampled: %d)" % [_out, magenta])
	quit(0)


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out
