extends Node
## Source-scene regression: actual player doors/cutaway and whole lot access routes.
const Migration = preload("res://tools/apply_borgo_recipes.gd")
var failures: PackedStringArray = []
var scene: Node3D
var buildings: Array = []

func _ready() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error("BORGO_CHECK " + message)
func settle(frames: int) -> void:
	for i in frames: await get_tree().physics_frame
func release() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
func move_to(target: Vector3, tolerance := .22, limit := 260) -> bool:
	for frame in limit:
		var delta: Vector3 = target - scene.player.global_position
		delta.y = 0
		if delta.length() < tolerance: release(); return true
		var raw := delta.normalized().rotated(Vector3.UP, -scene.camera.global_rotation.y)
		for pair in [["move_left", -raw.x], ["move_right", raw.x], ["move_up", -raw.z], ["move_down", raw.z]]:
			if pair[1] > 0: Input.action_press(pair[0], pair[1])
			else: Input.action_release(pair[0])
		await get_tree().physics_frame
	release()
	return false

func access_check(lot: Node3D, points := PackedVector3Array()) -> void:
	if points.is_empty(): points=lot.access_path
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3125
	capsule.height = 1.9481
	query.shape = capsule
	query.collision_mask = 1
	var excluded: Array[RID] = [scene.player.get_rid()]
	for door in scene.find_children("*", "AnimatableBody3D", true, false): excluded.append(door.get_rid())
	query.exclude = excluded
	var obstacles := {}
	for i in range(1, points.size()):
		var a: Vector3 = points[i-1]
		var b: Vector3 = points[i]
		var steps := ceili(a.distance_to(b)/.18)
		for j in range(steps+1):
			query.transform = Transform3D(Basis.IDENTITY, lot.to_global(a.lerp(b,float(j)/maxi(1,steps))) + Vector3.UP*1.1)
			for hit in lot.get_world_3d().direct_space_state.intersect_shape(query, 24):
				obstacles[str(hit.collider.get_path())] = true
	check(obstacles.is_empty(), str(lot.name)+" access corridor blocked: "+str(obstacles.keys()))

func entrance_check(house: Node3D) -> void:
	var door_record := {}
	for opening in house.openings:
		if opening.get("kind", "") == "door": door_record=house.resolved_opening(opening); break
	check(not door_record.is_empty(), str(house.get_path())+" missing entrance")
	if door_record.is_empty(): return
	var normal: Vector3 = house.global_basis * house.wall_normal(door_record.wall)
	var threshold: Vector3 = house.to_global(house.wall_point(door_record.wall, door_record.along, 0))
	var exterior := threshold + normal * 1.15
	scene.player.global_position = exterior + Vector3.UP*.8
	scene.player.velocity = Vector3.ZERO
	await settle(25)
	check(is_instance_valid(scene.nearest_door), str(house.get_path())+" door not selectable")
	if is_instance_valid(scene.nearest_door):
		var event := InputEventKey.new(); event.pressed=true; event.keycode=KEY_E
		scene._unhandled_key_input(event)
		await settle(26)
	var inside := threshold - normal * .85
	var entered := await move_to(inside, .28, 100)
	var plan = house.get_node("InteriorPlan")
	check(entered, str(house.get_path())+" cannot enter: "+str(scene.player.global_position)+" target="+str(inside))
	check(scene.interior_states.get(plan.get_instance_id(), Vector2i.ZERO).x == 1, str(house.get_path())+" cutaway did not activate")
	var left := await move_to(exterior, .28, 100)
	check(left, str(house.get_path())+" cannot exit")
	await settle(3)
	check(scene.interior_states.get(plan.get_instance_id(), Vector2i.ZERO).x == 0, str(house.get_path())+" roof did not return")
	print("BORGO_ENTRANCE ", house.get_path(), " entered=", entered, " exited=", left)

func capture(name: String, center: Vector3, span: float, fixed_focus: Variant = null) -> void:
	var viewport: SubViewport = scene.player.get_viewport()
	viewport.get_parent().stretch = false
	viewport.size = Vector2i(1152,648)
	scene.player.global_position = center
	scene.player.velocity=Vector3.ZERO
	var follow_target: Node3D = scene.camera._target
	if fixed_focus is Vector3:
		# An exterior study must not move the player into the building merely to
		# centre the frame: doing that correctly activates gameplay cutaway.
		scene.camera._target = null
		scene.camera._focus = fixed_focus
		scene.camera._have_focus = true
	scene.camera.ortho_size=span
	scene.camera._apply(true)
	await settle(100)
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://captures/"+name+".png")
	scene.camera._target = follow_target
	print("BORGO_CAPTURE ",name)

