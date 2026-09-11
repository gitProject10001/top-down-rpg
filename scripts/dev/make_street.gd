extends SceneTree
## WHINBEK STREET — the same house nine times, which is the scale the engine work is for.
##
## One building has never been the problem. `docs/gladekit-engine-todo.md` is about what happens when
## there are nine of them: a MultiMesh the renderer can only cull whole, no LOD on anything (Godot
## generates mesh LODs at IMPORT and every triangle here is a runtime ArrayMesh), and no occluders at
## all, because the occlusion baker ignores MultiMeshInstance3D — so a village draws straight through
## the house in front of it.
##
## THIS SCENE IS THE MEASUREMENT, not a place. It exists so those three claims can be checked with
## numbers rather than argued about, and it prints them: draw calls, primitives and objects with each
## of the new facilities off and on, from a camera standing in the street.
##
##   Godot_console.exe --path . --resolution 1280x720 --script res://scripts/dev/make_street.gd
##
## Saves `scenes/dev/whinbek_street.tscn`. Needs the house built first — run `make_whinbek.gd`.

const HOUSE := "res://scenes/dev/gladekit/whinbek_house.tscn"
const SCENE_OUT := "res://scenes/dev/gladekit/whinbek_street.tscn"
const ROWS := 3
const COLS := 3
const PITCH := 26.0
## Where the camera stands to be measured: in the street, at head height, looking down it — the one
## viewpoint where occlusion has anything to occlude.
const EYE := Vector3(-30, 1.7, -18)
const LOOK := Vector3(26, 4.0, 14)

var _world: Node3D
var _cam: Camera3D
var _houses: Array[Node3D] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	_world.name = "WhinbekStreet"
	root.add_child(_world)
	_stage()

	var packed: PackedScene = load(HOUSE)
	if packed == null:
		print("[STREET] no %s — run make_whinbek.gd first" % HOUSE)
		quit(1)
		return

	for r in ROWS:
		for c in COLS:
			var h := packed.instantiate() as Node3D
			h.name = "House_%d_%d" % [r, c]
			h.position = Vector3((c - 1) * PITCH, 0, (r - 1) * PITCH)
			# Every other row turned, so the street is not a mirror and the occluders have something
			# to hide behind that is not the same silhouette.
			h.rotation_degrees = Vector3(0, 90.0 * float((r + c) % 4), 0)
			_world.add_child(h)
			_houses.append(h)

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_world.add_child(_cam)
	await process_frame
	_cam.global_position = EYE
	_cam.look_at(LOOK, Vector3.UP)
	for i in 30:
		await process_frame

	print("[STREET] %d houses, %d masses, %d roofs"
			% [_houses.size(), _count(GladeMass), _count(GladeRoof)])
	await _measure()
	_save()
	quit(0)


# ---------------------------------------------------------------- the numbers ------------------


func _measure() -> void:
	print("\n--- what the renderer is actually asked for, from the street ---")
	# BASELINE: everything the addon used to do — one MultiMesh per variant per building, no
	# visibility ranges, no occluders.
	_set_occluders(false)
	_set_range(0.0)
	await _settle()
	var base := _stats()
	print("baseline (no ranges, no occluders)   %s" % _fmt(base))

	_set_range(45.0)
	await _settle()
	var ranged := _stats()
	print("+ visibility_range 45 m              %s   %s" % [_fmt(ranged), _delta(base, ranged)])

	_set_occluders(true)
	await _settle()
	var both := _stats()
	print("+ occluders                          %s   %s" % [_fmt(both), _delta(base, both)])

	# AND THE SETTING THEY NEED. Occluders do exactly nothing until occlusion culling is switched on,
	# and it is OFF by default in Godot — so a project can grow a perfect set of occluders and
	# measure no change at all, which is what the line above shows.
	root.use_occlusion_culling = true
	await _settle()
	var culled := _stats()
	print("+ use_occlusion_culling ON           %s   %s" % [_fmt(culled), _delta(base, culled)])
	print("     (against ranges alone: %s)" % _delta(ranged, culled))

	# ...and the split is not a switch, it is how the MultiMeshes were committed. Report it as a
	# count so the doc can say what it bought.
	print("\nMultiMeshInstance3D nodes in the street: %d  (one per variant per 16 m cluster)"
			% _count(MultiMeshInstance3D))
	print("OccluderInstance3D nodes:               %d" % _count(OccluderInstance3D))


func _settle() -> void:
	for i in 12:
		await process_frame


func _stats() -> Dictionary:
	return {
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}


static func _fmt(s: Dictionary) -> String:
	return "draws %5d  objects %5d  primitives %9d" % [s.draws, s.objs, s.prims]


static func _delta(a: Dictionary, b: Dictionary) -> String:
	return "(draws %+.0f%%, primitives %+.0f%%)" % [
		100.0 * (float(b.draws) - float(a.draws)) / maxf(float(a.draws), 1.0),
		100.0 * (float(b.prims) - float(a.prims)) / maxf(float(a.prims), 1.0)]


func _set_range(m: float) -> void:
	for n in _all(GladeMass):
		(n as GladeMass).detail_range = m
	for n in _all(GladeRoof):
		(n as GladeRoof).detail_range = m


func _set_occluders(on: bool) -> void:
	for n in _all(GladeBuilding):
		(n as GladeBuilding).occlude = on


func _all(t) -> Array:
	var out: Array = []
	_walk(_world, t, out)
	return out


func _walk(n: Node, t, out: Array) -> void:
	for c in n.get_children(true):
		if is_instance_of(c, t):
			out.append(c)
		_walk(c, t, out)


func _count(t) -> int:
	return _all(t).size()


# ---------------------------------------------------------------- staging ----------------------


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_horizon_color = Color(0.62, 0.68, 0.75)
	sm.ground_horizon_color = Color(0.55, 0.58, 0.55)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, 36, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	_world.add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.38, 0.26)
	ground.material_override = gm
	_world.add_child(ground)


func _save() -> void:
	_own(_world, _world)
	var packed := PackedScene.new()
	if packed.pack(_world) == OK and ResourceSaver.save(packed, SCENE_OUT) == OK:
		print("\n[STREET] saved %s" % SCENE_OUT)
	else:
		print("\n[STREET] FAILED to save %s" % SCENE_OUT)


## Own a node so `pack()` saves it — and STOP AT INSTANCED SCENES, which each house is. Recursing
## into one and owning its internals makes pack() serialize broken copies alongside the instance;
## see the same note in `shot_rocha.gd`, which learned it the hard way.
func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		if c.scene_file_path.is_empty():
			_own(c, owner_node)
