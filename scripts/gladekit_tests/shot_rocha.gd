extends SceneTree
## THE ROCHÁ PLATE — a foggy mountain valley, a multi-arched bridge, and a castle under a colossal
## stone head. The proof-of-concept the kit has been building toward: every solid in frame is
## GladeKit intent — walls, towers, keeps, the bridge, both cliffs and the monolith — with only the
## water, the hill, the flags and two rider silhouettes as plain meshes.
##
## What each part of the painting maps to:
##
##   the castle        a GladeBuilding of walls: crenellated curtain (stepped up the hill), a gabled
##                     hall with a cone-spired turret, the great keep with storeys + windows +
##                     chimney, a battlemented wing with a corner turret. Ranks make the junctions.
##   the bridge        ONE BOX WALL with three arched openings driven through it — the same rule
##                     that puts a door in a house puts an arch in a bridge — and a GladePath laid
##                     over the top for the flagstone deck.
##   the cliffs        two open runs in WallMode.ROCK (cliff_granite), leaning in over the valley
##                     with `GladeWall.lean` — the first scene to use it in anger.
##   the stone head    a 14-gon ROCK cylinder wearing a `profile` that swells at the crown, leaned
##                     a few degrees. In the fog it reads as the monument, which is all the painting
##                     lets you see of it either.
##   the atmosphere    depth fog + cool ambient + one warm sun from the upper right.
##
## Also SAVES the intent as `scenes/dev/rocha.tscn` — generated bricks are internal and unowned, so
## the file holds only curves, markers and styles, exactly like every other GladeKit scene.
##
## Run WITHOUT --headless:
##   Godot_console.exe --path . --resolution 1700x900 --script res://scripts/gladekit_tests/shot_rocha.gd -- --out=C:/some/folder

const WARMUP := 90                             ## many heavy walls; let every deferred rebuild land
const SCENE_OUT := "res://scenes/dev/gladekit/rocha.tscn"

var _out := "user://"
var _world: Node3D
var _cam: Camera3D

# -- the shared materials, made once --
var _flag_mat: StandardMaterial3D
var _pole_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
	_run()


func _run() -> void:
	_world = Node3D.new()
	_world.name = "Rocha"
	root.add_child(_world)
	_mats()
	_sky_and_light()
	_terrain()
	_castle()
	_bridge_and_causeway()
	_cliffs_and_head()
	_riders()
	_birds()

	for i in WARMUP:
		await process_frame
	for n in ["CliffLeft", "CliffRight", "Monument"]:
		var w := _world.get_node(n) as GladeWall
		print("[ROCK] %-10s pieces=%d stats=%s" % [n, w.snap_transforms.size(), str(w.stats)])

	_cam = Camera3D.new()
	_cam.name = "Camera"
	_world.add_child(_cam)
	_cam.current = true
	_look(Vector3(-70, 15.0, 55), Vector3(6, 11, -10), 42.0)
	await _shoot("rocha_plate")
	_look(Vector3(-30, 11.0, 30), Vector3(3, 9, -3), 33.0)
	await _shoot("rocha_castle")
	# ...and the arch from the water, where the first bridge showed 3.6 m stones: this framing is the
	# acceptance view for the two-leaf masonry.
	_look(Vector3(-30.5, 2.2, 9.5), Vector3(-24, 3.2, 17.5), 55.0)
	await _shoot("rocha_arch")

	_cam.free()                                # the rig owns the camera in play mode
	var player: Node3D = (load("res://scenes/player/player2.tscn") as PackedScene).instantiate()
	player.name = "Player"
	player.position = Vector3(-66, 4.4, 36.2)
	_world.add_child(player)
	var rig: Node3D = (load("res://scenes/camera_rig.tscn") as PackedScene).instantiate()
	rig.name = "CameraRig"
	_world.add_child(rig)
	rig.set("target_path", NodePath("../Player"))
	var grade: CanvasLayer = (load("res://scenes/fx/painterly_grade.tscn") as PackedScene) 			.instantiate()
	grade.name = "PainterlyGrade"
	grade.layer = 11
	_world.add_child(grade)

	_save_scene()
	quit(0)


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.position = from
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.fov = fov


