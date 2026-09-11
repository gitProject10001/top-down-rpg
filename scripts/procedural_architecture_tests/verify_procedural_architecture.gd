extends SceneTree
## Headless verification for the floorplan façade and addons/procedural_architecture. Run:
##   Godot_console.exe --headless --path . --script res://scripts/procedural_architecture_tests/verify_procedural_architecture.gd --log-file <fresh path>
## Non-zero exit on any failure. Results also in user://verify_procedural_architecture.txt.
## Same crash-detection idiom as verify_floorplan.gd: a suite that dies unwinds silently, so the
## suite count is checked at the end.

const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Layout := preload("res://addons/floorplan/api/plan_layout.gd")
const Baker := preload("res://addons/floorplan/core/plan_baker.gd")
const Kit := preload("res://addons/floorplan/data/blockout_kit.gd")
const Legend := preload("res://addons/floorplan/data/plan_legend.gd")
const LegendEntry := preload("res://addons/floorplan/data/plan_legend_entry.gd")
const PlanRootScript := preload("res://addons/floorplan/nodes/plan_root.gd")
const PlanLevelScript := preload("res://addons/floorplan/nodes/plan_level.gd")
const PlanShapeScript := preload("res://addons/floorplan/nodes/plan_shape.gd")
const PlanStairScript := preload("res://addons/floorplan/nodes/plan_stair.gd")
const PlanDoorScript := preload("res://addons/floorplan/nodes/plan_door.gd")

const EXPECTED_SUITES := 16
const Drafter := preload("res://addons/procedural_architecture/core/drafter.gd")
const Draft := preload("res://addons/procedural_architecture/core/draft.gd")
const Contract := preload("res://addons/procedural_architecture/core/contract.gd")
const Host := preload("res://addons/procedural_architecture/core/module_host.gd")
const DesignState := preload("res://addons/procedural_architecture/core/design_state.gd")
const RoomBrief := preload("res://addons/procedural_architecture/modules/room/contract/room_brief.gd")
const RectOverlay := preload("res://addons/procedural_architecture/editor/rect_overlay.gd")
const CellOverlay := preload("res://addons/procedural_architecture/editor/cell_overlay.gd")
const SiteBrief := preload("res://addons/procedural_architecture/modules/site/contract/site_brief.gd")
const ADDON := "res://addons/procedural_architecture"
const STUB_OK := """extends RefCounted
func id(): return "stub"
func level(): return 2
func title(): return "Stub"
func input_contract(): return preload("res://addons/procedural_architecture/modules/room/contract/room_brief.gd")
func output_contract(): return preload("res://addons/procedural_architecture/core/draft.gd")
func default_brief(_c): return null
func design(_b, _c): return {}
func extract(_p, _c): return []
func make_dock(_cb): return null
func make_overlay(): return null
"""
const STUB_BAD := """extends RefCounted
func id(): return "stub"
func level(): return 2
func title(): return "Stub"
func input_contract(): return preload("res://addons/procedural_architecture/modules/room/contract/room_brief.gd")
func output_contract(): return preload("res://addons/procedural_architecture/modules/room/contract/room_brief.gd")
func default_brief(_c): return null
func design(_b, _c): return {}
func extract(_p, _c): return []
func make_dock(_cb): return null
func make_overlay(): return null
"""

var _fails: Array[String] = []
var _log := ""
var _suites_done := 0


func _initialize() -> void:
	await _facade_suite()
	await _bake_equivalence_suite()
	await _ownership_suite()
	await _pipeline_suite()
	_discovery_suite()
	_encapsulation_suite()
	await _room_suite()
	await _chain_suite()
	_sync_suite()
	_hierarchy_suite()
	_overrides_suite()
	_extract_suite()
	_preview_suite()
	_drafter_suite()
	_plan3d_suite()
	_groups_suite()

	if _suites_done != EXPECTED_SUITES:
		_fails.append("only %d of %d suites reported done — one crashed silently"
				% [_suites_done, EXPECTED_SUITES])
	var f := FileAccess.open("user://verify_procedural_architecture.txt", FileAccess.WRITE)
	if f:
		f.store_string(_log)
	if _fails.is_empty():
		_say("[VERIFY] PROCEDURAL ARCHITECTURE PASS")
		quit(0)
	else:
		for line in _fails:
			_say("[VERIFY] FAIL: " + line)
		quit(1)


# ---------------------------------------------------------------- 1. façade round trip --------


## A two-floor Layout of every element kind, written as nodes, read back equal; saved and
## reopened equal; to_dict / from_dict equal.
func _sample_layout() -> Resource:
	var lay: Resource = Layout.new()
	var plate: Resource = lay.shape("Plate", 0)
	plate.size = Vector2(14.0, 8.0)
	plate.center = Vector2(7.0, 4.0)
	var room: Resource = lay.shape("Room", 0)
	room.room = true
	room.size = Vector2(4.0, 3.0)
	room.center = Vector2(3.0, 2.5)
	var cut: Resource = lay.shape("Cut", 0)
	cut.kind = 2
	cut.op = 1
	cut.radius = 0.5
	cut.segments = 16
	cut.center = Vector2(10.0, 6.0)
	var poly: Resource = lay.shape("Poly", 0)
	poly.kind = 0
	poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(0, 1.5)])
	poly.center = Vector2(12.0, 2.0)
	poly.rotation = 0.3
	var wall: Resource = lay.wall("W", 0)
	wall.points = PackedVector2Array([Vector2(6.0, 1.0), Vector2(6.0, 4.0)])
	var door: Resource = lay.door("D", 0)
	door.position = Vector2(5.0, 3.0)
	door.width_m = 1.0
	var bed: Resource = lay.prop("bed_1", 0)
	bed.legend_key = "bed"
	bed.position = Vector2(2.0, 2.0)
	bed.rotation = PI * 0.5
	bed.size_m = Vector2(2.0, 1.4)
	bed.shape = 1
	var st: Resource = lay.stair("S", 0)
	st.position = Vector2(3.0, 6.0)
	st.width_m = 1.2
	var plate1: Resource = lay.shape("Plate1", 1)
	plate1.size = Vector2(14.0, 8.0)
	plate1.center = Vector2(7.0, 4.0)
	lay.floor_at(1).roof = 2
	return lay


func _facade_suite() -> void:
	var lay := _sample_layout()
	_check((lay.validate() as PackedStringArray).is_empty(), "facade: sample layout invalid: %s" % str(lay.validate()))
	var plan: Node2D = Api.new_plan("Test")
	root.add_child(plan)
	var res: Dictionary = Api.write_layout(plan, lay, "t")
	_check((res.warnings as PackedStringArray).is_empty(), "facade: warnings %s" % str(res.warnings))
	_check((res.added as PackedStringArray).size() == 9, "facade: added %d, want 9" % (res.added as PackedStringArray).size())
	_check(plan.has_node("Floor_0/Room") and plan.has_node("Floor_1/Plate1"), "facade: nodes not under Floor_i containers")
	var owned := true
	var tagged := true
	for n: Node in _walk(plan):
		if n.owner != plan:
			owned = false
		if n.has_method("is_plan_shape") and String(n.get_meta("plan_owner", "")) != "t":
			tagged = false
	_check(owned, "facade: a written node is not owned by the root")
	_check(tagged, "facade: a written shape lacks the owner meta")
	var back: Resource = Api.read_layout(plan, "t")
	_check(Layout.equal(lay, back, 1e-4), "facade: read_layout differs from what was written\n%s\n%s" % [str(lay.to_dict()), str(back.to_dict())])
	var d: Dictionary = lay.to_dict()
	var again: Resource = Layout.from_dict(d)
	_check(Layout.equal(lay, again, 1e-6), "facade: to_dict/from_dict differs")
	# the plan on disk and back
	var path := "user://pa_facade_plan.tscn"
	var err: Error = Api.save_plan(plan, path)
	_check(err == OK, "facade: save_plan %s" % error_string(err))
	var opened: Node2D = Api.open_plan(path)
	_check(opened != null, "facade: open_plan returned null")
	if opened != null:
		root.add_child(opened)
		var back2: Resource = Api.read_layout(opened, "t")
		_check(Layout.equal(lay, back2, 1e-4), "facade: layout differs after save/open")
		_check(int(opened.call("level_container", 1).get("roof")) == 2, "facade: floor 1 roof override lost on disk")
		opened.free()
	# a single-floor layout keeps floor 0 loose (no container)
	var one: Resource = Layout.new()
	var s: Resource = one.shape("A", 0)
	s.center = Vector2(2, 2)
	var plan1: Node2D = Api.new_plan("One")
	root.add_child(plan1)
	Api.write_layout(plan1, one, "t")
	_check(plan1.has_node("A") and plan1.call("level_container", 0) == null, "facade: single-floor layout should stay loose")
	plan1.free()
	plan.free()
	_done("facade suite done")


# ---------------------------------------------------------------- 2. bake equivalence ---------


