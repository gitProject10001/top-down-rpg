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
	var samples := Node3D.new(); samples.name="Rocce"; world.add_child(samples); samples.owner=world
	var sizes := [Vector3(4,3,3),Vector3(3,5,3),Vector3(5,2.2,4),Vector3(4,4,3),Vector3(3.5,3,4),Vector3(5,3.5,3)]
	for i in 6:
		var rock=preload("res://addons/rock_builder/rock.gd").new()
		rock.name="Roccia_%d"%(i+1); rock.rock_seed=31+i*19; rock.dimensions=sizes[i]; rock.strata=2+i%3
		rock.position=Vector3((i%3-1)*7,0,(i/3)*7-3.5)
		samples.add_child(rock); rock.owner=world
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=24
	camera.position=Vector3(20,28,30); world.add_child(camera); camera.owner=world; camera.look_at(Vector3(0,1,0))
	var scene := PackedScene.new(); assert(scene.pack(world)==OK)
	assert(ResourceSaver.save(scene,"res://scenes/dev/rock_generator_examples.tscn")==OK)
	print("MULTI_VOLUME_EXAMPLE_SAVED")
	if DisplayServer.get_name()=="headless": quit(); return
	camera.size=24; camera.look_at(Vector3(0,1,0))
	root.msaa_3d=Viewport.MSAA_4X
	for frame in 30: await process_frame
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var ui := CanvasLayer.new(); root.add_child(ui)
	var label := Label.new(); label.text="R01 · ROCCE PARAMETRICHE\nSeed · proporzioni · strati · fratture"; label.position=Vector2(30,30); label.add_theme_font_size_override("font_size",20); ui.add_child(label)
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/balcony_attachment"))
	root.get_texture().get_image().save_png("res://captures/balcony_attachment/rock_generator_examples.png")
	quit()