func _shoot(name: String) -> void:
	for i in 8:
		await process_frame
	var img := root.get_texture().get_image()
	var path := _out + name + ".png"
	var err := img.save_png(path)
	print("[SHOT] %s   %s (%d x %d)" % ["ok" if err == OK else "FAILED",
			ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])


## The intent survives as a scene: walk the tree, own everything that is not generated (generated
## children are INTERNAL_BACK and default-excluded from get_children), pack, save.
func _save_scene() -> void:
	_own(_world)
	var packed := PackedScene.new()
	if packed.pack(_world) == OK and ResourceSaver.save(packed, SCENE_OUT) == OK:
		print("[SCENE] saved %s" % SCENE_OUT)
	else:
		print("[SCENE] FAILED to save %s" % SCENE_OUT)


## Own a node so `pack()` saves it — and STOP AT INSTANCED SCENES. Recursing into one and owning
## its internals makes pack() serialize broken COPIES of everything inside it alongside the
## instance itself: on load the real player spawned next to a duplicate skeleton with no skin
## binding — a grey T-posed mannequin — plus a `Camera3D2` that stole the viewport and a
## `StateMachine2` erroring about states it could not find. An instance is saved by owning its
## ROOT alone; what is inside it is the instance's own business.
func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = _world
		if c.scene_file_path == "":
			_own(c)


# ---------------------------------------------------------------- light and air ---------------


func _mats() -> void:
	_flag_mat = StandardMaterial3D.new()
	_flag_mat.albedo_color = Color(0.78, 0.68, 0.42)
	_flag_mat.roughness = 1.0
	_flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pole_mat = StandardMaterial3D.new()
	_pole_mat.albedo_color = Color(0.16, 0.14, 0.12)
	_pole_mat.roughness = 0.95
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.10, 0.10, 0.11)
	_dark_mat.roughness = 1.0


func _sky_and_light() -> void:
	var env := WorldEnvironment.new()
	env.name = "Air"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.58, 0.65, 0.68)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.60, 0.66)
	e.ambient_light_energy = 1.35
	# THE VALLEY IS MADE OF FOG. Depth fog against a cool background is nine tenths of the plate's
	# atmosphere: the cliffs go flat, the head goes half-legible, and scale arrives for free.
	e.fog_enabled = true
	e.fog_light_color = Color(0.60, 0.67, 0.70)
	e.fog_density = 0.005
	e.fog_sky_affect = 0.85
	env.environment = e
	_world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# From the UPPER RIGHT of the frame, as painted: warm highlights on the sun-facing faces, the
	# left-facing walls and the underside of the bridge arches in shadow.
	sun.rotation_degrees = Vector3(-34, -118, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	_world.add_child(sun)


# ---------------------------------------------------------------- ground and water ------------


func _terrain() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var wp := PlaneMesh.new()
	wp.size = Vector2(1200, 1200)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.13, 0.17, 0.19)
	wm.metallic = 0.55
	wm.roughness = 0.08
	wp.material = wm
	water.mesh = wp
	water.position = Vector3(0, 0.9, 0)
	_world.add_child(water)
	var wade := StaticBody3D.new()
	wade.name = "WadeFloor"
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(1200, 1.0, 1200)
	ws.shape = wb
	ws.position = Vector3(0, 0.15, 0)          # top a hand's width under the surface
	wade.add_child(ws)
	_world.add_child(wade)

	# The promontory: a flattened sphere is a perfectly good grassy hill under this much fog.
	var hill := MeshInstance3D.new()
	hill.name = "Hill"
	var hm := SphereMesh.new()
	hm.radius = 1.0
	hm.height = 2.0
	hm.radial_segments = 48
	hm.rings = 24
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.38, 0.22)
	gm.roughness = 1.0
	hm.material = gm
	hill.mesh = hm
	hill.scale = Vector3(27, 8.5, 23)
	hill.position = Vector3(0, -2.2, 0)
	_world.add_child(hill)
	hill.create_trimesh_collision()

	# ...and the causeway the riders approach on: a long paved shoulder standing out of the water.
	var cw := MeshInstance3D.new()
	cw.name = "Causeway"
	var cb := BoxMesh.new()
	cb.size = Vector3(52, 2.6, 6.2)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.30, 0.30, 0.30)
	cm.roughness = 0.95
	cb.material = cm
	cw.mesh = cb
	cw.position = Vector3(-58, 1.6, 31)
	cw.rotation.y = deg_to_rad(-22)
	_world.add_child(cw)
	cw.create_trimesh_collision()

	# Boulders where the island meets the water — a Rock Line along the shore.
	var rocks := GladeRocks.new()
	rocks.name = "Shore"
	var rc := Curve3D.new()
	for p in [Vector3(-18, 1.4, 13), Vector3(-6, 1.2, 16), Vector3(8, 1.3, 15),
			Vector3(18, 1.4, 9)]:
		rc.add_point(p)
	rocks.curve = rc
	rocks.region_mode = GladeRocks.RegionMode.PATH
	rocks.conform_to_ground = false
	rocks.path_width = 3.4
	rocks.size = 0.8
	rocks.big_chance = 0.2
	rocks.base_color = Color(0.42, 0.42, 0.40)
	rocks.generate_collision = false
	_world.add_child(rocks)


