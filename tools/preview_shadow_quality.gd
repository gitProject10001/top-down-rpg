extends SceneTree
## A/B in the actual SubViewport; no changes to roof geometry or materials.
var output := "res://captures/shadow_quality"
func _initialize() -> void: call_deferred("run")
func settle(frames: int=24) -> void:
	for i in frames: await process_frame
	await RenderingServer.frame_post_draw
func shot(view: SubViewport,path: String) -> void:
	await settle()
	assert(view.get_texture().get_image().save_png(output+"/"+path+".png")==OK)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var scene=load("res://scenes/dev/hearth_village_playable.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	await settle()
	var view: SubViewport=scene.get_node("Pixel/View")
	var cam: Camera3D=view.get_node("IsoCam")
	var sun: DirectionalLight3D=view.get_node("Sun")
	var fill: DirectionalLight3D=view.get_node("SoftSkyFill")
	var env: Environment=view.get_node("WorldEnvironment").environment
	var lighting=view.get_node("LightingPreview")
	print("ORIGINAL_VIEW msaa=",view.msaa_3d," taa=",view.use_taa," atlas=",ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")," mode=",sun.directional_shadow_mode)
	view.process_mode=Node.PROCESS_MODE_DISABLED
	var house: Node3D=view.get_node("Camp/hearth_cottage_authored2/hearth_cottage_authored")
	var focus: Vector3=house.to_global(Vector3(0,3.3,0))
	cam.global_position=focus+cam.global_basis.z*40.0
	var camera_start := cam.global_transform
	var quick := "--quick" in OS.get_cmdline_user_args()
	for hour in ([1] if quick else [-1,0,1,2,3]):
		if hour>=0: lighting.apply_preset(hour)
		# Fixed historical baseline so this comparison is reproducible after integration.
		var ambient_energy: float=[0.34,0.44,0.25,0.12][hour] if hour>=0 else 0.48
		var fill_energy: float=[0.16,0.20,0.10,0.045][hour] if hour>=0 else 0.48
		for variant in (["before","hard","atlas","aa","split","sharp","temporal"] if quick else ["before","sharp","temporal"]):
			RenderingServer.directional_shadow_atlas_set_size(8192 if variant in ["atlas","sharp","temporal"] else 4096,true)
			view.msaa_3d=Viewport.MSAA_4X if variant in ["aa","sharp","temporal"] else Viewport.MSAA_DISABLED
			view.use_taa=variant=="temporal"
			sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if variant=="split" else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_split_1=0.55 if variant=="split" else 0.1
			sun.directional_shadow_blend_splits=variant=="split"
			sun.light_angular_distance=0.6 if variant=="before" else 0.0
			sun.shadow_blur=1.0 if variant=="before" else 0.85
			sun.shadow_bias=0.04 if hour<0 else 0.045
			sun.shadow_normal_bias=0.35 if hour<0 else 0.25
			fill.light_energy=fill_energy*(1.0 if variant=="before" else (0.50 if hour<0 else 0.8))
			env.ambient_light_energy=ambient_energy*(1.0 if variant=="before" else (0.85 if hour<0 else 0.95))
			await shot(view,"%s_%d"%[variant,hour])
			if hour==1 and not quick:
				for frame in range(12):
					cam.global_position=camera_start.origin+cam.global_basis.x*(float(frame)*cam.size/view.size.y)
					await shot(view,"motion_%s_%02d"%[variant,frame])
				cam.global_transform=camera_start
			print("SHADOW_CAPTURE ",variant," hour=",hour)
		fill.light_energy=fill_energy
		env.ambient_light_energy=ambient_energy
	print("SHADOW_PREVIEW_OK")
	quit()
