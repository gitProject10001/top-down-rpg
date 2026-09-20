extends SceneTree
const Detail = preload("res://addons/house_builder/recipe_detail.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var debug := root.get_node_or_null("Dbg")
	if debug: debug.clean = true
	root.size = Vector2i(1280,960)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.12,.14,.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.64,.72,.78)
	environment.ambient_light_energy = .55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = .8
	environment.ssao_intensity = 1.4
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	sun.light_color = Color(1,.89,.74)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 35
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(18,16)
	floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(.31,.335,.31)
	floor_mat.roughness = 1.0
	floor_mat.metallic_specular = 0.0
	floor.material_override = floor_mat
	world.add_child(floor)
	for i in Detail.KINDS.size():
		var kind: String = Detail.KINDS[i]
		var detail: Node3D = Detail.new()
		detail.kind = kind
		detail.dimensions = Detail.default_dimensions(kind)
		detail.detail_seed = 154+i
		detail.position = Vector3(float(i%3)*4.0-4.0,0,floorf(i/3.0)*3.6-3.6)
		if kind == "hanging_sign": detail.motif = "tankard"
		world.add_child(detail)
		var label := Label3D.new()
		label.text = kind.replace("_"," ")
		label.font_size = 44
		label.pixel_size = .007
		label.modulate = Color(.91,.91,.83)
		label.outline_modulate = Color(.12,.14,.14)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = detail.position+Vector3(0,.15,1.05)
		world.add_child(label)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.2
	camera.position = Vector3(6,12,17)
	world.add_child(camera)
	camera.look_at(Vector3(0,.4,0))
	camera.current = true
	root.msaa_3d = Viewport.MSAA_4X
	for frame in 90: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	root.get_texture().get_image().save_png("res://captures/recipe_details_front.png")
	camera.position = Vector3(-6,14,-17)
	camera.look_at(Vector3(0,.4,0))
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/recipe_details_rear.png")
	print("RECIPE_DETAILS_RENDERED front/rear at1280x960")
	world.queue_free()
	await process_frame
	quit()
