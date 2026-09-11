extends SceneTree
## FOUR HOUSES — the closing gate for the mass-as-a-building cycle, and a scene you can open.
##
## Every claim this cycle makes is in here, on something you can walk around rather than in a number
## in a log. Left to right:
##
##   1  THE RENDERED COTTAGE   hollow, PANEL, per-face materials: one texture outside, another
##                             inside, a third on the floor. Door and two windows.
##   2  THE STONE HOUSE        hollow, MASONRY, a different `style_inside`, windows with real
##                             reveals, and one outer face carrying a MATERIAL override — so both
##                             systems are visible on one building.
##   3  THE HEXAGONAL KEEP     PRISM, six sides, `side_styles` alternating round the ring, one door.
##   4  THE THICK-WALLED HALL  0.7 m on one wall and 0.15 m on another, so the coping is visibly
##                             uneven, with a solid plinth beside it for the not-hollow case.
##
## IT SAVES ITSELF as `scenes/dev/glade_houses.tscn`, the way `shot_rocha.gd` saves the Rochá plate:
## own everything that is not generated, pack, write. Generated children are INTERNAL_BACK and are
## excluded from `get_children()`, so the scene stores intent and grows its stone back on load.
##
## Needs a real rendering context, so run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1600x860 --script res://scripts/gladekit_tests/shot_houses.gd -- --out=C:/some/folder

const WARMUP := 90                             ## noise textures generate on a thread; give them time
const SCENE_OUT := "res://scenes/dev/gladekit/glade_houses.tscn"
const PANEL_STYLE := "res://addons/gladekit/styles/panel_stone.tres"
const STONE := "res://addons/gladekit/styles/crypt_stone.tres"
const ALSACE := "res://addons/gladekit/styles/alsace_stone.tres"
## THE REAL TEXTURE SETS, which is what `_tinted` was always a stand-in for: a lime render on the
## walls and a terracotta hex floor, both full PBR — albedo, normal, roughness, and occlusion on
## the tiles. Nothing about the kit changed to accept them; they drop into the same two slots.
const RENDER_MAT := "res://assets/materials/glade_plaster_render.tres"
const TILE_MAT := "res://assets/materials/glade_hex_tiles.tres"

var _out := "user://"
var _save := false                             ## `--save` rewrites the scene; see `_run`
var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a == "--save":
			_save = true
	_run()


