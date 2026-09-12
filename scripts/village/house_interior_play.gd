extends Node
const House=preload("res://addons/house_builder/house.gd")
const Interior=preload("res://addons/house_builder/interior.gd")
const Door=preload("res://addons/house_builder/door.gd")
@export_group("Dimensioni edificio")
@export_range(6.0,12.0,0.25) var house_width := 7.0
@export_range(8.0,16.0,0.25) var house_depth := 10.0
@export_group("Piani")
@export_range(2.4,3.5,0.1) var storey_height := 2.6
@export_range(1,2) var storeys := 2
@export_group("Stanze e muri")
@export_range(0.0,1.0,0.05) var room_split_x := 0.45
@export_range(0.0,1.0,0.05) var room_split_z := 0.5
@export_range(0.12,0.35,0.01) var partition_thickness := 0.18
var house: House
var interior: Interior
var authored_plan: Node3D
var player: CharacterBody3D
var camera: Camera3D
var view: SubViewport
var sun: DirectionalLight3D
var environment: Environment
var ground_material: StandardMaterial3D
var prompt: Label
var inside := false
var active_floor := 0
var blend := 0.0
var lamps: Array[OmniLight3D]=[]
var entrance_light: OmniLight3D
var zoomed := false
var _last_floor := -1
var entry_x := 0.0
var selected_source := false
func _ready() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch=true; container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	container.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; add_child(container)
	view=SubViewport.new(); view.size=Vector2i(1152,648); view.msaa_3d=Viewport.MSAA_4X
	view.handle_input_locally=false; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; container.add_child(view)
	var world := Node3D.new(); world.name="World"; view.add_child(world)
	environment=Environment.new(); environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(0.018,0.020,0.026)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color(0.65,0.72,0.8); environment.ambient_light_energy=0.408
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled=true; environment.ssao_radius=0.7; environment.ssao_intensity=1.3
	var env := WorldEnvironment.new(); env.environment=environment; world.add_child(env)
	sun=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-35,0)
	sun.light_color=Color(1,0.94,0.84); sun.light_energy=1.15; sun.shadow_enabled=true
	sun.shadow_blur=0.85; world.add_child(sun)
	ground_material=StandardMaterial3D.new(); ground_material.albedo_color=Color(0.27,0.25,0.17); ground_material.roughness=1.0
	interior=Interior.new()
	interior.box(world,Vector3(0,-0.14,0),Vector3(30,0.2,30),ground_material)
	var authored_test := "--house-authored-test" in OS.get_cmdline_user_args()
	if authored_test or (FileAccess.file_exists("user://house_builder_playtest.tscn") and not "--house-play-test" in OS.get_cmdline_user_args()):
		selected_source=true
		house=load("res://scenes/dev/house_authoring_example.tscn" if authored_test else "user://house_builder_playtest.tscn").instantiate()
		authored_plan=house.get_node_or_null("InteriorPlan")
		house_width=house.width; house_depth=house.depth
		storeys=maxi(1,authored_plan.levels().size()) if authored_plan else 1
		storey_height=authored_plan.floor_height if authored_plan else house.wall_height
	else:
		house=House.new(); house.name="Casa"; house.width=house_width; house.depth=house_depth
		house.wall_height=storey_height*storeys; house.roof_height=2.1
		var divider := lerpf(-house_width*0.5+1.8,house_width*0.5-2.2,room_split_x)
		entry_x=(divider+house_width*0.5-1.55)*0.5
		house.openings=[{"kind":"door","wall":0,"u":entry_x/(house_width*0.5),"width":1.5,"height":2.3},{"kind":"window","wall":1,"u":-0.45,"y":1.5},{"kind":"window","wall":2,"u":-0.6,"y":1.5}]
	world.add_child(house)
	world.add_child(interior)
	if not selected_source: interior.build(house_width,house_depth,storey_height,storeys,room_split_x,room_split_z,partition_thickness,house._material(Vector2(0.5,0),Color(0.60,0.53,0.46)),house._plaster_material())
	for floor_index in storeys:
		for point in [Vector3(-2,2.0,-2.5),Vector3(-2,2.0,2.5),Vector3(1.8,2.0,0)]:
			var light := OmniLight3D.new(); light.position=point+Vector3.UP*floor_index*storey_height
			light.light_color=Color(1.0,0.79,0.54); light.light_energy=2.4; light.omni_range=5.0; light.shadow_enabled=true
			world.add_child(light); lamps.append(light)
	entrance_light=OmniLight3D.new()
	entrance_light.position=Vector3(entry_x,1.9,house_depth*0.5-0.9)
	entrance_light.light_color=Color(1.0,0.82,0.61)
	entrance_light.light_energy=1.4; entrance_light.omni_range=3.0; entrance_light.shadow_enabled=true
	world.add_child(entrance_light)
	player=load("res://scenes/player/player3.tscn").instantiate(); player.name="Player"
	player.position=Vector3(entry_x,0.15,house_depth*0.5+2.0); world.add_child(player)
	if authored_plan:
		for record in house.openings:
			var opening: Dictionary=house.resolved_opening(record)
			if opening.door and house.wall_exposed(opening.wall,opening.along):
				player.position=house.wall_point(opening.wall,opening.along,0.15,1.5); break
	camera=Camera3D.new(); camera.set_script(load("res://scripts/village/iso_cam.gd")); camera.name="IsoCam"
	camera.target_path=NodePath("../Player"); camera.pitch_deg=48; camera.ortho_size=17.5
	camera.focus_height=4.0; camera.pixel_rows=450; camera.add_to_group("camera_rig"); world.add_child(camera)
	var palette := Node.new(); palette.set_script(load("res://scripts/village/village_character_palette.gd")); world.add_child(palette)
	var snap := Node.new(); snap.set_script(load("res://scripts/village/pixel_snap.gd"))
	var targets: Array[NodePath]=[NodePath("../Player")]
	snap.camera_path=NodePath("../IsoCam"); snap.targets=targets; world.add_child(snap)
	var ui := CanvasLayer.new(); add_child(ui)
	prompt=Label.new(); prompt.position=Vector2(22,20); prompt.add_theme_font_size_override("font_size",18); ui.add_child(prompt)
	if "--house-play-test" in OS.get_cmdline_user_args(): _test.call_deferred()
	if authored_test: _test_authored.call_deferred()
