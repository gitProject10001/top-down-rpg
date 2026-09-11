extends SceneTree
## THE EDITOR'S CONTRACT WITH THE NODES — the one thing no other test can see.
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/verify_editor_scripts.gd
##
## WHY THIS EXISTS, WRITTEN THE DAY IT WAS NEEDED. `addons/gladekit/editor/` is never executed by
## `verify_gladekit.gd` (it needs an editor) and never by `golden_gladekit.gd` (it builds no
## geometry). So when the wall refactor deleted `GladeWall._tangent()` as an unused delegate, all 38
## suites passed, the golden dump was byte-identical across 139,325 lines, and every pearl in the
## editor was gone — `_redraw` threw on the first opening it drew, which takes the drag handles AND
## the click-to-select mesh down with it.
##
## The first version of this file only checked that the five editor scripts LOAD. They did. A script
## that loads is not a script that works, and "it parses" is the weakest claim a test can make.
##
## So this asserts the actual contract: every method the editor calls on a GladeKit node exists on
## that node. It is checked two ways, because either alone is escapable:
##
##   1. Against an EXPLICIT table, so the requirement is legible — a reviewer can see what the
##      editor depends on without reading 1,100 lines of plugin code.
##   2. By SCANNING `editor/*.gd` for `receiver._method(` calls, so a dependency added later cannot
##      quietly sit outside the table. The scan is what stops the table going stale.

const EDITOR_SCRIPTS := [
	"res://addons/gladekit/editor/glade_plugin.gd",
	"res://addons/gladekit/editor/glade_gizmos.gd",
	"res://addons/gladekit/editor/glade_palette.gd",
	"res://addons/gladekit/editor/glade_weather_brush.gd",
	"res://addons/gladekit/editor/glade_presets.gd",
]

## What the editor is entitled to call on each node type. Private names are in here on purpose: the
## gizmo is a privileged consumer, and pretending otherwise is how the contract got broken.
const CONTRACT := {
	"GladeWall": [
		"rebuild", "drop_to_ground", "collision_rids", "junction_volumes", "total_height",
		"top_jetty", "box_plan", "set_box_plan", "make_box", "snap_step", "cylinder_plan",
		"set_cylinder_plan", "make_cylinder", "set_cylinder_radius", "push_face", "pull_corner",
		"weather_at", "paint_weather", "clear_weather",
		# private, but the gizmo and the brush genuinely need them
		"_tangent", "_is_closed", "_mark_dirty",
	],
	"GladePath": ["rebuild", "drop_to_ground", "_tangent", "_is_closed", "_mark_dirty"],
	"GladeScatter": ["rebuild", "paint_at", "clear_scatter", "_mark_dirty"],
	"GladeRoof": ["rebuild", "junction_volumes", "_mark_dirty"],
	"GladeOpening": ["effective_sill"],
}

## Receivers the scan knows the type of. `node` and `p3` are deliberately loose in the gizmo — it
## drives walls and paths through the same code — so both are checked against both.
const RECEIVER_TYPES := {
	"wall": ["GladeWall"],
	"sc": ["GladeScatter"],
	"o": ["GladeOpening"],
	"node": ["GladeWall", "GladePath"],
	"p3": ["GladeWall", "GladePath"],
}

var _fails: Array[String] = []


func _initialize() -> void:
	_load_suite()
	_contract_suite()
	_scan_suite()

	if _fails.is_empty():
		print("[EDITOR] GLADEKIT EDITOR PASS")
		quit(0)
		return
	print("[EDITOR] GLADEKIT EDITOR FAIL (%d)" % _fails.size())
	for f in _fails:
		print("  FAIL: %s" % f)
	quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


## Every editor script resolves to a script resource at all.
##
## ⚠ THIS CANNOT SEE A COMPILE FAILURE, and believing otherwise cost real time on 2026-08-04: this
## suite printed PASS while `glade_gizmos.gd` was failing to compile against a class that was not yet
## in the global cache. Measured, on a script whose dependency does not compile, Godot returns a
## non-null resource, `reload()` returns `OK`, `can_instantiate()` returns `true`, and
## `get_script_method_list()` returns the full list — because the engine keeps serving the last
## GOOD compilation and reports the failure only to stderr. `CACHE_MODE_IGNORE` does not change any
## of it. There is no in-process signal to assert on.
##
## SO THE CHECK IS THE PROCESS, NOT THIS FUNCTION. A compile failure shows up as `Parse Error` or
## `Compilation failed` on stderr, and the way to catch it is to look:
##
##     Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/verify_editor_scripts.gd 2>&1 \
##         | grep -E "Parse Error|Compilation failed" && echo "EDITOR SCRIPTS DO NOT COMPILE"
##
## A new `class_name` is the usual cause: it is not in `.godot/global_script_class_cache.cfg` until
## an editor pass has scanned it, so a headless run right after adding one fails and a second run
## succeeds. Run `--editor --quit-after 200 --path .` once after adding a class.
func _load_suite() -> void:
	for p: String in EDITOR_SCRIPTS:
		_check(load(p) != null, "%s does not load" % p.get_file())
	print("[EDITOR] load suite done")


## Every method in the table exists on the node it names.
func _contract_suite() -> void:
	var names := CONTRACT.keys()
	names.sort()
	for type_name: String in names:
		var inst := _instance(type_name)
		if inst == null:
			_check(false, "%s could not be instantiated" % type_name)
			continue
		for m: String in CONTRACT[type_name]:
			_check(inst.has_method(m), "%s.%s() is gone — the editor calls it" % [type_name, m])
		_free(inst)
	print("[EDITOR] contract suite done")


## No editor script may call a private method on a known receiver unless the table names it. This is
## the half that keeps the table honest: add a `wall._something()` to the gizmo and this fails until
## the contract records it.
func _scan_suite() -> void:
	var re := RegEx.create_from_string("\\b(\\w+)\\.(_\\w+)\\(")
	for p: String in EDITOR_SCRIPTS:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		for m in re.search_all(src):
			var recv := m.get_string(1)
			var method := m.get_string(2)
			if not RECEIVER_TYPES.has(recv):
				continue                       # a local, or the plugin's own private method
			for type_name: String in RECEIVER_TYPES[recv]:
				var inst := _instance(type_name)
				if inst == null:
					continue
				var exists: bool = inst.has_method(method)
				_free(inst)
				if not exists:
					continue                   # a loose receiver: the OTHER type owns this call
				_check((CONTRACT[type_name] as Array).has(method),
						"%s.%s() is called from %s but is not in CONTRACT"
								% [type_name, method, p.get_file()])
	print("[EDITOR] scan suite done")


func _instance(type_name: String) -> Object:
	for e in ProjectSettings.get_global_class_list():
		if e.get("class") == type_name:
			var s := load(e.get("path")) as Script
			return s.new() if s and s.can_instantiate() else null
	return null


func _free(o: Object) -> void:
	if o is Node:
		(o as Node).free()
	elif not (o is RefCounted):
		o.free()