func _run() -> void:
	_world = Node3D.new()
	_world.name = "GladeHouses"
	root.add_child(_world)
	_sky_and_ground()

	_world.add_child(_cottage(Vector3(-9.5, 0, 0)))
	_world.add_child(_stone_house(Vector3(-2.0, 0, 0)))
	_world.add_child(_keep(Vector3(5.0, 0, 0)))
	_world.add_child(_hall(Vector3(11.5, 0, 0)))
	_world.add_child(_plinth(Vector3(16.5, 0, 0)))
	_world.add_child(_farmhouse(Vector3(-4.0, 0, 9.5)))

	await process_frame
	await process_frame
	_report(_world)

	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true

	# FROM THE FRONT. Every door and window is on the -Z face, so a camera on the +Z side sees four
	# blank backs — which is exactly what the first render of this showed.
	_look(Vector3(2.0, 8.0, -20.0), Vector3(2.0, 1.4, 0.0), 55.0)
	await _shoot("houses_row")

	# STRAIGHT DOWN on the farmhouse: a T outline is a PLAN, and a plan is read from above.
	_look(Vector3(-3.0, 16.0, 10.6), Vector3(-3.0, 0.0, 10.5), 44.0)
	await _shoot("houses_merged_plan")

	# ALL THE WAY ROUND IT, one shot every 45°. Every framing before this stood to the south-west and
	# reported on the two faces that have no junction in them at all — the reentrant corners are on
	# the north-east, and a defect there survives any number of photographs of the other side. A ring
	# leaves nowhere to hide, and the name says where the camera stood.
	var farm := Vector3(-4.0, 1.2, 11.2)
	for k in 8:
		var a := TAU * float(k) / 8.0
		_look(farm + Vector3(sin(a), 0.0, cos(a)) * 13.5 + Vector3.UP * 7.5, farm, 42.0)
		await _shoot("farm_%03d" % int(round(rad_to_deg(a))))

	# THE TWO REENTRANT CORNERS, CLOSE AND LOW. This is where the wing's wall band and the hall's meet
	# and where the light came through, and a low camera is the test: anything not closed shows the
	# sky or the grass behind it rather than the shadow of a room.
	_look(Vector3(0.8, 1.9, 14.2), Vector3(-1.9, 1.3, 11.3), 46.0)
	await _shoot("farm_corner_east")
	_look(Vector3(-9.4, 1.9, 14.4), Vector3(-4.9, 1.3, 11.3), 46.0)
	await _shoot("farm_corner_west")

	# ...and from inside the wing, looking back through the mouth into the hall — the join from the
	# side that has to be a doorway rather than a hole.
	_look(Vector3(-3.4, 1.6, 13.4), Vector3(-3.4, 1.2, 9.5), 74.0)
	await _shoot("farm_mouth")

	# FROM THE FLOOR, LOOKING UP. Every other camera in this file is at eye height or above it, and
	# the underside of a merge is the one place none of them reaches: the soffit over the mouth where
	# the hall carries on above the wing's roof, and the coping seen from beneath, which is where a
	# strip left hanging in the air shows as a wedge rather than as a line.
	_look(Vector3(-3.4, 0.5, 12.6), Vector3(-3.4, 3.2, 10.2), 68.0)
	await _shoot("farm_up_mouth")
	_look(Vector3(-2.5, 0.5, 10.2), Vector3(-1.6, 3.0, 11.4), 68.0)
	await _shoot("farm_up_corner")

	# ...AND OVER ITS WALL, which is the view a plan cannot give: from here the partition is a WALL
	# with a room behind it and the join is an opening you could walk through, not a line and a gap.
	# Eye height inside a 3 m room only ever renders one wall very close up — a roofless building is
	# read from above the eaves.
	_look(Vector3(-9.5, 11.5, 5.2), Vector3(-3.6, 0.8, 10.6), 46.0)
	await _shoot("houses_merged_inside")

	# AT EYE LEVEL IN THE WEST ROOM, looking through the partition's door at the east one. A hole
	# in a solid block is the one thing in this cycle a plan cannot show at all: from above it is
	# a gap in a line either way.
	_look(Vector3(-5.5, 1.6, 9.1), Vector3(-2.6, 1.2, 9.1), 58.0)
	await _shoot("houses_partition_door")

	# INSIDE the cottage. "You can walk in" and "the reveal is closed" are claims only an interior
	# shot supports — from outside, a solid block and a hollow one are the same picture.
	# From the BACK of the room, looking at the wall with the door and windows in it. Standing in the
	# middle put the camera 2 m off a 5 m wall, which fills the frame with one texture and shows
	# nothing — the interior of a small room needs the back corner and a wide lens.
	_look(Vector3(-9.5, 1.8, 1.5), Vector3(-9.5, 0.9, -2.2), 80.0)
	await _shoot("houses_inside")

	# ON the doorway, at an angle, which is the only view that shows whether a reveal has depth.
	_look(Vector3(-7.6, 1.7, -5.2), Vector3(-9.5, 1.1, -2.5), 42.0)
	await _shoot("houses_close")

	# ...AND ONLY IF ASKED. This wrote the scene on every run, which is fine while the scene is its
	# OUTPUT and destructive the moment it is somebody's INPUT: open it, move a box to show what is
	# wrong, run the shots to look at what you moved, and the run puts the box back. `--save` now.
	if _save:
		_save_scene()
	quit(0)


# ---------------------------------------------------------------- the four ------------------


## 1. PANEL throughout, and a different material on the outside, the inside and the floor — the
## per-face material path end to end.
func _cottage(at: Vector3) -> GladeMass:
	var st: GladeStyle = load(PANEL_STYLE)
	var m := _house("Cottage", at, Vector3(5.0, 3.0, 5.0), st)
	m.face_materials = {
		"front": _tinted(Color(0.86, 0.80, 0.68), 1.4),      # limewashed street front
		"left": _tinted(Color(0.72, 0.66, 0.56), 1.4),
		"right": _tinted(Color(0.72, 0.66, 0.56), 1.4),
		"back": _tinted(Color(0.68, 0.63, 0.54), 1.4),
		"left.inner": _tinted(Color(0.90, 0.88, 0.83), 3.0), # plaster: bigger tile, softer
		"right.inner": _tinted(Color(0.90, 0.88, 0.83), 3.0),
		"front.inner": _tinted(Color(0.90, 0.88, 0.83), 3.0),
		"back.inner": _tinted(Color(0.90, 0.88, 0.83), 3.0),
		"floor": _tinted(Color(0.45, 0.34, 0.24), 0.8),      # boards
	}
	_hole(m, Vector3(0, 0, -2.5), 1.1, 2.0, false)           # door, front
	_hole(m, Vector3(-1.6, 1.1, -2.5), 0.9, 1.0, false)      # windows either side
	_hole(m, Vector3(1.6, 1.1, -2.5), 0.9, 1.0, false)
	return m