# ---------------------------------------------------------------- the castle ------------------


## Dark, rough-hewn ashlar — the painting's stone, made from the Alsace masonry by swapping the
## palette. `crenellated` variants top the roofless walls with merlons.
func _castle_stone(crenels: bool) -> GladeStyle:
	var st: GladeStyle = (load("res://addons/gladekit/styles/alsace_stone.tres") as GladeStyle) \
			.duplicate()
	st.palette = [
		Color(0.33, 0.30, 0.27), Color(0.29, 0.27, 0.25), Color(0.37, 0.33, 0.28),
		Color(0.26, 0.25, 0.24), Color(0.40, 0.36, 0.30)] as Array[Color]
	st.palette_weights = PackedFloat32Array([3, 3, 2, 2, 1])
	st.crenellated = crenels
	st.door_leaf = null
	st.shutter = null
	st.flower_box = null
	st.wall_lantern = null
	st.hanging_sign = null
	return st


func _dark_slate() -> GladeStyle:
	var st: GladeStyle = (load("res://addons/gladekit/styles/alsace_slate.tres") as GladeStyle) \
			.duplicate()
	st.palette = [
		Color(0.16, 0.17, 0.20), Color(0.13, 0.14, 0.17), Color(0.19, 0.20, 0.23),
		Color(0.11, 0.12, 0.15)] as Array[Color]
	return st


func _storey(h: float, st: GladeStyle) -> GladeStorey:
	var s := GladeStorey.new()
	s.height = h
	s.style = st
	return s


func _box_wall(name: String, at: Vector3, w: float, d: float, h: float, st: GladeStyle,
		rank: int, seed_v: int) -> GladeWall:
	var wl := GladeWall.new()
	wl.name = name
	var c := Curve3D.new()
	for p in [Vector3.ZERO, Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d), Vector3.ZERO]:
		c.add_point(p)
	wl.curve = c
	wl.plan_mode = GladeWall.PlanMode.BOX
	wl.position = at - Vector3(w * 0.5, 0, d * 0.5)
	wl.wall_height = h
	wl.style = st
	wl.junction_rank = rank
	wl.rng_seed = seed_v
	return wl


