extends SceneTree
## THE ASHGROVE HOUSE — a photographed suburban house rebuilt out of `GladeMass` in MODULE mode,
## with a kit of ten blocks modelled in Blender. See `docs/ashgrove-comparison.md` for the reference
## and for what came out right and what did not.
##
## WHY THIS SCENE EXISTS, and why it is not another Whinbek. Whinbek is PANEL: every wall is a
## surface and every detail is a texture, which is the right answer for a hand-painted storybook
## house. This one is the opposite trade and the reference forces it — a builder's house is REGULAR.
## The same shuttered window eleven times, the same louvered vent in every gable, the same bronze
## awning over each bay. That is a modular kit, and a kit is geometry the artist put there rather
## than a picture of geometry.
##
## IT IS ALSO THE TEST THE THREE SOCKETS COULD NOT PASS. `WallMode.MODULE` shipped with exactly
## `module_wall`, `module_window` and `module_door`, and this elevation wants seven blocks on the
## façade alone. `GladeStyle.module_set` is that list with the count taken off, and this scene is what
## made the case for it.
##
##   Main      2 storeys, hip roof — the block everything else is attached to
##   GableL/R  the two big front cross-gables, 2 storeys, stacked windows
##   GableC    the centre gable over the entry, taller and narrower
##   WingL/R   single-storey wings, each with a bay window under a bronze awning
##   Porch     the entry portico: columns, the door, and its own shallow roof
##
## PER-FACE KITS ARE THE POINT. Every mass wears the full seven-role kit on its FRONT and a
## one-role plain kit everywhere else — which is exactly the case that was silently broken before
## `ProcKitSlotPlan`: two kits both number their first block slot 0, and the commit could only pick
## one, so the side of a building was drawn with the front's meshes.
##
##   Godot_console.exe --headless --path . --script res://scripts/dev/make_ashgrove.gd
##
## Then render it with `shot_scene.gd`, which never writes to a scene:
##   Godot_console.exe --path . --resolution 1600x1000 \
##       --script res://scripts/gladekit_tests/shot_scene.gd -- \
##       --scene=res://scenes/dev/gladekit/ashgrove_house.tscn --at=House --out=docs/images/

const SCENE_OUT := "res://scenes/dev/gladekit/ashgrove_house.tscn"
const STAGE_OUT := "res://scenes/dev/gladekit/ashgrove.tscn"
const STYLE_DIR := "res://addons/gladekit/styles/"
const GLB := "res://assets/models/ashgrove_%s.glb"
const SHINGLE := "res://assets/models/ashgrove_shingle.res"

## The kit's real sizes, in metres: width, storey height, wall depth. A storey of 2.9 is what makes
## a 6.4 m block come out as two rows rather than one stretched one.
const STOREY := 2.9
const DEPTH := 0.34

var _world: Node3D
var _kit: ProcKitSet
var _plain: ProcKitSet
var _front: GladeStyle
var _side: GladeStyle
var _gable: GladeStyle


func _initialize() -> void:
	_run()


