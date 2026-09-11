extends SceneTree
## THE WHINBEK HOUSE, out of masses — `docs/images/references/whinbek-conceptart.jpg` rebuilt with
## `GladeMass` in PANEL mode, a `GladeRoof` on three of the five volumes, and real stylized textures.
##
## WHY THIS SCENE EXISTS. Every fixture so far has been a box, or two boxes, chosen to make one rule
## visible. This one is chosen by somebody else — a painting — and that is a different test: it asks
## whether the pieces compose into a building a person drew before the kit existed.
##
## FIVE VOLUMES, ONE BUILDING. They sit under a single `GladeBuilding`, so they MERGE: the tower
## grows out of the hall instead of standing beside it, the porch opens into it, and the base course
## takes over the bottom of every wall it wraps. That is the whole of the last two cycles' work
## carrying a shape it was not designed for.
##
##   PLINTH   hollow, 0.95 m, a third of a metre proud — a base course, not a slab. Hollow because a
##            solid one would put a platform through the middle of the room, and merged masses must
##            share a base.
##   HALL     hollow box, half-timbered, a steep gable roof
##   TOWER    hollow 8-sided PRISM through the hall's ridge, with a CONE — which the roof chooses on
##            AUTO purely because the mass says it is round
##   PORCH    hollow box against the front, boarded, its own small gable
##   CHIMNEY  solid box, rubble, no roof
##
## Saves itself as `scenes/dev/whinbek_house.tscn`. Render it with `shot_scene.gd`, which never
## writes to a scene:
##   Godot_console.exe --headless --path . --script res://scripts/dev/make_whinbek.gd

const SCENE_OUT := "res://scenes/dev/gladekit/whinbek_house.tscn"
const PANEL_STYLE := "res://addons/gladekit/styles/panel_stone.tres"
const STONE := "res://addons/gladekit/styles/crypt_stone.tres"
const MAT := "res://assets/materials/whinbek_%s.tres"