## The regions fixture of verify_floorplan, once by hand and once through the façade: the same
## plan_data and the same CSG blockout.
func _bake_equivalence_suite() -> void:
	var kit := Kit.new()
	var legend := Legend.new()
	for k in ["door", "stair"]:
		var row := LegendEntry.new()
		row.key = k
		(legend.get("entries") as Array).append(row)
	# by hand
	var hand := PlanRootScript.new()
	hand.kit = kit
	hand.legend = legend
	root.add_child(hand)
	var f0 := PlanLevelScript.new()
	f0.name = "Floor_0"
	f0.index = 0
	hand.add_child(f0)
	var plate := PlanShapeScript.new()
	plate.name = "Plate"
	plate.kind = 1
	plate.size = Vector2(1400, 800)
	plate.position = Vector2(700, 400)
	f0.add_child(plate)
	var room := PlanShapeScript.new()
	room.name = "Room"
	room.kind = 1
	room.room = true
	room.size = Vector2(400, 300)
	room.position = Vector2(300, 250)
	f0.add_child(room)
	var inner := PlanShapeScript.new()
	inner.name = "Inner"
	inner.kind = 1
	inner.room = true
	inner.size = Vector2(150, 120)
	inner.position = Vector2(230, 200)
	f0.add_child(inner)
	var door := PlanDoorScript.new()
	door.name = "D"
	door.position = Vector2(500, 300)
	door.width_m = 1.0
	f0.add_child(door)
	var entrance := PlanDoorScript.new()
	entrance.name = "E"
	entrance.position = Vector2(5, 600)
	entrance.width_m = 1.2
	f0.add_child(entrance)
	var st := PlanStairScript.new()
	st.name = "S"
	st.position = Vector2(300, 600)
	f0.add_child(st)
	var f1 := PlanLevelScript.new()
	f1.name = "Floor_1"
	f1.index = 1
	hand.add_child(f1)
	var plate1 := PlanShapeScript.new()
	plate1.name = "Plate1"
	plate1.kind = 1
	plate1.size = Vector2(1400, 800)
	plate1.position = Vector2(700, 400)
	f1.add_child(plate1)
	# through the façade
	var lay: Resource = Layout.new()
	var lp: Resource = lay.shape("Plate", 0)
	lp.size = Vector2(14, 8)
	lp.center = Vector2(7, 4)
	var lr: Resource = lay.shape("Room", 0)
	lr.room = true
	lr.size = Vector2(4, 3)
	lr.center = Vector2(3, 2.5)
	var li: Resource = lay.shape("Inner", 0)
	li.room = true
	li.size = Vector2(1.5, 1.2)
	li.center = Vector2(2.3, 2.0)
	var ld: Resource = lay.door("D", 0)
	ld.position = Vector2(5, 3)
	ld.width_m = 1.0
	var le: Resource = lay.door("E", 0)
	le.position = Vector2(0.05, 6)
	le.width_m = 1.2
	var ls: Resource = lay.stair("S", 0)
	ls.position = Vector2(3, 6)
	var lp1: Resource = lay.shape("Plate1", 1)
	lp1.size = Vector2(14, 8)
	lp1.center = Vector2(7, 4)
	var api_plan: Node2D = Api.new_plan("Api", kit, legend)
	root.add_child(api_plan)
	Api.write_layout(api_plan, lay, "t")
	var da: Dictionary = hand.plan_data()
	var db: Dictionary = api_plan.call("plan_data")
	da.erase("source")
	db.erase("source")
	_check(_same(da, db, 1e-3), "equivalence: plan_data differs\n%s\n%s" % [str(da.levels), str(db.levels)])
	var ba: Node3D = Baker.build(da, kit, legend, "Fix")
	var bb: Node3D = Baker.build(db, kit, legend, "Fix")
	var wa := _walk(ba)
	var wb := _walk(bb)
	_check(wa.size() == wb.size(), "equivalence: bake node count %d vs %d" % [wa.size(), wb.size()])
	var same := wa.size() == wb.size()
	for i in mini(wa.size(), wb.size()):
		var x: Node = wa[i]
		var y: Node = wb[i]
		if x.name != y.name or x.get_class() != y.get_class():
			same = false
			_check(false, "equivalence: node %d %s/%s vs %s/%s" % [i, x.name, x.get_class(), y.name, y.get_class()])
			break
		if x is Node3D and not (x as Node3D).transform.is_equal_approx((y as Node3D).transform):
			same = false
			_check(false, "equivalence: transform differs on %s" % x.name)
			break
		if x is CSGPolygon3D and not _same((x as CSGPolygon3D).polygon, (y as CSGPolygon3D).polygon, 1e-4):
			same = false
			_check(false, "equivalence: polygon differs on %s" % x.name)
			break
	_check(same, "equivalence: the two bakes differ")
	ba.free()
	bb.free()
	hand.free()
	api_plan.free()
	_done("bake equivalence suite done")


# ---------------------------------------------------------------- 3. ownership ----------------


func _ownership_suite() -> void:
	var lay := _sample_layout()
	var plan: Node2D = Api.new_plan("Own")
	root.add_child(plan)
	Api.write_layout(plan, lay, "t")
	var names1 := _plan_names(plan)
	var r2: Dictionary = Api.write_layout(plan, lay, "t")
	var names2 := _plan_names(plan)
	_check(names1 == names2, "ownership: a second write changed the node set %s vs %s" % [str(names1), str(names2)])
	_check((r2.removed as PackedStringArray).size() == 9, "ownership: second write removed %d, want 9" % (r2.removed as PackedStringArray).size())
	# a hand-drawn shape beside them survives
	var hand := PlanShapeScript.new()
	hand.name = "Hand"
	hand.position = Vector2(900, 300)
	plan.get_node("Floor_0").add_child(hand)
	hand.owner = plan
	Api.write_layout(plan, lay, "t")
	_check(plan.has_node("Floor_0/Hand"), "ownership: the hand-drawn shape was removed by a re-run")
	# another owner's node on the same floor is kept, this owner's are cleared
	var other: Resource = Layout.new()
	var o: Resource = other.shape("Other", 0)
	o.center = Vector2(9, 5)
	Api.write_layout(plan, other, "u")
	_check(plan.has_node("Floor_0/Other") and plan.has_node("Floor_0/Room"), "ownership: two owners cannot share a floor")
	var n := Api.clear_owned(plan, "t")
	_check(n == 9, "ownership: clear_owned removed %d, want 9" % n)
	_check(plan.has_node("Floor_0/Other") and plan.has_node("Floor_0/Hand") and not plan.has_node("Floor_0/Room"),
			"ownership: clear_owned touched the wrong nodes")
	_check(Api.owned_nodes(plan, "u").size() == 1 and Api.owned_nodes(plan, "t").is_empty(), "ownership: owned_nodes wrong")
	# an id that clashes with a foreign node gets a unique name and a warning-free result
	var clash: Resource = Layout.new()
	var c: Resource = clash.shape("Hand", 0)
	c.center = Vector2(1, 1)
	var rc: Dictionary = Api.write_layout(plan, clash, "t")
	_check((rc.added as PackedStringArray).size() == 1 and String(rc.added[0]) != "Hand", "ownership: a clashing id should be renamed, got %s" % str(rc.added))
	plan.free()
	_done("ownership suite done")


# ---------------------------------------------------------------- 4. pipeline -----------------


func _pipeline_suite() -> void:
	var lay := _sample_layout()
	var plan: Node2D = Api.new_plan("Pipe")
	root.add_child(plan)
	Api.write_layout(plan, lay, "t")
	var info: Dictionary = Api.kit_info(plan)
	_check(absf(float(info.wall_thickness) - 0.5) < 1e-6 and float(info.ppm) == 100.0, "pipeline: kit_info wrong %s" % str(info))
	_check(Api.legend_keys(plan).has("bed"), "pipeline: legend_keys lacks bed")
	var path := "user://pa_pipe_3d.tscn"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var res: Dictionary = Api.bake(plan, path)
	_check(int(res.error) == OK and FileAccess.file_exists(path), "pipeline: bake %s" % error_string(int(res.error)))
	_check(int(res.levels) == 2 and int(res.rooms) >= 2, "pipeline: bake counts %s" % str(res))
	var again: Dictionary = Api.bake(plan, path)
	_check(int(again.error) == ERR_ALREADY_EXISTS, "pipeline: bake should refuse an existing file")
	var bk: Node3D = Api.build(plan)
	root.add_child(bk)
	var ops: Array = await Api.finalize(bk, self)
	_check(not ops.is_empty(), "pipeline: finalize produced no ops")
	var bodies := 0
	var csg_rooms := 0
	for n: Node in _walk(bk):
		if n is StaticBody3D and n.has_meta("floorplan_wall"):
			bodies += 1
		if n is CSGCombiner3D and String(n.name).begins_with("Room_"):
			csg_rooms += 1
	_check(bodies > 0 and csg_rooms == 0, "pipeline: finalize left %d CSG rooms, made %d wall bodies" % [csg_rooms, bodies])
	# apply assets: give the bed row a scene, the greybox is swapped
	var legend: Resource = Api.legend(plan)
	var row: Resource = legend.call("find", "bed")
	var scene_root := Node3D.new()
	scene_root.name = "BedScene"
	var ps := PackedScene.new()
	ps.pack(scene_root)
	scene_root.free()
	row.set("scene", ps)
	var aops: Array = Api.apply_assets(bk, legend, Api.kit(plan))
	_check(not aops.is_empty(), "pipeline: apply_assets produced no ops")
	bk.free()
	plan.free()
	_done("pipeline suite done")


# ---------------------------------------------------------------- 5. discovery + chain --------


