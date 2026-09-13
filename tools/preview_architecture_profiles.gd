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
	var profiles := [load("res://addons/house_builder/profiles/compact_timber.tres"),load("res://addons/house_builder/profiles/nordic_longhouse.tres")]
	var titles := ["COMPATTA A GRATICCIO", "NORDICO ALLUNGATO", "NORDICO + MODIFICA MANUALE"]
	for i in 3:
		var house := House.new(); house.name=["Compatta","Nordica","NordicaLunghezzaManuale"][i]
		house.apply_architecture(house.architecture_proposal(profiles[0 if i==0 else 1],true))
		if i==2:
			house.depth=14
			house.apply_architecture(house.architecture_proposal(profiles[0]))
			house.apply_architecture(house.architecture_proposal(profiles[1]))
		house.position=Vector3((i-1)*9,0,(1-i)*9)
		house.openings=[{"kind":"door","wall":0,"u":-0.35},{"kind":"window","wall":0,"u":0.45,"y":1.55},{"kind":"window","wall":2,"u":-0.45,"y":1.55},{"kind":"window","wall":2,"u":0.35,"y":1.55}]
		world.add_child(house); house.owner=world
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=36
	camera.position=Vector3(25,32,25); world.add_child(camera); camera.owner=world; camera.look_at(Vector3(0,2,0))
	var scene := PackedScene.new(); assert(scene.pack(world)==OK)
	assert(ResourceSaver.save(scene,"res://scenes/dev/architecture_profiles_example.tscn")==OK)
	print("ARCHITECTURE_PROFILES_EXAMPLE_SAVED")
	if DisplayServer.get_name()=="headless": quit(); return
	root.msaa_3d=Viewport.MSAA_4X
	for frame in 30: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var ui := CanvasLayer.new(); root.add_child(ui)
	for i in 3:
		var label := Label.new(); label.text=titles[i]+"\n"+["5 × 6 m · pareti 4 m", "5 × 11 m · pareti 2,6 m", "Lunghezza 14 m conservata"][i]; label.position=Vector2(30+i*380,35); label.add_theme_font_size_override("font_size",17); ui.add_child(label)
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/architecture_profiles"))
	root.get_texture().get_image().save_png("res://captures/architecture_profiles/comparison.png")
	quit()
