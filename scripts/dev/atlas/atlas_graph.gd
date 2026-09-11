extends RefCounted
## DERIVES THE ADDON'S DEPENDENCY GRAPH by reading its source — never a hardcoded picture.
##
## A diagram maintained by hand is a diagram that is wrong by the second refactor, and this project
## has just had one. So the map the atlas draws is scanned out of the files every time it opens:
## find every `class_name`, then find which of those names each file mentions. Move a class and the
## picture follows; add one and it appears.
##
## WHAT IT PROVES, when it is right: the arrow only ever points one way —
##
##     nodes/  ──▶  generate/  ──▶  core/  ──▶  (nothing)
##
## `core/` naming a `generate/` class, or anything at all naming `nodes/`, would be a cycle and the
## map would show it as a back-edge. That is the property the refactor was for, drawn rather than
## asserted.
##
## No `class_name`, by the same rule as the rest of scripts/dev — `preload()` this by path.

const ROOT := "res://addons/gladekit"

## Packages in dependency order, which is also the order they are drawn in.
const LAYERS := ["data", "core", "generate", "nodes", "editor", "meshes"]


## Everything the map needs: nodes with their package, and the edges between them.
##
## Returns `{ classes: {name: {path, layer, lines}}, edges: [[from, to]], by_layer: {layer: [name]} }`
static func build() -> Dictionary:
	var classes := {}
	var files := {}                            # path -> source text, read once

	for e in ProjectSettings.get_global_class_list():
		var path: String = e.get("path")
		if not path.begins_with(ROOT):
			continue
		var cls: String = e.get("class")
		var txt := _read(path)
		files[path] = txt
		classes[cls] = {
			"path": path,
			"layer": _layer_of(path),
			"lines": txt.split("\n").size(),
		}

	# An identifier only counts as a dependency if some OTHER GladeKit class declares it. That
	# single rule is what keeps the graph honest without a list of exceptions.
	#
	# COMMENTS ARE STRIPPED FIRST, and that is not a detail. This addon's doc headers name other
	# classes constantly — `glade_wall_frame.gd` explains itself by talking about `GladeWall` — so
	# scanning raw text draws an edge from core/ back up to nodes/ and the map claims a cycle that
	# does not exist. The first run of this file reported twenty such back-edges, every one of them
	# a sentence.
	var edges: Array = []
	var seen := {}
	var re := RegEx.create_from_string("\\bGlade[A-Z][A-Za-z0-9]*")
	for cls: String in classes:
		var txt: String = _strip_comments(files[classes[cls].path])
		for m in re.search_all(txt):
			var other := m.get_string()
			if other == cls or not classes.has(other):
				continue
			var key := "%s>%s" % [cls, other]
			if seen.has(key):
				continue
			seen[key] = true
			edges.append([cls, other])

	var by_layer := {}
	for l in LAYERS:
		by_layer[l] = []
	for cls: String in classes:
		var l: String = classes[cls].layer
		if not by_layer.has(l):
			by_layer[l] = []
		(by_layer[l] as Array).append(cls)
	for l: String in by_layer:
		(by_layer[l] as Array).sort()

	return {"classes": classes, "edges": edges, "by_layer": by_layer}


## Edges that point the WRONG way down the layering — a cycle, or a lower package reaching up.
## Empty is the result the refactor was for; the atlas draws any survivors in red.
static func back_edges(g: Dictionary) -> Array:
	var out: Array = []
	for e: Array in g.edges:
		var a: int = LAYERS.find(g.classes[e[0]].layer)
		var b: int = LAYERS.find(g.classes[e[1]].layer)
		# `meshes` is leaf-like and sits outside the wall's layering; ignore it either way
		if a < 0 or b < 0 or g.classes[e[0]].layer == "meshes" or g.classes[e[1]].layer == "meshes":
			continue
		if b > a:
			out.append(e)
	return out


## What a class depends on, and what depends on it — the two lists the panel shows on click.
static func neighbours_of(g: Dictionary, cls: String) -> Dictionary:
	var uses: Array = []
	var used_by: Array = []
	for e: Array in g.edges:
		if e[0] == cls:
			uses.append(e[1])
		elif e[1] == cls:
			used_by.append(e[0])
	uses.sort()
	used_by.sort()
	return {"uses": uses, "used_by": used_by}


static func _layer_of(path: String) -> String:
	var rest := path.substr(ROOT.length() + 1)
	var slash := rest.find("/")
	return rest.substr(0, slash) if slash > 0 else "root"


## Everything from an unquoted `#` to end of line. Crude on purpose — GDScript string literals
## containing `#` are vanishingly rare in this addon, and a full tokeniser to catch them would be a
## worse trade than the odd missed edge.
static func _strip_comments(src: String) -> String:
	var out := PackedStringArray()
	for raw in src.split("\n"):
		var line := raw as String
		var in_str := false
		var quote := ""
		var cut := -1
		for i in line.length():
			var ch := line[i]
			if in_str:
				if ch == quote and (i == 0 or line[i - 1] != "\\"):
					in_str = false
			elif ch == "\"" or ch == "'":
				in_str = true
				quote = ch
			elif ch == "#":
				cut = i
				break
		out.append(line.substr(0, cut) if cut >= 0 else line)
	return "\n".join(out)


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t
