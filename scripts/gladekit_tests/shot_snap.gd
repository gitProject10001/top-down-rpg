extends SceneTree
## A TERRACE, BUILT BY SNAPPING — and the same terrace built by eye, for comparison.
##
## The suite proves `GladeAnchor` returns the right number. This answers the question the suite
## cannot: does the right number produce a STREET?
##
## It matters because a junction is not approximately a junction. `GladeSeam` finds a seam where two
## solids actually MEET, and the rules that dress one fire on that or on nothing.
##
## WHAT THE TWO OVERLAYS ACTUALLY SHOW, which is more specific than "it does not work":
##
##   by eye     `corner`s and `valley`s, and NO `patch` anywhere. The roofs still meet — a 0.4 m
##              overhang comfortably bridges a 0.2 m gap — so the valley rule fires and the street
##              looks plausible from here. The WALLS never touch. There is no buried party face, so
##              `buried_style` has nothing to apply to and each house keeps a full outdoor skin on a
##              wall that is supposed to be indoors.
##   snapped    the same corners and valleys, plus `patch 6.5 m²` at every joint — the party walls
##              are genuinely buried against each other, which is the seam a terrace is made of.
##
## So the failure is not that a sloppy street looks sloppy. It is that it looks fine, and the one
## rule that had something to say about a shared wall was never asked.
##
## Four houses, each placed at a DELIBERATELY sloppy offset from the last — the sort of error a drag
## leaves behind. The left pass keeps those positions. The right pass hands each one to
## `GladeAnchor.snap_point()` first, exactly as the gizmo does on every mouse-move.
##
## Needs a real rendering context, so run it WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1500x820 --script res://scripts/gladekit_tests/shot_snap.gd -- --out=C:/some/folder

const WARMUP := 30
const STONE := "res://addons/gladekit/styles/alsace_stone.tres"
const TIMBER := "res://addons/gladekit/styles/alsace_timber.tres"

## What a mouse leaves behind: never quite zero, never quite the same twice.
const SLOP := [0.19, -0.24, 0.14]

var _out := "user://"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.71, 0.80)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.72, 0.82)
	e.ambient_light_energy = 0.65
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47, -125, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(120, 120)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.46, 0.28)
	pl.material = gm
	ground.mesh = pl
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.position = Vector3(-1.0, 9.5, 21.0)
	cam.look_at_from_position(cam.position, Vector3(-1.0, 2.6, 0.0), Vector3.UP)
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true

	# ONE TERRACE AT A TIME, IN THE SAME PLACE. Standing them side by side in one scene was the first
	# attempt and it quietly defeated the experiment: `REACH` is 20 m, both rows had identical
	# layouts, and every house in the snapped row found its opposite number in the other row offering
	# a perfect candidate exactly where it already stood. Separate passes also mean the two pictures
	# share a camera, which is what makes them comparable at all.
	var b := await _terrace(world, Vector3(-11, 0, -2), false)
	await _shoot("snap_by_eye")
	await _seams(b, "snap_by_eye_seams")
	b.free()

	var s := await _terrace(world, Vector3(-11, 0, -2), true)
	await _shoot("snap_snapped")
	await _seams(s, "snap_snapped_seams")
	quit(0)


## THE PAIR THAT SETTLES IT. The seam overlay draws only junctions that were actually FOUND, so it
## reads as a direct answer to "did these buildings meet": a labelled corner, valley and buried patch
## at each party joint, or bare wall where there is a gap.
func _seams(bldg: GladeBuilding, name: String) -> void:
	GladeDebug.show_seams = true
	for w in bldg.get_children():
		if w is GladeWall:
			(w as GladeWall).rebuild()
	await _shoot(name)
	GladeDebug.show_seams = false