func _discovery_suite() -> void:
	var d: Dictionary = Host.discover()
	var ids := PackedStringArray()
	for m: Object in d.modules:
		ids.append(String(m.call("id")))
	_check(ids == PackedStringArray(["room", "zone", "storey", "structure", "site"]), "discovery: modules %s" % str(ids))
	_check((d.problems as PackedStringArray).is_empty(), "discovery: problems %s" % str(d.problems))
	for id in ids:
		_check(bool((d.enabled as Dictionary).get(id, false)), "discovery: %s disabled" % id)
	var levels := PackedInt32Array()
	for m: Object in d.modules:
		levels.append(int(m.call("level")))
	_check(levels == PackedInt32Array([2, 3, 4, 5, 6]), "discovery: levels %s" % str(levels))
	# every module answers the whole interface with the right types
	for m: Object in d.modules:
		var ctx := {"ppm": 100.0, "kit": {"wall_thickness": 0.5}, "legend_keys": PackedStringArray(), "legend_sizes": {}, "floors": [0]}
		var b: Resource = m.call("default_brief", ctx)
		_check(b != null and b.get_script() == m.call("input_contract"), "discovery: %s default_brief is not its input contract" % m.call("id"))
		_check(m.call("make_overlay") != null, "discovery: %s has no overlay" % m.call("id"))
		var dock: Control = m.call("make_dock", func(_b: Resource) -> void: pass)
		_check(dock != null and dock.has_method("set_brief"), "discovery: %s dock lacks set_brief" % m.call("id"))
		if dock != null:
			dock.call("set_brief", b)
			dock.free()
	# a module that appears in a folder is found, and gone when the folder goes
	var dir := "user://pa_fake_modules"
	DirAccess.make_dir_recursive_absolute(dir + "/stub")
	var f := FileAccess.open(dir + "/stub/module.gd", FileAccess.WRITE)
	f.store_string(STUB_OK)
	f.close()
	var d2: Dictionary = Host.discover(dir)
	_check((d2.modules as Array).size() == 1 and (d2.problems as PackedStringArray).is_empty(), "discovery: stub not found: %s" % str(d2.problems))
	# a broken chain disables what sits above it
	var f2 := FileAccess.open(dir + "/stub/module.gd", FileAccess.WRITE)
	f2.store_string(STUB_BAD)
	f2.close()
	var d3: Dictionary = Host.discover(dir)
	_check(not bool((d3.enabled as Dictionary).get("stub", true)) and not (d3.problems as PackedStringArray).is_empty(), "discovery: a wrong bottom contract should disable the module")
	DirAccess.remove_absolute(dir + "/stub/module.gd")
	DirAccess.remove_absolute(dir + "/stub")
	var d4: Dictionary = Host.discover(dir)
	_check((d4.modules as Array).is_empty(), "discovery: removed module still found")
	DirAccess.remove_absolute(dir)
	_done("discovery suite done")


# ---------------------------------------------------------------- 6. encapsulation ------------


## Read every script of the addon: a module imports only the floorplan API, the addon's core and
## editor helpers, its own folder, and other modules' contracts; nobody declares a class_name.
func _encapsulation_suite() -> void:
	var files := _gd_files(ADDON)
	_check(files.size() > 10, "encapsulation: only %d scripts found" % files.size())
	var re_fp := RegEx.create_from_string("res://addons/floorplan/")
	var re_mod := RegEx.create_from_string("res://addons/procedural_architecture/modules/([a-z_]+)/([^\"]*)")
	var re_cls := RegEx.create_from_string("(?m)^class_name\\s")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if re_cls.search(text) != null:
			_check(false, "encapsulation: class_name in %s" % path)
		if not path.begins_with(ADDON + "/modules/"):
			continue
		var own := path.trim_prefix(ADDON + "/modules/").get_slice("/", 0)
		if re_fp.search(text) != null:
			_check(false, "encapsulation: %s reaches into floorplan internals" % path)
		for m in re_mod.search_all(text):
			var other := m.get_string(1)
			var rest := m.get_string(2)
			if other != own and not rest.begins_with("contract/"):
				_check(false, "encapsulation: %s imports %s/%s (not a contract)" % [path, other, rest])
	_done("encapsulation suite done")


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


# ---------------------------------------------------------------- 7. the Room designer --------


func _room_legend() -> Resource:
	var legend: Resource = Api.default_legend()
	var rows: Array = legend.get("entries")
	rows.append(Api.legend_row("pendant", Color(1, 1, 0.5), 0, Vector3(0.5, 0.3, 0.5)))
	rows.append(Api.legend_row("locker", Color(0.5, 0.5, 0.5), 1, Vector3(1.0, 2.0, 0.6)))
	return legend


func _room_suite() -> void:
	var d: Dictionary = Host.discover()
	var room: Object = Host.module_by_id(d.modules, "room")
	var plan: Node2D = Api.new_plan("RoomTest", null, _room_legend())
	root.add_child(plan)
	var ctx: Dictionary = Host.context(plan)
	var b: Resource = RoomBrief.new()
	b.id = "bedroom_a"
	b.rect = Rect2(1.0, 1.0, 4.0, 3.0)
	b.role = "bedroom"
	var ents: Array[Vector2] = [Vector2(2, 0.5)]
	b.entrances = ents
	_check((b.validate() as PackedStringArray).is_empty(), "room: brief invalid %s" % str(b.validate()))
	var out: Dictionary = room.call("design", b, ctx)
	var draft: Resource = out.draft
	_check(draft != null and (draft.validate() as PackedStringArray).is_empty(), "room: draft invalid %s" % (str(draft.validate()) if draft != null else "null"))
	_check((out.children as Array).is_empty(), "room: a room has no children")
	_check((draft.regions as Array).is_empty() and (draft.openings as Array).is_empty(), "room: a room draws no outline and no door (the zone's)")
	var lay: Resource = Drafter.merge(Drafter.draft_to_layouts([{"module_id": "room", "brief": b, "draft": draft}]))
	# the outline and the door the zone would have drawn, by hand, so the bake can be checked
	var outline: Resource = lay.shape("bedroom_a", 0)
	outline.room = true
	outline.size = Vector2(4, 3)
	outline.center = Vector2(3, 2.5)
	var door: Resource = lay.door("bedroom_a_door1", 0)
	door.position = Vector2(3, 4)
	var f0: Resource = lay.floor_at(0)
	var bed: Resource = null
	var pendant: Resource = null
	var locker: Resource = null
	for p: Resource in f0.props:
		match String(p.legend_key):
			"bed": bed = p
			"pendant": pendant = p
			"locker": locker = p
	_check(bed != null, "room: no bed placed (%s)" % str(out.warnings))
	if bed != null:
		var half: Vector2 = (bed.size_m as Vector2) * 0.5
		var pos: Vector2 = bed.position
		_check(pos.y - half.y >= 1.0 and pos.x - half.x >= 1.0 and pos.x + half.x <= 5.0, "room: bed footprint leaves the rect: %s %s" % [str(pos), str(bed.size_m)])
		_check(pos.y < 2.5, "room: bed should stand on the wall opposite the door, is at y %.2f" % pos.y)
		_check((pos + Vector2(0, half.y)).distance_to(Vector2(3, 4)) >= 0.6, "room: bed within 0.6 m of the door")
	_check(pendant != null and pendant.position.is_equal_approx(Vector2(3, 2.5)), "room: pendant not at the centre")
	_check(locker != null, "room: no locker in the corner (%s)" % str(out.warnings))
	# deterministic
	var out2: Dictionary = room.call("design", b, ctx)
	_check((out2.draft as Resource).to_dict() == draft.to_dict(), "room: two runs differ")
	# THE USER'S HAND: a placement moves that fixture only, clamped to the room; an extra
	# appears with its legend size at the centre; a removal drops one; still deterministic
	var bh: Resource = b.duplicate(true)
	bh.placements = {"bed1": {"position": Vector2(4.2, 1.4), "rotation": 0.3}}
	var outh: Dictionary = room.call("design", bh, ctx)
	var fh: Array = (outh.draft as Resource).fixtures
	var moved_bed: Dictionary = {}
	var same_rest := true
	for f: Dictionary in fh:
		if String(f.id) == "bed1":
			moved_bed = f
		else:
			var found := false
			for g: Dictionary in draft.fixtures:
				if String(g.id) == String(f.id) and (g.position as Vector2).is_equal_approx(f.position):
					found = true
			same_rest = same_rest and found
	_check(not moved_bed.is_empty() and same_rest, "room: placement touched other fixtures")
	if not moved_bed.is_empty():
		var half: Vector2 = (moved_bed.size_m as Vector2) * 0.5
		var pos: Vector2 = moved_bed.position
		_check(absf(float(moved_bed.rotation) - 0.3) < 1e-6 and pos.x + half.x <= 5.0 + 1e-6 and pos.x > 3.5, "room: placement not applied / clamped: %s rot %.2f" % [str(pos), float(moved_bed.rotation)])
	var be: Resource = b.duplicate(true)
	be.extra = PackedStringArray(["table"])
	be.removed = PackedStringArray(["pendant"])
	var oute: Dictionary = room.call("design", be, ctx)
	var extra_found: Dictionary = {}
	var pendant_found := false
	for f: Dictionary in (oute.draft as Resource).fixtures:
		if String(f.id) == "extra1":
			extra_found = f
		if String(f.id) == "pendant":
			pendant_found = true
	_check(not extra_found.is_empty() and String(extra_found.key) == "table" and (extra_found.position as Vector2).is_equal_approx(Vector2(3, 2.5)),
			"room: extra table missing or misplaced (%s)" % str(extra_found))
	_check(not pendant_found, "room: removed pendant still placed")
	var oute2: Dictionary = room.call("design", be, ctx)
	_check((oute2.draft as Resource).to_dict() == (oute.draft as Resource).to_dict(), "room: the user's hand is not deterministic")
	# the overlay: a click INSIDE a cell activates it (the smallest cell under the pointer)
	var ov: RefCounted = CellOverlay.new("rect")
	var r_zone: Resource = RoomBrief.new()
	r_zone.id = "big"
	r_zone.rect = Rect2(0, 0, 12, 9)
	var octx := {"xf": Transform2D(0.0, Vector2.ZERO), "ppm": 100.0, "brief": r_zone, "briefs": [r_zone, b], "floor": 0}
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300, 250)     # inside bedroom_a (1..5 × 1..4 m) and inside big
	ov.gui_input(press, octx)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(300, 250)
	var res_click: Dictionary = ov.gui_input(release, octx)
	_check(String(res_click.get("activate", "")) == "bedroom_a", "room: a click inside a cell should activate it, got %s" % str(res_click))
	# a fixture handle drags into a placement
	octx["brief"] = b
	octx["fixtures"] = [{"id": "bed1", "position": Vector2(3.0, 1.8), "rotation": 0.0, "size_m": Vector2(2.0, 1.4), "key": "bed"}]
	press.position = Vector2(300, 180)
	var r_begin: Dictionary = ov.gui_input(press, octx)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(350, 200)
	ov.gui_input(motion, octx)
	var r_end: Dictionary = ov.gui_input(release, octx)
	_check(bool(r_begin.get("begin", false)) and bool(r_end.get("commit", false)) and (b.placements as Dictionary).has("bed1")
			and ((b.placements as Dictionary)["bed1"] as Dictionary).get("position", Vector2.ZERO).is_equal_approx(Vector2(3.5, 2.0)),
			"room: fixture drag did not write a placement (%s)" % str(b.placements))
	b.placements = {}
	# a key the legend lacks is reported, not placed
	var b2: Resource = b.duplicate(true)
	b2.role = "living"
	var out3: Dictionary = room.call("design", b2, ctx)
	var has_warning := false
	for w in out3.warnings:
		if String(w).contains("rug"):
			has_warning = true
	_check(has_warning, "room: missing rug key not reported: %s" % str(out3.warnings))
	# written and baked: 4 walls, 1 door, the bed
	Api.write_layout(plan, lay, "designer")
	var bk: Node3D = Api.build(plan)
	var walls := 0
	var doors := 0
	var bed_node := false
	for n: Node in _walk(bk):
		if String(n.name).begins_with("Wall_"):
			walls += 1
		elif String(n.name).begins_with("Door_"):
			doors += 1
		elif String(n.name).begins_with("bed"):
			bed_node = true
	_check(walls == 4 and doors == 1 and bed_node, "room: bake has %d walls, %d doors, bed %s" % [walls, doors, bed_node])
	bk.free()
	plan.free()
	_done("room suite done")


