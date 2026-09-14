extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	world.name="HouseWorkshop"
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0.16,0.18,0.20)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(0.65,0.72,0.85)
	environment.environment.ambient_light_energy=0.4
	environment.environment.ssao_enabled=true
	world.add_child(environment); environment.owner=world
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.shadow_enabled=true
	sun.light_color=Color(1,0.93,0.84)
	sun.light_energy=1.2
	world.add_child(sun); sun.owner=world
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(50,50)
	ground.mesh=plane
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(0.25,0.28,0.20)
	material.roughness=1.0
	ground.material_override=material
	world.add_child(ground); ground.owner=world
	for index in 3:
		var house=preload("res://addons/house_builder/polygon_tower.gd").new()
		house.face_count=[8,12,16][index]; house.name="Torre_%d"%house.face_count
		house.width=8; house.depth=8; house.wall_height=6; house.roof_height=0.8; house.wall_finish=1
		house.position.x=(index-1)*11
		var records: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.1,"height":2.1}]
		house.openings=records
		world.add_child(house); house.owner=world; house.rebuild()
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=40
	camera.position=Vector3(25,32,25); world.add_child(camera); camera.owner=world; camera.look_at(Vector3(0,2.8,0))
	var scene := PackedScene.new(); assert(scene.pack(world)==OK)
	assert(ResourceSaver.save(scene,"res://scenes/dev/segmented_towers_example.tscn")==OK)
	print("MULTI_VOLUME_EXAMPLE_SAVED")
	if DisplayServer.get_name()=="headless": quit(); return
	camera.size=40; camera.look_at(Vector3(0,2.5,0))
	root.msaa_3d=Viewport.MSAA_4X
	for frame in 30: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var ui := CanvasLayer.new(); root.add_child(ui)
	var label := Label.new(); label.text="A07.4 · TORRI A 8 / 12 / 16 FACCE\nStesso builder · pianta, solai e parapetti coerenti"; label.position=Vector2(30,30); label.add_theme_font_size_override("font_size",20); ui.add_child(label)
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/balcony_attachment"))
	root.get_texture().get_image().save_png("res://captures/balcony_attachment/segmented_towers.png")
	quit()