func _tower(name: String, at: Vector3, r: float, h: float, st: GladeStyle, rank: int,
		seed_v: int, spire: bool) -> GladeWall:
	var t := GladeWall.new()
	t.name = name
	t.position = at
	t.wall_height = h
	t.style = st
	t.junction_rank = rank
	t.rng_seed = seed_v
	root.add_child(t)                          # make_cylinder wants a live node
	t.make_cylinder(r, 14)
	root.remove_child(t)
	if spire:
		var sp := GladeRoof.new()
		sp.name = "Spire"
		sp.shape = GladeRoof.Shape.CONE
		sp.pitch_degrees = 62.0
		sp.overhang = 0.45
		sp.style = _dark_slate()
		sp.rng_seed = seed_v
		t.add_child(sp)
	return t


func _window(wl: GladeWall, at: Vector3, w := 0.85, h := 1.35) -> void:
	var o := GladeOpening.new()
	o.position = at
	o.width = w
	o.height = h
	o.arched = false
	wl.add_child(o)


func _castle() -> void:
	var stone := _castle_stone(false)
	var battl := _castle_stone(true)
	var slate := _dark_slate()

	var castle := GladeBuilding.new()
	castle.name = "Castle"
	castle.position = Vector3(0, 1.5, 2.5)
	_world.add_child(castle)

	# THE STEPPED CURTAIN, following the hill up in two lifts, with the arched gateway in the lower
	# one. An open polyline: the wall, not a building.
	var curtain := GladeWall.new()
	curtain.name = "Curtain"
	var cc := Curve3D.new()
	for p in [Vector3(-14, 0, 6), Vector3(-5, 0, 9), Vector3(6, 0, 8.4)]:
		cc.add_point(p)
	curtain.curve = cc
	curtain.position = Vector3(0, 3.4, 0)
	curtain.wall_height = 5.2
	curtain.style = battl
	curtain.junction_rank = 1
	curtain.rng_seed = 21
	var gate := GladeOpening.new()
	gate.name = "Gate"
	gate.position = Vector3(-3.0, 0, 8.6)
	gate.width = 3.0
	gate.height = 3.9
	gate.arched = true
	curtain.add_child(gate)
	castle.add_child(curtain)

	var curtain2 := GladeWall.new()
	curtain2.name = "CurtainHigh"
	var c2 := Curve3D.new()
	for p in [Vector3(6, 0, 8.4), Vector3(13, 0, 3), Vector3(16, 0, -4)]:
		c2.add_point(p)
	curtain2.curve = c2
	curtain2.position = Vector3(0, 4.4, 0)
	curtain2.wall_height = 4.6
	curtain2.style = battl
	curtain2.junction_rank = 1
	curtain2.rng_seed = 22
	castle.add_child(curtain2)

	# The low round tower guarding the gate's right shoulder.
	castle.add_child(_tower("GateTower", Vector3(7.2, 3.4, 7.6), 2.4, 6.4, battl, 4, 23, false))

	# LEFT: the gabled hall with its cone-spired turret.
	var hall := _box_wall("Hall", Vector3(-9.5, 4.3, 0.5), 7.0, 6.0, 7.2, stone, 2, 24)
	var hall_roof := GladeRoof.new()
	hall_roof.name = "Roof"
	hall_roof.pitch_degrees = 56.0
	hall_roof.overhang = 0.5
	hall_roof.style = slate
	hall_roof.rng_seed = 24
	hall.add_child(hall_roof)
	_window(hall, Vector3(1.8, 3.2, 6.0), 0.8, 1.1)
	_window(hall, Vector3(4.6, 3.2, 6.0), 0.8, 1.1)
	castle.add_child(hall)
	castle.add_child(_tower("HallTurret", Vector3(-16.2, 4.3, 7.0), 2.0, 11.0, stone, 5, 25, true))

	# CENTRE-RIGHT: the great keep. Storeys of dark stone, deep-set windows in vertical ranks, a
	# pitched roof and a chimney — the painting's dominant mass.
	var keep := _box_wall("Keep", Vector3(4.5, 4.6, -3.5), 8.0, 10.0, 14.0, stone, 3, 26)
	keep.storeys = [_storey(4.8, stone), _storey(4.8, stone), _storey(4.4, stone)] \
			as Array[GladeStorey]
	var keep_roof := GladeRoof.new()
	keep_roof.name = "Roof"
	keep_roof.pitch_degrees = 42.0
	keep_roof.overhang = 0.5
	keep_roof.style = slate
	keep_roof.rng_seed = 26
	var ch := GladeChimney.new()
	ch.name = "Chimney"
	ch.position = Vector3(2.2, 0, 2.8)
	ch.clearance = 1.1
	keep_roof.add_child(ch)
	keep.add_child(keep_roof)
	for fy in [2.6, 7.2, 11.6]:
		_window(keep, Vector3(2.4, fy, 10.0))
		_window(keep, Vector3(5.6, fy, 10.0))
	for fy2 in [2.6, 7.2]:
		_window(keep, Vector3(0.0, fy2, 3.2))
		_window(keep, Vector3(0.0, fy2, 6.8))
	castle.add_child(keep)

	# RIGHT: the battlemented wing and its corner turret.
	var wing := _box_wall("Wing", Vector3(13.0, 4.0, -7.0), 9.0, 6.0, 6.2, battl, 2, 27)
	castle.add_child(wing)
	castle.add_child(_tower("WingTurret", Vector3(17.4, 3.8, -3.4), 1.7, 7.6, battl, 5, 28, false))

	# Flags from the peaks and the wall heads, as painted.
	_flag(Vector3(-9.5, 18.7, 3.0))
	_flag(Vector3(-16.2, 22.6, 9.5))
	_flag(Vector3(8.5, 21.9, -1.0))
	_flag(Vector3(17.4, 13.7, -0.9))
	_flag(Vector3(7.2, 12.1, 10.1))