func _run() -> void:
	_build_styles()

	_world = Node3D.new()
	_world.name = "Ashgrove"
	root.add_child(_world)
	_sky_and_ground()

	var b := GladeBuilding.new()
	b.name = "House"
	_world.add_child(b)

	# THE MAIN BLOCK. Two storeys and a HIP roof — the reference's roof runs round all four sides and
	# the gables are attached to it rather than cut out of it, which is why this is one mass with a
	# hip and the gables are their own.
	var main := _mass("Main", Vector3(0, 0, 0), Vector3(16.0, 6.4, 9.0))
	_hole(main, Vector3(-6.2, 0.9, -4.5), 1.6, 1.5, &"window")
	_hole(main, Vector3(6.2, 0.9, -4.5), 1.6, 1.5, &"window")
	b.add_child(main)
	_roof(main, GladeRoof.Shape.PYRAMID, 34.0, 0.85, true)

	# THE TWO BIG CROSS-GABLES. Two rows each, so one window marker gives a window on both storeys —
	# which is what the reference has and is the whole rhythm of the elevation.
	# A GABLE FACES THE WAY ITS MASS IS LONG. `GladeRoof` runs a PRISM's ridge along the longer
	# horizontal axis, so a SQUARE mass is a coin toss and the first pass of these came out with
	# their ridges along X — two roof slopes facing the street where two gables were wanted, and
	# nothing in the stats to say so. Deeper than wide is what points a gable at the camera.
	for spec: Array in [["GableL", -5.1], ["GableR", 5.1]]:
		var g := _mass(spec[0], Vector3(spec[1], 0, -4.6), Vector3(4.4, 6.4, 5.6))
		_hole(g, Vector3(spec[1], 0.9, -7.4), 1.7, 1.5, &"window")
		b.add_child(g)
		_roof(g, GladeRoof.Shape.PRISM, 46.0, 0.85, false)

	# THE CENTRE GABLE over the entry — one row, and its own kit.
	#
	# A MODULE FILLS ITS ROW, so a 7.3 m face at a 2.9 m storey is three rows and a vent marker in it
	# is THREE VENTS stacked up the gable. Its style therefore declares one row the height of the
	# whole gable field, and carries a two-role kit — wall and vent — whose vent block has its louvers
	# authored into the upper third. That is what puts one vent near the peak, which is the only place
	# a gable vent belongs.
	var gc := _mass("GableC", Vector3(0, 0, -3.9), Vector3(3.2, 7.3, 4.4))
	gc.style_front = _gable
	_hole(gc, Vector3(0, 0.0, -6.1), 1.4, 7.0, &"vent")
	b.add_child(gc)
	_roof(gc, GladeRoof.Shape.PRISM, 50.0, 0.85, false)

	# THE SINGLE-STOREY WINGS. One row apiece, so a bay marker gives exactly one bay and a vent marker
	# exactly one vent — the reference's ends, where the roof comes down to head height.
	for spec: Array in [["WingL", -10.9], ["WingR", 10.9]]:
		var w := _mass(spec[0], Vector3(spec[1], 0, -2.2), Vector3(5.8, 3.7, 6.6))
		_hole(w, Vector3(spec[1] - 0.7, 0.8, -5.5), 3.2, 1.6, &"bay")
		_hole(w, Vector3(spec[1] + 1.9, 1.9, -5.5), 1.2, 1.2, &"vent")
		b.add_child(w)
		# HIPPED, and for a reason the render found rather than the reference. `GladeRoof._gable_wall`
		# lays the ROOF's stone into the gable triangle, so socketing a Blender shingle strip for the
		# slope also tiles the gable field with shingle strips — the wing ends came out as a stack of
		# horizontal bars. A hip has no gable field, and the reference's wing ends are hipped anyway.
		_roof(w, GladeRoof.Shape.PYRAMID, 40.0, 0.85, true)

	# THE PORTICO. One row, so the door marker is a door once — a two-storey face would have put a
	# second front door on the first floor, which is the honest reason this is its own mass and not a
	# hole in the main block.
	var porch := _mass("Porch", Vector3(0, 0, -6.9), Vector3(5.2, 3.3, 2.4))
	_hole(porch, Vector3(0, 0.0, -8.1), 2.2, 2.6, &"door")
	_hole(porch, Vector3(-2.0, 0.0, -8.1), 0.5, 3.2, &"column")
	_hole(porch, Vector3(2.0, 0.0, -8.1), 0.5, 3.2, &"column")
	b.add_child(porch)
	_roof(porch, GladeRoof.Shape.PRISM, 26.0, 0.85, false)

	await process_frame
	await process_frame
	_report(_world)
	_save_scene()
	_save_stage()
	quit(0)


# ---------------------------------------------------------------- the kit --------------------


## ONE ROLE — a name, the block, what it is in metres, and how a bay that is not that size resolves.
##
## ASPECT is for anything with mouldings the artist drew: a 3.2 m bay marker against a 3.2 m bay
## window is a bay, but a 0.5 m column marker against a stretchy wall panel would be a column smeared
## across half the porch. STRETCH is right for the plain panel and for a window whose surround is
## meant to breathe with the pier either side of it.
func _role(n: StringName, glb: String, size: Vector3,
		fit := ProcKitRole.Fit.STRETCH) -> ProcKitRole:
	var r := ProcKitRole.new()
	r.role_name = n
	r.source = load(GLB % glb)
	r.size = size
	r.fit = fit
	return r


