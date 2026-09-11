extends SceneTree
## Headless verification for addons/floorplan. Run:
##   Godot_console.exe --headless --path . --script res://scripts/floorplan_tests/verify_floorplan.gd --log-file <fresh path>
## Non-zero exit on any failure. Results also in user://verify_floorplan.txt.
##
## Same crash-detection idiom as verify_dungeon.gd: an error inside an awaited suite unwinds
## silently, so the suite count is checked at the end.

const Geo := preload("res://addons/floorplan/core/plan_geometry.gd")
const Tracer := preload("res://addons/floorplan/core/plan_tracer.gd")
const Baker := preload("res://addons/floorplan/core/plan_baker.gd")
const Fixture := preload("res://scripts/floorplan_tests/floorplan_fixture.gd")
const Legend := preload("res://addons/floorplan/data/plan_legend.gd")
const LegendEntry := preload("res://addons/floorplan/data/plan_legend_entry.gd")
const Kit := preload("res://addons/floorplan/data/blockout_kit.gd")
const Plugin := preload("res://addons/floorplan/plugin.gd")
const Refine := preload("res://addons/floorplan/core/plan_refine.gd")

const EXPECTED_SUITES := 18
const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Layout := preload("res://addons/floorplan/api/plan_layout.gd")
const PlanMasks := preload("res://addons/floorplan/core/plan_masks.gd")
const Breaks := preload("res://tools/make_break_patches.gd")
const PlanUV := preload("res://addons/floorplan/core/plan_uv.gd")
const PlanRootScript := preload("res://addons/floorplan/nodes/plan_root.gd")
const PlanLevelScript := preload("res://addons/floorplan/nodes/plan_level.gd")
const PlanShapeScript := preload("res://addons/floorplan/nodes/plan_shape.gd")
const PlanStairScript := preload("res://addons/floorplan/nodes/plan_stair.gd")
const PlanDoorScript := preload("res://addons/floorplan/nodes/plan_door.gd")
const PlanWallScript := preload("res://addons/floorplan/nodes/plan_wall.gd")
const RoomVis := preload("res://scripts/room_visibility.gd")
const Occl := preload("res://scripts/occluder_fade.gd")
const RoofFadeScript := preload("res://scripts/roof_fade.gd")
const SAMPLE := "res://assets/reference/floorplan_sample.png"

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0


func _initialize() -> void:
	_geometry_suite()
	_tracer_suite()
	await _bake_csg_suite()
	await _bake_props_suite()
	_kit_suite()
	await _finalize_suite()
	_apply_suite()
	_partition_suite()
	await _floors_suite()
	await _uv_suite()
	_break_suite()
	await _mask_suite()
	await _occluder_suite()
	await _partition_walls_suite()
	await _regions_suite()
	await _roof_suite()
	_cache_suite()
	_plan3d_suite()

	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently"
				% [_suites_done, EXPECTED_SUITES])
	var f := FileAccess.open("user://verify_floorplan.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] FLOORPLAN PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


# ---------------------------------------------------------------- 1. geometry ------------------


func _geometry_suite() -> void:
	# The sample as three ADD shapes (metres × 100): room, circle on the bottom wall, corridor.
	var room := Geo.rect(Vector2(250, 200), Vector2(500, 400))
	var circ := Geo.circle(Vector2(250, 400), 200.0, 32)
	var corr := Geo.rect(Vector2(600, 200), Vector2(220, 160))
	var isl := Geo.compute([{"poly": room, "op": 0}, {"poly": circ, "op": 0}, {"poly": corr, "op": 0}])
	_check(isl.size() == 1, "union: expected 1 island, got %d" % isl.size())
	if isl.size() == 1:
		_check((isl[0].holes as Array).is_empty(), "union: unexpected holes")
		var got := Geo.total_area(isl) / 10000.0
		var half_circle := 0.5 * 32.0 / 2.0 * 4.0 * sin(TAU / 32.0)
		var want := 20.0 + half_circle + 2.2 * 1.6 - 0.1 * 1.6      # corridor overlaps the wall line
		_check(absf(got - want) / want < 0.01, "union area %.3f, want %.3f" % [got, want])
	# Subtract a pillar inside a room → exactly one hole, area 96.
	var big := Geo.rect(Vector2(500, 500), Vector2(1000, 1000))
	var pillar := Geo.rect(Vector2(500, 500), Vector2(200, 200))
	var cut := Geo.compute([{"poly": big, "op": 0}, {"poly": pillar, "op": 1}])
	_check(cut.size() == 1 and (cut[0].holes as Array).size() == 1,
			"subtract: expected 1 island with 1 hole")
	_check(absf(Geo.total_area(cut) / 10000.0 - 96.0) < 0.01, "subtract: area %.2f" % (Geo.total_area(cut) / 10000.0))
	_check(not Geo.point_in_floor(cut, Vector2(500, 500)), "subtract: pillar centre counted as floor")
	_check(Geo.point_in_floor(cut, Vector2(100, 100)), "subtract: corner not counted as floor")
	# A cut that splits a room in two.
	var bar := Geo.rect(Vector2(500, 500), Vector2(100, 2000))
	var split := Geo.compute([{"poly": big, "op": 0}, {"poly": bar, "op": 1}])
	_check(split.size() == 2, "split: expected 2 islands, got %d" % split.size())
	# Adding a shape inside a hole makes a new island, the hole becomes a ring.
	var inner := Geo.rect(Vector2(500, 500), Vector2(100, 100))
	var ring := Geo.compute([{"poly": big, "op": 0}, {"poly": pillar, "op": 1}, {"poly": inner, "op": 0}])
	_check(ring.size() == 2, "island-in-hole: expected 2 islands, got %d" % ring.size())
	_check(absf(Geo.total_area(ring) / 10000.0 - 97.0) < 0.01, "island-in-hole: area %.2f" % (Geo.total_area(ring) / 10000.0))
	# Every wall normal points away from the floor, on outers AND holes.
	var bad := 0
	for e: Dictionary in Geo.edges(cut):
		var probe: Vector2 = (e.a + e.b) * 0.5 + e.n * 5.0
		if Geo.point_in_floor(cut, probe):
			bad += 1
		var inside: Vector2 = (e.a + e.b) * 0.5 - e.n * 5.0
		if not Geo.point_in_floor(cut, inside):
			bad += 1
	_check(bad == 0, "normals: %d edges point into the floor" % bad)
	# Door snapping lands on the nearest edge.
	var edges := Geo.edges(isl)
	var s := Geo.snap(edges, Vector2(250, 30))
	_check(not s.is_empty() and (s.point as Vector2).distance_to(Vector2(250, 0)) < 1.0,
			"snap: expected (250,0), got %s" % str(s.get("point")))
	_done("geometry suite done")


# ---------------------------------------------------------------- 2. tracer --------------------


func _tracer_suite() -> void:
	var legend: Resource = Plugin.default_legend()
	var img := Fixture.build()
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = Tracer.trace(img, legend, Fixture.PPM, {})
	_say("  tracer: %d ms, %d shapes, %d doors, %d props" % [Time.get_ticks_msec() - t0,
			res.shapes.size(), res.doors.size(), res.props.size()])
	_check(res.shapes.size() >= 1, "tracer: no floor shape")
	var isl := Geo.compute(res.shapes)
	_check(isl.size() == 1, "tracer: expected 1 island after compute, got %d" % isl.size())
	var area := Geo.total_area(isl) / (Tracer.PLAN_PPM * Tracer.PLAN_PPM)
	_check(area > 24.0 and area < 36.0, "tracer: floor area %.2f m², expected ~30" % area)
	# The corridor's far end is the one door, near x = 485..495 px → 7.8..8.0 m.
	_check(res.doors.size() >= 1, "tracer: no door found")
	var east := false
	for d: Dictionary in res.doors:
		var pos: Vector2 = d.pos
		if pos.x > 7.4 * Tracer.PLAN_PPM and pos.y > 3.0 * Tracer.PLAN_PPM and pos.y < 5.0 * Tracer.PLAN_PPM:
			east = true
			_check(float(d.width_m) > 0.6 and float(d.width_m) < 1.6,
					"tracer: door width %.2f m, expected ~1.0" % float(d.width_m))
	_check(east, "tracer: no door at the corridor's east end (doors: %s)" % str(res.doors))
	# Props: a bed (rect) and a table (round), where the fixture put them.
	_check(res.props.size() == 2, "tracer: expected 2 props, got %d" % res.props.size())
	var keys := {}
	for p: Dictionary in res.props:
		keys[p.key] = p
	_check(keys.has("bed") and keys.has("table"), "tracer: keys %s" % str(keys.keys()))
	if keys.has("bed"):
		var bed: Dictionary = keys.bed
		var want := Vector2(Fixture.BED.get_center()) / Fixture.PPM * Tracer.PLAN_PPM
		_check((bed.pos as Vector2).distance_to(want) < 0.1 * Tracer.PLAN_PPM,
				"tracer: bed at %s, want %s" % [str(bed.pos), str(want)])
		_check(int(bed.shape) == Tracer.SHAPE_RECT, "tracer: bed not RECT")
		_check(absf(float(bed.size_m.x) - 105.0 / Fixture.PPM) < 0.05, "tracer: bed width %.2f" % float(bed.size_m.x))
	if keys.has("table"):
		var tb: Dictionary = keys.table
		var want := Fixture.TABLE_C / Fixture.PPM * Tracer.PLAN_PPM
		_check((tb.pos as Vector2).distance_to(want) < 0.1 * Tracer.PLAN_PPM,
				"tracer: table at %s, want %s" % [str(tb.pos), str(want)])
		_check(int(tb.shape) == Tracer.SHAPE_CIRCLE, "tracer: table not CIRCLE")
	# Room interior points must be floor; a point outside the building must not.
	var room_c := Vector2(200, 250) / Fixture.PPM * Tracer.PLAN_PPM
	var arena_c := Vector2(195, 470) / Fixture.PPM * Tracer.PLAN_PPM
	var corr_c := Vector2(430, 250) / Fixture.PPM * Tracer.PLAN_PPM
	var outside := Vector2(600, 450) / Fixture.PPM * Tracer.PLAN_PPM
	_check(Geo.point_in_floor(isl, room_c), "tracer: room centre not floor")
	_check(Geo.point_in_floor(isl, arena_c), "tracer: arena centre not floor")
	_check(Geo.point_in_floor(isl, corr_c), "tracer: corridor centre not floor")
	_check(not Geo.point_in_floor(isl, outside), "tracer: outside counted as floor")
	# The traced outline's staircase edges are far shorter than the wall thickness — the case
	# that folds mitres into bow-ties and makes bevels overlap. The partition must hold anyway.
	_check_partition(isl, "tracer")
	# The user's real picture, when present.
	if ResourceLoader.exists(SAMPLE) or FileAccess.file_exists(SAMPLE):
		var real := Image.load_from_file(ProjectSettings.globalize_path(SAMPLE))
		if real != null and not real.is_empty():
			var r2: Dictionary = Tracer.trace(real, legend, Fixture.PPM, {})
			var isl2 := Geo.compute(r2.shapes)
			_say("  real sample: %d islands, %.1f m², %d doors, %d props" % [isl2.size(),
					Geo.total_area(isl2) / 10000.0, r2.doors.size(), r2.props.size()])
			_check(isl2.size() >= 1, "real sample: no island")
			_check(r2.props.size() == 2, "real sample: expected 2 props, got %d" % r2.props.size())
	_done("tracer suite done")


# ---------------------------------------------------------------- 3. bake, CSG -----------------


func _bake_csg_suite() -> void:
	var kit := Kit.new()
	var room := Geo.rect(Vector2(250, 200), Vector2(500, 400))
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": room, "op": 0}]),
		"doors": [{"pos": Vector2(250, 395), "width_m": 2.0}],
		"props": [],
	}
	var bake: Node3D = Baker.build(data, kit, null, "Test")
	root.add_child(bake)
	var rm := bake.get_node_or_null("Level_0/Room_0") as CSGCombiner3D
	_check(rm != null, "bake: no Room_0")
	if rm == null:
		_done("bake csg suite done (aborted)")
		return
	_check(rm.use_collision and rm.collision_layer == 1 and rm.collision_mask == 0,
			"bake: room collision layer/mask")
	var walls := 0
	var doors := 0
	for c in rm.get_children():
		if c.name.begins_with("Wall_"):
			walls += 1
			var slab := c as CSGPolygon3D
			_check(slab != null, "bake: %s is not a CSGPolygon3D slab" % c.name)
			var centre := Vector2(slab.position.x, slab.position.z) * 100.0
			_check(not Geo.point_in_floor(data.islands, centre), "bake: %s stands on the floor" % c.name)
			_check(absf(slab.position.y) < 1e-4, "bake: %s y %.3f" % [c.name, slab.position.y])
			_check(absf(slab.depth - 4.5) < 1e-4, "bake: %s height %.2f" % [c.name, slab.depth])
			_check(slab.has_meta("floorplan_wall"), "bake: %s carries no floorplan_wall meta" % c.name)
		elif c.name.begins_with("Door_"):
			doors += 1
			_check((c as CSGBox3D).operation == CSGShape3D.OPERATION_SUBTRACTION, "bake: door not subtracted")
	_check(walls == 4, "bake: %d walls, want 4" % walls)
	_check(doors == 1, "bake: %d doors, want 1" % doors)
	_check(rm.get_node_or_null("Floor") != null, "bake: no Floor")
	# CSG updates one frame late (glade_present.gd:136) — measure after waiting.
	await process_frame
	await process_frame
	var meshes: Array = rm.get_meshes()
	_check(meshes.size() == 2 and meshes[1] != null, "bake: room produced no CSG mesh")
	if meshes.size() == 2 and meshes[1] != null:
		var aabb: AABB = (meshes[1] as Mesh).get_aabb()
		_say("  room aabb %s" % str(aabb))
		_check(absf(aabb.position.y + 0.2) < 0.02, "bake: floor bottom y %.3f, want -0.2" % aabb.position.y)
		_check(absf(aabb.end.y - 4.5) < 0.02, "bake: wall top y %.3f, want 4.5" % aabb.end.y)
		_check(absf(aabb.position.x + 0.5) < 0.02 and absf(aabb.end.x - 5.5) < 0.02,
				"bake: x extent %.2f..%.2f, want -0.5..5.5" % [aabb.position.x, aabb.end.x])
		_check(absf(aabb.position.z + 0.5) < 0.02 and absf(aabb.end.z - 4.5) < 0.02,
				"bake: z extent %.2f..%.2f, want -0.5..4.5" % [aabb.position.z, aabb.end.z])
	# A lone floor slab: top at 0, bottom at -thickness.
	var fl: CSGPolygon3D = Baker.floor_node(PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 3), Vector2(0, 3)]), 0.2, "F")
	root.add_child(fl)
	await process_frame
	await process_frame
	var fm: Array = fl.get_meshes()
	if fm.size() == 2 and fm[1] != null:
		# get_meshes() hands back the mesh in the shape's own space — stand it up ourselves.
		var fa: AABB = fl.global_transform * (fm[1] as Mesh).get_aabb()
		_check(absf(fa.end.y) < 0.01 and absf(fa.position.y + 0.2) < 0.01,
				"floor: y %.2f..%.2f, want -0.2..0" % [fa.position.y, fa.end.y])
		_check(absf(fa.end.z - 3.0) < 0.01 and absf(fa.end.x - 2.0) < 0.01,
				"floor: plan y must map to +Z (got x..%.2f z..%.2f)" % [fa.end.x, fa.end.z])
	else:
		_fails.append("floor: no mesh")
	fl.free()
	# Save, reload, same shape.
	var path := "user://floorplan_verify_bake.tscn"
	var err: Error = Baker.save_to(bake, path)
	_check(err == OK, "save: %s" % error_string(err))
	if err == OK:
		var ps: PackedScene = load(path)
		var again := ps.instantiate()
		_check(_walk(again).size() == _walk(bake).size(), "reload: %d nodes vs %d" % [_walk(again).size(), _walk(bake).size()])
		again.free()
	bake.free()
	_done("bake csg suite done")


