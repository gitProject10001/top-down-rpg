extends RefCounted
## THE RIG — the atlas's driver of the procedural-architecture generator, from OUTSIDE the addon.
##
## It runs the real `Generator.generate` with a TRACE (the generator stamps every child, seed,
## gate, fixture and wall with the step of the operator that made it), groups the trace's
## entries per cell, and classifies every cell on the LADDER (zone, ward, building, storey,
## room, area) so a chapter is a depth of the recursion and a step is one operator of one cell.
## It also bakes the tree — the drafter writes a fresh plan, the floorplan façade builds it —
## for the 3D chapter.
##
## THE BADGE IS THE POINT, as in the GladeKit atlas: the traced run is compared with a plain
## `generate` of the same brief on every rebuild. A trace that changed the result would be a
## plausible lie; if the stats ever differ the badge goes red and says which key.
##
## No `class_name` (scripts/dev's rule, see tuning_panel.gd): preload by path.

const Api := preload("res://addons/floorplan/api/floorplan_api.gd")
const Host := preload("res://addons/procedural_architecture/core/module_host.gd")
const Drafter := preload("res://addons/procedural_architecture/core/drafter.gd")
const Generator := preload("res://addons/procedural_architecture/gen/generator.gd")
const ZoneBrief := preload("res://addons/procedural_architecture/gen/zone_brief.gd")
const Dungeon := preload("res://addons/procedural_architecture/gen/recipes/dungeon.gd")

## The ladder: a chapter per level.
const LEVELS := ["Zone", "Wards", "Buildings", "Storeys", "Rooms", "Areas"]
const OPS_DIR := "res://addons/procedural_architecture/gen/ops/"

var host: Node                      ## where the hidden plans live (the atlas root)
var brief: Resource                 ## the ZoneBrief: seed, size, rules
var plan: Node                      ## a hidden 3D plan: the legend and kit the context reads
var tree: RefCounted                ## the generated cell tree (traced)
var trace: Array = []               ## the generator's entries, in order
var stats := {}
var warnings := PackedStringArray()
var steps_of := {}                  ## cell id -> PackedInt32Array of trace indices
var verified := {"ok": true, "note": "", "mine": 0}
var gen_ms := 0.0
var verify := true                  ## the badge's second run (doubles the generation time)


func _init(host_: Node) -> void:
	host = host_
	brief = ZoneBrief.new()
	brief.id = "zone"
	brief.seed = 7
	brief.size_m = 150.0


# ---------------------------------------------------------------- generation ---------------


func rebuild() -> void:
	if plan == null:
		plan = Api.new_plan("PaAtlas", null, _legend(), true)
		host.add_child(plan)
		plan.set("visible", false)
	var ctx: Dictionary = Host.context(plan)
	trace = []
	ctx["trace"] = trace
	var t0 := Time.get_ticks_usec()
	var res: Dictionary = Generator.generate(brief, ctx)
	gen_ms = (Time.get_ticks_usec() - t0) / 1000.0
	tree = res.tree
	stats = res.stats
	warnings = res.warnings
	steps_of = {}
	for i in trace.size():
		var e: Dictionary = trace[i]
		var l: PackedInt32Array = steps_of.get(String(e.cell_id), PackedInt32Array())
		l.append(i)
		steps_of[String(e.cell_id)] = l
	verified = {"ok": true, "note": "unverified", "mine": int(stats.cells)}
	if verify:
		var plain: Dictionary = Generator.generate(brief, Host.context(plan))
		var note := ""
		for key in ["cells", "wards", "buildings", "rooms", "gates", "fixtures", "walls"]:
			if int(plain.stats[key]) != int(stats[key]):
				note = "%s %d vs %d" % [key, int(stats[key]), int(plain.stats[key])]
				break
		if note == "" and str(plain.stats.roles) != str(stats.roles):
			note = "roles differ"
		verified = {"ok": note == "", "note": note, "mine": int(stats.cells)}


