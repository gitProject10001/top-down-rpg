extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/terrace_stairs_example.tscn").instantiate()
	var house=example.get_node("CasaConTerrazza"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var terrace=play.house.attached_components()[0]
	var bottom: Vector3=terrace.to_global(Vector3(terrace.stair_center(),terrace.ground_level-terrace.effective_elevation(),terrace.projection+terrace.stair_run()+0.7))
	await play._walk(bottom,400)
	var landing: Vector3=terrace.to_global(Vector3(terrace.stair_center(),0,terrace.projection-0.6))
	await play._walk(landing,400)
	assert(feet(play)>2.7,"Player climbs exterior staircase")
	await play._walk(Vector3(0,2.8,2.7),220); assert(play.inside,"Terrace door connects to interior")
	await play._walk(landing,180)
	await play._walk(bottom,400); assert(feet(play)<0.15,"Player descends to ground")
	play.authored_plan.floor_height=3.2; play.authored_plan.rebuild(); play.house.rebuild()
	bottom=terrace.to_global(Vector3(terrace.stair_center(),-3.2,terrace.projection+terrace.stair_run()+0.7))
	await play._walk(bottom,200)
	landing=terrace.to_global(Vector3(terrace.stair_center(),0,terrace.projection-0.6))
	await play._walk(landing,450); assert(feet(play)>3.1,"Stair follows raised floor")
	await play._walk(Vector3(0,3.2,2.7),220); assert(play.inside)
	print("TERRACE_REAL_PLAYER_ASCEND_ENTER_DESCEND_RAISED_FLOOR_OK")
	play.queue_free()
	for i in 3: await process_frame
	quit()

func feet(play: Node) -> float:
	var collision: CollisionShape3D=play.player.get_node("Collision")
	return play.player.position.y+collision.position.y-collision.shape.height*0.5
