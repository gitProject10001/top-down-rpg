extends SceneTree
## THE FOLIAGE BRUSH'S CONTRACT WITH THE PATCHES — the one thing no other suite can see.
##
##   Godot_console.exe --headless --path . --script res://scripts/dev/verify_foliage_editor.gd
##
## Modelled on scripts/gladekit_tests/verify_editor_scripts.gd, which exists because of a specific
## afternoon: a refactor deleted GladeWall._tangent() as an unused delegate, all 38 suites passed,
## the golden dump was byte-identical across 139,325 lines, and every pearl in the editor was gone.
## Editor code needs an editor to run, so nothing else executes it — and "it parses" is the weakest
## claim a test can make.
##
## The same hole is open here. addons/foliage_brush/ is duck-typed on purpose (`has_method`,
## `node.get("brush_points")`), which is what lets one brush drive grass and shrubs and lets a third
## kind of plant join later — and which also means a renamed method fails at the click, silently, in
## a session nobody is running headless.
##
## So this checks the contract two ways, because either alone is escapable:
##
##   1. An EXPLICIT table, so what the brush depends on is legible without reading the plugin.
##   2. A SCAN of the addon for `call("name"` / `has_method("name"` / `get("name"` strings, so a
##      dependency added later cannot quietly sit outside the table.

const ADDON_SCRIPTS := [
	"res://addons/foliage_brush/plugin.gd",
	"res://addons/foliage_brush/foliage_brush.gd",
	"res://addons/foliage_brush/foliage_dock.gd",
]

## What the brush is entitled to call on a patch, and read off it. PER CLASS, because the two are
## not identical and pretending they are would either demand a method that has no meaning or excuse
## one that does.
##
## `settle` is grass-only on purpose: it re-bakes the fake self-shadowing that darkens a tuft by how
## crowded it is, and shrubs have no such bake. The brush guards that call with has_method().
##
## `erase_stroke` is required of BOTH, and that is the point of listing it. It was absent from
## BushPatch for its whole life, the erase path guarded on has_method(), and the result was an
## eraser that silently skipped every shrub layer under the cursor — a guarded call that quietly
## does nothing is the exact failure this file exists to catch.
const CONTRACT := {
	"GrassPatch": {
		"methods": ["append_stroke", "erase_stroke", "rebuild", "settle", "reproject"],
		"properties": ["brush_points", "brush_radii", "brush_radius", "erase_points", "erase_radii",
				"erase_strengths", "paint_only", "density", "terrain"],
	},
	"BushPatch": {
		"methods": ["append_stroke", "erase_stroke", "rebuild", "reproject"],
		"properties": ["brush_points", "brush_radii", "brush_radius", "erase_points", "erase_radii",
				"erase_strengths", "paint_only", "density", "terrain", "mesh_source"],
	},
}

## Every patch class the brush is allowed to be handed.
const PATCHES := ["GrassPatch", "BushPatch"]

var _fails: Array[String] = []


func _initialize() -> void:
	_load_suite()
	_contract_suite()
	_scan_suite()

	if _fails.is_empty():
		print("[FOLIAGE-ED] PASS — brush and patches agree")
		quit(0)
		return
	for f in _fails:
		print("[FOLIAGE-ED] FAIL  %s" % f)
	print("[FOLIAGE-ED] %d PROBLEM(S)" % _fails.size())
	quit(1)


## The weakest check, kept because a plugin that does not parse takes the whole editor plugin list
## down with it and the message Godot prints for that is not obvious.
func _load_suite() -> void:
	for path: String in ADDON_SCRIPTS:
		if not ResourceLoader.exists(path):
			_fails.append("missing: %s" % path)
			continue
		if load(path) == null:
			_fails.append("will not load: %s" % path)


func _contract_suite() -> void:
	for cls: String in PATCHES:
		var node := _patch(cls)
		var want: Dictionary = CONTRACT[cls]
		for m: String in want["methods"]:
			if not node.has_method(m):
				_fails.append("%s has no %s() — the brush calls it" % [cls, m])
		var props := _props_of(node)
		for p: String in want["properties"]:
			if not props.has(p):
				_fails.append("%s has no `%s` — the brush reads or writes it" % [cls, p])
		node.free()


func _patch(cls: String) -> Node:
	var node: Node = ClassDB.instantiate("MultiMeshInstance3D")
	node.set_script(load(_script_for(cls)))
	return node


func _props_of(node: Node) -> Dictionary:
	var out := {}
	for p: Dictionary in node.get_property_list():
		out[p.name] = true
	return out


func _script_for(cls: String) -> String:
	return "res://addons/foliage_brush/nodes/%s.gd" % ("grass_patch" if cls == "GrassPatch"
			else "bush_patch")


## Scan the addon for names it hands to a patch as a STRING. Those are exactly the calls the
## compiler cannot check, which is why they are the ones worth checking here.
func _scan_suite() -> void:
	var pattern := RegEx.new()
	pattern.compile('(?:call|has_method|get|set)\\("([a-z_]+)"')
	var known := {}
	for cls: String in PATCHES:
		for m: String in CONTRACT[cls]["methods"]:
			known[m] = true
		for p: String in CONTRACT[cls]["properties"]:
			known[p] = true

	for path: String in ADDON_SCRIPTS:
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.open(path, FileAccess.READ).get_as_text()
		for m: RegExMatch in pattern.search_all(text):
			var nm := m.get_string(1)
			if known.has(nm):
				continue
			# Only flag names that actually resolve on a patch — the addon also calls things on
			# nodes of its own, and a table listing those would be noise rather than a contract.
			for cls: String in PATCHES:
				var node := _patch(cls)
				if node.has_method(nm) or _props_of(node).has(nm):
					_fails.append("%s uses \"%s\" on %s but the CONTRACT table does not list it"
							% [path.get_file(), nm, cls])
				node.free()