func _build_styles() -> void:
	var A := ProcKitRole.Fit.ASPECT
	_kit = ProcKitSet.new()
	# THE ORDER IS THE SLOT NUMBERING and it is saved into the scene. Append; never reorder.
	var roles: Array[ProcKitRole] = [
		_role(&"wall", "wall", Vector3(1.35, STOREY, DEPTH)),
		_role(&"window", "window", Vector3(1.70, STOREY, DEPTH)),
		_role(&"door", "door", Vector3(2.20, STOREY, DEPTH), A),
		_role(&"bay", "bay", Vector3(3.20, STOREY, DEPTH), A),
		_role(&"vent", "vent", Vector3(1.20, STOREY, DEPTH), A),
		_role(&"column", "column", Vector3(0.50, STOREY, 0.50), A),
		_role(&"awning", "awning", Vector3(3.40, STOREY, DEPTH), A),
	]
	_kit.roles = roles
	_kit.default_size = Vector3(1.35, STOREY, DEPTH)
	_save(_kit, "ashgrove_set.tres")

	# THE PLAIN KIT — one role, for the sides and the back. DELIBERATELY A DIFFERENT LENGTH from the
	# façade kit: seven roles against one is exactly the case that used to bleed, because the buffer
	# was sized from the longest and every kit numbered its blocks from zero.
	_plain = ProcKitSet.new()
	var only: Array[ProcKitRole] = [_role(&"wall", "wall", Vector3(1.35, STOREY, DEPTH))]
	_plain.roles = only
	_plain.default_size = Vector3(1.35, STOREY, DEPTH)
	_save(_plain, "ashgrove_plain_set.tres")

	# THE GABLE KIT — two roles, and a storey as tall as the whole gable field so the face is ONE row.
	# A third length, on purpose: 7 roles, 1 role and 2 roles on three faces of one building is the
	# widest spread of kit sizes in the scene and the sharpest test of the slot plan.
	var gk := ProcKitSet.new()
	var gr: Array[ProcKitRole] = [
		_role(&"wall", "wall", Vector3(1.60, 7.3, DEPTH)),
		_role(&"vent", "vent", Vector3(1.40, 7.3, DEPTH), A),
	]
	gk.roles = gr
	gk.default_size = Vector3(1.60, 7.3, DEPTH)
	_save(gk, "ashgrove_gable_set.tres")

	_front = _module_style(_kit)
	_save(_front, "ashgrove_stucco.tres")
	_side = _module_style(_plain)
	_save(_side, "ashgrove_plain.tres")
	_gable = _module_style(gk)
	_gable.module_size = Vector3(1.60, 7.3, DEPTH)
	_save(_gable, "ashgrove_gable.tres")


## A MODULE STYLE CARRIES NO MATERIAL, and that is not an oversight.
##
## The blocks arrive from Blender with their own materials on their own surfaces — stucco, cast
## stone, stained wood, white trim, glass, bronze — and a `MultiMesh` draws every surface of its mesh
## with that surface's material. Setting `style.material` would override all six with one, which is
## the same lesson `make_whinbek._slate()` records for roofs: a module is AUTHORED SURFACE, and what
## it wants from a style is nothing at all.
func _module_style(kit: ProcKitSet) -> GladeStyle:
	var st := GladeStyle.new()
	st.wall_mode = GladeStyle.WallMode.MODULE
	st.module_set = kit
	st.module_size = Vector3(1.35, STOREY, DEPTH)
	st.module_stretch = 1.30
	st.depth = DEPTH
	st.material = null
	st.value_jitter = 0.0                          # authored colour; a per-instance tint would fight it
	st.palette = [Color.WHITE] as Array[Color]
	st.palette_weights = PackedFloat32Array([1])
	return st


# ---------------------------------------------------------------- the pieces -----------------


## Every mass wears the seven-role kit on its FRONT and the one-role kit on its other three faces.
## Hollow, because a house is a shell and a solid one would put a block through the room.
func _mass(n: String, at: Vector3, sz: Vector3) -> GladeMass:
	var m := GladeMass.new()
	m.name = n
	m.size = sz
	m.position = at
	m.style = _side
	m.style_front = _front
	m.style_left = _side
	m.style_right = _side
	m.style_back = _side
	m.hollow = true
	m.rng_seed = hash(n) % 97
	return m


## A hole that NAMES the block it wants. `width` and `height` decide where the column of modules goes
## and how wide it is; the size of the actual window is whatever was modelled, which is the whole
## trade MODULE makes against PANEL.
func _hole(m: GladeMass, at: Vector3, w: float, h: float, role: StringName) -> void:
	var o := GladeOpening.new()
	o.name = "Op_" + String(role)
	o.position = at - m.position
	o.width = w
	o.height = h
	o.module = role
	o.shape = GladeOpening.Shape.RECT
	m.add_child(o)


## THE ROOF, out of Blender shingles. `brick_meshes` is the socket `GladeRoof._tile_mesh` already
## reads, so an authored strip displaces the procedural brick with no code change — which is the
## claim the handcraft socket has always made and this is the first roof to take it up.
##
## A ROOF WANTS A PALETTE, NOT A MATERIAL, for the reason `make_whinbek._slate()` states: an instance
## carries only its own mesh's UVs, so a tiling texture makes every shingle sample a different patch.
func _roof(host: GladeMass, shape: GladeRoof.Shape, pitch: float, dark: float,
		hip: bool) -> GladeRoof:
	var r := GladeRoof.new()
	r.name = "Roof"
	r.shape = shape
	r.hip = hip
	r.pitch_degrees = pitch
	r.overhang = 0.55
	r.rng_seed = hash(host.name) % 53
	r.style = _shingles(dark)
	r.shingle_row = 0.34
	r.tile_overlap = 1.30
	host.add_child(r)
	return r


