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
	var house := House.new()
	house.name="CasaEsempio"
	house.depth=6.5
	house.openings=[{"kind":"door","wall":0,"u":-0.35},{"kind":"window","wall":0,"u":0.45,"y":1.55},{"kind":"window","wall":2,"u":-0.45,"y":1.55},{"kind":"window","wall":2,"u":0.35,"y":1.55}]
	world.add_child(house); house.owner=world
	var camera := Camera3D.new()
	camera.name="Camera"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=12
	camera.position=Vector3(11,13,16)
	world.add_child(camera); camera.owner=world
	camera.look_at(Vector3(0,2,0))
	var scene := PackedScene.new()
	scene.pack(world)
	ResourceSaver.save(scene,"res://scenes/dev/house_builder_playground.tscn")
	root.msaa_3d=Viewport.MSAA_4X
	root.use_taa=false
	for frame in 20: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/house_builder"))
	root.get_texture().get_image().save_png("res://captures/house_builder/house.png")
	house.depth=11.0; house.width=6.0; house.rebuild()
	camera.size=16
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/house_builder/elongated.png")
	house.width=4.2; house.depth=6.5; house.wing_enabled=true
	house.openings.append({"kind":"window","wall":4,"u":0.0,"y":1.5})
	house.rebuild()
	camera.size=15
	camera.position=Vector3(13,16,18)
	camera.look_at(Vector3(1.5,2,0))
	var l_scene := PackedScene.new()
	l_scene.pack(world)
	ResourceSaver.save(l_scene,"res://scenes/dev/house_builder_l_playground.tscn")
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/house_builder/l_house.png")
	camera.position=Vector3(13,17,-16)
	camera.look_at(Vector3(1.5,2,0))
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/house_builder/l_house_back.png")
	camera.position=Vector3(4,3.3,10)
	camera.look_at(Vector3(0,1.3,3.25))
	camera.size=4.8
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/house_builder/openings_close.png")
	print("HOUSE_PREVIEW_OK rectangular and L scenes saved; five views rendered")
	quit()

