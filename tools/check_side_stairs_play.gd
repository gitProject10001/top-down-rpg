extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	for side in [1,2]:
		if not await test_side(side): quit(1); return
	print("SIDE_STAIRS_REAL_PLAYER_RIGHT_LEFT_ENTER_EXIT_OK"); quit()
func test_side(side: int) -> bool:
	var example=load("res://scenes/dev/terrace_stairs_example.tscn").instantiate()
	var house=example.get_node("CasaConTerrazza"); example.remove_child(house)
	var authored=house.attached_components()[0]; authored.exterior_stairs=false
	var stairs=preload("res://addons/house_builder/exterior_stair.gd").new(); stairs.side=side; stairs.name="ScalaEsterna"; authored.add_child(stairs)
	own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var terrace=play.house.attached_components()[0]
	var bottom: Vector3=terrace.to_global(terrace.stair_frame()*Vector3(0,terrace.stair_ground()-terrace.effective_elevation(),terrace.stair_run()+0.7))
	await play._walk(Vector3(0,0,5.1),180)
	await play._walk(Vector3(0,0,9),220)
	await play._walk(Vector3(bottom.x,0,9),400)
	await play._walk(bottom,400)
	var landing: Vector3=terrace.to_global(terrace.stair_frame()*Vector3(0,0,-0.6))
	await play._walk(landing,400)
	assert(feet(play)>2.7,"Player climbs exterior staircase")
	await play._walk(Vector3(0,2.8,4.7),220)
	await play._walk(Vector3(0,2.8,2.7),220); assert(play.inside,"Terrace door connects to interior")
	await play._walk(Vector3(0,2.8,4.7),220)
	await play._walk(landing,180)
	await play._walk(bottom,400); assert(feet(play)<0.15,"Player descends to ground")
	play.queue_free()
	for i in 3: await process_frame
	return true

func feet(play: Node) -> float:
	var collision: CollisionShape3D=play.player.get_node("Collision")
	return play.player.position.y+collision.position.y-collision.shape.height*0.5