# ---------------------------------------------------------------- 8. the chain + the state -----


func _chain_suite() -> void:
	var d: Dictionary = Host.discover()
	var plan: Node2D = Api.new_plan("ChainTest", null, _room_legend())
	root.add_child(plan)
	var ctx: Dictionary = Host.context(plan)
	var site: Resource = SiteBrief.new()
	site.id = "site"
	site.lots = 1
	site.storeys = 2
	site.bounds = Rect2(0, 0, 40, 30)
	var res: Dictionary = Host.run_chain(d.modules, "site", site, ctx)
	var lay: Resource = Drafter.merge(Drafter.draft_to_layouts(res.parts))
	_check((lay.validate() as PackedStringArray).is_empty(), "chain: layout invalid %s" % str(lay.validate()))
	_check((lay.floor_indices() as Array) == [0, 1], "chain: floors %s" % str(lay.floor_indices()))
	var briefs: Dictionary = res.briefs
	_check((briefs.get("structure", []) as Array).size() == 1 and (briefs.get("storey", []) as Array).size() == 2
			and (briefs.get("zone", []) as Array).size() >= 4 and (briefs.get("room", []) as Array).size() >= 8,
			"chain: brief fan-out wrong: %s" % str(briefs.keys()))
	var fatal := false
	for w in res.warnings:
		if String(w).contains("no module") or String(w).contains("invalid"):
			fatal = true
	_check(not fatal, "chain: warnings %s" % str(res.warnings))
	var wr: Dictionary = Api.write_layout(plan, lay, "designer")
	_check((wr.warnings as PackedStringArray).is_empty() and (wr.added as PackedStringArray).size() > 20, "chain: write %s" % str(wr))
	var bk: Node3D = Api.build(plan)
	var stairs := 0
	for n: Node in _walk(bk):
		if String(n.name).begins_with("Stair_"):
			stairs += 1
	_check(bk.has_node("Level_1") and stairs == 1, "chain: bake has no Level_1 or %d stairs" % stairs)
	bk.free()
	# the state beside the plan
	var plan_path := "user://pa_chain_plan.tscn"
	var state: Resource = DesignState.load_for(plan_path)
	state.active = "site"
	state.set_knobs("site", site, true)
	state.active_ids["site"] = "site"
	_check(state.save_for(plan_path) == OK, "chain: state save failed")
	_check(DesignState.path_for(plan_path) == "user://pa_chain_plan.design.tres", "chain: path_for %s" % DesignState.path_for(plan_path))
	var back: Resource = DesignState.load_for(plan_path)
	var sb: Resource = back.knobs_of("site", "site")
	_check(sb != null and int(sb.lots) == 1 and String(back.active) == "site" and back.is_edited("site", "site"), "chain: side-car round trip lost the knobs")
	_check((back.user_overrides() as Dictionary).has("site") and back.ids_of("site") == PackedStringArray(["site"]), "chain: overrides / ids_of")
	var snap: Dictionary = back.subtree("site")
	back.replace_subtree("site", {})
	_check(back.knobs_of("site", "site") == null, "chain: replace_subtree did not drop")
	back.replace_subtree("site", snap)
	_check(back.knobs_of("site", "site") != null, "chain: replace_subtree did not restore")
	plan.free()
	_done("chain suite done")


# ---------------------------------------------------------------- 9. sync in place ------------


## The incremental write: the same Layout again touches nothing (node identity kept), a moved
## prop updates only itself, a dropped element is removed, an added one appended; with an
## UndoRedo the inverse ops restore values and identity; a hand node is adopted, not duplicated.
func _sync_suite() -> void:
	var lay := _sample_layout()
	var plan: Node2D = Api.new_plan("Sync")
	root.add_child(plan)
	var first: Dictionary = Api.sync_layout(plan, lay, "t")
	_check((first.added as PackedStringArray).size() == 9 and (first.warnings as PackedStringArray).is_empty(), "sync: first sync added %d %s" % [(first.added as PackedStringArray).size(), str(first.warnings)])
	var ids_before := _instance_ids(plan)
	var again: Dictionary = Api.sync_layout(plan, lay, "t")
	_check((again.unchanged as PackedStringArray).size() == 9 and (again.updated as PackedStringArray).is_empty()
			and (again.added as PackedStringArray).is_empty() and (again.removed as PackedStringArray).is_empty(),
			"sync: same layout again: %s" % str(again))
	_check(_instance_ids(plan) == ids_before, "sync: node identity changed on an unchanged sync")
	_check(Layout.equal(lay, Api.read_layout(plan, "t"), 1e-4), "sync: read back differs")
	# one prop moved: only it is updated, to the same px the wholesale write would give
	var moved: Resource = Layout.from_dict(lay.to_dict())
	var bed: Resource = (moved.floor_at(0).get("props") as Array)[0]
	bed.position = Vector2(2.5, 2.25)
	var r2: Dictionary = Api.sync_layout(plan, moved, "t")
	_check(r2.updated == PackedStringArray(["bed_1"]) and (r2.unchanged as PackedStringArray).size() == 8, "sync: moved prop: %s" % str(r2))
	_check((plan.get_node("Floor_0/bed_1") as Node2D).position == Vector2(250, 225), "sync: moved prop position %s" % str((plan.get_node("Floor_0/bed_1") as Node2D).position))
	_check(_instance_ids(plan) == ids_before, "sync: node identity changed on an update")
	# a dropped element goes, an added one comes, the rest untouched
	var less: Resource = Layout.from_dict(moved.to_dict())
	(less.floor_at(0).get("walls") as Array).clear()
	var extra: Resource = less.prop("lamp", 0)
	extra.legend_key = "pillar"
	extra.position = Vector2(9, 5)
	var r3: Dictionary = Api.sync_layout(plan, less, "t")
	_check(r3.removed == PackedStringArray(["W"]) and r3.added == PackedStringArray(["lamp"]) and (r3.unchanged as PackedStringArray).size() == 8, "sync: drop/add: %s" % str(r3))
	_check(not plan.has_node("Floor_0/W") and plan.has_node("Floor_0/lamp"), "sync: tree does not match drop/add")
	# a wrong-kind node for an id is replaced
	var kind: Resource = Layout.from_dict(less.to_dict())
	var lamp_shape: Resource = kind.shape("lamp", 0)
	lamp_shape.center = Vector2(9, 5)
	(kind.floor_at(0).get("props") as Array).pop_back()
	var r4: Dictionary = Api.sync_layout(plan, kind, "t")
	_check(r4.removed == PackedStringArray(["lamp"]) and r4.added == PackedStringArray(["lamp"]) and plan.get_node("Floor_0/lamp").has_method("is_plan_shape"), "sync: kind change: %s" % str(r4))
	# undo: every op inverse — values and identity
	var undo := FakeUndo.new()
	var before_pos: Vector2 = (plan.get_node("Floor_0/bed_1") as Node2D).position
	var back: Resource = Layout.from_dict(kind.to_dict())
	((back.floor_at(0).get("props") as Array)[0] as Resource).position = Vector2(1, 1)
	(back.floor_at(0).get("shapes") as Array).pop_back()   # lamp shape dropped
	var w2: Resource = back.wall("W2", 0)
	w2.points = PackedVector2Array([Vector2(7, 1), Vector2(7, 3)])
	undo.create_action("sync")
	var r5: Dictionary = Api.sync_layout(plan, back, "t", undo)
	undo.commit_action()
	var bed_node := plan.get_node("Floor_0/bed_1") as Node2D
	_check(bed_node.position == Vector2(100, 100) and not plan.has_node("Floor_0/lamp") and plan.has_node("Floor_0/W2"), "sync: undo-able sync did not apply %s" % str(r5))
	undo.undo()
	_check(is_instance_valid(bed_node) and bed_node.position == before_pos and plan.has_node("Floor_0/lamp") and not plan.has_node("Floor_0/W2"), "sync: undo did not restore")
	undo.redo()
	_check(bed_node.position == Vector2(100, 100) and plan.has_node("Floor_0/W2"), "sync: redo did not reapply")
	# adopt a hand-drawn shape: renamed and tagged, never duplicated
	var hand := PlanShapeScript.new()
	hand.name = "Drawn"
	hand.kind = 1
	hand.room = true
	hand.size = Vector2(300, 200)
	hand.position = Vector2(1100, 600)
	plan.get_node("Floor_0").add_child(hand)
	hand.owner = plan
	var adopt_lay: Resource = Layout.new()
	var ad: Resource = adopt_lay.shape("zone_q_room", 0)
	ad.room = true
	ad.size = Vector2(3, 2)
	ad.center = Vector2(11, 6)
	var r6: Dictionary = Api.sync_layout(plan, adopt_lay, "zone_q", null, {}, false, {"zone_q_room": hand})
	_check(r6.unchanged == PackedStringArray(["zone_q_room"]) and hand.name == "zone_q_room" and String(hand.get_meta("plan_owner", "")) == "zone_q",
			"sync: adopt: %s name %s" % [str(r6), hand.name])
	_check(Api.owned_nodes(plan, "zone_q").size() == 1, "sync: adopted node not owned")
	plan.free()
	_done("sync suite done")