## 2. MASONRY outside, a different style inside, and ONE face wearing a material override — so the
## style system and the material system are visible on the same building.
func _stone_house(at: Vector3) -> GladeMass:
	var outer: GladeStyle = load(STONE)
	var inner: GladeStyle = load(ALSACE)
	var m := _house("StoneHouse", at, Vector3(5.5, 3.2, 5.0), outer)
	m.style_inside = inner
	m.face_materials = {"front": _tinted(Color(0.80, 0.74, 0.62), 1.2)}
	_hole(m, Vector3(0, 0, -2.5), 1.2, 2.1, true)            # an arched door
	_hole(m, Vector3(-1.8, 1.2, -2.5), 0.8, 0.9, false)
	_hole(m, Vector3(1.8, 1.2, -2.5), 0.8, 0.9, false)
	return m


## 3. A ring, not a box: six sides, two styles cycled round them, and one door.
func _keep(at: Vector3) -> GladeMass:
	var a: GladeStyle = load(STONE)
	var b: GladeStyle = a.duplicate()
	var pale: Array[Color] = [Color(0.80, 0.76, 0.64), Color(0.72, 0.68, 0.57)]
	b.palette = pale
	b.palette_weights = PackedFloat32Array([2, 2])
	var m := GladeMass.new()
	m.name = "HexKeep"
	m.shape = GladeMass.Shape.PRISM
	m.sides = 6
	m.size = Vector3(4.4, 4.2, 4.4)
	m.rng_seed = 4
	m.style = a
	var ring: Array[GladeStyle] = [a, b]
	m.side_styles = ring
	m.position = at
	_hole(m, Vector3(0, 0, -2.2), 1.0, 2.0, true)
	return m


## 4. Two wall thicknesses on one building, so the coping is wider on one side than the other.
func _hall(at: Vector3) -> GladeMass:
	var st: GladeStyle = load(PANEL_STYLE)
	var thick: GladeStyle = st.duplicate()
	thick.depth = 0.70
	var thin: GladeStyle = st.duplicate()
	thin.depth = 0.15
	var m := _house("ThickHall", at, Vector3(4.2, 3.4, 4.2), st)
	m.style_left = thick
	m.style_front = thin
	m.face_materials = {"left.top": _tinted(Color(0.55, 0.52, 0.48), 0.7)}
	_hole(m, Vector3(0, 0, -2.1), 1.0, 2.0, false)
	return m


## 5. TWO BOXES, ONE BUILDING — the sketch. Merging is declared by the parent, never inferred from an
## overlap: two masses that merely intersect elsewhere are still two buildings and still resolve by
## rank. Under a `GladeBuilding` neither wins. Each declines to build the part of itself inside the
## other, and *(hall outside wing) + (wing outside hall)* IS the T outline — no polygon union anywhere.
func _farmhouse(at: Vector3) -> GladeBuilding:
	var st: GladeStyle = load(PANEL_STYLE)
	var b := GladeBuilding.new()
	b.name = "Farmhouse"
	b.position = at

	var hall := _house("Hall", Vector3.ZERO, Vector3(7.0, 3.0, 3.4), st)
	hall.face_materials = _dressed()
	_hole(hall, Vector3(-2.2, 0, -1.7), 1.1, 2.0, false)
	b.add_child(hall)

	# LOWER THAN THE HALL BY A THIRD. Merging does not assume one height: the claim is a solid, so the
	# hall's wall behind the wing keeps everything above the wing's roofline and loses everything
	# below it — which only works because each cut is split up the wall as well as along it.
	var wing := _house("Wing", Vector3(0.6, 0, 3.0), Vector3(3.0, 2.1, 4.2), st)
	wing.face_materials = _dressed()
	_hole(wing, Vector3(0.0, 0, 2.1), 1.0, 1.8, false)     # the stem's far end, in the WING's space
	b.add_child(wing)

	# THE PARTITION: a thin box across the hall. It is not a claim — it takes nothing from the hall,
	# it only adds surface where it is inside one, which is exactly what a room divider is.
	# SHORTER THAN THE ROOM IT DIVIDES, by the wall it dies into. Run it the hall's full 3.4 m and its
	# two ends land exactly on the hall's outer faces, where two coplanar skins fight for the same
	# pixels; 3.2 buries them in the wall, which is where a partition's ends belong anyway.
	var divider := GladeMass.new()
	divider.name = "Partition"
	divider.size = Vector3(0.35, 3.0, 3.2)
	divider.position = Vector3(1.4, 0, 0)
	divider.rng_seed = 11
	divider.style = st
	divider.partition = true
	# ...WITH A DOOR IN IT, because two rooms that do not connect are two buildings. A hole through a
	# solid is not the hole a shell takes: it cuts BOTH faces and the reveal spans between them.
	_hole(divider, Vector3(0.0, 0, -0.4), 0.9, 2.0, false)
	b.add_child(divider)
	return b