# ---------------------------------------------------------------- bridge + causeway -----------


func _bridge_and_causeway() -> void:
	# THE BRIDGE IS ONE OPEN RUN — the sketch's two arrows and its arc, verbatim. `depth_override`
	# is the WIDTH arrow: the run is 3.6 m thick without a style of its own. `camber` is the ARC: the
	# deck rises 1.1 m over mid-span through the ground mechanism, so the masonry STEPS over the hump
	# in whole courses the way a real humpback does. The arches are the same `GladeOpening` that
	# makes a door — sill 0, arched — and they ride the camber with everything else.
	var stone := _castle_stone(false)
	var bridge := GladeWall.new()
	bridge.name = "Bridge"
	var bc := Curve3D.new()
	bc.add_point(Vector3.ZERO)
	bc.add_point(Vector3(32, 0, 0))
	bridge.curve = bc
	bridge.position = Vector3(-34.2, 0.5, 20.6)
	bridge.rotation.y = deg_to_rad(27)
	bridge.wall_height = 3.8
	bridge.depth_override = 3.6
	bridge.camber = 1.1
	bridge.style = stone
	bridge.rng_seed = 31
	for ax in [4.5, 12.0, 19.5, 27.0]:
		var arch := GladeOpening.new()
		arch.position = Vector3(ax, 0, 0)
		arch.width = 3.4
		arch.height = 2.5
		arch.arched = true
		bridge.add_child(arch)
	_world.add_child(bridge)

	# THE PARAPETS: the same stone, a tenth the thickness — one style serving both is exactly what
	# `depth_override` is for. They stand on the deck and carry the same camber, so their coping
	# steps with the roadway; their collision is the rail that keeps the player out of the water.
	for side in [-1.55, 1.55]:
		var para := GladeWall.new()
		para.name = "ParapetL" if side < 0.0 else "ParapetR"
		var pc := Curve3D.new()
		pc.add_point(Vector3(0.4, 0, side))
		pc.add_point(Vector3(31.6, 0, side))
		para.curve = pc
		para.position = bridge.position + Vector3(0, 3.75, 0)
		para.rotation.y = bridge.rotation.y
		para.wall_height = 1.0
		para.depth_override = 0.28
		para.camber = 1.1
		para.style = stone
		para.rng_seed = 32 if side < 0.0 else 33
		_world.add_child(para)

	# The flagstone deck: a GladePath laid from the causeway, over the bridge, up to the gate.
	var deck := GladePath.new()
	deck.name = "Road"
	var dc := Curve3D.new()
	for p in [Vector3(-74, 3.1, 39), Vector3(-50, 3.2, 29.6), Vector3(-33, 4.45, 20.2),
			Vector3(-26.5, 5.5, 16.9), Vector3(-20, 5.55, 13.6), Vector3(-12, 4.5, 9.6),
			Vector3(-3.4, 5.9, 11.6)]:
		dc.add_point(p)
	deck.curve = dc
	deck.path_width = 3.4
	deck.conform_to_ground = false
	deck.tone = 0.28
	_world.add_child(deck)
	var floor_body := StaticBody3D.new()
	floor_body.name = "RoadFloor"
	var pts := dc
	for si in pts.point_count - 1:
		var a := pts.get_point_position(si)
		var b := pts.get_point_position(si + 1)
		var seg := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(a.distance_to(b) + 0.4, 0.4, 3.6)
		seg.shape = box
		seg.position = (a + b) * 0.5 + Vector3.DOWN * 0.15
		seg.look_at_from_position(seg.position, seg.position + (b - a).normalized(), Vector3.UP)
		seg.rotate_object_local(Vector3.UP, PI * 0.5)
		floor_body.add_child(seg)
	_world.add_child(floor_body)

	# Flag posts: the causeway's left shoulder and the bridge's right barrier, as painted.
	for i in 6:
		var t := float(i) / 5.0
		var p := Vector3(-73, 3.0, 38.4).lerp(Vector3(-38, 3.0, 24.6), t) + Vector3(-1.0, 0, -2.2)
		_flag(p)
	for i2 in 5:
		var t2 := (float(i2) + 0.5) / 5.0
		var p2 := Vector3(-34.5, 5.3, 20.6).lerp(Vector3(-13, 5.4, 9.9), t2) + Vector3(0.55, 0, -1.6)
		p2.y += 1.1 * (1.0 - pow(2.0 * t2 - 1.0, 2.0))
		_flag(p2)