# ---------------------------------------------------------------- 10. hierarchical owners -----


## Owners nest by `_`: the chain's parts synced each under its brief's id; a prefix addresses a
## subtree exactly; re-running one room leaves every other node's identity; `keep` spares tags.
func _hierarchy_suite() -> void:
	var d: Dictionary = Host.discover()
	var plan: Node2D = Api.new_plan("Hier", null, _room_legend())
	root.add_child(plan)
	var ctx: Dictionary = Host.context(plan)
	var site: Resource = SiteBrief.new()
	site.id = "site"
	site.lots = 1
	site.storeys = 2
	site.bounds = Rect2(0, 0, 40, 30)
	var res: Dictionary = Host.run_chain(d.modules, "site", site, ctx)
	_check(res.has("parts"), "hierarchy: run_chain has no parts")
	Drafter.write(plan, res.parts, "site")
	var all := Api.plan_nodes(plan).size()
	var sub := Api.owned_nodes(plan, "site_S1", -1, true).size()
	var f0 := Api.owned_nodes(plan, "site_S1_F0", -1, true).size()
	var f1 := Api.owned_nodes(plan, "site_S1_F1", -1, true).size()
	_check(all > 40 and sub == all, "hierarchy: %d nodes, %d under site_S1" % [all, sub])
	_check(f0 + f1 + Api.owned_nodes(plan, "site_S1").size() == all, "hierarchy: floors %d + %d + structure %d != %d" % [f0, f1, Api.owned_nodes(plan, "site_S1").size(), all])
	_check(Api.owned_nodes(plan, "site_S1_F", -1, true).is_empty(), "hierarchy: prefix must respect the id boundary")
	# re-run one room: only its nodes may change identity
	var room_brief: Resource = null
	for part: Dictionary in res.parts:
		if String(part.module_id) == "room":
			room_brief = part.brief
			break
	var rid := String(room_brief.get("id"))
	var others := {}
	for item: Array in Api.plan_nodes(plan):
		var n: Node = item[0]
		if not Api._owner_match(String(n.get_meta("plan_owner", "")), rid, true):
			others[n.get_instance_id()] = true
	var rb: Resource = room_brief.duplicate(true)
	rb.rect = (rb.rect as Rect2).grow(-0.2)
	var one: Dictionary = Host.run_chain(d.modules, "room", rb, ctx)
	Drafter.write(plan, one.parts, rid, null, Host.survey(plan))
	var kept := 0
	for item: Array in Api.plan_nodes(plan):
		if others.has((item[0] as Node).get_instance_id()):
			kept += 1
	_check(kept == others.size(), "hierarchy: re-running one room lost %d other nodes" % (others.size() - kept))
	_check(Api.read_layout(plan, rid, true).floor_at(int(rb.floor)).props.size() >= 1, "hierarchy: read_layout by prefix (the room's fixtures)")
	# keep spares tags on a prefix clear
	var zone_id := rid.substr(0, rid.rfind("_"))
	var n_zone := Api.owned_nodes(plan, zone_id, -1, true).size()
	var removed := Api.clear_owned(plan, zone_id, -1, null, true, PackedStringArray([rid]))
	_check(removed == n_zone - Api.owned_nodes(plan, rid).size() and Api.owned_nodes(plan, rid).size() > 0, "hierarchy: keep spared %d of %d" % [Api.owned_nodes(plan, rid).size(), n_zone])
	plan.free()
	_done("hierarchy suite done")


func _instance_ids(plan: Node) -> Array:
	var out: Array = []
	for item: Array in Api.plan_nodes(plan):
		out.append((item[0] as Node).get_instance_id())
	return out


# ---------------------------------------------------------------- 11. the user's edits win ----


func _overrides_suite() -> void:
	var d: Dictionary = Host.discover()
	var plan: Node2D = Api.new_plan("Over", null, _room_legend())
	root.add_child(plan)
	var ctx: Dictionary = Host.context(plan)
	var site: Resource = SiteBrief.new()
	site.id = "site"
	site.lots = 1
	site.storeys = 1
	site.bounds = Rect2(0, 0, 40, 30)
	var base: Dictionary = Host.run_chain(d.modules, "site", site, ctx)
	var room_brief: Resource = null
	for part: Dictionary in base.parts:
		if String(part.module_id) == "room":
			room_brief = part.brief
			break
	var rid := String(room_brief.get("id"))
	var mine: Resource = room_brief.duplicate(true)
	mine.rect = (mine.rect as Rect2).grow(-0.5)
	mine.role = "workshop"
	var res: Dictionary = Host.run_chain(d.modules, "site", site, ctx, {"room": {rid: mine}})
	_check((res.kept as PackedStringArray) == PackedStringArray([rid]), "overrides: kept %s" % str(res.kept))
	var used: Resource = null
	var siblings := 0
	for part: Dictionary in res.parts:
		if String(part.module_id) == "room":
			if String((part.brief as Resource).get("id")) == rid:
				used = part.brief
			else:
				siblings += 1
	_check(used != null and (used.rect as Rect2).is_equal_approx((mine.rect as Rect2)) and String(used.role) == "workshop", "overrides: the user's brief was not used")
	_check(siblings == (base.briefs.room as Array).size() - 1, "overrides: sibling count changed")
	# the same siblings' layouts as without the override
	var a_ids := PackedStringArray()
	var b_ids := PackedStringArray()
	for part: Dictionary in base.parts:
		if String(part.module_id) == "room" and String((part.brief as Resource).get("id")) != rid:
			a_ids.append(String((part.brief as Resource).get("id")))
	for part: Dictionary in res.parts:
		if String(part.module_id) == "room" and String((part.brief as Resource).get("id")) != rid:
			b_ids.append(String((part.brief as Resource).get("id")))
	_check(a_ids == b_ids, "overrides: siblings differ")
	plan.free()
	_done("overrides suite done")


# ---------------------------------------------------------------- 12. extract from the plan ---


## The plan scene is the source: a hand-drawn room and door become a Room brief; a designer's
## plan re-extracted gives briefs whose ids are the owners with the geometry that was run; the
## structure and site read the footprint and the floors; a sync with `adopt` takes the hand
## node over instead of duplicating it.
func _extract_suite() -> void:
	var d: Dictionary = Host.discover()
	var room: Object = Host.module_by_id(d.modules, "room")
	var plan: Node2D = Api.new_plan("Ext", null, _room_legend())
	root.add_child(plan)
	# by hand: a plate, a room, its door on the south edge
	var hand: Resource = Layout.new()
	var plate: Resource = hand.shape("Plate", 0)
	plate.size = Vector2(14, 9)
	plate.center = Vector2(7, 4.5)
	var rm: Resource = hand.shape("Drawn", 0)
	rm.room = true
	rm.size = Vector2(4, 3)
	rm.center = Vector2(3, 2.5)
	var dr: Resource = hand.door("Door", 0)
	dr.position = Vector2(3, 4)
	Api.write_layout(plan, hand, "hand")
	for item: Array in Api.plan_nodes(plan):
		(item[0] as Node).remove_meta("plan_owner")
	var ctx: Dictionary = Host.context(plan)
	var briefs: Array = room.call("extract", Host.survey(plan), ctx)
	_check(briefs.size() == 1, "extract: %d room briefs from a hand plan, want 1" % briefs.size())
	if briefs.size() == 1:
		var b: Resource = briefs[0]
		_check(String(b.id) == "Drawn" and (b.rect as Rect2).is_equal_approx(Rect2(1, 1, 4, 3)) and not bool(b.furnish), "extract: hand room %s %s" % [b.id, str(b.rect)])
		_check((b.entrances as Array).size() == 1 and (b.entrances[0] as Vector2).is_equal_approx(Vector2(2, 0.5)), "extract: entrance %s" % str(b.entrances))
		# adopt: the hand shape and door are renamed and tagged, never duplicated
		b.furnish = true
		b.role = "bedroom"
		var out: Dictionary = Host.run_chain(d.modules, "room", b, ctx)
		var shape_node := plan.get_node("Drawn")
		var door_node := plan.get_node("Door")
		var w: Dictionary = Drafter.write(plan, out.parts, "Drawn", null, Host.survey(plan))
		_check(shape_node.name == "Drawn" and door_node.name == "Door" and not shape_node.has_meta("plan_owner"), "extract: the room level touched the hand outline")
		_check(int(w.counts.added) >= 1 and Api.owned_nodes(plan, "Drawn").size() == int(w.counts.added), "extract: the room's fixtures are owned by it (%s)" % str(w.counts))
		var again: Array = room.call("extract", Host.survey(plan), ctx)
		_check(again.size() == 1 and String((again[0] as Resource).id) == "Drawn", "extract: after a run %d briefs / %s" % [again.size(), str(again)])
	# the structure and the site read the plan
	var structure: Object = Host.module_by_id(d.modules, "structure")
	var sb: Array = structure.call("extract", Host.survey(plan), ctx)
	_check(sb.size() == 1 and int((sb[0] as Resource).storeys) == 1 and _same((sb[0] as Resource).footprint, PackedVector2Array([Vector2(0, 0), Vector2(14, 0), Vector2(14, 9), Vector2(0, 9)]), 1e-3),
			"extract: structure %s" % (str((sb[0] as Resource).footprint) if sb.size() == 1 else str(sb)))
	var site_m: Object = Host.module_by_id(d.modules, "site")
	var st: Array = site_m.call("extract", Host.survey(plan), ctx)
	_check(st.size() == 1 and int((st[0] as Resource).lots) == 1 and (st[0] as Resource).bounds.encloses(Rect2(0, 0, 14, 9)), "extract: site %s" % str(st))
	# a designer's plan re-extracted: ids are the owners, geometry what was run
	var plan2: Node2D = Api.new_plan("Ext2", null, _room_legend())
	root.add_child(plan2)
	var ctx2: Dictionary = Host.context(plan2)
	var site: Resource = SiteBrief.new()
	site.id = "site"
	site.lots = 1
	site.storeys = 2
	site.bounds = Rect2(0, 0, 40, 30)
	var res: Dictionary = Host.run_chain(d.modules, "site", site, ctx2)
	Drafter.write(plan2, res.parts, "site")
	var view: Resource = Host.survey(plan2)
	var rooms: Array = room.call("extract", view, ctx2)
	var run_rooms: Array = res.briefs.room
	_check(rooms.size() == run_rooms.size(), "extract: %d rooms read, %d run" % [rooms.size(), run_rooms.size()])
	var by_id := {}
	for b: Resource in run_rooms:
		by_id[String(b.id)] = b
	var geo_ok := true
	for b: Resource in rooms:
		var ran: Resource = by_id.get(String(b.id))
		if ran == null or not (b.rect as Rect2).is_equal_approx(ran.rect) or int(b.floor) != int(ran.floor):
			geo_ok = false
	_check(geo_ok, "extract: room ids or rects differ from the run")
	var zones: Array = Host.module_by_id(d.modules, "zone").call("extract", view, ctx2)
	_check(zones.size() == (res.briefs.zone as Array).size(), "extract: %d zones read, %d run" % [zones.size(), (res.briefs.zone as Array).size()])
	if not zones.is_empty():
		var z0: Resource = zones[0]
		_check((z0.splits as PackedFloat32Array).size() == 2 and (z0.doors as Array).size() == 3, "extract: zone partition read back %s %s" % [str(z0.splits), str(z0.doors)])
	var storeys0: Array = Host.module_by_id(d.modules, "storey").call("extract", view, ctx2)
	if not storeys0.is_empty():
		var s0: Resource = storeys0[0]
		_check((s0.corridor as Rect2).size.y > 0 and (s0.zone_splits as PackedFloat32Array).size() == 1 and (s0.zone_entrances as PackedFloat32Array).size() == 4,
				"extract: storey decisions read back %s %s %s" % [str(s0.corridor), str(s0.zone_splits), str(s0.zone_entrances)])
	var storeys: Array = Host.module_by_id(d.modules, "storey").call("extract", view, ctx2)
	_check(storeys.size() == 2 and String((storeys[0] as Resource).id) == "site_S1_F0", "extract: storeys %s" % str(storeys))
	var structs: Array = structure.call("extract", view, ctx2)
	_check(structs.size() == 1 and String((structs[0] as Resource).id) == "site_S1" and int((structs[0] as Resource).storeys) == 2, "extract: structure from a run %s" % str(structs))
	var sites: Array = site_m.call("extract", view, ctx2)
	_check(sites.size() == 1 and String((sites[0] as Resource).id) == "site", "extract: site from a run %s" % str(sites))
	plan.free()
	plan2.free()
	_done("extract suite done")


