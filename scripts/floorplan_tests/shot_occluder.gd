extends SceneTree
## THE SEE-THROUGH, PHOTOGRAPHED: a finalized 6 × 4 m room, a player capsule inside, the camera
## outside behind the near wall. With OccluderFade on, the wall fades and the capsule shows
## through; off, the wall hides it — and in both shots the wall's shadow lies on the floor,
## because the fade is a view aid, not a material change. NOT headless:
##   Godot_console.exe --path . --resolution 1280x800 --script res://scripts/floorplan_tests/shot_occluder.gd -- --out=C:/some/folder
## Writes <out>/occluder_on.png and <out>/occluder_off.png and prints the pixel colour at the
## player's screen position in each.

const Geo := preload("res://addons/floorplan/core/plan_geometry.gd")
const Baker := preload("res://addons/floorplan/core/plan_baker.gd")
const Kit := preload("res://addons/floorplan/data/blockout_kit.gd")
const Refine := preload("res://addons/floorplan/core/plan_refine.gd")
const Occl := preload("res://scripts/occluder_fade.gd")
const PlanStairScript := preload("res://addons/floorplan/nodes/plan_stair.gd")

var _out := "user://"
var _circle := false   ## --circle: a round room (32 wall pieces) instead of the 6 × 4 box
var _floors := false   ## --floors: two storeys with a stair, the player downstairs


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6).rstrip("/\\") + "/"
		elif a == "--circle":
			_circle = true
		elif a == "--floors":
			_floors = true
	_run()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var kit := Kit.new()
	kit.wall_material = load("res://assets/materials/whinbek_plaster.tres")
	kit.floor_material = load("res://assets/materials/whinbek_rubble.tres")
	var poly: PackedVector2Array = Geo.circle(Vector2(300, 300), 300.0, 32) if _circle \
			else Geo.rect(Vector2(300, 200), Vector2(600, 400))
	var data := {
		"ppm": 100.0,
		"islands": Geo.compute([{"poly": poly, "op": 0}]),
		"doors": [],
		"props": [],
	}
	var at := Vector3(3.0, 0.9, 3.0) if _circle else Vector3(3.0, 0.9, 2.0)
	var prefix := "occluder_circle_" if _circle else "occluder_"
	var cam_ofs := Vector3(0.0, 3.3, 6.5)
	if _floors:
		# Two storeys, the stair along the ground room's far side, the player under the slab.
		var p0 := PlanStairScript.passage_start(4.7, 0.2, 7.56, 0)
		var ground := {"index": 0, "islands": Geo.compute([{"poly": Geo.rect(Vector2(600, 400), Vector2(1200, 800)), "op": 0}]),
				"doors": [], "props": [], "stairs": [{"pos": Vector2(150, 150), "rot": 0.0, "width_m": 1.2,
				"length_m": 0.0, "steps": 0, "footprint": Geo.rect(Vector2(150 + (p0 + 7.56) * 50.0, 150), Vector2((7.56 - p0) * 100.0, 120))}]}
		var upper := {"index": 1, "islands": Geo.compute([{"poly": Geo.rect(Vector2(600, 400), Vector2(1200, 800)), "op": 0}]),
				"doors": [], "props": [], "stairs": []}
		data = {"ppm": 100.0, "pitch": 4.7, "levels": [ground, upper]}
		at = Vector3(6.0, 0.9, 5.0)
		prefix = "occluder_floors_"
		cam_ofs = Vector3(-2.0, 7.0, 9.0)
	var bake: Node3D = Baker.build(data, kit, null, "OcclRoom")
	world.add_child(bake)
	var ops: Array = await Refine.finalize(bake, self)
	Refine.apply_ops(ops, bake)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)

	# The player: a body in a group the fade aims at, wearing a bright capsule. Its own group,
	# not "player" — scripts/hud.gd dereferences `.health` on whatever joins that one.
	var player := CharacterBody3D.new()
	player.add_to_group("occluder_shot_player")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	col.shape = cap
	player.add_child(col)
	var vis := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.8
	vis.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.0)
	mat.emission_energy_multiplier = 1.5
	vis.material_override = mat
	player.add_child(vis)
	world.add_child(player)
	player.global_position = at

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(at + cam_ofs, at, Vector3.UP)
	cam.fov = 45.0
	cam.current = true
	var fade := Occl.new()
	fade.target_group = "occluder_shot_player"
	fade.fade_time = 0.15
	world.add_child(fade)

	for i in 40:
		await process_frame
	var on := root.get_viewport().get_texture().get_image()
	on.save_png(_out + prefix + "on.png")
	var px := cam.unproject_position(player.global_position + Vector3.UP * 0.3)
	var c_on := on.get_pixel(int(px.x), int(px.y))
	fade.enabled = false
	for i in 40:
		await process_frame
	var off := root.get_viewport().get_texture().get_image()
	off.save_png(_out + prefix + "off.png")
	var c_off := off.get_pixel(int(px.x), int(px.y))
	print("[SHOT] wrote %s%son.png / %soff.png; player pixel on %s, off %s" % [_out, prefix, prefix, c_on, c_off])
	quit(0)
