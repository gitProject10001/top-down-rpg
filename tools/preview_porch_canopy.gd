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
	var house := House.new(); house.name="CasaComposta"; house.width=6; house.depth=8; house.wall_height=6; house.roof_height=2.5
	house.openings=[{"kind":"door","wall":0,"u":-0.35},{"kind":"window","wall":0,"u":0.45,"y":1.5}]
	world.add_child(house); house.owner=world
	var volumes := Node3D.new(); volumes.name="Volumes"; house.add_child(volumes); volumes.owner=world
	for i in 2:
		var body=preload("res://addons/house_builder/volume.gd").new(); body.name="Portico" if i==0 else "Tettoia"
		body.canopy_roof=1 if i==0 else 0; body.structure_kind=1; body.width=4.2 if i==0 else 3.2; body.depth=3.6 if i==0 else 4.0
		body.wall_height=2.8; body.roof_height=1.2; body.host_wall=0; body.post_spacing=2.5
		if i==1: body.attached=false; body.position=Vector3(6,0,1)
		volumes.add_child(body); body.owner=world
	var porch=house.authored_volumes()[0]
	var supports := Node3D.new(); supports.name="Supports"; porch.add_child(supports); supports.owner=world
	for point in porch.automatic_posts():
		var post=preload("res://addons/house_builder/support.gd").new()
		post.name="Sostegno_%02d"%(supports.get_child_count()+1); post.position=point
		post.section=0.32 if point.z>0.5 else 0.18
		if point.z>0.5: post.position.x*=0.85
		supports.add_child(post); post.owner=world
	var links := Node3D.new(); links.name="FrameLinks"; porch.add_child(links); links.owner=world
	for pair in [[1,3],[0,1],[2,3]]:
		var link=preload("res://addons/house_builder/frame_link.gd").new(); link.name="Trave_%02d"%(links.get_child_count()+1)
		link.support_a=supports.get_child(pair[0]).support_id; link.support_b=supports.get_child(pair[1]).support_id
		link.section=0.24; link.brace_drop=0.75
		links.add_child(link); link.owner=world
	house.rebuild()
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=23
	camera.position=Vector3(25,32,25); world.add_child(camera); camera.owner=world; camera.look_at(Vector3(0,2.8,0))
	var scene := PackedScene.new(); assert(scene.pack(world)==OK)
	assert(ResourceSaver.save(scene,"res://scenes/dev/porch_canopy_example.tscn")==OK)
	print("PORCH_CANOPY_EXAMPLE_SAVED")
	if DisplayServer.get_name()=="headless": quit(); return
	camera.size=23; camera.look_at(Vector3(0,2.5,0))
	root.msaa_3d=Viewport.MSAA_4X
	for frame in 30: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var ui := CanvasLayer.new(); root.add_child(ui)
	var label := Label.new(); label.text="PORTICO + TETTOIA\nTravi e controventi collegati ai sostegni · telaio editabile"; label.position=Vector2(30,30); label.add_theme_font_size_override("font_size",20); ui.add_child(label)
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/balcony_attachment"))
	root.get_texture().get_image().save_png("res://captures/balcony_attachment/porch_canopy.png")
	camera.size=10; camera.position=Vector3(8,6,16); camera.look_at(Vector3(0,2,5))
	label.text="DETTAGLIO TELAIO\nTravi e controventi seguono i sostegni"
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/balcony_attachment/frame_links_detail.png")
	quit()