# ---------------------------------------------------------------- 13. a preview writes nothing


func _preview_suite() -> void:
	var d: Dictionary = Host.discover()
	var plan: Node2D = Api.new_plan("Prev", null, _room_legend())
	root.add_child(plan)
	var ctx: Dictionary = Host.context(plan)
	var b: Resource = RoomBrief.new()
	b.id = "p"
	b.rect = Rect2(1, 1, 4, 3)
	var res: Dictionary = Host.run_chain(d.modules, "room", b, ctx)
	Drafter.write(plan, res.parts, "p")
	var before := _plan_names(plan)
	var sig: int = plan.call("_signature")
	# the overlay drags the brief's corner; the chain runs for the preview; the plan is untouched
	var ov: RefCounted = RectOverlay.new("rect", "entrances", false)
	var xf := Transform2D(0.0, Vector2(1, 1), 0.0, Vector2.ZERO)
	var octx := {"root": plan, "ppm": 100.0, "xf": xf, "brief": b, "briefs": [b], "floor": 0, "preview": null, "color": Color.WHITE, "kit": ctx.kit}
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(500, 400)   # the SE corner in px
	var r1: Dictionary = ov.gui_input(press, octx)
	_check(bool(r1.get("begin", false)), "preview: corner press did not begin a drag")
	var move := InputEventMouseMotion.new()
	move.position = Vector2(600, 450)
	var r2: Dictionary = ov.gui_input(move, octx)
	_check(bool(r2.get("changed", false)) and (b.rect as Rect2).is_equal_approx(Rect2(1, 1, 5, 3.5)), "preview: drag did not resize %s" % str(b.rect))
	var pv: Dictionary = Host.run_chain(d.modules, "room", b, ctx)
	var pl: Resource = Drafter.merge(Drafter.draft_to_layouts(pv.parts))
	_check((pl.floor_at(0).props as Array).size() >= 1, "preview: chain gave no fixtures")
	_check(_plan_names(plan) == before and int(plan.call("_signature")) == sig, "preview: the plan changed before release")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(600, 450)
	var r3: Dictionary = ov.gui_input(release, octx)
	_check(bool(r3.get("commit", false)), "preview: release did not commit")
	# click on another brief's outline activates it
	var other: Resource = RoomBrief.new()
	other.id = "q"
	other.rect = Rect2(8, 1, 3, 3)
	octx.briefs = [b, other]
	var p2 := InputEventMouseButton.new()
	p2.button_index = MOUSE_BUTTON_LEFT
	p2.pressed = true
	p2.position = Vector2(800, 250)   # on q's west edge
	ov.gui_input(p2, octx)
	var rel2 := InputEventMouseButton.new()
	rel2.button_index = MOUSE_BUTTON_LEFT
	rel2.pressed = false
	rel2.position = Vector2(800, 250)
	var r4: Dictionary = ov.gui_input(rel2, octx)
	_check(String(r4.get("activate", "")) == "q", "preview: click on an outline did not activate %s" % str(r4))
	plan.free()
	_done("preview suite done")


# ---------------------------------------------------------------- 14. the drafter -------------


func _part(module_id: String, id: String, draft: Resource) -> Dictionary:
	var b: Resource = Contract.new()
	b.id = id
	return {"module_id": module_id, "brief": b, "draft": draft}


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _walls_of(layouts: Array, owner: String) -> Array:
	for item: Dictionary in layouts:
		if String(item.owner) == owner:
			var out: Array = []
			for f: Resource in (item.layout as Resource).get("floors"):
				out.append_array(f.get("walls"))
			return out
	return []


