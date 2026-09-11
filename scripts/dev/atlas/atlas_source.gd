extends RefCounted
## READS THE ADDON'S OWN SOURCE, so the atlas explains the code that is actually there.
##
## Every GladeKit class opens with a `##` block saying what it is for and, usually, which bug taught
## it that. Those headers were written to be the explanation, so the atlas quotes them rather than
## keeping a second description that would drift the first time somebody edited a file. A panel that
## can go stale is worse than no panel, because you cannot tell when it has.
##
## No `class_name`, by the same rule as the rest of scripts/dev — `preload()` this by path.

## path -> {"doc": String, "lines": int, "name": String, "extends": String}
static var _cache := {}


## The doc block at the top of a script: every leading `##` line after `class_name` / `extends`,
## stopping at the first line that is not one. Returns "" for a file with no header.
static func read(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]

	var out := {"doc": "", "lines": 0, "name": path.get_file(), "extends": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.doc = "(source not readable at runtime: %s)" % path
		_cache[path] = out
		return out
	var text := f.get_as_text()
	f.close()

	var lines := text.split("\n")
	out.lines = lines.size()
	var doc := PackedStringArray()
	var started := false
	for raw in lines:
		var line := (raw as String).strip_edges(false, true)
		if line.begins_with("class_name "):
			out.name = line.substr(11).strip_edges()
			continue
		if line.begins_with("extends "):
			out.extends = line.substr(8).strip_edges()
			continue
		if line.begins_with("##"):
			started = true
			# "## text" -> "text"; a bare "##" is a paragraph break
			doc.append(line.substr(2).strip_edges(true, false))
			continue
		if line.begins_with("@tool") or line.is_empty():
			if started:
				break                          # a blank line after the block ends it
			continue
		break                                  # first real code: the header is over
	out.doc = "\n".join(doc)
	_cache[path] = out
	return out


## The header of whichever file declares `class_name X`, or an empty result.
static func for_class(cls: String) -> Dictionary:
	var p := path_of(cls)
	return read(p) if p != "" else {"doc": "", "lines": 0, "name": cls, "extends": ""}


## Where a global class lives, straight from the project's own registry — so this stays correct if
## a file is moved, which is precisely what happened to all 48 of them.
static func path_of(cls: String) -> String:
	for e in ProjectSettings.get_global_class_list():
		if e.get("class") == cls:
			return e.get("path")
	return ""


## Wrap to `width` columns for a fixed-width panel, preserving the blank lines that separate
## paragraphs. RichTextLabel could do this, but the headers use `code` quoting and dashes that its
## BBCode parser would eat.
static func wrap(text: String, width := 52) -> String:
	var out := PackedStringArray()
	for para in text.split("\n"):
		var p := para as String
		if p.strip_edges().is_empty():
			out.append("")
			continue
		var line := ""
		for word in p.split(" "):
			var w := word as String
			if line.is_empty():
				line = w
			elif line.length() + 1 + w.length() <= width:
				line += " " + w
			else:
				out.append(line)
				line = w
		if not line.is_empty():
			out.append(line)
	return "\n".join(out)


## The first paragraph only — the one-line "what is this", for tight spaces.
static func summary(text: String) -> String:
	for para in text.split("\n"):
		var p := (para as String).strip_edges()
		if not p.is_empty():
			return p
	return ""