# ---------------------------------------------------------------- 4. bake, props ---------------


func _bake_props_suite() -> void:
	var legend: Resource = Plugin.default_legend()
	# A scene-backed entry: an in-memory PackedScene with one child.
	var chair := LegendEntry.new()
	chair.key = "chair"
	var proto := Node3D.new()
	var kid := MeshInstance3D.new()
	kid.name = "Seat"
	proto.add_child(kid)
	kid.owner = proto
	var ps := PackedScene.new()
	ps.pack(proto)
	proto.free()
	# A legend scene is a FILE in real use; only a file-backed instance serializes as an
	# instance (scene_file_path is what pack() writes), so give the fixture a path.
	ResourceSaver.save(ps, "user://floorplan_verify_chair.tscn")
	chair.scene = load("user://floorplan_verify_chair.tscn")
	(legend.get("entries") as Array).append(chair)
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(500, 500), Vector2(1000, 1000)), "op": 0}]),
		"doors": [],
		"props": [
			{"key": "bed", "pos": Vector2(200, 300), "rot": PI / 2.0, "size_m": Vector2(2.0, 1.4), "shape": 1},
			{"key": "table", "pos": Vector2(600, 600), "rot": 0.0, "size_m": Vector2(1.5, 1.5), "shape": 2},
			{"key": "SpawnA", "pos": Vector2(100, 100), "rot": 0.0, "size_m": Vector2(1, 1), "shape": 0},
			{"key": "chair", "pos": Vector2(700, 200), "rot": 0.0, "size_m": Vector2(1, 1), "shape": 0},
			{"key": "unknown", "pos": Vector2(800, 800), "rot": 0.0, "size_m": Vector2(0.5, 0.7), "shape": 1},
		],
	}
	var bake: Node3D = Baker.build(data, Kit.new(), legend, "Props")
	root.add_child(bake)
	var props := bake.get_node("Level_0/Props")
	var bed := props.get_node_or_null("bed_1") as StaticBody3D
	_check(bed != null, "props: no bed_1 StaticBody3D")
	if bed != null:
		_check(bed.position.is_equal_approx(Vector3(2.0, 0.0, 3.0)), "props: bed at %s" % str(bed.position))
		# 2D +90° (clockwise on screen) → local +X now faces +Z.
		_check(bed.basis.x.is_equal_approx(Vector3(0, 0, 1)), "props: bed facing %s, want +Z" % str(bed.basis.x))
		var mesh := bed.get_node("Mesh") as MeshInstance3D
		_check(mesh.mesh is BoxMesh and (mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(2.0, 0.6, 1.4)),
				"props: bed greybox size")
		_check(absf(mesh.position.y - 0.3) < 1e-5, "props: bed mesh not bottom-anchored")
		_check(bed.collision_layer == 1 and bed.collision_mask == 0, "props: bed collision layers")
	var table := props.get_node_or_null("table_1") as StaticBody3D
	_check(table != null and (table.get_node("Mesh") as MeshInstance3D).mesh is CylinderMesh, "props: table not a cylinder")
	var spawn := props.get_node_or_null("SpawnA1")
	_check(spawn is Marker3D, "props: SpawnA1 is not a Marker3D")
	var ch := props.get_node_or_null("chair_1")
	_check(ch != null and ch.get_child_count() == 1, "props: chair instance")
	var unk := props.get_node_or_null("unknown_1") as StaticBody3D
	_check(unk != null and ((unk.get_node("Mesh") as MeshInstance3D).mesh as BoxMesh).size.is_equal_approx(Vector3(0.5, 1.0, 0.7)),
			"props: unknown key greybox")
	# Save + reload: the instanced chair must come back with exactly one child, not two.
	var path := "user://floorplan_verify_props.tscn"
	var err: Error = Baker.save_to(bake, path)
	_check(err == OK, "props save: %s" % error_string(err))
	if err == OK:
		var again := (load(path) as PackedScene).instantiate()
		var ch2 := again.get_node_or_null("Level_0/Props/chair_1")
		_check(ch2 != null and ch2.get_child_count() == 1,
				"props reload: chair has %d children" % (ch2.get_child_count() if ch2 else -1))
		_check(_walk(again).size() == _walk(bake).size(), "props reload: node count")
		again.free()
	bake.free()
	_done("bake props suite done")


# ---------------------------------------------------------------- 5. modular kit ---------------


func _kit_suite() -> void:
	var proto := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Panel"
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 3.0, 0.5)
	mi.mesh = bm
	mi.position.y = 1.5
	proto.add_child(mi)
	mi.owner = proto
	var ps := PackedScene.new()
	ps.pack(proto)
	proto.free()
	var kit := Kit.new()
	kit.wall_scene = ps
	# 10 × 4 m room: 3 + 1 + 3 + 1 modules = 8 instances, each scaled to its bay.
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(500, 200), Vector2(1000, 400)), "op": 0}]),
		"doors": [{"pos": Vector2(500, 5), "width_m": 2.0}],
		"props": [],
	}
	var bake: Node3D = Baker.build(data, kit, null, "KitTest")
	root.add_child(bake)
	var rm := bake.get_node("Level_0/Room_0")
	var holders: Array = []
	var csg := 0
	var doors := 0
	for c in rm.get_children():
		if c.name.begins_with("Wall_"):
			holders.append(c)
			if c is CSGShape3D:
				csg += 1
		elif c.name.begins_with("Door_"):
			doors += 1
	_check(csg == 0, "kit: %d CSG walls on a kit bake" % csg)
	_check(doors == 0, "kit: %d door cuts on a kit bake (the door module carries the opening)" % doors)
	_check(holders.size() == 4, "kit: %d wall holders, want 4" % holders.size())
	# The door edge (10 m) splits into two 4 m stretches (one module each) plus the door bay:
	# 1 + 1 + 1 = 3, the other 10 m edge is 3, the 4 m edges 1 each → 8 modules.
	var modules: Array = []
	for w: Node3D in holders:
		_check(w.has_meta("floorplan_wall") and w.has_meta("floorplan_kit"), "kit: %s meta" % w.name)
		var centre := Vector2(w.position.x, w.position.z) * 100.0
		_check(not Geo.point_in_floor(data.islands, centre), "kit: %s stands on the floor" % w.name)
		for m in w.get_children():
			modules.append(m)
	_say("  kit: %d wall modules" % modules.size())
	_check(modules.size() == 8, "kit: %d modules, want 8" % modules.size())
	var seen_scale := false
	var seen_door_bay := false
	for m: Node3D in modules:
		_check(m.get_child_count() == 1 and m.get_child(0).name == "Panel", "kit: %s is not the module" % m.name)
		# The instance root is the bake's; its internals stay the instance's own.
		_check(m.owner == bake and m.get_child(0).owner == m, "kit: %s ownership" % m.name)
		var sx := m.basis.get_scale().x
		if absf(sx - 0.5) < 0.01:
			seen_door_bay = true
		if absf(sx - 1.0) > 0.01:
			seen_scale = true
		var centre := Vector2(m.global_position.x, m.global_position.z) * 100.0
		_check(not Geo.point_in_floor(data.islands, centre), "kit: %s stands on the floor" % m.name)
	_check(seen_scale, "kit: no module was stretched to fit — bays not honoured")
	_check(seen_door_bay, "kit: no 2 m door bay (scale 0.5) — the door did not anchor the grid")
	bake.free()
	_done("kit suite done")


# ---------------------------------------------------------------- 6. finalize ------------------


func _finalize_suite() -> void:
	var kit := Kit.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	kit.wall_material = red
	var room := Geo.rect(Vector2(250, 200), Vector2(500, 400))
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": room, "op": 0}]),
		"doors": [{"pos": Vector2(250, 395), "width_m": 2.0}],
		"props": [],
	}
	var bake: Node3D = Baker.build(data, kit, null, "Final")
	root.add_child(bake)
	# A user boolean added in 3D: a window through the top wall (y = 0 edge → world z ≈ 0).
	var window := CSGBox3D.new()
	window.name = "Window"
	window.operation = CSGShape3D.OPERATION_SUBTRACTION
	window.size = Vector3(1.0, 1.0, 2.0)
	window.position = Vector3(1.0, 2.5, -0.25)
	bake.get_node("Level_0/Room_0").add_child(window)
	window.owner = bake
	var ops: Array = await Refine.finalize(bake, self)
	_check(ops.size() == 1, "finalize: %d ops, want 1 room swap" % ops.size())
	Refine.apply_ops(ops, bake)
	var rm := bake.get_node_or_null("Level_0/Room_0")
	_check(rm != null and not rm is CSGShape3D and rm.get_class() == "Node3D", "finalize: Room_0 is not a plain Node3D")
	if rm == null:
		_done("finalize suite done (aborted)")
		return
	_check(bake.get_node_or_null("_floorplan_finalize_temps") == null, "finalize: temps left behind")
	var plain_verts := -1
	var door_verts := -1
	var cut_verts := -1
	var walls := 0
	for c in rm.get_children():
		_check(not c is CSGShape3D, "finalize: %s is still CSG" % c.name)
		if not c.name.begins_with("Wall_"):
			continue
		walls += 1
		var body := c as StaticBody3D
		_check(body != null and body.owner == bake, "finalize: %s not an owned StaticBody3D" % c.name)
		var mi := c.get_node_or_null("Mesh") as MeshInstance3D
		var col := c.get_node_or_null("Collision") as CollisionShape3D
		_check(mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0, "finalize: %s has no mesh" % c.name)
		_check(col != null and col.shape is ConcavePolygonShape3D, "finalize: %s has no trimesh collision" % c.name)
		_check(c.has_meta("floorplan_wall"), "finalize: %s lost its meta" % c.name)
		if mi == null or mi.mesh == null:
			continue
		var verts := 0
		var has_red := false
		for s in mi.mesh.get_surface_count():
			verts += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if mi.mesh.surface_get_material(s) == red:
				has_red = true
		_check(has_red, "finalize: %s lost the kit material" % c.name)
		var aabb: AABB = (body.transform * mi.mesh.get_aabb())
		_check(absf(aabb.position.y) < 0.02 and absf(aabb.end.y - 4.5) < 0.02,
				"finalize: %s spans y %.2f..%.2f" % [c.name, aabb.position.y, aabb.end.y])
		var info: Dictionary = c.get_meta("floorplan_wall")
		if not (info.doors as Array).is_empty():
			door_verts = verts
		elif absf(body.position.z + 0.25) < 0.01:
			cut_verts = verts                     # the top wall, with the window
		else:
			plain_verts = verts
	_check(walls == 4, "finalize: %d walls, want 4" % walls)
	_say("  finalize: verts plain %d, door %d, window %d" % [plain_verts, door_verts, cut_verts])
	_check(door_verts > plain_verts, "finalize: the door wall has no more geometry than a plain wall — the cut was lost")
	_check(cut_verts > plain_verts, "finalize: the 3D-added window was lost")
	var fl := rm.get_node_or_null("Floor")
	_check(fl is StaticBody3D and fl.has_meta("floorplan_floor"), "finalize: Floor not a body")
	# It saves and reloads as plain nodes.
	var path := "user://floorplan_verify_final.tscn"
	_check(Baker.save_to(bake, path) == OK, "finalize: save failed")
	var again := (load(path) as PackedScene).instantiate()
	_check(_walk(again).size() == _walk(bake).size(), "finalize reload: node count")
	again.free()
	bake.free()
	_done("finalize suite done")


# ---------------------------------------------------------------- 7. apply assets --------------


func _apply_suite() -> void:
	var legend: Resource = Plugin.default_legend()
	var kit := Kit.new()
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(500, 200), Vector2(1000, 400)), "op": 0}]),
		"doors": [{"pos": Vector2(500, 5), "width_m": 2.0}],
		"props": [
			{"key": "bed", "pos": Vector2(200, 300), "rot": PI / 2.0, "size_m": Vector2(2.0, 1.4), "shape": 1},
			{"key": "table", "pos": Vector2(600, 200), "rot": 0.0, "size_m": Vector2(1.5, 1.5), "shape": 2},
		],
	}
	var bake: Node3D = Baker.build(data, kit, legend, "Apply")
	root.add_child(bake)
	var bed_before := (bake.get_node("Level_0/Props/bed_1") as Node3D).transform
	# Nothing changed yet → nothing to do.
	_check((Refine.apply_assets(bake, legend, kit) as Array).is_empty(), "apply: ops on an unchanged plan")
	# Now the bed row gets a scene, the kit a wall module and a floor material.
	var bed_row: Resource = legend.call("find", "bed")
	bed_row.scene = load("user://floorplan_verify_chair.tscn")
	var proto := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Panel"
	mi.mesh = BoxMesh.new()
	proto.add_child(mi)
	mi.owner = proto
	var ps := PackedScene.new()
	ps.pack(proto)
	proto.free()
	kit.wall_scene = ps
	var stone := StandardMaterial3D.new()
	kit.floor_material = stone
	var ops: Array = Refine.apply_assets(bake, legend, kit)
	_say("  apply: %s" % Refine.summary(ops))
	Refine.apply_ops(ops, bake)
	var bed := bake.get_node_or_null("Level_0/Props/bed_1")
	_check(bed != null and bed.get_child_count() == 1 and bed.get_child(0).name == "Seat", "apply: bed not swapped for its scene")
	_check(bed != null and (bed as Node3D).transform.is_equal_approx(bed_before), "apply: bed transform changed")
	_check(bed != null and bed.owner == bake and not bed.has_meta("floorplan_greybox"), "apply: bed ownership/meta")
	var table := bake.get_node_or_null("Level_0/Props/table_1")
	_check(table is StaticBody3D and table.has_meta("floorplan_greybox"), "apply: table (no scene) should be untouched")
	var rm := bake.get_node("Level_0/Room_0")
	var modules := 0
	var doors := 0
	for c in rm.get_children():
		if c.name.begins_with("Wall_"):
			_check(not c is CSGShape3D and c.has_meta("floorplan_kit"), "apply: %s not tiled" % c.name)
			modules += c.get_child_count()
		elif c.name.begins_with("Door_"):
			doors += 1
	_check(modules == 8, "apply: %d modules, want 8" % modules)
	_check(doors == 0, "apply: door cut survived the wall swap")
	var fl := rm.get_node("Floor") as CSGPolygon3D
	_check(fl.material == stone, "apply: floor material not set")
	var again: Array = Refine.apply_assets(bake, legend, kit)
	_check(again.is_empty(), "apply: second apply is not a no-op (%d ops)" % again.size())
	bake.free()
	_done("apply suite done")