func _drafter_suite() -> void:
	var plate: Resource = Draft.new()
	plate.region("plate0", "plate", 0, _rect_poly(Rect2(0, 0, 20, 10)))
	# 1. a wall is a line: the zone module draws one partition between two rooms, the rooms are
	# regions without walls of their own
	var d: Dictionary = Host.discover()
	var zone_m: Object = Host.module_by_id(d.modules, "zone")
	var zb: Resource = preload("res://addons/procedural_architecture/modules/zone/contract/zone_brief.gd").new()
	zb.id = "h_F0_Z1"
	zb.polygon = _rect_poly(Rect2(0, 0, 10, 10))
	var ents: Array[Vector2] = [Vector2(5, 10)]
	zb.entrances = ents
	var prog: Array[String] = ["living", "bedroom"]
	zb.program = prog
	var zout: Dictionary = zone_m.call("design", zb, Host.context(Api.new_plan("x")))
	var zd: Resource = zout.draft
	_check((zd.regions as Array).size() == 2 and (zd.walls as Array).size() == 1 and (zd.openings as Array).size() == 2, "drafter: zone draft %d regions %d walls %d doors" % [(zd.regions as Array).size(), (zd.walls as Array).size(), (zd.openings as Array).size()])
	var pw: PackedVector2Array = (zd.walls[0] as Dictionary).points
	_check(pw.size() == 2 and absf(pw[0].x - 5.0) < 1e-6 and absf(pw[1].x - 5.0) < 1e-6, "drafter: partition not at x = 5: %s" % str(pw))
	var parts: Array = [_part("structure", "h", plate), {"module_id": "zone", "brief": zb, "draft": zd}]
	var lays: Array = Drafter.draft_to_layouts(parts)
	var zl: Resource = lays[1].layout
	for sh: Resource in zl.floor_at(0).shapes:
		_check(bool(sh.room) and not bool(sh.walled), "drafter: a room cell must be a region without walls (%s)" % sh.id)
	_check(_walls_of(lays, "h_F0_Z1").size() == 1 and _walls_of(lays, "h").is_empty(), "drafter: walls %d / %d" % [_walls_of(lays, "h_F0_Z1").size(), _walls_of(lays, "h").size()])
	# 2. the bake: the partition band exists once; two rooms sharing the line give the same walls
	# as the single line alone
	var plan_a: Node2D = Api.new_plan("A")
	root.add_child(plan_a)
	Api.write_layout(plan_a, Drafter.merge(lays), "t")
	var only_line: Resource = Layout.new()
	var lp: Resource = only_line.shape("plate", 0)
	lp.size = Vector2(20, 10)
	lp.center = Vector2(10, 5)
	var lw: Resource = only_line.wall("p", 0)
	lw.points = pw
	var plan_b: Node2D = Api.new_plan("B")
	root.add_child(plan_b)
	Api.write_layout(plan_b, only_line, "t")
	_check(_wall_count(Api.build(plan_a)) == _wall_count(Api.build(plan_b)), "drafter: the room cells added walls of their own")
	plan_a.free()
	plan_b.free()
	# 3. the storey module: the corridor's two edges and one party wall per side, cells only
	var storey_m: Object = Host.module_by_id(d.modules, "storey")
	var sb: Resource = preload("res://addons/procedural_architecture/modules/storey/contract/storey_brief.gd").new()
	sb.id = "h_F0"
	sb.plate = _rect_poly(Rect2(0, 0, 24, 15))
	sb.zones = 4
	var sout: Dictionary = storey_m.call("design", sb, Host.context(Api.new_plan("y")))
	var sd: Resource = sout.draft
	_check((sd.walls as Array).size() == 4 and (sd.regions as Array).size() == 5, "drafter: storey draft %d walls %d regions" % [(sd.walls as Array).size(), (sd.regions as Array).size()])
	# 4. survey round trip through a write
	var full: Array = [_part("structure", "h", plate), {"module_id": "storey", "brief": sb, "draft": sd}]
	var plan: Node2D = Api.new_plan("S")
	root.add_child(plan)
	var wr: Dictionary = Drafter.write(plan, full, "h")
	_check((wr.warnings as PackedStringArray).is_empty(), "drafter: write warnings %s" % str(wr.warnings))
	var sv: Resource = Drafter.survey(Host.plan_view(plan))
	var got := {}
	for reg: Dictionary in sv.regions:
		got[String(reg.id)] = String(reg.role)
	_check(got == {"h_plate0": "plate", "h_F0_corridor": "corridor", "h_F0_Z1": "zone", "h_F0_Z2": "zone", "h_F0_Z3": "zone", "h_F0_Z4": "zone"}, "drafter: survey regions %s" % str(got))
	_check((sv.walls as Array).size() == 4 and (sv.openings as Array).size() == 4, "drafter: survey walls %d openings %d" % [(sv.walls as Array).size(), (sv.openings as Array).size()])
	_check(Survey_parent("h_F0_Z1_R1") == "h_F0_Z1" and Survey_parent("h_F0") == "h" and Survey_parent("h") == "", "drafter: parent_owner")
	# a hand plan: plate / room / zone inferred
	var hand: Node2D = Api.new_plan("Hand")
	root.add_child(hand)
	var hl: Resource = Layout.new()
	var hp: Resource = hl.shape("Plate", 0)
	hp.size = Vector2(14, 9)
	hp.center = Vector2(7, 4.5)
	var hz: Resource = hl.shape("Big", 0)
	hz.room = true
	hz.size = Vector2(8, 6)
	hz.center = Vector2(4, 3)
	var hr: Resource = hl.shape("Small", 0)
	hr.room = true
	hr.size = Vector2(3, 2)
	hr.center = Vector2(2, 2)
	Api.write_layout(hand, hl, "x")
	for item: Array in Api.plan_nodes(hand):
		(item[0] as Node).remove_meta("plan_owner")
	var hs: Resource = Drafter.survey(Host.plan_view(hand))
	var roles := {}
	for reg: Dictionary in hs.regions:
		roles[String(reg.id)] = String(reg.role) + "/" + String(reg.owner) + "/" + String(reg.source)
	_check(roles == {"Plate": "plate//hand", "Big": "zone//hand", "Small": "room//hand"}, "drafter: hand survey %s" % str(roles))
	hand.free()
	# a container that comes LATER in tree order than what it holds (the user's plan: a starter
	# rectangle, then the chain's plate around it) must survey too
	var late: Node2D = Api.new_plan("Late")
	root.add_child(late)
	var ll: Resource = Layout.new()
	var inner_r: Resource = ll.shape("Starter", 0)
	inner_r.room = true
	inner_r.size = Vector2(6, 4)
	inner_r.center = Vector2(3, 2)
	var outer_p: Resource = ll.shape("plate0", 0)
	outer_p.size = Vector2(24, 15)
	outer_p.center = Vector2(12, 7.5)
	Api.write_layout(late, ll, "x")
	for item: Array in Api.plan_nodes(late):
		(item[0] as Node).remove_meta("plan_owner")
	var ls: Resource = Drafter.survey(Host.plan_view(late))
	_check(ls != null and (ls.regions as Array).size() == 2, "drafter: a late container broke the survey")
	late.free()
	# 5. remove a zone: its subtree goes, the storey's lines stay
	Drafter.remove(plan, "h_F0_Z1")
	_check(Api.owned_nodes(plan, "h_F0_Z1", -1, true).is_empty() and Api.owned_nodes(plan, "h_F0").size() == (sd.walls as Array).size() + (sd.regions as Array).size() + (sd.openings as Array).size(),
			"drafter: remove touched the storey's nodes")
	# 6. determinism
	var again: Array = Drafter.draft_to_layouts(full)
	_check(Layout.equal(Drafter.merge(Drafter.draft_to_layouts(full)), Drafter.merge(again), 1e-9), "drafter: two runs differ")
	plan.free()
	_done("drafter suite done")


# ---------------------------------------------------------------- 15. the pyramid on a 3D plan -


## The pyramid never knows the front: the default site chain written into a 3D plan reads back
## as the same Layout, surveys and extracts the same briefs as on a 2D plan; and the overlays'
## projection through a camera maps a floor point to the screen and back within a centimetre,
## perspective and orthogonal alike.
func _plan3d_suite() -> void:
	var d: Dictionary = Host.discover()
	var site := func() -> Resource:
		var s: Resource = SiteBrief.new()
		s.id = "site"
		s.lots = 1
		s.storeys = 2
		s.bounds = Rect2(0, 0, 40, 30)
		return s
	var p2: Node = Api.new_plan("Twin2", null, _room_legend())
	var p3: Node = Api.new_plan("Twin3", null, _room_legend(), true)
	root.add_child(p2)
	root.add_child(p3)
	var r2: Dictionary = Host.run_chain(d.modules, "site", site.call(), Host.context(p2))
	var r3: Dictionary = Host.run_chain(d.modules, "site", site.call(), Host.context(p3))
	var w2: Dictionary = Drafter.write(p2, r2.parts, "site")
	var w3: Dictionary = Drafter.write(p3, r3.parts, "site")
	_check(int(w2.counts.added) == int(w3.counts.added) and int(w3.counts.added) > 20, "plan3d: written %s vs %s" % [str(w2.counts), str(w3.counts)])
	_check(Api.is_plan_3d(p3) and Layout.equal(Api.read_layout(p2), Api.read_layout(p3), 0.011, true), "plan3d: the site chain reads back differently on the 3D plan")
	var v2: Resource = Host.survey(p2)
	var v3: Resource = Host.survey(p3)
	_check((v2.regions as Array).size() == (v3.regions as Array).size() and (v2.openings as Array).size() == (v3.openings as Array).size()
			and (v2.fixtures as Array).size() == (v3.fixtures as Array).size() and (v2.walls as Array).size() == (v3.walls as Array).size(),
			"plan3d: survey differs (%d/%d regions, %d/%d openings)" % [(v2.regions as Array).size(), (v3.regions as Array).size(), (v2.openings as Array).size(), (v3.openings as Array).size()])
	for mid in ["room", "zone", "storey", "structure", "site"]:
		var m: Object = Host.module_by_id(d.modules, mid)
		var b2: Array = m.call("extract", v2, Host.context(p2))
		var b3: Array = m.call("extract", v3, Host.context(p3))
		var ids2 := PackedStringArray()
		var ids3 := PackedStringArray()
		for b: Resource in b2:
			ids2.append(String(b.get("id")))
		for b: Resource in b3:
			ids3.append(String(b.get("id")))
		_check(ids2 == ids3, "plan3d: %s extracts %s on 2D, %s on 3D" % [mid, ids2, ids3])
	# a room re-run on the 3D plan adapts in place
	var rooms: Array = Host.module_by_id(d.modules, "room").call("extract", v3, Host.context(p3))
	if not rooms.is_empty():
		var rb: Resource = rooms[0]
		var n0 := Api.plan_nodes(p3).size()
		var before := Api.owned_nodes(p3, String(rb.id))
		rb.density = 0.2
		var rr: Dictionary = Host.run_chain(d.modules, "room", rb, Host.context(p3))
		var wr: Dictionary = Drafter.write(p3, rr.parts, String(rb.id), null, v3)
		_check(int(wr.counts.removed) + int(wr.counts.added) <= before.size() + 2 and Api.plan_nodes(p3).size() <= n0,
				"plan3d: room re-run rebuilt more than its own fixtures (%s)" % str(wr.counts))
	# the projection: a camera over the floor, to_screen ∘ from_screen = identity
	var sv := SubViewport.new()
	sv.size = Vector2i(800, 600)
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.current = true
	cam.position = Vector3(20, 25, 40)
	cam.look_at(Vector3(20, 4.7, 15), Vector3.UP)
	var ctx := {"camera": cam, "plane_y": 4.7, "root_xf": Transform3D.IDENTITY}
	var worst := 0.0
	for mode in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL]:
		cam.projection = mode
		cam.size = 50.0
		for p in [Vector2(0, 0), Vector2(40, 30), Vector2(12.5, 7.25), Vector2(33, 2)]:
			var back: Vector2 = RectOverlay.from_screen(RectOverlay.to_screen(p, ctx), ctx)
			worst = maxf(worst, back.distance_to(p))
	_check(worst < 0.01, "plan3d: projection round trip off by %.4f m" % worst)
	# a ray that misses the floor falls back to the last hit
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var last: Vector2 = RectOverlay.from_screen(RectOverlay.to_screen(Vector2(5, 5), ctx), ctx)
	cam.look_at(cam.position + Vector3(0, 1, 0), Vector3.FORWARD)
	var miss: Vector2 = RectOverlay.from_screen(Vector2(400, 300), ctx)
	_check(miss.is_equal_approx(last), "plan3d: a missed ray did not fall back (%s vs %s)" % [str(miss), str(last)])
	sv.free()
	p2.free()
	p3.free()
	_done("plan3d suite done")


# ---------------------------------------------------------------- 16. the owner groups ---------


