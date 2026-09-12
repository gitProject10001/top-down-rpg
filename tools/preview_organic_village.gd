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
	var scene := Node3D.new(); scene.name="OrganicVillageWorkshop"; root.add_child(scene)
	var env := WorldEnvironment.new(); env.name="Environment"; env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.15,0.18,0.2)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color(0.65,0.72,0.85); env.environment.ambient_light_energy=0.4; env.environment.ssao_enabled=true; scene.add_child(env)
	var sun := DirectionalLight3D.new(); sun.name="Sun"; sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.2; sun.shadow_enabled=true; scene.add_child(sun)
	var ground := MeshInstance3D.new(); ground.name="Ground"; var mesh := PlaneMesh.new(); mesh.size=Vector2(110,110); ground.mesh=mesh
	var material := StandardMaterial3D.new(); material.albedo_color=Color(0.25,0.28,0.2); ground.material_override=material; scene.add_child(ground); ground.create_trimesh_collision()
	var village := Village.new(); village.name="Villaggio"; village.max_houses=30; village.layout_mode=1; village.auto_surface=true; village.seed_value=3197; scene.add_child(village)
	guide(village,0,"Perimetro",PackedVector2Array([Vector2(-44,-39),Vector2(30,-43),Vector2(43,-25),Vector2(44,30),Vector2(24,43),Vector2(-34,40),Vector2(-45,14)]))
	guide(village,1,"ViaDelMercato",PackedVector2Array([Vector2(-40,17),Vector2(-23,17),Vector2(-9,14),Vector2(7,16),Vector2(22,13),Vector2(40,15)]))
	guide(village,1,"ViaDeiCampi",PackedVector2Array([Vector2(12,-38),Vector2(16,-23),Vector2(15,-8),Vector2(18,4),Vector2(22,13),Vector2(20,28),Vector2(15,39)]))
	guide(village,4,"CorteDelMercato",PackedVector2Array([Vector2(-8,-8),Vector2(5,-8),Vector2(6,6),Vector2(-7,7)]),1)
	guide(village,4,"CorteOccidentale",PackedVector2Array([Vector2(-29,-14),Vector2(-22,-14),Vector2(-21,-6),Vector2(-30,-5)]))
	guide(village,4,"CorteDeiCampi",PackedVector2Array([Vector2(-4,-30),Vector2(3,-30),Vector2(4,-23),Vector2(-4,-22)]))
	guide(village,4,"CorteMeridionale",PackedVector2Array([Vector2(-23,27),Vector2(-14,25),Vector2(-13,32),Vector2(-22,33)]))
	guide(village,4,"CorteOrientale",PackedVector2Array([Vector2(29,-18),Vector2(35,-18),Vector2(35,-9),Vector2(28,-10)]))
	guide(village,4,"CorteDelPozzo",PackedVector2Array([Vector2(1,28),Vector2(9,27),Vector2(9,34),Vector2(1,35)]))
	guide(village,4,"CorteNordOvest",PackedVector2Array([Vector2(-30,-30),Vector2(-24,-30),Vector2(-23,-25),Vector2(-30,-24)]))
	guide(village,4,"CorteSudEst",PackedVector2Array([Vector2(30,26),Vector2(36,25),Vector2(36,31),Vector2(30,32)]))
	village.guides(1)[0].point_widths=PackedFloat32Array([3.0,3.2,3.8,4.4,4.0,3.0])
	village.guides(1)[1].point_widths=PackedFloat32Array([2.8,3.2,3.6,4.0,4.0,3.0,2.8])
	village.entry_road_id="ViaDelMercato"
	var records := village.propose(); assert(not village.failed,village.report); village.apply(records)
	var routes := Village.Network.shared(village,village.snapshot())
	if not routes.is_empty():
		var route: Dictionary=routes[0]; var editable := Guide.new(); editable.kind=5; editable.name="Percorso_"+route.name; editable.stable_id="path_"+route.group; editable.group_id=route.group; editable.points=route.points; editable.point_widths=route.widths; village.add_child(editable)
	var camera := Camera3D.new(); camera.name="Camera"; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=91; scene.add_child(camera); camera.position=Vector3(60,94.3,60); camera.look_at(Vector3.ZERO)
	own(scene,scene); var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/dev/village_organic_example.tscn")==OK)
	print("VILLAGE_DEMO_SAVED lots=",records.size())
	if DisplayServer.get_name()!="headless":
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/village_builder"))
		root.get_texture().get_image().save_png("res://captures/village_builder/organic_layout.png")
	quit()