# ---------------------------------------------------------------- 8. wall partition ------------


## No two wall pieces overlap, and together they cover the band exactly — on an L-shaped room
## (one concave corner, where the bevelled quads used to overlap and z-fight after Finalize)
## and on a room with a pillar hole (concave corners on the hole ring).
func _partition_suite() -> void:
	var big := Geo.rect(Vector2(500, 500), Vector2(1000, 1000))
	var bite := Geo.rect(Vector2(750, 750), Vector2(500, 500))
	var l_room := Geo.compute([{"poly": big, "op": 0}, {"poly": bite, "op": 1}])
	_check(l_room.size() == 1, "partition: L-room islands %d" % l_room.size())
	_check_partition(l_room, "L-room")
	# Coverage: the band of an L-room with mitred 90° corners is exactly the offset ring.
	var t := 50.0
	var pieces := Geo.wall_pieces(l_room, t)
	var sum := 0.0
	for pc: Dictionary in pieces:
		sum += absf(Geo.area(pc.poly))
	var outer: PackedVector2Array = l_room[0].outer
	var grown := Geometry2D.offset_polygon(outer, t, Geometry2D.JOIN_MITER)
	_check(grown.size() == 1, "partition: offset_polygon returned %d polygons" % grown.size())
	if grown.size() == 1:
		var band := absf(Geo.area(grown[0])) - absf(Geo.area(outer))
		_check(absf(sum - band) / band < 0.005, "partition: pieces cover %.0f px², band is %.0f" % [sum, band])
	var pillar := Geo.compute([{"poly": big, "op": 0},
			{"poly": Geo.rect(Vector2(500, 500), Vector2(200, 200)), "op": 1}])
	_check_partition(pillar, "pillar-room")
	# A baked L-room: every wall slab's footprint is disjoint from every other's (this is what
	# stops the finalized meshes from sharing a coplanar top).
	var bake: Node3D = Baker.build({"ppm": 100.0, "islands": l_room, "doors": [], "props": []},
			Kit.new(), null, "L")
	root.add_child(bake)
	var walls := 0
	for c in bake.get_node("Level_0/Room_0").get_children():
		if c.name.begins_with("Wall_"):
			walls += 1
	_check(walls == 6, "partition: L-room baked %d walls, want 6" % walls)
	bake.free()
	_done("partition suite done")


# ---------------------------------------------------------------- 9. floors + stairs -----------


func _floors_suite() -> void:
	# The 2D side: a root with two containers reports two floors, hides the other one, and keeps
	# counting its nodes while hidden.
	var plan := PlanRootScript.new()
	plan.kit = Kit.new()
	root.add_child(plan)
	var f0 := PlanLevelScript.new()
	f0.name = "Floor_0"
	f0.index = 0
	plan.add_child(f0)
	var s0 := PlanShapeScript.new()
	s0.kind = 1
	s0.size = Vector2(1400, 800)
	s0.position = Vector2(700, 400)
	f0.add_child(s0)
	# Automatic length: 27 × 0.28 = 7.56 m for the 4.7 m pitch, a 32° stair a capsule can climb.
	# (The fixture once used 3.0 m — 57°, past the 45° floor limit — so the suite was proving
	# a stair nobody could walk.)
	var st := PlanStairScript.new()
	st.position = Vector2(200, 400)
	st.width_m = 1.2
	f0.add_child(st)
	var f1 := PlanLevelScript.new()
	f1.name = "Floor_1"
	f1.index = 1
	plan.add_child(f1)
	var s1 := PlanShapeScript.new()
	s1.kind = 1
	s1.size = Vector2(1200, 800)
	s1.position = Vector2(600, 400)
	f1.add_child(s1)
	_check(plan.levels() == [0, 1], "floors: levels %s" % str(plan.levels()))
	plan.current_level = 1
	_check(not f0.visible and f1.visible, "floors: visibility did not follow current_level")
	var data: Dictionary = plan.plan_data()
	_check((data.levels as Array).size() == 2, "floors: plan_data reports %d levels" % (data.levels as Array).size())
	_check(absf(float(data.pitch) - 4.7) < 1e-4, "floors: pitch %.2f, want 4.7" % float(data.pitch))
	var l0: Dictionary = data.levels[0]
	var l1: Dictionary = data.levels[1]
	_check((l0.stairs as Array).size() == 1 and (l1.stairs as Array).is_empty(), "floors: stair not on floor 0")
	_check((l0.islands as Array).size() == 1 and (l1.islands as Array).size() == 1,
			"floors: hidden floor 0 lost its island (%d / %d)" % [(l0.islands as Array).size(), (l1.islands as Array).size()])
	_check(plan.level_parent(1) == f1 and plan.level_parent(0) == f0, "floors: level_parent")
	plan.free()

	# The 3D side: two levels, the stair cuts a passage into floor 1, ramp collides, steps show.
	var bake: Node3D = Baker.build(data, Kit.new(), null, "Floors")
	root.add_child(bake)
	var lv1 := bake.get_node_or_null("Level_1") as Node3D
	_check(lv1 != null and absf(lv1.position.y - 4.7) < 1e-4, "floors: Level_1 y")
	var rm1 := bake.get_node_or_null("Level_1/Room_0")
	_check(rm1 != null and rm1.get_node_or_null("Passage_0") != null, "floors: no passage cut in floor 1")
	# The stairwell is an opening, not a pillar: floor 1 keeps its four walls, none around the hole.
	var walls1 := 0
	if rm1 != null:
		for c in rm1.get_children():
			if c.name.begins_with("Wall_"):
				walls1 += 1
	_check(walls1 == 4, "floors: floor 1 has %d walls — the passage grew walls" % walls1)
	var stair := bake.get_node_or_null("Level_0/Stairs/Stair_1") as Node3D
	_check(stair != null and stair.has_meta("floorplan_stair") and stair.has_meta("floorplan_greybox"), "floors: no Stair_1")
	if stair != null:
		_check(stair.position.is_equal_approx(Vector3(2.0, 0.0, 4.0)), "floors: stair at %s" % str(stair.position))
		var ramp := stair.get_node_or_null("Ramp") as CSGPolygon3D
		_check(ramp != null and ramp.use_collision and not ramp.visible, "floors: ramp collider")
		if ramp != null:
			var top := 0.0
			var far := 0.0
			for v in ramp.polygon:
				top = maxf(top, v.y)
				far = maxf(far, v.x)
			# The landing runs one tread past the 7.56 m run, under the intact slab.
			_check(absf(top - 4.7) < 1e-4 and absf(far - 7.84) < 1e-4, "floors: ramp profile %.2f × %.2f" % [far, top])
			# Flat landing at the storey pitch: two vertices at y = pitch.
			var at_top := 0
			for v in ramp.polygon:
				if absf(v.y - 4.7) < 1e-4:
					at_top += 1
			_check(at_top == 2, "floors: ramp has no flat landing at the top")
		var steps := stair.get_node_or_null("Steps") as CSGCombiner3D
		_check(steps != null and not steps.use_collision and steps.get_child_count() == 27,
				"floors: steps (%d)" % (steps.get_child_count() if steps else -1))
	# THE CONNECTION, physically: rays down onto the stair hit the invisible ramp at the tread
	# heights, the top landing sits flush with floor 1, and the passage in floor 1 is open.
	await process_frame
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	# Halfway up the 7.56 m run (3.78 m), cast from under the slab's height.
	var mid: Variant = _ray_down(space, Vector3(5.78, 4.4, 4.0))
	_check(mid != null and absf(float(mid) - (4.7 * 0.5 + 4.7 / 27.0 * 0.5)) < 0.05,
			"floors: mid-stair ray hit y %s, want ~2.44 (ramp through the tread centres)" % str(mid))
	var landing: Variant = _ray_down(space, Vector3(9.49, 8.0, 4.0))      # the last quarter tread
	_check(landing != null and absf(float(landing) - 4.7) < 0.02,
			"floors: landing ray hit y %s, want 4.7 (flush with floor 1)" % str(landing))
	var seam: Variant = _ray_down(space, Vector3(9.70, 8.0, 4.0))         # over the landing extension, slab intact
	_check(seam != null and absf(float(seam) - 4.7) < 0.02,
			"floors: seam ray hit y %s, want 4.7" % str(seam))
	var upper: Variant = _ray_down(space, Vector3(10.5, 8.0, 4.0))        # floor 1, past the stair
	_check(upper != null and absf(float(upper) - 4.7) < 0.02,
			"floors: floor 1 ray hit y %s, want 4.7" % str(upper))
	# The passage starts where 2.3 m of head room above the RAMP SURFACE (half a rise above the
	# corner line) no longer fits under the slab: 3.40 m up, 45 % of the run. Before it the floor
	# above is intact; inside it the ray reaches the ramp.
	var before: Variant = _ray_down(space, Vector3(4.0, 6.0, 4.0))        # 2.0 m up the run
	_check(before != null and absf(float(before) - 4.7) < 0.02,
			"floors: floor above cut too early (ray at 2.0 m hit y %s)" % str(before))
	var hole: Variant = _ray_down(space, Vector3(6.5, 6.0, 4.0))          # 4.5 m up: in the passage
	_check(hole != null and float(hole) < 4.3,
			"floors: ray into the passage hit y %s — the floor above is not cut" % str(hole))
	# THE CLIMB, as the player's collider does it: a capsule swept up the run parallel to the
	# ramp surface must never touch anything — not the slab's underside, not the cut edge. The
	# sweep is Godot's cast_motion; [1, 1] means the whole motion is free. Head room 2.1 m would
	# fail this (the crown reaches 4.51 m under a slab at 4.5); 2.3 m passes.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3125
	cap.height = 1.95
	var slope := atan2(4.7, 7.56)
	var lift := cap.radius / cos(slope) + cap.height * 0.5 - cap.radius + 0.02
	var s_from := Vector3(2.4, 4.7 / 27.0 * 0.5 + 4.7 / 7.56 * 0.4 + lift, 4.0)
	var s_to := Vector3(2.0 + 7.56 - 0.14, 4.7 + lift, 4.0)
	var sweep: Array = _sweep(space, cap, s_from, s_to)
	_check(sweep[0] >= 0.999 and sweep[1] >= 0.999,
			"floors: capsule sweep up the stair stopped at %.2f (CSG) — head room" % float(sweep[0]))
	var tall := CapsuleShape3D.new()
	tall.radius = 0.3125
	tall.height = 2.5
	var tall_lift := tall.radius / cos(slope) + tall.height * 0.5 - tall.radius + 0.02
	var tall_sweep: Array = _sweep(space, tall, Vector3(2.4, s_from.y - lift + tall_lift, 4.0),
			Vector3(s_to.x, 4.7 + tall_lift, 4.0))
	_check(tall_sweep[0] < 0.999, "floors: a 2.5 m capsule climbed through the slab — the probe is blind")
	# A stair left at its automatic length gets 27 × 0.28 m = 7.56 m for this pitch.
	var auto_plan := PlanRootScript.new()
	auto_plan.kit = Kit.new()
	root.add_child(auto_plan)
	var auto_st := PlanStairScript.new()
	auto_plan.add_child(auto_st)
	var fp: PackedVector2Array = auto_st.plan_footprint(auto_plan)
	_check(absf(fp[1].x - fp[0].x - 756.0) < 0.5, "floors: auto stair length %.0f px, want 756" % (fp[1].x - fp[0].x))
	var pf: PackedVector2Array = auto_st.passage_footprint(auto_plan)
	_check(absf(pf[0].x - 756.0 * (4.7 - 0.2 - 2.3 - 4.7 / 27.0 * 0.5) / 4.7) < 1.0,
			"floors: passage starts at %.0f px, want 340" % pf[0].x)
	auto_plan.free()
	# Whatever length is typed, the crown of a 2.3 m climber on the tread-centre line clears the
	# slab's underside at the passage edge.
	for L in [3.0, 5.04, 5.5, 7.56]:
		var x0: float = PlanStairScript.passage_start(4.7, 0.2, L, 0)
		_check(4.7 / 27.0 * 0.5 + 4.7 / L * x0 + 2.3 <= 4.5 + 1e-6,
				"floors: passage for a %.2f m run starts too late (%.2f)" % [L, x0])
	# Finalize keeps the split: steps become meshes without collision, the ramp a collider only.
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	var st3 := bake.get_node_or_null("Level_0/Stairs/Stair_1")
	if st3 != null:
		var ramp_b := st3.get_node_or_null("Ramp")
		_check(ramp_b is StaticBody3D and ramp_b.get_node_or_null("Collision") != null
				and ramp_b.get_node_or_null("Mesh") == null, "floors: finalized ramp")
		var steps_b := st3.get_node_or_null("Steps")
		_check(steps_b != null and steps_b.get_child_count() == 27, "floors: finalized steps")
		if steps_b != null and steps_b.get_child_count() > 0:
			var s := steps_b.get_child(0)
			_check(s.get_node_or_null("Mesh") != null and s.get_node_or_null("Collision") == null,
					"floors: step 0 should be visual only")
	_check(bake.get_node_or_null("Level_1/Room_0/Floor") is StaticBody3D, "floors: floor 1 finalized")
	# The same climb against the trimesh colliders Finalize made (where a seam would live).
	await physics_frame
	await physics_frame
	var sweep2: Array = _sweep(root.get_world_3d().direct_space_state, cap, s_from, s_to)
	_check(sweep2[0] >= 0.999 and sweep2[1] >= 0.999,
			"floors: capsule sweep up the stair stopped at %.2f (finalized) — head room" % float(sweep2[0]))
	var csg := 0
	for n in _walk(bake):
		if n is CSGShape3D:
			csg += 1
	_check(csg == 0, "floors: %d CSG nodes left after finalize" % csg)
	var path := "user://floorplan_verify_floors.tscn"
	_check(Baker.save_to(bake, path) == OK, "floors: save")
	var again := (load(path) as PackedScene).instantiate()
	_check(_walk(again).size() == _walk(bake).size(), "floors reload: node count")
	again.free()
	bake.free()
	_done("floors suite done")


