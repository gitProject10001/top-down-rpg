extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var world := Node3D.new(); world.name="StoneWallComparison"; root.add_child(world)
 var environment := WorldEnvironment.new(); environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(0.18,0.20,0.21)
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color(0.72,0.78,0.9); environment.environment.ambient_light_energy=0.35
 environment.environment.ssao_enabled=true; world.add_child(environment)
 var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-42,-30,0); sun.shadow_enabled=true; sun.light_energy=1.2; world.add_child(sun)
 var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(30,16); ground.mesh=plane
 var base := StandardMaterial3D.new(); base.albedo_color=Color(0.23,0.26,0.20); ground.material_override=base; world.add_child(ground)
 var old := MeshInstance3D.new(); old.name="CurrentShader"; var box := BoxMesh.new(); box.size=Vector3(6,3.1,0.56); old.mesh=box; old.position=Vector3(-3.6,1.55,0)
 var mat := ShaderMaterial.new(); mat.shader=load("res://shaders/pixelart/painted_architecture.gdshader"); mat.set_shader_parameter("atlas",load("res://assets/textures/hearth_painted/architecture_clear_v2.png")); mat.set_shader_parameter("tint",Color(0.65,0.63,0.59)); old.material_override=mat; world.add_child(old)
 var sample=load("res://addons/house_builder/stone_wall_sample.gd").new(); sample.name="ModeledStoneSample"; sample.position.x=3.6; world.add_child(sample)
 assert(sample.stone_count>50)
 var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=17.5; camera.position=Vector3(9,9,16); world.add_child(camera); camera.look_at(Vector3(0,1.3,0))
 for node in world.get_children(): node.owner=world
 var scene := PackedScene.new(); assert(scene.pack(world)==OK); assert(ResourceSaver.save(scene,"res://scenes/dev/solid_masonry_comparison.tscn")==OK)
 root.msaa_3d=Viewport.MSAA_4X
 for mode in ["comparison","detail","raking"]:
  if mode!="comparison": camera.size=9; camera.position=Vector3(11,7,12); camera.look_at(Vector3(3.6,1.5,0))
  if mode=="raking": sun.rotation_degrees=Vector3(-18,65,0)
  for i in 120: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/solid_masonry_%s.png"%mode)
 print("SOLID_MASONRY_SAMPLE_OK stones=",sample.stone_count)
 quit()