func performance() -> void:
	var viewport: SubViewport = scene.player.get_viewport()
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var gpu: Array[float]=[]
	var frames: Array[float]=[]
	var start := Time.get_ticks_usec()
	for i in 120:
		await RenderingServer.frame_post_draw
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		var now := Time.get_ticks_usec()
		frames.append((now-start)*.001); start=now
	gpu.sort();frames.sort()
	print("BORGO_PERFORMANCE 1152x648 median_ms=",frames[60]," p95_ms=",frames[114]," GPU_median_ms=",gpu[60]," GPU_p95_ms=",gpu[114])

func run() -> void:
	scene = load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	scene.combat_encounter_enabled=false
	get_tree().root.add_child(scene)
	get_tree().current_scene=scene
	await settle(35)
	var view = scene.get_node("GameplayPreviewRig/Pixel/View")
	for i in Migration.LOTS.size():
		var lot = view.get_node("Borgo/Lotto_"+Migration.LOTS[i])
		var house = lot.get_node("Edificio")
		buildings.append(house)
		check(house.building_recipe != null and house.archetype_id == Migration.ROLES[i], str(lot.name)+" role/order incorrect")
		access_check(lot)
	var home_area: float=buildings[0].width*buildings[0].depth
	check(buildings[2].width*buildings[2].depth>home_area*2.0,"Inn must have a substantially larger main body than a dwelling")
	check(buildings[5].width*buildings[5].depth>home_area*3.5 and buildings[5].width*buildings[5].depth>buildings[2].width*buildings[2].depth*1.5 and buildings[5].depth/buildings[5].width>1.5,"Chapel must dominate ordinary houses and be substantially larger than the inn")
	print("BORGO_ROLE_DIMENSIONS home=",buildings[0].dimensions()," inn=",buildings[2].dimensions()," chapel=",buildings[5].dimensions())
	for i in 6:
		var house = view.get_node("CasaCitta_%02d" % i)
		buildings.append(house)
		check(house.building_recipe != null and house.recipe_provenance.get("variant_id", "") == Migration.VARIANTS[i], str(house.name)+" variant not saved")
		var door: Dictionary=house.resolved_opening(house.openings[0])
		access_check(house,PackedVector3Array([house.wall_point(door.wall,door.along,0,2.4),house.wall_point(door.wall,door.along,0)]))
	var chapel_lot: Node3D=buildings[5].get_parent()
	check(chapel_lot.path_surface!=null and chapel_lot.painted_access_active,"church uses shared painted path coverage")
	var dimensions: Array=[]
	for house in buildings: dimensions.append(house.dimensions())
	var style_key:=InputEventKey.new(); style_key.pressed=true; style_key.keycode=KEY_F7
	var painted_environment: Environment=view.get_node("WorldEnvironment").environment
	var painted_fill: float=view.get_node("SoftSkyFill").light_energy
	check(painted_environment.ssao_enabled and painted_environment.sdfgi_enabled and painted_environment.sdfgi_use_occlusion,"painted lighting retains AO and GI with occlusion")
	check(is_equal_approx(painted_environment.ssao_radius,scene.art_direction.profile.contact_occlusion_radius),"lighting reads the saved profile")
	scene._unhandled_key_input(style_key)
	await settle(3)
	check(not chapel_lot.painted_access_active and chapel_lot._access.visible,"F7 restores the original access ribbon")
	check(view.get_node("WorldEnvironment").environment!=painted_environment,"F7 restores original environment")
	scene._unhandled_key_input(style_key)
	await settle(3)
	check(view.get_node("WorldEnvironment").environment==painted_environment and is_equal_approx(view.get_node("SoftSkyFill").light_energy,painted_fill),"F7 restores painted environment and fill")
	check(chapel_lot.painted_access_active and not chapel_lot._access.visible,"painted path does not retain the rectangular overlay")
	for i in buildings.size(): check(buildings[i].dimensions().is_equal_approx(dimensions[i]),"F7 changed building geometry")
	check(scene.waters.size()==2,"Water simulation lost")
	scene.toggle_overview(); check(scene.overview,"Overview did not activate")
	scene.toggle_overview(); check(not scene.overview and scene.camera.perspective_fov==13.0,"Overview changed normal camera")
	if "--capture-only" not in OS.get_cmdline_user_args():
		for house in buildings: await entrance_check(house)
		for id in Migration.LOTS:
			var lot=view.get_node("Borgo/Lotto_"+id)
			scene.player.global_position=lot.to_global(lot.access_path[0])+Vector3.UP*.6
			scene.player.velocity=Vector3.ZERO
			await settle(20)
			for i in range(1,lot.access_path.size()-1):
				check(await move_to(lot.to_global(lot.access_path[i])), id+" player blocked on access segment "+str(i))
		print("BORGO_ACCESS_PATHS walked six street-to-door routes")
	if DisplayServer.get_name() != "headless":
		Engine.max_fps=0
		await capture("borgo_overview",Vector3(31,1,31),46)
		await capture("borgo_gameplay",Vector3(27,1,24),17.5)
		await performance()
		for i in 6:
			var house: Node3D=buildings[i]
			var door: Dictionary = house.resolved_opening(house.openings[0])
			var outside: Vector3 = house.to_global(house.wall_point(door.wall, door.along, 0, 1.7)) + Vector3.UP*.6
			await capture("borgo_"+Migration.ROLES[i],outside,22 if i in [2,5] else 19,house.global_position+Vector3.UP*3.0)
			if i==5 and "--meadow-comparison" in OS.get_cmdline_user_args():
				var grass=scene.art_direction.grass
				var ground: ShaderMaterial=grass.terrain.material_override
				var region: Vector4=grass.material.get_shader_parameter("meadow_region")
				check(region.z>0,"local meadow region enabled")
				check(ground.get_shader_parameter("meadow_region")==region,"shared world pigment region")
				for state in ["before","still","wind"]:
					for mat in [grass.material,ground]:
						mat.set_shader_parameter("meadow_region",Vector4.ZERO if state=="before" else region)
						mat.set_shader_parameter("meadow_wind_strength",0.0 if state=="still" else 1.0)
					await capture("meadow_"+state,outside,12,outside+Vector3.UP*.5)
				grass.bind_meadow(grass.material); grass.bind_meadow(ground)
			if i==5 and "--portal-closeups" in OS.get_cmdline_user_args():
				var portal: Node3D=house.get_node("RecipeDetails/FacciataGotica")
				await capture("church_portal_close",outside,7.5,portal.to_global(Vector3(0,2.0,0)))
				var saved_yaw: float=scene.camera.yaw_deg
				var saved_pitch: float=scene.camera.pitch_deg
				scene.camera.yaw_deg+=30.0
				scene.camera.pitch_deg=35.0
				await capture("church_portal_oblique",outside,7.5,portal.to_global(Vector3(0,2.0,0)))
				scene.camera.yaw_deg=saved_yaw
				scene.camera.pitch_deg=saved_pitch
				scene.camera._apply(true)
			if i==5 and "--rose-closeup" in OS.get_cmdline_user_args():
				var facade: Node3D=house.get_node("RecipeDetails/FacciataGotica")
				await capture("church_rose_close",outside,5.0,facade.to_global(Vector3(0,facade.dimensions.y*.735,0)))
			if i==5 and "--shadow-comparison" in OS.get_cmdline_user_args():
				var sun: DirectionalLight3D=view.get_node("Sun")
				var angle: float=sun.light_angular_distance
				for sample in [0.0,0.5,1.0]:
					sun.light_angular_distance=sample
					await capture("church_shadow_"+str(sample).replace(".","_"),outside,22,house.global_position+Vector3.UP*3.0)
				sun.light_angular_distance=angle
			if i==5 and "--lighting-comparison" in OS.get_cmdline_user_args():
				var environment: Environment=view.get_node("WorldEnvironment").environment
				var before := environment.duplicate()
				var sun: DirectionalLight3D=view.get_node("Sun")
				var fill: DirectionalLight3D=view.get_node("SoftSkyFill")
				var angular: float=sun.light_angular_distance; var fill_energy: float=fill.light_energy
				print("BORGO_LIGHTING ssao=",environment.ssao_enabled," radius=",environment.ssao_radius," gi=",environment.sdfgi_enabled," gi_occlusion=",environment.sdfgi_use_occlusion," ambient=",environment.ambient_light_energy," fill=",fill_energy," sun_angle=",angular)
				environment.ambient_light_energy=.70; environment.sdfgi_use_occlusion=false
				environment.ssao_radius=.18; environment.ssao_intensity=1.05; environment.ssao_power=1.15
				sun.light_angular_distance=1.8; fill.light_energy=.30
				await capture("church_previous_lighting",outside,22,house.global_position+Vector3.UP*3.0)
				for property in ["ambient_light_energy","sdfgi_use_occlusion","ssao_radius","ssao_intensity","ssao_power"]: environment.set(property,before.get(property))
				sun.light_angular_distance=angular; fill.light_energy=fill_energy
		await capture("borgo_city_variants",Vector3(-29,1,-12),32)
	print("BORGO_CHECK_RESULT buildings=",buildings.size()," failures=",failures)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