var _world: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	_world.name = "Whinbek"
	root.add_child(_world)
	_sky_and_ground()

	var b := GladeBuilding.new()
	b.name = "House"
	_world.add_child(b)

	# THE HALL. Long, low walls and a very steep roof — the painting's proportions are roughly one
	# part wall to two parts roof, which is what makes it read as a storybook house rather than as a
	# shed. 52 degrees is at the top of what `pitch_degrees` allows without looking like a spire.
	var hall := _mass("Hall", Vector3(0, 0, 0), Vector3(11.0, 4.6, 6.4), true)
	hall.face_materials = _skin("tudor", "plaster")
	_hole(hall, Vector3(-3.4, 0, -3.2), 1.2, 2.2, false)          # the front door, under the porch
	_hole(hall, Vector3(1.6, 2.6, -3.2), 1.0, 1.1, false)         # upper windows, front
	_hole(hall, Vector3(4.0, 2.6, -3.2), 1.0, 1.1, false)
	_hole(hall, Vector3(-1.0, 2.6, 3.2), 1.0, 1.1, false)         # ...and back
	# THE PLAQUE with the house initials on it, high on the front wall — clear of the porch roof, which
	# stands in front of this wall from x -4.7 to -2.1 and hides everything behind it.
	_roundel(hall, Vector3(-0.6, 3.45, -3.2), 0.8, 0.14)
	b.add_child(hall)
	_roof(hall, GladeRoof.Shape.PRISM, 52.0, 1.0, 0.7)

	# THE BASE COURSE, a third of a metre proud of the hall and hollow, so the merge takes the hall's
	# wall away below its head and the batter is this mass's own. Mossy cobbles, as painted.
	var plinth := _mass("Plinth", Vector3(0, 0, 0), Vector3(11.6, 0.95, 7.0), true)
	plinth.face_materials = _skin("rubble", "rubble")
	# ...AND A CAP STONE THAT OVERSAILS IT. Two flat faces of a box meet in a razor edge, and no
	# texture makes a stone jut out over one; a projecting course does, and throws the shadow line
	# that says "base course" rather than "the wall changed colour here".
	plinth.coping_oversail = 0.07
	plinth.coping_thickness = 0.11
	b.add_child(plinth)

	# THE TOWER. Eight sides, standing through the hall's ridge and taller than it — and the roof
	# puts a CONE on it without being told, because a PRISM mass answers "round" the way a cylinder
	# wall does. That one line is the whole reason this scene is buildable.
	var tower := _mass("Tower", Vector3(2.2, 0, 0.4), Vector3(4.2, 12.0, 4.2), true)
	tower.shape = GladeMass.Shape.PRISM
	tower.sides = 8
	tower.face_materials = _skin("tudor", "plaster", 8)
	_hole(tower, Vector3(2.2, 9.6, -1.7), 0.8, 1.2, true)         # the two lit openings up top
	_hole(tower, Vector3(3.9, 9.6, 0.4), 0.8, 1.2, true)
	b.add_child(tower)
	_roof(tower, GladeRoof.Shape.CONE, 64.0, 0.86, 0.55)

	# THE PORCH, boarded, with its own little gable — the painting's is the one piece of the building
	# at human scale and it is what tells you how big the rest is.
	var porch := _mass("Porch", Vector3(-3.4, 0, -4.3), Vector3(2.6, 2.6, 3.2), true, "timber")
	porch.face_materials = _skin("boards", "boards")
	_hole(porch, Vector3(-3.4, 0, -5.9), 1.4, 2.1, true)
	b.add_child(porch)
	_roof(porch, GladeRoof.Shape.PRISM, 46.0, 1.0, 0.4)

	# THE CHIMNEY. Solid, rubble, running up the hall's east end past the eaves.
	# ...AND NO QUOINS ON IT, on purpose. A rubble stack has no dressed angle, and having one thing in
	# the scene that declines is what shows the knob is a choice rather than a default.
	var flue := _mass("Chimney", Vector3(-4.9, 0, 1.9), Vector3(1.2, 10.2, 1.7), false, "")
	# ...BUT A CHAMFER INSTEAD. The cheap arris: two quads a corner against a quoin's twelve stones,
	# and the whole demonstration of the pair — the same razor edge, answered the cheap way, standing
	# next to four volumes answered the expensive way.
	flue.bevel = 0.04
	flue.face_materials = _skin("rubble", "rubble")
	b.add_child(flue)

	# THE BARN, the open lean-to on the right of the painting — the one place you look straight INTO
	# the building rather than at it. A mouth 2.8 m wide in a boarded wall, which is the widest hole
	# in the scene and therefore the loudest test of whether a hole has sides: before this cycle a
	# reveal existed only where a lining happened to be, and a gap this size shows its two paper
	# edges from halfway across the yard.
	var barn := _mass("Barn", Vector3(6.6, 0, 0.6), Vector3(4.2, 2.9, 5.0), true, "timber")
	barn.face_materials = _skin("boards", "boards")
	_hole(barn, Vector3(6.6, 0, -1.9), 2.8, 2.3, false)
	b.add_child(barn)
	_roof(barn, GladeRoof.Shape.PRISM, 28.0, 1.0, 0.55)

	await process_frame
	await process_frame
	_report(_world)
	_save_scene()
	quit(0)


# ---------------------------------------------------------------- the pieces -----------------


func _mass(n: String, at: Vector3, sz: Vector3, hollow: bool, quoin := "stone") -> GladeMass:
	var m := GladeMass.new()
	m.name = n
	m.size = sz
	m.position = at
	m.style = load(PANEL_STYLE)
	m.hollow = hollow
	m.rng_seed = hash(n) % 97
	# DRESSED ANGLES. Two textured faces meet in a razor edge and no material setting changes that —
	# a stone standing proud of an arris has to BE a stone. `style_quoin` is the only thing in the kit
	# that gives a textured wall a silhouette, and the painting has dressed corners on every volume.
	if quoin != "":
		m.style_quoin = _quoin(quoin)
	return m