# ---------------------------------------------------------------- 10. metric UVs ---------------


func _uv_suite() -> void:
	# A 2 × 3 × 4 box: each face pair's UV extent is its metric size, and tangents exist.
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 4)
	var m: ArrayMesh = PlanUV.metric_uvs(bm)
	_check(m.get_surface_count() == 1, "uv: box surfaces %d" % m.get_surface_count())
	var arr := m.surface_get_arrays(0)
	_check(arr[Mesh.ARRAY_TANGENT] != null and (arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() > 0,
			"uv: no tangents generated")
	var ez := PlanUV.uv_extent(m, PlanUV.Axis.Z).size
	var ey := PlanUV.uv_extent(m, PlanUV.Axis.Y).size
	var ex := PlanUV.uv_extent(m, PlanUV.Axis.X).size
	_check(ez.is_equal_approx(Vector2(2, 3)), "uv: ±Z faces extent %s, want (2,3)" % str(ez))
	_check(ey.is_equal_approx(Vector2(2, 4)), "uv: ±Y faces extent %s, want (2,4)" % str(ey))
	_check(ex.is_equal_approx(Vector2(4, 3)), "uv: ±X faces extent %s, want (4,3)" % str(ex))
	# A scaled node measures metres through its basis.
	var scaled: ArrayMesh = PlanUV.metric_uvs(bm, Vector2.ZERO, Basis.from_scale(Vector3(10, 1, 10)))
	_check(PlanUV.uv_extent(scaled, PlanUV.Axis.Y, Basis.from_scale(Vector3(10, 1, 10))).size.is_equal_approx(Vector2(20, 40)),
			"uv: scaled node not measured in metres")

	# A finalized 6 × 4 m room: walls 6 m long tile 6 m, texture continuous around the ring.
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(300, 200), Vector2(600, 400)), "op": 0}]),
		"doors": [{"pos": Vector2(300, 395), "width_m": 2.0}],
		"props": [],
	}
	var bake: Node3D = Baker.build(data, Kit.new(), null, "UV")
	root.add_child(bake)
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	var rm := bake.get_node("Level_0/Room_0")
	var walls: Array = []
	for c in rm.get_children():
		if c.name.begins_with("Wall_"):
			walls.append(c)
	walls.sort_custom(func(a: Node, b: Node) -> bool:
			return float(a.get_meta("floorplan_wall").s0) < float(b.get_meta("floorplan_wall").s0))
	_check(walls.size() == 4, "uv: %d walls" % walls.size())
	var prev_end := -1.0
	var first_start := 0.0
	for k in walls.size():
		var w: Node3D = walls[k]
		var info: Dictionary = w.get_meta("floorplan_wall")
		var mesh: Mesh = (w.get_node("Mesh") as MeshInstance3D).mesh
		# The slab stands via a 90° X rotation: in its own frame the run is X, the thickness
		# is Y and the height is −Z, so the big faces are the ±Y ones. Which of them is the
		# ROOM face depends on the ring's winding; it is the shorter one, the outer face being
		# a mitre longer at each end (that one only meets its neighbour outside the corner).
		var fa := PlanUV.uv_extent(mesh, PlanUV.Axis.Y, Basis.IDENTITY, -1)
		var fb := PlanUV.uv_extent(mesh, PlanUV.Axis.Y, Basis.IDENTITY, 1)
		var face := fa if fa.size.x < fb.size.x else fb
		_check(absf(face.size.x - float(info.len)) < 0.02, "uv: %s u spans %.2f, want %.2f (its length)" % [w.name, face.size.x, float(info.len)])
		_check(absf(face.size.y - 4.5) < 0.02, "uv: %s v spans %.2f, want 4.5 (its height)" % [w.name, face.size.y])
		_check(absf(face.position.x - float(info.s0)) < 0.02, "uv: %s u starts at %.2f, s0 is %.2f" % [w.name, face.position.x, float(info.s0)])
		if k == 0:
			first_start = face.position.x
		else:
			_check(absf(face.position.x - prev_end) < 0.02, "uv: %s starts at %.2f, previous ended at %.2f" % [w.name, face.position.x, prev_end])
		prev_end = face.end.x
		var tan: PackedFloat32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
		_check(tan.size() > 0, "uv: %s has no tangents" % w.name)
	_check(absf(prev_end - first_start - 20.0) < 0.05, "uv: ring perimeter in UV space %.2f, want 20" % (prev_end - first_start))
	var fl := (rm.get_node("Floor/Mesh") as MeshInstance3D).mesh
	var top := PlanUV.uv_extent(fl, PlanUV.Axis.Z).size          # floor's frame: Z is world up
	_check(top.is_equal_approx(Vector2(6, 4)), "uv: floor extent %s, want (6,4)" % str(top))
	bake.free()
	_done("uv suite done")


# ---------------------------------------------------------------- 11. breaks on walls ----------


func _break_suite() -> void:
	# The starter patches: shape, rim, cavity.
	var t0 := Time.get_ticks_msec()
	var files: Array = Breaks.generate("user://breaks_test/")
	_say("  breaks: %d files in %d ms" % [files.size(), Time.get_ticks_msec() - t0])
	_check(files.size() == 9, "breaks: %d files written, want 9" % files.size())
	if files.size() == 9:
		var alb := Image.load_from_file(ProjectSettings.globalize_path("user://breaks_test/break_a_albedo.png"))
		_check(alb != null and alb.get_width() == 512 and alb.get_height() == 512, "breaks: albedo size")
		if alb != null:
			var inside := 0
			var rim_lum := 0.0
			var rim_n := 0
			var core_lum := 0.0
			var core_n := 0
			var c := Vector2(256, 256)
			for y in 512:
				for x in 512:
					var px := alb.get_pixel(x, y)
					if px.a > 0.5:
						inside += 1
					var r := Vector2(x, y).distance_to(c)
					# The rim is the band where alpha is still ramping in (f < RIM, alpha < 0.75).
					if px.a > 0.2 and px.a < 0.7:
						rim_lum += px.get_luminance()
						rim_n += 1
					elif px.a > 0.99 and r < 80.0:
						core_lum += px.get_luminance()
						core_n += 1
			var cover := float(inside) / (512.0 * 512.0)
			_check(cover > 0.3 and cover < 0.7, "breaks: alpha coverage %.2f" % cover)
			_check(rim_n > 0 and core_n > 0 and rim_lum / rim_n > core_lum / core_n,
					"breaks: rim is not lighter than the core (%.2f vs %.2f)" % [rim_lum / maxi(rim_n, 1), core_lum / maxi(core_n, 1)])
			var orm := Image.load_from_file(ProjectSettings.globalize_path("user://breaks_test/break_a_orm.png"))
			_check(orm != null and orm.get_pixel(256, 256).b < 0.01, "breaks: metallic not zero")

	# An on-wall legend row places a Decal on the room side of the nearest wall.
	var legend: Resource = Plugin.default_legend()
	var row: Resource = legend.call("find", "break")
	var proto := Decal.new()
	proto.size = Vector3(1.6, 0.6, 1.2)
	var ps := PackedScene.new()
	ps.pack(proto)
	proto.free()
	row.variants = [ps] as Array[PackedScene]
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(300, 200), Vector2(600, 400)), "op": 0}]),
		"doors": [],
		"props": [
			{"key": "break", "pos": Vector2(300, 40), "rot": 0.0, "size_m": Vector2(1, 1), "shape": 0},
			{"key": "break", "pos": Vector2(300, 200), "rot": 0.0, "size_m": Vector2(1, 1), "shape": 0},
		],
	}
	var bake: Node3D = Baker.build(data, Kit.new(), legend, "Breaks")
	root.add_child(bake)
	var d := bake.get_node_or_null("Level_0/Props/break_1") as Decal
	_check(d != null, "breaks: break_1 is not a Decal")
	if d != null:
		_check(absf(d.position.z - 0.01) < 0.02 and absf(d.position.y - 1.4) < 1e-3 and absf(d.position.x - 3.0) < 1e-3,
				"breaks: decal at %s, want (3, 1.4, 0.01)" % str(d.position))
		_check(d.basis.y.normalized().dot(Vector3(0, 0, 1)) > 0.99, "breaks: decal +Y %s should point into the room (+Z)" % str(d.basis.y))
		_check(d.has_meta("floorplan_on_wall"), "breaks: on-wall meta missing")
		var s := d.basis.get_scale()
		_check(s.x > 0.8 and s.x < 1.2 and absf(s.y - 1.0) < 1e-3, "breaks: jitter scale %s" % str(s))
	var far := bake.get_node_or_null("Level_0/Props/break_2")
	_check(far is StaticBody3D, "breaks: a mark 2 m from any wall should stay a plain greybox prop")
	# Determinism: the same plan bakes the same patch and the same jitter.
	var again: Node3D = Baker.build(data, Kit.new(), legend, "Breaks2")
	var d2 := again.get_node_or_null("Level_0/Props/break_1") as Node3D
	_check(d != null and d2 != null and d2.transform.is_equal_approx(d.transform), "breaks: re-bake changed the decal")
	again.free()
	bake.free()
	_done("break suite done")


# ---------------------------------------------------------------- 12. layered masks -----------


func _mask_suite() -> void:
	# The layered shader is the engine's generated code plus marked blocks: the parallax loop
	# must still be there verbatim, or someone replaced Godot's code with their own.
	var src := FileAccess.get_file_as_string("res://shaders/layered_plaster.gdshader")
	_check(src.contains("float layer_depth = 1.0 / num_layers;"), "masks: engine parallax line missing")
	_check(src.contains("while (current_depth < depth) {"), "masks: engine parallax loop missing")
	_check(src.contains("vec3 view_dir = normalize(normalize(-VERTEX + EYE_OFFSET) * mat3(TANGENT * heightmap_flip.x, -BINORMAL * heightmap_flip.y, NORMAL));"),
			"masks: engine view_dir line missing")
	_check(src.count("LAYERED") >= 8, "masks: added blocks are not marked")
	_check(src.contains("vec2 p = view_dir.xy * heightmap_scale * 0.01 * edge;"), "masks: edge fade not applied to the parallax depth")
	# Per-instance settings and the per-light relief shadow: instance uniforms (the docs' mechanism
	# for per-object values on a shared material) and a light() whose diffuse line is the docs'
	# Lambert example times the shadow.
	_check(src.count("instance uniform ") >= 12, "masks: fewer than 12 instance uniforms")
	_check(src.contains("uniform sampler2DArray mask_sheet"), "masks: mask sheet sampler missing")
	_check(src.contains("void light()"), "masks: no light() function")
	_check(src.contains("DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI * shadow;"), "masks: light() diffuse is not the docs' Lambert line")
	# Face boxes: a 2 × 3 × 4 box gets, per face, its own UV box in UV2 (min) and CUSTOM0 (max, 1).
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 4)
	var boxed: ArrayMesh = PlanUV.metric_uvs(bm)
	var barr := boxed.surface_get_arrays(0)
	var c1: PackedFloat32Array = barr[Mesh.ARRAY_CUSTOM1]
	var c0: PackedFloat32Array = barr[Mesh.ARRAY_CUSTOM0]
	_check(c1.size() > 0 and c0.size() == c1.size(), "masks: face box channels missing on the box")
	_check(barr[Mesh.ARRAY_TEX_UV2] == null, "masks: UV2 is written — that channel belongs to the lightmap")
	var boxes_seen := {}
	for i in c1.size() / 4:
		var mn := Vector2(c1[i * 4], c1[i * 4 + 1])
		var mx := Vector2(c0[i * 4], c0[i * 4 + 1])
		_check(absf(c0[i * 4 + 2] - 1.0) < 1e-6, "masks: face box flag not 1")
		boxes_seen["%s-%s" % [str(mn.snapped(Vector2(0.01, 0.01))), str(mx.snapped(Vector2(0.01, 0.01)))]] = (mx - mn)
	# Opposite faces project to the same box, so a cube has three distinct ones.
	_check(boxes_seen.size() == 3, "masks: %d distinct face boxes on a cube, want 3" % boxes_seen.size())
	var sizes := {}
	for k in boxes_seen:
		sizes[str((boxes_seen[k] as Vector2).snapped(Vector2(0.01, 0.01)))] = true
	_check(sizes.has(str(Vector2(2, 3))) and sizes.has(str(Vector2(2, 4))) and sizes.has(str(Vector2(4, 3))),
			"masks: cube face box sizes %s" % str(sizes.keys()))
	var shared := load("res://assets/materials/plaster_over_stone.tres") as ShaderMaterial
	_check(shared != null and PlanMasks.is_layered(shared), "masks: plaster_over_stone.tres is not the layered shader")

	# A finalized 6 × 4.5 wall wearing it: the mask is the room face, at 32 px/m.
	var kit := Kit.new()
	kit.wall_material = shared
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(300, 200), Vector2(600, 400)), "op": 0}]),
		"doors": [],
		"props": [],
	}
	var bake: Node3D = Baker.build(data, kit, null, "Masks")
	root.add_child(bake)
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	var mi := bake.get_node("Level_0/Room_0/Wall_0/Mesh") as MeshInstance3D
	_check(PlanMasks.is_layered(PlanMasks.material_of(mi)), "masks: finalized wall lost the layered material")
	# The finalized wall's room face carries its box: (s0, -4.5) .. (s0 + 6, 0).
	var warr := mi.mesh.surface_get_arrays(0)
	var wc1: PackedFloat32Array = warr[Mesh.ARRAY_CUSTOM1]
	var wc0: PackedFloat32Array = warr[Mesh.ARRAY_CUSTOM0]
	var room_box_ok := false
	for i in wc1.size() / 4:
		var mn := Vector2(wc1[i * 4], wc1[i * 4 + 1])
		var mx := Vector2(wc0[i * 4], wc0[i * 4 + 1])
		if mn.is_equal_approx(Vector2(0.0, -4.5)) and mx.is_equal_approx(Vector2(6.0, 0.0)):
			room_box_ok = true
	_check(room_box_ok, "masks: room face box (0,-4.5)..(6,0) not found on the finalized wall")
	# THE SHEET AND THE INSTANCE. prepare() gives the wall slot 0 of a fresh sheet, sets the three
	# instance parameters on the mesh, and leaves the material alone; a second wall gets slot 1;
	# a second call for the first wall finds slot 0 again.
	var dir := "user://masks_test"
	for f in [PlanMasks.sheet_path(dir), PlanMasks.sheet_path(dir) + ".import", PlanMasks.registry_path(dir)]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var res: Dictionary = PlanMasks.prepare(mi, "t|Wall_0/Mesh", dir)
	_check(not res.is_empty() and bool(res.wrote_sheet), "masks: prepare wrote no sheet")
	if not res.is_empty():
		var rect: Rect2 = res.rect
		_check(absf(rect.size.x - 6.0) < 0.02 and absf(rect.size.y - 4.5) < 0.02,
				"masks: rect %s, want 6 × 4.5 (the room face)" % str(rect))
		_check(int(res.slot) == 0, "masks: first slot is %d, want 0" % int(res.slot))
		_check(res.paint == Rect2i(0, 0, 192, 144), "masks: paint rect %s, want (0,0) 192 × 144 (32 px/m)" % str(res.paint))
		var sheet := Image.load_from_file(ProjectSettings.globalize_path(res.sheet))
		_check(sheet != null and sheet.get_width() == 2048 and sheet.get_height() == 2048, "masks: sheet is not 2048²")
		var imp := FileAccess.get_file_as_string(ProjectSettings.globalize_path(res.sheet + ".import"))
		_check(imp.contains('importer="2d_array_texture"') and imp.contains("slices/horizontal=8") and imp.contains("slices/vertical=8"),
				"masks: .import does not name the 2D array importer with 8 × 8 slices")
		_check(mi.get_instance_shader_parameter("mask_slot") == 0, "masks: mask_slot instance param not 0")
		_check(mi.get_instance_shader_parameter("mask_origin") == rect.position, "masks: mask_origin instance param not set")
		_check(mi.get_instance_shader_parameter("mask_size") == Vector2(8, 8), "masks: mask_size instance param not 8 × 8 m")
		_check(mi.material_override == null and PlanMasks.material_of(mi) == shared, "masks: the material was replaced or made unique")
		var mi1 := bake.get_node("Level_0/Room_0/Wall_1/Mesh") as MeshInstance3D
		var res1: Dictionary = PlanMasks.prepare(mi1, "t|Wall_1/Mesh", dir)
		_check(not res1.is_empty() and int(res1.slot) == 1 and not bool(res1.wrote_sheet), "masks: second wall did not get slot 1 on the same sheet")
		var again: Dictionary = PlanMasks.prepare(mi, "t|Wall_0/Mesh", dir)
		_check(not again.is_empty() and int(again.slot) == 0 and not bool(again.wrote_sheet), "masks: second prepare did not reuse slot 0")
		var reg := PlanMasks.load_registry(dir)
		_check((reg.slots as Dictionary).size() == 2, "masks: registry has %d slots, want 2" % (reg.slots as Dictionary).size())
		# Migration blit: a 192 × 144 white mask lands in slot 0's pixels and nowhere else.
		var white := Image.create(192, 144, false, Image.FORMAT_RGBA8)
		white.fill(Color.WHITE)
		_check(PlanMasks.blit_into_slot(white, 0, rect, dir), "masks: blit failed")
		var after := Image.load_from_file(ProjectSettings.globalize_path(res.sheet))
		_check(after != null and after.get_pixel(10, 10).r > 0.99 and after.get_pixel(300, 10).r < 0.01 and after.get_pixel(10, 200).r < 0.01,
				"masks: blit did not land in slot 0 only")
	bake.free()
	_done("mask suite done")