func nearest_door() -> Node3D:
	var best: Node3D=null; var distance := 2.2
	var all: Array=[]
	for child in house._generated.get_children():
		if child is Door: all.append(child)
	all.append_array(interior.doors)
	if authored_plan: all.append_array(authored_plan.doors())
	for door in all:
		var center: Vector3=(door.get_parent() as Node3D).to_global(door.closed_frame*Vector3(door.door_width*0.5,0,0))
		var delta := player.global_position-center
		if absf(delta.y)>1.0: continue
		var d := Vector2(delta.x,delta.z).length()
		if d<distance: distance=d; best=door
	return best
func _process(delta: float) -> void:
	if not is_instance_valid(player): return
	var p := player.position
	var margin := -0.12 if inside else 0.12
	var entered := absf(p.x)<house_width*0.5-margin and absf(p.z)<house_depth*0.5-margin and p.y>-0.5
	if house.wing_enabled:
		var q: Vector3=house.wing_transform().affine_inverse()*p
		entered=entered or (absf(q.x)<house.wing_span()*0.5-margin and absf(q.z)<(house.width*0.5+house.wing_length)*0.5-margin and p.y>-0.5)
	var collision: CollisionShape3D=player.get_node("Collision")
	var feet_y: float=p.y+collision.position.y-collision.shape.height*0.5
	active_floor=clampi(floori((feet_y+0.2)/storey_height),0,storeys-1)
	if entered!=inside or _last_floor!=active_floor:
		inside=entered; _last_floor=active_floor
		house.set_cutaway(inside,active_floor*storey_height,storey_height)
	interior.show_level(active_floor,inside)
	if inside: interior.reveal_room(player.global_position,camera.global_position)
	if authored_plan: authored_plan.runtime_view(inside,active_floor,player.global_position,camera.global_position)
	blend=move_toward(blend,1.0 if inside else 0.0,delta*4)
	sun.light_energy=lerpf(1.15,0.025,blend)
	environment.ambient_light_energy=lerpf(0.408,0.10,blend)
	ground_material.albedo_color=Color(0.27,0.25,0.17).lerp(Color(0.008,0.009,0.012),blend)
	camera.focus_height=lerpf(4.0,1.1,blend); camera.ortho_size=12.0 if zoomed else 17.5
	for i in lamps.size(): lamps[i].visible=inside and i/3==active_floor
	entrance_light.visible=inside and active_floor==0
	var door := nearest_door()
	if Input.is_action_just_pressed("interact") and door: door.toggle(player.global_position)
	prompt.text="WASD / stick: muovi  ·  E / Y: porta  ·  F7: zoom confronto\n%s · Piano %d/%d%s"%["Interno" if inside else "Esterno",active_floor+1,storeys,"  —  E: "+("chiudi" if door.opened else "apri") if door else ""]
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F7: zoomed=not zoomed
func _test() -> void:
	for i in 90: await get_tree().physics_frame
	await _capture("outside")
	await _walk(Vector3(entry_x,0,house_depth*0.5-0.5),60)
	assert(not inside and player.position.z>house_depth*0.5,"Closed door must block the player")
	var door := nearest_door(); assert(door!=null)
	Input.action_press("interact")
	await get_tree().process_frame
	Input.action_release("interact")
	for i in 30: await get_tree().physics_frame
	assert(door.opened,"Interaction opens the door")
	await _walk(Vector3(entry_x,0,house_depth*0.5-1.5),180)
	assert(inside,"Real player must cross the open doorway")
	await _capture("inside")
	var divider_x := lerpf(-house_width*0.5+1.8,house_width*0.5-2.2,room_split_x)
	var room_door_z := -house_depth*0.5+0.25+(house_depth-0.5)*0.67
	await _walk(Vector3(divider_x+0.9,0,room_door_z),180)
	var inner := nearest_door(); assert(inner!=null and inner!=door)
	assert(inner.toggle(player.global_position))
	for i in 30: await get_tree().physics_frame
	await _walk(Vector3(divider_x-1.0,0,room_door_z),150)
	assert(player.position.x<divider_x-0.5,"Player enters the side room")
	await _capture("room")
	await _walk(Vector3(divider_x+0.9,0,room_door_z),180)
	await _walk(Vector3(house_width*0.5-0.95,0,house_depth*0.5-0.5),180)
	await _walk(Vector3(house_width*0.5-0.95,storey_height,house_depth*0.5-5.0),240)
	assert(active_floor==1,"Existing player must climb the stair ramp")
	await _capture("upstairs")
	await _walk(Vector3(house_width*0.5-0.95,0,house_depth*0.5-0.5),240)
	assert(active_floor==0,"Descending restores the ground floor")
	await _walk(Vector3(entry_x,0,house_depth*0.5-1.0),180)
	await _walk(Vector3(entry_x,0,house_depth*0.5+1.5),180)
	assert(not inside and house._generated.get_node("Roof").visible,"Exiting restores the exterior")
	assert(door.toggle(player.global_position))
	await _capture("exit")
	print("HOUSE_PLAY_CLOSED_OPEN_ROOM_STAIRS_EXIT_OK player=",player.position)
	get_tree().quit()