## Four houses in a row, each set down a little out of true. With `snapped` on, each one asks the
## anchor where it belongs before it is left there.
func _terrace(world: Node3D, at: Vector3, snapped: bool) -> GladeBuilding:
	var bldg := GladeBuilding.new()
	bldg.name = "Snapped" if snapped else "ByEye"
	bldg.position = at
	world.add_child(bldg)

	var span := 4.6
	var prev: GladeWall = null
	for i in 4:
		var w := _house(span, i)
		bldg.add_child(w)
		# Rank rising along the street, so each house cuts into the one before it and the party joint
		# is a seam a rule can dress rather than two walls standing in the same place.
		w.junction_rank = i
		if prev == null:
			w.position = Vector3.ZERO
		else:
			# Where a drag would have left it: a wall's thickness along, plus a bit of slop.
			var st: GladeStyle = GladeUtil.current_style(w.style)
			w.position = prev.position + Vector3(span + st.depth + SLOP[i - 1], 0, 0)
			await process_frame
			if snapped:
				_snap_into_place(w, prev, span)
		await process_frame
		prev = w
	for i in 3:
		await process_frame
	return bldg


## MOVE THE WHOLE HOUSE THE WAY A DRAG WOULD MOVE ONE PEARL.
##
## The gizmo snaps the CURSOR and lets the pearl follow; here there is no cursor, so the wall's own
## leading edge stands in for one: ask the anchor where that edge should be, and shift the node by
## the difference. Same call, same candidate set, same answer — `snap_point` does not know or care
## that nobody is holding a mouse.
func _snap_into_place(w: GladeWall, prev: GladeWall, span: float) -> void:
	var anchor := GladeAnchor.gather(w)
	if anchor.planes.is_empty():
		push_warning("shot_snap: nothing to snap to — the terrace will not junction")
		return
	var edge := w.to_global(Vector3(0.0, 0.0, span * 0.5))     # middle of this house's near wall
	var got: Dictionary = anchor.snap_point(edge)
	if String(got.get("kind", "")) == "":
		push_warning("shot_snap: house %s found no face within reach" % w.name)
		return
	var delta: Vector3 = (got.pos as Vector3) - edge
	w.position += delta
	w.rebuild()
	print("[SNAP] %s  %s  moved %+.3f m in x" % [w.name, got.kind, delta.x])


func _house(span: float, i: int) -> GladeWall:
	var stone: GladeStyle = load(STONE)
	var timber: GladeStyle = load(TIMBER)
	var deep := 5.0
	var w := GladeWall.new()
	w.name = "House%d" % i
	var c := Curve3D.new()
	for p in [Vector3.ZERO, Vector3(span, 0, 0), Vector3(span, 0, deep), Vector3(0, 0, deep),
			Vector3.ZERO]:
		c.add_point(p)
	w.curve = c
	w.plan_mode = GladeWall.PlanMode.BOX
	w.rng_seed = 3 + i * 7                     # same street, four different masons
	w.style = stone
	w.storeys = [_storey(2.4, 0.0, stone), _storey(2.3, 0.28, timber)]

	_hole(w, Vector3(span * 0.5, 0.0, deep), 1.1, 2.0)
	_hole(w, Vector3(span * 0.28, 3.05, deep), 0.85, 1.0)
	_hole(w, Vector3(span * 0.72, 3.05, deep), 0.85, 1.0)

	var roof := GladeRoof.new()
	roof.name = "Roof"
	roof.style = timber
	roof.pitch_degrees = 50.0
	roof.overhang = 0.4
	roof.rng_seed = 3 + i * 7
	w.add_child(roof)
	return w


func _storey(h: float, jetty: float, st: GladeStyle) -> GladeStorey:
	var s := GladeStorey.new()
	s.height = h
	s.jetty = jetty
	s.style = st
	return s


func _hole(w: GladeWall, at: Vector3, width: float, height: float) -> void:
	var o := GladeOpening.new()
	o.position = at
	o.width = width
	o.height = height
	o.arched = false
	w.add_child(o)


func _shoot(name: String) -> void:
	for i in WARMUP:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %s   %s (%d x %d)" % ["ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])