func _shingles(dark: float) -> GladeStyle:
	var st := GladeStyle.new()
	var m: Mesh = load(SHINGLE)
	if m != null:
		var meshes: Array[Mesh] = [m]
		st.brick_meshes = meshes
	# Brown asphalt, read off the reference: warm mid-brown with a little variation course to course.
	st.palette = [Color(0.34, 0.30, 0.27) * dark, Color(0.29, 0.25, 0.23) * dark,
			Color(0.39, 0.35, 0.31) * dark, Color(0.31, 0.28, 0.26) * dark] as Array[Color]
	st.palette_weights = PackedFloat32Array([3, 3, 2, 2])
	st.material = null
	return st


func _save(res: Resource, name: String) -> void:
	var path := STYLE_DIR + name
	if ResourceSaver.save(res, path) == OK:
		res.take_over_path(path)
		print("[STYLE] saved %s" % path)
	else:
		print("[STYLE] FAILED %s" % path)


# ---------------------------------------------------------------- staging --------------------


func _sky_and_ground() -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"                  # named, because `_save_stage` looks it up by name
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.60, 0.71, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# COOLER AND WEAKER THAN IT WANTS TO BE. A bright blue ambient at 0.8 washed the cream stucco to
	# a flat lavender and took the shutters with it — the modules' authored colour has to survive the
	# light, and judging that in the render rather than in the swatch is the same lesson
	# `make_whinbek._quoin` records.
	e.ambient_light_color = Color(0.66, 0.71, 0.80)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34, 24, 0)
	sun.light_energy = 1.75
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	_world.add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.38, 0.46, 0.26)
	gm.roughness = 1.0
	ground.material_override = gm
	_world.add_child(ground)


func _report(n: Node) -> void:
	for c in n.get_children():
		if c is GladeMass:
			print("[MASS] %-8s %s" % [c.name, (c as GladeMass).stats])
		elif c is GladeRoof:
			print("[ROOF] %-8s %s" % [c.get_parent().name, (c as GladeRoof).stats])
		_report(c)


## THE SCENE IS THE HOUSE, NOT A WORLD — the sun, the environment and the ground plane are the
## standalone render's, and packing them drops a second sun into whoever instances this.
func _save_scene() -> void:
	var house := _world.get_node_or_null(NodePath("House"))
	if house == null:
		print("[SCENE] FAILED — no House to save")
		return
	_own(house, house)
	var packed := PackedScene.new()
	if packed.pack(house) == OK and ResourceSaver.save(packed, SCENE_OUT) == OK:
		print("[SCENE] saved %s (the building only)" % SCENE_OUT)
	else:
		print("[SCENE] FAILED to save %s" % SCENE_OUT)


## ...AND A SECOND SCENE THAT IS A PLACE, because the first one is deliberately not.
##
## `ashgrove_house.tscn` is the building alone, so instancing it into a level does not drop a second
## sun on everything already there. That makes it unviewable on its own: open it and you get a black
## silhouette, and `shot_scene.gd` adds no light of its own either. So this is the staged twin — the
## house INSTANCED, plus the sun, the sky and the ground it wants to be looked at in.
##
## The house goes in as an instance rather than a copy, so re-running this script updates both.
func _save_stage() -> void:
	var stage := Node3D.new()
	stage.name = "Ashgrove"
	root.add_child(stage)

	var packed_house: PackedScene = load(SCENE_OUT)
	if packed_house == null:
		print("[STAGE] FAILED — no %s to instance" % SCENE_OUT)
		return
	var house := packed_house.instantiate()
	house.name = "House"
	stage.add_child(house)

	for n: Node in [_world.get_node("WorldEnvironment"), _world.get_node("Sun"),
			_world.get_node("Ground")]:
		var dup := n.duplicate()
		stage.add_child(dup)

	# Standing across the street, straight on — the reference photograph's own viewpoint.
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 32.0
	cam.position = Vector3(0, 7.5, -34)
	cam.look_at_from_position(Vector3(0, 7.5, -34), Vector3(0, 4.2, -2), Vector3.UP)
	cam.current = true
	stage.add_child(cam)

	_own(stage, stage)
	var packed := PackedScene.new()
	if packed.pack(stage) == OK and ResourceSaver.save(packed, STAGE_OUT) == OK:
		print("[STAGE] saved %s (the house, lit, with a camera on it)" % STAGE_OUT)
	else:
		print("[STAGE] FAILED to save %s" % STAGE_OUT)


## Own a node so `pack()` saves it — and STOP AT INSTANCED SCENES. Recursing into one and owning its
## internals makes `pack()` serialise broken copies alongside the instance; `make_street.gd` carries
## the same note and learned it the hard way.
func _own(n: Node, root_of: Node) -> void:
	for c in n.get_children():
		c.owner = root_of
		if c.scene_file_path == "":
			_own(c, root_of)