func _test_authored() -> void:
	for i in 90: await get_tree().physics_frame
	assert(authored_plan!=null and authored_plan.levels().size()==2)
	await _capture("authored_outside")
	await _walk(Vector3(0,0,house_depth*0.5-0.5),90)
	assert(not inside,"Authored entrance must block while closed")
	var entry := nearest_door(); assert(entry!=null)
	assert(entry.toggle(player.global_position))
	for i in 30: await get_tree().physics_frame
	await _walk(Vector3(0,0,3.3),180)
	assert(inside,"Authored entrance must be passable")
	await _capture("authored_inside")
	var partition: Node3D
	for e in authored_plan.levels()[0].get_children():
		if e.kind==1 and e.has_door and "hall" in e.room_ids and e.position.x<0:
			partition=e; break
	assert(partition!=null)
	var doorway: Vector3=partition.position+partition.basis.x*partition.door_offset*partition.dimensions.x*0.5
	await _walk(Vector3(-0.7,0,3.3),150)
	await _walk(Vector3(-0.7,0,doorway.z),200)
	var inner: Node3D
	for child in partition._visual.get_children():
		if child is Door: inner=child
	assert(inner!=null and inner.toggle(player.global_position))
	for i in 30: await get_tree().physics_frame
	await _walk(Vector3(doorway.x-0.65,0,doorway.z),180)
	assert(player.position.x<doorway.x-0.4,"Authored partition opening must be passable")
	await _capture("authored_room")
	await _walk(Vector3(-0.7,0,doorway.z),180)
	await _walk(Vector3(-0.7,0,3.3),200)
	var stair: Node3D
	for e in authored_plan.levels()[0].get_children():
		if e.kind==2: stair=e
	assert(stair!=null)
	var bottom := stair.position+Vector3(0,0,stair.dimensions.z*0.5+0.55)
	await _walk(bottom,180)
	await _walk(stair.position+Vector3(0,storey_height,-stair.dimensions.z*0.5-0.55),300)
	assert(active_floor==1,"Authored stairs must reach upper floor")
	await _capture("authored_upstairs")
	await _walk(bottom,300)
	assert(active_floor==0,"Authored stairs must descend")
	await _walk(Vector3(0,0,3.4),180)
	await _walk(Vector3(0,0,6.4),180)
	assert(not inside,"Authored entrance must permit exit")
	print("HOUSE_AUTHORED_SAVED_FURNITURE_ENTRANCE_ROOM_STAIRS_EXIT_OK")
	get_tree().quit()
func _walk(target: Vector3,frames: int) -> void:
	for i in frames:
		var delta := target-player.position; delta.y=0
		if delta.length()<0.12: break
		var raw := delta.normalized().rotated(Vector3.UP,-camera.global_rotation.y)
		for pair in [["move_left",-raw.x],["move_right",raw.x],["move_up",-raw.z],["move_down",raw.z]]:
			if pair[1]>0: Input.action_press(pair[0],pair[1])
			else: Input.action_release(pair[0])
		await get_tree().physics_frame
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
	for i in 25: await get_tree().physics_frame
func _capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/house_interior"))
	get_viewport().get_texture().get_image().save_png("res://captures/house_interior/"+label+".png")