# ---------------------------------------------------------------- 14. partition walls ----------


## Rooms inside rooms and drawn walls: interior pieces wherever floor lies on both sides of the
## line, joined to the ring band and to each other without overlap, baked as Partition_n slabs
## that doors snap to.
func _partition_walls_suite() -> void:
	var t := 50.0
	var big := Geo.compute([{"poly": Geo.rect(Vector2(500, 500), Vector2(1000, 1000)), "op": 0}])
	var ring_pcs := Geo.wall_pieces(big, t)
	# 1. A room in the middle: four walls, floor on both sides of each, one thick square ring.
	var inner := {"points": Geo.rect(Vector2(450, 450), Vector2(300, 300)), "closed": true, "t": 0.0}
	var p1 := Geo.partition_pieces(big, [inner], t, ring_pcs)
	_check(p1.size() == 4, "walls: room-in-room made %d pieces, want 4" % p1.size())
	_check(absf(_pieces_area(p1) - 60000.0) / 60000.0 < 0.005, "walls: room-in-room band area %.0f, want 60000" % _pieces_area(p1))
	var sides_ok := true
	for pc: Dictionary in p1:
		var mid: Vector2 = (pc.a + pc.b) * 0.5
		if not Geo.point_in_floor(big, mid + pc.n * 26.0) or not Geo.point_in_floor(big, mid - pc.n * 26.0):
			sides_ok = false
		if not bool(pc.get("partition", false)) or int(pc.get("ring", 0)) != -1:
			sides_ok = false
	_check(sides_ok, "walls: a room-in-room piece lacks floor on a side or its tags")
	_check_partition(big, "room-in-room", [inner])
	# 2. A room half outside: the outline grows round it; only the edges inside become walls,
	# and nothing reaches past the outline into the bump.
	var half_out := {"points": Geo.rect(Vector2(950, 450), Vector2(300, 300)), "closed": true, "t": 0.0}
	var bump := Geo.compute([{"poly": Geo.rect(Vector2(500, 500), Vector2(1000, 1000)), "op": 0},
			{"poly": Geo.rect(Vector2(950, 450), Vector2(300, 300)), "op": 0}])
	var p2 := Geo.partition_pieces(bump, [half_out], t, Geo.wall_pieces(bump, t))
	_check(p2.size() == 3, "walls: half-outside room made %d pieces, want 3" % p2.size())
	_check(absf(_pieces_area(p2) - 35000.0) / 35000.0 < 0.005, "walls: half-outside band area %.0f, want 35000" % _pieces_area(p2))
	var tooth := false
	for pc: Dictionary in p2:
		for v: Vector2 in pc.poly:
			if v.x > 1000.5:
				tooth = true
	_check(not tooth, "walls: a piece reaches past the outline into the bump")
	_check_partition(bump, "half-outside room", [half_out])
	# 3. A drawn wall crossing the outline: clipped to the floor, flush at the outline, butt inside.
	var line := {"points": PackedVector2Array([Vector2(500, -200), Vector2(500, 500)]), "closed": false, "t": 0.0}
	var p3 := Geo.partition_pieces(big, [line], t, ring_pcs)
	_check(p3.size() == 1, "walls: crossing line made %d pieces, want 1" % p3.size())
	if p3.size() == 1:
		var bb := _poly_bounds(p3[0].poly)
		_check(bb.position.distance_to(Vector2(475, 0)) < 0.5 and bb.end.distance_to(Vector2(525, 500)) < 0.5,
				"walls: crossing line piece spans %s, want (475,0)..(525,500)" % str(bb))
	# 4. Two crossing walls and an L: six pieces, the crossing square owned by the first wall,
	# whichever order they are drawn in.
	var wa := {"points": PackedVector2Array([Vector2(200, 500), Vector2(800, 500)]), "closed": false, "t": 0.0}
	var wb := {"points": PackedVector2Array([Vector2(500, 200), Vector2(500, 800)]), "closed": false, "t": 0.0}
	var wl := {"points": PackedVector2Array([Vector2(100, 100), Vector2(300, 100), Vector2(300, 300)]), "closed": false, "t": 0.0}
	var p4 := Geo.partition_pieces(big, [wa, wb, wl], t, ring_pcs)
	_check(p4.size() == 6, "walls: cross + L made %d pieces, want 6" % p4.size())
	_check(absf(_pieces_area(p4) - 77500.0) / 77500.0 < 0.005, "walls: cross + L area %.0f, want 77500" % _pieces_area(p4))
	_check(absf(_ring_area(p4, -1) - 30000.0) < 200.0 and absf(_ring_area(p4, -2) - 27500.0) < 200.0,
			"walls: crossing square not owned by the first wall (A %.0f, B %.0f)" % [_ring_area(p4, -1), _ring_area(p4, -2)])
	_check_partition(big, "cross + L", [wa, wb, wl])
	var p4b := Geo.partition_pieces(big, [wb, wa, wl], t, ring_pcs)
	_check(p4b.size() == 6 and absf(_pieces_area(p4b) - 77500.0) / 77500.0 < 0.005 and absf(_ring_area(p4b, -1) - 30000.0) < 200.0,
			"walls: order swapped: %d pieces, area %.0f, first wall %.0f" % [p4b.size(), _pieces_area(p4b), _ring_area(p4b, -1)])
	# 5. Two rooms sharing a wall: the shared edge is built once, the second room's side walls
	# start on its face.
	var r1 := {"points": Geo.rect(Vector2(250, 250), Vector2(300, 300)), "closed": true, "t": 0.0}
	var r2 := {"points": Geo.rect(Vector2(550, 250), Vector2(300, 300)), "closed": true, "t": 0.0}
	var p5 := Geo.partition_pieces(big, [r1, r2], t, ring_pcs)
	_check(p5.size() == 7, "walls: two rooms sharing an edge made %d pieces, want 7" % p5.size())
	_check(absf(_pieces_area(p5) - 102500.0) / 102500.0 < 0.005, "walls: shared-edge area %.0f, want 102500" % _pieces_area(p5))
	_check_partition(big, "shared edge", [r1, r2])
	# A room nested in a hole is floor (point_in_floor once stopped at the first island's hole).
	var nest := Geo.compute([{"poly": Geo.rect(Vector2(500, 500), Vector2(1000, 1000)), "op": 0},
			{"poly": Geo.rect(Vector2(500, 500), Vector2(200, 200)), "op": 1},
			{"poly": Geo.rect(Vector2(500, 500), Vector2(100, 100)), "op": 0}])
	_check(Geo.point_in_floor(nest, Vector2(500, 500)), "walls: island-in-hole centre not counted as floor")
	# 7. The bake: Partition_n slabs standing ON the floor, one with a door cut, texture
	# continuous round the room.
	var data := {"ppm": 100.0, "islands": big, "doors": [{"pos": Vector2(450, 305), "width_m": 1.0}],
			"props": [], "walls": [inner]}
	var bake: Node3D = Baker.build(data, Kit.new(), null, "Rooms")
	root.add_child(bake)
	var rm := bake.get_node("Level_0/Room_0")
	var walls := 0
	var parts := 0
	var part_door := 0
	var on_floor := true
	var s0s: Array = []
	for c in rm.get_children():
		if c.name.begins_with("Wall_"):
			walls += 1
		elif c.name.begins_with("Partition_"):
			parts += 1
			var slab := c as CSGPolygon3D
			var info: Dictionary = c.get_meta("floorplan_wall")
			if slab == null or not bool(info.get("partition", false)) or absf(slab.depth - 4.5) > 1e-4 or absf(slab.position.y) > 1e-4:
				on_floor = false
			elif not Geo.point_in_floor(big, Vector2(slab.position.x, slab.position.z) * 100.0):
				on_floor = false
			s0s.append(float(info.s0))
		elif c.name.begins_with("Door_") and String(c.get_meta("floorplan_door_of", "")).begins_with("Partition_"):
			part_door += 1
	_check(walls == 4 and parts == 4, "walls: bake has %d walls and %d partitions, want 4 + 4" % [walls, parts])
	_check(on_floor, "walls: a partition slab is off the floor, mis-tagged or mis-sized")
	_check(part_door == 1, "walls: %d door cuts on partitions, want 1" % part_door)
	s0s.sort()
	_check(s0s.size() == 4 and absf(s0s[3] - 9.0) < 1e-3, "walls: partition s0 run %s, want 0, 3, 6, 9" % str(s0s))
	# 8. Finalize: partitions become bodies with mesh and collision.
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	var bodies := 0
	for c in bake.get_node("Level_0/Room_0").get_children():
		if c.name.begins_with("Partition_") and c is StaticBody3D and c.get_node_or_null("Mesh") != null \
				and c.get_node_or_null("Collision") != null:
			bodies += 1
	_check(bodies == 4, "walls: %d finalized partition bodies, want 4" % bodies)
	bake.free()
	_done("partition walls suite done")


func _pieces_area(pieces: Array) -> float:
	var s := 0.0
	for pc: Dictionary in pieces:
		s += absf(Geo.area(pc.poly))
	return s


func _ring_area(pieces: Array, ring: int) -> float:
	var s := 0.0
	for pc: Dictionary in pieces:
		if int(pc.get("ring", 0)) == ring:
			s += absf(Geo.area(pc.poly))
	return s


func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		r = r.expand(v)
	return r


## cast_motion of `shape` from `from` to `to` on mask 1: [safe, unsafe] fractions, [1, 1] = free.
## Also fails (returns [0, 0]) when the shape already overlaps something at `from`.
func _sweep(space: PhysicsDirectSpaceState3D, shape: Shape3D, from: Vector3, to: Vector3) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), from)
	q.motion = to - from
	if not space.intersect_shape(q, 1).is_empty():
		return [0.0, 0.0]
	return space.cast_motion(q)


# ---------------------------------------------------------------- 13. see-through --------------