## A pole and a small weathered pennant. The one prop the kit has no socket for, and at this
## distance a quad on a stick is exactly what the painting draws.
func _flag(at: Vector3) -> void:
	var pole := MeshInstance3D.new()
	pole.name = "Flag"
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 3.0, 0.09)
	pm.material = _pole_mat
	pole.mesh = pm
	pole.position = at + Vector3(0, 1.5, 0)
	_world.add_child(pole)
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.0, 0.42, 0.02)
	cm.material = _flag_mat
	cloth.mesh = cm
	cloth.position = Vector3(0.55, 1.28, 0)
	cloth.rotation.y = deg_to_rad(fmod(at.x * 37.0 + at.z * 53.0, 40.0) - 20.0)
	pole.add_child(cloth)


# ---------------------------------------------------------------- cliffs + the head -----------


func _cliffs_and_head() -> void:
	var granite: GladeStyle = (load("res://addons/gladekit/styles/cliff_granite.tres") 			as GladeStyle).duplicate()
	# The plate's cliffs are DARK; the quarry granite is not. Same rock, wet and in shadow.
	granite.palette = [
		Color(0.35, 0.36, 0.37), Color(0.32, 0.33, 0.35)] as Array[Color]
	granite.palette_weights = PackedFloat32Array([3, 2])
	granite.value_jitter = 0.05
	granite.rock_weld = 0.0

	var left := GladeWall.new()
	left.name = "CliffLeft"
	var lc := Curve3D.new()
	for p in [Vector3(-112, 0, 26), Vector3(-92, 0, -6), Vector3(-72, 0, -36)]:
		lc.add_point(p)
	left.curve = lc
	left.position = Vector3(0, -2, 0)
	left.wall_height = 56.0
	left.style = granite
	left.lean = Vector2(0.06, -0.03)           # looming in over the valley
	left.rng_seed = 41
	left.generate_collision = false
	_world.add_child(left)

	var right := GladeWall.new()
	right.name = "CliffRight"
	var rc := Curve3D.new()
	for p in [Vector3(42, 0, 12), Vector3(56, 0, -10), Vector3(64, 0, -34)]:
		rc.add_point(p)
	right.curve = rc
	right.position = Vector3(0, -2, 0)
	right.wall_height = 58.0
	right.style = granite
	right.lean = Vector2(-0.05, -0.03)
	right.rng_seed = 42
	right.generate_collision = false
	_world.add_child(right)

	# THE COLOSSAL HEAD: a rock cylinder wearing a profile that necks in and swells at the crown,
	# leaned a few degrees forward. The displacement does the weathering; the fog does the rest.
	var head := GladeWall.new()
	head.name = "Monument"
	head.position = Vector3(22, -1, -58)
	head.wall_height = 52.0
	var dark_rock: GladeStyle = granite.duplicate()
	dark_rock.palette = [
		Color(0.45, 0.48, 0.51), Color(0.41, 0.44, 0.48)] as Array[Color]
	dark_rock.palette_weights = PackedFloat32Array([3, 2])
	head.style = dark_rock
	head.rng_seed = 43
	head.generate_collision = false
	root.add_child(head)
	head.make_cylinder(15.0, 14)
	root.remove_child(head)
	var pr := Curve.new()
	pr.add_point(Vector2(0.0, 0.86))
	pr.add_point(Vector2(0.5, 0.74))           # the neck
	pr.add_point(Vector2(0.72, 1.0))           # the jaw and brow swell back out
	pr.add_point(Vector2(1.0, 0.62))           # the crown closes
	head.profile = pr
	head.lean = Vector2(0.02, 0.045)
	_world.add_child(head)