## ...and the case `hollow` is NOT for: a solid block, which must still be solid.
func _plinth(at: Vector3) -> GladeMass:
	var m := GladeMass.new()
	m.name = "Plinth"
	m.size = Vector3(2.2, 1.2, 2.2)
	m.rng_seed = 8
	m.style = load(PANEL_STYLE)
	m.position = at
	return m


func _house(n: String, at: Vector3, sz: Vector3, st: GladeStyle) -> GladeMass:
	var m := GladeMass.new()
	m.name = n
	m.size = sz
	m.rng_seed = 5
	m.style = st
	m.hollow = true
	m.position = at
	return m


## Recursive, because the farmhouse's masses hang under a GladeBuilding and the flat loop that came
## before it printed four houses and never mentioned the fifth's parts.
func _report(n: Node) -> void:
	for c in n.get_children():
		if c is GladeMass:
			print("[HOUSE] %-14s %s" % [c.name, (c as GladeMass).stats])
		_report(c)


## EVERY FACE OF A ROOM, dressed in the two real sets: render on the walls, their linings, their
## soffits and their copings; tiles on the floor. Named per face rather than per style because that
## is what the per-face slot is FOR — one building, two materials, no second style.
func _dressed() -> Dictionary:
	var render: Material = load(RENDER_MAT)
	var out := {"floor": load(TILE_MAT)}
	for f: String in ["left", "right", "front", "back"]:
		for layer: String in ["", ".inner", ".soffit", ".top"]:
			out[f + layer] = render
	return out


func _hole(m: GladeMass, at: Vector3, w: float, h: float, arched: bool) -> void:
	var o := GladeOpening.new()
	o.name = "Opening"
	o.position = at
	o.width = w
	o.height = h
	o.arched = arched
	m.add_child(o)


## A stand-in material: one tint, one tile scale. Real texture sets drop straight into these two
## slots; the point of the frame is the per-face plumbing, not the art.
func _tinted(c: Color, uv: float) -> StandardMaterial3D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 0.02 / maxf(uv, 0.05)
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	var nm := NoiseTexture2D.new()
	nm.noise = n
	nm.seamless = true
	nm.width = 256
	nm.height = 256
	nm.as_normal_map = true
	nm.bump_strength = 8.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = c
	mat.normal_enabled = true
	mat.normal_texture = nm
	mat.roughness = 0.94
	return mat


# ---------------------------------------------------------------- staging -------------------


func _sky_and_ground() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.60, 0.68, 0.78)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.65
	env.environment = e
	_world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-36, -134, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	_world.add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pl := PlaneMesh.new()
	pl.size = Vector2(120, 120)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.38, 0.44, 0.27)
	pl.material = gm
	ground.mesh = pl
	_world.add_child(ground)


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = from
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.fov = fov


func _shoot(name: String) -> void:
	for i in WARMUP:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %s   %s (%d x %d)" % ["ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])


## The intent survives as a scene: own everything that is not generated, pack, save. Generated
## children are INTERNAL_BACK and excluded from `get_children()`, so nothing built ends up stored.
func _save_scene() -> void:
	_cam.queue_free()                              # a saved scene does not want the shot camera
	_own(_world)
	var packed := PackedScene.new()
	if packed.pack(_world) == OK and ResourceSaver.save(packed, SCENE_OUT) == OK:
		print("[SCENE] saved %s" % SCENE_OUT)
	else:
		print("[SCENE] FAILED to save %s" % SCENE_OUT)


func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = _world
		if c.scene_file_path == "":
			_own(c)