## THE STONE AN ARRIS IS MADE OF. Two of them, because a building does not dress every corner in the
## same thing: the painting has stone quoins on its masonry and TIMBER POSTS on its boarded porch,
## which is the same rule (something solid at the angle) answered by whatever that wall is built of.
##
## MUCH darker than the default crypt ramp, and darker than looks right in the inspector: a bright
## sun on a mid-grey brick reads as white concrete, and the first two passes of this both came out
## shouting across the wall instead of sitting in it. Judged in the render, not in the swatch.
func _quoin(kind: String) -> GladeStyle:
	var st: GladeStyle = (load(STONE) as GladeStyle).duplicate()
	var p: Array[Color] = []
	if kind == "timber":
		p = [Color(0.17, 0.13, 0.10), Color(0.14, 0.11, 0.08),
			Color(0.21, 0.16, 0.12), Color(0.12, 0.09, 0.07)]
		st.course_height = 0.55                    # a post is not coursed; long blocks read as one
	else:
		p = [Color(0.40, 0.37, 0.33), Color(0.34, 0.32, 0.29),
			Color(0.45, 0.41, 0.35), Color(0.30, 0.29, 0.27)]
	st.palette = p
	st.palette_weights = PackedFloat32Array([3, 3, 2, 2])
	return st


## A roof on a MASS. Everything here is an ordinary GladeRoof property; the only new thing in the
## world is that its parent is not a wall.
func _roof(host: GladeMass, shape: GladeRoof.Shape, pitch: float, dark: float,
		overhang: float) -> GladeRoof:
	var r := GladeRoof.new()
	r.name = "Roof"
	r.shape = shape
	r.pitch_degrees = pitch
	r.overhang = overhang
	r.rng_seed = hash(host.name) % 53
	r.style = _slate(dark)
	# THE BELL-CAST is most of what makes the painting's roofs read as drawn rather than as CAD: the
	# slope eases as it reaches the eave instead of running straight off it. `GladeRoof` has had the
	# flare since the Rochá plate; it has simply never been asked for by a mass.
	r.eave_flare = 0.28
	r.flare_span = 0.3
	host.add_child(r)
	return r


## EVERY FACE OF A ROOM in one call: `out` on the four walls and their soffits, `inner` on the
## linings and the floor. The painting's walls are one material and its rooms another, which is what
## the per-face slot is for.
func _skin(out: String, inner: String, sides := 0) -> Dictionary:
	var o: Material = load(MAT % out)
	var i: Material = load(MAT % inner)
	# THE HORIZONTAL LAYERS GET THE SAME MATERIAL AS THE WALLS, parallax and all.
	#
	# They briefly did not. A coping seen along its own surface came out as grey soup and it looked
	# exactly like parallax swimming, so the horizontals were given a flat twin — and that was the
	# wrong diagnosis. It was ANISOTROPIC FILTERING: every material sat on Godot's default
	# `LINEAR_WITH_MIPMAPS`, which at a grazing angle picks a mip several levels too coarse. Fixing the
	# filter fixed the coping, the floor and the far end of every wall at once, and the parallax the
	# twins had removed was never the problem.
	# "top" is the CAP of a solid — the chimney's, here. Leave it out and it falls back to the style's
	# own material, which on a rubble stack reads as a cream slab dropped on top of it.
	var d := {"floor": i, "top": o}
	# A PRISM'S FACES ARE NUMBERED, NOT NAMED — `GladeMass.face_key` gives "side0".."sideN" once the
	# shape stops being a box, because "left" means nothing on an octagon. Handing an eight-sided
	# tower a dictionary of left/right/front/back is not an error and does nothing at all: it fell
	# straight through to the style's own material, and the tower came out in the wrong stone.
	var names: Array = ["left", "right", "front", "back"]
	if sides > 0:
		names = []
		for k in sides:
			names.append("side%d" % k)
	for f: String in names:
		d[f] = o
		d[f + ".soffit"] = o
		d[f + ".top"] = o
		d[f + ".cap"] = o           # the face of the coping stone, where it oversails
		d[f + ".inner"] = i
	return d


