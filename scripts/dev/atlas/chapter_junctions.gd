extends RefCounted
## CHAPTER 5 — JUNCTIONS: two buildings in the same place.
##
## The other chapters drive the pipeline through `atlas_rig.gd`, deliberately without a node. This
## one cannot and should not. A junction is the one rule that is genuinely ABOUT the scene: buildings
## find each other through the `glade_solid` group, ask each other what they CLAIM, and never ask
## what anybody built. Faking that with detached rigs would duplicate the interesting half and prove
## nothing, so this chapter puts real `GladeWall`s in the tree and lets the addon do its own work.
##
## WHAT IT SHOWS, and in this order of importance:
##
##   1  the CLAIM is a volume, not geometry — drawn as the massing prisms each building occupies.
##      Nothing is re-meshed and nothing is cut; each emitter simply asks "does someone else own
##      this spot?" just before it places a piece.
##   2  rank decides, and EQUAL RANKS DO NOTHING. That negative case is half the design: a scene
##      built before junctions existed is untouched until somebody sets a number.
##   3  the winner is UNCHANGED. Every piece it had standing alone is still there — checked live,
##      because if that failed the whole edit-locality promise would be dead.
##   4  what the seam GETS BACK: tee quoins up the joint, valley tiles down a roof fold. A claim can
##      only take a piece away; half of what a real junction needs is a piece put there.
##   5  `buried_style`: the swallowed region rebuilt as an interior face rather than deleted.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Rig := preload("res://scripts/dev/atlas/atlas_rig.gd")

const STYLES := [
	{"name": "stone", "path": Rig.STYLE_STONE},
	{"name": "timber", "path": Rig.STYLE_TIMBER},
	{"name": "clay", "path": Rig.STYLE_CLAY},
]

## The arrangements worth studying. Each is a pair of footprints and whether B carries a roof.
const CASES := [
	{"name": "wall × wall", "a": "wall", "b": "wall_cross", "roof": false,
		"note": "two open runs crossing. The simplest case: one loses its stones inside the other's ribbon."},
	{"name": "wall into house", "a": "house", "b": "wall_tee", "roof": false,
		"note": "a run dying into a face — a TEE. The classic reason a raw sawn course end needs dressing."},
	{"name": "house × house", "a": "house", "b": "house_offset", "roof": false,
		"note": "two blocks overlapping at a corner. Watch the loser lose a whole quadrant."},
	{"name": "tower through house", "a": "house", "b": "tower", "roof": false,
		"note": "the whinbek case: a round tower driven through a block, clearing the bricks it stands in."},
	{"name": "house + roof × tower", "a": "house", "b": "tower", "roof": true,
		"note": "the tower clears the TILES too. A roof claims a volume like anything else."},
]

var atlas

var _case := 3
var _rank_a := 1
var _rank_b := 5
var _style_a := 0
var _style_b := 0
var _buried := false
var _tee := true
var _show_volumes := false
var _show_seams := false

var _holder: Node3D
var _overlay: Node3D
var _a: GladeWall
var _b: GladeWall
var _report := {}
var _solo_roof := {}


func setup() -> void:
	_holder = Node3D.new()
	atlas.stage.add_child(_holder)
	_overlay = Node3D.new()
	atlas.stage.add_child(_overlay)
	_rebuild()


func teardown() -> void:
	pass


func on_step(dir: int) -> void:
	_case = posmod(_case + dir, CASES.size())
	_rebuild()
	atlas.refresh()


# ---------------------------------------------------------------- building --------------------


