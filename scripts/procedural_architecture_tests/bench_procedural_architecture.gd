extends SceneTree
## THE BENCH: where the time goes with the default Site chain (2 structures × 2 storeys × 4 zones
## × 3 rooms ≈ 250 plan nodes). Run:
##   Godot_console.exe --headless --path . --script res://scripts/procedural_architecture_tests/bench_procedural_architecture.gd --log-file <fresh>
## Every row is the minimum of 3 repeats, in milliseconds. Rows for API calls that do not exist
## yet (older checkouts) are skipped, so the same script measures before and after.

const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Layout := preload("res://addons/floorplan/api/plan_layout.gd")
const Host := preload("res://addons/procedural_architecture/core/module_host.gd")
const SiteBrief := preload("res://addons/procedural_architecture/modules/site/contract/site_brief.gd")
const Geo := preload("res://addons/floorplan/core/plan_geometry.gd")
const Drafter := preload("res://addons/procedural_architecture/core/drafter.gd")

var _rows: Array = []


func _initialize() -> void:
	var legend: Resource = Api.default_legend()
	var rows: Array = legend.get("entries")
	rows.append(Api.legend_row("pendant", Color(1, 1, 0.5), 0, Vector3(0.5, 0.3, 0.5)))
	rows.append(Api.legend_row("locker", Color(0.5, 0.5, 0.5), 1, Vector3(1.0, 2.0, 0.6)))
	var plan: Node2D = Api.new_plan("Bench", null, legend)
	root.add_child(plan)
	var d: Dictionary = Host.discover()
	var modules: Array = d.modules
	var ctx: Dictionary = Host.context(plan)
	var site: Resource = SiteBrief.new()
	site.id = "site"
	site.lots = 2
	site.storeys = 2
	site.bounds = Rect2(0, 0, 60, 40)

	var res: Dictionary = _time("run_chain(site)  full chain", func() -> Dictionary: return Host.run_chain(modules, "site", site, ctx))
	var lay: Resource = _time("draft_to_layouts (site)", func() -> Resource: return Drafter.merge(Drafter.draft_to_layouts(res.parts)))
	var n_el := 0
	for f: Resource in lay.get("floors"):
		n_el += (f.call("elements") as Array).size()
	var room_brief: Resource = null
	if res.has("parts"):
		for p: Dictionary in res.parts:
			if String(p.module_id) == "room":
				room_brief = p.brief
				break
	elif (res.briefs as Dictionary).has("room"):
		room_brief = (res.briefs.room as Array)[0]
	if room_brief != null:
		_time("run_chain(room)  one room", func() -> void: Host.run_chain(modules, "room", room_brief, ctx))
	_time("write_layout     first write (%d elements)" % n_el, func() -> void: Api.write_layout(plan, lay, "designer"))
	_time("write_layout     second write (remove + re-add)", func() -> void: Api.write_layout(plan, lay, "designer"))
	if _has(Api, "sync_layout"):
		_time("sync_layout      no change", func() -> void: Callable(Api, "sync_layout").call(plan, lay, "designer"))
		var moved: Resource = Layout.from_dict(lay.to_dict())
		var f0: Resource = moved.floor_at(0)
		var props: Array = f0.get("props")
		if not props.is_empty():
			(props[0] as Resource).position += Vector2(1, 0)
		_time("sync_layout      one prop moved", func() -> void: Callable(Api, "sync_layout").call(plan, moved, "designer"))
		Callable(Api, "sync_layout").call(plan, lay, "designer")
	_time("read_layout", func() -> void: Api.read_layout(plan))
	_time("plan_data()      both floors (bake input)", func() -> void: plan.call("plan_data"))
	var data: Dictionary = plan.call("plan_data")
	var lv0: Dictionary = data.levels[0]
	var t := float(Api.kit_info(plan).wall_thickness) * 100.0
	_time("draw: islands()  Geo.compute floor 0", func() -> void: plan.call("islands", 0))
	var isl: Array = plan.call("islands", 0)
	var ring: Array = []
	_time("draw: wall_pieces", func() -> void: ring = Geo.wall_pieces(isl, t))
	var walls: Array = plan.call("walls", 0)
	_time("draw: partition_pieces (%d wall outlines)" % walls.size(), func() -> void: Geo.partition_pieces(isl, walls, t, ring))
	var parts: Array = Geo.partition_pieces(isl, walls, t, ring)
	_time("draw: edges + %d door snaps" % (lv0.doors as Array).size(), func() -> void:
			var edge_list: Array = Geo.edges(isl) + parts
			for dd: Dictionary in lv0.doors:
				Geo.snap(edge_list, dd.pos))
	if plan.has_method("_level_geometry"):
		_time("draw: _level_geometry(0) cold", func() -> void:
				plan.call("_geo_cache_clear") if plan.has_method("_geo_cache_clear") else null
				plan.call("_level_geometry", 0))
		_time("draw: _level_geometry(0) hit", func() -> void: plan.call("_level_geometry", 0))
	_time("_signature()     the 10 Hz poll", func() -> void: plan.call("_signature"))
	_time("plan_nodes()     one API walk", func() -> void: Api.plan_nodes(plan))

	_say("[BENCH] %d plan nodes, %d elements, %d wall outlines on floor 0" % [Api.plan_nodes(plan).size(), n_el, walls.size()])
	var width := 0
	for r: Array in _rows:
		width = maxi(width, String(r[0]).length())
	for r: Array in _rows:
		_say("[BENCH] %s %8.2f ms" % [String(r[0]).rpad(width), float(r[1])])
	plan.free()
	quit(0)


## Times `f` three times, keeps the best, returns the last result.
func _time(label: String, f: Callable) -> Variant:
	var best := INF
	var last: Variant = null
	for i in 3:
		var t0 := Time.get_ticks_usec()
		last = f.call()
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	_rows.append([label, best])
	return last


func _has(script: GDScript, method: String) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if String(m.name) == method:
			return true
	return false


func _say(s: String) -> void:
	print(s)