## The camera's occluder fade against a finalized room: the query names exactly the wall on
## the line, the node fades it with GeometryInstance3D.transparency and nothing else, and it
## composes with RoofFade's holds.
func _occluder_suite() -> void:
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.rect(Vector2(300, 200), Vector2(600, 400)), "op": 0}]),
		"doors": [],
		"props": [],
	}
	var bake: Node3D = Baker.build(data, Kit.new(), null, "Occl")
	root.add_child(bake)
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	# A bare body stands in for the player; NOT in group "player" — scripts/hud.gd dereferences
	# `.health` on whatever joins that group, and the query takes the node directly anyway.
	var player := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	col.shape = cap
	player.add_child(col)
	root.add_child(player)
	player.global_position = Vector3(3.0, 0.9, 2.0)
	await process_frame
	await physics_frame
	await physics_frame
	var room := bake.get_node("Level_0/Room_0")
	var plus_z: Node3D = null
	var minus_z: Node3D = null
	for c in room.get_children():
		if c is Node3D and c.has_meta("floorplan_wall"):
			if plus_z == null or c.global_position.z > plus_z.global_position.z:
				plus_z = c
			if minus_z == null or c.global_position.z < minus_z.global_position.z:
				minus_z = c
	_check(plus_z != null and minus_z != null and plus_z != minus_z, "occluder: walls not found")
	if plus_z == null or minus_z == null:
		_done("occluder suite done")
		return
	var mesh := plus_z.get_node("Mesh") as MeshInstance3D
	var space := root.get_world_3d().direct_space_state
	var pts: Array[Vector3] = [Vector3(3, 0.2, 2), Vector3(3, 1.0, 2), Vector3(3, 1.7, 2)]
	var ex: Array[RID] = [player.get_rid()]
	# Camera outside the room behind the +Z wall, looking at the player inside.
	var found: Array[GeometryInstance3D] = Occl.occluders(space, Vector3(3, 5, 9), pts, ex, 1, 8, player)
	_check(found.size() == 1 and found[0] == mesh,
			"occluder: query found %s, want only the +Z wall's Mesh" % str(found.map(func(g): return g.get_path())))
	_check(not found.has(bake.get_node("Level_0/Room_0/Floor/Mesh")) and not found.has(minus_z.get_node("Mesh")),
			"occluder: floor or far wall in the set")
	# Camera inside, nothing in the way.
	var clear: Array[GeometryInstance3D] = Occl.occluders(space, Vector3(3, 2.5, 3.5), pts, ex, 1, 8, player)
	_check(clear.is_empty(), "occluder: %d occluders with a clear line" % clear.size())
	# A box room's corners stop the spread: the hit wall stays alone.
	var kept: Array[GeometryInstance3D] = Occl.spread_walls(found, Vector3(3, 5, 9), player.global_position, 35.0, 0.6, player)
	_check(kept.size() == 1, "occluder: spread crossed a 90° corner (%d pieces)" % kept.size())
	# The node: hold → transparency reaches `faded`; shadow and material untouched; release → 0.
	var n := Occl.new()
	n.faded = 0.85
	n.fade_time = 0.1
	root.add_child(n)
	n.set_physics_process(false)          # no camera here; drive it by hand
	n.apply(found)
	await create_timer(0.35).timeout
	_check(absf(mesh.transparency - 0.85) < 0.02, "occluder: transparency %.2f, want 0.85" % mesh.transparency)
	_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "occluder: cast_shadow changed")
	_check(mesh.material_override == null, "occluder: material touched")
	n.apply([] as Array[GeometryInstance3D])
	await create_timer(0.35).timeout
	_check(mesh.transparency < 0.02, "occluder: transparency %.2f after release, want 0" % mesh.transparency)
	# Composes with a RoofFade zone: the zone's hold survives the camera's release (the mesh
	# stays faded; the LEVEL is the latest holder's, as the protocol documents).
	RoofFadeScript.hold(mesh, +1, 0.95, 0.05)
	n.apply(found)
	n.apply([] as Array[GeometryInstance3D])
	_check(int(mesh.get_meta("rf_holds", 0)) == 1 and float(mesh.get_meta("rf_target", 0.0)) > 0.5,
			"occluder: zone hold lost (holds %d, target %.2f)" % [int(mesh.get_meta("rf_holds", 0)), float(mesh.get_meta("rf_target", 0.0))])
	RoofFadeScript.hold(mesh, -1, 0.95, 0.05)
	_check(int(mesh.get_meta("rf_holds", 0)) == 0, "occluder: hold count after release")
	# A held wall that gets freed leaves nothing dangling.
	n.apply(found)
	plus_z.free()
	n.apply([] as Array[GeometryInstance3D])
	_check((n._held as Dictionary).is_empty(), "occluder: freed mesh still held")
	bake.free()
	# A ROUND ROOM: 32 wall pieces of 0.59 m. The rays cross one or two; the spread takes the
	# whole arc between the camera and the player, and none of the far side.
	var cdata := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": Geo.circle(Vector2(300, 300), 300.0, 32), "op": 0}]),
		"doors": [],
		"props": [],
	}
	var cbake: Node3D = Baker.build(cdata, Kit.new(), null, "OcclCircle")
	root.add_child(cbake)
	var cops: Array = await Refine.finalize(cbake, self)
	Refine.apply_ops(cops, cbake)
	# x = 3.2, not 3.0: the line x = 3 runs exactly along the mitre seam between two pieces, and
	# a ray along a trimesh seam slips through (in play the lateral rays cover that).
	player.global_position = Vector3(3.2, 0.9, 3.0)
	await process_frame
	await physics_frame
	await physics_frame
	var cspace := root.get_world_3d().direct_space_state
	var cpts: Array[Vector3] = [Vector3(3.2, 0.2, 3), Vector3(3.2, 1.0, 3), Vector3(3.2, 1.7, 3)]
	var cam_pos := Vector3(3.2, 5, 12)
	var chit: Array[GeometryInstance3D] = Occl.occluders(cspace, cam_pos, cpts, ex, 1, 8, player)
	var cspread: Array[GeometryInstance3D] = Occl.spread_walls(chit, cam_pos, player.global_position, 35.0, 0.6, player)
	_check(chit.size() >= 1 and chit.size() <= 3 and cspread.size() >= 8,
			"occluder: round room %d hit → %d faded pieces, want a whole arc" % [chit.size(), cspread.size()])
	var far_side := 0
	for g in cspread:
		var body := g.get_parent() as Node3D
		if body != null and body.global_position.z < 3.0:
			far_side += 1
	_check(far_side == 0, "occluder: %d far-side pieces of the round room faded" % far_side)
	cbake.free()
	# FLOORS: two storeys and a stair. With the player downstairs the whole upper level fades
	# out (its slab is the ceiling), stairs excepted; a bake floor is never blocked by the size
	# guard; standing within level_switch_m of the upper floor counts as being on it.
	var p0: float = PlanStairScript.passage_start(4.7, 0.2, 7.56, 0)
	var ground := {"index": 0, "islands": Geo.compute([{"poly": Geo.rect(Vector2(600, 400), Vector2(1200, 800)), "op": 0}]),
			"doors": [], "props": [], "stairs": [{"pos": Vector2(150, 150), "rot": 0.0, "width_m": 1.2,
			"length_m": 0.0, "steps": 0, "footprint": Geo.rect(Vector2(150 + (p0 + 7.56) * 50.0, 150), Vector2((7.56 - p0) * 100.0, 120))}]}
	var upper := {"index": 1, "islands": Geo.compute([{"poly": Geo.rect(Vector2(600, 400), Vector2(1200, 800)), "op": 0}]),
			"doors": [], "props": [], "stairs": []}
	var fbake: Node3D = Baker.build({"ppm": 100.0, "pitch": 4.7, "levels": [ground, upper]}, Kit.new(), null, "OcclFloors")
	root.add_child(fbake)
	var fops: Array = await Refine.finalize(fbake, self)
	Refine.apply_ops(fops, fbake)
	await process_frame
	await physics_frame
	await physics_frame
	var levels: Array = Occl.find_levels(fbake)
	_check(levels.size() == 2, "occluder: %d levels found, want 2" % levels.size())
	var hidden: Array = Occl.levels_hidden(levels, 0.0, 1.2, true, false)
	_check(hidden.size() == 1 and int(hidden[0].index) == 1, "occluder: downstairs should hide level 1 only")
	var slab := fbake.get_node("Level_1/Room_0/Floor/Mesh") as MeshInstance3D
	var wall0 := fbake.get_node("Level_0/Room_0/Wall_0/Mesh") as MeshInstance3D
	var step0 := fbake.get_node("Level_0/Stairs/Stair_1/Steps/Step_0/Mesh") as MeshInstance3D
	var lv1_meshes: Array = hidden[0].meshes if hidden.size() == 1 else []
	_check(lv1_meshes.has(slab) and not lv1_meshes.has(wall0) and not lv1_meshes.has(step0), "occluder: level 1 mesh set wrong")
	n.apply_levels(hidden)
	await create_timer(0.35).timeout
	_check(slab.transparency > 0.98 and wall0.transparency < 0.02 and step0.transparency < 0.02,
			"occluder: upper slab %.2f / ground wall %.2f / step %.2f, want 1 / 0 / 0" % [slab.transparency, wall0.transparency, step0.transparency])
	_check(Occl.levels_hidden(levels, 4.7 - 1.0, 1.2, true, false).is_empty(), "occluder: 1 m below the upper floor still hides it")
	_check(Occl.levels_hidden(levels, 4.7 - 1.5, 1.2, true, false).size() == 1, "occluder: 1.5 m below the upper floor shows it")
	_check(Occl.levels_hidden(levels, 5.0, 1.2, true, true).size() == 1 and int(Occl.levels_hidden(levels, 5.0, 1.2, true, true)[0].index) == 0,
			"occluder: hide_below upstairs should hide level 0")
	n.apply_levels([])
	await create_timer(0.35).timeout
	_check(slab.transparency < 0.02, "occluder: upper slab %.2f after the player went up, want 0" % slab.transparency)
	# The rays through a big slab: a 12 × 8 m floor is over no size guard.
	var fpts: Array[Vector3] = [Vector3(6, 0.2, 5), Vector3(6, 1.0, 5), Vector3(6, 1.7, 5)]
	var through: Array[GeometryInstance3D] = Occl.occluders(space, Vector3(6, 9, 5.5), fpts, ex, 1, 8, player)
	_check(through.has(slab), "occluder: the upper slab was not found by a ray from above (size guard?)")
	n.free()
	player.free()
	fbake.free()
	_done("occluder suite done")


## Height of the first collider under `from`, or null.
func _ray_down(space: PhysicsDirectSpaceState3D, from: Vector3) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -20, 0), 1)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else null


