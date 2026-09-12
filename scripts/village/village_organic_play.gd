extends Node
var player: CharacterBody3D
var camera: Camera3D
var village: Node3D
var overview := false
var debug_zones: MeshInstance3D
var prompt: Label
func _ready() -> void:
	var container := SubViewportContainer.new(); container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch=true; container.mouse_filter=Control.MOUSE_FILTER_IGNORE; container.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; add_child(container)
	var view := SubViewport.new(); view.size=Vector2i(1152,648); view.msaa_3d=Viewport.MSAA_4X
	view.handle_input_locally=false; container.add_child(view)
	var world: Node3D=load("res://scenes/dev/village_organic_example.tscn").instantiate(); view.add_child(world)
	village=world.get_node("Villaggio")
	if FileAccess.file_exists("user://village_builder_playtest.tscn") and not "--organic-example" in OS.get_cmdline_user_args():
		world.remove_child(village); village.free()
		village=load("user://village_builder_playtest.tscn").instantiate(); world.add_child(village)
	world.get_node("Camera").queue_free()
	# Fit the test ground to the selected village, not just the demonstration.
	var bounds := AABB(Vector3.ZERO,Vector3.ONE)
	for guide in village.guides(0):
		for p in guide.village_points(): bounds=bounds.expand(Vector3(p.x,0,p.y))
	var ground: MeshInstance3D=world.get_node("Ground")
	ground.mesh=ground.mesh.duplicate(); ground.mesh.size=Vector2(bounds.size.x+20,bounds.size.z+20)
	ground.position=Vector3(bounds.get_center().x,-0.04,bounds.get_center().z)
	for child in ground.get_children(): ground.remove_child(child); child.queue_free()
	ground.create_trimesh_collision()
	player=load("res://scenes/player/player3.tscn").instantiate(); player.name="Player"
	var spawn := Vector3.ZERO
	if not village.lots().is_empty() and not village.lots()[0].access_path.is_empty(): spawn=village.lots()[0].transform*village.lots()[0].access_path[0]
	var entry: Node=null
	for road in village.guides(1):
		if entry==null or road.stable_id==village.entry_road_id: entry=road
		if road.stable_id==village.entry_road_id: break
	if entry!=null and entry.points.size()>0:
		var p: Vector2=entry.village_points()[0]; spawn=Vector3(p.x,0,p.y)
	player.position=spawn+Vector3.UP*0.2; world.add_child(player)
	camera=Camera3D.new(); camera.set_script(load("res://scripts/village/iso_cam.gd")); camera.name="IsoCam"
	camera.target_path=NodePath("../Player"); camera.pitch_deg=48; camera.yaw_deg=village.fixed_camera_yaw
	camera.ortho_size=17.5; camera.focus_height=4; camera.pixel_rows=450; camera.add_to_group("camera_rig"); world.add_child(camera)
	var palette := Node.new(); palette.set_script(load("res://scripts/village/village_character_palette.gd")); world.add_child(palette)
	var snap := Node.new(); snap.set_script(load("res://scripts/village/pixel_snap.gd")); snap.camera_path=NodePath("../IsoCam")
	var targets: Array[NodePath]=[NodePath("../Player")]; snap.targets=targets; world.add_child(snap)
	var ui := CanvasLayer.new(); add_child(ui); prompt=Label.new(); prompt.position=Vector2(20,20); ui.add_child(prompt)
	prompt.text="WASD / stick: muovi · F7: panoramica / camera di gioco\nProva disposizione, corti e percorsi — esterni"
	debug_zones=MeshInstance3D.new(); debug_zones.visible=false; world.add_child(debug_zones)
	var lines := ImmediateMesh.new(); var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.vertex_color_use_as_albedo=true; material.no_depth_test=true
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for kind in [0,1,2,3,4,5]:
		for guide in village.guides(kind):
			var points: PackedVector2Array=guide.village_points()
			lines.surface_set_color([Color.GREEN,Color.YELLOW,Color.CORNFLOWER_BLUE,Color.TOMATO,Color.ORANGE,Color.TURQUOISE][kind])
			for i in range(points.size()-(1 if kind in [1,5] else 0)):
				for p in [points[i],points[(i+1)%points.size()]]: lines.surface_add_vertex(Vector3(p.x,0.25,p.y))
	lines.surface_set_color(Color.TURQUOISE)
	for route in preload("res://addons/village_builder/path_network.gd").shared(village,village.snapshot(),false):
		for i in range(route.points.size()-1):
			for p in [route.points[i],route.points[i+1]]: lines.surface_add_vertex(Vector3(p.x,0.25,p.y))
	lines.surface_end(); debug_zones.mesh=lines; debug_zones.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var debug_button := Button.new(); debug_button.text="Mostra zone · F8"; debug_button.position=Vector2(20,70); debug_button.pressed.connect(_toggle_zones); ui.add_child(debug_button)
	if "--village-play-test" in OS.get_cmdline_user_args(): _test.call_deferred()
func _toggle_zones() -> void:
	debug_zones.visible=not debug_zones.visible
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8: _toggle_zones()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F7:
		overview=not overview; camera.ortho_size=80 if overview else 17.5
func _test() -> void:
	for i in 60: await get_tree().physics_frame
	assert(player.is_on_floor(),"Player must stand on the test ground")
	assert(camera.current and village.lots().size()>0)
	if "--village-network-walk-test" in OS.get_cmdline_user_args(): await _walk_courts()
	var start := player.position
	Input.action_press("move_down")
	for i in 30: await get_tree().physics_frame
	Input.action_release("move_down")
	assert(player.position.distance_to(start)>0.3,"Existing player must move in village playtest")
	assert(not debug_zones.visible); _toggle_zones(); assert(debug_zones.visible); _toggle_zones()
	if DisplayServer.get_name()!="headless":
		for i in 15: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://captures/village_builder/organic_play.png")
		_toggle_zones()
		for i in 2: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://captures/village_builder/organic_zones.png")
	print("VILLAGE_PLAY_GROUND_CAMERA_MOVEMENT_DEBUG_OK")
	get_tree().quit()

func _walk_courts() -> void:
	var network=load("res://addons/village_builder/path_network.gd")
	assert(network.validate(village,village.snapshot()).is_empty())
	for route in network.shared(village,village.snapshot()):
		var first: Vector2=route.points[0]; player.position=Vector3(first.x,0.2,first.y); player.velocity=Vector3.ZERO
		for i in 10: await get_tree().physics_frame
		for p in route.points:
			var target := Vector3(p.x,0,p.y)
			for frame in 1200:
				var delta := target-player.position; delta.y=0
				if delta.length()<0.22: break
				var raw := delta.normalized().rotated(Vector3.UP,-camera.global_rotation.y)
				for pair in [["move_left",-raw.x],["move_right",raw.x],["move_up",-raw.z],["move_down",raw.z]]:
					if pair[1]>0: Input.action_press(pair[0],pair[1])
					else: Input.action_release(pair[0])
				await get_tree().physics_frame
			for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
			assert(Vector2(player.position.x,player.position.z).distance_to(p)<0.35,"Player blocked on court route "+route.name)
		print("WALK_COURT_OK ",route.name)
