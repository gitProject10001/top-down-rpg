extends RefCounted
## CHAPTER 3 — ARC × HEIGHT, made visible. Law 3 as a picture.
##
## Every wall rule works in `(arc offset along the curve, height above the base)`, and that single
## fact is why a curved wall and a straight one are the same code — there is no special case for a
## bend anywhere in the fill. This chapter draws the domain on a deliberately BENT wall so you can
## watch the frame rotate along it while the rules stay put.
##
## What is drawn, all of it read live from `GladeWallFrame`:
##
##   the curve            `plumb(off)` sampled along its length
##   the frame            `frame(off, ZERO)` — X tangent (red), Y up (green), Z normal (blue)
##   plumb vs plumb_at    the centreline against the SURFACE, separated by the jetty slider
##   fold_dist            shaded along the wall; dark where a corner is near
##
## The last one is the quiet star: the clay's corner rounding, the mitre and the quoins all ask that
## one question, so three features share one definition of "a corner is near".

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Rig := preload("res://scripts/dev/atlas/atlas_rig.gd")

var atlas

var _holder: Node3D
var _overlay: Node3D
var _at := 0.35                                ## where along the wall the frame is drawn, 0..1
var _jetty := 0.25
var _show_wall := true


func setup() -> void:
	_holder = Node3D.new()
	atlas.stage.add_child(_holder)
	_overlay = Node3D.new()
	atlas.stage.add_child(_overlay)
	_rebuild()


func teardown() -> void:
	pass


func on_step(dir: int) -> void:
	_at = clampf(_at + dir * 0.02, 0.0, 1.0)
	_draw()
	atlas.refresh()


func _rebuild() -> void:
	var rig = atlas.rig
	rig.style_path = Rig.STYLE_STONE
	# an L with one sharp fold and one gentle one: enough for fold_dist to say something
	rig.points = [Vector3(-6, 0, 0), Vector3(0, 0, 0), Vector3(4, 0, 3.5), Vector3(9, 0, 3.5)]
	rig.wall_height = 2.6
	rig.weather = 0.0
	rig.storeys = _storeys()
	rig.openings = []
	if not rig.build(_holder):
		atlas.set_badge("rig error: %s" % rig.error, false)
		return
	var v = rig.verify_against_wall(atlas)
	atlas.set_badge("rig ✓ matches GladeWall (%d pieces)" % v.mine if v.ok
			else "rig ✗ DIVERGED %d vs %d" % [v.mine, v.theirs], v.ok)
	rig.render(_holder, 99, false)
	_holder.visible = _show_wall
	_draw()


## Two storeys, so `jetty_at` has something to return and `plumb_at` separates from `plumb`.
func _storeys() -> Array:
	var a := GladeStorey.new()
	a.height = 1.3
	var b := GladeStorey.new()
	b.height = 1.3
	b.jetty = _jetty
	return [a, b]


func _draw() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	var rig = atlas.rig
	if rig.ctx == null:
		return
	var f := rig.ctx.frame as GladeWallFrame
	var h: float = rig.ctx.stack.total_height()

	# --- the curve, and the surface above it -------------------------------------------------
	_line(_sample(f, 0.0, false), Color(1.0, 0.85, 0.35))          # the centreline
	_line(_sample(f, h, true), Color(0.45, 0.85, 1.0))             # the surface at the top

	# --- fold distance, as a shaded ribbon ---------------------------------------------------
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var pos := 0.0
	while pos < f.length:
		var d := minf(f.fold_dist(pos) / 2.0, 1.0)
		var p := f.plumb(pos) + Vector3.UP * (h + 0.35)
		im.surface_add_vertex(p)
		im.surface_add_vertex(p + Vector3.UP * (0.05 + (1.0 - d) * 0.7))
		pos += 0.12
	im.surface_end()
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = im
	ribbon.material_override = GladeDebug.overlay_material(Color(1.0, 0.45, 0.35))
	_overlay.add_child(ribbon)

	# --- the frame at the chosen offset ------------------------------------------------------
	var off := _at * f.length
	var b := f.frame(off, Vector3.ZERO)
	var base := f.plumb(off)
	var surf := f.plumb_at(off, h * 0.99)
	_arrow(base, b.x.normalized(), Color(1.0, 0.35, 0.35))         # X — along the wall
	_arrow(base, Vector3.UP, Color(0.4, 1.0, 0.45))                # Y — up
	_arrow(base, b.z.normalized(), Color(0.4, 0.6, 1.0))           # Z — the wall normal
	# the jetty, drawn as the gap between centreline and surface
	_seg(base + Vector3.UP * (h * 0.99), surf + Vector3.UP * (h * 0.99),
			Color(1.0, 0.85, 0.35))


## The curve sampled the whole way along, at height `y`. `at_surface` picks `plumb_at` (jetty and
## profile applied) over the bare `plumb`, which is exactly the difference this chapter is about.
func _sample(f: GladeWallFrame, y: float, at_surface: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var pos := 0.0
	while pos <= f.length:
		var p := f.plumb_at(pos, y) if at_surface else f.plumb(pos)
		pts.append(p + Vector3.UP * y)
		pos += 0.15
	return pts


func _line(pts: PackedVector3Array, col: Color) -> void:
	if pts.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in pts.size() - 1:
		im.surface_add_vertex(pts[i])
		im.surface_add_vertex(pts[i + 1])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = GladeDebug.overlay_material(col)
	_overlay.add_child(mi)


func _seg(a: Vector3, b: Vector3, col: Color) -> void:
	_line(PackedVector3Array([a, b]), col)


func _arrow(at: Vector3, dir: Vector3, col: Color) -> void:
	var tip := at + dir * 1.2
	var side := dir.cross(Vector3.UP).normalized() * 0.12
	if side.length() < 0.01:
		side = Vector3.RIGHT * 0.12
	_line(PackedVector3Array([at, tip, tip, tip - dir * 0.25 + side,
			tip, tip - dir * 0.25 - side]), col)


func build_rows(box: VBoxContainer) -> void:
	var rig = atlas.rig
	var head := Label.new()
	head.text = "the domain every rule works in"
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)

	var legend := Label.new()
	legend.add_theme_font_size_override("font_size", 11)
	legend.text = "yellow  the curve (plumb)\nblue    the surface (plumb_at)\nred bars  fold_dist — tall = a corner\n\nX along · Y up · Z the wall normal"
	box.add_child(legend)

	if rig.ctx != null:
		var f := rig.ctx.frame as GladeWallFrame
		var off := _at * f.length
		var v := Label.new()
		v.add_theme_font_size_override("font_size", 11)
		v.text = "arc %.2f of %.2f m\nfold_dist %.2f m\nbreaks at %s\noutward %+.0f" % [off,
				f.length, f.fold_dist(off), _fmt(f.breaks), f.outward]
		box.add_child(v)

	Tuning.slider(box, "arc offset", 0.0, 1.0, 0.01, _at, func(x): _at = x; _draw(); atlas.refresh())
	Tuning.slider(box, "jetty", 0.0, 0.5, 0.02, _jetty,
			func(x): _jetty = x; _rebuild(); atlas.refresh())
	Tuning.check(box, "show the wall", _show_wall,
			func(on): _show_wall = on; _holder.visible = on)

	atlas.show_class("GladeWallFrame")


static func _fmt(arr: Array) -> String:
	var out := PackedStringArray()
	for v: float in arr:
		out.append("%.1f" % v)
	return ", ".join(out)