## REGIONS, DOORS, LINKS, THE MASK: every ROOM outline is a region parented by containment, a
## door knows the regions on its two sides, a stair links two storeys' regions, a point query
## finds the deepest region, Apply assets keeps a stair's and a door's identity, and the room
## mask's pure pieces (the rectangle cover, the visible-set walk) behave.
func _regions_suite() -> void:
	var plan := PlanRootScript.new()
	var kit := Kit.new()
	plan.kit = kit
	var legend := Legend.new()
	var door_row := LegendEntry.new()
	door_row.key = "door"
	var stair_row := LegendEntry.new()
	stair_row.key = "stair"
	(legend.get("entries") as Array).append(door_row)
	(legend.get("entries") as Array).append(stair_row)
	plan.legend = legend
	root.add_child(plan)
	var f0 := PlanLevelScript.new()
	f0.name = "Floor_0"
	f0.index = 0
	plan.add_child(f0)
	var plate := PlanShapeScript.new()
	plate.kind = 1
	plate.size = Vector2(1400, 800)
	plate.position = Vector2(700, 400)
	f0.add_child(plate)
	var room := PlanShapeScript.new()          # x 1..5, y 1..4 m
	room.name = "Room"
	room.kind = 1
	room.room = true
	room.size = Vector2(400, 300)
	room.position = Vector2(300, 250)
	f0.add_child(room)
	var inner := PlanShapeScript.new()         # x 1.55..3.05, y 1.4..2.6 m, inside Room
	inner.name = "Inner"
	inner.kind = 1
	inner.room = true
	inner.size = Vector2(150, 120)
	inner.position = Vector2(230, 200)
	f0.add_child(inner)
	var door := PlanDoorScript.new()           # on Room's right edge, x = 5 m
	door.position = Vector2(500, 300)
	door.width_m = 1.0
	f0.add_child(door)
	var entrance := PlanDoorScript.new()       # on the ring, x = 0
	entrance.position = Vector2(5, 600)
	entrance.width_m = 1.2
	f0.add_child(entrance)
	var st := PlanStairScript.new()            # climbs +X from x = 3 m, in the open island
	st.position = Vector2(300, 600)
	f0.add_child(st)
	var f1 := PlanLevelScript.new()
	f1.name = "Floor_1"
	f1.index = 1
	plan.add_child(f1)
	var plate1 := PlanShapeScript.new()
	plate1.kind = 1
	plate1.size = Vector2(1400, 800)
	plate1.position = Vector2(700, 400)
	f1.add_child(plate1)
	var data: Dictionary = plan.plan_data()
	var lv0: Dictionary = data.levels[0]

	# 1. The pure region tree.
	var regs: Array = Baker.regions_of(lv0.islands, lv0.walls, 100.0)
	_check(regs.size() == 3, "regions: %d regions, want 3 (island, Room, Inner)" % regs.size())
	var by := {}
	for r: Dictionary in regs:
		by[r.name] = r
	_check(by.has("Island_0") and int(by.Island_0.depth) == 0 and String(by.Island_0.parent) == "", "regions: island root wrong")
	_check(by.has("Room") and String(by.Room.parent) == "Island_0" and int(by.Room.depth) == 1, "regions: Room's parent/depth wrong")
	_check(by.has("Inner") and String(by.Inner.parent) == "Room" and int(by.Inner.depth) == 2, "regions: Inner not parented to Room")
	_check(String(Baker.region_at(regs, Vector2(2.3, 2.0)).get("name", "")) == "Inner", "regions: deepest region at (2.3, 2) not Inner")
	_check(String(Baker.region_at(regs, Vector2(4.5, 3.5)).get("name", "")) == "Room", "regions: region at (4.5, 3.5) not Room")
	_check(String(Baker.region_at(regs, Vector2(10.0, 6.0)).get("name", "")) == "Island_0", "regions: region at (10, 6) not the island")
	_check(Baker.region_at(regs, Vector2(-1.0, 0.0)).is_empty(), "regions: a point outside found a region")

	# 2. The rectangle cover the mask builds on: an L, and a square with a room cut out.
	var ell := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(2, 2), Vector2(2, 4), Vector2(0, 4)])
	var rects: Array = RoomVis.boxes_of(ell)
	var area := 0.0
	var centres_in := true
	for rc: Rect2 in rects:
		area += rc.get_area()
		if not Geometry2D.is_point_in_polygon(rc.get_center(), ell):
			centres_in = false
	_check(absf(area - 12.0) < 1e-3 and centres_in, "regions: L cover area %.2f (want 12), centres inside %s" % [area, centres_in])
	var cut: Array = RoomVis.boxes_of(Geo.rect(Vector2(5, 5), Vector2(10, 10)), [Geo.rect(Vector2(5, 5), Vector2(4, 4))])
	area = 0.0
	var touches_cut := false
	for rc: Rect2 in cut:
		area += rc.get_area()
		if rc.intersects(Rect2(3.01, 3.01, 3.98, 3.98)):
			touches_cut = true
	_check(absf(area - 84.0) < 1e-3 and cut.size() == 4 and not touches_cut,
			"regions: square-minus-room cover area %.1f in %d rects (want 84 in 4), overlaps the cut %s" % [area, cut.size(), touches_cut])

	# 3. The bake: Area3Ds, door leaves with their sides, the stair's link.
	var bake := Baker.build(data, kit, legend, "Regions")
	root.add_child(bake)
	var regions_node := bake.get_node_or_null("Level_0/Regions")
	_check(regions_node != null and regions_node.get_child_count() == 3, "regions: Level_0/Regions missing or not 3 areas")
	var inner_area := bake.get_node_or_null("Level_0/Regions/Inner") as Area3D
	_check(inner_area != null and inner_area.collision_layer == Baker.LAYER_REGION and inner_area.collision_mask == 0
			and String((inner_area.get_meta("floorplan_region") as Dictionary).parent) == "Room"
			and inner_area.get_node_or_null("Shape") is CollisionPolygon3D, "regions: the Inner Area3D is wrong")
	_check(bake.get_node_or_null("Level_1/Regions/Island_0") != null, "regions: floor 1 has no island region")
	var d1 := bake.get_node_or_null("Level_0/Doors/door_1")
	var d2 := bake.get_node_or_null("Level_0/Doors/door_2")
	_check(d1 != null and d1.has_meta("floorplan_greybox") and d1.has_meta("floorplan_door"), "regions: door_1 (grey box) missing")
	if d1 != null and d2 != null:
		var s1: Array = (d1.get_meta("floorplan_door") as Dictionary).regions
		var s2: Array = (d2.get_meta("floorplan_door") as Dictionary).regions
		_check(s1.has("Room") and s1.has("Island_0"), "regions: the room door's sides %s, want Room + Island_0" % str(s1))
		_check(s2.has("Island_0") and s2.has(""), "regions: the entrance's sides %s, want Island_0 + outside" % str(s2))
		_check(absf(float((d1.get_meta("floorplan_door") as Dictionary).width) - 1.0) < 1e-3, "regions: door_1 width wrong")
		_check(absf((d1 as Node3D).position.x - 5.0) < 0.2 and absf((d1 as Node3D).position.y) < 1e-3, "regions: door_1 stands at %s, want x 5 on the floor" % (d1 as Node3D).position)
	var stair := bake.get_node_or_null("Level_0/Stairs/Stair_1")
	_check(stair != null and stair.has_meta("floorplan_link"), "regions: the stair has no link")
	if stair != null and stair.has_meta("floorplan_link"):
		var link: Dictionary = stair.get_meta("floorplan_link")
		_check(link.regions == ["Level_0/Regions/Island_0", "Level_1/Regions/Island_0"], "regions: stair link %s" % str(link.regions))
		_check(float((link.top as Vector3).y) > 4.0, "regions: stair link top %s not on the storey above" % str(link.top))

	# 4. The point query the controller uses: deepest hit.
	await physics_frame
	await physics_frame
	var q := PhysicsPointQueryParameters3D.new()
	q.position = Vector3(2.3, 0.5, 2.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = Baker.LAYER_REGION
	var hits: Array = root.get_viewport().world_3d.direct_space_state.intersect_point(q, 8)
	var deepest := ""
	var deepest_d := -1
	for h: Dictionary in hits:
		var info: Dictionary = (h.collider as Node).get_meta("floorplan_region")
		if int(info.depth) > deepest_d:
			deepest_d = int(info.depth)
			deepest = String(info.name)
	_check(hits.size() == 3 and deepest == "Inner", "regions: point query hit %d areas, deepest '%s' (want 3, Inner)" % [hits.size(), deepest])

	# 5. Apply assets keeps a stair's and a door's identity through the swap.
	var ps := PackedScene.new()
	var holder := Node3D.new()
	holder.name = "Asset"
	ps.pack(holder)
	holder.free()
	stair_row.scene = ps
	door_row.scene = ps
	var ops: Array = Refine.apply_assets(bake, legend, kit)
	Refine.apply_ops(ops, bake)
	stair = bake.get_node_or_null("Level_0/Stairs/Stair_1")
	d1 = bake.get_node_or_null("Level_0/Doors/door_1")
	_check(stair != null and stair.has_meta("floorplan_stair") and stair.has_meta("floorplan_link") and not stair.has_meta("floorplan_greybox"),
			"regions: the swapped stair lost its identity")
	_check(d1 != null and d1.has_meta("floorplan_door") and not d1.has_meta("floorplan_greybox"), "regions: the swapped door lost its identity")

	# 6. The visible-set walk: chains through open, near, seen doors; a link ignores distance.
	var edges: Array = [{"node": null, "a": "A", "b": "B", "link": false}, {"node": null, "a": "B", "b": "C", "link": false},
			{"node": null, "a": "C", "b": "D", "link": true}]
	var yes := func(_e: Dictionary) -> bool: return true
	var no := func(_e: Dictionary) -> bool: return false
	var all: Dictionary = RoomVis.visible_set("A", edges, yes, yes, yes)
	var shut: Dictionary = RoomVis.visible_set("A", edges, no, yes, yes)
	var far: Dictionary = RoomVis.visible_set("C", edges, yes, no, yes)
	_check(all.size() == 4 and shut.size() == 1 and far.has("D") and not far.has("B"),
			"regions: visible set sizes %d/%d, far-from-C %s (want 4/1, D only)" % [all.size(), shut.size(), far.keys()])

	# 7. The mask's slabs.
	var slabs: int = RoomVis.build_mask(bake, 3.0)
	var hidden := true
	for n in _walk(bake):
		if n.has_meta("room_mask") and (n.visible or (n as GeometryInstance3D).transparency < 1.0):
			hidden = false
	_check(slabs >= 3 and hidden, "regions: %d slabs, all hidden %s" % [slabs, hidden])
	bake.free()
	plan.free()
	_done("regions suite done")


## ROOFS: the straight-skeleton solid over a rectangle (hip, gable) and an L, a flat cap with a
## parapet, a lower storey's exposed part under a smaller storey above — heights from the pitch,
## every solid a manifold (each edge once each way), finalize keeping the pieces.
func _roof_suite() -> void:
	var Roof := preload("res://addons/floorplan/core/plan_roof.gd")
	var kit := Kit.new()
	kit.set("roof_kind", 2)   # hip
	kit.set("roof_pitch_degrees", 30.0)
	kit.set("roof_overhang", 0.5)
	kit.set("roof_step", 0.25)
	var h := float(kit.get("wall_height"))
	var t := float(kit.get("wall_thickness"))
	var slope := tan(deg_to_rad(30.0))
	# a 5 x 4 m room: the eave on the outer face (2 + t across), the ridge at h + (2 + t) * tan
	var room := Geo.rect(Vector2(250, 200), Vector2(500, 400))
	var data := {"ppm": 100.0, "islands": Geo.compute([{"poly": room, "op": 0}]), "doors": [], "props": []}
	var bake: Node3D = Baker.build(data, kit, null, "RoofTest")
	root.add_child(bake)
	var roof := bake.get_node_or_null("Level_0/Roof") as CSGCombiner3D
	_check(roof != null and roof.has_meta("floorplan_roof"), "roof: Level_0/Roof combiner with its meta")
	if roof != null:
		var piece := roof.get_node_or_null("Roof_0") as CSGMesh3D
		_check(piece != null, "roof: a CSGMesh3D piece")
		if piece != null:
			var rep: Dictionary = Roof.manifold_report(piece.mesh)
			_check(int(rep.bad) == 0, "roof: hip rect manifold (bad edges %d)" % int(rep.bad))
			var aabb := piece.mesh.get_aabb()
			var want := h + (2.0 + t) * slope
			_check(absf(aabb.end.y - want) < 0.3, "roof: hip ridge at %.2f (want %.2f)" % [aabb.end.y, want])
			_check(absf(aabb.position.y - (h - 0.5 * slope - 0.02)) < 0.02, "roof: base just under the eave")
			_check(absf(aabb.size.x - (5.0 + 2.0 * t + 1.0)) < 0.05, "roof: hip overhang all round (x %.2f)" % aabb.size.x)
		await process_frame
		await process_frame
		var out: Array = roof.get_meshes()
		var faces := 0
		if out.size() >= 2 and out[1] != null:
			faces = (out[1] as Mesh).get_faces().size() / 3
		_check(faces > 0, "roof: CSG accepted the hip solid (%d faces)" % faces)
	bake.free()
	# GABLE: same ridge, no overhang along the ridge axis (the gable ends sit on the wall line)
	kit.set("roof_kind", 3)
	bake = Baker.build(data, kit, null, "RoofTest")
	root.add_child(bake)
	var gp := bake.get_node_or_null("Level_0/Roof/Roof_0") as CSGMesh3D
	_check(gp != null, "roof: gable piece")
	if gp != null:
		var rep: Dictionary = Roof.manifold_report(gp.mesh)
		_check(int(rep.bad) == 0, "roof: gable rect manifold (bad edges %d)" % int(rep.bad))
		var aabb := gp.mesh.get_aabb()
		_check(absf(aabb.end.y - (h + (2.0 + t) * slope)) < 0.3, "roof: gable ridge height")
		_check(absf(aabb.size.x - (5.0 + 2.0 * t)) < 0.05, "roof: gable ends on the wall line (x %.2f)" % aabb.size.x)
		_check(absf(aabb.size.z - (4.0 + 2.0 * t + 1.0)) < 0.05, "roof: gable eaves overhang across (z %.2f)" % aabb.size.z)
	bake.free()
	# an L: hip, manifold
	kit.set("roof_kind", 2)
	var L := PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 400), Vector2(500, 400), Vector2(500, 800), Vector2(0, 800)])
	var ldata := {"ppm": 100.0, "islands": Geo.compute([{"poly": L, "op": 0}]), "doors": [], "props": []}
	bake = Baker.build(ldata, kit, null, "RoofTest")
	root.add_child(bake)
	var lp := bake.get_node_or_null("Level_0/Roof/Roof_0") as CSGMesh3D
	_check(lp != null, "roof: L piece")
	if lp != null:
		var rep: Dictionary = Roof.manifold_report(lp.mesh)
		_check(int(rep.bad) == 0, "roof: L hip manifold (bad edges %d)" % int(rep.bad))
	bake.free()
	# FLAT: a cap on the wall tops and a parapet above it
	kit.set("roof_kind", 1)
	kit.set("parapet_height", 1.0)
	bake = Baker.build(data, kit, null, "RoofTest")
	root.add_child(bake)
	var fr := bake.get_node_or_null("Level_0/Roof") as CSGCombiner3D
	_check(fr != null and fr.get_node_or_null("Cap_0") != null and fr.get_node_or_null("Parapet_0_0") != null, "roof: flat cap and parapet pieces")
	if fr != null:
		await process_frame
		await process_frame
		var out: Array = fr.get_meshes()
		if out.size() >= 2 and out[1] != null:
			var top: float = (out[1] as Mesh).get_aabb().end.y
			var ft := float(kit.get("floor_thickness"))
			_check(absf(top - (h + ft + 1.0)) < 0.02, "roof: flat parapet top at %.2f (want %.2f)" % [top, h + ft + 1.0])
	bake.free()
	# a SETBACK: a 10 x 4 lower storey under a 5 x 4 upper one — the exposed half gets a roof that
	# leans on the upper wall (no overhang past it), the upper storey its own
	kit.set("roof_kind", 2)
	var low := Geo.rect(Vector2(500, 200), Vector2(1000, 400))
	var up := Geo.rect(Vector2(250, 200), Vector2(500, 400))
	var sdata := {"ppm": 100.0, "levels": [
		{"index": 0, "islands": Geo.compute([{"poly": low, "op": 0}]), "doors": [], "props": [], "stairs": [], "walls": []},
		{"index": 1, "islands": Geo.compute([{"poly": up, "op": 0}]), "doors": [], "props": [], "stairs": [], "walls": []}]}
	bake = Baker.build(sdata, kit, null, "RoofTest")
	root.add_child(bake)
	var r0 := bake.get_node_or_null("Level_0/Roof/Roof_0") as CSGMesh3D
	var r1 := bake.get_node_or_null("Level_1/Roof/Roof_0") as CSGMesh3D
	_check(r0 != null and r1 != null, "roof: setback gives both storeys a roof")
	if r0 != null:
		var aabb := r0.mesh.get_aabb()
		_check(absf(aabb.position.x - (5.0 + t)) < 0.05, "roof: the lower roof starts at the upper wall's outer face (x %.2f)" % aabb.position.x)
		_check(int(Roof.manifold_report(r0.mesh).bad) == 0, "roof: setback lean-to manifold")
	# FINALIZE keeps the roof as bodies with the meta
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)
	var body := bake.get_node_or_null("Level_1/Roof/Roof_0") as StaticBody3D
	_check(body != null and body.has_meta("floorplan_roof") and body.get_node_or_null("Mesh") != null, "roof: finalize → StaticBody3D with Mesh and the meta")
	bake.free()
	_done("roof suite done")


func _check_partition(islands: Array, label: String, walls: Array = []) -> void:
	var t := 0.5 * Tracer.PLAN_PPM
	var pieces := Geo.wall_pieces(islands, t)
	if not walls.is_empty():
		pieces = pieces + Geo.partition_pieces(islands, walls, t, pieces)
	var overlaps := 0
	var bad := 0
	for i in pieces.size():
		var pi: PackedVector2Array = pieces[i].poly
		if pi.size() < 3 or absf(Geo.area(pi)) < 1.0:
			bad += 1
		for j in range(i + 1, pieces.size()):
			var pj: PackedVector2Array = pieces[j].poly
			var s := 0.0
			for p: PackedVector2Array in Geometry2D.intersect_polygons(pi, pj):
				s += absf(Geo.area(p))
			if s > 1.0:
				overlaps += 1
	_check(bad == 0, "%s: %d degenerate wall pieces" % [label, bad])
	_check(overlaps == 0, "%s: %d overlapping wall piece pairs of %d" % [label, overlaps, pieces.size()])


# ---------------------------------------------------------------- 17. the redraw cache ---------


