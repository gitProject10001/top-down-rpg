extends SceneTree
## Actual playable scene, same camera, four light rigs, identical material/exposure.
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in range(16): await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	var scene=load("res://scenes/dev/hearth_village_playable.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	await settle()
	var world=scene.get_node("Pixel/View")
	var cam: Camera3D=world.get_node("IsoCam")
	assert(world.msaa_3d==Viewport.MSAA_4X and not world.use_taa)
	assert(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")==8192)
	assert(is_zero_approx(world.get_node("Sun").light_angular_distance))
	var game_view_axis := cam.global_basis.z
	var game_camera_size := cam.size
	cam.set_process(false)
	cam.set_physics_process(false)
	var house: MeshInstance3D=world.get_node("Camp/hearth_cottage_authored2/hearth_cottage_authored")
	var lighting=world.get_node_or_null("LightingPreview")
	if lighting==null:
		lighting=load("res://scripts/village/lighting_preview.gd").new()
		world.add_child(lighting)
	var key := InputEventKey.new()
	key.physical_keycode=KEY_F6
	key.pressed=true
	Input.parse_input_event(key)
	await settle()
	assert(lighting.preset==0,"F6 must reach the lighting controller inside the SubViewport")
	key.pressed=false
	Input.parse_input_event(key)
	await settle()
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var original: Mesh=load("res://assets/models/roof_relief/cottage_source.res")
	var original_mat := ShaderMaterial.new()
	original_mat.shader=load("res://shaders/pixelart/architecture_clear.gdshader")
	original_mat.set_shader_parameter("painting",load("res://assets/textures/hearth_painted/architecture_clear_v2.png"))
	original_mat.set_shader_parameter("quadrant",Vector2.ZERO)
	original_mat.set_shader_parameter("uv_scale",Vector2(0.83,1.2))
	original_mat.set_shader_parameter("tint",Color(0.7,0.77,0.85,1))
	var relief: Mesh=load("res://assets/models/roof_relief/cottage_relief.res")
	var material: Material=load("res://assets/models/roof_relief/clay.tres")
	assert(house.mesh==relief and house.get_surface_override_material(3)==material,"Playable scene must use the new roof")
	for surface in [0,1,2,4]:
		var source_arrays := original.surface_get_arrays(surface)
		var rebuilt_arrays := relief.surface_get_arrays(surface)
		var a: PackedVector3Array=source_arrays[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array=rebuilt_arrays[Mesh.ARRAY_VERTEX]
		assert(a.size()==b.size(),"Non-roof vertex count must be preserved")
		assert(source_arrays[Mesh.ARRAY_INDEX]==rebuilt_arrays[Mesh.ARRAY_INDEX],"Non-roof topology must be preserved")
		var max_error := 0.0
		for v in a.size(): max_error=maxf(max_error,a[v].distance_to(b[v]))
		print("PRESERVED_SURFACE ",surface," maximum vertex drift=",max_error)
		# ArrayMesh serialization quantizes compressed positions; compare in metres.
		assert(max_error<0.001,"Non-roof geometry must remain within 1 mm")
	var focus: Vector3=house.to_global(Vector3(0,3.3,0))
	var output := "res://captures/roof_lighting"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for framing in ["detail","game"]:
		cam.size=8.2 if framing=="detail" else game_camera_size
		cam.global_position=focus+game_view_axis*40.0
		cam.look_at(focus)
		for index in range(4):
			lighting.apply_preset(index)
			house.mesh=relief
			house.set_surface_override_material(3,material)
			await settle()
			var img: Image=world.get_texture().get_image()
			assert(img.save_png(output+"/%s_%02d.png"%[framing,lighting.HOURS[index]])==OK)
			print("CAPTURE_OK ",framing," ",lighting.HOURS[index])
			if index==1 and ResourceLoader.exists("res://captures/roof_readability/previous_relief.res"):
				var previous_material := ShaderMaterial.new()
				previous_material.shader=load("res://captures/roof_readability/previous_clay.gdshader")
				house.mesh=load("res://captures/roof_readability/previous_relief.res")
				house.set_surface_override_material(3,previous_material)
				await settle()
				world.get_texture().get_image().save_png("res://captures/roof_readability/previous_%s_12.png"%framing)
				house.mesh=relief
				house.set_surface_override_material(3,material)
			if framing=="detail" and index==1:
				house.mesh=original
				house.set_surface_override_material(3,original_mat)
				await settle()
				world.get_texture().get_image().save_png(output+"/before_12.png")
	var board := Image.create(2560,1440,false,Image.FORMAT_RGB8)
	for i in range(4):
		var shot := Image.load_from_file(ProjectSettings.globalize_path(output+"/detail_%02d.png"%lighting.HOURS[i]))
		shot.resize(1280,720,Image.INTERPOLATE_LANCZOS)
		shot.convert(Image.FORMAT_RGB8)
		board.blit_rect(shot,Rect2i(0,0,1280,720),Vector2i((i%2)*1280,(i/2)*720))
	board.save_png(output+"/four_hours.png")
	if FileAccess.file_exists("res://captures/roof_readability/previous_game_12.png"):
		var before := Image.load_from_file(ProjectSettings.globalize_path("res://captures/roof_readability/previous_game_12.png"))
		var after := Image.load_from_file(ProjectSettings.globalize_path(output+"/game_12.png"))
		var compare := Image.create(720,360,false,Image.FORMAT_RGB8)
		var crop := Rect2i(after.get_width()/2-180,after.get_height()/2-180,360,360)
		before.convert(Image.FORMAT_RGB8)
		after.convert(Image.FORMAT_RGB8)
		compare.blit_rect(before,crop,Vector2i.ZERO)
		compare.blit_rect(after,crop,Vector2i(360,0))
		compare.save_png("res://captures/roof_readability/game_comparison.png")
	print("ROOF_PREVIEW_OK same material across four lights, two framings")
	quit()