# ---------------------------------------------------------------- staffage --------------------


## Two riders on the causeway — silhouettes, exactly as small as the painting keeps them.
func _riders() -> void:
	for i in 2:
		var at := Vector3(-51, 2.95, 28.6) + Vector3(2.6, 0, 1.1) * float(i)
		var horse := MeshInstance3D.new()
		horse.name = "Rider"
		var hb := BoxMesh.new()
		hb.size = Vector3(0.5, 0.85, 2.1)
		hb.material = _dark_mat
		horse.mesh = hb
		horse.position = at + Vector3(0, 0.8, 0)
		horse.rotation.y = deg_to_rad(-24)
		_world.add_child(horse)
		var rider := MeshInstance3D.new()
		var rb := CapsuleMesh.new()
		rb.radius = 0.18
		rb.height = 0.95
		rb.material = _dark_mat
		rider.mesh = rb
		rider.position = Vector3(0, 1.1, -0.15)
		horse.add_child(rider)


func _birds() -> void:
	var pts := [Vector3(-14, 26, -18), Vector3(-8, 28, -22), Vector3(2, 31, -30),
			Vector3(18, 24, -12), Vector3(24, 27, -20), Vector3(-20, 22, -10)]
	for p: Vector3 in pts:
		var b := MeshInstance3D.new()
		b.name = "Bird"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.04, 0.12)
		bm.material = _dark_mat
		b.mesh = bm
		b.position = p
		b.rotation.y = fmod(p.x * 1.7, TAU)
		_world.add_child(b)
