extends RefCounted
## CHAPTER 4 — THE THREE FILL STRATEGIES, side by side, from one registry lookup.
##
## The same run, the same seed, the same openings, built three times. The only thing that differs is
## which `GladeFill` subclass `GladeFillRegistry.for_style()` returned — masonry, timber or clay —
## and nothing above that line knows which it got. That is the Open/Closed claim made concrete: they
## are PEERS, not a default and two variants.
##
## The counts underneath each one are the honest ones. Clay reports quads rather than pieces because
## it places nothing at all: a mud wall has no pieces, and faking them with very small bricks looks
## exactly like very small bricks.
##
## This chapter builds three independent rigs rather than reusing the shared one, because the point
## is the comparison and a shared rig can only hold one result.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Rig := preload("res://scripts/dev/atlas/atlas_rig.gd")

const MODES := [
	{"name": "MASONRY", "style": Rig.STYLE_STONE, "cls": "GladeFillMasonry"},
	{"name": "TIMBER", "style": Rig.STYLE_TIMBER, "cls": "GladeFillTimber"},
	{"name": "ADOBE", "style": Rig.STYLE_CLAY, "cls": "GladeFillAdobe"},
]

var atlas

var _rigs: Array = []
var _holders: Array = []
var _pick := 0
var _length := 6.0
var _with_opening := true
var _adobe_cell := 0.3


func setup() -> void:
	_rigs = []
	_holders = []
	for i in MODES.size():
		var h := Node3D.new()
		h.position = Vector3(0, 0, i * -6.0)   # three bays, back to front
		atlas.stage.add_child(h)
		_holders.append(h)
		_rigs.append(Rig.new())
	_rebuild()


func teardown() -> void:
	for rig in _rigs:
		rig.dispose()


func on_step(dir: int) -> void:
	_pick = posmod(_pick + dir, MODES.size())
	atlas.refresh()


func _rebuild() -> void:
	var ok := true
	for i in MODES.size():
		var rig = _rigs[i]
		rig.dispose()                          # free last pass's markers before making new ones
		rig.style_path = MODES[i].style
		rig.points = [Vector3.ZERO, Vector3(_length, 0, 0)]
		rig.wall_height = 2.6
		rig.storeys = []
		rig.openings = _openings(rig)
		rig.adobe_cell = _adobe_cell if i == 2 else 0.0
		if not rig.build(_holders[i]):
			ok = false
			continue
		rig.render(_holders[i], 99, false)
	# masonry is the one with a real GladeWall equivalent to check against; the other two share the
	# same pipeline and differ only in the strategy, so one check covers the mechanism
	var v = _rigs[0].verify_against_wall(atlas)
	atlas.set_badge("rig ✓ matches GladeWall (%d pieces)" % v.mine if (ok and v.ok)
			else "rig ✗ DIVERGED %d vs %d" % [v.mine, v.theirs], ok and v.ok)


## One window, so all three modes have to split around the same hole — the thing they genuinely
## share. `GladeOpeningSet` is what both the courses and the clay grid ask.
##
## Built through `rig.make_opening()` so it carries a real `GladeOpening` marker: without one the
## pipeline reads it as a path crossing and correctly withholds the sill, lintel and frame.
func _openings(rig) -> Array:
	if not _with_opening:
		return []
	return [rig.make_opening(_length * 0.5, 1.1, 1.2, 0.9)]


func build_rows(box: VBoxContainer) -> void:
	var head := Label.new()
	head.text = "one run · one seed · three strategies"
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)

	for i in MODES.size():
		var rig = _rigs[i]
		var mark := "▶ " if i == _pick else "   "
		var count := "%d quads" % rig.clay_quads() if i == 2 else "%d pieces" % rig.total_pieces()
		var b := Tuning.button(box, "%s%s — %s" % [mark, MODES[i].name, count],
				func(): _pick = i; atlas.refresh())
		b.add_theme_font_size_override("font_size", 11)
		var t := Label.new()
		t.add_theme_font_size_override("font_size", 10)
		t.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
		t.text = "      %.2f ms · %s" % [rig.total_ms, MODES[i].cls.replace("GladeFill", "")]
		box.add_child(t)

	var note := Label.new()
	note.add_theme_font_size_override("font_size", 11)
	note.text = "\nNothing above the strategy knows which\none it got. Adding a fourth:\n\n 1  class GladeFillRubble extends GladeFill\n 2  append RUBBLE to GladeStyle.WallMode\n 3  one line in GladeFillRegistry\n\nNo existing class is edited."
	box.add_child(note)

	Tuning.header(box, "the shared run")
	Tuning.slider(box, "length", 3.0, 12.0, 0.5, _length,
			func(v): _length = v; _rebuild(); atlas.refresh())
	Tuning.check(box, "a window in the middle", _with_opening,
			func(on): _with_opening = on; _rebuild(); atlas.refresh())
	Tuning.slider(box, "adobe_cell", 0.12, 0.8, 0.02, _adobe_cell,
			func(v): _adobe_cell = v; _rebuild(); atlas.refresh())

	atlas.show_class(MODES[_pick].cls)
