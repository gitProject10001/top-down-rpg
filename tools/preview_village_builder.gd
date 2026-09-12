extends SceneTree
const Village=preload("res://addons/village_builder/village.gd")
const Guide=preload("res://addons/village_builder/guide.gd")
func _initialize() -> void: call_deferred("run")
func guide(parent: Node,kind: int,title: String,points: PackedVector2Array,type: int=0,floors: int=1) -> void:
	var g := Guide.new(); g.kind=kind; g.name=title; g.stable_id=title; g.points=points; g.building_type=type; g.storeys=floors; parent.add_child(g)
func own(node: Node,scene: Node) -> void:
	if node!=scene: node.owner=scene
	for child in node.get_children(): own(child,scene)
func run() -> void:
	var scene := Node3D.new(); scene.name="VillageWorkshop"; root.add_child(scene)
	var env := WorldEnvironment.new(); env.name="Environment"; env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.18,0.2)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color(0.65,0.72,0.85); env.environment.ambient_light_energy=0.4; env.environment.ssao_enabled=true; scene.add_child(env)
	var sun := DirectionalLight3D.new(); sun.name="Sun"; sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.2; sun.shadow_enabled=true; scene.add_child(sun)
	var ground := MeshInstance3D.new(); ground.name="Ground"; var mesh := PlaneMesh.new(); mesh.size=Vector2(90,75); ground.mesh=mesh
	var material := StandardMaterial3D.new(); material.albedo_color=Color(0.25,0.28,0.2); ground.material_override=material; scene.add_child(ground); ground.create_trimesh_collision()
	var village := Village.new(); village.name="Villaggio"; village.max_houses=12; scene.add_child(village)
	guide(village,0,"Perimetro",PackedVector2Array([Vector2(-30,-24),Vector2(30,-24),Vector2(30,24),Vector2(-30,24)]))
	guide(village,1,"ViaPrincipale",PackedVector2Array([Vector2(-25,0),Vector2(25,0)]))
	guide(village,1,"ViaLaterale",PackedVector2Array([Vector2(0,0),Vector2(0,20)]))
	guide(village,2,"CasePopolane",PackedVector2Array([Vector2(-29,2),Vector2(29,2),Vector2(29,23),Vector2(-29,23)]))
	guide(village,2,"QuartiereBenestante",PackedVector2Array([Vector2(-29,-23),Vector2(29,-23),Vector2(29,-2),Vector2(-29,-2)]),2,2)
	var records := village.propose(); assert(not village.failed,village.report); village.apply(records)
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=68; scene.add_child(camera); camera.position=Vector3(45,70.7,45); camera.look_at(Vector3.ZERO)
	own(scene,scene); var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/dev/village_builder_playground.tscn")==OK)
	print("VILLAGE_DEMO_SAVED lots=",records.size())
	if DisplayServer.get_name()!="headless":
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/village_builder"))
		root.get_texture().get_image().save_png("res://captures/village_builder/layout.png")
	quit()