func _legend() -> Resource:
	var legend: Resource = Api.default_legend()
	var rows: Array = legend.get("entries")
	rows.append(Api.legend_row("pendant", Color(1, 1, 0.5), 0, Vector3(0.5, 0.3, 0.5)))
	rows.append(Api.legend_row("locker", Color(0.5, 0.5, 0.5), 1, Vector3(1.0, 2.0, 0.6)))
	rows.append(Api.legend_row("altar", Color(0.8, 0.7, 0.4), 1, Vector3(1.4, 1.0, 1.4)))
	return legend


# ---------------------------------------------------------------- the ladder ---------------


## Which chapter a cell belongs to (−1: a corridor or passage — drawn, never focused).
func level_of(cell: RefCounted) -> int:
	if cell.parent == null:
		return 0
	if int(cell.depth) == 1:
		return 1
	if cell.is_building():
		return 2
	if not bool(cell.floored):
		return 5
	var par: RefCounted = cell.parent
	if par.is_building() and String(par.boundary) == "none" and not cell.children.is_empty():
		return 3
	if String(cell.role) == "corridor":
		return -1
	if cell.is_room():
		return 4
	return -1


func cells_at(level: int) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for c: RefCounted in tree.walk():
		if level_of(c) == level:
			out.append(c)
	return out


## The trace indices of a cell's own operators, in order.
func steps(cell: RefCounted) -> PackedInt32Array:
	return steps_of.get(String(cell.id), PackedInt32Array())


## The step a cell was made at (the root: −1).
func birth(cell: RefCounted) -> int:
	return int(cell.params.get("step", -1))


## The trace entry at a global step.
func entry(step: int) -> Dictionary:
	if step < 0 or step >= trace.size():
		return {}
	return trace[step]


## The cell's outline as it was at step S (the cave before carving).
func polygon_at(cell: RefCounted, s: int) -> PackedVector2Array:
	var sp := int(cell.params.get("step_polygon", -1))
	if sp >= 0 and s < sp:
		var e := entry(sp)
		if e.has("before") and (e.before as Dictionary).has("polygon"):
			return (e.before as Dictionary).polygon
	return cell.polygon


## The boundary meaning in force at step S.
func boundary_at(cell: RefCounted, s: int) -> String:
	var sb := int(cell.params.get("step_boundary", -1))
	if sb >= 0 and s < sb:
		return String(cell.params.get("boundary_before", cell.boundary))
	return String(cell.boundary)


## The rules a cell reads, nearest ancestor first: [{key, value, by, step}].
func rules_in_effect(cell: RefCounted) -> Array:
	var out: Array = []
	var seen := {}
	var c: RefCounted = cell
	while c != null:
		var stamps: Dictionary = c.params.get("step_rules", {})
		for key in c.rules:
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"key": String(key), "value": c.rules[key], "by": String(c.id), "step": int(stamps.get(key, -1))})
		c = c.parent
	return out


## A parameter as the op read it: a String names a rule.
func resolve_param(cell: RefCounted, v: Variant) -> String:
	if v is String and cell.rule(String(v), null) != null:
		return "%s → %s" % [String(v), str(cell.rule(String(v), null))]
	return str(v)


## The op's own script, for the reading pane.
func op_path(op: String) -> String:
	return OPS_DIR + op + ".gd"


func cell_label(cell: RefCounted) -> String:
	return "%s (%s, %.0f m²)" % [cell.id, cell.role, cell.area()]


# ---------------------------------------------------------------- the bake -----------------


## The plan as it was after step `upto` (−1 = everything), through the drafter and the façade:
## {node: Node3D, plan_nodes, counts, ms}. The plan itself is freed once built.
func bake(upto: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var bp: Node = Api.new_plan("PaAtlasBake", null, _legend(), true)
	host.add_child(bp)
	bp.set("visible", false)
	var w: Dictionary = Drafter.write(bp, Generator.to_parts(tree, brief, upto), "zone")
	var n_nodes: int = (Api.plan_nodes(bp) as Array).size()
	var node: Node3D = Api.build(bp, "Bake")
	bp.queue_free()
	return {"node": node, "plan_nodes": n_nodes, "counts": w.counts, "ms": (Time.get_ticks_usec() - t0) / 1000.0}