func _rebuild() -> void:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.free()

	var spec: Dictionary = CASES[_case]
	# EACH WALL ALONE FIRST. The invariant this chapter exists to show is that the winner keeps
	# every piece it had standing alone, and the only honest way to say that is to build it alone
	# and compare. Three passes: A by itself, B by itself, then both together.
	var solo_a := _capture_solo(spec, true)
	var solo_roof := _solo_roof
	var solo_b := _capture_solo(spec, false)

	_a = _make(spec, true)
	_b = _make(spec, false)
	_holder.add_child(_a)
	_holder.add_child(_b)
	# both are in the tree now, so each can see the other's claim; rebuild so neither is stale
	_rebuild_tree(_a)
	_rebuild_tree(_b)

	var scene_a := _sig(_a)
	var scene_b := _sig(_b)
	_report = {
		"a": _compare(solo_a, scene_a),
		"b": _compare(solo_b, scene_b),
		"stats_a": _a.stats.duplicate(),
		"stats_b": _b.stats.duplicate(),
	}
	if not solo_roof.is_empty():
		_report["roof"] = _compare(solo_roof, _sig_roof(_a))

	# THE BADGE: the winner must be unchanged. Whoever holds the higher rank should have lost
	# nothing; if that ever fails, one building moving would ripple through every neighbour.
	var win_lost: int = (_report.a.missing if _rank_a >= _rank_b else _report.b.missing)
	var who := "A" if _rank_a >= _rank_b else "B"
	if _rank_a == _rank_b:
		atlas.set_badge("equal ranks — neither cuts the other (A lost %d, B lost %d)"
				% [_report.a.missing, _report.b.missing],
				_report.a.missing == 0 and _report.b.missing == 0)
	else:
		atlas.set_badge("winner %s unchanged vs standing alone (%d pieces lost)" % [who, win_lost],
				win_lost == 0)
	_draw_overlay()


## A WALL AND ITS ROOF, IN ORDER — and the roof explicitly.
##
## A wall pokes its roof children with `_mark_dirty()`, which is `call_deferred`, so the roof has
## NOT rebuilt by the time a synchronous caller reads it. Left to the deferred pass this chapter
## compared a fresh wall against a stale roof and reported that a tower through a roof clears no
## tiles at all — which is precisely the thing that case exists to show.
##
## Wall first, then roof: the roof reads the wall's footprint and height.
func _rebuild_tree(w: GladeWall) -> void:
	w.rebuild()
	for c in w.get_children():
		if c is GladeRoof:
			(c as GladeRoof).rebuild()


## Build one wall on its own, capture its placements, then take it away again. A wall only sees
## neighbours that are in the tree, so "alone" is literally alone.
func _capture_solo(spec: Dictionary, is_a: bool) -> Dictionary:
	var w := _make(spec, is_a)
	_holder.add_child(w)
	_rebuild_tree(w)
	var s := _sig(w)
	_solo_roof = _sig_roof(w)
	_holder.remove_child(w)
	w.free()
	return s


func _make(spec: Dictionary, is_a: bool) -> GladeWall:
	var w := GladeWall.new()
	w.name = "A" if is_a else "B"
	w.rng_seed = 7 if is_a else 11
	w.generate_collision = false
	w.junction_rank = _rank_a if is_a else _rank_b
	w.tee_quoins = _tee
	var st: GladeStyle = load(STYLES[_style_a if is_a else _style_b].path)
	if _buried:
		# the swallowed region becomes an interior face instead of nothing. A duplicate so the
		# shipped .tres on disk is never touched by the atlas.
		st = st.duplicate() as GladeStyle
		st.buried_style = load(Rig.STYLE_TIMBER)
	w.style = st

	var c := Curve3D.new()
	for p: Vector3 in _plan(spec.a if is_a else spec.b):
		c.add_point(p)
	w.curve = c
	w.wall_height = 3.2 if (spec.b == "tower" and not is_a) else 2.8
	if spec.b == "tower" and not is_a:
		w.wall_height = 7.0
	if spec.roof and is_a:
		var r := GladeRoof.new()
		r.pitch_degrees = 46.0
		r.overhang = 0.5
		r.rng_seed = 3
		r.junction_rank = _rank_a
		w.add_child(r)
	return w