## _draw's geometry (islands, ring, partitions, edges) is cached per floor by the floor's
## shape/wall signature and the wall thickness: a hit returns the same result, a moved room
## recomputes, and the answer always equals the direct Geo calls. Also the _split prefilter:
## a room edge lying exactly on the plate's outline still gets its cuts.
func _cache_suite() -> void:
	var plan := PlanRootScript.new()
	plan.kit = Kit.new()
	root.add_child(plan)
	var plate := PlanShapeScript.new()
	plate.kind = 1
	plate.size = Vector2(1200, 900)
	plate.position = Vector2(600, 450)
	plan.add_child(plate)
	var rooms: Array = []
	for r in 3:
		for c in 4:
			var rm := PlanShapeScript.new()
			rm.name = "R%d%d" % [r, c]
			rm.kind = 1
			rm.room = true
			rm.size = Vector2(300, 300)
			rm.position = Vector2(150 + 300 * c, 150 + 300 * r)   # edges on the plate outline
			plan.add_child(rm)
			rooms.append(rm)
	var wall := PlanWallScript.new()
	wall.points = PackedVector2Array([Vector2(100, 450), Vector2(1100, 450)])
	plan.add_child(wall)
	var wall2 := PlanWallScript.new()
	wall2.points = PackedVector2Array([Vector2(600, 100), Vector2(600, 800)])
	plan.add_child(wall2)
	var t := 50.0
	var g1: Dictionary = plan._level_geometry(0)
	var g2: Dictionary = plan._level_geometry(0)
	_check(g1 == g2, "cache: second call is not the cached dictionary")
	var direct: Array = Geo.partition_pieces(plan.islands(0), plan.walls(0), t, Geo.wall_pieces(plan.islands(0), t))
	_check(_pieces_area(g1.parts) > 0.0 and absf(_pieces_area(g1.parts) - _pieces_area(direct)) < 1e-3,
			"cache: partitions differ from the direct call (%.1f vs %.1f)" % [_pieces_area(g1.parts), _pieces_area(direct)])
	_check((g1.parts as Array).size() == direct.size(), "cache: %d pieces vs %d direct" % [(g1.parts as Array).size(), direct.size()])
	# a room edge on the plate outline: the corner rooms' outer edges coincide with the ring, and
	# the rooms' shared edges must be cut at every crossing — the prefilter may drop none
	var cuts := 0
	for q: Dictionary in g1.parts:
		cuts += 1
	_check(cuts >= 17, "cache: only %d partition pieces for a 3x4 grid with two walls (want >= 17)" % cuts)
	# move a room: a miss, recomputed, equal to the direct call again
	(rooms[5] as Node2D).position += Vector2(40, 0)
	var g3: Dictionary = plan._level_geometry(0)
	_check(int(g3.sig) != int(g1.sig), "cache: a moved room kept the signature")
	var direct3: Array = Geo.partition_pieces(plan.islands(0), plan.walls(0), t, Geo.wall_pieces(plan.islands(0), t))
	_check(absf(_pieces_area(g3.parts) - _pieces_area(direct3)) < 1e-3, "cache: after a move, partitions differ from the direct call")
	# a kit change (thickness) is a miss too
	plan.kit.wall_thickness = 0.3
	var g4: Dictionary = plan._level_geometry(0)
	_check(absf(float(g4.t) - 30.0) < 1e-6 and g4 != g3, "cache: a thickness change did not recompute")
	# the bucket walk equals the old collectors: shapes/doors/walls in tree order, and plan_data still works
	_check(plan.shapes(0).size() == 13 and plan.walls(0).size() == 14, "cache: bucket counts %d shapes, %d walls" % [plan.shapes(0).size(), plan.walls(0).size()])
	var data: Dictionary = plan.plan_data()
	_check((data.levels as Array).size() == 1 and (data.levels[0].walls as Array).size() == 14, "cache: plan_data walls %d" % (data.levels[0].walls as Array).size())
	plan.free()
	_done("cache suite done")


# ---------------------------------------------------------------- helpers ----------------------


# ---------------------------------------------------------------- 18. the 3D front -------------


## The same Layout written through the façade into a 2D PlanRoot and a 3D PlanRoot3D is the
## same plan: plan_data equal per floor (the core never knows which front drew it), the read
## back equal, the bake equal; a re-sync changes nothing, an edit syncs in place; convert_plan
## round-trips nodes, names and metas; containers stand at the storey pitch; the preview is
## not saved.
func _plan3d_suite() -> void:
	var lay := _twin_layout()
	var kit := Kit.new()
	var p2: Node = Api.new_plan("Twin", kit)
	var p3: Node = Api.new_plan("Twin", kit, null, true)
	root.add_child(p2)
	root.add_child(p3)
	_check(not Api.is_plan_3d(p2) and Api.is_plan_3d(p3), "plan3d: is_plan_3d")
	var w2: Dictionary = Api.write_layout(p2, lay, "gen")
	var w3: Dictionary = Api.write_layout(p3, lay, "gen")
	_check((w2.warnings as PackedStringArray).is_empty() and (w3.warnings as PackedStringArray).is_empty(),
			"plan3d: write warnings %s / %s" % [w2.warnings, w3.warnings])
	_check((w2.added as PackedStringArray).size() == (w3.added as PackedStringArray).size(),
			"plan3d: added %d vs %d" % [(w2.added as PackedStringArray).size(), (w3.added as PackedStringArray).size()])
	# containers at the storey pitch, only the current one visible
	var pitch := float(p3.call("pitch_m"))
	var f0: Node3D = p3.call("level_container", 0)
	var f1: Node3D = p3.call("level_container", 1)
	_check(f0 != null and f1 != null, "plan3d: containers missing")
	if f1 != null:
		_check(absf(f1.position.y - pitch) < 1e-4, "plan3d: Floor_1 at y %.2f, want %.2f" % [f1.position.y, pitch])
		p3.set("current_level", 1)
		_check(f1.visible and not f0.visible, "plan3d: visibility did not follow current_level")
		p3.set("current_level", 0)
	# plan_data: the same numbers, floor by floor
	var d2: Dictionary = p2.call("plan_data")
	var d3: Dictionary = p3.call("plan_data")
	_check(_same_data(d2, d3, 0.6), "plan3d: plan_data differs between the fronts")
	# the unfloored area: a room entry (a region) that adds no island and no wall
	var area_entries := 0
	for wl: Dictionary in d3.levels[0].walls:
		if bool(wl.get("room", false)) and not bool(wl.get("floored", true)):
			area_entries += 1
	_check(area_entries == 1 and (d3.levels[0].islands as Array).size() == 1, "plan3d: unfloored area: %d entries, %d islands (want 1, 1)" % [area_entries, (d3.levels[0].islands as Array).size()])
	var bk3: Node3D = Baker.build(d3, kit, null, "Area")
	var region_names := PackedStringArray()
	for n: Node in _walk(bk3):
		if n.get_parent() != null and String(n.get_parent().name) == "Regions":
			region_names.append(String(n.name))
	_check(region_names.has("sleep"), "plan3d: the unfloored area is not a bake region (%s)" % str(region_names))
	bk3.free()
	# read back: the same Layout, owners included
	var r2: Resource = Api.read_layout(p2)
	var r3: Resource = Api.read_layout(p3)
	_check(Layout.equal(r2, r3, 0.011, true), "plan3d: read_layout differs between the fronts")
	_check(Layout.equal(r3, lay, 0.011, false), "plan3d: 3D read back differs from the Layout written")
	# a re-sync of the same Layout touches nothing; an edit syncs in place
	var s0: Dictionary = Api.sync_layout(p3, lay, "gen", null, {}, true)
	_check((s0.added as PackedStringArray).is_empty() and (s0.updated as PackedStringArray).is_empty()
			and (s0.removed as PackedStringArray).is_empty(), "plan3d: re-sync changed %s" % str(s0))
	var door_node: Node = Api.owned_nodes(p3, "gen", 0)[0]
	for n: Node in Api.owned_nodes(p3, "gen", 0):
		if n.has_method("is_plan_door"):
			door_node = n
	var lay2: Resource = Layout.from_dict(lay.call("to_dict"))
	for dr: Resource in (lay2.call("floor_at", 0) as Resource).get("doors"):
		if String(dr.get("id")) == "front":
			dr.set("width_m", 1.4)
	var s1: Dictionary = Api.sync_layout(p3, lay2, "gen", null, {}, true)
	_check((s1.updated as PackedStringArray).has("front") and (s1.added as PackedStringArray).is_empty(),
			"plan3d: edit did not sync in place: %s" % str(s1))
	_check(is_instance_valid(door_node) and door_node.get_parent() != null and absf(float(door_node.get("width_m")) - 1.4) < 1e-4,
			"plan3d: the door node was replaced instead of updated")
	Api.sync_layout(p3, lay, "gen", null, {}, true)
	# the bake: the same scene
	var b2: Node3D = Baker.build(d2, kit, null, "A")
	var b3: Node3D = Baker.build(d3, kit, null, "B")
	_check(_walk(b2).size() == _walk(b3).size(), "plan3d: bake %d vs %d nodes" % [_walk(b2).size(), _walk(b3).size()])
	b2.free()
	b3.free()
	# the 3D nodes are what the plan says they are
	var shape3: Node = null
	var wall3: Node = null
	for n: Node in Api.plan_nodes(p3).map(func(it: Array) -> Node: return it[0]):
		if n.has_method("is_plan_shape") and shape3 == null:
			shape3 = n
		if n.has_method("is_plan_wall"):
			wall3 = n
	_check(shape3 is CSGPolygon3D and wall3 is Path3D, "plan3d: node kinds")
	if wall3 != null:
		var pts: PackedVector2Array = wall3.get("points")
		_check(pts.size() == 3 and (wall3.get("curve") as Curve3D).point_count == 3, "plan3d: wall points ↔ curve")
	if shape3 != null:
		var b: Basis = (shape3 as Node3D).basis
		_check(absf(b.y.z - 1.0) < 1e-4, "plan3d: shape not tilted flat (local Y → +Z), got %s" % str(b.y))
	# convert: 2D → 3D → 2D keeps nodes, names, metas and the plan
	var c3: Node = Api.convert_plan(p2, true)
	root.add_child(c3)
	_check(Api.is_plan_3d(c3), "plan3d: convert made no 3D plan")
	_check(Layout.equal(Api.read_layout(c3), r2, 0.011, true), "plan3d: convert 2D→3D differs")
	_check(_plan_names(c3) == _plan_names(p2), "plan3d: convert lost names/order: %s vs %s" % [_plan_names(c3), _plan_names(p2)])
	var c2: Node = Api.convert_plan(c3, false)
	root.add_child(c2)
	_check(not Api.is_plan_3d(c2) and Layout.equal(Api.read_layout(c2), r2, 0.011, true), "plan3d: convert 3D→2D differs")
	var fc1: Node = c3.call("level_container", 1)
	_check(fc1 != null and int(fc1.get("roof")) == 2, "plan3d: convert lost the floor roof")
	# save, reload: the preview is not part of the scene
	var path := "user://floorplan_verify_plan3d.tscn"
	var err: Error = Api.save_plan(p3, path)
	_check(err == OK, "plan3d: save %s" % error_string(err))
	if err == OK:
		var again: Node = Api.open_plan(path)
		_check(again != null and Api.is_plan_3d(again), "plan3d: reopened plan is not a 3D plan")
		if again != null:
			root.add_child(again)
			_check(_walk(again).size() == _walk(p3).size(), "plan3d: reload %d nodes vs %d" % [_walk(again).size(), _walk(p3).size()])
			_check(_same_data(again.call("plan_data"), d3, 0.6), "plan3d: reloaded plan_data differs")
			again.free()
	p2.free()
	p3.free()
	c3.free()
	c2.free()
	_done("plan3d suite done")


## Two floors: a plate with a walled room inside, a free polygon, a drawn wall, a door, a
## prop, a stair; the floor above with a roof override.
func _twin_layout() -> Resource:
	var lay: Resource = Layout.new()
	var plate: Resource = lay.call("shape", "plate", 0)
	plate.set("kind", 1)
	plate.set("size", Vector2(14.0, 8.0))
	plate.set("center", Vector2(7.0, 4.0))
	var rm: Resource = lay.call("shape", "room", 0)
	rm.set("kind", 1)
	rm.set("room", true)
	rm.set("size", Vector2(5.0, 4.0))
	rm.set("center", Vector2(3.0, 2.5))
	rm.set("rotation", 0.3)
	var free: Resource = lay.call("shape", "wing", 0)
	free.set("kind", 0)
	free.set("polygon", PackedVector2Array([Vector2(-1, -1), Vector2(3, -1), Vector2(3, 2), Vector2(0, 2), Vector2(0, 1), Vector2(-1, 1)]))
	free.set("center", Vector2(12.0, 9.0))
	# an ACTIVITY AREA inside the room: a region only — no floor, no walls of its own
	var area: Resource = lay.call("shape", "sleep", 0)
	area.set("kind", 1)
	area.set("room", true)
	area.set("walled", false)
	area.set("floored", false)
	area.set("size", Vector2(2.0, 1.6))
	area.set("center", Vector2(2.4, 2.0))
	var w: Resource = lay.call("wall", "party", 0)
	w.set("points", PackedVector2Array([Vector2(8.0, 0.0), Vector2(8.0, 5.0), Vector2(11.0, 5.0)]))
	var d: Resource = lay.call("door", "front", 0)
	d.set("position", Vector2(7.0, 7.9))
	d.set("width_m", 2.0)
	var pr: Resource = lay.call("prop", "bed_1", 0)
	pr.set("legend_key", "bed")
	pr.set("position", Vector2(10.0, 2.0))
	pr.set("rotation", 1.2)
	pr.set("size_m", Vector2(2.0, 1.4))
	var st: Resource = lay.call("stair", "up", 0)
	st.set("position", Vector2(2.0, 6.5))
	st.set("rotation", 0.0)
	st.set("width_m", 1.2)
	var up: Resource = lay.call("shape", "plate1", 1)
	up.set("kind", 1)
	up.set("size", Vector2(12.0, 8.0))
	up.set("center", Vector2(6.0, 4.0))
	(lay.call("floor_at", 1) as Resource).set("roof", 2)
	return lay


## plan_data of two plans is the same to `eps` px: floors, islands, walls, doors, props, stairs.
func _same_data(a: Dictionary, b: Dictionary, eps: float) -> bool:
	if (a.levels as Array).size() != (b.levels as Array).size():
		return false
	for i in (a.levels as Array).size():
		var la: Dictionary = a.levels[i]
		var lb: Dictionary = b.levels[i]
		if int(la.roof) != int(lb.roof) or (la.islands as Array).size() != (lb.islands as Array).size():
			_say("  plan_data: level %d roof/islands differ" % i)
			return false
		for j in (la.islands as Array).size():
			if not _pts_same(la.islands[j].outer, lb.islands[j].outer, eps):
				_say("  plan_data: level %d island %d differs" % [i, j])
				return false
		for key in ["walls", "doors", "props", "stairs"]:
			var xa: Array = la[key]
			var xb: Array = lb[key]
			if xa.size() != xb.size():
				_say("  plan_data: level %d %s count %d vs %d" % [i, key, xa.size(), xb.size()])
				return false
			for j in xa.size():
				var ea: Dictionary = xa[j]
				var eb: Dictionary = xb[j]
				for k in ea:
					if not eb.has(k):
						return false
					var va: Variant = ea[k]
					var vb: Variant = eb[k]
					var same := true
					if va is PackedVector2Array:
						same = _pts_same(va, vb, eps)
					elif va is Vector2:
						same = (va as Vector2).distance_to(vb) <= eps
					elif va is float:
						same = absf(float(va) - float(vb)) <= 0.01
					else:
						same = va == vb
					if not same:
						_say("  plan_data: level %d %s[%d].%s: %s vs %s" % [i, key, j, k, str(va), str(vb)])
						return false
	return true


func _pts_same(a: PackedVector2Array, b: PackedVector2Array, eps: float) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > eps:
			return false
	return true


func _plan_names(plan: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for item: Array in Api.plan_nodes(plan):
		out.append(String((item[0] as Node).name))
	return out


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(msg: String) -> void:
	_suites_done += 1
	_say("[VERIFY] " + msg)


func _say(msg: String) -> void:
	print(msg)
	_log += msg + "\n"