## The Scene dock is the pyramid: a run nests each owner's nodes in a group along the owner
## chain, own nodes before sub-groups; a re-run keeps groups and identity; a removal takes the
## chain; a hidden group drops its content from plan_data on both fronts; a flat plan migrates
## into groups on its next run; convert_plan keeps the groups; undo restores the tree.
func _groups_suite() -> void:
	var d: Dictionary = Host.discover()
	for three_d in [false, true]:
		var tag := "3D" if three_d else "2D"
		var plan: Node = Api.new_plan("Grp", null, _room_legend(), three_d)
		root.add_child(plan)
		var ctx: Dictionary = Host.context(plan)
		var site: Resource = SiteBrief.new()
		site.id = "site"
		site.lots = 1
		site.storeys = 2
		site.bounds = Rect2(0, 0, 40, 30)
		var res: Dictionary = Host.run_chain(d.modules, "site", site, ctx)
		var w: Dictionary = Drafter.write(plan, res.parts, "site")
		# the chain of groups, on both floors
		var z1 := plan.get_node_or_null("Floor_0/site/S1/F0/Z1")
		var r1 := plan.get_node_or_null("Floor_0/site/S1/F0/Z1/R1")
		var f1 := plan.get_node_or_null("Floor_1/site/S1/F1")
		_check(z1 != null and r1 != null and f1 != null, "groups %s: chain missing (%s %s %s)" % [tag, z1 != null, r1 != null, f1 != null])
		if z1 == null or r1 == null:
			plan.free()
			continue
		_check(z1.has_meta("plan_group") and String(z1.get_meta("plan_owner")) == "site_S1_F0_Z1" and String(z1.get_meta("plan_level")) == "zone",
				"groups %s: zone group metas %s" % [tag, str(z1.get_meta_list())])
		_check((z1 is Node3D) == three_d, "groups %s: group node kind" % tag)
		# own nodes precede the sub-groups; the room's fixtures live in the room's group
		var last_plan := -1
		var first_group := z1.get_child_count()
		for i in z1.get_child_count():
			var c: Node = z1.get_child(i)
			if c.has_meta("plan_group"):
				first_group = mini(first_group, i)
			else:
				last_plan = maxi(last_plan, i)
		_check(last_plan < first_group and last_plan >= 0, "groups %s: zone's own nodes (…%d) must precede its groups (%d…)" % [tag, last_plan, first_group])
		var fixtures := Api.owned_nodes(plan, "site_S1_F0_Z1_R1")
		var inside := true
		for n: Node in fixtures:
			if n.get_parent() != r1:
				inside = false
		_check(not fixtures.is_empty() and inside, "groups %s: the room's fixtures are not in its group" % tag)
		_check(Api.plan_nodes(plan).size() == int(w.counts.added), "groups %s: plan_nodes counts groups?" % tag)
		# a room re-run keeps its group and every other node's identity
		var room_brief: Resource = null
		for part: Dictionary in res.parts:
			if String((part.brief as Resource).get("id")) == "site_S1_F0_Z1_R1":
				room_brief = (part.brief as Resource).duplicate(true)
		var ids_before := _instance_ids(plan)
		var r1_id := r1.get_instance_id()
		room_brief.density = 0.3
		var one: Dictionary = Host.run_chain(d.modules, "room", room_brief, ctx)
		var w1: Dictionary = Drafter.write(plan, one.parts, "site_S1_F0_Z1_R1", null, Host.survey(plan))
		_check(is_instance_valid(r1) and r1.get_instance_id() == r1_id and r1.get_parent() == z1, "groups %s: the room's group did not survive its re-run" % tag)
		var lost := 0
		for iid in ids_before:
			if not is_instance_valid(instance_from_id(iid)):
				lost += 1
		_check(lost <= fixtures.size(), "groups %s: re-run lost %d nodes outside the room" % [tag, lost])
		_check(int(w1.counts.moved) == 0, "groups %s: re-run moved %d nodes" % [tag, int(w1.counts.moved)])
		# a hidden group hides its content from the plan the bake reads (read_layout still sees it)
		var walls_before: int = (plan.call("plan_data").levels[0].walls as Array).size()
		var props_before: int = (plan.call("plan_data").levels[0].props as Array).size()
		z1.set("visible", false)
		var walls_hidden: int = (plan.call("plan_data").levels[0].walls as Array).size()
		var props_hidden: int = (plan.call("plan_data").levels[0].props as Array).size()
		_check(walls_hidden < walls_before and props_hidden < props_before, "groups %s: hiding the zone group left walls %d/%d props %d/%d" % [tag, walls_hidden, walls_before, props_hidden, props_before])
		_check(Api.read_layout(plan, "site_S1_F0_Z1", true).floor_at(0).props.size() > 0, "groups %s: read_layout must ignore visibility" % tag)
		z1.set("visible", true)
		_check((plan.call("plan_data").levels[0].walls as Array).size() == walls_before, "groups %s: showing the group again" % tag)
		# a flat node migrates into its group on the owner's next run
		var fx: Node = fixtures[0]
		var floor0: Node = plan.get_node("Floor_0")
		Api.reparent_node(fx, floor0, -1, plan)
		var w2: Dictionary = Drafter.write(plan, one.parts, "site_S1_F0_Z1_R1", null, Host.survey(plan))
		_check(fx.get_parent() == r1 and int(w2.counts.moved) == 1, "groups %s: flat node not moved home (%s, moved %d)" % [tag, str(fx.get_parent()), int(w2.counts.moved)])
		# removing the zone takes its chain of groups and nodes
		Drafter.remove(plan, "site_S1_F0_Z1")
		_check(not is_instance_valid(z1) or z1.get_parent() == null, "groups %s: zone group survived removal" % tag)
		_check(Api.owned_nodes(plan, "site_S1_F0_Z1", -1, true).is_empty(), "groups %s: zone nodes survived removal" % tag)
		_check(plan.get_node_or_null("Floor_0/site/S1/F0") != null, "groups %s: the storey group must survive" % tag)
		# undo: a room re-run under an EditorUndoRedo-like undo restores the tree
		var undo := FakeUndo.new()
		var z2 := plan.get_node("Floor_0/site/S1/F0/Z2")
		var kids_before := z2.get_child_count()
		var rb2: Resource = null
		for part: Dictionary in res.parts:
			if String((part.brief as Resource).get("id")) == "site_S1_F0_Z2_R1":
				rb2 = (part.brief as Resource).duplicate(true)
		rb2.density = 0.1
		var two: Dictionary = Host.run_chain(d.modules, "room", rb2, ctx)
		undo.create_action("room")
		Drafter.write(plan, two.parts, "site_S1_F0_Z2_R1", undo, Host.survey(plan))
		undo.commit_action()
		undo.undo()
		_check(z2.get_child_count() == kids_before, "groups %s: undo left %d children of Z2, had %d" % [tag, z2.get_child_count(), kids_before])
		undo.redo()
		# convert keeps the groups
		var conv: Node = Api.convert_plan(plan, not three_d)
		root.add_child(conv)
		_check(conv.get_node_or_null("Floor_0/site/S1/F0/Z2/R1") != null, "groups %s: convert lost the groups" % tag)
		_check(Layout.equal(Api.read_layout(conv), Api.read_layout(plan), 0.011, true), "groups %s: convert differs" % tag)
		conv.free()
		plan.free()
	_done("groups suite done")


func Survey_parent(owner: String) -> String:
	return preload("res://addons/procedural_architecture/core/survey.gd").parent_owner(owner)


func _wall_count(bk: Node3D) -> int:
	var n := 0
	for c: Node in _walk(bk):
		if String(c.name).begins_with("Wall_") or String(c.name).begins_with("Partition_"):
			n += 1
	bk.free()
	return n


# ---------------------------------------------------------------- helpers ---------------------


func _plan_names(plan: Node2D) -> PackedStringArray:
	var out := PackedStringArray()
	for n: Node in _walk(plan):
		if n.has_method("is_plan_shape") or n.has_method("is_plan_wall") or n.has_method("is_plan_door") \
				or n.has_method("is_plan_prop") or n.has_method("is_plan_stair"):
			out.append(String(plan.get_path_to(n)))
	return out


func _same(x: Variant, y: Variant, eps: float) -> bool:
	return Layout._same(x, y, eps)


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


## A stand-in for EditorUndoRedoManager (editor-only) with its call shape: do ops run in order
## on commit / redo, undo ops in reverse — the semantics of UndoRedo.
class FakeUndo:
	const NONE := "__no_arg__"
	var _do: Array = []
	var _undo: Array = []

	func create_action(_name: String, _merge: int = 0, _ctx: Object = null) -> void:
		_do.clear()
		_undo.clear()

	func add_do_method(obj: Object, method: String, a1: Variant = NONE, a2: Variant = NONE, a3: Variant = NONE, a4: Variant = NONE) -> void:
		_do.append(_bind(obj, method, [a1, a2, a3, a4]))

	func add_undo_method(obj: Object, method: String, a1: Variant = NONE, a2: Variant = NONE, a3: Variant = NONE, a4: Variant = NONE) -> void:
		_undo.append(_bind(obj, method, [a1, a2, a3, a4]))

	func add_do_property(obj: Object, prop: String, value: Variant) -> void:
		_do.append(func() -> void: obj.set(prop, value))

	func add_undo_property(obj: Object, prop: String, value: Variant) -> void:
		_undo.append(func() -> void: obj.set(prop, value))

	func add_do_reference(_o: Object) -> void:
		pass

	func add_undo_reference(_o: Object) -> void:
		pass

	func commit_action(_execute := true) -> void:
		redo()

	func redo() -> void:
		for c: Callable in _do:
			c.call()

	func undo() -> void:
		for i in range(_undo.size() - 1, -1, -1):
			(_undo[i] as Callable).call()

	func _bind(obj: Object, method: String, args: Array) -> Callable:
		var real: Array = []
		for a in args:
			if typeof(a) == TYPE_STRING and String(a) == NONE:
				break
			real.append(a)
		return func() -> void: obj.callv(method, real)