## The footprints. Kept as plain point lists so each case is legible as data.
func _plan(kind: String) -> Array:
	match kind:
		"wall":
			return [Vector3(-5, 0, 0), Vector3(5, 0, 0)]
		"wall_cross":
			return [Vector3(0, 0, -5), Vector3(0, 0, 5)]
		"wall_tee":
			return [Vector3(0, 0, 3), Vector3(0, 0, 9)]
		"house":
			return [Vector3(-4, 0, -3), Vector3(4, 0, -3), Vector3(4, 0, 3),
					Vector3(-4, 0, 3), Vector3(-4, 0, -3)]
		"house_offset":
			return [Vector3(2, 0, 1), Vector3(9, 0, 1), Vector3(9, 0, 7),
					Vector3(2, 0, 7), Vector3(2, 0, 1)]
		"tower":
			var pts: Array = []
			for i in 13:
				var ang := TAU * float(i % 12) / 12.0
				pts.append(Vector3(2.2, 0, 1.0) + Vector3(cos(ang), 0, sin(ang)) * 1.9)
			return pts
	return [Vector3.ZERO, Vector3(4, 0, 0)]


## Every placement of a wall as a rounded key set, so two builds can be compared as sets.
func _sig(w: GladeWall) -> Dictionary:
	var out := {}
	for t in w.snap_transforms:
		out["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	return out


## The same, for a wall's roof — reported SEPARATELY because a roof is its own node with its own
## claim. Without this the "house + roof x tower" case reads identically to the one without a roof:
## the tower clears TILES, and the wall's own count cannot show that.
func _sig_roof(w: GladeWall) -> Dictionary:
	var out := {}
	for c in w.get_children():
		if c is GladeRoof:
			for t in (c as GladeRoof).snap_transforms:
				out["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	return out


## What the scene did to a wall relative to standing alone: what it lost, and what it gained.
## GAINS ARE EXPECTED — the tee rules are additive and put pieces back on the joint.
func _compare(solo: Dictionary, scene: Dictionary) -> Dictionary:
	var missing := 0
	for k in solo:
		if not scene.has(k):
			missing += 1
	var added := 0
	for k in scene:
		if not solo.has(k):
			added += 1
	return {"solo": solo.size(), "scene": scene.size(), "missing": missing, "added": added}


# ---------------------------------------------------------------- the overlay -----------------


## The claim volumes and the seams, drawn where they are — reusing the addon's own debug meshes so
## the picture cannot disagree with what the generator used.
func _draw_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	if not is_instance_valid(_a) or not is_instance_valid(_b):
		return

	if _show_volumes:
		for pair in [[_a, Color(0.35, 0.75, 1.0)], [_b, Color(1.0, 0.62, 0.3)]]:
			var w: GladeWall = pair[0]
			var vols: Array = w.junction_volumes()
			for ch in w.get_children():
				if ch is GladeRoof:
					vols.append_array((ch as GladeRoof).junction_volumes())
			if vols.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = GladeDebug.massing_mesh(vols, pair[1])
			mi.material_override = _ghost(pair[1])
			mi.top_level = true                # the volumes are already world-space
			_overlay.add_child(mi)

	if _show_seams:
		var seams: Array = []
		for v: GladeVolume in _a.junction_volumes():
			seams.append_array(GladeSeam.between(v, GladeJunction.gather_related(_a)))
		seams = GladeSeam.significant(seams)
		if not seams.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = GladeDebug.seam_mesh(seams)
			mi.material_override = GladeDebug.overlay_material(Color.WHITE)
			mi.top_level = true
			_overlay.add_child(mi)
			var holder := Node3D.new()
			holder.top_level = true
			_overlay.add_child(holder)
			GladeDebug.seam_labels(seams, holder, 3)


## A claim drawn as GLASS, not as a solid.
##
## `GladeDebug.massing_material()` is deliberately opaque — blockout replaces the building, so it
## should look like one. Here the volume has to sit OVER the stones it explains, and an opaque prism
## hides the very thing it is an explanation of. Unshaded so the tint stays readable at any angle,
## and depth-writing off so two overlapping claims both show.
static func _ghost(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.20)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


# ---------------------------------------------------------------- the panel -------------------


func build_rows(box: VBoxContainer) -> void:
	var spec: Dictionary = CASES[_case]
	var head := Label.new()
	head.text = spec.name
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(296, 0)
	note.add_theme_font_size_override("font_size", 11)
	note.text = spec.note
	box.add_child(note)

	for i in CASES.size():
		var b := Tuning.button(box, ("▶ " if i == _case else "   ") + CASES[i].name,
				func(): _case = i; _rebuild(); atlas.refresh())
		b.add_theme_font_size_override("font_size", 11)

	# --- what the claim did, per building ----------------------------------------------------
	Tuning.header(box, "what the claim did")
	for key in ["a", "b"]:
		var r: Dictionary = _report.get(key, {})
		if r.is_empty():
			continue
		var st: Dictionary = _report.get("stats_" + key, {})
		var rank: int = _rank_a if key == "a" else _rank_b
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		l.text = "%s  rank %d  %s\n   alone %d → in scene %d\n   lost %d · gained %d (tees %d, quoins %d)" % [
				key.to_upper(), rank, STYLES[_style_a if key == "a" else _style_b].name,
				r.solo, r.scene, r.missing, r.added,
				int(st.get("tees", 0)), int(st.get("quoins", 0))]
		l.add_theme_color_override("font_color",
				Color(0.55, 0.95, 0.6) if r.missing == 0 else Color(1.0, 0.72, 0.45))
		box.add_child(l)

	var rr: Dictionary = _report.get("roof", {})
	if not rr.is_empty():
		var rl := Label.new()
		rl.add_theme_font_size_override("font_size", 11)
		rl.text = "A's ROOF  alone %d → in scene %d
   lost %d tiles to the tower's claim" % [
				rr.solo, rr.scene, rr.missing]
		rl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
		box.add_child(rl)

	var law := Label.new()
	law.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	law.custom_minimum_size = Vector2(296, 0)
	law.add_theme_font_size_override("font_size", 11)
	law.add_theme_color_override("font_color", Color(0.68, 0.72, 0.78))
	law.text = "\"lost\" must be 0 for the winner. \"gained\" is the tee dressing, which is additive — a claim can only take a piece away."
	box.add_child(law)

	# --- the knobs ---------------------------------------------------------------------------
	Tuning.header(box, "rank — who cuts whom")
	Tuning.slider(box, "rank A", 0, 8, 1, _rank_a,
			func(v): _rank_a = int(v); _rebuild(); atlas.refresh())
	Tuning.slider(box, "rank B", 0, 8, 1, _rank_b,
			func(v): _rank_b = int(v); _rebuild(); atlas.refresh())

	Tuning.header(box, "styles")
	for pair in [["A", true], ["B", false]]:
		var is_a: bool = pair[1]
		for i in STYLES.size():
			var cur: int = _style_a if is_a else _style_b
			var b := Tuning.button(box, "%s %s%s" % [pair[0], "▶ " if i == cur else "  ",
					STYLES[i].name], func(): _set_style(is_a, i))
			b.add_theme_font_size_override("font_size", 11)

	Tuning.header(box, "what the seam gets back")
	Tuning.check(box, "tee quoins", _tee, func(on): _tee = on; _rebuild(); atlas.refresh())
	Tuning.check(box, "buried_style (rebuild, not delete)", _buried,
			func(on): _buried = on; _rebuild(); atlas.refresh())

	Tuning.header(box, "show")
	Tuning.check(box, "claim volumes", _show_volumes,
			func(on): _show_volumes = on; _draw_overlay())
	Tuning.check(box, "seams", _show_seams, func(on): _show_seams = on; _draw_overlay())

	atlas.show_class("GladeClaim")


func _set_style(is_a: bool, i: int) -> void:
	if is_a:
		_style_a = i
	else:
		_style_b = i
	_rebuild()
	atlas.refresh()
