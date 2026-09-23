extends SceneTree
## Run headless for CPU timings, or with -- --render-profile for GPU timings.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var start := Time.get_ticks_usec()
	var packed := load("res://scenes/dev/integrated_landscape.tscn") as PackedScene
	var loaded := Time.get_ticks_usec()
	var scene := packed.instantiate()
	var instantiated := Time.get_ticks_usec()
	root.add_child(scene)
	print("PERF_START load_ms=",(loaded-start)/1000.0," instantiate_ms=",(instantiated-loaded)/1000.0," ready_ms=",(Time.get_ticks_usec()-instantiated)/1000.0)
	var view := scene.get_node("GameplayPreviewRig/Pixel/View")
	var grass := view.get_node("PaintedGrass")
	if "--startup-only" in OS.get_cmdline_user_args():
		scene.queue_free()
		await process_frame
		if "--flush-cache" in OS.get_cmdline_user_args():
			while not preload("res://scripts/generation_cache.gd")._pending_saves.is_empty(): await create_timer(.1).timeout
		quit()
		return
	var render_profile := "--render-profile" in OS.get_cmdline_user_args()
	var gpu_samples: Array[float]=[]
	if render_profile: RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	grass.set_physics_process(false)
	await physics_frame
	var samples: Array[float]=[]
	for destination in [Vector3(-42,1,10),Vector3(-34,1,10),Vector3(-26,1,10),Vector3(-42,1,10),Vector3(27,1,24)]:
		view.get_node("Player").position=destination
		for i in 80:
			await physics_frame
			var tick := Time.get_ticks_usec()
			grass._physics_process(1.0/60)
			samples.append((Time.get_ticks_usec()-tick)/1000.0)
			if render_profile:
				await RenderingServer.frame_post_draw
				var gpu := RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
				gpu_samples.append(gpu)
				if gpu>33 or samples[-1]>4: print("PERF_SPIKE destination=",destination," frame=",i," cpu_ms=",samples[-1]," gpu_ms=",gpu)
	samples.sort()
	print("PERF_GRASS median_ms=",samples[samples.size()/2]," p95_ms=",samples[int(samples.size()*.95)]," max_ms=",samples[-1]," chunks=",grass.chunks.size())
	if not gpu_samples.is_empty():
		gpu_samples.sort()
		print("PERF_GPU median_ms=",gpu_samples[gpu_samples.size()/2]," p95_ms=",gpu_samples[int(gpu_samples.size()*.95)]," max_ms=",gpu_samples[-1])
	var house := load("res://addons/house_builder/house.gd").new() as Node3D
	root.add_child(house)
	for width in [4.3,8.1,12.3]:
		house.width=width
		start=Time.get_ticks_usec()
		house.rebuild()
		print("PERF_HOUSE width=",width," rebuild_ms=",(Time.get_ticks_usec()-start)/1000.0)
	house.free()
	scene.queue_free()
	await process_frame
	quit()
