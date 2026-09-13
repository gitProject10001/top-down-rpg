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
	var house := House.new(); house.name="CasaConBalcone"; house.width=6.0; house.depth=7.0; house.wall_height=5.4; house.roof_height=2.5
	house.openings=[{"kind":"door","wall":0,"u":-0.5},{"kind":"window","wall":0,"u":0.5,"y":1.5},{"kind":"window","wall":2,"u":0.4,"y":4.0},{"kind":"window","wall":2,"u":-0.4,"y":1.5}]
	world.add_child(house); house.owner=world
	var container := Node3D.new(); container.name="Components"; house.add_child(container); container.owner=world
	var balcony=load("res://addons/house_builder/balcony.gd").new(); balcony.name="BalconeIngresso"; balcony.elevation=2.8; balcony.balcony_width=4.0; balcony.door_open=true
	container.add_child(balcony); balcony.owner=world; house.rebuild()
	var plan=load("res://addons/house_builder/plan.gd").new(); plan.name="InteriorPlan"; plan.floor_height=2.8; plan.preview_inside=false
	house.add_child(plan); plan.owner=world
	for i in 2:
		var level := Node3D.new(); level.name="Piano_%d"%(i+1); plan.add_child(level); level.owner=world
	var stairs=load("res://addons/house_builder/plan_element.gd").new(); stairs.name="Scala"; stairs.kind=2; stairs.position=Vector3(-1.6,0,0); stairs.dimensions=Vector3(1.1,2.8,4.0)
	plan.get_child(0).add_child(stairs); stairs.owner=world
	plan.rebuild(); house.rebuild()
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=16
	camera.position=Vector3(25,32,25); world.add_child(camera); camera.owner=world; camera.look_at(Vector3(0,2.8,0))
	var scene := PackedScene.new(); assert(scene.pack(world)==OK)
	assert(ResourceSaver.save(scene,"res://scenes/dev/balcony_attachment_example.tscn")==OK)
	print("BALCONY_EXAMPLE_SAVED")
	if DisplayServer.get_name()=="headless": quit(); return
	root.msaa_3d=Viewport.MSAA_4X
	for frame in 30: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var ui := CanvasLayer.new(); root.add_child(ui)
	var label := Label.new(); label.text="BALCONE AGGANCIATO ALLA FACCIATA\nPorta aperta · vano reale nel muro · pavimento a 2,8 m"; label.position=Vector2(30,30); label.add_theme_font_size_override("font_size",20); ui.add_child(label)
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/balcony_attachment"))
	root.get_texture().get_image().save_png("res://captures/balcony_attachment/comparison.png")
	quit()
