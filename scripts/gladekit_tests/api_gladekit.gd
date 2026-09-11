extends SceneTree
## THE ADDON'S PUBLIC CONTRACT, dumped for diffing. Everything a .tscn or a .tres can serialise,
## and everything another script is entitled to call.
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/api_gladekit.gd \
##       -- --out=docs/refactor-evidence/api_before.txt
##
## WHY NOT JUST GREP THE SOURCE. A scene stores properties, not source lines. An `@export` that
## keeps its name but loses its type, its hint or its default still breaks every scene that
## serialised it, and the source diff would look innocent. So this asks a real instance what it
## exposes — name, type, hint, usage AND the value a fresh one starts with, which is precisely
## what Godot compares against when deciding what to write into a .tscn.
##
## Reading the diff: the refactor is allowed to ADD lines. Any REMOVED or CHANGED line is a broken
## scene, a broken style resource, or a broken caller.

const TYPES := [
	"GladeWall", "GladeRoof", "GladePath", "GladeScatter",
	"GladeStyle", "GladeStorey", "GladeOpening", "GladeDormer", "GladeChimney",
	"GladeVolume", "GladeSeam", "GladeJunction", "GladeUtil", "GladeDebug",
	"GladeBrickMesh", "GladeTuftMesh", "GladeVineMesh",
]

## Private names the test suite and the marker nodes genuinely call. They are not public API in
## spirit, but they ARE load-bearing: verify_gladekit.gd must keep running unmodified, so a
## refactor that renames one of these has broken its own oracle. Listed here so the diff says so
## out loud rather than surfacing as 38 confusing suite failures.
const PINNED := {
	"GladeWall": ["_mark_dirty", "_course_spans", "_clear_rects", "_is_closed", "_do_rebuild"],
	"GladeRoof": ["_mark_dirty", "_plan", "_slope_pt", "_collect_dormers", "_in_cut", "_do_rebuild"],
	"GladePath": ["_mark_dirty"],
	"GladeScatter": ["_mark_dirty"],
}

var _out := PackedStringArray()


func _initialize() -> void:
	var path := "user://glade_api.txt"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(6)

	for t: String in TYPES:
		_dump(t)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[API] FAILED to open %s" % path)
		quit(1)
		return
	f.store_string("\n".join(_out) + "\n")
	f.close()
	print("[API] %s  (%d lines)" % [path, _out.size()])
	quit(0)


func _dump(type_name: String) -> void:
	_out.append("")
	_out.append("================================================ %s" % type_name)
	if not ClassDB.class_exists(type_name) and not _script_exists(type_name):
		_out.append("!! MISSING — the class_name is gone")
		return

	var script: Script = _script_for(type_name)
	if script == null:
		_out.append("!! no script")
		return
	_out.append("extends %s" % _base_of(script))

	# --- constants and enums: read straight off the script, so they survive on Object subclasses
	# that cannot be instantiated as nodes
	var consts := script.get_script_constant_map()
	var ckeys := consts.keys()
	ckeys.sort()
	for k in ckeys:
		_out.append("const %s = %s" % [k, var_to_str(consts[k])])

	for s in script.get_script_signal_list():
		_out.append("signal %s" % s.name)

	# --- properties, with the value a fresh instance starts with. THAT is the serialisation
	# contract: Godot writes a property into a .tscn only when it differs from this.
	var inst: Object = _instance(script)
	if inst != null:
		var props := script.get_script_property_list()
		for p in props:
			if int(p.usage) & PROPERTY_USAGE_STORAGE == 0 \
					and int(p.usage) & PROPERTY_USAGE_EDITOR == 0:
				continue
			var v: Variant = inst.get(p.name)
			_out.append("prop %s : type=%d hint=%d/%s usage=%d default=%s"
					% [p.name, p.type, p.hint, p.hint_string, p.usage, _short(v)])
		_free(inst)

	# --- callable surface
	var pinned: Array = PINNED.get(type_name, [])
	var methods := PackedStringArray()
	for m in script.get_script_method_list():
		var n: String = m.name
		if n.begins_with("_") and not pinned.has(n):
			continue
		var args := PackedStringArray()
		for a in m.args:
			args.append("%s:%d" % [a.name, a.type])
		var tag := "func" if not n.begins_with("_") else "func PINNED"
		methods.append("%s %s(%s) -> %d" % [tag, n, ", ".join(args), int(m["return"].type)])
	methods.sort()                             # declaration order is not part of the contract
	_out.append_array(methods)


# ---------------------------------------------------------------- plumbing ------------------


func _script_exists(type_name: String) -> bool:
	return _script_for(type_name) != null


func _script_for(type_name: String) -> Script:
	for e in ProjectSettings.get_global_class_list():
		if e.get("class") == type_name:
			return load(e.get("path")) as Script
	return null


func _base_of(script: Script) -> String:
	var base := script.get_instance_base_type()
	return base if base != "" else "?"


## A Resource or an Object can be `new`d; a Node can too, but must be freed the right way.
func _instance(script: Script) -> Object:
	if not script.can_instantiate():
		return null
	return script.new()


func _free(o: Object) -> void:
	if o is Node:
		(o as Node).free()
	elif not (o is RefCounted):
		o.free()


## Arrays of meshes and packed scenes print as multi-line resource dumps, which is noise. Keep the
## shape (a colour is a value, an Array[Mesh] is a length) and nothing else.
func _short(v: Variant) -> String:
	if v is Array:
		return "Array(%d)" % (v as Array).size()
	if v is Dictionary:
		return "Dictionary(%d)" % (v as Dictionary).size()
	if v is Object:
		return "<%s>" % ((v as Object).get_class() if v != null else "null")
	if v is Curve3D or v is Curve:
		return "<curve>"
	return var_to_str(v)
