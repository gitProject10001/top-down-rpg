extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func ray(stair: Node3D, y: float, a: Vector3, b: Vector3) -> Dictionary:
	var frame := Transform3D(stair.basis,Vector3(stair.position.x,y,stair.position.z))
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(frame*a,frame*b))
func run() -> void:
	var scene=load("res://scenes/dev/tower_roof_stair_example.tscn").instantiate(); root.add_child(scene)
	var tower=scene.get_node("TorreOttagonale"); var plan=tower.get_node("InteriorPlan")
	await settle()
	for stair in [plan.get_node("PianoTerra/ScalaPrimoPiano"),plan.get_node("PrimoPiano/ScalaTetto")]:
		var y: float=tower.effective_elevation() if stair.roof_exit else plan.floor_height+0.05
		assert(not ray(stair,y,Vector3(0,0.4,0),Vector3(-1,0.4,0)).is_empty(),"Side blocks falls")
		assert(not ray(stair,y,Vector3(0,0.4,1.5),Vector3(0,0.4,2.4)).is_empty(),"Closed low end")
		assert(ray(stair,y,Vector3(0,0.4,-1.8),Vector3(0,0.4,-2.6)).is_empty(),"Landing remains open")
		stair.guardrails_enabled=false; await settle()
		assert(ray(stair,y,Vector3(0,0.4,0),Vector3(-1,0.4,0)).is_empty(),"Disable removes collision")
		assert(stair.record().guardrails_enabled==false)
		stair.guardrails_enabled=true; stair.position.x-=0.2; stair.rotation.y+=0.15; await settle()
		assert(not ray(stair,y,Vector3(0,0.4,0),Vector3(-1,0.4,0)).is_empty(),"Guard follows moved/rotated stair")
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); assert(copy.get_node("TorreOttagonale/InteriorPlan/PrimoPiano/ScalaTetto").guardrails_enabled); copy.free()
	scene.free(); print("STAIR_GUARDS_COLLISION_LANDING_TOGGLE_TRANSFORM_SAVE_OK"); quit()