## A ROOF IS NOT A PANEL WALL, and this is the one place the distinction bites.
##
## A wall in PANEL mode is a SURFACE with UVs, so a tiling texture is exactly right on it. A roof
## lays 1164 instanced shingles, and an instance has only the brick mesh's own UVs — hand it a
## tiling material and every shingle samples its own arbitrary patch, which came out as a flat blue
## lid on the hall and a mottled brown cone on the tower. The roof's detail is GEOMETRY; what it
## wants from a style is a PALETTE.
##
## `GladeRoof.tone` was measured against this very painting (see its comment — 0.23 luminance, 0.40
## saturation), so the palette only has to be slate and the tone does the rest.
func _slate(dark: float) -> GladeStyle:
	var st: GladeStyle = (load(STONE) as GladeStyle).duplicate()
	var p: Array[Color] = [
		Color(0.44, 0.48, 0.57) * dark, Color(0.36, 0.40, 0.50) * dark,
		Color(0.52, 0.55, 0.62) * dark, Color(0.47, 0.46, 0.40) * dark]   # the last one is lichen
	st.palette = p
	st.palette_weights = PackedFloat32Array([3, 3, 2, 1])
	st.material = null
	return st


func _hole(m: GladeMass, at: Vector3, w: float, h: float, arched: bool) -> void:
	var o := GladeOpening.new()
	o.name = "Opening"
	o.position = at - m.position
	o.width = w
	o.height = h
	o.arched = arched
	m.add_child(o)


## THE PLAQUE OVER THE DOOR — the painting's one circular feature, and the reason `GladeOpening` has
## a shape at all rather than a boolean called `arched`.
##
## A recess, not a hole: `depth` stops it inside the wall and gives it a back, which is what a
## carved roundel is. Before this cycle neither half was expressible — a round outline had no way to
## be cut, and an opening in a wall this thick was refused outright rather than becoming a niche.
func _roundel(m: GladeMass, at: Vector3, d: float, deep: float) -> void:
	var o := GladeOpening.new()
	o.name = "Plaque"
	o.position = at - m.position
	o.width = d
	o.height = d
	o.shape = GladeOpening.Shape.ROUND
	o.depth = deep
	m.add_child(o)


# ---------------------------------------------------------------- staging --------------------


func _sky_and_ground() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.89, 0.93)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.75, 0.85)
	e.ambient_light_energy = 0.75
	env.environment = e
	_world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, 36, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	_world.add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.44, 0.47, 0.31)
	gm.roughness = 1.0
	ground.material_override = gm
	_world.add_child(ground)


func _report(n: Node) -> void:
	for c in n.get_children():
		if c is GladeMass:
			print("[MASS] %-9s %s" % [c.name, (c as GladeMass).stats])
		elif c is GladeRoof:
			print("[ROOF] %-9s %s" % [c.get_parent().name, (c as GladeRoof).stats])
		_report(c)


## THE SCENE IS THE HOUSE, NOT A WORLD.
##
## This packed the whole rig — the sun, the environment AND a 90 m ground plane — because that is
## what the standalone render needs. Instanced into somebody else's scene it therefore dropped a
## second sun, a second environment and a floor across everything already standing there. A saved
## building has to be a building; the lighting belongs to whoever is lighting it.
func _save_scene() -> void:
	var house := _world.get_node_or_null(NodePath("House"))
	if house == null:
		print("[SCENE] FAILED — no House to save")
		return
	_own(house, house)
	var packed := PackedScene.new()
	if packed.pack(house) == OK and ResourceSaver.save(packed, SCENE_OUT) == OK:
		print("[SCENE] saved %s (the building only — no sun, no ground)" % SCENE_OUT)
	else:
		print("[SCENE] FAILED to save %s" % SCENE_OUT)


func _own(n: Node, root_of: Node) -> void:
	for c in n.get_children():
		c.owner = root_of
		if c.scene_file_path == "":
			_own(c, root_of)
